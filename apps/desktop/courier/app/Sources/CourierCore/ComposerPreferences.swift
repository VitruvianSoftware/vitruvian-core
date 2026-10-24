// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// What ↑ does in an empty composer.
public enum UpArrowAction: String, CaseIterable, Sendable {
    /// Moves to the messages.
    case focusMessages
    /// "Edit your last message".
    case editLast
}

/// What double-clicking a message does.
public enum MessageDoubleClickAction: String, CaseIterable, Sendable {
    case reply, nothing, reactionPicker, forward, menu
    /// Reacts with `ComposerPreferences.quickReaction`.
    case reactWith
}

/// When a message scheduled for later is still sent.
public enum SendLaterCondition: String, CaseIterable, Sendable {
    /// Only if no one else has written in the chat since it was set (or last changed).
    case ifNoReply = "if_no_reply"
    case always

    /// As the protocol has it.
    public var wire: ScheduleCondition { ScheduleCondition(rawValue: rawValue) }
}

/// The composer's settings, kept in UserDefaults under "courier.composer.<name>" (inventory 02 §1.2). They are the
/// Mac's own settings: nothing here reaches a network, though `undoSendMillis` is passed on each send as `hold_ms`.
public final class ComposerPreferences: ObservableObject {
    /// The undo-send windows, in milliseconds: the ones the engine takes (`SendParams.holdValues`). 0 is off.
    public static let undoSendValues = [0, 750, 1000, 2000, 3000, 5000, 10000]

    /// How long a sent message is held, so it can be undone. One of `undoSendValues`; 0, the default, is off.
    @Published public var undoSendMillis: Int { didSet { set(undoSendMillis, "undoSendMillis") } }
    /// Clicking a held ("Queued") message undoes it.
    @Published public var clickPendingToUndo: Bool { didSet { set(clickPendingToUndo, "clickPendingToUndo") } }
    @Published public var upArrow: UpArrowAction { didSet { set(upArrow.rawValue, "upArrow") } }
    /// The formatting bar over a selection.
    @Published public var showFormattingMenu: Bool { didSet { set(showFormattingMenu, "showFormattingMenu") } }
    @Published public var sendLaterDefault: SendLaterCondition {
        didSet { set(sendLaterDefault.rawValue, "sendLaterDefault") }
    }
    @Published public var doubleClickMessage: MessageDoubleClickAction {
        didSet { set(doubleClickMessage.rawValue, "doubleClickMessage") }
    }
    /// The emoji of "React with" and the quick reaction.
    @Published public var quickReaction: String { didSet { set(quickReaction, "quickReaction") } }
    /// Copy takes the time and sender along.
    @Published public var copyWithTimestamps: Bool { didSet { set(copyWithTimestamps, "copyWithTimestamps") } }
    /// Deleted messages leave no placeholder.
    @Published public var hideDeletedMessages: Bool { didSet { set(hideDeletedMessages, "hideDeletedMessages") } }
    /// "Incognito mode" (02 §1.2, off): opening a chat marks nothing read and sends no receipt, until I reply or mark
    /// it read by hand. Part of a plan (`Feature.incognito`): without it this does nothing. Turn it on through
    /// `ConversationModel.setIncognito`, which asks whether to also hide typing.
    @Published public var incognito: Bool { didSet { set(incognito, "incognito") } }
    /// "Show recipients I'm typing" (02 §1.2, on): my typing goes out only while this is on. Incognito's Hide Typing
    /// turns it off; Incognito itself never hides typing.
    @Published public var showTyping: Bool { didSet { set(showTyping, "showTyping") } }
    /// "Show incognito mode indicator" (02 §1.3, on): a small mark in the message box while Incognito is on.
    @Published public var showIncognitoMark: Bool { didSet { set(showIncognitoMark, "showIncognitoMark") } }
    public static let showChatUpdatesKey = "courier.chat.showChatUpdatesInTimeline"
    /// "Show chat updates in timeline" (02 §1.2, on): consecutive m.room.member events are shown as a collapsed run.
    @Published public var showChatUpdatesInTimeline: Bool {
        didSet { defaults.set(showChatUpdatesInTimeline, forKey: Self.showChatUpdatesKey) }
    }

    /// The key a setting is kept under.
    public static func key(_ name: String) -> String { "courier.composer." + name }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ name: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: Self.key(name)) as? Bool ?? fallback
        }
        func value<T: RawRepresentable>(_ name: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: Self.key(name)).flatMap(T.init(rawValue:)) ?? fallback
        }
        // A window the engine wouldn't take reads as off, never as another window.
        let millis = defaults.object(forKey: Self.key("undoSendMillis")) as? Int ?? 0
        undoSendMillis = Self.undoSendValues.contains(millis) ? millis : 0
        clickPendingToUndo = bool("clickPendingToUndo", false)
        upArrow = value("upArrow", UpArrowAction.focusMessages)
        showFormattingMenu = bool("showFormattingMenu", true)
        sendLaterDefault = value("sendLaterDefault", SendLaterCondition.ifNoReply)
        doubleClickMessage = value("doubleClickMessage", MessageDoubleClickAction.reply)
        let reaction = defaults.string(forKey: Self.key("quickReaction")) ?? ""
        quickReaction = reaction.isEmpty ? "❤️" : reaction
        copyWithTimestamps = bool("copyWithTimestamps", false)
        hideDeletedMessages = bool("hideDeletedMessages", false)
        incognito = bool("incognito", false)
        showTyping = bool("showTyping", true)
        showIncognitoMark = bool("showIncognitoMark", true)
        showChatUpdatesInTimeline = defaults.object(forKey: Self.showChatUpdatesKey) as? Bool ?? true
    }

    private func set(_ value: Any, _ name: String) {
        defaults.set(value, forKey: Self.key(name))
    }
}
