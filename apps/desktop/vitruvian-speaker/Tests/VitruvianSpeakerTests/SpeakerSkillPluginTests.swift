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
import Testing
@testable import VitruvianSpeakerCore

@Suite struct SpeakerSkillPluginTests {
    private let appProgram = "/Applications/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker"

    private func makeScratchDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-speaker-skill-plugins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Simulates `claude plugin ...` writes strictly inside `home` while recording invocations.
    private final class FakeClaudeCLI: @unchecked Sendable {
        let lock = NSLock()
        let home: URL
        var calls: [[String]] = []
        var available: Bool

        init(home: URL, available: Bool = true) {
            self.home = home
            self.available = available
        }

        var runner: ClaudeCLIRunner {
            ClaudeCLIRunner(
                findExecutable: { self.available ? self.home.appendingPathComponent(".local/bin/claude").path : nil },
                run: { args in try self.handle(args) }
            )
        }

        private func handle(_ args: [String]) throws -> ClaudeCLI.CommandResult {
            lock.withLock { calls.append(args) }
            let fm = FileManager.default
            let pluginsDir = home.appendingPathComponent(".claude/plugins", isDirectory: true)
            let knownURL = pluginsDir.appendingPathComponent("known_marketplaces.json")
            let installedURL = pluginsDir.appendingPathComponent("installed_plugins.json")
            let settingsURL = home.appendingPathComponent(".claude/settings.json")

            func readDict(_ url: URL) -> [String: Any] {
                guard let data = try? Data(contentsOf: url),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
                return obj
            }
            func writeDict(_ obj: [String: Any], to url: URL) throws {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url, options: .atomic)
            }

            if args.count >= 4 && args[0] == "plugin" && args[1] == "marketplace" && args[2] == "add" {
                let path = args[3]
                var known = readDict(knownURL)
                known[AgentPlugins.claudeMarketplaceName] = [
                    "source": ["source": "directory", "path": path],
                    "installLocation": path,
                ]
                try writeDict(known, to: knownURL)
                return ClaudeCLI.CommandResult(exitCode: 0, stdout: "Added marketplace", stderr: "")
            }

            if args.count >= 4 && args[0] == "plugin" && args[1] == "marketplace" && args[2] == "remove" {
                let name = args[3]
                var known = readDict(knownURL)
                known.removeValue(forKey: name)
                try writeDict(known, to: knownURL)
                return ClaudeCLI.CommandResult(exitCode: 0, stdout: "Removed marketplace", stderr: "")
            }

            if args.count >= 3 && args[0] == "plugin" && args[1] == "install" {
                let pluginID = args[2]
                var installed = readDict(installedURL)
                var plugins = (installed["plugins"] as? [String: Any]) ?? [:]
                plugins[pluginID] = [["scope": "user", "version": "1.0.0"]]
                installed["version"] = 2
                installed["plugins"] = plugins
                try writeDict(installed, to: installedURL)

                var settings = readDict(settingsURL)
                var enabled = (settings["enabledPlugins"] as? [String: Any]) ?? [:]
                enabled[pluginID] = true
                settings["enabledPlugins"] = enabled
                try writeDict(settings, to: settingsURL)
                return ClaudeCLI.CommandResult(exitCode: 0, stdout: "Installed", stderr: "")
            }

            if args.count >= 3 && args[0] == "plugin" && args[1] == "uninstall" {
                let pluginID = args[2]
                var installed = readDict(installedURL)
                var plugins = (installed["plugins"] as? [String: Any]) ?? [:]
                plugins.removeValue(forKey: pluginID)
                installed["plugins"] = plugins
                try writeDict(installed, to: installedURL)

                var settings = readDict(settingsURL)
                if var enabled = settings["enabledPlugins"] as? [String: Any] {
                    enabled.removeValue(forKey: pluginID)
                    settings["enabledPlugins"] = enabled
                    try writeDict(settings, to: settingsURL)
                }
                return ClaudeCLI.CommandResult(exitCode: 0, stdout: "Uninstalled", stderr: "")
            }

