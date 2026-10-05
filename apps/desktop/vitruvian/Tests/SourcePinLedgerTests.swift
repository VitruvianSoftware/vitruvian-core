// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The tests that still read source files as text are counted in
/// `Tests/source_pins.txt`. This recounts them: a new source-text check has to
/// be added there in review, and one turned behavioral takes its line down, so
/// the number can only shrink on purpose (REFACTOR.md step 7).
enum SourcePinLedgerContract {
    /// Spelled in two pieces, so this file never counts itself.
    private static let needle = "contentsOf" + "File"

    static func run(_ suite: TestSuite) {
        let found = count()
        let ledger = read("Tests/source_pins.txt")
        suite.expect(!found.isEmpty && !ledger.isEmpty, "the tests and the ledger read back from the app directory")
        let keys = Set(found.keys).union(ledger.keys).sorted()
        let differences = keys.compactMap { key -> String? in
            let now = found[key] ?? 0
            let listed = ledger[key] ?? 0
            return now == listed ? nil : "\(key): \(now) read(s), ledger says \(listed)"
        }
        suite.expect(differences.isEmpty,
                     "every test that reads source as text is in Tests/source_pins.txt: \(differences)")
    }

    /// Each read's target: the first path after the call, or the test file's
    /// own name when the path is computed.
    private static func count() -> [String: Int] {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: "Tests")) ?? [])
            .filter { $0.hasSuffix(".swift") }.sorted()
        let literal = try? NSRegularExpression(pattern: needle + #":?\s*"([^"]+)""#)
        let path = try? NSRegularExpression(pattern: #""((?:Sources|Resources|bazel|Tests)/[^"]+|build\.sh)""#)
        var reads: [String: Int] = [:]
        for file in files {
            let lines = ((try? String(contentsOf: URL(fileURLWithPath: "Tests/" + file), encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                // A mention inside a string literal is not a read.
                guard let at = line.range(of: needle),
                      line[..<at.lowerBound].filter({ $0 == "\"" }).count % 2 == 0 else { continue }
                let window = lines[index..<min(lines.count, index + 3)].joined(separator: " ")
                let target = [literal, path].lazy.compactMap { firstGroup($0, in: window) }.first
                    ?? "<dynamic in \(file)>"
                reads[target, default: 0] += 1
            }
        }
        return reads
    }

    private static func firstGroup(_ expression: NSRegularExpression?, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression?.firstMatch(in: text, range: range),
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group])
    }

    private static func read(_ ledger: String) -> [String: Int] {
        let text = (try? String(contentsOf: URL(fileURLWithPath: ledger), encoding: .utf8)) ?? ""
        var counts: [String: Int] = [:]
        for line in text.components(separatedBy: "\n") where !line.isEmpty && !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard fields.count == 2, let number = Int(fields[0]) else { continue }
            counts[fields[1], default: 0] += number
        }
        return counts
    }
}
