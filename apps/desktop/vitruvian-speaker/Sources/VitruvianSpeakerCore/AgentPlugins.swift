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

/// The plugin files Vitruvian Speaker writes for Antigravity and OpenCode. Each
/// is generated from the hook command alone, so the same program always
/// gives the same bytes: Settings compares them to tell an installed plugin
/// from one an older Vitruvian Speaker wrote (shown as "Update").
public enum AgentPlugins {
    /// The plugin's name across supported coding agents.
    public static let name = "vitruvian-speaker"

    /// A generated file inside a plugin or local marketplace directory.
    public struct GeneratedPluginFile: Equatable, Sendable {
        public var relativePath: String
        public var data: Data
        public var isExecutable: Bool

        public init(relativePath: String, data: Data, isExecutable: Bool = false) {
            self.relativePath = relativePath
            self.data = data
            self.isExecutable = isExecutable
        }
    }

    // MARK: speaker-broadcast, per agent

    /// Where each plugin keeps its copy of `speaker-broadcast`, relative to
    /// the plugin's (or OpenCode skill's) own folder.
    public static let commandRelativePath = "bin/\(BroadcastCommand.commandName)"

    /// The `speaker-broadcast` script a plugin carries: it runs `program`
    /// (the app's, or the extension's `bin/tool`) as the broadcast command.
    public static func broadcastShim(program: String) -> Data {
        Data("#!/bin/sh\nexec \(shellSingleQuote(program)) \(BroadcastCommand.explicitInvocationFlag) \"$@\"\n".utf8)
    }

    /// How the skill installed for `agent` must run `speaker-broadcast`.
    ///
    /// Only Claude Code puts a plugin's `bin/` on its Bash PATH, so only its
    /// skill may say the bare name. Every other agent is told the absolute
    /// path of the copy the app wrote in `pluginFolder` (removed with it),
    /// so the skill works whatever the user's PATH is and with no
    /// `~/.local/bin`. Generated from the same place the copy is written,
    /// so the two cannot drift.
    public static func skillCommand(for agent: CodingAgent, pluginFolder: URL?) -> String {
        guard !agent.putsPluginBinOnPATH, let pluginFolder else { return BroadcastCommand.commandName }
        return shellWord(pluginFolder.appendingPathComponent(commandRelativePath).standardizedFileURL.path)
    }

    /// `value` as one shell word: as is when it needs no quoting, else single-quoted.
    static func shellWord(_ value: String) -> String {
        let plain = value.range(of: "^[A-Za-z0-9_./+:@%-]+$", options: .regularExpression) != nil
        return plain ? value : shellSingleQuote(value)
    }

    // MARK: Claude Code

    public static let claudeMarketplaceName = name
    public static let claudePluginID = "\(name)@\(claudeMarketplaceName)"

    /// Generates all files for Speaker's local Claude Code marketplace and plugin.
    public static func claudeMarketplaceFiles(program: String, hookCommand: String) throws -> [GeneratedPluginFile] {
        let description = "Speaks each finished Claude Code reply on your Google Home speakers or this Mac, through Vitruvian Speaker."
        let author: [String: Any] = [
            "name": "VitruvianSoftware",
            "url": "https://github.com/VitruvianSoftware",
        ]
        let marketplace: [String: Any] = [
            "name": claudeMarketplaceName,
            "owner": author,
            "metadata": ["description": "Vitruvian Speaker integration for Claude Code."],
            "plugins": [[
                "name": name,
                "source": "./plugins/\(name)",
                "description": description,
                "author": author,
                "license": "MIT",
            ]],
        ]
        let pluginManifest: [String: Any] = [
            "name": name,
            "version": "1.0.0",
            "description": description,
            "author": author,
            "license": "MIT",
        ]
        let hooks: [String: Any] = [
            "hooks": [
                "Stop": [[
                    "hooks": [[
                        "type": "command",
                        "command": hookCommand,
                        "timeout": 10,
                    ]],
                ]],
            ],
        ]
        return [
            GeneratedPluginFile(relativePath: ".claude-plugin/marketplace.json", data: try json(marketplace)),
            GeneratedPluginFile(relativePath: "plugins/\(name)/.claude-plugin/plugin.json", data: try json(pluginManifest)),
            GeneratedPluginFile(relativePath: "plugins/\(name)/hooks/hooks.json", data: try json(hooks)),
            GeneratedPluginFile(
                relativePath: "plugins/\(name)/skills/\(name)/SKILL.md",
                data: Data(SpeakerSkill.markdown(command: skillCommand(for: .claudeCode, pluginFolder: nil)).utf8)
            ),
            GeneratedPluginFile(relativePath: "plugins/\(name)/\(commandRelativePath)", data: broadcastShim(program: program), isExecutable: true),
        ]
    }

    // MARK: Antigravity

    public static let antigravityManifestFile = "plugin.json"
    public static let antigravityHooksFile = "hooks.json"
    public static let antigravitySkillFile = "skills/\(name)/SKILL.md"

    public static let antigravityCommandFile = commandRelativePath

