// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Something the person can ask for by name, from the command bar (⌘J, part 4.7).
public struct CourierCommand: Identifiable {
    public enum Category: String, Equatable, Sendable {
        case inbox
        case search
        case message
        case accounts
        case chatInfo
    }

    /// The inventory ledger's name for it, in English, which never changes with the language.
    public let id: String
    /// What the person reads.
    public let title: String
    /// The shortcut as the menu shows it, when it has one.
    public let keys: String?
    /// The primary shortcut key character, when applicable.
    public let key: String?
    /// The modifier flags for `key`, when applicable.
    public let modifiers: KeyModifiers
    /// The command bar category this command belongs to.
    public let category: Category
    /// What to ask the person before running it, when it changes many chats at once; nil when it just runs. The
    /// command bar shows it with the command's title and runs the command only after a yes.
    public let confirmation: String?
    /// Whether it can do anything now. The bar greys out what can't.
    public let isEnabled: @MainActor () -> Bool
    /// Does it. What takes the engine is started and not waited for.
    public let run: @MainActor () -> Void

    public init(
        id: String,
        title: String,
        keys: String?,
        key: String? = nil,
        modifiers: KeyModifiers = [],
        category: Category = .message,
        confirmation: String?,
        isEnabled: @escaping @MainActor () -> Bool,
        run: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.keys = keys
        self.key = key
        self.modifiers = modifiers
        self.category = category
        self.confirmation = confirmation
        self.isEnabled = isEnabled
        self.run = run
    }
}

