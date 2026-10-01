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
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The app's bundled assets: the Android app's assets folder (skin layouts, bundled skins, fonts, licences).
enum Assets {
    static let root: URL = Bundle.main.resourceURL!.appendingPathComponent("assets", isDirectory: true)

    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    static func data(_ path: String) throws -> Data { try Data(contentsOf: url(path)) }

    /// Makes the skin fonts (Roboto Medium, Noto Sans Symbols) available to Core Text by name, once.
    static let registerFonts: Void = {
        for file in ["fonts/Roboto-Medium.ttf", "fonts/NotoSansSymbols-Regular-Subsetted.ttf"] {
            CTFontManagerRegisterFontsForURL(url(file) as CFURL, .process, nil)
        }
    }()
}

/// Bitmaps the way the Android app's Canvas has them: pixels, origin at the top left, y going down, colours ARGB.
enum Graphics {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A transparent bitmap context of `width` x `height` pixels whose user space has y going down.
    static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0,
              let cg = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: 1, y: -1)
        return cg
    }

    static func color(_ argb: ARGB) -> CGColor {
        CGColor(
            srgbRed: CGFloat(argb >> 16 & 0xFF) / 255, green: CGFloat(argb >> 8 & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat(argb >> 24 & 0xFF) / 255
        )
    }

    /// `argb` with its alpha replaced by `alpha` (0...1).
    static func color(_ argb: ARGB, alpha: CGFloat) -> CGColor {
        CGColor(
            srgbRed: CGFloat(argb >> 16 & 0xFF) / 255, green: CGFloat(argb >> 8 & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255, alpha: alpha
        )
    }

    /// Draws `image` into `rect` of a y-down context (CGContext.draw alone would draw it upside down there).
    static func draw(_ image: CGImage, in rect: CGRect, of cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.maxY)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(image, in: CGRect(origin: .zero, size: rect.size))
        cg.restoreGState()
    }

    /// Reads any image file ImageIO knows (PNG, WebP).
    static func image(contentsOf url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
    }

    /// Writes `image` as a PNG file. Returns false on failure.
    @discardableResult
    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// The RGBA bytes (premultiplied, 4 per pixel, rows top first) of a context made by `context(width:height:)`.
    static func pixels(of cg: CGContext) -> (bytes: UnsafeMutablePointer<UInt8>, bytesPerRow: Int)? {
        guard let data = cg.data else { return nil }
        return (data.assumingMemoryBound(to: UInt8.self), cg.bytesPerRow)
    }
}
