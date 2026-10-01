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

/// The native emulators (TiEmu, TilEm) through their C API, graph89.h. The native code keeps one emulator in global
/// state: one calculator runs at a time. Engine calls come from the engine thread only, screen calls from the screen
/// thread, keys from any thread (see graph89.h).
enum EmulatorCore {
    // MARK: - engine

    /// Sets up the engine for `calcType`. Returns 0, or an error when an argument does not fit the model.
    static func initialize(
        calcType: Int32, lcdWidth: Int32, lcdHeight: Int32, zoom: Int32, grayscale: Bool,
        pixelOn: ARGB, pixelOff: ARGB, speed: Double, tmpDir: String
    ) -> Int32 {
        var c = g89_config()
        c.calc_type = calcType
        c.lcd_width = lcdWidth
        c.lcd_height = lcdHeight
        c.zoom = zoom
        c.grayscale = grayscale
        c.grid = false  // dot-matrix grid is not used
        c.pixel_on = pixelOn
        c.pixel_off = pixelOff
        c.grid_color = pixelOff
        c.speed = speed
        return tmpDir.withCString { dir in
            c.tmp_dir = dir
            return g89_init(&c)
        }
    }

    /// Frees the engine; safe when none is set up. Only once the engine and screen threads have ended.
    static func shutdown() { g89_shutdown() }

    /// Loads the ROM image (TiEmu: config, image, init, reset). On failure, `initFailed` tells that the image loaded
    /// but the hardware did not start.
    static func loadImage(_ path: String) -> (code: Int32, initFailed: Bool) {
        var stage: Int32 = 0
        let code = g89_load_image(path, &stage)
        return (code, stage == G89_STAGE_INIT)
    }

    static func loadState(_ path: String) -> Int32 { g89_load_state(path) }

    /// Saves the state; TilEm also writes the whole flash (the archive) back to `image`.
    static func saveState(image: String, state: String) -> Int32 { g89_save_state(image, state) }

    static func turnScreenOn() { g89_turn_screen_on() }

    /// One slice of emulated time (scaled by the CPU speed).
    static func runSlice() { g89_run_slice() }

    /// The settings' "Reset": TiEmu resets the hardware; TilEm also erases the archive.
    static func reset() -> Int32 { g89_reset() }

    static func syncClock() { g89_sync_clock() }

    /// Sends a file over the emulated link; blocks while the calculator takes it. Returns 0 or an error code.
    static func sendFile(_ path: String) -> Int32 { g89_send_file(path) }

    /// Makes a link transfer in progress give up soon (any thread); the next initialize clears it.
    static func abortLink() { g89_abort_link() }

    // MARK: - screen

    /// Reads the LCD. Returns a checksum of the picture, which changes when the picture does, and the screen's state.
    static func readScreen() -> (crc: UInt32, screenOff: Bool, busy: Bool) {
        var status = g89_screen_status()
        let crc = g89_read_screen(&status)
        return (crc, status.screen_off, status.busy)
    }

    /// Copies the zoomed LCD (ARGB) into `buffer`, which must hold exactly width * height * zoom * zoom pixels.
    @discardableResult
    static func getScreen(into buffer: UnsafeMutableBufferPointer<UInt32>) -> Int32 {
        guard let base = buffer.baseAddress else { return G89_E_BUFFER_SIZE }
        return g89_get_screen(base, Int32(buffer.count))
    }

    static func setZoom(_ zoom: Int32) { _ = g89_set_zoom(zoom) }

    // MARK: - keys

    static func sendKey(_ key: Int32, pressed: Bool) { g89_send_key(key, pressed) }

    // MARK: - ROM install

    /// Builds a calculator image from an OS upgrade file (`isRom` false) or a ROM dump. Returns an error code (0 = ok).
    /// Only while no calculator runs.
    static func installROM(source: String, destination: String, calcType: Int32, isRom: Bool) -> Int32 {
        g89_install_rom(source, destination, calcType, isRom)
    }

    // MARK: - files the calculator sends (TiEmu's link port)

    private static let receiverLock = NSLock()
    nonisolated(unsafe) private static var receiver: ((_ path: String, _ name: String) -> Void)?

    /// Takes each file the calculator sends: the path that holds it, which it must move away before returning, and
    /// its name. Called on the engine thread.
    static var fileReceiver: ((_ path: String, _ name: String) -> Void)? {
        get {
            receiverLock.lock()
            defer { receiverLock.unlock() }
            return receiver
        }
        set {
            receiverLock.lock()
            receiver = newValue
            receiverLock.unlock()
            g89_set_file_received_handler({ _, path, name in
                let p = String(cString: path)
                if let take = EmulatorCore.fileReceiver {
                    take(p, String(cString: name))
                } else {
                    try? FileManager.default.removeItem(atPath: p)
                }
            }, nil)
        }
    }
}
