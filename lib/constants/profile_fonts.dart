/// プロフィール画面のフォント方針（iOS のみ想定）:
///   - 英数字: SF Pro Rounded（この family を指定する）
///   - 日本語: iOS デフォルトの Hiragino Sans。SF Pro Rounded は日本語グリフを
///     持たないため、iOS のシステムフォールバックで自動的に Hiragino Sans に
///     なる。したがって fontFamily に本定数を指定するだけで両者を満たせる。
const String kSfProRounded = 'SF Pro Rounded';
