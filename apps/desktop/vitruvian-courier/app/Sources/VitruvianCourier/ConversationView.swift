// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import UniformTypeIdentifiers

/// The right-hand pane for an open chat: its header (with its disappearing timer), the timeline, a bar for problems,
/// the messages scheduled to send later, and the composer; and the thread pane beside it when a thread is open. The
/// message actions' questions and pickers (Unsend's and Delete's questions, Forward, React, Send Later, a quick
/// reply's title, a new poll) are shown from here.
struct ConversationView: View {
    @ObservedObject var conversation: ConversationModel
    let composer: ComposerModel
    let inbox: InboxModel
    @ObservedObject var messageActions: MessageActionsModel
    let scheduled: ScheduledModel
    @ObservedObject var preferences: ComposerPreferences
    @ObservedObject var thread: ThreadModel
    @ObservedObject var focus: MessageFocus
    let appModel: AppModel
    var appearance: AppearancePreferences? = nil
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.timelineCovered) private var windowCoversTimeline
    @Environment(\.appearancePreferences) private var appearanceEnv
    @Environment(\.themeAccentHex) private var themeAccentHex
    @Environment(\.drawsLiquidGlass) private var drawsLiquidGlass
    @Environment(\.conversationLayoutProbe) private var conversationLayoutProbe
    @StateObject private var ui = MessageUI()
    @State private var scrollBox = TimelineScrollBox()
    @State private var isDropTargeted = false
    /// The message that was first when older ones were asked for: the view returns to it once they are in.
    @State private var restoreAnchor: String?
    @State private var topInView = false
    @State private var composerTextHeight: CGFloat = ComposerTextView.minimumHeight
    @State private var composerChromeSignature: String = ""
    /// Leaving the bottom is told a moment late: new content below pushes the end out of sight for an instant
    /// before the view scrolls to it, and that is not the person scrolling up.
    @State private var leavingBottom: Task<Void, Never>?
    @State private var bottomInView = false
    /// The scroll to a message (a search result) that has been made. Until it is, the bottom being in view is the
    /// timeline starting there, not the person reaching it, and reads nothing newer.
    @State private var scrolledToMessage: Int?
    /// Just opened at its newest message: the view keeps the bottom in view until this time while rows settle
    /// (pictures and link previews growing after layout), unless the person scrolls first.
    @State private var pinToBottomUntil: Date?
    /// Watches for the person's own scrolling while `pinToBottomUntil` holds.
    @State private var pinScrollMonitor: Any?
    /// When the person last scrolled, clicked or pressed a key in the window: the bottom leaving the view soon
    /// after is their doing; otherwise content grew under it (a picture's real size, a status line).
    @State private var lastUserScroll = Date.distantPast
    /// The last scroll wheel, key or drag by the person (not a click, which opens chats): older history is loaded
    /// from the network only after one, never because a short chat opened with its top in view.
    @State private var lastScrollGesture = Date.distantPast
    @State private var earlierTopInView = false
    @State private var userScrollMonitor: Any?
    @State private var inviteCandidates: [ContactCandidate] = []
    /// The thread's and Chat Info's widths, for their headers in the toolbar.
    @State private var sidePaneWidths: [SidePane: CGFloat] = [:]
    @State private var measuredHeaderOverlayHeight: CGFloat = 0
    @State private var measuredBottomBarHeight: CGFloat = 0
    @State private var windowToolbarOverlap: CGFloat = 0

    var body: some View {
        HSplitView {
            chat
                .frame(minWidth: 340, maxWidth: .infinity)
            if thread.rootID != nil, thread.roomID == conversation.roomID {
                ThreadPane(thread: thread, conversation: conversation, composer: thread.composer,
                           messageActions: messageActions, preferences: preferences, focus: focus,
                           headerInToolbar: drawsLiquidGlass, chatName: chatName)
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 560)
                    .reportsSidePaneWidth(.thread)
            }
            if conversation.isShowingChatInfo, let info = conversation.chatInfo {
                ChatInfoPane(
                    info: info,
                    bookmarks: conversation.chatInfoBookmarks,
                    isRefreshing: conversation.isRefreshingChatInfo,
                    isMuted: inbox.row(of: info.roomID)?.muted ?? false,
                    isPinned: inbox.row(of: info.roomID)?.pinned ?? false,
                    showsCloseButton: true,
                    now: { conversation.currentTime },
                    timerChoices: conversation.timerChoices,
                    onSelectTimer: { choice in Task { await conversation.setTimer(choice) } },
                    readAloud: messageActions.readAloud.isVitruvianSpeakerInstalled
                        ? inbox.row(of: info.roomID)?.effectiveReadAloud : nil,
                    onSelectReadAloud: { choice in Task { await inbox.setReadAloud(choice, ids: [info.roomID]) } },
                    onEditTitleAndAvatar: {
                        Task { await conversation.beginEditChat(info: info) }
                    },
                    onAddParticipants: {
                        Task { await conversation.beginAddParticipants(info: info) }
                    },
                    onMessageMember: { member in
                        Task { _ = await conversation.messageParticipant(userID: member.userID, in: info.roomID) }
                    },
                    onToggleMemberAdmin: { member, makeAdmin in
                        Task {
                            _ = await conversation.setParticipantAdmin(
                                userID: member.userID,
                                isAdmin: makeAdmin,
                                in: info.roomID
                            )
                        }
                    },
                    onRemoveMember: { member in
                        conversation.requestRemoveParticipant(member, info: info)
                    },
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
                    onMergeChat: info.isDirect ? {
                        if let row = inbox.selectedRow {
                            inbox.openMergeEditor(for: row)
                        }
                    } : nil,
                    onLeaveGroup: {
                        conversation.requestLeaveGroup(info: info)
                    },
                    onDeleteChat: {
                        conversation.requestDeleteChat(info: info)
                    },
                    onReportSpam: {
                        Task { await conversation.beginReportSpam(info: info) }
                    },
                    isAIAvailable: composer.aiProvider.isAvailable,
                    onSummarizeChat: {
                        conversation.summarizeChat()
                    },
                    onOpenAISettings: {
                        conversation.onOpenAISettings()
                    },
                    onToggleMute: {
                        if !conversation.performToggleMute(info.roomID) {
                            Task { await inbox.toggleMute(ids: [info.roomID]) }
                        }
                    },
                    onTogglePin: {
                        if !conversation.performTogglePin(info.roomID) {
                            Task { await inbox.togglePin(ids: [info.roomID]) }
                        }
                    },
                    onArchive: {
                        if !conversation.performToggleArchive(info.roomID) {
                            let rows = inbox.row(of: info.roomID).map { [$0] } ?? inbox.targetRows([info.roomID])
                            Task { await inbox.archive(ChatInfoPresentation.shouldArchive(rows), ids: [info.roomID]) }
                        }
                    },
                    onRemind: {
                        if !conversation.performRemindLater(info.roomID),
                           !inbox.isLocked,
                           inbox.isEntitled(.reminders) {
                            inbox.customReminder = ReminderRequest(ids: [info.roomID])
                        }
                    },
                    onSearchInChat: {
                        conversation.onSearchInChat(info.roomID)
                    },
                    onClose: conversation.toggleChatInfo,
                    inbox: inbox,
                    headerInToolbar: drawsLiquidGlass,
                    selfAvatarPath: conversation.ownAvatarPath(for: info)
                )
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                .reportsSidePaneWidth(.chatInfo)
            }
            if conversation.isShowingAIPane {
                AIPane(
                    chatTitle: chatName ?? String(localized: "Chat"),
                    preferences: composer.aiPreferences,
                    provider: composer.aiProvider,
                    isSummarizing: conversation.isSummarizingChat,
                    summarizingMessageCount: conversation.summarizingMessageCount,
                    summary: conversation.chatSummary,
                    summaryError: conversation.chatSummaryError,
                    isSummaryExpanded: conversation.isChatSummaryExpanded,
                    onSummarize: { conversation.summarizeChat() },
                    onCancelSummarize: { conversation.cancelSummarizeChat() },
                    onToggleSummaryExpanded: { conversation.isChatSummaryExpanded.toggle() },
                    onCopySummary: { text in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        conversation.onToast(String(localized: "Copied summary"))
                    },
                    onReadAloudSummary: { text in messageActions.readAloudSummary(text) },
                    onOpenAISettings: { conversation.onOpenAISettings() },
                    onClose: { conversation.isShowingAIPane = false },
                    headerInToolbar: drawsLiquidGlass
                )
                .reportsSidePaneWidth(.ai)
            }
        }
        .onPreferenceChange(SidePaneWidthKey.self) { sidePaneWidths = $0 }
        .environment(\.appearancePreferences, resolvedAppearance)
        .environment(\.themeRoomID, conversation.roomID)
        .environment(\.timelineCovered, windowCoversTimeline || coveredBySheet)
        .environment(
            \.themeAccentHex,
            resolvedAppearance?.effectiveTheme(for: conversation.roomID).accentColorHex ?? themeAccentHex
        )
        .tint(
            Color(
                hex: resolvedAppearance?.effectiveTheme(for: conversation.roomID).accentColorHex ?? themeAccentHex
            ) ?? .accentColor
        )
        .courierChatToolbar {
            ConversationHeaderContainer(inbox: inbox, conversation: conversation, readAloud: messageActions.readAloud,
                                        redactNamesAndPictures: redact, part: .identity)
        } actions: {
            ConversationHeaderContainer(inbox: inbox, conversation: conversation, readAloud: messageActions.readAloud,
                                        redactNamesAndPictures: redact, part: .actions)
        } panes: {
            sidePaneHeaders
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
        .sheet(isPresented: $conversation.isCreatingPoll) {
            if let polls = conversation.features.poll {
                PollCreatorWindow(features: polls, create: { await messageActions.createPoll($0) },
                                  close: { conversation.isCreatingPoll = false })
            }
        }
        // Edit Chat… and Report as Spam… are hosted by the window (`ChatRoomSheets`), so the inbox's menu can open them
        // for a chat that isn't open.
        .sheet(
            isPresented: Binding(
                get: { conversation.activeAddParticipantsRoom != nil },
                set: { shown in if !shown { conversation.activeAddParticipantsRoom = nil } }
            )
        ) {
            if let info = conversation.activeAddParticipantsRoom {
                let existingIDs = Set(info.members.map(\.userID))
                AddParticipantsSheet(
                    roomName: info.name,
                    network: info.network,
                    candidates: inviteCandidates,
                    onSearch: { query in
                        Task {
                            inviteCandidates = await conversation.searchInviteCandidates(
                                query: query,
                                network: info.network,
                                existingMemberIDs: existingIDs
                            )
                        }
                    },
                    onAdd: { userIDs in
                        Task { _ = await conversation.inviteParticipants(userIDs: userIDs, in: info.roomID) }
                    },
                    onCancel: {
                        conversation.activeAddParticipantsRoom = nil
                    }
                )
                .task(id: info.roomID) {
                    inviteCandidates = await conversation.searchInviteCandidates(
                        query: "",
                        network: info.network,
                        existingMemberIDs: existingIDs
                    )
                }
            }
        }
        .sheet(item: $conversation.activeViewOnceMessage) { msg in
            ViewOnceSheet(
                message: msg,
                onMarkPlayed: {
                    Task { await conversation.markPlayed(msg.id, roomID: msg.roomID) }
                },
                onDismiss: {
                    conversation.activeViewOnceMessage = nil
                }
            )
            .frame(width: 440)
        }
        .alert(confirmPrompt, isPresented: confirming) {
            Button(confirmTitle, role: .destructive) { Task { await messageActions.confirm() } }
            Button(String(localized: "Cancel"), role: .cancel) { messageActions.dismissRequest() }
        }
        .alert(roomConfirmTitle, isPresented: confirmingRoomAction) {
            Button(roomConfirmButtonTitle, role: .destructive) {
                Task { await conversation.confirmRoomAction() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                conversation.dismissRoomConfirmation()
            }
        } message: {
            if !roomConfirmDetail.isEmpty {
                Text(roomConfirmDetail)
            }
        }
    }

    private var resolvedAppearance: AppearancePreferences? {
        appearance ?? appearanceEnv
    }

    private var redact: Bool { resolvedAppearance?.redactNamesAndPictures ?? false }

    /// The open chat's name, under the thread's title (redacted when names are).
    private var chatName: String? {
        guard let title = conversation.openChatDisplayTitle else { return nil }
        return redact ? AppearancePreferences.redactedText(title, kind: .chatTitle) : title
    }

    /// With glass, the open side panes' headers as one toolbar item: each exactly as wide as its pane, side by side as
    /// the panes are, so each title sits over its own pane. The toolbar lays the item against its trailing edge, where
    /// the panes are. Nothing until the panes have been measured, so a header never shows at a guessed width.
    @ViewBuilder
    private var sidePaneHeaders: some View {
        let showsThread = thread.rootID != nil && thread.roomID == conversation.roomID
        let info = conversation.isShowingChatInfo ? conversation.chatInfo : nil
        let showsAI = conversation.isShowingAIPane
        let threadWidth = showsThread ? sidePaneWidths[.thread] : nil
        let infoWidth = info != nil ? sidePaneWidths[.chatInfo] : nil
        let aiWidth = showsAI ? sidePaneWidths[.ai] : nil
        if threadWidth != nil || infoWidth != nil || aiWidth != nil {
            HStack(spacing: 0) {
                if let threadWidth {
                    let isLast = infoWidth == nil && aiWidth == nil
                    ThreadPaneHeader(thread: thread, focus: focus, chatName: chatName, inToolbar: true)
                        .frame(width: max(0, threadWidth - (isLast ? PaneHeaderMetrics.toolbarItemSlack : 0)))
                }
                if let info, let infoWidth {
                    let isLast = aiWidth == nil
                    ChatInfoHeader(roomID: info.roomID, onClose: conversation.toggleChatInfo, inToolbar: true)
                        .frame(width: max(0, infoWidth - (isLast ? PaneHeaderMetrics.toolbarItemSlack : 0)))
                }
                if let aiWidth {
                    AIPaneHeader(onClose: { conversation.isShowingAIPane = false }, inToolbar: true)
                        .frame(width: max(0, aiWidth - PaneHeaderMetrics.toolbarItemSlack))
                }
            }
        }
    }

    static let timelineVerticalPadding: CGFloat = 8
    static let chatCoordinateSpace = "conversation-chat-space"

    var minimumHeaderInset: CGFloat {
        if drawsLiquidGlass {
            return windowToolbarOverlap > 0 ? windowToolbarOverlap + PaneHeaderMetrics.hairlineHeight : 0
        }
        return PaneHeaderMetrics.stripHeight + PaneHeaderMetrics.hairlineHeight
    }

    var effectiveHeaderInset: CGFloat {
        max(minimumHeaderInset, measuredHeaderOverlayHeight)
    }

    @ViewBuilder
    var chatTopHeaderOverlay: some View {
        VStack(spacing: 0) {
            if !drawsLiquidGlass {
                ConversationHeaderContainer(
                    inbox: inbox,
                    conversation: conversation,
                    readAloud: messageActions.readAloud,
                    redactNamesAndPictures: redact,
                    part: .strip
                )
            } else if windowToolbarOverlap > 0 {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.bar)
                        .frame(height: windowToolbarOverlap)
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: PaneHeaderMetrics.hairlineHeight)
                }
                // NSToolbar handles clicks in the toolbar band (verified by HeaderLineWindowTests).
                .allowsHitTesting(false)
            }
            if let banner = conversation.unreadThreadsBanner {
                ThreadRepliesBanner(
                    text: banner,
                    mentionsMe: conversation.unreadThreadsMentionMe,
                    show: conversation.showNextUnreadThread
                )
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ChatHeaderOverlayHeightKey.self, value: proxy.size.height)
            }
        )
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(Self.chatCoordinateSpace))
        } action: { frame in
            conversationLayoutProbe?("headerOverlay", frame)
        }
    }

    private var chat: some View {
        let effectiveTheme = resolvedAppearance?.effectiveTheme(for: conversation.roomID)
        return ZStack(alignment: .top) {
            WindowToolbarOverlapReader { overlap in
                windowToolbarOverlap = overlap
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            if let effectiveTheme, (effectiveTheme.wallpaper != .none || effectiveTheme.customWallpaperPath != nil) {
                ChatWallpaperCanvasView(
                    preset: effectiveTheme.wallpaper,
                    customImagePath: effectiveTheme.customWallpaperPath,
                    opacity: effectiveTheme.wallpaperOpacity,
                    blur: effectiveTheme.wallpaperBlur,
                    reduceTransparency: resolvedAppearance?.reduceTransparency ?? false
                )
                .courierExtendsUnderBars()
            }
            timeline
            chatTopHeaderOverlay
        }
        .coordinateSpace(name: Self.chatCoordinateSpace)
        .onPreferenceChange(ChatHeaderOverlayHeightKey.self) { measuredHeaderOverlayHeight = $0 }
        .modifier(IgnoreTopContainerSafeAreaWhenGlass(enabled: drawsLiquidGlass))
        // With glass the messages run under the composer, which floats over their bottom.
        .courierEdgeBar(.bottom) {
            VStack(spacing: 0) {
                if let problem = conversation.problem {
                    ProblemBar(problem: problem, retry: conversation.reload)
                }
                ScheduledStrip(scheduled: scheduled)
                TypingLine(text: conversation.typingLine)
                ConversationComposerContainer(
                    composer: composer,
                    inbox: inbox,
                    conversation: conversation,
                    preferences: preferences,
                    messageActions: messageActions,
                    focus: focus,
                    textHeight: $composerTextHeight,
                    chromeSignature: $composerChromeSignature,
                    closeThread: { conversation.deselectMessage() || closeThread() },
                    upArrow: upArrow,
                    redactNames: redact
                )
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(measuredBottomBarHeight - height) > 0.25 {
                    measuredBottomBarHeight = height
                }
            }
        }
        .overlay {
            if isDropTargeted {
                FileDropOverlayView(isShiftHeld: NSEvent.modifierFlags.contains(.shift))
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted, perform: drop)
        .onChange(of: controlActiveState, initial: true) { _, state in
            conversation.setWindowKey(state == .key)
        }
        // A window that closes (⌘W) is never told it stopped being key: going away says it.
        .onDisappear { conversation.setWindowKey(false) }
        // Esc leaves selection mode first, then ends an edit or clears a reply, then deselects the message, then
        // closes the thread pane.
        .onExitCommand { if !inbox.escape(), !composer.escape(), !conversation.deselectMessage() { _ = closeThread() } }
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

    /// A sheet or an alert of this chat is up: no message shows its hover bar behind it.
    private var coveredBySheet: Bool {
        conversation.isCreatingPoll || conversation.activeEditGroupDraft != nil
            || conversation.activeAddParticipantsRoom != nil || conversation.activeReportSpamDraft != nil
            || conversation.activeViewOnceMessage != nil || sheetRequestIsShown
            || conversation.pendingRoomConfirmation != nil
            || { if case .confirm? = messageActions.request { return true } else { return false } }()
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

    private var confirmingRoomAction: Binding<Bool> {
        Binding(
            get: { conversation.pendingRoomConfirmation != nil },
            set: { shown in
                if !shown { conversation.dismissRoomConfirmation() }
            }
        )
    }

    private var roomConfirmTitle: String {
        guard let request = conversation.pendingRoomConfirmation else { return "" }
        switch request {
        case let .leaveGroup(_, groupName, _):
            return ConversationModel.leaveGroupConfirmation(groupName: groupName).title
        case let .deleteChat(_, chatName, isDirect, features, _):
            return ConversationModel.deleteChatConfirmation(chatName: chatName, isDirect: isDirect, features: features).title
        case let .removeParticipant(_, member, groupName, _):
            return ConversationModel.removeParticipantConfirmation(
                memberName: member.name.isEmpty ? member.userID : member.name,
                groupName: groupName
            )
        }
    }

    private var roomConfirmDetail: String {
        guard let request = conversation.pendingRoomConfirmation else { return "" }
        switch request {
        case let .leaveGroup(_, groupName, _):
            return ConversationModel.leaveGroupConfirmation(groupName: groupName).detail
        case let .deleteChat(_, chatName, isDirect, features, _):
            return ConversationModel.deleteChatConfirmation(chatName: chatName, isDirect: isDirect, features: features).detail
        case .removeParticipant:
            return ""
        }
    }

    private var roomConfirmButtonTitle: String {
        guard let request = conversation.pendingRoomConfirmation else { return String(localized: "Confirm") }
        switch request {
        case .leaveGroup:
            return String(localized: "Leave Group")
        case .deleteChat:
            return String(localized: "Delete Chat")
        case .removeParticipant:
            return String(localized: "Remove")
        }
    }

    // MARK: Timeline

    @ViewBuilder
    private var timeline: some View {
        if conversation.isLoaded {
            // Made only once there is something in it, so that it starts at the newest message.
            Group {
                switch preferences.timelineEngine {
                case .table:
                    tableMessages
                case .swiftui:
                    messages
                }
            }
            .id(conversation.roomID)
            .overlay { placeholder }
        } else {
            Color.clear
                .overlay { placeholder }
        }
    }

    private var tableMessages: some View {
        let bottomInset = drawsLiquidGlass ? measuredBottomBarHeight : 0
        let resolvedThemeHex = resolvedAppearance?.effectiveTheme(for: conversation.roomID).accentColorHex ?? themeAccentHex
        return TimelineTableView(
            conversation: conversation,
            messageActions: messageActions,
            preferences: preferences,
            ui: ui,
            appModel: appModel,
            actions: actions,
            effectiveHeaderInset: effectiveHeaderInset,
            bottomSafeAreaInset: bottomInset,
            bottomBarSignature: bottomBarSignature,
            resolvedAppearance: resolvedAppearance,
            redact: redact,
            themeAccentHex: resolvedThemeHex,
            drawsLiquidGlass: drawsLiquidGlass,
            timelineCovered: windowCoversTimeline || coveredBySheet
        )
        .modifier(ConversationBottomScrollEdge())
        .modifier(IgnoreBottomContainerSafeAreaWhenGlass(enabled: drawsLiquidGlass))
        .overlay(alignment: .bottomTrailing) {
            jumpButton
                .padding(.bottom, bottomInset)
        }
    }

    private var messages: some View {
        let rowActions = actions
        return ScrollViewReader { proxy in
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
                    if !conversation.hasOlder, conversation.canLoadEarlier {
                        earlierRow
                    }
                    ForEach(conversation.items) { item in
                        TimelineItemView(item: item, isSelected: conversation.selectedMessageID == item.id,
                                         isHighlighted: conversation.highlightedMessageID == item.id,
                                         showsSent: conversation.lastOutgoingID == item.id, actions: rowActions, ui: ui)
                            .id(item.id)
                            .onGeometryChange(for: CGRect.self) {
                                $0.frame(in: .named(Self.chatCoordinateSpace))
                            } action: { frame in
                                ScrollPerfCounters.geometryCallback()
                                scrollBox.itemFrames[item.id] = frame
                                conversationLayoutProbe?("item/\(item.id)", frame)
                            }
                            .popover(
                                isPresented: Binding(
                                    get: { conversation.activeSenderCard?.messageID == item.id },
                                    set: { shown in
                                        if !shown, conversation.activeSenderCard?.messageID == item.id {
                                            conversation.dismissSenderCard()
                                        }
                                    }
                                ),
                                arrowEdge: .leading
                            ) {
                                if let card = conversation.activeSenderCard, card.messageID == item.id {
                                    UserHoverCard(
                                        member: card.member,
                                        network: card.network,
                                        sharedGroups: conversation.senderCardSharedGroups,
                                        contactsBridge: conversation.contactsBridge,
                                        now: conversation.currentTime,
                                        showsMessageButton: !(conversation.isDirectChat ?? false),
                                        onMessage: {
                                            let userID = card.userID
                                            conversation.dismissSenderCard()
                                            Task { _ = await conversation.messageParticipant(userID: userID) }
                                        },
                                        onSelectRoom: { targetRoomID in
                                            conversation.dismissSenderCard()
                                            appModel.open(.chat(roomID: targetRoomID))
                                        }
                                    )
                                    .onHover { hovering in
                                        conversation.setCardHovered(hovering)
                                    }
                                }
                            }
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
                                guard !Task.isCancelled else { return }
                                // Pushed out by content growing, not by the person: follow it down.
                                if conversation.isAtBottom, !conversation.isAwayFromLatest,
                                   conversation.scrollToMessageRequest == nil,
                                   restoreAnchor == nil,
                                   !topInView,
                                   Date().timeIntervalSince(lastUserScroll) > 0.6 {
                                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                                    return
                                }
                                conversation.scrolled(toBottom: false)
                            }
                        }
                }
                .padding(.top, effectiveHeaderInset + Self.timelineVerticalPadding)
                .padding(.horizontal, 14)
                .padding(.bottom, Self.timelineVerticalPadding)
                .background(TimelineScrollViewAccessor { scrollBox.nsScrollView = $0 })
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: { height in
                scrollBox.viewportHeight = height
            }
            .contentMargins(.top, effectiveHeaderInset, for: .scrollIndicators)
            .defaultScrollAnchor(.bottom)
            .modifier(ConversationBottomScrollEdge())
            // A click on the timeline's empty space (not on a message, which takes its own click) deselects.
            .deselectsOnEmptyClick { conversation.deselectMessage() }
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
                if (conversation.isAtBottom || isPinningToBottom), !conversation.isAwayFromLatest, restoreAnchor == nil {
                    scrollToBottom(proxy)
                }
            }
            .onAppear {
                startPinningToBottom(proxy)
                if userScrollMonitor == nil {
                    userScrollMonitor = NSEvent.addLocalMonitorForEvents(
                        matching: [.scrollWheel, .keyDown, .leftMouseDown, .leftMouseDragged]
                    ) { event in
                        MainActor.assumeIsolated {
                            lastUserScroll = Date()
                            if event.type != .leftMouseDown {
                                lastScrollGesture = Date()
                                // Scrolling up with the oldest message already in view: ask the network for more.
                                if earlierTopInView, event.type != .scrollWheel || event.scrollingDeltaY > 0 {
                                    conversation.loadEarlier()
                                }
                            }
                        }
                        return event
                    }
                }
            }
            .onDisappear {
                stopPinningToBottom()
                if let monitor = userScrollMonitor {
                    NSEvent.removeMonitor(monitor)
                    userScrollMonitor = nil
                }
            }
            .onChange(of: bottomBarSignature) { _, _ in
                // The bottom bar grew (a reply, files, more lines): keep the newest message in view.
                if conversation.isAtBottom, !conversation.isAwayFromLatest { scrollToBottom(proxy) }
            }
            .onChange(of: firstMessageID) { _, _ in
                // Older messages came in above: stay where the person was, cleared below the header overlay.
                // Older messages that joined without a scroll of the person's asking (a page the network answered
                // later) are anchored the same way.
                let arrived = conversation.takeEarlierAnchor()
                guard let anchor = restoreAnchor ?? arrived else { return }
                restoreAnchor = nil
                scrollToBelowHeader(proxy, id: anchor, preferCenter: false)
            }
        }
    }

    /// Changes when anything under the timeline changes size.
    private var bottomBarSignature: [String] {
        [composerChromeSignature,
         conversation.problem == nil ? "" : "problem", String(describing: composerTextHeight),
         conversation.typingLine == nil ? "" : "typing"]
    }

    /// At the top of the timeline when this Mac holds no older message but the network may: the "Loading earlier
    /// messages…" row while a page loads, and otherwise an empty row whose appearing, after the person scrolled,
    /// asks for one. Nothing is asked when a chat opens (the person has not scrolled).
    @ViewBuilder
    private var earlierRow: some View {
        Group {
            if conversation.isLoadingEarlier {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading earlier messages…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .accessibilityElement(children: .combine)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .onAppear {
            earlierTopInView = true
            if Date().timeIntervalSince(lastScrollGesture) < 1.0 { conversation.loadEarlier() }
        }
        .onDisappear { earlierTopInView = false }
    }

    private func requestOlder() {
        guard conversation.hasOlder, !conversation.isLoadingOlder else { return }
        stopPinningToBottom()
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

    /// Computes a normalized `ScrollViewReader` anchor that accounts for the top header overlay inset.
    static func headerClearedScrollAnchor(
        headerInset: CGFloat,
        viewportHeight: CGFloat,
        itemHeight: CGFloat = 0,
        preferCenter: Bool = false
    ) -> UnitPoint {
        let topClearance = headerInset + timelineVerticalPadding
        guard viewportHeight > topClearance else { return .top }
        if preferCenter {
            if itemHeight > 0, itemHeight >= viewportHeight - topClearance {
                return .top
            }
            let rawY: CGFloat = if itemHeight > 0, viewportHeight > itemHeight {
                ((topClearance + viewportHeight - itemHeight) * 0.5) / (viewportHeight - itemHeight)
            } else {
                (topClearance + viewportHeight) / (2 * viewportHeight)
            }
            return UnitPoint(x: 0.5, y: min(1, max(0, rawY)))
        }
        let rawY: CGFloat = if itemHeight > 0, viewportHeight - itemHeight > topClearance {
            topClearance / (viewportHeight - itemHeight)
        } else if itemHeight > 0 {
            0
        } else {
            min(0.45, topClearance / max(viewportHeight, topClearance + 1))
        }
        return UnitPoint(x: 0.5, y: min(1, max(0, rawY)))
    }

    private func scrollToBelowHeader(_ proxy: ScrollViewProxy, id: String, preferCenter: Bool) {
        let anchor = Self.headerClearedScrollAnchor(
            headerInset: effectiveHeaderInset,
            viewportHeight: scrollBox.viewportHeight,
            itemHeight: scrollBox.itemFrames[id]?.height ?? 0,
            preferCenter: preferCenter
        )
        proxy.scrollTo(id, anchor: anchor)
        DispatchQueue.main.async {
            scrollBox.nsScrollView?.layoutSubtreeIfNeeded()
            adjustScrollIfUnderHeader(id: id, alignTopIfUnaligned: !preferCenter)
        }
    }

    private func adjustScrollIfUnderHeader(id: String, alignTopIfUnaligned: Bool) {
        guard let sv = scrollBox.nsScrollView,
              let docView = sv.documentView,
              let frame = scrollBox.itemFrames[id]
        else { return }
        let desiredMinY = effectiveHeaderInset + Self.timelineVerticalPadding
        let needsAdjust = alignTopIfUnaligned
            ? abs(frame.minY - desiredMinY) > 0.5
            : frame.minY < desiredMinY - 0.5
        guard needsAdjust else { return }
        let docBounds = docView.bounds
        let clipBounds = sv.contentView.bounds
        let minOriginY = docBounds.minY
        let maxOriginY = max(minOriginY, docBounds.maxY - clipBounds.height)
        let sign: CGFloat = docView.isFlipped ? 1 : -1
        let targetY = min(maxOriginY, max(minOriginY, clipBounds.origin.y + sign * (frame.minY - desiredMinY)))
        guard abs(targetY - clipBounds.origin.y) > 0.5 else { return }
        sv.contentView.scroll(to: NSPoint(x: clipBounds.origin.x, y: targetY))
        sv.reflectScrolledClipView(sv.contentView)
        sv.layoutSubtreeIfNeeded()
    }

    /// Opened at a message or unread thread: scroll so the target lands below the header. Once there, reaching the
    /// bottom reads newer messages.
    private func scrollToMessage(_ proxy: ScrollViewProxy, _ request: ConversationModel.MessageScrollRequest) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scrollToBelowHeader(proxy, id: request.messageID, preferCenter: true)
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

    /// The first moments after the chat opens at its newest message, before the person has scrolled.
    private var isPinningToBottom: Bool {
        guard let until = pinToBottomUntil else { return false }
        return Date() < until
    }

    /// How long after opening the view keeps the newest message in view while rows settle.
    static let pinToBottomDuration: TimeInterval = 1.5

    /// Opened at its newest message: scroll to the bottom now, and again a few times while rows settle (a picture
    /// takes its real size, a link preview comes in), so the chat opens at the newest message and not above it.
    /// Never when it was opened at a message (a search result), and it stops as soon as the person scrolls.
    private func startPinningToBottom(_ proxy: ScrollViewProxy) {
        stopPinningToBottom()
        guard !conversation.isHeldAwayFromLatest, !conversation.isAwayFromLatest,
              conversation.scrollToMessageRequest == nil else { return }
        pinToBottomUntil = Date().addingTimeInterval(Self.pinToBottomDuration)
        pinScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // The person's own scroll (not the tail of a fling from before) ends it.
            if !event.phase.isEmpty || event.momentumPhase.isEmpty, event.scrollingDeltaY != 0 {
                MainActor.assumeIsolated { stopPinningToBottom() }
            }
            return event
        }
        let room = conversation.roomID
        for delay in [0.0, 0.05, 0.15, 0.3, 0.5, 0.75, 1.0, 1.25, Self.pinToBottomDuration] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard pinToBottomUntil != nil, conversation.roomID == room, !conversation.isAwayFromLatest,
                      conversation.scrollToMessageRequest == nil, restoreAnchor == nil else { return }
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
                if delay >= Self.pinToBottomDuration { stopPinningToBottom() }
            }
        }
    }

    private func stopPinningToBottom() {
        pinToBottomUntil = nil
        if let monitor = pinScrollMonitor {
            NSEvent.removeMonitor(monitor)
            pinScrollMonitor = nil
        }
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
            // Only when nothing is kept for the chat, and only after a moment: a fast read never flashes it.
            if conversation.problem == nil {
                DelayedSpinner()
                    .id(conversation.roomID)
                    .padding(.top, effectiveHeaderInset)
            }
        } else if conversation.items.isEmpty {
            Text(String(localized: "No messages yet"))
                .foregroundStyle(.secondary)
                .padding(.top, effectiveHeaderInset)
        }
    }

    /// The way back to the newest message.
    private var jumpButton: some View {
        JumpToLatestButton(conversation: conversation, bottom: conversation.bottom, appearance: resolvedAppearance)
    }

    private var actions: MessageActions {
        var base = MessageRowActions.make(
            conversation: conversation, messageActions: messageActions, preferences: preferences,
            composer: composer, ui: ui, source: .chat, deselect: { conversation.deselectMessage() }
        ) { id in
            conversation.selectedMessageID = id
            focus.inPane = false
        }
        if let merged = conversation.mergedChat {
            base.messageNetwork = { msg in
                if let idx = merged.roomIDs.firstIndex(of: msg.roomID), idx < merged.networks.count {
                    return merged.networks[idx]
                }
                return inbox.row(of: msg.roomID)?.network
            }
        }
        base.appearance = resolvedAppearance
        return base
    }

    // MARK: Dropping files

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                && $0.canLoadObject(ofClass: URL.self)
        }
        let imageProviders = providers.filter {
            !$0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                && $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        guard !fileProviders.isEmpty || !imageProviders.isEmpty else { return false }
        let shiftHeld = NSEvent.modifierFlags.contains(.shift)
        let lock = NSLock()
        var loadedURLs: [URL] = []
        let group = DispatchGroup()
        for provider in fileProviders {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.withLock { loadedURLs.append(url) }
                }
                group.leave()
            }
        }
        for provider in imageProviders {
            group.enter()
            let preferredTypes: [(UTType, String)] = [
                (.gif, "gif"),
                (.png, "png"),
                (.jpeg, "jpg"),
                (.webP, "webp"),
                (.tiff, "tiff"),
                (.image, "png"),
            ]
            if let match = preferredTypes.first(where: {
                provider.hasItemConformingToTypeIdentifier($0.0.identifier)
            }) {
                _ = provider.loadDataRepresentation(forTypeIdentifier: match.0.identifier) { data, _ in
                    if let data,
                       let savedURL = PasteboardAttachmentExtractor.writeImageData(
                           data,
                           preferredExtension: match.1
                       ) {
                        lock.withLock { loadedURLs.append(savedURL) }
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                guard !loadedURLs.isEmpty else { return }
                composer.attach(loadedURLs)
                if shiftHeld, composer.notices.isEmpty, composer.canSend {
                    _ = composer.submit()
                }
            }
        }
        return true
    }
}

