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
// copyright holder on 2026-10-08 (apps/desktop/vitruvian/UPSTREAM.md).

import Foundation

/// How much the agent may do without asking, as the bot's `AGY_APPROVAL_MODE`
/// spells it. The raw values are what the bot reads.
public enum NexusAgentApprovalMode: String, CaseIterable, Identifiable {
    case yolo
    case acceptEdits = "accept-edits"
    case plan
    case standard = "default"

    public var id: String { rawValue }

    /// The bot's own reading, and the bot is the authority: it is what runs.
    /// An absent key means yolo, the retired Gemini name and the underscore
    /// spelling mean accept-edits, and anything it does not know (an empty
    /// value included) asks agy for its default. Capitals do not matter to
    /// the bot, but spaces do: it does not trim, so ` plan ` (which only
    /// reaches it from inside quotes) is not a mode. Showing it as Plan here
    /// would promise something the bot will not do.
    ///
    /// The examples are shared with the bot's tests:
    /// `apps/desktop/nexus-agent/testdata/approval-modes.json`.
    public static func parse(_ raw: String?) -> NexusAgentApprovalMode {
        guard let raw else { return .yolo }
        switch raw.lowercased() {
        case "yolo": return .yolo
        case "auto_edit", "accept-edits", "accept_edits": return .acceptEdits
        case "plan": return .plan
        default: return .standard
        }
    }

    /// The agy flags for the mode, exactly as the bot passes them.
    public var agyArguments: [String] {
        switch self {
        case .yolo: return ["--dangerously-skip-permissions"]
        case .acceptEdits: return ["--mode", "accept-edits"]
        case .plan: return ["--mode", "plan"]
        case .standard: return []
        }
    }

    /// The Claude Code permission mode corresponding to this approval mode.
    public var claudePermissionMode: String {
        switch self {
        case .yolo: return "bypassPermissions"
        case .acceptEdits: return "acceptEdits"
        case .plan: return "plan"
        case .standard: return "default"
        }
    }
}

/// agy's `--effort`; `automatic` leaves the choice to agy.
public enum NexusAgentEffort: String, CaseIterable, Identifiable {
    case automatic = ""
    case low, medium, high, max

    public var id: String { rawValue }

    public static func parse(_ raw: String?) -> NexusAgentEffort {
        NexusAgentEffort(rawValue: (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased())
            ?? .automatic
    }
}

/// Represents a CLI backend that can handle prompts in Quick Prompt.
public struct NexusAgentCLIProvider: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var commandTemplate: String
    public var isBuiltIn: Bool

    public init(id: UUID, name: String, commandTemplate: String, isBuiltIn: Bool = true) {
        self.id = id
        self.name = name
        self.commandTemplate = commandTemplate
        self.isBuiltIn = isBuiltIn
    }

    public static let antigravity = NexusAgentCLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Antigravity CLI",
        commandTemplate: "agy -p \"{prompt}\" --output-format stream-json --dangerously-skip-permissions"
    )

    public static let claude = NexusAgentCLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Claude Code",
        commandTemplate: "claude -p \"{prompt}\""
    )

    public static let ollama = NexusAgentCLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Ollama (claude)",
        commandTemplate: "ollama launch claude --model {model} -- -p \"{prompt}\""
    )

    public static let opencode = NexusAgentCLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "OpenCode",
        commandTemplate: "opencode run --format json \"{prompt}\""
    )

    public static let builtIns: [NexusAgentCLIProvider] = [.antigravity, .claude, .ollama, .opencode]

    /// The providers a user can pick from, given what the app has saved.
    /// The four built in come first, in their fixed order, each with its
    /// saved command if the user edited it; its id and name stay as they
    /// are today, so a name saved by an older version does not come back.
    /// Then the user's own, in the order they were saved. An entry marked
    /// built-in that is not one of the four is left out: it is a provider
    /// a later version took away. A built-in's saved command is taken only
    /// from an entry that is itself marked built-in, as the standalone app
    /// reads it from its built-in list; an entry marked as the user's own
    /// that carries a built-in's id changes nothing and is not listed.
    public static func available(saved: [NexusAgentCLIProvider]) -> [NexusAgentCLIProvider] {
        let builtInIDs = Set(builtIns.map(\.id))
        let edited = builtIns.map { builtIn -> NexusAgentCLIProvider in
            var provider = builtIn
            // The last saved copy wins, as it does where the standalone app reads them.
            if let copy = saved.last(where: { $0.id == builtIn.id && $0.isBuiltIn }) {
                provider.commandTemplate = copy.commandTemplate
            }
            return provider
        }
        return edited + saved.filter { !$0.isBuiltIn && !builtInIDs.contains($0.id) }
    }

    /// The provider with this id among `providers`. With no id (the user
    /// never chose) that is Antigravity as listed, edited command included;
    /// with an id nothing in the list has, it is Antigravity as built in.
    public static func chosen(id: UUID?, among providers: [NexusAgentCLIProvider]) -> NexusAgentCLIProvider {
        providers.first { $0.id == id ?? antigravity.id } ?? .antigravity
    }

    /// How this provider's turns are run, decided as the standalone app's
    /// own chat decided it (removed in step 3c; last shipped in nexus-agent
    /// 1.19.0). The built-in Antigravity provider is always agy,
    /// whatever its template says. Any other is Ollama, OpenCode or Claude
    /// if it is that built-in provider or the first word of its template
    /// ends in `ollama`, `opencode` or `claude` (so a full path counts, and
    /// so does any other word with that ending); they are tried in that
    /// order. What is left is a command of the user's own, run as its
    /// template is written.
    ///
    /// For all but that last the template is not run: the provider's own
    /// arguments are (`NexusAgentSupport.agentArguments`).
    public var route: NexusAgentProviderRoute {
        if id == Self.antigravity.id { return .antigravity }
        let program = commandTemplate.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces).first ?? ""
        if program.hasSuffix("ollama") || id == Self.ollama.id { return .ollama }
        if program.hasSuffix("opencode") || id == Self.opencode.id { return .opencode }
        if program.hasSuffix("claude") || id == Self.claude.id { return .claude }
        return .custom
    }

    /// The program a turn is started with. For a command of the user's own
    /// this is not it: the program is the first word of the template (see
    /// `NexusAgentSupport.providerCommand`).
    public var executableName: String {
        switch route {
        case .claude: return "claude"
        case .ollama: return "ollama"
        case .opencode: return "opencode"
        case .antigravity, .custom: return "agy"
        }
    }

    /// Whether a turn can be run in a git worktree of its own: only Claude
    /// Code (`-w`) can, Ollama's included. agy, OpenCode and a command of
    /// the user's own have no such flag.
    public var supportsWorktree: Bool {
        route == .claude || route == .ollama
    }
}

/// The ways a provider's turn can be run.
public enum NexusAgentProviderRoute: Equatable, Sendable {
    /// `agy`, with streamed JSON.
    case antigravity
    /// `claude`, with streamed JSON.
    case claude
    /// `ollama launch claude`, which is Claude Code on a local model.
    case ollama
    /// `opencode run`, with its JSON events.
    case opencode
    /// The provider's own command template; what it prints is the reply.
    case custom
}

/// How a provider's own command ended, from what it printed and its exit.
public enum NexusAgentCommandOutcome: Equatable, Sendable {
    /// It printed an answer.
    case reply(String)
    /// It exited badly with no answer. `errors` is what it complained
    /// about, cut short, or empty if it said nothing.
    case failed(status: Int32, errors: String)
    /// It ran to its end and printed nothing.
    case noOutput
    /// It was ended by a signal: someone stopped it.
    case stopped
}

/// The part of the bot's `.env` the Settings page edits. Everything else in
/// the file (the timeout, a custom provider, comments) is left as it was.
public struct NexusAgentConfiguration: Equatable {
    public var botToken: String
    public var allowedUserIDs: String
    public var workingDirectory: String
    public var approvalMode: NexusAgentApprovalMode
    public var model: String
    /// The effort as the page names it. Choosing one is the user's word, so
    /// it forgets how the file said it (`effortAsWritten`,
    /// `effortIsFromThinkingLine`), and a save then writes the choice.
    public var effort: NexusAgentEffort {
        didSet {
            effortAsWritten = nil
            effortIsFromThinkingLine = false
        }
    }
    /// The file's effort line, when it holds something the page has no
    /// name for: `HIGH`, `max`, a value with spaces kept by quotes. The bot
    /// passes agy whatever the line says, changing nothing, so a turn here
    /// passes this too (`effortArgument`), and `effort` is only the nearest
    /// name the page can show for it. While it is set a save writes the
    /// line back as it was. Set by reading a file, never by hand.
    public fileprivate(set) var effortAsWritten: String?
    /// True when the file has no effort and `effort` is high only because
    /// its `AGY_THINKING` line says `true`. While it is set a save leaves
    /// both lines as they are: writing `high` into the effort line would
    /// change a key on a save that was about something else. Set by
    /// reading a file, never by hand.
    public fileprivate(set) var effortIsFromThinkingLine = false
    public var activeProvider: NexusAgentCLIProvider
    /// The program the bot should run, written to `.env` on save. Nil leaves
    /// the file's own `CLI_PROVIDER` and `CLI_COMMAND_TEMPLATE` lines alone,
    /// which is what an app that does not manage the bot's provider wants.
    /// Reading a file never fills it in: an app that sets it holds the choice
    /// itself. So after the engine saves or loads, `engine.configuration`'s
    /// copy is nil. Keep your own choice and set it on every save; do not
    /// compare your draft against the engine's copy, or save that copy back.
    public var botProvider: NexusAgentCLIProvider?

    public init(botToken: String = "",
                 allowedUserIDs: String = "",
                 workingDirectory: String = "",
                 approvalMode: NexusAgentApprovalMode = .yolo,
                 model: String = "",
                 effort: NexusAgentEffort = .automatic,
                 activeProvider: NexusAgentCLIProvider = .antigravity,
                 botProvider: NexusAgentCLIProvider? = nil) {
        self.botToken = botToken
        self.allowedUserIDs = allowedUserIDs
        self.workingDirectory = workingDirectory
        self.approvalMode = approvalMode
        self.model = model
        self.effort = effort
        self.activeProvider = activeProvider
        self.botProvider = botProvider
    }

    /// What follows `--effort` when agy is run, as the bot decides it; nil
    /// passes no flag and leaves the choice to agy. The examples are shared
    /// with the bot's tests: `apps/desktop/nexus-agent/testdata/agy-flags.json`.
    public var effortArgument: String? {
        effortAsWritten ?? (effort == .automatic ? nil : effort.rawValue)
    }

    /// The file's effort line when it is a word none of the page's names
    /// stands for (`max`), and nil otherwise: `HIGH` is High in other
    /// letters. A page that can show such a word shows this, as written,
    /// in place of `effort`, which for it is only "automatic".
    public var unnamedEffort: String? {
        guard let written = effortAsWritten, NexusAgentEffort.parse(written) == .automatic else { return nil }
        return written
    }

    /// The effort as a page with a row for every case selects it, by the
    /// row's tag: the name of one of the four efforts (empty for
    /// automatic), or the file's own word when it is none of them
    /// (`unnamedEffort`), which is then a row of its own.
    ///
    /// Setting it is the user choosing a row, and replaces whatever the
    /// file said. Setting the row that is already selected is no choice:
    /// the effort stays as it was read, so a save leaves the file's lines
    /// alone. A tag that is no effort's name, other than the selected
    /// word, counts as automatic.
    public var effortChoice: String {
        get { unnamedEffort ?? effort.rawValue }
        set {
            guard newValue != effortChoice else { return }
            effort = .parse(newValue)
        }
    }

    /// The placeholder the bot's example file ships with.
    public static let placeholderToken = "your_bot_token_here"

    /// The bot refuses to start without a real token.
    public var isConfigured: Bool {
        let token = botToken.trimmingCharacters(in: .whitespaces)
        return !token.isEmpty && token != Self.placeholderToken
    }

