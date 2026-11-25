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

import CryptoKit
import Foundation
@testable import VitruvianCodeCore
import XCTest

/// Installing agents from the ACP registry (`ACPRegistry`, design step 5e). The network and
/// npm/uv are fakes; archives are real ones made with the Mac's `tar` and unpacked by it.
final class ACPRegistryTests: XCTestCase {
    private var scratch: String!

    override func setUpWithError() throws {
        scratch = (NSTemporaryDirectory() as NSString).appendingPathComponent("acp-registry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: scratch)
    }

    // MARK: Fakes

    /// Counts what the installer asked of the Mac, so a test can prove that reading never installs.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _downloads: [URL] = []
        private var _runs: [(String, [String], [String: String])] = []
        private var _fetches = 0
        var downloads: [URL] { lock.lock(); defer { lock.unlock() }; return _downloads }
        var runs: [(String, [String], [String: String])] { lock.lock(); defer { lock.unlock() }; return _runs }
        var fetches: Int { lock.lock(); defer { lock.unlock() }; return _fetches }
        func download(_ url: URL) { lock.lock(); _downloads.append(url); lock.unlock() }
        func run(_ exe: String, _ args: [String], _ env: [String: String]) { lock.lock(); _runs.append((exe, args, env)); lock.unlock() }
        func fetch() { lock.lock(); _fetches += 1; lock.unlock() }
        /// Runs the installer asked for other than the Mac's own `tar`.
        var packageManagerRuns: [(String, [String], [String: String])] { runs.filter { $0.0 != "/usr/bin/tar" } }
    }

    private func host(
        calls: Calls,
        index: Data? = nil,
        archive: String? = nil,
        programs: [String: String] = [:],
        packageManager: (@Sendable (String, [String], [String: String]) throws -> ACPRegistryHost.CommandResult)? = nil
    ) -> ACPRegistryHost {
        ACPRegistryHost(
            fetch: { _, _, _ in
                calls.fetch()
                guard let index else { throw URLError(.notConnectedToInternet) }
                return index
            },
            download: { url, destination, _, _ in
                calls.download(url)
                guard let archive else { throw URLError(.notConnectedToInternet) }
                try FileManager.default.copyItem(atPath: archive, toPath: destination)
                let data = try Data(contentsOf: URL(fileURLWithPath: destination))
                return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            },
            run: { exe, args, env, timeout, maxStdout in
                calls.run(exe, args, env)
                if exe == "/usr/bin/tar" { return try await ACPRegistryLive.run(exe, args, env, timeout, maxStdout) }
                guard let packageManager else { return .init(status: 127, stdout: "", stderr: "no fake") }
                return try packageManager(exe, args, env)
            },
            findProgram: { name, _ in programs[name] }
        )
    }

    private func installer(_ host: ACPRegistryHost, platform: String? = "darwin-aarch64") -> ACPRegistryInstaller {
        ACPRegistryInstaller(stateDirectory: (scratch as NSString).appendingPathComponent("state"), host: host,
                             environment: ["PATH": "/usr/bin:/bin", "HOME": scratch], platformTarget: platform)
    }

    private func sha256(ofFile path: String) throws -> String {
        SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map { String(format: "%02x", $0) }.joined()
    }

