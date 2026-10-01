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

/// A key held by a finger: the key code and the touch that holds it.
struct KeyPress {
    let keyCode: Int
    var touchId: Int
}

/// Pressed-key highlight: the key's touch area (key shape plus overhang) as a small image, placed at mask cell
/// (`maskX`, `maskY`) and `width` x `height` mask cells large.
struct KeyOverlay {
    let image: CGImage
    let maskX: Int
    let maskY: Int
    var width: Int { image.width }
    var height: Int { image.height }
}

enum SkinError: Error {
    case noMemory
    case badAsset(String)
}

/// Portrait skin: keypad on the lower part, LCD on top. The key mask has one cell per design pixel of the skin;
/// a cell holds the key code of the key whose shape (plus overhang) covers it, or 255 for no key.
/// All coordinates are pixels of the emulator view.
final class Skin {
    private static let borderScreenSkin = 2
    private static let noKey = 255
    private static let highlight: UInt8 = 0x5A  // white, 35% opaque

    private let type: SkinType
    private let model: CalcModel

    private(set) var canvasWidth = 0
    private(set) var canvasHeight = 0

    /// The whole view: LCD band (in the LCD background colour) and keypad.
    private(set) var image: CGImage?
    private let screenLock = NSLock()
    private var _screen: EmulatorScreen?
    var screen: EmulatorScreen? {
        screenLock.lock()
        defer { screenLock.unlock() }
        return _screen
    }

    private(set) var backgroundColor: ARGB = 0xFF00_0000
    private(set) var lcdBackground: ARGB = 0xFFA5_BAA0
    private(set) var lcdPixelOff: ARGB = 0xFFB6_C5B7
    private(set) var lcdPixelOn: ARGB = 0xFF00_0000

    private var keyMask: [UInt8]?
    private var keyMaskW = 0
    private var keyMaskH = 0
    private var skinInCanvas = CGRect.zero
    private var overlays: [Int: KeyOverlay?] = [:]

    private var root: String { "portrait/\(model.skin)\((type.bundled ? type : .CLASSIC).suffix)/" }

    init(type: SkinType, model: CalcModel) {
        self.type = type
        self.model = model
    }

