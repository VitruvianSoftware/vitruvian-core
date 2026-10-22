// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A key a menu item shows, which the view turns into the system's shortcut.
public enum MenuKey: Equatable, Sendable {
    case commandT, commandR, commandDown, commandC, commandShiftH, commandShiftF

    /// As the menu writes it.
    public var symbols: String {
        switch self {
        case .commandT: "⌘T"
        case .commandR: "⌘R"
        case .commandDown: "⌘↓"
        case .commandC: "⌘C"
        case .commandShiftH: "⌘⇧H"
        case .commandShiftF: "⌘⇧F"
        }
    }
}

/// One line of a message's menu.
public struct MessageMenuItem: Equatable, Sendable, Identifiable {
    public enum Command: Equatable, Sendable {
        case action(MessageAction)
        /// Show Replies, on a thread's root: opens the thread pane.
        case showReplies
        /// A line that only says something ("Sent at 14:02"), always greyed.
        case info
    }

    public let command: Command
    public let title: String
    public let key: MenuKey?
    public let isEnabled: Bool
    /// Why it is greyed, for an action the chat shows greyed.
    public let help: String?

    public var id: String { "\(command)|\(title)" }
}

/// What a message's menu shows (02 §3.4.2, the 4.3 subset), in its sections:
///   1. Edit… (⌘T); Reply… (⌘R) or Reply in Thread…; Show Replies (⌘↓, on a thread's root)
///   2. React…
///   3. Bookmark / Remove Bookmark
///   4. Unsend; Delete for Me… (or "Delete from This Mac and Your Phone…")
///   5. Copy (⌘C), Copy with Timestamp; Insert as Draft (others' messages); Open Link (⌘⇧H)
///   6. Forward… (⌘⇧F)
///   7. Edit History (when edited)
///   8. greyed lines: "Sent at …" or "Received at …", and "Disappears in …"
/// An action the chat shows greyed is there, off, with why (`Unavailable.reason`). Empty sections are left out.
public enum MessageMenu {
    /// - Parameters:
    ///   - available: what the message offers (`ConversationModel.availableActions(for:)`).
    ///   - disappearsIn: the countdown line ("Disappears in 1 hour"), when its timer runs.
    ///   - time: how the sent or received line writes the message's time.
    public static func sections(for message: TimelineMessage,
                                available: (actions: [MessageAction], unavailable: [Unavailable]),
                                features: ChatFeatures, disappearsIn: String?,
                                time: (Date) -> String) -> [[MessageMenuItem]] {
        let offered = Set(available.actions)
        let greyed = Dictionary(available.unavailable.map { ($0.action, $0.reason) }, uniquingKeysWith: { a, _ in a })

        func item(_ action: MessageAction) -> MessageMenuItem? {
            if offered.contains(action) {
                return MessageMenuItem(command: .action(action), title: title(of: action, features: features),
                                       key: key(of: action), isEnabled: true, help: nil)
            }
            if let reason = greyed[action] {
                return MessageMenuItem(command: .action(action), title: title(of: action, features: features),
                                       key: key(of: action), isEnabled: false, help: reason)
            }
            return nil
        }

        var first = [item(.edit), item(.reply), item(.replyInThread)].compactMap { $0 }
        if message.thread != nil, message.kind != .deleted, !message.isNote {
            first.append(MessageMenuItem(command: .showReplies, title: String(localized: "Show Replies"),
                                         key: .commandDown, isEnabled: true, help: nil))
        }
        var sections: [[MessageMenuItem]] = [
            first,
            [item(.react)].compactMap { $0 },
            [item(.bookmark), item(.removeBookmark)].compactMap { $0 },
            [item(.unsend), item(.deleteForMe)].compactMap { $0 },
            [item(.copy), item(.copyWithTimestamp), item(.insertAsDraft), item(.openFirstLink)].compactMap { $0 },
            [item(.forward)].compactMap { $0 },
            [item(.showHistory)].compactMap { $0 },
        ]
        var info: [MessageMenuItem] = []
        // A message not yet sent has no time it was sent at.
        if message.statusLine == nil || message.statusLine == .sent {
            let when = time(Date(timeIntervalSince1970: Double(message.ts) / 1000))
            let line = message.mine ? String(localized: "Sent at \(when)") : String(localized: "Received at \(when)")
            info.append(MessageMenuItem(command: .info, title: line, key: nil, isEnabled: false, help: nil))
        }
        if let disappearsIn {
            info.append(MessageMenuItem(command: .info, title: disappearsIn, key: nil, isEnabled: false, help: nil))
        }
        sections.append(info)
        return sections.filter { !$0.isEmpty }
    }