    /// Runs the Mac's `tar` to build a test archive, so the installer unpacks a real one.
    private func tar(_ arguments: [String], in directory: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "tar \(arguments)")
    }

    /// A `.tar.gz` holding an executable `opencode` script, and its SHA-256.
    private func opencodeArchive(extraArguments: [String] = [], prepare: ((String) throws -> Void)? = nil) throws -> (path: String, sha: String) {
        let source = (scratch as NSString).appendingPathComponent("src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: source, withIntermediateDirectories: true)
        if let prepare {
            try prepare(source)
        } else {
            let script = (source as NSString).appendingPathComponent("opencode")
            try "#!/bin/sh\necho opencode\n".write(toFile: script, atomically: true, encoding: .utf8)
            chmod(script, 0o755)
        }
        let archive = (scratch as NSString).appendingPathComponent("opencode-\(UUID().uuidString).tar.gz")
        let entries = try FileManager.default.contentsOfDirectory(atPath: source)
        try tar(["-czf", archive] + extraArguments + entries, in: source)
        return (archive, try sha256(ofFile: archive))
    }

    private func binaryAgent(sha: String?, cmd: String = "./opencode", archive: String = "https://example.test/opencode-darwin-arm64.tar.gz") -> ACPRegistry.Agent {
        ACPRegistry.Agent(
            id: "opencode", name: "OpenCode", version: "2.4.1", description: "The open source coding agent",
            authors: [], license: "MIT", website: nil, repository: nil, icon: nil,
            distribution: .init(binary: ["darwin-aarch64": .init(archive: archive, cmd: cmd, sha256: sha, args: ["acp"], env: [:])],
                                npx: nil, uvx: nil))
    }

    private func packageAgent(npx: String? = nil, uvx: String? = nil, id: String = "demo") -> ACPRegistry.Agent {
        ACPRegistry.Agent(
            id: id, name: "Demo", version: "1.2.3", description: "", authors: [], license: nil, website: nil,
            repository: nil, icon: nil,
            distribution: .init(binary: [:],
                                npx: npx.map { .init(package: $0, args: ["--acp"], env: ["DEMO_MODE": "acp"]) },
                                uvx: uvx.map { .init(package: $0, args: ["acp"], env: [:]) }))
    }

    private func fixture(_ name: String) throws -> Data {
        let relative = "apps/desktop/vitruvian-code/testdata/acp/\(name)"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let testsDir = (#filePath as NSString).deletingLastPathComponent
        let appRoot = ((testsDir as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        candidates.append("\(appRoot)/testdata/acp/\(name)")
        let path = try XCTUnwrap(candidates.first { FileManager.default.fileExists(atPath: $0) }, "missing \(name)")
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    // MARK: The index

    /// Every entry in the real registry, recorded on 2026-11-24, passes the checks: the parser
    /// does not drop agents the user should be able to pick.
    func testRecordedRegistryParsesWithNothingDropped() throws {
        let index = try ACPRegistry.parseIndex(try fixture("registry-index-2026-11-24.json"))
        XCTAssertEqual(index.agents.count, 46)
        XCTAssertEqual(index.discarded, 0)
        let opencode = try XCTUnwrap(index.agents.first { $0.id == "opencode" })
        XCTAssertEqual(opencode.version, "2.4.1")
        let mac = try XCTUnwrap(opencode.distribution.binary["darwin-aarch64"])
        XCTAssertEqual(mac.cmd, "./opencode")
        XCTAssertEqual(mac.args, ["acp"])
        XCTAssertEqual(mac.sha256?.count, 64)
        let claude = try XCTUnwrap(index.agents.first { $0.id == "claude-acp" })
        XCTAssertEqual(ACPRegistry.resolveDistribution(claude, platformTarget: "darwin-aarch64")?.kind, .binary)
    }

    /// An entry that fails one of T3 Code's checks is dropped and counted; the rest are kept.
    func testUnsafeEntriesAreDropped() throws {
        let json = """
        {"version": "1.0.0", "agents": [
          {"id": "good", "name": "Good", "version": "1.0.0", "description": "",
           "distribution": {"npx": {"package": "@scope/good-acp@1.0.0"}}},
          {"id": "good-bin", "name": "Good Bin", "version": "2.0.0+build.1", "description": "",
           "distribution": {"binary": {"darwin-aarch64": {"archive": "https://example.test/a.zip", "cmd": "./a",
             "sha256": "\(String(repeating: "a", count: 64))"}}}},
          {"id": "floating", "name": "Floating", "version": "1.0.0", "description": "",
           "distribution": {"npx": {"package": "floating@latest"}}},
          {"id": "plain-http", "name": "HTTP", "version": "1.0.0", "description": "",
           "distribution": {"binary": {"darwin-aarch64": {"archive": "http://example.test/a.zip", "cmd": "a"}}}},
          {"id": "creds", "name": "Creds", "version": "1.0.0", "description": "",
           "distribution": {"binary": {"darwin-aarch64": {"archive": "https://user:pw@example.test/a.zip", "cmd": "a"}}}},
          {"id": "Bad ID", "name": "Bad", "version": "1.0.0", "description": "", "distribution": {}},
          {"id": "dots", "name": "Dots", "version": "..", "description": "", "distribution": {}},
          {"id": "bad-sha", "name": "Bad sha", "version": "1.0.0", "description": "",
           "distribution": {"binary": {"darwin-aarch64": {"archive": "https://example.test/a.zip", "cmd": "a", "sha256": "xyz"}}}},
          {"id": "uv-range", "name": "Range", "version": "1.0.0", "description": "",
           "distribution": {"uvx": {"package": "tool>=1.0"}}}
        ]}
        """
        let index = try ACPRegistry.parseIndex(Data(json.utf8))
        XCTAssertEqual(index.agents.map(\.id), ["good", "good-bin"])
        XCTAssertEqual(index.discarded, 7)
    }

    func testBadEnvelopeIsRefused() {
        XCTAssertThrowsError(try ACPRegistry.parseIndex(Data("not json".utf8))) {
            XCTAssertEqual(($0 as? ACPRegistryError)?.reason, .registryUnavailable)
        }
        let tooMany = "{\"version\":\"1.0.0\",\"agents\":[" + Array(repeating: "{}", count: 513).joined(separator: ",") + "]}"
        XCTAssertThrowsError(try ACPRegistry.parseIndex(Data(tooMany.utf8)))
        let tooBig = Data(count: ACPRegistry.maxIndexBytes + 1)
        XCTAssertThrowsError(try ACPRegistry.parseIndex(tooBig))
    }

    func testDistributionOrderIsBinaryThenNpxThenUvx() {
        var agent = packageAgent(npx: "demo@1.2.3", uvx: "demo==1.2.3")
        XCTAssertEqual(ACPRegistry.resolveDistribution(agent, platformTarget: "darwin-aarch64")?.kind, .npx)
        XCTAssertEqual(ACPRegistry.resolveDistribution(agent, preference: .uvx, platformTarget: "darwin-aarch64")?.kind, .uvx)
        agent.distribution.binary["darwin-x86_64"] = .init(archive: "https://example.test/a", cmd: "a", sha256: nil, args: [], env: [:])
        XCTAssertEqual(ACPRegistry.resolveDistribution(agent, platformTarget: "darwin-x86_64")?.kind, .binary)
        // An Apple-silicon Mac does not take the Intel build.
        XCTAssertEqual(ACPRegistry.resolveDistribution(agent, platformTarget: "darwin-aarch64")?.kind, .npx)
        XCTAssertNil(ACPRegistry.resolveDistribution(agent, preference: .binary, platformTarget: "darwin-aarch64"))
        XCTAssertEqual(ACPRegistry.platformTarget(architecture: "arm64"), "darwin-aarch64")
        XCTAssertEqual(ACPRegistry.platformTarget(architecture: "x86_64"), "darwin-x86_64")
    }

    func testPathsThatLeaveTheFolderAreRefused() {
        XCTAssertEqual(ACPRegistry.commandSegments("./opencode"), ["opencode"])
        XCTAssertEqual(ACPRegistry.commandSegments("bin/agent"), ["bin", "agent"])
        for unsafe in ["/usr/bin/agent", "../agent", "bin/../../agent", "./", "C:/agent", ".."] {
            XCTAssertNil(ACPRegistry.commandSegments(unsafe), unsafe)
        }
        XCTAssertTrue(ACPRegistry.archiveEntriesAreSafe("./\nopencode\nbin/tool\n"))
        XCTAssertFalse(ACPRegistry.archiveEntriesAreSafe("opencode\n../evil\n"))
        XCTAssertFalse(ACPRegistry.archiveEntriesAreSafe("/etc/evil\n"))
        XCTAssertEqual(ACPRegistry.versionFolderName("2.0.0+build.1"), "2.0.0%2Bbuild.1")
        XCTAssertEqual(ACPRegistry.archiveKind("https://x.test/a.tar.gz?x=1"), .tarGz)
        XCTAssertEqual(ACPRegistry.archiveKind("https://x.test/a.zip"), .zip)
        XCTAssertEqual(ACPRegistry.archiveKind("https://x.test/agent"), .raw)
    }

    // MARK: Binary installs

    func testBinaryInstallsAtItsExactVersionAndIsReused() async throws {
        let archive = try opencodeArchive()
        let calls = Calls()
        let registry = installer(host(calls: calls, archive: archive.path))
        let agent = binaryAgent(sha: archive.sha)

        let install = try await registry.install(agent)
        XCTAssertEqual(install.distribution, .binary)
        XCTAssertEqual(install.version, "2.4.1")
        XCTAssertTrue(install.executablePath.hasSuffix("/state/agents/opencode/2.4.1/darwin-aarch64/opencode"), install.executablePath)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: install.executablePath))
        XCTAssertEqual(install.arguments, ["acp"])

        let again = try await registry.install(agent)
        XCTAssertEqual(again, install)
        XCTAssertEqual(calls.downloads.count, 1, "a second add reuses the copy already installed")
        let found = await registry.installed(agentID: "opencode", version: "2.4.1")
        XCTAssertEqual(found, install)
        let none = await registry.installed(agentID: "opencode", version: "2.4.2")
        XCTAssertNil(none, "another version is not this one")

        let launch = ACPRegistryInstaller.launchSpec(for: install, workingDirectory: "/work", baseEnvironment: ["PATH": "/usr/bin"])
        XCTAssertEqual(launch.executable, install.executablePath)
        XCTAssertEqual(launch.arguments, ["acp"])
        XCTAssertEqual(launch.workingDirectory, "/work")
    }

    func testChecksumMismatchInstallsNothing() async throws {
        let archive = try opencodeArchive()
        let calls = Calls()
        let registry = installer(host(calls: calls, archive: archive.path))
        do {
            _ = try await registry.install(binaryAgent(sha: String(repeating: "0", count: 64)))
            XCTFail("a download that does not match its SHA-256 must not install")
        } catch let error as ACPRegistryError {
            XCTAssertEqual(error.reason, .checksumMismatch)
        }
        let found = await registry.installed(agentID: "opencode", version: "2.4.1")
        XCTAssertNil(found)
        XCTAssertFalse(FileManager.default.fileExists(atPath: registry.agentsDirectory + "/opencode/2.4.1/darwin-aarch64"))
    }

    func testArchiveWithAParentPathIsRefusedAndWritesNothingOutside() async throws {
        let escaped = (scratch as NSString).appendingPathComponent("state/agents/opencode/escaped")
        let archive = try opencodeArchive(extraArguments: ["-s", ",^payload,../escaped,"]) { source in
            let script = (source as NSString).appendingPathComponent("opencode")
            try "#!/bin/sh\n".write(toFile: script, atomically: true, encoding: .utf8)
            chmod(script, 0o755)
            try "x".write(toFile: (source as NSString).appendingPathComponent("payload"), atomically: true, encoding: .utf8)
        }
        let registry = installer(host(calls: Calls(), archive: archive.path))
        do {
            _ = try await registry.install(binaryAgent(sha: archive.sha))
            XCTFail("an archive naming ../ must be refused")
        } catch let error as ACPRegistryError {
            XCTAssertEqual(error.reason, .archiveInvalid)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped))
    }

    func testCommandThatLinksOutsideTheFolderIsRefused() async throws {
        let archive = try opencodeArchive { source in
            try FileManager.default.createSymbolicLink(atPath: (source as NSString).appendingPathComponent("opencode"),
                                                       withDestinationPath: "/bin/sh")
        }
        let registry = installer(host(calls: Calls(), archive: archive.path))
        do {
            _ = try await registry.install(binaryAgent(sha: archive.sha))
            XCTFail("a command that resolves outside its folder must be refused")
        } catch let error as ACPRegistryError {
            XCTAssertEqual(error.reason, .archiveInvalid)
        }
        let found = await registry.installed(agentID: "opencode", version: "2.4.1")
        XCTAssertNil(found)
    }

    func testArchiveWithoutTheCommandIsRefused() async throws {
        let archive = try opencodeArchive()
        let registry = installer(host(calls: Calls(), archive: archive.path))
        do {
            _ = try await registry.install(binaryAgent(sha: archive.sha, cmd: "./not-there"))
            XCTFail("the command the entry names must be in the archive")
        } catch let error as ACPRegistryError {
            XCTAssertEqual(error.reason, .archiveInvalid)
        }
    }

    func testUnsafeCommandInEntryIsRefusedBeforeDownloading() async throws {
        let calls = Calls()
        let registry = installer(host(calls: calls, archive: nil))
        do {
            _ = try await registry.install(binaryAgent(sha: nil, cmd: "../../bin/sh"))
            XCTFail("an entry whose command leaves its folder must be refused")
        } catch let error as ACPRegistryError {
            XCTAssertEqual(error.reason, .archiveInvalid)
        }
        XCTAssertTrue(calls.downloads.isEmpty)
    }

    func testNoBuildForThisMacIsReported() async throws {
        let registry = installer(host(calls: Calls()), platform: "darwin-x86_64")
        do {
            _ = try await registry.install(binaryAgent(sha: nil))
            XCTFail("an agent with no build for this Mac must not install")
        } catch let error as ACPRegistryError {
            XCTAssertEqual(error.reason, .unsupportedPlatform)
        }
    }

    // MARK: Package installs

    /// A fake npm that installs `spec` under `npm_config_prefix`, as `npm install --global` does.
    private static let fakeNpm: @Sendable (String, [String], [String: String]) throws -> ACPRegistryHost.CommandResult = { _, args, env in
        let prefix = try XCTUnwrap(env["npm_config_prefix"])
        let modules = prefix + "/lib/node_modules"
        switch args {
        case ["root", "--global"]: return .init(status: 0, stdout: modules + "\n")
        case ["prefix", "--global"]: return .init(status: 0, stdout: prefix + "\n")
        default:
            guard args.first == "install", args.last == "@scope/demo-acp@1.2.3" else {
                return .init(status: 1, stdout: "", stderr: "unexpected \(args)")
            }
            let package = modules + "/@scope/demo-acp"
            try FileManager.default.createDirectory(atPath: package + "/dist", withIntermediateDirectories: true)
            try #"{"name":"@scope/demo-acp","version":"1.2.3","bin":{"demo-acp":"dist/cli.js"}}"#
                .write(toFile: package + "/package.json", atomically: true, encoding: .utf8)
            try "#!/bin/sh\n".write(toFile: package + "/dist/cli.js", atomically: true, encoding: .utf8)
            chmod(package + "/dist/cli.js", 0o755)
            try FileManager.default.createDirectory(atPath: prefix + "/bin", withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: prefix + "/bin/demo-acp",
                                                       withDestinationPath: "../lib/node_modules/@scope/demo-acp/dist/cli.js")
            return .init(status: 0, stdout: "added 1 package\n")
        }
    }

    func testNpxInstallsIntoItsOwnFolderWithTheExactSpec() async throws {
        let calls = Calls()
        let registry = installer(host(calls: calls, programs: ["npm": "/opt/tools/npm"], packageManager: Self.fakeNpm))
        let install = try await registry.install(packageAgent(npx: "@scope/demo-acp@1.2.3"))

        let runs = calls.packageManagerRuns
        let installRun = try XCTUnwrap(runs.first { $0.1.first == "install" })
        XCTAssertEqual(installRun.0, "/opt/tools/npm")
        XCTAssertEqual(installRun.1, ["install", "--global", "@scope/demo-acp@1.2.3"])
        XCTAssertTrue(installRun.2["npm_config_prefix"]!.hasSuffix("/state/agents/demo/1.2.3/npm"))
        XCTAssertTrue(installRun.2["PATH"]!.hasPrefix("/opt/tools:"), "npm's own folder comes first, as T3 Code does")

        XCTAssertEqual(install.distribution, .npx)
        XCTAssertTrue(install.executablePath.hasSuffix("/agents/demo/1.2.3/npm/lib/node_modules/@scope/demo-acp/dist/cli.js"),
                      install.executablePath)
        let launch = ACPRegistryInstaller.launchSpec(for: install, workingDirectory: nil, baseEnvironment: ["PATH": "/usr/bin"])
        XCTAssertEqual(launch.arguments, ["--acp"])
        XCTAssertEqual(launch.environment["DEMO_MODE"], "acp")
        XCTAssertTrue(launch.environment["PATH"]!.hasSuffix(":/usr/bin"))
        let found = await registry.installed(agentID: "demo", version: "1.2.3")
        XCTAssertEqual(found, install)
    }

    func testUvxInstallsIntoItsOwnToolFolder() async throws {
        let calls = Calls()
        let fakeUv: @Sendable (String, [String], [String: String]) throws -> ACPRegistryHost.CommandResult = { _, args, env in
            let bin = try XCTUnwrap(env["UV_TOOL_BIN_DIR"])
            switch args {
            case ["tool", "install", "--force", "demo==1.2.3"]:
                try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
                try "#!/bin/sh\n".write(toFile: bin + "/demo", atomically: true, encoding: .utf8)
                chmod(bin + "/demo", 0o755)
                return .init(status: 0, stdout: "")
            case ["tool", "list"]: return .init(status: 0, stdout: "demo v1.2.3\n- demo\n")
            case ["tool", "dir", "--bin"]: return .init(status: 0, stdout: bin + "\n")
            default: return .init(status: 1, stdout: "", stderr: "unexpected \(args)")
            }
        }
        let registry = installer(host(calls: calls, programs: ["uv": "/opt/tools/uv"], packageManager: fakeUv))
        let install = try await registry.install(packageAgent(uvx: "demo==1.2.3"))
        XCTAssertEqual(install.distribution, .uvx)
        XCTAssertTrue(install.executablePath.hasSuffix("/agents/demo/1.2.3/python/bin/demo"), install.executablePath)
        let installRun = try XCTUnwrap(calls.packageManagerRuns.first)
        XCTAssertTrue(installRun.2["UV_TOOL_DIR"]!.hasSuffix("/agents/demo/1.2.3/python"))
    }

    /// A Mac without `uv` (or `npm`) is told so before the user adds the agent, and an add
    /// fails plainly instead of running anything.
    func testMissingRunnerIsFlaggedAndNothingRuns() async throws {
        let calls = Calls()
        let registry = installer(host(calls: calls, programs: [:]))
        let uvAgent = packageAgent(uvx: "demo==1.2.3")
        XCTAssertEqual(registry.missingRunner(for: uvAgent), "uv")
        XCTAssertEqual(registry.missingRunner(for: packageAgent(npx: "demo@1.2.3")), "npm")
        XCTAssertNil(registry.missingRunner(for: binaryAgent(sha: nil)))
        do {
            _ = try await registry.install(uvAgent)
            XCTFail("an install whose runner is missing must not proceed")
        } catch let error as ACPRegistryError {
            XCTAssertEqual(error.reason, .runnerUnavailable)
            XCTAssertTrue(error.detail.contains("'uv'"))
        }
        XCTAssertTrue(calls.runs.isEmpty)
    }

    func testFailedPackageInstallLeavesNoInstall() async throws {
        let failing: @Sendable (String, [String], [String: String]) throws -> ACPRegistryHost.CommandResult = { _, _, _ in
            .init(status: 1, stdout: "", stderr: "E404 not found")
        }
        let registry = installer(host(calls: Calls(), programs: ["npm": "/opt/tools/npm"], packageManager: failing))
        do {
            _ = try await registry.install(packageAgent(npx: "@scope/demo-acp@1.2.3"))
            XCTFail("a failed npm install must fail the add")
        } catch let error as ACPRegistryError {
            XCTAssertEqual(error.reason, .installFailed)
            XCTAssertTrue(error.detail.contains("E404"))
        }
        let found = await registry.installed(agentID: "demo", version: "1.2.3")
        XCTAssertNil(found)
    }

    // MARK: Reading never installs

    func testReadingTheListAndInstallsNeverInstalls() async throws {
        let calls = Calls()
        let index = try fixture("registry-index-2026-11-24.json")
        let registry = installer(host(calls: calls, index: index, programs: ["npm": "/opt/tools/npm", "uv": "/opt/tools/uv"]))
        let loaded = try await registry.loadIndex()
        for agent in loaded.agents {
            _ = registry.missingRunner(for: agent)
            let found = await registry.installed(agentID: agent.id, version: agent.version)
            XCTAssertNil(found)
        }
        let all = await registry.allInstalled()
        XCTAssertTrue(all.isEmpty)
        XCTAssertTrue(calls.downloads.isEmpty)
        XCTAssertTrue(calls.runs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: registry.agentsDirectory))
    }

    func testIndexFallsBackToTheSavedCopyWhenOffline() async throws {
        let index = try fixture("registry-index-2026-11-24.json")
        let state = (scratch as NSString).appendingPathComponent("state")
        let online = ACPRegistryInstaller(stateDirectory: state, host: host(calls: Calls(), index: index), environment: [:])
        let first = try await online.loadIndex()
        let offline = ACPRegistryInstaller(stateDirectory: state, host: host(calls: Calls(), index: nil), environment: [:])
        let second = try await offline.loadIndex()
        XCTAssertEqual(second, first)

        let fresh = ACPRegistryInstaller(stateDirectory: state + "-other", host: host(calls: Calls(), index: nil), environment: [:])
        do {
            _ = try await fresh.loadIndex()
            XCTFail("offline with no saved copy must fail")
        } catch let error as ACPRegistryError {
            XCTAssertEqual(error.reason, .registryUnavailable)
        }
    }

    // MARK: Removing

    func testUninstallRemovesEveryVersionAndRefusesABadID() async throws {
        let archive = try opencodeArchive()
        let registry = installer(host(calls: Calls(), archive: archive.path))
        _ = try await registry.install(binaryAgent(sha: archive.sha))
        try await registry.uninstall(agentID: "opencode")
        let found = await registry.installed(agentID: "opencode", version: "2.4.1")
        XCTAssertNil(found)
        XCTAssertFalse(FileManager.default.fileExists(atPath: registry.agentsDirectory + "/opencode"))
        do {
            try await registry.uninstall(agentID: "../state")
            XCTFail("an id that is not an agent id must be refused")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: registry.agentsDirectory))
    }

    /// A receipt edited to point outside the agent's folder is not trusted.
    func testReceiptPointingOutsideItsFolderIsIgnored() async throws {
        let archive = try opencodeArchive()
        let registry = installer(host(calls: Calls(), archive: archive.path))
        var install = try await registry.install(binaryAgent(sha: archive.sha))
        install.executablePath = "/bin/sh"
        let receipt = registry.agentsDirectory + "/opencode/2.4.1/receipt.json"
        try JSONEncoder().encode(install).write(to: URL(fileURLWithPath: receipt))
        let found = await registry.installed(agentID: "opencode", version: "2.4.1")
        XCTAssertNil(found)
    }
}
