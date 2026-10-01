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

/// A value shared between threads.
final class Atomic<Value> {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }

    /// Changes the value in one step (a get and a set apart could lose another thread's change in between).
    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&stored)
        lock.unlock()
    }

    /// Replaces the value and returns the old one, in one step.
    func swap(_ new: Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        let old = stored
        stored = new
        return old
    }
}

/// Owns the running emulation: skin, the two worker threads (engine + LCD refresh) and key input.
final class EmulatorSession {
    private let _isEmulating = Atomic(false)
    private(set) var isEmulating: Bool {
        get { _isEmulating.value }
        set { _isEmulating.value = newValue }
    }

    private let _syncClock = Atomic(false)
    var syncClock: Bool {
        get { _syncClock.value }
        set { _syncClock.value = newValue }
    }

    /// Set the clock once, a second after the calculator starts (after a new ROM, when the OS is booting).
    private let _syncClockAfterBoot = Atomic(false)
    var syncClockAfterBoot: Bool {
        get { _syncClockAfterBoot.value }
        set { _syncClockAfterBoot.value = newValue }
    }

    private let _resetCalc = Atomic(false)
    var resetCalc: Bool {
        get { _resetCalc.value }
        set { _resetCalc.value = newValue }
    }

    /// Save the state at the next turn of the engine loop, without stopping (the app may be ended without notice).
    private let saveRequested = Atomic(false)

    private let _config = Atomic(EmulatorConfig())
    /// Read by the worker threads; the next start applies all of it, key feedback applies at once.
    var config: EmulatorConfig {
        get { _config.value }
        set { _config.value = newValue }
    }

    private let _skin = Atomic<Skin?>(nil)
    private(set) var skin: Skin? {
        get { _skin.value }
        set { _skin.value = newValue }
    }

    /// The display as it was when the calculator last stopped (for the skin picker's previews).
    private let _lastScreen = Atomic<LcdSnapshot?>(nil)
    private(set) var lastScreen: LcdSnapshot? {
        get { _lastScreen.value }
        set { _lastScreen.value = newValue }
    }

    private(set) lazy var keypad = KeyPad(session: self)

    // Set by the UI. All except onDisplayChanged are called from worker threads: the UI moves them to the main thread.
    /// The skin is ready, a new LCD frame came or the emulation started or stopped: the view draws again.
    var onDisplayChanged: () -> Void = {}
    var onError: (String) -> Void = { _ in }
    /// The saved state of the calculator did not load; the UI offers to discard it.
    var onStateError: () -> Void = {}
    /// The user turned the calculator off ([2ND] [ON]).
    var onExit: () -> Void = {}
    /// The name of the file being sent to the calculator, then nil when all are sent.
    var onSending: (String?) -> Void = { _ in }
    /// Files the calculator did not take, with the native error code of each.
    var onSendFailed: ([String]) -> Void = { _ in }
    /// A file the calculator sent (TI-89 family), waiting to be saved.
    var onFileReceived: (LinkFiles.Received) -> Void = { _ in }

    /// Files waiting to be sent: the engine sends them while the calculator runs.
    private let toSend = Atomic<[URL]>([])

    /// Guards the start and stop of runs. Recursive, as pause() and onViewSize() call stop().
    private let lock = NSRecursiveLock()

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private var viewWidth = 0
    private var viewHeight = 0
    private var resumed = false
    private var installingFlag = false
    private var held = false

    /// A ROM install runs native code that shares global state with the engine: no start meanwhile.
    var installing: Bool {
        get { locked { installingFlag } }
        set {
            locked {
                installingFlag = newValue
                if !newValue { startIfReady() }
            }
        }
    }

    /// One start of the calculator. While `preparing` (the skin is being drawn) a stop only marks it `killed` and
    /// does not wait: the thread notices and ends by itself, so the main thread never waits for a skin drawing.
    /// Once the engine runs, a stop waits for it (the state is saved on the way out).
    private final class Run {
        let killed = Atomic(false)
        var preparing = true  // guarded by the session's lock
        let engineDone = DispatchGroup()
        let screenDone = DispatchGroup()
    }

    private var run: Run?
    private let firstCycleComplete = Atomic(false)

    /// When ON was last pressed (uptime): [2nd] [ON] turns the calculator off, its idle timer does too.
    private let lastOnPress = Atomic<TimeInterval>(0)

