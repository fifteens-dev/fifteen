import Flutter
import Foundation
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
            let ids = args["ids"] as? [String] ?? []
            result(ids.filter { id in
                guard let url = MusicMemoryShared.artworkURL(for: "\(id).jpg") else { return true }
                return !FileManager.default.fileExists(atPath: url.path)
            })

        case "syncDays":
            // ストリップだけ更新（アクティビティ未起動でも呼べる）。
            syncDays(from: args)
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
    private func syncDays(from args: [String: Any]) {
        guard let raw = args["days"] as? [[String: Any]] else { return }

        var days: [MusicMemoryDay] = []
        for entry in raw {
            let label = entry["label"] as? String ?? ""
            let isToday = entry["isToday"] as? Bool ?? false
            var file: String?

            if let imageId = entry["imageId"] as? String, !imageId.isEmpty {
                let name = "\(imageId).jpg"
                if let url = MusicMemoryShared.artworkURL(for: name) {
                    if !FileManager.default.fileExists(atPath: url.path),
                       let data = (entry["imageBytes"] as? FlutterStandardTypedData)?.data {
                        try? data.write(to: url, options: .atomic)
                    }
                    if FileManager.default.fileExists(atPath: url.path) { file = name }
                }
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
            result(info(for: activity))
        } catch {
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
        guard content.revision >= currentState(of: activity).revision else { return }
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
    private func observePushToStartToken() {
        guard #available(iOS 17.2, *) else { return }
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
