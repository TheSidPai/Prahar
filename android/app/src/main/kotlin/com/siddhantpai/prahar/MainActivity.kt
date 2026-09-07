package com.siddhantpai.prahar

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.OpenableColumns
import android.util.Log
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
                    "backgroundVendor" -> {
                        result.success(Build.MANUFACTURER.lowercase())
                    }
                    // Whether this device actually has a vendor autostart
                    // screen. This is the honest question, and the one the
                    // manufacturer string only guesses at.
                    "hasAutoStartSettings" -> {
                        result.success(autoStartIntent() != null)
                    }
                    "openAutoStartSettings" -> {
                        result.success(openAutoStartSettings())
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prahar/widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    @Suppress("UNCHECKED_CAST")
                    val payload = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                    WidgetBridge.update(applicationContext, payload)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prahar/files")
            .setMethodCallHandler { call, result ->
                // A Java exception escaping this block does not become a Dart
                // error — the engine aborts the process on a pending JNI
                // exception, which surfaces as a native tombstone naming
                // CheckException and nothing about the actual cause. Catching
                // here turns any such crash into a message Dart can show.
                try {
                    Log.i(TAG, "call ${call.method}")
                    when (call.method) {
                        "save" -> saveDocument(
                            call.argument<String>("name") ?: "prahar-backup.json",
                            call.argument<String>("contents") ?: "",
                            result,
                        )
                        "open" -> openDocument(result)
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    Log.e(TAG, "handler threw on ${call.method}", t)
                    clearPending()
                    try {
                        result.error("handler", t.toString(), null)
                    } catch (ignored: Throwable) {
                        // The reply channel is gone; nothing left to tell.
                    }
                }
            }
    }

    // ---------------------------------------------------------------------
    // Backup files, through the Storage Access Framework.
    //
    // The app used to write to /sdcard/Download/Prahar and read a file the
    // user had to name prahar-restore.json by hand. Both are wrong: scoped
    // storage blocks raw writes to public directories from API 30, so the
    // path may not be writable at all, and no app should be dictating where
    // someone keeps their own data.
    //
    // SAF hands the choice to the system picker. It needs no storage
    // permission of any kind — the user granting access to one document *is*
    // the permission — which is why the manifest gains nothing here.
    // ---------------------------------------------------------------------

    private var pendingResult: MethodChannel.Result? = null
    private var pendingContents: String? = null

    private fun saveDocument(name: String, contents: String, result: MethodChannel.Result) {
        if (!claim(result)) return
        pendingContents = contents
        try {
            startActivityForResult(
                Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                    putExtra(Intent.EXTRA_TITLE, name)
                },
                REQ_SAVE,
            )
        } catch (e: Exception) {
            clearPending()
            result.error("no_picker", e.message, null)
        }
    }

    private fun openDocument(result: MethodChannel.Result) {
        if (!claim(result)) return
        try {
            startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    // Not "application/json": plenty of providers report a
                    // backup as octet-stream or text/plain, and a strict
                    // filter greys out the very file the user is looking at.
                    type = "*/*"
                    putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        arrayOf("application/json", "text/plain", "application/octet-stream"),
                    )
                },
                REQ_OPEN,
            )
        } catch (e: Exception) {
            clearPending()
            result.error("no_picker", e.message, null)
        }
    }

    /** One picker at a time; a second call while one is open is a bug. */
    private fun claim(result: MethodChannel.Result): Boolean {
        if (pendingResult != null) {
            result.error("busy", "A file picker is already open.", null)
            return false
        }
        pendingResult = result
        return true
    }

    /** Named for what it does rather than `release`, which is already a member
     *  of FlutterActivity and hides it. */
    private fun clearPending() {
        pendingResult = null
        pendingContents = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQ_SAVE && requestCode != REQ_OPEN) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingResult
        val contents = pendingContents

        // clearPending, NOT release. FlutterActivity has its own release(),
        // which tears down the engine — calling it here destroyed the engine
        // and the very next line replied through it, throwing a Java
        // exception that the JNI check turns into an immediate process abort.
        // The tombstone said only "CheckException" and named nothing.
        clearPending()

        Log.i(TAG, "result req=$requestCode code=$resultCode pending=${result != null}")

        // The activity can be destroyed and rebuilt while the picker is in
        // front of it, leaving a new instance with nothing pending and a Dart
        // future that will never complete. There is nobody to reply to.
        if (result == null) {
            Log.w(TAG, "no pending result — the activity was recreated")
            return
        }

        try {
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) {
                // Cancelling is an ordinary outcome, not a failure. Dart shows
                // nothing rather than an error nobody caused.
                result.success(null)
                return
            }

            if (requestCode == REQ_SAVE) {
                contentResolver.openOutputStream(uri)?.use {
                    it.write((contents ?: "").toByteArray(Charsets.UTF_8))
                } ?: throw IllegalStateException("Could not open $uri for writing")
                result.success(displayNameOf(uri))
            } else {
                val text = contentResolver.openInputStream(uri)?.use { stream ->
                    stream.bufferedReader(Charsets.UTF_8).readText()
                } ?: throw IllegalStateException("Could not read $uri")
                Log.i(TAG, "read ${text.length} chars")
                result.success(text)
            }
        } catch (t: Throwable) {
            // Throwable rather than Exception: an Error escaping here aborts
            // the process through that same JNI check instead of failing the
            // call, and the crash would again name nothing useful.
            Log.e(TAG, "activity result failed", t)
            try {
                result.error("io", t.toString(), null)
            } catch (ignored: Throwable) {
                // Reply channel already gone.
            }
        }
    }

    /** What to call the file in a confirmation message; the raw URI is not
     *  something to show anybody. */
    private fun displayNameOf(uri: Uri): String {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (i >= 0 && c.moveToFirst()) c.getString(i) else uri.lastPathSegment
            } ?: uri.lastPathSegment ?: "backup"
        } catch (e: Exception) {
            uri.lastPathSegment ?: "backup"
        }
    }

    private companion object {
        const val REQ_SAVE = 4201
        const val REQ_OPEN = 4202
        const val TAG = "PraharFiles"
    }

    // ---------------------------------------------------------------------
    // Autostart, which is a separate gate from battery optimisation.
    //
    // The exemption tells stock Android not to freeze the process. It says
    // nothing to MIUI, ColorOS, Funtouch or One UI, each of which keeps its
    // own list of apps allowed to start on their own, and each of which
    // defaults a sideloaded app to "not allowed". A blocked app's alarms stay
    // registered and visible in dumpsys, and simply never wake anything.
    //
    // There is no API to read the state of any of these lists, so the app
    // cannot know whether it is blocked. It can only know it is on a phone
    // that has the gate, which is why the card this drives is advisory and
    // dismissible rather than a warning that claims to have checked.
    //
    // Components rather than actions because none of these are public
    // intents; they are activities inside each vendor's own security app.
    // ---------------------------------------------------------------------

    private val autoStartTargets = listOf(
        // Xiaomi, and so also Redmi and Poco, which run the same firmware.
        "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        // Oppo, Realme and OnePlus, which all run ColorOS underneath now.
        //
        // com.oplus.battery first, and this one is not a guess: it was read
        // off a OnePlus Pad on OxygenOS 16 with `dev.ps1 vendorpkgs`. The
        // autostart list moved out of the security app and into the battery
        // app, which is why an earlier build found com.oplus.safecenter
        // installed, resolved none of its activities, and showed no card at
        // all on a phone that very much has the gate.
        "com.oplus.battery" to "com.oplus.startupapp.view.StartupAppListActivity",
        "com.oplus.battery" to "com.oplus.startupapp.view.OptimizationAutoStartActivity",
        "com.oplus.safecenter" to "com.oplus.safecenter.permission.startup.StartupAppListActivity",
        "com.oplus.safecenter" to "com.oplus.safecenter.startupapp.StartupAppListActivity",
        "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
        "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
        "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
        "com.coloros.safecenter" to "com.coloros.privacypermissionsentry.PermissionTopActivity",
        "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
        // Vivo and iQOO.
        "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
        "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
        "com.iqoo.secure" to "com.iqoo.secure.safeguard.PurviewTabActivity",
        // Huawei and Honor.
        "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
        // Samsung. There is no autostart list; the equivalent is keeping the
        // app out of the sleeping-apps list, inside Device Care. One UI has
        // moved this activity across versions, so several spellings are tried
        // rather than assuming the one that happened to be current.
        "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
        "com.samsung.android.lool" to "com.samsung.android.sm.ui.battery.BatteryActivity",
        "com.samsung.android.lool" to "com.samsung.android.sm.ui.cstyleboard.SmartManagerDashBoardActivity",
        "com.asus.mobilemanager" to "com.asus.mobilemanager.autostart.AutoStartActivity",
        "com.letv.android.letvsafe" to "com.letv.android.letvsafe.AutobootManageActivity",
    )

    /** The first vendor screen that exists on this device, or null. */
    private fun autoStartIntent(): Intent? {
        for ((pkg, cls) in autoStartTargets) {
            val intent = Intent().setComponent(ComponentName(pkg, cls))
            val found = try {
                // resolveActivityInfo with no flags, not MATCH_DEFAULT_ONLY.
                // These are explicit components, and MATCH_DEFAULT_ONLY drops
                // any activity whose filter lacks CATEGORY_DEFAULT — which a
                // vendor's internal settings screen has no reason to declare.
                //
                // The exported check matters just as much: an activity that
                // resolves but is not exported throws SecurityException on
                // startActivity, which would put us back to promising a screen
                // and delivering App info.
                val info = intent.resolveActivityInfo(packageManager, 0)
                info != null && info.exported
            } catch (e: Exception) {
                false
            }
            if (found) return intent
        }
        return null
    }

    /**
     * Opens the vendor's autostart screen.
     *
     * Returns what actually happened rather than a bare boolean, because the
     * three outcomes need three different things said to the user:
     *
     *  - "vendor"   the real list opened; say nothing
     *  - "fallback" only App info opened, which is not what the button
     *               promised, so Dart has to explain where to go from there
     *  - "none"     nothing opened at all
     *
     * The old version returned true for the fallback, so a OnePlus owner
     * tapped a button promising the Auto-launch list, landed on App info, and
     * got no explanation, because as far as the app was concerned it had
     * succeeded.
     */
    private fun openAutoStartSettings(): String {
        val intent = autoStartIntent()
        if (intent != null) {
            try {
                // The vendor activity is in another task; without this it can
                // reopen behind Prahar and look as though nothing happened.
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return "vendor"
            } catch (e: Exception) {
                Log.w(TAG, "autostart screen resolved but would not open", e)
            }
        }
        return try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
            "fallback"
        } catch (e: Exception) {
            "none"
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
