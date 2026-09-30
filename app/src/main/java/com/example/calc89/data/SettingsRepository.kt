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
package com.example.calc89.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.example.calc89.core.EmulatorConfig
import com.example.calc89.core.LcdTheme
import com.example.calc89.core.ScreenMargins
import com.example.calc89.core.nearestHaptic
import com.example.calc89.core.SkinType
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
private val saveScope = kotlinx.coroutines.CoroutineScope(
    kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.IO.limitedParallelism(1),
)

class SettingsRepository(private val context: Context) {
    private object Keys {
        val haptic = intPreferencesKey("haptic_ms")
        val hapticStrength = intPreferencesKey("haptic_strength")
        val audio = booleanPreferencesKey("audio_feedback")
        val scale = intPreferencesKey("screen_scale")
        val skin = stringPreferencesKey("skin")
        val grayscale = booleanPreferencesKey("grayscale")
        val saveState = booleanPreferencesKey("save_state_on_exit")
        val cpu = intPreferencesKey("cpu_speed")
        val exitOnOff = booleanPreferencesKey("exit_on_screen_off")
        val exitOnDoubleBack = booleanPreferencesKey("exit_on_double_back")
        val lcdTheme = stringPreferencesKey("lcd_theme")
        val customLcdBg = intPreferencesKey("custom_lcd_background")
        val customLcdText = intPreferencesKey("custom_lcd_text")
        val linkLcd = booleanPreferencesKey("link_lcd_to_skin")
        val oledContrast = intPreferencesKey("oled_contrast")
        val skin3d = booleanPreferencesKey("skin_3d")
        val margins = stringPreferencesKey("screen_margins")
    }

    val config: Flow<EmulatorConfig> = context.dataStore.data.map { p ->
        val d = EmulatorConfig()
        EmulatorConfig(
            hapticMs = p[Keys.haptic]?.let(::nearestHaptic) ?: d.hapticMs,
            hapticStrength = p[Keys.hapticStrength]?.coerceIn(1, 100) ?: d.hapticStrength,
            audioFeedback = p[Keys.audio] ?: d.audioFeedback,
            screenScale = p[Keys.scale] ?: d.screenScale,
            skin = SkinType.entries.firstOrNull { it.name == p[Keys.skin] } ?: d.skin,
            skin3d = p[Keys.skin3d] ?: d.skin3d,
            grayscale = p[Keys.grayscale] ?: d.grayscale,
            saveStateOnExit = p[Keys.saveState] ?: d.saveStateOnExit,
            cpuSpeed = p[Keys.cpu] ?: d.cpuSpeed,
            exitOnScreenOff = p[Keys.exitOnOff] ?: d.exitOnScreenOff,
            exitOnDoubleBack = p[Keys.exitOnDoubleBack] ?: d.exitOnDoubleBack,
            lcdTheme = LcdTheme.entries.firstOrNull { it.name == p[Keys.lcdTheme] } ?: d.lcdTheme,
            customLcdBackground = p[Keys.customLcdBg] ?: d.customLcdBackground,
            customLcdText = p[Keys.customLcdText] ?: d.customLcdText,
            linkLcdToSkin = p[Keys.linkLcd] ?: d.linkLcdToSkin,
            oledContrast = (p[Keys.oledContrast] ?: d.oledContrast).coerceIn(20, 100),
            screenMargins = ScreenMargins.entries.firstOrNull { it.name == p[Keys.margins] } ?: d.screenMargins,
        )
    }

    /**
     * Saves in the background on an app-wide queue: saves run one after another in order, and they are not
     * cancelled when the Activity ends (a change made right before exiting is kept).
     */
    fun saveAsync(c: EmulatorConfig) {
        saveScope.launch { save(c) }
    }

    suspend fun save(c: EmulatorConfig) {
        context.dataStore.edit { p ->
            p[Keys.haptic] = c.hapticMs
            p[Keys.hapticStrength] = c.hapticStrength
            p[Keys.audio] = c.audioFeedback
            p[Keys.scale] = c.screenScale
            p[Keys.skin] = c.skin.name
            p[Keys.grayscale] = c.grayscale
            p[Keys.saveState] = c.saveStateOnExit
            p[Keys.cpu] = c.cpuSpeed
            p[Keys.exitOnOff] = c.exitOnScreenOff
            p[Keys.exitOnDoubleBack] = c.exitOnDoubleBack
            p[Keys.lcdTheme] = c.lcdTheme.name
            p[Keys.customLcdBg] = c.customLcdBackground
            p[Keys.customLcdText] = c.customLcdText
            p[Keys.linkLcd] = c.linkLcdToSkin
            p[Keys.oledContrast] = c.oledContrast
            p[Keys.skin3d] = c.skin3d
            p[Keys.margins] = c.screenMargins.name
        }
    }
}
