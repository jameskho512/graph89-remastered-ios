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

/// A component in the app, with the licence it is used under (a text file in assets/licenses).
private struct Component: Identifiable {
    let name: String
    let authors: String
    let license: String
    let file: String
    var id: String { name }
}

private let components = [
    Component(name: "Graph89", authors: "Copyright (C) 2012-2013 Dritan Hashorva", license: "GNU GPL version 3", file: "GPL-3.0.txt"),
    Component(name: "TilEm 2.0 (TI-83 and TI-84 emulation)", authors: "Copyright (C) 2009-2012 Benjamin Moody", license: "GNU GPL version 3", file: "GPL-3.0.txt"),
    Component(
        name: "TiEmu 3.03 (TI-89 emulation)",
        authors: "Copyright (C) 2000-2006 Thomas Corvazier, Romain Liévin, Julien Blache, Kevin Kofler",
        license: "GNU GPL version 2 or later", file: "GPL-2.0.txt"
    ),
    Component(
        name: "libticalcs2, libtifiles2, libticables2, libticonv",
        authors: "Copyright (C) 1999-2006 Romain Liévin, Kevin Kofler",
        license: "GNU GPL version 2 or later", file: "GPL-2.0.txt"
    ),
    Component(name: "GLib", authors: "Copyright (C) The GLib team", license: "GNU LGPL version 2 or later", file: "LGPL-2.0.txt"),
    Component(name: "Roboto (key labels in the skins)", authors: "Copyright (C) Google", license: "Apache License 2.0", file: "Apache-2.0.txt"),
    Component(name: "Noto Sans Symbols (symbols in the skins)", authors: "Copyright (C) Google", license: "SIL Open Font License 1.1", file: "OFL-1.1.txt"),
]

/// Version, the source code link, the TI disclaimer and the licences of everything in the app (GPL notices).
struct AboutView: View {
    @State private var shown: Component?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var sourceUrl: String {
        Bundle.main.object(forInfoDictionaryKey: "G89SourceURL") as? String ?? ""
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Graph89 Remastered \(version)").font(.title3.weight(.semibold))
                    Text("Based on Graph89 by Dritan Hashorva. This app is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License version 3. It comes with ABSOLUTELY NO WARRANTY.")
                    Text("Not affiliated with or endorsed by Texas Instruments. TI-83, TI-84 Plus, TI-89 and TI-89 Titanium are trademarks of Texas Instruments. The app does not include any Texas Instruments software: you supply the OS or ROM of your own calculator.")
                }
                .padding(.vertical, 4)
            }
            if let url = URL(string: sourceUrl), !sourceUrl.isEmpty {
                Section {
                    Link(destination: url) {
                        LabeledRow(title: "Source code", detail: sourceUrl)
                    }
                    .textSelection(.enabled)
                }
            }
            Section("Licences") {
                ForEach(components) { c in
                    Button { shown = c } label: {
                        LabeledRow(title: c.name, detail: "\(c.authors)\n\(c.license)")
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shown) { c in
            NavigationStack {
                ScrollView {
                    Text(licenceText(c))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(c.license)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Close") { shown = nil } }
                }
            }
        }
    }

    private func licenceText(_ c: Component) -> String {
        (try? String(contentsOf: Assets.url("licenses/\(c.file)"), encoding: .utf8)) ?? "The licence text did not load."
    }
}
