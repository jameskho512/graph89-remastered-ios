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
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.View
import java.io.File

/**
 * Owns the running emulation: skin, the two worker threads (engine + LCD refresh) and key input.
 */
class EmulatorSession(private val context: Context) {
    @Volatile var isEmulating = false
        private set
    @Volatile var syncClock = false

    /** Set the clock once, a second after the calculator starts (after a new ROM, when the OS is booting). */
    @Volatile var syncClockAfterBoot = false
    @Volatile var resetCalc = false

    var config = EmulatorConfig()
    @Volatile var skin: Skin? = null
        private set

    /** The display as it was when the calculator last stopped (for the skin picker's previews). */
    @Volatile var lastScreen: LcdSnapshot? = null
        private set
    val keypad = KeyPad(this)

    /** Set by the UI; called from worker threads. */
    var view: View? = null
    var onError: (String) -> Unit = {}
    /** The saved state of the calculator did not load; the UI offers to discard it. */
    var onStateError: () -> Unit = {}
    var onExit: () -> Unit = {}
    var isFinishing: () -> Boolean = { false }

    /** The name of the file being sent to the calculator, then null when all are sent. */
    var onSending: (String?) -> Unit = {}
    /** Files the calculator did not take, with the native error code of each. */
    var onSendFailed: (List<String>) -> Unit = {}
    /** A file the calculator sent (TI-89 family), waiting to be saved. */
    var onFileReceived: (LinkFiles.Received) -> Unit = {}

    /** Files waiting to be sent: the engine sends them while the calculator runs. */
    @Volatile private var toSend: List<File> = emptyList()
    // its own lock: stop() holds the session's lock while it waits for the engine thread, which takes this one
    private val sendLock = Any()

    init {
        EmulatorCore.fileReceiver = { path, name -> LinkFiles.keepReceived(context, path, name)?.let { onFileReceived(it) } }
    }

    /** Sends [files] (copies made by [LinkFiles.stageForSending]) to the calculator, which must be running for it. */
    fun sendFiles(files: List<File>) {
        synchronized(sendLock) { toSend = toSend + files }
    }

    private var viewWidth = 0
    private var viewHeight = 0
    private var resumed = false

    /** A ROM install runs native code that shares global state with the engine: no start meanwhile. */
    @Volatile var installing = false
        @Synchronized set(value) {
            field = value
            if (!value) startIfReady()
        }

    /**
     * One start of the calculator. While [preparing] (the skin is being drawn) a stop only marks it [killed] and
     * does not wait: the thread notices and ends by itself, so the main thread never waits for a skin drawing.
     * Once the engine runs, a stop waits for it (the state is saved on the way out).
     */
    private class Run {
        @Volatile var killed = false
        var preparing = true  // guarded by the session's lock
        var thread: Thread? = null
        @Volatile var screenThread: Thread? = null
    }

    private var run: Run? = null
    @Volatile private var firstCycleComplete = false

    private var click: KeyClick? = null

    private val vibrator: Vibrator? = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator

    // ---- lifecycle ----

    @Synchronized
    fun resume() {
        resumed = true
        startIfReady()
    }

    @Synchronized
    fun pause() {
        resumed = false
        stop()
    }

    @Synchronized
    fun onViewSize(width: Int, height: Int) {
        if (run != null && (width != viewWidth || height != viewHeight)) stop()
        viewWidth = width
        viewHeight = height
        startIfReady()
    }

    /** The emulator view left the screen (menu, settings): stop, and forget its size until a new view reports one. */
    @Synchronized
    fun onViewDetached() {
        stop()
        viewWidth = 0
        viewHeight = 0
    }

    /** Deletes the saved state of the calculator on screen and starts it fresh. */
    @Synchronized
    fun discardStateAndRestart() {
        stop()
        RomStore.state(context)?.delete()
        startIfReady()
    }

    fun release() {
        click?.release()
        click = null
    }

    private fun startIfReady() {
        if (resumed && !installing && !RomInstaller.running && viewWidth > 0 && viewHeight > 0 && run == null) start(viewWidth, viewHeight)
    }

    /** The calculator being emulated (set when the emulation starts). */
    private var model = CalcModel.TI89T
    private val isTilem get() = model.engine == Engine.TILEM

