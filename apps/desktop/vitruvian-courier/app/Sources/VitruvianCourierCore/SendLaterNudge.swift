// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// When the message box offers "It's late — send this later?". Late is 22:00 to 06:59 on the person's own clock:
/// the hours when a message sent now will most likely wake someone.
public enum SendLaterNudge {
    /// The hour (24h) the late window opens, and the hour it is over.
    public static let lateFromHour = 22
    public static let lateUntilHour = 7

    /// True from 22:00 through 06:59 in `calendar`'s time zone.
    public static func isLate(now: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= lateFromHour || hour < lateUntilHour
    }

    /// The nudge shows when it is late, there is something to schedule, and it has not been dismissed this session.
    public static func shows(hasText: Bool, now: Date, calendar: Calendar = .current, dismissed: Bool) -> Bool {
        hasText && !dismissed && isLate(now: now, calendar: calendar)
    }
}

/// The keyboard shortcut a space on the bar answers to: Go to Space's modifier (⌃ unless changed in Settings ▸
/// Shortcuts) and the space's place on the bar, 1 to 9.
public enum SpaceShortcutLabel {
    /// `"⌃2"` for the second space; nil past the ninth, or when Switch First 9 Spaces is off (`modifier` nil).
    public static func label(position: Int, modifier: KeyChord?) -> String? {
        guard (1 ... 9).contains(position), let modifier else { return nil }
        let symbols = KeyChord(key: "", command: modifier.command, shift: modifier.shift,
                               option: modifier.option, control: modifier.control).symbols
        return symbols.isEmpty ? nil : symbols + String(position)
    }
}