    /// The user ids the bot will answer, in order and without blanks. Empty
    /// means the bot answers anyone who finds it.
    public var allowedUserIDList: [String] {
        allowedUserIDs.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Reads and writes the bot's `.env` the way its `dotenv` loader reads it.
public enum NexusAgentEnvFile {
    public static let tokenKey = "TELEGRAM_BOT_TOKEN"
    public static let allowedUsersKey = "ALLOWED_USER_IDS"
    public static let workingDirectoryKey = "AGY_WORKING_DIR"
    public static let approvalModeKey = "AGY_APPROVAL_MODE"
    public static let modelKey = "AGY_MODEL"
    public static let effortKey = "AGY_EFFORT"
    /// `true`, and nothing else, means high effort when the effort line is
    /// empty. The page has no control of its own for it: see
    /// `effortAssignments` for when a save writes it.
    public static let thinkingKey = "AGY_THINKING"
    /// Which program the bot runs: `agy`, or `custom` with the template below.
    /// Owned by the page only when the configuration sets `botProvider`.
    public static let providerKey = "CLI_PROVIDER"
    public static let commandTemplateKey = "CLI_COMMAND_TEMPLATE"

    /// Pre-migration names the bot still honours when the AGY_ one is absent.
    /// Writing the file supersedes them, so they are dropped then: left in
    /// place, `GEMINI_THINKING=true` would keep forcing high effort after the
    /// page said otherwise.
    public static let legacyKeys = ["GEMINI_WORKING_DIR", "GEMINI_APPROVAL_MODE",
                                     "GEMINI_MODEL", "GEMINI_THINKING"]

    /// The keys the page owns, in the order a new file lists them.
    public static let managedKeys = [tokenKey, allowedUsersKey, workingDirectoryKey,
                                      approvalModeKey, modelKey, effortKey]

    /// Every `KEY=value` pair, later lines winning as they do for dotenv.
    public static func values(in content: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in lines(of: content) {
            if let pair = assignment(in: line.text) {
                values[pair.key] = pair.value
            }
        }
        return values
    }

    public static func parse(_ content: String) -> NexusAgentConfiguration {
        let values = values(in: content)
        func compat(_ name: String) -> String? {
            values["AGY_\(name)"] ?? values["GEMINI_\(name)"]
        }
        let written = values[effortKey] ?? ""
        var effort = NexusAgentEffort.parse(written)
        // The thinking line means high effort when there is no effort to
        // go by: an effort line that says anything wins, a word the page
        // has no name for included. The bot takes thinking from
        // AGY_THINKING, or from the old name when that key is absent (an
        // empty AGY_THINKING line still hides the old one), and only the
        // exact word `true` switches it on.
        let thinking = written.isEmpty && compat("THINKING") == "true"
        if thinking { effort = .high }
        var configuration = NexusAgentConfiguration(
            botToken: values[tokenKey] ?? "",
            allowedUserIDs: values[allowedUsersKey] ?? "",
            workingDirectory: compat("WORKING_DIR") ?? "",
            approvalMode: .parse(compat("APPROVAL_MODE")),
            model: compat("MODEL") ?? "",
            effort: effort)
        if isUnnamedEffort(written) { configuration.effortAsWritten = written }
        // Only the line a save keeps counts here. The old name is dropped
        // by every save, so the high it stands for is written as an effort.
        configuration.effortIsFromThinkingLine = thinking && values[thinkingKey] == "true"
        return configuration
    }

    /// True for an effort line that says something, but not one of the
    /// words the page offers, spelled as the page writes them.
    private static func isUnnamedEffort(_ written: String) -> Bool {
        !written.isEmpty && NexusAgentEffort(rawValue: written) == nil
    }

    /// What a save writes for the effort and for the thinking line, which
    /// between them decide the `--effort` the bot passes agy. A key that
    /// is not in the answer is left as the file has it.
    ///
    /// A configuration that still holds the effort as it was read keeps
    /// the file's own words: a line the page has no name for (`HIGH`,
    /// `max`) is written back as it was, and a high that comes from
    /// `AGY_THINKING=true` leaves the effort line empty, as long as that
    /// thinking line is still there to mean it. Neither key changes on a
    /// save that was about something else.
    ///
    /// An effort the user chose is written by its name. Choosing
    /// "automatic" also has to switch off an `AGY_THINKING=true`, or the
    /// bot would go on passing high and the page would show High again the
    /// next time it read the file. Any other choice leaves the thinking
    /// line alone: the effort line wins over it.
    private static func effortAssignments(for configuration: NexusAgentConfiguration,
                                          over existing: String) -> [String: String] {
        let thinks = values(in: existing)[thinkingKey] == "true"
        if let written = configuration.effortAsWritten { return [effortKey: written] }
        if configuration.effortIsFromThinkingLine, thinks { return [effortKey: ""] }
        if configuration.effort == .automatic, thinks { return [effortKey: "", thinkingKey: "false"] }
        return [effortKey: configuration.effort.rawValue]
    }

    /// The file with the page's values written in. An existing file keeps its
    /// comments, its order and every key the page does not own; a key it
    /// lacks is added at the end. With no file yet, the bot's template is
    /// written, so the result matches what the standalone app produced.
    public static func render(_ configuration: NexusAgentConfiguration, over existing: String?) -> String {
        var wanted = assignments(for: configuration)
        guard let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // An effort word read from a file that has since gone is still
            // the effort: the new file gets it as it was written.
            wanted.merge(effortAssignments(for: configuration, over: "")) { _, effort in effort }
            return template(wanted)
        }
        wanted.merge(effortAssignments(for: configuration, over: existing)) { _, effort in effort }
        var written: Set<String> = []
        // Each entry is a line with its own ending, so a line left alone
        // comes out byte for byte as it went in (a CRLF file keeps its CRLF
        // on every line the page does not change). A line the page rewrites
        // ends in a plain newline, and so does the last line if the file
        // did not end in one.
        var output: [String] = []
        var lastText = ""
        for line in lines(of: existing) {
            let ending = line.ending.isEmpty ? "\n" : line.ending
            guard let key = assignment(in: line.text)?.key else {
                output.append(line.text + ending)
                lastText = line.text
                continue
            }
            if legacyKeys.contains(key) { continue }
            if let value = wanted[key] {
                // Every copy gets the new value: dotenv reads the last one.
                let rewritten = "\(key)=\(encoded(value))"
                output.append(rewritten + "\n")
                lastText = rewritten
                written.insert(key)
            } else {
                output.append(line.text + ending)
                lastText = line.text
            }
        }
        // The provider lines count as owned only when the app chose one.
        let owned = managedKeys + (configuration.botProvider == nil ? [] : [providerKey, commandTemplateKey])
        let missing = owned.filter { !written.contains($0) }
        if !missing.isEmpty {
            if !lastText.trimmingCharacters(in: .whitespaces).isEmpty {
                output.append("\n")
            }
            for key in missing {
                output.append("\(key)=\(encoded(wanted[key] ?? ""))\n")
            }
        }
        return output.joined()
    }

    /// The lines of a file, each with the ending it had. A line ends at
    /// `\r\n`, `\r` or `\n` and nowhere else, which is where dotenv splits
    /// the file. Other characters that look like line breaks (a vertical tab,
    /// a form feed, U+0085, U+2028, U+2029) stay inside the line, as they do
    /// for the bot. The last line has an empty ending if the file did not end
    /// in a line break; a file that does has no empty line after it.
    private static func lines(of content: String) -> [(text: String, ending: String)] {
        var lines: [(text: String, ending: String)] = []
        var text = String.UnicodeScalarView()
        var scalars = content.unicodeScalars.makeIterator()
        var next = scalars.next()
        while let scalar = next {
            next = scalars.next()
            switch scalar {
            case "\n":
                lines.append((String(text), "\n"))
                text = String.UnicodeScalarView()
            case "\r":
                if next == Unicode.Scalar("\n") {
                    next = scalars.next()
                    lines.append((String(text), "\r\n"))
                } else {
                    lines.append((String(text), "\r"))
                }
                text = String.UnicodeScalarView()
            default:
                text.append(scalar)
            }
        }
        if !text.isEmpty { lines.append((String(text), "")) }
        return lines
    }

    // MARK: - Lines

    /// One line of `.env`, read as the bot's `dotenv` reads it. dotenv is the
    /// authority: what it makes of a line is what the bot runs with, so this
    /// follows it case for case, the odd ones included. The examples are
    /// shared with the bot's tests, which run them through dotenv itself:
    /// `apps/desktop/nexus-agent/testdata/env-lines.json`.
    ///
    /// In short: `KEY=value` or `KEY: value`, with an optional `export`; the
    /// key is ASCII letters, digits, `_`, `.` and `-`; a value in matching
    /// quotes (`'`, `"` or a backtick) keeps what is between them; any other
    /// value ends at the first `#`, with or without a space before it.
    ///
    /// Only the first line of `line` is read. dotenv can carry a quoted value
    /// across several lines; a one-line reader cannot, and does not try.
    public static func assignment(in line: String) -> (key: String, value: String)? {
        // dotenv matches one UTF-16 unit at a time and never looks at a
        // letter's accents; scalars give the same answers here.
        var text = Array(line.unicodeScalars)
        if let end = text.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            text.removeSubrange(end...)
        }
        var start = 0
        while start < text.count, isSpace(text[start]) { start += 1 }
        // `export KEY=value`. If no assignment follows the word, dotenv takes
        // `export` for the key itself (`export=v`), so that is tried next.
        let export = Array("export".unicodeScalars)
        if text[start...].starts(with: export) {
            var afterExport = start + export.count
            if afterExport < text.count, isSpace(text[afterExport]) {
                while afterExport < text.count, isSpace(text[afterExport]) { afterExport += 1 }
                if let pair = keyAndValue(text, from: afterExport) { return pair }
            }
        }
        return keyAndValue(text, from: start)
    }

    /// `KEY`, then `=` (spaces allowed before it) or `:` and a space, then
    /// the value.
    private static func keyAndValue(_ text: [Unicode.Scalar], from start: Int) -> (key: String, value: String)? {
        var index = start
        while index < text.count, isKeyCharacter(text[index]) { index += 1 }
        guard index > start else { return nil }
        let key = string(text[start..<index])
        if index < text.count, text[index] == ":" {
            guard index + 1 < text.count, isSpace(text[index + 1]) else { return nil }
            index += 2
        } else {
            while index < text.count, isSpace(text[index]) { index += 1 }
            guard index < text.count, text[index] == "=" else { return nil }
            index += 1
        }
        return (key, value(text, from: index))
    }

    /// What follows the `=`, as dotenv takes it.
    private static func value(_ text: [Unicode.Scalar], from start: Int) -> String {
        var open = start
        while open < text.count, isSpace(text[open]) { open += 1 }
        var raw: ArraySlice<Unicode.Scalar>
        if open < text.count, isQuote(text[open]), let close = closingQuote(text, open: open) {
            raw = text[open...close]
        } else {
            // Not a quoted value (or not one dotenv accepts as such): it ends
            // at the first `#`, wherever that is.
            let end = text[start...].firstIndex(of: "#") ?? text.count
            raw = text[start..<end]
        }
        while let first = raw.first, isSpace(first) { raw = raw.dropFirst() }
        while let last = raw.last, isSpace(last) { raw = raw.dropLast() }
        // dotenv decides on the first character BEFORE removing the quotes,
        // and removes them whenever both ends match, even for a value it did
        // not take as quoted above (`"a" "b"` loses its outer pair).
        let first = raw.first
        if raw.count >= 2, let first, isQuote(first), raw.last == first {
            raw = raw.dropFirst().dropLast()
        }
        var value = string(raw)
        if first == "\"" {
            // Literal, as dotenv's text search is: without it a combining
            // accent after the `n` makes `n` + accent one letter, which is
            // not a match.
            value = value.replacingOccurrences(of: "\\n", with: "\n", options: .literal)
                .replacingOccurrences(of: "\\r", with: "\r", options: .literal)
        }
        return value
    }

