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
import android.net.Uri
import android.os.Environment
import android.provider.OpenableColumns
import java.io.File

/**
 * The installed calculators. Each has a folder (named by its id) with image.img and image.img.state;
 * calculators.txt lists them ("id model" per line) and "active <id>" names the one on screen.
 */
object RomStore {
    private const val BUNDLED_ID = "ti89t"
    private const val BUNDLED_ROM_ASSET = "rom/TI89Titanium_OS.89u"

    private fun root(context: Context): File? = context.getExternalFilesDir(null)
    private fun listFile(context: Context) = root(context)?.let { File(it, "calculators.txt") }

    fun tmpDir(context: Context): File? = root(context)?.let { File(it, "tmp").apply { mkdirs() } }
    fun isStorageAvailable() = Environment.getExternalStorageState() == Environment.MEDIA_MOUNTED

    // ---- calculator list ----

    fun calculators(context: Context): List<CalcEntry> = read(context).first

    fun active(context: Context): CalcEntry? {
        val (list, activeId) = read(context)
        return list.firstOrNull { it.id == activeId } ?: list.firstOrNull()
    }

    fun setActive(context: Context, id: String) {
        write(context, calculators(context), id)
    }

    private fun read(context: Context): Pair<List<CalcEntry>, String?> {
        val file = listFile(context) ?: return emptyList<CalcEntry>() to null
        if (!file.isFile) return emptyList<CalcEntry>() to null
        val list = ArrayList<CalcEntry>()
        var activeId: String? = null
        file.readLines().forEach { line ->
            val p = line.trim().split(" ")
            if (p.size != 2) return@forEach
            if (p[0] == "active") activeId = p[1]
            else CalcModel.entries.firstOrNull { it.name == p[1] }?.let { list.add(CalcEntry(p[0], it)) }
        }
        return list to activeId
    }

    private fun write(context: Context, list: List<CalcEntry>, activeId: String?) {
        val file = listFile(context) ?: return
        val lines = list.map { "${it.id} ${it.model.name}" } + listOfNotNull(activeId?.let { "active $it" })
        file.writeText(lines.joinToString("\n") + "\n")
    }

    // ---- files of a calculator (the active one unless given) ----

    fun folder(context: Context, id: String? = active(context)?.id): File? =
        id?.let { i -> root(context)?.let { File(it, i).apply { mkdirs() } } }

    fun image(context: Context, id: String? = active(context)?.id) = folder(context, id)?.let { File(it, "image.img") }
    fun state(context: Context, id: String? = active(context)?.id) = folder(context, id)?.let { File(it, "image.img.state") }
    fun hasRom(context: Context) = image(context)?.isFile == true

    /** True when this build carries a TI-89 Titanium OS (debug builds only; see app/src/debug/assets). */
    fun hasBundledRom(context: Context) = try {
        context.assets.list("rom")?.contains(BUNDLED_ROM_ASSET.substringAfter('/')) == true
    } catch (e: java.io.IOException) {
        false
    }

    /**
     * Checks a picked file before any native code parses it: a ROM dump must have the exact size of the
     * model's flash, an OS upgrade the model's extension. A file without a known extension (some file
     * providers drop it) counts as a dump when its size fits, otherwise as an OS upgrade.
     * Returns 0 and the file to install (renamed to the extension the native installer expects), or an error.
     */
    private fun checkFile(model: CalcModel, file: File): Pair<Int, File> {
        val name = file.name.lowercase()
        val size = file.length()
        val isOsName = model.osExtension?.let { name.endsWith(it) } == true
        val isDump = name.endsWith(".rom") || (!isOsName && size == model.romSize)
        if (isDump) {
            if (size != model.romSize) return 801 to file
            return 0 to rename(file, ".rom")
        }
        val os = model.osExtension ?: return 802 to file   // the TI-83 has no OS upgrades: only a dump works
        if (name.endsWith(".89u") || name.endsWith(".8xu") || name.endsWith(".v2u") || name.endsWith(".9xu")) {
            return (if (name.endsWith(os)) 0 else 802) to file
        }
        if (size < 64 * 1024 || size > 8 * 1024 * 1024) return 802 to file
        return 0 to rename(file, os)
    }

    private fun rename(file: File, ext: String): File {
        if (file.name.lowercase().endsWith(ext)) return file
        val to = File(file.parentFile, file.name + ext)
        return if (file.renameTo(to)) to else file
    }

