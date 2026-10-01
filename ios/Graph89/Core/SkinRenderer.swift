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

/// Draws a skin on the phone at the exact size of the keypad area, so it is never stretched and always sharp.
/// The keypad layout from assets/skin/<layout>.json is widened or narrowed to the area's shape (keys spread and
/// lengthen, circles stay round, tilts follow the flatter row curve), then drawn in design units (1014 high)
/// scaled to the area.
/// The touch mask is rasterised from the same key shapes. Skin.swift falls back to the bundled images if this fails.
/// Safe to call from several threads at once: the only shared state is the parsed layouts (locked) and the font.
enum SkinRenderer {
    /// A drawn skin: where its design canvas landed in the output, and the touch mask (one cell per design unit).
    struct Result {
        let keypad: CGRect
        let mask: [UInt8]
        let maskWidth: Int
        let maskHeight: Int
        let backgroundColor: ARGB
    }

    // ---- layout data ----

    private struct Key {
        let name: String
        let kind: String
        var cx: CGFloat
        let cy: CGFloat
        var w: CGFloat
        let h: CGFloat
        var ang: CGFloat
        let r: [CGFloat]  // corner radii: tl tr br bl
        let wedge: Bool
        let mirror: Bool
        let rCorner: CGFloat
        let rFillet: CGFloat
        let sag: CGFloat
        let code: Int
        let codeDown: Int
        var legend: [String?]
        var lx: CGFloat = 0
        var ly: CGFloat = 0
    }

    private struct Layout {
        let name: String
        let baseW: CGFloat
        let axis: CGFloat
        var keys: [Key]
        let legends83: [String: [String?]]

        var ti84: Bool { name == "ti84" }

        func key(_ n: String) -> Key? { keys.first(where: { $0.name == n }) }
    }

    /// Guards the parsed layouts and the counter.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var layouts: [String: Layout] = [:]

    /// The layout in assets/skin/<name>.json, parsed once (callers change their own copy).
    private static func loadLayout(_ name: String) throws -> Layout {
        lock.lock()
        let cached = layouts[name]
        lock.unlock()
        if let cached = cached { return cached }

        let path = "skin/\(name).json"
        let bad = SkinError.badAsset(path)
        guard let j = try JSONSerialization.jsonObject(with: Assets.data(path)) as? [String: Any],
              let arr = j["keys"] as? [[String: Any]],
              let layoutName = j["layout"] as? String,
              let baseW = j["W"] as? NSNumber,
              let axis = j["axis"] as? NSNumber
        else { throw bad }
        func num(_ o: [String: Any], _ field: String) throws -> CGFloat {
            guard let n = o[field] as? NSNumber else { throw bad }
            return CGFloat(n.doubleValue)
        }
        func opt(_ o: [String: Any], _ field: String) -> CGFloat {
            CGFloat((o[field] as? NSNumber)?.doubleValue ?? 0)
        }
        func legend(_ v: Any?) throws -> [String?] {
            guard let a = v as? [Any] else { throw bad }
            return (0..<4).map { i -> String? in i < a.count ? (a[i] as? String) : nil }
        }
        var keys: [Key] = []
        for k in arr {
            guard let keyName = k["name"] as? String, let kind = k["kind"] as? String,
                  let r = k["r"] as? [NSNumber], r.count >= 4, let code = k["code"] as? NSNumber
            else { throw bad }
            let cx = try num(k, "cx"), cy = try num(k, "cy"), w = try num(k, "w"), h = try num(k, "h")
            let ang = try num(k, "ang")
            let lg = try legend(k["legend"])
            keys.append(Key(
                name: keyName, kind: kind, cx: cx, cy: cy, w: w, h: h, ang: ang,
                r: r.prefix(4).map { CGFloat($0.doubleValue) },
                wedge: (k["shape"] as? String) == "wedge", mirror: (k["mirror"] as? NSNumber)?.boolValue ?? false,
                rCorner: opt(k, "r_corner"), rFillet: opt(k, "r_fillet"), sag: opt(k, "sag"),
                code: code.intValue, codeDown: (k["codeDown"] as? NSNumber)?.intValue ?? -1, legend: lg
            ))
        }
        var l83: [String: [String?]] = [:]
        if let o = j["legends83"] as? [String: Any] {
            for (n, v) in o { l83[n] = try legend(v) }
        }
        let layout = Layout(
            name: layoutName, baseW: CGFloat(baseW.doubleValue), axis: CGFloat(axis.doubleValue), keys: keys, legends83: l83
        )
        lock.lock()
        layouts[name] = layout
        lock.unlock()
        return layout
    }

    // ---- themes ----

    private struct Theme {
        let bg0, bg1, caseColor, floor0, floor1: ARGB
        let fills: [String: ARGB]
        let blue, green, alpha, onLight, onDark, purple, ink, blackRim, shiftRing: ARGB
        let outline: ARGB?
        let outlineW: CGFloat
        let labelLift: CGFloat
        let shadow: Float
        let halo: ARGB?
        let haloW: CGFloat
        let haloOp: Float
        let palette: Palette?

        init(
            _ bg0: ARGB, _ bg1: ARGB, _ caseColor: ARGB, _ floor0: ARGB, _ floor1: ARGB, _ fills: [String: ARGB],
            _ blue: ARGB, _ green: ARGB, _ alpha: ARGB, _ onLight: ARGB, _ onDark: ARGB, _ purple: ARGB, _ ink: ARGB,
            _ blackRim: ARGB, _ shiftRing: ARGB, outline: ARGB? = nil, outlineW: CGFloat = 0, labelLift: CGFloat = 0,
            shadow: Float = 0.6, halo: ARGB? = nil, haloW: CGFloat = 1.6, haloOp: Float = 0.7, palette: Palette? = nil
        ) {
            self.bg0 = bg0
            self.bg1 = bg1
            self.caseColor = caseColor
            self.floor0 = floor0
            self.floor1 = floor1
            self.fills = fills
            self.blue = blue
            self.green = green
            self.alpha = alpha
            self.onLight = onLight
            self.onDark = onDark
            self.purple = purple
            self.ink = ink
            self.blackRim = blackRim
            self.shiftRing = shiftRing
            self.outline = outline
            self.outlineW = outlineW
            self.labelLift = labelLift
            self.shadow = shadow
            self.halo = halo
            self.haloW = haloW
            self.haloOp = haloOp
            self.palette = palette
        }
    }

    private enum Finish { case flat, neon, outline }

    /// A 7-colour skin: 2nd, ◆ and alpha (key and function text), number keys, other keys, recesses and
    /// default text; `body` is usually one of them. NEON draws dark keys with glowing
    /// outlines and legends in their role colour; OUTLINE (OLED) the same without the glow.
    private struct Palette {
        let c2nd, dia, alpha, num, keys, recess, text, body: ARGB
        let finish: Finish
        /// OUTLINE: outline of the keys other than 2nd / ◆ / alpha, and the APPS legend colour.
        let line: ARGB
        let apps: ARGB

        init(
            _ c2nd: ARGB, _ dia: ARGB, _ alpha: ARGB, _ num: ARGB, _ keys: ARGB, _ recess: ARGB, _ text: ARGB,
            _ body: ARGB, _ finish: Finish = .flat, line: ARGB = 0, apps: ARGB = 0
        ) {
            self.c2nd = c2nd
            self.dia = dia
            self.alpha = alpha
            self.num = num
            self.keys = keys
            self.recess = recess
            self.text = text
            self.body = body
            self.finish = finish
            self.line = line
            self.apps = apps
        }

        var all: [ARGB] { [c2nd, dia, alpha, num, keys, recess, text] }
    }

    private static func paletteTheme(_ p: Palette) -> Theme {
        Theme(
            p.body, p.body, p.recess, p.recess, p.recess, [:],
            p.c2nd, p.dia, p.alpha, p.text, p.text, p.text, p.text, p.text, p.text,
            outline: (p.finish == .neon || p.finish == .outline) ? nil : p.recess, outlineW: 1.6, labelLift: 1,
            shadow: 0.45, palette: p
        )
    }

    private static func pal(
        _ c2nd: String, _ dia: String, _ alpha: String, _ num: String, _ keys: String, _ recess: String, _ text: String,
        _ body: String, _ finish: Finish = .flat
    ) -> Palette {
        // body: the role whose colour the face reuses, or a colour of its own
        let cs = ["num": num, "keys": keys, "recess": recess]
        return Palette(c(c2nd), c(dia), c(alpha), c(num), c(keys), c(recess), c(text), c(cs[body] ?? body), finish)
    }