/// Isolates `InboxModel` observation to the header bar so inbox updates in other chats do not invalidate `timeline`.
private struct ConversationHeaderContainer: View {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var conversation: ConversationModel
    let readAloud: ReadAloudService
    var redactNamesAndPictures: Bool = false
    var part: ConversationHeader.Part = .strip

    var body: some View {
        let headerRow = conversation.headerRow
        ConversationHeader(
            row: headerRow,
            displayTitle: conversation.openChatDisplayTitle,
            networkName: headerRow.map { NetworkNames.displayName(of: $0.network) ?? inbox.networkName($0.network) },
            conversation: conversation,
            readAloud: readAloud.isVitruvianSpeakerInstalled ? headerRow?.effectiveReadAloud : nil,
            onSelectReadAloud: { choice in
                guard let roomID = headerRow?.roomID ?? conversation.roomID else { return }
                Task { await inbox.setReadAloud(choice, ids: [roomID]) }
            },
            redactNamesAndPictures: redactNamesAndPictures,
            part: part
        )
    }
}

/// Isolates `ComposerModel` and `InboxModel` observation to the composer bar so keystrokes never redraw `timeline`.
private struct ConversationComposerContainer: View {
    @ObservedObject var composer: ComposerModel
    @ObservedObject var inbox: InboxModel
    @ObservedObject var conversation: ConversationModel
    @ObservedObject var preferences: ComposerPreferences
    let messageActions: MessageActionsModel
    let focus: MessageFocus
    @Binding var textHeight: CGFloat
    @Binding var chromeSignature: String
    let closeThread: () -> Bool
    let upArrow: () -> Bool
    /// Names and pictures are hidden (Appearance): the placeholder names no one.
    var redactNames: Bool = false

