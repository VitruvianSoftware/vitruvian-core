// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import XCTest

import VitruvianToolProtocol
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

    // MARK: The mouse settings' menus

    /// The colours the app's GitHub feature offered, in its order.
    private static let colours = ["green", "cyan", "blue", "purple", "magenta", "yellow", "orange", "red", "white", "pink"]
    private static let lights = [GitHubTool.Preference.mouseSuccess, GitHubTool.Preference.mouseRunning,
                                 GitHubTool.Preference.mouseFailure, GitHubTool.Preference.mouseApproval]

    private func preference(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> ToolManifestFile.Preference? {
        let found = ToolFiles.manifest()?.preferences?.first { $0.id == id }
        XCTAssertNotNil(found, "the manifest has no preference \(id)", file: file, line: line)
        return found
    }

    private func options(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let values = preference(id, file: file, line: line)?.options?.map(\.value) ?? []
        XCTAssertFalse(values.isEmpty, "\(id) offers no options", file: file, line: line)
        return values
    }

    func testEveryOptionIsALightTheMouseCommandTakes() {
        for id in Self.lights {
            for value in options(id) {
                let light = MouseLight.parse(value)
                XCTAssertNotNil(light, "\(id): \(value)")
                XCTAssertTrue(Self.colours.contains(light?.color ?? ""), "\(id): \(value) is one of the ten colours")
                XCTAssertEqual(value, value.lowercased().trimmingCharacters(in: .whitespaces), "\(id): \(value) as it is written back")
            }
        }
        XCTAssertEqual(options(GitHubTool.Preference.mouseIdle), ["restore", "off"])
        var settings = MouseSettings()
        for (value, command) in [("restore", ["restore"]), ("off", ["off"])] {
            settings.idle = value
            XCTAssertEqual(MouseDriver.arguments(verdict: .grey, awaitingApproval: false, settings: settings), command)
        }
    }

    func testEveryDefaultIsAnOption() {
        let defaults = MouseSettings.defaults
        let expected = [GitHubTool.Preference.mouseSuccess: defaults.success, GitHubTool.Preference.mouseRunning: defaults.running,
                        GitHubTool.Preference.mouseFailure: defaults.failure, GitHubTool.Preference.mouseApproval: defaults.approval,
                        GitHubTool.Preference.mouseIdle: defaults.idle]
        for (id, value) in expected {
            XCTAssertEqual(preference(id)?.default, .string(value), "\(id)'s default is the tool's own")
            XCTAssertEqual(preference(id)?.type, "string", "\(id) is still text, so an older app draws a field")
            XCTAssertTrue(options(id).contains(value), "\(id)'s default \(value) is an option")
        }
        XCTAssertEqual(ToolFiles.manifest()?.problems(), [], "the manifest is valid with its options and its status")
        XCTAssertEqual(ToolFiles.manifest()?.contributes?.status?.placement, "island")
    }

    func testWhatTheFeatureHandedOverIsAnOption() {
        // `GitHubHandoff.light` in the app writes a colour alone, or
        // `breathe <colour>`, and the approval light with its speed, 9 unless
        // the person changed it.
        for colour in Self.colours {
            for id in [GitHubTool.Preference.mouseSuccess, GitHubTool.Preference.mouseRunning, GitHubTool.Preference.mouseFailure] {
                XCTAssertTrue(options(id).contains(colour), "\(id): \(colour)")
                XCTAssertTrue(options(id).contains("breathe \(colour)"), "\(id): breathe \(colour)")
            }
            XCTAssertTrue(options(GitHubTool.Preference.mouseApproval).contains(colour), "mouseApproval: \(colour)")
            XCTAssertTrue(options(GitHubTool.Preference.mouseApproval).contains("breathe \(colour) 9"),
                          "mouseApproval: breathe \(colour) 9")
        }
        for id in Self.lights {
            XCTAssertEqual(options(id).count, 20, id)
        }
    }

    func testTheManifestFitsWithRoom() {
        let size = ToolFiles.data("vitruvian-tool.json").count
        XCTAssertLessThan(size, ManifestLimits.maxBytes * 3 / 4,
                          "the manifest is \(size) bytes; keep a quarter of the app's limit free")
    }
}

/// The tool's own files, as the tests read them: Bazel puts them among the
/// test's runfiles; SwiftPM finds them beside the sources.
enum ToolFiles {
    static func data(_ path: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/apps/desktop/vitruvian-tool-github/\(path)")
            }
        }
        // Outside Bazel: this file is three folders below the tool's.
        var folder = URL(fileURLWithPath: "\(file)")
        for _ in 0..<3 { folder.deleteLastPathComponent() }
        candidates.append(folder.appendingPathComponent(path).path)
        for candidate in candidates {
            if let data = FileManager.default.contents(atPath: candidate) { return data }
        }
        XCTFail("\(path) is missing; looked in \(candidates)", file: file, line: line)
        return Data()
    }

    /// The manifest as the app reads it; nil, and a failure, when it does
    /// not read.
    static func manifest(file: StaticString = #filePath, line: UInt = #line) -> ToolManifestFile? {
        switch ToolManifestFile.read(data("vitruvian-tool.json", file: file, line: line)) {
        case .success(let manifest): return manifest
        case .failure(let problem):
            XCTFail("vitruvian-tool.json does not read: \(problem)", file: file, line: line)
            return nil
        }
    }
}
