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
import VitruvianCodeCore
import VitruvianToolKit
import VitruvianToolProtocol

/// The tool's two pages, as pure functions of what the tool knows: the app
/// draws them, in its own style, from the blocks. The ids are the blocks a
/// person can act on; `VitruvianCodeTool` answers each.
public enum Pages {
    /// What the island page and the top of the settings panel say.
    public struct Status: Equatable, Sendable {
        public var isRunning = false
        public var pid: Int32?
        /// Why the bot could not start or the settings be saved, in words.
        public var problem: String?
        public var needsRestart = false
        public var replyStreaming = false
        public var awaitingApproval = false
        /// The first line of the agent's last reply, if any.
        public var lastReply: String?
        /// Recent conversations, newest first, as the chat lists them.
        public var sessions: [VitruvianCodeSessionSummary] = []

        public init() {}
    }

    public static let maxSessionRows = 10
    public static let maxTitleLength = 80

    public enum Block {
        public static let open = "open"
        public static let newChat = "newChat"
        public static let startBot = "startBot"
        public static let stopBot = "stopBot"
        public static let restartBot = "restartBot"
        public static let openLog = "openLog"
        public static let sessions = "sessions"
        public static let token = "token"
        public static let allowedUsers = "allowedUsers"
        public static let workingFolder = "workingFolder"
        public static let chooseFolder = "chooseFolder"
        public static let approval = "approval"
        public static let model = "model"
        public static let effort = "effort"
        public static let save = "save"
        public static let mcpServers = "mcpServers"
        public static let mcpAdd = "mcpAdd"
        public static let mcpName = "mcpName"
        public static let mcpTransport = "mcpTransport"
        public static let mcpCommand = "mcpCommand"
        public static let mcpArguments = "mcpArguments"
        public static let mcpURL = "mcpURL"
        public static let mcpSecret = "mcpSecret"
        public static let mcpClearSecrets = "mcpClearSecrets"
        public static let mcpEnabled = "mcpEnabled"
        public static let mcpSaveServer = "mcpSaveServer"
        public static let mcpRemove = "mcpRemove"
        public static let mcpCancel = "mcpCancel"
    }

    /// The MCP part of the settings panel: the app's servers, and the one being edited.
    public struct MCP: Equatable, Sendable {
        public var servers: [AgentMCPServer] = []
        /// The server being edited or added; nil shows the list alone.
        public var draft: AgentMCPServerDraft?
        /// The names of the secrets the draft will keep (stored or newly typed), never a value.
        public var secretNames: [String] = []
        /// Why the last Save of the draft did not happen.
        public var problem: AgentMCPServerDraft.Problem?
        /// The draft's secrets could not be written.
        public var saveFailed = false

        public init(servers: [AgentMCPServer] = [], draft: AgentMCPServerDraft? = nil, secretNames: [String] = [],
                    problem: AgentMCPServerDraft.Problem? = nil, saveFailed: Bool = false) {
            self.servers = servers
            self.draft = draft
            self.secretNames = secretNames
            self.problem = problem
            self.saveFailed = saveFailed
        }
    }

    // MARK: - The island page

    public static func island(_ status: Status, language: String) -> UITree {
        let word = { (key: String) in Words.text(key, language) }
        return UITree {
            heading("Vitruvian Code")
            button(Block.open, UIText.plain(word("openQuickPrompt")), style: .prominent)
            button(Block.newChat, UIText.plain(word("newChat")))
            if status.awaitingApproval {
                text(UIText.plain(word("awaitingApproval")), style: .secondary)
            } else if status.replyStreaming {
                text(UIText.plain(word("replyStreaming")), style: .secondary)
            } else if let reply = status.lastReply {
                text(UIText.plain("\(word("lastReply")): \(cut(reply))"), style: .secondary, lines: 2)
            }
            divider()
            row(nil, UIText.plain(word("bot")), subtitle: UIText.plain(botLine(status, language: language)),
                icon: status.isRunning ? "paperplane.fill" : "paperplane")
            if status.isRunning {
                button(Block.stopBot, UIText.plain(word("stop")))
            } else {
                button(Block.startBot, UIText.plain(word("start")))
            }
            if let problem = status.problem {
                text(UIText.plain(problem), style: .caption)
            }
            if !status.sessions.isEmpty {
                divider()
                text(UIText.plain(word("recentSessions")), style: .caption)
                list(Block.sessions, sessionRows(status.sessions, language: language))
            }
        }
    }

