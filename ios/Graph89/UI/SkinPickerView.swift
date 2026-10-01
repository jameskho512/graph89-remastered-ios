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

import SwiftUI
import UIKit

// Sizes of the two strips, in points.
private let lcdItemWidth: CGFloat = 76
private let lcdSpacing: CGFloat = 8
private let skinCardWidth: CGFloat = 124
private let skinCardHeight: CGFloat = 170
private let skinSpacing: CGFloat = 12

/// How long an item stays in the centre before it counts as settled, in nanoseconds (iOS 17 does not tell when a
/// scroll ends).
private let settleDelay: UInt64 = 350_000_000

/// Skin and LCD picker: a strip of LCD schemes at the top (Custom at the far left), a large preview of the
/// calculator in the middle and a strip of skins at the bottom. Both strips snap with the choice in the centre and
/// apply it once it settles. With the link on, a skin brings its LCD scheme and an LCD scheme brings its skin. The
/// OLED skin has a contrast slider.
struct SkinPickerView: View {
    @Bindable var model: AppModel

    /// The skin being looked at.
    @State private var viewed: SkinType
    /// The items in the centre of the two strips; they change while the strips scroll.
    @State private var skinCentre: SkinType?
    @State private var lcdCentre: LcdTheme?
    /// The items last settled in the centre. The strips act only on a change: the items the picker opened on are not
    /// a choice, and acting on them would re-link (and overwrite) the saved LCD just by opening the picker.
    @State private var settledSkin: SkinType
    @State private var settledLcd: LcdTheme
    /// Follows the slider while it moves.
    @State private var contrast: Int
    @State private var editingCustom = false
    @State private var thumbs: [SkinType: CGImage] = [:]

    init(model: AppModel) {
        self.model = model
        let c = model.config
        _viewed = State(initialValue: c.skin)
        _skinCentre = State(initialValue: c.skin)
        _lcdCentre = State(initialValue: c.lcdTheme)
        _settledSkin = State(initialValue: c.skin)
        _settledLcd = State(initialValue: c.lcdTheme)
        _contrast = State(initialValue: c.oledContrast)
    }

    private var config: EmulatorConfig { model.config }

    /// The display as the calculator last showed it, when it is of this calculator.
    private var screen: LcdSnapshot? {
        guard let s = model.session.lastScreen, s.width == model.activeModel.lcdWidth else { return nil }
        return s
    }

    var body: some View {
        let calc = model.activeModel
        let snapshot = screen
        VStack(spacing: 0) {
            // ---- LCD schemes
            LcdStrip(centre: $lcdCentre, settled: settledLcd, config: config, screen: snapshot) { editingCustom = true }
                .frame(height: 88)
                .padding(.top, 8)

            // ---- link toggle, and the Custom editor when Custom is chosen
            linkRow
                .frame(height: 44)
                .padding(.horizontal, 16)

            // ---- preview
            CalculatorPreview(
                calc: calc, type: viewed, config: config, contrast: contrast,
                screen: snapshot?.height == calc.lcdHeight ? snapshot : nil,
                viewSize: model.emulatorViewSize
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            // ---- status (OLED contrast or the skin's name) and the 3D switch, right above the skins
            statusRow
                .frame(height: 56)
                .padding(.horizontal, 16)

            // ---- skins
            SkinStrip(centre: $skinCentre, settled: settledSkin, inUse: config.skin, thumbs: thumbs)
                .frame(height: skinCardHeight)
                .padding(.bottom, 16)
        }
        .navigationTitle("Skin and LCD")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ThumbKey(model: calc, threeD: config.skin3d, contrast: config.oledContrast)) {
            await drawThumbs()
        }
        .task(id: skinCentre) {
            try? await Task.sleep(nanoseconds: settleDelay)
            if Task.isCancelled { return }
            if let t = skinCentre { skinSettled(t) }
        }
        .task(id: lcdCentre) {
            try? await Task.sleep(nanoseconds: settleDelay)
            if Task.isCancelled { return }
            if let lcd = lcdCentre { lcdSettled(lcd) }
        }
        .sheet(isPresented: $editingCustom) {
            CustomLcdEditor(background: model.config.customLcdBackground, text: model.config.customLcdText) { bg, fg in
                var c = model.config
                c.lcdTheme = .CUSTOM
                c.customLcdBackground = bg
                c.customLcdText = fg
                model.updateConfig(c)
            }
        }
    }

