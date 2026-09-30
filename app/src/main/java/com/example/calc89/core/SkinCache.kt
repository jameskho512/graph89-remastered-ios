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
import android.graphics.BitmapFactory
import android.graphics.Rect
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File

/**
 * Drawn keypads, so the calculator does not draw its skin again at every start: the last one in memory,
 * recent ones as files in the app's cache folder. A keypad depends on the calculator model, the skin and the
 * size of the keypad area; the app's install time is part of the key, so an update never shows an old drawing.
 */
object SkinCache {
    /** A drawn keypad: [bitmap] covers the whole keypad area; [keypad] (in area coordinates) is where the mask maps. */
    class Entry(val bitmap: Bitmap, val keypad: Rect, val mask: ByteArray, val maskWidth: Int, val maskHeight: Int, val backgroundColor: Int)

    private const val KEEP = 8  // files kept on disk (most recently used)

    private val lock = Any()
    private var memKey: String? = null
    private var mem: Entry? = null

    /** The app's install time: part of every cache key, so an update never shows an old drawing. */
    fun stamp(context: Context): Long = try {
        context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
    } catch (e: Exception) {
        0L
    }

    /**
     * Empties the app's cache folder (drawn skins, thumbnails) the first time a new build runs, so nothing
     * drawn by the previous build is left behind.
     */
    fun wipeIfNewBuild(context: Context) {
        val prefs = context.getSharedPreferences("cache", Context.MODE_PRIVATE)
        val stamp = stamp(context)
        if (prefs.getLong(KEY_BUILD, -1L) == stamp) return
        context.cacheDir.listFiles()?.forEach { it.deleteRecursively() }
        clearMemory()
        prefs.edit().putLong(KEY_BUILD, stamp).apply()
    }

    private const val KEY_BUILD = "build"

    /** Forgets the in-memory entry (the files stay). */
    fun clearMemory() = synchronized(lock) { memKey = null; mem = null }

    fun key(context: Context, model: CalcModel, type: SkinType, width: Int, height: Int, oledContrast: Int, threeD: Boolean): String {
        val stamp = stamp(context)
        val variant = (if (type == SkinType.OLED) "_c$oledContrast" else "") + (if (threeD) "_3d" else "")
        return "${model.name}_${type.name}${variant}_${width}x${height}_$stamp"
    }

    private fun dir(context: Context) = File(context.cacheDir, "skins").apply { mkdirs() }

    fun get(context: Context, key: String): Entry? {
        synchronized(lock) { if (memKey == key) return mem }
        val png = File(dir(context), "$key.png")
        val bin = File(dir(context), "$key.bin")
        if (!png.isFile || !bin.isFile) return null
        return try {
            val bitmap = BitmapFactory.decodeFile(png.path, BitmapFactory.Options().apply { inScaled = false }) ?: return null
            val entry = DataInputStream(bin.inputStream().buffered()).use { s ->
                val keypad = Rect(s.readInt(), s.readInt(), s.readInt(), s.readInt())
                val w = s.readInt(); val h = s.readInt(); val bg = s.readInt()
                val mask = ByteArray(w * h).also { s.readFully(it) }
                Entry(bitmap, keypad, mask, w, h, bg)
            }
            png.setLastModified(System.currentTimeMillis())
            synchronized(lock) { memKey = key; mem = entry }
            entry
        } catch (e: Exception) {
            png.delete(); bin.delete()
            null
        } catch (e: OutOfMemoryError) {
            null
        }
    }

    /** Keeps [entry] in memory and writes it to disk in the background. */
    fun put(context: Context, key: String, entry: Entry) {
        synchronized(lock) { memKey = key; mem = entry }
        val d = dir(context)
        Thread {
            try {
                val tmp = File(d, "$key.png.tmp")
                tmp.outputStream().use { entry.bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                DataOutputStream(File(d, "$key.bin").outputStream().buffered()).use { s ->
                    s.writeInt(entry.keypad.left); s.writeInt(entry.keypad.top); s.writeInt(entry.keypad.right); s.writeInt(entry.keypad.bottom)
                    s.writeInt(entry.maskWidth); s.writeInt(entry.maskHeight); s.writeInt(entry.backgroundColor)
                    s.write(entry.mask)
                }
                tmp.renameTo(File(d, "$key.png"))
                prune(d)
            } catch (e: Exception) {
                // a missing cache file only means the skin is drawn again next time
            }
        }.start()
    }

    private fun prune(d: File) {
        val pngs = d.listFiles { f -> f.name.endsWith(".png") }?.sortedByDescending { it.lastModified() } ?: return
        for (old in pngs.drop(KEEP)) {
            old.delete()
            File(d, old.name.removeSuffix(".png") + ".bin").delete()
        }
    }
}
