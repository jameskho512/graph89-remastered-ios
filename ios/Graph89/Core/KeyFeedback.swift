/*
 * Graph89 Remastered - TI graphing calculator emulator for iPhone
 * Copyright (C) 2026 JH
 * Based on Graph89, Copyright (C) 2012-2013 Dritan Hashorva (modified and rewritten in Swift, 2026).
 *
 * This program is free software: you can redistribute it and/or modify it under the terms of the
 * GNU General Public License as published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version. This program is distributed in the hope that it
 * will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License (LICENSE) for more details.
 */

import AudioToolbox
import AVFoundation
import CoreHaptics

/// Key vibration through the Taptic Engine: a tap at the chosen strength, held for the chosen time.
final class Haptics {
    private var engine: CHHapticEngine?
    private var players: [Int: CHHapticPatternPlayer] = [:]  // by time and strength

    /// True when the phone can vibrate at different strengths (every iPhone with a Taptic Engine).
    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// One key vibration of `ms` milliseconds at `strength` percent.
    func play(ms: Int, strength: Int) {
        guard ms > 0, supportsHaptics, let engine = startedEngine() else { return }
        let key = ms * 1000 + strength
        do {
            let player: CHHapticPatternPlayer
            if let p = players[key] {
                player = p
            } else {
                player = try engine.makePlayer(with: pattern(ms: ms, strength: strength))
                players[key] = player
            }
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            players.removeAll()  // the engine was reset: players are made again on the next press
        }
    }

    /// A crisp tap, then (for longer times) a buzz that lasts the rest of the time.
    private func pattern(ms: Int, strength: Int) throws -> CHHapticPattern {
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(min(max(strength, 1), 100)) / 100)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
        var events = [CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)]
        if ms > 10 {
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: Double(ms) / 1000))
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private func startedEngine() -> CHHapticEngine? {
        if let e = engine { return e }
        do {
            let e = try CHHapticEngine()
            e.playsHapticsOnly = true
            e.isAutoShutdownEnabled = true
            // after a reset (media server restart) or a stop the players are gone; they are made again on demand
            e.resetHandler = { [weak self] in
                self?.players.removeAll()
                try? self?.engine?.start()
            }
            e.stoppedHandler = { [weak self] _ in self?.players.removeAll() }
            try e.start()
            engine = e
            return e
        } catch {
            return nil
        }
    }
}

/// Key click sound: the iPhone keyboard's own click, played through the app's audio (so it also sounds when the
/// phone is on silent, like the Android app on vibrate). The system sound is the fallback.
final class KeyClick {
    private var players: [AVAudioPlayer] = []
    private var next = 0

    init() {
        let sample = Self.samplePaths.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isReadableFile(atPath: $0.path) }
        guard let url = sample else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        // a few players, so quick presses overlap instead of cutting each other off
        players = (0..<4).compactMap { _ in
            let p = try? AVAudioPlayer(contentsOf: url)
            p?.prepareToPlay()
            return p
        }
    }

    func play() {
        guard !players.isEmpty else {
            AudioServicesPlaySystemSound(1104)
            return
        }
        let p = players[next]
        next = (next + 1) % players.count
        p.currentTime = 0
        p.play()
    }

    private static let samplePaths = [
        "/System/Library/Audio/UISounds/key_press_click.caf",
        "/System/Library/Audio/UISounds/Tock.caf",
    ]
}
