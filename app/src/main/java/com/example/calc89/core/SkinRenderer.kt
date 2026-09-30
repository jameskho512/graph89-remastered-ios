/*
 * Graph89 Remastered - TI graphing calculator emulator for Android
 * Copyright (C) 2026 JH
 * Based on Graph89, Copyright (C) 2012-2013 Dritan Hashorva (modified and rewritten in Kotlin, 2026).
 *
 * This program is free software: you can redistribute it and/or modify it under the terms of the
 * GNU General Public License as published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version. This program is distributed in the hope that it
 * will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License (LICENSE) for more details.
 */
package com.example.calc89.core

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.atan
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Draws a skin on the phone at the exact size of the keypad area, so it is never stretched and always sharp.
 * The keypad layout from assets/skin/<layout>.json is widened or narrowed to the area's shape (keys spread and
 * lengthen, circles stay round, tilts follow the flatter row curve), then drawn in design units (1014 high)
 * scaled to the area.
 * The touch mask is rasterised from the same key shapes. Skin.kt falls back to the bundled images if this fails.
 */
object SkinRenderer {
    /** A drawn skin: where its design canvas landed in the output, and the touch mask (one cell per design unit). */
    class Result(val keypad: Rect, val mask: ByteArray, val maskWidth: Int, val maskHeight: Int, val backgroundColor: Int)

    private const val H = 1014f
    private const val OVERHANG = 10f  // touch area around each key, design units
    private const val NO_KEY = 255

    // ---- layout data ----

    private class Key(
        val name: String, val kind: String, var cx: Float, val cy: Float, var w: Float, val h: Float, var ang: Float,
        val r: FloatArray, val wedge: Boolean, val mirror: Boolean, val rCorner: Float, val rFillet: Float, val sag: Float,
        val code: Int, val codeDown: Int, var legend: Array<String?>,
    ) {
        var lx = 0f
        var ly = 0f
    }

    private class Layout(val name: String, val baseW: Float, val axis: Float, val keys: List<Key>, val legends83: Map<String, Array<String?>>) {
        val ti84 get() = name == "ti84"
        fun key(n: String) = keys.first { it.name == n }
    }

    private fun loadLayout(context: Context, name: String): Layout {
        val j = JSONObject(context.assets.open("skin/$name.json").bufferedReader(Charsets.UTF_8).use { it.readText() })
        fun legend(a: org.json.JSONArray) = Array(4) { if (a.isNull(it)) null else a.getString(it) }
        val keys = ArrayList<Key>()
        val arr = j.getJSONArray("keys")
        for (i in 0 until arr.length()) {
            val k = arr.getJSONObject(i)
            val r = k.getJSONArray("r")
            keys.add(
                Key(
                    k.getString("name"), k.getString("kind"), k.getDouble("cx").toFloat(), k.getDouble("cy").toFloat(),
                    k.getDouble("w").toFloat(), k.getDouble("h").toFloat(), k.getDouble("ang").toFloat(),
                    FloatArray(4) { r.getDouble(it).toFloat() }, k.optString("shape") == "wedge", k.optBoolean("mirror"),
                    k.optDouble("r_corner", 0.0).toFloat(), k.optDouble("r_fillet", 0.0).toFloat(), k.optDouble("sag", 0.0).toFloat(),
                    k.getInt("code"), k.optInt("codeDown", -1), legend(k.getJSONArray("legend")),
                ),
            )
        }
        val l83 = HashMap<String, Array<String?>>()
        j.optJSONObject("legends83")?.let { o -> o.keys().forEach { l83[it] = legend(o.getJSONArray(it)) } }
        return Layout(j.getString("layout"), j.getDouble("W").toFloat(), j.getDouble("axis").toFloat(), keys, l83)
    }

    // ---- themes ----

    private class Theme(
        val bg0: Int, val bg1: Int, val case: Int, val floor0: Int, val floor1: Int, val fills: Map<String, Int>,
        val blue: Int, val green: Int, val alpha: Int, val onLight: Int, val onDark: Int, val purple: Int, val ink: Int,
        val blackRim: Int, val shiftRing: Int, val outline: Int? = null, val outlineW: Float = 0f, val labelLift: Float = 0f,
        val shadow: Float = 0.6f, val halo: Int? = null, val haloW: Float = 1.6f, val haloOp: Float = 0.7f,
        val palette: Palette? = null,
    )

    private enum class Finish { FLAT, NEON, OUTLINE }

    /**
     * A 7-colour skin: 2nd, ◆ and alpha (key and function text), number keys, other keys, recesses and
     * default text; [body] is usually one of them. NEON draws dark keys with glowing
     * outlines and legends in their role colour; OUTLINE (OLED) the same without the glow.
     */
    private class Palette(
        val c2nd: Int, val dia: Int, val alpha: Int, val num: Int, val keys: Int, val recess: Int, val text: Int,
        val body: Int, val finish: Finish = Finish.FLAT,
        /** OUTLINE: outline of the keys other than 2nd / ◆ / alpha, and the APPS legend colour. */
        val line: Int = 0, val apps: Int = 0,
    ) {
        val all get() = listOf(c2nd, dia, alpha, num, keys, recess, text)
    }

    private fun paletteTheme(p: Palette) = Theme(
        p.body, p.body, p.recess, p.recess, p.recess, emptyMap(),
        p.c2nd, p.dia, p.alpha, p.text, p.text, p.text, p.text, p.text, p.text,
        outline = if (p.finish == Finish.NEON || p.finish == Finish.OUTLINE) null else p.recess, outlineW = 1.6f, labelLift = 1f, shadow = 0.45f, palette = p,
    )

    private fun pal(
        c2nd: String, dia: String, alpha: String, num: String, keys: String, recess: String, text: String, body: String,
        finish: Finish = Finish.FLAT,
    ): Palette {
        // body: the role whose colour the face reuses, or a colour of its own
        val cs = mapOf("num" to num, "keys" to keys, "recess" to recess)
        return Palette(c(c2nd), c(dia), c(alpha), c(num), c(keys), c(recess), c(text), c(cs[body] ?: body), finish)
    }

