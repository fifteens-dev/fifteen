import Flutter
import UIKit

// MARK: - PlatformView: Native UIButton with UIMenu

/// Flutter PlatformView ファクトリ — com.fifteen.nativemenu/button
///
/// 使い方: Flutter 側の UiKitView(viewType: 'com.fifteen.nativemenu/button') が
/// このファクトリを通じて NativeMenuButtonView を生成する。
@available(iOS 14.0, *)
class NativeMenuButtonFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return NativeMenuButtonView(frame: frame, viewId: viewId, messenger: messenger, args: args)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

/// Flutter PlatformView 本体 — 透明な UIButton を生成し、UIMenu をプライマリアクションに設定する。
///
/// ユーザーが実際にタップすると UIButton がタッチを受け取り UIMenu が開く。
/// 選択されたアイテムの id は MethodChannel `com.fifteen.nativemenu/button_{viewId}` で
/// Flutter 側に通知される。
@available(iOS 14.0, *)
class NativeMenuButtonView: NSObject, FlutterPlatformView {
  private let button: UIButton
  private var channel: FlutterMethodChannel?

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: Any?) {
    button = UIButton(type: .system)
    button.frame = frame
    button.backgroundColor = .clear
    button.tintColor = .clear
    button.showsMenuAsPrimaryAction = true

    super.init()

    channel = FlutterMethodChannel(
      name: "com.fifteen.nativemenu/button_\(viewId)",
      binaryMessenger: messenger
    )

    if let params = args as? [String: Any],
       let itemDicts = params["items"] as? [[String: Any]] {
      button.menu = buildMenu(from: itemDicts)
    }
  }

  func view() -> UIView {
    return button
  }

  private func buildMenu(from itemDicts: [[String: Any]]) -> UIMenu {
    let actions: [UIAction] = itemDicts.map { dict in
      let id = dict["id"] as? String ?? ""
      let title = dict["title"] as? String ?? ""
      let typeStr = dict["type"] as? String ?? "default"
      let iconName = dict["icon"] as? String

      var attributes: UIMenuElement.Attributes = []
      if typeStr == "destructive" { attributes = .destructive }

      let image = iconName.flatMap { UIImage(systemName: $0) }

      return UIAction(title: title, image: image, attributes: attributes) { [weak self] _ in
        self?.channel?.invokeMethod("onItemSelected", arguments: id)
      }
    }
    return UIMenu(title: "", children: actions)
  }
}

// MARK: - Method Channel: UIAlertController（ActionSheet）

/// iOS ネイティブ UIAlertController（ActionSheet）を Flutter から呼び出す Method Channel
///
/// チャンネル名: com.fifteen.nativemenu
/// メソッド: showMenu
///   引数:
///     items      [[String: Any]]  メニュー項目
///       id       String           選択時に返す識別子
///       title    String           表示ラベル
///       type     String           "default" or "destructive"
///     anchorX/Y/W/H Double       ボタン座標（iPad のポップオーバー用）
///   戻り値: 選択された id（String）。キャンセルは nil。
@available(iOS 14.0, *)
class NativeMenuChannel: NSObject {
  static let channelName = "com.fifteen.nativemenu"

  private var channel: FlutterMethodChannel?
  private weak var viewController: FlutterViewController?

  func setup(controller: FlutterViewController) {
    self.viewController = controller
    channel = FlutterMethodChannel(
      name: NativeMenuChannel.channelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "showMenu":
        self?.handleShowMenu(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleShowMenu(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let itemDicts = args["items"] as? [[String: Any]],
      let anchorX = args["anchorX"] as? Double,
      let anchorY = args["anchorY"] as? Double,
      let anchorW = args["anchorW"] as? Double,
      let anchorH = args["anchorH"] as? Double,
      let vc = viewController
    else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
      return
    }

    let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

    for dict in itemDicts {
      let id = dict["id"] as? String ?? ""
      let title = dict["title"] as? String ?? ""
      let typeStr = dict["type"] as? String ?? "default"
      let style: UIAlertAction.Style = (typeStr == "destructive") ? .destructive : .default

      alert.addAction(UIAlertAction(title: title, style: style) { _ in
        result(id)
      })
    }

    alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in
      result(nil)
    })

    // iPad: ポップオーバーの表示位置を指定
    if let popover = alert.popoverPresentationController {
      popover.sourceView = vc.view
      popover.sourceRect = CGRect(x: anchorX, y: anchorY, width: anchorW, height: anchorH)
      popover.permittedArrowDirections = [.up, .down]
    }

    DispatchQueue.main.async {
      vc.present(alert, animated: true)
    }
  }
}
