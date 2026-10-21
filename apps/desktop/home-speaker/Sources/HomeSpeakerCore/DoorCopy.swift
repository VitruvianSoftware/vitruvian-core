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

// MARK: - One side, in plain facts

/// One HomeSpeaker's state in plain facts, for showing the app and the
/// extension side by side before a copy (design 7.4, step 2).
///
/// It holds no token, by construction: only whether a login is there, and
/// whose. Every stored property is a flag, a count, a name or the settings
/// (which never carry a token; see `SecretStore`).
public struct DoorSnapshot: Equatable {
    /// Where announcements play.
    public enum Outputs: String, Equatable, Sendable {
        case home, thisMac, both
        /// Both switched off.
        case nowhere
    }

    /// The settings file as read, which also carries what this summary
    /// leaves out (announce volume, pausing media, speech length).
    public let settingsRead: ConfigFileRead
    /// When the settings file last changed; nil when there is none.
    public let settingsChanged: Date?
    /// Whom the Google Home login belongs to.
    public let googleEmail: String?
    public let hasHomeLogin: Bool
    public let hasChatLogin: Bool
    public let hasSlackToken: Bool
    public let hasBeeperToken: Bool
    public let hasGeminiKey: Bool
    /// A sign-in client of the person's own, used instead of the shipped one.
    public let hasOwnClient: Bool
    public let homeName: String?
    /// Speakers and displays, not counting the whole-home group.
    public let speakerCount: Int
    public let defaultSpeaker: String?
    public let outputs: Outputs
    /// "22:00 to 07:00" while quiet hours are on; nil while off.
    public let quietHours: String?
    /// The chat sources switched on, by name: "Slack", "Google Chat", "Beeper".
    public let chatSources: [String]
    public let historyCount: Int

    public init(
        settingsRead: ConfigFileRead = .missing, settingsChanged: Date? = nil, googleEmail: String? = nil,
        hasHomeLogin: Bool = false, hasChatLogin: Bool = false, hasSlackToken: Bool = false,
        hasOwnClient: Bool = false, homeName: String? = nil, speakerCount: Int = 0,
        defaultSpeaker: String? = nil, outputs: Outputs = .home, quietHours: String? = nil,
        chatSources: [String] = [], historyCount: Int = 0, hasBeeperToken: Bool = false,
        hasGeminiKey: Bool = false
    ) {
        self.settingsRead = settingsRead
        self.settingsChanged = settingsChanged
        self.googleEmail = googleEmail
        self.hasHomeLogin = hasHomeLogin
        self.hasChatLogin = hasChatLogin
        self.hasSlackToken = hasSlackToken
        self.hasBeeperToken = hasBeeperToken
        self.hasGeminiKey = hasGeminiKey
        self.hasOwnClient = hasOwnClient
        self.homeName = homeName
        self.speakerCount = speakerCount
        self.defaultSpeaker = defaultSpeaker
        self.outputs = outputs
        self.quietHours = quietHours
        self.chatSources = chatSources
        self.historyCount = historyCount
    }

    /// `profile`'s three files, read and never written: the settings through
    /// `SpeakerConfigFile.read` (not `ConfigManager`, which writes the
    /// defaults when there is no file), the sign-ins through
    /// `SecretStore.load`, and the history's length.
    public init(profile: HomeSpeakerProfile) {
        let read = SpeakerConfigFile(url: profile.settingsURL).read()
        let secrets = SecretStore(fileURL: profile.secretsURL).load()
        // A file that is missing or does not read: what this side would
        // run with, the defaults.
        let config: SpeakerConfig
        if case .loaded(let loaded) = read { config = loaded } else { config = SpeakerConfig() }

        let outputs: Outputs
        switch (config.effectiveSpeakHome, config.effectiveSpeakLocal) {
        case (true, true): outputs = .both
        case (true, false): outputs = .home
        case (false, true): outputs = .thisMac
        case (false, false): outputs = .nowhere
        }
        var quietHours: String?
        if config.quietHoursEnabled == true, let start = config.quietHoursStart, let end = config.quietHoursEnd {
            quietHours = "\(start) to \(end)"
        }
        let monitor = config.effectiveChatMonitor
        var sources: [String] = []
        if monitor.slackEnabled { sources.append("Slack") }
        if monitor.googleChatEnabled { sources.append("Google Chat") }
        if monitor.beeperEnabled { sources.append("Beeper") }

        self.init(
            settingsRead: read,
            settingsChanged: (try? FileManager.default.attributesOfItem(atPath: profile.settingsURL.path))?[
                .modificationDate] as? Date,
            googleEmail: secrets.google?.email,
            hasHomeLogin: Self.present(secrets.google?.refreshToken),
            hasChatLogin: Self.present(secrets.googleChat?.refreshToken),
            hasSlackToken: Self.present(secrets.slackToken),
            hasOwnClient: Self.present(secrets.oauthClientIdOverride),
            homeName: config.structureName,
            speakerCount: config.uniqueTargets().filter { !$0.device.isWholeHome }.count,
            defaultSpeaker: config.defaultDevice?.name,
            outputs: outputs,
            quietHours: quietHours,
            chatSources: sources,
            historyCount: BroadcastHistory(fileURL: profile.historyURL).load().count,
            hasBeeperToken: Self.present(secrets.beeperToken),
            hasGeminiKey: Self.present(secrets.geminiApiKey))
    }

