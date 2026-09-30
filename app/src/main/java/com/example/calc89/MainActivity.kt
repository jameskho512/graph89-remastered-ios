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
package com.example.calc89

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.RoundedCorner
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.example.calc89.core.CalcEntry
import com.example.calc89.core.CalcModel
import com.example.calc89.core.EmulatorConfig
import com.example.calc89.core.Engine
import com.example.calc89.core.EmulatorSession
import com.example.calc89.core.LinkFiles
import com.example.calc89.core.RomInstaller
import com.example.calc89.core.RomStore
import com.example.calc89.core.ScreenMargins
import com.example.calc89.core.Skin
import com.example.calc89.core.SkinCache
import com.example.calc89.data.SettingsRepository
import com.example.calc89.ui.EmulatorView
import com.example.calc89.ui.Graph89Theme
import com.example.calc89.ui.AboutScreen
import com.example.calc89.ui.CalculatorsScreen
import com.example.calc89.ui.MenuSheet
import com.example.calc89.ui.SettingsScreen
import com.example.calc89.ui.SkinPickerScreen
import kotlin.math.ceil
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

class MainActivity : ComponentActivity() {
    private lateinit var session: EmulatorSession
    private lateinit var settings: SettingsRepository

    private var config by mutableStateOf(EmulatorConfig())
    private var errorMessage by mutableStateOf<String?>(null)

    private var romInstalled by mutableStateOf(false)
    private var installing by mutableStateOf(false)
    private var stateError by mutableStateOf(false)

    private var menuOpen by mutableStateOf(false)
    private var confirmReset by mutableStateOf(false)
    private var showSettings by mutableStateOf(false)
    private var showCalculators by mutableStateOf(false)
    private var showAbout by mutableStateOf(false)
    private var showSkinPicker by mutableStateOf(false)
    private var calculators by mutableStateOf<List<CalcEntry>>(emptyList())
    private var activeId by mutableStateOf<String?>(null)
    /** The calculator on screen (read from storage in refreshCalculators, not while drawing). */
    private var activeModel by mutableStateOf(CalcModel.TI89T)
    /** A calculator being added: the file picker result installs into it. */
    private var pendingNew: CalcEntry? = null

    /** The file being sent to the calculator (a progress dialog shows meanwhile). */
    private var sendingFile by mutableStateOf<String?>(null)
    /** Files the calculator sent, waiting to be saved or discarded (the first one is offered). */
    private val received = mutableStateListOf<LinkFiles.Received>()
    /** The received file whose "save as" picker is open. */
    private var saving: LinkFiles.Received? = null

    // Display geometry that hides the edges of the screen, in pixels (reported by the window insets).
    private var cornerRadiusPx by mutableIntStateOf(0)
    private var cutoutTopPx by mutableIntStateOf(0)
    private var gestureBottomPx by mutableIntStateOf(0)

    private var lastHaptic = 5

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        trackDisplayEdges()

        SkinCache.wipeIfNewBuild(this)
        settings = SettingsRepository(applicationContext)
        config = runBlocking { settings.config.first() }
        refreshCalculators()
        lastHaptic = if (config.hapticMs > 0) config.hapticMs else 5

        session = EmulatorSession(this).apply {
            this.config = this@MainActivity.config
            onError = { message -> runOnUiThread { errorMessage = message } }
            onStateError = { runOnUiThread { stateError = true } }
            onExit = { runOnUiThread { exitApp() } } // [2nd] [OFF]: save like the menu's Exit
            isFinishing = { this@MainActivity.isFinishing }
            onSending = { name -> runOnUiThread { sendingFile = name } }
            onSendFailed = { files ->
                runOnUiThread {
                    errorMessage = "The calculator did not take:\n${files.joinToString("\n")}\n\nShow the home screen on the calculator and try again."
                }
            }
            onFileReceived = { file -> runOnUiThread { received.add(file) } }
        }
        // files left from an earlier run (a send cut short, received files never saved)
        if (savedInstanceState == null) LinkFiles.clear(this)
        // a new calculator being added survives the activity being recreated while the file picker is open
        savedInstanceState?.getString(KEY_PENDING)?.let { saved ->
            val (id, model) = saved.split(' ')
            CalcModel.entries.firstOrNull { it.name == model }?.let { pendingNew = CalcEntry(id, it) }
        }
        installing = RomInstaller.running
        if (installing) session.installing = true
        RomInstaller.listener = installListener
        if (!romInstalled && calculators.isEmpty() && !installing && RomStore.hasBundledRom(this)) installRom { RomStore.installBundled(it) }

