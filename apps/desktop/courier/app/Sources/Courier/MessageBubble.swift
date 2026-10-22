// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// What a message row can ask for. The conversation (or the thread pane) gives each its call; a preview gives none.
struct MessageActions {
    var select: (String) -> Void = { _ in }
    var reply: (String) -> Void = { _ in }
    var react: (String, String) -> Void = { _, _ in }
    var retry: (String) -> Void = { _ in }
    var discard: (String) -> Void = { _ in }
    /// The message's menu, in its sections (`MessageMenu`).
    var menu: (TimelineMessage) -> [[MessageMenuItem]] = { _ in [] }
    /// A menu item chosen, for the message.
    var perform: (MessageMenuItem.Command, String) -> Void = { _, _ in }
    /// A held ("Queued") message clicked: undoes it, when the preference says so.
    var undoHeld: ((String) -> Void)?
    /// A poll's options chosen ([] takes my vote back).
    var vote: (String, [String]) -> Void = { _, _ in }
    /// A thread's root: its replies, in the pane. Nil in the pane itself, which shows them already.
    var openThread: ((String) -> Void)?
    /// The note for a timer-change message, in Courier's words.
    var timerNote: (TimelineMessage) -> String? = { _ in nil }
    /// Who to name beside a call note: the caller, in a group; nil in a one-to-one chat.
    var callCaller: (TimelineMessage) -> String? = { _ in nil }
    /// "Disappears in …", for a message whose timer runs.
    var disappearsIn: (TimelineMessage) -> String? = { _ in nil }
    /// The chat's disappearing-timer choices and how to set one, for "Change Setting" on a timer note.
    var timerChoices: () -> [DisappearingChoice] = { [] }
    var setTimer: (DisappearingChoice) -> Void = { _ in }
    /// A double click, as Settings ▸ Messages says.
    var doubleClick: (String) -> Void = { _ in }
    /// A double click shows the message's menu, beside it.
    var doubleClickShowsMenu = false
}

/// What the message rows show that is no model's: which messages have their edits open below them, the versions
/// read for them, and whose spoilers were clicked. One per timeline (the chat's, the thread pane's).
@MainActor
final class MessageUI: ObservableObject {
    @Published var historyOpen: Set<String> = []
    @Published var versions: [String: [Version]] = [:]
    @Published var revealed: Set<String> = []
    /// Reads a message's versions (message.history).
    var history: (String) async -> [Version] = { _ in [] }
    private var reading: Set<String> = []

    /// Opens or closes a message's edits below it, reading them the first time.
    func toggleHistory(_ id: String) {
        if historyOpen.contains(id) {
            historyOpen.remove(id)
        } else {
            historyOpen.insert(id)
            loadHistory(id)
        }
    }

    func showHistory(_ id: String) {
        historyOpen.insert(id)
        loadHistory(id)
    }

    /// Reads the versions once (again after an edit adds one: see `forget`).
    func loadHistory(_ id: String) {
        guard versions[id] == nil, reading.insert(id).inserted else { return }
        Task {
            let read = await history(id)
            reading.remove(id)
            if !read.isEmpty { versions[id] = read }
        }
    }

    /// A message edited again: its versions are read anew.
    func forget(_ id: String) {
        versions[id] = nil
    }

    func revealedBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { self.revealed.contains(id) }, set: { if $0 { self.revealed.insert(id) } else { self.revealed.remove(id) } })
    }
}

/// One row of the timeline: a day, the "New" divider, a timer-change note or a message.
struct TimelineItemView: View {
    let item: TimelineItem
    let isSelected: Bool
    /// The message a search result opened the chat at.
    var isHighlighted = false
    let showsSent: Bool
    let actions: MessageActions
    @ObservedObject var ui: MessageUI