    private let haptics = Haptics()
    private var click: KeyClick?

    init() {
        EmulatorCore.fileReceiver = { [weak self] path, name in
            if let kept = LinkFiles.keepReceived(path: path, name: name) {
                self?.onFileReceived(kept)
            }
        }
    }

    /// Sends `files` (copies made by LinkFiles.stageForSending) to the calculator, which must be running for it.
    func sendFiles(_ files: [URL]) {
        toSend.mutate { $0 += files }
    }

    /// Saves the state soon, while the calculator keeps running (when the app may be about to be ended).
    func requestSave() {
        saveRequested.value = true
    }

    /// Drops what was asked of the calculator on screen (reset, clock sync, files to send) when another one takes its
    /// place, so it does not happen to that one.
    func forgetRequests() {
        resetCalc = false
        syncClock = false
        syncClockAfterBoot = false
        for f in toSend.swap([]) { LinkFiles.sent(f) }
    }

    // MARK: - lifecycle

    func resume() {
        locked {
            resumed = true
            startIfReady()
        }
    }

    func pause() {
        locked {
            resumed = false
            stop()
        }
    }

    /// The emulator view has a size (pixels): a new size draws the skin again.
    func onViewSize(width: Int, height: Int) {
        locked {
            if run != nil && (width != viewWidth || height != viewHeight) { stop() }
            viewWidth = width
            viewHeight = height
            startIfReady()
        }
    }

    /// The emulator view left the screen: stop, and forget its size until a new view reports one.
    func onViewDetached() {
        locked {
            stop()
            viewWidth = 0
            viewHeight = 0
        }
    }

    /// Deletes the saved state of the calculator on screen and starts it fresh.
    func discardStateAndRestart() {
        locked {
            stop()
            if let state = RomStore.state() { try? FileManager.default.removeItem(at: state) }
            startIfReady()
        }
    }

    /// While held (Settings is open over the calculator) the calculator stays stopped, also when its view lays out
    /// again; released, it starts with the session's config as it is then.
    func hold(_ on: Bool) {
        locked {
            held = on
            if on { stop() } else { startIfReady() }
        }
    }

    /// Starts the calculator again after a stop, when everything it needs is there.
    func restart() {
        locked { startIfReady() }
    }

    private func startIfReady() {
        if resumed && !held && !installingFlag && !RomInstaller.running && viewWidth > 0 && viewHeight > 0 && run == nil {
            start(viewWidth, viewHeight)
        }
    }

    /// The calculator being emulated (set when the emulation starts).
    private var model = CalcModel.TI89T

    private func start(_ width: Int, _ height: Int) {
        model = RomStore.active()?.model ?? .TI89T
        guard let image = RomStore.image() else {
            onError("Internal storage is not available.")
            return
        }
        if !RomStore.isFile(image) {
            onError("No ROM is installed.")
            return
        }
        let tmp = RomStore.tmpDir()

        keypad.reset()
        firstCycleComplete.value = false
        let cfg = config
        let model = self.model
        let r = Run()
        run = r
        r.engineDone.enter()
        // the skin is prepared on the engine thread, never on the main thread: a skin that has to be drawn
        // (not yet cached) takes a moment, and the app must not freeze meanwhile
        let thread = Thread { [self] in
            defer { r.engineDone.leave() }
            let s = Skin(type: cfg.skin, model: model)
            do {
                try s.initialize(width: width, height: height, config: cfg) { [weak self] in self?.onDisplayChanged() }
            } catch {
                if !r.killed.value { onError("The skin did not load.") }
                return
            }
            // from here on a stop waits for this thread; a stop that came while drawing ends it here
            let go: Bool = locked {
                if r.killed.value { return false }
                r.preparing = false
                skin = s
                return true
            }
            if !go {
                s.release()
                return
            }
            onDisplayChanged()  // the keypad shows while the calculator loads
            guard let screen = s.screen else { return }
            let err = EmulatorCore.initialize(
                calcType: model.type, lcdWidth: Int32(screen.rawWidth), lcdHeight: Int32(screen.rawHeight), zoom: Int32(screen.zoom),
                grayscale: cfg.grayscale, pixelOn: s.lcdPixelOn, pixelOff: s.lcdPixelOff,
                speed: Double(cfg.cpuSpeed) / 100, tmpDir: tmp.path
            )
            if err != 0 { return fail("The calculator did not start. Error code: \(err)") }
            engineRun(r, image)
        }
        thread.name = "Graph89 engine"
        thread.stackSize = 8 << 20  // the 68000 core recurses deeply (Android threads have a large stack too)
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        locked {
            guard let r = run else { return }
            run = nil
            r.killed.value = true
            if r.preparing { return }  // still drawing the skin: it ends by itself, nothing native has started
            EmulatorCore.abortLink()  // a file transfer in progress gives up, so the engine thread ends soon
            r.engineDone.wait()
            r.screenDone.wait()

            isEmulating = false
            if let s = skin, let snap = s.screen?.snapshot(pixelOff: s.lcdPixelOff, pixelOn: s.lcdPixelOn) { lastScreen = snap }
            EmulatorCore.shutdown()
            EngineScreenParams.reset()
            skin?.release()
            skin = nil
            onDisplayChanged()
        }
    }

