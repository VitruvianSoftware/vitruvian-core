// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// What a message row can ask for. The conversation gives each its call; a preview gives none.
struct MessageActions {
    var select: (String) -> Void = { _ in }
    var reply: (String) -> Void = { _ in }
    var react: (String, String) -> Void = { _, _ in }
    var retry: (String) -> Void = { _ in }
    var discard: (String) -> Void = { _ in }
}

/// One row of the timeline: a day, the "New" divider or a message.
struct TimelineItemView: View {
    let item: TimelineItem
    let isSelected: Bool
    /// The message a search result opened the chat at.
    var isHighlighted = false
    let showsSent: Bool
    let actions: MessageActions

    var body: some View {
        switch item {
        case let .dateSeparator(day):
            DaySeparator(day: day)
        case .newDivider:
            NewDivider()
        case let .message(message):
            MessageRowView(message: message, isSelected: isSelected, isHighlighted: isHighlighted, showsSent: showsSent,
                           actions: actions)
        }
    }
}

private struct DaySeparator: View {
    let day: Date

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(.quaternary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityAddTraits(.isHeader)
    }

    private var label: String {
        switch DayLabel.of(day: day, now: Date()) {
        case .today: return String(localized: "Today")
        case .yesterday: return String(localized: "Yesterday")
        case let .date(date):
            let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            return sameYear ? date.formatted(.dateTime.weekday(.wide).month(.wide).day())
                : date.formatted(.dateTime.year().month(.wide).day())
        }
    }
}

private struct NewDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            line
            Text(String(localized: "New"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            line
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "New messages"))
    }

    private var line: some View {
        Rectangle().fill(Color.accentColor.opacity(0.5)).frame(height: 1)
    }
}

/// A message: the bubble with what it quotes, its reactions, and (for mine) how it went.
struct MessageRowView: View {
    let message: TimelineMessage
    let isSelected: Bool
    /// Opened at from search: a tint that fades over the highlight's time.
    var isHighlighted = false
    let showsSent: Bool
    let actions: MessageActions
    @State private var isHovering = false
    /// The highlight's tint, from 1 to 0.
    @State private var highlight: Double = 0

