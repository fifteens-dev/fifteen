import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(ActivityKit)
import ActivityKit
#endif

/// アプリ本体とウィジェット拡張で共有する Live Activity の定義。
///
/// # 設計方針
/// ContentState は **APNs の Live Activity push で丸ごと差し替えられる**ため、
/// 4KB 制限とサーバ側の知識量を最小化する目的で「状態と締切だけ」を持たせる。
/// 曜日ストリップ（過去4日＋今日のアートワーク）は push で送らず、
/// App Group 共有コンテナ（[MusicMemoryShared]）にアプリが書き出したものを
/// ウィジェットが描画時に読む。これでサーバはアートワークを一切知らずに
/// 「まだ投稿していない → 友達が待っている」の1状態だけを押せる。
public struct MusicMemoryActivityAttributes: Codable, Hashable {
    /// push で差し替わる可変部分。
    public struct ContentState: Codable, Hashable {
        /// 表示フェーズ。`MusicMemoryPhase` の rawValue。
        /// 文字列で持つのは、サーバ(JSON)からそのまま差し替えられるようにするため。
        public var phase: String

        /// 通常投稿の締切（＝通知日の翌 01:00 JST＝「25:00」）。**Unix エポック秒**。
        ///
        /// Date ではなく数値で持つのは、ActivityKit が APNs の `content-state` を
        /// 既定の `JSONDecoder`（Date は Apple 基準日=2001-01-01 からの秒）で
        /// デコードするため。サーバと解釈がズレる余地を無くす。
        public var deadlineEpoch: Double

        /// 状態の版。ローカル更新と push 更新が交差したときの順序判定用。
        public var revision: Int

        public init(phase: String, deadlineEpoch: Double, revision: Int) {
            self.phase = phase
            self.deadlineEpoch = deadlineEpoch
            self.revision = revision
        }

        public var deadline: Date {
            Date(timeIntervalSince1970: deadlineEpoch)
        }

        public var resolvedPhase: MusicMemoryPhase {
            MusicMemoryPhase(rawValue: phase) ?? .waiting
        }
    }

    /// サイクル開始（通知が発火した時刻）の **Unix エポック秒**。
    /// 1サイクル1アクティビティの識別に使う。ContentState と同じ理由で数値にする。
    public var cycleStartEpoch: Double

    public init(cycleStartEpoch: Double) {
        self.cycleStartEpoch = cycleStartEpoch
    }

    public var cycleStart: Date {
        Date(timeIntervalSince1970: cycleStartEpoch)
    }
}

#if canImport(ActivityKit)
// Runner ターゲットの deployment target は 16.0 なので、ActivityKit(16.1+) への
// 適合だけを availability 付きの extension に分離する。
@available(iOS 16.1, *)
extension MusicMemoryActivityAttributes: ActivityAttributes {}
#endif

/// 3つの表示パターン。
public enum MusicMemoryPhase: String, Codable {
    /// 通知は来たが、フォロワーの誰もまだ投稿していない。
    case waiting
    /// 通知が来ていて、かつフォロワーが投稿済み（＝友達が待っている）。
    case friendsWaiting
    /// このサイクルの投稿が完了した。
    case posted
}

// MARK: - 曜日ストリップの共有ストア

/// ストリップ 1 枠分（過去4日＋今日）。
public struct MusicMemoryDay: Codable, Hashable {
    /// 見出し（"木" "金" … / 今日の枠は "今日"）。
    public var label: String
    /// アートワークの識別子（投稿の postId）。未投稿の日は nil。
    /// 画像本体は [MusicMemoryShared.artworkData] から引く。
    public var imageFile: String?
    /// 今日の枠か（枠線・プレースホルダ表示の分岐に使う）。
    public var isToday: Bool

    public init(label: String, imageFile: String?, isToday: Bool) {
        self.label = label
        self.imageFile = imageFile
        self.isToday = isToday
    }

    /// 保存ファイル名に使う識別子（拡張子は落とす）。
    public var artworkId: String? {
        guard let f = imageFile else { return nil }
        return f.hasSuffix(".jpg") ? String(f.dropLast(4)) : f
    }
}

