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
import android.graphics.Canvas
import android.graphics.Rect
import androidx.test.core.app.ApplicationProvider
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * Draws every skin with the app's own renderer (Android's real graphics, on the JVM) and writes PNGs to
 * app/build/skin-renders, for checking the skins without a phone. The keypad area is the
 * one on the developer's phone (1280 x 1733 for the TI-89 family, 1280 x 1701 for the TI-83/84).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35])
class SkinRenderTest {
    @Test
    fun renderAll() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val out = File("build/skin-renders").apply { mkdirs() }
        for (model in listOf(CalcModel.TI89T, CalcModel.TI84PLUS)) {
            val h = if (model.engine == Engine.TILEM) 1701 else 1733
            for (type in SkinType.entries) {
                val bmp = Bitmap.createBitmap(1280, h, Bitmap.Config.ARGB_8888)
                val t0 = System.nanoTime()
                SkinRenderer.render(context, model, type, Canvas(bmp), Rect(0, 0, 1280, h))
                val ms = (System.nanoTime() - t0) / 1_000_000
                File(out, "${model.name}_${type.name}.png").outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                println("rendered ${model.name} ${type.name} in $ms ms")
                // the same skin with the 3D finish
                val b3 = Bitmap.createBitmap(1280, h, Bitmap.Config.ARGB_8888)
                SkinRenderer.render(context, model, type, Canvas(b3), Rect(0, 0, 1280, h), threeD = true)
                File(out, "${model.name}_${type.name}_3D.png").outputStream().use { b3.compress(Bitmap.CompressFormat.PNG, 100, it) }
            }
        }
    }
}
