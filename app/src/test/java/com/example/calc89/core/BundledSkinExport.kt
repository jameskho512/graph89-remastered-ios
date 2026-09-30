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
 * Regenerates the bundled last-resort skins (assets/portrait/<family><theme>) with the app's own renderer, so
 * they match what the phone draws. Runs only when asked:
 *
 *   set EXPORT_SKINS=1 && gradlew testDebugUnitTest --tests *BundledSkinExport*
 *
 * The keypad areas are the developer's phone's (1280 x 1733 for the TI-89 family, 1280 x 1701 for the TI-83/84).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35])
class BundledSkinExport {
    @Test
    fun export() {
        if (System.getenv("EXPORT_SKINS") != "1") return
        val context = ApplicationProvider.getApplicationContext<Context>()
        val assets = File("src/main/assets/portrait")
        for (model in listOf(CalcModel.TI89T, CalcModel.TI89, CalcModel.TI84PLUS, CalcModel.TI83)) {
            val h = if (model.engine == Engine.TILEM) 1701 else 1733
            for (type in SkinType.entries.filter { it.bundled }) {
                val bmp = Bitmap.createBitmap(1280, h, Bitmap.Config.ARGB_8888)
                val r = SkinRenderer.render(context, model, type, Canvas(bmp), Rect(0, 0, 1280, h))
                check(r.keypad == Rect(0, 0, 1280, h)) { "the mask must cover the whole image: ${r.keypad}" }
                val dir = File(assets, model.skin + type.suffix).apply { mkdirs() }
                File(dir, "skin.webp").outputStream().use { bmp.compress(Bitmap.CompressFormat.WEBP_LOSSLESS, 100, it) }
                File(dir, "buttonmask.bin").writeBytes(r.mask)
                File(dir, "info").writeText("mask: ${r.maskWidth} ${r.maskHeight}\r\nbackgroundcolor: %08X\r\n".format(r.backgroundColor))
                println("exported ${dir.name} (${r.maskWidth} x ${r.maskHeight} mask)")
            }
        }
    }
}
