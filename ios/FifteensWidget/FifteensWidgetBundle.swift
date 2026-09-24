import SwiftUI
import WidgetKit

/// Live Activity とホーム画面ウィジェットのまとめ役。
/// （このターゲットの deployment target は 16.2 なので availability 分岐は不要）
@main
struct FifteensWidgetBundle: WidgetBundle {
    var body: some Widget {
        MusicMemoryLiveActivity()
        FriendNowPlayingWidget()
    }
}
