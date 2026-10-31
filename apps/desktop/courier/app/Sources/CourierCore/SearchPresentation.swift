// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// How a search result's row reads: its date, where its chat is, who sent it and the groups a person is in.

/// A found message's date: the time today, the day and month this year, else the whole date.
public enum SearchDate {
    public static func text(forMillis millis: Int64, now: Date = Date(), calendar: Calendar = .current,
                            locale: Locale = .current,
                            timeFormat: TimeFormatPreference = .system) -> String {
        guard millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            if timeFormat != .system {
                return timeFormat.formatTime(date, locale: locale, timeZone: calendar.timeZone)
            }
            return date.formatted(style.hour().minute())
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(style.month(.abbreviated).day())
        }
        return date.formatted(style.year().month(.abbreviated).day())
    }
}

extension ChatPlace {
    /// The tag a result outside the inbox carries; nil in the inbox (and for a place this app doesn't know).
    public var tag: String? {
        switch self {
        case .archive: String(localized: "Archived")
        case .lowPriority: String(localized: "Low priority")
        case .hidden: String(localized: "Hidden")
        case .requests: String(localized: "Request")
        default: nil
        }
    }
}

extension InboxRow {
    /// Where the chat is, decided as the engine decides a message's place: hidden, then a request, then low
    /// priority, then archived, else the inbox.
    public var place: ChatPlace {
        if hidden { return .hidden }
        if request { return .requests }
        if lowPriority { return .lowPriority }
        if archived { return .archive }
        return .inbox
    }
}

extension PersonHit {
    /// "In <group>", or "In <group> and N other groups".
    public var groupsLine: String {
        let others = groups - 1
        switch others {
        case ...0: return String(localized: "In \(roomName)")
        case 1: return String(localized: "In \(roomName) and 1 other group")
        default: return String(localized: "In \(roomName) and \(others) other groups")
        }
    }
}

extension MessageHit {
    /// Who sent it: "You" for mine, else their name (their ID when they have none).
    public var senderLine: String {
        if mine { return String(localized: "You") }
        return senderName.isEmpty ? sender : senderName
    }
}
