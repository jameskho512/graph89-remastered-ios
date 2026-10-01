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

import Foundation
import Observation
import UIKit

/// What the file picker is open for.
enum ImportRequest: Equatable {
    /// An OS upgrade / ROM dump for a calculator: a new one being added, or the one on screen ("Replace ROM").
    case rom(CalcEntry?)
    /// Programs, apps and variables to send to the calculator.
    case sendFiles
}

/// Screens pushed inside Settings.
enum SettingsRoute: Hashable {
    case skinPicker, calculators, about
}

/// The app's state and actions (the Android app's MainActivity): which screen shows, the dialogs, and the emulation.
/// Main thread only; the session's callbacks come here through the main queue.
@Observable
final class AppModel {
    let session = EmulatorSession()
    private let settings = SettingsStore()

    private(set) var config = EmulatorConfig()
    var errorMessage: String?
    /// A short note at the bottom of the screen (the Android app's toasts).
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: DispatchWorkItem?

    private(set) var romInstalled = false
    private(set) var installing = false
    var stateError = false

    var menuOpen = false
    var confirmReset = false
    /// Settings is open (the calculator is stopped meanwhile); `settingsPath` holds the screens pushed in it.
    private(set) var settingsOpen = false
    var settingsPath: [SettingsRoute] = []
    /// The calculator list fills the screen: the first screen of the app, and after [2ND] [ON] turned the calculator off.
    private(set) var showCalculators = false

    private(set) var calculators: [CalcEntry] = []
    private(set) var activeId: String?
    /// The calculator on screen.
    private(set) var activeModel = CalcModel.TI89T

    /// The file picker, while it is open.
    var importRequest: ImportRequest?

    /// The file being sent to the calculator (a progress dialog shows meanwhile).
    private(set) var sendingFile: String?
    /// Files the calculator sent, waiting to be saved or discarded (the first one is offered).
    private(set) var received: [LinkFiles.Received] = []
    /// The received file being saved (the export picker is open).
    var saving: LinkFiles.Received?

    /// Size in pixels of the calculator's view on this phone (for the skin picker's previews and the screen scale).
    var emulatorViewSize = CGSize(width: 1179, height: 2556)

    /// A new ROM's clock is set once it runs; not for the test operating systems, which do not speak the link protocol.
    @ObservationIgnored private var syncClockAfterInstall = true

    init() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["G89_RESET"] == "1" {  // UI tests: start as a new installation
            try? FileManager.default.removeItem(at: RomStore.root)
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        }
        #endif
        SkinCache.wipeIfNewBuild()
        config = settings.load()
        refreshCalculators()
        LinkFiles.clear()  // files left from an earlier run (a send cut short, received files never saved)

        session.config = config
        session.onError = { [weak self] message in DispatchQueue.main.async { self?.errorMessage = message } }
        session.onStateError = { [weak self] in DispatchQueue.main.async { self?.stateError = true } }
        session.onExit = { [weak self] in DispatchQueue.main.async { self?.calculatorTurnedOff() } }
        session.onSending = { [weak self] name in DispatchQueue.main.async { self?.sendingFile = name } }
        session.onSendFailed = { [weak self] files in
            DispatchQueue.main.async {
                self?.errorMessage = "The calculator did not take:\n\(files.joined(separator: "\n"))\n\nShow the home screen on the calculator and try again."
            }
        }
        session.onFileReceived = { [weak self] file in DispatchQueue.main.async { self?.received.append(file) } }

