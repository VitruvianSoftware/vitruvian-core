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

import NexusAgentCore

final class ArchiveRuleTests: XCTestCase {
    private typealias Layout = NexusAgentSessionSummary

    // Which annotation text counts as archived is checked in SharedCasesTests,
    // from the examples the bot's tests also read
    // (apps/desktop/nexus-agent/testdata/archive-annotations.json).

    func testArchivedIDsAcrossDataDirectories() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("agy-annotations-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent(".gemini/antigravity/annotations")
        let cli = home.appendingPathComponent(".gemini/antigravity-cli/annotations")
        for directory in [app, cli] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "archived:true".write(to: app.appendingPathComponent("a.pbtxt"), atomically: true, encoding: .utf8)
        try "pinned:true".write(to: app.appendingPathComponent("b.pbtxt"), atomically: true, encoding: .utf8)
        try "archived: true".write(to: cli.appendingPathComponent("c.pbtxt"), atomically: true, encoding: .utf8)
        try "archived:true".write(to: cli.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        XCTAssertEqual(Layout.antigravityArchivedSessionIds(home: home.path), ["a", "c"])
        XCTAssertEqual(Layout.antigravityArchivedSessionIds(home: home.appendingPathComponent("missing").path), [])
    }
}
