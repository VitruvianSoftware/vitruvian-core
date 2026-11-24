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

/// The pure rules of the Claude helper connection: no process runs here, so none of these skip.
final class ClaudeSDKSupportTests: XCTestCase {
    // MARK: - Reading the version

    func testTheVersionIsReadAsT3CodeReadsIt() {
        XCTAssertEqual(ClaudeSDKSupport.parseVersion("2.1.45 (Claude Code)\n"), "2.1.45")
        XCTAssertEqual(ClaudeSDKSupport.parseVersion("v2.1.326"), "2.1.326")
        XCTAssertEqual(ClaudeSDKSupport.parseVersion("Claude Code 2.2.0-beta.1+abc.2 something"), "2.2.0-beta.1+abc.2")
        XCTAssertNil(ClaudeSDKSupport.parseVersion("no version here"))
        XCTAssertNil(ClaudeSDKSupport.parseVersion(""))
        XCTAssertNil(ClaudeSDKSupport.parseVersion(nil))
        XCTAssertNil(ClaudeSDKSupport.parseVersion("2.1"), "two parts are not a version")
    }

    func testVersionsCompareNumbersNotText() {
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.326", "2.1.326"), 0)
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.99", "2.1.326"), -1)
        XCTAssertEqual(ClaudeSDKSupport.compare("2.10.0", "2.9.9"), 1)
        XCTAssertEqual(ClaudeSDKSupport.compare("3.0.0", "2.99.99"), 1)
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.326+build.5", "2.1.326"), 0, "build metadata counts for nothing")
    }

    /// T3 Code's `compareSemverVersions`: a pre-release ranks below its release.
    func testAPreReleaseRanksBelowItsRelease() {
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.280-rc.1", "2.1.280"), -1)
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.280", "2.1.280-rc.1"), 1)
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.279", "2.1.280-rc.1"), -1, "the numbers come first")
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.281-rc.1", "2.1.280"), 1)
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.280-rc.1", "2.1.280-rc.2"), -1)
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.280-rc.2", "2.1.280-rc.10"), -1, "numbers compare as numbers")
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.280-rc.1", "2.1.280-rc.1"), 0)
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.280-1", "2.1.280-rc"), -1, "numbers rank below words")
        XCTAssertEqual(ClaudeSDKSupport.compare("2.1.280-rc", "2.1.280-rc.1"), -1, "a shorter list ranks below")
        // ...and so the upgrade message and model hiding treat a pre-release as older.
        XCTAssertEqual(
            ClaudeSDKSupport.unavailableModels(version: "2.1.280-rc.1").map(\.id),
            ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
        )
    }

    // MARK: - Too old for the helper

    func testTheUpgradeCommandFollowsHowClaudeWasInstalled() {
        XCTAssertEqual(ClaudeSDKSupport.updateCommand(forClaudeAt: "/Users/me/.local/bin/claude"), "claude update")
        XCTAssertEqual(
            ClaudeSDKSupport.updateCommand(forClaudeAt: "/opt/homebrew/Caskroom/claude-code/2.1.100/claude"),
            "brew upgrade --cask claude-code"
        )
        XCTAssertEqual(
            ClaudeSDKSupport.updateCommand(forClaudeAt: "/opt/homebrew/Caskroom/claude-code@latest/2.1.100/claude"),
            "brew upgrade --cask claude-code@latest"
        )
    }

    func testTheTooOldMessageNamesBothVersionsAndTheCommand() {
        XCTAssertEqual(
            ClaudeSDKSupport.tooOldMessage(version: "2.1.100", minimum: "2.1.326", updateCommand: "claude update"),
            "Claude Code v2.1.100 is older than v2.1.326. Chats work, but MCP servers that carry "
                + "secrets need v2.1.326 or newer. Upgrade with `claude update`."
        )
    }