        setContent {
            Graph89Theme {
                val pickRom = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
                    val target = pendingNew
                    pendingNew = null
                    if (uri != null) installRom { RomStore.importFromUri(it, uri, target ?: RomStore.active(it)) }
                }
                val pickFilesToSend = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
                    if (uris.isNotEmpty()) sendFiles(uris)
                }
                val saveReceived = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
                    val file = saving
                    saving = null
                    if (file != null && uri != null) saveReceivedFile(file, uri)
                }

                when {
                    !romInstalled || showCalculators -> {
                        // with no calculator installed this is the first screen, and Back leaves the app
                        val firstRun = !romInstalled
                        BackHandler { if (firstRun) finish() else showCalculators = false }
                        Framed {
                            CalculatorsScreen(
                                calculators = calculators,
                                activeId = activeId,
                                firstRun = firstRun,
                                onSelect = { c -> selectCalculator(c) },
                                onAdd = { model -> pendingNew = RomStore.newEntry(this, model); pickRom.launch(arrayOf("*/*")) },
                                onRemove = { c -> removeCalculator(c) },
                                onBack = { if (firstRun) finish() else showCalculators = false },
                            )
                        }
                    }

                    showAbout -> {
                        BackHandler { showAbout = false }
                        Framed {
                            AboutScreen(onBack = { showAbout = false })
                        }
                    }

                    showSkinPicker -> {
                        BackHandler { showSkinPicker = false }
                        val m = edgeMargins(config.screenMargins)
                        Framed {
                            SkinPickerScreen(
                                config = config,
                                model = activeModel,
                                screen = session.lastScreen,
                                viewWidth = resources.displayMetrics.widthPixels - m[0] - m[2],
                                viewHeight = resources.displayMetrics.heightPixels - m[1] - m[3],
                                onChange = { updated -> updateConfig(updated) },
                                onBack = { showSkinPicker = false },
                            )
                        }
                    }

                    showSettings -> {
                        BackHandler { closeSettings() }
                        Framed {
                            SettingsScreen(
                                config = config,
                                maxScreenZoom = maxScreenZoom(),
                                onChange = { updated -> updateConfig(updated) },
                                canSetVibrationStrength = session.hasAmplitudeControl,
                                onPreviewVibration = { ms, strength -> session.previewVibration(ms, strength) },
                                onSyncClock = { syncClock() },
                                onOpenSkinPicker = { showSkinPicker = true },
                                onOpenCalculators = { refreshCalculators(); showCalculators = true },
                                // Settings closes first: the files go as soon as the calculator runs again, back from the picker
                                onSendFiles = { closeSettings(); pickFilesToSend.launch(arrayOf("*/*")) },
                                onOpenAbout = { showAbout = true },
                                onReplaceRom = { pickRom.launch(arrayOf("*/*")) },
                                onResetCalculator = { confirmReset = true },
                                onBack = { closeSettings() },
                            )
                        }
                    }

                    else -> {
                        val density = LocalDensity.current
                        val m = edgeMargins(config.screenMargins)
                        val padding = with(density) { PaddingValues(m[0].toDp(), m[1].toDp(), m[2].toDp(), m[3].toDp()) }
                        Box(Modifier.fillMaxSize().background(Color.Black).padding(padding)) {
                            AndroidView(factory = { EmulatorView(it, session) }, modifier = Modifier.fillMaxSize())
                        }
                        BackHandler(enabled = !menuOpen) { openMenu() }
                        if (menuOpen) {
                            MenuSheet(
                                exitOnBack = config.exitOnDoubleBack,
                                onSettings = { openSettings() },
                                onExit = { exitApp() },
                                onDismiss = { menuOpen = false },
                            )
                        }
                    }
                }

                if (confirmReset) {
                    AlertDialog(
                        onDismissRequest = { confirmReset = false },
                        title = { Text("Reset the calculator?") },
                        text = {
                            val tilem = activeModel.engine == Engine.TILEM
                            Text(
                                if (tilem) "The reset clears all RAM and also erases the archive and all apps. Only the OS stays. You cannot undo this."
                                else "The reset clears all RAM. You lose all data that is not in the archive. This is the same as when you remove the batteries.",
                            )
                        },
                        confirmButton = { TextButton(onClick = { confirmReset = false; resetCalculator() }) { Text("Reset") } },
                        dismissButton = { TextButton(onClick = { confirmReset = false }) { Text("Cancel") } },
                    )
                }

                if (stateError) {
                    AlertDialog(
                        onDismissRequest = {},  // the calculator cannot run until one of the two is chosen
                        title = { Text("The saved state did not load") },
                        text = { Text("The saved state of this calculator is damaged or belongs to a different ROM. Discard it to start the calculator fresh, or close the app and keep the file. The ROM and the archive stay.") },
                        confirmButton = { TextButton(onClick = { stateError = false; session.discardStateAndRestart() }) { Text("Discard state") } },
                        dismissButton = { TextButton(onClick = { stateError = false; finish() }) { Text("Close app") } },
                    )
                }

                if (installing) {
                    AlertDialog(
                        onDismissRequest = {},
                        confirmButton = {},
                        text = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                CircularProgressIndicator()
                                Text("Installing the ROM", modifier = Modifier.padding(start = 16.dp))
                            }
                        },
                    )
                }

                sendingFile?.let { name ->
                    AlertDialog(
                        onDismissRequest = {},  // a transfer cannot be stopped halfway
                        confirmButton = {},
                        text = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                CircularProgressIndicator()
                                Text("Sending $name", modifier = Modifier.padding(start = 16.dp))
                            }
                        },
                    )
                }

                received.firstOrNull()?.let { file ->
                    AlertDialog(
                        onDismissRequest = {},
                        title = { Text("File received") },
                        text = { Text("The calculator sent ${file.name}. Save it on the phone?") },
                        confirmButton = { TextButton(onClick = { saving = file; saveReceived.launch(file.name) }) { Text("Save") } },
                        dismissButton = { TextButton(onClick = { file.file.delete(); received.remove(file) }) { Text("Discard") } },
                    )
                }

                errorMessage?.let { message ->
                    AlertDialog(
                        onDismissRequest = { errorMessage = null },
                        title = { Text("Error") },
                        text = { Text(message) },
                        confirmButton = { TextButton(onClick = { errorMessage = null }) { Text("OK") } },
                    )
                }
            }
        }
    }

    // ---- display edges (rounded corners, camera cutout) ----

    /**
     * Full screens (Settings, Skin and LCD, Calculators, About) keep the same edge margins as the calculator.
     * The margins are applied here, so the insets are consumed and the screens' own bars add nothing on top.
     */
    @Composable
    private fun Framed(content: @Composable () -> Unit) {
        val m = edgeMargins(config.screenMargins)
        val padding = with(LocalDensity.current) { PaddingValues(m[0].toDp(), m[1].toDp(), m[2].toDp(), m[3].toDp()) }
        Box(Modifier.fillMaxSize().background(Color.Black).padding(padding).consumeWindowInsets(WindowInsets.safeDrawing)) { content() }
    }

    private fun trackDisplayEdges() {
        window.decorView.setOnApplyWindowInsetsListener { v, insets ->
            if (Build.VERSION.SDK_INT >= 31) {
                cornerRadiusPx = intArrayOf(
                    RoundedCorner.POSITION_TOP_LEFT, RoundedCorner.POSITION_TOP_RIGHT,
                    RoundedCorner.POSITION_BOTTOM_LEFT, RoundedCorner.POSITION_BOTTOM_RIGHT,
                ).maxOf { insets.getRoundedCorner(it)?.radius ?: 0 }
            }
            if (Build.VERSION.SDK_INT >= 28) cutoutTopPx = insets.displayCutout?.safeInsetTop ?: 0
            // the area at the bottom for the home swipe, also when the system bars are hidden
            val compat = WindowInsetsCompat.toWindowInsetsCompat(insets, v)
            gestureBottomPx = maxOf(
                compat.getInsetsIgnoringVisibility(WindowInsetsCompat.Type.navigationBars()).bottom,
                compat.getInsets(WindowInsetsCompat.Type.systemGestures()).bottom,
            )
            v.onApplyWindowInsets(insets)
        }
    }

    /**
     * Margins (left, top, right, bottom) in px. A rounded corner of radius r hides nothing beyond the
     * point (m, m) when m = r * (1 - 1 / sqrt 2). That is the margin on every side for the corner modes.
     * Auto also moves the top below the camera cutout. Camera only uses the cutout and no corner margin.
     * Every mode except None keeps the bottom area for the home swipe free.
     */
    private fun edgeMargins(mode: ScreenMargins): IntArray {
        if (mode == ScreenMargins.NONE) return intArrayOf(0, 0, 0, 0)
        if (mode == ScreenMargins.CAMERA) return intArrayOf(0, cutoutTopPx, 0, gestureBottomPx)
        val corner = if (cornerRadiusPx > 0) ceil(cornerRadiusPx * 0.2929f).toInt() + 2 else 0
        val top = if (mode == ScreenMargins.AUTO) maxOf(corner, cutoutTopPx) else corner
        return intArrayOf(corner, top, corner, maxOf(corner, gestureBottomPx))
    }

    private fun maxScreenZoom(): Int {
        val m = edgeMargins(config.screenMargins)
        val width = resources.displayMetrics.widthPixels - m[0] - m[2]
        return (width / activeModel.lcdWidth).coerceAtLeast(1)
    }

    // ---- settings and menu actions ----

    private fun updateConfig(updated: EmulatorConfig) {
        config = updated
        settings.saveAsync(updated)
    }

    /** Haptics and click sound are read live, so quick toggles apply without restarting the calculator. */
    private fun updateFeedback(updated: EmulatorConfig) {
        updateConfig(updated)
        session.config = session.config.copy(hapticMs = updated.hapticMs, hapticStrength = updated.hapticStrength, audioFeedback = updated.audioFeedback)
    }

    private fun toggleVibration() {
        if (config.hapticMs > 0) {
            lastHaptic = config.hapticMs
            updateFeedback(config.copy(hapticMs = 0))
        } else {
            updateFeedback(config.copy(hapticMs = lastHaptic))
        }
    }

    private fun openMenu() {
        session.keypad.unpressAll()
        menuOpen = true
    }

    private fun openSettings() {
        menuOpen = false
        session.keypad.unpressAll()
        session.stop() // settings are applied by starting the emulation again with the new values
        showSettings = true
    }

    private fun refreshCalculators() {
        calculators = RomStore.calculators(this).filter { RomStore.image(this, it.id)?.isFile == true }
        val active = RomStore.active(this)
        activeId = active?.id
        activeModel = active?.model ?: CalcModel.TI89T
        romInstalled = RomStore.hasRom(this)
    }

    private fun selectCalculator(c: CalcEntry) {
        RomStore.setActive(this, c.id)
        refreshCalculators()
        showCalculators = false
    }

    private fun removeCalculator(c: CalcEntry) {
        RomStore.remove(this, c.id)
        refreshCalculators()
        // the bundled TI-89 Titanium comes back when no calculator is left
        if (calculators.isEmpty() && RomStore.hasBundledRom(this)) installRom { RomStore.installBundled(it) }
    }

    /** Copies the picked files off the main thread, then queues those the calculator takes for sending. */
    private fun sendFiles(uris: List<android.net.Uri>) {
        val model = activeModel
        Thread {
            val (files, rejected) = LinkFiles.stageForSending(this, model, uris)
            runOnUiThread {
                if (files.isNotEmpty()) session.sendFiles(files)
                if (rejected.isNotEmpty()) {
                    errorMessage = "The ${model.label} does not take:\n${rejected.joinToString("\n")}\n\n" +
                        "It takes ${model.linkExtensions.sorted().joinToString(" ")} files."
                }
            }
        }.start()
    }

    private fun saveReceivedFile(file: LinkFiles.Received, uri: android.net.Uri) {
        Thread {
            val ok = LinkFiles.save(this, file, uri)
            runOnUiThread {
                if (ok) {
                    received.remove(file)
                    Toast.makeText(this, "${file.name} is saved.", Toast.LENGTH_SHORT).show()
                } else {
                    errorMessage = "${file.name} could not be saved. Try another folder."
                }
            }
        }.start()
    }

    private fun closeSettings() {
        session.config = config
        showSettings = false
    }

    /** The engine is stopped while Settings is open, so both actions run when the calculator starts again. */
    private fun syncClock() {
        session.syncClock = true
        closeSettings()
        Toast.makeText(this, "The clock is synchronized.", Toast.LENGTH_SHORT).show()
    }

    private fun resetCalculator() {
        session.resetCalc = true
        closeSettings()
    }

    private fun exitApp() {
        menuOpen = false
        session.stop() // saves the state (unless disabled) while the activity is not yet finishing
        finish()
    }

    /** Bundled ROM on first launch, user import and "Replace ROM": a failed install keeps the previous ROM. */
    private fun installRom(install: (Context) -> Int) {
        if (RomInstaller.running) return
        installing = true
        session.stop()
        session.installing = true
        RomInstaller.start(this, install)
    }

    /** The result of an install, also one that a previous instance of this Activity started. */
    private val installListener: (Int) -> Unit = { error ->
        installing = false
        refreshCalculators()
        if (error == 0) {
            showCalculators = false
            session.syncClockAfterBoot = true // a new ROM starts with the default date; the engine sets the clock once
            Toast.makeText(this, "The ROM is installed.", Toast.LENGTH_SHORT).show()
        } else {
            errorMessage = "The ROM installation failed. Error: ${RomStore.errorName(error)}"
        }
        // the engine starts again once the calculator is on screen and the activity is resumed
        session.installing = false
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        pendingNew?.let { outState.putString(KEY_PENDING, "${it.id} ${it.model.name}") }
    }

    override fun onResume() {
        super.onResume()
        hideSystemBars()
        session.resume()
    }

    override fun onStop() {
        super.onStop()
        session.pause()
    }

    override fun onDestroy() {
        super.onDestroy()
        session.release()
        if (RomInstaller.listener === installListener) RomInstaller.listener = null
    }

    private companion object {
        const val KEY_PENDING = "pending_new_calculator"
    }

    private fun hideSystemBars() {
        WindowInsetsControllerCompat(window, window.decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }
}
