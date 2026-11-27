package com.example.my_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home screen widget showing today's tasks.
 *
 * The Flutter app saves the text to show (see lib/services/home_widget_sync.dart);
 * this class only copies it into the layout. Tapping the widget opens the app.
 */
class TasksWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val lineIds =
        intArrayOf(
            R.id.widget_line0,
            R.id.widget_line1,
            R.id.widget_line2,
            R.id.widget_line3,
            R.id.widget_line4,
        )

    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.tasks_widget)

      views.setOnClickPendingIntent(
          R.id.widget_container,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
      )

      val title = widgetData.getString("title", null)
      if (title == null) {
        // The app hasn't saved anything yet.
        views.setTextViewText(R.id.widget_title, "Tasks")
        showText(views, R.id.widget_line0, "Open the app to see your tasks")
      } else {
        views.setTextViewText(R.id.widget_title, title)
        lineIds.forEachIndexed { index, id ->
          showText(views, id, widgetData.getString("line$index", null))
        }
      }
      showText(views, R.id.widget_now, widgetData.getString("now", null))
      showText(views, R.id.widget_footer, widgetData.getString("footer", null))

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  /** Shows [text] in the view, or hides the view when there is nothing to show. */
  private fun showText(views: RemoteViews, viewId: Int, text: String?) {
    if (text.isNullOrEmpty()) {
      views.setViewVisibility(viewId, View.GONE)
    } else {
      views.setTextViewText(viewId, text)
      views.setViewVisibility(viewId, View.VISIBLE)
    }
  }
}
