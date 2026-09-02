import SwiftUI
import WidgetKit

/// Live Activity 専用のウィジェット拡張。ホーム画面ウィジェットは持たない。
/// （このターゲットの deployment target は 16.2 なので availability 分岐は不要）
@main
struct FifteensWidgetBundle: WidgetBundle {
    var body: some Widget {
        MusicMemoryLiveActivity()
    }
}
