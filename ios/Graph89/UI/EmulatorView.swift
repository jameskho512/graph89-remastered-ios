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

/// The calculator on screen: the whole display, black, with the calculator inside the chosen screen margins.
struct EmulatorScreenView: UIViewRepresentable {
    let model: AppModel

    func makeUIView(context: Context) -> EmulatorHostView {
        EmulatorHostView(model: model)
    }

    func updateUIView(_ view: EmulatorHostView, context: Context) {
        view.margins = model.config.screenMargins
    }

    static func dismantleUIView(_ view: EmulatorHostView, coordinator: ()) {
        view.detach()
    }
}

/// Black host of the calculator view: places it inside the screen margins (camera housing, rounded corners, home
/// indicator) and holds the menu button.
final class EmulatorHostView: UIView {
    private let model: AppModel
    private let calculator: CalculatorView
    private let menuButton = UIButton(type: .system)

    var margins: ScreenMargins = .CAMERA {
        didSet { if margins != oldValue { setNeedsLayout() } }
    }

    init(model: AppModel) {
        self.model = model
        calculator = CalculatorView(session: model.session)
        super.init(frame: .zero)
        backgroundColor = .black
        margins = model.config.screenMargins
        addSubview(calculator)

        let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        menuButton.setImage(UIImage(systemName: "ellipsis.circle", withConfiguration: symbol), for: .normal)
        menuButton.tintColor = UIColor(white: 1, alpha: 0.55)
        menuButton.accessibilityLabel = "Menu"
        menuButton.accessibilityIdentifier = "menuButton"
        menuButton.addAction(UIAction { [weak self] _ in self?.model.openMenu() }, for: .touchUpInside)
        addSubview(menuButton)

        // a long press on the LCD opens the menu too (the Android app opens it with Back)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(lcdLongPress(_:)))
        longPress.minimumPressDuration = 0.6
        longPress.cancelsTouchesInView = false
        longPress.delegate = calculator
        calculator.addGestureRecognizer(longPress)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func lcdLongPress(_ g: UILongPressGestureRecognizer) {
        if g.state == .began { model.openMenu() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // the screen stays on while the calculator shows, as on a calculator
        UIApplication.shared.isIdleTimerDisabled = window != nil
        if window != nil { setNeedsLayout() } else { detach() }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    func detach() {
        UIApplication.shared.isIdleTimerDisabled = false
        model.session.onViewDetached()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let window else { return }
        // the panel's own pixels (nativeScale differs from scale on the mini models and with Display Zoom)
        let scale = window.screen.nativeScale
        let m = edgeMargins(window)
        // whole pixels, so the skin is drawn 1:1
        func px(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let frame = CGRect(
            x: px(m.left), y: px(m.top),
            width: px(bounds.width - m.left - m.right), height: px(bounds.height - m.top - m.bottom)
        )
        if calculator.frame != frame { calculator.frame = frame }
        calculator.layoutIfNeeded()

        let w = Int((frame.width * scale).rounded())
        let h = Int((frame.height * scale).rounded())
        if w > 0 && h > 0 {
            let size = CGSize(width: w, height: h)
            if model.emulatorViewSize != size { model.emulatorViewSize = size }
            model.session.onViewSize(width: w, height: h)
        }

        // the menu button sits in the black band above the calculator when there is one, else on the LCD's corner
        let b: CGFloat = 36
        if m.top >= 28 {
            menuButton.frame = CGRect(x: bounds.width - max(m.right, 12) - b - 8, y: (m.top - b) / 2, width: b, height: b)
        } else {
            menuButton.frame = CGRect(x: frame.maxX - b - 4, y: frame.minY + 2, width: b, height: b)
        }
    }

    /// Margins in points. A rounded corner of radius r hides nothing beyond the point (m, m) when
    /// m = r * (1 - 1 / sqrt 2): that is the margin on every side for the corner modes. Camera keeps the top below
    /// the camera housing; every mode except None keeps the home indicator's area at the bottom free.
    private func edgeMargins(_ window: UIWindow) -> UIEdgeInsets {
        let insets = window.safeAreaInsets
        switch margins {
        case .NONE:
            return .zero
        case .CAMERA:
            return UIEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0)
        case .CORNERS, .AUTO:
            let r = Self.displayCornerRadius(window.screen)
            let corner = r > 0 ? ceil(r * 0.2929) + 1 : 0
            let top = margins == .AUTO ? max(corner, insets.top) : corner
            return UIEdgeInsets(top: top, left: corner, bottom: max(corner, insets.bottom), right: corner)
        }
    }

    /// The radius of the display's rounded corners in points (0 on phones with square corners).
    private static func displayCornerRadius(_ screen: UIScreen) -> CGFloat {
        let key = ["Radius", "Corner", "display", "_"].reversed().joined()  // the screen's own (unpublished) value
        guard screen.responds(to: NSSelectorFromString(key)) else { return 0 }
        return (screen.value(forKey: key) as? CGFloat) ?? 0
    }
}

/// Draws the skin, the LCD and the pressed-key highlights, and turns touches into key presses.
final class CalculatorView: UIView, UIGestureRecognizerDelegate {
    private let session: EmulatorSession
    private let skinLayer = CALayer()
    private let lcdLayer = CALayer()
    private var overlayLayers: [CALayer] = []

    private weak var shownSkin: Skin?
    private var shownFrame = -1
    private let refreshQueued = Atomic(false)

    init(session: EmulatorSession) {
        self.session = session
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "Calculator"
        accessibilityIdentifier = "calculator"
        skinLayer.contentsGravity = .topLeft
        lcdLayer.magnificationFilter = .nearest
        layer.addSublayer(skinLayer)
        layer.addSublayer(lcdLayer)
        session.onDisplayChanged = { [weak self] in self?.displayChanged() }
        session.keypad.onChanged = { [weak self] in self?.updateOverlays() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Pixels of the skin per point: the panel's own pixels, so the skin and a whole-number LCD zoom show 1:1.
    private var scale: CGFloat { window?.screen.nativeScale ?? UIScreen.main.nativeScale }

    /// Called from any thread: draws again on the main thread (once, however many frames came meanwhile).
    func displayChanged() {
        if refreshQueued.value { return }
        refreshQueued.value = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshQueued.value = false
            self.refresh()
        }
    }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let s = session.skin
        // the keypad shows as soon as the skin is ready; the LCD and key highlights once the calculator runs
        if s !== shownSkin {
            shownSkin = s
            shownFrame = -1
            skinLayer.contents = s?.image
            skinLayer.contentsScale = scale
            skinLayer.frame = CGRect(x: 0, y: 0, width: CGFloat(s?.canvasWidth ?? 0) / scale, height: CGFloat(s?.canvasHeight ?? 0) / scale)
            updateOverlays()
        }
        guard let skin = s, session.isEmulating, let screen = skin.screen else {
            lcdLayer.isHidden = true
            return
        }
        if let current = screen.currentImage(), current.frame != shownFrame {
            shownFrame = current.frame
            lcdLayer.contents = current.image
        }
        let d = screen.destination
        lcdLayer.frame = CGRect(x: d.minX / scale, y: d.minY / scale, width: d.width / scale, height: d.height / scale)
        lcdLayer.magnificationFilter = screen.integerZoom ? .nearest : .linear
        lcdLayer.minificationFilter = .linear
        lcdLayer.isHidden = shownFrame < 0
    }

    private func updateOverlays() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        overlayLayers.forEach { $0.removeFromSuperlayer() }
        overlayLayers.removeAll()
        guard let skin = session.skin, session.isEmulating else { return }
        for key in session.keypad.pressedKeys() {
            guard let o = skin.overlay(for: key.keyCode) else { continue }
            let r = skin.overlayRect(o)
            let l = CALayer()
            l.contents = o.image
            l.frame = CGRect(x: r.minX / scale, y: r.minY / scale, width: r.width / scale, height: r.height / scale)
            l.magnificationFilter = .linear
            layer.addSublayer(l)
            overlayLayers.append(l)
        }
    }

    // MARK: - touches

    private func touchId(_ t: UITouch) -> Int { ObjectIdentifier(t).hashValue }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.isEmulating, let skin = session.skin else { return }
        for t in touches {
            let p = t.location(in: self)
            if let code = skin.keyCode(atX: Int(p.x * scale), y: Int(p.y * scale)) {
                session.keypad.press(KeyPress(keyCode: code, touchId: touchId(t)))
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { session.keypad.unpress(touchId: touchId(t)) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        session.keypad.unpressAll()
    }

    /// The menu's long press counts only on the LCD band above the keypad.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard g is UILongPressGestureRecognizer, let screen = session.skin?.screen else { return false }
        return g.location(in: self).y * scale < screen.destination.maxY + 5
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