    /// T3 Code (`ClaudeModelCatalog.ts`, `formatClaudeVersionUpgradeMessage`) tells a user of the
    /// stable cask to move to `claude-code@latest` when the stable cask is behind. The app cannot
    /// know what the cask offers, so it says to switch if the upgrade does not reach the minimum.
    func testTheStableHomebrewCaskIsToldToSwitchToTheLatestChannel() {
        let stable = "/opt/homebrew/Caskroom/claude-code/2.1.322/claude"
        let switchCommand = "brew uninstall --cask claude-code && brew install --cask claude-code@latest"
        XCTAssertEqual(ClaudeSDKSupport.channelSwitchCommand(forClaudeAt: stable), switchCommand)
        XCTAssertNil(ClaudeSDKSupport.channelSwitchCommand(forClaudeAt: "/opt/homebrew/Caskroom/claude-code@latest/2.1.322/claude"))
        XCTAssertNil(ClaudeSDKSupport.channelSwitchCommand(forClaudeAt: "/Users/me/.local/bin/claude"))
        XCTAssertEqual(
            ClaudeSDKSupport.tooOldMessage(
                version: "2.1.322",
                minimum: "2.1.326",
                updateCommand: ClaudeSDKSupport.updateCommand(forClaudeAt: stable),
                switchCommand: ClaudeSDKSupport.channelSwitchCommand(forClaudeAt: stable)
            ),
            "Claude Code v2.1.322 is older than v2.1.326. Chats work, but MCP servers that carry "
                + "secrets need v2.1.326 or newer. Upgrade with `brew upgrade --cask claude-code`. "
                + "The stable claude-code Homebrew cask may not reach v2.1.326 yet: if it does not, "
                + "switch to the claude-code@latest cask with `\(switchCommand)`."
        )
    }

    // MARK: - Models

    func testEveryClaudeModelTheAppListsHasAMinimumVersionRow() {
        let listed = VitruvianCodeSupport.defaultModels(for: .claude).map(\.id)
        let known = Set(ClaudeSDKSupport.modelRequirements.flatMap { [$0.id] + $0.aliases })
        XCTAssertEqual(Set(listed).subtracting(known), [], "a model added to the list needs its row from T3 Code's manifest")
        XCTAssertEqual(known.subtracting(listed), [], "a row for a model the app no longer lists")
    }

    func testTheMinimumsAreT3CodesManifestValues() {
        let byID = Dictionary(uniqueKeysWithValues: ClaudeSDKSupport.modelRequirements.map { ($0.id, $0.minVersion) })
        XCTAssertEqual(byID["claude-opus-5-5"] ?? nil, "2.1.280")
        XCTAssertEqual(byID["claude-sonnet-5-5"] ?? nil, "2.1.284")
        XCTAssertEqual(byID["claude-haiku-5-5"] ?? nil, "2.1.293")
        XCTAssertEqual(byID["claude-opus-4-7"] ?? nil, "2.1.111")
        XCTAssertNil(byID["claude-sonnet-4-6"] ?? nil)
    }

