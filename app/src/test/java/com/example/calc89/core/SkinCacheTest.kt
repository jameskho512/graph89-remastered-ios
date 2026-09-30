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
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** A skin is drawn once: later starts take it from memory, or from the cache folder after the app restarts. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35])
class SkinCacheTest {
    @Test
    fun drawnOnce() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val config = EmulatorConfig(skin = SkinType.EMBER, skin3d = true)
        fun start() = Skin(context, config.skin, CalcModel.TI89T).apply { init(1280, 2544, config) {} }.release()

        val before = SkinRenderer.renders
        start()
        assertEquals("first start draws the skin", before + 1, SkinRenderer.renders)

        start()
        assertEquals("second start uses the memory cache", before + 1, SkinRenderer.renders)

        // the file is written in the background; then forget memory, as after an app restart
        Thread.sleep(3000)
        SkinCache.clearMemory()
        start()
        assertEquals("start after a restart uses the cached file", before + 1, SkinRenderer.renders)

        // another skin is drawn
        Skin(context, SkinType.FROST, CalcModel.TI89T).apply { init(1280, 2544, config.copy(skin = SkinType.FROST)) {} }.release()
        assertEquals(before + 2, SkinRenderer.renders)
    }

    @Test
    fun thumbnailsDrawnOnce() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val before = SkinRenderer.renders
        SkinPreview.keypad(context, CalcModel.TI89T, SkinType.NORD, 360, 460)
        SkinPreview.keypad(context, CalcModel.TI89T, SkinType.NORD, 360, 460)
        assertEquals(before + 1, SkinRenderer.renders)
    }
}
