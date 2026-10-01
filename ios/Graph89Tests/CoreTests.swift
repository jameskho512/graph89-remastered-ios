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

/// The emulators themselves, driven the way the engine thread drives them but step by step, with free operating
/// systems instead of TI's: PedroM (TI-89, TI-89 Titanium) and the KnightOS kernel (TI-83 Plus ... TI-84 Plus SE).
/// CI downloads them into G89_TEST_OS_DIR (ios/scripts/fetch-test-os.sh); without it these tests are skipped.
final class CoreTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("g89-core-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        RomStore.rootOverride = root
    }

    override func tearDown() {
        EmulatorCore.shutdown()
        RomStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func testOS(_ name: String) throws -> URL {
        guard let dir = ProcessInfo.processInfo.environment["G89_TEST_OS_DIR"], !dir.isEmpty else {
            throw XCTSkip("G89_TEST_OS_DIR is not set")
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("\(name) is not in G89_TEST_OS_DIR") }
        return url
    }

    /// Installs `file` as a new calculator of `model` the way the app does (a copy under its own name, RomStore).
    private func install(_ file: URL, _ model: CalcModel) throws -> CalcEntry {
        let entry = RomStore.newEntry(model)
        let picked = root.appendingPathComponent("picked-\(file.lastPathComponent)")
        try? FileManager.default.removeItem(at: picked)
        try FileManager.default.copyItem(at: file, to: picked)
        let error = RomStore.importFile(at: picked, into: entry)
        XCTAssertEqual(error, 0, "install \(file.lastPathComponent) as \(model): \(RomStore.errorName(error))")
        XCTAssertEqual(RomStore.active(), entry)
        return entry
    }

    private struct Frame {
        let crc: UInt32
        let screenOff: Bool
        let pixels: [UInt32]
        let lit: Int
    }

    private let on: ARGB = 0xFF00_0000
    private let off: ARGB = 0xFFFF_FFFF

    private func start(_ entry: CalcEntry) throws {
        let m = entry.model
        let err = EmulatorCore.initialize(
            calcType: m.type, lcdWidth: Int32(m.lcdWidth), lcdHeight: Int32(m.lcdHeight), zoom: 1, grayscale: false,
            pixelOn: on, pixelOff: off, speed: 1, tmpDir: RomStore.tmpDir().path
        )
        XCTAssertEqual(err, 0)
        let image = try XCTUnwrap(RomStore.image(entry.id))
        let loaded = EmulatorCore.loadImage(image.path)
        XCTAssertEqual(loaded.code, 0, "load \(m): \(RomStore.errorName(loaded.code))")
    }

    private func frame(_ m: CalcModel) -> Frame {
        let read = EmulatorCore.readScreen()
        var pixels = [UInt32](repeating: 0, count: m.lcdWidth * m.lcdHeight)
        pixels.withUnsafeMutableBufferPointer { _ = EmulatorCore.getScreen(into: $0) }
        return Frame(crc: read.crc, screenOff: read.screenOff, pixels: pixels, lit: pixels.filter { $0 == on }.count)
    }

    private func run(_ slices: Int) {
        for _ in 0..<slices { EmulatorCore.runSlice() }
    }

    private func press(_ key: Int32) {
        EmulatorCore.sendKey(key, pressed: true)
        run(3)
        EmulatorCore.sendKey(key, pressed: false)
        run(3)
    }

    /// Writes the LCD as a PNG for a person to look at (with G89_OUTPUT_DIR).
    private func savePNG(_ f: Frame, _ m: CalcModel, _ name: String) {
        guard let out = testOutputDir("lcd") else { return }
        var data = f.pixels
        let w = m.lcdWidth, h = m.lcdHeight
        let image: CGImage? = data.withUnsafeMutableBytes { raw in
            guard let cg = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
            ) else { return nil }
            return cg.makeImage()
        }
        if let image { Graphics.writePNG(image, to: out.appendingPathComponent("\(name).png")) }
    }

    // MARK: - TiEmu with PedroM

    private func pedrom(_ file: String, _ model: CalcModel) throws {
        let entry = try install(testOS(file), model)
        // the image TiEmu built is the model's size (TiEmu takes the model from the file, not from the app)
        let size = try FileManager.default.attributesOfItem(atPath: RomStore.image(entry.id)!.path)[.size] as? NSNumber
        XCTAssertGreaterThan(size?.int64Value ?? 0, model.romSize / 2)

        try start(entry)
        EmulatorCore.turnScreenOn()
        run(120)  // a few emulated seconds: PedroM boots to its shell
        let booted = frame(model)
        savePNG(booted, model, "\(model.rawValue)_pedrom_boot")
        XCTAssertFalse(booted.screenOff, "\(model): the screen is on after boot")
        XCTAssertGreaterThan(booted.lit, 150, "\(model): the PedroM banner and prompt are on the screen")

        // CLEAR on an empty prompt clears the screen
        press(56)
        run(20)
        let cleared = frame(model)
        savePNG(cleared, model, "\(model.rawValue)_pedrom_clear")
        XCTAssertLessThan(cleared.lit, booted.lit, "\(model): CLEAR clears the screen")

        // the state saves and loads back
        let image = RomStore.image(entry.id)!, state = RomStore.state(entry.id)!
        XCTAssertEqual(EmulatorCore.saveState(image: image.path, state: state.path), 0)
        EmulatorCore.shutdown()
        try start(entry)
        XCTAssertEqual(EmulatorCore.loadState(state.path), 0, "\(model): the saved state loads")
        EmulatorCore.turnScreenOn()
        run(20)
        XCTAssertFalse(frame(model).screenOff)
    }

    func testPedromOnTi89() throws { try pedrom("PedroM-89.89u", .TI89) }
    func testPedromOnTi89Titanium() throws { try pedrom("PedroM-89ti.89u", .TI89T) }

    // MARK: - TilEm with the KnightOS kernel (boot page patched for TilEm by the fetch script)

    private func knightos(_ file: String, _ model: CalcModel) throws {
        let entry = try install(testOS(file), model)
        try start(entry)
        run(5)
        XCTAssertTrue(frame(model).screenOff, "\(model): the kernel waits for ON with the screen off")

        // ON wakes it: no /bin/init, so the kernel shows its error screen and waits for a key
        press(Engine.tilem.onKey)
        var shown = frame(model)
        for _ in 0..<20 where shown.screenOff || shown.lit == 0 {
            run(1)
            shown = frame(model)
        }
        savePNG(shown, model, "\(model.rawValue)_knightos")
        XCTAssertFalse(shown.screenOff, "\(model): ON turns the screen on")
        XCTAssertTrue((100...2000).contains(shown.lit), "\(model): the kernel's message is on the screen (\(shown.lit) pixels)")
        run(5)
        XCTAssertEqual(frame(model).crc, frame(model).crc, "\(model): the screen is still")

        // any key shuts it down
        press(0x09)  // ENTER
        run(10)
        XCTAssertTrue(frame(model).screenOff, "\(model): a key turns it off")

        // the state saves (with the flash) and loads back
        let image = RomStore.image(entry.id)!, state = RomStore.state(entry.id)!
        XCTAssertEqual(EmulatorCore.saveState(image: image.path, state: state.path), 0)
        EmulatorCore.shutdown()
        try start(entry)
        XCTAssertEqual(EmulatorCore.loadState(state.path), 0, "\(model): the saved state loads")
    }

    func testKnightOSOnTi83Plus() throws { try knightos("kernel-TI83p.rom", .TI83PLUS) }
    func testKnightOSOnTi83PlusSE() throws { try knightos("kernel-TI83pSE.rom", .TI83PLUS_SE) }
    func testKnightOSOnTi84Plus() throws { try knightos("kernel-TI84p.rom", .TI84PLUS) }
    func testKnightOSOnTi84PlusSE() throws { try knightos("kernel-TI84pSE.rom", .TI84PLUS_SE) }

    // MARK: - guards of the C API

    func testCallsWithoutAnEngineAreHarmless() {
        EmulatorCore.shutdown()
        let read = EmulatorCore.readScreen()
        XCTAssertTrue(read.screenOff)
        EmulatorCore.sendKey(78, pressed: true)
        EmulatorCore.sendKey(78, pressed: false)
        var buffer = [UInt32](repeating: 0, count: 16)
        XCTAssertNotEqual(buffer.withUnsafeMutableBufferPointer { EmulatorCore.getScreen(into: $0) }, 0)
    }

    func testRejectsAWrongLcdSize() {
        let err = EmulatorCore.initialize(
            calcType: CalcModel.TI84PLUS.type, lcdWidth: 160, lcdHeight: 100, zoom: 1, grayscale: false,
            pixelOn: on, pixelOff: off, speed: 1, tmpDir: RomStore.tmpDir().path
        )
        XCTAssertNotEqual(err, 0)
    }
}
