// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Which messages the keys act on: the chat's selected message, or, after a click in the thread pane, the pane's
/// (its menus and keys act `from: .thread`, so what goes into a composer goes into the pane's).
@MainActor
final class MessageFocus: ObservableObject {
    /// The message selected in the thread pane.
    @Published var paneSelection: String?
    /// The pane was clicked last (its messages or its composer), not the chat.
    @Published var inPane = false
}

/// The thread pane (01 §10's ThreadedRepliesPane): the root and its replies, a composer that writes in the thread
/// ("Reply in thread…"), and a close button. Esc closes it once the composer has nothing else to close.
struct ThreadPane: View {
    @ObservedObject var thread: ThreadModel
    @ObservedObject var conversation: ConversationModel
    @ObservedObject var composer: ComposerModel
    let messageActions: MessageActionsModel
    @ObservedObject var preferences: ComposerPreferences
    @ObservedObject var focus: MessageFocus
    @StateObject private var ui = MessageUI()
    @State private var composerTextHeight: CGFloat = ComposerTextView.minimumHeight

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            replies
            ComposerView(composer: composer, preferences: preferences, textHeight: $composerTextHeight,
                         placeholder: String(localized: "Reply in thread…"),
                         escapeLast: {
                             close()
                             return true
                         })
                .simultaneousGesture(TapGesture().onEnded { focus.inPane = true })
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
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
        .onExitCommand { if !composer.escape() { close() } }
    }

    private func close() {
        focus.paneSelection = nil
        focus.inPane = false
        thread.close()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Thread"))
                .font(.headline)
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Close (Esc)"))
            .accessibilityLabel(String(localized: "Close thread"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .accessibilityAddTraits(.isHeader)
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
                                             showsSent: false, actions: actions, ui: ui)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.bottom)
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
                               composer: composer, ui: ui, source: .thread) { id in
            focus.paneSelection = id
            focus.inPane = true
        }
    }
}

/// Under a thread's root: how many replies and who wrote the newest. A click opens the thread pane.
struct ThreadSummaryLine: View {
    let summary: ThreadSummary
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                Text(MessageLines.replies(summary))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
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
        .accessibilityLabel(String(localized: "\(MessageLines.replies(summary)), show replies"))
    }
}
