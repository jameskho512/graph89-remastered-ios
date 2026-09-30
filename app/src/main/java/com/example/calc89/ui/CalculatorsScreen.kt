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
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.calc89.core.CalcEntry
import com.example.calc89.core.CalcModel

/**
 * The installed calculators: tap one to show it, add a new one from an OS / ROM file, or remove one.
 * With [firstRun] (nothing installed yet) it is the app's first screen and explains what to do.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalculatorsScreen(
    calculators: List<CalcEntry>,
    activeId: String?,
    firstRun: Boolean,
    onSelect: (CalcEntry) -> Unit,
    onAdd: (CalcModel) -> Unit,
    onRemove: (CalcEntry) -> Unit,
    onBack: () -> Unit,
) {
    var choosingModel by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf<CalcEntry?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (firstRun) "Graph89 Remastered" else "Calculators") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).verticalScroll(rememberScrollState())) {
            if (firstRun) {
                Text(
                    "The app emulates TI graphing calculators. It does not include their operating system. " +
                        "Add a calculator and select an OS upgrade file or a ROM dump of your own calculator.",
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
            calculators.forEach { c ->
                val same = calculators.count { it.model == c.model } > 1
                ListItem(
                    headlineContent = { Text(if (same) "${c.model.label} (${c.id.substringAfterLast('-')})" else c.model.label) },
                    supportingContent = if (c.id == activeId) ({ Text("On screen") }) else null,
                    leadingContent = { if (c.id == activeId) Icon(Icons.Default.Check, contentDescription = null) },
                    trailingContent = {
                        IconButton(onClick = { removing = c }) { Icon(Icons.Default.Delete, contentDescription = "Remove") }
                    },
                    modifier = Modifier.clickable { onSelect(c) },
                )
            }
            ListItem(
                headlineContent = { Text("Add calculator") },
                supportingContent = { Text("Select the model, then its OS or ROM file.") },
                leadingContent = { Icon(Icons.Default.Add, contentDescription = null) },
                modifier = Modifier.clickable { choosingModel = true },
            )
        }
    }

    if (choosingModel) {
        AlertDialog(
            onDismissRequest = { choosingModel = false },
            title = { Text("Add calculator") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    CalcModel.entries.forEach { m ->
                        ListItem(
                            headlineContent = { Text(m.label) },
                            supportingContent = { Text("File: ${m.romFiles}") },
                            modifier = Modifier.clickable { choosingModel = false; onAdd(m) },
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { choosingModel = false }) { Text("Cancel") } },
        )
    }

    removing?.let { c ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text("Remove ${c.model.label}?") },
            text = { Text("The app deletes the ROM image and the saved state of this calculator. Files on the phone are not changed.") },
            confirmButton = { TextButton(onClick = { removing = null; onRemove(c) }) { Text("Remove") } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } },
        )
    }
}