/// Live Activity の調査用ログ。
///
/// 「どこまで成功してどこで落ちたか」を端末上で追えるようにするためのもの。
/// 曜日データの構築 → アートワークの取得 → 保存 → アクティビティの開始/更新
/// という一連の流れを、成功も含めて 1 行ずつ残す。
///
/// 実際に書けるのは**アプリ本体のプロセスだけ**。ウィジェット拡張は描画時に
/// ファイルを読めるが書き込みは通らない（実機で確認済み）。
/// 将来ウィジェット側も書けるようになった場合に備え、プロセスごとに別ファイルへ
/// 書いて読み出し時にマージする形は残してある。行数は [maxLines] で頭打ち。
public enum MMLog {
    /// 保持する行数（プロセスごと）。
    public static let maxLines = 300

    /// 書き手の識別子。拡張はバンドルIDの末尾で判別する。
    public static var source: String {
        let id = Bundle.main.bundleIdentifier ?? ""
        return id.hasSuffix("FifteensWidget") ? "widget" : "app"
    }

    private static func url(for source: String) -> URL? {
        MusicMemoryShared.sharedDirectory?
            .appendingPathComponent("log_\(source).txt")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return f
    }()

    /// 1 行追記する。失敗しても何もしない（調査用なので本処理を止めない）。
    public static func log(_ tag: String, _ message: String) {
        let src = source
        guard let url = url(for: src) else { return }
        let line = "\(formatter.string(from: Date())) [\(src)] \(tag): \(message)"
        var lines = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init) ?? []
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        let joined = lines.joined(separator: "\n")
        if let data = joined.data(using: .utf8) {
            try? data.write(to: url, options: [.atomic, .noFileProtection])
        }
    }

    /// 両プロセスのログを時刻順にマージして返す。
    public static func read() -> String {
        var all: [String] = []
        for src in ["app", "widget"] {
            guard let u = url(for: src),
                  let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            all.append(contentsOf: text.split(separator: "\n").map(String.init))
        }
        // 先頭が "MM-dd HH:mm:ss" なのでそのまま辞書順で時刻順になる。
        return all.filter { !$0.isEmpty }.sorted().joined(separator: "\n")
    }

    public static func clear() {
        for src in ["app", "widget"] {
            if let u = url(for: src) { try? FileManager.default.removeItem(at: u) }
        }
    }
}

/// アプリ本体 ↔ ウィジェット拡張の共有領域（App Group）。
///
/// アプリは投稿直後・フォアグラウンド復帰時にストリップを書き出し、
/// ウィジェットは描画のたびにここを読む。push ではこの領域は変わらない。
///
/// # 保護レベルを `.noFileProtection` にしている理由（重要）
/// Live Activity を描画するウィジェットのプロセスは非常に制限の強い
/// サンドボックスで動いており、**`.completeFileProtectionUntilFirstUserAuthentication`
/// でも読めない**。実機で次のとおり確認した。
///
/// | 保護レベル | アプリから | ウィジェットから |
/// |---|---|---|
/// | completeUntilFirstUserAuthentication | 読める | **読めない**（枠がグレーのまま） |
/// | noFileProtection | 読める | 読める |
///
/// 「初回アンロック後は読める」レベルでは足りない。アルバムアートと曜日ラベルに
/// 秘匿性は無いので保護を外して問題ない。**ここを変えると表示が壊れる。**
///
/// # UserDefaults ではなくファイルにしている理由
/// App Group の `UserDefaults` はプロセスごとにキャッシュされ、ウィジェットが
/// 古い内容を読み続けることがある。ファイルはキャッシュ層が無く常に現在の
/// 内容が読めるので、曜日データ・アートワーク・ログのすべてをファイルに統一する。
///
/// # ウィジェットからは書けない
/// 読み取りは上記のとおり可能だが、**ウィジェットのプロセスからの書き込みは通らない**
/// （ログも診断の記録も残らないことを実機で確認済み）。ウィジェット側の状態は
/// 観測できないので、調査はアプリ側のログ（[MMLog] の `[app]` 行）で行う。
public enum MusicMemoryShared {
    /// App Group ID。Runner / FifteensWidget の entitlements と一致させること。
    public static let appGroupId = "group.com.fifteens.sns"

    /// 保存するアートワークの最大辺。ストリップは 53pt なので 3x でも 159px。
    /// 余裕を見て 240px に収め、ウィジェットの描画メモリも抑える。
    public static let artworkMaxPixel: CGFloat = 240

