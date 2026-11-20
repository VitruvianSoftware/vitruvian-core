// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Pure formatting helpers shared by `AttachmentCarouselOverlay` and `MediaViewerWindow`.
public enum PhotoViewerPresentation {
    /// Display name for the sender of a photo or media hit, stripping bridge network tags and honouring redaction.
    public static func displaySender(
        sender: String,
        senderName: String,
        mine: Bool,
        redacted: Bool = false
    ) -> String {
        if mine {
            return String(localized: "You")
        }
        let cleaned = NetworkTag.stripped(senderName).trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = cleaned.isEmpty ? sender.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
        guard !raw.isEmpty else { return "" }
        return redacted ? AppearancePreferences.redactedText(raw, kind: .name) : raw
    }

    /// Formatted timestamp string for a Unix-millisecond timestamp, or `nil` when `ts <= 0`.
    public static func formattedDate(
        forMillis ts: Int64,
        locale: Locale = .current,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard ts > 0 else { return nil }
        let date = Date(timeIntervalSince1970: Double(ts) / 1000.0)
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Header attribution (`"Sender · Date"`) replacing raw filenames in photo viewers.
    public static func headerText(
        sender: String,
        senderName: String,
        mine: Bool,
        ts: Int64,
        locale: Locale = .current,
        timeZone: TimeZone = .autoupdatingCurrent,
        redacted: Bool = false
    ) -> String {
        let who = displaySender(sender: sender, senderName: senderName, mine: mine, redacted: redacted)
        let when = formattedDate(forMillis: ts, locale: locale, timeZone: timeZone)
        switch (who.isEmpty, when) {
        case let (false, date?):
            return "\(who) · \(date)"
        case (false, nil):
            return who
        case let (true, date?):
            return date
        case (true, nil):
            return ""
        }
    }

    public static func headerText(
        for item: CarouselItem,
        locale: Locale = .current,
        timeZone: TimeZone = .autoupdatingCurrent,
        redacted: Bool = false
    ) -> String {
        headerText(
            sender: item.sender,
            senderName: item.senderName,
            mine: item.mine,
            ts: item.ts,
            locale: locale,
            timeZone: timeZone,
            redacted: redacted
        )
    }

    public static func headerText(
        for hit: MediaHit,
        locale: Locale = .current,
        timeZone: TimeZone = .autoupdatingCurrent,
        redacted: Bool = false
    ) -> String {
        headerText(
            sender: hit.sender,
            senderName: hit.senderName,
            mine: hit.mine,
            ts: hit.ts,
            locale: locale,
            timeZone: timeZone,
            redacted: redacted
        )
    }

    /// Returns the trimmed caption when present and distinct from `fileName`, otherwise `nil`.
    public static func displayCaption(caption: String, fileName: String) -> String? {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCaption.isEmpty, trimmedCaption != trimmedFileName else { return nil }
        return trimmedCaption
    }
}