    private fun start(width: Int, height: Int) {
        model = RomStore.active(context)?.model ?: CalcModel.TI89T
        val image = RomStore.image(context)
        val tmp = RomStore.tmpDir(context)
        if (image == null || tmp == null) {
            onError("Internal storage is not available.")
            return
        }
        if (!image.isFile) {
            onError("No ROM is installed.")
            return
        }

        keypad.reset()
        if (click == null) click = KeyClick(context)
        firstCycleComplete = false
        val cfg = config
        val r = Run()
        run = r
        // the skin is prepared on the engine thread, never on the main thread: a skin that has to be drawn
        // (not yet cached) takes a moment, and the app must not freeze meanwhile
        r.thread = Thread {
            val s = Skin(context, cfg.skin, model)
            try {
                s.init(width, height, cfg) { view?.postInvalidate() }
            } catch (e: Exception) {
                if (!r.killed) onError("The skin did not load.")
                return@Thread
            }
            // from here on a stop waits for this thread; a stop that came while drawing ends it here
            val go = synchronized(this) {
                if (r.killed) false else { r.preparing = false; skin = s; true }
            }
            if (!go) {
                s.release()
                return@Thread
            }
            view?.postInvalidate() // the keypad shows while the calculator loads
            val screen = s.screen!!
            EmulatorCore.nativeInitGraph89(
                model.type,
                screen.rawWidth, screen.rawHeight, screen.zoom,
                if (cfg.grayscale) 1 else 0, 0, // dot-matrix grid is not used
                s.lcdPixelOn, s.lcdPixelOff, s.lcdPixelOff,
                cfg.cpuSpeed / 100.0, tmp.absolutePath,
            )
            engineRun(r, image)
        }.also { it.start() }
    }

    @Synchronized
    fun stop() {
        val r = run ?: return
        run = null
        r.killed = true
        if (r.preparing) return  // still drawing the skin: it ends by itself, nothing native has started
        r.thread?.join()
        r.screenThread?.join()

        isEmulating = false
        skin?.let { s -> s.screen?.snapshot(s.lcdPixelOff, s.lcdPixelOn)?.let { lastScreen = it } }
        EmulatorCore.nativeCleanGraph89()
        EngineScreenParams.reset()
        skin?.release()
        skin = null
    }

    // ---- input ----

    fun sendKey(key: Int, active: Int, haptic: Boolean) {
        if (!isEmulating) return

        if (haptic) {
            if (config.hapticMs > 0) vibrate(config.hapticMs.toLong(), config.hapticStrength)
            if (config.audioFeedback) click?.play()
        }
        EmulatorCore.nativeSendKey(key, active)
    }

    /** One pulse, so the user can feel a vibration time or strength while choosing it. */
    fun previewVibration(ms: Int, strength: Int) {
        if (ms > 0) vibrate(ms.toLong(), strength)
    }

    /** True when the phone can vibrate at different strengths. */
    val hasAmplitudeControl: Boolean
        get() = Build.VERSION.SDK_INT >= 26 && vibrator?.hasAmplitudeControl() == true

