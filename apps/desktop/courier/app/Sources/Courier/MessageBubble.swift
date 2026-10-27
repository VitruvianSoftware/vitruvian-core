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
    /// Don't Send, on a message waiting for its network: takes it back, as Undo does. Nil where nothing can (a
    /// preview), and the line then has no button.
    var dontSend: ((String) -> Void)?
    /// The help on "Waiting to send": when it goes, naming the chat's network.
    var waitingHelp: () -> String = { StatusLine.waitingHelp(network: "") }
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
    /// In a merged chat, the network id of the message's underlying room; nil in a single-room chat.
    var messageNetwork: (TimelineMessage) -> String? = { _ in nil }
    /// Hovering a sender's avatar or name in a message row (`hovering, message`).
    var hoverSender: (Bool, TimelineMessage) -> Void = { _, _ in }
    /// Reference time for future date detection in message text.
    var now: () -> Date = Date.init
    /// Local calendar bridge used when clicking a detected date in a message bubble.
    var calendarBridge: CalendarBridge? = nil
    /// Opens an image or gallery tile in the in-app lightbox instead of an external app.
    var openLightbox: (String) -> Void = { _ in }
    /// Opens an unopened view-once message in `ViewOnceSheet`.
    var openViewOnce: (TimelineMessage) -> Void = { _ in }
    /// Shared voice-note & audio player model.
    var audioPlayer: AudioPlayerModel? = nil
    /// Title of the chat a message belongs to, for `VoiceNoteView` and `GlobalAudioPlayerBar`.
    var chatTitle: (TimelineMessage) -> String = { _ in "" }
    /// Consecutive voice-note queue starting at the given message ID in the same chat.
    var voiceNoteQueue: (String) -> [AudioPlayerModel.Track] = { _ in [] }
    /// Whether external media embeds load automatically without click-to-load consent.
    var loadExternalEmbedsAutomatically = false
    /// Pops a video message out into the floating Picture-in-Picture window.
    var popOutPiP: @MainActor (TimelineMessage) -> Void = { message in
        PictureInPictureController.shared.show(
            PiPVideoItem(
                messageID: message.id,
                roomID: message.roomID,
                mediaPath: message.mediaPath,
                thumbnailPath: message.thumbnailPath,
                blurhash: message.blurhash,
                title: message.fileName.isEmpty ? message.senderName : message.fileName,
                width: message.width,
                height: message.height,
                durationMS: message.durationMS
            )
        )
    }
}

