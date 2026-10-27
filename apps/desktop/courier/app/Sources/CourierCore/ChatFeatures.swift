// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// What a message offers in its chat, from the chat's features (room.features), and why an action is greyed.
//
// Each network's bridge says what its chats can do, and the engine passes that on as ChatFeatures. An action a chat
// can't do at all, or can't do any more for this message (too old, edited too often), stays in the menu greyed, with
// a line that says why in Courier's words and the network's own name: "WhatsApp only lets you edit for 15 minutes",
// "Google Messages can’t unsend". No error code or bridge word reaches a person.

/// The networks' names for people, by the id the engine gives them (engine/internal/networks: Name and DisplayName).
/// A greyed line names the network; an id the app doesn't know reads as "this network", never as the raw id.
public enum NetworkNames {
    static let names: [String: String] = [
        "whatsapp": "WhatsApp",
        "signal": "Signal",
        "telegram": "Telegram",
        "gmessages": "Google Messages",
        "slack": "Slack",
    ]

    /// The network's name, or nil for an id this app doesn't know.
    public static func displayName(of network: String) -> String? {
        names[network]
    }
}

/// Something a person can do to one message, from its menu.
public enum MessageAction: Hashable, Sendable {
    case reply, replyInThread, edit, forward, copy, copyWithTimestamp, insertAsDraft
    case bookmark, removeBookmark, react, unsend, deleteForMe, openFirstLink, showHistory
    /// The chat's unread count runs from this message on, on this Mac only.
    case markUnread
    /// Marks an unplayed voice note as played, on this Mac only.
    case markAsPlayed
    /// A one-to-one chat with the message's sender, the message quoted in its composer.
    case replyPrivately
}

/// An action the message's menu shows greyed, and the line that says why.
public struct Unavailable: Equatable, Sendable {
    public let action: MessageAction
    public let reason: String

    public init(action: MessageAction, reason: String) {
        self.action = action
        self.reason = reason
    }
}

public enum MessageActions {
    /// The menu's order (inventory 02 §3.4.2, the 4.4 subset): Edit, Reply (or Reply in Thread), Reply Privately,
    /// React, Bookmark, Mark as Unread, Mark as played, Unsend, Delete for Me, Copy, Copy with Timestamp, Insert as Draft, Open Link,
    /// Forward, Edit History.
    static let order: [MessageAction] = [
        .edit, .reply, .replyInThread, .replyPrivately, .react, .bookmark, .removeBookmark, .markUnread, .markAsPlayed, .unsend,
        .deleteForMe, .copy, .copyWithTimestamp, .insertAsDraft, .openFirstLink, .forward, .showHistory,
    ]

