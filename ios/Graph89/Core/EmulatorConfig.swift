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

/// An ARGB colour (0xAARRGGBB), the format the native screen buffer and the skins use.
typealias ARGB = UInt32

/// Skin theme. Skins are drawn on the phone; `bundled` ones also have pre-rendered images (folder: the
/// calculator's skin family plus `suffix`, e.g. ti89classic) as a last resort, the others fall back to Classic.
/// The raw value is the stored setting (the same as the Android app's).
enum SkinType: String, CaseIterable, Identifiable {
    case CLASSIC, MIDNIGHT, OLED, MONO, NEON_GRID, EMBER, FROST, SOLAR, RETRO, EMERALD, BLOSSOM, NORD, RADIOACTIVE, ROYAL

    var id: String { rawValue }

    var label: String {
        switch self {
        case .CLASSIC: "Classic"
        case .MIDNIGHT: "Midnight"
        case .OLED: "OLED"
        case .MONO: "Grayscale"
        case .NEON_GRID: "Neon"
        case .EMBER: "Ember"
        case .FROST: "Frost"
        case .SOLAR: "Solar"
        case .RETRO: "Retro"
        case .EMERALD: "Forest"
        case .BLOSSOM: "Floral"
        case .NORD: "Nord"
        case .RADIOACTIVE: "Radioactive"
        case .ROYAL: "Royal"
        }
    }

    var suffix: String {
        switch self {
        case .NEON_GRID: "neongrid"
        default: rawValue.lowercased()
        }
    }

    var bundled: Bool { self == .CLASSIC || self == .MIDNIGHT }
}

/// LCD colours as ARGB: background of the LCD area, off pixel, on pixel.
struct LcdColors: Equatable {
    var background: ARGB
    var pixelOff: ARGB
    var pixelOn: ARGB
}

/// LCD colour schemes. Those named after a keypad skin match that skin.
/// CUSTOM takes its colours from the settings (EmulatorConfig.customLcdBackground / customLcdText).
enum LcdTheme: String, CaseIterable, Identifiable {
    case CUSTOM, CLASSIC, GREY, HIGH_CONTRAST, DARK, MIDNIGHT, OLED, MONO, NEON_GRID, EMBER, FROST, SOLAR, RETRO, EMERALD, BLOSSOM, NORD, RADIOACTIVE, ROYAL

    var id: String { rawValue }

    var label: String {
        switch self {
        case .CUSTOM: "Custom"
        case .CLASSIC: "Classic"
        case .GREY: "Grey"
        case .HIGH_CONTRAST: "High contrast"
        case .DARK: "Dark"
        case .MIDNIGHT: "Midnight"
        case .OLED: "OLED"
        case .MONO: "Grayscale"
        case .NEON_GRID: "Neon"
        case .EMBER: "Ember"
        case .FROST: "Frost"
        case .SOLAR: "Solar"
        case .RETRO: "Retro"
        case .EMERALD: "Forest"
        case .BLOSSOM: "Floral"
        case .NORD: "Nord"
        case .RADIOACTIVE: "Radioactive"
        case .ROYAL: "Royal"
        }
    }

    var colors: LcdColors {
        switch self {
        case .CUSTOM, .CLASSIC: LcdColors(background: 0xFFA5_BAA0, pixelOff: 0xFFB6_C5B7, pixelOn: 0xFF00_0000)
        case .GREY: LcdColors(background: 0xFFB4_B4B4, pixelOff: 0xFFC4_C4C4, pixelOn: 0xFF1A_1A1A)
        case .HIGH_CONTRAST: LcdColors(background: 0xFFFF_FFFF, pixelOff: 0xFFFF_FFFF, pixelOn: 0xFF00_0000)
        case .DARK: LcdColors(background: 0xFF10_1418, pixelOff: 0xFF16_1B20, pixelOn: 0xFFE3_E8EC)
        case .MIDNIGHT: LcdColors(background: 0xFF14_1217, pixelOff: 0xFF1B_1920, pixelOn: 0xFFE6_E0F0)
        case .OLED: LcdColors(background: 0xFF00_0000, pixelOff: 0xFF00_0000, pixelOn: 0xFFE8_E8E8)
        case .MONO: LcdColors(background: 0xFFF4_F4F4, pixelOff: 0xFFFC_FCFC, pixelOn: 0xFF11_1111)
        case .NEON_GRID: LcdColors(background: 0xFF02_080B, pixelOff: 0xFF06_1419, pixelOn: 0xFF00_E5FF)
        case .EMBER: LcdColors(background: 0xFF1B_120C, pixelOff: 0xFF24_180F, pixelOn: 0xFFFF_9A4A)
        case .FROST: LcdColors(background: 0xFFDC_E8F0, pixelOff: 0xFFE7_F0F6, pixelOn: 0xFF1E_3448)
        case .SOLAR: LcdColors(background: 0xFF00_2B36, pixelOff: 0xFF07_3642, pixelOn: 0xFFEE_E8D5)
        case .RETRO: LcdColors(background: 0xFFC7_C0A3, pixelOff: 0xFFD2_CCB2, pixelOn: 0xFF3A_2E25)
        case .EMERALD: LcdColors(background: 0xFF0E_1F16, pixelOff: 0xFF13_291D, pixelOn: 0xFF7C_C6A4)
        case .BLOSSOM: LcdColors(background: 0xFFF6_E3E9, pixelOff: 0xFFFB_EEF2, pixelOn: 0xFF5B_4453)
        case .NORD: LcdColors(background: 0xFF2E_3440, pixelOff: 0xFF35_3C4A, pixelOn: 0xFF88_C0D0)
        case .RADIOACTIVE: LcdColors(background: 0xFF02_0A02, pixelOff: 0xFF06_1406, pixelOn: 0xFF39_FF14)
        case .ROYAL: LcdColors(background: 0xFF0B_0E24, pixelOff: 0xFF11_153A, pixelOn: 0xFFE3_B341)
        }
    }