    private var linkRow: some View {
        let linked = config.linkLcdToSkin
        return HStack(spacing: 12) {
            Button {
                var c = model.config
                c.linkLcdToSkin.toggle()
                model.updateConfig(c)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: linked ? "link" : "link.badge.plus")
                        .foregroundStyle(linked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 28)
                    Text("Match LCD and Keypad Skins")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(linked ? Text("On") : Text("Off"))
            Spacer(minLength: 0)
            if config.lcdTheme == .CUSTOM {
                Button("Edit custom") { editingCustom = true }
            }
        }
        .font(.subheadline)
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            Group {
                if viewed == .OLED {
                    HStack(spacing: 12) {
                        Text("Contrast")
                        Slider(
                            value: Binding(get: { Double(contrast) }, set: { contrast = Int($0.rounded()) }),
                            in: 20...100,
                            step: 1,
                            onEditingChanged: { editing in
                                if !editing {
                                    var c = model.config
                                    c.oledContrast = contrast
                                    model.updateConfig(c)
                                }
                            }
                        )
                        Text("\(contrast)%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.subheadline)
                } else {
                    Text(viewed.label).font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 3D finish for any skin (keys only)
            Text("3D").font(.subheadline.weight(.semibold))
            Toggle("3D", isOn: Binding(
                get: { model.config.skin3d },
                set: { on in
                    var c = model.config
                    c.skin3d = on
                    model.updateConfig(c)
                }
            ))
            .labelsHidden()
        }
    }

    /// Thumbnails are cached, so only changed ones are drawn.
    private func drawThumbs() async {
        let calc = model.activeModel
        let threeD = config.skin3d
        let oled = config.oledContrast
        for t in SkinType.allCases {
            let image = await Task.detached(priority: .userInitiated) {
                SkinPreview.keypad(model: calc, type: t, width: 360, height: 460, oledContrast: oled, threeD: threeD)
            }.value
            if Task.isCancelled { return }
            thumbs[t] = image
        }
    }

    /// A skin settled in the centre: apply it; with the link on, its LCD scheme too.
    private func skinSettled(_ t: SkinType) {
        guard t != settledSkin else { return }
        settledSkin = t
        viewed = t
        var c = model.config
        c.skin = t
        if c.linkLcdToSkin, let match = LcdTheme(rawValue: t.rawValue) {
            c.lcdTheme = match
            if lcdCentre != match { withAnimation { lcdCentre = match } }
        }
        if c != model.config { model.updateConfig(c) }
    }

    /// An LCD scheme settled in the centre: apply it; with the link on, bring its skin to the centre too.
    private func lcdSettled(_ lcd: LcdTheme) {
        guard lcd != settledLcd else { return }
        settledLcd = lcd
        if model.config.lcdTheme != lcd {
            var c = model.config
            c.lcdTheme = lcd
            model.updateConfig(c)
        }
        if model.config.linkLcdToSkin, let match = SkinType(rawValue: lcd.rawValue), skinCentre != match {
            withAnimation { skinCentre = match }
        }
    }
}

/// What the skin thumbnails are drawn for.
private struct ThumbKey: Equatable {
    let model: CalcModel
    let threeD: Bool
    let contrast: Int
}

// MARK: - LCD schemes

/// The LCD schemes, Custom at the far left: the one in the centre is the choice. Tapping another one brings it to
/// the centre; tapping Custom in the centre edits it.
private struct LcdStrip: View {
    @Binding var centre: LcdTheme?
    /// Where the strip opens.
    let settled: LcdTheme
    let config: EmulatorConfig
    let screen: LcdSnapshot?
    let onEditCustom: () -> Void

    var body: some View {
        GeometryReader { geo in
            let centreX = geo.frame(in: .global).midX
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: lcdSpacing) {
                        ForEach(LcdTheme.allCases, id: \.self) { lcd in
                            Button { tapped(lcd) } label: {
                                LcdSwatch(
                                    label: lcd.label,
                                    lcd: colors(lcd),
                                    screen: screen,
                                    custom: lcd == .CUSTOM,
                                    selected: lcd == centre
                                )
                                .frame(width: lcdItemWidth)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(lcd.label) LCD")
                            .carousel(centreX: centreX, step: lcdItemWidth + lcdSpacing)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, max((geo.size.width - lcdItemWidth) / 2, 0), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centre, anchor: .center)
            }
        }
    }

    private func colors(_ lcd: LcdTheme) -> LcdColors {
        lcd == .CUSTOM ? customLcd(background: config.customLcdBackground, text: config.customLcdText) : lcd.colors
    }

    private func tapped(_ lcd: LcdTheme) {
        if lcd == centre {
            if lcd == .CUSTOM { onEditCustom() }
        } else {
            withAnimation { centre = lcd }
        }
    }
}

/// An LCD colour scheme: the calculator's display in its colours (when there is one), and its name.
private struct LcdSwatch: View {
    let label: String
    let lcd: LcdColors
    let screen: LcdSnapshot?
    let custom: Bool
    let selected: Bool

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let colors = lcd
        let snapshot = screen
        let scale = displayScale
        let height: CGFloat = snapshot.map { 38 * CGFloat($0.height) / CGFloat(max($0.width, 1)) } ?? 24
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(swiftColor(colors.background))
                Canvas { ctx, size in
                    drawLcd(&ctx, snapshot, colors, in: CGRect(origin: .zero, size: size), displayScale: scale)
                }
                .frame(width: 38, height: height)
                if custom {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(swiftColor(colors.pixelOn))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 4)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(selected ? Color.accentColor : Color.gray, lineWidth: selected ? 3 : 1)
            }
            Text(label)
                .font(.caption2)
                .lineLimit(1)
        }
    }
}

