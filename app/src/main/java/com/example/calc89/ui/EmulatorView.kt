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
package com.example.calc89.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import com.example.calc89.core.EmulatorSession
import com.example.calc89.core.Skin

/** Draws the skin, the LCD and the pressed-key highlights, and turns touches into key presses. */
class EmulatorView(context: Context, private val session: EmulatorSession) : View(context) {
    private val rect = RectF()

    init {
        session.view = this
        session.keypad.onChanged = { invalidate() }
    }

    override fun onDetachedFromWindow() {
        session.onViewDetached()
        super.onDetachedFromWindow()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        session.onViewSize(w, h)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawColor(Color.BLACK)
        val skin = session.skin ?: return

        // the keypad shows as soon as the skin is ready; the LCD and key highlights once the calculator runs
        skin.bitmap?.let { canvas.drawBitmap(it, 0f, 0f, null) }
        if (!session.isEmulating) return
        skin.screen?.draw(canvas)

        for (key in session.keypad.pressedKeys()) {
            val overlay = skin.overlayFor(key.keyCode) ?: continue
            skin.overlayRect(overlay, rect)
            canvas.drawBitmap(overlay.bitmap, null, rect, Skin.filteredPaint)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!session.isEmulating) return false
        val skin = session.skin ?: return false

        val index = event.actionIndex
        val pointerId = event.getPointerId(index)

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                skin.getKeypress(event.getX(index).toInt(), event.getY(index).toInt())?.let {
                    it.touchId = pointerId
                    session.keypad.press(it)
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> session.keypad.unpress(pointerId)
            MotionEvent.ACTION_CANCEL -> session.keypad.unpressAll()
        }
        return true
    }
}
