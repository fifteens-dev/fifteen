import Flutter
import UIKit
import MusicKit
import MediaPlayer
import StoreKit
import ObjectiveC.runtime

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let musicKitChannel = "com.fifteen.musickit"
  private let fontsChannel = "com.fifteen.fonts"
  private let instagramChannel = "com.fifteen.instagram"
  private let deepLinkChannel = "com.fifteen.deeplink"
  private let musicMemoryChannel = "com.fifteen.musicmemory"
  private var nativeMenuChannel: AnyObject?
  private var deepLinkFlutterChannel: FlutterMethodChannel?
  // コールドスタート時に Flutter が準備できる前に届いた postId を保持
  private var _pendingDeepLinkPostId: String? = nil

  // MARK: - FlutterTextInputView swizzle: ペーストを常に許可

  /// FlutterTextInputView の canPerformAction:withSender: を差し替えて
  /// paste: セレクタを常に true にする。
  /// UIEditMenuInteraction (SystemContextMenu) はこの値を参照してペーストを表示する。
  private var _originalCanPerformIMP: IMP?

  private func swizzleFlutterPasteAction() {
    guard let targetClass = NSClassFromString("FlutterTextInputView") else { return }
    let sel = NSSelectorFromString("canPerformAction:withSender:")
    guard let method = class_getInstanceMethod(targetClass, sel) else { return }

    _originalCanPerformIMP = method_getImplementation(method)
    let origIMP = _originalCanPerformIMP  // ブロックにキャプチャするためローカルに保持

    // ブロックの引数: (receiver, action, sender)
    // imp_implementationWithBlock では _cmd は渡されない
    let newBlock: @convention(block) (AnyObject, Selector, AnyObject?) -> Bool =
      { (receiver, action, sender) in
        if action == #selector(UIResponderStandardEditActions.paste(_:)) {
          return true
        }
        guard let orig = origIMP else { return false }
        // 元の IMP を C 呼び出し規約で呼び出す（self, _cmd, action, sender の順）
        typealias Fn = @convention(c) (AnyObject, Selector, Selector, AnyObject?) -> Bool
        return unsafeBitCast(orig, to: Fn.self)(receiver, sel, action, sender)
      }

    method_setImplementation(method, imp_implementationWithBlock(newBlock))
  }

  /// UIKit のシステム UI（テキスト編集メニュー等）を端末言語に関わらず
  /// 日本語で表示するため、アプリ言語を起動前に強制設定する。
  override init() {
    UserDefaults.standard.set(["ja"], forKey: "AppleLanguages")
    super.init()
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // FlutterTextInputView の paste を常に許可（SystemContextMenu でペーストを常時表示）
    swizzleFlutterPasteAction()

    // Setup MusicKit Method Channel + Native Menu Channel
    if let controller = window?.rootViewController as? FlutterViewController {
      setupMusicKitChannel(controller: controller)
      setupFontsChannel(controller: controller)
      setupInstagramChannel(controller: controller)
      setupDeepLinkChannel(controller: controller)
      setupMusicMemoryChannel(controller: controller)
      if #available(iOS 14.0, *) {
        let menuChannel = NativeMenuChannel()
        menuChannel.setup(controller: controller)
        nativeMenuChannel = menuChannel  // ARC で解放されないよう保持

        // PlatformView: 透明 UIButton + UIMenu
        if let registrar = self.registrar(forPlugin: "NativeMenuButtonPlugin") {
          registrar.register(
            NativeMenuButtonFactory(messenger: registrar.messenger()),
            withId: "com.fifteen.nativemenu/button"
          )
        }
      }
    }

    // FCM: Request notification permissions
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { _, _ in }
      )
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }

    // FCM: Register for remote notifications
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Instagram Storiesチャンネル

  private func setupInstagramChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: instagramChannel,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "shareToStories":
        guard let args = call.arguments as? [String: Any],
              let imageTypedData = args["imageData"] as? FlutterStandardTypedData else {
          result(FlutterError(code: "INVALID_ARGS", message: "imageData is required", details: nil))
          return
        }
        let imageData = imageTypedData.data
        let contentURL = args["contentURL"] as? String

        self?.writeInstagramPasteboard(imageData: imageData, contentURL: contentURL)
        result(true)

      case "isInstagramAvailable":
        let url = URL(string: "instagram-stories://share")!
        result(UIApplication.shared.canOpenURL(url))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Instagram Stories ペーストボード書き込み

  private func writeInstagramPasteboard(imageData: Data, contentURL: String?) {
    var items: [String: Any] = ["com.instagram.sharedSticker.stickerImage": imageData]
    if let url = contentURL { items["com.instagram.sharedSticker.contentURL"] = url }
    UIPasteboard.general.setItems([items], options: [.expirationDate: Date().addingTimeInterval(300)])
  }

  // MARK: - Music Memory 再生情報チャンネル
  //
  // 端末の音楽ライブラリ / 再生状態から「今聞いている曲」「最後に再生した曲＋時刻」を
  // 取得して Flutter に返す。投稿フローの Now Playing / ○時間前 表示に使う。
  // 要 NSAppleMusicUsageDescription（Info.plist）。

  private func setupMusicMemoryChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: musicMemoryChannel,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "getNowPlaying":
        self?.ensureMediaAuth { authorized in
          guard authorized else { result(nil); return }
          let player = MPMusicPlayerController.systemMusicPlayer
          if let item = player.nowPlayingItem {
            result([
              "title": item.title ?? "",
              "artist": item.artist ?? "",
              "isPlaying": player.playbackState == .playing,
            ])
          } else {
            result(nil)
          }
        }
      case "getRecentlyPlayed":
        let limit = (call.arguments as? [String: Any])?["limit"] as? Int ?? 20
        self?.ensureMediaAuth { authorized in
          guard authorized else { result([]); return }
          let items = (MPMediaQuery.songs().items ?? [])
            .filter { $0.lastPlayedDate != nil }
            .sorted {
              ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast)
            }
            .prefix(limit)
          let mapped: [[String: Any]] = items.map { item in
            [
              "title": item.title ?? "",
              "artist": item.artist ?? "",
              "playedAtMs": Int((item.lastPlayedDate?.timeIntervalSince1970 ?? 0) * 1000),
            ]
          }
          result(mapped)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// メディアライブラリ権限を確認し、必要なら要求してから completion(認可可否) を返す。
  private func ensureMediaAuth(_ completion: @escaping (Bool) -> Void) {
    switch MPMediaLibrary.authorizationStatus() {
    case .authorized:
      completion(true)
    case .notDetermined:
      MPMediaLibrary.requestAuthorization { status in
        DispatchQueue.main.async { completion(status == .authorized) }
      }
    default:
      completion(false)
    }
  }

  // MARK: - SF Pro フォントチャンネル

  private func setupFontsChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: fontsChannel,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard self != nil else {
        result(FlutterError(code: "UNAVAILABLE", message: "App delegate not available", details: nil))
        return
      }
      switch call.method {
      case "getSFProFonts":
        self?.getSFProFonts(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// SF Pro の固有フォントファイルデータをリストで返す
  /// UIFont.systemFont を使うことで iOS が正しく SF Pro を解決する
  private func getSFProFonts(result: @escaping FlutterResult) {
    // UIFont.Weight で各ウェイトのシステムフォントを取得
    let weights: [(name: String, uiWeight: UIFont.Weight)] = [
      ("w100", .ultraLight),
      ("w200", .thin),
      ("w300", .light),
      ("w400", .regular),
      ("w500", .medium),
      ("w600", .semibold),
      ("w700", .bold),
      ("w800", .heavy),
      ("w900", .black),
    ]

    var seenURLs = Set<String>()
    var fontDataList: [FlutterStandardTypedData] = []

    for (_, uiWeight) in weights {
      let uiFont = UIFont.systemFont(ofSize: 17, weight: uiWeight)
      let ctFont = uiFont as CTFont
      guard let fontURL = CTFontCopyAttribute(ctFont, kCTFontURLAttribute) as? URL else { continue }

      let urlString = fontURL.absoluteString
      guard !seenURLs.contains(urlString) else { continue }
      seenURLs.insert(urlString)

      guard let data = try? Data(contentsOf: fontURL) else { continue }
      fontDataList.append(FlutterStandardTypedData(bytes: data))
    }

    if fontDataList.isEmpty {
      result(FlutterError(code: "FONT_ERROR", message: "Failed to load any SF Pro fonts", details: nil))
    } else {
      result(fontDataList)
    }
  }

  // MARK: - MusicKit チャンネル

  private func setupMusicKitChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: musicKitChannel,
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard self != nil else {
        result(FlutterError(code: "UNAVAILABLE", message: "App delegate not available", details: nil))
        return
      }

      switch call.method {
      case "requestAuthorization":
        self?.requestMusicKitAuthorization(result: result)
      case "getAuthorizationStatus":
        self?.getAuthorizationStatus(result: result)
      case "getUserToken":
        let args = call.arguments as? [String: Any]
        let developerToken = args?["developerToken"] as? String
        self?.getUserToken(result: result, developerToken: developerToken)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestMusicKitAuthorization(result: @escaping FlutterResult) {
    // Check iOS version
    if #available(iOS 15.0, *) {
      Task {
        do {
          let status = await MusicAuthorization.request()

          let statusString: String
          switch status {
          case .authorized:
            statusString = "authorized"
          case .denied:
            statusString = "denied"
          case .notDetermined:
            statusString = "notDetermined"
          case .restricted:
            statusString = "restricted"
          @unknown default:
            statusString = "unknown"
          }

          DispatchQueue.main.async {
            result(statusString)
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "AUTHORIZATION_ERROR",
              message: "Failed to request authorization: \(error.localizedDescription)",
              details: nil
            ))
          }
        }
      }
    } else {
      // iOS 15未満では利用不可
      result(FlutterError(
        code: "UNAVAILABLE",
        message: "MusicKit requires iOS 15.0 or later",
        details: nil
      ))
    }
  }

  private func getAuthorizationStatus(result: @escaping FlutterResult) {
    // Check iOS version
    if #available(iOS 15.0, *) {
      let status = MusicAuthorization.currentStatus

      let statusString: String
      switch status {
      case .authorized:
        statusString = "authorized"
      case .denied:
        statusString = "denied"
      case .notDetermined:
        statusString = "notDetermined"
      case .restricted:
        statusString = "restricted"
      @unknown default:
        statusString = "unknown"
      }

      result(statusString)
    } else {
      // iOS 15未満では「denied」を返す
      result("denied")
    }
  }

  private func getUserToken(result: @escaping FlutterResult, developerToken: String?) {
    if #available(iOS 15.0, *) {
      // Check if user is authorized first
      let status = MusicAuthorization.currentStatus
      guard status == .authorized else {
        result(FlutterError(
          code: "NOT_AUTHORIZED",
          message: "User is not authorized for Apple Music",
          details: nil
        ))
        return
      }

      guard let devToken = developerToken, !devToken.isEmpty else {
        result(FlutterError(
          code: "TOKEN_ERROR",
          message: "Developer token is required to obtain user token",
          details: nil
        ))
        return
      }

      // Use SKCloudServiceController to request actual Music User Token
      let controller = SKCloudServiceController()
      controller.requestUserToken(forDeveloperToken: devToken) { (userToken, error) in
        DispatchQueue.main.async {
          if let error = error {
            let nsError = error as NSError
            print("🔍 Token error - code: \(nsError.code), domain: \(nsError.domain)")
            // 認証済み(authorized)後にトークン取得が失敗する主な原因はサブスクリプション未加入
            result(FlutterError(
              code: "NO_SUBSCRIPTION",
              message: "Apple Musicのサブスクリプションが必要です",
              details: "\(nsError.code)"
            ))
          } else if let userToken = userToken, !userToken.isEmpty {
            result(userToken)
          } else {
            result(FlutterError(
              code: "TOKEN_ERROR",
              message: "User token was empty",
              details: nil
            ))
          }
        }
      }
    } else {
      result(FlutterError(
        code: "UNAVAILABLE",
        message: "MusicKit requires iOS 15.0 or later",
        details: nil
      ))
    }
  }

  // MARK: - ディープリンクチャンネル（fifteenapp://post/{postId}）

  private func setupDeepLinkChannel(controller: FlutterViewController) {
    let ch = FlutterMethodChannel(name: deepLinkChannel, binaryMessenger: controller.binaryMessenger)
    deepLinkFlutterChannel = ch

    // Flutter から呼ばれるメソッドを処理
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(FlutterMethodNotImplemented) }
      switch call.method {
      case "getInitialPostId":
        // コールドスタート時に保持した postId を返して消去
        result(self._pendingDeepLinkPostId)
        self._pendingDeepLinkPostId = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleDeepLinkURL(_ url: URL) -> Bool {
    guard url.scheme == "fifteenapp", url.host == "post" else { return false }
    let segments = url.pathComponents.filter { $0 != "/" }
    guard let postId = segments.first, !postId.isEmpty else { return false }

    // 常に pending に保存（Flutter が未準備のコールドスタートに備える）
    _pendingDeepLinkPostId = postId

    // Flutter が既に起動済みならすぐ通知（バックグラウンド復帰など）
    deepLinkFlutterChannel?.invokeMethod("onDeepLink", arguments: ["postId": postId])
    return true
  }

  // フォアグラウンドまたはバックグラウンドからURLで開かれたとき
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if handleDeepLinkURL(url) { return true }
    return super.application(app, open: url, options: options)
  }
}

