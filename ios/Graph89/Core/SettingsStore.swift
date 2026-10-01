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

import Foundation

/// The settings, kept in UserDefaults under the Android app's preference keys.
final class SettingsStore {
    private enum Keys {
        static let haptic = "haptic_ms"
        static let hapticStrength = "haptic_strength"
        static let audio = "audio_feedback"
        static let scale = "screen_scale"
        static let skin = "skin"
        static let grayscale = "grayscale"
        static let saveState = "save_state_on_exit"
        static let cpu = "cpu_speed"
        static let exitOnOff = "exit_on_screen_off"
        static let lcdTheme = "lcd_theme"
        static let customLcdBg = "custom_lcd_background"
        static let customLcdText = "custom_lcd_text"
        static let linkLcd = "link_lcd_to_skin"
        static let oledContrast = "oled_contrast"
        static let skin3d = "skin_3d"
        static let margins = "screen_margins"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> EmulatorConfig {
        let d = EmulatorConfig()
        // integer(forKey:) and bool(forKey:) also read the strings of launch arguments ("-skin_3d YES", for tests)
        func int(_ key: String) -> Int? { defaults.object(forKey: key) == nil ? nil : defaults.integer(forKey: key) }
        func bool(_ key: String) -> Bool? { defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key) }
        func string(_ key: String) -> String? { defaults.string(forKey: key) }
        func color(_ key: String) -> ARGB? { int(key).map { ARGB(truncatingIfNeeded: $0) } }
        return EmulatorConfig(
            hapticMs: int(Keys.haptic).map(nearestHaptic) ?? d.hapticMs,
            hapticStrength: int(Keys.hapticStrength).map { min(max($0, 1), 100) } ?? d.hapticStrength,
            audioFeedback: bool(Keys.audio) ?? d.audioFeedback,
            screenScale: int(Keys.scale) ?? d.screenScale,
            skin: string(Keys.skin).flatMap(SkinType.init(rawValue:)) ?? d.skin,
            grayscale: bool(Keys.grayscale) ?? d.grayscale,
            saveStateOnExit: bool(Keys.saveState) ?? d.saveStateOnExit,
            cpuSpeed: int(Keys.cpu).flatMap { cpuSpeeds.contains($0) ? $0 : nil } ?? d.cpuSpeed,
            exitOnScreenOff: bool(Keys.exitOnOff) ?? d.exitOnScreenOff,
            lcdTheme: string(Keys.lcdTheme).flatMap(LcdTheme.init(rawValue:)) ?? d.lcdTheme,
            customLcdBackground: color(Keys.customLcdBg) ?? d.customLcdBackground,
            customLcdText: color(Keys.customLcdText) ?? d.customLcdText,
            linkLcdToSkin: bool(Keys.linkLcd) ?? d.linkLcdToSkin,
            oledContrast: min(max(int(Keys.oledContrast) ?? d.oledContrast, 20), 100),
            skin3d: bool(Keys.skin3d) ?? d.skin3d,
            screenMargins: string(Keys.margins).flatMap(ScreenMargins.init(rawValue:)) ?? d.screenMargins
        )
    }

    func save(_ c: EmulatorConfig) {
        defaults.set(c.hapticMs, forKey: Keys.haptic)
        defaults.set(c.hapticStrength, forKey: Keys.hapticStrength)
        defaults.set(c.audioFeedback, forKey: Keys.audio)
        defaults.set(c.screenScale, forKey: Keys.scale)
        defaults.set(c.skin.rawValue, forKey: Keys.skin)
        defaults.set(c.grayscale, forKey: Keys.grayscale)
        defaults.set(c.saveStateOnExit, forKey: Keys.saveState)
        defaults.set(c.cpuSpeed, forKey: Keys.cpu)
        defaults.set(c.exitOnScreenOff, forKey: Keys.exitOnOff)
        defaults.set(c.lcdTheme.rawValue, forKey: Keys.lcdTheme)
        defaults.set(Int(c.customLcdBackground), forKey: Keys.customLcdBg)
        defaults.set(Int(c.customLcdText), forKey: Keys.customLcdText)
        defaults.set(c.linkLcdToSkin, forKey: Keys.linkLcd)
        defaults.set(c.oledContrast, forKey: Keys.oledContrast)
        defaults.set(c.skin3d, forKey: Keys.skin3d)
        defaults.set(c.screenMargins.rawValue, forKey: Keys.margins)
    }
}