    /// What `message` offers in a chat with `features`, in the menu's order, and the actions shown greyed with why.
    ///
    /// - Parameters:
    ///   - network: the chat's network, by the engine's id ("gmessages"). The greyed lines name it ("Google
    ///     Messages"), and one this app doesn't know reads as "this network".
    ///   - now: the time the age limits are measured at, against the message's `ts`.
    ///   - locale: how the limits' lengths read ("15 minutes").
    ///   - isDirect: the chat is one-to-one (or not known to be a group): there is no one to reply to privately.
    ///   - networkRunning: the chat's network runs this session, so a private chat can be found or made.
    ///
    /// The rules:
    ///   - Edit and Unsend are for my sent messages only (someone else's are never offered, nor greyed); Edit for
    ///     text, not files or polls. Past the chat's age or edit-count limit, or in a chat that can't, they are greyed.
    ///   - Reply is Reply in Thread where the chat's replies are thread replies (Slack); where the chat has both,
    ///     both are offered; where it has neither (an SMS chat), neither is.
    ///   - A held message (queued) offers nothing: clicking it undoes, when the preference allows. A message that
    ///     didn't go (waiting, sending, failed, not sent) offers Copy only: Don't Send, or Retry and Delete, are on
    ///     its status line. A deleted placeholder, or a message that couldn't be decrypted, can only leave this Mac.
    ///   - A note (`isNote`: a timer change, a call) offers Delete for Me only, whoever made it.
    ///   - Delete for Me is anyone's message, on this Mac (and, in Google Messages, the phone: `deleteForMeTitle`).
    ///   - Mark as Unread is any message with a place in the chat everyone sees: someone else's (a deleted or
    ///     undecryptable one too) and mine that went (my deleted one too); never a note, or mine that hasn't gone
    ///     (held, waiting, sending, failed). It stays on this Mac.
    ///   - Reply Privately is someone else's message in a group, while the network runs. Neither is ever greyed: where
    ///     it can't be done it isn't there.
    public static func available(for message: TimelineMessage, in features: ChatFeatures, network: String, now: Date,
                                 locale: Locale = .current, isDirect: Bool = true, networkRunning: Bool = false)
        -> (actions: [MessageAction], unavailable: [Unavailable]) {
        // The bridge's note that the chat's timer changed, or of a call, is not a message of anyone's to edit, reply to
        // or forward, even when it is mine (set from my phone, a call I made): it can only leave this Mac.
        if message.isNote { return ([.deleteForMe], []) }

        var offered = Set<MessageAction>()
        var greyed: [MessageAction: String] = [:]
        let hasText = !message.rich.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        switch message.statusLine {
        case .queued:
            return ([], [])
        case .waiting, .noAccount, .sending, .failed, .mayHaveBeenSent, .notSent:
            if hasText { offered.formUnion([.copy, .copyWithTimestamp]) }
            return (order.filter(offered.contains), [])
        case .sent, .delivered, .seen, nil:
            break
        }
        offered.insert(.markUnread)
        if message.kind == .voiceNote, !message.played, !message.viewOnce {
            offered.insert(.markAsPlayed)
        }
        switch message.kind {
        case .deleted, .undecryptable:
            offered.insert(.deleteForMe)
            return (order.filter(offered.contains), [])
        default:
            break
        }

        let name = Reason.Name(network)
        let unknown = features.source == .none
        let age = Int64((now.timeIntervalSince1970 * 1000).rounded()).saturatingMinus(message.ts)

        if message.mine, isEditable(message.kind) {
            if !features.edit {
                greyed[.edit] = unknown ? Reason.unknown(name) : Reason.cantEdit(name)
            } else if features.editMaxAgeMS > 0, age > features.editMaxAgeMS {
                greyed[.edit] = Reason.editAge(name, duration(features.editMaxAgeMS, locale: locale))
            } else if features.editMaxCount > 0, message.editCount >= features.editMaxCount {
                greyed[.edit] = Reason.editCount(name, features.editMaxCount)
            } else {
                offered.insert(.edit)
            }
        }

        if features.replyIsThread {
            offered.insert(.replyInThread)
        } else {
            if features.reply { offered.insert(.reply) }
            if features.thread { offered.insert(.replyInThread) }
        }
        if !message.mine, !isDirect, networkRunning { offered.insert(.replyPrivately) }
        offered.insert(.react)
        offered.insert(message.bookmarked ? .removeBookmark : .bookmark)

        if message.mine {
            if !features.unsend {
                greyed[.unsend] = unknown ? Reason.unknown(name) : Reason.cantUnsend(name)
            } else if features.unsendMaxAgeMS > 0, age > features.unsendMaxAgeMS {
                greyed[.unsend] = Reason.unsendAge(name, duration(features.unsendMaxAgeMS, locale: locale))
            } else {
                offered.insert(.unsend)
            }
        }
        offered.insert(.deleteForMe)

        if hasText {
            offered.formUnion([.copy, .copyWithTimestamp])
            if !message.mine { offered.insert(.insertAsDraft) }
            if firstLink(in: message.rich) != nil { offered.insert(.openFirstLink) }
        }
        if isForwardable(message.kind), !message.viewOnce { offered.insert(.forward) }
        if message.isEdited { offered.insert(.showHistory) }

        let unavailable = order.compactMap { action in greyed[action].map { Unavailable(action: action, reason: $0) } }
        return (order.filter(offered.contains), unavailable)
    }

    /// Delete for Me's menu title: in a chat where it also reaches the phone's own app (Google Messages), it says so.
    public static func deleteForMeTitle(in features: ChatFeatures) -> String {
        features.deleteReachesPhone
            ? String(localized: "Delete from This Mac and Your Phone…")
            : String(localized: "Delete for Me…")
    }

    /// The first link in a message, for Open Link (⌘⇧H): a link range's address, or else the first http, https or
    /// mailto address in its text.
    public static func firstLink(in rich: RichText) -> URL? {
        let text = rich.text as NSString
        var found: (offset: Int, url: URL)?
        for entity in rich.entities where entity.kind == .link {
            if let address = entity.url, let url = URL(string: address), found.map({ entity.offset < $0.offset }) ?? true {
                found = (entity.offset, url)
            }
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(location: 0, length: text.length)
            for match in detector.matches(in: rich.text, options: [], range: range) {
                guard let url = match.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else {
                    continue
                }
                if found.map({ match.range.location < $0.offset }) ?? true { found = (match.range.location, url) }
                break
            }
        }
        return found?.url
    }

    /// Text a person can edit: a text message, a notice or an emote (the engine's `editable`).
    private static func isEditable(_ kind: MessageKind) -> Bool {
        kind == .text || kind == .notice || kind == .emote
    }