    /// Where the quoted value opened at `open` closes, or nil if dotenv does
    /// not read it as a quoted value. A quote of the same kind may sit inside
    /// only after a backslash, and nothing but spaces and a `#` comment may
    /// follow the closing one. Of the quotes that could close it, dotenv
    /// takes the last that leaves the rest of the line acceptable.
    private static func closingQuote(_ text: [Unicode.Scalar], open: Int) -> Int? {
        let quote = text[open]
        var candidates: [Int] = []
        var index = open + 1
        while index < text.count {
            if text[index] == quote {
                candidates.append(index)
                let escaped = index - 1 > open && text[index - 1] == "\\"
                if !escaped { break }
            }
            index += 1
        }
        return candidates.last { close in
            var rest = close + 1
            while rest < text.count, isSpace(text[rest]) { rest += 1 }
            return rest == text.count || text[rest] == "#"
        }
    }

    private static func isQuote(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\"" || scalar == "'" || scalar == "`"
    }

    /// The characters dotenv allows in a key: JavaScript's `\w`, `.` and `-`.
    private static func isKeyCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "_", ".", "-": return true
        default: return false
        }
    }

    /// JavaScript's `\s`, which is what dotenv skips and trims.
    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// A value as it can be written on one line, so that the bot's dotenv
    /// reads back exactly what was meant. Line breaks are removed so a pasted
    /// value can never smuggle in a second assignment, and a value dotenv
    /// would otherwise cut, trim or unquote is put in quotes.
    ///
    /// Which quotes is decided by reading the result back with
    /// `assignment(in:)`, the same reading the shared examples hold to
    /// dotenv's (`apps/desktop/nexus-agent/testdata/env-written-values.json`).
    /// Single quotes come first, or double quotes for a value holding a
    /// single quote; backticks carry a value that holds both. One kind of
    /// value has no spelling at all: a `#` together with all three quote
    /// characters. It is written in the first choice of quotes and the bot
    /// reads it cut short; the shared examples keep that limit visible.
    public static func encoded(_ value: String) -> String {
        let flat = value.components(separatedBy: .newlines).joined()
        func readsBack(_ written: String) -> Bool {
            assignment(in: "K=\(written)")?.value == flat
        }
        let needsQuotes = flat.contains("#") || flat.first == "\"" || flat.first == "'" || flat.first == "`"
            || flat != flat.trimmingCharacters(in: .whitespaces)
        if !needsQuotes, readsBack(flat) { return flat }
        let quotes = flat.contains("'") ? ["\"", "`", "'"] : ["'", "\"", "`"]
        let spellings = quotes.map { "\($0)\(flat)\($0)" }
        return spellings.first(where: readsBack) ?? spellings[0]
    }

    private static func assignments(for configuration: NexusAgentConfiguration) -> [String: String] {
        var wanted = [
            tokenKey: configuration.botToken.trimmingCharacters(in: .whitespaces),
            allowedUsersKey: configuration.allowedUserIDList.joined(separator: ","),
            workingDirectoryKey: configuration.workingDirectory.trimmingCharacters(in: .whitespaces),
            approvalModeKey: configuration.approvalMode.rawValue,
            modelKey: configuration.model.trimmingCharacters(in: .whitespaces),
            effortKey: configuration.effort.rawValue,
        ]
        if let provider = configuration.botProvider {
            // The built-in agent is the bot's own default; anything else is
            // run from its command template.
            let builtIn = provider.id == NexusAgentCLIProvider.antigravity.id
            wanted[providerKey] = builtIn ? "agy" : "custom"
            wanted[commandTemplateKey] = builtIn ? "" : provider.commandTemplate
        }
        return wanted
    }

    private static func template(_ values: [String: String]) -> String {
        func value(_ key: String) -> String { encoded(values[key] ?? "") }
        return """
        # Telegram Bot Token (get from @BotFather on Telegram)
        \(tokenKey)=\(value(tokenKey))

        # Comma-separated list of allowed Telegram user IDs
        \(allowedUsersKey)=\(value(allowedUsersKey))

        # Working directory for the Antigravity CLI (agy)
        \(workingDirectoryKey)=\(value(workingDirectoryKey))

        # Max execution time per prompt in milliseconds
        AGY_TIMEOUT_MS=300000

        # Approval mode: yolo, accept-edits, plan, default
        \(approvalModeKey)=\(value(approvalModeKey))

        # Model (optional; `agy models` lists them)
        \(modelKey)=\(value(modelKey))

        # Reasoning effort: low, medium, high (empty = agy default)
        \(effortKey)=\(value(effortKey))

        # AI backend provider: agy or custom
        \(providerKey)=\(encoded(values[providerKey] ?? "agy"))

        # Command template for custom provider ({prompt} and {model} are substituted at runtime)
        \(commandTemplateKey)=\(value(commandTemplateKey))

        """
    }
}

/// Where the bot and the agent CLI live, and how the agent is asked.
public enum NexusAgentSupport {
    /// The bot's standard home, shared with the standalone app.
    public static func defaultBotDirectory(home: String) -> String {
        (home as NSString).appendingPathComponent(".config/nexus-agent")
    }