    // MARK: - input

    /// Main thread.
    func sendKey(_ key: Int, active: Bool, haptic: Bool) {
        if !isEmulating { return }
        if haptic {
            let cfg = config
            if cfg.hapticMs > 0 { haptics.play(ms: cfg.hapticMs, strength: cfg.hapticStrength) }
            if cfg.audioFeedback {
                if click == nil { click = KeyClick() }
                click?.play()
            }
        }
        if active && Int32(key) == model.engine.onKey { lastOnPress.value = ProcessInfo.processInfo.systemUptime }
        EmulatorCore.sendKey(Int32(key), pressed: active)
    }

    /// One pulse, so the user can feel a vibration time or strength while choosing it.
    func previewVibration(ms: Int, strength: Int) {
        if ms > 0 { haptics.play(ms: ms, strength: strength) }
    }

    /// True when the phone can vibrate at different strengths.
    var hasAmplitudeControl: Bool { haptics.supportsHaptics }

    // MARK: - engine thread

    private func fail(_ message: String) { onError(message) }

    private func engineRun(_ r: Run, _ image: URL) {
        let loaded = EmulatorCore.loadImage(image.path)
        if loaded.code != 0 {
            return fail("\(loaded.initFailed ? "The initialization failed" : "The IMG file did not load"). Error code: \(RomStore.errorName(loaded.code))")
        }

        if loadState() != 0 {
            onStateError()
            return
        }

        EmulatorCore.turnScreenOn()

        let speedCoefficient = Float(config.cpuSpeed) / 100
        r.screenDone.enter()
        let screenThread = Thread { [self] in
            defer { r.screenDone.leave() }
            screenRun(r)
        }
        screenThread.name = "Graph89 screen"
        screenThread.qualityOfService = .userInteractive
        screenThread.start()

        isEmulating = true
        onDisplayChanged()

        var runCntr = 0
        let loopStart = ProcessInfo.processInfo.systemUptime
        let sleepInterval = TimeInterval(Int(Float(Self.engineLoopSleep) / speedCoefficient)) / 1000

        while true {
            runCntr += 1

            if r.killed.value {
                // don't save if the engine hasn't run for a second or so; it might corrupt the state
                if runCntr > 20 { writeState() }
                break
            }

            if saveRequested.swap(false) && runCntr > 20 { writeState() }

            if resetCalc {
                _ = EmulatorCore.reset()
                resetCalc = false
            }

            if !toSend.value.isEmpty { sendQueued(r) }

            guard let screen = skin?.screen else { break }

            if syncClock || (syncClockAfterBoot && ProcessInfo.processInfo.systemUptime - loopStart > Self.bootTime) {
                EmulatorCore.syncClock()
                syncClock = false
                syncClockAfterBoot = false
            }

            runEngine()
            firstCycleComplete.value = true

            if screen.isBusy() {
                // turbo while busy; one iteration takes about 4 ms
                var i = 0
                while i < 30 && !r.killed.value && screen.isBusy() {
                    runEngine()
                    i += 1
                }
                Thread.sleep(forTimeInterval: 0.001)
            } else {
                Thread.sleep(forTimeInterval: sleepInterval)
            }
        }
    }

