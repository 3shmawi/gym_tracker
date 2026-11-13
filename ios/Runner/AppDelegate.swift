import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: taps on "Rest over" reach the app.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Move games: keep the screen on during a round (the phone lies on the
    // floor, untouched). lib/core/screen_awake/screen_awake.dart
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AzmScreenAwake") {
      let channel = FlutterMethodChannel(
        name: "azm/screen_awake", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "keepOn", let on = call.arguments as? Bool {
          UIApplication.shared.isIdleTimerDisabled = on
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
