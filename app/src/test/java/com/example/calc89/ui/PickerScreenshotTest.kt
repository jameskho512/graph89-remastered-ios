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

import android.app.Dialog
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import android.view.View
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import com.example.calc89.core.CalcModel
import com.example.calc89.core.EmulatorConfig
import com.example.calc89.core.LcdTheme
import com.example.calc89.core.SkinType
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowDialog
import java.io.File
import java.time.Duration

/**
 * Screenshots of the skin picker and its dialogs (app/build/screens), for reviewing the UI without a phone.
 * The windows are drawn directly (the picker renders its previews in the background and shows a spinner meanwhile,
 * so it never becomes idle in the Compose test sense).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
class PickerScreenshotTest {
    private fun save(view: View, name: String) {
        val bmp = Bitmap.createBitmap(view.width.coerceAtLeast(1), view.height.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        view.draw(Canvas(bmp))
        val out = File("build/screens").apply { mkdirs() }
        File(out, "$name.png").outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun run(ms: Long) {
        var t = 0L
        while (t < ms) {
            Thread.sleep(50)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
            t += 50
        }
    }

    private fun screen(content: @Composable () -> Unit): ComponentActivity {
        val activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()
        activity.setContent { Graph89Theme { content() } }
        run(3000)
        return activity
    }

    private fun picker(config: EmulatorConfig) = screen {
        SkinPickerScreen(
            config, CalcModel.TI89T, null, 1280, 2544, onChange = {}, onBack = {},
        )
    }

    private fun latestDialog(): Dialog = ShadowDialog.getShownDialogs().last()

    @Test
    fun oledPicker() {
        val a = picker(EmulatorConfig(skin = SkinType.OLED, lcdTheme = LcdTheme.OLED))
        save(a.window.decorView, "picker_oled")
    }

    @Test
    fun customPicker() {
        val a = picker(EmulatorConfig(lcdTheme = LcdTheme.CUSTOM))
        save(a.window.decorView, "picker_custom")
    }

    @Test
    fun customDialog() {
        screen { CustomLcdDialog(0xFFA5BAA0.toInt(), 0xFF000000.toInt(), onDone = { _, _ -> }, onCancel = {}) }
        save(latestDialog().window!!.decorView, "custom_dialog")
    }

    @Test
    fun colorWheel() {
        screen { ColorWheelDialog("Text colour", 0xFF2A6FD6.toInt(), onPick = {}, onCancel = {}) }
        save(latestDialog().window!!.decorView, "color_wheel")
    }
}
