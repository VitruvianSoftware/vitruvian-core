// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UniformTypeIdentifiers

/// The right-hand pane for an open chat: its header, the timeline, a bar for problems, and the composer.
struct ConversationView: View {
    @ObservedObject var conversation: ConversationModel
    @ObservedObject var composer: ComposerModel
    @ObservedObject var inbox: InboxModel
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isDropTargeted = false
    /// The message that was first when older ones were asked for: the view returns to it once they are in.
    @State private var restoreAnchor: String?
    @State private var topInView = false
    @State private var composerTextHeight: CGFloat = ComposerTextView.minimumHeight
    /// Leaving the bottom is told a moment late: new content below pushes the end out of sight for an instant
    /// before the view scrolls to it, and that is not the person scrolling up.
    @State private var leavingBottom: Task<Void, Never>?
    @State private var bottomInView = false
    /// The scroll to a message (a search result) that has been made. Until it is, the bottom being in view is the
    /// timeline starting there, not the person reaching it, and reads nothing newer.
    @State private var scrolledToMessage: Int?

    var body: some View {
        VStack(spacing: 0) {
            ConversationHeader(row: inbox.selectedRow, networkName: inbox.selectedRow.map { inbox.networkName($0.network) })
            Divider()
            timeline
            if let problem = conversation.problem {
                ProblemBar(problem: problem, retry: conversation.reload)
            }
            ComposerView(composer: composer, textHeight: $composerTextHeight, escapeFirst: { inbox.escape() })
        }
        .overlay { if isDropTargeted { DropOverlay() } }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: drop)
        .onChange(of: controlActiveState, initial: true) { _, state in
            conversation.setWindowKey(state == .key)
        }
        // A window that closes (⌘W) is never told it stopped being key: going away says it.
        .onDisappear { conversation.setWindowKey(false) }
        // Esc leaves selection mode first, then clears a reply.
        .onExitCommand { if !inbox.escape() { _ = composer.escape() } }
    }

    // MARK: Timeline

    @ViewBuilder
    private var timeline: some View {
        if conversation.isLoaded {
            // Made only once there is something in it, so that it starts at the newest message.
            messages
                .id(conversation.roomID)
                .overlay { placeholder }
        } else {
            Color.clear
                .overlay { placeholder }
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if conversation.hasOlder {
                        if conversation.olderFailed {
                            Button(String(localized: "Load older messages"), action: requestOlder)
                                .padding(10)
                        } else {
                            // Reaching the top asks for the next page; and when a page is in and this is still
                            // in view (it was a short one), the next.
                            ProgressView()
                                .controlSize(.small)
                                .padding(10)
                                .onAppear {
                                    topInView = true
                                    requestOlder()
                                }
                                .onDisappear { topInView = false }
                        }
                    }
                    ForEach(conversation.items) { item in
                        TimelineItemView(item: item, isSelected: conversation.selectedMessageID == item.id,
                                         isHighlighted: conversation.highlightedMessageID == item.id,
                                         showsSent: conversation.lastOutgoingID == item.id, actions: actions)
                            .id(item.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                        .onAppear {
                            leavingBottom?.cancel()
                            bottomInView = true
                            conversation.scrolled(toBottom: true)
                            readNewerIfAtBottom()
                        }
                        .onDisappear {
                            bottomInView = false
                            leavingBottom?.cancel()
                            leavingBottom = Task {
                                try? await Task.sleep(nanoseconds: 150_000_000)
                                if !Task.isCancelled { conversation.scrolled(toBottom: false) }
                            }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom)
            .overlay(alignment: .bottomTrailing) { jumpButton }
            .onChange(of: conversation.isLoadingOlder) { _, loading in
                if !loading, topInView, !conversation.olderFailed { requestOlder() }
            }
            .onChange(of: conversation.isLoadingNewer) { _, loading in
                // A newer page is in and the bottom is still in view (it was a short one): the next.
                if !loading { readNewerIfAtBottom() }
            }
            .onChange(of: conversation.scrollToMessageRequest, initial: true) { _, request in
                if let request { scrollToMessage(proxy, request) }
            }
            .onChange(of: conversation.jumpToBottomRequest) { _, _ in
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: conversation.items) { _, _ in
                // New messages, a reaction or a status line are followed only by someone already at the newest
                // message. Away from it (opened at a search result), new messages never move the view.
                if conversation.isAtBottom, !conversation.isAwayFromLatest { scrollToBottom(proxy) }
            }
            .onChange(of: bottomBarSignature) { _, _ in
                // The bottom bar grew (a reply, files, more lines): keep the newest message in view.
                if conversation.isAtBottom, !conversation.isAwayFromLatest { scrollToBottom(proxy) }
            }
            .onChange(of: firstMessageID) { _, _ in
                // Older messages came in above: stay where the person was.
                guard let anchor = restoreAnchor else { return }
                restoreAnchor = nil
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }

    /// Changes when anything under the timeline changes size.
    private var bottomBarSignature: [String] {
        [composer.replyTarget?.eventID ?? "", String(composer.attachments.count), composer.notice == nil ? "" : "notice",
         conversation.problem == nil ? "" : "problem", String(describing: composerTextHeight)]
    }

    private func requestOlder() {
        guard conversation.hasOlder, !conversation.isLoadingOlder else { return }
        restoreAnchor = firstMessageID
        conversation.loadOlder()
    }

    private static let bottomID = "conversation-bottom"

    private var firstMessageID: String? {
        for item in conversation.items.prefix(3) {
            if case let .message(message) = item { return message.id }
        }
        return nil
    }

    /// Opened at a message: scroll to it, in the middle. Once there, reaching the bottom reads newer messages.
    private func scrollToMessage(_ proxy: ScrollViewProxy, _ request: ConversationModel.MessageScrollRequest) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo(request.messageID, anchor: .center)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                scrolledToMessage = request.serial
                readNewerIfAtBottom()
            }
        }
    }

    /// Away from the newest message, reaching the bottom reads the next newer page.
    private func readNewerIfAtBottom() {
        guard bottomInView, conversation.isAwayFromLatest, !conversation.isLoadingNewer,
              let request = conversation.scrollToMessageRequest, scrolledToMessage == request.serial else { return }
        conversation.loadNewer()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = false) {
        // A moment later, so the layout that asked for it has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            } else {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if !conversation.isLoaded {
            if conversation.problem == nil { ProgressView() }
        } else if conversation.items.isEmpty {
            Text(String(localized: "No messages yet"))
                .foregroundStyle(.secondary)
        }
    }

    /// The way back to the newest message. Away from it (opened at a search result) it says "Jump to latest", with
    /// a dot once something new has come in.
    @ViewBuilder
    private var jumpButton: some View {
        if !conversation.isAtBottom || conversation.isAwayFromLatest {
            Button {
                conversation.jumpToBottom()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                    if conversation.isAwayFromLatest {
                        Text(String(localized: "Jump to latest"))
                            .font(.callout.weight(.medium))
                        if conversation.hasNewerWhileAway {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 7, height: 7)
                                .accessibilityLabel(String(localized: "New messages"))
                        }
                    } else if conversation.newMessageCount > 0 {
                        Text(conversation.newMessageCount == 1 ? String(localized: "1 new message")
                            : String(localized: "\(conversation.newMessageCount) new messages"))
                            .font(.callout.weight(.medium))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
            .padding(14)
            .help(String(localized: "Jump to the newest message (⌘↓)"))
            .accessibilityLabel(String(localized: "Jump to the newest message"))
        }
    }

    private var actions: MessageActions {
        MessageActions(
            select: { conversation.selectedMessageID = $0 },
            reply: { conversation.reply(to: $0) },
            react: { id, key in Task { await conversation.react(to: id, key: key) } },
            retry: { id in Task { await conversation.retry(id) } },
            discard: { id in Task { await conversation.discard(id) } })
    }

    // MARK: Dropping files

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in composer.attach([url]) }
            }
        }
        return handled
    }
}

private struct ConversationHeader: View {
    let row: InboxRow?
    let networkName: String?

    var body: some View {
        HStack(spacing: 10) {
            if let row {
                AvatarView(path: row.avatarPath, initials: row.initials, seed: row.name)
                    .frame(width: 32, height: 32)
                Text(row.name)
                    .font(.headline)
                    .lineLimit(1)
                NetworkBadge(network: row.network, name: networkName ?? row.network, size: 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ProblemBar: View {
    let problem: ConversationProblem
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
            Spacer(minLength: 0)
            Button(String(localized: "Try again"), action: retry)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        switch problem {
        case .loadFailed: String(localized: "Courier could not read the latest messages.")
        case let .actionFailed(reason): reason
        case .messageGone: String(localized: "That message isn’t in this chat any more.")
        }
    }
}

/// What a drag of files over the chat says.
private struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.10)
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(8)
            Label(String(localized: "Drop files here to attach"), systemImage: "paperclip")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.accentColor)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
