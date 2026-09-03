package com.siddhantpai.prahar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/**
 * The larger "today" tile: next block, the one after that, and a progress bar
 * across the day.
 *
 * A distinct widget rather than a resize variant so each layout stays
 * hand-tuned. Sharing the payload with [NextBlockWidget] keeps the data path
 * single-sourced; the two widgets differ only in which fields they render.
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

        val progress = prefs.getInt(WidgetBridge.KEY_PROGRESS, 0)
        val progressText = prefs.getString(WidgetBridge.KEY_PROGRESS_TEXT, "") ?: ""

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_today)

            // Empty state — no blocks left today.
            if (status == "none" || title.isEmpty()) {
                views.setTextViewText(R.id.today_block1_title, "Nothing today")
                views.setTextViewText(R.id.today_block1_meta,
                    "Tap to open Prahar")
                views.setViewVisibility(R.id.today_now_badge, View.GONE)
                views.setViewVisibility(R.id.today_block2_row, View.GONE)
                views.setViewVisibility(R.id.today_progress_row, View.GONE)
            } else {
                views.setTextViewText(R.id.today_block1_title, title)
                views.setTextViewText(
                    R.id.today_block1_meta, "$subject  ·  $time")

                views.setViewVisibility(R.id.today_now_badge,
                    if (status == "now") View.VISIBLE else View.GONE)

                if (title2.isEmpty()) {
                    // Placeholder line rather than a jump — the widget's
                    // height is fixed, so hiding a row leaves whitespace we
                    // fill with an honest "nothing after" note.
                    views.setViewVisibility(R.id.today_block2_row, View.VISIBLE)
                    views.setTextViewText(
                        R.id.today_block2_title, "Nothing after")
                    views.setTextViewText(R.id.today_block2_meta, "")
                } else {
                    views.setViewVisibility(R.id.today_block2_row, View.VISIBLE)
                    views.setTextViewText(R.id.today_block2_title, title2)
                    views.setTextViewText(
                        R.id.today_block2_meta, "$subject2  ·  $time2")
                }

                views.setViewVisibility(R.id.today_progress_row, View.VISIBLE)
                views.setProgressBar(R.id.today_progress, 100, progress, false)
                views.setTextViewText(R.id.today_progress_text, progressText)
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