    /// "Message Florian on Google Messages": the chat's name and, in a merged chat, the network replies go to.
    private var placeholder: String {
        conversation.composerPlaceholderText(
            networkDisplayName: { net in NetworkNames.displayName(of: net) ?? inbox.networkName(net) },
            redactNames: redactNames
        )
    }

    private var currentChromeSignature: String {
        "\(composer.replyTarget?.eventID ?? "")|\(composer.attachments.count)|\(composer.notice == nil ? "" : "notice")|\(composer.isAIWriting)|\(composer.aiResult != nil)|\(composer.aiError ?? "")"
    }

    var body: some View {
        ComposerView(
            composer: composer,
            preferences: preferences,
            textHeight: $textHeight,
            showsIncognitoMark: conversation.incognitoIsOn && preferences.showIncognitoMark,
            mergedChat: conversation.mergedChat,
            activeReplyRoomID: conversation.activeReplyRoomID,
            activeReplyNetwork: conversation.activeReplyNetwork,
            activeReplyAccountName: conversation.activeReplyRoomID.flatMap { inbox.row(of: $0)?.loginName }
                ?? conversation.headerRow?.loginName ?? "",
            onCycleReplyNetwork: conversation.cycleMergedReplyNetwork,
            placeholder: placeholder,
            menus: ComposerMenus(
                sendLater: messageActions.requestSendLater,
                createPoll: { conversation.isCreatingPoll = true },
                pollsUnavailable: conversation.features.pollsUnavailableReason(network: conversation.network)
            ),
            escapeFirst: { inbox.escape() },
            escapeLast: closeThread,
            upArrow: upArrow
        )
        .simultaneousGesture(TapGesture().onEnded { focus.inPane = false })
        .onChange(of: currentChromeSignature, initial: true) { _, sig in
            if chromeSignature != sig {
                chromeSignature = sig
            }
        }
    }
}

