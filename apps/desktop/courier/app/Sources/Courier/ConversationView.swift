// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UniformTypeIdentifiers

/// The right-hand pane for an open chat: its header (with its disappearing timer), the timeline, a bar for problems,
/// the messages scheduled to send later, and the composer; and the thread pane beside it when a thread is open. The
/// message actions' questions and pickers (Unsend's and Delete's questions, Forward, React, Send Later, a quick
/// reply's title, a new poll) are shown from here.
struct ConversationView: View {
    @ObservedObject var conversation: ConversationModel
    @ObservedObject var composer: ComposerModel
    @ObservedObject var inbox: InboxModel
    @ObservedObject var messageActions: MessageActionsModel
    let scheduled: ScheduledModel
    @ObservedObject var preferences: ComposerPreferences
    @ObservedObject var thread: ThreadModel
    @ObservedObject var focus: MessageFocus
    let appModel: AppModel
    @Environment(\.controlActiveState) private var controlActiveState
    @StateObject private var ui = MessageUI()
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
    @State private var creatingPoll = false

    var body: some View {
        HSplitView {
            chat
                .frame(minWidth: 340, maxWidth: .infinity)
            if thread.rootID != nil, thread.roomID == conversation.roomID {
                ThreadPane(thread: thread, conversation: conversation, composer: thread.composer,
                           messageActions: messageActions, preferences: preferences, focus: focus)
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 560)
            }
            if conversation.isShowingChatInfo, let info = conversation.chatInfo {
                ChatInfoPane(
                    info: info,
                    bookmarks: conversation.chatInfoBookmarks,
                    isRefreshing: conversation.isRefreshingChatInfo,
                    showsCloseButton: true,
                    focusSearchTrigger: conversation.focusChatInfoSearchRequest,
                    timerChoices: conversation.timerChoices,
                    onSelectTimer: { choice in Task { await conversation.setTimer(choice) } },
                    onSelectEvent: { eventID in
                        conversation.openEvent(eventID)
                    },
                    onRefresh: { Task { await conversation.refreshChatInfo(force: true) } },
                    onExport: { url in
                        guard let roomID = conversation.roomID else { return }
                        Task {
                            do {
                                let count = try await conversation.exportChat(roomID: roomID, to: url)
                                conversation.onToast(String(localized: "Exported \(count) messages"))
                            } catch {
                                conversation.onToast(
                                    EngineErrorText.text(
                                        for: error,
                                        fallback: String(localized: "Couldn’t export the chat.")
                                    )
                                )
                            }
                        }
                    },
                    onClose: conversation.toggleChatInfo
                )
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
            }
        }
        .onAppear { ui.history = { [messageActions] in await messageActions.history(of: $0) } }
        .onChange(of: messageActions.request) { _, request in
            // Edit History opens below the bubble; the other requests are sheets and questions (below).
            if case let .history(id, .chat)? = request {
                ui.showHistory(id)
                messageActions.dismissRequest()
            }
        }
        .sheet(item: sheetRequest) { sheet in requestSheet(sheet) }
        .sheet(isPresented: $creatingPoll) {
            if let polls = conversation.features.poll {
                PollCreatorWindow(features: polls, create: { await messageActions.createPoll($0) },
                                  close: { creatingPoll = false })
            }
        }
        .alert(confirmPrompt, isPresented: confirming) {
            Button(confirmTitle, role: .destructive) { Task { await messageActions.confirm() } }
            Button(String(localized: "Cancel"), role: .cancel) { messageActions.dismissRequest() }
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ConversationHeader(row: inbox.selectedRow, networkName: inbox.selectedRow.map { inbox.networkName($0.network) },
                               conversation: conversation)
            Divider()
            timeline
            if let problem = conversation.problem {
                ProblemBar(problem: problem, retry: conversation.reload)
            }
            ScheduledStrip(scheduled: scheduled)
            TypingLine(text: conversation.typingLine)
            ComposerView(composer: composer, preferences: preferences, textHeight: $composerTextHeight,
                         showsIncognitoMark: conversation.incognitoIsOn && preferences.showIncognitoMark,
                         menus: ComposerMenus(sendLater: messageActions.requestSendLater,
                                              createPoll: { creatingPoll = true },
                                              pollsUnavailable: conversation.features.pollsUnavailableReason(
                                                  network: conversation.network)),
                         escapeFirst: { inbox.escape() }, escapeLast: closeThread, upArrow: upArrow)
                .simultaneousGesture(TapGesture().onEnded { focus.inPane = false })
        }
        .overlay { if isDropTargeted { DropOverlay() } }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: drop)
        .onChange(of: controlActiveState, initial: true) { _, state in
            conversation.setWindowKey(state == .key)
        }
        // A window that closes (⌘W) is never told it stopped being key: going away says it.
        .onDisappear { conversation.setWindowKey(false) }
        // Esc leaves selection mode first, then ends an edit or clears a reply, then closes the thread pane.
        .onExitCommand { if !inbox.escape(), !composer.escape() { _ = closeThread() } }
    }

    /// Esc's last use: the thread pane closes.
    private func closeThread() -> Bool {
        guard thread.rootID != nil else { return false }
        focus.paneSelection = nil
        focus.inPane = false
        thread.close()
        return true
    }

    /// ↑ in an empty composer: my last message to edit, or (Settings ▸ Messages) the message above the selected one,
    /// the newest first, so ↑↑↑ walks up the chat.
    private func upArrow() -> Bool {
        if composer.editLast(in: conversation.items) { return true }
        guard preferences.upArrow == .focusMessages else { return false }
        focus.inPane = false
        return conversation.selectOlderMessage()
    }

    // MARK: Requests

    /// The requests shown as sheets.
    private enum Sheet: Identifiable {
        case forward(String), react(String), sendLater, quickReplyTitle

        var id: String {
            switch self {
            case let .forward(id): "forward:\(id)"
            case let .react(id): "react:\(id)"
            case .sendLater: "sendLater"
            case .quickReplyTitle: "quickReplyTitle"
            }
        }
    }

    private var sheetRequest: Binding<Sheet?> {
        Binding(get: {
            switch messageActions.request {
            case let .forward(id)?: .forward(id)
            case let .reactionPicker(id)?: .react(id)
            case .sendLater?: .sendLater
            case .quickReplyTitle?: .quickReplyTitle
            default: nil
            }
        }, set: { value in
            if value == nil, sheetRequestIsShown { messageActions.dismissRequest() }
        })
    }

    private var sheetRequestIsShown: Bool {
        switch messageActions.request {
        case .forward?, .reactionPicker?, .sendLater?, .quickReplyTitle?: true
        default: false
        }
    }

    @ViewBuilder
    private func requestSheet(_ sheet: Sheet) -> some View {
        switch sheet {
        case let .forward(id):
            ForwardPicker(model: ForwardPickerModel(appModel: appModel), networkName: inbox.networkName,
                          forward: { rooms in Task { await messageActions.forward(id, to: rooms) } },
                          cancel: messageActions.dismissRequest)
        case let .react(id):
            ReactionPicker(react: { key in
                messageActions.dismissRequest()
                Task { await conversation.react(to: id, key: key) }
            }, cancel: messageActions.dismissRequest)
        case .sendLater:
            SendLaterPicker(composer: composer, preferences: preferences, done: messageActions.dismissRequest)
        case .quickReplyTitle:
            QuickReplyTitleSheet(actions: messageActions)
        }
    }

    private var confirming: Binding<Bool> {
        Binding(get: {
            if case .confirm? = messageActions.request { return true }
            return false
        }, set: { shown in
            if !shown, case .confirm? = messageActions.request { messageActions.dismissRequest() }
        })
    }

    private var confirmPrompt: String {
        if case let .confirm(_, _, prompt)? = messageActions.request { return prompt }
        return ""
    }

    private var confirmTitle: String {
        if case let .confirm(action, _, _)? = messageActions.request, action == .unsend {
            return String(localized: "Unsend")
        }
        return String(localized: "Delete")
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
                                         showsSent: conversation.lastOutgoingID == item.id, actions: actions, ui: ui)
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
         conversation.problem == nil ? "" : "problem", String(describing: composerTextHeight),
         conversation.typingLine == nil ? "" : "typing"]
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
        MessageRowActions.make(conversation: conversation, messageActions: messageActions, preferences: preferences,
                               composer: composer, ui: ui, source: .chat) { id in
            conversation.selectedMessageID = id
            focus.inPane = false
        }
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

/// The chat's picture, name and network, and with a disappearing timer running, "Messages disappear after 7 days",
/// with the timer's menu.
private struct ConversationHeader: View {
    let row: InboxRow?
    let networkName: String?
    @ObservedObject var conversation: ConversationModel

    var body: some View {
        HStack(spacing: 10) {
            if let row {
                AvatarView(path: row.avatarPath, initials: row.initials, seed: row.name)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.headline)
                            .lineLimit(1)
                        NetworkBadge(network: row.network, name: networkName ?? row.network, size: 14)
                    }
                    if let timer = conversation.timerLine {
                        Label(timer, systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            DisappearingMenu(conversation: conversation)
            Button(action: conversation.toggleChatInfo) {
                Image(systemName: conversation.isShowingChatInfo ? "info.circle.fill" : "info.circle")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Chat Info (⌘⇧I)"))
            .accessibilityLabel(String(localized: "Chat Info"))
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
