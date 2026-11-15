package com.mohager.azm

import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Move games: keep the screen on during a round (the phone lies on
        // the floor, untouched). lib/core/screen_awake/screen_awake.dart
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "azm/screen_awake")
            .setMethodCallHandler { call, result ->
                if (call.method == "keepOn") {
                    val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    if (call.arguments == true) window.addFlags(flag) else window.clearFlags(flag)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        // Google's test devices (Firebase Test Lab, which runs Play's
        // pre-launch report): no crash reports, no analytics, plain surfaces.
        // lib/core/device/test_device.dart
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "azm/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "isTestLab") {
                    val value = Settings.System.getString(contentResolver, "firebase.test.lab")
                    result.success("true" == value)
                } else {
                    result.notImplemented()
                }
            }
    }
}