    /// A configured folder, with `~` expanded, or the standard home.
    public static func botDirectory(configured: String, home: String) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return defaultBotDirectory(home: home) }
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") {
            return (home as NSString).appendingPathComponent(String(trimmed.dropFirst(2)))
        }
        return trimmed
    }

    /// The bot's entry point inside its folder.
    public static let botEntryPoint = "src/bot.js"

    /// Install locations an app launched from Finder does not have on its
    /// PATH, in the order they are tried.
    public static func searchDirectories(home: String) -> [String] {
        [(home as NSString).appendingPathComponent(".local/bin"), "/opt/homebrew/bin", "/usr/local/bin"]
    }

    /// `AGY_BIN` or named executable first, then the usual install locations. Nil when none is
    /// executable, so the page can say so instead of failing at run time.
    public static func locateAgent(named binary: String = "agy", environment: [String: String], home: String,
                                    isExecutable: (String) -> Bool) -> String? {
        if binary == "agy", let explicit = environment["AGY_BIN"]?.trimmingCharacters(in: .whitespaces),
           !explicit.isEmpty, isExecutable(explicit) {
            return explicit
        }
        return searchDirectories(home: home)
            .map { ($0 as NSString).appendingPathComponent(binary) }
            .first(where: isExecutable)
    }

    /// Where the Claude or Ollama program is, looked for so that nothing
    /// either app finds today is lost: first the install locations above,
    /// in their order (so a program found there is found at the same path
    /// as before), and only if it is in none of them, where the standalone
    /// app's chat looks (`executablePath`: more folders, then PATH).
    public static func locateChatProgram(named name: String, environment: [String: String], home: String,
                                         isExecutable: (String) -> Bool, fileExists: (String) -> Bool) -> String? {
        locateAgent(named: name, environment: environment, home: home, isExecutable: isExecutable)
            ?? executablePath(named: name, pathVariable: environment["PATH"] ?? "",
                              isExecutable: isExecutable, fileExists: fileExists)
    }

    /// Node from Homebrew or the official installer. macOS ships none.
    public static func locateNode(home: String, isExecutable: (String) -> Bool) -> String? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node",
         (home as NSString).appendingPathComponent(".local/bin/node")]
            .first(where: isExecutable)
    }

    /// The child's environment: the app's own, the install locations put in
    /// front of PATH, and colour codes off so logs stay readable.
    public static func childEnvironment(base: [String: String], home: String) -> [String: String] {
        var environment = base
        let current = base["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let existing = Set(current.split(separator: ":").map(String.init))
        let extra = searchDirectories(home: home).filter { !existing.contains($0) }
        environment["PATH"] = (extra + [current]).joined(separator: ":")
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// Check whether a folder contains a .git directory.
    public static func isGitRepo(at url: URL) -> Bool {
        let gitDir = url.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDirectory)
    }

    /// Where a program is, as the standalone app's own chat found one
    /// (removed in step 3c; last shipped in nexus-agent 1.19.0). A full
    /// path is taken as given if anything is there. A bare name is looked
    /// for in the usual install folders and then in the folders of
    /// `pathVariable` (the PATH an app launched from Finder has is short),
    /// and the first one that can be run wins.
    public static func executablePath(named name: String, pathVariable: String,
                                       isExecutable: (String) -> Bool,
                                       fileExists: (String) -> Bool) -> String? {
        if name.hasPrefix("/") {
            return fileExists(name) ? name : nil
        }
        var seen = Set<String>()
        return (commandInstallFolders + pathVariable.split(separator: ":").map(String.init))
            .filter { seen.insert($0).inserted }
            .map { ($0 as NSString).appendingPathComponent(name) }
            .first(where: isExecutable)
    }

    /// Where the standalone app's own chat, removed in step 3c, expected
    /// programs to be installed, in the order it tried them.
    static let commandInstallFolders = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
                                        "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    // MARK: - A provider's own command

    /// The model a template's `{model}` stands for when the settings name none.
    public static let templateFallbackModel = "gemma4:31b-cloud"

    /// A provider's command template as a program and its arguments, with
    /// `{prompt}` and `{model}` filled in. Nil when the template has no
    /// words in it.
    ///
    /// The template is cut into words FIRST, and only then are the
    /// placeholders filled, each inside the word it was written in. So the
    /// prompt is always part of exactly one argument, whatever it holds:
    /// spaces, quotes, `;`, `$(…)` or new lines in it are plain text. The
    /// result is for starting the program directly; it must never be
    /// joined back into a line for a shell.
    ///
    /// The cutting is the standalone app's, kept as it is so a saved
    /// template means what it did: words are separated by spaces (not tabs);
    /// single or double quotes keep spaces inside a word and are removed;
    /// nothing escapes a quote; a quote left open runs to the end; and an
    /// empty pair of quotes makes no word. The first word is the program,
    /// and is filled in like the rest.
    ///
    /// Two things are NOT the standalone's. It fills `{prompt}` and then
    /// looks for `{model}` in the result, so a prompt that says `{model}`
    /// is altered. Here what was filled in is never read again.
    ///
    /// And the standalone fills `{prompt}` into the program's name too. That
    /// is never useful, and it is the one way a prompt could choose what is
    /// run, so here a template whose first word holds `{prompt}` has no
    /// program: the executable comes back empty, which callers treat as a
    /// program that cannot be found, and the arguments are filled as usual.
    /// `{model}` in the first word is still filled in: it is the user's own
    /// setting.
    public static func providerCommand(template: String, prompt: String,
                                       model: String) -> (executable: String, arguments: [String])? {
        let words = templateWords(template)
        guard !words.isEmpty else { return nil }

        let filled = words.map {
            fillingPlaceholders(in: $0, prompt: prompt, model: model.isEmpty ? templateFallbackModel : model)
        }
        // The mark is looked for in the template's word, before anything is
        // put in, so no prompt or model can make or hide it.
        let programTakesPrompt = words[0].contains("{prompt}")
        return (programTakesPrompt ? "" : filled[0], Array(filled.dropFirst()))
    }

    /// What a command's program is called when it cannot be found: the
    /// template's first word with `{model}` filled in, which is the name
    /// that was looked for. A first word that holds `{prompt}` is no
    /// program (see `providerCommand`) and is named as written. Nil when
    /// the template has no words. The chat's bubble and a settings page
    /// both name the program through here, so they cannot disagree.
    static func programName(template: String, model: String) -> String? {
        guard let command = providerCommand(template: template, prompt: "", model: model) else { return nil }
        return command.executable.isEmpty ? templateWords(template).first : command.executable
    }

    /// A template cut into words, placeholders not yet filled in.
    static func templateWords(_ template: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        for character in template {
            if character == "'" && !inDouble {
                inSingle.toggle()
            } else if character == "\"" && !inSingle {
                inDouble.toggle()
            } else if character == " " && !inSingle && !inDouble {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// One word of a template with its placeholders replaced, reading the
    /// word once from left to right: text that was put in is not looked at.
    private static func fillingPlaceholders(in word: String, prompt: String, model: String) -> String {
        let promptMark = "{prompt}"
        let modelMark = "{model}"
        var result = ""
        var rest = Substring(word)
        while let brace = rest.firstIndex(of: "{") {
            result += rest[..<brace]
            rest = rest[brace...]
            if rest.hasPrefix(promptMark) {
                result += prompt
                rest = rest.dropFirst(promptMark.count)
            } else if rest.hasPrefix(modelMark) {
                result += model
                rest = rest.dropFirst(modelMark.count)
            } else {
                result.append("{")
                rest = rest.dropFirst()
            }
        }
        return result + rest
    }

    /// A prompt for plan mode, for a provider with no flag to say it with:
    /// the rules go in front of what the user asked, in the standalone
    /// app's words.
    public static func planModePrompt(_ prompt: String) -> String {
        """
        [SYSTEM] You are in PLAN MODE. You MUST follow these rules strictly:
        - Do NOT create, edit, modify, or delete any files.
        - Do NOT run any shell commands or scripts.
        - Do NOT execute any tools that modify the filesystem or environment.
        - ONLY explain what you WOULD do, step by step, as a detailed plan.
        - Present your plan as a numbered list of actions you would take.
        - Wait for explicit user approval before taking any action.

        User request: \(prompt)
        """
    }

    /// The environment a provider's own command runs in, as the standalone
    /// app gives it: the app's own, colour codes off, and the install
    /// folders that exist put in front of PATH.
    public static func commandEnvironment(base: [String: String],
                                          fileExists: (String) -> Bool) -> [String: String] {
        var environment = base
        let current = base["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = (commandInstallFolders.filter(fileExists) + [current]).joined(separator: ":")
        environment["NO_COLOR"] = "1"
        return environment
    }

    /// Reads how a provider's own command ended, as the standalone app
    /// reads it. `output` is all it printed and `errors` all it wrote to
    /// standard error; both are trimmed, and either counts as empty if it
    /// is not text. An answer is an answer even when the exit status is
    /// bad; a bad exit matters only when nothing was printed.
    public static func commandOutcome(output: Data, errors: Data, status: Int32) -> NexusAgentCommandOutcome {
        let printed = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let complaint = String(data: errors, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // SIGTERM and SIGKILL: the two ways a turn is stopped.
        if status == 15 || status == 9 { return .stopped }
        if status != 0 && printed.isEmpty { return .failed(status: status, errors: String(complaint.prefix(300))) }
        if !printed.isEmpty { return .reply(printed) }
        return .noOutput
    }

    /// The model Ollama is run with when none is set and none can be found.
    public static let ollamaFallbackModel = "qwen3"

    /// The model to run Ollama with when the settings name none: the first
    /// one `ollama list` reports. `output` is what that command printed, or
    /// nil if it could not be run. The first row is the table's header and
    /// is passed over; the name is the first word of the first row after
    /// it that is not empty. Anything else gives the fallback.
    ///
    /// Read exactly as the standalone app reads it, oddities included: the
    /// first row is dropped whatever it holds, and if the first row with
    /// anything on it begins with a space, the rows after it are not tried.
    public static func ollamaDefaultModel(fromList output: String?) -> String {
        guard let output else { return ollamaFallbackModel }
        let rows = output.components(separatedBy: "\n").dropFirst()
        guard let first = rows.first(where: { !$0.isEmpty }) else { return ollamaFallbackModel }
        let name = first.components(separatedBy: .whitespaces).first ?? ""
        return name.isEmpty ? ollamaFallbackModel : name
    }

    /// One Quick Prompt turn: formatted per active provider, by the way it
    /// is run (`NexusAgentCLIProvider.route`). Ollama must be
    /// told a model: `ollamaDefaultModel` is the one to use when the
    /// settings name none, which the caller looks up (see
    /// `ollamaDefaultModel(fromList:)`) so that this stays a plain function.
    ///
    /// Plan mode is a flag for agy and for Claude. Ollama gets Claude's
    /// flags too, and the rules in front of the prompt as well, as the
    /// standalone app has it. OpenCode plans with its own `plan` agent, and
    /// YOLO is its `--auto`; it has no worktree flag, so worktree mode is
    /// not passed to it. A command of the user's own has no arguments
    /// here: `providerCommand` makes them from its template.
    ///
    /// Effort is `--effort` for agy and Claude Code (both take low, medium,
    /// high, xhigh and max); OpenCode has no effort flag, so none is sent.
    /// Attachments are `--file` for OpenCode and `@path` lines in front of
    /// the prompt for the rest. `forkSession` continues `conversationID` in
    /// a new session: Claude's `--fork-session` (with `--resume`) and
    /// OpenCode's `--fork` (with `--session`); agy has no fork, so it is
    /// ignored there.
    public static func agentArguments(prompt: String, configuration: NexusAgentConfiguration,
                                       conversationID: String?,
                                       planMode: Bool = false,
                                       worktreeMode: Bool = false,
                                       ollamaDefaultModel: String = NexusAgentSupport.ollamaFallbackModel,
                                       attachments: [NexusAgentAttachment] = [],
                                       forkSession: Bool = false) -> [String] {
        let route = configuration.activeProvider.route
        let effort = configuration.effortArgument.map(claudeEffort)
        let prompt = route == .opencode ? prompt : promptWithAttachments(prompt, attachments)
        if route == .claude {
            var args = ["-p", prompt, "--output-format", "stream-json", "--include-partial-messages", "--verbose"]
            if planMode {
                args += ["--permission-mode", "plan",
                         "--append-system-prompt", "You are in PLAN MODE. Do NOT create, edit, modify, or delete any files. Do NOT run any shell commands. ONLY explain what you would do as a detailed numbered plan. Wait for explicit user approval before taking any action."]
            } else {
                args += ["--permission-mode", configuration.approvalMode.claudePermissionMode]
                if configuration.approvalMode == .yolo {
                    args += ["--dangerously-skip-permissions"]
                }
            }
            if worktreeMode {
                args += ["-w"]
            }
            let model = configuration.model.trimmingCharacters(in: .whitespaces)
            if !model.isEmpty { args += ["--model", model] }
            if let effort { args += ["--effort", effort] }
            if let conversationID, !conversationID.isEmpty {
                args += ["--resume", conversationID]
                if forkSession { args += ["--fork-session"] }
            }
            return args
        }
        if route == .ollama {
            let model = configuration.model.trimmingCharacters(in: .whitespaces)
            let args = ["launch", "claude", "--model", model.isEmpty ? ollamaDefaultModel : model]
            var innerArgs = ["-p", planMode ? planModePrompt(prompt) : prompt,
                             "--output-format", "stream-json", "--include-partial-messages", "--verbose"]
            if planMode {
                innerArgs += ["--permission-mode", "plan",
                              "--append-system-prompt", "You are in PLAN MODE. Do NOT create, edit, modify, or delete any files. Do NOT run any shell commands. ONLY explain what you would do as a detailed numbered plan. Wait for explicit user approval before taking any action."]
            } else {
                innerArgs += ["--permission-mode", configuration.approvalMode.claudePermissionMode]
                if configuration.approvalMode == .yolo {
                    innerArgs += ["--dangerously-skip-permissions"]
                }
            }
            if worktreeMode {
                innerArgs += ["-w"]
            }
            if let effort { innerArgs += ["--effort", effort] }
            if let conversationID, !conversationID.isEmpty {
                innerArgs += ["--resume", conversationID]
                if forkSession { innerArgs += ["--fork-session"] }
            }
            return args + ["--"] + innerArgs
        }
        if route == .opencode {
            var args = ["run", "--format", "json"]
            if planMode || configuration.approvalMode == .plan {
                args += ["--agent", "plan"]
            } else if configuration.approvalMode == .yolo {
                args += ["--auto"]
            }
            let model = configuration.model.trimmingCharacters(in: .whitespaces)
            if !model.isEmpty { args += ["--model", model] }
            if let id = conversationID?.trimmingCharacters(in: .whitespaces), !id.isEmpty {
                args += ["--session", id]
                if forkSession { args += ["--fork"] }
            }
            for attachment in attachments { args += ["--file", attachment.url.path] }
            // OpenCode's `run` command appends arguments after `--` a second
            // time on top of its positional `message` array, duplicating the
            // prompt. A leading space keeps a dash-prefixed prompt positional.
            let safePrompt = prompt.hasPrefix("-") ? " " + prompt : prompt
            return args + [safePrompt]
        }
        var arguments = ["-p", prompt, "--output-format", "stream-json"]
        if planMode {
            arguments += ["--mode", "plan"]
        } else {
            arguments += configuration.approvalMode.agyArguments
        }
        let model = configuration.model.trimmingCharacters(in: .whitespaces)
        if !model.isEmpty { arguments += ["--model", model] }
        if let effort = configuration.effortArgument { arguments += ["--effort", effort] }
        if let conversationID, !conversationID.isEmpty { arguments += ["--conversation", conversationID] }
        return arguments
    }

    /// The effort levels Claude Code's `--effort` takes (2.1.x), which are
    /// agy's as well. A word outside them, kept from a hand-written `.env`,
    /// is sent as the nearest level rather than as a flag the CLI rejects.
    public static let claudeEffortLevels = ["low", "medium", "high", "xhigh", "max"]

    static func claudeEffort(_ written: String) -> String {
        let word = written.trimmingCharacters(in: .whitespaces).lowercased()
        if claudeEffortLevels.contains(word) { return word }
        switch word {
        case "minimal", "none", "off": return "low"
        case "maximum", "ultra", "ultrathink": return "max"
        case "extra-high", "extra_high", "very-high": return "xhigh"
        default: return "high"
        }
    }

    /// The prompt with each attachment named in front as `@path`, one a
    /// line, then a blank line: how Claude Code, agy and Ollama's Claude
    /// are pointed at files.
    public static func promptWithAttachments(_ prompt: String, _ attachments: [NexusAgentAttachment]) -> String {
        guard !attachments.isEmpty else { return prompt }
        let references = attachments.map { "@" + $0.url.path }.joined(separator: "\n")
        return references + "\n\n" + prompt
    }

    /// The last `count` non-empty lines of a log.
    public static func tail(_ text: String, count: Int = 20) -> [String] {
        guard count > 0 else { return [] }
        return Array(text.components(separatedBy: .newlines).filter { !$0.isEmpty }.suffix(count))
    }

    /// A PID file's process id, or nil when it holds anything else.
    public static func processID(fromPIDFile text: String) -> Int32? {
        guard let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return nil }
        return pid
    }

    /// `agy models` prints a "Fetching…" line, then `id<TAB>name` rows.
    public static func parseModels(_ raw: String) -> [(id: String, name: String)] {
        raw.split(separator: "\n").compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.lowercased().hasPrefix("fetching") else { return nil }
            let parts = text.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let id = parts.first, !id.isEmpty else { return nil }
            return (id, parts.count > 1 && !parts[1].isEmpty ? parts[1] : id)
        }
    }

    /// Built-in model catalog for `route`, offered immediately before or
    /// without running the provider's CLI.
    public static func defaultModels(for route: NexusAgentProviderRoute) -> [NexusAgentModelOption] {
        switch route {
        case .antigravity:
            return [
                NexusAgentModelOption(id: "gemini-4-argon-high", name: "Gemini 4 Argon (High)", group: "Gemini"),
                NexusAgentModelOption(id: "gemini-4-argon-medium", name: "Gemini 4 Argon (Medium)", group: "Gemini"),
                NexusAgentModelOption(id: "gemini-4-argon-low", name: "Gemini 4 Argon (Low)", group: "Gemini"),
                NexusAgentModelOption(id: "gemini-3.8-flash-high", name: "Gemini 3.8 Flash (High)", group: "Gemini"),
                NexusAgentModelOption(id: "gemini-3.8-flash-medium", name: "Gemini 3.8 Flash (Medium)", group: "Gemini"),
                NexusAgentModelOption(id: "gemini-3.8-flash-low", name: "Gemini 3.8 Flash (Low)", group: "Gemini"),
                NexusAgentModelOption(id: "claude-opus-5-5-high", name: "Claude Opus 5.5 (High)", group: "Claude"),
                NexusAgentModelOption(id: "claude-opus-5-5-medium", name: "Claude Opus 5.5 (Medium)", group: "Claude"),
                NexusAgentModelOption(id: "claude-opus-5-5-low", name: "Claude Opus 5.5 (Low)", group: "Claude"),
                NexusAgentModelOption(id: "claude-sonnet-5-5-high", name: "Claude Sonnet 5.5 (High)", group: "Claude"),
                NexusAgentModelOption(id: "claude-sonnet-5-5-medium", name: "Claude Sonnet 5.5 (Medium)", group: "Claude"),
                NexusAgentModelOption(id: "claude-sonnet-5-5-low", name: "Claude Sonnet 5.5 (Low)", group: "Claude"),
                NexusAgentModelOption(id: "gpt-oss-120b-medium", name: "GPT-OSS 120B (Medium)", group: "GPT"),
            ]
        case .claude:
            return [
                NexusAgentModelOption(id: "sonnet", name: "Claude Sonnet (Latest)", group: "Aliases"),
                NexusAgentModelOption(id: "opus", name: "Claude Opus (Latest)", group: "Aliases"),
                NexusAgentModelOption(id: "haiku", name: "Claude Haiku (Latest)", group: "Aliases"),
                NexusAgentModelOption(id: "claude-opus-5-5", name: "Claude Opus 5.5", group: "Pinned Versions"),
                NexusAgentModelOption(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", group: "Pinned Versions"),
                NexusAgentModelOption(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", group: "Pinned Versions"),
                NexusAgentModelOption(id: "claude-opus-4-7", name: "Claude Opus 4.7", group: "Pinned Versions"),
                NexusAgentModelOption(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", group: "Pinned Versions"),
            ]
        case .opencode:
            return [
                NexusAgentModelOption(id: "anthropic/claude-opus-5-5", name: "claude-opus-5-5", group: "Anthropic"),
                NexusAgentModelOption(id: "anthropic/claude-sonnet-5-5", name: "claude-sonnet-5-5", group: "Anthropic"),
                NexusAgentModelOption(id: "anthropic/claude-haiku-5-5", name: "claude-haiku-5-5", group: "Anthropic"),
                NexusAgentModelOption(id: "anthropic/claude-opus-4-7", name: "claude-opus-4-7", group: "Anthropic"),
                NexusAgentModelOption(id: "anthropic/claude-sonnet-4-6", name: "claude-sonnet-4-6", group: "Anthropic"),
                NexusAgentModelOption(id: "openai/gpt-6.1-sol", name: "gpt-6.1-sol", group: "OpenAI"),
                NexusAgentModelOption(id: "openai/gpt-6-astra", name: "gpt-6-astra", group: "OpenAI"),
                NexusAgentModelOption(id: "openai/gpt-5.4", name: "gpt-5.4", group: "OpenAI"),
                NexusAgentModelOption(id: "openai/gpt-5.3-codex", name: "gpt-5.3-codex", group: "OpenAI"),
                NexusAgentModelOption(id: "opencode/big-pickle", name: "big-pickle", group: "OpenCode"),
                NexusAgentModelOption(id: "opencode/deepseek-v4.1-flash-free", name: "deepseek-v4.1-flash-free", group: "OpenCode"),
            ]
        case .ollama:
            return [
                NexusAgentModelOption(id: "gemma4:26b", name: "gemma4:26b"),
                NexusAgentModelOption(id: "qwen3.5:35b", name: "qwen3.5:35b"),
                NexusAgentModelOption(id: "qwen3:latest", name: "qwen3:latest"),
                NexusAgentModelOption(id: "llama3.2:latest", name: "llama3.2:latest"),
            ]
        case .custom:
            return []
        }
    }

    /// `opencode models` prints one `provider/model` identifier per line.
    public static func parseOpenCodeModels(_ raw: String) -> [NexusAgentModelOption] {
        var seen = Set<String>()
        var options: [NexusAgentModelOption] = []
        for line in raw.components(separatedBy: .newlines) {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  !text.lowercased().hasPrefix("fetching"),
                  !text.contains(" "),
                  !text.contains("\t") else { continue }
            guard seen.insert(text).inserted else { continue }
            if let slash = text.firstIndex(of: "/") {
                let rawGroup = String(text[..<slash])
                let name = String(text[text.index(after: slash)...])
                guard !rawGroup.isEmpty, !name.isEmpty else { continue }
                let group: String
                switch rawGroup.lowercased() {
                case "anthropic": group = "Anthropic"
                case "openai": group = "OpenAI"
                case "google": group = "Google"
                case "gemini": group = "Gemini"
                case "opencode": group = "OpenCode"
                case "xai": group = "xAI"
                case "deepseek": group = "DeepSeek"
                case "mistral": group = "Mistral"
                default: group = rawGroup.capitalized
                }
                options.append(NexusAgentModelOption(id: text, name: name, group: group))
            } else {
                options.append(NexusAgentModelOption(id: text, name: text))
            }
        }
        return options
    }

    /// `ollama list` prints a `NAME ...` header followed by one model row per line.
    public static func parseOllamaModels(_ raw: String) -> [NexusAgentModelOption] {
        var seen = Set<String>()
        var options: [NexusAgentModelOption] = []
        for (index, line) in raw.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let name = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init),
                  !name.isEmpty else { continue }
            if index == 0 && name.uppercased() == "NAME" { continue }
            guard seen.insert(name).inserted else { continue }
            options.append(NexusAgentModelOption(id: name, name: name))
        }
        return options
    }

    /// Parses live CLI model output for `route`.
    public static func parseModelOptions(for route: NexusAgentProviderRoute, raw: String) -> [NexusAgentModelOption] {
        switch route {
        case .antigravity:
            return parseModels(raw).map { item in
                let lower = item.id.lowercased()
                let group: String?
                if lower.hasPrefix("gemini") {
                    group = "Gemini"
                } else if lower.hasPrefix("claude") {
                    group = "Claude"
                } else if lower.hasPrefix("gpt") {
                    group = "GPT"
                } else {
                    group = nil
                }
                return NexusAgentModelOption(id: item.id, name: item.name, group: group)
            }
        case .opencode:
            return parseOpenCodeModels(raw)
        case .ollama:
            return parseOllamaModels(raw)
        case .claude:
            return defaultModels(for: .claude)
        case .custom:
            return []
        }
    }
}

/// A selectable LLM model option for a coding agent provider.
public struct NexusAgentModelOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let group: String?

    public init(id: String, name: String, group: String? = nil) {
        self.id = id
        self.name = name
        self.group = group
    }
}

/// An interactive tool execution approval request.
public struct NexusAgentApprovalRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let toolName: String
    public let commandOrPath: String
    public var status: Status

    public enum Status: String, Sendable, Equatable {
        case pending
        case approved
        case denied
        case sessionAllowed = "session_allowed"
    }

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        commandOrPath: String,
        status: Status = .pending
    ) {
        self.id = id
        self.toolName = toolName
        self.commandOrPath = commandOrPath
        self.status = status
    }
}

/// How full the model's context window is, as Claude Code shows it: what the
/// latest step of the conversation sent and got back. Every step sends the
/// whole conversation again, so this is the latest step's tokens, never a sum
/// across steps (which would count the history once per step).
public struct NexusAgentContextUsage: Equatable, Sendable, Codable {
    /// Input tokens not read from or written to the prompt cache.
    public let inputTokens: Int
    /// Input tokens read from the prompt cache plus those written to it.
    public let cachedTokens: Int
    public let outputTokens: Int
    /// The most the model holds. 0 while not yet known: the session fills
    /// it in from the provider and model (`resolved`).
    public let contextWindow: Int
    /// True when counted from the text's length because no provider said
    /// how many tokens were used.
    public let isEstimate: Bool

    public init(inputTokens: Int, cachedTokens: Int, outputTokens: Int, contextWindow: Int,
                isEstimate: Bool = false) {
        self.inputTokens = max(0, inputTokens)
        self.cachedTokens = max(0, cachedTokens)
        self.outputTokens = max(0, outputTokens)
        self.contextWindow = max(0, contextWindow)
        self.isEstimate = isEstimate
    }

    public var totalTokens: Int { inputTokens + cachedTokens + outputTokens }

    public var usedFraction: Double {
        min(1.0, max(0.0, Double(totalTokens) / Double(max(1, contextWindow))))
    }

    /// Whole percent, 0 to 100. Any use at all shows as at least 1%, so a
    /// started conversation never reads as empty.
    public var usedPercent: Int {
        let percent = Int((usedFraction * 100.0).rounded())
        return totalTokens > 0 ? min(100, max(1, percent)) : 0
    }

    /// "850", "33.4k", "142k", "1.2M".
    public var compactTokens: String { Self.compact(totalTokens) }

    /// "33.4k · 17%", with "~" in front of an estimate.
    public var badgeLabel: String {
        "\(isEstimate ? "~" : "")\(compactTokens) · \(usedPercent)%"
    }

    /// The exact counts, for the badge's tooltip.
    public var tooltipText: String {
        let head = "Context: \(Self.grouped(totalTokens)) / \(Self.grouped(contextWindow)) tokens (\(usedPercent)%)"
        if isEstimate {
            return head + "\nEstimated from the conversation's length; the agent has not reported its tokens yet."
        }
        return head + "\nInput: \(Self.grouped(inputTokens)) · Cached: \(Self.grouped(cachedTokens))"
            + " · Output: \(Self.grouped(outputTokens))"
    }

    /// The same counts with a window filled in when it is not yet known.
    public func resolved(model: String?, provider: NexusAgentCLIProvider) -> NexusAgentContextUsage {
        guard contextWindow <= 0 else { return self }
        return with(contextWindow: Self.defaultContextWindow(for: model, provider: provider))
    }

    public func with(contextWindow: Int) -> NexusAgentContextUsage {
        NexusAgentContextUsage(inputTokens: inputTokens, cachedTokens: cachedTokens, outputTokens: outputTokens,
                               contextWindow: contextWindow, isEstimate: isEstimate)
    }

    /// One step's share of counts summed over `steps` steps, when only the
    /// sum is known. An average: the last step, which is the one that
    /// matters, is usually larger.
    public static func perStep(input: Int, cached: Int, output: Int, steps: Int?,
                               contextWindow: Int = 0) -> NexusAgentContextUsage? {
        guard input + cached + output > 0 else { return nil }
        let steps = max(1, steps ?? 1)
        return NexusAgentContextUsage(inputTokens: input / steps, cachedTokens: cached / steps,
                                      outputTokens: output / steps, contextWindow: contextWindow)
    }

    /// A Claude message's `usage`. When its top-level input counts are
    /// zero, its last `iterations` entry holds the step's.
    public static func claude(usage: [String: Any], contextWindow: Int = 0) -> NexusAgentContextUsage? {
        func count(_ object: [String: Any], _ key: String) -> Int { (object[key] as? NSNumber)?.intValue ?? 0 }
        func inputs(_ object: [String: Any]) -> Int {
            count(object, "input_tokens") + count(object, "cache_read_input_tokens")
                + count(object, "cache_creation_input_tokens")
        }
        var source = usage
        if inputs(usage) == 0, let last = (usage["iterations"] as? [[String: Any]])?.last { source = last }
        let usage = NexusAgentContextUsage(
            inputTokens: count(source, "input_tokens"),
            cachedTokens: count(source, "cache_read_input_tokens") + count(source, "cache_creation_input_tokens"),
            outputTokens: count(source, "output_tokens"),
            contextWindow: contextWindow)
        return usage.totalTokens > 0 ? usage : nil
    }

    /// An OpenCode step's `tokens`: `input`, `output` and `cache.read` and
    /// `cache.write`. Reasoning is not kept in the context, so not counted.
    public static func openCode(tokens: [String: Any], contextWindow: Int = 0) -> NexusAgentContextUsage? {
        func count(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
        let cache = tokens["cache"] as? [String: Any] ?? [:]
        let usage = NexusAgentContextUsage(
            inputTokens: count(tokens["input"]),
            cachedTokens: count(cache["read"]) + count(cache["write"]),
            outputTokens: count(tokens["output"]),
            contextWindow: contextWindow)
        return usage.totalTokens > 0 ? usage : nil
    }

    /// A rough count for a conversation no provider has reported on: about
    /// four characters a token.
    public static func estimate(characters: Int, contextWindow: Int) -> NexusAgentContextUsage {
        NexusAgentContextUsage(inputTokens: max(1, characters / 4), cachedTokens: 0, outputTokens: 0,
                               contextWindow: contextWindow, isEstimate: true)
    }

    /// The window a model is likely to have when nothing reports it: a
    /// million for Gemini and the 1M variants, 128k for the local and
    /// smaller open models, 200k for the rest (Claude, GLM, GPT).
    public static func defaultContextWindow(for model: String?, provider: NexusAgentCLIProvider) -> Int {
        let name = (model ?? "").lowercased()
        if name.contains("1m") || name.contains("gemini") { return 1_000_000 }
        if name.contains("deepseek") || name.contains("llama") || provider.route == .ollama { return 128_000 }
        // Antigravity runs Gemini unless a model says otherwise.
        if name.isEmpty, provider.route == .antigravity { return 1_000_000 }
        return 200_000
    }

    static func compact(_ tokens: Int) -> String {
        func trimmed(_ value: Double) -> String {
            let text = String(format: "%.1f", value)
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        }
        switch tokens {
        case ..<1_000: return "\(tokens)"
        case ..<100_000: return trimmed(Double(tokens) / 1_000) + "k"
        case ..<999_500: return "\(Int((Double(tokens) / 1_000).rounded()))k"
        default: return trimmed(Double(tokens) / 1_000_000) + "M"
        }
    }

    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

public struct NexusAgentTurnMetrics: Equatable {
    public var durationMs: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedTokens: Int?
    public var numTurns: Int?
    public var toolCalls: Int?
    public var totalCostUSD: Double?
    /// One step's context use as the turn's result gives it (see
    /// `NexusAgentContextUsage.perStep`); nil when it gives no tokens.
    public var contextUsage: NexusAgentContextUsage?

    public init(
        durationMs: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cachedTokens: Int? = nil,
        numTurns: Int? = nil,
        toolCalls: Int? = nil,
        totalCostUSD: Double? = nil,
        contextUsage: NexusAgentContextUsage? = nil
    ) {
        self.durationMs = durationMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.numTurns = numTurns
        self.toolCalls = toolCalls
        self.totalCostUSD = totalCostUSD
        self.contextUsage = contextUsage
    }
}

/// One line of `agy --output-format stream-json`, Claude Code stream-json or
/// `opencode run --format json`, reduced to what the Quick Prompt shows.
public enum NexusAgentStreamEvent: Equatable {
    case started(conversationID: String?)
    case text(String)
    case tool(name: String, finished: Bool)
    case approval(NexusAgentApprovalRequest)
    case finished(status: String, response: String?, error: String?, conversationID: String?, metrics: NexusAgentTurnMetrics? = nil)
    /// How much of the context window a step that has just ended used, sent
    /// as each step ends so the meter moves during a long turn.
    case contextUsage(NexusAgentContextUsage)
    /// A tool call with its full input, so the bubble can list it while the
    /// turn runs. Sent again with the same id when more is known.
    case toolStep(NexusAgentToolStep)
    /// The result of the tool call with this id.
    case toolStepResult(id: String, output: String?, isError: Bool)
    /// Slash commands the CLI reports it accepts (names, no slash needed).
    case slashCommands([String])
    /// A piece of the model's reasoning.
    case thinking(String)
    /// How many reasoning tokens the model has used so far this turn.
    case thinkingTokens(Int)

    /// The first event of a line; nil for blank lines, non-JSON noise and
    /// events the prompt ignores. A line can hold several events (a Claude
    /// message with three tool calls); `parseAll` gives them all.
    public static func parse(_ line: String) -> NexusAgentStreamEvent? {
        parseAll(line).first
    }

    /// Every event of one line, in order. Empty for blank lines, non-JSON
    /// noise and events the prompt ignores.
    public static func parseAll(_ line: String) -> [NexusAgentStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }

        // Format 1: Antigravity stream-json (keyed by "event")
        if let event = json["event"] as? String {
            return parseAntigravity(event: event, json: json)
        }

        // Format 2: Claude Code stream-json and OpenCode JSON (keyed by "type").
        // Only OpenCode's lines carry `sessionID`.
        guard let type = json["type"] as? String else { return [] }
        if let sessionID = json["sessionID"] as? String {
            return parseOpenCode(type: type, json: json, sessionID: nonEmpty(sessionID))
        }
        return parseClaude(type: type, json: json)
    }

    /// One line of `agy --output-format stream-json`. A tool step carries
    /// its index and `tool_info` (name, parameters, and once done, output),
    /// so it is sent as a step the bubble can list; an older agy that says
    /// only the tool's name is sent as activity.
    private static func parseAntigravity(event: String, json: [String: Any]) -> [NexusAgentStreamEvent] {
        switch event {
        case "init":
            return [.started(conversationID: nonEmpty(json["conversation_id"]))]
        case "step_update":
            guard let step = json["step_update"] as? [String: Any] else { return [] }
            var events: [NexusAgentStreamEvent] = []
            if let thinking = step["thinking_delta"] as? String, !thinking.isEmpty {
                events.append(.thinking(thinking))
            }
            switch step["step_type"] as? String {
            case "agent_response", "planner_response":
                if let delta = step["text_delta"] as? String, !delta.isEmpty { events.append(.text(delta)) }
            case "tool":
                let info = step["tool_info"] as? [String: Any]
                let name = nonEmpty(step["tool_name"]) ?? nonEmpty(info?["name"]) ?? "tool"
                let done = (step["state"] as? String)?.uppercased() == "DONE"
                guard let index = step["step_index"] as? NSNumber else {
                    events.append(.tool(name: name, finished: done))
                    break
                }
                let id = "agy-\(nonEmpty(step["conversation_id"]) ?? "")-\(index.intValue)"
                let output = info?["output"] as? String
                let isError = (step["state"] as? String)?.uppercased() == "ERROR" || info?["error"] != nil
                events.append(.toolStep(.from(id: id, name: name, input: info?["parameters"] as? [String: Any],
                                              isFinished: false)))
                if done || isError {
                    events.append(.toolStepResult(id: id, output: NexusAgentToolStep.truncatedOutput(
                        output ?? nonEmpty(info?["error"])), isError: isError))
                }
            default:
                break
            }
            if let usage = step["usage"] as? [String: Any],
               let thinking = (usage["thinking_tokens"] as? NSNumber)?.intValue, thinking > 0 {
                events.append(.thinkingTokens(thinking))
            }
            return events
        case "result":
            guard let result = json["result"] as? [String: Any] else { return [] }
            var m = NexusAgentTurnMetrics()
            var hasMetrics = false
            if let secs = result["duration_seconds"] as? NSNumber {
                m.durationMs = Int(secs.doubleValue * 1000)
                hasMetrics = true
            } else if let ms = result["duration_ms"] as? NSNumber {
                m.durationMs = ms.intValue
                hasMetrics = true
            }
            if let usage = result["usage"] as? [String: Any] {
                if let t = usage["input_tokens"] as? NSNumber { m.inputTokens = t.intValue; hasMetrics = true }
                if let t = usage["output_tokens"] as? NSNumber { m.outputTokens = t.intValue; hasMetrics = true }
                if let t = usage["cache_read_tokens"] as? NSNumber { m.cachedTokens = t.intValue; hasMetrics = true }
            }
            if let t = result["input_tokens"] as? NSNumber { m.inputTokens = t.intValue; hasMetrics = true }
            if let t = result["output_tokens"] as? NSNumber { m.outputTokens = t.intValue; hasMetrics = true }
            if let t = result["cached_tokens"] as? NSNumber { m.cachedTokens = t.intValue; hasMetrics = true }
            if let turns = result["num_turns"] as? NSNumber { m.numTurns = turns.intValue; hasMetrics = true }
            if let tools = result["tool_calls"] as? NSNumber { m.toolCalls = tools.intValue; hasMetrics = true }
            m.contextUsage = NexusAgentContextUsage.perStep(
                input: m.inputTokens ?? 0, cached: m.cachedTokens ?? 0, output: m.outputTokens ?? 0,
                steps: m.numTurns)
            return [.finished(status: (result["status"] as? String) ?? "",
                              response: nonEmpty(result["response"]),
                              error: nonEmpty(result["error"]),
                              conversationID: nonEmpty(result["conversation_id"]),
                              metrics: hasMetrics ? m : nil)]
        default:
            return []
        }
    }

    /// The `system` subtypes that are a real request for the user's
    /// permission. A tool call alone is not one: in `-p` mode Claude Code
    /// either runs it or refuses it by its permission mode.
    static let permissionSubtypes: Set<String> = ["permission_request", "permission_prompt", "can_use_tool"]

    /// One line of Claude Code `--output-format stream-json --verbose
    /// --include-partial-messages`. Text and thinking come as deltas
    /// (`stream_event`); the whole `assistant` message that follows repeats
    /// them, so only its tool calls and usage are read. Lines a subagent
    /// sent (`parent_tool_use_id` set) are left out of the reply.
    private static func parseClaude(type: String, json: [String: Any]) -> [NexusAgentStreamEvent] {
        let fromSubagent = nonEmpty(json["parent_tool_use_id"]) != nil
        switch type {
        case "system":
            let subtype = json["subtype"] as? String ?? ""
            if permissionSubtypes.contains(subtype) { return approval(from: json).map { [$0] } ?? [] }
            if subtype == "thinking_tokens" {
                guard let count = (json["estimated_tokens"] as? NSNumber)?.intValue, !fromSubagent else { return [] }
                return [.thinkingTokens(count)]
            }
            var events: [NexusAgentStreamEvent] = []
            if let sid = nonEmpty(json["session_id"]) { events.append(.started(conversationID: sid)) }
            if subtype == "init", let names = json["slash_commands"] as? [String] {
                events.append(.slashCommands(names))
            } else if subtype == "commands_changed", let commands = json["commands"] as? [Any] {
                let names = commands.compactMap { ($0 as? [String: Any])?["name"] as? String ?? $0 as? String }
                events.append(.slashCommands(names))
            }
            return events
        case "permission_request":
            return approval(from: json).map { [$0] } ?? []
        case "control_request":
            guard let request = json["request"] as? [String: Any],
                  permissionSubtypes.contains(request["subtype"] as? String ?? "") else { return [] }
            var merged = request
            merged["id"] = request["tool_use_id"] ?? json["request_id"]
            return approval(from: merged).map { [$0] } ?? []
        case "stream_event":
            guard !fromSubagent, let innerEvent = json["event"] as? [String: Any],
                  let innerType = innerEvent["type"] as? String else { return [] }
            switch innerType {
            case "content_block_delta":
                guard let delta = innerEvent["delta"] as? [String: Any] else { return [] }
                switch delta["type"] as? String {
                case "text_delta":
                    guard let text = delta["text"] as? String, !text.isEmpty else { return [] }
                    return [.text(text)]
                case "thinking_delta":
                    guard let thinking = delta["thinking"] as? String, !thinking.isEmpty else { return [] }
                    return [.thinking(thinking)]
                default:
                    return []
                }
            case "content_block_start":
                // The tool is starting: activity only. The step itself, with
                // its whole input, comes in the `assistant` message after it.
                guard let block = innerEvent["content_block"] as? [String: Any],
                      (block["type"] as? String) == "tool_use",
                      let name = nonEmpty(block["name"]) else { return [] }
                return [.tool(name: name, finished: false)]
            default:
                return []
            }
        case "assistant":
            guard !fromSubagent, let message = json["message"] as? [String: Any] else { return [] }
            var events: [NexusAgentStreamEvent] = []
            // A step of the turn has ended; its usage is what it sent and got.
            if let usage = message["usage"] as? [String: Any], let context = NexusAgentContextUsage.claude(usage: usage) {
                events.append(.contextUsage(context))
            }
            for block in message["content"] as? [[String: Any]] ?? [] where (block["type"] as? String) == "tool_use" {
                guard let id = nonEmpty(block["id"]) else { continue }
                events.append(.toolStep(.from(id: id, name: nonEmpty(block["name"]) ?? "tool",
                                              input: block["input"] as? [String: Any])))
            }
            return events
        case "user":
            guard !fromSubagent, let message = json["message"] as? [String: Any] else { return [] }
            return (message["content"] as? [[String: Any]] ?? []).compactMap { block in
                guard (block["type"] as? String) == "tool_result", let id = nonEmpty(block["tool_use_id"]) else {
                    return nil
                }
                return .toolStepResult(id: id,
                                       output: NexusAgentToolStep.truncatedOutput(
                                           NexusAgentToolStep.resultText(block["content"])),
                                       isError: (block["is_error"] as? Bool) ?? false)
            }
        case "result":
            var m = NexusAgentTurnMetrics()
            var hasMetrics = false
            if let ms = json["duration_ms"] as? NSNumber {
                m.durationMs = ms.intValue
                hasMetrics = true
            }
            if let cost = json["total_cost_usd"] as? NSNumber {
                m.totalCostUSD = cost.doubleValue
                hasMetrics = true
            }
            if let usage = json["usage"] as? [String: Any] {
                if let t = usage["input_tokens"] as? NSNumber { m.inputTokens = t.intValue; hasMetrics = true }
                if let t = usage["output_tokens"] as? NSNumber { m.outputTokens = t.intValue; hasMetrics = true }
                if let t = usage["cache_read_input_tokens"] as? NSNumber { m.cachedTokens = t.intValue; hasMetrics = true }
                else if let t = usage["cache_read_tokens"] as? NSNumber { m.cachedTokens = t.intValue; hasMetrics = true }
            }
            if let turns = json["num_turns"] as? NSNumber { m.numTurns = turns.intValue; hasMetrics = true }
            // `usage` is summed over the turn's steps; `modelUsage` names the
            // window of each model used, the main one with the most input.
            var thinkingTokens: Int?
            if let usage = json["usage"] as? [String: Any] {
                func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
                let models = (json["modelUsage"] as? [String: [String: Any]] ?? [:]).values
                let main = models.max { a, b in
                    func inputs(_ m: [String: Any]) -> Int {
                        ["inputTokens", "cacheReadInputTokens", "cacheCreationInputTokens"]
                            .reduce(0) { $0 + ((m[$1] as? NSNumber)?.intValue ?? 0) }
                    }
                    return inputs(a) < inputs(b)
                }
                m.contextUsage = NexusAgentContextUsage.perStep(
                    input: count("input_tokens"),
                    cached: count("cache_read_input_tokens") + count("cache_creation_input_tokens"),
                    output: count("output_tokens"), steps: m.numTurns,
                    contextWindow: (main?["contextWindow"] as? NSNumber)?.intValue ?? 0)
                thinkingTokens = ((usage["output_tokens_details"] as? [String: Any])?["thinking_tokens"]
                    as? NSNumber)?.intValue
            }
            let isError = (json["is_error"] as? Bool) ?? false
            let resultText = json["result"] as? String
            var events: [NexusAgentStreamEvent] = [.finished(
                status: (json["stop_reason"] as? String) ?? (isError ? "error" : "completed"),
                response: resultText,
                error: isError ? (resultText ?? "Error") : nil,
                conversationID: nonEmpty(json["session_id"]),
                metrics: hasMetrics ? m : nil
            )]
            // The turn's exact count, after the estimates sent while it ran.
            if let thinkingTokens, thinkingTokens > 0 { events.append(.thinkingTokens(thinkingTokens)) }
            return events
        default:
            return []
        }
    }

    /// An explicit permission prompt as an approval card: the tool, and
    /// the command or file it wants.
    private static func approval(from json: [String: Any]) -> NexusAgentStreamEvent? {
        guard let name = nonEmpty(json["tool_name"]) ?? nonEmpty(json["name"]) ?? nonEmpty(json["tool"]) else {
            return nil
        }
        let input = json["input"] as? [String: Any] ?? json["tool_input"] as? [String: Any]
        let step = NexusAgentToolStep.from(id: "", name: name, input: input)
        let preview: String
        switch step.kind {
        case .bash: preview = (input?["command"] as? String) ?? ""
        case .edit, .write, .read: preview = step.filePath ?? ""
        default: preview = (input?["description"] as? String) ?? (step.title == name ? "" : step.title)
        }
        let id = nonEmpty(json["id"]) ?? nonEmpty(json["tool_use_id"]) ?? nonEmpty(json["request_id"]) ?? UUID().uuidString
        return .approval(NexusAgentApprovalRequest(id: id, toolName: name, commandOrPath: preview, status: .pending))
    }

    /// One line of `opencode run --format json`. A turn is one or more
    /// steps; a step that ends to call tools (`tool-calls`) is not the end
    /// of the turn, so only the step that ends any other way finishes it.
    /// Its tokens and cost are that last step's. Every step's tokens are
    /// sent on as context use (`.contextUsage`). Reasoning parts, which
    /// OpenCode prints with `--thinking`, are sent as thinking.
    private static func parseOpenCode(type: String, json: [String: Any], sessionID: String?) -> [NexusAgentStreamEvent] {
        let part = json["part"] as? [String: Any] ?? [:]
        switch type {
        case "step_start":
            return sessionID.map { [.started(conversationID: $0)] } ?? []
        case "text":
            guard let text = part["text"] as? String, !text.isEmpty else { return [] }
            return [.text(text)]
        case "reasoning":
            guard let text = part["text"] as? String, !text.isEmpty else { return [] }
            return [.thinking(text)]
        case "tool_use":
            let name = nonEmpty(part["tool"]) ?? nonEmpty(part["name"]) ?? "tool"
            let state = part["state"] as? [String: Any]
            let status = (state?["status"] as? String)?.lowercased() ?? ""
            let finished = ["completed", "error", "done"].contains(status)
            guard let id = nonEmpty(part["callID"]) ?? nonEmpty(part["id"]) else {
                return [.tool(name: name, finished: finished)]
            }
            var events: [NexusAgentStreamEvent] = [
                .toolStep(.from(id: id, name: name, input: state?["input"] as? [String: Any])),
            ]
            if finished {
                let output = nonEmpty(state?["output"]) ?? nonEmpty(state?["error"])
                events.append(.toolStepResult(id: id, output: NexusAgentToolStep.truncatedOutput(output),
                                              isError: status == "error"))
            }
            return events
        case "step_finish":
            let reason = (part["reason"] as? String) ?? ""
            let tokens = part["tokens"] as? [String: Any]
            let reasoning = (tokens?["reasoning"] as? NSNumber)?.intValue ?? 0
            let thinking: [NexusAgentStreamEvent] = reasoning > 0 ? [.thinkingTokens(reasoning)] : []
            // A step that ends to call tools does not end the turn, but the
            // context it used is shown at once.
            guard !["tool-calls", "tool_calls"].contains(reason) else {
                return (tokens.flatMap { NexusAgentContextUsage.openCode(tokens: $0) }.map { [.contextUsage($0)] } ?? [])
                    + thinking
            }
            var m = NexusAgentTurnMetrics()
            var hasMetrics = false
            if let tokens {
                if let t = tokens["input"] as? NSNumber { m.inputTokens = t.intValue; hasMetrics = true }
                if let t = tokens["output"] as? NSNumber { m.outputTokens = t.intValue; hasMetrics = true }
                if let t = (tokens["cache"] as? [String: Any])?["read"] as? NSNumber {
                    m.cachedTokens = t.intValue; hasMetrics = true
                }
                // The last step's own tokens, not a sum.
                m.contextUsage = NexusAgentContextUsage.openCode(tokens: tokens)
            }
            if let cost = part["cost"] as? NSNumber { m.totalCostUSD = cost.doubleValue; hasMetrics = true }
            return [.finished(status: reason.isEmpty ? "completed" : reason, response: nil, error: nil,
                              conversationID: sessionID, metrics: hasMetrics ? m : nil)] + thinking
        case "error":
            let error = json["error"]
            let detail = error as? [String: Any]
            let message = nonEmpty(error) ?? nonEmpty(detail?["message"])
                ?? nonEmpty((detail?["data"] as? [String: Any])?["message"]) ?? nonEmpty(detail?["type"]) ?? "Error"
            return [.finished(status: "error", response: nil, error: message, conversationID: sessionID)]
        default:
            return []
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}

/// Splits a byte stream into complete lines, holding a partial last line
/// (and a UTF-8 sequence cut between reads) until the rest arrives.
public struct NexusAgentLineBuffer {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            lines.append(String(decoding: line, as: UTF8.self))
            pending = Data(pending[pending.index(after: newline)...])
        }
        return lines
    }

    /// What is left once the stream has ended.
    public mutating func finish() -> String? {
        defer { pending = Data() }
        guard !pending.isEmpty else { return nil }
        return String(decoding: pending, as: UTF8.self)
    }
}

/// An active subagent executing in the current session.
public struct NexusAgentActiveSubagent: Identifiable, Equatable, Sendable {
    public let id: String
    public let typeName: String
    public let role: String
    public let prompt: String
    public let model: String
    public let isRunning: Bool

    public init(
        id: String,
        typeName: String,
        role: String,
        prompt: String,
        model: String,
        isRunning: Bool = true
    ) {
        self.id = id
        self.typeName = typeName
        self.role = role
        self.prompt = prompt
        self.model = model
        self.isRunning = isRunning
    }
}

/// A tool execution step within an agent response.
public struct NexusAgentToolStep: Identifiable, Equatable, Sendable {
    /// What sort of tool ran, so the bubble can show a diff, a shell
    /// output block or a plain row.
    public enum Kind: String, Equatable, Sendable, Codable {
        case edit, write, bash, read, search, subagent, other
    }

    public let id: String
    public let title: String
    public let detail: String?
    public var isFinished: Bool
    public var kind: Kind
    public var filePath: String?
    public var diffOld: String?
    public var diffNew: String?
    public var output: String?
    public var isError: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        detail: String? = nil,
        isFinished: Bool = true,
        kind: Kind = .other,
        filePath: String? = nil,
        diffOld: String? = nil,
        diffNew: String? = nil,
        output: String? = nil,
        isError: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isFinished = isFinished
        self.kind = kind
        self.filePath = filePath
        self.diffOld = diffOld
        self.diffNew = diffNew
        self.output = output
        self.isError = isError
    }

    /// True when the row has something to expand into.
    public var hasDetail: Bool { diffOld != nil || diffNew != nil || output != nil }
}

extension NexusAgentToolStep {
    /// The most of a tool's output a step keeps.
    public static let outputLimit = 4_000

    /// What kind of tool `name` is, for every provider's spelling of it,
    /// ignoring case: Claude's `Edit`, OpenCode's `edit`, agy's
    /// `replace_file_content` are all edits.
    public static func kind(forToolNamed name: String) -> Kind {
        let lowered = name.lowercased()
        switch lowered {
        case "edit", "multiedit", "str_replace", "str_replace_editor", "str_replace_based_edit_tool", "edit_file",
             "replace_file_content", "multi_replace_file_content", "apply_patch", "patch", "notebookedit":
            return .edit
        case "write", "create", "write_file", "write_to_file", "create_file":
            return .write
        case "bash", "shell", "run_command", "run_shell_command", "execute", "exec", "command", "bashoutput":
            return .bash
        case "read", "view", "view_file", "read_file", "view_file_outline", "cat", "read_many_files":
            return .read
        case "grep", "glob", "search", "find", "list", "ls", "grep_search", "find_by_name", "list_dir",
             "list_directory", "codebase_search", "search_web", "websearch", "web_search", "search_files":
            return .search
        case "agent", "task", "invoke_subagent", "subagent":
            return .subagent
        default:
            if ["grep", "search", "glob", "find_"].contains(where: lowered.contains) { return .search }
            return .other
        }
    }

    /// A tool call as a step, its kind, file and diff read from `input`
    /// under each provider's own key names. agy writes every argument as
    /// JSON text (`"\"/a/b\""`), which is unwrapped first.
    public static func from(id: String, name: String, input: [String: Any]?, isFinished: Bool = false,
                            output: String? = nil, isError: Bool = false) -> NexusAgentToolStep {
        let input = (input ?? [:]).mapValues(unwrappedArgument)
        let kind = kind(forToolNamed: name)
        func text(_ keys: [String]) -> String? {
            for key in keys {
                if let value = input[key] as? String, !value.isEmpty { return value }
            }
            return nil
        }
        func firstLine(_ value: String?) -> String? {
            value?.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
        }
        let filePath = text(["file_path", "filePath", "path", "AbsolutePath", "TargetFile", "Path", "notebook_path"])
        var diffOld: String?
        var diffNew: String?
        if kind == .edit || kind == .write {
            diffOld = text(["old_string", "oldText", "oldString", "TargetContent", "Target"])
            diffNew = text(["new_string", "newText", "newString", "content", "CodeContent",
                            "ReplacementContent", "Replacement"])
            // MultiEdit and agy's multi-replace carry a list of edits.
            let edits = (input["edits"] ?? input["ReplacementChunks"]) as? [[String: Any]] ?? []
            if diffOld == nil, diffNew == nil, !edits.isEmpty {
                let olds = edits.compactMap { ($0["old_string"] ?? $0["oldString"] ?? $0["TargetContent"]) as? String }
                let news = edits.compactMap { ($0["new_string"] ?? $0["newString"] ?? $0["ReplacementContent"]) as? String }
                diffOld = olds.isEmpty ? nil : olds.joined(separator: "\n…\n")
                diffNew = news.isEmpty ? nil : news.joined(separator: "\n…\n")
            }
        }
        let summary: String?
        switch kind {
        case .bash:
            summary = firstLine(text(["command", "CommandLine", "cmd"])).map { String($0.prefix(80)) }
                ?? text(["description", "toolSummary"])
        case .subagent:
            summary = text(["description", "Role", "toolSummary"]) ?? firstLine(text(["prompt", "Prompt"]))
                .map { String($0.prefix(80)) }
        case .edit, .write, .read:
            summary = filePath ?? text(["description", "toolSummary"])
        case .search:
            summary = text(["pattern", "query", "Query", "Pattern", "SearchPath", "DirectoryPath"]) ?? filePath
                ?? text(["description", "toolSummary"])
        case .other:
            summary = text(["description", "toolSummary", "url", "Url"])
        }
        return NexusAgentToolStep(id: id, title: summary ?? name, detail: name, isFinished: isFinished,
                                  kind: kind, filePath: filePath, diffOld: diffOld, diffNew: diffNew,
                                  output: truncatedOutput(output), isError: isError)
    }

    /// `text` cut to `outputLimit` characters, nil when empty.
    public static func truncatedOutput(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        guard text.count > outputLimit else { return text }
        return String(text.prefix(outputLimit)) + "\n… (truncated)"
    }

    /// A `tool_result` block's text: a string, or `{type: text}` parts.
    public static func resultText(_ content: Any?) -> String? {
        if let text = content as? String { return text }
        if let parts = content as? [[String: Any]] {
            let texts = parts.compactMap { ($0["type"] as? String ?? "text") == "text" ? $0["text"] as? String : nil }
            return texts.isEmpty ? nil : texts.joined(separator: "\n")
        }
        return nil
    }

    /// An argument agy wrote as JSON text, decoded; anything else as it is.
    static func unwrappedArgument(_ value: Any) -> Any {
        guard let text = value as? String, let first = text.first, first == "\"" || first == "[" || first == "{",
              let data = text.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return value }
        return decoded
    }
}

