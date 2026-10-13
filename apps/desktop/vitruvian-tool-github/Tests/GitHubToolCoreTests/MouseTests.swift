// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import XCTest

@testable import GitHubToolCore

final class MouseTests: XCTestCase {
    func testLocateTriesTheConfiguredPathThenTheAppsCopyThenPATHThenTheUsualPlaces() {
        let home = "/Users/me"
        func locate(configured: String, executable: Set<String>) -> String? {
            MouseCommand.locate(configured: configured, environment: ["PATH": "/usr/bin:relative:/opt/x/bin"], home: home,
                                isExecutable: { executable.contains($0) })
        }
        XCTAssertEqual(locate(configured: "~/tools/gm", executable: ["/Users/me/tools/gm"]), "/Users/me/tools/gm")
        XCTAssertEqual(locate(configured: "", executable: [MouseCommand.appCopy]), MouseCommand.appCopy)
        XCTAssertEqual(locate(configured: "", executable: ["/opt/x/bin/gravastar-mouse"]), "/opt/x/bin/gravastar-mouse")
        XCTAssertEqual(locate(configured: "", executable: ["/Users/me/.local/bin/gravastar-mouse"]),
                       "/Users/me/.local/bin/gravastar-mouse")
        XCTAssertNil(locate(configured: "", executable: ["relative/gravastar-mouse"]), "a relative PATH entry never counts")
        XCTAssertNil(locate(configured: "/nope", executable: []))
        XCTAssertTrue(MouseCommand.configuredIsIgnored(configured: "/nope", home: home, isExecutable: { _ in false }))
        XCTAssertFalse(MouseCommand.configuredIsIgnored(configured: "", home: home, isExecutable: { _ in false }))
    }

    func testALightIsReadAsThePersonWritesIt() {
        XCTAssertEqual(MouseLight.parse("green"), MouseLight(color: "green"))
        XCTAssertEqual(MouseLight.parse(" Breathe Orange "), MouseLight(color: "orange", breathes: true))
        XCTAssertEqual(MouseLight.parse("breathe blue 9"), MouseLight(color: "blue", breathes: true, speed: 9))
        XCTAssertEqual(MouseLight.parse("breathe blue 40")?.speed, 9, "the speed is held to 0 to 9")
        XCTAssertNil(MouseLight.parse(""))
        XCTAssertNil(MouseLight.parse("blue 9"), "a solid colour has no speed")
        XCTAssertNil(MouseLight.parse("breathe blue fast"))
        XCTAssertEqual(MouseLight.parse("breathe blue 3")?.arguments, ["breathe", "blue", "--speed", "3"])
        XCTAssertEqual(MouseLight.parse("cyan")?.arguments, ["color", "cyan"])
    }

    func testTheCommandsForEachVerdictAreTheFeatures() {
        var settings = MouseSettings()
        XCTAssertEqual(MouseDriver.arguments(verdict: .green, awaitingApproval: false, settings: settings), ["color", "green"])
        XCTAssertEqual(MouseDriver.arguments(verdict: .amber, awaitingApproval: false, settings: settings), ["breathe", "orange"])
        XCTAssertEqual(MouseDriver.arguments(verdict: .red, awaitingApproval: false, settings: settings), ["breathe", "red"])
        XCTAssertEqual(MouseDriver.arguments(verdict: .grey, awaitingApproval: false, settings: settings), ["restore"])
        settings.idle = " Off "
        XCTAssertEqual(MouseDriver.arguments(verdict: .grey, awaitingApproval: false, settings: settings), ["off"])
        XCTAssertEqual(MouseDriver.arguments(verdict: .red, awaitingApproval: true, settings: settings),
                       ["breathe", "blue", "--speed", "9"], "approval outranks red")
        settings.approval = "breathe purple"
        XCTAssertEqual(MouseDriver.arguments(verdict: .green, awaitingApproval: true, settings: settings), ["breathe", "purple"])
        settings.success = "not a light at all"
        XCTAssertEqual(MouseDriver.arguments(verdict: .green, awaitingApproval: false, settings: settings), ["color", "green"],
                       "a setting that is no light falls back to its default")
    }

    func testARepeatedStateWritesNothingUnlessForcedAndRestoreForgets() {
        var sent: [[String]] = []
        let driver = MouseDriver { sent.append($0) }
        let settings = MouseSettings()
        driver.update(verdict: .green, settings: settings)
        driver.update(verdict: .green, settings: settings)
        XCTAssertEqual(sent, [["color", "green"]])
        driver.update(verdict: .green, settings: settings, force: true)
        XCTAssertEqual(sent.count, 2, "the first snapshot after a start writes again: the mouse keeps its last light")
        driver.update(verdict: .red, awaitingApproval: true, settings: settings)
        driver.update(verdict: .amber, awaitingApproval: true, settings: settings)
        XCTAssertEqual(sent.count, 3, "a verdict that moves behind a wait writes nothing")
        driver.update(verdict: .amber, settings: settings)
        XCTAssertEqual(sent.last, ["breathe", "orange"], "when the wait clears, the verdict is written")
        driver.restore()
        XCTAssertEqual(sent.last, ["restore"])
        driver.update(verdict: .amber, settings: settings)
        XCTAssertEqual(sent.count, 6, "after a restore the same verdict is written again")
    }
}
