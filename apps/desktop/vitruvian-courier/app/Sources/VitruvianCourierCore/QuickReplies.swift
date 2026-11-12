// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// A saved reply: typed ";" and its title in the composer, it puts its text in.
public struct QuickReply: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var text: String

    public init(id: UUID = UUID(), title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

/// Why a quick reply wasn't saved.
public enum QuickReplyError: Error, Equatable, Sendable {
    /// There are `QuickReplies.maxCount` already.
    case full
    case emptyTitle
    case titleTooLong
    case emptyText
    case textTooLong
    /// Another has the same title (folding case and accents): titles are how they're found. Inferred (inventory
    /// 02 §1.7): the inventory doesn't say whether two may share a title; one per title keeps ";title" unambiguous.
    case duplicateTitle
    /// The one to update is gone.
    case notFound
}

/// Names available when expanding quick-reply variables in a chat.
public struct QuickReplyContext: Sendable, Equatable {
    public var recipientFullName: String
    public var senderFullName: String

    public init(recipientFullName: String = "", senderFullName: String = "") {
        self.recipientFullName = recipientFullName
        self.senderFullName = senderFullName
    }

    public var recipientFirstName: String { Self.firstName(of: recipientFullName) }
    public var senderFirstName: String { Self.firstName(of: senderFullName) }

    private static func firstName(of full: String) -> String {
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }
}

/// A quick reply being added (`reply == nil`) or changed (`reply != nil`).
public struct QuickReplyEdit: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let reply: QuickReply?

    public init(id: UUID = UUID(), reply: QuickReply?) {
        self.id = id
        self.reply = reply
    }
}

/// The person's quick replies, kept on this Mac only (UserDefaults "courier.composer.quickReplies", as JSON), in the
/// order they were made.
public final class QuickReplies: ObservableObject {
    public static let key = "courier.composer.quickReplies"
    /// Where a store this version can't read is kept aside, so saving never writes over it.
    public static let unreadableKey = "courier.composer.quickReplies.unreadable"
    public static let maxCount = 100
    /// Characters.
    public static let maxTitle = 40
    /// Characters.
    public static let maxText = 16384
    /// The most `matching` gives.
    public static let maxMatches = 8

    @Published public private(set) var all: [QuickReply]
    /// Active quick reply editor sheet state in `MessagesSettingsPane`.
    @Published public var editing: QuickReplyEdit?

    private let defaults: UserDefaults
    private weak var observedLifecycle: SystemLifecycleModel?
    private var lockObserver: AnyCancellable?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.key)
        if let data = stored as? Data, let read = try? JSONDecoder().decode([QuickReply].self, from: data) {
            all = read
        } else {
            all = []
            // Unreadable (written by a newer Courier, say): kept aside once, never overwritten, rather than lost.
            if let stored, defaults.object(forKey: Self.unreadableKey) == nil {
                defaults.set(stored, forKey: Self.unreadableKey)
            }
        }
        self.lockObserver = NotificationCenter.default
            .publisher(for: SystemLifecycleModel.didLockNotification)
            .sink { [weak self] notification in
                self?.observedLifecycle = notification.object as? SystemLifecycleModel
                self?.dismissAllPresentations()
            }
    }

    public func dismissAllPresentations() {
        editing = nil
    }

    public var lifecycle: SystemLifecycleModel {
        MainActor.assumeIsolated {
            observedLifecycle ?? AppLockGate.shared.lifecycle
        }
    }

    public var isLocked: Bool {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated {
            !AppLockGate.shared.canPerform(.settingsChange, lifecycle: observedLifecycle)
        }
    }

    public func add(title: String, text: String) throws {
        guard !isLocked else { return }
        guard all.count < Self.maxCount else { throw QuickReplyError.full }
        let reply = try checked(QuickReply(title: title, text: text), replacing: nil)
        all.append(reply)
        save()
    }

    public func update(_ reply: QuickReply) throws {
        guard !isLocked else { return }
        guard let index = all.firstIndex(where: { $0.id == reply.id }) else { throw QuickReplyError.notFound }
        all[index] = try checked(reply, replacing: reply.id)
        save()
    }

    public func remove(_ id: UUID) {
        guard !isLocked else { return }
        all.removeAll { $0.id == id }
        save()
    }

    /// The replies whose title starts with `prefix`, folding case and accents, in their order; at most 8. Inferred
    /// (inventory 02 §1.7): a quick reply is found by the start of its title, not by words inside it or its text.
    public func matching(_ prefix: String) -> [QuickReply] {
        let folded = Self.fold(prefix)
        return Array(all.filter { Self.fold($0.title).hasPrefix(folded) }.prefix(Self.maxMatches))
    }

    /// Expands `{recipient.firstName}`, `{recipient.fullName}`, `{sender.firstName}` and `{sender.fullName}` using
    /// `context`. An empty name expands to `""`, never leaving the `{…}` token in the text.
    public static func expand(_ body: String, context: QuickReplyContext) -> String {
        let recipientFull = context.recipientFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let senderFull = context.senderFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return body
            .replacingOccurrences(of: "{recipient.firstName}", with: context.recipientFirstName)
            .replacingOccurrences(of: "{recipient.fullName}", with: recipientFull)
            .replacingOccurrences(of: "{sender.firstName}", with: context.senderFirstName)
            .replacingOccurrences(of: "{sender.fullName}", with: senderFull)
    }

    /// {first_name}, {last_name}, {full_name} from the other person's name in a one-to-one chat; every other {…} and
    /// these in a group stay as typed (Inferred, 02 §1.7: 4.5 adds the rest).
    ///
    /// Inferred (inventory 02 §1.7): the first name is the name's first word, the last name its last word (none for
    /// a one-word name), the full name all of it with single spaces.
    public static func fill(_ text: String, otherPerson: String?) -> String {
        let words = (otherPerson ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return text }
        let values = [
            "{first_name}": first,
            "{last_name}": words.count > 1 ? words[words.count - 1] : "",
            "{full_name}": words.joined(separator: " "),
        ]
        // One pass, so a name that itself reads "{last_name}" is never filled again.
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let candidate = rest[open...]
            if let match = values.first(where: { candidate.hasPrefix($0.key) }) {
                result += match.value
                rest = candidate.dropFirst(match.key.count)
            } else {
                result += "{"
                rest = candidate.dropFirst()
            }
        }
        return result + rest
    }

    // MARK: -

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private func checked(_ reply: QuickReply, replacing id: UUID?) throws -> QuickReply {
        var reply = reply
        reply.title = reply.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.title.isEmpty else { throw QuickReplyError.emptyTitle }
        guard reply.title.count <= Self.maxTitle else { throw QuickReplyError.titleTooLong }
        guard !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickReplyError.emptyText
        }
        guard reply.text.count <= Self.maxText else { throw QuickReplyError.textTooLong }
        let folded = Self.fold(reply.title)
        guard !all.contains(where: { $0.id != id && Self.fold($0.title) == folded }) else {
            throw QuickReplyError.duplicateTitle
        }
        return reply
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