    /// Lays out and draws the skin for a view of `width` x `height` pixels. Slow when the skin is not cached:
    /// call it off the main thread. Throws when even the bundled skin does not load.
    func initialize(width: Int, height: Int, config: EmulatorConfig, onFrame: @escaping () -> Void) throws {
        release()
        canvasWidth = width
        canvasHeight = height

        let maxZoom = width / model.lcdWidth
        let zoom = adjustScreenZoom(config.screenScale, maxZoom, width, height)
        let screenW = Int((Float(model.lcdWidth) * zoom).rounded())
        let lcdH = Int((Float(model.lcdHeight) * zoom).rounded())
        let screenH = lcdH + 10

        let lcd = config.lcd()
        lcdPixelOff = lcd.pixelOff
        lcdPixelOn = lcd.pixelOn
        lcdBackground = lcd.background

        guard let cg = Graphics.context(width: width, height: height) else { throw SkinError.noMemory }

        // the keypad fills the view below the LCD: drawn on the phone at this exact size, or as a last
        // resort the bundled image, scaled evenly (never stretched)
        let buttonsH = height - screenH - Self.borderScreenSkin
        let area = CGRect(x: 0, y: height - buttonsH, width: width, height: buttonsH)
        let cacheKey = SkinCache.key(model: model, type: type, width: Int(area.width), height: Int(area.height), oledContrast: config.oledContrast, threeD: config.skin3d)
        if let cached = SkinCache.get(cacheKey) {
            Graphics.draw(cached.image, in: CGRect(x: area.minX, y: area.minY, width: CGFloat(cached.image.width), height: CGFloat(cached.image.height)), of: cg)
            backgroundColor = cached.backgroundColor
            keyMask = cached.mask
            keyMaskW = cached.maskWidth
            keyMaskH = cached.maskHeight
            skinInCanvas = cached.keypad.offsetBy(dx: area.minX, dy: area.minY)
        } else if let rendered = try? SkinRenderer.render(model: model, type: type, into: cg, area: area, oledContrast: config.oledContrast, threeD: config.skin3d) {
            backgroundColor = rendered.backgroundColor
            keyMask = rendered.mask
            keyMaskW = rendered.maskWidth
            keyMaskH = rendered.maskHeight
            skinInCanvas = rendered.keypad
            // keep the drawing, so the next start only copies it
            if let full = cg.makeImage(), let keypadOnly = full.cropping(to: area) {
                SkinCache.put(cacheKey, SkinCache.Entry(
                    image: keypadOnly, keypad: rendered.keypad.offsetBy(dx: -area.minX, dy: -area.minY),
                    mask: rendered.mask, maskWidth: rendered.maskWidth, maskHeight: rendered.maskHeight, backgroundColor: rendered.backgroundColor
                ))
            }
        } else {
            try drawBundled(cg, area)
        }

        cg.setFillColor(Graphics.color(backgroundColor))
        cg.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: area.minY))
        cg.setFillColor(Graphics.color(lcdBackground))
        cg.fill(CGRect(x: 0, y: 0, width: width, height: screenH))
        image = cg.makeImage()
        overlays.removeAll()

        let left = width / 2 - screenW / 2
        let s = EmulatorScreen(destination: CGRect(x: left, y: 5, width: screenW, height: lcdH), rawWidth: model.lcdWidth, rawHeight: model.lcdHeight, onFrame: onFrame)
        screenLock.lock()
        _screen = s
        screenLock.unlock()
    }

    /// The pre-rendered skin from assets/portrait: scaled evenly to fit `area`, bottom-aligned and centred;
    /// the space left over repeats the image's edge rows / columns, so the body and case simply continue.
    private func drawBundled(_ cg: CGContext, _ area: CGRect) throws {
        guard let image = Graphics.image(contentsOf: Assets.url(root + "skin.webp")) else { throw SkinError.badAsset(root + "skin.webp") }
        try parseInfo()
        let mask = try Assets.data(root + "buttonmask.bin")
        guard mask.count >= keyMaskW * keyMaskH else { throw SkinError.badAsset(root + "buttonmask.bin") }
        keyMask = [UInt8](mask.prefix(keyMaskW * keyMaskH))

        let iw = CGFloat(image.width)
        let ih = CGFloat(image.height)
        let s = min(area.width / iw, area.height / ih)
        let w = (iw * s).rounded(.towardZero)
        let h = (ih * s).rounded(.towardZero)
        let left = area.minX + ((area.width - w) / 2).rounded(.towardZero)
        let dest = CGRect(x: left, y: area.maxY - h, width: w, height: h)
        cg.setFillColor(Graphics.color(backgroundColor))
        cg.fill(area)
        cg.interpolationQuality = .high
        if dest.minX > area.minX, let l = image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: ih)),
           let r = image.cropping(to: CGRect(x: iw - 1, y: 0, width: 1, height: ih)) {
            Graphics.draw(l, in: CGRect(x: area.minX, y: dest.minY, width: dest.minX - area.minX, height: h), of: cg)
            Graphics.draw(r, in: CGRect(x: dest.maxX, y: dest.minY, width: area.maxX - dest.maxX, height: h), of: cg)
        }
        if dest.minY > area.minY, let t = image.cropping(to: CGRect(x: 0, y: 0, width: iw, height: 1)) {
            Graphics.draw(t, in: CGRect(x: dest.minX, y: area.minY, width: w, height: dest.minY - area.minY), of: cg)
        }
        Graphics.draw(image, in: dest, of: cg)
        skinInCanvas = dest
    }

    /// Automatic: the LCD fills the width (up to half the height), at a fractional zoom when the width is not a
    /// multiple of the LCD's. A chosen scale stays a whole number, for pixels of one exact size.
    private func adjustScreenZoom(_ scale: Int, _ maxZoom: Int, _ width: Int, _ height: Int) -> Float {
        if scale <= 0 { return min(Float(width) / Float(model.lcdWidth), 0.5 * Float(height) / Float(model.lcdHeight)) }
        if scale > maxZoom { return Float(maxZoom) }
        return Float(scale)
    }

    private func parseInfo() throws {
        guard let text = String(data: try Assets.data(root + "info"), encoding: .utf8) else { throw SkinError.badAsset(root + "info") }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count != 2 { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch parts[0].trimmingCharacters(in: .whitespaces).lowercased() {
            case "backgroundcolor":
                backgroundColor = ARGB(value, radix: 16) ?? backgroundColor
            case "mask":
                let xy = value.split(whereSeparator: \.isWhitespace)
                if xy.count >= 2, let w = Int(xy[0]), let h = Int(xy[1]) {
                    keyMaskW = w
                    keyMaskH = h
                }
            default:
                break
            }
        }
    }

    /// The key code under a touch point, or nil when the point is outside the skin. Code 255 means no key.
    func keyCode(atX x: Int, y: Int) -> Int? {
        guard let mask = keyMask, keyMaskW > 0, keyMaskH > 0 else { return nil }
        let r = skinInCanvas
        let left = Int(r.minX), top = Int(r.minY), right = Int(r.maxX), bottom = Int(r.maxY)
        if x < left || x > right || y < top || y > bottom || right == left || bottom == top { return nil }
        let maskX = min(max((x - left) * keyMaskW / (right - left), 0), keyMaskW - 1)
        let maskY = min(max((y - top) * keyMaskH / (bottom - top), 0), keyMaskH - 1)
        return Int(mask[maskX + maskY * keyMaskW])
    }

    /// Highlight of one key, built from the mask on first use. Nil when the key has no cells. Main thread only.
    func overlay(for code: Int) -> KeyOverlay? {
        if let o = overlays[code] { return o }
        let o = buildOverlay(code)
        overlays[code] = o
        return o
    }

    private func buildOverlay(_ code: Int) -> KeyOverlay? {
        guard let mask = keyMask, code >= 0, code < Self.noKey else { return nil }
        let c = UInt8(code)
        var x0 = keyMaskW, y0 = keyMaskH, x1 = -1, y1 = -1
        for y in 0..<keyMaskH {
            let row = y * keyMaskW
            for x in 0..<keyMaskW where mask[row + x] == c {
                x0 = min(x0, x); x1 = max(x1, x)
                y0 = min(y0, y); y1 = max(y1, y)
            }
        }
        if x1 < 0 { return nil }

        let w = x1 - x0 + 1
        let h = y1 - y0 + 1
        // premultiplied RGBA: white at 35%
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w where mask[(y0 + y) * keyMaskW + x0 + x] == c {
                let i = (y * w + x) * 4
                bytes[i] = Self.highlight; bytes[i + 1] = Self.highlight; bytes[i + 2] = Self.highlight; bytes[i + 3] = Self.highlight
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: Graphics.colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return nil }
        return KeyOverlay(image: image, maskX: x0, maskY: y0)
    }

    /// Where an overlay goes on the canvas.
    func overlayRect(_ o: KeyOverlay) -> CGRect {
        let sx = skinInCanvas.width / CGFloat(keyMaskW)
        let sy = skinInCanvas.height / CGFloat(keyMaskH)
        return CGRect(
            x: skinInCanvas.minX + CGFloat(o.maskX) * sx, y: skinInCanvas.minY + CGFloat(o.maskY) * sy,
            width: CGFloat(o.width) * sx, height: CGFloat(o.height) * sy
        )
    }

    func release() {
        image = nil
        screenLock.lock()
        _screen = nil
        screenLock.unlock()
        overlays.removeAll()
    }
}
