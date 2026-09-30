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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.calc89.BuildConfig

/** A component in the app, with the licence it is used under (a text file in assets/licenses). */
private class Component(val name: String, val authors: String, val license: String, val file: String)

private val COMPONENTS = listOf(
    Component("Graph89", "Copyright (C) 2012-2013 Dritan Hashorva", "GNU GPL version 3", "GPL-3.0.txt"),
    Component("TilEm 2.0 (TI-83 and TI-84 emulation)", "Copyright (C) 2009-2012 Benjamin Moody", "GNU GPL version 3", "GPL-3.0.txt"),
    Component(
        "TiEmu 3.03 (TI-89 emulation)",
        "Copyright (C) 2000-2006 Thomas Corvazier, Romain Liévin, Julien Blache, Kevin Kofler",
        "GNU GPL version 2 or later", "GPL-2.0.txt",
    ),
    Component(
        "libticalcs2, libtifiles2, libticables2, libticonv",
        "Copyright (C) 1999-2006 Romain Liévin, Kevin Kofler",
        "GNU GPL version 2 or later", "GPL-2.0.txt",
    ),
    Component("GLib", "Copyright (C) The GLib team", "GNU LGPL version 2 or later", "LGPL-2.0.txt"),
    Component("AndroidX, Jetpack Compose, Kotlin", "Copyright (C) The Android Open Source Project, JetBrains", "Apache License 2.0", "Apache-2.0.txt"),
    Component("Roboto (key labels in the skins)", "Copyright (C) Google", "Apache License 2.0", "Apache-2.0.txt"),
    Component("Noto Sans Symbols (symbols in the skins)", "Copyright (C) Google", "SIL Open Font License 1.1", "OFL-1.1.txt"),
)

/** Version, the source code link, the TI disclaimer and the licences of everything in the app (GPL notices). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val uri = LocalUriHandler.current
    var shown by remember { mutableStateOf<Component?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("About") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).verticalScroll(rememberScrollState())) {
            val text = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
            Text("Graph89 Remastered ${BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.titleLarge, modifier = text)
            Text(
                "Based on Graph89 by Dritan Hashorva. This app is free software: you can redistribute it and/or modify it " +
                    "under the terms of the GNU General Public License version 3. It comes with ABSOLUTELY NO WARRANTY.",
                modifier = text,
            )
            Text(
                "Not affiliated with or endorsed by Texas Instruments. TI-83, TI-84 Plus, TI-89 and TI-89 Titanium are " +
                    "trademarks of Texas Instruments. The app does not include any Texas Instruments software: " +
                    "you supply the OS or ROM of your own calculator.",
                modifier = text,
            )
            if (BuildConfig.SOURCE_URL.isNotBlank()) {
                ListItem(
                    headlineContent = { Text("Source code") },
                    supportingContent = { Text(BuildConfig.SOURCE_URL) },
                    modifier = Modifier.clickable {
                        // no browser (or no app for the link): the address stays visible to copy by hand
                        try { uri.openUri(BuildConfig.SOURCE_URL) } catch (e: Exception) { }
                    },
                )
            }
            Text("Licences", style = MaterialTheme.typography.titleMedium, modifier = text.padding(top = 8.dp))
            COMPONENTS.forEach { c ->
                ListItem(
                    headlineContent = { Text(c.name) },
                    supportingContent = { Text("${c.authors}\n${c.license}") },
                    modifier = Modifier.clickable { shown = c },
                )
            }
        }
    }

    shown?.let { c ->
        val body = remember(c) {
            try {
                context.assets.open("licenses/${c.file}").bufferedReader().use { it.readText() }
            } catch (e: java.io.IOException) {
                "The licence text did not load."
            }
        }
        AlertDialog(
            onDismissRequest = { shown = null },
            title = { Text(c.license) },
            text = {
                Text(
                    body,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.sp,
                    modifier = Modifier.verticalScroll(rememberScrollState()),
                )
            },
            confirmButton = { TextButton(onClick = { shown = null }) { Text("Close") } },
        )
    }
}
