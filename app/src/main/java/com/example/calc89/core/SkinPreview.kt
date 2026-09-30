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

/**
 * Pictures of the calculator for the skin picker, laid out like Skin.init but at any size. Each picture is drawn
 * once: keypad thumbnails are kept in memory and as files in the cache folder, whole-calculator previews in memory.
 */
object SkinPreview {
    private val memory = object : android.util.LruCache<String, Bitmap>((Runtime.getRuntime().maxMemory() / 8).toInt().coerceAtMost(64 shl 20)) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }

    private fun thumbDir(context: Context) = java.io.File(context.cacheDir, "thumbs").apply { mkdirs() }

    private fun cached(key: String, draw: () -> Bitmap): Bitmap = memory.get(key) ?: draw().also { memory.put(key, it) }

    /** The LCD's place in a picture [width] px wide: the height of the LCD band at the top, and the screen in it. */
    class LcdArea(val bandHeight: Int, val screen: RectF)

    /** Where the LCD goes, as on this phone: [viewWidth] x [viewHeight] is the real emulator view, which sets its share. */
    fun lcdArea(model: CalcModel, width: Int, viewWidth: Int, viewHeight: Int, screenScale: Int): LcdArea {
        val f = width.toFloat() / viewWidth
        val maxZoom = viewWidth / model.lcdWidth
        val zoom = if (screenScale <= 0) minOf(maxZoom, (0.5 * viewHeight).toInt() / model.lcdHeight) else minOf(screenScale, maxZoom)
        val lw = model.lcdWidth * zoom * f
        val lh = model.lcdHeight * zoom * f
        return LcdArea(((model.lcdHeight * zoom + 10) * f).toInt(), RectF((width - lw) / 2, 5 * f, (width + lw) / 2, 5 * f + lh))
    }

    /**
     * The keypad of the whole calculator as it will look on this phone, below a transparent LCD band (see [lcdArea]):
     * the skin picker draws the LCD itself, so a change of LCD colours needs no new picture.
     */
    fun calculator(
        context: Context, model: CalcModel, type: SkinType, width: Int, height: Int,
        viewWidth: Int, viewHeight: Int, screenScale: Int, oledContrast: Int = 70, threeD: Boolean = false,
    ): Bitmap = cached("calc_${model.name}_${type.name}_${width}x${height}_${viewWidth}x${viewHeight}_${screenScale}_${oledContrast}_$threeD") {
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val f = width.toFloat() / viewWidth
        val band = lcdArea(model, width, viewWidth, viewHeight, screenScale).bandHeight
        keypad(context, model, type, Canvas(bmp), Rect(0, band + (2 * f).toInt(), width, height), oledContrast, threeD)
        bmp
    }

    /** Only the keypad, for the skin thumbnails. */
    fun keypad(context: Context, model: CalcModel, type: SkinType, width: Int, height: Int, oledContrast: Int = 70, threeD: Boolean = false): Bitmap {
        val variant = (if (type == SkinType.OLED) "_c$oledContrast" else "") + (if (threeD) "_3d" else "")
        val key = "thumb_${model.name}_${type.name}${variant}_${width}x${height}_${SkinCache.stamp(context)}"
        return cached(key) {
            val file = java.io.File(thumbDir(context), "$key.png")
            val fromDisk = if (file.isFile) BitmapFactory.decodeFile(file.path) else null
            fromDisk ?: Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bmp ->
                keypad(context, model, type, Canvas(bmp), Rect(0, 0, width, height), oledContrast, threeD)
                try {
                    file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                } catch (e: Exception) {
                    // without the file the thumbnail is drawn again next time
                }
            }
        }
    }

    private fun keypad(context: Context, model: CalcModel, type: SkinType, cv: Canvas, area: Rect, oledContrast: Int, threeD: Boolean) {
        try {
            SkinRenderer.render(context, model, type, cv, area, oledContrast, threeD)
        } catch (e: Exception) {
            cv.drawRect(area, Paint().apply { color = 0xFF404040.toInt() })
        }
    }
}
