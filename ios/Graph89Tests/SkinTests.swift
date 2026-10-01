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

/// Where tests write pictures for a person to look at: G89_OUTPUT_DIR (set by CI through TEST_RUNNER_G89_OUTPUT_DIR),
/// or nowhere.
func testOutputDir(_ sub: String) -> URL? {
    guard let dir = ProcessInfo.processInfo.environment["G89_OUTPUT_DIR"], !dir.isEmpty else { return nil }
    let url = URL(fileURLWithPath: dir).appendingPathComponent(sub, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Every skin is drawn with the app's own renderer; with G89_OUTPUT_DIR set the pictures are written as PNGs (the same
/// sizes as the Android app's SkinRenderTest, to compare the two).
final class SkinTests: XCTestCase {
    /// The key codes of a layout file (both halves of the cursor bar).
    private func keyCodes(_ layout: String, model: CalcModel) throws -> Set<UInt8> {
        let json = try JSONSerialization.jsonObject(with: Assets.data("skin/\(layout).json")) as! [String: Any]
        var codes = Set<UInt8>()
        for k in json["keys"] as! [[String: Any]] {
            codes.insert(UInt8(k["code"] as! Int))
            if let down = k["codeDown"] as? Int, down >= 0 { codes.insert(UInt8(down)) }
        }
        return codes
    }

    func testRendersEverySkin() throws {
        let out = testOutputDir("skin-renders")
        for model in [CalcModel.TI89T, .TI84PLUS] {
            let h = model.engine == .tilem ? 1701 : 1733
            let codes = try keyCodes(model.engine == .tilem ? "ti84" : "ti89", model: model)
            for type in SkinType.allCases {
                for threeD in [false, true] {
                    let cg = try XCTUnwrap(Graphics.context(width: 1280, height: h))
                    let start = Date()
                    let r = try SkinRenderer.render(model: model, type: type, into: cg, area: CGRect(x: 0, y: 0, width: 1280, height: h), threeD: threeD)
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    print("rendered \(model.rawValue) \(type.rawValue)\(threeD ? " 3D" : "") in \(ms) ms")

                    XCTAssertEqual(r.mask.count, r.maskWidth * r.maskHeight)
                    XCTAssertEqual(r.maskHeight, 1014)
                    let inMask = Set(r.mask).subtracting([255])
                    XCTAssertEqual(inMask, codes, "\(model) \(type): every key, and only keys, in the touch mask")
                    XCTAssertTrue(r.keypad.maxY <= CGFloat(h) + 1 && r.keypad.minX >= -1, "\(model) \(type): keypad inside the area")

                    let image = try XCTUnwrap(cg.makeImage())
                    if let out {
                        Graphics.writePNG(image, to: out.appendingPathComponent("\(model.rawValue)_\(type.rawValue)\(threeD ? "_3D" : "").png"))
                    }
                }
            }
        }
    }

    func testTi83AndOriginalTi89Render() throws {
        let out = testOutputDir("skin-renders")
        for model in [CalcModel.TI83, .TI89] {
            let cg = try XCTUnwrap(Graphics.context(width: 1179, height: 1900))
            _ = try SkinRenderer.render(model: model, type: .CLASSIC, into: cg, area: CGRect(x: 0, y: 0, width: 1179, height: 1900))
            if let out, let image = cg.makeImage() {
                Graphics.writePNG(image, to: out.appendingPathComponent("\(model.rawValue)_CLASSIC_1179.png"))
            }
        }
    }

    /// A whole calculator view as on an iPhone 16 Pro (1206 x 2622 px minus the default margins).
    func testSkinLaysOutTheLcdAndKeys() throws {
        SkinCache.clearMemory()
        for model in CalcModel.allCases {
            let skin = Skin(type: .CLASSIC, model: model)
            var config = EmulatorConfig()
            config.skin3d = false
            try skin.initialize(width: 1206, height: 2420, config: config) {}
            let screen = try XCTUnwrap(skin.screen)
            XCTAssertEqual(screen.rawWidth, model.lcdWidth)
            XCTAssertGreaterThan(screen.destination.width, 1000, "\(model): the LCD fills the width")
            XCTAssertNil(skin.keyCode(atX: 600, y: 20), "\(model): no key on the LCD band")
            // the decimal point sits on the centre line of the bottom row on every model
            let bottom = stride(from: 2419, to: 2000, by: -4).lazy.compactMap { skin.keyCode(atX: 603, y: $0) }.first { $0 != 255 }
            let key = try XCTUnwrap(bottom, "\(model): a key in the bottom row")
            XCTAssertNotNil(skin.overlay(for: key))
            if let out = testOutputDir("skins"), let image = skin.image {
                Graphics.writePNG(image, to: out.appendingPathComponent("\(model.rawValue).png"))
            }
        }
    }

    func testBundledFallbackSkinsLoad() throws {
        // the pre-rendered skins (used only when drawing fails) and their masks are intact
        for dir in ["ti89classic", "ti89midnight", "ti89origclassic", "ti89origmidnight", "ti84classic", "ti84midnight", "ti83classic", "ti83midnight"] {
            XCTAssertNotNil(Graphics.image(contentsOf: Assets.url("portrait/\(dir)/skin.webp")), dir)
            let info = try String(contentsOf: Assets.url("portrait/\(dir)/info"), encoding: .utf8)
            XCTAssertTrue(info.contains("mask"), dir)
        }
    }

    func testCacheRoundTrip() throws {
        let cg = try XCTUnwrap(Graphics.context(width: 640, height: 900))
        let r = try SkinRenderer.render(model: .TI84PLUS, type: .NORD, into: cg, area: CGRect(x: 0, y: 0, width: 640, height: 900))
        let image = try XCTUnwrap(cg.makeImage())
        let key = SkinCache.key(model: .TI84PLUS, type: .NORD, width: 640, height: 900, oledContrast: 70, threeD: false) + "_test"
        SkinCache.put(key, SkinCache.Entry(image: image, keypad: r.keypad, mask: r.mask, maskWidth: r.maskWidth, maskHeight: r.maskHeight, backgroundColor: r.backgroundColor))
        // from disk, once the background write is done
        let deadline = Date().addingTimeInterval(10)
        var fromDisk: SkinCache.Entry?
        while Date() < deadline {
            SkinCache.clearMemory()
            if let e = SkinCache.get(key) { fromDisk = e; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let e = try XCTUnwrap(fromDisk)
        XCTAssertEqual(e.mask, r.mask)
        XCTAssertEqual(e.keypad, r.keypad)
        XCTAssertEqual(e.backgroundColor, r.backgroundColor)
        XCTAssertEqual(e.image.width, 640)
    }
}
