package com.siddhantpai.prahar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * The wider "today" tile: next block, the one after that, and a two-view
 * progress bar across the day.
 *
 * Deliberately narrow set of views (LinearLayout, TextView, View, FrameLayout)
 * after MIUI rejected the earlier layout with a generic "Can't load widget"
 * — its widget host has a stripped-down inflater that trips on framework
 * style references, drawable references from ProgressBar, and API 26 XML
 * attributes. Nothing here relies on any of those.
 */
class TodayWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = context.getSharedPreferences(
            WidgetBridge.PREFS, Context.MODE_PRIVATE)
        val title = prefs.getString(WidgetBridge.KEY_TITLE, "") ?: ""
        val subject = prefs.getString(WidgetBridge.KEY_SUBJECT, "") ?: ""
        val time = prefs.getString(WidgetBridge.KEY_TIME, "") ?: ""
        val status = prefs.getString(WidgetBridge.KEY_STATUS, "none") ?: "none"

        val title2 = prefs.getString(WidgetBridge.KEY_TITLE_2, "") ?: ""
        val subject2 = prefs.getString(WidgetBridge.KEY_SUBJECT_2, "") ?: ""
        val time2 = prefs.getString(WidgetBridge.KEY_TIME_2, "") ?: ""

        val progress = prefs.getInt(WidgetBridge.KEY_PROGRESS, 0).coerceIn(0, 100)
        val progressText = prefs.getString(WidgetBridge.KEY_PROGRESS_TEXT, "") ?: ""

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_today)

            if (status == "none" || title.isEmpty()) {
                views.setTextViewText(R.id.today_block1_subject, "")
                views.setTextViewText(R.id.today_block1_title, "Nothing today")
                views.setTextViewText(R.id.today_block1_time,
                    "Tap to open Prahar")
                views.setTextViewText(R.id.today_block2_title, "")
                views.setTextViewText(R.id.today_block2_meta, "")
                views.setTextViewText(R.id.today_progress_text, "")
            } else {
                views.setTextViewText(R.id.today_block1_subject, subject)
                views.setTextViewText(R.id.today_block1_title, title)
                views.setTextViewText(
                    R.id.today_block1_time,
                    if (status == "now") "Now  ·  $time" else time,
                )

                if (title2.isEmpty()) {
                    views.setTextViewText(
                        R.id.today_block2_title, "Nothing after")
                    views.setTextViewText(R.id.today_block2_meta, "")
                } else {
                    views.setTextViewText(R.id.today_block2_title, title2)
                    views.setTextViewText(
                        R.id.today_block2_meta, "$subject2  ·  $time2")
                }

                // A block of ▮ characters as a low-tech progress bar; TextView
                // renders these on every device without needing a runtime
                // width change. Ten cells covers percent precision to 10%,
                // which is as much as this format needs.
                val filled = (progress / 10).coerceIn(0, 10)
                val bar = "▮".repeat(filled) + "▯".repeat(10 - filled)
                views.setTextViewText(
                    R.id.today_progress_text, "$bar   $progressText")
            }

            val launch = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pending = PendingIntent.getActivity(
                context,
                0,
                launch,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.today_root, pending)

            appWidgetManager.updateAppWidget(id, views)
        }
    }

}
