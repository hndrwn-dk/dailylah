package com.tursinalabs.dailylah.notify

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews

/** Builds and posts one alert from the map the app sends (`RichNote.toMap()` in Dart). */
internal object NotePoster {
    /** The channel flutter_local_notifications already uses for every alert. */
    private const val CHANNEL = "dailylah_alerts"

    /** home_widget's launch action: the app reads the link like a tap on the widget. */
    private const val LAUNCH = "es.antonborri.home_widget.action.LAUNCH"

    /** Pill slots of dl_note.xml, row by row. */
    private val rows = listOf(
        R.id.dl_note_row_1 to listOf(R.id.dl_note_pill_1a, R.id.dl_note_pill_1b, R.id.dl_note_pill_1c),
        R.id.dl_note_row_2 to listOf(R.id.dl_note_pill_2a, R.id.dl_note_pill_2b),
        R.id.dl_note_row_3 to listOf(R.id.dl_note_pill_3a),
    )

    /** Characters of pill text a row takes at 100% text on a narrow shade. */
    private const val ROW_CHARS = 30

    /** What the picture and a pill's padding take from that, in characters. */
    private const val ART_CHARS = 6
    private const val PILL_CHARS = 3

    private class Pill(val text: String, val tone: String, val lineColor: Int?)

    fun post(ctx: Context, note: Map<String, Any?>, channelName: String, channelDescription: String): Boolean {
        val manager = ctx.getSystemService(NotificationManager::class.java) ?: return false
        if (!manager.areNotificationsEnabled()) return false
        val id = (note["id"] as? Number)?.toInt() ?: return false
        val title = note["title"] as? String ?: return false
        val body = note["body"] as? String ?: ""
        if (manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, channelName, NotificationManager.IMPORTANCE_HIGH).apply {
                    description = channelDescription
                },
            )
        }
        val pills = (note["pills"] as? List<*>).orEmpty().mapNotNull { raw ->
            val m = raw as? Map<*, *> ?: return@mapNotNull null
            val text = (m["text"] as? String)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            Pill(text, m["tone"] as? String ?: "sky", (m["lineColor"] as? Number)?.toInt())
        }.take(3)
        val art = NoteArt.draw(
            ctx,
            note["art"] as? String ?: "none",
            (note["artValue"] as? Number)?.toDouble(),
            (note["bars"] as? List<*>).orEmpty().mapNotNull { (it as? Number)?.toDouble() },
        )

        val large = ctx.resources.configuration.fontScale >= 1.3f

        // The shade cuts a custom view from the bottom, where the pills are. So the text gives
        // way to them: two body lines fewer for each row of pills, and two fewer at large text.
        // A note with no pills keeps 9 lines (7 at large text), so a long digest is not cut
        // short; one row leaves 7, two 5, three 3, never under 2. The pop-up is short: title,
        // one line of text and the first row only.
        fun views(headsUp: Boolean) = RemoteViews(ctx.packageName, R.layout.dl_note).apply {
            setTextViewText(R.id.dl_note_title, title)
            setTextViewText(R.id.dl_note_body, body)
            setViewVisibility(R.id.dl_note_body, if (body.isEmpty()) View.GONE else View.VISIBLE)
            if (art != null) {
                setImageViewBitmap(R.id.dl_note_art, art)
                setViewVisibility(R.id.dl_note_art, View.VISIBLE)
            }
            val used = fill(ctx, this, pills, art != null)
            if (headsUp) {
                setInt(R.id.dl_note_title, "setMaxLines", 1)
                setInt(R.id.dl_note_body, "setMaxLines", 1)
                setViewVisibility(R.id.dl_note_row_2, View.GONE)
                setViewVisibility(R.id.dl_note_row_3, View.GONE)
            } else {
                val lines = (if (large) 7 else 9) - 2 * used
                setInt(R.id.dl_note_body, "setMaxLines", lines.coerceAtLeast(2))
            }
        }

        val builder = Notification.Builder(ctx, CHANNEL)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomBigContentView(views(headsUp = false))
            .setCustomHeadsUpContentView(views(headsUp = true))
            .setAutoCancel(true)
            .setShowWhen(true)
        launch(ctx, id, note["link"] as? String)?.let { builder.setContentIntent(it) }
        manager.notify(id, builder.build())
        return true
    }

    /**
     * Puts the pills in the slots row by row. A pill that would not fit beside the ones
     * before it starts the next row, by a character budget that shrinks with larger text,
     * so nothing has to be measured (RemoteViews cannot) and no pill is cut in the usual case.
     * Returns how many rows it used.
     */
    private fun fill(ctx: Context, v: RemoteViews, pills: List<Pill>, hasArt: Boolean): Int {
        val budget = (ROW_CHARS / ctx.resources.configuration.fontScale.coerceAtLeast(0.85f)).toInt()
        var row = 0
        var slot = 0
        var used = if (hasArt) ART_CHARS else 0
        if (hasArt) v.setViewVisibility(rows[0].first, View.VISIBLE)
        for (p in pills) {
            val need = p.text.length + PILL_CHARS
            val full = slot >= rows[row].second.size || (slot > 0 && used + need > budget)
            if (full && row < rows.lastIndex) {
                row++
                slot = 0
                used = 0
            }
            if (slot >= rows[row].second.size) break
            val id = rows[row].second[slot]
            v.setViewVisibility(rows[row].first, View.VISIBLE)
            v.setViewVisibility(id, View.VISIBLE)
            v.setTextViewText(id, p.text)
            v.setInt(id, "setBackgroundResource", background(p))
            v.setTextColor(id, ctx.getColor(textColor(p.tone)))
            slot++
            used += need
        }
        return if (pills.isEmpty() && !hasArt) 0 else row + 1
    }

    private fun background(p: Pill): Int = when (p.tone) {
        "amber" -> R.drawable.dl_note_pill_amber
        "red" -> R.drawable.dl_note_pill_red
        "teal" -> R.drawable.dl_note_pill_teal
        "mint" -> R.drawable.dl_note_pill_mint
        "board" -> R.drawable.dl_note_pill_board
        "line" -> when (p.lineColor) {
            0xD42E12 -> R.drawable.dl_note_pill_nsl
            0x009645 -> R.drawable.dl_note_pill_ewl
            0xFA9E0D -> R.drawable.dl_note_pill_ccl
            0x005EC4 -> R.drawable.dl_note_pill_dtl
            0x9900AA -> R.drawable.dl_note_pill_nel
            0x9D5B25 -> R.drawable.dl_note_pill_tel
            0x748477 -> R.drawable.dl_note_pill_lrt
            else -> R.drawable.dl_note_pill_board
        }
        else -> R.drawable.dl_note_pill_sky
    }

    private fun textColor(tone: String): Int = when (tone) {
        "red", "teal", "line" -> R.color.dl_note_white
        "board" -> R.color.dl_note_led
        else -> R.color.dl_note_ink
    }

    /** Opens the app; with a `dailylah://` link, on that tab (read like a widget tap). */
    private fun launch(ctx: Context, id: Int, link: String?): PendingIntent? {
        val intent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: return null
        if (link != null) {
            intent.action = LAUNCH
            intent.data = Uri.parse(link)
            intent.removeCategory(Intent.CATEGORY_LAUNCHER)
        }
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        return PendingIntent.getActivity(
            ctx,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