    /// The bot's state as one line: "Running · PID 123" or "Stopped".
    public static func botLine(_ status: Status, language: String) -> String {
        guard status.isRunning else { return Words.text("statusStopped", language) }
        return status.pid.map { "\(Words.text("statusRunning", language)) · PID \($0)" }
            ?? Words.text("statusRunning", language)
    }

    /// The newest sessions, at most ten, titles cut to 80 characters.
    public static func sessionRows(_ sessions: [VitruvianCodeSessionSummary], language: String) -> [UIListRow] {
        sessions.prefix(maxSessionRows).map { summary in
            let title = summary.title.isEmpty ? Words.text("untitledSession", language) : summary.title
            return UIListRow(id: summary.id, title: UIText.plain(cut(title)),
                             subtitle: summary.preview.isEmpty ? nil : UIText.plain(cut(summary.preview)),
                             icon: "bubble.left")
        }
    }

    static func cut(_ text: String) -> String {
        let line = text.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text
        return line.count > maxTitleLength ? String(line.prefix(maxTitleLength - 1)) + "…" : line
    }

    // MARK: - The settings panel

    /// The most log lines the panel shows: the protocol's most for a text.
    public static let logPreviewLines = UILimits.maxTextLines

    /// The bot's status and log, and the part of its `.env` a person
    /// changes, with Save. The bot folder, start at launch, plan mode and
    /// worktree mode are the app's own fields, above this panel.
    ///
    /// The token is a secret: the page never carries it back to the app.
    /// Its field is empty, with dots for a placeholder when one is set, and
    /// an empty answer leaves the token as it was.
    ///
    /// `supportsChoice` and `supportsSections` are what the app said it has
    /// (`ui.choice`, `ui.sections`): with the first, the approval mode and
    /// the effort are pop-up menus rather than lists; with the second, the
    /// configuration heading starts a section and the fields carry their
    /// captions as help. An app without them gets the page it always had.
    public static func settings(_ status: Status, draft: VitruvianCodeConfiguration, saved: VitruvianCodeConfiguration,
                                logLines: [String], language: String, supportsChoice: Bool = false,
                                supportsSections: Bool = false, mcp: MCP? = nil) -> UITree {
        let word = { (key: String) in Words.text(key, language) }
        let help = { (key: String) in supportsSections ? UIText.plain(word(key)) : nil }
        return UITree {
            row(nil, UIText.plain(word("bot")), subtitle: UIText.plain(botLine(status, language: language)),
                icon: status.isRunning ? "paperplane.fill" : "paperplane")
            if status.isRunning {
                button(Block.restartBot, UIText.plain(word("restart")))
                button(Block.stopBot, UIText.plain(word("stop")))
            } else {
                button(Block.startBot, UIText.plain(word("start")))
            }
            if let problem = status.problem {
                text(UIText.plain(problem), style: .caption)
            }
            if status.needsRestart {
                text(UIText.plain(word("savedRestartHint")), style: .caption)
            }
            text(UIText.plain(word("recentLog")), style: .caption)
            text(UIText.plain(logLines.isEmpty ? word("logEmpty")
                    : logLines.suffix(logPreviewLines).joined(separator: "\n")),
                 style: .monospaced, lines: logPreviewLines)
            button(Block.openLog, UIText.plain(word("openLog")))
            divider()
            heading(UIText.plain(word("configurationSection")), section: supportsSections ? true : nil)
            field(Block.token, title: UIText.plain(word("token")), value: "",
                  placeholder: draft.botToken.isEmpty ? nil : UIText.plain("••••••••"), kind: .secret,
                  help: help("tokenCaption"))
            if !supportsSections { text(UIText.plain(word("tokenCaption")), style: .caption) }
            field(Block.allowedUsers, title: UIText.plain(word("allowedUsers")), value: draft.allowedUserIDs,
                  help: help("allowedUsersCaption"))
            if !supportsSections { text(UIText.plain(word("allowedUsersCaption")), style: .caption) }
            field(Block.workingFolder, title: UIText.plain(word("workingFolder")), value: draft.workingDirectory,
                  help: help("workingFolderCaption"))
            button(Block.chooseFolder, UIText.plain(word("choose")))
            if !supportsSections { text(UIText.plain(word("workingFolderCaption")), style: .caption) }
            if supportsChoice {
                choice(Block.approval, title: UIText.plain(word("approvalMode")), value: draft.approvalMode.rawValue,
                       options: VitruvianCodeApprovalMode.globalChoices.map { mode in
                           UIChoiceOption(value: mode.rawValue, title: UIText.plain(approvalName(mode, language: language)))
                       })
            } else {
                text(UIText.plain(word("approvalMode")), style: .secondary)
                list(Block.approval, VitruvianCodeApprovalMode.globalChoices.map { mode in
                    UIListRow(id: mode.rawValue, title: UIText.plain(approvalName(mode, language: language)),
                              trailing: mode == draft.approvalMode ? "✓" : nil)
                })
            }
            field(Block.model, title: UIText.plain(word("model")), value: draft.model,
                  placeholder: UIText.plain(word("modelPlaceholder")))
            if supportsChoice {
                choice(Block.effort, title: UIText.plain(word("effort")), value: effortValue(draft),
                       options: effortRows(draft, language: language).map { UIChoiceOption(value: $0.id, title: $0.title) })
            } else {
                text(UIText.plain(word("effort")), style: .secondary)
                list(Block.effort, effortRows(draft, language: language))
            }
            button(Block.save, UIText.plain(word("save")), style: .prominent, enabled: draft != saved)
            text(UIText.plain(word("notInstalledHere")), style: .caption)
            if let mcp {
                mcpBlocks(mcp, language: language, supportsChoice: supportsChoice, supportsSections: supportsSections)
            }
        }
    }

