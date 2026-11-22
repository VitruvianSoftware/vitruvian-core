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

    // MARK: - How the file is written (`writePrivateFile`)

    private func mode(of path: String) -> Int? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Int(info.st_mode & 0o777)
    }

    func testAPrivateFileIsCreated0600InAFolderMade0700() throws {
        let folder = root.appendingPathComponent("made/here", isDirectory: true)
        let path = folder.appendingPathComponent("secret.json").path

        XCTAssertTrue(VitruvianCodeEngine.writePrivateFile(path, "{\"k\":\"v\"}"))

        XCTAssertEqual(mode(of: path), 0o600)
        XCTAssertEqual(mode(of: folder.path), 0o700, "the folder this call made")
        XCTAssertEqual(mode(of: root.appendingPathComponent("made").path), 0o700, "and the one above it")
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "{\"k\":\"v\"}")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: folder.path),
            ["secret.json"],
            "no temporary file is left behind"
        )
    }

    func testReplacingAFileKeepsItPrivate() throws {
        let path = root.appendingPathComponent("again/secret.json").path
        XCTAssertTrue(VitruvianCodeEngine.writePrivateFile(path, "one"))
        XCTAssertTrue(VitruvianCodeEngine.writePrivateFile(path, "two"))
        XCTAssertEqual(mode(of: path), 0o600)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "two")
    }

    /// The temporary file is opened with `O_EXCL | O_NOFOLLOW`: a symlink planted at its name is
    /// refused, and what it points at is not written through.
    func testASymlinkPlantedAtTheTemporaryNameIsRefusedNotFollowed() throws {
        let folder = root.appendingPathComponent("planted", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let victim = root.appendingPathComponent("victim.txt")
        try "untouched".write(to: victim, atomically: true, encoding: .utf8)
        let temporary = ".planted.tmp"
        try FileManager.default.createSymbolicLink(
            atPath: folder.appendingPathComponent(temporary).path,
            withDestinationPath: victim.path
        )
        let path = folder.appendingPathComponent("secret.json").path

        XCTAssertFalse(VitruvianCodeEngine.writePrivateFile(path, "SECRET", temporaryName: temporary))

        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "untouched", "nothing was written through the link")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "and nothing was put in place")
    }

    func testAFileAtTheTemporaryNameIsNotWrittenOverEither() throws {
        let folder = root.appendingPathComponent("exclusive", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let squatter = folder.appendingPathComponent(".squat.tmp")
        try "someone else's".write(to: squatter, atomically: true, encoding: .utf8)

        XCTAssertFalse(VitruvianCodeEngine.writePrivateFile(folder.appendingPathComponent("s.json").path, "SECRET", temporaryName: ".squat.tmp"))
        XCTAssertEqual(try String(contentsOf: squatter, encoding: .utf8), "someone else's")
    }

    func testASymlinkAtTheDestinationIsReplacedNotWrittenThrough() throws {
        let folder = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let victim = root.appendingPathComponent("victim2.txt")
        try "untouched".write(to: victim, atomically: true, encoding: .utf8)
        let path = folder.appendingPathComponent("secret.json").path
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: victim.path)

        XCTAssertTrue(VitruvianCodeEngine.writePrivateFile(path, "SECRET"))

        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "untouched")
        XCTAssertEqual(mode(of: path), 0o600, "now a regular file of its own")
    }

    func testStoringASecretTightensAStateFolderThatAlreadyExisted() throws {
        let store = secrets()
        let folder = (store.path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(mode(of: folder), 0o755)

        XCTAssertTrue(store.set("v", forKey: "K", provider: providerA))

        XCTAssertEqual(mode(of: folder), 0o700)
        XCTAssertEqual(mode(of: store.path), 0o600)
    }

    // MARK: - A file that cannot be trusted

    private func plantFile(_ json: String, mode: mode_t = 0o600) throws -> AgentSecrets {
        let store = secrets()
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: store.path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try json.write(toFile: store.path, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(store.path, mode), 0)
        return store
    }

    private func json(_ values: [String: String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["version": 1, "providers": [providerA.uuidString: values]])
        return String(data: data, encoding: .utf8)!
    }

    func testAFileOthersCanReadIsIgnoredAndTheReasonNamesNoValue() throws {
        for permissions: mode_t in [0o644, 0o640, 0o604, 0o660] {
            let store = try plantFile(json(["ANTHROPIC_API_KEY": "sk-leaked"]), mode: permissions)
            XCTAssertEqual(store.values(for: providerA), [:], String(permissions, radix: 8))
            let reason = try XCTUnwrap(store.problem)
            XCTAssertTrue(reason.contains(String(permissions, radix: 8)), reason)
            XCTAssertFalse(reason.contains("sk-leaked"))
            XCTAssertFalse(store.set("new", forKey: "OTHER_KEY", provider: providerA), "it is not written over")
        }
    }

    func testAFileThatIsASymlinkIsIgnored() throws {
        let store = secrets()
        let real = root.appendingPathComponent("elsewhere.json")
        try json(["ANTHROPIC_API_KEY": "sk-through-link"]).write(to: real, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(real.path, 0o600), 0)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: store.path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(atPath: store.path, withDestinationPath: real.path)

        XCTAssertEqual(store.values(for: providerA), [:])
        XCTAssertEqual(store.problem, "agent-secrets.json: it is a symbolic link")
    }

    func testAFileThatIsNotAFileIsIgnored() throws {
        let store = secrets()
        try FileManager.default.createDirectory(atPath: store.path, withIntermediateDirectories: true)
        XCTAssertEqual(store.values(for: providerA), [:])
        XCTAssertEqual(store.problem, "agent-secrets.json: it is not a regular file")
    }

    func testAGoodFileHasNoProblem() throws {
        let store = try plantFile(json(["ANTHROPIC_API_KEY": "sk-ok"]))
        XCTAssertNil(store.problem)
        XCTAssertEqual(store.values(for: providerA), ["ANTHROPIC_API_KEY": "sk-ok"])
        XCTAssertNil(secrets().problem, "and a file that is not there yet has none")
    }

    // MARK: - Names that change how a process starts

    func testNamesThatChangeHowAProcessStartsAreRefusedWhenStored() {
        let store = secrets()
        for key in ["PATH", "HOME", "NODE_OPTIONS", "NODE_PATH", "CLAUDE_CODE_EXECPATH",
                    "DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "LD_PRELOAD", "LD_LIBRARY_PATH"] {
            XCTAssertFalse(store.set("x", forKey: key, provider: providerA), key)
            XCTAssertTrue(AgentSecrets.isDeniedKey(key), key)
        }
        XCTAssertEqual(store.keys(for: providerA), [])
        // Close-looking names that do not change how anything starts are fine.
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL", "NODE_EXTRA_CA_CERTS", "MYPATH", "HOMEBREW_TOKEN", "GOLD_KEY", "path"] {
            XCTAssertFalse(AgentSecrets.isDeniedKey(key), key)
        }
        XCTAssertTrue(store.set("x", forKey: "NODE_EXTRA_CA_CERTS", provider: providerA))
    }

    func testNamesThatChangeHowAProcessStartsAreDroppedWhenRead() throws {
        let store = try plantFile(json([
            "ANTHROPIC_API_KEY": "sk-ok",
            "NODE_OPTIONS": "--require=/tmp/evil.js",
            "PATH": "/tmp/evil",
            "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib",
            "LD_PRELOAD": "/tmp/evil.so",
            "HOME": "/tmp/evil",
            "NODE_PATH": "/tmp/evil",
            "CLAUDE_CODE_EXECPATH": "/tmp/evil",
        ]))
        XCTAssertEqual(store.values(for: providerA), ["ANTHROPIC_API_KEY": "sk-ok"])
        XCTAssertEqual(store.keys(for: providerA), ["ANTHROPIC_API_KEY"])
    }
}
