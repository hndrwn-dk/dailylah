package com.tursinalabs.dailylah

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar
import java.util.Locale

/**
 * Home screen widget. The app and the background pass save string keys with
 * HomeWidget.saveWidgetData (`widgetData` in lib/logic.dart); this draws them.
 *
 * Resizing: Android 12+ gets one layout per size (the launcher picks the closest that fits,
 * also after a resize or when a foldable opens, without waking the app). Android 10/11
 * launchers (One UI 2/3 included) report the size in onAppWidgetOptionsChanged and we pick.
 */
open class DailyLahWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(
                id,
                DailyLahWidget.build(context, widgetData, appWidgetManager.getAppWidgetOptions(id)),
            )
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return // sized layouts handle it
        appWidgetManager.updateAppWidget(
            appWidgetId,
            DailyLahWidget.build(context, HomeWidgetPlugin.getData(context), newOptions),
        )
    }
}

/** The same widget on the Galaxy Z Flip cover screen (Flex Window); see the manifest. */
class DailyLahCoverWidgetProvider : DailyLahWidgetProvider()

internal object DailyLahWidget {
    /** A layout and the smallest size (dp) it is drawn at. One layout can serve several sizes. */
    private class Tier(val w: Float, val h: Float, val layout: Int)

    private val tiers = listOf(
        Tier(40f, 40f, R.layout.dl_widget_small), // 1x1, 2x1, 3x1 on narrow grids
        Tier(220f, 40f, R.layout.dl_widget_wide), // 4x1 and wider single rows
        Tier(150f, 140f, R.layout.dl_widget_medium), // 2x2
        Tier(220f, 140f, R.layout.dl_widget_medium), // short 3x2 / 4x2
        Tier(150f, 200f, R.layout.dl_widget_large), // 2x3
        Tier(220f, 170f, R.layout.dl_widget_large), // 4x2 (Samsung cells are tall)
        Tier(180f, 300f, R.layout.dl_widget_xl), // 3x3
        Tier(220f, 280f, R.layout.dl_widget_xl), // 4x3+, unfolded foldables, Flex Window
    )

    private const val STALE_MS = 2 * 60 * 60 * 1000L // two-hour forecast
    private const val BUS_GRACE_MS = 60 * 1000L