    /// What the engine forwards: text and media, a sticker as an image; not a poll.
    private static func isForwardable(_ kind: MessageKind) -> Bool {
        switch kind {
        case .text, .notice, .emote, .image, .video, .file, .sticker, .voiceNote, .location: true
        case .poll, .deleted, .undecryptable: false
        }
    }

    /// A limit's length as people say it: "15 minutes", "2 days".
    public static func duration(_ millis: Int64, locale: Locale = .current) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 2
        return formatter.string(from: Double(millis) / 1000) ?? ""
    }

    /// The greyed lines. Each has a form for a network this app doesn't know, so no raw id reaches a person.
    enum Reason {
        /// A network as a greyed line names it: its name, or none for an id this app doesn't know.
        struct Name {
            let known: String?

            init(_ network: String) { known = NetworkNames.displayName(of: network) }
        }

        static func unknown(_ name: Name) -> String {
            guard let network = name.known else { return String(localized: "Not available until this network connects") }
            return String(localized: "Not available until \(network) connects")
        }

        static func cantEdit(_ name: Name) -> String {
            guard let network = name.known else { return String(localized: "This network can’t edit messages") }
            return String(localized: "\(network) can’t edit messages")
        }

        static func editAge(_ name: Name, _ duration: String) -> String {
            guard let network = name.known else {
                return String(localized: "This network only lets you edit for \(duration)")
            }
            return String(localized: "\(network) only lets you edit for \(duration)")
        }

        static func editCount(_ name: Name, _ count: Int) -> String {
            guard let network = name.known else {
                return String(localized: "This network only lets you edit a message \(count) times")
            }
            return String(localized: "\(network) only lets you edit a message \(count) times")
        }

        static func cantUnsend(_ name: Name) -> String {
            guard let network = name.known else { return String(localized: "This network can’t unsend") }
            return String(localized: "\(network) can’t unsend")
        }

        static func unsendAge(_ name: Name, _ duration: String) -> String {
            guard let network = name.known else {
                return String(localized: "This network only lets you unsend for \(duration)")
            }
            return String(localized: "\(network) only lets you unsend for \(duration)")
        }

        static func noPolls(_ name: Name) -> String {
            guard let network = name.known else { return String(localized: "Polls aren’t available on this network") }
            return String(localized: "Polls aren’t available on \(network)")
        }
    }
}

extension ChatFeatures {
    /// Whether the chat keeps formatting of `kind`; a kind it doesn't keep goes as plain text.
    public func keeps(_ kind: TextEntity.Kind) -> Bool {
        formatting.contains(kind)
    }

    /// Whether `text` is within the chat's `maxTextLength`, which counts bytes of UTF-8, not characters (an emoji
    /// is four). 0 is no limit.
    public func fits(text: String) -> Bool {
        maxTextLength <= 0 || text.utf8.count <= maxTextLength
    }

    /// Why Create Poll is greyed in this chat, or nil when the chat takes polls. `network` is the engine's id.
    public func pollsUnavailableReason(network: String) -> String? {
        guard poll == nil else { return nil }
        let name = MessageActions.Reason.Name(network)
        return source == .none ? MessageActions.Reason.unknown(name) : MessageActions.Reason.noPolls(name)
    }

    public var supportsVoiceSend: Bool {
        voiceFeatures?.supported == true
    }

    public var supportsLocationSend: Bool {
        locationSupported
    }

    public var supportsStickers: Bool {
        sticker.supported
    }

    public var supportsGIFs: Bool {
        gif.supported
    }

    public func maxSizeBytes(for msgType: String) -> Int64? {
        switch msgType {
        case "m.image": return imageFeatures?.maxSize
        case "m.video": return videoFeatures?.maxSize
        case "m.audio": return audioFeatures?.maxSize
        case "m.voice", "org.matrix.msc3245.voice": return voiceFeatures?.maxSize
        case "m.file": return fileFeatures?.maxSize
        case "fi.mau.gif": return gif.maxSize
        case "m.sticker": return sticker.maxSize
        default: return nil
        }
    }

    public func supportsCaption(for msgType: String) -> Bool {
        switch msgType {
        case "m.image": return imageFeatures?.caption == true
        case "m.video": return videoFeatures?.caption == true
        case "m.audio": return audioFeatures?.caption == true
        case "m.voice", "org.matrix.msc3245.voice": return voiceFeatures?.caption == true
        case "m.file": return fileFeatures?.caption == true
        case "fi.mau.gif": return gif.captions
        case "m.sticker": return sticker.captions
        default: return false
        }
    }
}
