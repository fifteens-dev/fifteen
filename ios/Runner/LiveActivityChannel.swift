import Flutter
import Foundation
import WidgetKit
import UIKit

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Flutter ↔ ActivityKit のブリッジ（チャンネル `com.fifteen.liveactivity`）。
///
/// # 役割
/// - 「今日のMusic Memory」Live Activity の開始 / 更新 / 終了
/// - 曜日ストリップ（過去4日＋今日）のアートワークを App Group に書き出す
/// - push 更新用トークン（update token / push-to-start token）を Flutter へ返す
///
/// # 更新経路
/// - ローカル: アプリ起動・フォアグラウンド復帰・投稿完了時にこのチャンネル経由。
/// - リモート: Cloud Functions が APNs へ liveactivity push を送る。トークンは
///   Flutter 側が Firestore に保存する（`onPushToken` / `onPushToStartToken`）。
final class LiveActivityChannel: NSObject {
    private static let channelName = "com.fifteen.liveactivity"

    private var channel: FlutterMethodChannel?

    /// Activity ごとの push トークン監視タスク（activityId → Task）。
    private var tokenObservers: [String: Task<Void, Never>] = [:]
    private var pushToStartObserver: Task<Void, Never>?
    private var activityObserver: Task<Void, Never>?

    func setup(controller: FlutterViewController) {
        let ch = FlutterMethodChannel(
            name: LiveActivityChannel.channelName,
            binaryMessenger: controller.binaryMessenger
        )
        channel = ch
        ch.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        observePushToStartToken()
        observeActivities()
    }

    /// 既存＋今後生まれる全 Activity に push トークン監視を張る。
    ///
    /// push-to-start（サーバ発の開始）で生まれた Activity は、アプリが
    /// `Activity.request` を呼んでいないため start() の経路を通らない。
    /// ここで拾わないと update token が永久に Flutter へ渡らず、
    /// 「友達があなたを待っています」への push 更新ができなくなる。
    private func observeActivities() {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<MusicMemoryActivityAttributes>.activities {
            observePushToken(of: activity)
        }
        activityObserver?.cancel()
        activityObserver = Task { [weak self] in
            for await activity in Activity<MusicMemoryActivityAttributes>.activityUpdates {
                await MainActor.run { self?.observePushToken(of: activity) }
            }
        }
    }

    // MARK: - メソッドディスパッチ

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "isSupported":
            result(isSupported())

