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
import UniformTypeIdentifiers

/// The calculator, or the calculator list when none is installed or the calculator was turned off; Settings opens
/// over it from the menu.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.calculatorsAsRoot {
                NavigationStack {
                    CalculatorsView(model: model, asRoot: true)
                }
            } else {
                EmulatorScreenView(model: model)
                    .ignoresSafeArea()
                    .statusBarHidden(true)
                    .persistentSystemOverlays(.hidden)
                    .defersSystemGestures(on: .all)
            }
        }
        .modalHost(model, isTop: !model.settingsOpen)
        .confirmationDialog("Graph89", isPresented: $model.menuOpen, titleVisibility: .hidden) {
            Button("Settings") { model.openSettings() }
            Button("Calculators") { model.openCalculatorsFromMenu() }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: Binding(get: { model.settingsOpen }, set: { if !$0 { model.closeSettings() } })) {
            NavigationStack(path: $model.settingsPath) {
                SettingsView(model: model)
                    .navigationDestination(for: SettingsRoute.self) { route in
                        switch route {
                        case .skinPicker: SkinPickerView(model: model)
                        case .calculators: CalculatorsView(model: model, asRoot: false)
                        case .about: AboutView()
                        }
                    }
            }
            .modalHost(model, isTop: true)
        }
    }
}

extension View {
    /// The app's dialogs, progress notes, file pickers and notices. Applied to the screen on top only (the root, or
    /// Settings while it is open), since a covered view cannot present anything.
    func modalHost(_ model: AppModel, isTop: Bool) -> some View {
        modifier(ModalHost(model: model, isTop: isTop))
    }
}

private struct ModalHost: ViewModifier {
    @Bindable var model: AppModel
    let isTop: Bool

    private func shown(_ condition: Bool, onDismiss: @escaping () -> Void = {}) -> Binding<Bool> {
        Binding(get: { isTop && condition }, set: { if !$0 { onDismiss() } })
    }

    func body(content: Content) -> some View {
        let request = model.importRequest
        let offered = model.offeredFile
        let saving = model.saving
        content
            .overlay {
                if isTop, model.installing || model.sendingFile != nil {
                    ProgressNote(text: model.installing ? "Installing the ROM" : "Sending \(model.sendingFile ?? "")")
                }
            }
            .overlay(alignment: .bottom) {
                if isTop, let notice = model.notice {
                    Text(notice)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 48)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.notice)
            .fileImporter(
                isPresented: shown(request != nil) { model.importRequest = nil },
                allowedContentTypes: [.data],
                allowsMultipleSelection: request == .sendFiles
            ) { result in
                guard let request, case .success(let urls) = result else { return }
                model.filesPicked(urls, for: request)
            }
            .fileExporter(
                // closed without a result (cancelled): the file is offered again; after onCompletion this does nothing
                isPresented: shown(saving != nil) { DispatchQueue.main.async { model.savingFinished(saved: false) } },
                document: saving.map { ReceivedFileDocument(url: $0.url) },
                contentType: .data,
                defaultFilename: saving?.name
            ) { result in
                switch result {
                case .success:
                    model.savingFinished(saved: true)
                case .failure(let error):
                    let cancelled = (error as? CocoaError)?.code == .userCancelled
                    model.savingFinished(saved: false, error: cancelled ? nil : error)
                }
            }
            .alert("Reset the calculator?", isPresented: shown(model.confirmReset) { model.confirmReset = false }) {
                Button("Reset", role: .destructive) { model.resetCalculator() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(model.activeModel.engine == .tilem
                    ? "The reset clears all RAM and also erases the archive and all apps. Only the OS stays. You cannot undo this."
                    : "The reset clears all RAM. You lose all data that is not in the archive. This is the same as when you remove the batteries.")
            }
            .alert("The saved state did not load", isPresented: shown(model.stateError)) {
                Button("Discard state", role: .destructive) { model.discardStateAndRestart() }
                Button("Keep it") { model.keepDamagedState() }
            } message: {
                Text("The saved state of this calculator is damaged or belongs to a different ROM. Discard it to start the calculator fresh, or keep the file and leave the calculator off. The ROM and the archive stay.")
            }
            .alert("File received", isPresented: shown(offered != nil && model.errorMessage == nil)) {
                if let file = offered {
                    Button("Save") { model.saveReceived(file) }
                    Button("Discard", role: .destructive) { model.discardReceived(file) }
                }
            } message: {
                Text("The calculator sent \(offered?.name ?? "a file"). Save it on the phone?")
            }
            .alert("Error", isPresented: shown(model.errorMessage != nil) { model.errorMessage = nil }) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
    }
}

/// A modal note with a spinner, for work that cannot be stopped halfway (ROM install, file transfer).
private struct ProgressNote: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            HStack(spacing: 16) {
                ProgressView()
                Text(text)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// A file the calculator sent, for the export picker.
struct ReceivedFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    let data: Data

    init(url: URL) {
        data = (try? Data(contentsOf: url)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
