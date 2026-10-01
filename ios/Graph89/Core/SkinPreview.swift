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

/// Pictures of the calculator for the skin picker, laid out like Skin.initialize but at any size. Each picture is
/// drawn once: keypad thumbnails are kept in memory and as files in the Caches folder, whole-calculator previews in
/// memory. Sizes are pixels.
enum SkinPreview {
    private final class Box {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static let memory: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.totalCostLimit = 64 << 20
        return c
    }()

    private static func thumbDir() -> URL {
        let d = SkinCache.cacheDir.appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func cached(_ key: String, _ draw: () -> CGImage) -> CGImage {
        if let b = memory.object(forKey: key as NSString) { return b.image }
        let image = draw()
        memory.setObject(Box(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
        return image
    }

    /// The LCD's place in a picture `width` px wide: the height of the LCD band at the top, and the screen in it.
    struct LcdArea {
        let bandHeight: Int
        let screen: CGRect
    }

    /// Where the LCD goes, as on this phone: `viewWidth` x `viewHeight` is the real emulator view, which sets its share.
    /// The zoom is Skin.initialize's: automatic fills the width (up to half the height), fractionally.
    static func lcdArea(model: CalcModel, width: Int, viewWidth: Int, viewHeight: Int, screenScale: Int) -> LcdArea {
        let f = CGFloat(width) / CGFloat(max(viewWidth, 1))
        let maxZoom = viewWidth / model.lcdWidth
        let zoom: Float = screenScale <= 0
            ? min(Float(viewWidth) / Float(model.lcdWidth), 0.5 * Float(viewHeight) / Float(model.lcdHeight))
            : Float(min(screenScale, maxZoom))
        let screenW = (Float(model.lcdWidth) * zoom).rounded()
        let lcdH = (Float(model.lcdHeight) * zoom).rounded()
        let lw = CGFloat(screenW) * f
        let lh = CGFloat(lcdH) * f
        return LcdArea(
            bandHeight: Int((CGFloat(lcdH) + 10) * f),
            screen: CGRect(x: (CGFloat(width) - lw) / 2, y: 5 * f, width: lw, height: lh)
        )
    }

    /// The keypad of the whole calculator as it will look on this phone, below a transparent LCD band (see `lcdArea`):
    /// the skin picker draws the LCD itself, so a change of LCD colours needs no new picture.
    static func calculator(
        model: CalcModel, type: SkinType, width: Int, height: Int,
        viewWidth: Int, viewHeight: Int, screenScale: Int, oledContrast: Int = 70, threeD: Bool = false
    ) -> CGImage {
        cached("calc_\(model.rawValue)_\(type.rawValue)_\(width)x\(height)_\(viewWidth)x\(viewHeight)_\(screenScale)_\(oledContrast)_\(threeD)") {
            let f = CGFloat(width) / CGFloat(max(viewWidth, 1))
            let band = lcdArea(model: model, width: width, viewWidth: viewWidth, viewHeight: viewHeight, screenScale: screenScale).bandHeight
            let top = band + Int(2 * f)
            return draw(width, height) { cg in
                keypad(model, type, cg, CGRect(x: 0, y: top, width: width, height: height - top), oledContrast, threeD)
            }
        }
    }

    /// Only the keypad, for the skin thumbnails.
    static func keypad(model: CalcModel, type: SkinType, width: Int, height: Int, oledContrast: Int = 70, threeD: Bool = false) -> CGImage {
        let variant = (type == .OLED ? "_c\(oledContrast)" : "") + (threeD ? "_3d" : "")
        let key = "thumb_\(model.rawValue)_\(type.rawValue)\(variant)_\(width)x\(height)_\(SkinCache.stamp)"
        return cached(key) {
            let file = thumbDir().appendingPathComponent("\(key).png")
            if let fromDisk = Graphics.image(contentsOf: file) { return fromDisk }
            let image = draw(width, height) { cg in
                keypad(model, type, cg, CGRect(x: 0, y: 0, width: width, height: height), oledContrast, threeD)
            }
            Graphics.writePNG(image, to: file)  // without the file the thumbnail is drawn again next time
            return image
        }
    }

    private static func draw(_ width: Int, _ height: Int, _ body: (CGContext) -> Void) -> CGImage {
        guard let cg = Graphics.context(width: width, height: height) else { return blank() }
        body(cg)
        return cg.makeImage() ?? blank()
    }

    private static func blank() -> CGImage {
        let cg = Graphics.context(width: 1, height: 1)!
        return cg.makeImage()!
    }

    private static func keypad(_ model: CalcModel, _ type: SkinType, _ cg: CGContext, _ area: CGRect, _ oledContrast: Int, _ threeD: Bool) {
        do {
            _ = try SkinRenderer.render(model: model, type: type, into: cg, area: area, oledContrast: oledContrast, threeD: threeD)
        } catch {
            cg.setFillColor(Graphics.color(0xFF40_4040))
            cg.fill(area)
        }
    }
}
