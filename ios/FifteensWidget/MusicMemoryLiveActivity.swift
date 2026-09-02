import ActivityKit
import SwiftUI
import WidgetKit

/// ロック画面 / 通知センターに貼り付く「今日のMusic Memory」Live Activity。
///
/// Figma 5305:12537 / 12623 / 12685 の 3 パターンを [MusicMemoryPhase] で切り替える。
/// 3 状態の差分は「サブタイトル・3行目・投稿ボタンの有無・今日の枠の中身」だけで、
/// 曜日ストリップ（過去4日＋今日）は共通。
@available(iOS 16.1, *)
struct MusicMemoryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MusicMemoryActivityAttributes.self) { context in
            MusicMemoryLockScreenView(state: context.state)
                .widgetURL(URL(string: MMLink.compose))
                .activityBackgroundTint(MMColor.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            MusicMemoryDynamicIsland.make(for: context.state)
        }
    }
}

// MARK: - 定数（Figma 準拠）

enum MMColor {
    /// カード背景 rgba(42,42,46,0.9)。
    static let background = Color(red: 42 / 255, green: 42 / 255, blue: 46 / 255).opacity(0.9)
    /// サブテキスト #9D9D9D。
    static let subtext = Color(red: 0x9D / 255, green: 0x9D / 255, blue: 0x9D / 255)
    /// 締切カウントダウンの警告色 #DFA506。
    static let deadline = Color(red: 0xDF / 255, green: 0xA5 / 255, blue: 0x06 / 255)
    /// 今日の空き枠の背景 #2B2927。
    static let todayPlaceholder = Color(red: 0x2B / 255, green: 0x29 / 255, blue: 0x27 / 255)
    /// 「投稿する」ボタン rgba(0,0,0,0.7)。
    static let button = Color.black.opacity(0.7)
}

enum MMLink {
    /// アクティビティ全体・投稿ボタンのタップ先（投稿フローを開く）。
    static let compose = "fifteenapp://compose"
}

/// Figma のカード幅 374pt を基準にした固定値。
private enum MMLayout {
    static let referenceWidth: CGFloat = 374
    static let horizontalPadding: CGFloat = 21
    static let slotGap: CGFloat = 13
    /// 4枠目と「今日」枠の間（区切り線を含む）の距離。
    static let dividerBlock: CGFloat = 30
    static let slotCorner: CGFloat = 10
}

// MARK: - ロック画面ビュー

@available(iOS 16.1, *)
struct MusicMemoryLockScreenView: View {
    let state: MusicMemoryActivityAttributes.ContentState

    /// ストリップは push では変わらないので、共有コンテナから描画のたびに読む。
    private var days: [MusicMemoryDay] { MusicMemoryShared.readDays() }

