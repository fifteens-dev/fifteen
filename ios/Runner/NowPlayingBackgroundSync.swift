import Foundation
import MediaPlayer

#if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
import FirebaseAuth
import FirebaseFirestore
#endif

/// 「今 Apple Music で聴いている曲」をバックグラウンドで共有する。
///
/// 友達の端末の再生状態を直接知る API は無いので、各自が自分のぶんを
/// Firestore に書き、友達はそれを読む（ウィジェット用）。
///
/// ## なぜ Swift でやるか
/// Background App Refresh の持ち時間は短い。Flutter エンジンを起こして
/// Dart 側で書くと、起動だけで使い切って間に合わないことがある。
/// 再生状態は MediaPlayer から同期で取れ、Firestore も iOS SDK が
/// 既に入っているので、ネイティブだけで完結させる。
///
/// ## 書く内容
/// 曲名・アーティスト名・カタログ ID だけ。位置情報や再生履歴のような
/// 重いものは持たせない。停止中も「停止」として書く（黙っていると友達側に
/// 前の曲が残り続ける）。
enum NowPlayingBackgroundSync {

    /// Dart 側の NowPlayingShareService.freshness と合わせること。
    /// 向こうはこれを過ぎた報告を「聴いていない」として捨てる。
    static let collection = "now_playing"

    /// 再生状態を書き込む。完了したら [completion] に「更新があったか」を返す。
    ///
    /// Background App Refresh の completionHandler へそのまま渡す想定。
    /// 新しいデータを返さないと OS が次から呼ばなくなるので、書けたかどうかを
    /// 正直に返す。
    static func publish(completion: @escaping (Bool) -> Void) {
        #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }

        // 再生中の曲。権限が無い・停止中なら nil のまま。
        let player = MPMusicPlayerController.systemMusicPlayer
        let isPlaying = player.playbackState == .playing
        let item = isPlaying ? player.nowPlayingItem : nil

        var data: [String: Any] = [
            "isPlaying": item != nil,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let item {
            data["trackName"] = item.title ?? ""
            data["artistName"] = item.artist ?? ""
            // カタログ ID があればアートワークを引ける。
            let storeId = item.playbackStoreID
            data["storeId"] = storeId.isEmpty ? NSNull() : storeId
        } else {
            data["trackName"] = NSNull()
            data["artistName"] = NSNull()
            data["storeId"] = NSNull()
        }

        Firestore.firestore().collection(collection).document(uid)
            .setData(data) { error in
                if let error {
                    NSLog("[nowPlayingSync] 失敗: \(error.localizedDescription)")
                    completion(false)
                } else {
                    NSLog("[nowPlayingSync] ok playing=\(item != nil)")
                    completion(true)
                }
            }
        #else
        completion(false)
        #endif
    }
}