/// A `/` command the composer offers: built in, or reported by the CLI.
public struct NexusAgentSlashCommand: Identifiable, Equatable, Sendable {
    public var id: String { name }
    /// Without the leading slash, e.g. `compact`.
    public let name: String
    public let description: String
    public let argumentHint: String?
    public let isBuiltIn: Bool

    public init(name: String, description: String, argumentHint: String? = nil, isBuiltIn: Bool = false) {
        self.name = name.hasPrefix("/") ? String(name.dropFirst()) : name
        self.description = description
        self.argumentHint = argumentHint
        self.isBuiltIn = isBuiltIn
    }

    public static let builtIns: [NexusAgentSlashCommand] = [
        .init(name: "compact", description: "Compact conversation context", isBuiltIn: true),
        .init(name: "clear", description: "Start a new conversation", isBuiltIn: true),
        .init(name: "cost", description: "Show token & cost breakdown", isBuiltIn: true),
        .init(name: "model", description: "Switch active LLM model", argumentHint: "<model>", isBuiltIn: true),
        .init(name: "effort", description: "Cycle reasoning effort level", isBuiltIn: true),
        .init(name: "plan", description: "Toggle read-only plan mode", isBuiltIn: true),
        .init(name: "worktree", description: "Toggle isolated git worktree mode", isBuiltIn: true),
        .init(name: "fork", description: "Fork current conversation", isBuiltIn: true),
    ]

