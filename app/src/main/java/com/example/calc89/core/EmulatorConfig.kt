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

/**
 * Skin theme. Skins are drawn on the phone; [bundled] ones also have pre-rendered images (folder: the
 * calculator's skin family plus [suffix], e.g. ti89classic) as a last resort, the others fall back to Classic.
 */
enum class SkinType(val label: String, val suffix: String, val bundled: Boolean = false) {
    CLASSIC("Classic", "classic", bundled = true),
    MIDNIGHT("Midnight", "midnight", bundled = true),
    OLED("OLED", "oled"),
    MONO("Grayscale", "mono"),
    NEON_GRID("Neon", "neongrid"),
    EMBER("Ember", "ember"),
    FROST("Frost", "frost"),
    SOLAR("Solar", "solar"),
    RETRO("Retro", "retro"),
    EMERALD("Forest", "emerald"),
    BLOSSOM("Floral", "blossom"),
    NORD("Nord", "nord"),
    RADIOACTIVE("Radioactive", "radioactive"),
    ROYAL("Royal", "royal"),
}

/** LCD colours as ARGB: background of the LCD area, off pixel, on pixel. */
data class LcdColors(val background: Int, val pixelOff: Int, val pixelOn: Int)

/**
 * LCD colour schemes. Those named after a keypad skin match that skin.
 * CUSTOM takes its colours from the settings (EmulatorConfig.customLcdBackground / customLcdText).
 */
enum class LcdTheme(val label: String, val background: Int, val pixelOff: Int, val pixelOn: Int) {
    CUSTOM("Custom", 0xFFA5BAA0.toInt(), 0xFFB6C5B7.toInt(), 0xFF000000.toInt()),
    CLASSIC("Classic", 0xFFA5BAA0.toInt(), 0xFFB6C5B7.toInt(), 0xFF000000.toInt()),
    GREY("Grey", 0xFFB4B4B4.toInt(), 0xFFC4C4C4.toInt(), 0xFF1A1A1A.toInt()),
    HIGH_CONTRAST("High contrast", 0xFFFFFFFF.toInt(), 0xFFFFFFFF.toInt(), 0xFF000000.toInt()),
    DARK("Dark", 0xFF101418.toInt(), 0xFF161B20.toInt(), 0xFFE3E8EC.toInt()),
    MIDNIGHT("Midnight", 0xFF141217.toInt(), 0xFF1B1920.toInt(), 0xFFE6E0F0.toInt()),
    OLED("OLED", 0xFF000000.toInt(), 0xFF000000.toInt(), 0xFFE8E8E8.toInt()),
    MONO("Grayscale", 0xFFF4F4F4.toInt(), 0xFFFCFCFC.toInt(), 0xFF111111.toInt()),
    NEON_GRID("Neon", 0xFF02080B.toInt(), 0xFF061419.toInt(), 0xFF00E5FF.toInt()),
    EMBER("Ember", 0xFF1B120C.toInt(), 0xFF24180F.toInt(), 0xFFFF9A4A.toInt()),
    FROST("Frost", 0xFFDCE8F0.toInt(), 0xFFE7F0F6.toInt(), 0xFF1E3448.toInt()),
    SOLAR("Solar", 0xFF002B36.toInt(), 0xFF073642.toInt(), 0xFFEEE8D5.toInt()),
    RETRO("Retro", 0xFFC7C0A3.toInt(), 0xFFD2CCB2.toInt(), 0xFF3A2E25.toInt()),
    EMERALD("Forest", 0xFF0E1F16.toInt(), 0xFF13291D.toInt(), 0xFF7CC6A4.toInt()),
    BLOSSOM("Floral", 0xFFF6E3E9.toInt(), 0xFFFBEEF2.toInt(), 0xFF5B4453.toInt()),
    NORD("Nord", 0xFF2E3440.toInt(), 0xFF353C4A.toInt(), 0xFF88C0D0.toInt()),
    RADIOACTIVE("Radioactive", 0xFF020A02.toInt(), 0xFF061406.toInt(), 0xFF39FF14.toInt()),
    ROYAL("Royal", 0xFF0B0E24.toInt(), 0xFF11153A.toInt(), 0xFFE3B341.toInt()),
}

/** Unlit pixels are a faint step from the background towards the ink, as on a real LCD. */
fun customLcd(background: Int, text: Int): LcdColors {
    fun ch(a: Int, b: Int, shift: Int) = ((a shr shift and 0xFF) * 93 + (b shr shift and 0xFF) * 7) / 100
    val off = (0xFF shl 24) or (ch(background, text, 16) shl 16) or (ch(background, text, 8) shl 8) or ch(background, text, 0)
    return LcdColors(background, off, text)
}

/** Black margins around the calculator so rounded screen corners and the camera cutout do not hide it. */
enum class ScreenMargins(val label: String) {
    CAMERA("Default: Camera only"),
    CORNERS("Corners only"),
    AUTO("Camera & corners"),
    NONE("None"),
}

/** Vibration time range in milliseconds; 0 is off. The slider moves in steps of 1. */
const val HAPTIC_MAX_MS = 50

/** A stored value clamped to the slider range. */
fun nearestHaptic(ms: Int): Int = ms.coerceIn(0, HAPTIC_MAX_MS)

/** Selectable CPU speeds in percent; 100 is the default. */
val CPU_SPEEDS = listOf(50, 75, 100, 150, 200, 250)

data class EmulatorConfig(
    val hapticMs: Int = 5,
    /** Vibration strength in percent (1-100); only phones with amplitude control can vary it. */
    val hapticStrength: Int = 35,
    val audioFeedback: Boolean = false,
    /** <= 0 means automatic. */
    val screenScale: Int = -1,
    val skin: SkinType = SkinType.CLASSIC,
    val grayscale: Boolean = false,
    val saveStateOnExit: Boolean = true,
    val cpuSpeed: Int = 100,
    val exitOnScreenOff: Boolean = true,
    /** Back opens the menu; with this on, Back again exits (otherwise it closes the menu). */
    val exitOnDoubleBack: Boolean = false,
    val lcdTheme: LcdTheme = LcdTheme.CLASSIC,
    /** Colours of the Custom LCD (ARGB). */
    val customLcdBackground: Int = 0xFFA5BAA0.toInt(),
    val customLcdText: Int = 0xFF000000.toInt(),
    /** Picking a skin also picks its LCD scheme, and the other way round. */
    val linkLcdToSkin: Boolean = true,
    /** Brightness of the OLED skin's text and outlines (and, when linked, the OLED LCD's text), in percent. */
    val oledContrast: Int = 70,
    /** 3D finish on any skin: satin keys with bevelled edges and engraved legends (the face stays as it is). */
    val skin3d: Boolean = false,
    val screenMargins: ScreenMargins = ScreenMargins.CAMERA,
)

/** The LCD colours in use: the chosen scheme, or the Custom colours. */
fun EmulatorConfig.lcd(): LcdColors {
    if (lcdTheme == LcdTheme.CUSTOM) return customLcd(customLcdBackground, customLcdText)
    var on = lcdTheme.pixelOn
    if (lcdTheme == LcdTheme.OLED && linkLcdToSkin) {  // the OLED contrast dims the OLED LCD's text too
        val f = oledContrast.coerceIn(0, 100) / 100f
        on = (0xFF shl 24) or ((((on shr 16) and 0xFF) * f).toInt() shl 16) or ((((on shr 8) and 0xFF) * f).toInt() shl 8) or ((on and 0xFF) * f).toInt()
    }
    return LcdColors(lcdTheme.background, lcdTheme.pixelOff, on)
}
