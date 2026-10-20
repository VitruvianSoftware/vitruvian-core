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

/// The plugin files HomeSpeaker writes for Antigravity and OpenCode. Each
/// is generated from the hook command alone, so the same program always
/// gives the same bytes: Settings compares them to tell an installed plugin
/// from one an older HomeSpeaker wrote (shown as "Update").
public enum AgentPlugins {
    /// The plugin's name in both agents.
    public static let name = "home-speaker"

    // MARK: Antigravity

    public static let antigravityManifestFile = "plugin.json"
    public static let antigravityHooksFile = "hooks.json"

    /// `plugin.json` and `hooks.json` for `~/.gemini/config/plugins/home-speaker/`.
    /// Antigravity enables a plugin it finds there unless its `config.json`
    /// says `"enabled": false` for it, so nothing else is written. Its `Stop`
    /// event takes a flat list of handlers (no `matcher`), its timeout is
    /// in seconds, and the command runs through `sh -c`.
    public static func antigravityFiles(command: String) throws -> [(String, Data)] {
        let manifest: [String: Any] = [
            "name": name,
            "version": "1.0.0",
            "description": "Speaks each finished Antigravity reply on your Google Home speakers or this Mac, through HomeSpeaker.",
            "author": ["name": "VitruvianSoftware", "url": "https://github.com/VitruvianSoftware"],
            "license": "MIT",
        ]
        let hooks: [String: Any] = [
            name: ["Stop": [["type": "command", "command": command, "timeout": 10]]],
        ]
        return [
            (antigravityManifestFile, try json(manifest)),
            (antigravityHooksFile, try json(hooks)),
        ]
    }

    /// The command of the HomeSpeaker `Stop` handler in an Antigravity
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

    /// The line that records the hook command in the plugin file.
    static let openCodeCommandPrefix = "// Command: "

    /// `~/.config/opencode/plugins/home-speaker.ts`. OpenCode 2.x requires a
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
        // HomeSpeaker: speaks each finished OpenCode reply on your Google Home
        // speakers or this Mac. Written by HomeSpeaker; install, update or
        // remove it from HomeSpeaker's Settings, AI Agents.
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

    /// The hook command recorded in an OpenCode plugin file HomeSpeaker
    /// wrote; nil for any other file.
    public static func openCodeCommand(inPlugin text: String) -> String? {
        for line in text.split(separator: "\n").prefix(10) where line.hasPrefix(openCodeCommandPrefix) {
            let command = String(line.dropFirst(openCodeCommandPrefix.count))
            return AgentIntegration.isOurs(command) ? command : nil
        }
        return nil
    }
}