    /** Builds image.img from an OS upgrade file or a .rom dump. Returns a native error code (0 = ok). */
    private fun install(context: Context, entry: CalcEntry, picked: File): Int {
        val (check, source) = checkFile(entry.model, picked)
        if (check != 0) return check
        val image = image(context, entry.id) ?: return 776
        // build next to the current image so a failed replacement keeps the working ROM
        val next = File(image.parentFile, "image.img.new")
        val isRom = if (source.name.lowercase().endsWith(".rom")) 1 else 0
        val error = try {
            EmulatorCore.nativeInstallROM(source.absolutePath, next.absolutePath, entry.model.type, isRom)
        } finally {
            if (source != picked) source.delete()
        }
        if (error == 0 && !(next.renameTo(image) || (image.delete() && next.renameTo(image)))) return 768
        if (error != 0) next.delete()
        if (error == 0) state(context, entry.id)?.delete() // a saved state belongs to the previous ROM
        return error
    }

    /** Builds the bundled TI-89 Titanium from the OS file in the APK. Returns a native error code. */
    fun installBundled(context: Context): Int {
        val tmp = tmpDir(context) ?: return 777
        val copy = File(tmp, "bundled.89u")
        try {
            context.assets.open(BUNDLED_ROM_ASSET).use { i -> copy.outputStream().use { o -> i.copyTo(o) } }
            val entry = CalcEntry(BUNDLED_ID, CalcModel.TI89T)
            val error = install(context, entry, copy)
            if (error == 0) {
                val list = calculators(context).filter { it.id != BUNDLED_ID }
                write(context, listOf(entry) + list, BUNDLED_ID)
            }
            return error
        } catch (e: java.io.IOException) {
            return 768
        } finally {
            copy.delete()
        }
    }

    /**
     * Copies a user-picked OS file / ROM dump into the tmp folder (the native installer needs a real file
     * path and checks the extension) and builds image.img from it for [entry]: an existing calculator
     * ("Replace ROM") or a new one, which is then added to the list and made active.
     */
    fun importFromUri(context: Context, uri: Uri, entry: CalcEntry? = active(context)): Int {
        val target = entry ?: return 772
        val tmp = tmpDir(context) ?: return 777
        val copy = File(tmp, "import_${displayName(context, uri) ?: "rom.bin"}")
        try {
            val input = context.contentResolver.openInputStream(uri) ?: return 768
            input.use { i -> copy.outputStream().use { o -> i.copyTo(o) } }
            val error = install(context, target, copy)
            val list = calculators(context)
            if (error == 0) {
                val updated = if (list.any { it.id == target.id }) list else list + target
                write(context, updated, target.id)
            } else if (list.none { it.id == target.id }) {
                folder(context, target.id)?.deleteRecursively() // a failed new calculator leaves nothing behind
            }
            return error
        } catch (e: java.io.IOException) {
            return 768
        } finally {
            copy.delete()
        }
    }

    /** The file name of a picked document (without any folder), or null when the provider does not say. */
    fun displayName(context: Context, uri: Uri): String? =
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0)?.let { n -> File(n).name }?.takeIf { n -> n.isNotBlank() } else null
        }

    /** A new, not yet installed calculator of [model] with a unique folder id. */
    fun newEntry(context: Context, model: CalcModel): CalcEntry {
        val taken = calculators(context).map { it.id }.toSet()
        val base = model.name.lowercase()
        var i = 1
        while ("$base-$i" in taken || root(context)?.let { File(it, "$base-$i").exists() } == true) i++
        return CalcEntry("$base-$i", model)
    }

    /** Deletes a calculator with its ROM image and saved state. */
    fun remove(context: Context, id: String) {
        val (list, activeId) = read(context)
        val rest = list.filter { it.id != id }
        write(context, rest, if (activeId == id) rest.firstOrNull()?.id else activeId)
        folder(context, id)?.deleteRecursively()
    }

    fun errorName(code: Int): String = when (code) {
        0 -> "ERR_NONE"
        768 -> "ERR_CANT_OPEN"
        770 -> "ERR_INVALID_IMAGE"
        771 -> "ERR_INVALID_UPGRADE"
        772 -> "ERR_NO_IMAGE"
        774 -> "ERR_INVALID_ROM_SIZE"
        775 -> "ERR_NOT_TI_FILE"
        776 -> "ERR_MALLOC"
        777 -> "ERR_CANT_OPEN_DIR"
        778 -> "ERR_CANT_UPGRADE"
        779 -> "ERR_INVALID_ROM"
        800 -> "The file type does not match this calculator"
        801 -> "The ROM dump has the wrong size for this calculator"
        802 -> "The file is not an OS upgrade for this calculator"
        -1 -> "The file could not be read"
        -2 -> "The file is not an OS upgrade for this calculator"
        -3 -> "The OS upgrade could not be loaded"
        else -> "Unknown error $code"
    }
}