    /// Built-ins first, then CLI-reported names not already built in.
    public static func merged(builtIns: [NexusAgentSlashCommand] = builtIns, cli names: [String]) -> [NexusAgentSlashCommand] {
        var seen = Set(builtIns.map(\.name))
        var result = builtIns
        for raw in names {
            let command = NexusAgentSlashCommand(name: raw, description: "")
            guard !command.name.isEmpty, seen.insert(command.name).inserted else { continue }
            result.append(command)
        }
        return result
    }

    /// Commands whose name starts with what follows the `/` in `draft`;
    /// empty unless the draft is a lone `/word` with no space yet.
    public static func matching(_ draft: String, in commands: [NexusAgentSlashCommand]) -> [NexusAgentSlashCommand] {
        guard draft.hasPrefix("/"), !draft.contains(where: \.isWhitespace) else { return [] }
        let query = draft.dropFirst().lowercased()
        return commands.filter { query.isEmpty || $0.name.lowercased().hasPrefix(query) }
    }
}

/// A file or screenshot attached to the next turn.
public struct NexusAgentAttachment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let isImage: Bool
    public let displayName: String

    public init(id: UUID = UUID(), url: URL, isImage: Bool? = nil, displayName: String? = nil) {
        self.id = id
        self.url = url
        let ext = url.pathExtension.lowercased()
        self.isImage = isImage ?? ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "webp", "bmp"].contains(ext)
        self.displayName = displayName ?? url.lastPathComponent
    }
}

