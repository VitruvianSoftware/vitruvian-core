// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// One row of the search panel: a chat, a person in a group, a message, or a recent search (01 §12's
/// GeneralSearchResults, SelectMessageCommand, SelectRecentSearchCommand).
struct SearchRowView: View {
    let item: SearchItem
    let isSelected: Bool
    let networkName: (String) -> String
    /// A row of the Bookmarks section: the message, with a bookmark beside it.
    var isBookmark = false

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear))
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
            MessageResultRow(hit: hit, isBookmark: isBookmark)
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

    var body: some View {
        HStack(spacing: 10) {
            ChatAvatar(row: row)
                .frame(width: 32, height: 32)
                .overlay(alignment: .bottomTrailing) { badge(row.network) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name.isEmpty ? String(localized: "Unnamed chat") : row.name)
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

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(path: person.avatarPath, initials: InboxRow.initials(of: person.name), seed: person.name)
                .frame(width: 32, height: 32)
                .overlay(alignment: .bottomTrailing) {
                    NetworkBadge(network: person.network, name: networkName, size: 13)
                        .background(Circle().fill(.background))
                        .offset(x: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
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

/// A message found: who sent it, in which chat, when, and the words around the match with the matches in bold.
private struct MessageResultRow: View {
    let hit: MessageHit
    var isBookmark = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if isBookmark {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(String(localized: "Bookmarked"))
                }
                Text(hit.senderLine)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(hit.roomName.isEmpty ? String(localized: "Unnamed chat") : hit.roomName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let tag = hit.place.tag { PlaceTag(text: tag) }
                Spacer(minLength: 6)
                Text(SearchDate.text(forMillis: hit.ts))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            // The ranges are the engine's UTF-16 offsets, made bold in CourierCore (Ruling 3).
            Text(hit.highlightedSnippet)
                .font(.callout)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 4)
    }
}

/// A photo or video found, in the Media grid: its thumbnail, with its date on hover.
struct MediaCell: View {
    let hit: MessageHit
    let isSelected: Bool
    @State private var image: CGImage?

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
            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3))
        .contentShape(Rectangle())
        .help(Text(verbatim: "\(hit.senderLine) · \(hit.roomName) · \(SearchDate.text(forMillis: hit.ts))"))
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
