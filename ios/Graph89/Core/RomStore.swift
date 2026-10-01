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
import UIKit

/// The installed calculators, in Application Support/Graph89. Each has a folder (named by its id) with image.img and
/// image.img.state; calculators.txt lists them ("id model" per line) and "active <id>" names the one on screen.
enum RomStore {
    private static let fm = FileManager.default

    /// Where everything is kept; tests point it at a folder of their own.
    nonisolated(unsafe) static var rootOverride: URL?

    static var root: URL {
        if let r = rootOverride { return r }
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Graph89", isDirectory: true)
    }

    private static var listFile: URL { root.appendingPathComponent("calculators.txt") }

    private static func mkdirs(_ url: URL) -> URL {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func tmpDir() -> URL { mkdirs(root.appendingPathComponent("tmp", isDirectory: true)) }

    // MARK: - calculator list

    static func calculators() -> [CalcEntry] { read().list }

    static func active() -> CalcEntry? {
        let (list, activeId) = read()
        return list.first { $0.id == activeId } ?? list.first
    }

    static func setActive(_ id: String) {
        write(calculators(), activeId: id)
    }

    private static func read() -> (list: [CalcEntry], activeId: String?) {
        guard let text = try? String(contentsOf: listFile, encoding: .utf8) else { return ([], nil) }
        var list: [CalcEntry] = []
        var activeId: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let p = line.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
            guard p.count == 2 else { continue }
            if p[0] == "active" {
                activeId = p[1]
            } else if let model = CalcModel(rawValue: p[1]) {
                list.append(CalcEntry(id: p[0], model: model))
            }
        }
        return (list, activeId)
    }

    private static func write(_ list: [CalcEntry], activeId: String?) {
        _ = mkdirs(root)
        var lines = list.map { "\($0.id) \($0.model.rawValue)" }
        if let id = activeId { lines.append("active \(id)") }
        try? (lines.joined(separator: "\n") + "\n").write(to: listFile, atomically: true, encoding: .utf8)
    }

    // MARK: - files of a calculator (the active one unless given)

    static func folder(_ id: String? = active()?.id) -> URL? {
        id.map { mkdirs(root.appendingPathComponent($0, isDirectory: true)) }
    }

    static func image(_ id: String? = active()?.id) -> URL? { folder(id)?.appendingPathComponent("image.img") }
    static func state(_ id: String? = active()?.id) -> URL? { folder(id)?.appendingPathComponent("image.img.state") }
    static func hasRom() -> Bool { image().map(isFile) ?? false }

