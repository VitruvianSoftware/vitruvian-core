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
@testable import VitruvianCodeCore
import XCTest

@MainActor
final class AgentSecretsTests: XCTestCase {
    private var root: URL!
    private var suites: [(UserDefaults, String)] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-secrets-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for (defaults, name) in suites { defaults.removePersistentDomain(forName: name) }
        suites.removeAll()
        try? FileManager.default.removeItem(at: root)
    }

    private func environment(override: String? = nil) -> VitruvianCodeEngine.Environment {
        let live = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: override)
        if let override {
            suites.append((live.defaults, VitruvianCodeSupport.preferencesSuiteName(
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.vitruviansoftware.vitruvian-code",
                stateDirectory: override
            )))
        }
        return live
    }

    private func secrets() -> AgentSecrets {
        let env = environment(override: root.path)
        return AgentSecrets(environment: env)
    }

    private let providerA = UUID()
    private let providerB = UUID()

    func testTheFileIsReadableByTheUserAloneAndHoldsTheValue() throws {
        let store = secrets()
        XCTAssertTrue(store.set("sk-secret-value", forKey: "ANTHROPIC_API_KEY", provider: providerA))

        let attributes = try FileManager.default.attributesOfItem(atPath: store.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(store.values(for: providerA), ["ANTHROPIC_API_KEY": "sk-secret-value"])
    }

    func testValuesSurviveAReload() {
        XCTAssertTrue(secrets().set("one", forKey: "A_KEY", provider: providerA))
        XCTAssertTrue(secrets().set("two", forKey: "B_KEY", provider: providerA))

        let reloaded = secrets()
        XCTAssertEqual(reloaded.values(for: providerA), ["A_KEY": "one", "B_KEY": "two"])
    }

    func testStateDirMovesTheFile() {
        let moved = AgentSecrets(environment: environment(override: root.path))
        XCTAssertEqual(moved.path, root.appendingPathComponent("state/agent-secrets.json").path)
        XCTAssertTrue(moved.set("v", forKey: "K", provider: providerA))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("state/agent-secrets.json").path))

        let normal = AgentSecrets(environment: environment(override: nil))
        XCTAssertTrue(
            normal.path.hasSuffix("Library/Application Support/Vitruvian Code/agent-secrets.json"),
            "with no override the file is in the app's own state folder: \(normal.path)"
        )
        XCTAssertNotEqual(normal.path, moved.path)
    }

    func testListingGivesNamesAndNeverValues() throws {
        let store = secrets()
        XCTAssertTrue(store.set("value-one-AAAA", forKey: "B_KEY", provider: providerA))
        XCTAssertTrue(store.set("value-two-BBBB", forKey: "A_KEY", provider: providerA))

        let keys = store.keys(for: providerA)
        XCTAssertEqual(keys, ["A_KEY", "B_KEY"])
        XCTAssertFalse(keys.contains { $0.contains("value-") })
    }

    func testEachProviderHasItsOwnValues() {
        let store = secrets()
        XCTAssertTrue(store.set("a", forKey: "KEY", provider: providerA))
        XCTAssertTrue(store.set("b", forKey: "KEY", provider: providerB))

        XCTAssertEqual(store.values(for: providerA), ["KEY": "a"])
        XCTAssertEqual(store.values(for: providerB), ["KEY": "b"])
        XCTAssertEqual(store.values(for: UUID()), [:])
    }

    func testRemoveTakesOneValueOutAndLeavesTheRest() {
        let store = secrets()
        XCTAssertTrue(store.set("a", forKey: "ONE", provider: providerA))
        XCTAssertTrue(store.set("b", forKey: "TWO", provider: providerA))

        XCTAssertTrue(store.remove(key: "ONE", provider: providerA))

        XCTAssertEqual(store.keys(for: providerA), ["TWO"])
        XCTAssertTrue(store.remove(key: "NEVER_THERE", provider: providerA), "gone either way")
    }

    func testANameAnEnvironmentVariableCannotHaveIsRefused() {
        let store = secrets()
        XCTAssertFalse(store.set("v", forKey: "", provider: providerA))
        XCTAssertFalse(store.set("v", forKey: "A=B", provider: providerA))
        XCTAssertFalse(store.set("v", forKey: "A\0B", provider: providerA))
        XCTAssertEqual(store.keys(for: providerA), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path), "nothing was written")
    }

    func testAFileThatCannotBeReadIsNeverWrittenOver() throws {
        let store = secrets()
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: store.path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not json at all".write(toFile: store.path, atomically: true, encoding: .utf8)

        XCTAssertFalse(store.set("v", forKey: "K", provider: providerA))
        XCTAssertFalse(store.remove(key: "K", provider: providerA))
        XCTAssertEqual(try String(contentsOfFile: store.path, encoding: .utf8), "not json at all")
        XCTAssertEqual(store.values(for: providerA), [:])
    }

    func testTheFileIsWrittenThroughTheEnvironmentsPrivateWriter() {
        let written = ClaudeLockedBox<[(String, String)]>([])
        let store = AgentSecrets(
            stateDirectory: "/state",
            readFile: { _ in nil },
            fileExists: { _ in false },
            writePrivateFile: { path, content in
                written.update { $0.append((path, content)) }
                return true
            }
        )
        XCTAssertTrue(store.set("v", forKey: "K", provider: providerA))
        XCTAssertEqual(written.value.map(\.0), ["/state/agent-secrets.json"])
        XCTAssertTrue(written.value.first?.1.contains("\"K\"") == true)
    }
}
