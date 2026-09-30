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
package com.example.calc89.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.example.calc89.core.CPU_SPEEDS
import com.example.calc89.core.HAPTIC_MAX_MS
import com.example.calc89.core.EmulatorConfig
import com.example.calc89.core.ScreenMargins
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    config: EmulatorConfig,
    maxScreenZoom: Int,
    onChange: (EmulatorConfig) -> Unit,
    canSetVibrationStrength: Boolean,
    onPreviewVibration: (ms: Int, strength: Int) -> Unit,
    onSyncClock: () -> Unit,
    onOpenSkinPicker: () -> Unit,
    onOpenCalculators: () -> Unit,
    onSendFiles: () -> Unit,
    onOpenAbout: () -> Unit,
    onReplaceRom: () -> Unit,
    onResetCalculator: () -> Unit,
    onBack: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).verticalScroll(rememberScrollState())) {
            SectionHeader("Appearance")
            ListItem(
                headlineContent = { Text("Skin and LCD") },
                supportingContent = { Text("${config.skin.label} skin, ${config.lcdTheme.label} LCD") },
                modifier = Modifier.clickable(onClick = onOpenSkinPicker),
            )

            SectionHeader("Screen")
            ChoiceSetting("Screen margins", ScreenMargins.entries, config.screenMargins, { it.label }) {
                onChange(config.copy(screenMargins = it))
            }
            SwitchSetting("Automatic screen size", null, config.screenScale <= 0) {
                onChange(config.copy(screenScale = if (it) -1 else maxScreenZoom))
            }
            if (config.screenScale > 0 && maxScreenZoom > 1) {
                SliderSetting("Screen scale", config.screenScale.coerceIn(1, maxScreenZoom), 1, maxScreenZoom, { "${it}x" }) {
                    onChange(config.copy(screenScale = it))
                }
            }
            SwitchSetting("Grayscale", "Some games and apps use grayscale. Grayscale decreases the speed.", config.grayscale) {
                onChange(config.copy(grayscale = it))
            }

            SectionHeader("Feedback")
            SliderSetting("Vibration", config.hapticMs, 0, HAPTIC_MAX_MS, { if (it == 0) "Off" else "$it ms" }, steps = HAPTIC_MAX_MS - 1) {
                onChange(config.copy(hapticMs = it))
                onPreviewVibration(it, config.hapticStrength)
            }
            SliderSetting(
                "Vibration strength", config.hapticStrength, 1, 100,
                { if (canSetVibrationStrength) "$it%" else "This phone vibrates at one strength only." },
                steps = 98, enabled = canSetVibrationStrength && config.hapticMs > 0,
            ) {
                onChange(config.copy(hapticStrength = it))
                onPreviewVibration(config.hapticMs, it)
            }
            SwitchSetting("Keypress audio", "The app makes a sound when you press a key.", config.audioFeedback) {
                onChange(config.copy(audioFeedback = it))
            }

            SectionHeader("Emulation")
            DropdownSetting(
                "CPU speed",
                CPU_SPEEDS,
                config.cpuSpeed,
                { speed ->
                    when (speed) {
                        100 -> "100% (default)"
                        CPU_SPEEDS.last() -> "$speed% (maximum)"
                        else -> "$speed%"
                    }
                },
            ) { onChange(config.copy(cpuSpeed = it)) }
            SwitchSetting("Save state on exit", null, config.saveStateOnExit) {
                onChange(config.copy(saveStateOnExit = it))
            }
            SwitchSetting("Exit when calculator turns off [2ND -> ON]", null, config.exitOnScreenOff) {
                onChange(config.copy(exitOnScreenOff = it))
            }
            SwitchSetting("Exit on double back", "Back opens the menu; Back again exits the app.", config.exitOnDoubleBack) {
                onChange(config.copy(exitOnDoubleBack = it))
            }

            SectionHeader("Calculator")
            ListItem(
                headlineContent = { Text("Calculators") },
                supportingContent = { Text("Switch, add or remove calculators.") },
                modifier = Modifier.clickable(onClick = onOpenCalculators),
            )
            ListItem(
                headlineContent = { Text("Send files") },
                supportingContent = { Text("Send programs, apps and variables to the calculator.") },
                modifier = Modifier.clickable(onClick = onSendFiles),
            )
            ListItem(
                headlineContent = { Text("Sync clock") },
                modifier = Modifier.clickable(onClick = onSyncClock),
            )
            ListItem(
                headlineContent = { Text("Replace ROM file") },
                supportingContent = { Text("Install a different .89u or .rom file. This clears the saved state.") },
                modifier = Modifier.clickable(onClick = onReplaceRom),
            )
            ListItem(
                headlineContent = { Text("Reset calculator", color = MaterialTheme.colorScheme.error) },
                supportingContent = { Text("Clear all RAM. This is the same as when you remove the batteries.") },
                modifier = Modifier.clickable(onClick = onResetCalculator),
            )

            SectionHeader("About")
            ListItem(
                headlineContent = { Text("About Graph89 Remastered") },
                modifier = Modifier.clickable(onClick = onOpenAbout),
            )
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 4.dp),
    )
}

