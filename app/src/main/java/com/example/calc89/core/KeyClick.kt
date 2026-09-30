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
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import java.io.File

/**
 * Key click sound: the standard Android keyboard click.
 *
 * The system sample is played on the media stream through a SoundPool. The system effect itself
 * (AudioManager.playSoundEffect) uses the ring stream and is silent when the phone is on vibrate.
 * If the phone has no sample file, the system effect is the fallback.
 */
class KeyClick(context: Context) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val pool: SoundPool?
    private var soundId = 0
    @Volatile private var loaded = false

    init {
        val sample = SAMPLE_PATHS.map(::File).firstOrNull { it.canRead() }
        pool = sample?.let {
            SoundPool.Builder()
                .setMaxStreams(4)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .build()
                .also { p ->
                    p.setOnLoadCompleteListener { _, _, status -> loaded = status == 0 }
                    soundId = p.load(it.absolutePath, 1)
                }
        }
    }

    fun play() {
        if (pool == null) {
            audio.playSoundEffect(AudioManager.FX_KEYPRESS_STANDARD)
        } else if (loaded) {
            pool.play(soundId, 1f, 1f, 1, 0, 1f)
        }
    }

    fun release() {
        pool?.release()
    }

    private companion object {
        val SAMPLE_PATHS = listOf(
            "/product/media/audio/ui/KeypressStandard.ogg",
            "/system/media/audio/ui/KeypressStandard.ogg",
            "/system_ext/media/audio/ui/KeypressStandard.ogg",
            "/vendor/media/audio/ui/KeypressStandard.ogg",
            "/odm/media/audio/ui/KeypressStandard.ogg",
        )
    }
}
