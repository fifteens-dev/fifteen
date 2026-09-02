import Foundation

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
    /// App Group コンテナ内のアートワークファイル名。未投稿の日は nil。
    public var imageFile: String?
    /// 今日の枠か（枠線・プレースホルダ表示の分岐に使う）。
    public var isToday: Bool

    public init(label: String, imageFile: String?, isToday: Bool) {
        self.label = label
        self.imageFile = imageFile
        self.isToday = isToday
    }
}

/// アプリ本体 ↔ ウィジェット拡張の共有領域（App Group）。
///
/// アプリは投稿直後・フォアグラウンド復帰時にストリップを書き出し、
/// ウィジェットは描画のたびにここを読む。push ではこの領域は変わらない。
public enum MusicMemoryShared {
    /// App Group ID。Runner / FifteensWidget の entitlements と一致させること。
    public static let appGroupId = "group.com.fifteens.sns"

    private static let daysKey = "musicMemory.days"

    public static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    /// アートワークを置くディレクトリ（App Group コンテナ内）。
    public static var artworkDirectory: URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return nil }
        let dir = base.appendingPathComponent("MusicMemoryArtwork", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func artworkURL(for file: String) -> URL? {
        artworkDirectory?.appendingPathComponent(file)
    }

    public static func writeDays(_ days: [MusicMemoryDay]) {
        guard let data = try? JSONEncoder().encode(days) else { return }
        defaults?.set(data, forKey: daysKey)
    }

    public static func readDays() -> [MusicMemoryDay] {
        guard let data = defaults?.data(forKey: daysKey),
              let days = try? JSONDecoder().decode([MusicMemoryDay].self, from: data)
        else { return [] }
        return days
    }

    /// 現在のストリップで参照されていないアートワークを削除する。
    public static func pruneArtwork(keeping days: [MusicMemoryDay]) {
        guard let dir = artworkDirectory else { return }
        let keep = Set(days.compactMap { $0.imageFile })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where !keep.contains(f) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }
}
