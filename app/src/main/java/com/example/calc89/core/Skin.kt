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
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import java.io.DataInputStream
import java.util.Locale
import kotlin.math.roundToInt

class KeyPress(val keyCode: Int, var touchId: Int)

/** Pressed-key highlight: the key's touch area (key shape plus overhang) as a small bitmap. */
class KeyOverlay(val bitmap: Bitmap, val maskX: Int, val maskY: Int)

/**
 * Portrait skin: button image on the lower part, LCD on top. The key mask has one cell per design pixel of
 * the skin; a cell holds the key code of the key whose shape (plus overhang) covers it, or 255 for no key.
 */
class Skin(private val context: Context, private val type: SkinType, private val model: CalcModel) {
    companion object {
        private const val BORDER_SCREEN_SKIN = 2
        private const val NO_KEY = 255
        private const val HIGHLIGHT_COLOR = 0x5AFFFFFF // white, 35% opaque
        val filteredPaint = Paint().apply { isFilterBitmap = true }
    }

    var canvasWidth = 0
        private set
    var canvasHeight = 0
        private set

    var bitmap: Bitmap? = null
        private set
    @Volatile var screen: EmulatorScreen? = null
        private set

    var backgroundColor = 0xFF000000.toInt()
    var lcdBackground = 0xFFA5BAA0.toInt()
    var lcdPixelOff = 0xFFB6C5B7.toInt()
    var lcdPixelOn = 0xFF000000.toInt()

    private var keyMask: ByteArray? = null
    private var keyMaskW = 0
    private var keyMaskH = 0
    private var skinInCanvas = Rect()
    private val overlays = HashMap<Int, KeyOverlay?>()

    private val root get() = "portrait/${model.skin}${(if (type.bundled) type else SkinType.CLASSIC).suffix}/"

    fun init(width: Int, height: Int, config: EmulatorConfig, onFrame: () -> Unit) {
        release()
        canvasWidth = width
        canvasHeight = height

        val maxZoom = width / model.lcdWidth
        val zoom = adjustScreenZoom(config.screenScale, maxZoom, width, height)
        val screenW = (model.lcdWidth * zoom).roundToInt()
        val lcdH = (model.lcdHeight * zoom).roundToInt()
        val screenH = lcdH + 10

        val lcd = config.lcd()
        lcdPixelOff = lcd.pixelOff
        lcdPixelOn = lcd.pixelOn
        lcdBackground = lcd.background

        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val skinCanvas = Canvas(out)

        // the keypad fills the view below the LCD: drawn on the phone at this exact size, or as a last
        // resort the bundled image, scaled evenly (never stretched)
        val buttonsH = height - screenH - BORDER_SCREEN_SKIN
        val area = Rect(0, height - buttonsH, width, height)
        val cacheKey = SkinCache.key(context, model, type, area.width(), area.height(), config.oledContrast, config.skin3d)
        val cached = SkinCache.get(context, cacheKey)
        if (cached != null) {
            skinCanvas.drawBitmap(cached.bitmap, area.left.toFloat(), area.top.toFloat(), null)
            backgroundColor = cached.backgroundColor
            keyMask = cached.mask
            keyMaskW = cached.maskWidth
            keyMaskH = cached.maskHeight
            skinInCanvas = Rect(cached.keypad).apply { offset(area.left, area.top) }
        } else {
            val rendered = try {
                SkinRenderer.render(context, model, type, skinCanvas, area, config.oledContrast, config.skin3d)
            } catch (e: Exception) {
                null
            } catch (e: OutOfMemoryError) {
                null
            }
            if (rendered != null) {
                backgroundColor = rendered.backgroundColor
                keyMask = rendered.mask
                keyMaskW = rendered.maskWidth
                keyMaskH = rendered.maskHeight
                skinInCanvas = rendered.keypad
                // keep the drawing, so the next start only copies it
                val keypadOnly = Bitmap.createBitmap(out, area.left, area.top, area.width(), area.height())
                val keypad = Rect(rendered.keypad).apply { offset(-area.left, -area.top) }
                SkinCache.put(context, cacheKey, SkinCache.Entry(keypadOnly, keypad, rendered.mask, rendered.maskWidth, rendered.maskHeight, rendered.backgroundColor))
            } else {
                drawBundled(skinCanvas, area)
            }
        }

        val above = Paint().apply { color = backgroundColor }
        skinCanvas.drawRect(0f, 0f, width.toFloat(), area.top.toFloat(), above)
        val lcdPaint = Paint().apply { color = lcdBackground; style = Paint.Style.FILL }
        skinCanvas.drawRect(Rect(0, 0, width, screenH), lcdPaint)
        bitmap = out
        overlays.clear()

        val left = width / 2 - screenW / 2
        screen = EmulatorScreen(Rect(left, 5, left + screenW, lcdH + 5), model.lcdWidth, model.lcdHeight, onFrame)
    }

