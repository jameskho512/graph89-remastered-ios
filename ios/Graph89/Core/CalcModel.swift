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

/// The emulation engine of a model. `onKey` is the native key code of the calculator's ON key.
enum Engine {
    case tiemu, tilem

    var onKey: Int32 { self == .tiemu ? 78 : 41 }
}

/// The emulated calculator models. `type` is the calculator type code shared with the native wrapper,
/// `skin` the skin family (folder prefix under assets/portrait) and `lcdWidth` x `lcdHeight` the LCD.
/// The raw value is the name stored in calculators.txt (the same as the Android app's).
enum CalcModel: String, CaseIterable, Identifiable {
    case TI89T, TI89, TI84PLUS_SE, TI84PLUS, TI83PLUS_SE, TI83PLUS, TI83

    var id: String { rawValue }

    var type: Int32 {
        switch self {
        case .TI89T: 2
        case .TI89: 1
        case .TI84PLUS_SE: 6
        case .TI84PLUS: 7
        case .TI83PLUS_SE: 8
        case .TI83PLUS: 9
        case .TI83: 10
        }
    }

    var label: String {
        switch self {
        case .TI89T: "TI-89 Titanium"
        case .TI89: "TI-89"
        case .TI84PLUS_SE: "TI-84 Plus SE"
        case .TI84PLUS: "TI-84 Plus"
        case .TI83PLUS_SE: "TI-83 Plus SE"
        case .TI83PLUS: "TI-83 Plus"
        case .TI83: "TI-83"
        }
    }

    var engine: Engine { self == .TI89T || self == .TI89 ? .tiemu : .tilem }

    var lcdWidth: Int { engine == .tiemu ? 160 : 96 }
    var lcdHeight: Int { engine == .tiemu ? 100 : 64 }

    var skin: String {
        switch self {
        case .TI89T: "ti89"
        case .TI89: "ti89orig"
        case .TI83: "ti83"
        default: "ti84"
        }
    }

    /// Size in bytes of a ROM dump (the calculator's flash / ROM).
    var romSize: Int64 {
        switch self {
        case .TI89T: 4 << 20
        case .TI89, .TI84PLUS_SE, .TI83PLUS_SE: 2 << 20
        case .TI84PLUS: 1 << 20
        case .TI83PLUS: 512 << 10
        case .TI83: 256 << 10
        }
    }

    /// Extension of the model's OS upgrade file; nil when there is none (a dump is required).
    var osExtension: String? {
        switch self {
        case .TI89T, .TI89: ".89u"
        case .TI83: nil
        default: ".8xu"
        }
    }

    /// File types the ROM picker accepts for this model, shown to the user.
    var romFiles: String { osExtension.map { "\($0) or .rom dump" } ?? ".rom dump" }

    /// File types the calculator takes over its link port: apps, programs and variables.
    var linkExtensions: Set<String> { engine == .tiemu ? ti89LinkFiles : ti83And84LinkFiles }
}

private let ti89LinkFiles: Set<String> = [
    ".89k", ".89z", ".89f", ".89p", ".89l", ".89g", ".89q", ".89m", ".89i", ".89c", ".89t", ".89y", ".89x",
    ".89a", ".89s", ".89e", ".89d", ".tig",
]

private let ti83And84LinkFiles: Set<String> = [
    ".8xu", ".8xk", ".8xp", ".8xn", ".8xl", ".8xm", ".8xe", ".8xs", ".8xi", ".8xw", ".8xc", ".8xz", ".8xt",
    ".8xb", ".8xv", ".8xo", ".8xg",
    ".83l", ".83m", ".83p", ".83y", ".83s", ".83i", ".83c", ".83w", ".83z", ".83t", ".83b",
]

/// One installed calculator: its own folder with image.img and the saved state.
struct CalcEntry: Equatable, Hashable, Identifiable {
    let id: String
    let model: CalcModel
}
