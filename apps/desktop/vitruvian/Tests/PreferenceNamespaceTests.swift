// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Every defaults suite a test opens leaves a plist in the account's real
/// ~/Library/Preferences, and only the sweep that runs after the tests
/// (`discard_test_preferences` in build.sh, which bazel/run_unit_tests.sh
/// runs) takes it away again. The suites are found in the test code, a lint
/// over Tests/ like `TestRegistrationContract`, and the sweep itself then runs
/// over a scratch folder holding a plist for each of them: a suite outside the
/// swept namespaces fails here instead of leaving its file behind on every run.
enum PreferenceNamespaceTests {
    static func run(_ suite: TestSuite) {
        // Everything Bazel compiles into the tests from Tests/ is under it
        // (Tests/*.swift and Tests/SwiftTesting/*.swift), so the scan
        // covers every suite the test binary can open.
        let paths = ((try? FileManager.default.subpathsOfDirectory(atPath: "Tests")) ?? [])
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        suite.expect(!paths.isEmpty, "the preference namespace guard discovers Swift test files")

        var declarations: [(path: String, name: String?)] = []
        for path in paths {
            let source = (try? String(contentsOf: URL(fileURLWithPath: "Tests/" + path), encoding: .utf8)) ?? ""
            suite.expect(!source.isEmpty, "Tests/\(path) reads for preference namespace checks")
            declarations += suiteNames(in: source).map { (path: path, name: $0) }
        }
        suite.expect(!declarations.isEmpty,
                     "the preference namespace guard discovers suite declarations")

        let constructor = "UserDefaults(suiteName" + ": "
        suite.expect(suiteNames(in: constructor + #""vitru.tests.literal")"#)
                         == ["vitru.tests.literal"],
                     "literal preference suite names are recognized")
        suite.expect(suiteNames(in: #"let name = "com.vitruviansoftware.vitruvian.tests.local""# + "\n"
                         + constructor + "name)") == ["com.vitruviansoftware.vitruvian.tests.local"],
                     "locally declared literal preference suite names are resolved")
        let reusedName = #"let name = "vitru.tests.first""# + "\n"
            + constructor + "name)\n"
            + #"let name = "unsafe.temporary""# + "\n"
            + constructor + "name)"
        let reusedNames = suiteNames(in: reusedName)
        suite.expect(reusedNames == ["vitru.tests.first", "unsafe.temporary"],
                     "reused local preference suite names resolve at each call")
        suite.expect(suiteNames(in: constructor + "computedName())") == [nil],
                     "computed preference suite names fail closed")

        // The app's own preferences stand beside the test suites in the
        // scratch folder, as they do in the real one, and must survive.
        let appDomain = "com.vitruviansoftware.vitruvian"
        let samples = Set(reusedNames.compactMap { $0 })
        let declared = Set(declarations.compactMap { $0.name })
        guard let left = survivorsOfSweep(declared.union(samples).union([appDomain])) else {
            suite.expect(false, "the preference sweep runs over a scratch preferences folder")
            return
        }
        for (path, name) in declarations {
            // A computed name cannot be put to the sweep, so it fails.
            suite.expect(name.map { !left.contains($0) } ?? false,
                         "defaults suite \(name ?? "<unresolved>") in Tests/\(path) is swept")
        }
        suite.expect(!left.contains("vitru.tests.first") && left.contains("unsafe.temporary"),
                     "a temporary unswept preference namespace fails the guard")
        suite.expect(left.contains(appDomain), "the preference sweep never takes the app's own preferences")
    }

    /// Runs the sweep that follows every test run over a scratch preferences
    /// folder holding a plist for each name, and returns the names whose plist
    /// it left behind (a name that cannot be a file name counts as left), or
    /// nil when the sweep did not run to the end.
    private static func survivorsOfSweep(_ names: Set<String>) -> Set<String>? {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("vitru-preference-sweep-\(UUID().uuidString)")
        guard (try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        defer { try? fileManager.removeItem(at: folder) }
        func plist(_ name: String) -> String { folder.appendingPathComponent(name + ".plist").path }
        var unstaged: Set<String> = []
        for name in names {
            if name.contains("/") || !fileManager.createFile(atPath: plist(name), contents: Data("{}".utf8)) {
                unstaged.insert(name)
            }
        }
        let sweep = BoundedProcessRunner.run(
            "/bin/zsh",
            ["-c", #"source <(sed -n '/^discard_test_preferences() {$/,/^}$/p' build.sh) && discard_test_preferences "$1""#,
             "zsh", folder.path],
            timeout: 30, maxOutputBytes: 4_096)
        guard sweep.status == 0, !sweep.timedOut else { return nil }
        return unstaged.union(names.filter { fileManager.fileExists(atPath: plist($0)) })
    }

    private static func suiteNames(in source: String) -> [String?] {
        let calls = try! NSRegularExpression(pattern: #"\bUserDefaults\s*\(\s*suiteName\s*:\s*"#)
        let fullRange = NSRange(source.startIndex..., in: source)
        return calls.matches(in: source, range: fullRange).map { match in
            let matchRange = Range(match.range, in: source)!
            let argument = source[matchRange.upperBound...]
            if argument.first == "\"" {
                return String(argument.dropFirst().prefix { $0 != "\"" })
            }

            let variable = String(argument.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            guard !variable.isEmpty,
                  argument.dropFirst(variable.count).drop(while: \.isWhitespace).first == ")" else {
                return nil
            }
            let declarations = try! NSRegularExpression(
                pattern: #"\blet\s+"# + NSRegularExpression.escapedPattern(for: variable)
                    + #"\s*=\s*"([^"]*)""#
            )
            guard let declaration = declarations.matches(
                in: source,
                range: NSRange(source.startIndex..<matchRange.lowerBound, in: source)
            ).last,
                  let nameRange = Range(declaration.range(at: 1), in: source) else {
                return nil
            }
            return String(source[nameRange])
        }
    }
}