    /**
     * The pre-rendered skin from assets/portrait: scaled evenly to fit [area], bottom-aligned and centred;
     * the space left over repeats the image's edge rows / columns, so the body and case simply continue.
     */
    private fun drawBundled(cv: Canvas, area: Rect) {
        val image = context.assets.open(root + "skin.webp").use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inScaled = false })
        } ?: error("Cannot decode skin")
        parseInfo()
        keyMask = ByteArray(keyMaskW * keyMaskH).also { mask ->
            DataInputStream(context.assets.open(root + "buttonmask.bin")).use { it.readFully(mask) }
        }

        val s = minOf(area.width().toFloat() / image.width, area.height().toFloat() / image.height)
        val w = (image.width * s).toInt()
        val h = (image.height * s).toInt()
        val dest = Rect(area.left + (area.width() - w) / 2, area.bottom - h, area.left + (area.width() - w) / 2 + w, area.bottom)
        cv.drawColor(backgroundColor)
        if (dest.left > area.left) {
            cv.drawBitmap(image, Rect(0, 0, 1, image.height), Rect(area.left, dest.top, dest.left, dest.bottom), filteredPaint)
            cv.drawBitmap(image, Rect(image.width - 1, 0, image.width, image.height), Rect(dest.right, dest.top, area.right, dest.bottom), filteredPaint)
        }
        if (dest.top > area.top) {
            cv.drawBitmap(image, Rect(0, 0, image.width, 1), Rect(dest.left, area.top, dest.right, dest.top), filteredPaint)
        }
        cv.drawBitmap(image, null, dest, filteredPaint)
        image.recycle()
        skinInCanvas = dest
    }

    /**
     * Automatic: the LCD fills the width (up to half the height), at a fractional zoom when the width is not a
     * multiple of the LCD's. A chosen scale stays a whole number, for pixels of one exact size.
     */
    private fun adjustScreenZoom(scale: Int, maxZoom: Int, width: Int, height: Int): Float = when {
        scale <= 0 -> minOf(width.toFloat() / model.lcdWidth, 0.5f * height / model.lcdHeight)
        scale > maxZoom -> maxZoom.toFloat()
        else -> scale.toFloat()
    }

    private fun parseInfo() {
        context.assets.open(root + "info").bufferedReader().useLines { lines ->
            for (line in lines) {
                val parts = line.split(":")
                if (parts.size != 2) continue
                val value = parts[1].trim()
                when (parts[0].trim().lowercase(Locale.ROOT)) {
                    "backgroundcolor" -> backgroundColor = value.toLong(16).toInt()
                    "mask" -> {
                        val xy = value.split(Regex("\\s"))
                        keyMaskW = xy[0].trim().toInt()
                        keyMaskH = xy[1].trim().toInt()
                    }
                }
            }
        }
    }

    /** The key under a touch point, or null when the point is outside the skin. Code 255 means no key. */
    fun getKeypress(x: Int, y: Int): KeyPress? {
        val mask = keyMask ?: return null
        val r = skinInCanvas
        if (x < r.left || x > r.right || y < r.top || y > r.bottom) return null

        val maskX = ((x - r.left) * keyMaskW / (r.right - r.left)).coerceIn(0, keyMaskW - 1)
        val maskY = ((y - r.top) * keyMaskH / (r.bottom - r.top)).coerceIn(0, keyMaskH - 1)
        return KeyPress(mask[maskX + maskY * keyMaskW].toInt() and 0xFF, 0)
    }

    /** Highlight bitmap of one key, built from the mask on first use. Null when the key has no cells. */
    fun overlayFor(code: Int): KeyOverlay? = overlays.getOrPut(code) { buildOverlay(code) }

    private fun buildOverlay(code: Int): KeyOverlay? {
        val mask = keyMask ?: return null
        val c = code.toByte()
        var x0 = keyMaskW
        var y0 = keyMaskH
        var x1 = -1
        var y1 = -1
        for (y in 0 until keyMaskH) {
            val row = y * keyMaskW
            for (x in 0 until keyMaskW) {
                if (mask[row + x] == c) {
                    if (x < x0) x0 = x
                    if (x > x1) x1 = x
                    if (y < y0) y0 = y
                    if (y > y1) y1 = y
                }
            }
        }
        if (x1 < 0) return null

        val w = x1 - x0 + 1
        val h = y1 - y0 + 1
        val pixels = IntArray(w * h)
        for (y in 0 until h) {
            for (x in 0 until w) {
                if (mask[(y0 + y) * keyMaskW + x0 + x] == c) pixels[y * w + x] = HIGHLIGHT_COLOR
            }
        }
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.setPixels(pixels, 0, w, 0, 0, w, h)
        return KeyOverlay(bmp, x0, y0)
    }

    /** Where an overlay goes on the canvas. */
    fun overlayRect(o: KeyOverlay, out: RectF) {
        val sx = skinInCanvas.width().toFloat() / keyMaskW
        val sy = skinInCanvas.height().toFloat() / keyMaskH
        out.set(
            skinInCanvas.left + o.maskX * sx,
            skinInCanvas.top + o.maskY * sy,
            skinInCanvas.left + (o.maskX + o.bitmap.width) * sx,
            skinInCanvas.top + (o.maskY + o.bitmap.height) * sy,
        )
    }

    fun release() {
        bitmap?.recycle()
        bitmap = null
        screen?.release()
        screen = null
        overlays.values.forEach { it?.bitmap?.recycle() }
        overlays.clear()
    }
}