/// The inbox's and search's commands, registered here for the command bar, which part 4.7 builds.
public enum CommandSet {
    /// The 13 commands of the inventory ledger that act on the inbox, in its order.
    ///
    /// The four bulk commands ("Archive all …", "Mark all chats as read") carry a `confirmation` for the bar to ask
    /// first; `run` itself acts at once. The other nine have none.
    ///
    /// The filter commands step through their choices one at a time until the bar has the pickers that list them:
    /// Filter Chats is Cycle Filters (⌥Tab), Filter by folder type steps through Archived, Low priority, Hidden,
    /// Requests, Reminders and Send later and back to none, Filter by type through DMs, Groups and back to none, and
    /// Filter by account through the accounts.
    @MainActor
    public static func inbox(_ inbox: InboxModel, _ spaces: SpacesModel) -> [CourierCommand] {
        let sweepable: @MainActor () -> Bool = { inbox.isLoaded && inbox.canArchiveAll }
        return [
            CourierCommand(id: "Archive all chats", title: String(localized: "Archive all chats"), keys: nil,
                           confirmation: String(localized: "Archive every chat in this space? Pinned chats stay where they are. You can undo this."),
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAll(readOnly: false) }
            },
            CourierCommand(id: "Archive all chats older than a week",
                           title: String(localized: "Archive all chats older than a week"), keys: nil,
                           confirmation: String(localized: "Archive every chat in this space whose last message is over a week old? Pinned chats stay where they are. You can undo this."),
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAll(readOnly: false, olderThanDays: 7) }
            },
            CourierCommand(id: "Archive all read chats", title: String(localized: "Archive all read chats"),
                           keys: "⌘⇧E",
                           confirmation: String(localized: "Archive every chat in this space that has nothing unread? Pinned chats stay where they are. You can undo this."),
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAllRead() }
            },
            CourierCommand(id: "Mark all chats as read", title: String(localized: "Mark all chats as read"),
                           keys: nil,
                           confirmation: String(localized: "Mark every unread chat in this space as read? Your networks are told too, so this can’t be undone."),
                           isEnabled: { hasUnread(inbox, spaces) }) {
                Task { await inbox.markAllRead() }
            },
            CourierCommand(id: "Next Chat", title: String(localized: "Next Chat"), keys: "⌘]", confirmation: nil,
                           isEnabled: { !inbox.rows.isEmpty }) {
                inbox.selectNext()
            },
            CourierCommand(id: "Show message requests", title: String(localized: "Show message requests"),
                           keys: nil, confirmation: nil, isEnabled: { true }) {
                spaces.select("requests")
            },
            CourierCommand(id: "Toggle space bar", title: String(localized: "Toggle space bar"), keys: "⌘S", confirmation: nil,
                           isEnabled: { true }) {
                inbox.preferences.showSpaceBar.toggle()
            },
            CourierCommand(id: "Edit spaces", title: String(localized: "Edit spaces"), keys: nil, confirmation: nil,
                           isEnabled: { true }) {
                spaces.isEditing = true
            },
            CourierCommand(id: "Filter Chats", title: String(localized: "Filter Chats"), keys: nil, confirmation: nil,
                           isEnabled: { true }) {
                inbox.cycleFilter()
            },
            CourierCommand(id: "Filter by folder type", title: String(localized: "Filter by folder type"),
                           keys: nil, confirmation: nil, isEnabled: { true }) {
                step(inbox, through: SpacesModel.placeFilters)
            },
            CourierCommand(id: "Filter by type", title: String(localized: "Filter by type"), keys: nil, confirmation: nil,
                           isEnabled: { true }) {
                step(inbox, through: [.dms, .groups])
            },
            CourierCommand(id: "Filter by account", title: String(localized: "Filter by account"), keys: "⌘⌥A", confirmation: nil,
                           isEnabled: { nextAccount(inbox, spaces) != nil }) {
                if let next = nextAccount(inbox, spaces) { spaces.select(next.spaceID) }
            },
            CourierCommand(id: "Toggle chat selection mode", title: String(localized: "Toggle chat selection mode"),
                           keys: nil, confirmation: nil, isEnabled: { inbox.isSelecting || !inbox.rows.isEmpty }) {
                if inbox.isSelecting { inbox.endSelecting() } else { inbox.beginSelecting() }
            },
        ]
    }

    /// The three search commands, for the command bar: "Search chats" and "Search messages in all chats" open ⌘K's
    /// panel over every chat; "Search messages in current chat" opens it in the open chat (⌘F), and is off with no
    /// chat open. None asks first.
    @MainActor
    public static func search(_ search: SearchModel,
                              openRoomID: @escaping @MainActor () -> String?) -> [CourierCommand] {
        [
            CourierCommand(id: "Search chats", title: String(localized: "Search chats"), keys: "⌘K",
                           confirmation: nil, isEnabled: { true }) {
                search.show()
            },
            CourierCommand(id: "Search messages in all chats", title: String(localized: "Search messages in all chats"),
                           keys: "⌘K", confirmation: nil, isEnabled: { true }) {
                search.show()
            },
            CourierCommand(id: "Search messages in current chat",
                           title: String(localized: "Search messages in current chat"), keys: "⌘F",
                           confirmation: nil, isEnabled: { openRoomID() != nil }) {
                guard let roomID = openRoomID() else { return }
                search.show(in: roomID)
            },
        ]
    }

    /// The message commands of the ledger's command bar (02 §3.3, "Message" and "Navigation and global"; 02 §3.4.2
    /// items 5 and 8), for the command bar part 4.7 builds: Send later, Create quick reply from draft (it asks for a
    /// title), Edit, Forward, Unsend, Delete for me, Reply in thread, Reply privately and Mark as unread. Each acting on a message acts on the selected one, and is on only
    /// when `MessageActions.available` offers it for that message, as the message's menu does; running it does what
    /// the menu's item does (Unsend and Delete for Me still ask first, in their own words, so none carries a
    /// `confirmation`). Send later and the quick reply act on the composer's text.
    @MainActor
    public static func message(_ actions: MessageActionsModel, _ conversation: ConversationModel) -> [CourierCommand] {
        func offers(_ action: MessageAction) -> Bool {
            guard let selected = conversation.selectedMessage else { return false }
            return conversation.availableActions(for: selected).actions.contains(action)
        }
        func run(_ action: MessageAction) {
            guard let selected = conversation.selectedMessage else { return }
            Task { await actions.perform(action, on: selected.id) }
        }
        return [
            CourierCommand(id: "Send later", title: String(localized: "Send later"), keys: "⌘⇧L", confirmation: nil,
                           isEnabled: { conversation.composer.canSchedule }) {
                actions.requestSendLater()
            },
            CourierCommand(id: "Create quick reply from draft", title: String(localized: "Create quick reply from draft"),
                           keys: nil, confirmation: nil, isEnabled: { actions.canCreateQuickReply }) {
                actions.requestQuickReplyFromDraft()
            },
            CourierCommand(id: "Edit", title: String(localized: "Edit"), keys: "⌘T", confirmation: nil,
                           isEnabled: { offers(.edit) }) {
                guard let selected = conversation.selectedMessage, offers(.edit) else { return }
                conversation.composer.startEditing(selected)
            },
            CourierCommand(id: "Forward", title: String(localized: "Forward"), keys: "⌘⇧F", confirmation: nil,
                           isEnabled: { offers(.forward) }) {
                run(.forward)
            },
            CourierCommand(id: "Unsend", title: String(localized: "Unsend"), keys: nil, confirmation: nil,
                           isEnabled: { offers(.unsend) }) {
                run(.unsend)
            },
            CourierCommand(id: "Delete for me", title: String(localized: "Delete for me"), keys: nil,
                           confirmation: nil, isEnabled: { offers(.deleteForMe) }) {
                run(.deleteForMe)
            },
            CourierCommand(id: "Reply in thread", title: String(localized: "Reply in thread"), keys: "⌘↓",
                           confirmation: nil, isEnabled: { offers(.replyInThread) }) {
                run(.replyInThread)
            },
            CourierCommand(id: "Reply privately", title: String(localized: "Reply privately"), keys: nil,
                           confirmation: nil, isEnabled: { offers(.replyPrivately) }) {
                run(.replyPrivately)
            },
            CourierCommand(id: "Mark as unread", title: String(localized: "Mark as unread"), keys: nil,
                           confirmation: nil, isEnabled: { offers(.markUnread) }) {
                run(.markUnread)
            },
        ]
    }

    /// Incognito and the accounts (02 §2.6): "Turn on incognito mode" (and, while it is on, "Turn off incognito
    /// mode", the same ledger row's other state: only the one that applies is on), "Add Account" and "Accounts". Both
    /// account commands open Add a Network until the Accounts pane comes (4.6), where Add Another Account is offered
    /// for a linked network. The ledger's "Account" command (its pane is 4.6's) is not registered yet. Turning
    /// Incognito on asks about typing (`ConversationModel.setIncognito`), as Settings does. None asks first.
    @MainActor
    public static func accounts(_ login: LoginFlowModel, _ conversation: ConversationModel) -> [CourierCommand] {
        [
            CourierCommand(id: "Turn on incognito mode", title: String(localized: "Turn on incognito mode"), keys: nil,
                           confirmation: nil,
                           isEnabled: { !conversation.incognitoIsOn && conversation.isEntitled(.incognito) }) {
                conversation.setIncognito(true)
            },
            CourierCommand(id: "Turn off incognito mode", title: String(localized: "Turn off incognito mode"),
                           keys: nil, confirmation: nil, isEnabled: { conversation.incognitoIsOn }) {
                conversation.setIncognito(false)
            },
            CourierCommand(id: "Add Account", title: String(localized: "Add Account"), keys: nil, confirmation: nil,
                           isEnabled: { true }) {
                login.showPicker()
            },
            CourierCommand(id: "Accounts", title: String(localized: "Accounts"), keys: nil, confirmation: nil,
                           isEnabled: { true }) {
                login.showPicker()
            },
        ]
    }

    /// Chat info, calendar, sender profile and new group/blast commands (Milestone 4.5).
    /// Per Ruling 5 (inventory 02 lines 298, 340, 744): Toggle Chat Info is ⌘⇧I (`⌘I` stays Italic),
    /// and Search in chat info has no shortcut (it still focuses the search field when chosen from the command list).
    @MainActor
    public static func chatInfo(
        hasOpenChat: @escaping @MainActor () -> Bool = { true },
        hasSelectedMessage: @escaping @MainActor () -> Bool = { true },
        toggleChatInfo: @escaping @MainActor () -> Void = {},
        searchChatInfo: @escaping @MainActor () -> Void = {},
        toggleCalendar: @escaping @MainActor () -> Void = {},
        showSenderCard: @escaping @MainActor () -> Void = {},
        newGroupOrBlast: @escaping @MainActor () -> Void = {},
        openMediaViewer: @escaping @MainActor () -> Void = {}
    ) -> [CourierCommand] {
        [
            CourierCommand(
                id: "conversation.toggleChatInfo",
                title: String(localized: "Toggle chat info"),
                keys: "⌘⇧I",
                confirmation: nil,
                isEnabled: hasOpenChat,
                run: toggleChatInfo
            ),
            CourierCommand(
                id: "conversation.searchChatInfo",
                title: String(localized: "Search in chat info"),
                keys: nil,
                confirmation: nil,
                isEnabled: hasOpenChat,
                run: searchChatInfo
            ),
            CourierCommand(
                id: "conversation.toggleCalendar",
                title: String(localized: "Jump to date in chat"),
                keys: "⌘⌥K",
                confirmation: nil,
                isEnabled: hasOpenChat,
                run: toggleCalendar
            ),
            CourierCommand(
                id: "conversation.showSenderCard",
                title: String(localized: "Show sender profile"),
                keys: "⌘⇧O",
                confirmation: nil,
                isEnabled: hasSelectedMessage,
                run: showSenderCard
            ),
            CourierCommand(
                id: "inbox.newGroupOrBlast",
                title: String(localized: "New group or blast chat"),
                keys: "⌘⇧N",
                confirmation: nil,
                isEnabled: { true },
                run: newGroupOrBlast
            ),
            mediaViewer(openMediaViewer: openMediaViewer),
        ]
    }

    /// `command Media viewer` (`id: "media.viewer"`, `title: "Media viewer"`): opens the Media Viewer window.
    @MainActor
    public static func mediaViewer(
        openMediaViewer: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        CourierCommand(
            id: "media.viewer",
            title: String(localized: "Media viewer"),
            keys: nil,
            confirmation: nil,
            isEnabled: { true },
            run: openMediaViewer
        )
    }

    /// `hotkey Message: Record Audio` (`⌘⇧A`): starts or stops recording a voice note in the active composer.
    @MainActor
    public static func recordAudio(_ composer: ComposerModel) -> CourierCommand {
        CourierCommand(
            id: "hotkey Message: Record Audio",
            title: String(localized: "Record Voice Note"),
            keys: "⌘⇧A",
            confirmation: nil,
            isEnabled: {
                composer.roomID != nil && (
                    composer.voiceRecorder.isRecordingOrReviewing || composer.features.supportsVoiceSend
                )
            }
        ) {
            Task {
                if composer.voiceRecorder.isRecordingOrReviewing {
                    await composer.voiceRecorder.stopAndSend(using: composer)
                } else {
                    await composer.startVoiceRecording()
                }
            }
        }
    }

    /// `hotkey Message: Send GIF` (`⌘⇧G`, `id: "message.sendGIF"`): opens `GIFPickerPopover` in the active composer.
    @MainActor
    public static func sendGIF(_ composer: ComposerModel) -> CourierCommand {
        CourierCommand(
            id: "message.sendGIF",
            title: String(localized: "Send GIF"),
            keys: "⌘⇧G",
            key: "g",
            modifiers: [.command, .shift],
            category: .message,
            confirmation: nil,
            isEnabled: { composer.canSendGIF },
            run: { _ = composer.openGIFPicker() }
        )
    }

    /// `hotkey Message: Send Sticker` (`⌘⌥⇧S`, `id: "message.sendSticker"`): opens `StickerPickerPopover` in the active composer.
    @MainActor
    public static func sendSticker(_ composer: ComposerModel) -> CourierCommand {
        CourierCommand(
            id: "message.sendSticker",
            title: String(localized: "Send Sticker"),
            keys: "⌘⌥⇧S",
            key: "s",
            modifiers: [.command, .option, .shift],
            category: .message,
            confirmation: nil,
            isEnabled: { composer.canSendSticker },
            run: { _ = composer.openStickerPicker() }
        )
    }

    /// Composer media commands (`message.sendGIF` and `message.sendSticker`) under `.message` category.
    @MainActor
    public static func composerMedia(_ composer: ComposerModel) -> [CourierCommand] {
        [sendGIF(composer), sendSticker(composer)]
    }

    /// `command Open space in new window` (`id: "Open space in new window"`): opens the current space in a detached window.
    @MainActor
    public static func openSpaceInNewWindow(
        _ inbox: InboxModel,
        registry: DetachedWindowRegistry
    ) -> CourierCommand {
        CourierCommand(
            id: "Open space in new window",
            title: String(localized: "Open space in new window"),
            keys: nil,
            category: .inbox,
            confirmation: nil,
            isEnabled: { !inbox.lifecycle.isLocked && AppLockGate.shared.canPerform(.openChat) },
            run: {
                guard !inbox.lifecycle.isLocked, AppLockGate.shared.canPerform(.openChat) else { return }
                registry.open(.space(spaceID: inbox.query.space))
            }
        )
    }

    /// `command Show keyboard shortcuts` (`id: "Show keyboard shortcuts"`): opens the `⌘/` Keyboard Shortcuts sheet.
    @MainActor
    public static func showKeyboardShortcuts(_ hotkeys: HotkeyRegistry) -> CourierCommand {
        let primary = hotkeys.primaryChord(for: "Keyboard Shortcuts")?.symbols ?? "⌘/"
        return CourierCommand(
            id: "Show keyboard shortcuts",
            title: String(localized: "Show keyboard shortcuts"),
            keys: primary,
            category: .inbox,
            confirmation: nil,
            isEnabled: { AppLockGate.shared.canPerform(.other) },
            run: {
                guard AppLockGate.shared.canPerform(.other) else { return }
                hotkeys.isShortcutsSheetPresented = true
            }
        )
    }

    /// `command Hotkeys` (`id: "Hotkeys"`): opens the Settings ▸ Shortcuts pane.
    @MainActor
    public static func hotkeys(_ coordinator: AppMenuCoordinator) -> CourierCommand {
        CourierCommand(
            id: "Hotkeys",
            title: String(localized: "Hotkeys"),
            keys: nil,
            category: .inbox,
            confirmation: nil,
            isEnabled: { !coordinator.lifecycle.isLocked },
            run: { coordinator.openSettings(.shortcuts) }
        )
    }

    // MARK: - Milestone 4.6 Settings, Help & System Commands

    @MainActor
    public static func settings(
        _ navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        paneCommand(id: "Settings", title: String(localized: "Settings"), keys: "⌘,", pane: .general, navigation: navigation, openWindow: openWindow)
    }

    @MainActor
    public static func general(
        _ navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        paneCommand(id: "General", title: String(localized: "General"), keys: nil, pane: .general, navigation: navigation, openWindow: openWindow)
    }

    @MainActor
    public static func appearance(
        _ navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        paneCommand(id: "Appearance", title: String(localized: "Appearance"), keys: nil, pane: .appearance, navigation: navigation, openWindow: openWindow)
    }

    @MainActor
    public static func notifications(
        _ navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        paneCommand(id: "Notifications", title: String(localized: "Notifications"), keys: nil, pane: .notifications, navigation: navigation, openWindow: openWindow)
    }

    @MainActor
    public static func accounts(
        _ navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        paneCommand(id: "Accounts", title: String(localized: "Accounts"), keys: nil, pane: .accounts, navigation: navigation, openWindow: openWindow)
    }

    @MainActor
    public static func account(
        _ navigation: SettingsNavigationModel,
        accountKey: String? = nil,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        CourierCommand(
            id: "Account",
            title: String(localized: "Account"),
            keys: nil,
            category: .accounts,
            confirmation: nil,
            isEnabled: { AppLockGate.shared.canPerform(.settingsChange) },
            run: {
                guard AppLockGate.shared.canPerform(.settingsChange) else { return }
                navigation.openPane(.accounts, accountKey: accountKey)
                openWindow()
            }
        )
    }

    @MainActor
    public static func hotkeys(
        _ navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        paneCommand(id: "Hotkeys", title: String(localized: "Hotkeys"), keys: nil, pane: .hotkeys, navigation: navigation, openWindow: openWindow)
    }

    @MainActor
    public static func quickReplies(
        _ navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        paneCommand(id: "Quick Replies", title: String(localized: "Quick Replies"), keys: nil, pane: .quickReplies, navigation: navigation, openWindow: openWindow)
    }

    @MainActor
    public static func bridges(
        _ navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        paneCommand(id: "Bridges", title: String(localized: "Bridges"), keys: nil, pane: .bridges, navigation: navigation, openWindow: openWindow)
    }

    @MainActor
    public static func about(
        _ navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        paneCommand(id: "About", title: String(localized: "About"), keys: nil, pane: .about, navigation: navigation, openWindow: openWindow)
    }

    @MainActor
    public static func help(
        _ navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        paneCommand(id: "Help", title: String(localized: "Help"), keys: nil, pane: .about, navigation: navigation, openWindow: openWindow)
    }

    @MainActor
    public static func lockApp(_ lifecycle: SystemLifecycleModel) -> CourierCommand {
        CourierCommand(
            id: "Lock app",
            title: String(localized: "Lock app"),
            keys: nil,
            category: .inbox,
            confirmation: nil,
            isEnabled: { !lifecycle.isLocked },
            run: { lifecycle.lockApp() }
        )
    }

    @MainActor
    public static func reportProblem(
        presentReportProblem: @escaping @MainActor () -> Void
    ) -> CourierCommand {
        CourierCommand(
            id: "Report a problem",
            title: String(localized: "Report a problem"),
            keys: "⌘⇧P",
            category: .inbox,
            confirmation: nil,
            isEnabled: { AppLockGate.shared.canPerform(.export) },
            run: {
                guard AppLockGate.shared.canPerform(.export) else { return }
                presentReportProblem()
            }
        )
    }

    @MainActor
    public static func restartNotificationCenter(
        _ restart: @escaping @MainActor () -> Void
    ) -> CourierCommand {
        CourierCommand(
            id: "Restart Notification Center",
            title: String(localized: "Restart Notification Center"),
            keys: nil,
            category: .inbox,
            confirmation: nil,
            isEnabled: { AppLockGate.shared.canPerform(.settingsChange) },
            run: {
                guard AppLockGate.shared.canPerform(.settingsChange) else { return }
                restart()
            }
        )
    }

    /// All Milestone 4.6 Settings, Help, and System commands for the command bar.
    @MainActor
    public static func settingsAndSystem(
        navigation: SettingsNavigationModel,
        inbox: InboxModel,
        lifecycle: SystemLifecycleModel,
        hotkeys: HotkeyRegistry,
        detachedRegistry: DetachedWindowRegistry,
        openSettingsWindow: @escaping @MainActor () -> Void = {},
        presentReportProblem: @escaping @MainActor () -> Void = {},
        restartNotificationCenter: @escaping @MainActor () -> Void = {}
    ) -> [CourierCommand] {
        [
            settings(navigation, openWindow: openSettingsWindow),
            general(navigation, openWindow: openSettingsWindow),
            appearance(navigation, openWindow: openSettingsWindow),
            notifications(navigation, openWindow: openSettingsWindow),
            accounts(navigation, openWindow: openSettingsWindow),
            account(navigation, openWindow: openSettingsWindow),
            Self.hotkeys(navigation, openWindow: openSettingsWindow),
            quickReplies(navigation, openWindow: openSettingsWindow),
            bridges(navigation, openWindow: openSettingsWindow),
            about(navigation, openWindow: openSettingsWindow),
            help(navigation, openWindow: openSettingsWindow),
            lockApp(lifecycle),
            reportProblem(presentReportProblem: presentReportProblem),
            Self.restartNotificationCenter(restartNotificationCenter),
            openSpaceInNewWindow(inbox, registry: detachedRegistry),
            showKeyboardShortcuts(hotkeys),
        ]
    }

    @MainActor
    private static func paneCommand(
        id: String,
        title: String,
        keys: String?,
        pane: SettingsPaneID,
        navigation: SettingsNavigationModel,
        openWindow: @escaping @MainActor () -> Void
    ) -> CourierCommand {
        CourierCommand(
            id: id,
            title: title,
            keys: keys,
            category: .inbox,
            confirmation: nil,
            isEnabled: { AppLockGate.shared.canPerform(.settingsChange) },
            run: {
                guard AppLockGate.shared.canPerform(.settingsChange) else { return }
                navigation.openPane(pane)
                openWindow()
            }
        )
    }

    /// Something in the space shown is unread. The bar's count says so for the whole space; the chats loaded say so
    /// only when the bar doesn't know the space yet.
    @MainActor
    private static func hasUnread(_ inbox: InboxModel, _ spaces: SpacesModel) -> Bool {
        if let space = spaces.spaces.first(where: { $0.spaceID == inbox.query.space }) { return space.unreadChats > 0 }
        return inbox.rows.contains { $0.isUnread }
    }

    /// Replaces the one of `choices` that the query has with the next, and after the last with none. The query's
    /// other filters stay.
    @MainActor
    private static func step(_ inbox: InboxModel, through choices: [InboxFilter]) {
        var filters = inbox.query.filters
        let current = choices.firstIndex { filters.contains($0) }
        filters.subtract(choices)
        let next = current.map { $0 + 1 } ?? 0
        if next < choices.count { filters.insert(choices[next]) }
        inbox.query.filters = filters
    }

    /// The first account on the bar after the space shown, and after the last the first; nil with no account on the
    /// bar.
    @MainActor
    public static func nextAccount(_ inbox: InboxModel, _ spaces: SpacesModel) -> Space? {
        let bar = spaces.visible
        let accounts = bar.filter { $0.kind == .account }
        guard !accounts.isEmpty else { return nil }
        guard let here = bar.firstIndex(where: { $0.spaceID == inbox.query.space }) else { return accounts[0] }
        return bar[(here + 1)...].first { $0.kind == .account } ?? accounts[0]
    }
}