// MARK: - preview

/// What a calculator preview is drawn for; its sizes are pixels.
private struct PreviewKey: Equatable {
    let model: CalcModel
    let type: SkinType
    let width: Int
    let height: Int
    let viewWidth: Int
    let viewHeight: Int
    let screenScale: Int
    let contrast: Int
    let threeD: Bool
}

/// The calculator as it will look on this phone, in the shape of the real emulator view: the keypad is drawn off
/// the main thread at the preview's pixel size, the LCD band and the LCD live on top.
private struct CalculatorPreview: View {
    let calc: CalcModel
    let type: SkinType
    let config: EmulatorConfig
    /// The OLED contrast, live while the slider moves.
    let contrast: Int
    let screen: LcdSnapshot?
    /// Pixels of the real emulator view: it sets the preview's shape and the LCD's share.
    let viewSize: CGSize

    @Environment(\.displayScale) private var displayScale
    @State private var shown: Shown?

    private struct Shown {
        let key: PreviewKey
        let image: CGImage
    }

    var body: some View {
        GeometryReader { geo in
            let scale = max(displayScale, 1)
            let key = previewKey(geo.size, scale: scale)
            box(key, scale: scale)
                .frame(width: CGFloat(key.width) / scale, height: CGFloat(key.height) / scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: key) { await draw(key) }
        }
    }

    /// The largest box of the emulator view's shape that fits `size` (points), in pixels.
    private func previewKey(_ size: CGSize, scale: CGFloat) -> PreviewKey {
        let vw = max(Int(viewSize.width), 1)
        let vh = max(Int(viewSize.height), 1)
        let aspect = CGFloat(vw) / CGFloat(vh)
        let w = max(Int(min(size.width, size.height * aspect) * scale), 1)
        let h = max(Int(CGFloat(w) / aspect), 1)
        return PreviewKey(
            model: calc, type: type, width: w, height: h, viewWidth: vw, viewHeight: vh,
            screenScale: config.screenScale, contrast: contrast, threeD: config.skin3d
        )
    }

