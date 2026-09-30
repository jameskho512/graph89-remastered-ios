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

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.PagerDefaults
import androidx.compose.foundation.pager.PagerSnapDistance
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.calc89.core.CalcModel
import com.example.calc89.core.EmulatorConfig
import com.example.calc89.core.LcdColors
import com.example.calc89.core.LcdSnapshot
import com.example.calc89.core.LcdTheme
import com.example.calc89.core.SkinPreview
import com.example.calc89.core.SkinType
import com.example.calc89.core.customLcd
import com.example.calc89.core.lcd
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.absoluteValue
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Skin and LCD picker: a strip of LCD schemes at the top (Custom at the far left), a large preview of the
 * calculator in the middle and a strip of skins at the bottom. Both strips snap with the choice in the centre and
 * apply it at once. With the link on, a skin brings its LCD scheme and an LCD scheme brings its skin. The OLED
 * skin has a contrast slider.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SkinPickerScreen(
    config: EmulatorConfig,
    model: CalcModel,
    screen: LcdSnapshot?,
    viewWidth: Int,
    viewHeight: Int,
    onChange: (EmulatorConfig) -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val latestConfig by rememberUpdatedState(config)
    val scope = rememberCoroutineScope()

    // the skin being looked at
    var viewed by remember { mutableStateOf(config.skin) }
    var editCustom by remember { mutableStateOf(false) }
    var contrast by remember { mutableIntStateOf(config.oledContrast) }  // follows the slider while it moves
    val thumbs = remember(model) { mutableStateMapOf<SkinType, ImageBitmap>() }

    val skins = SkinType.entries
    val lcds = LcdTheme.entries
    val skinPager = rememberPagerState(initialPage = skins.indexOf(config.skin).coerceAtLeast(0)) { skins.size }
    val lcdPager = rememberPagerState(initialPage = lcds.indexOf(config.lcdTheme).coerceAtLeast(0)) { lcds.size }

    LaunchedEffect(model, config.skin3d, config.oledContrast) {  // thumbnails are cached, so only changed ones are drawn
        for (t in skins) {
            thumbs[t] = withContext(Dispatchers.Default) { SkinPreview.keypad(context, model, t, 360, 460, config.oledContrast, config.skin3d).asImageBitmap() }
        }
    }

    // a skin settled in the centre: apply it; with the link on, its LCD scheme too
    LaunchedEffect(skinPager) {
        // drop(1): the first value is the page the picker opened on, not a choice; acting on it would re-link
        // (and overwrite) the saved LCD just by opening the picker
        snapshotFlow { skinPager.settledPage }.drop(1).collect { i ->
            val t = skins[i]
            viewed = t
            var c = latestConfig.copy(skin = t)
            if (c.linkLcdToSkin) {
                val match = lcds.firstOrNull { it.name == t.name }
                if (match != null) {
                    c = c.copy(lcdTheme = match)
                    scrollTo(scope, lcdPager, lcds.indexOf(match))
                }
            }
            if (c != latestConfig) onChange(c)
        }
    }
    // an LCD scheme settled in the centre: apply it; with the link on, bring its skin to the centre too
    LaunchedEffect(lcdPager) {
        snapshotFlow { lcdPager.settledPage }.drop(1).collect { i ->
            val lcd = lcds[i]
            if (latestConfig.lcdTheme != lcd) onChange(latestConfig.copy(lcdTheme = lcd))
            if (latestConfig.linkLcdToSkin) {
                skins.firstOrNull { it.name == lcd.name }?.let { scrollTo(scope, skinPager, skins.indexOf(it)) }
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Skin and LCD") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            // ---- LCD schemes
            BoxWithConstraints(Modifier.fillMaxWidth().height(96.dp).padding(top = 8.dp)) {
                val itemW = 76.dp
                HorizontalPager(
                    state = lcdPager,
                    pageSize = PageSize.Fixed(itemW),
                    pageSpacing = 8.dp,
                    contentPadding = PaddingValues(horizontal = (maxWidth - itemW) / 2),
                    flingBehavior = PagerDefaults.flingBehavior(lcdPager, pagerSnapDistance = PagerSnapDistance.atMost(lcds.size)),
                    modifier = Modifier.fillMaxSize(),
                ) { i ->
                    val lcd = lcds[i]
                    val colors = if (lcd == LcdTheme.CUSTOM) customLcd(config.customLcdBackground, config.customLcdText)
                    else LcdColors(lcd.background, lcd.pixelOff, lcd.pixelOn)
                    LcdSwatch(lcd.label, colors, screen?.takeIf { it.width == model.lcdWidth }, custom = lcd == LcdTheme.CUSTOM, selected = i == lcdPager.currentPage, modifier = Modifier.carousel(lcdPager, i)) {
                        if (i == lcdPager.currentPage && lcd == LcdTheme.CUSTOM) editCustom = true
                        else scope.launch { lcdPager.animateScrollToPage(i) }
                    }
                }
            }

            // ---- link toggle, and the Custom editor when Custom is chosen
            Row(Modifier.fillMaxWidth().height(44.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconToggleButton(checked = config.linkLcdToSkin, onCheckedChange = { onChange(config.copy(linkLcdToSkin = it)) }) {
                    Icon(
                        if (config.linkLcdToSkin) Icons.Default.Link else Icons.Default.LinkOff,
                        contentDescription = if (config.linkLcdToSkin) "LCD linked to skin" else "LCD not linked to skin",
                        tint = if (config.linkLcdToSkin) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    "Match LCD and Keypad Skins",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
                if (config.lcdTheme == LcdTheme.CUSTOM) TextButton(onClick = { editCustom = true }) { Text("Edit custom") }
            }

            // ---- preview
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
                val aspect = viewWidth.toFloat() / viewHeight
                val density = LocalDensity.current
                val boxW = with(density) { minOf(maxWidth.toPx(), maxHeight.toPx() * aspect) }.toInt().coerceAtLeast(1)
                val boxH = (boxW / aspect).toInt().coerceAtLeast(1)
                var preview by remember { mutableStateOf<ImageBitmap?>(null) }
                val lcdColors = config.copy(oledContrast = contrast).lcd()  // live while the contrast slider moves
                LaunchedEffect(viewed, model, boxW, boxH, contrast, config.skin3d) {
                    preview = withContext(Dispatchers.Default) {
                        SkinPreview.calculator(context, model, viewed, boxW, boxH, viewWidth, viewHeight, config.screenScale, contrast, config.skin3d).asImageBitmap()
                    }
                }
                Box(Modifier.aspectRatio(aspect).clip(RoundedCornerShape(16.dp)).background(Color.Black), contentAlignment = Alignment.Center) {
                    preview?.let { Image(it, contentDescription = "Preview of ${viewed.label}", modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Fit) }
                        ?: CircularProgressIndicator()
                    // the LCD on top, drawn live: sharp at any size, and new colours are only a redraw
                    Canvas(Modifier.fillMaxSize()) {
                        val area = SkinPreview.lcdArea(model, size.width.roundToInt(), viewWidth, viewHeight, config.screenScale)
                        drawRect(Color(lcdColors.background), size = Size(size.width, area.bandHeight.toFloat()))
                        drawLcd(screen?.takeIf { it.width == model.lcdWidth && it.height == model.lcdHeight }, lcdColors, area.screen.left, area.screen.top, area.screen.width(), area.screen.height())
                    }
                }
            }

            // ---- status (OLED contrast or the skin's name) and the 3D switch, right above the skins
            Row(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                when {
                    viewed == SkinType.OLED -> Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Contrast", style = MaterialTheme.typography.bodyMedium)
                        Slider(
                            value = contrast.toFloat(),
                            onValueChange = { contrast = it.toInt() },
                            onValueChangeFinished = { onChange(latestConfig.copy(oledContrast = contrast)) },
                            valueRange = 20f..100f,
                            modifier = Modifier.weight(1f).padding(horizontal = 12.dp),
                        )
                        Text("$contrast%", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.width(44.dp))
                    }
                    else -> Text(viewed.label, style = MaterialTheme.typography.titleMedium)
                }
                }
                // 3D finish for any skin (keys only)
                Text("3D", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(start = 12.dp, end = 8.dp))
                Switch(checked = config.skin3d, onCheckedChange = { onChange(config.copy(skin3d = it)) })
            }

            // ---- skins
            BoxWithConstraints(Modifier.fillMaxWidth().height(180.dp).padding(bottom = 16.dp)) {
                val itemW = 124.dp
                HorizontalPager(
                    state = skinPager,
                    pageSize = PageSize.Fixed(itemW),
                    pageSpacing = 12.dp,
                    contentPadding = PaddingValues(horizontal = (maxWidth - itemW) / 2),
                    flingBehavior = PagerDefaults.flingBehavior(skinPager, pagerSnapDistance = PagerSnapDistance.atMost(skins.size)),
                    modifier = Modifier.fillMaxSize(),
                ) { i ->
                    val t = skins[i]
                    val centre = i == skinPager.currentPage
                    Box(
                        Modifier.fillMaxSize()
                            .carousel(skinPager, i)
                            .clip(RoundedCornerShape(16.dp))
                            .border(if (centre) 3.dp else 0.dp, if (centre) MaterialTheme.colorScheme.primary else Color.Transparent, RoundedCornerShape(16.dp))
                            .background(Color.DarkGray)
                            .clickable { scope.launch { skinPager.animateScrollToPage(i) } },
                    ) {
                        thumbs[t]?.let { Image(it, contentDescription = t.label, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
                        Row(
                            Modifier.align(Alignment.BottomStart).fillMaxWidth().background(Color(0xAA000000)).padding(horizontal = 8.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            if (t == config.skin) Icon(Icons.Default.Check, contentDescription = "In use", tint = Color.White, modifier = Modifier.size(14.dp))
                            Text(" ${t.label}", color = Color.White, style = MaterialTheme.typography.labelMedium, maxLines = 1)
                        }
                    }
                }
            }
        }
    }

    if (editCustom) {
        CustomLcdDialog(
            background = config.customLcdBackground,
            text = config.customLcdText,
            onDone = { bg, fg -> editCustom = false; onChange(latestConfig.copy(lcdTheme = LcdTheme.CUSTOM, customLcdBackground = bg, customLcdText = fg)) },
            onCancel = { editCustom = false },
        )
    }

}

private fun scrollTo(scope: kotlinx.coroutines.CoroutineScope, pager: PagerState, page: Int) {
    if (page >= 0 && pager.currentPage != page) scope.launch { pager.animateScrollToPage(page) }
}

/** Neighbours of the centred item shrink and fade. */
private fun Modifier.carousel(pager: PagerState, page: Int) = graphicsLayer {
    val distance = ((pager.currentPage - page) + pager.currentPageOffsetFraction).absoluteValue.coerceIn(0f, 1f)
    val s = 1f - 0.18f * distance
    scaleX = s; scaleY = s
    alpha = 1f - 0.45f * distance
}

/** An LCD colour scheme: the calculator's display in its colours (when there is one), and its name. */
@Composable
private fun LcdSwatch(label: String, lcd: LcdColors, screen: LcdSnapshot?, custom: Boolean, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = modifier.fillMaxSize().clickable(onClick = onClick)) {
        Box(
            Modifier.size(56.dp).clip(CircleShape).background(Color(lcd.background))
                .border(if (selected) 3.dp else 1.dp, if (selected) MaterialTheme.colorScheme.primary else Color.Gray, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            val w = 38.dp
            val h = if (screen != null) w * screen.height / screen.width else 24.dp
            Canvas(Modifier.size(w, h)) { drawLcd(screen, lcd, 0f, 0f, size.width, size.height) }
            if (custom) Icon(Icons.Default.Edit, contentDescription = null, tint = Color(lcd.pixelOn), modifier = Modifier.size(14.dp).align(Alignment.BottomCenter).padding(bottom = 2.dp))
        }
        Text(label, style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center, maxLines = 1, modifier = Modifier.padding(top = 4.dp))
    }
}

/**
 * The calculator's display [frame] in [lcd]'s colours, as one rectangle per run of equal pixels: drawn at the
 * screen's own resolution, so it is sharp at any size. When an LCD pixel covers at least one screen pixel the edges
 * snap to whole screen pixels (no seams, no blur); smaller, the pixels blend by coverage like a real miniature.
 */
private fun DrawScope.drawLcd(frame: LcdSnapshot?, lcd: LcdColors, left: Float, top: Float, width: Float, height: Float) {
    drawRect(Color(lcd.pixelOff), Offset(left, top), Size(width, height))
    frame ?: return
    val snap = width / frame.width >= 1f
    val xs = FloatArray(frame.width + 1) { (left + it * width / frame.width).let { v -> if (snap) floor(v) else v } }
    val ys = FloatArray(frame.height + 1) { (top + it * height / frame.height).let { v -> if (snap) floor(v) else v } }
    for (y in 0 until frame.height) {
        var x = 0
        while (x < frame.width) {
            val level = frame.level(x, y)
            var end = x + 1
            while (end < frame.width && frame.level(end, y) == level) end++
            if (level > 0) drawRect(Color(LcdSnapshot.color(level, lcd)), Offset(xs[x], ys[y]), Size(xs[end] - xs[x], ys[y + 1] - ys[y]))
            x = end
        }
    }
}

/**
 * Custom LCD: start from any preset (dropdown), then tap the background or text colour to change it on a colour
 * wheel. A preview shows the result, including the unlit pixels derived from the two colours.
 */
@Composable
internal fun CustomLcdDialog(background: Int, text: Int, onDone: (Int, Int) -> Unit, onCancel: () -> Unit) {
    var bg by remember { mutableIntStateOf(background) }
    var fg by remember { mutableIntStateOf(text) }
    var presets by remember { mutableStateOf(false) }
    var wheelFor by remember { mutableStateOf<String?>(null) }  // "bg" or "fg"

    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text("Custom LCD") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Box {
                    OutlinedButton(onClick = { presets = true }, modifier = Modifier.fillMaxWidth()) {
                        Text("Start from a preset", modifier = Modifier.weight(1f))
                        Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                    }
                    DropdownMenu(expanded = presets, onDismissRequest = { presets = false }) {
                        LcdTheme.entries.filter { it != LcdTheme.CUSTOM }.forEach { p ->
                            DropdownMenuItem(
                                text = { Text(p.label) },
                                leadingIcon = {
                                    Box(Modifier.size(24.dp).clip(CircleShape).background(Color(p.background)).border(1.dp, Color.Gray, CircleShape), contentAlignment = Alignment.Center) {
                                        Box(Modifier.size(8.dp).clip(CircleShape).background(Color(p.pixelOn)))
                                    }
                                },
                                onClick = { bg = p.background; fg = p.pixelOn; presets = false },
                            )
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                val lcd = customLcd(bg, fg)
                Box(Modifier.fillMaxWidth().height(64.dp).clip(RoundedCornerShape(8.dp)).background(Color(lcd.background)).padding(8.dp)) {
                    Box(Modifier.fillMaxSize().background(Color(lcd.pixelOff)).padding(horizontal = 8.dp), contentAlignment = Alignment.CenterStart) {
                        Text("2+3·4          14", color = Color(lcd.pixelOn), fontFamily = FontFamily.Monospace)
                    }
                }
                ColorRow("Background", bg) { wheelFor = "bg" }
                ColorRow("Text", fg) { wheelFor = "fg" }
            }
        },
        confirmButton = { TextButton(onClick = { onDone(bg, fg) }) { Text("Done") } },
        dismissButton = { TextButton(onClick = onCancel) { Text("Cancel") } },
    )

    wheelFor?.let { which ->
        ColorWheelDialog(
            title = if (which == "bg") "Background colour" else "Text colour",
            initial = if (which == "bg") bg else fg,
            onPick = { c -> if (which == "bg") bg = c else fg = c; wheelFor = null },
            onCancel = { wheelFor = null },
        )
    }
}

@Composable
private fun ColorRow(title: String, color: Int, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(top = 12.dp).clip(RoundedCornerShape(8.dp)).clickable(onClick = onClick).padding(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(Color(color)).border(1.dp, Color.Gray, CircleShape))
        Column(Modifier.padding(start = 12.dp).weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text("#%06X".format(color and 0xFFFFFF), style = MaterialTheme.typography.bodySmall)
        }
        Icon(Icons.Default.Edit, contentDescription = "Change $title colour")
    }
}

/**
 * Colour wheel: hue around the circle, saturation from the centre out, brightness on the slider. Hue, saturation
 * and brightness are kept separately, so a grey or black colour keeps its hue while it is being adjusted.
 */
@Composable
internal fun ColorWheelDialog(title: String, initial: Int, onPick: (Int) -> Unit, onCancel: () -> Unit) {
    val start = remember { FloatArray(3).also { android.graphics.Color.colorToHSV(initial, it) } }
    var hue by remember { mutableFloatStateOf(start[0]) }
    var sat by remember { mutableFloatStateOf(start[1]) }
    var value by remember { mutableFloatStateOf(start[2]) }
    val color = android.graphics.Color.HSVToColor(floatArrayOf(hue, sat, value))

    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(title) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                val hues = listOf(Color.Red, Color.Yellow, Color.Green, Color.Cyan, Color.Blue, Color.Magenta, Color.Red)
                Canvas(
                    Modifier.size(220.dp).pointerInput(Unit) {
                        awaitEachGesture {
                            fun pick(p: Offset) {
                                val cx = size.width / 2f; val cy = size.height / 2f
                                val dx = p.x - cx; val dy = p.y - cy
                                hue = ((Math.toDegrees(atan2(dy, dx).toDouble()) + 360) % 360).toFloat()
                                sat = (hypot(dx, dy) / min(cx, cy)).coerceIn(0f, 1f)
                            }
                            val down = awaitFirstDown()
                            pick(down.position)
                            do {
                                val event = awaitPointerEvent()
                                event.changes.forEach { if (it.pressed) { pick(it.position); it.consume() } }
                            } while (event.changes.any { it.pressed })
                        }
                    },
                ) {
                    val r = size.minDimension / 2
                    drawCircle(Brush.sweepGradient(hues), r)
                    drawCircle(Brush.radialGradient(listOf(Color.White, Color.White.copy(alpha = 0f)), center, r), r)
                    drawCircle(Color.Black.copy(alpha = 1f - value), r)
                    val a = Math.toRadians(hue.toDouble())
                    val m = Offset(center.x + (cos(a) * sat * r).toFloat(), center.y + (sin(a) * sat * r).toFloat())
                    drawCircle(Color(color), 11.dp.toPx(), m)
                    drawCircle(Color.White, 11.dp.toPx(), m, style = Stroke(3.dp.toPx()))
                    drawCircle(Color.Black, 13.dp.toPx(), m, style = Stroke(1.dp.toPx()))
                }
                Text("Brightness", style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 12.dp))
                Slider(value = value, onValueChange = { value = it }, valueRange = 0f..1f)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                    Box(Modifier.size(28.dp).clip(CircleShape).background(Color(color)).border(1.dp, Color.Gray, CircleShape))
                    Text("  #%06X".format(color and 0xFFFFFF), style = MaterialTheme.typography.bodyMedium)
                }
            }
        },
        confirmButton = { TextButton(onClick = { onPick(color) }) { Text("OK") } },
        dismissButton = { TextButton(onClick = onCancel) { Text("Cancel") } },
    )
}
