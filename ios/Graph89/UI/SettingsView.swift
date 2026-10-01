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

/// Settings. The calculator is stopped while it is open; closing it starts the calculator with the new values.
struct SettingsView: View {
    @Bindable var model: AppModel

    private var config: EmulatorConfig { model.config }

    /// A binding to one setting; `feedback` settings also reach the running session at once.
    private func setting<T>(_ keyPath: WritableKeyPath<EmulatorConfig, T>, feedback: Bool = false) -> Binding<T> {
        Binding(
            get: { model.config[keyPath: keyPath] },
            set: { value in
                var c = model.config
                c[keyPath: keyPath] = value
                if feedback { model.updateFeedback(c) } else { model.updateConfig(c) }
            }
        )
    }

    var body: some View {
        Form {
            Section("Appearance") {
                NavigationLink(value: SettingsRoute.skinPicker) {
                    LabeledRow(title: "Skin and LCD", detail: "\(config.skin.label) skin, \(config.lcdTheme.label) LCD")
                }
            }

            Section("Screen") {
                Picker("Screen margins", selection: setting(\.screenMargins)) {
                    ForEach(ScreenMargins.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Automatic screen size", isOn: Binding(
                    get: { config.screenScale <= 0 },
                    set: { auto in
                        var c = config
                        c.screenScale = auto ? -1 : model.maxScreenZoom
                        model.updateConfig(c)
                    }
                ))
                if config.screenScale > 0 && model.maxScreenZoom > 1 {
                    Stepper(value: Binding(
                        get: { min(max(config.screenScale, 1), model.maxScreenZoom) },
                        set: { v in
                            var c = config
                            c.screenScale = v
                            model.updateConfig(c)
                        }
                    ), in: 1...model.maxScreenZoom) {
                        LabeledContent("Screen scale", value: "\(min(max(config.screenScale, 1), model.maxScreenZoom))x")
                    }
                }
                Toggle(isOn: setting(\.grayscale)) {
                    LabeledRow(title: "Grayscale", detail: "Some games and apps use grayscale. Grayscale decreases the speed.")
                }
            }

            Section("Feedback") {
                SliderRow(
                    title: "Vibration", value: config.hapticMs, range: 0...hapticMaxMs,
                    label: { $0 == 0 ? "Off" : "\($0) ms" }
                ) { ms in
                    var c = model.config
                    c.hapticMs = ms
                    model.updateFeedback(c)
                    model.session.previewVibration(ms: ms, strength: c.hapticStrength)
                }
                SliderRow(
                    title: "Vibration strength", value: config.hapticStrength, range: 1...100,
                    label: { model.session.hasAmplitudeControl ? "\($0)%" : "This phone does not vibrate." },
                    enabled: model.session.hasAmplitudeControl && config.hapticMs > 0
                ) { strength in
                    var c = model.config
                    c.hapticStrength = strength
                    model.updateFeedback(c)
                    model.session.previewVibration(ms: c.hapticMs, strength: strength)
                }
                Toggle(isOn: setting(\.audioFeedback, feedback: true)) {
                    LabeledRow(title: "Keypress audio", detail: "The app makes a sound when you press a key.")
                }
            }

            Section("Emulation") {
                Picker("CPU speed", selection: setting(\.cpuSpeed)) {
                    ForEach(cpuSpeeds, id: \.self) { speed in
                        Text(speed == 100 ? "100% (default)" : speed == cpuSpeeds.last ? "\(speed)% (maximum)" : "\(speed)%").tag(speed)
                    }
                }
                Toggle("Save state on exit", isOn: setting(\.saveStateOnExit))
                Toggle(isOn: setting(\.exitOnScreenOff)) {
                    LabeledRow(title: "Show calculators when turned off", detail: "[2ND] → [ON] turns the calculator off and shows the calculator list.")
                }
            }

            Section("Calculator") {
                NavigationLink(value: SettingsRoute.calculators) {
                    LabeledRow(title: "Calculators", detail: "Switch, add or remove calculators.")
                }
                Button { model.chooseFilesToSend() } label: {
                    LabeledRow(title: "Send files", detail: "Send programs, apps and variables to the calculator.")
                }
                .accessibilityIdentifier("sendFiles")
                Button { model.syncClock() } label: {
                    LabeledRow(title: "Sync clock", detail: nil)
                }
                Button { model.replaceRom() } label: {
                    LabeledRow(title: "Replace ROM file", detail: "Install a different OS or .rom file. This clears the saved state.")
                }
                Button { model.confirmReset = true } label: {
                    LabeledRow(title: "Reset calculator", detail: "Clear all RAM. This is the same as when you remove the batteries.", destructive: true)
                }
            }

            Section("About") {
                NavigationLink("About Graph89 Remastered", value: SettingsRoute.about)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { model.closeSettings() }
                    .accessibilityIdentifier("settingsDone")
            }
        }
    }
}

/// A title with an optional line of explanation below it.
struct LabeledRow: View {
    let title: String
    let detail: String?
    var destructive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(destructive ? Color.red : Color.primary)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// A slider that applies its value when the finger lifts (like the Android app's sliders).
private struct SliderRow: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let label: (Int) -> String
    var enabled = true
    let onCommit: (Int) -> Void

    @State private var current: Double?

    var body: some View {
        let shown = Int((current ?? Double(value)).rounded())
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: label(shown))
            Slider(
                value: Binding(get: { current ?? Double(value) }, set: { current = $0 }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1,
                onEditingChanged: { editing in
                    if !editing, let c = current {
                        onCommit(Int(c.rounded()))
                        current = nil
                    }
                }
            )
            .disabled(!enabled)
        }
    }
}
