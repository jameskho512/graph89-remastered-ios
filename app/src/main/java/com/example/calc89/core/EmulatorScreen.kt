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

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.roundToInt

/** Zoom currently configured in the native engine. */
object EngineScreenParams {
    var rawWidth = 0
    var rawHeight = 0
    var zoom = 0

    fun reset() {
        rawWidth = 0
        rawHeight = 0
        zoom = 0
    }
}

/**
 * A frame of the calculator's display at its own resolution: for each pixel, how far it is from unlit (0) to lit
 * (255). Grayscale shades fall in between. The skin picker shows it in any LCD scheme's colours.
 */
class LcdSnapshot(val width: Int, val height: Int, private val levels: ByteArray) {
    fun level(x: Int, y: Int) = levels[y * width + x].toInt() and 0xFF

    companion object {
        /** The colour of a pixel at [level] (0 unlit, 255 lit) in [lcd]'s colours. */
        fun color(level: Int, lcd: LcdColors): Int {
            val t = level / 255f
            fun ch(shift: Int): Int {
                val a = (lcd.pixelOff shr shift) and 0xFF
                val b = (lcd.pixelOn shr shift) and 0xFF
                return (a + (b - a) * t).roundToInt() shl shift
            }
            return 0xFF000000.toInt() or ch(16) or ch(8) or ch(0)
        }
    }
}

class EmulatorScreen(private var destination: Rect, val rawWidth: Int, val rawHeight: Int, private val onFrame: () -> Unit) {
    companion object {
        val screenChangeLock = Any()
    }

    private var integerZoom: Boolean
    private var drawingPaint: Paint? = null

    var zoom: Int
        private set

    private var bitmap: Bitmap?
    private val bitmapRect: Rect
    private val screenData: IntArray
    private val flags = ByteArray(6) // [0] screen off, [1] busy

    @Volatile private var busy = false
    @Volatile private var screenOff = false
    private var crc = 0
    private var counter = 0

    init {
        val dw = destination.right - destination.left
        val dh = destination.bottom - destination.top

        integerZoom = dw % rawWidth == 0
        val zoomf = dw.toFloat() / rawWidth
        zoom = dw / rawWidth

        val diff = max(abs(dw - floor(zoomf) * rawWidth), abs(dh - floor(zoomf) * rawHeight)).toInt()

        // try at best to use an integer zoom. tolerance 20px
        if (!integerZoom && diff < 20) {
            integerZoom = true
            zoom = floor(zoomf).toInt()
            val width = rawWidth * zoom
            val height = rawHeight * zoom
            val cx = (destination.left + destination.right) / 2
            val cy = (destination.top + destination.bottom) / 2
            val top = cy - height / 2
            val left = cx - width / 2
            destination = Rect(left, top, left + width, top + height)
        }

        if (!integerZoom) {
            drawingPaint = Skin.filteredPaint
            zoom = ceil(zoomf).toInt()
        }

        val zw = rawWidth * zoom
        val zh = rawHeight * zoom
        bitmap = Bitmap.createBitmap(zw, zh, Bitmap.Config.ARGB_8888)
        bitmapRect = Rect(0, 0, zw, zh)
        screenData = IntArray(zw * zh)
    }

    fun refresh() {
        synchronized(screenChangeLock) {
            ++counter

            if (EngineScreenParams.rawHeight != rawHeight || EngineScreenParams.rawWidth != rawWidth || EngineScreenParams.zoom != zoom) {
                EngineScreenParams.rawHeight = rawHeight
                EngineScreenParams.rawWidth = rawWidth
                EngineScreenParams.zoom = zoom
                EmulatorCore.nativeUpdateScreenZoom(zoom)
            }

            val newCrc = EmulatorCore.nativeReadEmulatedScreen(flags)
            screenOff = flags[0].toInt() != 0
            busy = flags[1].toInt() != 0

            if (crc != newCrc || counter % 40 == 0) {
                crc = newCrc
                EmulatorCore.nativeGetEmulatedScreen(screenData)
                onFrame()
            }
        }
    }

    fun isBusy() = busy && !screenOff
    fun isScreenOff() = screenOff

    fun draw(canvas: Canvas) {
        synchronized(screenChangeLock) {
            val bmp = bitmap ?: return
            bmp.setPixels(screenData, 0, bmp.width, 0, 0, bmp.width, bmp.height)
            if (integerZoom) {
                canvas.drawBitmap(bmp, destination.left.toFloat(), destination.top.toFloat(), null)
            } else {
                canvas.drawBitmap(bmp, bitmapRect, destination, drawingPaint)
            }
        }
    }

    /**
     * The last frame as an [LcdSnapshot]; [pixelOff] and [pixelOn] are the colours it was drawn in. Null before
     * the first frame.
     */
    fun snapshot(pixelOff: Int, pixelOn: Int): LcdSnapshot? {
        synchronized(screenChangeLock) {
            val zw = rawWidth * zoom
            if (screenData.isEmpty() || screenData[0] == 0) return null  // no frame yet (every drawn pixel is opaque)
            val dr = ((pixelOn shr 16) and 0xFF) - ((pixelOff shr 16) and 0xFF)
            val dg = ((pixelOn shr 8) and 0xFF) - ((pixelOff shr 8) and 0xFF)
            val db = (pixelOn and 0xFF) - (pixelOff and 0xFF)
            val len2 = (dr * dr + dg * dg + db * db).coerceAtLeast(1)
            val levels = ByteArray(rawWidth * rawHeight)
            for (y in 0 until rawHeight) {
                for (x in 0 until rawWidth) {
                    // the centre of the pixel's zoomed block, projected onto the unlit -> lit colour line
                    val c = screenData[(y * zoom + zoom / 2) * zw + x * zoom + zoom / 2]
                    val t = (((c shr 16) and 0xFF) - ((pixelOff shr 16) and 0xFF)) * dr +
                        (((c shr 8) and 0xFF) - ((pixelOff shr 8) and 0xFF)) * dg +
                        ((c and 0xFF) - (pixelOff and 0xFF)) * db
                    levels[y * rawWidth + x] = (t * 255 / len2).coerceIn(0, 255).toByte()
                }
            }
            return LcdSnapshot(rawWidth, rawHeight, levels)
        }
    }

    fun release() {
        synchronized(screenChangeLock) {
            bitmap?.recycle()
            bitmap = null
        }
    }
}
