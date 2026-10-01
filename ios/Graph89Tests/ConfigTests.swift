/*
 * Graph89 Remastered - TI graphing calculator emulator for iPhone
 * Copyright (C) 2026 JH
 *
 * This program is free software: you can redistribute it and/or modify it under the terms of the
 * GNU General Public License as published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version. This program is distributed in the hope that it
 * will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License (LICENSE) for more details.
 */

import XCTest
@testable import Graph89

/// Settings and LCD colours: the same values as the Android app.
final class ConfigTests: XCTestCase {
    func testCustomLcdDerivesTheUnlitPixel() {
        // 93% background + 7% text per channel, truncated (Kotlin integer division)
        let lcd = customLcd(background: 0xFFA5_BAA0, text: 0xFF00_0000)
        XCTAssertEqual(lcd.pixelOff, 0xFF99_AC94)
        XCTAssertEqual(lcd.background, 0xFFA5_BAA0)
        XCTAssertEqual(lcd.pixelOn, 0xFF00_0000)
    }

    func testOledContrastDimsTheLinkedOledLcd() {
        var c = EmulatorConfig()
        c.lcdTheme = .OLED
        c.oledContrast = 70
        XCTAssertEqual(c.lcd().pixelOn, 0xFFA2_A2A2)  // 232 * 0.7 = 162.4
        c.linkLcdToSkin = false
        XCTAssertEqual(c.lcd().pixelOn, 0xFFE8_E8E8)
    }

    func testCustomThemeUsesTheCustomColours() {
        var c = EmulatorConfig()
        c.lcdTheme = .CUSTOM
        c.customLcdBackground = 0xFF10_2030
        c.customLcdText = 0xFFF0_E0D0
        XCTAssertEqual(c.lcd(), customLcd(background: 0xFF10_2030, text: 0xFFF0_E0D0))
    }

    func testSettingsRoundTrip() {
        let suite = "g89.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), EmulatorConfig())

        var c = EmulatorConfig()
        c.hapticMs = 12
        c.hapticStrength = 80
        c.audioFeedback = true
        c.screenScale = 3
        c.skin = .NEON_GRID
        c.grayscale = true
        c.saveStateOnExit = false
        c.cpuSpeed = 200
        c.exitOnScreenOff = false
        c.lcdTheme = .CUSTOM
        c.customLcdBackground = 0xFF12_3456
        c.customLcdText = 0xFFFE_DCBA
        c.linkLcdToSkin = false
        c.oledContrast = 45
        c.skin3d = true
        c.screenMargins = .AUTO
        store.save(c)
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), c)
        defaults.removePersistentDomain(forName: suite)
    }

    func testStoredValuesAreClamped() {
        let suite = "g89.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(500, forKey: "haptic_ms")
        defaults.set(0, forKey: "haptic_strength")
        defaults.set(5, forKey: "oled_contrast")
        defaults.set("NO_SUCH_SKIN", forKey: "skin")
        let c = SettingsStore(defaults: defaults).load()
        XCTAssertEqual(c.hapticMs, hapticMaxMs)
        XCTAssertEqual(c.hapticStrength, 1)
        XCTAssertEqual(c.oledContrast, 20)
        XCTAssertEqual(c.skin, .CLASSIC)
        defaults.removePersistentDomain(forName: suite)
    }

    func testLcdSnapshotColourBlendsBetweenOffAndOn() {
        let lcd = LcdColors(background: 0xFF00_0000, pixelOff: 0xFF00_0000, pixelOn: 0xFFFF_FFFF)
        XCTAssertEqual(LcdSnapshot.color(0, lcd), 0xFF00_0000)
        XCTAssertEqual(LcdSnapshot.color(255, lcd), 0xFFFF_FFFF)
        XCTAssertEqual(LcdSnapshot.color(128, lcd), 0xFF80_8080)
    }
}

/// The calculator list file and folders.
final class RomStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("g89-romstore-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        RomStore.rootOverride = root
    }

    override func tearDown() {
        RomStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
    }

    func testReadsTheAndroidListFormat() throws {
        try "ti89t TI89T\nti84plus-1 TI84PLUS\nbad line here\nx NOT_A_MODEL\nactive ti84plus-1\n"
            .write(to: root.appendingPathComponent("calculators.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(RomStore.calculators(), [CalcEntry(id: "ti89t", model: .TI89T), CalcEntry(id: "ti84plus-1", model: .TI84PLUS)])
        XCTAssertEqual(RomStore.active()?.id, "ti84plus-1")
        RomStore.setActive("ti89t")
        XCTAssertEqual(RomStore.active()?.id, "ti89t")
        RomStore.remove("ti89t")
        XCTAssertEqual(RomStore.calculators().map(\.id), ["ti84plus-1"])
        XCTAssertEqual(RomStore.active()?.id, "ti84plus-1")  // the removed one was active: the next one is
        XCTAssertFalse(RomStore.hasRom())
    }

    func testNewEntriesGetUniqueIds() throws {
        let a = RomStore.newEntry(.TI89T)
        XCTAssertEqual(a.id, "ti89t-1")
        _ = RomStore.folder(a.id)  // its folder exists now: the next id moves on
        XCTAssertEqual(RomStore.newEntry(.TI89T).id, "ti89t-2")
        XCTAssertEqual(RomStore.newEntry(.TI83).id, "ti83-1")
    }

    func testRejectsAWrongSizedDump() throws {
        let file = root.appendingPathComponent("dump.rom")
        try Data(count: 1000).write(to: file)
        XCTAssertEqual(RomStore.importFile(at: file, into: CalcEntry(id: "ti83-1", model: .TI83)), 801)
        XCTAssertTrue(RomStore.calculators().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ti83-1").path))  // nothing left behind
    }

    func testRejectsAnOsFileOfAnotherModel() throws {
        let file = root.appendingPathComponent("os.8xu")
        try Data(count: 100_000).write(to: file)
        XCTAssertEqual(RomStore.importFile(at: file, into: CalcEntry(id: "ti89t-1", model: .TI89T)), 802)
    }
}