    private static let avatarSize: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.mine {
                Spacer(minLength: 60)
            } else {
                avatarColumn
            }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if message.startsGroup { header }
                bubble
                if !message.reactions.isEmpty { reactions }
                if message.mine { statusLine }
            }
            if !message.mine { Spacer(minLength: 60) }
        }
        .padding(.top, message.startsGroup ? 10 : 2)
        .padding(.vertical, 1)
        .background(isSelected ? Color.accentColor.opacity(0.10) : .clear)
        .background(Color.yellow.opacity(0.28 * highlight))
        .onChange(of: isHighlighted, initial: true) { _, on in fadeHighlight(on) }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { actions.select(message.id) }
        .overlay(alignment: message.mine ? .topLeading : .topTrailing) {
            if (isHovering || isSelected) && canAct { HoverActions(message: message, actions: actions) }
        }
        .contextMenu { if canAct { menu } }
        .accessibilityElement(children: .contain)
    }

    /// Full at once, then fading out over `ConversationModel.highlightDuration`, which is as long as the model keeps
    /// the message highlighted.
    private func fadeHighlight(_ on: Bool) {
        guard on else {
            highlight = 0
            return
        }
        highlight = 1
        let parts = ConversationModel.highlightDuration.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        // On the next turn, so the full tint is drawn before it starts to fade.
        DispatchQueue.main.async {
            withAnimation(.easeIn(duration: seconds)) { highlight = 0 }
        }
    }

    /// A deleted or undecryptable message, or one that has not been sent, has nothing to reply to or react to.
    private var canAct: Bool {
        guard message.kind != .deleted, message.kind != .undecryptable else { return false }
        return message.statusLine != .sending && message.statusLine != .queued && !isFailed
    }

    private var isFailed: Bool {
        switch message.statusLine {
        case .failed, .mayHaveBeenSent, .notSent: true
        default: false
        }
    }

    // MARK: Parts

    @ViewBuilder
    private var avatarColumn: some View {
        if message.startsGroup {
            AvatarView(path: message.senderAvatarPath, initials: InboxRow.initials(of: message.senderName),
                       seed: message.senderName)
                .frame(width: Self.avatarSize, height: Self.avatarSize)
        } else {
            Color.clear.frame(width: Self.avatarSize, height: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if !message.mine {
                Text(message.senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AvatarView.color(for: message.senderName))
            }
            Text(Date(timeIntervalSince1970: Double(message.ts) / 1000), style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let reply = message.reply { QuoteView(reply: reply, onBubble: message.mine) }
            content
            if message.isEdited {
                Text(String(localized: "Edited"))
                    .font(.caption2)
                    .foregroundStyle(foreground.opacity(0.7))
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, message.kind == .image || message.kind == .sticker ? 4 : 11)
        .padding(.vertical, message.kind == .image || message.kind == .sticker ? 4 : 7)
        .background(RoundedRectangle(cornerRadius: 14).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isFailed ? Color.red : .clear, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .deleted:
            Label(String(localized: "This message was deleted"), systemImage: "trash")
                .font(.callout.italic())
                .foregroundStyle(foreground.opacity(0.75))
        case .undecryptable:
            Label(String(localized: "Waiting for this message to be decrypted"), systemImage: "lock")
                .font(.callout.italic())
                .foregroundStyle(foreground.opacity(0.75))
        case .image, .sticker:
            InlineImage(message: message)
            caption
        case .video, .voiceNote, .file:
            FileAttachmentChip(message: message)
            caption
        case .emote:
            Text(LinkedText.attributed("* \(message.senderName) \(message.body)"))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        case .text, .notice:
            Text(LinkedText.attributed(message.body))
                .fixedSize(horizontal: false, vertical: true)
                .italic(message.kind == .notice)
        case .poll:
            // The question, until the poll view (Task 12) draws its options.
            Label(message.body, systemImage: "chart.bar")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var caption: some View {
        if !message.body.isEmpty {
            Text(LinkedText.attributed(message.body))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, message.kind == .image || message.kind == .sticker ? 7 : 0)
                .padding(.bottom, message.kind == .image || message.kind == .sticker ? 3 : 0)
        }
    }

    private var fill: Color {
        if message.kind == .deleted || message.kind == .undecryptable { return Color.primary.opacity(0.06) }
        return message.mine ? Color.accentColor : Color.primary.opacity(0.09)
    }

    private var foreground: Color {
        if message.kind == .deleted || message.kind == .undecryptable { return .secondary }
        return message.mine ? .white : .primary
    }

    private var reactions: some View {
        HStack(spacing: 4) {
            ForEach(message.reactions) { chip in
                Button {
                    // Giving the same one again is not a way to take it back (that is milestone 4).
                    if !chip.mine { actions.react(message.id, chip.key) }
                } label: {
                    HStack(spacing: 3) {
                        Text(chip.key)
                        if chip.count > 1 {
                            Text("\(chip.count)").font(.caption.monospacedDigit())
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(chip.mine ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(chip.mine ? Color.accentColor : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reactionLabel(chip))
            }
        }
        .padding(.horizontal, 4)
    }

    private func reactionLabel(_ chip: ReactionChip) -> String {
        chip.mine ? String(localized: "\(chip.key), \(chip.count), including you")
            : String(localized: "\(chip.key), \(chip.count)")
    }

    @ViewBuilder
    private var statusLine: some View {
        switch message.statusLine {
        case .queued:
            Text(StatusLine.queuedLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        case let .notSent(cause):
            HStack(spacing: 8) {
                Label(String(localized: "Not sent"), systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .help(StatusLine.notSentText(cause))
                Button(String(localized: "Retry")) { actions.retry(message.id) }
                Button(String(localized: "Delete")) { actions.discard(message.id) }
            }
            .font(.caption)
            .buttonStyle(.link)
            .padding(.horizontal, 4)
        case .sending:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(String(localized: "Sending…"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        case .sent:
            if showsSent {
                Text(String(localized: "Sent"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        case let .failed(reason):
            HStack(spacing: 8) {
                Label(String(localized: "Not sent"), systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .help(reason.isEmpty ? String(localized: "The network did not take this message.") : reason)
                Button(String(localized: "Retry")) { actions.retry(message.id) }
                Button(String(localized: "Delete")) { actions.discard(message.id) }
            }
            .font(.caption)
            .buttonStyle(.link)
            .padding(.horizontal, 4)
        case .mayHaveBeenSent:
            HStack(spacing: 8) {
                Label(StatusLine.mayHaveBeenSentLabel, systemImage: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                    .help(StatusLine.mayHaveBeenSentText)
                Button(String(localized: "Retry")) { actions.retry(message.id) }
                Button(String(localized: "Delete")) { actions.discard(message.id) }
            }
            .font(.caption)
            .buttonStyle(.link)
            .padding(.horizontal, 4)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button(String(localized: "Reply")) { actions.reply(message.id) }
        Menu(String(localized: "React")) {
            ForEach(ConversationModel.quickReactions, id: \.self) { key in
                Button(key) { actions.react(message.id, key) }
            }
        }
        if message.kind == .text || message.kind == .notice || message.kind == .emote || !message.body.isEmpty {
            Button(String(localized: "Copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.body, forType: .string)
            }
        }
    }

    private var accessibilityText: String {
        let who = message.mine ? String(localized: "You") : message.senderName
        switch message.kind {
        case .deleted: return String(localized: "\(who): deleted message")
        case .undecryptable: return String(localized: "\(who): message waiting to be decrypted")
        case .image: return String(localized: "\(who): image \(message.body)")
        case .sticker: return String(localized: "\(who): sticker")
        case .video: return String(localized: "\(who): video \(message.body)")
        case .voiceNote: return String(localized: "\(who): voice note")
        case .file: return String(localized: "\(who): file \(message.fileName) \(message.body)")
        default: return "\(who): \(message.body)"
        }
    }
}

/// What a reply quotes, above its text.
private struct QuoteView: View {
    let reply: ReplyPreview
    let onBubble: Bool

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(onBubble ? Color.white.opacity(0.7) : Color.accentColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                switch reply {
                case let .quoted(quote):
                    Text(quote.mine ? String(localized: "You") : quote.senderName)
                        .font(.caption.weight(.semibold))
                    Text(preview(quote))
                        .font(.caption)
                        .lineLimit(2)
                        .opacity(0.85)
                case .notLoaded:
                    Text(String(localized: "Original message not loaded"))
                        .font(.caption.italic())
                        .opacity(0.85)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func preview(_ quote: QuotedMessage) -> String {
        if !quote.text.isEmpty { return quote.text }
        switch quote.kind {
        case .image: return String(localized: "Image")
        case .video: return String(localized: "Video")
        case .voiceNote: return String(localized: "Voice note")
        case .file: return String(localized: "File")
        case .sticker: return String(localized: "Sticker")
        case .deleted: return String(localized: "This message was deleted")
        default: return ""
        }
    }
}

/// The strip on hover: the quick reactions (the default first) and Reply.
private struct HoverActions: View {
    let message: TimelineMessage
    let actions: MessageActions

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ConversationModel.quickReactions, id: \.self) { key in
                Button(key) { actions.react(message.id, key) }
                    .buttonStyle(.plain)
                    .padding(3)
                    .help(String(localized: "React with \(key)"))
                    .accessibilityLabel(String(localized: "React with \(key)"))
            }
            Divider().frame(height: 14)
            Button {
                actions.reply(message.id)
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            }
            .buttonStyle(.plain)
            .padding(3)
            .help(String(localized: "Reply"))
            .accessibilityLabel(String(localized: "Reply"))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .padding(.top, 2)
    }
}

/// Links in a message's text. Only web and mail links are made, and a text is worked out once.
enum LinkedText {
    private final class Box { let value: AttributedString; init(_ value: AttributedString) { self.value = value } }

    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 2000
        return cache
    }()
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func attributed(_ text: String) -> AttributedString {
        if let known = cache.object(forKey: text as NSString) { return known.value }
        var result = AttributedString(text)
        let whole = NSRange(text.startIndex..., in: text)
        for match in detector?.matches(in: text, range: whole) ?? [] {
            guard let url = match.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? ""),
                  let range = Range(match.range, in: text), let target = Range(range, in: result) else { continue }
            result[target].link = url
        }
        cache.setObject(Box(result), forKey: text as NSString)
        return result
    }
}
