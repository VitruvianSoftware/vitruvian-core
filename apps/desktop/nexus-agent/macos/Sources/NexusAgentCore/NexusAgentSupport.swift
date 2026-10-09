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
    case low, medium, high

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

    public static let builtIns: [NexusAgentCLIProvider] = [.antigravity, .claude, .ollama]

    /// The providers a user can pick from, given what the app has saved.
    /// The three built in come first, in their fixed order, each with its
    /// saved command if the user edited it; its id and name stay as they
    /// are today, so a name saved by an older version does not come back.
    /// Then the user's own, in the order they were saved. An entry marked
    /// built-in that is not one of the three is left out: it is a provider
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
    /// whatever its template says. Any other is Ollama or Claude if it is
    /// that built-in provider or the first word of its template ends in
    /// `ollama` or `claude` (so a full path counts, and so does any other
    /// word with that ending); Ollama wins when both apply. What is left is
    /// a command of the user's own, run as its template is written.
    ///
    /// For the first three the template is not run: the provider's own
    /// arguments are (`NexusAgentSupport.agentArguments`).
    public var route: NexusAgentProviderRoute {
        if id == Self.antigravity.id { return .antigravity }
        let program = commandTemplate.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces).first ?? ""
        if program.hasSuffix("ollama") || id == Self.ollama.id { return .ollama }
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
        case .antigravity, .custom: return "agy"
        }
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
    public var effort: NexusAgentEffort
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
        var effort = NexusAgentEffort.parse(values[effortKey])
        if effort == .automatic, values["GEMINI_THINKING"]?.lowercased() == "true" {
            effort = .high
        }
        return NexusAgentConfiguration(
            botToken: values[tokenKey] ?? "",
            allowedUserIDs: values[allowedUsersKey] ?? "",
            workingDirectory: compat("WORKING_DIR") ?? "",
            approvalMode: .parse(compat("APPROVAL_MODE")),
            model: compat("MODEL") ?? "",
            effort: effort)
    }

    /// The file with the page's values written in. An existing file keeps its
    /// comments, its order and every key the page does not own; a key it
    /// lacks is added at the end. With no file yet, the bot's template is
    /// written, so the result matches what the standalone app produced.
    public static func render(_ configuration: NexusAgentConfiguration, over existing: String?) -> String {
        let wanted = assignments(for: configuration)
        guard let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return template(wanted)
        }
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

    /// A template cut into words, placeholders not yet filled in. Also how
    /// the session names the program it could not find, as written.
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
    /// standalone app has it. A command of the user's own has no arguments
    /// here: `providerCommand` makes them from its template.
    public static func agentArguments(prompt: String, configuration: NexusAgentConfiguration,
                                       conversationID: String?,
                                       planMode: Bool = false,
                                       worktreeMode: Bool = false,
                                       ollamaDefaultModel: String = NexusAgentSupport.ollamaFallbackModel) -> [String] {
        let route = configuration.activeProvider.route
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
            if let conversationID, !conversationID.isEmpty {
                args += ["--resume", conversationID]
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
            if let conversationID, !conversationID.isEmpty {
                innerArgs += ["--resume", conversationID]
            }
            return args + ["--"] + innerArgs
        }
        var arguments = ["-p", prompt, "--output-format", "stream-json"]
        if planMode {
            arguments += ["--mode", "plan"]
        } else {
            arguments += configuration.approvalMode.agyArguments
        }
        let model = configuration.model.trimmingCharacters(in: .whitespaces)
        if !model.isEmpty { arguments += ["--model", model] }
        if configuration.effort != .automatic { arguments += ["--effort", configuration.effort.rawValue] }
        if let conversationID, !conversationID.isEmpty { arguments += ["--conversation", conversationID] }
        return arguments
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

public struct NexusAgentTurnMetrics: Equatable {
    public var durationMs: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedTokens: Int?
    public var numTurns: Int?
    public var toolCalls: Int?
    public var totalCostUSD: Double?

    public init(
        durationMs: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cachedTokens: Int? = nil,
        numTurns: Int? = nil,
        toolCalls: Int? = nil,
        totalCostUSD: Double? = nil
    ) {
        self.durationMs = durationMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.numTurns = numTurns
        self.toolCalls = toolCalls
        self.totalCostUSD = totalCostUSD
    }
}

/// One line of `agy --output-format stream-json` or Claude Code stream-json, reduced to what the Quick
/// Prompt shows.
public enum NexusAgentStreamEvent: Equatable {
    case started(conversationID: String?)
    case text(String)
    case tool(name: String, finished: Bool)
    case approval(NexusAgentApprovalRequest)
    case finished(status: String, response: String?, error: String?, conversationID: String?, metrics: NexusAgentTurnMetrics? = nil)

    /// Nil for blank lines, non-JSON noise and events the prompt ignores.
    public static func parse(_ line: String) -> NexusAgentStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        // Format 1: Antigravity stream-json (keyed by "event")
        if let event = json["event"] as? String {
            switch event {
            case "init":
                return .started(conversationID: nonEmpty(json["conversation_id"]))
            case "step_update":
                guard let step = json["step_update"] as? [String: Any] else { return nil }
                switch step["step_type"] as? String {
                case "agent_response":
                    guard let delta = step["text_delta"] as? String, !delta.isEmpty else { return nil }
                    return .text(delta)
                case "tool":
                    let name = nonEmpty(step["tool_name"]) ?? "tool"
                    return .tool(name: name, finished: (step["state"] as? String)?.uppercased() == "DONE")
                default:
                    return nil
                }
            case "result":
                guard let result = json["result"] as? [String: Any] else { return nil }
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
                return .finished(status: (result["status"] as? String) ?? "",
                                 response: nonEmpty(result["response"]),
                                 error: nonEmpty(result["error"]),
                                 conversationID: nonEmpty(result["conversation_id"]),
                                 metrics: hasMetrics ? m : nil)
            default:
                return nil
            }
        }

        // Format 2: Claude Code stream-json (keyed by "type")
        guard let type = json["type"] as? String else { return nil }
        switch type {
        case "system":
            if let sid = nonEmpty(json["session_id"]) {
                return .started(conversationID: sid)
            }
            return nil
        case "stream_event":
            guard let innerEvent = json["event"] as? [String: Any],
                  let innerType = innerEvent["type"] as? String else { return nil }
            switch innerType {
            case "content_block_delta":
                guard let delta = innerEvent["delta"] as? [String: Any],
                      let deltaType = delta["type"] as? String, deltaType == "text_delta",
                      let text = delta["text"] as? String, !text.isEmpty else { return nil }
                return .text(text)
            case "content_block_start":
                guard let block = innerEvent["content_block"] as? [String: Any],
                      let blockType = block["type"] as? String, blockType == "tool_use",
                      let name = nonEmpty(block["name"]) else { return nil }
                let toolInput = block["input"] as? [String: Any]
                let toolId = (block["id"] as? String) ?? UUID().uuidString
                let preview: String
                if name == "Bash" {
                    preview = (toolInput?["command"] as? String) ?? ""
                } else if name == "Edit" || name == "Write" || name == "Read" {
                    preview = (toolInput?["file_path"] as? String) ?? ""
                } else {
                    preview = (toolInput?["description"] as? String) ?? ""
                }
                return .approval(NexusAgentApprovalRequest(id: toolId, toolName: name, commandOrPath: preview, status: .pending))
            default:
                return nil
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
            let isError = (json["is_error"] as? Bool) ?? false
            let resultText = json["result"] as? String
            return .finished(
                status: (json["stop_reason"] as? String) ?? (isError ? "error" : "completed"),
                response: resultText,
                error: isError ? (resultText ?? "Error") : nil,
                conversationID: nonEmpty(json["session_id"]),
                metrics: hasMetrics ? m : nil
            )
        default:
            return nil
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
    public let id: String
    public let title: String
    public let detail: String?
    public let isFinished: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        detail: String? = nil,
        isFinished: Bool = true
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isFinished = isFinished
    }
}
