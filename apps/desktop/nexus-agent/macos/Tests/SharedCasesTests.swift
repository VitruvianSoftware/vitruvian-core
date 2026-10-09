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

    // MARK: - Approval modes

    /// One row of `approval-modes.json`. A nil value is the absent key (JSON
    /// `null`).
    private struct ApprovalCase {
        let name: String
        let value: String?
        let args: [String]
    }

    private func approvalCases(line: UInt = #line) -> [ApprovalCase] {
        let cases = loadCases("approval-modes.json", line: line)
        let decoded: [ApprovalCase] = cases.compactMap { item in
            let name = item["name"] as? String ?? "(unnamed)"
            guard let args = item["args"] as? [String], let raw = item["value"],
                  raw is NSNull || raw is String else {
                XCTFail("\(name): needs a value (a string or null) and a list of args", line: line)
                return nil
            }
            return ApprovalCase(name: name, value: raw as? String, args: args)
        }
        XCTAssertEqual(decoded.count, cases.count, "every case in the file was read", line: line)
        return decoded
    }

    func testApprovalModesGiveTheFlagsTheBotPasses() {
        let cases = approvalCases()
        var checked = 0
        for item in cases {
            XCTAssertEqual(NexusAgentApprovalMode.parse(item.value).agyArguments, item.args, item.name)
            checked += 1
        }
        XCTAssertEqual(checked, cases.count, "every case in the file was checked")
        XCTAssertGreaterThan(checked, 0, "at least one case was checked")
    }

    /// Settings shows a mode the user may have spelled differently, then
    /// writes its own spelling on save. That is only safe if the bot runs agy
    /// with the same flags for the spelling written as for the one typed.
    func testSavingAnApprovalModeNeverChangesWhatTheBotWillDo() {
        let cases = approvalCases()
        var flags: [String: [String]] = [:]
        for item in cases {
            if let value = item.value { flags[value] = item.args }
        }
        var checked = 0
        for item in cases {
            guard let typed = item.value else { continue }
            let key = NexusAgentEnvFile.approvalModeKey
            let before = "\(key)=\(NexusAgentEnvFile.encoded(typed))\n"
            XCTAssertEqual(NexusAgentEnvFile.values(in: before)[key], typed,
                           "\(item.name): the line under test carries the value as typed")

            let saved = NexusAgentEnvFile.render(NexusAgentEnvFile.parse(before), over: before)
            guard let written = NexusAgentEnvFile.values(in: saved)[key] else {
                XCTFail("\(item.name): the saved file has no \(key)")
                continue
            }
            guard let after = flags[written] else {
                XCTFail("\(item.name): a save writes \"\(written)\", which the shared examples do not cover")
                continue
            }
            XCTAssertEqual(after, item.args,
                           "\(item.name): typed \"\(typed)\", saved as \"\(written)\"")
            checked += 1
        }
        XCTAssertEqual(checked, cases.filter { $0.value != nil }.count, "every case with a value was checked")
        XCTAssertGreaterThan(checked, 0, "at least one case was checked")
    }

    /// A file with no approval-mode line: the page shows the bot's default,
    /// and saving writes that default out. The bot must still run agy with
    /// the flags it ran with when the line was missing.
    func testSavingAFileWithNoApprovalModeNeverChangesWhatTheBotWillDo() {
        let cases = approvalCases()
        var flags: [String: [String]] = [:]
        var absent: [[String]] = []
        for item in cases {
            if let value = item.value { flags[value] = item.args } else { absent.append(item.args) }
        }
        XCTAssertEqual(absent.count, 1, "the shared examples have one case for the absent key")
        guard let whenAbsent = absent.first else { return }

        let key = NexusAgentEnvFile.approvalModeKey
        let before = "# nothing about approval here\nOTHER=1\n"
        XCTAssertNil(NexusAgentEnvFile.values(in: before)[key], "the file under test has no \(key) line")

        let saved = NexusAgentEnvFile.render(NexusAgentEnvFile.parse(before), over: before)
        guard let written = NexusAgentEnvFile.values(in: saved)[key] else {
            XCTFail("the saved file has no \(key)")
            return
        }
        guard let after = flags[written] else {
            XCTFail("a save writes \"\(written)\", which the shared examples do not cover")
            return
        }
        XCTAssertEqual(after, whenAbsent, "no line, saved as \"\(written)\"")
    }

    // MARK: - .env lines

    func testEnvLinesAreReadAsDotenvReadsThem() {
        let cases = loadCases("env-lines.json")
        var checked = 0
        for item in cases {
            let name = item["name"] as? String ?? "(unnamed)"
            guard let line = item["line"] as? String, let rawKey = item["key"], let rawValue = item["value"] else {
                XCTFail("\(name): needs a line, a key and a value")
                continue
            }
            let read = NexusAgentEnvFile.assignment(in: line)
            if rawKey is NSNull, rawValue is NSNull {
                XCTAssertNil(read.map { "\($0.key)=\($0.value)" }, "\(name): the line assigns nothing")
            } else if let key = rawKey as? String, let value = rawValue as? String {
                XCTAssertEqual(read?.key, key, "\(name): key")
                XCTAssertEqual(read?.value, value, "\(name): value")
            } else {
                XCTFail("\(name): key and value are both strings, or both null")
                continue
            }
            checked += 1
        }
        XCTAssertEqual(checked, cases.count, "every case in the file was checked")
        XCTAssertGreaterThan(checked, 0, "at least one case was checked")
    }

    // MARK: - .env files

    /// A whole file, not one line: where a line ends decides which keys exist.
    /// The bot's dotenv ends a line only at a line feed, a carriage return or
    /// both; the apps must not see a second line where the bot sees one.
    func testEnvFilesAreReadAsDotenvReadsThem() {
        let cases = loadCases("env-files.json")
        var checked = 0
        for item in cases {
            let name = item["name"] as? String ?? "(unnamed)"
            guard let content = item["content"] as? String, let values = item["values"] as? [String: String] else {
                XCTFail("\(name): needs a content and values, an object of strings")
                continue
            }
            XCTAssertEqual(NexusAgentEnvFile.values(in: content), values, name)
            checked += 1
        }
        XCTAssertEqual(checked, cases.count, "every case in the file was checked")
        XCTAssertGreaterThan(checked, 0, "at least one case was checked")
    }

    /// Saving rewrites the keys the page owns and leaves every other line
    /// alone, so a key the page does not own must come out of a save with the
    /// value the bot would have read before it.
    func testSavingKeepsTheOtherKeysOfEveryFileTheSame() {
        let cases = loadCases("env-files.json")
        var checked = 0
        for item in cases {
            let name = item["name"] as? String ?? "(unnamed)"
            guard let content = item["content"] as? String, let values = item["values"] as? [String: String] else {
                XCTFail("\(name): needs a content and values, an object of strings")
                continue
            }
            let saved = NexusAgentEnvFile.render(NexusAgentEnvFile.parse(content), over: content)
            let after = NexusAgentEnvFile.values(in: saved)
            for (key, value) in values where !NexusAgentEnvFile.managedKeys.contains(key) {
                XCTAssertEqual(after[key], value, "\(name): \(key) after a save")
            }
            checked += 1
        }
        XCTAssertEqual(checked, cases.count, "every case in the file was checked")
        XCTAssertGreaterThan(checked, 0, "at least one case was checked")
    }

    /// What the apps write must be what the file says they write, and must
    /// read back as the value that was meant. The bot's test checks the same
    /// lines with dotenv itself.
    func testEnvValuesAreWrittenSoTheyReadBackUnchanged() {
        let cases = loadCases("env-written-values.json")
        var checked = 0
        for item in cases {
            let name = item["name"] as? String ?? "(unnamed)"
            guard let value = item["value"] as? String, let line = item["line"] as? String else {
                XCTFail("\(name): needs a value and a line")
                continue
            }
            XCTAssertEqual(NexusAgentEnvFile.encoded(value), line, "\(name): what is written")
            let read = NexusAgentEnvFile.assignment(in: "K=\(line)")?.value
            if let lossy = item["lossy"] {
                // No spelling carries this value. The day one does, this
                // fails, and the case loses its `lossy` mark.
                XCTAssertEqual(lossy as? Bool, true, "\(name): lossy is true or left out")
                XCTAssertNotEqual(read, value, "\(name): marked lossy, but it reads back")
            } else {
                XCTAssertEqual(read, value, "\(name): what is read back")
            }
            checked += 1
        }
        XCTAssertEqual(checked, cases.count, "every case in the file was checked")
        XCTAssertGreaterThan(checked, 0, "at least one case was checked")
    }
}