            return ClaudeCLI.CommandResult(exitCode: 1, stdout: "", stderr: "unexpected command: \(args)")
        }
    }

    @Test func generatedPluginFilesAreByteStableAndSkipUnchangedWrites() throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let hookCmd = AgentIntegration.hookCommand(executable: appProgram, agent: .claudeCode)
        let first = try AgentPlugins.claudeMarketplaceFiles(program: appProgram, hookCommand: hookCmd)
        let second = try AgentPlugins.claudeMarketplaceFiles(program: appProgram, hookCommand: hookCmd)
        #expect(first == second)
        #expect(first.map(\.relativePath) == [
            ".claude-plugin/marketplace.json",
            "plugins/vitruvian-speaker/.claude-plugin/plugin.json",
            "plugins/vitruvian-speaker/hooks/hooks.json",
            "plugins/vitruvian-speaker/skills/vitruvian-speaker/SKILL.md",
            "plugins/vitruvian-speaker/bin/speaker-broadcast",
        ])

        let antiA = try AgentPlugins.antigravityFiles(command: hookCmd)
        let antiB = try AgentPlugins.antigravityFiles(command: hookCmd)
        #expect(antiA.count == 3)
        for (a, b) in zip(antiA, antiB) {
            #expect(a.0 == b.0)
            #expect(a.1 == b.1)
        }
        #expect(AgentPlugins.openCodeSkillData() == AgentPlugins.openCodeSkillData())

        let integration = AgentIntegration(home: root, executablePath: appProgram)
        let dest = root.appendingPathComponent("test/file.sh")
        let didWrite = try integration.writeFileIfChanged(at: dest, data: Data("#!/bin/sh\n".utf8), isExecutable: true)
        let didRewrite = try integration.writeFileIfChanged(at: dest, data: Data("#!/bin/sh\n".utf8), isExecutable: true)
        #expect(didWrite)
        #expect(!didRewrite)
    }

    @Test func claudeCodePluginInstallsMigratesUpdatesAndUninstallsInScratchHome() throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)

        // Pre-populate legacy Stop hook + unrelated user hook + legacy CLAUDE.md line
        let legacyHook = AgentIntegration.mergeHook(
            into: ["hooks": ["Stop": [["hooks": [["type": "command", "command": "/bin/echo user", "timeout": 5]]]]]],
            command: "\"/Old/VitruvianSpeaker\" --claude-stop-hook",
            agent: .claudeCode
        )
        let legacyData = try JSONSerialization.data(withJSONObject: legacyHook, options: [.prettyPrinted])
        let settingsURL = CodingAgent.claudeCode.settingsURL(home: root)
        try legacyData.write(to: settingsURL)

        let claudeMd = root.appendingPathComponent(".claude/CLAUDE.md")
        try "# User notes\n- Follow the `vitruvian-speaker-broadcast` skill: read `~/.gemini/speaker_broadcast.json` and run `speaker-broadcast`.\n".write(to: claudeMd, atomically: true, encoding: .utf8)

        let fakeCLI = FakeClaudeCLI(home: root)
        let integration = AgentIntegration(home: root, executablePath: appProgram, claudeCLI: fakeCLI.runner)

        // Install plugin -> migrates Stop hook out of settings.json, strips instruction line, writes 0755 shim
        try integration.installHook(for: .claudeCode)

        #expect(fakeCLI.calls == [
            ["plugin", "marketplace", "add", integration.claudeMarketplaceDirectory.path],
            ["plugin", "install", AgentPlugins.claudePluginID],
        ])

        let status = integration.status(of: .claudeCode)
        #expect(status.hook == .installed)
        #expect(!status.usingSettingsFallback)

        // Old Stop hook removed while unrelated user hook survived
        let afterSettings = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        #expect(AgentIntegration.installedHookCommand(in: afterSettings ?? [:], agent: .claudeCode) == nil)
        let stopGroups = ((afterSettings?["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]) ?? []
        let userCmd = stopGroups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
        #expect(userCmd == ["/bin/echo user"])

        // Legacy CLAUDE.md instruction removed
        #expect(try String(contentsOf: claudeMd, encoding: .utf8) == "# User notes\n")

        // Verify bin/speaker-broadcast shim content + executable permissions
        let shimURL = integration.claudeMarketplaceDirectory.appendingPathComponent("plugins/vitruvian-speaker/bin/speaker-broadcast")
        #expect(fm.isExecutableFile(atPath: shimURL.path))
        let shimText = try String(contentsOf: shimURL, encoding: .utf8)
        #expect(shimText.contains(BroadcastCommand.explicitInvocationFlag))
        #expect(shimText.contains(appProgram))

        // Update from moved app path rewrites files in place WITHOUT re-running marketplace add/install
        let movedApp = "/Users/someone/Downloads/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker"
        let movedIntegration = AgentIntegration(
            home: root,
            executablePath: movedApp,
            claudeCLI: fakeCLI.runner,
            dataFolder: integration.dataFolder
        )
        #expect(movedIntegration.status(of: .claudeCode).hook == .stale(integration.hookCommand(for: .claudeCode)))
        let callsBeforeUpdate = fakeCLI.calls.count
        try movedIntegration.installHook(for: .claudeCode)
        #expect(fakeCLI.calls.count == callsBeforeUpdate, "same marketplace location updates bytes in place")
        #expect(movedIntegration.status(of: .claudeCode).hook == .installed)
        #expect(try String(contentsOf: shimURL, encoding: .utf8).contains(movedApp))

        // Removing / toggling off uninstalls plugin + removes marketplace + cleans marketplace directory
        try movedIntegration.removeHook(for: .claudeCode)
        #expect(fakeCLI.calls.suffix(2) == [
            ["plugin", "uninstall", AgentPlugins.claudePluginID],
            ["plugin", "marketplace", "remove", AgentPlugins.claudeMarketplaceName],
        ])
        #expect(!fm.fileExists(atPath: movedIntegration.claudeMarketplaceDirectory.path))
        #expect(movedIntegration.status(of: .claudeCode).hook == .notInstalled)
    }

    @Test func claudeCodeFallsBackWithoutCLIAndAutoMigratesWhenCLIAppears() throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let fakeCLI = FakeClaudeCLI(home: root, available: false)
        let withoutCLI = AgentIntegration(home: root, executablePath: appProgram, claudeCLI: fakeCLI.runner)

        try withoutCLI.installHook(for: .claudeCode)
        let fallbackStatus = withoutCLI.status(of: .claudeCode)
        #expect(fallbackStatus.hook == .installed)
        #expect(fallbackStatus.usingSettingsFallback)

        // Once claude CLI is available, fallback status is .stale and syncPlugins migrates cleanly
        fakeCLI.available = true
        let withCLI = AgentIntegration(home: root, executablePath: appProgram, claudeCLI: fakeCLI.runner)
        #expect(withCLI.status(of: .claudeCode).hook == .stale(withCLI.hookCommand(for: .claudeCode)))

        var claudeConfig = SpeakerConfig(enabled: true)
        claudeConfig.setAnnounces(.claudeCode, true)
        withCLI.syncPlugins(config: claudeConfig, installMissing: true, choice: .app)
        let migratedStatus = withCLI.status(of: .claudeCode)
        #expect(migratedStatus.hook == .installed)
        #expect(!migratedStatus.usingSettingsFallback)
    }

    @Test func antigravityAndOpenCodeSkillsInstallUpdateAndRemoveWithToggle() throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent(".gemini/config"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".config/opencode"), withIntermediateDirectories: true)

        let integration = AgentIntegration(home: root, executablePath: appProgram)
        var config = SpeakerConfig(enabled: true)
        config.setAnnounces(.antigravity, true)
        config.setAnnounces(.opencode, true)
        integration.syncPlugins(config: config, installMissing: true, choice: .app)

        let antiSkill = root.appendingPathComponent(".gemini/config/plugins/vitruvian-speaker/skills/vitruvian-speaker/SKILL.md")
        let openSkill = root.appendingPathComponent(AgentPlugins.openCodeSkillRelativePath)
        #expect(try String(contentsOf: antiSkill, encoding: .utf8) == SpeakerSkill.markdown())
        #expect(try String(contentsOf: openSkill, encoding: .utf8) == SpeakerSkill.markdown())
        #expect(integration.status(of: .antigravity).hook == .installed)
        #expect(integration.status(of: .opencode).hook == .installed)

        // Modifying or removing SKILL.md makes status .stale and syncPlugins restores it
        try fm.removeItem(at: openSkill)
        #expect(integration.status(of: .opencode).hook == .stale(integration.hookCommand(for: .opencode)))
        integration.syncPlugins(config: config, installMissing: true, choice: .app)
        #expect(integration.status(of: .opencode).hook == .installed)

        // Turning off toggles removes plugins & skills on sync
        config.setAnnounces(.antigravity, false)
        config.setAnnounces(.opencode, false)
        integration.syncPlugins(config: config, installMissing: true, choice: .app)
        #expect(!fm.fileExists(atPath: CodingAgent.antigravity.settingsURL(home: root).path))
        #expect(!fm.fileExists(atPath: CodingAgent.opencode.settingsURL(home: root).path))
        #expect(!fm.fileExists(atPath: openSkill.path))
    }

    @Test func claudeCLILocatesExecutableInScratchHomeWithoutSystemFallback() throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        let runner = ClaudeCLIRunner.scopedToHome(root)
        #expect(!runner.isAvailable)

        let nvmBin = root.appendingPathComponent(".nvm/versions/node/v22.2.0/bin")
        try fm.createDirectory(at: nvmBin, withIntermediateDirectories: true)
        let nvmClaude = nvmBin.appendingPathComponent("claude")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: nvmClaude)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nvmClaude.path)

        #expect(runner.findExecutable() == nvmClaude.path)

        let localBin = root.appendingPathComponent(".local/bin")
        try fm.createDirectory(at: localBin, withIntermediateDirectories: true)
        let localClaude = localBin.appendingPathComponent("claude")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: localClaude)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localClaude.path)

        #expect(runner.findExecutable() == localClaude.path, "native ~/.local/bin takes precedence over nvm")
    }
}