    /// `plugin.json`, `hooks.json`, `skills/vitruvian-speaker/SKILL.md` and
    /// `bin/speaker-broadcast` for `folder`
    /// (`~/.gemini/config/plugins/vitruvian-speaker/`). Antigravity enables a
    /// plugin it finds there unless its `config.json` says `"enabled": false`
    /// for it. Its `Stop` event takes a flat list of handlers (no `matcher`),
    /// its timeout is in seconds, and the command runs through `sh -c`.
    /// Antigravity does not put the plugin's `bin/` on PATH, so the skill
    /// names that copy by its absolute path.
    public static func antigravityFiles(command: String, program: String, folder: URL) throws -> [GeneratedPluginFile] {
        let manifest: [String: Any] = [
            "name": name,
            "version": "1.0.0",
            "description": "Speaks each finished Antigravity reply on your Google Home speakers or this Mac, through Vitruvian Speaker.",
            "author": ["name": "VitruvianSoftware", "url": "https://github.com/VitruvianSoftware"],
            "license": "MIT",
        ]
        let hooks: [String: Any] = [
            name: ["Stop": [["type": "command", "command": command, "timeout": 10]]],
        ]
        let skill = SpeakerSkill.markdown(command: skillCommand(for: .antigravity, pluginFolder: folder))
        return [
            GeneratedPluginFile(relativePath: antigravityManifestFile, data: try json(manifest)),
            GeneratedPluginFile(relativePath: antigravityHooksFile, data: try json(hooks)),
            GeneratedPluginFile(relativePath: antigravitySkillFile, data: Data(skill.utf8)),
            GeneratedPluginFile(relativePath: antigravityCommandFile, data: broadcastShim(program: program), isExecutable: true),
        ]
    }

    public static func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The command of the Vitruvian Speaker `Stop` handler in an Antigravity
    /// `hooks.json`, whichever named hook holds it, in the flat form or a
    /// `matcher` group; nil when there is none.
    public static func antigravityCommand(inHooks data: Data) -> String? {
        guard let specs = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for case let spec as [String: Any] in specs.values {
            for item in (spec["Stop"] as? [[String: Any]]) ?? [] {
                let handlers = (item["hooks"] as? [[String: Any]]) ?? [item]
                for handler in handlers {
                    if let command = handler["command"] as? String, AgentIntegration.isOurs(command) { return command }
                }
            }
        }
        return nil
    }

    private static func json(_ object: Any) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    // MARK: OpenCode

    /// The skill's folder, relative to the home folder. OpenCode loads
    /// `SKILL.md` from it; the app also keeps the skill's `speaker-broadcast`
    /// there, so removing the folder removes both.
    public static let openCodeSkillFolderRelativePath = ".config/opencode/skills/\(name)"
    public static let openCodeSkillRelativePath = "\(openCodeSkillFolderRelativePath)/SKILL.md"

    /// `SKILL.md` and `bin/speaker-broadcast`, relative to the home folder.
    /// OpenCode does not put a skill's `bin/` on PATH, so the skill names
    /// that copy by its absolute path.
    public static func openCodeSkillFiles(program: String, home: URL) -> [GeneratedPluginFile] {
        let folder = home.appendingPathComponent(openCodeSkillFolderRelativePath, isDirectory: true)
        let skill = SpeakerSkill.markdown(command: skillCommand(for: .opencode, pluginFolder: folder))
        return [
            GeneratedPluginFile(relativePath: openCodeSkillRelativePath, data: Data(skill.utf8)),
            GeneratedPluginFile(relativePath: "\(openCodeSkillFolderRelativePath)/\(commandRelativePath)", data: broadcastShim(program: program), isExecutable: true),
        ]
    }

    /// The line that records the hook command in the plugin file.
    static let openCodeCommandPrefix = "// Command: "

    /// `~/.config/opencode/plugins/vitruvian-speaker.ts`. OpenCode 2.x requires a
    /// default export with `{ id, setup(ctx) }`. On `session.idle` of a
    /// top-level session (`event.data.sessionID`, or `event.properties.sessionID`
    /// in 1.x), it reads the session's active context messages through
    /// `ctx.session.context({ sessionID })` and pipes them to
    /// `<program> --opencode-hook`, detached, so OpenCode never waits on it.
    /// Any failure is swallowed: a plugin that throws must never break the agent.
    public static func openCodePlugin(program: String) -> String {
        let command = AgentIntegration.hookCommand(executable: program, agent: .opencode)
        let quoted = String(data: (try? JSONSerialization.data(
            withJSONObject: program, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data(), encoding: .utf8) ?? "\"\""
        return """
        // Vitruvian Speaker: speaks each finished OpenCode reply on your Google Home
        // speakers or this Mac. Written by Vitruvian Speaker; install, update or
        // remove it from Vitruvian Speaker's Settings, AI Agents.
        \(openCodeCommandPrefix)\(command)
        import { spawn } from "node:child_process"

        const PROGRAM = \(quoted)
        const MESSAGES = 40

        export default {
          id: "\(name)",
          setup(ctx) {
            const controller = new AbortController()

            void (async () => {
              try {
                for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
                  if (!event || event.type !== "session.idle") continue
                  const sessionID = (event.data && event.data.sessionID) || (event.properties && event.properties.sessionID)
                  if (!sessionID) continue
                  try {
                    const session = await ctx.session.get({ sessionID })
                    if (session && session.parentID) continue
                    const all = await ctx.session.context({ sessionID })
                    if (!Array.isArray(all) || all.length === 0) continue
                    const child = spawn(PROGRAM, ["\(OpenCodeHook.argument)"], {
                      stdio: ["pipe", "ignore", "ignore"],
                      detached: true,
                    })
                    child.on("error", () => {})
                    child.stdin.on("error", () => {})
                    child.stdin.end(JSON.stringify({ sessionID, messages: all.slice(-MESSAGES) }))
                    child.unref()
                  } catch {}
                }
              } catch {}
            })()

            return () => controller.abort()
          },
        }

        """
    }

    /// The hook command recorded in an OpenCode plugin file Vitruvian Speaker
    /// wrote; nil for any other file.
    public static func openCodeCommand(inPlugin text: String) -> String? {
        for line in text.split(separator: "\n").prefix(10) where line.hasPrefix(openCodeCommandPrefix) {
            let command = String(line.dropFirst(openCodeCommandPrefix.count))
            return AgentIntegration.isOurs(command) ? command : nil
        }
        return nil
    }
}
