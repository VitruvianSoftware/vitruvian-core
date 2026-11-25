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

/// One real install from the live ACP registry, then an ACP session with it. Skipped unless
/// asked for, as it downloads the agent from the network:
///
///     bazel test --config=macos-app //apps/desktop/vitruvian-code/macos:VitruvianCodeTests \
///       --test_filter=ACPRegistryLiveTests --test_env=ACP_REGISTRY_LIVE_AGENT=opencode
///
/// Everything happens in a scratch folder with a scratch HOME, so the agent sees none of the
/// user's own settings or sign-ins. No prompt is sent.
@MainActor
final class ACPRegistryLiveTests: XCTestCase {
    func testInstallsFromTheLiveRegistryAndOpensASession() async throws {
        guard let agentID = ProcessInfo.processInfo.environment["ACP_REGISTRY_LIVE_AGENT"], !agentID.isEmpty else {
            throw XCTSkip("Set ACP_REGISTRY_LIVE_AGENT to a registry agent id (for example opencode) to run one real install.")
        }
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("acp-live-\(UUID().uuidString)")
        let home = scratch.appendingPathComponent("home"), state = scratch.appendingPathComponent("state")
        let work = scratch.appendingPathComponent("work")
        for folder in [home, state, work] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: scratch) }

        let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path, "TMPDIR": NSTemporaryDirectory()]
        let installer = ACPRegistryInstaller(stateDirectory: state.path, host: .live(home: home.path), environment: environment)
        let index = try await installer.loadIndex()
        let agent = try XCTUnwrap(index.agents.first { $0.id == agentID }, "\(agentID) is not in the registry")
        let install = try await installer.install(agent)
        XCTAssertTrue(install.executablePath.hasPrefix(state.resolvingSymlinksInPath().path)
                      || install.executablePath.contains("/agents/\(agentID)/"), install.executablePath)

        let launch = ACPRegistryInstaller.launchSpec(for: install, workingDirectory: work.path, baseEnvironment: environment)
        let connection = ACPConnection(launchSpec: launch, policy: .none,
                                       stateFolderURL: state, sessionSetupTimeout: 120)
        defer { Task { await connection.stop() } }
        let sessionID = try await connection.start(AgentSessionRequest(workingDirectory: work.path))
        XCTAssertFalse(sessionID.isEmpty)
        print("ACPRegistryLive: \(agent.name) \(agent.version) via \(install.distribution.rawValue), agent reports \(connection.agentVersion ?? "no version"), session \(sessionID)")
        await connection.stop()
    }
}
