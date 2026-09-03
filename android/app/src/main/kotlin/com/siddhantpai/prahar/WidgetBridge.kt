package com.siddhantpai.prahar

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context

/**
 * Persists what the home-screen widgets should show, then asks Android to
 * re-render every instance of each registered widget.
 *
 * The widget process is not the app process. It reads from SharedPreferences —
 * the only bridge available to a passive AppWidgetProvider that never runs
 * Dart. Keeping the payload small (a dozen strings) keeps updates cheap; the
 * widget's job is to render, not to compute.
 *
 * Two widget flavours share this payload:
 *   NextBlockWidget  — compact tile: title / subject / time of block 0
 *   TodayWidget      — larger tile:  block 0 + block 1 + progress bar
 */
object WidgetBridge {
    const val PREFS = "com.siddhantpai.prahar.widget"

    // Block 0 — the next (or currently running) study block.
    const val KEY_TITLE = "title"
    const val KEY_SUBJECT = "subject"
    const val KEY_TIME = "time"

    // Block 1 — the one after that. Empty when there is only one block left.
    const val KEY_TITLE_2 = "title2"
    const val KEY_SUBJECT_2 = "subject2"
    const val KEY_TIME_2 = "time2"

    // "next", "now", "none". Drives whether block 0 gets a "Now" marker.
    const val KEY_STATUS = "status"

    // Progress across today's plan, as a 0..100 int for RemoteViews, and a
    // human-readable summary. Integer to avoid float parsing in the widget.
    const val KEY_PROGRESS = "progress"        // 0..100
    const val KEY_PROGRESS_TEXT = "progressText" // "1h 30m of 3h"

    fun update(
        context: Context,
        payload: Map<String, Any?>,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val edit = prefs.edit()
        for ((k, v) in payload) {
            when (v) {
                null -> edit.putString(k, "")
                is String -> edit.putString(k, v)
                is Int -> edit.putInt(k, v)
                else -> edit.putString(k, v.toString())
            }
        }
        edit.apply()

        val mgr = AppWidgetManager.getInstance(context)
        for (cls in arrayOf(NextBlockWidget::class.java, TodayWidget::class.java)) {
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isNotEmpty()) {
                val intent = android.content.Intent(context, cls)
                intent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                context.sendBroadcast(intent)
            }
        }
    }
}
