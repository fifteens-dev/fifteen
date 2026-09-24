import SwiftUI
import WidgetKit

/// ホーム画面ウィジェット「友達が今聴いてる曲」（Figma 5761-11798）。
///
/// アプリが App Group に書いた [FriendNowPlaying] を読んで出す。1 件ずつ
/// 表示し、更新のたびに次の友達へ送る。
///
/// 背景はすりガラス。iOS 17 以降は `containerBackground` を付けないと
/// ホーム画面のウィジェットが表示されないため、必ず指定する。
struct FriendNowPlayingWidget: Widget {
    static let kind = "FriendNowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FriendNowPlayingProvider()) { entry in
            FriendNowPlayingView(entry: entry)
        }
        .configurationDisplayName("友達の1曲")
        .description("友達が今日えらんだ曲を表示します。")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Timeline

struct FriendNowPlayingEntry: TimelineEntry {
    let date: Date
    let item: FriendNowPlaying?
}

struct FriendNowPlayingProvider: TimelineProvider {
    /// 1 件を見せている時間。短すぎると通信・電力の無駄になり、長すぎると
    /// 友達が一巡しない。
    private static let rotateInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> FriendNowPlayingEntry {
        FriendNowPlayingEntry(date: Date(), item: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FriendNowPlayingEntry) -> Void) {
        completion(FriendNowPlayingEntry(date: Date(), item: FriendNowPlayingShared.read().first))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FriendNowPlayingEntry>) -> Void) {
        let items = FriendNowPlayingShared.read()
        guard !items.isEmpty else {
            // まだ何も無いときは少し待ってから取り直す。
            let entry = FriendNowPlayingEntry(date: Date(), item: nil)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
            return
        }

        // 友達を順番に見せる。1 回の Timeline に全員ぶん積んでおけば、
        // 途中で OS に更新を取りに来てもらわなくても切り替わる。
        let now = Date()
        var entries: [FriendNowPlayingEntry] = []
        for (index, item) in items.enumerated() {
            let date = now.addingTimeInterval(Double(index) * Self.rotateInterval)
            entries.append(FriendNowPlayingEntry(date: date, item: item))
        }
        // 一巡したら読み直す（そのころには新しい投稿が来ている）。
        let end = now.addingTimeInterval(Double(items.count) * Self.rotateInterval)
        completion(Timeline(entries: entries, policy: .after(end)))
    }
}

// MARK: - View

struct FriendNowPlayingView: View {
    let entry: FriendNowPlayingEntry

    @ViewBuilder
    var body: some View {
        if #available(iOS 17.0, *) {
            // iOS 17 以降はこれが無いとホーム画面に出ない。
            // すりガラスは自前で敷かず、システムのマテリアルに任せる。
            content.containerBackground(for: .widget) { Color.clear }
        } else {
            // iOS 16 では containerBackground が無く、既定で
            // すりガラスの上に描かれる。
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let item = entry.item {
            filled(item)
        } else {
            empty
        }
    }

    /// Figma: 164×164 の中に アート 85（左上 18,18）、
    /// サービスバッジ 35（111,18）、友達アイコン 35（111,65）、
    /// 曲名 13pt（18,111）、アーティスト 11pt。
    private func filled(_ item: FriendNowPlaying) -> some View {
        GeometryReader { geo in
            // 164 を基準にした比率で置く（Small の実寸は端末で変わる）。
            let s = geo.size.width / 164

            ZStack(alignment: .topLeading) {
                artwork(item, side: 85 * s)
                    .offset(x: 18 * s, y: 18 * s)

                serviceBadge(item.service, side: 35 * s)
                    .offset(x: 111 * s, y: 18 * s)

                avatar(item, side: 35 * s)
                    .offset(x: 111 * s, y: 65 * s)

                VStack(alignment: .leading, spacing: 1 * s) {
                    Text(item.trackName)
                        .font(.system(size: 13 * s, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.artistName)
                        .font(.system(size: 11 * s))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .offset(x: 18 * s, y: 111 * s)
                .frame(width: 128 * s, alignment: .leading)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("友達の投稿を待っています")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func artwork(_ item: FriendNowPlaying, side: CGFloat) -> some View {
        Group {
            if let id = item.artworkId,
               let data = MusicMemoryShared.artworkData(for: id),
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.primary.opacity(0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.3))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 5 * (side / 85), style: .continuous))
    }

    private func avatar(_ item: FriendNowPlaying, side: CGFloat) -> some View {
        Group {
            if let id = item.avatarId,
               let data = MusicMemoryShared.artworkData(for: id),
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.primary.opacity(0.15)
                    Text(String(item.friendName.prefix(1)))
                        .font(.system(size: side * 0.42, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
    }

    /// 右上の音楽サービス。素材を増やさず SF Symbols で出す。
    private func serviceBadge(_ service: String?, side: CGFloat) -> some View {
        ZStack {
            Circle().fill(badgeColor(service))
            Image(systemName: "music.note")
                .font(.system(size: side * 0.45, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: side, height: side)
    }

    private func badgeColor(_ service: String?) -> Color {
        switch service {
        case "spotify": return Color(red: 0.11, green: 0.73, blue: 0.33)
        default: return Color(red: 0.98, green: 0.19, blue: 0.36) // Apple Music
        }
    }
}
