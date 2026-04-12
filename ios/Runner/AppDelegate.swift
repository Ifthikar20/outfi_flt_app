import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var pushChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Set up the MethodChannel for push notifications
    let controller = window?.rootViewController as! FlutterViewController
    pushChannel = FlutterMethodChannel(
      name: "ai.outfi.app/push",
      binaryMessenger: controller.binaryMessenger
    )

    pushChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "requestPermission" {
        self?.requestPushPermission(application: application, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Set notification delegate so we receive notifications in foreground
    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Permission Request

  private func requestPushPermission(
    application: UIApplication,
    result: @escaping FlutterResult
  ) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { granted, error in
      DispatchQueue.main.async {
        if granted {
          application.registerForRemoteNotifications()
        }
        result(granted)
      }
    }
  }

  // MARK: - APNs Token

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Convert token data to hex string
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    pushChannel?.invokeMethod("onToken", arguments: token)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("APNs registration failed: \(error.localizedDescription)")
  }

  // MARK: - Foreground Notification Display

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show the notification even when the app is in the foreground
    completionHandler([.banner, .badge, .sound])
  }

  // MARK: - Notification Tap

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    pushChannel?.invokeMethod("onNotification", arguments: userInfo)
    completionHandler()
  }
}
