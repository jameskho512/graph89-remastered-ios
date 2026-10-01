/*
 * Graph89 Remastered - TI graphing calculator emulator for iPhone
 * Copyright (C) 2026 JH
 *
 * This program is free software: you can redistribute it and/or modify it under the terms of the
 * GNU General Public License as published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version. This program is distributed in the hope that it
 * will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License (LICENSE) for more details.
 */

import XCTest

/// Goes through the app's screens as a user would and keeps a screenshot of each (as test attachments, and as PNGs in
/// G89_OUTPUT_DIR/screens when CI sets it). The calculator runs PedroM from G89_TEST_OS_DIR.
final class ScreenshotTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment

    override func setUp() {
        continueAfterFailure = false
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = env["G89_OUTPUT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("screens", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url.appendingPathComponent("\(name).png"))
        }
    }

    private func testOS(_ name: String) throws -> String {
        guard let dir = env["G89_TEST_OS_DIR"], !dir.isEmpty else { throw XCTSkip("G89_TEST_OS_DIR is not set") }
        let path = URL(fileURLWithPath: dir).appendingPathComponent(name).path
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("\(name) is missing") }
        return path
    }

    /// The app on a fresh install, with `rom` installed for `model` at its first start.
    private func launch(rom: String? = nil, model: String = "TI89T", arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["G89_RESET"] = "1"
        if let rom {
            app.launchEnvironment["G89_INSTALL_ROM"] = rom
            app.launchEnvironment["G89_INSTALL_MODEL"] = model
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    func testFirstRun() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Graph89 Remastered"].waitForExistence(timeout: 15))
        snap("01-first-run")
        app.buttons["addCalculator"].tap()
        XCTAssertTrue(app.buttons["TI-89 Titanium (.89u or .rom dump)"].waitForExistence(timeout: 5))
        snap("02-add-calculator")
    }

    func testTour() throws {
        let app = launch(rom: try testOS("PedroM-89ti.89u"))
        let calculator = app.otherElements["calculator"]
        XCTAssertTrue(calculator.waitForExistence(timeout: 60))
        sleep(10)  // PedroM boots
        snap("03-calculator")

        // a key press on the keypad: CLEAR (right column, fifth row of the TI-89 layout)
        calculator.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.62)).tap()
        sleep(2)
        snap("04-after-key")

        app.buttons["menuButton"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        snap("05-menu")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        snap("06-settings")

        app.staticTexts["Skin and LCD"].tap()
        XCTAssertTrue(app.navigationBars["Skin and LCD"].waitForExistence(timeout: 10))
        sleep(4)  // previews draw
        snap("07-skin-picker")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.staticTexts["Calculators"].tap()
        XCTAssertTrue(app.navigationBars["Calculators"].waitForExistence(timeout: 10))
        snap("08-calculators")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.swipeUp()
        app.staticTexts["About Graph89 Remastered"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 10))
        snap("09-about")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["settingsDone"].tap()
        XCTAssertTrue(calculator.waitForExistence(timeout: 10))
        sleep(4)
        snap("10-calculator-again")
    }

    /// The same calculator in other skins and LCD schemes (set through launch arguments, which UserDefaults reads).
    func testSkins() throws {
        let rom = try testOS("PedroM-89ti.89u")
        for (i, look) in [("MIDNIGHT", "MIDNIGHT", "NO"), ("NEON_GRID", "NEON_GRID", "YES"), ("ROYAL", "ROYAL", "YES")].enumerated() {
            let app = launch(rom: rom, arguments: ["-skin", look.0, "-lcd_theme", look.1, "-skin_3d", look.2])
            XCTAssertTrue(app.otherElements["calculator"].waitForExistence(timeout: 60))
            sleep(8)
            snap("2\(i)-skin-\(look.0.lowercased())\(look.2 == "YES" ? "-3d" : "")")
            app.terminate()
        }
    }

    /// A TI-84 Plus running the KnightOS kernel.
    func testTi84() throws {
        let app = launch(rom: try testOS("kernel-TI84p.rom"), model: "TI84PLUS")
        XCTAssertTrue(app.otherElements["calculator"].waitForExistence(timeout: 60))
        sleep(8)
        snap("30-ti84-plus")
    }
}