    /**
     * OLED: pure black face and keys drawn as outlines (no glow), 2nd / ◆ / alpha outlined in their colours, the
     * other keys in Classic's key grey; all text keeps Classic's colours (APPS purple).
     */
    private val OLED = Palette(
        c("#A4D3F6"), c("#CDE6A2"), c("#EEF1F4"), c("#000000"), c("#000000"), c("#0A0A0B"), c("#F4F5F7"),
        c("#000000"), Finish.OUTLINE, line = c("#6A6D73"), apps = c("#C79BEA"),
    )

    private val PALETTES = mapOf(
        SkinType.OLED to OLED,
        SkinType.NEON_GRID to pal("#00E5FF", "#FF9E1B", "#F2FDFF", "#0A2530", "#000000", "#07141B", "#7FEFFF", "keys", Finish.NEON),
        SkinType.EMBER to pal("#FF6B2C", "#FFC857", "#8FD3FF", "#3A3A40", "#222226", "#121214", "#EDEAE4", "num"),
        SkinType.FROST to pal("#3B82C4", "#2BA88F", "#8A5CC2", "#FFFFFF", "#2A4A66", "#B7CAD8", "#13202B", "num"),
        SkinType.SOLAR to pal("#268BD2", "#859900", "#D33682", "#073642", "#586E75", "#002B36", "#EEE8D5", "num"),
        SkinType.RETRO to pal("#E07A2E", "#3F8F5A", "#C23B3B", "#5B4636", "#2F2A26", "#D9CDB5", "#3A2E25", "recess"),
        SkinType.EMERALD to pal("#7CC6A4", "#E8C468", "#E58F65", "#2E5641", "#1B3325", "#0E1F16", "#EDE6D3", "num"),
        SkinType.BLOSSOM to pal("#D94F7E", "#3E9A88", "#7B63B8", "#FFFFFF", "#5B4453", "#F2D5DE", "#3D2632", "recess"),
        SkinType.NORD to pal("#88C0D0", "#A3BE8C", "#B48EAD", "#4C566A", "#3B4252", "#2E3440", "#ECEFF4", "recess"),
        SkinType.RADIOACTIVE to pal("#39FF14", "#C6FF5A", "#E6FFE0", "#0C230C", "#050C05", "#000000", "#8CFF8C", "keys", Finish.NEON),
        SkinType.ROYAL to pal("#E3B341", "#4FB3A9", "#D9D9E3", "#262D66", "#161A3D", "#0B0E24", "#E8E6F2", "recess"),
    )

