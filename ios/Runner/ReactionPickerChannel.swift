import Flutter
import UIKit

/// ネイティブの絵文字リアクションピッカー（すりガラスの吹き出し）。
///
/// チャンネル名: com.fifteen.reactionpicker
/// メソッド: show
///   引数:
///     emojis        [String]  横並びに表示する絵文字
///     anchorX/Y/W/H Double    スマイルボタンのグローバル座標(論理pt)
///   戻り値: 選択された絵文字(String)。キャンセル/外側タップ時は nil。
///
/// UIVisualEffectView によるネイティブのすりガラスで描画するため、Flutter の
/// BackdropFilter のようにプラットフォームビュー越しで黒くなる問題や、
/// FittedBox スケールによる見切れが起きない。
@available(iOS 13.0, *)
class ReactionPickerChannel: NSObject {
  static let channelName = "com.fifteen.reactionpicker"

  private var channel: FlutterMethodChannel?
  private weak var viewController: FlutterViewController?
  private var overlay: ReactionPickerOverlay?

  func setup(controller: FlutterViewController) {
    self.viewController = controller
    channel = FlutterMethodChannel(
      name: ReactionPickerChannel.channelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "show":
        self?.handleShow(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleShow(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let emojis = args["emojis"] as? [String],
      let ax = args["anchorX"] as? Double,
      let ay = args["anchorY"] as? Double,
      let aw = args["anchorW"] as? Double,
      let ah = args["anchorH"] as? Double,
      let vc = viewController
    else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
      return
    }

    // 既存があれば消す
    overlay?.dismissImmediately()
    overlay = nil

    let anchor = CGRect(x: ax, y: ay, width: aw, height: ah)
    var didReturn = false
    let ov = ReactionPickerOverlay(frame: vc.view.bounds, emojis: emojis, anchor: anchor) { [weak self] emoji in
      if didReturn { return }
      didReturn = true
      self?.overlay = nil
      result(emoji)
    }
    ov.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    vc.view.addSubview(ov)
    ov.present()
    overlay = ov
  }
}

@available(iOS 13.0, *)
class ReactionPickerOverlay: UIView {
  private let emojis: [String]
  private let onDone: (String?) -> Void
  private let bubble = UIView()

  init(frame: CGRect, emojis: [String], anchor: CGRect, onDone: @escaping (String?) -> Void) {
    self.emojis = emojis
    self.onDone = onDone
    super.init(frame: frame)
    backgroundColor = .clear

    // 外側タップで閉じる
    let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
    addGestureRecognizer(tap)

    // ── 吹き出し寸法 ─────────────────────────────
    let emojiSize: CGFloat = 30
    let sidePad: CGFloat = 16
    let gap: CGFloat = 16
    let count = CGFloat(max(emojis.count, 1))
    let bubbleW = sidePad * 2 + count * emojiSize + (count - 1) * gap
    let bubbleH: CGFloat = 50
    let corner: CGFloat = bubbleH / 2

    // ── すりガラス本体 ───────────────────────────
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    blur.frame = CGRect(x: 0, y: 0, width: bubbleW, height: bubbleH)
    blur.layer.cornerRadius = corner
    blur.clipsToBounds = true
    // 薄いふち
    blur.layer.borderWidth = 0.5
    blur.layer.borderColor = UIColor(white: 1.0, alpha: 0.12).cgColor

    bubble.frame = blur.frame
    bubble.layer.cornerRadius = corner
    bubble.layer.shadowColor = UIColor.black.cgColor
    bubble.layer.shadowOpacity = 0.28
    bubble.layer.shadowRadius = 14
    bubble.layer.shadowOffset = CGSize(width: 0, height: 6)
    bubble.addSubview(blur)

    // ── 絵文字ボタン ─────────────────────────────
    for (i, e) in emojis.enumerated() {
      let b = UIButton(type: .system)
      let x = sidePad + CGFloat(i) * (emojiSize + gap)
      b.frame = CGRect(x: x, y: (bubbleH - emojiSize) / 2, width: emojiSize, height: emojiSize)
      b.setTitle(e, for: .normal)
      b.titleLabel?.font = UIFont.systemFont(ofSize: 27)
      b.tag = i
      b.addTarget(self, action: #selector(handleEmoji(_:)), for: .touchUpInside)
      blur.contentView.addSubview(b)
    }

    // ── 位置決め（スマイルの真上、画面内にクランプ）──
    let margin: CGFloat = 8
    var bx = anchor.midX - 40.0 // 少し左寄り（尻尾がスマイルを指す位置感）
    bx = max(margin, min(bx, frame.width - bubbleW - margin))
    var by = anchor.minY - bubbleH - 8.0
    if by < margin { by = anchor.maxY + 8.0 } // 上に入らなければ下に出す
    bubble.frame = CGRect(x: bx, y: by, width: bubbleW, height: bubbleH)
    addSubview(bubble)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func present() {
    bubble.alpha = 0
    bubble.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
    UIView.animate(withDuration: 0.16, delay: 0, options: .curveEaseOut, animations: {
      self.bubble.alpha = 1
      self.bubble.transform = .identity
    })
    let gen = UISelectionFeedbackGenerator()
    gen.selectionChanged()
  }

  func dismissImmediately() {
    removeFromSuperview()
  }

  private func dismiss(selected: String?) {
    UIView.animate(withDuration: 0.12, animations: {
      self.bubble.alpha = 0
      self.bubble.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
    }, completion: { _ in
      self.removeFromSuperview()
    })
    onDone(selected)
  }

  @objc private func handleBackgroundTap() {
    dismiss(selected: nil)
  }

  @objc private func handleEmoji(_ sender: UIButton) {
    let idx = sender.tag
    let emoji = (idx >= 0 && idx < emojis.count) ? emojis[idx] : nil
    let gen = UIImpactFeedbackGenerator(style: .light)
    gen.impactOccurred()
    dismiss(selected: emoji)
  }
}