    /// The MCP servers: a row for each (tapping one edits it), Add, and the editor when a draft
    /// is open. A secret is never carried back: its field is empty, and the names kept are listed.
    public static func mcpBlocks(_ mcp: MCP, language: String, supportsChoice: Bool,
                                 supportsSections: Bool) -> [UIBlock] {
        let word = { (key: String) in Words.text(key, language) }
        return UITree {
            divider()
            heading(UIText.plain(word("mcpSection")), section: supportsSections ? true : nil)
            text(UIText.plain(word("mcpCaption")), style: .caption)
            if mcp.servers.isEmpty {
                text(UIText.plain(word("mcpNone")), style: .secondary)
            } else {
                list(Block.mcpServers, mcp.servers.prefix(UILimits.maxListRows).map { server in
                    let from = server.source == .claudeCode ? " · \(word("mcpFromClaudeCode"))" : ""
                    return UIListRow(id: server.id.uuidString, title: UIText.plain(cut(server.name)),
                                     subtitle: UIText.plain(cut(server.summary + from)),
                                     icon: server.transport == .http ? "globe" : "terminal",
                                     trailing: UIText.plain(word(server.isEnabled ? "mcpOn" : "mcpOff")))
                })
            }
            if let draft = mcp.draft {
                field(Block.mcpName, title: UIText.plain(word("mcpName")), value: draft.name)
                if supportsChoice {
                    choice(Block.mcpTransport, title: UIText.plain(word("mcpTransport")), value: draft.transport.rawValue,
                           options: AgentMCPServer.Transport.allCases.map { transport in
                               UIChoiceOption(value: transport.rawValue, title: UIText.plain(transportName(transport, language: language)))
                           })
                } else {
                    text(UIText.plain(word("mcpTransport")), style: .secondary)
                    list(Block.mcpTransport, AgentMCPServer.Transport.allCases.map { transport in
                        UIListRow(id: transport.rawValue, title: UIText.plain(transportName(transport, language: language)),
                                  trailing: transport == draft.transport ? "✓" : nil)
                    })
                }
                switch draft.transport {
                case .stdio:
                    field(Block.mcpCommand, title: UIText.plain(word("mcpCommand")), value: draft.command,
                          placeholder: UIText.plain("npx"))
                    field(Block.mcpArguments, title: UIText.plain(word("mcpArguments")), value: draft.argumentsLine,
                          placeholder: UIText.plain("-y @modelcontextprotocol/server-filesystem ."))
                case .http:
                    field(Block.mcpURL, title: UIText.plain(word("mcpURL")), value: draft.url,
                          placeholder: UIText.plain("https://example.com/mcp"))
                }
                field(Block.mcpSecret,
                      title: UIText.plain(word(draft.transport == .stdio ? "mcpSecretEnvironment" : "mcpSecretHeader")),
                      value: "", placeholder: UIText.plain("NAME=value"), kind: .secret,
                      help: supportsSections ? UIText.plain(word("mcpSecretCaption")) : nil)
                if !supportsSections { text(UIText.plain(word("mcpSecretCaption")), style: .caption) }
                if !mcp.secretNames.isEmpty {
                    text(UIText.plain("\(word("mcpSecretsKept")) \(mcp.secretNames.joined(separator: ", "))"), style: .caption)
                    button(Block.mcpClearSecrets, UIText.plain(word("mcpClearSecrets")))
                }
                toggle(Block.mcpEnabled, UIText.plain(word("mcpEnabled")), isOn: draft.isEnabled)
                if let problem = mcp.problem {
                    text(UIText.plain(problemText(problem, language: language)), style: .caption)
                } else if mcp.saveFailed {
                    text(UIText.plain(word("mcpSaveFailed")), style: .caption)
                }
                button(Block.mcpSaveServer, UIText.plain(word("mcpSaveServer")), style: .prominent)
                if draft.id != nil { button(Block.mcpRemove, UIText.plain(word("mcpRemove"))) }
                button(Block.mcpCancel, UIText.plain(word("mcpCancel")))
            } else {
                button(Block.mcpAdd, UIText.plain(word("mcpAdd")))
            }
        }.blocks
    }