    /// OLED: pure black face and keys drawn as outlines (no glow), 2nd / ◆ / alpha outlined in their colours, the
    /// other keys in Classic's key grey; all text keeps Classic's colours (APPS purple).
    private static let OLED = Palette(
        c("#A4D3F6"), c("#CDE6A2"), c("#EEF1F4"), c("#000000"), c("#000000"), c("#0A0A0B"), c("#F4F5F7"),
        c("#000000"), .outline, line: c("#6A6D73"), apps: c("#C79BEA")
    )

    private static let PALETTES: [SkinType: Palette] = [
        .OLED: OLED,
        .NEON_GRID: pal("#00E5FF", "#FF9E1B", "#F2FDFF", "#0A2530", "#000000", "#07141B", "#7FEFFF", "keys", .neon),
        .EMBER: pal("#FF6B2C", "#FFC857", "#8FD3FF", "#3A3A40", "#222226", "#121214", "#EDEAE4", "num"),
        .FROST: pal("#3B82C4", "#2BA88F", "#8A5CC2", "#FFFFFF", "#2A4A66", "#B7CAD8", "#13202B", "num"),
        .SOLAR: pal("#268BD2", "#859900", "#D33682", "#073642", "#586E75", "#002B36", "#EEE8D5", "num"),
        .RETRO: pal("#E07A2E", "#3F8F5A", "#C23B3B", "#5B4636", "#2F2A26", "#D9CDB5", "#3A2E25", "recess"),
        .EMERALD: pal("#7CC6A4", "#E8C468", "#E58F65", "#2E5641", "#1B3325", "#0E1F16", "#EDE6D3", "num"),
        .BLOSSOM: pal("#D94F7E", "#3E9A88", "#7B63B8", "#FFFFFF", "#5B4453", "#F2D5DE", "#3D2632", "recess"),
        .NORD: pal("#88C0D0", "#A3BE8C", "#B48EAD", "#4C566A", "#3B4252", "#2E3440", "#ECEFF4", "recess"),
        .RADIOACTIVE: pal("#39FF14", "#C6FF5A", "#E6FFE0", "#0C230C", "#050C05", "#000000", "#8CFF8C", "keys", .neon),
        .ROYAL: pal("#E3B341", "#4FB3A9", "#D9D9E3", "#262D66", "#161A3D", "#0B0E24", "#E8E6F2", "recess"),
    ]

    private static let MIDNIGHT = Theme(
        c("#2a272c"), c("#141217"), c("#060507"), c("#070608"), c("#110f13"),
        ["fkey": c("#3b393f"), "gray": c("#3b393f"), "black": c("#1d1b20"), "dpad": c("#1d1b20"),
         "2nd": c("#a9dcf7"), "diamond": c("#bfe89a"), "alpha": c("#f7f7f5")],
        c("#a9dcf7"), c("#bfe89a"), c("#f7f7f5"), c("#141217"), c("#f2efeb"), c("#c89be3"), c("#f2efeb"),
        c("#85848a"), c("#f7f7f5")
    )

    /// Classic: the look of the TI-89 Titanium and the TI-83/84 family.
    private static let CLASSIC = Theme(
        c("#807D7F"), c("#807D7F"), c("#141518"), c("#2a2b2f"), c("#36373b"),
        ["fkey": c("#6a6d73"), "gray": c("#6a6d73"), "black": c("#1e1d21"), "dpad": c("#1e1d21"),
         "2nd": c("#a4d3f6"), "diamond": c("#cde6a2"), "alpha": c("#eef1f4")],
        c("#a4d3f6"), c("#cde6a2"), c("#eef1f4"), c("#15212c"), c("#ffffff"), c("#c79bea"), c("#f4f5f7"),
        c("#9a9ca2"), c("#ffffff"), outline: c("#1b1c1f"), outlineW: 1.6, labelLift: 1, shadow: 0.45,
        halo: c("#26272b"), haloW: 2, haloOp: 0.9
    )

    /// The original TI-89: navy face, yellow 2ND, teal ◆, purple ALPHA, blue F-keys and cursor pad.
    private static let TI89 = Theme(
        c("#2d3056"), c("#222544"), c("#0d0e18"), c("#141630"), c("#1b1d38"),
        ["fkey": c("#5d6bd6"), "gray": c("#1b1b24"), "black": c("#8c90c4"), "dpad": c("#5d6bd6"),
         "2nd": c("#f0cf2e"), "diamond": c("#2fb5a6"), "alpha": c("#7a3f9e")],
        c("#f3dc6a"), c("#46cbbb"), c("#c59cf0"), c("#15151f"), c("#ffffff"), c("#ffffff"), c("#f2f2fa"),
        c("#5d6bd6"), c("#ffffff"), outline: c("#0d0e18"), outlineW: 1.6, labelLift: 1, shadow: 0.45
    )

    /// Grayscale skin: white face, black keys, black function text; ◆ functions in grey to tell them apart.
    private static let MONO = Theme(
        c("#f7f7f7"), c("#e4e4e4"), c("#0c0c0c"), c("#c9c9c9"), c("#dadada"),
        ["fkey": c("#1a1a1a"), "gray": c("#1a1a1a"), "black": c("#000000"), "dpad": c("#000000"),
         "2nd": c("#ffffff"), "diamond": c("#ffffff"), "alpha": c("#ffffff")],
        c("#111111"), c("#6b6b6b"), c("#111111"), c("#000000"), c("#ffffff"), c("#ffffff"), c("#ffffff"),
        c("#5a5a5a"), c("#ffffff"), outline: c("#000000"), outlineW: 1.6, labelLift: 1, shadow: 0.3
    )

    /// OLED with its text and outlines dimmed to `contrast` percent (toward black).
    private static func oled(_ contrast: Int) -> Palette {
        let f = Float(min(max(contrast, 0), 100)) / 100
        func d(_ color: ARGB) -> ARGB { mix(BLACK, color, f) }
        let p = OLED
        return Palette(
            d(p.c2nd), d(p.dia), d(p.alpha), p.num, p.keys, p.recess, d(p.text), p.body, p.finish,
            line: d(p.line), apps: d(p.apps)
        )
    }

    private static func themeFor(_ model: CalcModel, _ type: SkinType, _ oledContrast: Int) -> Theme {
        if type == .OLED { return paletteTheme(oled(oledContrast)) }
        if let p = PALETTES[type] { return paletteTheme(p) }
        if type == .MONO { return MONO }
        if type == .MIDNIGHT { return MIDNIGHT }
        if model == .TI89 { return TI89 }
        return CLASSIC
    }

    // ---- entry point ----