    static func isFile(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &dir) && !dir.boolValue
    }

    private static func size(_ url: URL) -> Int64 {
        ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Checks a picked file before any native code parses it: a ROM dump must have the exact size of the
    /// model's flash, an OS upgrade the model's extension. A file without a known extension counts as a dump
    /// when its size fits, otherwise as an OS upgrade.
    /// Returns 0 and the file to install (renamed to the extension the native installer expects), or an error.
    private static func checkFile(_ model: CalcModel, _ file: URL) -> (Int32, URL) {
        let name = file.lastPathComponent.lowercased()
        let size = size(file)
        let isOsName = model.osExtension.map { name.hasSuffix($0) } ?? false
        let isDump = name.hasSuffix(".rom") || (!isOsName && size == model.romSize)
        if isDump {
            if size != model.romSize { return (801, file) }
            return (0, rename(file, ".rom"))
        }
        guard let os = model.osExtension else { return (802, file) }  // the TI-83 has no OS upgrades: only a dump works
        if [".89u", ".8xu", ".v2u", ".9xu"].contains(where: name.hasSuffix) {
            return (name.hasSuffix(os) ? 0 : 802, file)
        }
        if size < 64 * 1024 || size > 8 * 1024 * 1024 { return (802, file) }
        return (0, rename(file, os))
    }

    private static func rename(_ file: URL, _ ext: String) -> URL {
        if file.lastPathComponent.lowercased().hasSuffix(ext) { return file }
        let to = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ext)
        try? fm.removeItem(at: to)
        return (try? fm.moveItem(at: file, to: to)) != nil ? to : file
    }

    /// Builds image.img from an OS upgrade file or a .rom dump. Returns a native error code (0 = ok).
    private static func install(_ entry: CalcEntry, _ picked: URL) -> Int32 {
        let (check, source) = checkFile(entry.model, picked)
        if check != 0 { return check }
        guard let image = image(entry.id) else { return 776 }
        // build next to the current image so a failed replacement keeps the working ROM
        let next = image.deletingLastPathComponent().appendingPathComponent("image.img.new")
        let isRom = source.lastPathComponent.lowercased().hasSuffix(".rom")
        let error = EmulatorCore.installROM(source: source.path, destination: next.path, calcType: entry.model.type, isRom: isRom)
        if source != picked { try? fm.removeItem(at: source) }
        if error != 0 {
            try? fm.removeItem(at: next)
            return error
        }
        do {
            if isFile(image) { _ = try fm.replaceItemAt(image, withItemAt: next) } else { try fm.moveItem(at: next, to: image) }
        } catch {
            try? fm.removeItem(at: next)
            return 768
        }
        if let state = state(entry.id) { try? fm.removeItem(at: state) }  // a saved state belongs to the previous ROM
        return 0
    }

    /// Copies a user-picked OS file / ROM dump into the tmp folder (the native installer needs a real file path and
    /// checks the extension) and builds image.img from it for `entry`: an existing calculator ("Replace ROM") or a
    /// new one, which is then added to the list and made active. Runs file I/O: call it off the main thread.
    static func importFile(at url: URL, into entry: CalcEntry? = active()) -> Int32 {
        guard let target = entry else { return 772 }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent.isEmpty ? "rom.bin" : url.lastPathComponent
        let copy = tmpDir().appendingPathComponent("import_\(name)")
        defer { try? fm.removeItem(at: copy) }
        do {
            try? fm.removeItem(at: copy)
            try fm.copyItem(at: url, to: copy)
        } catch {
            return 768
        }
        let error = install(target, copy)
        let list = calculators()
        if error == 0 {
            write(list.contains { $0.id == target.id } ? list : list + [target], activeId: target.id)
        } else if !list.contains(where: { $0.id == target.id }), let dir = folder(target.id) {
            try? fm.removeItem(at: dir)  // a failed new calculator leaves nothing behind
        }
        return error
    }

    /// Deletes what an install the app was ended in the middle of left behind: folders of calculators that are not in
    /// the list, half-built images and copies of picked files.
    static func cleanUp() {
        let listed = Set(calculators().map(\.id))
        let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for item in items where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let name = item.lastPathComponent
            if name == "tmp" { continue }
            if listed.contains(name) {
                try? fm.removeItem(at: item.appendingPathComponent("image.img.new"))
            } else {
                try? fm.removeItem(at: item)
            }
        }
        let tmp = tmpDir()
        for item in (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] where item.lastPathComponent.hasPrefix("import_") {
            try? fm.removeItem(at: item)
        }
    }

    /// A new, not yet installed calculator of `model` with a unique folder id.
    static func newEntry(_ model: CalcModel) -> CalcEntry {
        let taken = Set(calculators().map(\.id))
        let base = model.rawValue.lowercased()
        var i = 1
        while taken.contains("\(base)-\(i)") || fm.fileExists(atPath: root.appendingPathComponent("\(base)-\(i)").path) { i += 1 }
        return CalcEntry(id: "\(base)-\(i)", model: model)
    }

    /// Deletes a calculator with its ROM image and saved state.
    static func remove(_ id: String) {
        let (list, activeId) = read()
        let rest = list.filter { $0.id != id }
        write(rest, activeId: activeId == id ? rest.first?.id : activeId)
        try? fm.removeItem(at: root.appendingPathComponent(id, isDirectory: true))
    }

    static func errorName(_ code: Int32) -> String {
        switch code {
        case 0: "ERR_NONE"
        case 768: "ERR_CANT_OPEN"
        case 770: "ERR_INVALID_IMAGE"
        case 771: "ERR_INVALID_UPGRADE"
        case 772: "ERR_NO_IMAGE"
        case 774: "ERR_INVALID_ROM_SIZE"
        case 775: "ERR_NOT_TI_FILE"
        case 776: "ERR_MALLOC"
        case 777: "ERR_CANT_OPEN_DIR"
        case 778: "ERR_CANT_UPGRADE"
        case 779: "ERR_INVALID_ROM"
        case 800: "The file type does not match this calculator"
        case 801: "The ROM dump has the wrong size for this calculator"
        case 802: "The file is not an OS upgrade for this calculator"
        case -1: "The file could not be read"
        case -2: "The file is not an OS upgrade for this calculator"
        case -3: "The OS upgrade could not be loaded"
        default: "Unknown error \(code)"
        }
    }
}

/// Runs a ROM install on a background thread. The calculator does not start meanwhile: the installer shares the
/// native emulator's global state.
enum RomInstaller {
    /// True while an install runs (read and written on the main thread).
    nonisolated(unsafe) private(set) static var running = false

    /// Runs `install` off the main thread, then hands its result (native error code, 0 = ok) to `completion` on
    /// the main thread.
    static func start(_ install: @escaping () -> Int32, completion: @escaping (Int32) -> Void) {
        if running { return }
        running = true
        // it finishes also when the user leaves the app meanwhile
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Install ROM") {
            UIApplication.shared.endBackgroundTask(task)
        }
        Thread {
            let error = install()
            DispatchQueue.main.async {
                running = false
                completion(error)
                UIApplication.shared.endBackgroundTask(task)
            }
        }.start()
    }
}
