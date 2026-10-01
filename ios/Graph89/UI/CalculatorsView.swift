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

/// The installed calculators: tap one to show it, add a new one from an OS / ROM file, or remove one.
/// As the root (`asRoot`) it fills the screen: with nothing installed it is the app's first screen and explains what
/// to do; after the calculator was turned off it is where the user picks it up again.
struct CalculatorsView: View {
    @Bindable var model: AppModel
    let asRoot: Bool

    @State private var choosingModel = false
    @State private var removing: CalcEntry?

    private var firstRun: Bool { !model.romInstalled }

    var body: some View {
        List {
            if firstRun {
                Section {
                    Text("The app emulates TI graphing calculators. It does not include their operating system. Add a calculator and select an OS upgrade file or a ROM dump of your own calculator.")
                }
            }
            if !model.calculators.isEmpty {
                Section {
                    ForEach(model.calculators) { c in
                        Button { model.selectCalculator(c) } label: { row(c) }
                            .accessibilityIdentifier("calculator-\(c.id)")
                            .swipeActions {
                                Button("Remove", role: .destructive) { removing = c }
                            }
                    }
                }
            }
            Section {
                Button { choosingModel = true } label: {
                    Label {
                        LabeledRow(title: "Add calculator", detail: "Select the model, then its OS or ROM file.")
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
                .accessibilityIdentifier("addCalculator")
            }
        }
        .navigationTitle(firstRun ? "Graph89 Remastered" : "Calculators")
        .toolbar {
            if asRoot && !firstRun {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.closeCalculators() }
                }
            }
        }
        .confirmationDialog("Add calculator", isPresented: $choosingModel, titleVisibility: .visible) {
            ForEach(CalcModel.allCases) { m in
                Button("\(m.label) (\(m.romFiles))") { model.addCalculator(m) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Remove \(removing?.model.label ?? "")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
        ) {
            Button("Remove", role: .destructive) {
                if let c = removing { model.removeCalculator(c) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("The app deletes the ROM image and the saved state of this calculator. Your files are not changed.")
        }
    }

    private func row(_ c: CalcEntry) -> some View {
        let same = model.calculators.filter { $0.model == c.model }.count > 1
        let name = same ? "\(c.model.label) (\(c.id.split(separator: "-").last.map(String.init) ?? c.id))" : c.model.label
        let active = c.id == model.activeId
        return HStack {
            Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .opacity(active ? 1 : 0)
            LabeledRow(title: name, detail: active ? "On screen" : nil)
            Spacer()
            Button { removing = c } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .tint(.red)
            .accessibilityLabel("Remove")
        }
        .contentShape(Rectangle())
    }
}