    func testModelsTheInstalledClaudeIsTooOldForAreHiddenAliasesIncluded() {
        let all = VitruvianCodeSupport.defaultModels(for: .claude)

        let hiddenAt200 = Set(all.map(\.id)).subtracting(ClaudeSDKSupport.visibleModels(all, version: "2.1.200").map(\.id))
        XCTAssertEqual(hiddenAt200, ["opus", "sonnet", "haiku", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"])

        let hiddenAt100 = Set(all.map(\.id)).subtracting(ClaudeSDKSupport.visibleModels(all, version: "2.1.100").map(\.id))
        XCTAssertTrue(hiddenAt100.contains("claude-opus-4-7"))
        XCTAssertFalse(hiddenAt100.contains("claude-sonnet-4-6"), "a model with no minimum is never hidden")

        XCTAssertEqual(ClaudeSDKSupport.visibleModels(all, version: "2.1.293"), all)
    }

    func testAVersionThatCannotBeReadHidesNothing() {
        let all = VitruvianCodeSupport.defaultModels(for: .claude)
        XCTAssertEqual(ClaudeSDKSupport.visibleModels(all, version: nil), all)
        XCTAssertNil(ClaudeSDKSupport.versionUpgradeMessage(version: nil))
    }

    func testTheUpgradeMessageNamesTheModelThatNeedsTheOldestClaude() {
        XCTAssertEqual(
            ClaudeSDKSupport.versionUpgradeMessage(version: "2.1.200"),
            "Claude Code v2.1.200 is too old for Claude Opus 5.5. Upgrade to v2.1.280 or newer to use it."
        )
        XCTAssertEqual(
            ClaudeSDKSupport.versionUpgradeMessage(version: "2.1.100"),
            "Claude Code v2.1.100 is too old for Claude Opus 4.7. Upgrade to v2.1.111 or newer to use it."
        )
        XCTAssertEqual(
            ClaudeSDKSupport.versionUpgradeMessage(version: "2.1.282"),
            "Claude Code v2.1.282 is too old for Claude Sonnet 5.5. Upgrade to v2.1.284 or newer to use it."
        )
        XCTAssertNil(ClaudeSDKSupport.versionUpgradeMessage(version: "2.1.293"))
    }

    func testNoListedModelIsHeldBackOnAClaudeTheHelperAccepts() {
        // A claude older than the helper's 2.1.326 still starts (it only warns), so models can be
        // held back on one that runs. At 2.1.326 itself none is: the newest minimum the app lists
        // is 2.1.293. The hiding matters below that, and for the first model that needs more.
        let all = VitruvianCodeSupport.defaultModels(for: .claude)
        XCTAssertEqual(ClaudeSDKSupport.visibleModels(all, version: ClaudeSDKSupport.minimumClaudeVersion), all)
    }

    // MARK: - Modes

    func testTheApprovalModeAndPlanSwitchChooseClaudesMode() {
        XCTAssertEqual(ClaudeSDKSupport.claudeModeID(for: .yolo, planSwitch: false), "bypassPermissions")
        XCTAssertEqual(ClaudeSDKSupport.claudeModeID(for: .acceptEdits, planSwitch: false), "acceptEdits")
        XCTAssertEqual(ClaudeSDKSupport.claudeModeID(for: .standard, planSwitch: false), "default")
        XCTAssertEqual(ClaudeSDKSupport.claudeModeID(for: .plan, planSwitch: false), "plan")
        XCTAssertEqual(ClaudeSDKSupport.claudeModeID(for: .auto, planSwitch: false), "auto", "Auto is the SDK's own auto permission mode")
        for mode in VitruvianCodeApprovalMode.allCases {
            XCTAssertEqual(ClaudeSDKSupport.claudeModeID(for: mode, planSwitch: true), "plan", "the plan switch wins over \(mode)")
        }
    }

    func testClaudeAsksTheUserWhateverTheToolKindIs() {
        let options = [AgentPermissionOption(id: "allow_once", name: "Allow", kind: .allowOnce)]
        let policy = ACPClientPolicy.claudeSDK
        for kind in ["read", "search", "think", "edit", "execute", "other", nil] as [String?] {
            for mode in VitruvianCodeApprovalMode.allCases {
                XCTAssertEqual(
                    policy.decide(mode: mode, planSwitch: false, toolKind: kind, options: options),
                    .ask,
                    "\(mode) \(String(describing: kind))"
                )
            }
        }
        XCTAssertTrue(policy.elicitation)
        XCTAssertFalse(policy.readTextFile || policy.writeTextFile || policy.terminal)
    }

    // MARK: - Secrets

    func testSecretsGoToTheHelperInTheShapeOfTheExample() {
        let plan = ClaudeSDKSupport.secretsPlan(
            environment: ["ANTHROPIC_API_KEY": "k1", "CUSTOM_GATEWAY_TOKEN": "k2"],
            mcpSecrets: [
                "local-docs": .init(environment: ["DOCS_ACCESS_KEY": "k3"]),
                "remote-mcp": .init(headers: ["Authorization": "Bearer k4"]),
                "empty": .init(),
            ]
        )
        XCTAssertEqual(
            plan.params,
            .object([
                "env": .object(["ANTHROPIC_API_KEY": .string("k1"), "CUSTOM_GATEWAY_TOKEN": .string("k2")]),
                "mcpServers": .object([
                    "local-docs": .object(["env": .object(["DOCS_ACCESS_KEY": .string("k3")])]),
                    "remote-mcp": .object(["headers": .object(["Authorization": .string("Bearer k4")])]),
                ]),
            ])
        )
        XCTAssertEqual(Set(plan.values), ["k1", "k2", "k3", "Bearer k4"])
    }

    func testOnlyEnvironmentSecretsSendNoMCPKey() {
        let plan = ClaudeSDKSupport.secretsPlan(environment: ["K": "v"], mcpSecrets: [:])
        XCTAssertEqual(plan.params, .object(["env": .object(["K": .string("v")])]))
    }

    // MARK: - Helper messages

    func testUsageLimitResetTimesAreReadWithAndWithoutFractions() {
        let expected = Date(timeIntervalSince1970: 1_795_201_200)
        func params(_ reset: ACPJSONValue) -> ACPJSONValue { .object(["sessionId": .string("s"), "resetsAt": reset]) }
        XCTAssertEqual(ClaudeSDKSupport.usageLimitResetDate(from: params(.string("2026-11-20T19:00:00Z"))), expected)
        XCTAssertEqual(ClaudeSDKSupport.usageLimitResetDate(from: params(.string("2026-11-20T19:00:00.000Z"))), expected)
        XCTAssertNil(ClaudeSDKSupport.usageLimitResetDate(from: params(.null)))
        XCTAssertNil(ClaudeSDKSupport.usageLimitResetDate(from: params(.string("later"))))
        XCTAssertNil(ClaudeSDKSupport.usageLimitResetDate(from: nil))
    }

    func testTheHelperSaysWhichToolCallsAreSubagents() throws {
        let launch = ACPToolCall(
            toolCallId: "t1",
            title: "Explore repository",
            kind: "other",
            status: "pending",
            rawInput: .object(["description": .string("Explore repository"), "prompt": .string("Find it")]),
            _meta: ["vitruvian": .object(["subagent": .bool(true)])]
        )
        XCTAssertTrue(ClaudeSDKSupport.isSubagentLaunch(launch))
        XCTAssertFalse(ClaudeSDKSupport.isSubagentLaunch(ACPToolCall(toolCallId: "t2", title: "Run Bash: ls", kind: "execute")))
        let subagent = ClaudeSDKSupport.subagent(from: launch, running: true)
        XCTAssertEqual(subagent.id, "t1")
        XCTAssertEqual(subagent.role, "Explore repository")
        XCTAssertEqual(subagent.prompt, "Find it")
        XCTAssertTrue(subagent.isRunning)
    }

    // MARK: - The provider's Claude config folder

    func testTheConfigFolderIsKeptWithTheProviderAndOlderSavedDataStillDecodes() throws {
        var provider = VitruvianCodeCLIProvider.claude
        provider.connection = .claudeSDK
        provider.claudeConfigDirectory = "/Users/me/.claude-work"

        let decoded = try JSONDecoder().decode(VitruvianCodeCLIProvider.self, from: JSONEncoder().encode(provider))
        XCTAssertEqual(decoded.claudeConfigDirectory, "/Users/me/.claude-work")

        let older = #"{"id":"00000000-0000-0000-0000-000000000003","name":"Claude Code","commandTemplate":"claude -p \"{prompt}\"","isBuiltIn":true}"#
        XCTAssertNil(try JSONDecoder().decode(VitruvianCodeCLIProvider.self, from: Data(older.utf8)).claudeConfigDirectory)

        let available = VitruvianCodeCLIProvider.available(saved: [provider])
        XCTAssertEqual(available.first { $0.id == VitruvianCodeCLIProvider.claude.id }?.claudeConfigDirectory, "/Users/me/.claude-work")
        let stored = VitruvianCodeCLIProvider.storedLists(saving: [provider], over: [])
        XCTAssertEqual(stored.builtIn.first { $0.id == VitruvianCodeCLIProvider.claude.id }?.claudeConfigDirectory, "/Users/me/.claude-work")
    }
}