    /// An action's title in the menu.
    public static func title(of action: MessageAction, features: ChatFeatures) -> String {
        switch action {
        case .edit: String(localized: "Edit…")
        case .reply: String(localized: "Reply…")
        case .replyInThread: String(localized: "Reply in Thread…")
        case .react: String(localized: "React…")
        case .bookmark: String(localized: "Bookmark")
        case .removeBookmark: String(localized: "Remove Bookmark")
        case .unsend: String(localized: "Unsend")
        case .deleteForMe: MessageActions.deleteForMeTitle(in: features)
        case .copy: String(localized: "Copy")
        case .copyWithTimestamp: String(localized: "Copy with Timestamp")
        case .insertAsDraft: String(localized: "Insert as Draft")
        case .openFirstLink: String(localized: "Open Link")
        case .forward: String(localized: "Forward…")
        case .showHistory: String(localized: "Edit History")
        }
    }

    static func key(of action: MessageAction) -> MenuKey? {
        switch action {
        case .edit: .commandT
        case .reply: .commandR
        case .copy: .commandC
        case .openFirstLink: .commandShiftH
        case .forward: .commandShiftF
        default: nil
        }
    }
}

// MARK: - The formatting bar

/// One button of the composer's formatting bar.
public struct FormattingItem: Equatable, Sendable, Identifiable {
    public let kind: TextEntity.Kind
    public let title: String
    /// The key, as the menu writes it.
    public let keys: String
    public let isEnabled: Bool
    /// The tooltip: its name and key, or why it is off ("Spoiler (Unavailable for WhatsApp)").
    public let help: String

    public var id: TextEntity.Kind { kind }
}

/// The composer's formatting bar (01 §6): Bold, Italic, Strikethrough, Code, Code Block, Quote, Bulleted List,
/// Numbered List, Link, Spoiler. A kind the chat doesn't keep is off, saying so with the network's name.
public enum FormattingBar {
    public static let order: [TextEntity.Kind] = [
        .bold, .italic, .strikethrough, .code, .pre, .blockquote, .bulletList, .orderedList, .link, .spoiler,
    ]

    public static func items(features: ChatFeatures, network: String) -> [FormattingItem] {
        order.map { kind in
            let name = title(of: kind)
            let keys = self.keys(of: kind)
            if features.keeps(kind) {
                return FormattingItem(kind: kind, title: name, keys: keys, isEnabled: true,
                                      help: keys.isEmpty ? name : "\(name) (\(keys))")
            }
            return FormattingItem(kind: kind, title: name, keys: keys, isEnabled: false,
                                  help: unavailable(name, features: features, network: network))
        }
    }

    /// "Bold (Unavailable for WhatsApp)"; for a chat whose features aren't known yet, why.
    static func unavailable(_ name: String, features: ChatFeatures, network: String) -> String {
        guard features.source != .none else {
            return MessageActions.Reason.unknown(MessageActions.Reason.Name(network))
        }
        guard let network = NetworkNames.displayName(of: network) else {
            return String(localized: "\(name) (Unavailable for this network)")
        }
        return String(localized: "\(name) (Unavailable for \(network))")
    }

    public static func title(of kind: TextEntity.Kind) -> String {
        switch kind {
        case .bold: String(localized: "Bold")
        case .italic: String(localized: "Italic")
        case .strikethrough: String(localized: "Strikethrough")
        case .code: String(localized: "Code")
        case .pre: String(localized: "Code Block")
        case .blockquote: String(localized: "Quote")
        case .bulletList: String(localized: "Bulleted List")
        case .orderedList: String(localized: "Numbered List")
        case .link: String(localized: "Link")
        case .spoiler: String(localized: "Spoiler")
        case .mention: String(localized: "Mention")
        }
    }

