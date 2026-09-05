package com.siddhantpai.prahar

import android.content.Context
import android.content.Intent
import android.net.Uri
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