    /// Roboto Medium, with Noto Sans Symbols for the legend symbols Roboto lacks (arrows, ◆, ▸, ∠, ⇄), so they look
    /// the same on every phone. Nil when Roboto does not load.
    private static let skinFont: CTFontDescriptor? = {
        _ = Assets.registerFonts
        // the PostScript names inside the bundled font files
        let symbols = CTFontDescriptorCreateWithNameAndSize("NotoSansSymbols" as CFString, 0)
        let attrs: [CFString: Any] = [kCTFontNameAttribute: "Roboto-Medium", kCTFontCascadeListAttribute: [symbols]]
        let byName = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        if CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(byName, 12, nil)) as String == "Roboto-Medium" {
            return byName
        }
        // not registered by name: take the fonts straight from their files
        func file(_ path: String) -> CTFontDescriptor? {
            guard let data = try? Assets.data(path) else { return nil }
            return CTFontManagerCreateFontDescriptorFromData(data as CFData)
        }
        guard let roboto = file("fonts/Roboto-Medium.ttf") else { return nil }
        guard let noto = file("fonts/NotoSansSymbols-Regular-Subsetted.ttf") else { return roboto }
        let cascade: [CFString: Any] = [kCTFontCascadeListAttribute: [noto]]
        return CTFontDescriptorCreateCopyWithAttributes(roboto, cascade as CFDictionary)
    }()

    /// Number of skins drawn so far (tests use it to check the caches).
    nonisolated(unsafe) private(set) static var renders = 0

    /// Draws the skin of `model` into `cg` inside `area` (the keypad part of the view, in pixels of a y-down context
    /// made by Graphics.context) and returns the placement of the design canvas and the touch mask. Throws on any
    /// failure (the caller falls back).
    static func render(
        model: CalcModel, type: SkinType, into cg: CGContext, area: CGRect, oledContrast: Int = 70, threeD: Bool = false
    ) throws -> Result {
        lock.lock()
        renders += 1
        lock.unlock()
        guard area.width >= 1, area.height >= 1 else { throw SkinError.badAsset("keypad area") }
        var layout = try loadLayout(model.engine == .tilem ? "ti84" : "ti89")
        if model == .TI83 {
            for i in layout.keys.indices {
                if let l = layout.legends83[layout.keys[i].name] { layout.keys[i].legend = l }
            }
        }
        guard let font = skinFont else { throw SkinError.badAsset("fonts/Roboto-Medium.ttf") }
        let theme = themeFor(model, type, oledContrast)

        // design width for this area's shape, within what the layout can take without cramping or gaps
        let aspect = area.width / area.height
        let minW = layout.baseW * (layout.ti84 ? 0.82 : 0.9)
        let maxW = layout.baseW * (layout.ti84 ? 1.35 : 1.45)
        let w2 = min(max(aspect * H, minW), maxW)
        let scale = min(area.width / w2, area.height / H)
        let left = area.minX + (area.width - w2 * scale) / 2
        let top = area.maxY - H * scale  // keypad at the bottom; any space above belongs to the body

        let d = try Drawer(layout, theme, font, model, w2, scale, threeD)

        cg.saveGState()
        cg.clip(to: area)
        cg.setFillColor(Graphics.color(theme.bg0))
        cg.fill(area)
        // extra space above the design canvas (very tall areas): the body continues up
        if top > area.minY {
            cg.fill(CGRect(x: left, y: area.minY, width: w2 * scale, height: top + 1 - area.minY))
        }
        cg.translateBy(x: left, y: top)
        cg.scaleBy(x: scale, y: scale)
        d.draw(cg)
        cg.restoreGState()

        let mw = Int(w2.rounded(.up))
        guard let mask = d.mask(mw, Int(H)) else { throw SkinError.noMemory }
        let l = Int(left), t = Int(top), r = Int(left + w2 * scale), b = Int(area.maxY)
        return Result(
            keypad: CGRect(x: l, y: t, width: r - l, height: b - t), mask: mask, maskWidth: mw, maskHeight: Int(H),
            backgroundColor: theme.bg0
        )
    }

    // ---- drawing ----

    /// A run of label text in one colour; `sup`: set as raised small text.
    private struct Run {
        let text: String
        let color: ARGB
        let sup: Bool

        init(_ text: String, _ color: ARGB, _ sup: Bool) {
            self.text = text
            self.color = color
            self.sup = sup
        }
    }

    /// Type sizes, design units.
    private struct Sizes {
        let digit: CGFloat
        let fkey: CGFloat
        let key: CGFloat
        let label: CGFloat
    }

    /// A path built the way android.graphics.Path builds one. `bounds` is what Path.computeBounds gives: the box of
    /// all its points, control points included, with arcs split into conics the way Skia splits them (the recess
    /// gradients span it, so it must match).
    private final class PathBuilder {
        let cg = CGMutablePath()
        private var minX = CGFloat.infinity
        private var minY = CGFloat.infinity
        private var maxX = -CGFloat.infinity
        private var maxY = -CGFloat.infinity

        var bounds: CGRect {
            minX <= maxX ? CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY) : .zero
        }

        private func add(_ x: CGFloat, _ y: CGFloat) {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }

        /// The path already ends at (x, y) (Skia's nearly-equal test).
        func isAt(_ x: CGFloat, _ y: CGFloat) -> Bool {
            if cg.isEmpty { return false }
            let p = cg.currentPoint
            let tolerance: CGFloat = 1.0 / 4096
            return abs(p.x - x) <= tolerance && abs(p.y - y) <= tolerance
        }

        func moveTo(_ x: CGFloat, _ y: CGFloat) {
            cg.move(to: CGPoint(x: x, y: y))
            add(x, y)
        }

        func lineTo(_ x: CGFloat, _ y: CGFloat) {
            cg.addLine(to: CGPoint(x: x, y: y))
            add(x, y)
        }

        func quadTo(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            cg.addQuadCurve(to: CGPoint(x: x2, y: y2), control: CGPoint(x: x1, y: y1))
            add(x1, y1)
            add(x2, y2)
        }

        func cubicTo(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x3: CGFloat, _ y3: CGFloat) {
            cg.addCurve(to: CGPoint(x: x3, y: y3), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            add(x1, y1)
            add(x2, y2)
            add(x3, y3)
        }

        func close() {
            cg.closeSubpath()
        }

        /// Path.arcTo(the circle's oval, startDeg, sweepDeg): a line to the arc's start unless the path is there
        /// already, then the arc; angle a is the point (cx + r cos a, cy + r sin a), so a positive sweep turns
        /// clockwise on screen (y down).
        func arcTo(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ startDeg: CGFloat, _ sweepDeg: CGFloat) {
            func at(_ deg: CGFloat, _ dist: CGFloat) -> CGPoint {
                let a = deg * .pi / 180
                return CGPoint(x: cx + dist * cos(a), y: cy + dist * sin(a))
            }
            let start = at(startDeg, r)
            if cg.isEmpty {
                moveTo(start.x, start.y)
            } else if !isAt(start.x, start.y) {
                lineTo(start.x, start.y)
            }
            // the arc itself as cubic Béziers of at most 90° each
            let n = max(1, Int((abs(sweepDeg) / 90).rounded(.up)))
            let step = sweepDeg / CGFloat(n) * .pi / 180
            let kk = CGFloat(4) / 3 * tan(step / 4)
            var a = startDeg * .pi / 180
            for _ in 0..<n {
                let b = a + step
                cg.addCurve(
                    to: CGPoint(x: cx + r * cos(b), y: cy + r * sin(b)),
                    control1: CGPoint(x: cx + r * (cos(a) - kk * sin(a)), y: cy + r * (sin(a) + kk * cos(a))),
                    control2: CGPoint(x: cx + r * (cos(b) + kk * sin(b)), y: cy + r * (sin(b) - kk * cos(b)))
                )
                a = b
            }
            // bounds as Skia's: one conic per quarter turn from the start (control point at the square's corner),
            // then one for the rest (control point on the bisector)
            let dir: CGFloat = sweepDeg < 0 ? -1 : 1
            let quarters = Int(abs(sweepDeg) / 90)
            for i in 0..<quarters {
                let p = at(startDeg + dir * (CGFloat(i) * 90 + 45), r * CGFloat(2).squareRoot())
                add(p.x, p.y)
                let q = at(startDeg + dir * CGFloat(i + 1) * 90, r)
                add(q.x, q.y)
            }
            let rest = abs(sweepDeg) - CGFloat(quarters) * 90
            if rest > 0 {
                let p = at(startDeg + dir * (CGFloat(quarters) * 90 + rest / 2), r / cos(rest / 2 * .pi / 180))
                add(p.x, p.y)
            }
            let end = at(startDeg + sweepDeg, r)
            add(end.x, end.y)
        }
    }

    private final class Drawer {
        let base: Layout
        let t: Theme
        let descriptor: CTFontDescriptor
        let model: CalcModel
        let w2: CGFloat
        let scale: CGFloat
        let threeD: Bool
        let keys: [Key]
        let axis: CGFloat
        let sx: CGFloat
        let fk: [Key]
        let decorDx: CGFloat
        private let cap: CGFloat
        private let sizes: Sizes
        let pal: Palette?
        private let numpad: Set<String> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "DOT", "NEG", "DECPNT", "CHS"]
        /// Fonts by size (this drawer's own: one drawer per render).
        private var fonts: [CGFloat: CTFont] = [:]

        init(
            _ base: Layout, _ t: Theme, _ descriptor: CTFontDescriptor, _ model: CalcModel, _ w2: CGFloat,
            _ scale: CGFloat, _ threeD: Bool
        ) throws {
            let ref = base.ti84 ? ["MATH", "MATH", "YEQU"] : ["HOME", "CATALOG", "F1"]
            guard let pill = base.key(ref[0]), let catalogKey = base.key(ref[1]), let fKey = base.key(ref[2]),
                  let numKey = base.key("8"), let up = base.key("UP"), base.key("LEFT") != nil, base.key("RIGHT") != nil
            else { throw SkinError.badAsset("skin/\(base.name).json") }
            self.base = base
            self.t = t
            self.descriptor = descriptor
            self.model = model
            self.w2 = w2
            self.scale = scale
            self.threeD = threeD
            let axis = w2 / 2
            self.axis = axis
            sx = w2 / 635
            pal = t.palette

            // type sizes come from the base layout, so text keeps its size when widened
            let big = CTFontCreateWithFontDescriptor(descriptor, 1000, nil)
            let cap = -Drawer.inkBounds(Drawer.makeLine("H", big)).minY / 1000
            self.cap = cap
            let word = 0.30 * pill.h / cap
            let catalog = 0.8 * catalogKey.w / (Drawer.advance(Drawer.makeLine("CATALOG", big)) / 1000)
            sizes = Sizes(
                digit: 0.40 * numKey.h / cap, fkey: 0.27 * fKey.w / cap, key: (word + catalog) / 2,
                label: 0.20 * pill.h / cap + 4.0 / 3.0
            )

            // widen: spread the keys from the axis, lengthen the pills, move the cursor pad as one piece
            let f = w2 / base.baseW
            let kw = 1 + 0.557 * (f - 1)
            func spread(_ x: CGFloat) -> CGFloat { axis + (x - base.axis) * f }
            let oldEdge = base.key("SUB").map { $0.cx + $0.w / 2 } ?? 0
            let padDx = spread(up.cx) - up.cx
            var keys: [Key] = []
            for b in base.keys {
                var k = b
                if k.kind == "dpad" {
                    k.cx += padDx
                } else {
                    k.cx = spread(k.cx)
                    if k.kind != "fkey" { k.w *= kw }
                    k.ang = atan(tan(k.ang * .pi / 180) / f) * 180 / .pi
                }
                if k.wedge { Drawer.wedgeCentre(&k) }
                keys.append(k)
            }
            self.keys = keys
            let fNames: Set<String> = ["F1", "F2", "F3", "F4", "F5"]
            fk = base.ti84 ? [] : keys.filter { fNames.contains($0.name) }
            // the contrast bracket (drawn in 635-wide base coordinates) follows the right column
            decorDx = keys.first(where: { $0.name == "SUB" }).map { $0.cx + $0.w / 2 - oldEdge } ?? 0
        }

        func k(_ n: String) -> Key { keys.first(where: { $0.name == n }) ?? keys[0] }

        func draw(_ cg: CGContext) {
            cg.setMiterLimit(4)  // Skia's default (Core Graphics': 10)
            // the face fills the whole keypad area (no curved bottom corners)
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: 0, width: w2, height: H))
            // body: radial gradient centred at (.5, .25) of the canvas, radius .9 of each side
            if let g = gradient([t.bg0, t.bg1], [0, 1]) {
                cg.saveGState()
                cg.translateBy(x: w2 / 2, y: H / 4)
                cg.scaleBy(x: 0.9 * w2, y: 0.9 * H)
                cg.drawRadialGradient(
                    g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [.drawsAfterEndLocation]
                )
                cg.restoreGState()
            }

            if !fk.isEmpty { recess(cg, frecess()) }
            recess(cg, drecess())
            for k in keys { key(cg, k) }
            over(cg)
            for k in keys { legend(cg, k) }
            if !base.ti84 { decor(cg) }
            cg.restoreGState()
        }

        /// The key's palette role colour: 2nd, ◆, alpha, number keys or other keys.
        private func roleColor(_ p: Palette, _ k: Key) -> ARGB {
            if k.kind == "2nd" { return p.c2nd }
            if k.kind == "diamond" { return p.dia }
            if k.kind == "alpha" { return p.alpha }
            if numpad.contains(k.name) { return p.num }
            return p.keys
        }

        private func fillOf(_ k: Key) -> ARGB {
            // "white" (TI-84 number keys) = the ALPHA key colour
            guard let p = pal else { return t.fills[k.kind] ?? t.fills["alpha"] ?? BLACK }
            if p.finish == .neon { return numpad.contains(k.name) ? p.num : p.keys }
            if p.finish == .outline { return p.keys }
            return roleColor(p, k)
        }

        /// Neon outline colour: 2nd / ◆ / alpha in their colour, number keys in the 2nd colour, the rest in text colour.
        private func outlineOf(_ p: Palette, _ k: Key) -> ARGB {
            if k.kind == "2nd" || k.kind == "diamond" || k.kind == "alpha" { return roleColor(p, k) }
            if p.finish == .outline { return p.line }
            if numpad.contains(k.name) { return p.c2nd }
            return p.text
        }

        // ---- shapes ----

        /// Key outline in the key's own (unrotated) frame; `off` > 0 grows it.
        func kpath(_ k: Key, _ off: CGFloat = 0) -> CGPath {
            let w = k.w / 2 + off
            let h = k.h / 2 + off
            let x0 = k.cx - w, x1 = k.cx + w, y0 = k.cy - h, y1 = k.cy + h
            if k.name == "UP" { return hourglass(k, off, x0, x1, y0, y1) }
            if k.wedge { return wedge(k, x0, x1, y0, y1) }
            let rr = (0..<4).map { i -> CGFloat in max(0, min(k.r[i] + off, min(w, h))) }  // tl tr br bl
            return roundRect(x0, y0, x1, y1, rr)
        }

        /// Path.addRoundRect with one radius per corner (tl tr br bl), clockwise.
        private func roundRect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ rr: [CGFloat]) -> CGPath {
            let p = PathBuilder()
            // no zero-length sides (a full circle has none)
            func side(_ x: CGFloat, _ y: CGFloat) {
                if !p.isAt(x, y) { p.lineTo(x, y) }
            }
            p.moveTo(x0 + rr[0], y0)
            side(x1 - rr[1], y0)
            if rr[1] > 0 { p.arcTo(x1 - rr[1], y0 + rr[1], rr[1], 270, 90) }
            side(x1, y1 - rr[2])
            if rr[2] > 0 { p.arcTo(x1 - rr[2], y1 - rr[2], rr[2], 0, 90) }
            side(x0 + rr[3], y1)
            if rr[3] > 0 { p.arcTo(x0 + rr[3], y1 - rr[3], rr[3], 90, 90) }
            side(x0, y0 + rr[0])
            if rr[0] > 0 { p.arcTo(x0 + rr[0], y0 + rr[0], rr[0], 180, 90) }
            p.close()
            return p.cg
        }

        private func hourglass(_ k: Key, _ off: CGFloat, _ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> CGPath {
            let w = k.w / 2 + off
            let r = w
            let wr = 0.6 * (w - off) + off
            let cx = k.cx, cy = k.cy
            let ya = y0 + r, yb = y1 - r
            let k1 = (cy - ya) * 0.5, k2 = (cy - ya) * 0.45
            let p = PathBuilder()
            p.moveTo(x0, ya)
            p.arcTo(cx, ya, r, 180, 180)
            p.cubicTo(x1, ya + k1, cx + wr, cy - k2, cx + wr, cy)
            p.cubicTo(cx + wr, cy + k2, x1, yb - k1, x1, yb)
            p.arcTo(cx, yb, r, 0, 180)
            p.cubicTo(x0, yb - k1, cx - wr, cy + k2, cx - wr, cy)
            p.cubicTo(cx - wr, cy - k2, x0, ya + k1, x0, ya)
            p.close()
            return p.cg
        }

        struct WedgeParts {
            let c: [CGFloat]
            let R: CGFloat
            let fx: CGFloat
            let fy: CGFloat
            let t1: [CGFloat]
            let t2: [CGFloat]
        }

        static func wedgeParts(_ k: Key, _ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> WedgeParts {
            let rf = k.rFillet
            let ww = x1 - x0, hh = y1 - y0, l = hyp(ww, hh)
            let mx = (x0 + x1) / 2, my = (y0 + y1) / 2
            let nx = hh / l, ny = ww / l
            let s = k.sag * l
            let r = (l * l / 4 + s * s) / (2 * s)
            let c = [mx - nx * (r - s), my - ny * (r - s)]
            let fx = c[0] + ((r - rf) * (r - rf) - (y0 + rf - c[1]) * (y0 + rf - c[1])).squareRoot()
            let fy = c[1] + ((r - rf) * (r - rf) - (x0 + rf - c[0]) * (x0 + rf - c[0])).squareRoot()
            func onArc(_ px: CGFloat, _ py: CGFloat) -> [CGFloat] {
                [c[0] + (px - c[0]) * r / (r - rf), c[1] + (py - c[1]) * r / (r - rf)]
            }
            return WedgeParts(c: c, R: r, fx: fx, fy: fy, t1: onArc(fx, y0 + rf), t2: onArc(x0 + rf, fy))
        }

        /// ENTER-shaped wedge (ON is its mirror image): straight top and left, a rounded diagonal bottom-right.
        private func wedge(_ k: Key, _ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> CGPath {
            let p = Drawer.wedgeParts(k, x0, x1, y0, y1)
            let rt = k.rCorner, rf = k.rFillet
            let path = PathBuilder()
            path.moveTo(x0, y0 + rt)
            arc(path, x0 + rt, y0 + rt, rt, x0, y0 + rt, x0 + rt, y0, true)
            path.lineTo(p.fx, y0)
            arc(path, p.fx, y0 + rf, rf, p.fx, y0, p.t1[0], p.t1[1], true)
            arc(path, p.c[0], p.c[1], p.R, p.t1[0], p.t1[1], p.t2[0], p.t2[1], true)
            arc(path, x0 + rf, p.fy, rf, p.t2[0], p.t2[1], x0, p.fy, true)
            path.close()
            if !k.mirror { return path.cg }
            let mirrored = CGMutablePath()
            mirrored.addPath(path.cg, transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * k.cx, ty: 0))
            return mirrored
        }

        /// Legend offset for a wedge key: its area centroid.
        static func wedgeCentre(_ k: inout Key) {
            let x0 = k.cx - k.w / 2, x1 = k.cx + k.w / 2, y0 = k.cy - k.h / 2, y1 = k.cy + k.h / 2
            let p = wedgeParts(k, x0, x1, y0, y1)
            var sxs = 0.0, sys = 0.0
            var n = 0
            var y = y0
            while y < y1 {
                var x = x0
                while x < x1 {
                    if (x - p.c[0]) * (x - p.c[0]) + (y - p.c[1]) * (y - p.c[1]) <= p.R * p.R {
                        sxs += Double(x)
                        sys += Double(y)
                        n += 1
                    }
                    x += 0.5
                }
                y += 0.5
            }
            if n == 0 { return }
            let dx = CGFloat(sxs / Double(n)) - k.cx
            k.lx = k.mirror ? -dx : dx
            k.ly = CGFloat(sys / Double(n)) - k.cy
        }

        /// Circular arc around (cx, cy) from one point to another, clockwise (y down) or counter-clockwise.
        private func arc(
            _ p: PathBuilder, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ fx: CGFloat, _ fy: CGFloat, _ tx: CGFloat,
            _ ty: CGFloat, _ clockwise: Bool
        ) {
            let a0 = atan2(fy - cy, fx - cx) * 180 / .pi
            let a1 = atan2(ty - cy, tx - cx) * 180 / .pi
            var sweep = ((a1 - a0).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            if !clockwise { sweep -= 360 }
            if abs(sweep) < 1e-3 || abs(sweep) > 359.999 {
                p.lineTo(tx, ty)
                return
            }
            p.arcTo(cx, cy, r, a0, sweep)
        }

        /// Smooth outline around a loop of circles (x, y, r), visited clockwise, with concave fillets between them.
        private func blob(_ circles: [[CGFloat]], _ rho: CGFloat) -> PathBuilder {
            let n = circles.count
            var fil = [[CGFloat]](repeating: [0, 0, 0, 0, 0, 0], count: n)  // t1, t2, fillet centre
            for i in 0..<n {
                let x1 = circles[i][0], y1 = circles[i][1], r1 = circles[i][2]
                let next = circles[(i + 1) % n]
                let x2 = next[0], y2 = next[1], r2 = next[2]
                let dx = x2 - x1, dy = y2 - y1, dd = hyp(dx, dy)
                let a = r1 + rho, b = r2 + rho
                let tt = (a * a - b * b + dd * dd) / (2 * dd)
                let hgt = max(a * a - tt * tt, 0).squareRoot()
                let ox = dy / dd, oy = -dx / dd
                let px = x1 + dx / dd * tt + ox * hgt, py = y1 + dy / dd * tt + oy * hgt
                fil[i] = [
                    x1 + (px - x1) * r1 / a, y1 + (py - y1) * r1 / a,
                    x2 + (px - x2) * r2 / b, y2 + (py - y2) * r2 / b, px, py,
                ]
            }
            let p = PathBuilder()
            p.moveTo(fil[n - 1][2], fil[n - 1][3])
            for i in 0..<n {
                let x = circles[i][0], y = circles[i][1], r = circles[i][2]
                let s = fil[(i - 1 + n) % n]
                arc(p, x, y, r, s[2], s[3], fil[i][0], fil[i][1], true)
                arc(p, fil[i][4], fil[i][5], rho, fil[i][0], fil[i][1], fil[i][2], fil[i][3], false)
            }
            p.close()
            return p
        }

        private func frecess(_ pad: CGFloat = 7, _ rho0: CGFloat = 24) -> PathBuilder {
            let cs = fk.map { [$0.cx, $0.cy, $0.w / 2 + pad] }
            let r = cs[0][2]
            let n: CGFloat = 9
            var dmax: CGFloat = 0
            for i in 1..<cs.count {
                dmax = max(dmax, hyp(cs[i - 1][0] - cs[i][0], cs[i - 1][1] - cs[i][1]))
            }
            let rho = max(rho0, ((dmax / 2) * (dmax / 2) + n * n - r * r) / (2 * (r - n)))
            return blob(cs + Array(cs[1..<(cs.count - 1)].reversed()), rho)
        }

        private func drecess(_ pad: CGFloat = 9, _ rho: CGFloat = 16) -> PathBuilder {
            let u = k("UP"), l = k("LEFT"), r = k("RIGHT")
            let ru = u.w / 2
            return blob(
                [
                    [u.cx, u.cy - u.h / 2 + ru, ru + pad], [r.cx, r.cy, r.w / 2 + pad],
                    [u.cx, u.cy + u.h / 2 - ru, ru + pad], [l.cx, l.cy, l.w / 2 + pad],
                ],
                rho
            )
        }

        // ---- painting ----

        private func gradient(_ colors: [ARGB], _ locations: [CGFloat]) -> CGGradient? {
            CGGradient(colorsSpace: Graphics.colorSpace, colors: colors.map { Graphics.color($0) } as CFArray, locations: locations)
        }

        private func fillShape(_ cg: CGContext, _ path: CGPath, _ color: ARGB) {
            cg.addPath(path)
            cg.setFillColor(Graphics.color(color))
            cg.fillPath()
        }

        private func strokeShape(_ cg: CGContext, _ path: CGPath, _ width: CGFloat, _ color: ARGB) {
            cg.addPath(path)
            cg.setLineWidth(width)
            cg.setStrokeColor(Graphics.color(color))
            cg.strokePath()
        }

        /// The path filled with a vertical LinearGradient from y0 to y1 (CLAMP).
        private func fillGradient(
            _ cg: CGContext, _ path: CGPath, _ y0: CGFloat, _ y1: CGFloat, _ colors: [ARGB], _ locations: [CGFloat]
        ) {
            guard let g = gradient(colors, locations) else { return }
            cg.saveGState()
            cg.addPath(path)
            cg.clip()
            cg.drawLinearGradient(
                g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            cg.restoreGState()
        }

        /// The path stroked `width` wide with a vertical LinearGradient from y0 to y1 (CLAMP).
        private func strokeGradient(
            _ cg: CGContext, _ path: CGPath, _ width: CGFloat, _ y0: CGFloat, _ y1: CGFloat, _ colors: [ARGB],
            _ locations: [CGFloat]
        ) {
            guard let g = gradient(colors, locations) else { return }
            cg.saveGState()
            cg.addPath(path)
            cg.setLineWidth(width)
            cg.replacePathWithStrokedPath()
            cg.clip()
            cg.drawLinearGradient(
                g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            cg.restoreGState()
        }

        /// A vector of the current user space in device pixels, where Core Graphics takes shadow offsets (device y
        /// goes up; Android's shadow offsets turn and scale with the canvas, so these do too).
        private func device(_ cg: CGContext, _ dx: CGFloat, _ dy: CGFloat) -> CGSize {
            let m = cg.ctm
            return CGSize(width: m.a * dx + m.c * dy, height: m.b * dx + m.d * dy)
        }

        /// An Android blur radius (design units) as a Core Graphics shadow blur: Skia blurs with
        /// sigma = 0.57735 r + 0.5, a Core Graphics blur is about 2 sigma, in device pixels.
        private func blur(_ radius: CGFloat) -> CGFloat {
            2 * (0.57735 * radius + 0.5) * scale
        }

        /// Draws what `shapes` draws as Android's BlurMaskFilter(radius) in `color` would: blurred only. The shapes
        /// go far off the canvas, and only their shadow, carried back by its offset, lands.
        private func blurred(_ cg: CGContext, _ radius: CGFloat, _ color: ARGB, _ shapes: () -> Void) {
            let far: CGFloat = 16384  // device pixels, a whole number: shadow offsets may be truncated
            let inv = cg.ctm.inverted()
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: far, height: 0), blur: blur(radius), color: Graphics.color(color))
            cg.translateBy(x: -far * inv.a, y: -far * inv.b)
            shapes()
            cg.restoreGState()
        }

        /// A recess: gradient floor, the shadow of its upper wall, light on its lower lip.
        private func recess(_ cg: CGContext, _ path: PathBuilder) {
            let b = path.bounds
            fillGradient(cg, path.cg, b.minY, b.maxY, [t.floor0, t.floor1], [0, 1])
            cg.saveGState()
            cg.addPath(path.cg)
            cg.clip()
            // everything but the path moved down 4 (Android: INVERSE_WINDING), as far out as the blur reaches
            let wall = CGMutablePath()
            wall.addRect(b.insetBy(dx: -40, dy: -40))
            wall.addPath(path.cg, transform: CGAffineTransform(translationX: 0, y: 4))
            blurred(cg, 6, withAlpha(BLACK, 0.85)) {
                cg.addPath(wall)
                cg.setFillColor(Graphics.color(BLACK))
                cg.fillPath(using: .evenOdd)
            }
            cg.restoreGState()
            strokeGradient(
                cg, path.cg, 1.6, b.minY, b.maxY,
                [withAlpha(BLACK, 0.9), withAlpha(WHITE, 0), withAlpha(WHITE, 0.16)], [0, 0.45, 1]
            )
        }

        private func rotated(_ cg: CGContext, _ k: Key, _ body: () -> Void) {
            cg.saveGState()
            if k.ang != 0 {
                cg.translateBy(x: k.cx, y: k.cy)
                cg.rotate(by: k.ang * .pi / 180)
                cg.translateBy(x: -k.cx, y: -k.cy)
            }
            body()
            cg.restoreGState()
        }

        /// The 3D finish of a key: satin gradient, soft bevel at the bottom, light rim at the top.
        private func satin(_ cg: CGContext, _ k: Key, _ fill: ARGB) {
            let y0 = k.cy - k.h / 2, y1 = k.cy + k.h / 2
            fillGradient(cg, kpath(k), y0, y1, [mix(fill, WHITE, 0.16), fill, mix(fill, BLACK, 0.12)], [0, 0.55, 1])
            strokeGradient(
                cg, kpath(k, -0.9), 1.8, y0, y1, [withAlpha(BLACK, 0), withAlpha(BLACK, 0), withAlpha(BLACK, 0.35)], [0, 0.5, 1]
            )
        }

        private func rim(_ cg: CGContext, _ k: Key) {
            strokeGradient(
                cg, kpath(k, -0.7), 1.4, k.cy - k.h / 2, k.cy + k.h / 2,
                [withAlpha(WHITE, 0.22), withAlpha(WHITE, 0.03), withAlpha(WHITE, 0.03)], [0, 0.5, 1]
            )
        }

        private func shiftRing(_ cg: CGContext, _ k: Key) {
            if k.name == "SHIFT" { strokeShape(cg, kpath(k, -7), 1.8, pal != nil ? legendColor(k) : t.shiftRing) }
        }

        private func key(_ cg: CGContext, _ k: Key) {
            rotated(cg, k) {
                let fill = fillOf(k)
                if let p = pal, p.finish == .neon || p.finish == .outline {
                    let lineColor = outlineOf(p, k)
                    if p.finish == .neon {
                        let glow = kpath(k, 0.5)
                        blurred(cg, 4.5, withAlpha(lineColor, 0.45)) {
                            cg.addPath(glow)
                            cg.setLineWidth(6)
                            cg.setStrokeColor(Graphics.color(BLACK))
                            cg.strokePath()
                        }
                    }
                    fillShape(cg, kpath(k), fill)
                    if threeD { satin(cg, k, mix(fill, lineColor, 0.12)) }  // a hint of the outline colour, so the satin shows on black
                    strokeShape(cg, kpath(k, -1), 2, lineColor)
                    if p.finish == .outline { shiftRing(cg, k) }
                    return
                }
                if let outline = t.outline { fillShape(cg, kpath(k, t.outlineW), outline) }
                // solid pass for the shadow (a shadow on a gradient paint would take the gradient's colours)
                cg.saveGState()
                cg.setShadow(offset: device(cg, 0, 3), blur: blur(4.6), color: Graphics.color(withAlpha(BLACK, t.shadow)))
                fillShape(cg, kpath(k), fill)
                cg.restoreGState()
                if threeD { satin(cg, k, fill) }
                rim(cg, k)
                if !threeD && (k.kind == "black" || k.kind == "dpad") {
                    strokeShape(cg, kpath(k, -0.5), 1, withAlpha(t.blackRim, 0.35))
                }
                shiftRing(cg, k)
            }
        }

        /// Cursor pad marks: arrowheads; on the 89 also the home/end marks and the page-scroll chevrons.
        private func over(_ cg: CGContext) {
            let u = k("UP"), l = k("LEFT"), r = k("RIGHT")
            let cx = u.cx, cy = u.cy, hh = u.h / 2
            let tri = pal != nil ? legendColor(u) : t.ink
            func triangle(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat, _ s: CGFloat = 7) {
                let p = PathBuilder()
                p.moveTo(x + dx * s, y + dy * s)
                p.lineTo(x - dx * s * 0.6 - dy * s, y - dy * s * 0.6 + dx * s)
                p.lineTo(x - dx * s * 0.6 + dy * s, y - dy * s * 0.6 - dx * s)
                p.close()
                // Paint.Style.FILL_AND_STROKE, 2 wide, round joins
                cg.saveGState()
                cg.addPath(p.cg)
                cg.setFillColor(Graphics.color(tri))
                cg.setStrokeColor(Graphics.color(tri))
                cg.setLineWidth(2)
                cg.setLineJoin(.round)
                cg.drawPath(using: .fillStroke)
                cg.restoreGState()
            }
            triangle(cx, cy - hh + 20, 0, -1)
            triangle(cx, cy + hh - 20, 0, 1)
            triangle(l.cx - 12, l.cy, -1, 0)
            triangle(r.cx + 12, r.cy, 1, 0)
            if base.ti84 { return }
            func line(_ color: ARGB, _ p: PathBuilder) {
                cg.saveGState()
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                strokeShape(cg, p.cg, 2.2, color)
                cg.restoreGState()
            }
            let ends: [(CGFloat, CGFloat)] = [(cy - hh + 46, -1), (cy + hh - 46, 1)]
            for (y, dy) in ends {
                let p = PathBuilder()
                p.moveTo(cx - 8, y + dy * 7)
                p.lineTo(cx + 8, y + dy * 7)
                p.moveTo(cx, y - dy * 7)
                p.lineTo(cx, y + dy * 3)
                p.moveTo(cx - 5, y - dy)
                p.lineTo(cx, y + dy * 4)
                p.lineTo(cx + 5, y - dy)
                line(t.green, p)
            }
            let chevrons: [(CGFloat, CGFloat)] = [(cy - 36, -1), (cy + 36, 1)]
            for (y, dy) in chevrons {
                for i in 0..<3 {
                    let yi = y + dy * 5 * CGFloat(i)
                    let p = PathBuilder()
                    p.moveTo(cx - 9, yi + dy * 3)
                    p.lineTo(cx, yi + dy * 7)
                    p.lineTo(cx + 9, yi + dy * 3)
                    line(t.blue, p)
                }
            }
        }

        /// Contrast bracket beside − and + (TI-89 layout).
        private func decor(_ cg: CGContext) {
            cg.saveGState()
            cg.translateBy(x: decorDx, y: 0)
            let col = t.green
            let bracket = PathBuilder()
            bracket.moveTo(608, 718)
            bracket.lineTo(617, 718)
            bracket.quadTo(622, 718, 622, 724)
            bracket.lineTo(622, 800)
            bracket.quadTo(622, 806, 616, 806)
            bracket.lineTo(608, 806)
            cg.saveGState()
            cg.setLineCap(.round)
            strokeShape(cg, bracket.cg, 2.6, col)
            cg.restoreGState()
            let circle = CGMutablePath()
            circle.addEllipse(in: CGRect(x: 613, y: 754, width: 16, height: 16))  // centre (621, 762), radius 8
            fillShape(cg, circle, col)
            let dia = PathBuilder()
            dia.moveTo(621, 756)
            dia.lineTo(627, 762)
            dia.lineTo(621, 768)
            dia.lineTo(615, 762)
            dia.close()
            fillShape(cg, dia.cg, col)
            strokeShape(cg, dia.cg, 1.4, withAlpha(BLACK, 0.35))
            cg.restoreGState()
        }

        // ---- text ----

        /// The skin font at `size` (Paint.textSize).
        private func font(_ size: CGFloat) -> CTFont {
            if let f = fonts[size] { return f }
            let f = CTFontCreateWithFontDescriptor(descriptor, size, nil)
            fonts[size] = f
            return f
        }

        /// One line of text in `font`; `kern`: extra space after each glyph (Paint.letterSpacing times the size);
        /// `stroke` > 0: drawn as an outline that many percent of the size wide (Paint.Style.STROKE).
        static func makeLine(_ s: String, _ font: CTFont, kern: CGFloat = 0, color: ARGB = 0xFF00_0000, stroke: CGFloat = 0) -> CTLine {
            func attr(_ name: CFString) -> NSAttributedString.Key { NSAttributedString.Key(name as String) }
            var attrs: [NSAttributedString.Key: Any] = [
                attr(kCTFontAttributeName): font, attr(kCTForegroundColorAttributeName): Graphics.color(color),
            ]
            if kern != 0 { attrs[attr(kCTKernAttributeName)] = kern }
            if stroke != 0 {
                attrs[attr(kCTStrokeWidthAttributeName)] = stroke
                attrs[attr(kCTStrokeColorAttributeName)] = Graphics.color(color)
            }
            return CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs) as CFAttributedString)
        }

        /// Paint.getTextBounds: the inked box in whole units (rounded out), y down, from x = 0 on the baseline.
        static func inkBounds(_ line: CTLine) -> CGRect {
            let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            if b.isNull { return .zero }
            let left = b.minX.rounded(.down), top = (-b.maxY).rounded(.down)
            let right = b.maxX.rounded(.up), bottom = (-b.minY).rounded(.up)
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }

        /// Paint.measureText: the line's advance width.
        static func advance(_ line: CTLine) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }

        private func textLine(_ s: String, _ size: CGFloat, kern: CGFloat = 0, color: ARGB = 0xFF00_0000, stroke: CGFloat = 0) -> CTLine {
            Drawer.makeLine(s, font(size), kern: kern, color: color, stroke: stroke)
        }

        /// Canvas.drawText: `line` from x on the baseline y, upright in the y-down user space.
        private func drawLine(_ cg: CGContext, _ line: CTLine, _ x: CGFloat, _ y: CGFloat) {
            cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            cg.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, cg)
        }

        /// canvas.skew(0, skew) about (px, py).
        private func shear(_ cg: CGContext, _ px: CGFloat, _ py: CGFloat, _ skew: CGFloat) {
            cg.translateBy(x: px, y: py)
            cg.concatenate(CGAffineTransform(a: 1, b: skew, c: 0, d: 1, tx: 0, ty: 0))
            cg.translateBy(x: -px, y: -py)
        }

        private func inFk(_ k: Key) -> Bool { fk.contains(where: { $0.name == k.name }) }

        private func legendColor(_ k: Key) -> ARGB {
            guard let p = pal else { return defaultLegendColor(k) }
            if p.finish == .neon { return outlineOf(p, k) }
            if p.finish == .outline {
                if k.kind == "2nd" || k.kind == "diamond" || k.kind == "alpha" { return roleColor(p, k) }
                if k.name == "APPS" || (k.name == "MATRIX" && k.legend[0] == "APPS") { return p.apps }
                return p.text
            }
            let f = fillOf(k)
            if contrast(p.text, f) >= 4.5 { return p.text }
            // the most legible palette colour (the first of equals, as Kotlin's maxBy)
            var best = p.all[0]
            for col in p.all.dropFirst() where contrast(col, f) > contrast(best, f) { best = col }
            return best
        }

        private func defaultLegendColor(_ k: Key) -> ARGB {
            if k.name == "APPS" || (k.name == "MATRIX" && k.legend[0] == "APPS") { return t.purple }
            if k.kind == "white" { return t.onLight }
            if k.kind == "2nd" || k.kind == "diamond" || k.kind == "alpha" { return t.onLight }
            return t.onDark
        }

        private func primarySize(_ k: Key, _ p: String) -> CGFloat {
            if p == "←" { return sizes.digit * 1.3 }  // Noto's arrow is small next to the digits
            if p == "↑" || p == "(−)" { return sizes.key }  // ↑ must clear the shift ring; (−) reads too big at digit size
            if !p.unicodeScalars.contains(where: { isLetter($0) }) { return sizes.digit }
            if inFk(k) { return sizes.fkey }
            return sizes.key
        }

        /// Inked bounds of `s` at `size`, from x = 0 on the baseline (y down).
        private func inkBox(_ s: String, _ size: CGFloat) -> CGRect {
            let b = Drawer.inkBounds(textLine(s, 1000))
            let f = size / 1000
            return CGRect(x: b.minX * f, y: b.minY * f, width: b.width * f, height: b.height * f)
        }

        private func labelWidth(_ s: String, _ fs: CGFloat) -> CGFloat {
            Drawer.advance(textLine(s, fs, kern: 0.2))
        }

        /// Runs of a label: (text, colour, superscript). ⁻¹ and ˣ are set as raised small text.
        private func runs(_ s: String, _ color: ARGB) -> [Run] {
            var out: [Run] = []
            let u = Array(s.unicodeScalars)
            var i = 0
            var buf = ""
            while i < u.count {
                var sup: String?
                if u[i] == "⁻" && i + 1 < u.count && u[i + 1] == "¹" {
                    sup = "−1"
                } else if u[i] == "ˣ" {
                    sup = "x"
                }
                if let sup = sup {
                    if !buf.isEmpty {
                        out.append(Run(buf, color, false))
                        buf = ""
                    }
                    out.append(Run(sup, color, true))
                    i += sup == "x" ? 1 : 2
                } else {
                    buf.unicodeScalars.append(u[i])
                    i += 1
                }
            }
            if !buf.isEmpty { out.append(Run(buf, color, false)) }
            return out
        }

        private func legend(_ cg: CGContext, _ k: Key) {
            let prim = k.legend[0], b = k.legend[1], g = k.legend[2], a = k.legend[3]
            let tilt = abs(k.ang) > 1
            let rad = k.ang * .pi / 180
            let ca = cos(rad)
            let sa = sin(rad)
            let skew = tan(rad)

            if let prim = prim, !prim.isEmpty {
                let size = primarySize(k, prim)
                let ink = inkBox(prim, size)
                let tx = k.cx + k.lx - (ink.minX + ink.maxX) / 2
                let by = k.cy + k.ly - (ink.minY + ink.maxY) / 2
                cg.saveGState()
                if tilt { shear(cg, k.cx, k.cy, skew) }
                cg.setTextDrawingMode(.fill)
                if threeD {  // engraved: a light edge just below the glyphs
                    drawLine(cg, textLine(prim, size, color: withAlpha(WHITE, 0.30)), tx, by + 1)
                }
                drawLine(cg, textLine(prim, size, color: legendColor(k)), tx, by)
                cg.restoreGState()
            }

            // label row above the key: laid out in the key's frame, each label's centre rotated with
            // the key and the label sheared about it so it runs parallel to the key's top edge
            let x0 = k.cx - k.w / 2, x1 = k.cx + k.w / 2
            let fs = sizes.label
            let isF = inFk(k)
            var ly = CGFloat.infinity
            if isF {
                for f in fk { ly = min(ly, f.cy - f.h / 2 - 7 - 5) }
            } else {
                let lift: CGFloat = (k.name == "ON" || k.name == "ENTER") ? 0 : t.labelLift
                ly = k.cy - k.h / 2 - lift - 5
            }
            let inset: CGFloat = 8, gap: CGFloat = 7
            let rowY = ly
            func tw(_ s: String) -> CGFloat { labelWidth(s, fs) }
            func spread(_ wl: CGFloat, _ wr: CGFloat) -> CGFloat { min(inset, (k.w - wl - wr - gap) / 2) }
            func txt(_ x: CGFloat, _ anchor: String, _ parts: [Run], _ plain: String) {
                let wd = tw(plain)
                var left = x
                if anchor == "e" { left = x - wd } else if anchor == "m" { left = x - wd / 2 }
                let u = left + wd / 2 - k.cx, v = rowY - k.cy
                let px = k.cx + u * ca - v * sa, py = k.cy + u * sa + v * ca
                drawRuns(cg, parts, px, py, fs, (tilt && !isF) ? skew : 0)
            }
            if isF {
                var parts: [Run] = []
                if let b = b {
                    parts += runs(b, t.blue)
                    parts.append(Run(" ", t.blue, false))
                }
                parts += runs(g ?? "", t.green)
                txt(k.cx, "m", parts, (b.map { "\($0) " } ?? "") + (g ?? ""))
            } else if let a = a {
                let ps = [b, g].compactMap { $0 }
                let leftText = ps.joined(separator: "  ")
                let ins = ps.isEmpty ? inset : spread(tw(leftText), tw(a))
                txt(x1 - ins, "e", runs(a, t.alpha), a)
                if !ps.isEmpty {
                    var parts: [Run] = []
                    for (i, s) in ps.enumerated() {
                        if i > 0 { parts.append(Run("  ", t.blue, false)) }
                        parts += runs(s, s == b ? t.blue : t.green)
                    }
                    txt(x0 + ins, "s", parts, leftText)
                }
            } else if let b = b, let g = g {
                let ins = spread(tw(b), tw(g))
                txt(x0 + ins, "s", runs(b, t.blue), b)
                txt(x1 - ins, "e", runs(g, t.green), g)
            } else if let s = b ?? g {
                txt(k.cx, "m", runs(s, b != nil ? t.blue : t.green), s)
            }
        }

        /// Draws label runs centred on (px, py), sheared by `skew` about that point; halo first if the theme has one.
        private func drawRuns(_ cg: CGContext, _ parts: [Run], _ px: CGFloat, _ py: CGFloat, _ fs: CGFloat, _ skew: CGFloat) {
            func sizeOf(_ p: Run) -> CGFloat { p.sup ? fs * 0.72 : fs }
            func widthOf(_ p: Run) -> CGFloat { labelWidth(p.text, sizeOf(p)) }
            var total: CGFloat = 0
            for p in parts { total += widthOf(p) }
            cg.saveGState()
            if skew != 0 { shear(cg, px, py, skew) }
            let passes: [Bool] = t.halo != nil ? [true, false] : [false]
            for halo in passes {
                var x = px - total / 2
                for p in parts {
                    let size = sizeOf(p)
                    let w = widthOf(p)
                    let y = p.sup ? py - 0.38 * fs : py
                    if halo, let haloColor = t.halo {
                        // Paint.Style.STROKE, haloW wide with round joins (Core Text sets the stroke from the
                        // attributes; the context gets the same, whichever it uses)
                        let color = withAlpha(haloColor, t.haloOp)
                        cg.setTextDrawingMode(.stroke)
                        cg.setLineWidth(t.haloW)
                        cg.setLineJoin(.round)
                        cg.setStrokeColor(Graphics.color(color))
                        drawLine(cg, textLine(p.text, size, kern: 0.2, color: color, stroke: t.haloW / size * 100), x, y)
                    } else {
                        cg.setTextDrawingMode(.fill)
                        drawLine(cg, textLine(p.text, size, kern: 0.2, color: p.color), x, y)
                    }
                    x += w
                }
            }
            cg.restoreGState()
        }

        // ---- touch mask ----

        /// Key code per design unit: each key's shape plus OVERHANG; 255 = no key. The cursor bar is UP / DOWN.
        /// Nil when there is no memory for it.
        func mask(_ w: Int, _ h: Int) -> [UInt8]? {
            guard let cg = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            cg.setFillColor(gray: 1, alpha: 1)  // NO_KEY everywhere
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            cg.translateBy(x: 0, y: CGFloat(h))
            cg.scaleBy(x: 1, y: -1)
            cg.setShouldAntialias(false)
            cg.setAllowsAntialiasing(false)
            cg.setMiterLimit(4)
            cg.setLineWidth(2 * OVERHANG)
            // first every key grown by OVERHANG (fill and stroke), then the exact shapes over them
            for grow in [true, false] {
                for k in keys {
                    rotated(cg, k) {
                        let path = kpath(k)
                        func paint(_ code: Int) {
                            // a grey that lands on byte `code` whether Core Graphics rounds or truncates
                            let v = (CGFloat(code) + 0.25) / 255
                            cg.setFillColor(gray: v, alpha: 1)
                            cg.setStrokeColor(gray: v, alpha: 1)
                            cg.addPath(path)
                            cg.drawPath(using: grow ? .fillStroke : .fill)
                        }
                        if k.codeDown >= 0 {
                            // the cursor bar: upper half UP, lower half DOWN, split on a whole cell row as Skia
                            // rounds an aliased clip (so the clip edge is never blended; the bar is not tilted)
                            let split = (k.cy + 0.5).rounded(.down)
                            cg.saveGState()
                            cg.clip(to: CGRect(x: -1e4, y: -1e4, width: 2e4, height: split + 1e4))
                            paint(k.code)
                            cg.restoreGState()
                            cg.saveGState()
                            cg.clip(to: CGRect(x: -1e4, y: split, width: 2e4, height: 1e4 - split))
                            paint(k.codeDown)
                            cg.restoreGState()
                        } else {
                            paint(k.code)
                        }
                    }
                }
            }
            guard let data = cg.data else { return nil }
            let bytes = data.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = cg.bytesPerRow
            var out = [UInt8](repeating: NO_KEY, count: w * h)
            for y in 0..<h {
                for x in 0..<w { out[y * w + x] = bytes[y * bytesPerRow + x] }
            }
            return out
        }
    }
}

