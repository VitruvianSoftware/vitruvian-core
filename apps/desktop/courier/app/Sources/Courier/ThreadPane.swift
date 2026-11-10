// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// The thread pane (01 §10's ThreadedRepliesPane): the root and its replies, a composer that writes in the thread
/// ("Reply in thread…"), and a close button. Esc closes it once the composer has nothing else to close.
struct ThreadPane: View {
    @ObservedObject var thread: ThreadModel
    @ObservedObject var conversation: ConversationModel
    @ObservedObject var composer: ComposerModel
    @ObservedObject var messageActions: MessageActionsModel
    @ObservedObject var preferences: ComposerPreferences
    @ObservedObject var focus: MessageFocus
    var showsOpenInNewWindowButton = true
    var onOpenInNewWindow: ((String, String) -> Void)?
    /// With glass in the main window the header is a toolbar item (`ThreadPaneHeader`, placed by ConversationView), so
    /// the pane draws none of its own.
    var headerInToolbar = false
    /// The chat the thread is in, under the pane's title.
    var chatName: String?
    @StateObject private var ui = MessageUI()
    @State private var composerTextHeight: CGFloat = ComposerTextView.minimumHeight

    var body: some View {
        VStack(spacing: 0) {
            if !headerInToolbar {
                ThreadPaneHeader(thread: thread, focus: focus, chatName: chatName,
                                 showsOpenInNewWindowButton: showsOpenInNewWindowButton,
                                 onOpenInNewWindow: onOpenInNewWindow, inToolbar: false)
                Divider()
            }
            replies
                // With glass the replies run under the pane's composer, as the chat's messages do under its own.
                .courierEdgeBar(.bottom) {
                    ComposerView(composer: composer, preferences: preferences, textHeight: $composerTextHeight,
                                 showsIncognitoMark: conversation.incognitoIsOn && preferences.showIncognitoMark,
                                 placeholder: String(localized: "Reply in thread…"),
                                 escapeLast: {
                                     if Self.deselect(focus) { return true }
                                     close()
                                     return true
                                 })
                        .simultaneousGesture(TapGesture().onEnded { focus.inPane = true })
                }
        }
        .courierSurface(.sidePane)
        .environment(\.themeRoomID, thread.roomID ?? conversation.roomID)
        .onAppear {
            ui.history = { await messageActions.history(of: $0) }
            // Return in the pane's empty composer edits or replies to the message selected in the pane.
            let thread = self.thread
            let focus = self.focus
            composer.selectedMessage = { [weak thread, weak focus] in
                guard let id = focus?.paneSelection else { return nil }
                for case let .message(message) in thread?.items ?? [] where message.id == id { return message }
                return nil
            }
        }
        // Esc ends an edit or clears a reply first, then deselects the pane's message, then closes the pane.
        .onExitCommand { if !composer.escape(), !Self.deselect(focus) { close() } }
        // Edit History asked from the pane opens below the pane's bubble.
        .onChange(of: messageActions.request) { _, request in
            if case let .history(id, .thread)? = request {
                ui.showHistory(id)
                messageActions.dismissRequest()
            }
        }
    }

    /// Nothing selected in the pane (a click on its selected message, Esc, a click on the pane's empty space); false
    /// when nothing was.
    private static func deselect(_ focus: MessageFocus) -> Bool {
        guard focus.paneSelection != nil else { return false }
        focus.paneSelection = nil
        return true
    }

    private func close() {
        Self.close(thread, focus: focus)
    }

    /// Closes the pane: nothing selected or focused in it any more, and the thread closed.
    static func close(_ thread: ThreadModel, focus: MessageFocus) {
        focus.paneSelection = nil
        focus.inPane = false
        thread.close()
    }

    @ViewBuilder
    private var replies: some View {
        if thread.loadFailed, thread.items.isEmpty {
            VStack(spacing: 8) {
                Text(String(localized: "Courier could not read this thread."))
                    .foregroundStyle(.secondary)
                Button(String(localized: "Try again"), action: thread.refresh)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !thread.isLoaded, thread.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let rowActions = actions
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if thread.hasOlder {
                            Button(String(localized: "Load older replies"), action: thread.loadOlder)
                                .disabled(thread.isLoadingOlder)
                                .padding(10)
                        }
                        ForEach(thread.items) { item in
                            TimelineItemView(item: item, isSelected: focus.paneSelection == item.id,
                                             isHighlighted: thread.highlightedMessageID == item.id,
                                             showsSent: false, actions: rowActions, ui: ui)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.bottom)
                .courierScrollEdges()
                .deselectsOnEmptyClick { [focus] in _ = Self.deselect(focus) }
                .onChange(of: thread.scrollToMessageRequest, initial: true) { _, request in
                    guard let request else { return }
                    DispatchQueue.main.async { proxy.scrollTo(request.messageID, anchor: .center) }
                }
            }
        }
    }

