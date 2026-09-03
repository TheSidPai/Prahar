package com.siddhantpai.prahar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * The compact "next block" tile.
 *
 * Deliberately narrow: subject / title / one line of time. Widgets are read at
 * a glance and any layout richer than this fails on a stock 2x1 cell. Tapping
 * it opens the app.
 */
class NextBlockWidget : AppWidgetProvider() {

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

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_next_block)

            if (status == "none" || title.isEmpty()) {
                views.setTextViewText(R.id.widget_title, "No study today")
                views.setTextViewText(R.id.widget_subject, "")
                views.setTextViewText(R.id.widget_time, "Tap to open Prahar")
            } else {
                views.setTextViewText(R.id.widget_title, title)
                views.setTextViewText(R.id.widget_subject, subject)
                views.setTextViewText(R.id.widget_time,
                    if (status == "now") "Now  ·  $time" else time)
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
            views.setOnClickPendingIntent(R.id.widget_root, pending)

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