    private var phase: MusicMemoryPhase { state.resolvedPhase }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                headerText
                Spacer(minLength: 8)
                if phase != .posted {
                    postButton
                }
            }
            .padding(.top, 14)

            Spacer(minLength: 8)

            strip
                .padding(.bottom, 17)
        }
        .padding(.horizontal, MMLayout.horizontalPadding)
        .frame(height: 165)
    }

    // MARK: 左上のテキストブロック

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 「今日の」= SF Pro Bold / 「Music Memory」= SF Pro Rounded Bold
            (
                Text("今日の").font(.system(size: 18, weight: .bold))
                    + Text("Music Memory").font(.system(size: 18, weight: .bold, design: .rounded))
            )
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(MMColor.subtext)
                .lineLimit(1)
                .padding(.top, 5)

            thirdLine
                .padding(.top, 5)
        }
    }

    private var subtitle: String {
        switch phase {
        case .waiting: return "まだ投稿していません"
        case .friendsWaiting: return "友達があなたを待っています"
        case .posted: return "投稿が完了しました🎉"
        }
    }

    /// 3行目。友達待ちのときだけ、締切までのライブカウントダウン（アンバー）にする。
    @ViewBuilder
    private var thirdLine: some View {
        switch phase {
        case .waiting:
            Text("25:00まで")
                .font(.system(size: 11))
                .foregroundColor(.white)
                .lineLimit(1)
        case .friendsWaiting:
            HStack(spacing: 0) {
                Text("締切まで")
                // タイマーは 1 秒ごとにシステムが再描画する（push 不要）。
                Text(timerInterval: Date()...max(state.deadline, Date().addingTimeInterval(1)),
                     countsDown: true)
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(MMColor.deadline)
            .lineLimit(1)
        case .posted:
            Text("友達の今日にリアクションしよう！")
                .font(.system(size: 11))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }

    // MARK: 「🎵 投稿する」ボタン

    private var postButton: some View {
        Link(destination: URL(string: MMLink.compose)!) {
            Text("🎵 投稿する")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 103, height: 33)
                .background(MMColor.button)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: 曜日ストリップ（木/金/土/日 ＋ 区切り線 ＋ 今日）

    private var strip: some View {
        GeometryReader { geo in
            let slot = slotSize(for: geo.size.width)
            let past = days.filter { !$0.isToday }
            let today = days.first(where: { $0.isToday })

            HStack(spacing: 0) {
                HStack(spacing: MMLayout.slotGap) {
                    ForEach(Array(past.enumerated()), id: \.offset) { _, day in
                        slotView(day: day, size: slot)
                    }
                }
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 1, height: 20)
                Spacer(minLength: 0)
                slotView(day: today ?? MusicMemoryDay(label: "今日", imageFile: nil, isToday: true),
                         size: slot)
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
        // ラベル(11pt) + 余白 + アート
        .frame(height: 53 + 20)
    }

    /// Figma の 374pt 幅で 53pt になる比率を保ちつつ、狭い端末でも収める。
    private func slotSize(for width: CGFloat) -> CGFloat {
        let usable = width - MMLayout.slotGap * 3 - MMLayout.dividerBlock
        return max(34, min(53, usable / 5))
    }

    private func slotView(day: MusicMemoryDay, size: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(day.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(day.isToday ? .white : MMColor.subtext)
                .lineLimit(1)
            artwork(for: day, size: size)
        }
        .frame(width: size)
    }

    @ViewBuilder
    private func artwork(for day: MusicMemoryDay, size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: MMLayout.slotCorner, style: .continuous)
        if let file = day.imageFile,
           let url = MusicMemoryShared.artworkURL(for: file),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(shape)
        } else if day.isToday {
            // 未投稿の「今日」枠: グラデーション枠線 ＋ ＋ アイコン。
            shape
                .fill(MMColor.todayPlaceholder)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundColor(.white)
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(red: 0x36 / 255, green: 0xC5 / 255, blue: 0xF4 / 255),
                                Color(red: 0xF8 / 255, green: 0x57 / 255, blue: 0xC1 / 255),
                                Color(red: 0x6D / 255, green: 0x5B / 255, blue: 0xFF / 255),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                )
        } else {
            // 過去日で投稿が無い枠は、空のプレースホルダにする（歯抜けを潰さない）。
            shape
                .fill(Color.white.opacity(0.06))
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Dynamic Island

@available(iOS 16.1, *)
enum MusicMemoryDynamicIsland {
    static func make(
        for state: MusicMemoryActivityAttributes.ContentState
    ) -> DynamicIsland {
        let phase = state.resolvedPhase
        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                Image(systemName: "music.note")
                    .foregroundColor(.white)
                    .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                if phase != .posted {
                    Text(timerInterval: Date()...max(state.deadline, Date().addingTimeInterval(1)),
                         countsDown: true)
                        .monospacedDigit()
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MMColor.deadline)
                        .frame(width: 64)
                } else {
                    Text("🎉").font(.system(size: 16))
                }
            }
            DynamicIslandExpandedRegion(.center) {
                Text("今日のMusic Memory")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            DynamicIslandExpandedRegion(.bottom) {
                Text(bottomText(phase))
                    .font(.system(size: 12))
                    .foregroundColor(MMColor.subtext)
            }
        } compactLeading: {
            Image(systemName: "music.note").foregroundColor(.white)
        } compactTrailing: {
            if phase == .posted {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                Text(timerInterval: Date()...max(state.deadline, Date().addingTimeInterval(1)),
                     countsDown: true)
                    .monospacedDigit()
                    .frame(width: 44)
                    .foregroundColor(MMColor.deadline)
            }
        } minimal: {
            Image(systemName: phase == .posted ? "checkmark.circle.fill" : "music.note")
                .foregroundColor(phase == .posted ? .green : .white)
        }
        .widgetURL(URL(string: MMLink.compose))
        .keylineTint(MMColor.deadline)
    }

    private static func bottomText(_ phase: MusicMemoryPhase) -> String {
        switch phase {
        case .waiting: return "まだ投稿していません"
        case .friendsWaiting: return "友達があなたを待っています"
        case .posted: return "友達の今日にリアクションしよう！"
        }
    }
}
