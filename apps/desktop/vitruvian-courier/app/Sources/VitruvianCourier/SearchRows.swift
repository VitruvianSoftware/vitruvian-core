// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// One row of the search panel: a chat, a person in a group, a message, or a recent search (01 §12's
/// GeneralSearchResults, SelectMessageCommand, SelectRecentSearchCommand).
struct SearchRowView: View {
    let item: SearchItem
    let isSelected: Bool
    let networkName: (String) -> String
    /// The title of the chat a found message is in, as that chat's inbox row shows it.
    var chatTitle: (MessageHit) -> String = { $0.roomName }
    /// A row of the Bookmarks section: the message, with a bookmark beside it.
    var isBookmark = false
    /// True when search is scoped to a single non-merged chat: leaves the redundant chat/network suffix off rows.
    var scopedToSingleChat = false
    @ObservedObject var composerPreferences: ComposerPreferences = ComposerPreferences()
    @Environment(\.themeAccentColor) private var themeAccent

    func formattedTimestamp(
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard case let .message(hit) = item else { return nil }
        return SearchDate.text(
            forMillis: hit.ts,
            now: now,
            calendar: calendar,
            locale: locale,
            timeFormat: composerPreferences.timeFormat
        )
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? themeAccent.opacity(0.18) : .clear))
            .padding(.horizontal, 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case let .chat(row):
            ChatResultRow(row: row, networkName: networkName(row.network))
        case let .person(person):
            PersonResultRow(person: person, networkName: networkName(person.network))
        case let .message(hit):
            MessageResultRow(hit: hit, chatTitle: chatTitle(hit), networkName: networkName(hit.network),
                             isBookmark: isBookmark, scopedToSingleChat: scopedToSingleChat,
                             timeFormat: composerPreferences.timeFormat)
        case let .recentSearch(text):
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Avatar with its network badge, name, the row's preview line, and where it is when not in the inbox.
private struct ChatResultRow: View {
    let row: InboxRow
    let networkName: String
    @Environment(\.redactNamesAndPictures) private var isRedacted

    var body: some View {
        HStack(spacing: 10) {
            ChatAvatar(row: row)
                .blur(radius: isRedacted ? 6 : 0)
                .frame(width: 32, height: 32)
                .overlay(alignment: .bottomTrailing) { badge(row.network) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(SearchRedaction.chatTitle(PhoneNumberFormat.display(NetworkTag.stripped(row.name)), redacted: isRedacted))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if let tag = row.place.tag { PlaceTag(text: tag) }
                }
                ChatPreview.text(row)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func badge(_ network: String) -> some View {
        NetworkBadge(network: network, name: networkName, size: 13)
            .background(Circle().fill(.background))
            .offset(x: 3, y: 3)
    }
}

/// Someone in a group with me: avatar, name, network badge, and the groups.
private struct PersonResultRow: View {
    let person: PersonHit
    let networkName: String
    @Environment(\.redactNamesAndPictures) private var isRedacted

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(path: person.avatarPath, initials: InboxRow.initials(of: person.name),
                       identity: AvatarColor.identity(id: person.userID, fallbackName: person.name))
                .blur(radius: isRedacted ? 6 : 0)
                .clipShape(Circle())
                .frame(width: 32, height: 32)
                .overlay(alignment: .bottomTrailing) {
                    NetworkBadge(network: person.network, name: networkName, size: 13)
                        .background(Circle().fill(.background))
                        .offset(x: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(isRedacted ? AppearancePreferences.redactedText(person.name, kind: .name) : PhoneNumberFormat.display(NetworkTag.stripped(person.name)))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(person.groupsLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// What a message row says, as styled text: where the message is, and the words around the match.
enum SearchRowText {
    /// The soft tint behind a matched word: the system's find-highlight yellow, light enough for the text over it to
    /// keep its contrast in light and in dark mode.
    static var matchTint: Color { Color(nsColor: .findHighlightColor).opacity(0.4) }

    /// "<Sender> in <chat> · <Network>": the sender strong and in the primary colour, the rest secondary.
    static func location(sender: String, line: String) -> AttributedString {
        var text = AttributedString(line)
        text.foregroundColor = .secondary
        if line.hasPrefix(sender), !sender.isEmpty, let bounds = text.range(of: sender) {
            text[bounds].foregroundColor = .primary
            text[bounds].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }

    /// The snippet with each matched word in bold on a soft tint. The ranges are the engine's, from the matching the
    /// search itself uses (case and accents ignored, a prefix of the last word), so a row highlights what made it a
    /// result and nothing else.
    static func snippet(of hit: MessageHit) -> AttributedString {
        var text = hit.highlightedSnippet
        for range in hit.matchRanges {
            guard let bounds = Range<AttributedString.Index>(range, in: text) else { continue }
            text[bounds].backgroundColor = matchTint
        }
        return text
    }
}

/// A message found: who sent it, in which chat and network, when, and the words around the match with the matches in
/// bold on a soft tint.
private struct MessageResultRow: View {
    let hit: MessageHit
    let chatTitle: String
    let networkName: String
    var isBookmark = false
    var scopedToSingleChat = false
    var timeFormat: TimeFormatPreference = .system
    @Environment(\.redactNamesAndPictures) private var isRedacted

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if isBookmark {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(String(localized: "Bookmarked"))
                }
                Text(SearchRowText.location(sender: sender, line: locationLine))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let tag = hit.place.tag { PlaceTag(text: tag) }
                Spacer(minLength: 6)
                Text(SearchDate.text(forMillis: hit.ts, timeFormat: timeFormat))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            // The ranges are the engine's UTF-16 offsets, made bold in VitruvianCourierCore (Ruling 3).
            Text(SearchRowText.snippet(of: hit))
                .font(.callout)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 4)
    }

    private var sender: String {
        isRedacted && !hit.mine ? AppearancePreferences.redactedText(hit.senderLine, kind: .name) : hit.senderLine
    }

    private var locationLine: String {
        SearchResultLocation.subtitle(
            sender: sender, chatTitle: SearchRedaction.chatTitle(chatTitle, redacted: isRedacted),
            networkName: networkName, isDirect: hit.isDirect, scopedToSingleChat: scopedToSingleChat)
    }
}

/// A photo or video found, in the Media grid: its thumbnail, with its date on hover.
struct MediaCell: View {
    let hit: MessageHit
    var chatTitle: String? = nil
    let isSelected: Bool
    var scopedToSingleChat = false
    @ObservedObject var composerPreferences: ComposerPreferences = ComposerPreferences()
    @State private var image: CGImage?
    @Environment(\.themeAccentColor) private var themeAccent

    func helpText(
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let dateText = SearchDate.text(
            forMillis: hit.ts,
            now: now,
            calendar: calendar,
            locale: locale,
            timeFormat: composerPreferences.timeFormat
        )
        if scopedToSingleChat {
            return "\(hit.senderLine) · \(dateText)"
        }
        return "\(hit.senderLine) · \(chatTitle ?? hit.roomName) · \(dateText)"
    }

    var body: some View {
        ZStack {
            Color.primary.opacity(0.06)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: hit.kind == .video ? "film" : "photo")
                    .foregroundStyle(.secondary)
            }
            if hit.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isSelected ? themeAccent : .clear, lineWidth: 3))
        .contentShape(Rectangle())
        .help(Text(verbatim: helpText()))
        .accessibilityElement()
        .accessibilityLabel(hit.kind == .video ? String(localized: "Video from \(hit.senderLine)")
            : String(localized: "Photo from \(hit.senderLine)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .task(id: hit.mediaPath) {
            image = hit.mediaPath.isEmpty ? nil : await ThumbnailLoader.shared.thumbnail(atPath: hit.mediaPath)?.image
        }
    }
}

/// "Archived", "Low priority", "Hidden", "Request": where a result outside the inbox is.
private struct PlaceTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().strokeBorder(.tertiary))
            .fixedSize()
    }
}

/// A chat's name in a search row: "Unnamed chat" for none, and with "Redact names and pictures" on, the stand-in the
/// chat list shows.
@MainActor
enum SearchRedaction {
    static func chatTitle(_ name: String, redacted: Bool) -> String {
        let raw = name.isEmpty ? String(localized: "Unnamed chat") : name
        return redacted ? AppearancePreferences.redactedText(raw, kind: .chatTitle) : raw
    }
}