    public static func transportName(_ transport: AgentMCPServer.Transport, language: String) -> String {
        switch transport {
        case .stdio: return Words.text("mcpTransportStdio", language)
        case .http: return Words.text("mcpTransportHTTP", language)
        }
    }

    public static func problemText(_ problem: AgentMCPServerDraft.Problem, language: String) -> String {
        switch problem {
        case .emptyName: return Words.text("mcpProblemName", language)
        case .duplicateName: return Words.text("mcpProblemDuplicate", language)
        case .missingCommand: return Words.text("mcpProblemCommand", language)
        case .invalidURL: return Words.text("mcpProblemURL", language)
        case .invalidSecretName: return Words.text("mcpProblemSecret", language)
        }
    }

    /// A typed secret, `NAME=value`, as its name and value; nil when it has no name.
    public static func secretEntry(_ text: String) -> (name: String, value: String)? {
        guard let equals = text.firstIndex(of: "=") else { return nil }
        let name = text[text.startIndex..<equals].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return (name, String(text[text.index(after: equals)...]))
    }

    public static func approvalName(_ mode: VitruvianCodeApprovalMode, language: String) -> String {
        switch mode {
        case .yolo: return Words.text("approvalYolo", language)
        case .acceptEdits: return Words.text("approvalAcceptEdits", language)
        case .plan: return Words.text("approvalPlan", language)
        case .standard, .auto: return Words.text("approvalDefault", language)
        }
    }

    public static func effortName(_ effort: VitruvianCodeEffort, language: String) -> String {
        switch effort {
        case .automatic: return Words.text("effortAutomatic", language)
        case .low: return Words.text("effortLow", language)
        case .medium: return Words.text("effortMedium", language)
        case .high: return Words.text("effortHigh", language)
        case .max: return Words.text("effortMax", language)
        }
    }

    /// One row per effort, and one more for a word the file has that is
    /// none of them (`xhigh`), shown as itself, as the app's page did.
    public static func effortRows(_ draft: VitruvianCodeConfiguration, language: String) -> [UIListRow] {
        var rows = VitruvianCodeEffort.allCases.map { effort in
            UIListRow(id: effort.rawValue.isEmpty ? "automatic" : effort.rawValue,
                      title: UIText.plain(effortName(effort, language: language)),
                      trailing: draft.effortChoice == effort.rawValue ? "✓" : nil)
        }
        if let written = draft.unnamedEffort {
            rows.append(UIListRow(id: "written:" + written, title: UIText.plain("\(written) (from .env)"), trailing: "✓"))
        }
        return rows
    }

    /// The id of the effort row the draft has chosen: the menu's value.
    public static func effortValue(_ draft: VitruvianCodeConfiguration) -> String {
        if let written = draft.unnamedEffort { return "written:" + written }
        return draft.effortChoice.isEmpty ? "automatic" : draft.effortChoice
    }

    /// The effort a tapped row stands for: the row's id, or the file's own
    /// word for the row that shows it.
    public static func effortChoice(ofRow id: String) -> String {
        if id == "automatic" { return "" }
        if id.hasPrefix("written:") { return String(id.dropFirst("written:".count)) }
        return id
    }
}
