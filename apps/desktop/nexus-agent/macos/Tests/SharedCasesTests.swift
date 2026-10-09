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

/// The examples in `apps/desktop/nexus-agent/testdata` are shared with the
/// bot's tests (`src/shared-cases.test.js`). This file runs them through the
/// shared library, so a rule changed on one side without the other following
/// fails here. Expected values live only in the JSON.
final class SharedCasesTests: XCTestCase {
    /// The cases of one shared file. A missing, unreadable or empty file fails
    /// the test: a loop over no cases would pass without checking anything.
    private func loadCases(_ file: String, line: UInt = #line) -> [[String: Any]] {
        let relative = "apps/desktop/nexus-agent/testdata/\(file)"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        // Outside Bazel (SwiftPM, Xcode): beside the sources, two folders up.
        let tests = (#filePath as NSString).deletingLastPathComponent
        let package = ((tests as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        candidates.append("\(package)/testdata/\(file)")

        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            XCTFail("shared cases file \(file) is missing; looked in \(candidates)", line: line)
            return []
        }
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cases = root["cases"] as? [[String: Any]] else {
            XCTFail("shared cases file \(path) cannot be read as { \"cases\": [ … ] }", line: line)
            return []
        }
        if cases.isEmpty {
            XCTFail("shared cases file \(path) has no cases", line: line)
        }
        return cases
    }

    func testArchiveAnnotationsAreReadAsTheBotReadsThem() {
        let cases = loadCases("archive-annotations.json")
        var checked = 0
        for item in cases {
            let name = item["name"] as? String ?? "(unnamed)"
            guard let text = item["text"] as? String, let archived = item["archived"] as? Bool else {
                XCTFail("\(name): needs a text and an archived true/false")
                continue
            }
            XCTAssertEqual(NexusAgentSessionSummary.antigravityAnnotationIsArchived(text), archived, name)
            checked += 1
        }
        XCTAssertEqual(checked, cases.count, "every case in the file was checked")
        XCTAssertGreaterThan(checked, 0, "at least one case was checked")
    }
}
