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

import Foundation
import Testing
@testable import HomeSpeakerCore

/// Verifies `apps/desktop/home-speaker/testdata/controls.json` is well-formed,
/// has unique kebab-case ids, and covers every `--apply` operation in
/// `HomeSpeakerStateContract.supportedOperations`.
@Suite("Controls Manifest")
struct ControlsManifestTests {

    private struct ControlEntry: Decodable, Equatable {
        let id: String
        let label: String
        let via: String
        let phone: String
        let reason: String?
    }

    private static func manifestURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let runfiles = env["RUNFILES_DIR"] ?? env["TEST_SRCDIR"] {
            let workspace = env["TEST_WORKSPACE"] ?? "_main"
            let bazel = URL(fileURLWithPath: runfiles)
                .appendingPathComponent(workspace)
                .appendingPathComponent("apps/desktop/home-speaker/testdata/controls.json")
            if FileManager.default.fileExists(atPath: bazel.path) {
                return bazel
            }
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("testdata/controls.json")
    }

    private static func isKebabCase(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { scalar in
                ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
            }
        }
    }

    private static func isValidCLIVia(_ via: String) -> Bool {
        var tokens = via.split(separator: " ").map(String.init)
        guard let first = tokens.first, first.hasPrefix("--") else { return false }
        if first == "--say" {
            tokens.insert("hello", at: 1)
        } else if first == "--set-volume" {
            tokens.append("50")
        } else if tokens.last == "--home" {
            tokens.append("home-structure-1")
        }
        guard let parsed = HomeSpeakerCommandLine.parse(tokens) else { return false }
        switch parsed {
        case .usage, .state(.some), .apply(.failure), .app(.failure), .chatMonitor(.failure), .volume(.invalidLevel):
            return false
        default:
            return true
        }
    }

    @Test("controls.json entries are well-formed, have unique kebab-case ids, and cover every supportedOperations op")
    func manifestIsWellFormedAndCoversEverySupportedOperation() throws {
        let data = try Data(contentsOf: Self.manifestURL())
        let rawArray = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let entries = try JSONDecoder().decode([ControlEntry].self, from: data)

        #expect(!entries.isEmpty)
        #expect(rawArray.count == entries.count)

        let allowedKeys: Set<String> = ["id", "label", "via", "phone", "reason"]
        let supportedOpSet = Set(HomeSpeakerStateContract.supportedOperations)
        var seenIds = Set<String>()

        for (index, entry) in entries.enumerated() {
            let rawKeys = Set(rawArray[index].keys)
            #expect(rawKeys.isSubset(of: allowedKeys), "Unexpected keys on entry \(entry.id): \(rawKeys.subtracting(allowedKeys))")

            #expect(Self.isKebabCase(entry.id), "Control id must be kebab-case: \(entry.id)")
            #expect(seenIds.insert(entry.id).inserted, "Duplicate control id: \(entry.id)")

            #expect(!entry.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Blank label on \(entry.id)")
            #expect(entry.label == entry.label.trimmingCharacters(in: .whitespacesAndNewlines), "Untrimmed label on \(entry.id)")

            #expect(!entry.via.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Blank via on \(entry.id)")
            #expect(entry.via == entry.via.trimmingCharacters(in: .whitespacesAndNewlines), "Untrimmed via on \(entry.id)")

            #expect(entry.phone == "supported" || entry.phone == "excluded", "Invalid phone status '\(entry.phone)' on \(entry.id)")
            if entry.phone == "excluded" {
                let reason = (entry.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(!reason.isEmpty, "Excluded control \(entry.id) must declare a non-empty reason")
            } else {
                #expect(entry.reason == nil, "Supported control \(entry.id) must not carry an exclusion reason")
            }

            if entry.via.hasPrefix("--") {
                #expect(Self.isValidCLIVia(entry.via), "Unrecognized CLI flag(s) in via '\(entry.via)' on \(entry.id)")
            } else if entry.via == "extension-ui" {
                #expect(entry.phone == "excluded", "Only excluded controls may use 'extension-ui' via (\(entry.id))")
            } else if entry.via.hasPrefix("helper:") {
                // Done by the Mac helper itself (e.g. voice preview runs macOS `say`), so
                // there is no Home Speaker op to check; macagent_test checks the helper side.
                #expect(entry.via.count > "helper:".count, "Empty helper name in via on \(entry.id)")
            } else {
                #expect(supportedOpSet.contains(entry.via), "Unknown --apply op '\(entry.via)' on \(entry.id)")
            }
        }

        let manifestVias = Set(entries.map(\.via))
        let missingOps = HomeSpeakerStateContract.supportedOperations.filter { !manifestVias.contains($0) }
        #expect(
            missingOps.isEmpty,
            "HomeSpeakerStateContract.supportedOperations missing from testdata/controls.json via: \(missingOps)"
        )
    }
}