    private func box(_ key: PreviewKey, scale: CGFloat) -> some View {
        var live = config
        live.oledContrast = contrast  // live while the contrast slider moves
        let lcd = live.lcd()
        let snapshot = screen
        let area = SkinPreview.lcdArea(
            model: calc, width: key.width, viewWidth: key.viewWidth, viewHeight: key.viewHeight, screenScale: key.screenScale
        )
        let pixelWidth = CGFloat(key.width)
        return ZStack {
            Color.black
            if let shown {
                Image(shown.image, scale: scale, label: Text("Preview of \(type.label)"))
                    .resizable()
            }
            // the LCD on top, drawn live: sharp at any size, and new colours are only a redraw
            Canvas { ctx, size in
                let k = size.width / pixelWidth  // preview pixels to points
                let band = CGRect(x: 0, y: 0, width: size.width, height: CGFloat(area.bandHeight) * k)
                ctx.fill(Path(band), with: .color(swiftColor(lcd.background)))
                let s = area.screen
                let rect = CGRect(x: s.minX * k, y: s.minY * k, width: s.width * k, height: s.height * k)
                drawLcd(&ctx, snapshot, lcd, in: rect, displayScale: scale)
            }
            if shown?.key != key {
                ProgressView()
                    .controlSize(.large)
                    .environment(\.colorScheme, .dark)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func draw(_ key: PreviewKey) async {
        guard key.width >= 16, key.height >= 16 else { return }  // not laid out yet
        if let s = shown, s.key.contrast != key.contrast {
            // the contrast slider is moving: draw when it pauses, not at every step
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled { return }
        }
        let image = await Task.detached(priority: .userInitiated) {
            SkinPreview.calculator(
                model: key.model, type: key.type, width: key.width, height: key.height,
                viewWidth: key.viewWidth, viewHeight: key.viewHeight, screenScale: key.screenScale,
                oledContrast: key.contrast, threeD: key.threeD
            )
        }.value
        if Task.isCancelled { return }
        shown = Shown(key: key, image: image)
    }
}

// MARK: - skins

/// The skins: the one in the centre is the choice. Tapping another one brings it to the centre.
private struct SkinStrip: View {
    @Binding var centre: SkinType?
    /// Where the strip opens.
    let settled: SkinType
    let inUse: SkinType
    let thumbs: [SkinType: CGImage]

    var body: some View {
        GeometryReader { geo in
            let centreX = geo.frame(in: .global).midX
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: skinSpacing) {
                        ForEach(SkinType.allCases, id: \.self) { t in
                            Button { withAnimation { centre = t } } label: {
                                SkinCard(type: t, image: thumbs[t], inUse: t == inUse, centred: t == centre)
                            }
                            .buttonStyle(.plain)
                            .carousel(centreX: centreX, step: skinCardWidth + skinSpacing)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, max((geo.size.width - skinCardWidth) / 2, 0), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centre, anchor: .center)
            }
        }
    }
}

/// A skin's keypad, cropped to the card, with its name (and a check when it is in use).
private struct SkinCard: View {
    let type: SkinType
    let image: CGImage?
    let inUse: Bool
    let centred: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(white: 0.27)
            if let image {
                Image(image, scale: 1, label: Text(type.label))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: skinCardWidth, height: skinCardHeight)
                    .clipped()
            }
            HStack(spacing: 4) {
                if inUse {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityLabel("In use")
                }
                Text(type.label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.67))
        }
        .frame(width: skinCardWidth, height: skinCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if centred {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Custom LCD

/// Custom LCD: start from any preset, then change the background or text colour with the colour picker. A preview
/// shows the result, including the unlit pixels derived from the two colours.
private struct CustomLcdEditor: View {
    let onDone: (ARGB, ARGB) -> Void

    @State private var bg: ARGB
    @State private var fg: ARGB
    @Environment(\.dismiss) private var dismiss

    init(background: ARGB, text: ARGB, onDone: @escaping (ARGB, ARGB) -> Void) {
        self.onDone = onDone
        _bg = State(initialValue: background)
        _fg = State(initialValue: text)
    }

    var body: some View {
        let lcd = customLcd(background: bg, text: fg)
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: "2+3·4          14")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(swiftColor(lcd.pixelOn))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(swiftColor(lcd.pixelOff))
                        .padding(8)
                        .frame(height: 64)
                        .background(swiftColor(lcd.background))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Preview")
                    Menu {
                        ForEach(LcdTheme.allCases.filter { $0 != .CUSTOM }, id: \.self) { p in
                            Button {
                                bg = p.background
                                fg = p.pixelOn
                            } label: {
                                Label {
                                    Text(p.label)
                                } icon: {
                                    Image(uiImage: presetSwatch(p))
                                }
                            }
                        }
                    } label: {
                        Label("Start from a preset", systemImage: "paintpalette")
                    }
                }
                Section {
                    ColorPicker(selection: colorBinding($bg), supportsOpacity: false) {
                        LabeledRow(title: "Background", detail: hexString(bg))
                    }
                    ColorPicker(selection: colorBinding($fg), supportsOpacity: false) {
                        LabeledRow(title: "Text", detail: hexString(fg))
                    }
                }
            }
            .navigationTitle("Custom LCD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(bg, fg)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// A preset for the menu: its background with a dot of its text colour.
    private func presetSwatch(_ p: LcdTheme) -> UIImage {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { ctx in
            let cg = ctx.cgContext
            let circle = CGRect(x: 0.5, y: 0.5, width: 23, height: 23)
            cg.setFillColor(Graphics.color(p.background))
            cg.fillEllipse(in: circle)
            cg.setStrokeColor(Graphics.color(0xFF9E_9E9E))
            cg.setLineWidth(1)
            cg.strokeEllipse(in: circle)
            cg.setFillColor(Graphics.color(p.pixelOn))
            cg.fillEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8))
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

// MARK: - drawing and colours

/// Neighbours of the centred item shrink and fade.
private extension View {
    func carousel(centreX: CGFloat, step: CGFloat) -> some View {
        visualEffect { content, proxy in
            content
                .scaleEffect(1 - 0.18 * carouselDistance(proxy.frame(in: .global), centreX: centreX, step: step))
                .opacity(Double(1 - 0.45 * carouselDistance(proxy.frame(in: .global), centreX: centreX, step: step)))
        }
    }
}

/// How far an item is from the centre of its strip, in items (0 in the centre, at most 1).
private func carouselDistance(_ frame: CGRect, centreX: CGFloat, step: CGFloat) -> CGFloat {
    min(abs(frame.midX - centreX) / max(step, 1), 1)
}

/// The calculator's display `snapshot` in `lcd`'s colours, as one rectangle per run of equal pixels (one path per
/// shade): drawn at the screen's own resolution, so it is sharp at any size. When an LCD pixel covers at least one
/// screen pixel the edges snap to whole screen pixels (no seams, no blur); smaller, the pixels blend by coverage like
/// a real miniature.
private func drawLcd(_ ctx: inout GraphicsContext, _ snapshot: LcdSnapshot?, _ lcd: LcdColors, in rect: CGRect, displayScale: CGFloat) {
    ctx.fill(Path(rect), with: .color(swiftColor(lcd.pixelOff)))
    guard let frame = snapshot, frame.width > 0, frame.height > 0 else { return }
    let scale = max(displayScale, 1)
    let snap = rect.width / CGFloat(frame.width) * scale >= 1
    func edge(_ v: CGFloat) -> CGFloat { snap ? (v * scale).rounded(.down) / scale : v }
    let xs: [CGFloat] = (0...frame.width).map { edge(rect.minX + CGFloat($0) * rect.width / CGFloat(frame.width)) }
    let ys: [CGFloat] = (0...frame.height).map { edge(rect.minY + CGFloat($0) * rect.height / CGFloat(frame.height)) }
    var shades: [Int: Path] = [:]
    for y in 0..<frame.height {
        var x = 0
        while x < frame.width {
            let level = frame.level(x, y)
            var end = x + 1
            while end < frame.width && frame.level(end, y) == level { end += 1 }
            if level > 0 {
                shades[level, default: Path()].addRect(CGRect(x: xs[x], y: ys[y], width: xs[end] - xs[x], height: ys[y + 1] - ys[y]))
            }
            x = end
        }
    }
    for (level, path) in shades {
        ctx.fill(path, with: .color(swiftColor(LcdSnapshot.color(level, lcd))))
    }
}

/// An ARGB colour as a SwiftUI colour.
private func swiftColor(_ argb: ARGB) -> Color {
    Color(
        .sRGB,
        red: Double(argb >> 16 & 0xFF) / 255, green: Double(argb >> 8 & 0xFF) / 255, blue: Double(argb & 0xFF) / 255,
        opacity: Double(argb >> 24 & 0xFF) / 255
    )
}

/// A SwiftUI colour as an opaque ARGB colour (the colour picker can give colours outside sRGB: they are clamped).
private func argbColor(_ color: Color) -> ARGB {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    _ = UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    func ch(_ v: CGFloat) -> ARGB { ARGB((min(max(v, 0), 1) * 255).rounded()) }
    return 0xFF00_0000 | ch(r) << 16 | ch(g) << 8 | ch(b)
}

/// The colour picker's binding to an ARGB value.
private func colorBinding(_ value: Binding<ARGB>) -> Binding<Color> {
    Binding(get: { swiftColor(value.wrappedValue) }, set: { value.wrappedValue = argbColor($0) })
}

/// `argb` as #RRGGBB.
private func hexString(_ argb: ARGB) -> String {
    String(format: "#%06X", argb & 0xFF_FFFF)
}
