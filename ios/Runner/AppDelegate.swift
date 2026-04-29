import Flutter
import UIKit
import AVFoundation
import MusicKit
import StoreKit
import ObjectiveC.runtime

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let musicKitChannel = "com.fifteen.musickit"
  private let fontsChannel = "com.fifteen.fonts"
  private let instagramChannel = "com.fifteen.instagram"
  private let deepLinkChannel = "com.fifteen.deeplink"
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
        let audioURLString = args["audioURL"] as? String
        let audioStartMs = args["audioStartMs"] as? Int ?? 0
        let durationSec = args["durationSec"] as? Int ?? 15

        if let urlString = audioURLString, let audioURL = URL(string: urlString) {
          // 音楽付き動画を生成してbackgroundVideoとして共有
          self?.createStoryVideo(
            imageData: imageData,
            audioURL: audioURL,
            audioStartMs: audioStartMs,
            durationSec: durationSec
          ) { videoData in
            DispatchQueue.main.async {
              if let videoData = videoData {
                self?.writeInstagramPasteboard(videoData: videoData, contentURL: contentURL)
              } else {
                // 動画生成失敗 → 静止画フォールバック
                self?.writeInstagramPasteboard(imageData: imageData, contentURL: contentURL)
              }
              result(true)
            }
          }
        } else {
          // previewURLなし → 静止画で共有
          self?.writeInstagramPasteboard(imageData: imageData, contentURL: contentURL)
          result(true)
        }

      case "isInstagramAvailable":
        let url = URL(string: "instagram-stories://share")!
        result(UIApplication.shared.canOpenURL(url))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Instagram Stories ペーストボード書き込み

  private func writeInstagramPasteboard(videoData: Data, contentURL: String?) {
    var items: [String: Any] = ["com.instagram.sharedSticker.backgroundVideo": videoData]
    if let url = contentURL { items["com.instagram.sharedSticker.contentURL"] = url }
    UIPasteboard.general.setItems([items], options: [.expirationDate: Date().addingTimeInterval(300)])
  }

  private func writeInstagramPasteboard(imageData: Data, contentURL: String?) {
    var items: [String: Any] = ["com.instagram.sharedSticker.stickerImage": imageData]
    if let url = contentURL { items["com.instagram.sharedSticker.contentURL"] = url }
    UIPasteboard.general.setItems([items], options: [.expirationDate: Date().addingTimeInterval(300)])
  }

  // MARK: - ストーリー用動画生成（投稿カード画像 + 音楽）

  /// 9:16 ストーリー動画を生成する
  /// - 投稿カード画像を中央に配置した黒背景フレームを動画に変換
  /// - iTunes previewを指定時刻からdurationSec秒だけ音声トラックとして合成
  private func createStoryVideo(
    imageData: Data,
    audioURL: URL,
    audioStartMs: Int,
    durationSec: Int,
    completion: @escaping (Data?) -> Void
  ) {
    guard let sourceImage = UIImage(data: imageData),
          let storyImage = makeStoryImage(from: sourceImage) else {
      completion(nil)
      return
    }

    let tmp = FileManager.default.temporaryDirectory
    let videoOnlyURL = tmp.appendingPathComponent("fif_vid_\(UUID().uuidString).mp4")
    let outputURL   = tmp.appendingPathComponent("fif_story_\(UUID().uuidString).mp4")

    // Step1: 静止画から無音動画を生成
    writeImageVideo(image: storyImage, duration: durationSec, outputURL: videoOnlyURL) { ok in
      guard ok else { completion(nil); return }

      // Step2: iTunes previewをダウンロード
      URLSession.shared.dataTask(with: audioURL) { [weak self] data, _, _ in
        guard let self = self, let audioData = data else {
          // ダウンロード失敗 → 無音動画をそのまま返す
          let v = try? Data(contentsOf: videoOnlyURL)
          try? FileManager.default.removeItem(at: videoOnlyURL)
          completion(v)
          return
        }

        let audioTmp = tmp.appendingPathComponent("fif_audio_\(UUID().uuidString).mp3")
        try? audioData.write(to: audioTmp)

        // Step3: 動画 + 音声を合成
        self.mergeVideoAndAudio(
          videoURL: videoOnlyURL,
          audioURL: audioTmp,
          audioStartMs: audioStartMs,
          durationSec: durationSec,
          outputURL: outputURL
        ) { success in
          try? FileManager.default.removeItem(at: videoOnlyURL)
          try? FileManager.default.removeItem(at: audioTmp)
          if success, let result = try? Data(contentsOf: outputURL) {
            try? FileManager.default.removeItem(at: outputURL)
            completion(result)
          } else {
            try? FileManager.default.removeItem(at: outputURL)
            completion(nil)
          }
        }
      }.resume()
    }
  }

  /// 投稿カード画像を 1080×1920（9:16）の黒背景中央に配置する
  private func makeStoryImage(from image: UIImage) -> UIImage? {
    let sw: CGFloat = 1080, sh: CGFloat = 1920
    let maxW = sw * 0.88, maxH = sh * 0.55
    let s = min(maxW / image.size.width, maxH / image.size.height)
    let iw = image.size.width * s, ih = image.size.height * s
    let ix = (sw - iw) / 2, iy = (sh - ih) / 2

    UIGraphicsBeginImageContextWithOptions(CGSize(width: sw, height: sh), true, 1)
    defer { UIGraphicsEndImageContext() }
    UIColor.black.setFill()
    UIRectFill(CGRect(x: 0, y: 0, width: sw, height: sh))
    image.draw(in: CGRect(x: ix, y: iy, width: iw, height: ih))
    return UIGraphicsGetImageFromCurrentImageContext()
  }

  /// 静止画を繰り返すだけの無音 H.264 動画を生成
  private func writeImageVideo(image: UIImage, duration: Int, outputURL: URL, completion: @escaping (Bool) -> Void) {
    try? FileManager.default.removeItem(at: outputURL)
    let w = Int(image.size.width), h = Int(image.size.height)

    guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
      completion(false); return
    }
    let videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: w, AVVideoHeightKey: h,
      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_500_000]
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h
      ]
    )
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    guard let pixelBuffer = image.toPixelBuffer(width: w, height: h) else {
      writer.cancelWriting(); completion(false); return
    }

    // 1fps: 0〜duration-1 フレームで durationSec 秒の動画を生成
    var frame = 0
    input.requestMediaDataWhenReady(on: DispatchQueue.global(qos: .userInitiated)) {
      while input.isReadyForMoreMediaData {
        if frame >= duration {
          input.markAsFinished()
          writer.finishWriting { completion(writer.status == .completed) }
          return
        }
        adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 1))
        frame += 1
      }
    }
  }

  /// 無音動画 + 音声ファイルを合成して MP4 を出力
  private func mergeVideoAndAudio(
    videoURL: URL,
    audioURL: URL,
    audioStartMs: Int,
    durationSec: Int,
    outputURL: URL,
    completion: @escaping (Bool) -> Void
  ) {
    try? FileManager.default.removeItem(at: outputURL)

    let composition = AVMutableComposition()
    let videoAsset = AVURLAsset(url: videoURL)
    let audioAsset = AVURLAsset(url: audioURL)

    let dur = CMTime(seconds: Double(durationSec), preferredTimescale: 600)
    let videoRange = CMTimeRange(start: .zero, duration: dur)

    guard
      let vTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
      let aTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
      let vAssetTrack = videoAsset.tracks(withMediaType: .video).first,
      let aAssetTrack = audioAsset.tracks(withMediaType: .audio).first
    else { completion(false); return }

    do {
      try vTrack.insertTimeRange(videoRange, of: vAssetTrack, at: .zero)

      // audioStartMs 分だけプレビューをオフセットして再生
      let audioOffset = CMTime(value: CMTimeValue(audioStartMs), timescale: 1000)
      let audioAvail  = CMTimeSubtract(audioAsset.duration, audioOffset)
      let audioDur    = CMTimeMinimum(audioAvail > .zero ? audioAvail : audioAsset.duration, dur)
      let audioRange  = CMTimeRange(start: audioOffset > .zero ? audioOffset : .zero, duration: audioDur)
      try aTrack.insertTimeRange(audioRange, of: aAssetTrack, at: .zero)
    } catch {
      completion(false); return
    }

    guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetMediumQuality) else {
      completion(false); return
    }
    export.outputURL = outputURL
    export.outputFileType = .mp4
    export.timeRange = videoRange
    export.exportAsynchronously { completion(export.status == .completed) }
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
            result(FlutterError(
              code: "TOKEN_ERROR",
              message: "Failed to get user token: \(error.localizedDescription)",
              details: nil
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

// MARK: - UIImage → CVPixelBuffer

private extension UIImage {
  func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    var buf: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    guard CVPixelBufferCreate(
      kCFAllocatorDefault, width, height,
      kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buf
    ) == kCVReturnSuccess, let buffer = buf else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let ctx = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer),
      width: width, height: height,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }

    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    UIGraphicsPushContext(ctx)
    draw(in: CGRect(x: 0, y: 0, width: width, height: height))
    UIGraphicsPopContext()
    return buffer
  }
}