    fun build(context: Context, prefs: SharedPreferences, options: Bundle?): RemoteViews {
        val data = Data(prefs)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return RemoteViews(tiers.associate { t -> SizeF(t.w, t.h) to views(context, t.layout, data) })
        }
        val (w, h) = sizeOf(context, options)
        return views(context, pick(w, h).layout, data)
    }

    /** Same rule as Android 12+: of the tiers that fit, the one closest to the widget's size. */
    private fun pick(w: Float, h: Float): Tier {
        val fits = tiers.filter { it.w <= w + 0.5f && it.h <= h + 0.5f }
        if (fits.isEmpty()) return tiers.first()
        return fits.minBy { (w - it.w) * (w - it.w) + (h - it.h) * (h - it.h) }
    }

    /** Widget size in dp from launcher options: portrait uses min width x max height. */
    private fun sizeOf(context: Context, options: Bundle?): Pair<Float, Float> {
        val o = options ?: Bundle()
        val portrait = context.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
        val w = o.getInt(if (portrait) AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
        val h = o.getInt(if (portrait) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
        // No size reported yet: the default 4x2.
        if (w <= 0 || h <= 0) return 250f to 110f
        return w.toFloat() to h.toFloat()
    }

    private class Data(private val p: SharedPreferences) {
        private fun s(key: String) = p.getString(key, null)?.trim().orEmpty()
        val updated = s("dl_updated").toLongOrNull()
        val card = s("dl_card")
        val place = s("dl_place")
        val wx = s("dl_wx")
        val wxKind = s("dl_wx_kind")
        val wxNote = s("dl_wx_note")
        val mrt = s("dl_mrt")
        val mrtBad = s("dl_mrt_bad") == "1"
        val trip = s("dl_trip")
        val alert = s("dl_alert")
        val alertMore = s("dl_alert_more")
        private val busText = s("dl_bus")
        private val busAt = s("dl_bus_at").toLongOrNull()

        /** The bus to leave for, until its leave-by time has passed. */
        fun bus(now: Long) = if (busText.isNotEmpty() && busAt != null && now <= busAt + BUS_GRACE_MS) busText else ""

        fun alertLine() = if (alertMore.isEmpty()) alert else "$alert · $alertMore"
    }

    private fun clock(ms: Long): String {
        val c = Calendar.getInstance().apply { timeInMillis = ms }
        return String.format(Locale.ROOT, "%02d.%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
    }

    private fun weatherIcon(kind: String) = when (kind) {
        "thunder" -> R.drawable.dl_wx_thunder
        "rain" -> R.drawable.dl_wx_rain
        "haze" -> R.drawable.dl_wx_haze
        "wind" -> R.drawable.dl_wx_wind
        "cloud" -> R.drawable.dl_wx_cloud
        "partly_day" -> R.drawable.dl_wx_partly_day
        "partly_night" -> R.drawable.dl_wx_partly_night
        "moon" -> R.drawable.dl_wx_moon
        else -> R.drawable.dl_wx_sun
    }

    private fun launch(context: Context, target: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("dailylah://$target"))

    private fun RemoteViews.show(id: Int, visible: Boolean) =
        setViewVisibility(id, if (visible) View.VISIBLE else View.GONE)

    private fun RemoteViews.line(id: Int, icon: Int, text: Int, value: String, iconRes: Int, bgRes: Int) {
        show(id, value.isNotEmpty())
        setTextViewText(text, value)
        setImageViewResource(icon, iconRes)
        setInt(id, "setBackgroundResource", bgRes)
    }

    private fun views(context: Context, layout: Int, d: Data): RemoteViews {
        if (d.updated == null) {
            return RemoteViews(context.packageName, R.layout.dl_widget_empty).apply {
                setOnClickPendingIntent(android.R.id.background, launch(context, "today"))
            }
        }
        val now = System.currentTimeMillis()
        val stale = now - d.updated > STALE_MS
        val v = RemoteViews(context.packageName, layout)
        v.setOnClickPendingIntent(android.R.id.background, launch(context, "today"))

        // Header: "MORNING · TAMPINES" and the time of the data, or a nudge when it is old.
        val header = listOf(d.card, d.place).filter { it.isNotEmpty() }.joinToString(" · ")
        v.setTextViewText(R.id.w_header, if (stale) context.getString(R.string.widget_stale, clock(d.updated)) else header)
        v.setTextViewText(R.id.w_updated, clock(d.updated))
        v.show(R.id.w_updated, !stale)

        // Weather: amber panel (look now) when it is wet or rain is due on the way, sky when dry.
        val wet = d.wxKind == "rain" || d.wxKind == "thunder" || d.wxNote.isNotEmpty()
        v.setTextViewText(R.id.w_wx_text, d.wx.ifEmpty { context.getString(R.string.widget_loading) })
        v.setImageViewResource(R.id.w_wx_icon, weatherIcon(d.wxKind))
        v.setInt(R.id.w_wx_panel, "setBackgroundResource", if (wet) R.drawable.dl_w_panel_amber else R.drawable.dl_w_panel_sky)
        v.setTextViewText(R.id.w_wx_note, d.wxNote)
        v.show(R.id.w_wx_note, d.wxNote.isNotEmpty())

        // MRT: teal dot when normal; red dot on a red tint when a watched line is disrupted.
        v.show(R.id.w_mrt_row, d.mrt.isNotEmpty())
        v.setTextViewText(R.id.w_mrt_text, d.mrt)
        v.setImageViewResource(R.id.w_mrt_dot, if (d.mrtBad) R.drawable.dl_w_dot_bad else R.drawable.dl_w_dot_ok)
        v.setInt(R.id.w_mrt_row, "setBackgroundResource", if (d.mrtBad) R.drawable.dl_w_row_bad else R.drawable.dl_w_row_none)

        // One more line where there is room for one: the bus to leave for (go), else an alert
        // (look now), else rain on the way (when the layout has no weather note), else the trip.
        val bus = d.bus(now)
        val hasNote = layout == R.layout.dl_widget_large
        when {
            bus.isNotEmpty() -> v.line(R.id.w_line3_row, R.id.w_line3_icon, R.id.w_line3_text, bus,
                R.drawable.dl_ic_w_bus_go, R.drawable.dl_w_row_go)
            d.alert.isNotEmpty() -> v.line(R.id.w_line3_row, R.id.w_line3_icon, R.id.w_line3_text, d.alertLine(),
                R.drawable.dl_ic_w_alert_look, R.drawable.dl_w_row_look)
            d.wxNote.isNotEmpty() && !hasNote -> v.line(R.id.w_line3_row, R.id.w_line3_icon, R.id.w_line3_text, d.wxNote,
                R.drawable.dl_ic_w_rain_look, R.drawable.dl_w_row_look)
            else -> v.line(R.id.w_line3_row, R.id.w_line3_icon, R.id.w_line3_text, d.trip,
                R.drawable.dl_ic_w_clock_text, R.drawable.dl_w_row_none)
        }

        // Extra large: every line, plus buttons to Today, Nearby and Home.
        v.setTextViewText(R.id.w_trip_text, d.trip)
        v.show(R.id.w_trip_row, d.trip.isNotEmpty())
        v.setTextViewText(R.id.w_bus_text, bus)
        v.show(R.id.w_bus_row, bus.isNotEmpty())
        v.setTextViewText(R.id.w_alert_text, d.alert)
        v.setTextViewText(R.id.w_alert_more, d.alertMore)
        v.show(R.id.w_alert_more, d.alertMore.isNotEmpty())
        v.show(R.id.w_alert_row, d.alert.isNotEmpty())
        v.setOnClickPendingIntent(R.id.w_btn_today, launch(context, "today"))
        v.setOnClickPendingIntent(R.id.w_btn_nearby, launch(context, "nearby"))
        v.setOnClickPendingIntent(R.id.w_btn_home, launch(context, "home"))
        return v
    }
}