/// What the message rows show that is no model's: which messages have their edits open below them, the versions
/// read for them, and whose spoilers were clicked. One per timeline (the chat's, the thread pane's).
@MainActor
final class MessageUI: ObservableObject {
    @Published var historyOpen: Set<String> = []
    @Published var versions: [String: [Version]] = [:]
    @Published var revealed: Set<String> = []
    @Published var loadedEmbeds: Set<String> = []
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
        case let .membershipRun(_, _, summary):
            MembershipRunRow(summary: summary, isSelected: isSelected)
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

/// A collapsed run of membership changes (joins/leaves/renames/avatars) in the timeline, styled like the existing
/// timer and call notes: a centred, muted line across the timeline with no bubble and no Sent mark.
struct MembershipRunRow: View {
    let summary: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2")
                .accessibilityHidden(true)
            Text(verbatim: summary)
                .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityElement(children: .combine)
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
    /// Detected date clicked inside the message bubble, presenting `AddCalendarEventPopover`.
    @State private var activeDetectedDate: DetectedMessageDate?

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
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "courier-calendar" {
                if let detected = CalendarBridge.detectedDate(from: url) {
                    activeDetectedDate = detected
                    if let bridge = actions.calendarBridge {
                        Task { await bridge.loadSelectedDay() }
                    }
                }
                return .handled
            }
            return .systemAction
        })
        .popover(
            isPresented: Binding(
                get: { activeDetectedDate != nil },
                set: { if !$0 { activeDetectedDate = nil } }
            ),
            arrowEdge: .bottom
        ) {
            if let detected = activeDetectedDate {
                AddCalendarEventPopover(
                    bridge: actions.calendarBridge ?? CalendarBridge(now: actions.now),
                    defaultTitle: message.rich.text.isEmpty ? message.body : message.rich.text,
                    detectedDate: detected,
                    onCancel: { activeDetectedDate = nil }
                )
            }
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
        return message.statusLine != .sending && message.statusLine != .queued
            && !(message.statusLine?.isWaiting ?? false) && !isFailed
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
                .onHover { hovering in
                    if !message.mine {
                        actions.hoverSender(hovering, message)
                    }
                }
        } else {
            Color.clear.frame(width: Self.avatarSize, height: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let net = actions.messageNetwork(message), !net.isEmpty {
                NetworkBadge(
                    network: net,
                    name: NetworkNames.displayName(of: net) ?? net,
                    size: 12
                )
            }
            if !message.mine {
                Text(message.senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AvatarView.color(for: message.senderName))
                    .onHover { hovering in
                        actions.hoverSender(hovering, message)
                    }
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
                if let reply = message.reply {
                    QuoteView(reply: reply, onBubble: message.mine && !message.suppressesBubbleBackground)
                        .padding(.horizontal, message.suppressesBubbleBackground ? 8 : 0)
                        .padding(.vertical, message.suppressesBubbleBackground ? 4 : 0)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(message.suppressesBubbleBackground ? Color.primary.opacity(0.08) : .clear)
                        )
                }
                content
                if message.kind != .deleted && message.kind != .undecryptable {
                    ForEach(Array(message.linkPreviews.enumerated()), id: \.offset) { _, preview in
                        LinkPreviewCardView(preview: preview, onBubble: message.mine && !message.suppressesBubbleBackground)
                    }
                    if let embed = ExternalEmbedDescriptor.first(in: message) {
                        EmbedConsentCard(
                            messageID: message.id,
                            descriptor: embed,
                            isLoaded: actions.loadExternalEmbedsAutomatically || ui.loadedEmbeds.contains(message.id),
                            onBubble: message.mine && !message.suppressesBubbleBackground,
                            onLoadEmbed: { ui.loadedEmbeds.insert(message.id) }
                        )
                    }
                }
            }
            .accessibilityElement(children: message.kind == .poll ? .contain : .combine)
            // A poll is a group of its option buttons, summed up as "who: question".
            .accessibilityLabel(accessibilityText)
            if message.isEdited { editedButton }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, message.suppressesBubbleBackground ? 2 : (message.kind == .image || message.kind == .sticker || message.kind == .video ? 4 : 11))
        .padding(.vertical, message.suppressesBubbleBackground ? 2 : (message.kind == .image || message.kind == .sticker || message.kind == .video ? 4 : 7))
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
        if message.viewOnce {
            ViewOnceChip(message: message) {
                actions.openViewOnce(message)
            }
            caption
        } else if !message.galleryItems.isEmpty {
            GalleryGridView(message: message, onOpenLightbox: actions.openLightbox)
            caption
        } else {
            switch message.kind {
            case .deleted:
                Label(String(localized: "This message was deleted"), systemImage: "trash")
                    .font(.callout.italic())
                    .foregroundStyle(foreground.opacity(0.75))
            case .undecryptable:
                Label(String(localized: "Waiting for this message to be decrypted"), systemImage: "lock")
                    .font(.callout.italic())
                    .foregroundStyle(foreground.opacity(0.75))
            case .sticker:
                if let sticker = message.sticker {
                    StickerAttachmentView(message: message, sticker: sticker, onOpenLightbox: actions.openLightbox)
                } else {
                    EnhancedImageView(message: message, onOpenLightbox: actions.openLightbox)
                    caption
                }
            case .image:
                if let gif = message.gif {
                    GIFAttachmentView(
                        message: message,
                        gif: gif,
                        onPopOutPiP: { actions.popOutPiP(message) },
                        onOpenLightbox: actions.openLightbox
                    )
                    caption
                } else {
                    EnhancedImageView(message: message, onOpenLightbox: actions.openLightbox)
                    caption
                }
            case .video:
                if let gif = message.gif {
                    GIFAttachmentView(
                        message: message,
                        gif: gif,
                        onPopOutPiP: { actions.popOutPiP(message) },
                        onOpenLightbox: actions.openLightbox
                    )
                    caption
                } else {
                    InlineVideoPlayer(
                        messageID: message.id,
                        roomID: message.roomID,
                        mediaPath: message.mediaPath,
                        thumbnailPath: message.thumbnailPath,
                        blurhash: message.blurhash,
                        width: message.width,
                        height: message.height,
                        durationMS: message.durationMS,
                        isGIF: message.isGIF,
                        onPopOutPiP: { actions.popOutPiP(message) },
                        onOpenLightbox: { actions.openLightbox(message.id) }
                    )
                    caption
                }
            case .voiceNote:
                VoiceNoteView(
                    message: message,
                    chatTitle: actions.chatTitle(message),
                    audioPlayer: actions.audioPlayer ?? AudioPlayerModel(),
                    queueInRoom: actions.voiceNoteQueue(message.id)
                )
                caption
            case .file:
                if InlinePDFView.canDisplay(message) {
                    InlinePDFView(message: message)
                } else {
                    FileAttachmentChip(message: message)
                }
                caption
            case .location:
                if let geoURI = message.geoURI,
                   let coordinate = GeoCoordinate.parse(geoURI, fallbackLabel: message.body) {
                    LocationCardView(coordinate: coordinate, onBubble: message.mine)
                } else {
                    Label(
                        message.body.isEmpty ? (message.geoURI ?? String(localized: "Location")) : message.body,
                        systemImage: "mappin.and.ellipse"
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
            case .emote:
                Text(LinkedText.attributed("* \(message.senderName) \(message.body)", now: actions.now()))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            case .text, .notice:
                RichTextView(rich: message.rich, onBubble: message.mine, revealed: ui.revealedBinding(message.id),
                             italic: message.kind == .notice, now: actions.now())
            case .poll:
                if let poll = message.poll {
                    PollView(poll: poll, onBubble: message.mine) { actions.vote(message.id, $0) }
                } else {
                    Label(message.body, systemImage: "chart.bar")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        if !message.rich.text.isEmpty {
            RichTextView(rich: message.rich, onBubble: message.mine && !message.suppressesBubbleBackground, revealed: ui.revealedBinding(message.id),
                         now: actions.now())
                .padding(.horizontal, message.kind == .image || message.kind == .sticker || message.kind == .video ? 7 : 0)
                .padding(.bottom, message.kind == .image || message.kind == .sticker || message.kind == .video ? 3 : 0)
        }
    }

    private var fill: Color {
        if message.suppressesBubbleBackground { return .clear }
        if message.kind == .deleted || message.kind == .undecryptable { return Color.primary.opacity(0.06) }
        return message.mine ? Color.accentColor : Color.primary.opacity(0.09)
    }

    private var foreground: Color {
        if message.suppressesBubbleBackground { return .primary }
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
        case .waiting:
            // Every waiting message has this line (Timeline.build): it goes when the chat's account is back.
            HStack(spacing: 8) {
                Label(StatusLine.waitingLabel, systemImage: "clock")
                    .foregroundStyle(.secondary)
                    .help(actions.waitingHelp())
                dontSendButton
            }
            .font(.caption)
            .buttonStyle(.link)
            .padding(.horizontal, 4)
        case .noAccount:
            HStack(spacing: 8) {
                Label(StatusLine.noAccountLabel, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                dontSendButton
            }
            .font(.caption)
            .buttonStyle(.link)
            .padding(.horizontal, 4)
        case .delivered, .seen:
            // Only under my newest message that went (Timeline.build, and lastOutgoingID for the chat; the thread
            // pane shows none, as it shows no Sent).
            if showsSent {
                Text(message.statusLine.flatMap { line in
                    StatusLine.seenText(line, time: { $0.formatted(date: .omitted, time: .shortened) })
                } ?? StatusLine.deliveredLabel)
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
    private var dontSendButton: some View {
        if let dontSend = actions.dontSend {
            Button(StatusLine.dontSendTitle) { dontSend(message.id) }
                .help(String(localized: "Takes the message back. It isn’t sent."))
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

/// Links and future detected dates in a message's text. Only web and mail links and future dates are marked.
enum LinkedText {
    private final class Box { let value: AttributedString; init(_ value: AttributedString) { self.value = value } }

    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 2000
        return cache
    }()
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func attributed(_ text: String, now: Date = Date(), detectDates: Bool = true) -> AttributedString {
        let cacheKey = "\(detectDates ? 1 : 0):\(Int(now.timeIntervalSince1970 / 60)):\(text)" as NSString
        if let known = cache.object(forKey: cacheKey) { return known.value }
        var result = AttributedString(text)
        let whole = NSRange(text.startIndex..., in: text)
        for match in detector?.matches(in: text, range: whole) ?? [] {
            guard let url = match.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? ""),
                  let range = Range(match.range, in: text), let target = Range(range, in: result) else { continue }
            result[target].link = url
        }
        if detectDates {
            for detected in CalendarBridge.detectDates(in: text, referenceDate: now) {
                guard let target = Range(detected.range, in: result),
                      result[target].link == nil else { continue }
                result[target].underlineStyle = Text.LineStyle(pattern: .dash)
                if let actionURL = CalendarBridge.dateActionURL(for: detected) {
                    result[target].link = actionURL
                }
            }
        }
        cache.setObject(Box(result), forKey: cacheKey)
        return result
    }
}

/// AppKit `NSImageView` wrapper with transparent background and Reduce Motion-aware animation control.
private struct BorderlessAnimatedNSImageView: NSViewRepresentable {
    let image: NSImage
    let animates: Bool
    let scaling: NSImageScaling

    func makeNSView(context _: Context) -> NSImageView {
        let view = NSImageView()
        view.imageFrameStyle = .none
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.imageScaling = scaling
        view.animates = animates
        view.canDrawSubviewsIntoLayer = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateNSView(_ nsView: NSImageView, context _: Context) {
        nsView.imageFrameStyle = .none
        nsView.layer?.backgroundColor = NSColor.clear.cgColor
        nsView.imageScaling = scaling
        nsView.image = image
        nsView.animates = animates
    }
}

/// Borderless sticker attachment view (`StickerAttachment.tsx`): renders up to `160×160 pt` preserving aspect ratio
/// on a transparent background with no message bubble, resolves local media via `ThumbnailLoader.resolveMediaPath`,
/// and pauses animated stickers when macOS Reduce Motion is enabled.
public struct StickerAttachmentView: View {
    public static let maxDimension: CGFloat = 160

    public let message: TimelineMessage
    public let sticker: StickerAttachment
    public var onOpenLightbox: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var asyncCGImage: CGImage?

    public init(
        message: TimelineMessage,
        sticker: StickerAttachment,
        onOpenLightbox: @escaping (String) -> Void = { _ in }
    ) {
        self.message = message
        self.sticker = sticker
        self.onOpenLightbox = onOpenLightbox
    }

    /// Computes a proportional sticker frame constrained to `160×160 pt`.
    public static func displaySize(width: Int?, height: Int?) -> CGSize {
        guard let width, let height, width > 0, height > 0 else {
            return CGSize(width: 128, height: 128)
        }
        let scale = min(1.0, maxDimension / CGFloat(max(width, height)))
        return CGSize(
            width: max(48, (CGFloat(width) * scale).rounded()),
            height: max(48, (CGFloat(height) * scale).rounded())
        )
    }

    /// Returns whether animated sticker frames should play given the macOS Reduce Motion setting.
    public static func shouldAnimate(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Resolves the local file path for a sticker attachment using `ThumbnailLoader.resolveMediaPath`.
    public static func resolveLocalPath(
        message: TimelineMessage,
        sticker: StickerAttachment,
        dataDirectory: URL = EngineLocation.dataDirectory()
    ) -> String? {
        for candidate in [message.mediaPath, sticker.mediaURL, message.thumbnailPath] {
            if let path = ThumbnailLoader.resolveMediaPath(candidate, dataDirectory: dataDirectory),
               !path.isEmpty {
                return path
            }
        }
        return nil
    }

    private var frameSize: CGSize {
        Self.displaySize(width: sticker.width ?? message.width, height: sticker.height ?? message.height)
    }

    private var resolvedPath: String? {
        Self.resolveLocalPath(message: message, sticker: sticker)
    }

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public var body: some View {
        let size = frameSize
        let animate = Self.shouldAnimate(reduceMotion: accessibilityReduceMotion || reduceMotionEnabled)
        ZStack {
            if let path = resolvedPath,
               FileManager.default.fileExists(atPath: path),
               let nsImage = NSImage(contentsOfFile: path) {
                BorderlessAnimatedNSImageView(
                    image: nsImage,
                    animates: animate,
                    scaling: .scaleProportionallyUpOrDown
                )
                .frame(width: size.width, height: size.height)
            } else if let cgImage = asyncCGImage ?? resolvedPath.flatMap({ ThumbnailLoader.thumbnail(atPath: $0, maxPixelSize: 320) }) {
                Image(decorative: cgImage, scale: 2.0, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
            } else {
                VStack(spacing: 4) {
                    if let emoji = sticker.emoji, !emoji.isEmpty {
                        Text(verbatim: emoji)
                            .font(.system(size: 52))
                    } else {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    if !sticker.name.isEmpty {
                        Text(sticker.name)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard resolvedPath != nil else { return }
            onOpenLightbox(message.id)
        }
        .task(id: resolvedPath) {
            guard asyncCGImage == nil, let path = resolvedPath else { return }
            asyncCGImage = await ThumbnailLoader.shared.thumbnail(atPath: path)?.image
        }
        .help(sticker.name.isEmpty ? String(localized: "Sticker") : sticker.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sticker.name.isEmpty ? String(localized: "Sticker") : sticker.name)
        .accessibilityAddTraits(.isImage)
    }
}

/// Looping GIF attachment view (`GIFAttachment.tsx` / `GifVideo.tsx`): renders inside a rounded `12 pt` media frame
/// with a top-leading `"GIF"` pill badge, loops silently, resolves local media via `ThumbnailLoader.resolveMediaPath`,
/// and pauses when macOS Reduce Motion is enabled.
public struct GIFAttachmentView: View {
    public static let cornerRadius: CGFloat = 12

    public let message: TimelineMessage
    public let gif: GIFAttachment
    public var onPopOutPiP: () -> Void
    public var onOpenLightbox: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var asyncCGImage: CGImage?

    public init(
        message: TimelineMessage,
        gif: GIFAttachment,
        onPopOutPiP: @escaping () -> Void = {},
        onOpenLightbox: @escaping (String) -> Void = { _ in }
    ) {
        self.message = message
        self.gif = gif
        self.onPopOutPiP = onPopOutPiP
        self.onOpenLightbox = onOpenLightbox
    }

    /// Returns whether GIF playback should loop automatically given the macOS Reduce Motion setting.
    public static func shouldAnimate(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Resolves the local file path for a GIF attachment using `ThumbnailLoader.resolveMediaPath`.
    public static func resolveLocalPath(
        message: TimelineMessage,
        gif: GIFAttachment,
        dataDirectory: URL = EngineLocation.dataDirectory()
    ) -> String? {
        for candidate in [message.mediaPath, gif.mediaURL, message.thumbnailPath] {
            if let path = ThumbnailLoader.resolveMediaPath(candidate, dataDirectory: dataDirectory),
               !path.isEmpty {
                return path
            }
        }
        return nil
    }

    private var isVideoGIF: Bool {
        message.kind == .video || (gif.mimeType?.lowercased().hasPrefix("video/") == true)
    }

    private var frameSize: CGSize {
        EnhancedImageView.proportionalSize(
            width: gif.width ?? message.width,
            height: gif.height ?? message.height,
            longestSide: EnhancedImageView.longestSide,
            fallback: CGSize(width: 260, height: 180)
        )
    }

    private var resolvedPath: String? {
        Self.resolveLocalPath(message: message, gif: gif)
    }

    public var body: some View {
        let size = frameSize
        let animate = Self.shouldAnimate(
            reduceMotion: accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        ZStack(alignment: .topLeading) {
            if isVideoGIF {
                InlineVideoPlayer(
                    messageID: message.id,
                    roomID: message.roomID,
                    mediaPath: resolvedPath ?? message.mediaPath,
                    thumbnailPath: message.thumbnailPath,
                    blurhash: message.blurhash,
                    width: gif.width ?? message.width,
                    height: gif.height ?? message.height,
                    durationMS: message.durationMS,
                    isGIF: true,
                    onPopOutPiP: onPopOutPiP,
                    onOpenLightbox: { onOpenLightbox(message.id) },
                    initialIsPlaying: animate,
                    initialIsMuted: true
                )
            } else if let path = resolvedPath,
                      FileManager.default.fileExists(atPath: path),
                      let nsImage = NSImage(contentsOfFile: path) {
                BorderlessAnimatedNSImageView(
                    image: nsImage,
                    animates: animate,
                    scaling: .scaleAxesIndependently
                )
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenLightbox(message.id)
                }
            } else if let cgImage = asyncCGImage ?? resolvedPath.flatMap({ ThumbnailLoader.thumbnail(atPath: $0, maxPixelSize: 640) }) {
                Image(decorative: cgImage, scale: 2.0, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onOpenLightbox(message.id)
                    }
            } else {
                EnhancedImageView(message: message, onOpenLightbox: onOpenLightbox)
            }

            Text(verbatim: "GIF")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.68)))
                .padding(8)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .task(id: resolvedPath) {
            guard !isVideoGIF, asyncCGImage == nil, let path = resolvedPath else { return }
            asyncCGImage = await ThumbnailLoader.shared.thumbnail(atPath: path)?.image
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(gif.caption ?? (message.fileName.isEmpty ? String(localized: "GIF") : message.fileName))
    }
}