// ---- shared constants and colour helpers ----

private let H: CGFloat = 1014
private let OVERHANG: CGFloat = 10  // touch area around each key, design units
private let NO_KEY: UInt8 = 255
private let BLACK: ARGB = 0xFF00_0000
private let WHITE: ARGB = 0xFFFF_FFFF

/// Color.parseColor for "#rrggbb".
private func c(_ hex: String) -> ARGB {
    0xFF00_0000 | (ARGB(hex.dropFirst(), radix: 16) ?? 0)
}

/// Colour `a` moved a fraction `t` towards `b` (opaque; channels truncated like Kotlin's toInt()).
private func mix(_ a: ARGB, _ b: ARGB, _ t: Float) -> ARGB {
    func ch(_ shift: ARGB) -> ARGB {
        let x = Float(a >> shift & 0xFF)
        let y = Float(b >> shift & 0xFF)
        return ARGB(Int(x + (y - x) * t)) << shift
    }
    return 0xFF00_0000 | ch(16) | ch(8) | ch(0)
}

private func luminance(_ color: ARGB) -> Double {
    func ch(_ v: ARGB) -> Double {
        let x = Double(v) / 255.0
        return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * ch(color >> 16 & 0xFF) + 0.7152 * ch(color >> 8 & 0xFF) + 0.0722 * ch(color & 0xFF)
}

private func contrast(_ a: ARGB, _ b: ARGB) -> Double {
    let la = luminance(a)
    let lb = luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// `color` with its alpha set to `a` (0...1, truncated like Kotlin's toInt()).
private func withAlpha(_ color: ARGB, _ a: Float) -> ARGB {
    let alpha = ARGB(min(max(Int(a * 255), 0), 255))
    return (alpha << 24) | (color & 0x00FF_FFFF)
}

private func hyp(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    (x * x + y * y).squareRoot()
}

/// Kotlin's Char.isLetter: the Unicode letter categories.
private func isLetter(_ s: Unicode.Scalar) -> Bool {
    switch s.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
    default: return false
    }
}
