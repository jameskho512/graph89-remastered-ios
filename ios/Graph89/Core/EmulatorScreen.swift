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

import CoreGraphics
import Foundation

/// Zoom currently configured in the native engine.
enum EngineScreenParams {
    nonisolated(unsafe) static var rawWidth = 0
    nonisolated(unsafe) static var rawHeight = 0
    nonisolated(unsafe) static var zoom = 0

    static func reset() {
        rawWidth = 0
        rawHeight = 0
        zoom = 0
    }
}

/// A frame of the calculator's display at its own resolution: for each pixel, how far it is from unlit (0) to lit
/// (255). Grayscale shades fall in between. The skin picker shows it in any LCD scheme's colours.
struct LcdSnapshot {
    let width: Int
    let height: Int
    let levels: [UInt8]

    func level(_ x: Int, _ y: Int) -> Int { Int(levels[y * width + x]) }

    /// The colour of a pixel at `level` (0 unlit, 255 lit) in `lcd`'s colours.
    static func color(_ level: Int, _ lcd: LcdColors) -> ARGB {
        let t = Float(level) / 255
        func ch(_ shift: ARGB) -> ARGB {
            let a = Float(lcd.pixelOff >> shift & 0xFF)
            let b = Float(lcd.pixelOn >> shift & 0xFF)
            return ARGB((a + (b - a) * t).rounded()) << shift
        }
        return 0xFF00_0000 | ch(16) | ch(8) | ch(0)
    }
}

/// The calculator's LCD: the native engine draws it, zoomed, into `screenData` (ARGB); the view shows it in
/// `destination` (pixels of the emulator view).
final class EmulatorScreen {
    /// Guards the screen data and the native screen calls (the engine and the view use them from different threads).
    static let screenChangeLock = NSLock()

    let rawWidth: Int
    let rawHeight: Int
    private(set) var destination: CGRect
    /// The zoomed image fits `destination` exactly; otherwise it is scaled (smoothly) into it.
    private(set) var integerZoom: Bool
    private(set) var zoom: Int

    private let onFrame: () -> Void
    private var screenData: [UInt32]

    private let stateLock = NSLock()
    private var busy = false
    private var screenOff = false
    private var crc: UInt32 = 0
    private var counter = 0
    private var frameNumber = 0

    init(destination: CGRect, rawWidth: Int, rawHeight: Int, onFrame: @escaping () -> Void) {
        self.rawWidth = rawWidth
        self.rawHeight = rawHeight
        self.onFrame = onFrame
        var destination = destination
        let dw = Int(destination.width)
        let dh = Int(destination.height)

        var integerZoom = dw % rawWidth == 0
        let zoomf = Double(dw) / Double(rawWidth)
        var zoom = dw / rawWidth

        let diff = Int(max(abs(Double(dw) - floor(zoomf) * Double(rawWidth)), abs(Double(dh) - floor(zoomf) * Double(rawHeight))))

        // try at best to use an integer zoom. tolerance 20px
        if !integerZoom && diff < 20 {
            integerZoom = true
            zoom = Int(floor(zoomf))
            let width = rawWidth * zoom
            let height = rawHeight * zoom
            let cx = (Int(destination.minX) + Int(destination.maxX)) / 2
            let cy = (Int(destination.minY) + Int(destination.maxY)) / 2
            destination = CGRect(x: cx - width / 2, y: cy - height / 2, width: width, height: height)
        }
        if !integerZoom {
            zoom = Int(ceil(zoomf))
        }
        zoom = max(zoom, 1)

        self.destination = destination
        self.integerZoom = integerZoom
        self.zoom = zoom
        screenData = [UInt32](repeating: 0, count: rawWidth * zoom * rawHeight * zoom)
    }

    /// Reads the engine's screen; called on the screen thread. Calls `onFrame` when the picture changed.
    func refresh() {
        var changed = false
        Self.screenChangeLock.lock()
        counter += 1
        if EngineScreenParams.rawHeight != rawHeight || EngineScreenParams.rawWidth != rawWidth || EngineScreenParams.zoom != zoom {
            EngineScreenParams.rawHeight = rawHeight
            EngineScreenParams.rawWidth = rawWidth
            EngineScreenParams.zoom = zoom
            EmulatorCore.setZoom(Int32(zoom))
        }
        let read = EmulatorCore.readScreen()
        stateLock.lock()
        screenOff = read.screenOff
        busy = read.busy
        stateLock.unlock()
        if crc != read.crc || counter % 40 == 0 {
            crc = read.crc
            screenData.withUnsafeMutableBufferPointer { EmulatorCore.getScreen(into: $0) }
            frameNumber += 1
            changed = true
        }
        Self.screenChangeLock.unlock()
        if changed { onFrame() }
    }

    func isBusy() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return busy && !screenOff
    }

    func isScreenOff() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return screenOff
    }

    /// The last frame as an image of `rawWidth * zoom` x `rawHeight * zoom` pixels, with its frame number (so a view
    /// can skip a frame it already shows). Nil before the first frame.
    func currentImage() -> (image: CGImage, frame: Int)? {
        Self.screenChangeLock.lock()
        defer { Self.screenChangeLock.unlock() }
        guard frameNumber > 0 else { return nil }
        let w = rawWidth * zoom
        let h = rawHeight * zoom
        let data = screenData.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                // ARGB words in little-endian memory: B G R A bytes
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: !integerZoom, intent: .defaultIntent
              )
        else { return nil }
        return (image, frameNumber)
    }

    /// The last frame as an `LcdSnapshot`; `pixelOff` and `pixelOn` are the colours it was drawn in. Nil before the
    /// first frame.
    func snapshot(pixelOff: ARGB, pixelOn: ARGB) -> LcdSnapshot? {
        Self.screenChangeLock.lock()
        defer { Self.screenChangeLock.unlock() }
        let zw = rawWidth * zoom
        if screenData.isEmpty || screenData[0] == 0 { return nil }  // no frame yet (every drawn pixel is opaque)
        func c(_ v: ARGB, _ shift: ARGB) -> Int { Int(v >> shift & 0xFF) }
        let dr = c(pixelOn, 16) - c(pixelOff, 16)
        let dg = c(pixelOn, 8) - c(pixelOff, 8)
        let db = c(pixelOn, 0) - c(pixelOff, 0)
        let len2 = max(dr * dr + dg * dg + db * db, 1)
        var levels = [UInt8](repeating: 0, count: rawWidth * rawHeight)
        for y in 0..<rawHeight {
            for x in 0..<rawWidth {
                // the centre of the pixel's zoomed block, projected onto the unlit -> lit colour line
                let p = screenData[(y * zoom + zoom / 2) * zw + x * zoom + zoom / 2]
                let t = (c(p, 16) - c(pixelOff, 16)) * dr + (c(p, 8) - c(pixelOff, 8)) * dg + (c(p, 0) - c(pixelOff, 0)) * db
                levels[y * rawWidth + x] = UInt8(min(max(t * 255 / len2, 0), 255))
            }
        }
        return LcdSnapshot(width: rawWidth, height: rawHeight, levels: levels)
    }
}
