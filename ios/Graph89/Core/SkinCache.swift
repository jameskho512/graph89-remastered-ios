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
import Foundation

/// Drawn keypads, so the calculator does not draw its skin again at every start: the last one in memory,
/// recent ones as files in the app's Caches folder. A keypad depends on the calculator model, the skin and the
/// size of the keypad area; the build is part of the key, so an update never shows an old drawing.
enum SkinCache {
    /// A drawn keypad: `image` covers the whole keypad area; `keypad` (in area coordinates) is where the mask maps.
    struct Entry {
        let image: CGImage
        let keypad: CGRect
        let mask: [UInt8]
        let maskWidth: Int
        let maskHeight: Int
        let backgroundColor: ARGB
    }

    private static let keep = 8  // files kept on disk (most recently used)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var memKey: String?
    nonisolated(unsafe) private static var mem: Entry?
    private static let fm = FileManager.default

    /// This build: its version and the time its executable was made. Part of every cache key.
    static let stamp: String = {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "")-\(info?["CFBundleVersion"] ?? "")"
        let built = Bundle.main.executableURL.flatMap { try? fm.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        return "\(version)-\(Int(built?.timeIntervalSince1970 ?? 0))"
    }()

    static var cacheDir: URL { fm.urls(for: .cachesDirectory, in: .userDomainMask)[0] }

    /// Empties the drawn skins and thumbnails the first time a new build runs, so nothing drawn by the previous
    /// build is left behind.
    static func wipeIfNewBuild() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "cache_build") == stamp { return }
        for name in ["skins", "thumbs"] { try? fm.removeItem(at: cacheDir.appendingPathComponent(name)) }
        clearMemory()
        defaults.set(stamp, forKey: "cache_build")
    }

    /// Forgets the in-memory entry (the files stay).
    static func clearMemory() {
        lock.lock()
        memKey = nil
        mem = nil
        lock.unlock()
    }

    static func key(model: CalcModel, type: SkinType, width: Int, height: Int, oledContrast: Int, threeD: Bool) -> String {
        let variant = (type == .OLED ? "_c\(oledContrast)" : "") + (threeD ? "_3d" : "")
        return "\(model.rawValue)_\(type.rawValue)\(variant)_\(width)x\(height)_\(stamp)"
    }

    private static func dir() -> URL {
        let d = cacheDir.appendingPathComponent("skins", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func get(_ key: String) -> Entry? {
        lock.lock()
        if memKey == key, let m = mem {
            lock.unlock()
            return m
        }
        lock.unlock()
        let png = dir().appendingPathComponent("\(key).png")
        let bin = dir().appendingPathComponent("\(key).bin")
        guard let image = Graphics.image(contentsOf: png), let data = try? Data(contentsOf: bin), data.count >= 28 else {
            try? fm.removeItem(at: png)
            try? fm.removeItem(at: bin)
            return nil
        }
        // big-endian ints: keypad left, top, right, bottom, mask width, mask height, background; then the mask
        func int(_ i: Int) -> Int32 { data.withUnsafeBytes { Int32(bigEndian: $0.loadUnaligned(fromByteOffset: i * 4, as: Int32.self)) } }
        let w = Int(int(4)), h = Int(int(5))
        guard w > 0, h > 0, data.count == 28 + w * h else {
            try? fm.removeItem(at: png)
            try? fm.removeItem(at: bin)
            return nil
        }
        let keypad = CGRect(x: Int(int(0)), y: Int(int(1)), width: Int(int(2) - int(0)), height: Int(int(3) - int(1)))
        let entry = Entry(image: image, keypad: keypad, mask: [UInt8](data.suffix(from: 28)), maskWidth: w, maskHeight: h, backgroundColor: ARGB(bitPattern: int(6)))
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: png.path)
        lock.lock()
        memKey = key
        mem = entry
        lock.unlock()
        return entry
    }

    /// Keeps `entry` in memory and writes it to disk in the background.
    static func put(_ key: String, _ entry: Entry) {
        lock.lock()
        memKey = key
        mem = entry
        lock.unlock()
        let d = dir()
        DispatchQueue.global(qos: .utility).async {
            var data = Data()
            func append(_ v: Int32) { withUnsafeBytes(of: v.bigEndian) { data.append(contentsOf: $0) } }
            let k = entry.keypad
            for v in [Int(k.minX), Int(k.minY), Int(k.maxX), Int(k.maxY), entry.maskWidth, entry.maskHeight] { append(Int32(v)) }
            append(Int32(bitPattern: entry.backgroundColor))
            data.append(contentsOf: entry.mask)
            let tmp = d.appendingPathComponent("\(key).tmp.png")
            // a missing cache file only means the skin is drawn again next time
            guard Graphics.writePNG(entry.image, to: tmp), (try? data.write(to: d.appendingPathComponent("\(key).bin"))) != nil else { return }
            let png = d.appendingPathComponent("\(key).png")
            try? fm.removeItem(at: png)
            try? fm.moveItem(at: tmp, to: png)
            prune(d)
        }
    }

    private static func prune(_ d: URL) {
        let files = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let pngs = files.filter { $0.pathExtension == "png" && !$0.lastPathComponent.hasSuffix(".tmp.png") }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for old in pngs.dropFirst(keep) {
            try? fm.removeItem(at: old)
            try? fm.removeItem(at: old.deletingPathExtension().appendingPathExtension("bin"))
        }
    }
}