@Composable
private fun SwitchSetting(title: String, summary: String?, checked: Boolean, onChange: (Boolean) -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = summary?.let { { Text(it) } },
        trailingContent = { Switch(checked = checked, onCheckedChange = onChange) },
        modifier = Modifier.clickable { onChange(!checked) },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SliderSetting(
    title: String, value: Int, min: Int, max: Int, label: (Int) -> String,
    steps: Int = 0, enabled: Boolean = true, onCommit: (Int) -> Unit,
) {
    var current by remember(value) { mutableFloatStateOf(value.toFloat()) }
    val interaction = remember { MutableInteractionSource() }
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = {
            Column {
                Text(label(current.roundToInt()))
                Slider(
                    value = current,
                    onValueChange = { current = it },
                    onValueChangeFinished = { onCommit(current.roundToInt()) },
                    valueRange = min.toFloat()..max.toFloat(),
                    enabled = enabled,
                    steps = steps,
                    interactionSource = interaction,
                    // thin style: round thumb on a thin track, no step ticks and no stop dot
                    thumb = { SliderDefaults.Thumb(interactionSource = interaction, enabled = enabled, thumbSize = DpSize(20.dp, 20.dp)) },
                    track = { state ->
                        SliderDefaults.Track(
                            sliderState = state, modifier = Modifier.height(4.dp), enabled = enabled,
                            drawStopIndicator = null, drawTick = { _, _ -> },
                            thumbTrackGapSize = 0.dp, trackInsideCornerSize = 2.dp,
                        )
                    },
                )
            }
        },
    )
}

/** Pick one value from a short list in a dropdown menu. */
@Composable
private fun <T> DropdownSetting(title: String, options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        ListItem(
            headlineContent = { Text(title) },
            supportingContent = { Text(label(selected)) },
            trailingContent = { Icon(Icons.Default.ArrowDropDown, contentDescription = null) },
            modifier = Modifier.clickable { open = true },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, offset = DpOffset(16.dp, 0.dp)) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(label(option)) },
                    onClick = { onSelect(option); open = false },
                    trailingIcon = if (option == selected) {
                        { Icon(Icons.Default.Check, contentDescription = null) }
                    } else {
                        null
                    },
                )
            }
        }
    }
}

@Composable
private fun <T> ChoiceSetting(title: String, options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(label(selected)) },
        modifier = Modifier.clickable { open = true },
    )
    if (open) {
        AlertDialog(
            onDismissRequest = { open = false },
            title = { Text(title) },
            text = {
                Column {
                    options.forEach { option ->
                        Row(
                            Modifier.clickable { onSelect(option); open = false },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = option == selected, onClick = { onSelect(option); open = false })
                            Text(label(option))
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { open = false }) { Text("Cancel") } },
        )
    }
}
