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
//
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).

import NexusAgentCore
import NexusAgentUI
import XCTest

@MainActor
final class OrcaWorktreeAndRaceTests: XCTestCase {

    // MARK: - .nexus.yaml / orca.yaml Configuration Parsing

    func testWorktreeConfigParsesAndSerializesSetupEnvAndBaseBranch() {
        let yaml = """
        # Orca / Nexus worktree config
        baseBranch: main
        env:
          NODE_ENV: "development"
          API_PORT: 8080
        setup:
          - "pnpm install --frozen-lockfile"
          - bazel build //...
        """

        let config = NexusAgentWorktreeConfig.parse(yaml: yaml)
        XCTAssertEqual(config.baseBranch, "main")
        XCTAssertEqual(config.env, ["NODE_ENV": "development", "API_PORT": "8080"])
        XCTAssertEqual(config.setup, ["pnpm install --frozen-lockfile", "bazel build //..."])

        let roundTripped = NexusAgentWorktreeConfig.parse(yaml: config.serialize())
        XCTAssertEqual(roundTripped, config)
    }

    // MARK: - Porcelain Worktree Parsing & Provider Worktree Lifecycle

    func testPorcelainWorktreeListParsingAndAllProviderWorktreeCommands() async {
        let porcelain = """
        worktree /workspace/repo
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /workspace/repo-worktrees/antigravity-cli-fix-auth
        HEAD 2222222222222222222222222222222222222222
        branch refs/heads/nexus/antigravity-cli/fix-auth

        """

        let parsed = NexusAgentWorktreeManager.parsePorcelainList(porcelain)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].worktreePath, "/workspace/repo")
        XCTAssertEqual(parsed[0].shortBranchName, "main")
        XCTAssertEqual(parsed[1].worktreePath, "/workspace/repo-worktrees/antigravity-cli-fix-auth")
        XCTAssertEqual(parsed[1].shortBranchName, "nexus/antigravity-cli/fix-auth")

        let customProvider = NexusAgentCLIProvider(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            name: "Custom Aider",
            commandTemplate: "aider --message \"{prompt}\"",
            isBuiltIn: false
        )
        let providers: [NexusAgentCLIProvider] = [
            .antigravity,
            .claude,
            .opencode,
            customProvider,
        ]

        let manager = NexusAgentWorktreeManager()
        let config = NexusAgentWorktreeConfig(setup: ["pnpm install"], env: ["CI": "1"], baseBranch: "origin/main")

        for provider in providers {
            let created = await manager.createWorktree(
                taskName: "Refactor Auth",
                baseRepositoryPath: "/workspace/repo",
                provider: provider,
                config: config,
                runGit: { _, _ in "" },
                runSetup: { _, _ in "ok" }
            )
            XCTAssertEqual(created.setupStatus, .ready)
            XCTAssertEqual(created.baseRef, "origin/main")
            XCTAssertEqual(created.providerID, provider.id)

            let removed = await manager.removeWorktree(
                id: created.id,
                force: true,
                deleteBranch: true,
                runGit: { _, _ in "" }
            )
            XCTAssertTrue(removed)
        }
        XCTAssertTrue(manager.worktrees.isEmpty)
    }

    // MARK: - Multi-Agent Race Mode Lifecycle

    func testRaceSessionFansOutContendersParsesDiffStatsAndPicksWinner() async {
        let session = NexusAgentRaceSession()
        let specs: [(provider: NexusAgentCLIProvider, model: String)] = [
            (.antigravity, "gemini-3-pro"),
            (.claude, "claude-opus-4-6"),
            (.opencode, "anthropic/claude-sonnet-4-5"),
        ]

        await session.startRace(
            prompt: "Optimize the SQLite query planner",
            specs: specs,
            baseDirectory: "/workspace/repo",
            baseRef: "main",
            runGit: { _, _ in "" }
        )

        XCTAssertEqual(session.contenders.count, 3)
        XCTAssertTrue(session.isRunning)

        let firstID = session.contenders[0].id
        let secondID = session.contenders[1].id
        let thirdID = session.contenders[2].id

        session.updateContender(
            id: firstID,
            status: .completed,
            responseText: "Added covering index on conversation_summaries",
            durationMs: 4200,
            diffStat: " 2 files changed, 34 insertions(+), 5 deletions(-)"
        )
        session.updateContender(
            id: secondID,
            status: .completed,
            responseText: "Rewrote query with CTE",
            durationMs: 5100,
            diffStat: " 1 file changed, 18 insertions(+), 12 deletions(-)"
        )
        session.updateContender(
            id: thirdID,
            status: .completed,
            responseText: "Added query cache",
            durationMs: 6300,
            diffStat: " 3 files changed, 60 insertions(+), 2 deletions(-)"
        )

        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.contenders[0].filesChanged, 2)
        XCTAssertEqual(session.contenders[0].addedLines, 34)
        XCTAssertEqual(session.contenders[0].removedLines, 5)

        let winner = await session.pickWinner(id: secondID, runGit: { _, _ in "" })
        XCTAssertEqual(winner?.id, secondID)
        XCTAssertEqual(session.winnerID, secondID)
        XCTAssertEqual(session.contenders[0].status, .discarded)
        XCTAssertEqual(session.contenders[1].status, .winner)
        XCTAssertEqual(session.contenders[2].status, .discarded)
    }

    // MARK: - Checkpoint Timeline & Attribution

    func testCheckpointTimelineAttributionAndRewind() async {
        let timeline = NexusAgentCheckpointTimeline()

        let turn1 = timeline.recordTurnCheckpoint(
            turnIndex: 1,
            promptPreview: "Scaffold worktree config parser",
            commitOrStashRef: "aaa1111",
            aiAddedLines: 80,
            aiRemovedLines: 0,
            humanAddedLines: 20,
            humanRemovedLines: 0
        )
        let turn2 = timeline.recordTurnCheckpoint(
            turnIndex: 2,
            promptPreview: "Add multi-agent race session",
            commitOrStashRef: "bbb2222",
            aiAddedLines: 120,
            aiRemovedLines: 30,
            humanAddedLines: 0,
            humanRemovedLines: 0
        )
        let turn3 = timeline.recordTurnCheckpoint(
            turnIndex: 3,
            promptPreview: "Polish UI badges",
            commitOrStashRef: "ccc3333",
            aiAddedLines: 30,
            aiRemovedLines: 10,
            humanAddedLines: 10,
            humanRemovedLines: 0
        )

        XCTAssertEqual(turn1.aiAttributionPercentage, 80)
        XCTAssertEqual(turn2.aiAttributionPercentage, 100)
        XCTAssertEqual(turn3.aiAttributionPercentage, 80)
        XCTAssertEqual(timeline.overallAttribution.aiAttributionPercentage, 90)

        let undone = await timeline.rewind(
            to: turn1.id,
            repositoryPath: "/workspace/repo",
            runGit: { _, _ in "" }
        )
        XCTAssertEqual(undone.map(\.id), [turn2.id, turn3.id])
        XCTAssertEqual(timeline.entries.map(\.id), [turn1.id])
    }

    // MARK: - Multi-Repo Parent Workspace Discovery & CLI Flags

    func testMultiRepoDiscoveryAndAdditionalDirectoryFlags() {
        let childEntries = ["frontend", "backend", "docs", ".hidden-repo"]
        let gitSet: Set<String> = ["/workspace/parent/frontend", "/workspace/parent/backend", "/workspace/parent/.hidden-repo"]

        let discovered = NexusAgentMultiRepoWorkspace.discoverRepositories(
            in: "/workspace/parent",
            listDirectory: { _ in childEntries },
            isGitRepo: { gitSet.contains($0) }
        )

        XCTAssertEqual(discovered, ["/workspace/parent/backend", "/workspace/parent/frontend"])

        let claudeFlags = NexusAgentMultiRepoWorkspace.additionalDirectoryArguments(
            for: .claude,
            childRepos: discovered
        )
        XCTAssertEqual(
            claudeFlags,
            ["--add-dir", "/workspace/parent/backend", "--add-dir", "/workspace/parent/frontend"]
        )

        let ollamaFlags = NexusAgentMultiRepoWorkspace.additionalDirectoryArguments(
            for: .ollama,
            childRepos: discovered
        )
        XCTAssertEqual(ollamaFlags, claudeFlags)

        let opencodeFlags = NexusAgentMultiRepoWorkspace.additionalDirectoryArguments(
            for: .opencode,
            childRepos: discovered
        )
        XCTAssertEqual(opencodeFlags, [])
    }

    func testWorktreeConfigIgnoresUnknownListSectionAndExportsEnvInSetup() async {
        let yaml = """
        baseBranch: main
        unknownSection:
          - should-not-be-in-setup
        env:
          API_TOKEN: "secret'123"
        setup:
          - "npm test"
        """
        let config = NexusAgentWorktreeConfig.parse(yaml: yaml)
        XCTAssertEqual(config.setup, ["npm test"])
        XCTAssertEqual(config.env["API_TOKEN"], "secret'123")

        let manager = NexusAgentWorktreeManager()
        nonisolated(unsafe) var capturedSetupArgs: [[String]] = []
        let created = await manager.createWorktree(
            taskName: "env-test",
            baseRepositoryPath: "/workspace/my repo",
            provider: .claude,
            config: config,
            runGit: { _, _ in "" },
            runSetup: { _, args in
                capturedSetupArgs.append(args)
                return "ok"
            }
        )
        XCTAssertEqual(created.setupStatus, .ready)
        XCTAssertEqual(capturedSetupArgs.count, 1)
        XCTAssertEqual(capturedSetupArgs.first?.first, "-c")
        XCTAssertTrue(capturedSetupArgs.first?[1].contains("export API_TOKEN='secret'\\''123'; npm test") ?? false)
        XCTAssertEqual(capturedSetupArgs.first?.last, "/workspace/my repo-worktrees/claude-code-env-test")
    }

    func testRaceSessionResetAndCheckpointTimelineClear() async {
        let race = NexusAgentRaceSession()
        await race.startRace(
            prompt: "Test reset",
            specs: [(.antigravity, ""), (.claude, "")],
            baseDirectory: "/workspace/repo",
            runGit: { _, _ in "" }
        )
        XCTAssertEqual(race.contenders.count, 2)
        race.reset()
        XCTAssertTrue(race.contenders.isEmpty)
        XCTAssertNil(race.winnerID)
        XCTAssertFalse(race.isRunning)

        let timeline = NexusAgentCheckpointTimeline()
        timeline.recordTurnCheckpoint(promptPreview: "Turn 1", commitOrStashRef: "abc1234", aiAddedLines: 10)
        XCTAssertEqual(timeline.entries.count, 1)
        timeline.clear()
        XCTAssertTrue(timeline.entries.isEmpty)
    }
}
