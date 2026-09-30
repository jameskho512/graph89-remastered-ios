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
import android.os.Handler
import android.os.Looper

/**
 * Runs a ROM install on a background thread for the whole process, not for one Activity: if the Activity is
 * recreated during an install (dark mode, font size ...), the new one still sees the install running (so it does
 * not start the calculator, which shares native state with the installer) and receives its result.
 */
object RomInstaller {
    /** True while an install runs; the calculator does not start meanwhile. */
    @Volatile var running = false
        private set

    /** Receives the result (native error code, 0 = ok) on the main thread; set by the Activity on screen. */
    var listener: ((Int) -> Unit)? = null
        set(value) {
            field = value
            // a result that arrived while no Activity was listening
            val waiting = pending
            if (value != null && waiting != null) { pending = null; value(waiting) }
        }

    private var pending: Int? = null
    private val main = Handler(Looper.getMainLooper())

    fun start(context: Context, install: (Context) -> Int) {
        if (running) return
        running = true
        val app = context.applicationContext
        Thread {
            val error = install(app)
            main.post {
                running = false
                listener?.invoke(error) ?: run { pending = error }
            }
        }.start()
    }
}