    /// The keys (Task 12's table). None take ⌘K or ⌘F, which are search's.
    public static func keys(of kind: TextEntity.Kind) -> String {
        switch kind {
        case .bold: "⌘B"
        case .italic: "⌘I"
        case .strikethrough: "⌘⇧X"
        case .code: "`"
        case .pre: "⌘⌥C"
        case .blockquote: "⌘⇧9"
        case .bulletList: "⌘⇧8"
        case .orderedList: "⌘⇧7"
        case .link: "⌘⇧K"
        case .spoiler, .mention: ""
        }
    }
}

// MARK: - Lines under a message

public enum MessageLines {
    /// Under a thread's root: "1 Reply", "3 Replies".
    public static func replies(_ summary: ThreadSummary) -> String {
        summary.replies == 1 ? String(localized: "\(summary.replies) Reply")
            : String(localized: "\(summary.replies) Replies")
    }

    /// Who wrote the newest replies: "Ann", or "Ann & 2 others" (the engine names at most three, newest first).
    public static func repliers(_ summary: ThreadSummary) -> String? {
        let names = summary.lastSenders.filter { !$0.isEmpty }
        guard let first = names.first else { return nil }
        let others = names.count - 1
        if others == 0 { return first }
        return others == 1 ? String(localized: "\(first) & \(others) other")
            : String(localized: "\(first) & \(others) others")
    }

    /// Under a poll: "1 vote", "12 votes" (how many people voted).
    public static func votes(_ count: Int) -> String {
        count == 1 ? String(localized: "\(count) vote") : String(localized: "\(count) votes")
    }

    /// What a poll asks for, or that it ended.
    public static func pollHint(_ poll: PollTally) -> String {
        if poll.ended { return String(localized: "Poll ended") }
        return poll.maxSelections > 1 ? String(localized: "Select one or more options")
            : String(localized: "Select one option")
    }

    /// An option's share of the votes, 0 to 1, for its bar. With nobody voted, 0.
    public static func share(of option: PollOption, in poll: PollTally) -> Double {
        let total = poll.options.reduce(0) { $0 + $1.votes }
        guard total > 0 else { return 0 }
        return Double(option.votes) / Double(total)
    }
}

// MARK: - The link dialog

/// What the link dialog takes as an address.
public enum LinkAddress {
    /// The address as sent: with a scheme, as typed; without one, https. Nil for one the engine wouldn't send (not
    /// http, https or mailto, or with a space).
    public static func url(from typed: String) -> URL? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = hasScheme(trimmed) ? trimmed : "https://" + trimmed
        guard RichTextHTML.isSafeURL(candidate), let url = URL(string: candidate) else { return nil }
        return url
    }

    /// "https:", "mailto:", "javascript:": letters (then letters, digits, +, - or .) and a colon not followed by a
    /// digit. "example.test:8080/x" is a host and port, with no scheme.
    static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }) else { return false }
        // The schemes Courier sends are schemes whatever follows them ("mailto:2fast@example.test").
        if ["http", "https", "mailto"].contains(scheme.lowercased()) { return true }
        let after = text[text.index(after: colon)...]
        return !(after.first?.isNumber ?? false)
    }
}

// MARK: - Send later

/// What Send Later and Reschedule take: a time at least a minute from now, and at most five years ahead (the
/// engine's rule). Anything else is said, never moved: the person picks again.
public enum ScheduleTime {
    public static func problem(with due: Date, now: Date, calendar: Calendar = .current) -> String? {
        if due < now {
            return String(localized: "That time has passed. Choose a later one.")
        }
        if due < now.addingTimeInterval(60) {
            return String(localized: "Pick a time at least a minute from now.")
        }
        if let last = calendar.date(byAdding: .year, value: 5, to: now), due > last {
            return String(localized: "Choose a time within 5 years.")
        }
        return nil
    }
}