    @Suppress("DEPRECATION")
    private fun vibrate(ms: Long, strength: Int) {
        val v = vibrator ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            val amplitude = if (v.hasAmplitudeControl()) (strength * 255 / 100).coerceIn(1, 255) else VibrationEffect.DEFAULT_AMPLITUDE
            v.vibrate(VibrationEffect.createOneShot(ms, amplitude))
        } else {
            v.vibrate(ms)
        }
    }

    // ---- engine thread ----

    private fun fail(message: String) = onError(message)

    private fun engineRun(r: Run, image: File) {
        try {
            if (isTilem) {
                val err = EmulatorCore.nativeTilemLoadImage(image.absolutePath)
                if (err != 0) return fail("The IMG file did not load. Error code: ${RomStore.errorName(err)}")
            } else {
                EmulatorCore.nativeTiEmuStep1LoadDefaultConfig()
                var err = EmulatorCore.nativeTiEmuStep2LoadImage(image.absolutePath)
                if (err != 0) return fail("The IMG file did not load. Error code: ${RomStore.errorName(err)}")
                err = EmulatorCore.nativeTiEmuStep3Init()
                if (err != 0) return fail("The initialization failed. Error code: ${RomStore.errorName(err)}")
                EmulatorCore.nativeTiEmuStep4Reset()
            }

            if (loadState() != 0) {
                if (RomStore.isStorageAvailable()) onStateError()
                else fail("The saved state did not load. Make sure that the internal storage is available.")
                return
            }

            if (isTilem) EmulatorCore.nativeTilemTurnScreenOn() else EmulatorCore.nativeTiEmuTurnScreenOn()

            val speedCoefficient = config.cpuSpeed / 100.0f
            r.screenThread = Thread { screenRun(r) }.also { it.start() }

            isEmulating = true
            view?.postInvalidate()

            var runCntr = 0
            val loopStart = System.currentTimeMillis()
            val sleepInterval = (ENGINE_LOOP_SLEEP / speedCoefficient).toInt()

            while (true) {
                ++runCntr

                if (r.killed) {
                    // don't save if the engine hasn't run for a second or so; it might corrupt the state
                    if (runCntr > 20) writeState()
                    break
                }

                if (resetCalc) {
                    if (isTilem) EmulatorCore.nativeTilemReset() else EmulatorCore.nativeTiEmuStep4Reset()
                    resetCalc = false
                }

                if (toSend.isNotEmpty()) sendQueued(r)

                val screen = skin?.screen ?: break

                if (syncClock || (syncClockAfterBoot && System.currentTimeMillis() - loopStart > BOOT_TIME_MS)) {
                    if (isTilem) EmulatorCore.nativeTilemSyncClock() else EmulatorCore.nativeTiEmuSyncClock()
                    syncClock = false
                    syncClockAfterBoot = false
                }

                runEngine()
                firstCycleComplete = true

                if (screen.isBusy()) {
                    // turbo while busy; one iteration takes about 4 ms
                    var i = 0
                    while (i < 30 && !r.killed && screen.isBusy()) {
                        runEngine()
                        ++i
                    }
                    Thread.sleep(1)
                } else {
                    Thread.sleep(sleepInterval.toLong())
                }
            }
        } catch (_: InterruptedException) {
        }
    }

    /** Sends the queued files one after another (each transfer runs the calculator itself until it is done). */
    private fun sendQueued(r: Run) {
        val files = synchronized(sendLock) { toSend.also { toSend = emptyList() } }
        val failed = ArrayList<String>()
        for (f in files) {
            if (r.killed) {
                LinkFiles.sent(f)  // the activity is going away: the rest is dropped
                continue
            }
            onSending(f.name)
            val code = if (isTilem) EmulatorCore.nativeTilemUploadFile(f.absolutePath) else EmulatorCore.nativeTiEmuUploadFile(f.absolutePath)
            if (code != 0) failed += "${f.name} (error $code)"
            LinkFiles.sent(f)
        }
        onSending(null)
        if (failed.isNotEmpty()) onSendFailed(failed)
    }

    private fun runEngine() {
        if (isTilem) EmulatorCore.nativeTilemRunEngine() else EmulatorCore.nativeTiEmuRunEngine()
    }

    private fun screenRun(r: Run) {
        var prevScreenOff = true

        while (!r.killed) {
            try {
                val screen = skin?.screen ?: return
                screen.refresh()
                val screenOff = screen.isScreenOff()

                if (firstCycleComplete && !r.killed && config.exitOnScreenOff && !prevScreenOff && screenOff) {
                    onExit()
                }
                prevScreenOff = screenOff
                Thread.sleep(SCREEN_LOOP_SLEEP)
            } catch (_: InterruptedException) {
                return
            }
        }
    }

    private fun loadState(): Int {
        val image = RomStore.image(context)
        val state = RomStore.state(context)
        if (!RomStore.isStorageAvailable() || image?.isFile != true || state == null) return -1
        if (!state.isFile) return 0
        return if (isTilem) EmulatorCore.nativeTilemLoadState(state.absolutePath) else EmulatorCore.nativeTiEmuLoadState(state.absolutePath)
    }

    private fun writeState() {
        val state = RomStore.state(context) ?: return
        if (config.saveStateOnExit && RomStore.isStorageAvailable() && !isFinishing()) {
            if (isTilem) RomStore.image(context)?.let { EmulatorCore.nativeTilemSaveState(it.absolutePath, state.absolutePath) }
            else EmulatorCore.nativeTiEmuSaveState(state.absolutePath)
        }
    }

    private companion object {
        const val ENGINE_LOOP_SLEEP = 30
        const val SCREEN_LOOP_SLEEP = 50L
        const val BOOT_TIME_MS = 1000L
    }
}

/** Multi-touch key tracking: which key each finger holds. */
class KeyPad(private val session: EmulatorSession) {
    private val pressed = ArrayList<KeyPress>()
    var onChanged: () -> Unit = {}

    fun reset() {
        pressed.clear()
    }

    fun press(key: KeyPress) {
        if (isInvalid(key.keyCode)) return
        val found = pressed.any { it.keyCode == key.keyCode || it.touchId == key.touchId }
        if (!found) {
            pressed.add(key)
            session.sendKey(key.keyCode, 1, true)
        }
        onChanged()
    }

    fun unpress(touchId: Int) {
        val i = pressed.indexOfFirst { it.touchId == touchId }
        if (i < 0) return
        session.sendKey(pressed[i].keyCode, 0, false)
        onChanged()
        pressed.removeAt(i)
    }

    fun unpressAll() {
        pressed.forEach { session.sendKey(it.keyCode, 0, false) }
        pressed.clear()
        onChanged()
    }

    fun pressedKeys(): List<KeyPress> = pressed.toList()

    private fun isInvalid(code: Int) = code < 0 || code >= 255
}