        case "areActivitiesEnabled":
            if #available(iOS 16.1, *) {
                result(ActivityAuthorizationInfo().areActivitiesEnabled)
            } else {
                result(false)
            }

        case "missingArtwork":
            // まだ共有コンテナに無い imageId だけ返す（Flutter が差分だけ落とす）。
            // 存在するだけでなく **画像として読めるか** まで見る。0 バイトや壊れた
            // ファイルが残っていると、存在チェックだけでは二度と落とし直されず
            // 永久にグレーのままになるため。
            let ids = args["ids"] as? [String] ?? []
            result(ids.filter { !MusicMemoryShared.hasUsableArtwork(id: $0) })

        case "logRead":
            result(MMLog.read())

        case "logClear":
            MMLog.clear()
            result(true)

        case "log":
            // Dart 側の出来事も同じログに混ぜる（Firestore の結果など）。
            MMLog.log(args["tag"] as? String ?? "dart",
                      args["message"] as? String ?? "")
            result(true)

        case "artworkDiagnostics":
            // 端末側の共有コンテナの状態をそのまま返す（管理者パネルの調査用）。
            result(MusicMemoryShared.diagnostics())

        case "syncDays":
            // ストリップだけ更新（アクティビティ未起動でも呼べる）。
            syncDays(from: args)
            result(true)

        case "syncFriends":
            // ホーム画面ウィジェット用。アクティビティとは無関係に呼べる。
            syncFriends(from: args)
            result(true)

        case "start":
            guard #available(iOS 16.1, *) else { result(nil); return }
            syncDays(from: args)
            start(args: args, result: result)

        case "update":
            guard #available(iOS 16.1, *) else { result(false); return }
            syncDays(from: args)
            update(args: args, result: result)

        case "end":
            guard #available(iOS 16.1, *) else { result(false); return }
            end(immediately: args["immediately"] as? Bool ?? false, result: result)

        case "getPushToStartToken":
            getPushToStartToken(result: result)

        case "syncPushToStartToken":
            // フォアグラウンド復帰のたびに現在値を送り直し、閉じている間の
            // トークン更新を取りこぼさないようにする。
            emitCurrentPushToStartToken()
            observeActivities()
            result(true)

        case "currentActivity":
            guard #available(iOS 16.1, *) else { result(nil); return }
            result(currentActivityInfo())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func isSupported() -> Bool {
        if #available(iOS 16.1, *) { return true }
        return false
    }

    // MARK: - ストリップ（App Group への書き出し）

    /// `days` 引数（Flutter から渡る 5 件）を App Group に反映する。
    ///
    /// 各要素: `{ label: String, isToday: Bool, imageBytes: Uint8List? , imageId: String? }`
    /// 画像は毎回書き直さず、`imageId` が同じファイルが既にあれば再利用する。
    /// ホーム画面ウィジェット（友達が今聴いてる曲）のデータを書き出す。
    ///
    /// 画像は Live Activity と同じ置き場に `art_<id>.jpg` で入れる。
    /// 既に持っている画像は Dart 側が bytes を送ってこないので、
    /// その場合は保存済みのものをそのまま使う。
    private func syncFriends(from args: [String: Any]) {
        guard let raw = args["items"] as? [[String: Any]] else {
            MMLog.log("syncFriends", "失敗: items の型が想定と違う")
            return
        }

        var items: [FriendNowPlaying] = []
        for entry in raw {
            func store(_ idKey: String, _ bytesKey: String) -> String? {
                guard let id = entry[idKey] as? String, !id.isEmpty else { return nil }
                if !MusicMemoryShared.hasUsableArtwork(id: id),
                   let data = (entry[bytesKey] as? FlutterStandardTypedData)?.data {
                    MusicMemoryShared.writeArtwork(id: id, data: data)
                }
                return MusicMemoryShared.hasUsableArtwork(id: id) ? id : nil
            }

            items.append(FriendNowPlaying(
                trackName: entry["trackName"] as? String ?? "",
                artistName: entry["artistName"] as? String ?? "",
                artworkId: store("artworkId", "artworkBytes"),
                avatarId: store("avatarId", "avatarBytes"),
                friendName: entry["friendName"] as? String ?? "",
                service: entry["service"] as? String
            ))
        }

        FriendNowPlayingShared.write(items)
        FriendNowPlayingShared.pruneArtwork(keeping: items)
        MMLog.log("syncFriends", "保存 \(items.count) 件")

        // 書き換えたらウィジェットに取り直させる。
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "FriendNowPlayingWidget")
        }
    }

    private func syncDays(from args: [String: Any]) {
        guard let raw = args["days"] as? [[String: Any]] else {
            MMLog.log("syncDays", "失敗: days の型が想定と違う (\(type(of: args["days"])))")
            return
        }
        MMLog.log("syncDays", "受信 \(raw.count) 件")

        var days: [MusicMemoryDay] = []
        for entry in raw {
            let label = entry["label"] as? String ?? ""
            let isToday = entry["isToday"] as? Bool ?? false
            var file: String?

            if let imageId = entry["imageId"] as? String, !imageId.isEmpty {
                let already = MusicMemoryShared.hasUsableArtwork(id: imageId)
                let bytes = (entry["imageBytes"] as? FlutterStandardTypedData)?.data
                if !already {
                    if let data = bytes {
                        MusicMemoryShared.writeArtwork(id: imageId, data: data)
                    } else {
                        MMLog.log("syncDays",
                                  "\(label): 保存済みでないのに imageBytes が無い id=\(imageId)")
                    }
                }
                let usable = MusicMemoryShared.hasUsableArtwork(id: imageId)
                if usable { file = "\(imageId).jpg" }
                MMLog.log("syncDays",
                          "\(label): id=\(imageId) 既存=\(already) 受信=\(bytes?.count ?? -1)B 結果=\(usable)")
            } else {
                MMLog.log("syncDays", "\(label): 投稿なし")
            }
            days.append(MusicMemoryDay(label: label, imageFile: file, isToday: isToday))
        }

        MusicMemoryShared.writeDays(days)
        MusicMemoryShared.pruneArtwork(keeping: days)
    }

    // MARK: - 開始 / 更新 / 終了

    @available(iOS 16.1, *)
    private func start(args: [String: Any], result: @escaping FlutterResult) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            MMLog.log("start", "失敗: 設定でライブアクティビティが無効")
            result(FlutterError(code: "DISABLED",
                                message: "Live Activities are disabled by the user",
                                details: nil))
            return
        }

        let cycleStartEpoch = epoch(args["cycleStartMs"])
        let content = contentState(from: args)

        // 同じサイクルの Activity が既に動いていれば作り直さず更新する。
        if let existing = Activity<MusicMemoryActivityAttributes>.activities.first(where: {
            Int($0.attributes.cycleStartEpoch) == Int(cycleStartEpoch)
        }) {
            MMLog.log("start", "既存のアクティビティを再利用 id=\(existing.id)")
            // push-to-start で始まったものと自前で作ったものが混ざると
            // ロック画面に複数枚並ぶため、別サイクルの残骸をここでも畳む。
            endActivities(immediately: true, except: existing.id)
            observePushToken(of: existing)
            Task {
                await updateActivity(existing, to: content, staleMs: args["staleMs"])
                await MainActor.run { result(self.info(for: existing)) }
            }
            return
        }

        // 別サイクルの残骸は終了させる（1ユーザー1アクティビティに保つ）。
        endActivities(immediately: true)

        do {
            let attributes = MusicMemoryActivityAttributes(cycleStartEpoch: cycleStartEpoch)
            let activity: Activity<MusicMemoryActivityAttributes>
            if #available(iOS 16.2, *) {
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: content, staleDate: staleDate(args["staleMs"])),
                    pushType: .token
                )
            } else {
                activity = try Activity.request(
                    attributes: attributes,
                    contentState: content,
                    pushType: .token
                )
            }
            observePushToken(of: activity)
            MMLog.log("start", "新規作成 id=\(activity.id) phase=\(content.phase)")
            result(info(for: activity))
        } catch {
            MMLog.log("start", "失敗: \(error.localizedDescription)")
            result(FlutterError(code: "START_FAILED",
                                message: error.localizedDescription,
                                details: nil))
        }
    }

    @available(iOS 16.1, *)
    private func update(args: [String: Any], result: @escaping FlutterResult) {
        let content = contentState(from: args)
        let activities = Activity<MusicMemoryActivityAttributes>.activities
        guard !activities.isEmpty else { result(false); return }
        Task {
            for activity in activities {
                await updateActivity(activity, to: content, staleMs: args["staleMs"])
            }
            await MainActor.run { result(true) }
        }
    }

    @available(iOS 16.1, *)
    private func updateActivity(
        _ activity: Activity<MusicMemoryActivityAttributes>,
        to content: MusicMemoryActivityAttributes.ContentState,
        staleMs: Any?
    ) async {
        // 版が後退する更新（push とローカルの交差）は捨てる。
        let current = currentState(of: activity)
        guard content.revision >= current.revision else {
            MMLog.log("update", "スキップ（版が古い）\(content.revision) < \(current.revision)")
            return
        }
        MMLog.log("update", "phase=\(content.phase) rev=\(content.revision)")
        if #available(iOS 16.2, *) {
            await activity.update(
                ActivityContent(state: content, staleDate: staleDate(staleMs))
            )
        } else {
            await activity.update(using: content)
        }
    }

    @available(iOS 16.1, *)
    private func end(immediately: Bool, result: @escaping FlutterResult) {
        endActivities(immediately: immediately)
        result(true)
    }

    /// 表示中のアクティビティを終了する。[except] に渡した id だけは残す。
    @available(iOS 16.1, *)
    private func endActivities(immediately: Bool, except keepId: String? = nil) {
        let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .default
        for activity in Activity<MusicMemoryActivityAttributes>.activities
        where activity.id != keepId {
            Task {
                if #available(iOS 16.2, *) {
                    await activity.end(nil, dismissalPolicy: policy)
                } else {
                    await activity.end(dismissalPolicy: policy)
                }
            }
            tokenObservers.removeValue(forKey: activity.id)?.cancel()
        }
    }

    // MARK: - push トークン

    /// Activity ごとの update token を監視して Flutter に流す。
    @available(iOS 16.1, *)
    private func observePushToken(of activity: Activity<MusicMemoryActivityAttributes>) {
        guard tokenObservers[activity.id] == nil else { return }
        // 既に配布済みのトークンは stream に流れてこないことがあるため先に一度送る。
        if let token = activity.pushToken {
            channel?.invokeMethod("onPushToken", arguments: [
                "activityId": activity.id,
                "token": token.map { String(format: "%02x", $0) }.joined(),
            ])
        }
        tokenObservers[activity.id] = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await MainActor.run {
                    self?.channel?.invokeMethod("onPushToken", arguments: [
                        "activityId": activity.id,
                        "token": token,
                    ])
                }
            }
            await MainActor.run { self?.tokenObservers[activity.id] = nil }
        }
    }

    /// push-to-start トークン（iOS 17.2+）。通知と同時にサーバから開始するために使う。
    ///
    /// `pushToStartTokenUpdates` は **既に発行済みのトークンを再送しないことがある**。
    /// 起動のたびに購読するだけだと、アプリが閉じている間にトークンが変わっても
    /// 気づけず、サーバは古いトークンに送り続ける（APNs は受理して 200 を返すが
    /// 端末には何も出ない）。そのため購読の前に現在値を必ず 1 回送る。
    private func observePushToStartToken() {
        guard #available(iOS 17.2, *) else { return }
        emitCurrentPushToStartToken()
        pushToStartObserver?.cancel()
        pushToStartObserver = Task { [weak self] in
            for await data in Activity<MusicMemoryActivityAttributes>.pushToStartTokenUpdates {
                let token = data.map { String(format: "%02x", $0) }.joined()
                await MainActor.run {
                    self?.channel?.invokeMethod("onPushToStartToken", arguments: ["token": token])
                }
            }
        }
    }

    /// 現在の push-to-start トークンを Flutter へ送る（保存済みと同じなら Dart 側で握り潰す）。
    private func emitCurrentPushToStartToken() {
        guard #available(iOS 17.2, *) else { return }
        guard let data = Activity<MusicMemoryActivityAttributes>.pushToStartToken else { return }
        let token = data.map { String(format: "%02x", $0) }.joined()
        channel?.invokeMethod("onPushToStartToken", arguments: ["token": token])
    }

    private func getPushToStartToken(result: @escaping FlutterResult) {
        guard #available(iOS 17.2, *) else { result(nil); return }
        // pushToStartToken は非同期に配布されるため、即時に取れないことがある。
        // その場合は onPushToStartToken の通知を待つ（ここでは nil を返す）。
        let token = Activity<MusicMemoryActivityAttributes>.pushToStartToken
        result(token?.map { String(format: "%02x", $0) }.joined())
    }

    // MARK: - ヘルパ

    @available(iOS 16.1, *)
    private func currentActivityInfo() -> [String: Any]? {
        guard let activity = Activity<MusicMemoryActivityAttributes>.activities.first else {
            return nil
        }
        return info(for: activity)
    }

    @available(iOS 16.1, *)
    private func info(for activity: Activity<MusicMemoryActivityAttributes>) -> [String: Any] {
        let state = currentState(of: activity)
        var payload: [String: Any] = [
            "activityId": activity.id,
            "phase": state.phase,
            "revision": state.revision,
        ]
        if let token = activity.pushToken {
            payload["token"] = token.map { String(format: "%02x", $0) }.joined()
        }
        return payload
    }

    /// 現在の ContentState。`activity.content` は iOS 16.2 以降なので分岐する。
    @available(iOS 16.1, *)
    private func currentState(
        of activity: Activity<MusicMemoryActivityAttributes>
    ) -> MusicMemoryActivityAttributes.ContentState {
        if #available(iOS 16.2, *) {
            return activity.content.state
        }
        return activity.contentState
    }

    private func contentState(from args: [String: Any]) -> MusicMemoryActivityAttributes.ContentState {
        MusicMemoryActivityAttributes.ContentState(
            phase: args["phase"] as? String ?? MusicMemoryPhase.waiting.rawValue,
            deadlineEpoch: epoch(args["deadlineMs"]),
            revision: args["revision"] as? Int ?? 0
        )
    }

    /// Flutter からはミリ秒で受け取り、共有モデルの秒（Unix エポック）に直す。
    private func epoch(_ value: Any?) -> Double {
        guard let ms = value as? NSNumber else { return Date().timeIntervalSince1970 }
        return ms.doubleValue / 1000.0
    }

    private func staleDate(_ value: Any?) -> Date? {
        guard let ms = value as? NSNumber, ms.doubleValue > 0 else { return nil }
        return Date(timeIntervalSince1970: ms.doubleValue / 1000.0)
    }
}
