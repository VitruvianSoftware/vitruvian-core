// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// No test declares a type named after a system type or one of the app's own
/// top-level types (REFACTOR.md step 4). A stand-in named like the real thing
/// shadows it for every line around it, which is how tests used to fake a
/// service's collaborators; the services now take them instead.
enum TestDoubleNameContract {
    struct Declaration: Equatable {
        let name: String
        let indented: Bool
    }

    static func run(_ suite: TestSuite) {
        // The scanner and the rule, on known text: one string per line, so
        // this file's own scan finds none of it.
        let sample = declarations(in: [
            "package final class Island {",
            "    nonisolated enum DispatchQueue { static var main = 0 }",
            "    @MainActor final class Window {}",
            "    class func make() {}",
            "    private typealias Moment = Double",
            "}",
        ].joined(separator: "\n"))
        suite.expect(sample == [Declaration(name: "Island", indented: false),
                                Declaration(name: "DispatchQueue", indented: true),
                                Declaration(name: "Window", indented: true),
                                Declaration(name: "Moment", indented: true)],
                     "the scan finds nested and attributed declarations, and not class members")
        suite.expect(["NSScreen", "NSEvent", "CGSConnectionID", "DispatchQueue", "UserDefaults", "Bundle"]
                        .allSatisfy(isSystemName)
                     && !["Display", "Pointer", "Clock", "Switches", "NSome", "Bundler"].contains(where: isSystemName),
                     "system names are the framework prefixes and the Foundation types tests used to fake")

        let production = Set(files(under: "Sources").flatMap { declarations(in: $0.text) }
            .filter { !$0.indented }.map(\.name))
        let tests = files(under: "Tests")
        suite.expect(production.count > 100 && tests.count > 100, "the sources and the tests read back from the app directory")
        let shadows = tests.flatMap { file in
            declarations(in: file.text)
                .filter { production.contains($0.name) || isSystemName($0.name) }
                .map { "\(file.path): \($0.name)" }
        }
        suite.expect(shadows.isEmpty, "no test type shadows a system type or one of the app's own: \(shadows)")
    }

    static func isSystemName(_ name: String) -> Bool {
        let foundation: Set = ["UserDefaults", "NotificationCenter", "DistributedNotificationCenter", "Bundle",
                               "ProcessInfo", "FileManager", "RunLoop", "Timer", "Thread", "OperationQueue",
                               "URLSession", "Date", "URL", "Data", "Calendar", "Locale"]
        guard !foundation.contains(name) else { return true }
        return ["NS", "CG", "CF", "AX", "Dispatch"].contains { prefix in
            name.hasPrefix(prefix) && name.dropFirst(prefix.count).first?.isUppercase == true
        }
    }

    private static let keywords = ["class ", "struct ", "enum ", "actor ", "protocol ", "typealias "]
    private static let pattern = try? NSRegularExpression(
        pattern: #"^(\s*)(?:@\w+(?:\([^)]*\))?\s+)*"#
            + #"(?:(?:private|fileprivate|internal|public|package|final|nonisolated|indirect|open)\s+)*"#
            + #"(?:class|struct|enum|actor|protocol|typealias)\s+(?!func\b|var\b|let\b|subscript\b|init\b)([A-Za-z_]\w*)"#)

    static func declarations(in text: String) -> [Declaration] {
        text.components(separatedBy: "\n").compactMap { line in
            guard keywords.contains(where: { line.contains($0) }) else { return nil }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = pattern?.firstMatch(in: line, range: range),
                  let indent = Range(match.range(at: 1), in: line),
                  let name = Range(match.range(at: 2), in: line) else { return nil }
            return Declaration(name: String(line[name]), indented: !line[indent].isEmpty)
        }
    }

    private static func files(under directory: String) -> [(path: String, text: String)] {
        let paths = (FileManager.default.enumerator(atPath: directory)?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix(".swift") }.sorted()
        return paths.map { path in
            let file = directory + "/" + path
            return (file, (try? String(contentsOf: URL(fileURLWithPath: file), encoding: .utf8)) ?? "")
        }
    }
}