    /** Colour [a] moved a fraction [t] towards [b]. */
    private fun mix(a: Int, b: Int, t: Float): Int = Color.rgb(
        (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt(),
    )

    private fun luminance(c: Int): Double {
        fun ch(v: Int) = (v / 255.0).let { if (it <= 0.03928) it / 12.92 else Math.pow((it + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(Color.red(c)) + 0.7152 * ch(Color.green(c)) + 0.0722 * ch(Color.blue(c))
    }

    private fun contrast(a: Int, b: Int): Double {
        val la = luminance(a); val lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private fun c(hex: String) = Color.parseColor(hex)

    private val MIDNIGHT = Theme(
        c("#2a272c"), c("#141217"), c("#060507"), c("#070608"), c("#110f13"),
        mapOf("fkey" to c("#3b393f"), "gray" to c("#3b393f"), "black" to c("#1d1b20"), "dpad" to c("#1d1b20"),
            "2nd" to c("#a9dcf7"), "diamond" to c("#bfe89a"), "alpha" to c("#f7f7f5")),
        c("#a9dcf7"), c("#bfe89a"), c("#f7f7f5"), c("#141217"), c("#f2efeb"), c("#c89be3"), c("#f2efeb"),
        c("#85848a"), c("#f7f7f5"),
    )

    /** Classic: the look of the TI-89 Titanium and the TI-83/84 family. */
    private val CLASSIC = Theme(
        c("#807D7F"), c("#807D7F"), c("#141518"), c("#2a2b2f"), c("#36373b"),
        mapOf("fkey" to c("#6a6d73"), "gray" to c("#6a6d73"), "black" to c("#1e1d21"), "dpad" to c("#1e1d21"),
            "2nd" to c("#a4d3f6"), "diamond" to c("#cde6a2"), "alpha" to c("#eef1f4")),
        c("#a4d3f6"), c("#cde6a2"), c("#eef1f4"), c("#15212c"), c("#ffffff"), c("#c79bea"), c("#f4f5f7"),
        c("#9a9ca2"), c("#ffffff"), outline = c("#1b1c1f"), outlineW = 1.6f, labelLift = 1f, shadow = 0.45f,
        halo = c("#26272b"), haloW = 2f, haloOp = 0.9f,
    )

    /** The original TI-89: navy face, yellow 2ND, teal ◆, purple ALPHA, blue F-keys and cursor pad. */
    private val TI89 = Theme(
        c("#2d3056"), c("#222544"), c("#0d0e18"), c("#141630"), c("#1b1d38"),
        mapOf("fkey" to c("#5d6bd6"), "gray" to c("#1b1b24"), "black" to c("#8c90c4"), "dpad" to c("#5d6bd6"),
            "2nd" to c("#f0cf2e"), "diamond" to c("#2fb5a6"), "alpha" to c("#7a3f9e")),
        c("#f3dc6a"), c("#46cbbb"), c("#c59cf0"), c("#15151f"), c("#ffffff"), c("#ffffff"), c("#f2f2fa"),
        c("#5d6bd6"), c("#ffffff"), outline = c("#0d0e18"), outlineW = 1.6f, labelLift = 1f, shadow = 0.45f,
    )

    /** Grayscale skin: white face, black keys, black function text; ◆ functions in grey to tell them apart. */
    private val MONO = Theme(
        c("#f7f7f7"), c("#e4e4e4"), c("#0c0c0c"), c("#c9c9c9"), c("#dadada"),
        mapOf("fkey" to c("#1a1a1a"), "gray" to c("#1a1a1a"), "black" to c("#000000"), "dpad" to c("#000000"),
            "2nd" to c("#ffffff"), "diamond" to c("#ffffff"), "alpha" to c("#ffffff")),
        c("#111111"), c("#6b6b6b"), c("#111111"), c("#000000"), c("#ffffff"), c("#ffffff"), c("#ffffff"),
        c("#5a5a5a"), c("#ffffff"), outline = c("#000000"), outlineW = 1.6f, labelLift = 1f, shadow = 0.3f,
    )

    /** OLED with its text and outlines dimmed to [contrast] percent (toward black). */
    private fun oled(contrast: Int): Palette {
        val f = contrast.coerceIn(0, 100) / 100f
        val d = { c: Int -> mix(Color.BLACK, c, f) }
        val p = OLED
        return Palette(d(p.c2nd), d(p.dia), d(p.alpha), p.num, p.keys, p.recess, d(p.text), p.body, p.finish,
            line = d(p.line), apps = d(p.apps))
    }

    private fun themeFor(model: CalcModel, type: SkinType, oledContrast: Int) = when {
        type == SkinType.OLED -> paletteTheme(oled(oledContrast))
        type in PALETTES -> paletteTheme(PALETTES.getValue(type))
        type == SkinType.MONO -> MONO
        type == SkinType.MIDNIGHT -> MIDNIGHT
        model == CalcModel.TI89 -> TI89
        else -> CLASSIC
    }

    // ---- entry point ----

    /**
     * Roboto Medium, with Noto Sans Symbols for the legend symbols Roboto lacks (arrows, ◆, ▸, ∠, ⇄), so they look
     * the same on every phone. Android 9 and older use the phone's own fallback font.
     */
    private fun skinTypeface(context: Context): Typeface {
        val roboto = Typeface.createFromAsset(context.assets, "fonts/Roboto-Medium.ttf")
        if (android.os.Build.VERSION.SDK_INT < 29) return roboto
        return try {
            fun family(path: String) = android.graphics.fonts.FontFamily.Builder(
                android.graphics.fonts.Font.Builder(context.assets, path).build(),
            ).build()
            Typeface.CustomFallbackBuilder(family("fonts/Roboto-Medium.ttf"))
                .addCustomFallback(family("fonts/NotoSansSymbols-Regular-Subsetted.ttf"))
                .build()
        } catch (e: Exception) {
            roboto
        }
    }

    private var typeface: Typeface? = null

    /**
     * Draws the skin of [model] into [canvas] inside [area] (the keypad part of the view) and returns the
     * placement of the design canvas and the touch mask. Throws on any failure (the caller falls back).
     */
    /** Number of skins drawn so far (tests use it to check the caches). */
    @Volatile var renders = 0
        private set

    fun render(context: Context, model: CalcModel, type: SkinType, canvas: Canvas, area: Rect, oledContrast: Int = 70, threeD: Boolean = false): Result {
        renders++
        val layout = loadLayout(context, if (model.engine == Engine.TILEM) "ti84" else "ti89")
        if (model == CalcModel.TI83) layout.keys.forEach { k -> layout.legends83[k.name]?.let { k.legend = it } }
        val tf = typeface ?: skinTypeface(context).also { typeface = it }
        val theme = themeFor(model, type, oledContrast)

        // design width for this area's shape, within what the layout can take without cramping or gaps
        val aspect = area.width().toFloat() / area.height()
        val minW = layout.baseW * (if (layout.ti84) 0.82f else 0.9f)
        val maxW = layout.baseW * (if (layout.ti84) 1.35f else 1.45f)
        val w2 = (aspect * H).coerceIn(minW, maxW)
        val scale = min(area.width() / w2, area.height() / H)
        val left = area.left + (area.width() - w2 * scale) / 2f
        val top = area.bottom - H * scale // keypad at the bottom; any space above belongs to the body

        val d = Drawer(layout, theme, tf, model, w2, scale, threeD)

        canvas.save()
        canvas.clipRect(area)
        canvas.drawColor(theme.bg0)
        // extra space above the design canvas (very tall areas): the body continues up
        if (top > area.top) {
            val fill = Paint().apply { color = theme.bg0 }
            canvas.drawRect(left, area.top.toFloat(), left + w2 * scale, top + 1, fill)
        }
        canvas.translate(left, top)
        canvas.scale(scale, scale)
        d.draw(canvas)
        canvas.restore()

        val mw = ceil(w2).toInt()
        val mask = d.mask(mw, H.toInt())
        return Result(Rect(left.toInt(), top.toInt(), (left + w2 * scale).toInt(), area.bottom), mask, mw, H.toInt(), theme.bg0)
    }

    // ---- drawing ----

    private class Drawer(val base: Layout, val t: Theme, val tf: Typeface, val model: CalcModel, val w2: Float, val scale: Float, val threeD: Boolean) {
        val keys: List<Key>
        val axis = w2 / 2f
        val sx = w2 / 635f
        val fk: List<Key>
        val decorDx: Float
        private val cap: Float
        private val sizes: Map<String, Float>

        init {
            // type sizes come from the base layout, so text keeps its size when widened
            val p = Paint().apply { typeface = tf; textSize = 1000f }
            val b = Rect()
            p.getTextBounds("H", 0, 1, b)
            cap = -b.top / 1000f
            val ref = if (base.ti84) Triple("MATH", "MATH", "YEQU") else Triple("HOME", "CATALOG", "F1")
            val pillH = base.key(ref.first).h
            val numH = base.key("8").h
            val fD = base.key(ref.third).w
            val word = 0.30f * pillH / cap
            val catalog = 0.8f * base.key(ref.second).w / (p.measureText("CATALOG") / 1000f)
            sizes = mapOf(
                "digit" to 0.40f * numH / cap, "fkey" to 0.27f * fD / cap, "key" to (word + catalog) / 2f,
                "label" to 0.20f * pillH / cap + 4f / 3f,
            )

            // widen: spread the keys from the axis, lengthen the pills, move the cursor pad as one piece
            val f = w2 / base.baseW
            val kw = 1f + 0.557f * (f - 1f)
            val spread = { x: Float -> axis + (x - base.axis) * f }
            val sub = base.keys.firstOrNull { it.name == "SUB" }
            val oldEdge = sub?.let { it.cx + it.w / 2 } ?: 0f
            val up = base.key("UP")
            val padDx = spread(up.cx) - up.cx
            keys = base.keys.map { k ->
                Key(k.name, k.kind, k.cx, k.cy, k.w, k.h, k.ang, k.r, k.wedge, k.mirror, k.rCorner, k.rFillet, k.sag, k.code, k.codeDown, k.legend).apply {
                    if (kind == "dpad") {
                        cx += padDx
                    } else {
                        cx = spread(cx)
                        if (kind != "fkey") w *= kw
                        ang = Math.toDegrees(atan(tan(Math.toRadians(ang.toDouble())) / f)).toFloat()
                    }
                    if (wedge) wedgeCentre(this)
                }
            }
            fk = if (base.ti84) emptyList() else keys.filter { it.name in setOf("F1", "F2", "F3", "F4", "F5") }
            // the contrast bracket (drawn in 635-wide base coordinates) follows the right column
            decorDx = keys.firstOrNull { it.name == "SUB" }?.let { it.cx + it.w / 2 - oldEdge } ?: 0f
        }

        fun k(n: String) = keys.first { it.name == n }

        fun draw(cv: Canvas) {
            // the face fills the whole keypad area (no curved bottom corners)
            val body = Path().apply { addRect(0f, 0f, w2, H, Path.Direction.CW) }
            cv.save()
            cv.clipPath(body)
            // body: radial gradient centred at (.5, .25) of the canvas, radius .9 of each side
            val g = RadialGradient(0f, 0f, 1f, t.bg0, t.bg1, Shader.TileMode.CLAMP)
            g.setLocalMatrix(Matrix().apply { setScale(0.9f * w2, 0.9f * H); postTranslate(w2 / 2f, H / 4f) })
            cv.drawRect(0f, 0f, w2, H, Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = g })

            if (fk.isNotEmpty()) recess(cv, frecess())
            recess(cv, drecess())
            keys.forEach { key(cv, it) }
            over(cv)
            keys.forEach { legend(cv, it) }
            if (!base.ti84) decor(cv)
            cv.restore()
        }

        val pal = t.palette

        private val numpad = setOf("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "DOT", "NEG", "DECPNT", "CHS")

        /** The key's palette role colour: 2nd, ◆, alpha, number keys or other keys. */
        private fun roleColor(p: Palette, k: Key) = when {
            k.kind == "2nd" -> p.c2nd
            k.kind == "diamond" -> p.dia
            k.kind == "alpha" -> p.alpha
            k.name in numpad -> p.num
            else -> p.keys
        }

        private fun fillOf(k: Key): Int {
            val p = pal ?: return t.fills[k.kind] ?: t.fills.getValue("alpha") // "white" (TI-84 number keys) = the ALPHA key colour
            if (p.finish == Finish.NEON) return if (k.name in numpad) p.num else p.keys
            if (p.finish == Finish.OUTLINE) return p.keys
            return roleColor(p, k)
        }

        /** Neon outline colour: 2nd / ◆ / alpha in their colour, number keys in the 2nd colour, the rest in text colour. */
        private fun outlineOf(p: Palette, k: Key) = when {
            k.kind == "2nd" || k.kind == "diamond" || k.kind == "alpha" -> roleColor(p, k)
            p.finish == Finish.OUTLINE -> p.line
            k.name in numpad -> p.c2nd
            else -> p.text
        }

        // ---- shapes ----

        /** Key outline in the key's own (unrotated) frame; [off] > 0 grows it. */
        fun kpath(k: Key, off: Float = 0f): Path {
            val w = k.w / 2 + off
            val h = k.h / 2 + off
            val x0 = k.cx - w; val x1 = k.cx + w; val y0 = k.cy - h; val y1 = k.cy + h
            if (k.name == "UP") return hourglass(k, off, x0, x1, y0, y1)
            if (k.wedge) return wedge(k, x0, x1, y0, y1)
            val rr = FloatArray(4) { max(0f, min(k.r[it] + off, min(w, h))) }  // tl tr br bl
            return Path().apply {
                addRoundRect(RectF(x0, y0, x1, y1), floatArrayOf(rr[0], rr[0], rr[1], rr[1], rr[2], rr[2], rr[3], rr[3]), Path.Direction.CW)
            }
        }

        private fun hourglass(k: Key, off: Float, x0: Float, x1: Float, y0: Float, y1: Float): Path {
            val w = k.w / 2 + off
            val r = w
            val wr = 0.6f * (w - off) + off
            val cx = k.cx; val cy = k.cy
            val ya = y0 + r; val yb = y1 - r
            val k1 = (cy - ya) * 0.5f; val k2 = (cy - ya) * 0.45f
            return Path().apply {
                moveTo(x0, ya)
                arcTo(RectF(cx - r, ya - r, cx + r, ya + r), 180f, 180f)
                cubicTo(x1, ya + k1, cx + wr, cy - k2, cx + wr, cy)
                cubicTo(cx + wr, cy + k2, x1, yb - k1, x1, yb)
                arcTo(RectF(cx - r, yb - r, cx + r, yb + r), 0f, 180f)
                cubicTo(x0, yb - k1, cx - wr, cy + k2, cx - wr, cy)
                cubicTo(cx - wr, cy - k2, x0, ya + k1, x0, ya)
                close()
            }
        }

        private class WedgeParts(val c: FloatArray, val R: Float, val fx: Float, val fy: Float, val t1: FloatArray, val t2: FloatArray)

        private fun wedgeParts(k: Key, x0: Float, x1: Float, y0: Float, y1: Float): WedgeParts {
            val rf = k.rFillet
            val ww = x1 - x0; val hh = y1 - y0; val l = hypot(ww, hh)
            val mx = (x0 + x1) / 2; val my = (y0 + y1) / 2
            val nx = hh / l; val ny = ww / l
            val s = k.sag * l
            val r = (l * l / 4 + s * s) / (2 * s)
            val c = floatArrayOf(mx - nx * (r - s), my - ny * (r - s))
            val fx = c[0] + sqrt((r - rf) * (r - rf) - (y0 + rf - c[1]) * (y0 + rf - c[1]))
            val fy = c[1] + sqrt((r - rf) * (r - rf) - (x0 + rf - c[0]) * (x0 + rf - c[0]))
            val onArc = { px: Float, py: Float -> floatArrayOf(c[0] + (px - c[0]) * r / (r - rf), c[1] + (py - c[1]) * r / (r - rf)) }
            return WedgeParts(c, r, fx, fy, onArc(fx, y0 + rf), onArc(x0 + rf, fy))
        }

        /** ENTER-shaped wedge (ON is its mirror image): straight top and left, a rounded diagonal bottom-right. */
        private fun wedge(k: Key, x0: Float, x1: Float, y0: Float, y1: Float): Path {
            val p = wedgeParts(k, x0, x1, y0, y1)
            val rt = k.rCorner; val rf = k.rFillet
            val path = Path().apply {
                moveTo(x0, y0 + rt)
                arc(this, x0 + rt, y0 + rt, rt, x0, y0 + rt, x0 + rt, y0, true)
                lineTo(p.fx, y0)
                arc(this, p.fx, y0 + rf, rf, p.fx, y0, p.t1[0], p.t1[1], true)
                arc(this, p.c[0], p.c[1], p.R, p.t1[0], p.t1[1], p.t2[0], p.t2[1], true)
                arc(this, x0 + rf, p.fy, rf, p.t2[0], p.t2[1], x0, p.fy, true)
                close()
            }
            if (k.mirror) path.transform(Matrix().apply { setScale(-1f, 1f, k.cx, k.cy) })
            return path
        }

        /** Legend offset for a wedge key: its area centroid. */
        private fun wedgeCentre(k: Key) {
            val x0 = k.cx - k.w / 2; val x1 = k.cx + k.w / 2; val y0 = k.cy - k.h / 2; val y1 = k.cy + k.h / 2
            val p = wedgeParts(k, x0, x1, y0, y1)
            var sxs = 0.0; var sys = 0.0; var n = 0
            var y = y0
            while (y < y1) {
                var x = x0
                while (x < x1) {
                    if ((x - p.c[0]) * (x - p.c[0]) + (y - p.c[1]) * (y - p.c[1]) <= p.R * p.R) { sxs += x; sys += y; n++ }
                    x += 0.5f
                }
                y += 0.5f
            }
            if (n == 0) return
            val dx = (sxs / n).toFloat() - k.cx
            k.lx = if (k.mirror) -dx else dx
            k.ly = (sys / n).toFloat() - k.cy
        }

        /** Circular arc around (cx, cy) from one point to another, clockwise (y down) or counter-clockwise. */
        private fun arc(p: Path, cx: Float, cy: Float, r: Float, fx: Float, fy: Float, tx: Float, ty: Float, clockwise: Boolean) {
            val a0 = Math.toDegrees(atan2((fy - cy).toDouble(), (fx - cx).toDouble())).toFloat()
            val a1 = Math.toDegrees(atan2((ty - cy).toDouble(), (tx - cx).toDouble())).toFloat()
            var sweep = ((a1 - a0) % 360f + 360f) % 360f
            if (!clockwise) sweep -= 360f
            if (abs(sweep) < 1e-3f || abs(sweep) > 359.999f) { p.lineTo(tx, ty); return }
            p.arcTo(RectF(cx - r, cy - r, cx + r, cy + r), a0, sweep)
        }

        /** Smooth outline around a loop of circles, visited clockwise, with concave fillets between them. */
        private fun blob(circles: List<FloatArray>, rho: Float): Path {
            val n = circles.size
            val fil = Array(n) { FloatArray(6) }  // t1, t2, fillet centre
            for (i in 0 until n) {
                val (x1, y1, r1) = circles[i].let { Triple(it[0], it[1], it[2]) }
                val (x2, y2, r2) = circles[(i + 1) % n].let { Triple(it[0], it[1], it[2]) }
                val dx = x2 - x1; val dy = y2 - y1; val dd = hypot(dx, dy)
                val a = r1 + rho; val b = r2 + rho
                val tt = (a * a - b * b + dd * dd) / (2 * dd)
                val hgt = sqrt(max(a * a - tt * tt, 0f))
                val ox = dy / dd; val oy = -dx / dd
                val px = x1 + dx / dd * tt + ox * hgt; val py = y1 + dy / dd * tt + oy * hgt
                fil[i] = floatArrayOf(
                    x1 + (px - x1) * r1 / a, y1 + (py - y1) * r1 / a,
                    x2 + (px - x2) * r2 / b, y2 + (py - y2) * r2 / b, px, py,
                )
            }
            val p = Path()
            p.moveTo(fil[n - 1][2], fil[n - 1][3])
            for (i in 0 until n) {
                val (x, y, r) = circles[i].let { Triple(it[0], it[1], it[2]) }
                val s = fil[(i - 1 + n) % n]
                arc(p, x, y, r, s[2], s[3], fil[i][0], fil[i][1], true)
                arc(p, fil[i][4], fil[i][5], rho, fil[i][0], fil[i][1], fil[i][2], fil[i][3], false)
            }
            p.close()
            return p
        }

        private fun frecess(pad: Float = 7f, rho0: Float = 24f): Path {
            val cs = fk.map { floatArrayOf(it.cx, it.cy, it.w / 2 + pad) }
            val r = cs[0][2]; val n = 9f
            val dmax = cs.zipWithNext { a, b -> hypot(a[0] - b[0], a[1] - b[1]) }.max()
            val rho = max(rho0, ((dmax / 2) * (dmax / 2) + n * n - r * r) / (2 * (r - n)))
            return blob(cs + cs.subList(1, cs.size - 1).reversed(), rho)
        }

        private fun drecess(pad: Float = 9f, rho: Float = 16f): Path {
            val u = k("UP"); val l = k("LEFT"); val r = k("RIGHT")
            val ru = u.w / 2
            return blob(
                listOf(
                    floatArrayOf(u.cx, u.cy - u.h / 2 + ru, ru + pad), floatArrayOf(r.cx, r.cy, r.w / 2 + pad),
                    floatArrayOf(u.cx, u.cy + u.h / 2 - ru, ru + pad), floatArrayOf(l.cx, l.cy, l.w / 2 + pad),
                ),
                rho,
            )
        }

        // ---- painting ----

        private fun aa() = Paint(Paint.ANTI_ALIAS_FLAG)
        private fun withAlpha(color: Int, a: Float) = Color.argb((a * 255).toInt().coerceIn(0, 255), Color.red(color), Color.green(color), Color.blue(color))

        /** A recess: gradient floor, the shadow of its upper wall, light on its lower lip. */
        private fun recess(cv: Canvas, path: Path) {
            val b = RectF().also { path.computeBounds(it, true) }
            cv.drawPath(path, aa().apply { shader = LinearGradient(0f, b.top, 0f, b.bottom, t.floor0, t.floor1, Shader.TileMode.CLAMP) })
            cv.save()
            cv.clipPath(path)
            val wall = Path(path).apply { offset(0f, 4f); fillType = Path.FillType.INVERSE_WINDING }
            cv.drawPath(wall, aa().apply { color = withAlpha(Color.BLACK, 0.85f); maskFilter = BlurMaskFilter(6f, BlurMaskFilter.Blur.NORMAL) })
            cv.restore()
            cv.drawPath(path, aa().apply {
                style = Paint.Style.STROKE; strokeWidth = 1.6f
                shader = LinearGradient(
                    0f, b.top, 0f, b.bottom,
                    intArrayOf(withAlpha(Color.BLACK, 0.9f), withAlpha(Color.WHITE, 0f), withAlpha(Color.WHITE, 0.16f)),
                    floatArrayOf(0f, 0.45f, 1f), Shader.TileMode.CLAMP,
                )
            })
        }

        private inline fun rotated(cv: Canvas, k: Key, block: () -> Unit) {
            cv.save()
            if (k.ang != 0f) cv.rotate(k.ang, k.cx, k.cy)
            block()
            cv.restore()
        }

        /** The 3D finish of a key: satin gradient, soft bevel at the bottom, light rim at the top. */
        private fun satin(cv: Canvas, k: Key, fill: Int) {
            val w = Color.WHITE; val b = Color.BLACK
            cv.drawPath(kpath(k), aa().apply {
                shader = LinearGradient(0f, k.cy - k.h / 2, 0f, k.cy + k.h / 2,
                    intArrayOf(mix(fill, w, .16f), fill, mix(fill, b, .12f)), floatArrayOf(0f, .55f, 1f), Shader.TileMode.CLAMP)
            })
            cv.drawPath(kpath(k, -0.9f), aa().apply {
                style = Paint.Style.STROKE; strokeWidth = 1.8f
                shader = LinearGradient(0f, k.cy - k.h / 2, 0f, k.cy + k.h / 2,
                    intArrayOf(withAlpha(b, 0f), withAlpha(b, 0f), withAlpha(b, .35f)), floatArrayOf(0f, .5f, 1f), Shader.TileMode.CLAMP)
            })
        }

        private fun rim(cv: Canvas, k: Key) = cv.drawPath(kpath(k, -0.7f), aa().apply {
            style = Paint.Style.STROKE; strokeWidth = 1.4f
            shader = LinearGradient(0f, k.cy - k.h / 2, 0f, k.cy + k.h / 2,
                intArrayOf(withAlpha(Color.WHITE, 0.22f), withAlpha(Color.WHITE, 0.03f), withAlpha(Color.WHITE, 0.03f)),
                floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
        })

        private fun shiftRing(cv: Canvas, k: Key) {
            if (k.name == "SHIFT") cv.drawPath(kpath(k, -7f), aa().apply {
                style = Paint.Style.STROKE; strokeWidth = 1.8f; color = if (pal != null) legendColor(k) else t.shiftRing
            })
        }

        private fun key(cv: Canvas, k: Key) = rotated(cv, k) {
            val fill = fillOf(k)
            val p = pal
            if (p?.finish == Finish.NEON || p?.finish == Finish.OUTLINE) {
                val line = outlineOf(p, k)
                if (p.finish == Finish.NEON) cv.drawPath(kpath(k, 0.5f), aa().apply {
                    style = Paint.Style.STROKE; strokeWidth = 6f; color = withAlpha(line, 0.45f)
                    maskFilter = BlurMaskFilter(4.5f, BlurMaskFilter.Blur.NORMAL)
                })
                cv.drawPath(kpath(k), aa().apply { color = fill })
                if (threeD) satin(cv, k, mix(fill, line, .12f))  // a hint of the outline colour, so the satin shows on black
                cv.drawPath(kpath(k, -1f), aa().apply { style = Paint.Style.STROKE; strokeWidth = 2f; color = line })
                if (p.finish == Finish.OUTLINE) shiftRing(cv, k)
                return@rotated
            }
            t.outline?.let { cv.drawPath(kpath(k, t.outlineW), aa().apply { color = it }) }
            // solid pass for the shadow (a shadow on a gradient paint would take the gradient's colours)
            cv.drawPath(kpath(k), aa().apply { color = fill; setShadowLayer(4.6f, 0f, 3f, withAlpha(Color.BLACK, t.shadow)) })
            if (threeD) satin(cv, k, fill)
            rim(cv, k)
            if (!threeD && (k.kind == "black" || k.kind == "dpad")) {
                cv.drawPath(kpath(k, -0.5f), aa().apply { style = Paint.Style.STROKE; strokeWidth = 1f; color = withAlpha(t.blackRim, 0.35f) })
            }
            shiftRing(cv, k)
        }

        /** Cursor pad marks: arrowheads; on the 89 also the home/end marks and the page-scroll chevrons. */
        private fun over(cv: Canvas) {
            val u = k("UP"); val l = k("LEFT"); val r = k("RIGHT")
            val cx = u.cx; val cy = u.cy; val hh = u.h / 2
            val tri = aa().apply { color = if (pal != null) legendColor(u) else t.ink; style = Paint.Style.FILL_AND_STROKE; strokeWidth = 2f; strokeJoin = Paint.Join.ROUND }
            fun triangle(x: Float, y: Float, dx: Float, dy: Float, s: Float = 7f) = cv.drawPath(Path().apply {
                moveTo(x + dx * s, y + dy * s)
                lineTo(x - dx * s * .6f - dy * s, y - dy * s * .6f + dx * s)
                lineTo(x - dx * s * .6f + dy * s, y - dy * s * .6f - dx * s); close()
            }, tri)
            triangle(cx, cy - hh + 20, 0f, -1f); triangle(cx, cy + hh - 20, 0f, 1f)
            triangle(l.cx - 12, l.cy, -1f, 0f); triangle(r.cx + 12, r.cy, 1f, 0f)
            if (base.ti84) return
            fun line(color: Int) = aa().apply {
                this.color = color; style = Paint.Style.STROKE; strokeWidth = 2.2f; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
            }
            val green = line(t.green); val blue = line(t.blue)
            for ((y, dy) in listOf(cy - hh + 46 to -1f, cy + hh - 46 to 1f)) {
                cv.drawPath(Path().apply {
                    moveTo(cx - 8, y + dy * 7); lineTo(cx + 8, y + dy * 7)
                    moveTo(cx, y - dy * 7); lineTo(cx, y + dy * 3)
                    moveTo(cx - 5, y - dy); lineTo(cx, y + dy * 4); lineTo(cx + 5, y - dy)
                }, green)
            }
            for ((y, dy) in listOf(cy - 36 to -1f, cy + 36 to 1f)) {
                for (i in 0 until 3) cv.drawPath(Path().apply {
                    moveTo(cx - 9, y + dy * 5 * i + dy * 3); lineTo(cx, y + dy * 5 * i + dy * 7); lineTo(cx + 9, y + dy * 5 * i + dy * 3)
                }, blue)
            }
        }

        /** Contrast bracket beside − and + (TI-89 layout). */
        private fun decor(cv: Canvas) {
            cv.save()
            cv.translate(decorDx, 0f)
            val col = t.green
            cv.drawPath(Path().apply {
                moveTo(608f, 718f); lineTo(617f, 718f); quadTo(622f, 718f, 622f, 724f); lineTo(622f, 800f)
                quadTo(622f, 806f, 616f, 806f); lineTo(608f, 806f)
            }, aa().apply { color = col; style = Paint.Style.STROKE; strokeWidth = 2.6f; strokeCap = Paint.Cap.ROUND })
            cv.drawCircle(621f, 762f, 8f, aa().apply { color = col })
            val dia = Path().apply { moveTo(621f, 756f); lineTo(627f, 762f); lineTo(621f, 768f); lineTo(615f, 762f); close() }
            cv.drawPath(dia, aa().apply { color = col })
            cv.drawPath(dia, aa().apply { style = Paint.Style.STROKE; strokeWidth = 1.4f; color = withAlpha(Color.BLACK, 0.35f) })
            cv.restore()
        }

        // ---- text ----

        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = tf }

        private fun legendColor(k: Key): Int {
            val p = pal ?: return defaultLegendColor(k)
            if (p.finish == Finish.NEON) return outlineOf(p, k)
            if (p.finish == Finish.OUTLINE) return when {
                k.kind == "2nd" || k.kind == "diamond" || k.kind == "alpha" -> roleColor(p, k)
                k.name == "APPS" || (k.name == "MATRIX" && k.legend[0] == "APPS") -> p.apps
                else -> p.text
            }
            val f = fillOf(k)
            return if (contrast(p.text, f) >= 4.5) p.text else p.all.maxBy { contrast(it, f) }
        }

        private fun defaultLegendColor(k: Key): Int = when {
            k.name == "APPS" || (k.name == "MATRIX" && k.legend[0] == "APPS") -> t.purple
            k.kind == "white" -> t.onLight
            k.kind in setOf("2nd", "diamond", "alpha") -> t.onLight
            else -> t.onDark
        }

        private fun primarySize(k: Key, p: String) = when {
            p == "←" -> sizes.getValue("digit") * 1.3f  // Noto's arrow is small next to the digits
            p == "↑" || p == "(−)" -> sizes.getValue("key")  // ↑ must clear the shift ring; (−) reads too big at digit size
            p.none { it.isLetter() } -> sizes.getValue("digit")
            k in fk -> sizes.getValue("fkey")
            else -> sizes.getValue("key")
        }

        /** Inked bounds of [s] at [size], from x = 0 on the baseline (y down). */
        private fun inkBox(s: String, size: Float): RectF {
            textPaint.textSize = 1000f; textPaint.letterSpacing = 0f
            val b = Rect()
            textPaint.getTextBounds(s, 0, s.length, b)
            val f = size / 1000f
            return RectF(b.left * f, b.top * f, b.right * f, b.bottom * f)
        }

        private fun labelWidth(s: String, fs: Float): Float {
            textPaint.textSize = fs; textPaint.letterSpacing = 0.2f / fs
            return textPaint.measureText(s)
        }

        /** Runs of a label: (text, colour, superscript). ⁻¹ and ˣ are set as raised small text. */
        private fun runs(s: String, color: Int): List<Triple<String, Int, Boolean>> {
            val out = ArrayList<Triple<String, Int, Boolean>>()
            var i = 0
            val buf = StringBuilder()
            while (i < s.length) {
                val sup = when {
                    s.startsWith("⁻¹", i) -> "−1"
                    s[i] == 'ˣ' -> "x"
                    else -> null
                }
                if (sup != null) {
                    if (buf.isNotEmpty()) { out.add(Triple(buf.toString(), color, false)); buf.clear() }
                    out.add(Triple(sup, color, true))
                    i += if (sup == "x") 1 else 2
                } else {
                    buf.append(s[i]); i++
                }
            }
            if (buf.isNotEmpty()) out.add(Triple(buf.toString(), color, false))
            return out
        }

        private fun legend(cv: Canvas, k: Key) {
            val (prim, b, g, a) = k.legend.let { listOf(it[0], it[1], it[2], it[3]) }
            val tilt = abs(k.ang) > 1f
            val ca = cos(Math.toRadians(k.ang.toDouble())).toFloat()
            val sa = sin(Math.toRadians(k.ang.toDouble())).toFloat()
            val skew = tan(Math.toRadians(k.ang.toDouble())).toFloat()

            if (!prim.isNullOrEmpty()) {
                val size = primarySize(k, prim)
                val ink = inkBox(prim, size)
                val tx = k.cx + k.lx - (ink.left + ink.right) / 2
                val by = k.cy + k.ly - (ink.top + ink.bottom) / 2
                cv.save()
                if (tilt) { cv.translate(k.cx, k.cy); cv.skew(0f, skew); cv.translate(-k.cx, -k.cy) }
                textPaint.textSize = size; textPaint.letterSpacing = 0f; textPaint.color = legendColor(k); textPaint.style = Paint.Style.FILL
                if (threeD) {  // engraved: a light edge just below the glyphs
                    textPaint.color = withAlpha(Color.WHITE, 0.30f); cv.drawText(prim, tx, by + 1f, textPaint)
                    textPaint.color = legendColor(k)
                }
                cv.drawText(prim, tx, by, textPaint)
                cv.restore()
            }

            // label row above the key: laid out in the key's frame, each label's centre rotated with
            // the key and the label sheared about it so it runs parallel to the key's top edge
            val x0 = k.cx - k.w / 2; val x1 = k.cx + k.w / 2
            val fs = sizes.getValue("label")
            val ly = if (k in fk) fk.minOf { it.cy - it.h / 2 - 7f - 5f } else {
                val lift = if (k.name == "ON" || k.name == "ENTER") 0f else t.labelLift
                k.cy - k.h / 2 - lift - 5f
            }
            val inset = 8f; val gap = 7f
            fun tw(s: String) = labelWidth(s, fs)
            fun spread(wl: Float, wr: Float) = min(inset, (k.w - wl - wr - gap) / 2)
            fun txt(x: Float, anchor: Char, parts: List<Triple<String, Int, Boolean>>, plain: String) {
                val wd = tw(plain)
                val left = x - when (anchor) { 'e' -> wd; 'm' -> wd / 2; else -> 0f }
                val u = left + wd / 2 - k.cx; val v = ly - k.cy
                val px = k.cx + u * ca - v * sa; val py = k.cy + u * sa + v * ca
                drawRuns(cv, parts, px, py, fs, if (tilt && k !in fk) skew else 0f)
            }
            when {
                k in fk -> {
                    val parts = (if (b != null) runs(b, t.blue) + Triple(" ", t.blue, false) else emptyList()) + runs(g ?: "", t.green)
                    txt(k.cx, 'm', parts, (if (b != null) "$b " else "") + (g ?: ""))
                }
                a != null -> {
                    val ps = listOfNotNull(b, g)
                    val leftText = ps.joinToString("  ")
                    val ins = if (ps.isNotEmpty()) spread(tw(leftText), tw(a)) else inset
                    txt(x1 - ins, 'e', runs(a, t.alpha), a)
                    if (ps.isNotEmpty()) {
                        val parts = ArrayList<Triple<String, Int, Boolean>>()
                        ps.forEachIndexed { i, s -> if (i > 0) parts.add(Triple("  ", t.blue, false)); parts.addAll(runs(s, if (s == b) t.blue else t.green)) }
                        txt(x0 + ins, 's', parts, leftText)
                    }
                }
                b != null && g != null -> {
                    val ins = spread(tw(b), tw(g))
                    txt(x0 + ins, 's', runs(b, t.blue), b)
                    txt(x1 - ins, 'e', runs(g, t.green), g)
                }
                b != null || g != null -> txt(k.cx, 'm', runs((b ?: g)!!, if (b != null) t.blue else t.green), (b ?: g)!!)
            }
        }

        /** Draws label runs centred on (px, py), sheared by [skew] about that point; halo first if the theme has one. */
        private fun drawRuns(cv: Canvas, parts: List<Triple<String, Int, Boolean>>, px: Float, py: Float, fs: Float, skew: Float) {
            fun widthOf(p: Triple<String, Int, Boolean>): Float {
                val size = if (p.third) fs * 0.72f else fs
                textPaint.textSize = size; textPaint.letterSpacing = 0.2f / size
                return textPaint.measureText(p.first)
            }
            val total = parts.sumOf { widthOf(it).toDouble() }.toFloat()
            cv.save()
            if (skew != 0f) { cv.translate(px, py); cv.skew(0f, skew); cv.translate(-px, -py) }
            val passes = if (t.halo != null) listOf(true, false) else listOf(false)
            for (halo in passes) {
                var x = px - total / 2
                for (p in parts) {
                    val size = if (p.third) fs * 0.72f else fs
                    val w = widthOf(p)
                    textPaint.textSize = size; textPaint.letterSpacing = 0.2f / size
                    if (halo) {
                        textPaint.style = Paint.Style.STROKE; textPaint.strokeWidth = t.haloW; textPaint.strokeJoin = Paint.Join.ROUND
                        textPaint.color = withAlpha(t.halo!!, t.haloOp)
                    } else {
                        textPaint.style = Paint.Style.FILL; textPaint.color = p.second
                    }
                    cv.drawText(p.first, x, if (p.third) py - 0.38f * fs else py, textPaint)
                    x += w
                }
            }
            textPaint.style = Paint.Style.FILL
            cv.restore()
        }

        // ---- touch mask ----

        /** Key code per design unit: each key's shape plus OVERHANG; 255 = no key. The cursor bar is UP / DOWN. */
        fun mask(w: Int, h: Int): ByteArray {
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val cv = Canvas(bmp)
            val grow = Paint().apply { style = Paint.Style.FILL_AND_STROKE; strokeWidth = 2 * OVERHANG; isAntiAlias = false }
            val exact = Paint().apply { style = Paint.Style.FILL; isAntiAlias = false }
            for (paint in listOf(grow, exact)) {
                for (k in keys) rotated(cv, k) {
                    val path = kpath(k)
                    if (k.codeDown >= 0) {
                        // the cursor bar: upper half UP, lower half DOWN
                        cv.save(); cv.clipRect(-1e4f, -1e4f, 1e4f, k.cy)
                        paint.color = Color.argb(255, k.code, 0, 0); cv.drawPath(path, paint); cv.restore()
                        cv.save(); cv.clipRect(-1e4f, k.cy, 1e4f, 1e4f)
                        paint.color = Color.argb(255, k.codeDown, 0, 0); cv.drawPath(path, paint); cv.restore()
                    } else {
                        paint.color = Color.argb(255, k.code, 0, 0)
                        cv.drawPath(path, paint)
                    }
                }
            }
            val px = IntArray(w * h)
            bmp.getPixels(px, 0, w, 0, 0, w, h)
            bmp.recycle()
            return ByteArray(w * h) { i -> (if (Color.alpha(px[i]) < 255) NO_KEY else Color.red(px[i])).toByte() }
        }
    }
}
