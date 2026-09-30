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
import java.io.File
import java.io.IOException

/**
 * Files that go over the calculator's link port: apps, programs and variables sent to it from the phone, and the
 * files it sends back (TI-89 family). Both wait in folders under the app's tmp folder.
 */
object LinkFiles {
    /** A file the calculator sent: [file] holds it until it is saved or discarded; [name] is its file name. */
    class Received(val file: File, val name: String)

    private fun dir(context: Context, name: String): File? = RomStore.tmpDir(context)?.let { File(it, name).apply { mkdirs() } }

    /**
     * Copies picked documents into the send folder under their own names (the native link code tells the file
     * type by its extension). Returns the copies to send and the names of the files [model] does not take.
     * Runs file I/O: call it off the main thread.
     */
    fun stageForSending(context: Context, model: CalcModel, uris: List<Uri>): Pair<List<File>, List<String>> {
        val folder = dir(context, "send") ?: return emptyList<File>() to uris.map { it.lastPathSegment ?: "file" }
        val staged = ArrayList<File>()
        val rejected = ArrayList<String>()
        for (uri in uris) {
            val name = RomStore.displayName(context, uri) ?: uri.lastPathSegment?.substringAfterLast('/') ?: "file"
            if (model.linkExtensions.none { name.endsWith(it, ignoreCase = true) }) {
                rejected += name
                continue
            }
            // each file in a folder of its own, so two files with the same name can be sent together
            val copy = File(File(folder, System.nanoTime().toString()).apply { mkdirs() }, name)
            try {
                val input = context.contentResolver.openInputStream(uri) ?: throw IOException("no stream")
                input.use { i -> copy.outputStream().use { o -> i.copyTo(o) } }
                staged += copy
            } catch (e: IOException) {
                copy.parentFile?.deleteRecursively()
                rejected += name
            }
        }
        return staged to rejected
    }

    /** Deletes a file after it was sent (with the folder [stageForSending] made for it). */
    fun sent(file: File) {
        file.parentFile?.deleteRecursively()
    }

    /**
     * Keeps a file the calculator just sent: [path] is reused for the next one, so the file moves to the received
     * folder. Called on the engine thread. Returns null when the file could not be kept.
     */
    fun keepReceived(context: Context, path: String, name: String): Received? {
        val source = File(path)
        val folder = dir(context, "received")
        if (folder == null) {
            source.delete()
            return null
        }
        // a variable without a name (only its type) still gets a usable file name
        val clean = name.replace('/', '_').trim().let { if (it.startsWith(".")) "noname$it" else it }.ifEmpty { "noname" }
        val kept = File(folder, "${System.nanoTime()}_$clean")
        if (!source.renameTo(kept)) {
            try {
                source.copyTo(kept, overwrite = true)
            } catch (e: IOException) {
                return null
            } finally {
                source.delete()
            }
        }
        return Received(kept, clean)
    }

    /** Writes [received] to [uri] (a document the user created) and deletes it. Returns false on failure. */
    fun save(context: Context, received: Received, uri: Uri): Boolean = try {
        val output = context.contentResolver.openOutputStream(uri) ?: throw IOException("no stream")
        output.use { o -> received.file.inputStream().use { i -> i.copyTo(o) } }
        received.file.delete()
        true
    } catch (e: IOException) {
        false
    }

    /** Deletes files left from an earlier run: sends that did not finish and received files never saved. */
    fun clear(context: Context) {
        RomStore.tmpDir(context)?.let { tmp ->
            File(tmp, "send").deleteRecursively()
            File(tmp, "received").deleteRecursively()
        }
    }
}
