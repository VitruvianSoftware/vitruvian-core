// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// One entry of the chat header's "Disappearing Messages" menu: a timer the chat offers, or Off.
public struct DisappearingChoice: Equatable, Identifiable, Sendable {
    /// `.off` for Off.
    public let type: DisappearingType
    /// 0 for Off.
    public let timerMS: Int64
    /// What the menu says: "Off", "1 day".
    public let title: String
    /// This is the chat's timer now, as the engine reports it.
    public let isCurrent: Bool

    public var id: String { "\(type.rawValue):\(timerMS)" }

    public init(type: DisappearingType, timerMS: Int64, title: String = "", isCurrent: Bool = false) {
        self.type = type
        self.timerMS = timerMS
        self.title = title
        self.isCurrent = isCurrent
    }
}

/// A bridge's note that a chat's disappearing timer changed (bridgev2's `DisappearingMessageNotice`): a notice whose
/// English body is the bridge's, and whose `com.beeper.action_message` says what happened. The timeline keeps it
/// among the messages, so counts stay what the engine's are, and draws a note from this instead of the body.
public struct TimerChange: Equatable, Sendable {
    /// When the timer starts; `.off` when it was turned off.
    public let type: DisappearingType
    /// 0 is off.
    public let timerMS: Int64
    /// The bridge changed it by itself, because a message arrived with (or without) a timer: no person did.
    public let implicit: Bool

    public var isOff: Bool { timerMS <= 0 }

    public init(type: DisappearingType, timerMS: Int64, implicit: Bool) {
        self.type = type
        self.timerMS = timerMS
        self.implicit = implicit
    }

    /// Reads `content["com.beeper.action_message"]`; nil for any other message.
    static func of(_ content: JSONValue) -> TimerChange? {
        guard let action = content["com.beeper.action_message"], action["type"]?.stringValue == "disappearing_timer"
        else { return nil }
        let timer = max(0, action["timer"]?.integerValue ?? 0)
        let type = timer == 0 ? DisappearingType.off : DisappearingType(rawValue: action["timer_type"]?.stringValue ?? "")
        return TimerChange(type: type, timerMS: timer, implicit: action["implicit"] == .bool(true))
    }
}

/// The words and the clock arithmetic of disappearing messages (01 §5).
///
/// Lengths are said by `MessageActions.duration`, the system's formatter in the locale the model was given, as the
/// edit and unsend limits are. A countdown is coarse: whole minutes, rounded up, so it never says 0 and never
/// shows seconds.
enum Disappearing {
    /// The header: "Messages disappear after 7 days". Nil with no timer running.
    static func headerLine(for timer: DisappearingTimer?, locale: Locale) -> String? {
        guard let timer, timer.timerMS > 0 else { return nil }
        let length = MessageActions.duration(timer.timerMS, locale: locale)
        return String(localized: "Messages disappear after \(length)")
    }

    /// The menu: Off first, then the chat's timers, shortest first. Empty for a chat with no timer to set.
    static func choices(in features: ChatFeatures, locale: Locale) -> [DisappearingChoice] {
        guard let offered = features.disappearing else { return [] }
        let current = features.currentTimer.flatMap { $0.timerMS > 0 ? $0 : nil }
        var choices = [DisappearingChoice(type: .off, timerMS: 0, title: String(localized: "Off"),
                                          isCurrent: current == nil)]
        for timer in Set(offered.timersMS).filter({ $0 > 0 }).sorted() {
            choices.append(DisappearingChoice(
                type: offered.type, timerMS: timer, title: MessageActions.duration(timer, locale: locale),
                isCurrent: current?.type == offered.type && current?.timerMS == timer))
        }
        return choices
    }

    /// "Disappears in 1 hour, 30 minutes"; nil for a message with no timer running or one that has run out.
    static func countdown(expiresAt: Int64?, now: Date, locale: Locale) -> String? {
        guard let expiresAt else { return nil }
        let remaining = expiresAt - millis(now)
        guard remaining > 0 else { return nil }
        let minutes = (remaining + 59_999) / 60_000
        let length = MessageActions.duration(minutes * 60_000, locale: locale)
        return String(localized: "Disappears in \(length)")
    }

    /// The note for a timer change: who made it, and what they set. A change the bridge made by itself names no one.
    static func note(for change: TimerChange, by name: String, mine: Bool, locale: Locale) -> String {
        if change.implicit {
            guard !change.isOff else { return String(localized: "Disappearing messages were turned off.") }
            let length = MessageActions.duration(change.timerMS, locale: locale)
            return String(localized: "Messages now disappear after \(length).")
        }
        let who = mine ? String(localized: "You") : (name.isEmpty ? String(localized: "Someone") : name)
        guard !change.isOff else { return String(localized: "\(who) turned off disappearing messages.") }
        let length = MessageActions.duration(change.timerMS, locale: locale)
        return String(localized: "\(who) set messages to disappear after \(length).")
    }

    /// How long until what a timeline shows next changes with the clock, in milliseconds: a message with a timer
    /// leaves when it runs out, and its countdown steps down a minute each time the minutes left lose one. Nil when
    /// no message shown has a timer still running (one already past is for a rebuild to drop, not to wait for).
    static func millisUntilNextChange(in items: [TimelineItem], now: Date) -> Int64? {
        let nowMillis = millis(now)
        var soonest: Int64?
        for case let .message(message) in items {
            guard let expiresAt = message.expiresAt, expiresAt > nowMillis else { continue }
            let remaining = expiresAt - nowMillis
            let minutes = (remaining + 59_999) / 60_000
            // The text says `minutes` until the time left falls to one minute less; the last minute runs out.
            let until = remaining - (minutes - 1) * 60_000
            soonest = min(soonest ?? until, until)
        }
        return soonest
    }

    static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
}