/// The chat's picture, name and network, and with a disappearing timer running, "Messages disappear after 7 days",
/// with the timer's menu. Without glass it is a strip over the messages; with glass its two parts go in the window's
/// toolbar, the identity where the title was and the buttons as toolbar buttons.
struct ConversationHeader: View {
    enum Part { case strip, identity, actions }

    let row: InboxRow?
    var displayTitle: String? = nil
    let networkName: String?
    @ObservedObject var conversation: ConversationModel
    /// The chat's Read Aloud on Vitruvian Speaker choice; nil hides the menu (Vitruvian Speaker is not installed).
    var readAloud: ChatReadAloud? = nil
    var onSelectReadAloud: (ChatReadAloud) -> Void = { _ in }
    var redactNamesAndPictures: Bool = false
    var part: Part = .strip

    var body: some View {
        switch part {
        case .strip:
            HStack(spacing: 10) {
                identity
                Spacer(minLength: 0)
                actions
            }
            // The height every column's header strip has, so the titles share a line (PaneHeader.swift).
            .padding(.horizontal, PaneHeaderMetrics.inset)
            .frame(height: PaneHeaderMetrics.stripHeight)
            .clipped()
            .background(.bar)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: PaneHeaderMetrics.hairlineHeight)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        case .identity:
            HStack(alignment: .center, spacing: 8) { identity }
                .frame(maxHeight: 34)
                .clipped()
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
        case .actions:
            actions
        }
    }

    @ViewBuilder
    private var identity: some View {
        if let row {
            let formatted = PhoneNumberFormat.display(displayTitle.flatMap { $0.isEmpty ? nil : $0 } ?? row.displayTitle)
            let shownTitle = formatted.isEmpty ? String(localized: "Unnamed chat") : formatted
            // The inbox's picture: a group with none gets the group picture, not initials.
            // 28 pt with a square clip keeps multi-circle group avatars fully inside the header and above its hairline.
            ChatAvatar(row: row, size: 28)
                .frame(width: 28, height: 28)
                .blur(radius: redactNamesAndPictures ? 6 : 0)
                .clipShape(Rectangle())
            VStack(alignment: .leading, spacing: 1) {
                Text(
                    redactNamesAndPictures
                        ? AppearancePreferences.redactedText(shownTitle, kind: .chatTitle)
                        : shownTitle
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                let subtitle = subtitle(of: row)
                if subtitle != nil || conversation.timerLine != nil {
                    HStack(spacing: 4) {
                        if let subtitle {
                            Text(subtitle)
                                .lineLimit(1)
                        }
                        if subtitle != nil, conversation.timerLine != nil {
                            Text(verbatim: "·")
                        }
                        if let timer = conversation.timerLine {
                            Label(timer, systemImage: "timer")
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
    }

    /// Under the name: the network ("Google Messages") and, for a group whose members are known (Chat Info has
    /// read them), how many ("Google Messages · 5 members"). Nil when neither is known.
    private func subtitle(of row: InboxRow) -> String? {
        var parts: [String] = []
        if let networkName, !networkName.isEmpty { parts.append(networkName) }
        if !row.isDirect, let info = conversation.chatInfo, info.roomID == row.roomID, !info.members.isEmpty {
            let count = info.members.count
            parts.append(count == 1 ? String(localized: "1 member") : String(localized: "\(count) members"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The buttons: borderless in the strip; in the toolbar in the toolbar's own style, which draws them as glass.
    @ViewBuilder
    private var actions: some View {
        let inToolbar = part == .actions
        DisappearingMenu(conversation: conversation, inToolbar: inToolbar)
        let info = Button(action: conversation.toggleChatInfo) {
            Image(systemName: conversation.isShowingChatInfo ? "info.circle.fill" : "info.circle")
        }
        .contextMenu {
            Button(String(localized: "Chat Info")) {
                conversation.toggleChatInfo()
            }
            Divider()
            Button(String(localized: "Summarize Chat")) {
                if conversation.composer.aiProvider.isAvailable {
                    conversation.summarizeChat()
                } else {
                    conversation.onOpenAISettings()
                }
            }
            .disabled(!conversation.composer.aiProvider.isAvailable)
            .help(conversation.composer.aiProvider.isAvailable ? "" : String(localized: "Set up AI in Settings"))
            if let readAloud {
                Divider()
                Menu(String(localized: "Read Aloud on Vitruvian Speaker")) {
                    Picker(
                        String(localized: "Read Aloud on Vitruvian Speaker"),
                        selection: Binding(get: { readAloud }, set: onSelectReadAloud)
                    ) {
                        ForEach(ChatReadAloud.settable, id: \.rawValue) { choice in
                            Text(choice.displayTitle).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Text(String(localized: "Muted chats are never read aloud."))
                }
            }
        }
        .help(String(localized: "Chat Info (⌘⇧I)"))
        .accessibilityLabel(String(localized: "Chat Info"))
        if inToolbar { info } else { info.buttonStyle(.borderless) }
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
        case .loadFailed: String(localized: "Vitruvian Courier could not read the latest messages.")
        case let .actionFailed(reason): reason
        case .messageGone: String(localized: "That message isn’t in this chat any more.")
        }
    }
}

/// A spinner that shows only after `delay`, so a read that finishes sooner never flashes one.
private struct DelayedSpinner: View {
    var delay: Duration = .milliseconds(250)
    @State private var isShown = false

    var body: some View {
        Group {
            if isShown { ProgressView() } else { Color.clear }
        }
        .task {
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { isShown = true }
        }
    }
}

/// The way back to the newest message. Away from it (opened at a search result) it says "Jump to latest", with
/// a dot once something new has come in. It watches `BottomState` itself, so the timeline does not have to.
private struct JumpToLatestButton: View {
    @ObservedObject var conversation: ConversationModel
    @ObservedObject var bottom: BottomState
    let appearance: AppearancePreferences?

    var body: some View {
        if !bottom.isAtBottom || conversation.isAwayFromLatest {
            Button {
                conversation.jumpToBottom()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                    if conversation.isAwayFromLatest {
                        Text(String(localized: "Jump to latest"))
                            .font(.callout.weight(.medium))
                        if conversation.hasNewerWhileAway {
                            let accentHex = appearance?.effectiveTheme(for: conversation.roomID).accentColorHex
                                ?? CourierThemePreset.classicTeal.defaultAccentHex
                            Circle()
                                .fill(Color(hex: accentHex) ?? Color.accentColor)
                                .frame(width: 7, height: 7)
                                .accessibilityLabel(String(localized: "New messages"))
                        }
                    } else if bottom.newMessageCount > 0 {
                        Text(bottom.newMessageCount == 1 ? String(localized: "1 new message")
                            : String(localized: "\(bottom.newMessageCount) new messages"))
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
}

private struct ConversationLayoutProbeKey: EnvironmentKey {
    static let defaultValue: ((String, CGRect) -> Void)? = nil
}

extension EnvironmentValues {
    var conversationLayoutProbe: ((String, CGRect) -> Void)? {
        get { self[ConversationLayoutProbeKey.self] }
        set { self[ConversationLayoutProbeKey.self] = newValue }
    }
}

@MainActor
private final class TimelineScrollBox {
    weak var nsScrollView: NSScrollView?
    var itemFrames: [String: CGRect] = [:]
    var viewportHeight: CGFloat = 0
}

private struct TimelineScrollViewAccessor: NSViewRepresentable {
    let onResolve: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> AccessorView {
        AccessorView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: AccessorView, context: Context) {
        nsView.onResolve = onResolve
        nsView.report()
    }

    final class AccessorView: NSView {
        var onResolve: (NSScrollView?) -> Void

        init(onResolve: @escaping (NSScrollView?) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        func report() {
            let sv = superview.flatMap { start in
                sequence(first: start, next: \.superview)
                    .compactMap { $0 as? NSScrollView }
                    .first
            }
            DispatchQueue.main.async { [onResolve] in
                onResolve(sv)
            }
        }
    }
}

private struct ChatHeaderOverlayHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct IgnoreTopContainerSafeAreaWhenGlass: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea(.container, edges: .top)
        } else {
            content
        }
    }
}

private struct IgnoreBottomContainerSafeAreaWhenGlass: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea(.container, edges: .bottom)
        } else {
            content
        }
    }
}

private struct ConversationBottomScrollEdge: ViewModifier {
    @Environment(\.liquidGlass) private var liquidGlass

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), liquidGlass {
            content.scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            content
        }
    }
}

/// Measures how many vertical points the top of `ConversationView` extends under the window's unified toolbar
/// (`contentLayoutRect`) so the transcript can reserve exact top clearance inside `HSplitView`.
private struct WindowToolbarOverlapReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> OverlapObserverView {
        OverlapObserverView(onChange: onChange)
    }

    func updateNSView(_ nsView: OverlapObserverView, context: Context) {
        nsView.onChange = onChange
    }

    final class OverlapObserverView: NSView {
        var onChange: (CGFloat) -> Void
        private var contentLayoutObservation: NSKeyValueObservation?
        private var resizeObserver: NSObjectProtocol?
        private var lastReported: CGFloat = -1

        init(onChange: @escaping (CGFloat) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        deinit {
            contentLayoutObservation?.invalidate()
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            contentLayoutObservation?.invalidate()
            contentLayoutObservation = nil
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            guard let window else {
                reportIfNeeded(0)
                return
            }
            contentLayoutObservation = window.observe(\.contentLayoutRect, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.measure()
                }
            }
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.measure()
                }
            }
            Task { @MainActor [weak self] in
                self?.measure()
            }
        }

        override func layout() {
            super.layout()
            measure()
        }

        private func measure() {
            guard let window, window.toolbar != nil else {
                reportIfNeeded(0)
                return
            }
            let topInWindow = convert(bounds, to: nil).maxY
            let overlap = max(0, ceil(topInWindow - window.contentLayoutRect.maxY))
            reportIfNeeded(overlap)
        }

        private func reportIfNeeded(_ value: CGFloat) {
            guard abs(value - lastReported) > 0.25 else { return }
            lastReported = value
            DispatchQueue.main.async { [weak self] in
                self?.onChange(value)
            }
        }
    }
}
