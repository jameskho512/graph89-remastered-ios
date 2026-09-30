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

/** JNI bridge to the native emulators (TiEmu, TilEm). Symbol names in the jni wrapper C files are bound to this class. */
object EmulatorCore {
    init {
        System.loadLibrary("glib-2.0")
        System.loadLibrary("ticables2-1.3.3")
        System.loadLibrary("ticonv-1.1.3")
        System.loadLibrary("tifiles2-1.1.5")
        System.loadLibrary("ticalcs2-1.1.7")
        System.loadLibrary("tiemu-3.03")
        System.loadLibrary("tilem-2.0")
        System.loadLibrary("wrapper")
    }

    // ----- common -----
    @JvmStatic external fun nativeInitGraph89(calcType: Int, screenWidth: Int, screenHeight: Int, zoom: Int, isGrayscale: Int, isGrid: Int, pixelOnColor: Int, pixelOffColor: Int, gridColor: Int, speedCoefficient: Double, tmpDir: String)
    @JvmStatic external fun nativeCleanGraph89()
    @JvmStatic external fun nativeInstallROM(romSource: String, romDestination: String, calcType: Int, isRom: Int): Int
    @JvmStatic external fun nativeReadEmulatedScreen(returnFlags: ByteArray): Int
    @JvmStatic external fun nativeGetEmulatedScreen(screenBuffer: IntArray)
    @JvmStatic external fun nativeSendKey(key: Int, active: Int)
    @JvmStatic external fun nativeSendKeys(keys: IntArray)
    @JvmStatic external fun nativeUpdateScreenZoom(zoom: Int)

    // ----- tiemu -----
    @JvmStatic external fun nativeTiEmuStep1LoadDefaultConfig()
    @JvmStatic external fun nativeTiEmuStep2LoadImage(path: String): Int
    @JvmStatic external fun nativeTiEmuStep3Init(): Int
    @JvmStatic external fun nativeTiEmuStep4Reset(): Int
    @JvmStatic external fun nativeTiEmuLoadState(filename: String): Int
    @JvmStatic external fun nativeTiEmuRunEngine()
    @JvmStatic external fun nativeTiEmuSaveState(filename: String): Int
    @JvmStatic external fun nativeTiEmuSyncClock()
    @JvmStatic external fun nativeTiEmuTurnScreenOn()
    @JvmStatic external fun nativeTiEmuUploadFile(filename: String): Int

    // ----- tilem (TI-83 / 84 family) -----
    @JvmStatic external fun nativeTilemLoadImage(path: String): Int
    @JvmStatic external fun nativeTilemReset(): Int
    @JvmStatic external fun nativeTilemTurnScreenOn()
    @JvmStatic external fun nativeTilemRunEngine()
    @JvmStatic external fun nativeTilemLoadState(filename: String): Int
    @JvmStatic external fun nativeTilemSaveState(romFilename: String, stateFilename: String): Int
    @JvmStatic external fun nativeTilemSyncClock()
    @JvmStatic external fun nativeTilemUploadFile(filename: String): Int

    // ----- files the calculator sends (TiEmu's link port) -----

    /** Takes each file the calculator sends: the path that holds it, which it must move away, and its name. */
    @Volatile var fileReceiver: ((path: String, name: String) -> Unit)? = null

    /** Called by the native link port on the engine thread: [path] holds the file and is reused for the next one. */
    @JvmStatic
    fun onFileReceived(path: String, name: String) {
        fileReceiver?.invoke(path, name) ?: java.io.File(path).delete()
    }
}