        #if DEBUG
        // UI tests: install a calculator OS from a file at the first start (like the Android debug build's bundled OS)
        if calculators.isEmpty, let path = env["G89_INSTALL_ROM"], let model = env["G89_INSTALL_MODEL"].flatMap(CalcModel.init(rawValue:)) {
            syncClockAfterInstall = false
            installRom { RomStore.importFile(at: URL(fileURLWithPath: path), into: RomStore.newEntry(model)) }
        }
        #endif
    }

    /// The calculator list is the whole screen: nothing is installed yet, or the user left the calculator.
    var calculatorsAsRoot: Bool { !romInstalled || showCalculators }

    // MARK: - lifecycle

    /// The app came to the foreground.
    func appBecameActive() {
        session.resume()
    }

    /// The app went to the background: the state is saved now, as iOS may end the app without notice.
    func appEnteredBackground() {
        session.keypad.unpressAll()
        let task = UIApplication.shared.beginBackgroundTask(withName: "Save calculator state")
        session.pause()
        UIApplication.shared.endBackgroundTask(task)
    }

    // MARK: - settings and menu

    func updateConfig(_ updated: EmulatorConfig) {
        config = updated
        settings.save(updated)
    }

    /// Key vibration and click apply at once, without restarting the calculator.
    func updateFeedback(_ updated: EmulatorConfig) {
        updateConfig(updated)
        var c = session.config
        c.hapticMs = updated.hapticMs
        c.hapticStrength = updated.hapticStrength
        c.audioFeedback = updated.audioFeedback
        session.config = c
    }

    func openMenu() {
        session.keypad.unpressAll()
        menuOpen = true
    }

    func openSettings() {
        menuOpen = false
        session.keypad.unpressAll()
        session.hold(true)  // settings are applied by starting the emulation again with the new values
        settingsPath = []
        settingsOpen = true
    }

    func closeSettings() {
        settingsOpen = false
        settingsPath = []
        session.config = config
        session.hold(false)
    }

    /// The calculator list, from the menu: the calculator stops (and saves) like the Android app's Exit.
    func openCalculatorsFromMenu() {
        menuOpen = false
        session.keypad.unpressAll()
        session.stop()
        refreshCalculators()
        showCalculators = true
    }

    /// [2ND] [ON]: the Android app closes; here the calculator stops (and saves) and the calculator list shows.
    private func calculatorTurnedOff() {
        guard romInstalled, !showCalculators, !settingsOpen else { return }
        menuOpen = false
        session.keypad.unpressAll()
        session.stop()
        refreshCalculators()
        showCalculators = true
    }

    /// Closes the full-screen calculator list (when a calculator is installed): back to the calculator.
    func closeCalculators() {
        guard romInstalled else { return }
        showCalculators = false
        session.restart()
    }

    func refreshCalculators() {
        calculators = RomStore.calculators().filter { RomStore.image($0.id).map(RomStore.isFile) ?? false }
        let active = RomStore.active()
        activeId = active?.id
        activeModel = active?.model ?? .TI89T
        romInstalled = RomStore.hasRom()
    }

    /// Shows `c`: from the full-screen list or from Settings, the app goes straight to the calculator.
    func selectCalculator(_ c: CalcEntry) {
        session.stop()
        RomStore.setActive(c.id)
        refreshCalculators()
        if settingsOpen { closeSettings() }
        showCalculators = false
        session.restart()
    }

    func addCalculator(_ model: CalcModel) {
        importRequest = .rom(RomStore.newEntry(model))
    }

    func removeCalculator(_ c: CalcEntry) {
        if c.id == activeId { session.stop() }
        RomStore.remove(c.id)
        refreshCalculators()
    }

    func replaceRom() {
        importRequest = .rom(nil)
    }

    /// Settings closes first: the files go as soon as the calculator runs again, back from the picker.
    func chooseFilesToSend() {
        if settingsOpen { closeSettings() }
        importRequest = .sendFiles
    }

    /// The file picker's result for `request`.
    func filesPicked(_ urls: [URL], for request: ImportRequest) {
        switch request {
        case .rom(let target):
            guard let url = urls.first else { return }
            installRom { RomStore.importFile(at: url, into: target ?? RomStore.active()) }
        case .sendFiles:
            if !urls.isEmpty { sendFiles(urls) }
        }
    }

    /// The engine is stopped while Settings is open, so it runs when the calculator starts again.
    func syncClock() {
        session.syncClock = true
        closeSettings()
        showNotice("The clock is synchronized.")
    }

    func resetCalculator() {
        session.resetCalc = true
        closeSettings()
    }

    func discardStateAndRestart() {
        stateError = false
        session.discardStateAndRestart()
    }

    /// The saved state did not load and the user keeps it: the calculator list shows instead of the calculator.
    func keepDamagedState() {
        stateError = false
        session.stop()
        refreshCalculators()
        showCalculators = true
    }

    // MARK: - link files

    /// Copies the picked files off the main thread, then queues those the calculator takes for sending.
    private func sendFiles(_ urls: [URL]) {
        let model = activeModel
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (files, rejected) = LinkFiles.stageForSending(model, urls)
            DispatchQueue.main.async {
                guard let self else { return }
                if !files.isEmpty { self.session.sendFiles(files) }
                if !rejected.isEmpty {
                    self.errorMessage = "The \(model.label) does not take:\n\(rejected.joined(separator: "\n"))\n\n" +
                        "It takes \(model.linkExtensions.sorted().joined(separator: " ")) files."
                }
            }
        }
    }

    /// The first received file, offered to save.
    var offeredFile: LinkFiles.Received? { saving == nil ? received.first : nil }

    func saveReceived(_ file: LinkFiles.Received) {
        saving = file
    }

    /// The export picker closed: `saved` tells whether the file was saved.
    func savingFinished(saved: Bool, error: Error? = nil) {
        guard let file = saving else { return }
        saving = nil
        if saved {
            received.removeAll { $0 == file }
            LinkFiles.discard(file)
            showNotice("\(file.name) is saved.")
        } else if error != nil {
            errorMessage = "\(file.name) could not be saved. Try another folder."
        }
    }

    func discardReceived(_ file: LinkFiles.Received) {
        received.removeAll { $0 == file }
        LinkFiles.discard(file)
    }

    // MARK: - ROM install

    /// User import and "Replace ROM": a failed install keeps the previous ROM.
    private func installRom(_ install: @escaping () -> Int32) {
        if RomInstaller.running { return }
        installing = true
        session.stop()
        session.installing = true
        RomInstaller.start(install) { [weak self] error in self?.installFinished(error) }
    }

    private func installFinished(_ error: Int32) {
        installing = false
        refreshCalculators()
        if error == 0 {
            showCalculators = false
            if settingsOpen { closeSettings() }
            session.syncClockAfterBoot = syncClockAfterInstall  // a new ROM starts with the default date; the engine sets the clock once
            showNotice("The ROM is installed.")
        } else {
            errorMessage = "The ROM installation failed. Error: \(RomStore.errorName(error))"
        }
        // the engine starts again once the calculator is on screen
        session.installing = false
    }

    // MARK: - notices

    func showNotice(_ text: String) {
        noticeTask?.cancel()
        notice = text
        let task = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: task)
    }

    /// The largest whole-number screen scale on this phone.
    var maxScreenZoom: Int { max(Int(emulatorViewSize.width) / activeModel.lcdWidth, 1) }
}