    var background: ARGB { colors.background }
    var pixelOff: ARGB { colors.pixelOff }
    var pixelOn: ARGB { colors.pixelOn }
}

/// Unlit pixels are a faint step from the background towards the ink, as on a real LCD.
func customLcd(background: ARGB, text: ARGB) -> LcdColors {
    func ch(_ shift: ARGB) -> ARGB { ((background >> shift & 0xFF) * 93 + (text >> shift & 0xFF) * 7) / 100 }
    let off: ARGB = 0xFF00_0000 | ch(16) << 16 | ch(8) << 8 | ch(0)
    return LcdColors(background: background, pixelOff: off, pixelOn: text)
}

/// Black margins around the calculator so rounded screen corners and the camera cutout do not hide it.
enum ScreenMargins: String, CaseIterable, Identifiable {
    case CAMERA, CORNERS, AUTO, NONE

    var id: String { rawValue }

    var label: String {
        switch self {
        case .CAMERA: "Default: Camera only"
        case .CORNERS: "Corners only"
        case .AUTO: "Camera & corners"
        case .NONE: "None"
        }
    }
}

/// Vibration time range in milliseconds; 0 is off. The slider moves in steps of 1.
let hapticMaxMs = 50

/// A stored value clamped to the slider range.
func nearestHaptic(_ ms: Int) -> Int { min(max(ms, 0), hapticMaxMs) }

/// Selectable CPU speeds in percent; 100 is the default.
let cpuSpeeds = [50, 75, 100, 150, 200, 250]

struct EmulatorConfig: Equatable {
    var hapticMs = 5
    /// Vibration strength in percent (1-100).
    var hapticStrength = 35
    var audioFeedback = false
    /// <= 0 means automatic.
    var screenScale = -1
    var skin = SkinType.CLASSIC
    var grayscale = false
    var saveStateOnExit = true
    var cpuSpeed = 100
    /// Turning the calculator off ([2ND] [ON]) shows the calculator list (the Android app closes instead).
    var exitOnScreenOff = true
    var lcdTheme = LcdTheme.CLASSIC
    /// Colours of the Custom LCD (ARGB).
    var customLcdBackground: ARGB = 0xFFA5_BAA0
    var customLcdText: ARGB = 0xFF00_0000
    /// Picking a skin also picks its LCD scheme, and the other way round.
    var linkLcdToSkin = true
    /// Brightness of the OLED skin's text and outlines (and, when linked, the OLED LCD's text), in percent.
    var oledContrast = 70
    /// 3D finish on any skin: satin keys with bevelled edges and engraved legends (the face stays as it is).
    var skin3d = false
    var screenMargins = ScreenMargins.CAMERA

    /// The LCD colours in use: the chosen scheme, or the Custom colours.
    func lcd() -> LcdColors {
        if lcdTheme == .CUSTOM { return customLcd(background: customLcdBackground, text: customLcdText) }
        var on = lcdTheme.pixelOn
        if lcdTheme == .OLED && linkLcdToSkin {  // the OLED contrast dims the OLED LCD's text too
            let f = Float(min(max(oledContrast, 0), 100)) / 100
            func ch(_ shift: ARGB) -> ARGB { ARGB(Float(on >> shift & 0xFF) * f) << shift }
            on = 0xFF00_0000 | ch(16) | ch(8) | ch(0)
        }
        return LcdColors(background: lcdTheme.background, pixelOff: lcdTheme.pixelOff, pixelOn: on)
    }
}