    /// Set up: signed in to Google Home, with a Gemini key, with speakers,
    /// or with local speech on this Mac or this phone turned on.
    public var isSetUp: Bool {
        if case .loaded(let config) = settingsRead, config.effectiveSpeakPhone { return true }
        return hasHomeLogin || hasGeminiKey || speakerCount > 0 || outputs == .thisMac || outputs == .both
    }

    private static func present(_ value: String?) -> Bool {
        !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

// MARK: - Copying

/// Why a copy stopped before writing anything, besides a settings file that
/// does not read (`ConfigFileError`, as `SpeakerConfigFile` says it).
public enum DoorCopyError: Error, Equatable, LocalizedError {
    /// The source's sign-in file is there but does not read. Copying it
    /// would sign the destination out of everything.
    case unreadableSecrets(path: String)

    public var errorDescription: String? {
        switch self {
        case .unreadableSecrets(let path):
            return "\(path) could not be read, so nothing was copied; this one's sign-ins are as they were."
        }
    }
}

/// A copy that stopped part-way, after it had started writing: what was
/// copied, what was not, and whether the sign-ins were replaced, so the
/// destination can be told. It names no token.
public struct DoorCopyPartial: Error, Equatable, LocalizedError {
    /// A sentence for each part that was written.
    public let copied: [String]
    /// A sentence for each part that was not: the one that failed, with
    /// why, then the ones after it.
    public let notCopied: [String]
    /// The destination's sign-ins were replaced before it stopped.
    public let signInsWritten: Bool

    public init(copied: [String], notCopied: [String], signInsWritten: Bool) {
        self.copied = copied
        self.notCopied = notCopied
        self.signInsWritten = signInsWritten
    }

    public var errorDescription: String? { (copied + notCopied).joined(separator: " ") }
}

/// What a copy did, in words. It names no token: only which sign-ins came
/// along, and whose.
public struct CopyReport: Equatable {
    /// One sentence each, for the page.
    public let lines: [String]
    /// The settings were written. False when the source has none.
    public let settingsCopied: Bool
    /// The history's length after the merge.
    public let historyCount: Int
    /// How many of those came from the source.
    public let historyAdded: Int
}

/// Comparing the app and the extension, and copying one into the other
/// (design 7.4 and 7.5).
public enum DoorCopy {
    public enum Suggestion: Equatable, Sendable {
        case copyFromOther
        case keep
    }

    /// The note beside the copy buttons ("The strings").
    public static let copyNote =
        "Sign-ins are copied, never shown. macOS permissions, such as pausing music, are asked for again."

    /// Which button to mark (design 7.4, step 2):
    /// - copy, when the chosen side is not set up and the other is;
    /// - keep, when the chosen side is set up and the other is not, or
    ///   neither is;
    /// - when both are, the side whose settings changed last. A tie, or no
    ///   date to go by, keeps what the chosen side has.
    public static func suggest(chosen: DoorSnapshot, other: DoorSnapshot) -> Suggestion {
        switch (chosen.isSetUp, other.isSetUp) {
        case (false, true): return .copyFromOther
        case (true, false), (false, false): return .keep
        case (true, true):
            guard let mine = chosen.settingsChanged, let theirs = other.settingsChanged else { return .keep }
            return theirs > mine ? .copyFromOther : .keep
        }
    }

    /// Copies `source` into `destination`, leaving `source` exactly as it
    /// was, so the copy can always be undone by copying back:
    /// - the settings, through `SpeakerConfigFile.write`, so keys the
    ///   destination's file holds for others survive;
    /// - the whole `Secrets` value, in one `SecretStore.update` under the
    ///   destination's lock (0600);
    /// - the history, both lists merged by entry id, newest first, at most
    ///   `BroadcastHistory.limit`, under the destination's history lock.
    ///
    /// Everything is read and checked before anything is written. It
    /// throws, writing nothing, when either settings file does not read
    /// (`ConfigFileError`) or the source's sign-in file does not
    /// (`DoorCopyError`).
    ///
    /// The sign-ins are the whole value: copying from a side with none
    /// signs the destination out of everything. Callers must warn the
    /// person before copying from a side with no sign-ins
    /// (`DoorSnapshot.hasHomeLogin` and the rest are all false).
    ///
    /// It posts nothing. The caller tells the destination its sign-ins
    /// changed, by posting `CredentialsChangedNotice` under the
    /// destination profile's names (design 7.5), never the source's.
    ///
    /// A write that fails after the first one throws `DoorCopyPartial`,
    /// which says what was copied and what was not; the caller still tells
    /// the destination when its sign-ins were replaced.
    public static func copy(from source: HomeSpeakerProfile, to destination: HomeSpeakerProfile) throws -> CopyReport {
        let from = name(source.door)

        // Read and check everything first.
        let sourceSettings = SpeakerConfigFile(url: source.settingsURL).read()
        if case .unreadable(let why) = sourceSettings { throw why }
        let destinationFile = SpeakerConfigFile(url: destination.settingsURL)
        if case .unreadable(let why) = destinationFile.read() { throw why }
        try requireReadable(secretsAt: source.secretsURL)
        let secrets = SecretStore(fileURL: source.secretsURL).load()
        let incoming = BroadcastHistory(fileURL: source.historyURL).load()

        var lines: [String] = []
        var signInsWritten = false
        // The part that failed, with why, and the parts after it.
        func stopped(_ part: String, _ error: Error, then rest: [String]) -> DoorCopyPartial {
            DoorCopyPartial(
                copied: lines,
                notCopied: ["\(part): not copied (\(error.localizedDescription))."] + rest.map { "\($0): not copied." },
                signInsWritten: signInsWritten)
        }

        var settingsCopied = false
        if case .loaded(let config) = sourceSettings {
            do {
                try destinationFile.write(config)
            } catch {
                throw stopped("Settings", error, then: ["Sign-ins", "History"])
            }
            settingsCopied = true
            lines.append("Settings: copied from \(from).")
        } else {
            lines.append("Settings: \(from) has none saved, so this one's were kept.")
        }

        do {
            try SecretStore(fileURL: destination.secretsURL).update { $0 = secrets }
        } catch {
            throw stopped("Sign-ins", error, then: ["History"])
        }
        signInsWritten = true
        lines.append(signInLine(secrets, from: from))

        let history = BroadcastHistory(fileURL: destination.historyURL)
        let count: Int
        let added: Int
        do {
            (count, added) = try FileLock.withExclusiveLock(at: history.lockURL) { () throws -> (Int, Int) in
                let mine = history.load()
                let merged = merge(mine, incoming)
                if merged != mine {
                    try JSONEncoder().encode(merged).write(to: history.fileURL, options: .atomic)
                }
                let mineIDs = Set(mine.map(\.id))
                return (merged.count, merged.filter { !mineIDs.contains($0.id) }.count)
            }
        } catch {
            throw stopped("History", error, then: [])
        }
        lines.append("History: \(count) \(count == 1 ? "entry" : "entries"), \(added) of them from \(from).")

        lines.append("Not copied: the hooks, which are pointed at the HomeSpeaker in use, and the app's Open at Login.")
        lines.append(copyNote)
        return CopyReport(lines: lines, settingsCopied: settingsCopied, historyCount: count, historyAdded: added)
    }

    /// Both lists, each entry once (by id; `mine`'s copy wins), newest
    /// first, at most `BroadcastHistory.limit`.
    static func merge(_ mine: [BroadcastLogItem], _ incoming: [BroadcastLogItem]) -> [BroadcastLogItem] {
        var seen = Set<UUID>()
        let all = (mine + incoming).filter { seen.insert($0.id).inserted }
        let ordered = all.enumerated().sorted {
            $0.element.timestamp != $1.element.timestamp
                ? $0.element.timestamp > $1.element.timestamp : $0.offset < $1.offset
        }
        return Array(ordered.map(\.element).prefix(BroadcastHistory.limit))
    }

    private static func name(_ door: HomeSpeakerProfile.Door) -> String {
        switch door {
        case .app: return "the app"
        case .extension: return "the extension"
        }
    }

    /// Which sign-ins came along, in words; never a token.
    private static func signInLine(_ secrets: Secrets, from: String) -> String {
        var parts: [String] = []
        if let home = secrets.google, !home.refreshToken.isEmpty {
            parts.append(home.email.map { "Google Home (as \($0))" } ?? "Google Home")
        }
        if let chat = secrets.googleChat, !chat.refreshToken.isEmpty { parts.append("Google Chat") }
        if !(secrets.slackToken ?? "").isEmpty { parts.append("a Slack token") }
        if !(secrets.beeperToken ?? "").isEmpty { parts.append("a Beeper token") }
        if !(secrets.geminiApiKey ?? "").isEmpty { parts.append("a Gemini API key") }
        if !(secrets.oauthClientIdOverride ?? "").isEmpty { parts.append("an own sign-in client") }
        guard !parts.isEmpty else { return "Sign-ins: \(from) has none, so this one is now signed out." }
        let list = parts.count == 1
            ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        return "Sign-ins: copied from \(from): \(list)."
    }

    /// Throws when a sign-in file is there but does not decode as `Secrets`
    /// (`SecretStore.load` would read it as empty).
    private static func requireReadable(secretsAt url: URL) throws {
        guard let data = try? Data(contentsOf: url) else {
            if FileManager.default.fileExists(atPath: url.path) { throw DoorCopyError.unreadableSecrets(path: url.path) }
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard (try? decoder.decode(Secrets.self, from: data)) != nil else {
            throw DoorCopyError.unreadableSecrets(path: url.path)
        }
    }
}
