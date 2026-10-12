// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import XCTest

import VitruvianToolCLI
import VitruvianToolProtocol

final class FolderCheckTests: XCTestCase {
    /// The folders the app is tested against too
    /// (`ToolFolderExamplesTests` in apps/desktop/vitruvian).
    func testEveryExampleFolderIsJudgedAsTheFileSays() throws {
        let scratch = Scratch()
        let (base, examples) = try FolderExample.all()
        XCTAssertEqual(examples.count, 22)
        var seen = Set<String>()
        for (index, example) in examples.enumerated() {
            let folder = scratch.folder("example-\(index)")
            try example.build(in: folder, base: base)
            let report = FolderCheck.check(folder, limits: example.limits)
            XCTAssertEqual(report.verdict, example.verdict, example.about)
            // A rule's name is its case's, without what the case carries.
            var rule: String?
            if case .manifest(let broken)? = report.problems.first { rule = String("\(broken)".prefix { $0 != "(" }) }
            XCTAssertEqual(rule, example.rule, "\(example.about): the rule of the manifest that is broken")
            seen.insert(example.verdict)
        }
        XCTAssertEqual(seen, ["ok", "noManifest", "manifest", "programMissing", "programOutsideFolder",
                              "programNotExecutable", "quarantined", "tooBig"],
                       "every verdict there is has an example")
    }

    func testTheLimitsAreTheApps() {
        XCTAssertEqual(FolderLimits(), FolderLimits(bytes: 268_435_456, things: 10_000))
    }

    func testEveryBrokenRuleOfAManifestIsListed() throws {
        let scratch = Scratch()
        let folder = scratch.folder("tool")
        Scratch.write(#"""
            {"id":"nodot","name":{"fr":"Outil"},"version":"1","protocol":"7","publisher":"Me",
             "uses":["camera"],"runtime":{"kind":"external","exec":"bin/tool"}}
            """#, to: folder.appendingPathComponent("vitruvian-tool.json"))
        let report = FolderCheck.check(folder)
        XCTAssertEqual(report.problems, [
            .manifest(.idWithoutDot("nodot")), .manifest(.noEnglish(field: "name")),
            .manifest(.unsupportedProtocol("7")), .manifest(.unknownService("camera")),
            .programMissing("bin/tool"),
        ], "all of them, in the order the fields are written, then the program")
        var said: [String] = []
        XCTAssertEqual(VitruvianToolCommand.main(["validate", folder.path], say: { said.append($0) }), 1)
        XCTAssertEqual(said.filter { $0.hasPrefix("NOT OK") }.count, 5)
        XCTAssertTrue(said.contains { $0.contains("the id `nodot` has no dot") })
        XCTAssertFalse(said.contains { $0.hasPrefix("ok       manifest") || $0.hasPrefix("ok       program") })
    }

    func testAPickedLinkIsFollowed() throws {
        let scratch = Scratch()
        let (base, examples) = try FolderExample.all()
        let real = scratch.folder("real")
        try examples[0].build(in: real, base: base)
        let link = scratch.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let report = FolderCheck.check(link)
        XCTAssertEqual(report.verdict, "ok")
        XCTAssertEqual(report.folder.path, real.resolvingSymlinksInPath().path)
        XCTAssertEqual(report.things, 3, "the manifest, bin and the program")
    }

    func testAProgramStartedThroughEnvGetsANote() throws {
        let scratch = Scratch()
        let (base, examples) = try FolderExample.all()
        let folder = scratch.folder("tool")
        try examples[0].build(in: folder, base: base)
        XCTAssertEqual(FolderCheck.check(folder).notes, [])
        Scratch.write("#!/usr/bin/env python3\nprint()\n", to: folder.appendingPathComponent("bin/tool"), mode: 0o755)
        let report = FolderCheck.check(folder)
        XCTAssertEqual(report.verdict, "ok", "a note refuses nothing")
        XCTAssertEqual(report.notes.count, 1)
        XCTAssertTrue(report.notes[0].contains("env python3") && report.notes[0].contains("/usr/bin:/bin"))
    }

    func testValidateSaysWhatTheAppWouldSay() throws {
        let scratch = Scratch()
        let (base, examples) = try FolderExample.all()
        let folder = scratch.folder("tool")
        try examples[0].build(in: folder, base: base)
        var said: [String] = []
        XCTAssertEqual(VitruvianToolCommand.main(["validate", folder.path], say: { said.append($0) }), 0)
        XCTAssertEqual(Array(said.prefix(3)), [
            "ok       manifest: com.example.folders 1.0.0, 0 commands",
            "ok       program: bin/tool",
            "ok       folder: 3 things, 1 KB",
        ])
        XCTAssertTrue(said.last?.contains("It cannot promise the rest") == true, "a pass says what it did not check")
        XCTAssertTrue(said.last?.contains("a folder inside its own support folder") == true,
                      "and each thing only the app refuses")

        chmod(folder.appendingPathComponent("bin/tool").path, 0o644)
        said = []
        XCTAssertEqual(VitruvianToolCommand.main(["validate", folder.path], say: { said.append($0) }), 1)
        XCTAssertTrue(said.contains { $0.hasPrefix("NOT OK   the program `bin/tool` is not a file macOS will run") })
        XCTAssertTrue(said.last?.hasPrefix("The app would refuse this folder, and say: the program") == true)
    }

    func testARelativeFolderIsReadFromWhereThePersonWas() throws {
        let scratch = Scratch()
        let (base, examples) = try FolderExample.all()
        try examples[0].build(in: scratch.folder("tool"), base: base)
        var said: [String] = []
        let status = VitruvianToolCommand.main(["validate", "tool"],
                                               environment: ["BUILD_WORKING_DIRECTORY": scratch.url.path],
                                               say: { said.append($0) })
        XCTAssertEqual(status, 0, "\(said)")
    }

    func testAnythingElseIsUsage() {
        for arguments in [[], ["validate"], ["validate", "a", "b"], ["publish", "x"]] {
            var said: [String] = []
            XCTAssertEqual(VitruvianToolCommand.main(arguments, say: { said.append($0) }), 2)
            XCTAssertTrue(said.first?.hasPrefix("vitruvian-tool:") == true)
        }
    }
}