    var body: some View {
        switch item {
        case let .dateSeparator(day):
            DaySeparator(day: day)
        case .newDivider:
            NewDivider()
        case let .message(message):
            if message.timerChange != nil {
                TimerNoteRow(message: message, isSelected: isSelected, actions: actions)
            } else if let call = message.call {
                CallNoteRow(message: message, call: call, isSelected: isSelected, actions: actions)
            } else {
                MessageRowView(message: message, isSelected: isSelected, isHighlighted: isHighlighted,
                               showsSent: showsSent, actions: actions, ui: ui)
            }
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

/// The bridge's note that the chat's disappearing timer changed, in Courier's words, as a line across the timeline:
/// no bubble, no Sent mark. Its menu has Delete for Me, and "Change Setting" opens the timer's choices.
private struct TimerNoteRow: View {
    let message: TimelineMessage
    let isSelected: Bool
    let actions: MessageActions

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
            Text(actions.timerNote(message) ?? String(localized: "Disappearing messages changed"))
                .fixedSize(horizontal: false, vertical: true)
            let choices = actions.timerChoices()
            if !choices.isEmpty {
                Menu(ConversationModel.changeSettingTitle) {
                    DisappearingItems(choices: choices, set: actions.setTimer)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.10) : .clear))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { actions.select(message.id) }
        .contextMenu { MessageMenuItems(sections: actions.menu(message)) { actions.perform($0, message.id) } }
        .accessibilityElement(children: .combine)
    }
}

/// A bridge's notice of a call, in Courier's words, as a line across the timeline like a timer note: it is something
/// that happened, not anyone's words, so no bubble and no Sent mark. In a group, the caller's name is beside it; a
/// one-to-one chat needs none. Its menu has Delete for Me.
private struct CallNoteRow: View {
    let message: TimelineMessage
    let call: CallNote
    let isSelected: Bool
    let actions: MessageActions

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: call.symbol)
                .accessibilityHidden(true)
            Text(verbatim: message.body)
                .fixedSize(horizontal: false, vertical: true)
            if let caller = actions.callCaller(message) {
                Text(verbatim: "·").foregroundStyle(.tertiary).accessibilityHidden(true)
                Text(verbatim: caller)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.10) : .clear))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { actions.select(message.id) }
        .contextMenu { MessageMenuItems(sections: actions.menu(message)) { actions.perform($0, message.id) } }
        .accessibilityElement(children: .combine)
    }
}