    /// The pane's rows act `from: .thread`.
    private var actions: MessageActions {
        MessageRowActions.make(conversation: conversation, messageActions: messageActions, preferences: preferences,
                               composer: composer, ui: ui, source: .thread,
                               deselect: { [focus] in _ = Self.deselect(focus) }) { id in
            focus.paneSelection = id
            focus.inPane = true
        }
    }
}

/// Under a thread's root: how many replies and who wrote the newest, and, while some aren't read in the thread, an
/// accent dot and "2 new" (an at sign in place of the dot when one of them mentions me). A click opens the thread
/// pane, which reads them.
struct ThreadSummaryLine: View {
    let summary: ThreadSummary
    let open: () -> Void
    @Environment(\.themeAccentColor) private var themeAccent

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                Text(MessageLines.replies(summary))
                    .fontWeight(.semibold)
                    .foregroundStyle(themeAccent)
                if let new = MessageLines.newReplies(summary) {
                    NewRepliesMark(text: new, mentionsMe: summary.unreadMentionsMe)
                }
                if let names = MessageLines.repliers(summary) {
                    Text(names)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Show Replies (⌘↓)"))
        .accessibilityLabel(MessageLines.summaryAccessibilityLabel(summary))
    }
}

/// The unread mark of a thread, in the accent colour: a dot and "2 new", or, when one of the replies mentions me, an
/// at sign in place of the dot, as the inbox row marks a mention.
private struct NewRepliesMark: View {
    let text: String
    let mentionsMe: Bool

    var body: some View {
        HStack(spacing: 3) {
            if mentionsMe {
                Image(systemName: "at")
                    .font(.caption2.weight(.bold))
            } else {
                Circle().frame(width: 6, height: 6)
            }
            Text(text).fontWeight(.semibold)
        }
        .foregroundStyle(themeAccent)
    }

    @Environment(\.themeAccentColor) private var themeAccent
}

/// Above the open chat's timeline while it has threads with unread replies: "New replies in 2 threads". A click
/// opens the thread pane at the oldest unread reply, then, click by click, the next thread's
/// (`ConversationModel.showNextUnreadThread`).
struct ThreadRepliesBanner: View {
    let text: String
    let mentionsMe: Bool
    let show: () -> Void
    @Environment(\.themeAccentColor) private var themeAccent

    var body: some View {
        Button(action: show) {
            HStack(spacing: 6) {
                Image(systemName: mentionsMe ? "at" : "bubble.left.and.bubble.right.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeAccent)
                Text(text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(.quaternary))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .help(String(localized: "Show the thread with new replies"))
        .accessibilityLabel(text)
        .accessibilityHint(String(localized: "Opens the thread at its first new reply"))
    }
}

/// The thread pane's header: "Thread" over the chat's name, with Open in New Window and Close. A strip at the pane's
/// top, or with glass, the pane's item in the window's toolbar (`inToolbar`).
struct ThreadPaneHeader: View {
    @ObservedObject var thread: ThreadModel
    @ObservedObject var focus: MessageFocus
    var chatName: String?
    var showsOpenInNewWindowButton = true
    var onOpenInNewWindow: ((String, String) -> Void)?
    var inToolbar: Bool
    @Environment(\.openDetachedWindow) private var openDetachedWindow

    var body: some View {
        PaneHeader(title: String(localized: "Thread"), subtitle: chatName, inToolbar: inToolbar) {
            if showsOpenInNewWindowButton, let roomID = thread.roomID, let rootID = thread.rootID {
                Button {
                    if let onOpenInNewWindow {
                        onOpenInNewWindow(roomID, rootID)
                    } else {
                        openDetachedWindow?(.thread(roomID: roomID, rootEventID: rootID))
                    }
                } label: {
                    Image(systemName: "macwindow.badge.plus")
                }
                .help(String(localized: "Open in New Window"))
                .accessibilityLabel(String(localized: "Open in New Window"))
            }
            if showsOpenInNewWindowButton {
                Button { ThreadPane.close(thread, focus: focus) } label: {
                    Image(systemName: "xmark")
                }
                .help(String(localized: "Close (Esc)"))
                .accessibilityLabel(String(localized: "Close thread"))
            }
        }
    }
}
