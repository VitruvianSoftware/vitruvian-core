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
import XCTest
@testable import VitruvianCodeCore

/// One real Claude turn: the bundled Node runs the bundled helper, and the helper runs the
/// user's own signed-in `claude`. It sends a real prompt, so it costs a request on the user's
/// plan, and it only runs when asked to:
///
///   bazel test --config=macos-app //apps/desktop/vitruvian-code/macos:VitruvianCodeTests \
///     --test_filter=ClaudeSDKLiveTests --test_env=CLAUDE_SDK_LIVE_CLAUDE=$(command -v claude) \
///     --test_env=HOME --spawn_strategy=local --nocache_test_results
///
/// `HOME` and the local strategy let `claude` reach its own sign-in. The chat runs in an empty
/// temporary folder in plan mode, so Claude can read nothing of the user's and change nothing.
@MainActor
final class ClaudeSDKLiveTests: XCTestCase {
    func testARealClaudeTurnThroughTheBundledHelper() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let claudePath = env["CLAUDE_SDK_LIVE_CLAUDE"], !claudePath.isEmpty else {
            throw XCTSkip("Set CLAUDE_SDK_LIVE_CLAUDE to the path of a signed-in claude to run one real turn.")
        }
        guard let bundled = ClaudeSDKTestSupport.locateBundled() else {
            throw XCTSkip("No bundled Node and Claude helper here.")
        }
        let home = try XCTUnwrap(env["HOME"], "pass --test_env=HOME so claude finds its sign-in")

        let made = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-sdk-live-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: made) }
        let state = made.appendingPathComponent("state", isDirectory: true)
        let work = made.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        var environment = VitruvianCodeEngine.Environment.live(stateDirectoryOverride: state.path)
        environment.home = home
        environment.processEnvironment = [
            "PATH": "\(URL(fileURLWithPath: claudePath).deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home,
        ]
        var provider = VitruvianCodeCLIProvider.claude
        provider.connection = .claudeSDK
        let spec = AgentConnectionSpec(
            kind: .claudeSDK,
            provider: provider,
            configuration: VitruvianCodeConfiguration(approvalMode: .standard, activeProvider: provider),
            agentPath: claudePath,
            workingDirectory: work.path,
            turnModes: AgentTurnModes(plan: true),
            environment: environment.processEnvironment
        )
        let connection = ClaudeSDKConnection(spec: spec, environment: environment, bundledNode: { bundled })
        let recorder = ClaudeEventRecorder(connection.events)

        let sessionID = try await connection.start(AgentSessionRequest(workingDirectory: work.path))
        XCTAssertFalse(sessionID.isEmpty)
        XCTAssertNotNil(connection.installedClaudeVersion, "claude --version was read")

        let stop = try await withACPTestTimeout(seconds: 120, description: "the real turn to end") {
            try await connection.prompt([.text("Reply with exactly the word: pong. Don't use any tools.")])
        }
        XCTAssertEqual(stop, .endTurn)
        await recorder.wait("Claude's reply streamed back as text") { event in
            if case .text(let piece) = event { return piece.lowercased().contains("pong") }
            return false
        }

        await connection.stop()
        await recorder.finish()
    }
}
