package com.siddhantpai.prahar

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes the battery-optimisation exemption to Dart.
 *
 * This is deliberately hand-written rather than using permission_handler. That
 * package pulls in a requirement for Android SDK 37, which installs as
 * `android-37.0` under Android's new minor-version scheme while Gradle looks
 * for `android-37` and fails. Two methods of platform code avoid a dependency,
 * an SDK bump and that mismatch entirely.
 *
 * The exemption matters more than anything else in the app: without it Android
 * freezes the process, and a correctly registered exact alarm wakes nothing, so
 * reminders only appear when the user next opens the app by hand.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "prahar/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        // Fire-and-forget: the system dialog is a separate
                        // activity, so the answer is not available here. Dart
                        // re-checks on resume instead.
                        result.success(requestExemption())
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prahar/widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    WidgetBridge.update(
                        applicationContext,
                        call.argument<String?>("title"),
                        call.argument<String?>("subject"),
                        call.argument<String?>("time"),
                        call.argument<String>("status") ?: "none",
                    )
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return true
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /** Returns false if the dialog could not be opened, so Dart can fall back
     *  to telling the user where to find the setting themselves. */
    private fun requestExemption(): Boolean = try {
        startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
        )
        true
    } catch (e: Exception) {
        // Some OEM builds do not ship this activity. Fall back to the app's
        // own settings page, which always exists.
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
            true
        } catch (e2: Exception) {
            false
        }
    }
}
