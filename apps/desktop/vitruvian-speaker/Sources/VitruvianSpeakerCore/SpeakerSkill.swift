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

/// Single-source definition of the `vitruvian-speaker` agent skill (`SKILL.md`)
/// embedded in the Claude Code, Antigravity, and OpenCode plugins.
public enum SpeakerSkill {
    public static let name = "vitruvian-speaker"
    public static let description =
        "Speak concise voice summaries aloud on Google Home speakers, this Mac, or your phone with speaker-broadcast, and manage Vitruvian Speaker targets and settings."

    /// Renders the Commands & Options section directly from `BroadcastCommand.optionSpecs`
    /// so `SKILL.md` and `speaker-broadcast --help` cannot drift. `command` is
    /// how the agent reading the skill runs `speaker-broadcast` (see `markdown(command:)`).
    public static func commandsAndOptionsSection(command: String = BroadcastCommand.commandName) -> String {
        var lines = [
            "## Commands and options",
            "",
        ]
        for spec in BroadcastCommand.optionSpecs {
            let label = spec.isPositional ? "\(command) \(spec.syntax)" : spec.syntax
            lines.append("- `\(label)`: \(spec.summary)")
        }
        return lines.joined(separator: "\n")
    }

    /// The skill, telling the agent to run `speaker-broadcast` as `command`.
    ///
    /// `command` must be something that agent can actually run: the bare
    /// name only where the agent itself puts the plugin's `bin/` on its PATH
    /// (Claude Code), otherwise the absolute path of the copy the app wrote
    /// inside that agent's plugin (`AgentPlugins.skillCommand`). Nothing the
    /// app installs puts `speaker-broadcast` on any other agent's PATH.
    public static func markdown(command: String = BroadcastCommand.commandName) -> String {
        let isBare = command == BroadcastCommand.commandName
        let reach = isBare
            ? ""
            : "\n\nAlways run it by this full path, exactly as written here: `\(command)`. It is not on your PATH, so the bare name \(BroadcastCommand.commandName) will not be found."
        let frontmatter = """
        ---
        name: \(name)
        description: \(description)
        ---
        """

        let body = """
        # Vitruvian Speaker

        Use the speaker-broadcast command shipped by Vitruvian Speaker to deliver short spoken summaries and adjust broadcast settings.\(reach)

        ## When to speak

        - Accompany **top-level conversational replies** to the user with a brief spoken summary.
        - **Never** run `\(command)` from background subagents, delegated `claude -p` runs, or `agy` runs (the CLI also suppresses subagent environments automatically).
        - Stay silent if the user or prompt asks for quiet output or no speech.

        ## How to speak

        Run `\(command)` with 1 to 3 plain, natural sentences:

        ```sh
        \(command) "Finished the refactor and all unit tests pass."
        ```

        - Write everyday spoken phrasing: no code blocks, no Markdown syntax, no file paths, no raw git SHAs, and no URLs.
        - If `\(command)` is missing, Vitruvian Speaker isn't installed on this Mac — say so plainly rather than attempting manual smart-home device calls.

        ## Turning broadcasts on or off

        ```sh
        \(command) --on
        \(command) --off
        \(command) --toggle
        \(command) --status
        ```

        ## Switching speakers and overrides

        ```sh
        \(command) --list
        \(command) --set-target kitchen
        \(command) --target office "Deployment finished."
        \(command) --force "Urgent alert."
        \(command) --help
        ```

        \(commandsAndOptionsSection(command: command))

        ## Chat and Slack monitor

        Background chat announcements for Slack, Google Chat, Beeper, and Courier are built into Vitruvian Speaker itself (configured in Vitruvian Speaker Settings › Monitor), not invoked through speaker-broadcast.
        """

        return frontmatter + "\n\n" + body + "\n"
    }
}
