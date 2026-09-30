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

enum class Engine { TIEMU, TILEM }

/**
 * The emulated calculator models. [type] is the calculator type code shared with the native wrapper,
 * [skin] the skin family (folder prefix under assets/portrait) and [lcdWidth] x [lcdHeight] the LCD.
 */
enum class CalcModel(
    val type: Int,
    val label: String,
    val engine: Engine,
    val lcdWidth: Int,
    val lcdHeight: Int,
    val skin: String,
    /** Size in bytes of a ROM dump (the calculator's flash / ROM). */
    val romSize: Long,
    /** Extension of the model's OS upgrade file; null when there is none (a dump is required). */
    val osExtension: String?,
) {
    TI89T(2, "TI-89 Titanium", Engine.TIEMU, 160, 100, "ti89", 4L shl 20, ".89u"),
    TI89(1, "TI-89", Engine.TIEMU, 160, 100, "ti89orig", 2L shl 20, ".89u"),
    TI84PLUS_SE(6, "TI-84 Plus SE", Engine.TILEM, 96, 64, "ti84", 2L shl 20, ".8xu"),
    TI84PLUS(7, "TI-84 Plus", Engine.TILEM, 96, 64, "ti84", 1L shl 20, ".8xu"),
    TI83PLUS_SE(8, "TI-83 Plus SE", Engine.TILEM, 96, 64, "ti84", 2L shl 20, ".8xu"),
    TI83PLUS(9, "TI-83 Plus", Engine.TILEM, 96, 64, "ti84", 512L shl 10, ".8xu"),
    TI83(10, "TI-83", Engine.TILEM, 96, 64, "ti83", 256L shl 10, null);

    /** File types the ROM picker accepts for this model, shown to the user. */
    val romFiles: String get() = if (osExtension == null) ".rom dump" else "$osExtension or .rom dump"

    /** File types the calculator takes over its link port: apps, programs and variables. */
    val linkExtensions: Set<String> get() = if (engine == Engine.TIEMU) TI89_LINK_FILES else TI83_84_LINK_FILES
}

private val TI89_LINK_FILES = setOf(
    ".89k", ".89z", ".89f", ".89p", ".89l", ".89g", ".89q", ".89m", ".89i", ".89c", ".89t", ".89y", ".89x",
    ".89a", ".89s", ".89e", ".89d", ".tig",
)

private val TI83_84_LINK_FILES = setOf(
    ".8xu", ".8xk", ".8xp", ".8xn", ".8xl", ".8xm", ".8xe", ".8xs", ".8xi", ".8xw", ".8xc", ".8xz", ".8xt",
    ".8xb", ".8xv", ".8xo", ".8xg",
    ".83l", ".83m", ".83p", ".83y", ".83s", ".83i", ".83c", ".83w", ".83z", ".83t", ".83b",
)

/** One installed calculator: its own folder with image.img and the saved state. */
data class CalcEntry(val id: String, val model: CalcModel)
