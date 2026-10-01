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

/// Files that go over the calculator's link port: apps, programs and variables sent to it from the phone, and the
/// files it sends back (TI-89 family). Both wait in folders under the app's tmp folder.
enum LinkFiles {
    /// A file the calculator sent: `url` holds it until it is saved or discarded; `name` is its file name.
    struct Received: Identifiable, Equatable {
        let url: URL
        let name: String
        var id: URL { url }
    }

    private static let fm = FileManager.default

    private static func dir(_ name: String) -> URL {
        let url = RomStore.tmpDir().appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies picked documents into the send folder under their own names (the native link code tells the file
    /// type by its extension). Returns the copies to send and the names of the files `model` does not take.
    /// Runs file I/O: call it off the main thread.
    static func stageForSending(_ model: CalcModel, _ urls: [URL]) -> (staged: [URL], rejected: [String]) {
        let folder = dir("send")
        var staged: [URL] = []
        var rejected: [String] = []
        for url in urls {
            let name = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
            if !model.linkExtensions.contains(where: { name.lowercased().hasSuffix($0) }) {
                rejected.append(name)
                continue
            }
            // each file in a folder of its own, so two files with the same name can be sent together
            let own = folder.appendingPathComponent(String(DispatchTime.now().uptimeNanoseconds), isDirectory: true)
            let copy = own.appendingPathComponent(name)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try fm.createDirectory(at: own, withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: copy)
                staged.append(copy)
            } catch {
                try? fm.removeItem(at: own)
                rejected.append(name)
            }
        }
        return (staged, rejected)
    }

    /// Deletes a file after it was sent (with the folder `stageForSending` made for it).
    static func sent(_ file: URL) {
        try? fm.removeItem(at: file.deletingLastPathComponent())
    }

    /// Keeps a file the calculator just sent: `path` is reused for the next one, so the file moves to the received
    /// folder. Called on the engine thread. Returns nil when the file could not be kept.
    static func keepReceived(path: String, name: String) -> Received? {
        let source = URL(fileURLWithPath: path)
        // a variable without a name (only its type) still gets a usable file name
        var clean = name.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix(".") { clean = "noname" + clean }
        if clean.isEmpty { clean = "noname" }
        // its own folder, so the file keeps its exact name for the share sheet / save dialog
        let own = dir("received").appendingPathComponent(String(DispatchTime.now().uptimeNanoseconds), isDirectory: true)
        let kept = own.appendingPathComponent(clean)
        do {
            try fm.createDirectory(at: own, withIntermediateDirectories: true)
            do {
                try fm.moveItem(at: source, to: kept)
            } catch {
                defer { try? fm.removeItem(at: source) }
                try fm.copyItem(at: source, to: kept)
            }
        } catch {
            try? fm.removeItem(at: own)
            return nil
        }
        return Received(url: kept, name: clean)
    }

    /// Deletes a received file once it is saved or discarded.
    static func discard(_ received: Received) {
        try? fm.removeItem(at: received.url.deletingLastPathComponent())
    }

    /// Deletes files left from an earlier run: sends that did not finish and received files never saved.
    static func clear() {
        let tmp = RomStore.tmpDir()
        try? fm.removeItem(at: tmp.appendingPathComponent("send"))
        try? fm.removeItem(at: tmp.appendingPathComponent("received"))
    }
}
