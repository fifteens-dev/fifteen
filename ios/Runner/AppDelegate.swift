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

  @available(iOS 15.0, *)
  private func requestMusicKitAuthorization(result: @escaping FlutterResult) {
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
  }

  @available(iOS 15.0, *)
  private func getAuthorizationStatus(result: @escaping FlutterResult) {
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
  }

  @available(iOS 15.0, *)
  private func getUserToken(result: @escaping FlutterResult) {
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
  }
}
