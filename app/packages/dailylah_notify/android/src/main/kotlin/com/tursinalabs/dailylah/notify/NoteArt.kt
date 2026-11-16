package com.tursinalabs.dailylah.notify

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.ceil

/**
 * The small picture beside the pills, drawn like the landing page's (`.psi`, `.therm`,
 * `.bars` in web/index.html). Decorative: it never carries text, and the pills say the
 * same in words.
 */
internal object NoteArt {
    fun draw(ctx: Context, art: String, value: Double?, bars: List<Double>): Bitmap? {
        val d = ctx.resources.displayMetrics.density
        val v = (value ?: 0.0).coerceIn(0.0, 1.0).toFloat()
        return when (art) {
            "psi" -> psi(ctx, d, v)
            "heat" -> thermometer(ctx, d, v)
            "week" -> if (bars.size == 7) week(ctx, d, bars) else null
            "rain" -> rain(ctx, d)
            "phone" -> phone(ctx, d)
            else -> null
        }
    }

    private fun bitmap(w: Float, h: Float): Pair<Bitmap, Canvas> {
        val b = Bitmap.createBitmap(ceil(w).toInt(), ceil(h).toInt(), Bitmap.Config.ARGB_8888)
        return b to Canvas(b)
    }

    private fun fill(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        this.color = color
    }

    private fun stroke(color: Int, width: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = width
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
        this.color = color
    }

    /** A green, amber and red bar with a marker at [at] (PSI 0 to 300). */
    private fun psi(ctx: Context, d: Float, at: Float): Bitmap {
        val w = 96 * d
        val h = 22 * d
        val (b, c) = bitmap(w, h)
        val edge = 2 * d
        val bar = RectF(edge / 2, 5 * d, w - edge / 2, 17 * d)
        val r = 6 * d
        val clip = Path().apply { addRoundRect(bar, r, r, Path.Direction.CW) }
        c.save()
        c.clipPath(clip)
        val third = bar.width() / 3
        c.drawRect(bar.left, bar.top, bar.left + third, bar.bottom, fill(ctx.getColor(R.color.dl_note_good)))
        c.drawRect(bar.left + third, bar.top, bar.left + 2 * third, bar.bottom, fill(ctx.getColor(R.color.dl_note_amber)))
        c.drawRect(bar.left + 2 * third, bar.top, bar.right, bar.bottom, fill(ctx.getColor(R.color.dl_note_red)))
        c.restore()
        c.drawRoundRect(bar, r, r, stroke(ctx.getColor(R.color.dl_note_edge), edge))
        val x = (bar.left + bar.width() * at).coerceIn(3 * d, w - 3 * d)
        c.drawRoundRect(RectF(x - 3 * d, 0f, x + 3 * d, h), 3 * d, 3 * d, fill(ctx.getColor(R.color.dl_note_mark)))
        return b
    }

    /** A thermometer filled to [level]. */
    private fun thermometer(ctx: Context, d: Float, level: Float): Bitmap {
        val w = 14 * d
        val h = 34 * d
        val (b, c) = bitmap(w, h)
        val edge = 2 * d
        val tube = RectF(edge / 2, edge / 2, w - edge / 2, h - edge / 2)
        val r = 6 * d
        c.save()
        c.clipPath(Path().apply { addRoundRect(tube, r, r, Path.Direction.CW) })
        c.drawRect(tube, fill(ctx.getColor(R.color.dl_note_card)))
        val top = tube.bottom - tube.height() * (0.25f + 0.6f * level)
        c.drawRect(tube.left, top, tube.right, tube.bottom, fill(ctx.getColor(R.color.dl_note_red)))
        c.restore()
        c.drawRoundRect(tube, r, r, stroke(ctx.getColor(R.color.dl_note_edge), edge))
        return b
    }

    /** Seven bars, oldest day first; the last two (the weekend on a Sunday) in sky. */
    private fun week(ctx: Context, d: Float, bars: List<Double>): Bitmap {
        val barW = 9 * d
        val gap = 3 * d
        val h = 34 * d
        val w = 7 * barW + 6 * gap
        val (b, c) = bitmap(w, h)
        val edge = 1.5f * d
        val line = stroke(ctx.getColor(R.color.dl_note_edge), edge)
        bars.forEachIndexed { i, raw ->
            val v = raw.coerceIn(0.0, 1.0).toFloat()
            val left = i * (barW + gap) + edge / 2
            val top = (h - edge / 2) - (h - edge) * (0.12f + 0.88f * v)
            val rect = RectF(left, top, left + barW - edge, h - edge / 2)
            val color = if (i >= 5) R.color.dl_note_sky else R.color.dl_note_teal_fill
            c.drawRoundRect(rect, 2 * d, 2 * d, fill(ctx.getColor(color)))
            c.drawRoundRect(rect, 2 * d, 2 * d, line)
        }
        return b
    }

    /** Three falling drops. */
    private fun rain(ctx: Context, d: Float): Bitmap {
        val w = 26 * d
        val h = 26 * d
        val (b, c) = bitmap(w, h)
        val paint = fill(ctx.getColor(R.color.dl_note_teal_fill))
        val line = stroke(ctx.getColor(R.color.dl_note_edge), 1.5f * d)
        for ((cx, cy) in listOf(5f to 6f, 13f to 14f, 21f to 7f)) {
            val x = cx * d
            val y = cy * d
            val drop = Path().apply {
                moveTo(x, y - 5 * d)
                cubicTo(x + 5 * d, y + 1 * d, x + 3.5f * d, y + 6 * d, x, y + 6 * d)
                cubicTo(x - 3.5f * d, y + 6 * d, x - 5 * d, y + 1 * d, x, y - 5 * d)
                close()
            }
            c.drawPath(drop, paint)
            c.drawPath(drop, line)
        }
        return b
    }

    /** A phone with buzz marks on both sides. */
    private fun phone(ctx: Context, d: Float): Bitmap {
        val w = 28 * d
        val h = 30 * d
        val (b, c) = bitmap(w, h)
        val edge = 2 * d
        val line = stroke(ctx.getColor(R.color.dl_note_edge), edge)
        val body = RectF(8 * d, edge / 2, 20 * d, h - edge / 2)
        c.drawRoundRect(body, 3 * d, 3 * d, fill(ctx.getColor(R.color.dl_note_amber)))
        c.drawRoundRect(body, 3 * d, 3 * d, line)
        c.drawLine(12 * d, h - 5 * d, 16 * d, h - 5 * d, line)
        val mark = stroke(ctx.getColor(R.color.dl_note_mark), 1.5f * d)
        c.drawLine(3.5f * d, 10 * d, 3.5f * d, 20 * d, mark)
        c.drawLine(24.5f * d, 10 * d, 24.5f * d, 20 * d, mark)
        return b
    }
}
