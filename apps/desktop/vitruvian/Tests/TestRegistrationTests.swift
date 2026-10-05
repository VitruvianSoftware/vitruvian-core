// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Every test contract (a type with a `static func run`) is reached from
/// `TestGroups`, directly or through a contract that runs it. One that is not
/// would compile and never run (REFACTOR.md step 7).
enum TestRegistrationContract {
    static func run(_ suite: TestSuite) {
        // The scan on known text: one string per line, so this file's own
        // scan finds none of it.
        let sample = reachability(in: [
            "enum TestGroups {",
            "    static func all() { First.run(suite) }",
            "}",
            "enum First {",
            "    static func run(_ suite: TestSuite) { Second.run { _ in } }",
            "}",
            "enum Second {",
            "    nonisolated static func run(_ check: (Bool) -> Void) {}",
            "}",
            "enum Orphan {",
            "    static func run(_ suite: TestSuite) {}",
            "}",
        ].joined(separator: "\n"))
        suite.expect(sample.contracts == ["First", "Orphan", "Second"] && sample.unreached == ["Orphan"],
                     "the scan follows runs from TestGroups through contracts, and finds the one nothing runs")

        let files = ((try? FileManager.default.contentsOfDirectory(atPath: "Tests")) ?? [])
            .filter { $0.hasSuffix(".swift") }.sorted()
        let text = files.map { (try? String(contentsOf: URL(fileURLWithPath: "Tests/" + $0), encoding: .utf8)) ?? "" }
            .joined(separator: "\n")
        let found = reachability(in: text)
        suite.expect(found.contracts.count > 100, "the tests read back from the app directory")
        suite.expect(found.unreached.isEmpty, "every test contract runs from TestGroups: \(found.unreached)")
    }

    private static let topLevel = try? NSRegularExpression(
        pattern: #"^(?:(?:private|fileprivate|internal|package|public|final|nonisolated)\s+)*"#
            + #"(?:enum|struct|class|extension)\s+(\w+)"#)
    private static let runDeclaration = try? NSRegularExpression(pattern: #"^\s+(?:nonisolated\s+)?static func run\b"#)
    private static let call = try? NSRegularExpression(pattern: #"\b(\w+)\.run\s*[({]"#)

    /// The types that declare a `run`, and those of them no chain of runs from
    /// `TestGroups` reaches. A type's text runs from its top-level
    /// declaration to the next one.
    static func reachability(in text: String) -> (contracts: [String], unreached: [String]) {
        var bodies: [String: [String]] = [:]
        var contracts = Set<String>()
        var current: String?
        for line in text.components(separatedBy: "\n") {
            if let name = groups(topLevel, in: line).first { current = name }
            guard let owner = current else { continue }
            bodies[owner, default: []].append(line)
            if !groups(runDeclaration, in: line, group: 0).isEmpty { contracts.insert(owner) }
        }
        var reached = Set<String>()
        var pending = ["TestGroups"]
        while let next = pending.popLast() {
            guard reached.insert(next).inserted else { continue }
            pending += (bodies[next] ?? []).flatMap { groups(call, in: $0) }
        }
        return (contracts.sorted(), contracts.subtracting(reached).sorted())
    }

    private static func groups(_ expression: NSRegularExpression?, in line: String, group: Int = 1) -> [String] {
        let range = NSRange(line.startIndex..., in: line)
        return (expression?.matches(in: line, range: range) ?? []).compactMap { match in
            Range(match.range(at: group), in: line).map { String(line[$0]) }
        }
    }
}