/// A message: the bubble with what it quotes, its reactions, its thread, and (for mine) how it went.
struct MessageRowView: View {
    let message: TimelineMessage
    let isSelected: Bool
    /// Opened at from search: a tint that fades over the highlight's time.
    var isHighlighted = false
    let showsSent: Bool
    let actions: MessageActions
    @ObservedObject var ui: MessageUI
    @State private var isHovering = false
    /// The highlight's tint, from 1 to 0.
    @State private var highlight: Double = 0
    /// A double click set to show the menu.
    @State private var showsMenu = false

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
                HStack(alignment: .center, spacing: 4) {
                    if message.mine { bookmarkMark }
                    bubble
                    if !message.mine { bookmarkMark }
                }
                if message.editFailed != nil { editNotSent }
                if ui.historyOpen.contains(message.id) {
                    EditHistoryView(versions: ui.versions[message.id], mine: message.mine)
                }
                if let thread = message.thread, thread.replies > 0, let open = actions.openThread {
                    ThreadSummaryLine(summary: thread) { open(message.id) }
                }
                if !message.reactions.isEmpty { reactions }
                if message.mine { statusLine }
                if let countdown = actions.disappearsIn(message) {
                    Label(countdown, systemImage: "timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
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
        .gesture(TapGesture(count: 2).onEnded {
            guard canAct else { return }
            if actions.doubleClickShowsMenu { showsMenu = true } else { actions.doubleClick(message.id) }
        })
        .popover(isPresented: $showsMenu, arrowEdge: message.mine ? .leading : .trailing) {
            MessageMenuList(sections: actions.menu(message)) { command in
                showsMenu = false
                actions.perform(command, message.id)
            }
        }
        // A message edited again has a new version to read.
        .onChange(of: message.editCount) { _, _ in
            ui.forget(message.id)
            if ui.historyOpen.contains(message.id) { ui.loadHistory(message.id) }
        }
        .simultaneousGesture(TapGesture().onEnded { click() })
        .overlay(alignment: message.mine ? .topLeading : .topTrailing) {
            if (isHovering || isSelected) && canAct { HoverActions(message: message, actions: actions) }
        }
        .contextMenu { MessageMenuItems(sections: actions.menu(message)) { actions.perform($0, message.id) } }
        .accessibilityElement(children: .contain)
    }

    /// A click selects the message; on a held one, with "Click pending messages to undo send" on, it undoes it.
    private func click() {
        if message.statusLine == .queued, let undo = actions.undoHeld {
            undo(message.id)
        } else {
            actions.select(message.id)
        }
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

    @ViewBuilder
    private var bookmarkMark: some View {
        if message.bookmarked {
            Image(systemName: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help(String(localized: "Bookmarked"))
                .accessibilityLabel(String(localized: "Bookmarked"))
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 5) {
            // The message reads as one line to VoiceOver; "Edited" is a button of its own beside it, and a poll's
            // options stay buttons.
            VStack(alignment: .leading, spacing: 5) {
                if let reply = message.reply { QuoteView(reply: reply, onBubble: message.mine) }
                content
            }
            .accessibilityElement(children: message.kind == .poll ? .contain : .combine)
            // A poll is a group of its option buttons, summed up as "who: question".
            .accessibilityLabel(accessibilityText)
            if message.isEdited { editedButton }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, message.kind == .image || message.kind == .sticker ? 4 : 11)
        .padding(.vertical, message.kind == .image || message.kind == .sticker ? 4 : 7)
        .background(RoundedRectangle(cornerRadius: 14).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isFailed ? Color.red : .clear, lineWidth: 1))
        // Held for undo send: dimmed until it goes.
        .opacity(message.statusLine == .queued ? 0.55 : 1)
        .help(message.statusLine == .queued && actions.undoHeld != nil ? String(localized: "Click to unsend") : "")
        .accessibilityElement(children: .contain)
    }

    /// "Edited": opens the versions below the bubble ("Hide Edits" closes them). Its tooltip says what it first was,
    /// once read.
    private var editedButton: some View {
        Button {
            ui.toggleHistory(message.id)
        } label: {
            Text(ui.historyOpen.contains(message.id) ? String(localized: "Hide Edits") : String(localized: "Edited"))
                .font(.caption2)
                .underline(ui.historyOpen.contains(message.id))
                .foregroundStyle(foreground.opacity(0.75))
        }
        .buttonStyle(.plain)
        .onHover { if $0 { ui.loadHistory(message.id) } }
        .help(originally)
    }

    private var originally: String {
        guard let first = ui.versions[message.id]?.first else { return String(localized: "Show the earlier versions") }
        return String(localized: "Originally: \(first.rich.text)")
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
            RichTextView(rich: message.rich, onBubble: message.mine, revealed: ui.revealedBinding(message.id),
                         italic: message.kind == .notice)
        case .poll:
            if let poll = message.poll {
                PollView(poll: poll, onBubble: message.mine) { actions.vote(message.id, $0) }
            } else {
                Label(message.body, systemImage: "chart.bar")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        if !message.rich.text.isEmpty {
            RichTextView(rich: message.rich, onBubble: message.mine, revealed: ui.revealedBinding(message.id))
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

    /// My newest edit was refused: the message reads as before it, and this offers to send the edit again or drop it.
    @ViewBuilder
    private var editNotSent: some View {
        if let edit = message.failedEditID {
            HStack(spacing: 8) {
                Label(String(localized: "Edit not sent"), systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .help(editNotSentHelp)
                Button(String(localized: "Retry")) { actions.retry(edit) }
                Button(String(localized: "Discard")) { actions.discard(edit) }
            }
            .font(.caption)
            .buttonStyle(.link)
            .padding(.horizontal, 4)
        }
    }

    private var editNotSentHelp: String {
        if case let .failed(reason)? = message.editFailed, !reason.isEmpty { return reason }
        return String(localized: "The network didn’t take this edit. The message still reads as before.")
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

    private var accessibilityText: String {
        let who = message.mine ? String(localized: "You") : message.senderName
        // A spoiler not yet shown reads as "Spoiler", not as what it hides.
        let words = RichTextLayout.spoken(message.rich, revealed: ui.revealed.contains(message.id))
        switch message.kind {
        case .deleted: return String(localized: "\(who): deleted message")
        case .undecryptable: return String(localized: "\(who): message waiting to be decrypted")
        case .image: return String(localized: "\(who): image \(words)")
        case .sticker: return String(localized: "\(who): sticker")
        case .video: return String(localized: "\(who): video \(words)")
        case .voiceNote: return String(localized: "\(who): voice note")
        case .file: return String(localized: "\(who): file \(message.fileName) \(words)")
        default: return "\(who): \(words)"
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
