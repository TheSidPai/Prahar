package com.siddhantpai.prahar

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context

/**
 * Persists what the home-screen widget should show, then asks Android to
 * re-render every instance of the widget.
 *
 * The widget process is not the app process. It reads from SharedPreferences —
 * the only bridge available to a passive AppWidgetProvider that never runs
 * Dart. Keeping the payload small (four strings) keeps the widget update
 * cheap; the widget's job is to render, not to compute.
 */
object WidgetBridge {
    const val PREFS = "com.siddhantpai.prahar.widget"
    const val KEY_TITLE = "title"          // "Ch 4 — Aldehydes"
    const val KEY_SUBJECT = "subject"      // "Organic Chemistry"
    const val KEY_TIME = "time"            // "18:00 · 50m"
    const val KEY_STATUS = "status"        // "next", "now", "none"

    fun update(
        context: Context,
        title: String?,
        subject: String?,
        time: String?,
        status: String,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_TITLE, title ?: "")
            .putString(KEY_SUBJECT, subject ?: "")
            .putString(KEY_TIME, time ?: "")
            .putString(KEY_STATUS, status)
            .apply()

        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(ComponentName(context, NextBlockWidget::class.java))
        if (ids.isNotEmpty()) {
            val intent = android.content.Intent(context, NextBlockWidget::class.java)
            intent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            context.sendBroadcast(intent)
        }
    }
}
