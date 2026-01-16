import Flutter
import UIKit
import MusicKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let musicKitChannel = "com.fifteen.musickit"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Setup MusicKit Method Channel
    if let controller = window?.rootViewController as? FlutterViewController {
      setupMusicKitChannel(controller: controller)
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
        self?.getUserToken(result: result)
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

  private func getUserToken(result: @escaping FlutterResult) {
    // Check iOS version
    if #available(iOS 15.0, *) {
      Task {
        do {
          // Get user token (requires authorization)
          let token = try await MusicUserTokenProvider().getUserToken()

          DispatchQueue.main.async {
            result(token)
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "TOKEN_ERROR",
              message: "Failed to get user token: \(error.localizedDescription)",
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
}