// MARK: - Workspace files and git checkpoints

extension NexusAgentSupport {
    /// The prompt that asks a CLI to compact its conversation.
    public static let compactPrompt = "/compact"

    /// Folders the file picker never walks into when git cannot list files.
    static let skippedFolders: Set<String> = ["node_modules", ".build", "build", "dist", "DerivedData", "Pods",
                                              "vendor", "target", "__pycache__"]

    /// Where `git` is: the usual install folders, then PATH. Nil when none.
    public static func gitPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        executablePath(named: "git", pathVariable: environment["PATH"] ?? "",
                       isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                       fileExists: { FileManager.default.fileExists(atPath: $0) })
    }

    /// Runs git in `directory` and waits; nil when git cannot be run or
    /// exits non-zero. Small and synchronous: for short commands only.
    @discardableResult
    static func runGit(_ arguments: [String], in directory: String,
                       environment extra: [String: String] = [:]) -> String? {
        guard let git = gitPath() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        for (key, value) in extra { environment[key] = value }
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Files in `directory` the composer can attach, as paths relative to
    /// it: what git tracks or would track (ignored files left out), or,
    /// outside a repository, a walk that skips hidden folders, build output
    /// and `bazel-*` links. At most `limit`.
    public static func listWorkspaceFiles(in directory: String, limit: Int = 200) -> [String] {
        guard limit > 0, !directory.isEmpty else { return [] }
        if let listed = runGit(["ls-files", "--cached", "--others", "--exclude-standard"], in: directory) {
            var seen = Set<String>()
            let files = listed.split(separator: "\n").map(String.init)
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            return Array(files.prefix(limit))
        }
        let root = URL(fileURLWithPath: directory).standardizedFileURL
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [String] = []
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        for case let url as URL in walker {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true || values?.isSymbolicLink == true {
                if skippedFolders.contains(name) || name.hasPrefix("bazel-") { walker.skipDescendants() }
                if values?.isDirectory == true { continue }
            }
            if walker.level > 6 { walker.skipDescendants() }
            let path = url.standardizedFileURL.path
            files.append(path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : name)
            if files.count >= limit { break }
        }
        return files
    }

    /// The files that match `query`, ignoring case: those whose name starts
    /// with it first, then those whose name holds it, then those whose path
    /// does, each group in its original order. An empty query keeps the
    /// first `limit` as they are.
    public static func filterWorkspaceFiles(_ files: [String], query: String, limit: Int = 50) -> [String] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Array(files.prefix(limit)) }
        var prefix: [String] = [], inName: [String] = [], inPath: [String] = []
        for file in files {
            let lowered = file.lowercased()
            let name = (lowered as NSString).lastPathComponent
            if name.hasPrefix(query) { prefix.append(file) }
            else if name.contains(query) { inName.append(file) }
            else if lowered.contains(query) { inPath.append(file) }
        }
        return Array((prefix + inName + inPath).prefix(limit))
    }

    /// A snapshot of the working tree of the repository `directory` is in,
    /// before a turn, for Undo Turn: a commit (not on any branch) holding
    /// every file git tracks or would track, changed or not, made through a
    /// copy of the index so the user's own index is not touched. Nil when
    /// `directory` is not in a git repository or git cannot be run.
    ///
    /// The commit is unreferenced, so `git gc` may prune it after its
    /// expiry (two weeks by default): fine for undoing a recent turn.
    public static func gitCheckpoint(in directory: String) -> String? {
        guard let top = runGit(["rev-parse", "--show-toplevel"], in: directory)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty,
              let indexPath = runGit(["rev-parse", "--path-format=absolute", "--git-path", "index"], in: top)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let scratch = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("nexus-agent-checkpoint-\(UUID().uuidString).index")
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        // A copy of the real index keeps git's file-stat cache, so adding
        // everything only reads the files that changed.
        if FileManager.default.fileExists(atPath: indexPath) {
            try? FileManager.default.copyItem(atPath: indexPath, toPath: scratch)
        }
        let scratchIndex = ["GIT_INDEX_FILE": scratch]
        guard runGit(["add", "-A", "--", ":/"], in: top, environment: scratchIndex) != nil,
              let tree = runGit(["write-tree"], in: top, environment: scratchIndex)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !tree.isEmpty else { return nil }
        var commit = ["commit-tree", tree, "-m", "nexus-agent checkpoint"]
        if let head = runGit(["rev-parse", "--verify", "-q", "HEAD"], in: top)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty {
            commit += ["-p", head]
        }
        let identity = ["GIT_AUTHOR_NAME": "Nexus Agent", "GIT_AUTHOR_EMAIL": "nexus-agent@localhost",
                        "GIT_COMMITTER_NAME": "Nexus Agent", "GIT_COMMITTER_EMAIL": "nexus-agent@localhost"]
        let sha = runGit(commit, in: top, environment: identity)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (sha?.isEmpty ?? true) ? nil : sha
    }

    /// Puts the working tree back as `gitCheckpoint` found it. It restores
    /// every file the checkpoint holds, deletes tracked files it does not
    /// hold, and deletes files that are new since it and not ignored.
    ///
    /// It does NOT touch the index (what is staged), commits, branches or
    /// HEAD, ignored files (build output, `.env`), or anything outside the
    /// repository. A commit the turn made stays; only the files go back.
    /// False when `sha` is not a commit here or git fails.
    @discardableResult
    public static func restoreGitCheckpoint(_ sha: String, in directory: String) -> Bool {
        let sha = sha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sha.isEmpty, !sha.hasPrefix("-"),
              let top = runGit(["rev-parse", "--show-toplevel"], in: directory)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty,
              runGit(["cat-file", "-e", sha + "^{commit}"], in: top) != nil,
              let snapshot = runGit(["ls-tree", "-r", "-z", "--name-only", sha], in: top) else { return false }
        let kept = Set(snapshot.split(separator: "\0").map(String.init))
        // New, unignored files the checkpoint does not have.
        let untracked = runGit(["ls-files", "-z", "--others", "--exclude-standard"], in: top)?
            .split(separator: "\0").map(String.init) ?? []
        for file in untracked where !kept.contains(file) {
            try? FileManager.default.removeItem(atPath: (top as NSString).appendingPathComponent(file))
        }
        return runGit(["restore", "--source=\(sha)", "--worktree", "--", ":/"], in: top) != nil
    }
}