    /// Sends the queued files one after another (each transfer runs the calculator itself until it is done).
    private func sendQueued(_ r: Run) {
        let files = toSend.swap([])
        var failed: [String] = []
        for f in files {
            if r.killed.value {
                LinkFiles.sent(f)  // the calculator is stopping: the rest is dropped
                continue
            }
            onSending(f.lastPathComponent)
            let code = EmulatorCore.sendFile(f.path)
            if code != 0 { failed.append("\(f.lastPathComponent) (error \(code))") }
            LinkFiles.sent(f)
        }
        onSending(nil)
        if !failed.isEmpty { onSendFailed(failed) }
    }

    private func runEngine() {
        EmulatorCore.runSlice()
    }

    private func screenRun(_ r: Run) {
        var prevScreenOff = true
        while !r.killed.value {
            guard let screen = skin?.screen else { return }
            screen.refresh()
            let screenOff = screen.isScreenOff()

            // only when the user turned it off: after its idle timer (APD) the screen just stays blank
            if firstCycleComplete.value && !r.killed.value && config.exitOnScreenOff && !prevScreenOff && screenOff &&
                ProcessInfo.processInfo.systemUptime - lastOnPress.value < Self.offAfterOn {
                onExit()
            }
            prevScreenOff = screenOff
            Thread.sleep(forTimeInterval: Self.screenLoopSleep)
        }
    }

    private func loadState() -> Int32 {
        guard let image = RomStore.image(), RomStore.isFile(image), let state = RomStore.state() else { return -1 }
        if !RomStore.isFile(state) { return 0 }
        return EmulatorCore.loadState(state.path)
    }

    /// Saves into new files, then puts them in place: the app being ended halfway through never leaves a broken state
    /// or (TilEm, whose save writes the whole flash with the archive) a broken image.
    private func writeState() {
        guard config.saveStateOnExit, let state = RomStore.state(), let image = RomStore.image() else { return }
        let fm = FileManager.default
        let tilem = model.engine == .tilem
        let newState = state.deletingLastPathComponent().appendingPathComponent("image.img.state.saving")
        let newImage = image.deletingLastPathComponent().appendingPathComponent("image.img.saving")
        let ok = EmulatorCore.saveState(image: tilem ? newImage.path : image.path, state: newState.path) == 0
        func place(_ new: URL, _ url: URL) -> Bool {
            if fm.fileExists(atPath: url.path) { return (try? fm.replaceItemAt(url, withItemAt: new)) != nil }
            return (try? fm.moveItem(at: new, to: url)) != nil
        }
        // the flash first, then the state that goes with it
        if ok && (!tilem || place(newImage, image)) { _ = place(newState, state) }
        try? fm.removeItem(at: newState)
        try? fm.removeItem(at: newImage)
    }

    private static let engineLoopSleep = 30  // ms
    private static let screenLoopSleep: TimeInterval = 0.05
    private static let bootTime: TimeInterval = 1
    /// The calculator turns off within this time of an ON press when the user turned it off.
    private static let offAfterOn: TimeInterval = 2
}

/// Multi-touch key tracking: which key each finger holds. Main thread only.
final class KeyPad {
    private unowned let session: EmulatorSession
    private var pressed: [KeyPress] = []
    var onChanged: () -> Void = {}

    init(session: EmulatorSession) {
        self.session = session
    }

    func reset() {
        pressed.removeAll()
    }

    func press(_ key: KeyPress) {
        if isInvalid(key.keyCode) { return }
        let found = pressed.contains { $0.keyCode == key.keyCode || $0.touchId == key.touchId }
        if !found {
            pressed.append(key)
            session.sendKey(key.keyCode, active: true, haptic: true)
        }
        onChanged()
    }

    func unpress(touchId: Int) {
        guard let i = pressed.firstIndex(where: { $0.touchId == touchId }) else { return }
        session.sendKey(pressed[i].keyCode, active: false, haptic: false)
        pressed.remove(at: i)
        onChanged()
    }

    func unpressAll() {
        for k in pressed { session.sendKey(k.keyCode, active: false, haptic: false) }
        pressed.removeAll()
        onChanged()
    }

    func pressedKeys() -> [KeyPress] { pressed }

    private func isInvalid(_ code: Int) -> Bool { code < 0 || code >= 255 }
}