    /// 共有データを置くディレクトリ（App Group コンテナ内）。
    public static var sharedDirectory: URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return nil }
        let dir = base.appendingPathComponent("MusicMemory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static var daysURL: URL? {
        sharedDirectory?.appendingPathComponent("days.json")
    }

    public static func artworkURL(for id: String) -> URL? {
        sharedDirectory?.appendingPathComponent("art_\(id).jpg")
    }

    /// ロック中でも読めるよう保護レベルを外して書く。
    @discardableResult
    private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: [.atomic, .noFileProtection])
            return true
        } catch {
            return false
        }
    }

    // MARK: 曜日データ

    public static func writeDays(_ days: [MusicMemoryDay]) {
        guard let url = daysURL, let data = try? JSONEncoder().encode(days) else {
            MMLog.log("writeDays", "失敗: URL かエンコードが取れない")
            return
        }
        let ok = write(data, to: url)
        let detail = days.map { "\($0.label)=\($0.imageFile ?? "-")" }.joined(separator: ",")
        MMLog.log("writeDays", "ok=\(ok) count=\(days.count) [\(detail)]")
    }

    public static func readDays() -> [MusicMemoryDay] {
        guard let url = daysURL else {
            MMLog.log("readDays", "失敗: 共有ディレクトリが取れない")
            return []
        }
        guard let data = try? Data(contentsOf: url) else {
            MMLog.log("readDays", "ファイル無し \(url.lastPathComponent)")
            return []
        }
        guard let days = try? JSONDecoder().decode([MusicMemoryDay].self, from: data) else {
            MMLog.log("readDays", "デコード失敗 size=\(data.count)")
            return []
        }
        return days
    }

    // MARK: アートワーク

    /// アートワークを保存する。保存前に [artworkMaxPixel] まで縮小する。
    @discardableResult
    public static func writeArtwork(id: String, data: Data) -> Bool {
        guard !data.isEmpty, let url = artworkURL(for: id) else { return false }
        #if canImport(UIKit)
        guard let shrunk = downscaledJPEG(data) else {
            MMLog.log("writeArtwork", "縮小失敗 id=\(id) in=\(data.count)")
            return false
        }
        let ok = write(shrunk, to: url)
        MMLog.log("writeArtwork", "ok=\(ok) id=\(id) \(data.count)→\(shrunk.count)B")
        return ok
        #else
        return write(data, to: url)
        #endif
    }

    public static func artworkData(for id: String) -> Data? {
        guard let url = artworkURL(for: id) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// そのアートワークが使える状態で保存されているか。
    public static func hasUsableArtwork(id: String) -> Bool {
        guard let data = artworkData(for: id), !data.isEmpty else { return false }
        #if canImport(UIKit)
        return UIImage(data: data) != nil
        #else
        return true
        #endif
    }

    #if canImport(UIKit)
    /// 長辺を [artworkMaxPixel] に収めた JPEG を返す。
    private static func downscaledJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > 0 else { return nil }
        let scale = min(1.0, artworkMaxPixel / maxSide)
        if scale >= 1.0 {
            return image.jpegData(compressionQuality: 0.85) ?? data
        }
        let target = CGSize(width: image.size.width * scale,
                            height: image.size.height * scale)
        // scale を明示しないと画面スケール（3x など）で描画され、
        // 指定した pt の 3 倍の px になって元より重くなる。
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
    #endif

    /// 現在のストリップで参照されていないアートワークを削除する。
    public static func pruneArtwork(keeping days: [MusicMemoryDay]) {
        guard let dir = sharedDirectory else { return }
        let keep = Set(days.compactMap { $0.artworkId }.map { "art_\($0).jpg" })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where f.hasPrefix("art_") && !keep.contains(f) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }

    // MARK: 診断

    /// 端末で何が起きているかを調べるための現状ダンプ（管理者向け）。
    public static func diagnostics() -> [String: Any] {
        var out: [String: Any] = [:]
        out["appGroupId"] = appGroupId
        out["defaultsAvailable"] = true
        out["containerAvailable"] = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil
        out["storage"] = sharedDirectory?.path ?? "(コンテナ取得失敗)"

        let days = readDays()
        out["dayCount"] = days.count
        out["days"] = days.map { day -> [String: Any] in
            var d: [String: Any] = [
                "label": day.label,
                "isToday": day.isToday,
                "imageFile": day.imageFile ?? "(なし)",
            ]
            if let id = day.artworkId {
                let data = artworkData(for: id)
                d["fileExists"] = data != nil
                d["fileSize"] = data?.count ?? -1
                #if canImport(UIKit)
                d["decodable"] = data.flatMap { UIImage(data: $0) } != nil
                #endif
            }
            return d
        }

        if let dir = sharedDirectory {
            out["filesInDirectory"] =
                (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        }
        return out
    }
}
