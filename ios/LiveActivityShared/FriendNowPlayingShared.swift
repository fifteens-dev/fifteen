import Foundation

/// ホーム画面ウィジェットに出す「友達が聴いている曲」1 件分。
///
/// アプリが App Group のファイルに書き、ウィジェットが読む。画像本体は
/// [MusicMemoryShared.artworkData] と同じ置き場から `art_<id>.jpg` で引く
/// （ファイル保護レベルの都合は [MusicMemoryShared] のコメント参照）。
public struct FriendNowPlaying: Codable, Hashable {
    /// 曲名。
    public var trackName: String
    /// アーティスト名。
    public var artistName: String
    /// アルバムアートの識別子（投稿の postId）。画像が無いときは nil。
    public var artworkId: String?
    /// 友達のアイコンの識別子。`art_<id>.jpg` として同じ置き場から引く。
    public var avatarId: String?
    /// 友達の表示名。アイコンが出せないときの代わりに頭文字を出す。
    public var friendName: String
    /// 音楽サービス（"appleMusic" / "spotify"）。右上のバッジに使う。
    public var service: String?

    public init(
        trackName: String,
        artistName: String,
        artworkId: String?,
        avatarId: String?,
        friendName: String,
        service: String?
    ) {
        self.trackName = trackName
        self.artistName = artistName
        self.artworkId = artworkId
        self.avatarId = avatarId
        self.friendName = friendName
        self.service = service
    }
}

/// 友達の曲の読み書き。
///
/// ウィジェットは更新のたびに次の 1 件へ送る想定なので、複数件をそのまま
/// 持っておき、どれを出すかは表示側（TimelineProvider）が決める。
public enum FriendNowPlayingShared {
    private static var listURL: URL? {
        MusicMemoryShared.sharedDirectory?
            .appendingPathComponent("friend_now_playing.json")
    }

    public static func write(_ items: [FriendNowPlaying]) {
        guard let url = listURL, let data = try? JSONEncoder().encode(items) else {
            MMLog.log("writeFriends", "失敗: URL かエンコードが取れない")
            return
        }
        do {
            // ロック中でも読めるよう保護レベルを外す（MusicMemoryShared と同じ理由）。
            try data.write(to: url, options: [.atomic, .noFileProtection])
            MMLog.log("writeFriends", "ok count=\(items.count)")
        } catch {
            MMLog.log("writeFriends", "書き込み失敗 \(error)")
        }
    }

    public static func read() -> [FriendNowPlaying] {
        guard let url = listURL,
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([FriendNowPlaying].self, from: data)
        else {
            return []
        }
        return items
    }

    /// 一覧に無くなった画像を消す。アートワークと友達アイコンの両方が対象。
    public static func pruneArtwork(keeping items: [FriendNowPlaying]) {
        guard let dir = MusicMemoryShared.sharedDirectory else { return }
        var keep = Set<String>()
        for item in items {
            if let id = item.artworkId { keep.insert("art_\(id).jpg") }
            if let id = item.avatarId { keep.insert("art_\(id).jpg") }
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for file in files where file.hasPrefix("art_friend_") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
    }
}
