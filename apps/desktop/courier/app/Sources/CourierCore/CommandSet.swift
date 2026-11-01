// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Something the person can ask for by name, from the command bar (⌘J, part 4.7).
public struct CourierCommand: Identifiable {
    public enum Category: String, CaseIterable, Equatable, Sendable {
        case recent
        case chat
        case inbox
        case search
        case message
        case accounts
        case chatInfo
        case navigation
        case appearance
        case settings
        case aiAndStubs

        public var title: String {
            switch self {
            case .recent: String(localized: "Recent")
            case .chat: String(localized: "Chat")
            case .inbox: String(localized: "Inbox")
            case .search: String(localized: "Search")
            case .message: String(localized: "Message")
            case .accounts: String(localized: "Accounts")
            case .chatInfo: String(localized: "Chat Info")
            case .navigation: String(localized: "Navigation")
            case .appearance: String(localized: "Appearance")
            case .settings: String(localized: "Settings")
            case .aiAndStubs: String(localized: "AI & Integrations")
            }
        }
    }

    /// The inventory ledger's name for it, in English, which never changes with the language.
    public let id: String
    /// What the person reads.
    public let title: String
    /// Optional secondary line shown under the title in the command bar.
    public let subtitle: String?
    /// The shortcut as the menu shows it, when it has one.
    public let keys: String?
    /// Alias for `keys` used by the command bar view.
    public var shortcut: String? { keys }
    /// The primary shortcut key character, when applicable.
    public let key: String?
    /// The modifier flags for `key`, when applicable.
    public let modifiers: KeyModifiers
    /// The command bar category this command belongs to.
    public let category: Category
    /// Search keywords that match this command in the command bar.
    public let keywords: [String]
    /// SF Symbol name displayed beside the command in the command bar.
    public let icon: String
    /// What to ask the person before running it, when it changes many chats at once; nil when it just runs. The
    /// command bar shows it with the command's title and runs the command only after a yes.
    public let confirmation: String?
    /// Nested sub-commands shown when drilling into this command in the command bar.
    public let children: [CourierCommand]
    /// Whether it can do anything now. The bar greys out what can't.
    public let isEnabled: @MainActor () -> Bool
    /// Convenience property reading `isEnabled()` on `@MainActor`.
    @MainActor public var enabled: Bool { isEnabled() }
    /// Does it. What takes the engine is started and not waited for.
    public let run: @MainActor () -> Void

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        keys: String? = nil,
        key: String? = nil,
        modifiers: KeyModifiers = [],
        category: Category = .message,
        keywords: [String] = [],
        icon: String = "command",
        confirmation: String? = nil,
        children: [CourierCommand] = [],
        isEnabled: @escaping @MainActor () -> Bool = { true },
        run: @escaping @MainActor () -> Void = {}
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keys = keys
        self.key = key
        self.modifiers = modifiers
        self.category = category
        self.keywords = keywords
        self.icon = icon
        self.confirmation = confirmation
        self.children = children
        self.isEnabled = isEnabled
        self.run = run
    }

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        category: Category,
        keywords: [String] = [],
        icon: String = "command",
        shortcut: String?,
        confirmation: String? = nil,
        children: [CourierCommand] = [],
        isEnabled: @escaping @MainActor () -> Bool = { true },
        run: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            id: id,
            title: title,
            subtitle: subtitle,
            keys: shortcut,
            category: category,
            keywords: keywords,
            icon: icon,
            confirmation: confirmation,
            children: children,
            isEnabled: isEnabled,
            run: run
        )
    }

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        category: Category,
        keywords: [String] = [],
        icon: String = "command",
        shortcut: String?,
        confirmation: String? = nil,
        children: [CourierCommand] = [],
        run: @escaping @MainActor () -> Void
    ) {
        self.init(
            id: id,
            title: title,
            subtitle: subtitle,
            keys: shortcut,
            category: category,
            keywords: keywords,
            icon: icon,
            confirmation: confirmation,
            children: children,
            isEnabled: { true },
            run: run
        )
    }
}

public typealias CommandCategory = CourierCommand.Category

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
                           category: .inbox, icon: "archivebox",
                           confirmation: String(localized: "Archive every chat in this space? Pinned chats stay where they are. You can undo this."),
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAll(readOnly: false) }
            },
            CourierCommand(id: "Archive all chats older than a week",
                           title: String(localized: "Archive all chats older than a week"), keys: nil,
                           category: .inbox, icon: "archivebox",
                           confirmation: String(localized: "Archive every chat in this space whose last message is over a week old? Pinned chats stay where they are. You can undo this."),
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAll(readOnly: false, olderThanDays: 7) }
            },
            CourierCommand(id: "Archive all read chats", title: String(localized: "Archive all read chats"),
                           keys: "⌘⇧E",
                           category: .inbox, icon: "archivebox",
                           confirmation: String(localized: "Archive every chat in this space that has nothing unread? Pinned chats stay where they are. You can undo this."),
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAllRead() }
            },
            CourierCommand(id: "Mark all chats as read", title: String(localized: "Mark all chats as read"),
                           keys: nil,
                           category: .inbox, icon: "envelope.open",
                           confirmation: String(localized: "Mark every unread chat in this space as read? Your networks are told too, so this can’t be undone."),
                           isEnabled: { hasUnread(inbox, spaces) }) {
                Task { await inbox.markAllRead() }
            },
            CourierCommand(id: "Next Chat", title: String(localized: "Next Chat"), keys: "⌘]",
                           category: .inbox, icon: "arrow.down", confirmation: nil,
                           isEnabled: { !inbox.rows.isEmpty }) {
                inbox.selectNext()
            },
            CourierCommand(id: "Show message requests", title: String(localized: "Show message requests"),
                           keys: nil, category: .inbox, icon: "tray.and.arrow.down", confirmation: nil, isEnabled: { true }) {
                spaces.select("requests")
            },
            CourierCommand(id: "Toggle space bar", title: String(localized: "Toggle space bar"), keys: "⌘S",
                           category: .inbox, icon: "sidebar.left", confirmation: nil,
                           isEnabled: { true }) {
                inbox.preferences.showSpaceBar.toggle()
            },
            CourierCommand(id: "Edit spaces", title: String(localized: "Edit spaces"), keys: nil,
                           category: .inbox, icon: "slider.horizontal.3", confirmation: nil,
                           isEnabled: { true }) {
                spaces.isEditing = true
            },
            CourierCommand(
                id: "Filter Chats",
                title: String(localized: "Filter Chats"),
                keys: nil,
                category: .inbox,
                keywords: ["filter", "unread", "drafts", "unanswered", "dms", "groups", "archived", "requests", "reminders"],
                icon: "line.3.horizontal.decrease.circle",
                confirmation: nil,
                children: filterSubCommands(inbox),
                isEnabled: { true }
            ) {
                inbox.cycleFilter()
            },
            CourierCommand(id: "Filter by folder type", title: String(localized: "Filter by folder type"),
                           keys: nil, category: .inbox, icon: "line.3.horizontal.decrease.circle", confirmation: nil, isEnabled: { true }) {
                step(inbox, through: SpacesModel.placeFilters)
            },
            CourierCommand(id: "Filter by type", title: String(localized: "Filter by type"), keys: nil,
                           category: .inbox, icon: "line.3.horizontal.decrease.circle", confirmation: nil,
                           isEnabled: { true }) {
                step(inbox, through: [.dms, .groups])
            },
            CourierCommand(id: "Filter by account", title: String(localized: "Filter by account"), keys: "⌘⌥A",
                           category: .inbox, icon: "line.3.horizontal.decrease.circle", confirmation: nil,
                           isEnabled: { nextAccount(inbox, spaces) != nil }) {
                if let next = nextAccount(inbox, spaces) { spaces.select(next.spaceID) }
            },
            CourierCommand(id: "Toggle chat selection mode", title: String(localized: "Toggle chat selection mode"),
                           keys: nil, category: .inbox, icon: "checkmark.circle", confirmation: nil, isEnabled: { inbox.isSelecting || !inbox.rows.isEmpty }) {
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
                           category: .search, icon: "magnifyingglass",
                           confirmation: nil, isEnabled: { true }) {
                search.show()
            },
            CourierCommand(id: "Search messages in all chats", title: String(localized: "Search messages in all chats"),
                           keys: "⌘K", category: .search, icon: "magnifyingglass", confirmation: nil, isEnabled: { true }) {
                search.show()
            },
            CourierCommand(id: "Search messages in current chat",
                           title: String(localized: "Search messages in current chat"), keys: "⌘F",
                           category: .search, icon: "text.magnifyingglass",
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
                           category: .accounts, icon: "eyeglasses",
                           confirmation: nil,
                           isEnabled: { !conversation.incognitoIsOn && conversation.isEntitled(.incognito) }) {
                conversation.setIncognito(true)
            },
            CourierCommand(id: "Turn off incognito mode", title: String(localized: "Turn off incognito mode"),
                           keys: nil, category: .accounts, icon: "eyeglasses", confirmation: nil, isEnabled: { conversation.incognitoIsOn }) {
                conversation.setIncognito(false)
            },
            CourierCommand(id: "Add Account", title: String(localized: "Add Account"), keys: nil,
                           category: .accounts, icon: "person.badge.plus", confirmation: nil,
                           isEnabled: { true }) {
                login.showPicker()
            },
            CourierCommand(id: "accounts.manage", title: String(localized: "Accounts"), keys: nil,
                           category: .accounts, icon: "person.2", confirmation: nil,
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
                category: .chatInfo,
                icon: "sidebar.right",
                confirmation: nil,
                isEnabled: hasOpenChat,
                run: toggleChatInfo
            ),
            CourierCommand(
                id: "conversation.searchChatInfo",
                title: String(localized: "Search in chat info"),
                keys: nil,
                category: .chatInfo,
                icon: "magnifyingglass",
                confirmation: nil,
                isEnabled: hasOpenChat,
                run: searchChatInfo
            ),
            CourierCommand(
                id: "conversation.toggleCalendar",
                title: String(localized: "Jump to date in chat"),
                keys: "⌘⌥K",
                category: .chatInfo,
                icon: "calendar",
                confirmation: nil,
                isEnabled: hasOpenChat,
                run: toggleCalendar
            ),
            CourierCommand(
                id: "conversation.showSenderCard",
                title: String(localized: "Show sender profile"),
                keys: "⌘⇧O",
                category: .chatInfo,
                icon: "person.crop.rectangle",
                confirmation: nil,
                isEnabled: hasSelectedMessage,
                run: showSenderCard
            ),
            CourierCommand(
                id: "inbox.newGroupOrBlast",
                title: String(localized: "New group or blast chat"),
                keys: "⌘⇧N",
                category: .chatInfo,
                icon: "person.3",
                confirmation: nil,
                isEnabled: { true },
                run: newGroupOrBlast
            ),
            mediaViewer(openMediaViewer: openMediaViewer),
        ]
    }

    @MainActor
    public static func chatInfo(
        conversation: ConversationModel,
        inbox: InboxModel,
        openMediaViewer: @escaping @MainActor () -> Void = {}
    ) -> [CourierCommand] {
        chatInfo(
            hasOpenChat: { conversation.roomID != nil },
            hasSelectedMessage: { conversation.selectedMessage != nil || conversation.roomID != nil },
            toggleChatInfo: { conversation.toggleChatInfo() },
            searchChatInfo: { conversation.focusChatInfoSearch() },
            toggleCalendar: { conversation.toggleCalendar() },
            showSenderCard: { Task { await conversation.showSenderCardForSelectedMessage() } },
            newGroupOrBlast: { inbox.openStartNewChat(multiSelect: true) },
            openMediaViewer: openMediaViewer
        )
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
            category: .chatInfo,
            icon: "photo.on.rectangle",
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
            category: .message,
            icon: "mic",
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
            icon: "sparkles.rectangle.stack",
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
            icon: "face.smiling",
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
            category: .settings,
            icon: "macwindow.badge.plus",
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
            category: .settings,
            icon: "keyboard",
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
            category: .settings,
            icon: "keyboard",
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
        paneCommand(id: "settings.accounts", title: String(localized: "Accounts"), keys: nil, pane: .accounts, navigation: navigation, openWindow: openWindow)
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
            category: .settings,
            icon: "person.crop.circle",
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
            category: .settings,
            icon: "lock",
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
            category: .settings,
            icon: "ladybug",
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
            category: .settings,
            icon: "bell.badge",
            confirmation: nil,
            isEnabled: { AppLockGate.shared.canPerform(.settingsChange) },
            run: {
                guard AppLockGate.shared.canPerform(.settingsChange) else { return }
                restart()
            }
        )
    }

    // MARK: - Media Deletion Copy & Command

    /// User-facing action title for deleting local media on this Mac.
    public static let deleteMediaTitle = String(localized: "Delete Media…")

    /// The Storage pane's button for deleting every photo, video and file on this Mac (imported stickers stay).
    public static let deleteAllMediaTitle = String(localized: "Delete All Media…")

    /// User-facing action title for age-scoped media deletion.
    public static func deleteMediaOlderThanTitle(_ age: String) -> String {
        String(localized: "Delete media older than \(age)")
    }

    /// User-facing action title for room-scoped media deletion.
    public static let deleteMediaInThisChatTitle = String(localized: "Delete media in this chat")

    /// User-facing confirmation copy explaining that deleting media removes local files permanently while keeping messages.
    public static let deleteMediaConfirmation = String(
        localized: "This deletes photos, videos and files from this Mac. Messages stay, but the media can't be brought back."
    )

    /// Command bar entry for deleting media from this Mac (`storage.cleanup`).
    @MainActor
    public static func deleteMedia(
        performDelete: @escaping @MainActor () -> Void = {}
    ) -> CourierCommand {
        CourierCommand(
            id: "Delete Media…",
            title: deleteMediaTitle,
            keys: nil,
            category: .settings,
            icon: "trash",
            confirmation: deleteMediaConfirmation,
            isEnabled: { AppLockGate.shared.canPerform(.settingsChange) },
            run: {
                guard AppLockGate.shared.canPerform(.settingsChange) else { return }
                performDelete()
            }
        )
    }

    /// All Milestone 4.6 Settings, Help, and System commands for the command bar.
    @MainActor
    public static func settingsAndSystem(
        navigation: SettingsNavigationModel? = nil,
        inbox: InboxModel,
        lifecycle: SystemLifecycleModel? = nil,
        hotkeys: HotkeyRegistry? = nil,
        detachedRegistry: DetachedWindowRegistry? = nil,
        openSettingsWindow: @escaping @MainActor () -> Void = {},
        presentReportProblem: @escaping @MainActor () -> Void = {},
        restartNotificationCenter: @escaping @MainActor () -> Void = {},
        performDeleteMedia: @escaping @MainActor () -> Void = {}
    ) -> [CourierCommand] {
        let resolvedNavigation = navigation ?? SettingsNavigationModel()
        let resolvedHotkeys = hotkeys ?? HotkeyRegistry()
        let resolvedLifecycle = lifecycle ?? inbox.lifecycle
        let openSpaceCmd: CourierCommand
        if let detachedRegistry {
            openSpaceCmd = openSpaceInNewWindow(inbox, registry: detachedRegistry)
        } else {
            openSpaceCmd = CourierCommand(
                id: "Open space in new window",
                title: String(localized: "Open space in new window"),
                keys: nil,
                category: .settings,
                icon: "macwindow.badge.plus",
                confirmation: nil,
                isEnabled: { !inbox.lifecycle.isLocked && AppLockGate.shared.canPerform(.openChat) },
                run: {}
            )
        }
        return [
            settings(resolvedNavigation, openWindow: openSettingsWindow),
            general(resolvedNavigation, openWindow: openSettingsWindow),
            appearance(resolvedNavigation, openWindow: openSettingsWindow),
            notifications(resolvedNavigation, openWindow: openSettingsWindow),
            accounts(resolvedNavigation, openWindow: openSettingsWindow),
            account(resolvedNavigation, openWindow: openSettingsWindow),
            Self.hotkeys(resolvedNavigation, openWindow: openSettingsWindow),
            quickReplies(resolvedNavigation, openWindow: openSettingsWindow),
            bridges(resolvedNavigation, openWindow: openSettingsWindow),
            about(resolvedNavigation, openWindow: openSettingsWindow),
            help(resolvedNavigation, openWindow: openSettingsWindow),
            lockApp(resolvedLifecycle),
            reportProblem(presentReportProblem: presentReportProblem),
            Self.restartNotificationCenter(restartNotificationCenter),
            openSpaceCmd,
            showKeyboardShortcuts(resolvedHotkeys),
            deleteMedia(performDelete: performDeleteMedia),
        ]
    }

    // MARK: - Unified ⌘J Command Bar Catalog (Milestone 4.7)

    /// Aggregates every existing `CommandSet` group (`inbox`, `search`, `message`, `accounts`, `chatInfo`,
    /// `recordAudio`, `composerMedia`, `settingsAndSystem`) plus the remaining 4.1–4.7 chat, navigation,
    /// appearance, storage, AI, and stub commands into one unified catalog for the `⌘J` Command Bar.
    @MainActor
    public static func all(
        inbox: InboxModel? = nil,
        spaces: SpacesModel? = nil,
        search: SearchModel? = nil,
        actions: MessageActionsModel? = nil,
        conversation: ConversationModel? = nil,
        composer: ComposerModel? = nil,
        login: LoginFlowModel? = nil,
        appearance: AppearancePreferences? = nil,
        navigation: SettingsNavigationModel? = nil,
        lifecycle: SystemLifecycleModel? = nil,
        hotkeys: HotkeyRegistry? = nil,
        detachedRegistry: DetachedWindowRegistry? = nil,
        openSettingsWindow: @escaping @MainActor () -> Void = {},
        presentReportProblem: @escaping @MainActor () -> Void = {},
        restartNotificationCenter: @escaping @MainActor () -> Void = {},
        performDeleteMedia: @escaping @MainActor () -> Void = {},
        openMediaViewer: @escaping @MainActor () -> Void = {},
        openRecentlyViewedChats: @escaping @MainActor () -> Void = {},
        toggleSidebar: @escaping @MainActor () -> Void = {},
        focusApp: @escaping @MainActor () -> Void = {},
        openCustomThemePicker: @escaping @MainActor () -> Void = {},
        openAISettings: @escaping @MainActor (String) -> Void = { _ in },
        attachFile: @escaping @MainActor () -> Void = {},
        downloadAttachments: @escaping @MainActor () -> Void = {}
    ) -> [CourierCommand] {
        let resolvedNavigation = navigation ?? SettingsNavigationModel()
        let resolvedHotkeys = hotkeys ?? HotkeyRegistry()
        var result: [CourierCommand] = []
        var seenIDs = Set<String>()
        func appendAll(_ commands: [CourierCommand]) {
            for cmd in commands where seenIDs.insert(cmd.id).inserted {
                result.append(cmd)
            }
        }

        // 1. Recent
        appendAll([
            CourierCommand(
                id: "recent.openRecentlyViewedChats",
                title: String(localized: "Open recently viewed chats"),
                subtitle: String(localized: "Jump to a chat you viewed recently"),
                category: .recent,
                keywords: ["recent", "history", "viewed", "chats", "switch"],
                icon: "clock.arrow.circlepath",
                shortcut: nil,
                run: openRecentlyViewedChats
            ),
        ])

        // 2. Existing CommandSet.inbox group (13 ledger commands, including Filter Chats with nested children) + inbox-level actions
        if let inbox, let spaces {
            appendAll(Self.inbox(inbox, spaces))
        }
        appendAll([
            CourierCommand(
                id: "inbox.createNewChat",
                title: String(localized: "Create new chat"),
                category: .inbox,
                keywords: ["new chat", "compose", "start", "direct message"],
                icon: "square.and.pencil",
                shortcut: "⌘N"
            ) {
                inbox?.openStartNewChat(multiSelect: false)
            },
            CourierCommand(
                id: "inbox.mergeChats",
                title: String(localized: "Merge chats"),
                category: .inbox,
                keywords: ["merge", "combine", "unify", "person"],
                icon: "arrow.triangle.merge",
                shortcut: nil,
                isEnabled: { (inbox?.selectedRow ?? inbox?.rows.first) != nil }
            ) {
                guard let inbox, let target = inbox.selectedRow ?? inbox.rows.first else { return }
                inbox.openMergeEditor(for: target)
            },
        ])

        // 3. Direct chat actions
        let hasTargets: @MainActor () -> Bool = { !(inbox?.targets.isEmpty ?? true) }
        let hasOpenRoom: @MainActor () -> Bool = { (conversation?.roomID ?? inbox?.selectedRoomID) != nil }
        appendAll([
            CourierCommand(
                id: "chat.archive",
                title: (inbox?.selectedRow?.archived == true) ? String(localized: "Unarchive") : String(localized: "Archive"),
                category: .chat,
                keywords: ["archive", "unarchive", "done"],
                icon: "archivebox",
                shortcut: "E",
                isEnabled: hasTargets
            ) {
                guard let inbox else { return }
                let shouldArchive = !(inbox.selectedRow?.archived ?? false)
                Task { await inbox.archive(shouldArchive) }
            },
            CourierCommand(
                id: "chat.pin",
                title: (inbox?.selectedRow?.pinned == true) ? String(localized: "Unpin") : String(localized: "Pin"),
                category: .chat,
                keywords: ["pin", "unpin", "favorite", "top"],
                icon: "pin",
                shortcut: "P",
                isEnabled: hasTargets
            ) {
                guard let inbox else { return }
                Task { await inbox.togglePin() }
            },
            CourierCommand(
                id: "chat.mute",
                title: (inbox?.selectedRow?.muted == true) ? String(localized: "Unmute") : String(localized: "Mute"),
                category: .chat,
                keywords: ["mute", "unmute", "notifications", "silence"],
                icon: "bell.slash",
                shortcut: "M",
                isEnabled: hasTargets
            ) {
                guard let inbox else { return }
                Task { await inbox.toggleMute() }
            },
            CourierCommand(
                id: "chat.toggleRead",
                title: (inbox?.toggleReadMarksRead == true) ? String(localized: "Mark as Read") : String(localized: "Mark as Unread"),
                category: .chat,
                keywords: ["read", "unread", "mark"],
                icon: "envelope.badge",
                shortcut: "⌘⇧U",
                isEnabled: hasTargets
            ) {
                guard let inbox else { return }
                Task { await inbox.toggleRead() }
            },
            CourierCommand(
                id: "chat.lowPriority",
                title: String(localized: "Move to Low Priority"),
                category: .chat,
                keywords: ["low priority", "quiet"],
                icon: "arrow.down.circle",
                shortcut: nil,
                isEnabled: hasTargets
            ) {
                guard let inbox else { return }
                let makeLow = !(inbox.selectedRow?.lowPriority ?? false)
                Task { await inbox.setLowPriority(makeLow) }
            },
            CourierCommand(
                id: "chat.hide",
                title: (inbox?.selectedRow?.hidden == true) ? String(localized: "Unhide Chat") : String(localized: "Hide Chat"),
                category: .chat,
                keywords: ["hide", "unhide", "hidden"],
                icon: "eye.slash",
                shortcut: nil,
                isEnabled: hasTargets
            ) {
                guard let inbox else { return }
                let makeHidden = !(inbox.selectedRow?.hidden ?? false)
                Task { await inbox.setHidden(makeHidden) }
            },
            CourierCommand(
                id: "chat.remindLater",
                title: String(localized: "Remind Later"),
                category: .chat,
                keywords: ["remind", "snooze", "later", "tomorrow"],
                icon: "alarm",
                shortcut: "⌘L",
                children: remindLaterSubCommands(inbox),
                isEnabled: hasTargets
            ) {
                inbox?.isRemindPopoverPresented = true
            },
            CourierCommand(
                id: "chat.label",
                title: String(localized: "Label…"),
                category: .chat,
                keywords: ["label", "tag", "organize"],
                icon: "tag",
                shortcut: "⌘⇧L",
                children: labelSubCommands(inbox: inbox, spaces: spaces, navigation: resolvedNavigation, openSettingsWindow: openSettingsWindow),
                isEnabled: { true }
            ) {},
            CourierCommand(
                id: "chat.disappearingMessages",
                title: String(localized: "Disappearing Messages…"),
                category: .chat,
                keywords: ["disappearing", "timer", "ephemeral", "expiry"],
                icon: "timer",
                shortcut: nil,
                children: disappearingSubCommands(conversation),
                isEnabled: hasOpenRoom
            ) {},
            CourierCommand(
                id: "chat.leaveGroup",
                title: String(localized: "Leave Group"),
                category: .chat,
                keywords: ["leave", "exit", "group"],
                icon: "rectangle.portrait.and.arrow.right",
                shortcut: nil,
                confirmation: ConversationModel.leaveGroupConfirmation(
                    groupName: inbox?.selectedRow?.name ?? conversation?.chatInfo?.name ?? ""
                ).detail,
                isEnabled: hasOpenRoom
            ) {
                guard let conversation else { return }
                Task { _ = await conversation.leaveGroup() }
            },
            CourierCommand(
                id: "chat.deleteChat",
                title: String(localized: "Delete Chat"),
                category: .chat,
                keywords: ["delete", "remove", "chat"],
                icon: "trash",
                shortcut: nil,
                confirmation: ConversationModel.deleteChatConfirmation(
                    chatName: inbox?.selectedRow?.name ?? conversation?.chatInfo?.name ?? "",
                    isDirect: inbox?.selectedRow?.isDirect ?? conversation?.isDirectChat ?? true,
                    features: conversation?.features ?? .noFeatures
                ).detail,
                isEnabled: hasOpenRoom
            ) {
                guard let conversation else { return }
                Task { _ = await conversation.deleteChat() }
            },
            CourierCommand(
                id: "chat.rename",
                title: String(localized: "Rename Chat / Edit Group…"),
                category: .chat,
                keywords: ["rename", "edit", "group", "name", "avatar", "override"],
                icon: "pencil",
                shortcut: nil,
                isEnabled: hasOpenRoom
            ) {
                guard let conversation else { return }
                Task { await conversation.beginEditChat() }
            },
            CourierCommand(
                id: "chat.clearOverride",
                title: String(localized: "Clear Chat Override"),
                category: .chat,
                keywords: ["reset", "override", "local name", "local avatar"],
                icon: "arrow.counterclockwise",
                shortcut: nil,
                isEnabled: hasOpenRoom
            ) {
                guard let conversation else { return }
                Task { _ = await conversation.resetLocalOverride() }
            },
        ])

        // 4. Existing CommandSet.search group (3 ledger commands)
        if let search {
            appendAll(Self.search(search, openRoomID: { inbox?.selectedRoomID ?? conversation?.roomID }))
        }

        // 5. Existing CommandSet.message group (9 commands) + composer media + record audio + extra message actions
        if let actions, let conversation {
            appendAll(Self.message(actions, conversation))
        }
        let activeComposer = composer ?? conversation?.composer
        if let activeComposer {
            appendAll([Self.recordAudio(activeComposer)])
            appendAll(Self.composerMedia(activeComposer))
        }
        appendAll([
            CourierCommand(
                id: "message.reply",
                title: String(localized: "Reply"),
                category: .message,
                keywords: ["reply", "quote"],
                icon: "arrowshape.turn.up.left",
                shortcut: "⌘R",
                isEnabled: { conversation?.selectedMessage != nil }
            ) {
                conversation?.replyToSelected()
            },
            CourierCommand(
                id: "message.react",
                title: String(localized: "React…"),
                category: .message,
                keywords: ["react", "emoji", "reaction"],
                icon: "face.smiling",
                shortcut: "⌘E",
                isEnabled: { conversation?.selectedMessage != nil }
            ) {
                guard let actions, let selected = conversation?.selectedMessage else { return }
                Task { await actions.perform(.react, on: selected.id) }
            },
            CourierCommand(
                id: "message.copy",
                title: String(localized: "Copy Message"),
                category: .message,
                keywords: ["copy", "clipboard"],
                icon: "doc.on.doc",
                shortcut: "⌘C",
                isEnabled: { conversation?.selectedMessage != nil }
            ) {
                guard let actions, let selected = conversation?.selectedMessage else { return }
                Task { await actions.perform(.copy, on: selected.id) }
            },
            CourierCommand(
                id: "message.bookmark",
                title: String(localized: "Bookmark Message"),
                category: .message,
                keywords: ["bookmark", "pin message", "save"],
                icon: "bookmark",
                shortcut: "⌘B",
                isEnabled: { conversation?.selectedMessage != nil }
            ) {
                guard let actions, let selected = conversation?.selectedMessage else { return }
                let action: MessageAction = selected.bookmarked ? .removeBookmark : .bookmark
                Task { await actions.perform(action, on: selected.id) }
            },
            CourierCommand(
                id: "message.openFirstLink",
                title: String(localized: "Open First Link in Message"),
                category: .message,
                keywords: ["link", "url", "open"],
                icon: "link",
                shortcut: "⌘⇧H",
                isEnabled: { conversation?.firstLinkOfSelected() != nil }
            ) {
                guard let actions, let url = conversation?.firstLinkOfSelected() else { return }
                actions.openURL(url)
            },
            CourierCommand(
                id: "message.attachFile",
                title: String(localized: "Attach file"),
                category: .message,
                keywords: ["attach", "file", "upload", "photo", "document"],
                icon: "paperclip",
                shortcut: "⌘⇧A",
                isEnabled: hasOpenRoom,
                run: attachFile
            ),
            CourierCommand(
                id: "message.downloadAttachments",
                title: String(localized: "Download attachments"),
                category: .message,
                keywords: ["download", "save", "attachments", "media"],
                icon: "arrow.down.to.line",
                shortcut: "⌘D",
                isEnabled: hasOpenRoom,
                run: downloadAttachments
            ),
            CourierCommand(
                id: "message.createPoll",
                title: String(localized: "Create Poll…"),
                category: .message,
                keywords: ["poll", "vote", "survey"],
                icon: "chart.bar.xaxis",
                shortcut: nil,
                isEnabled: { conversation?.features.poll != nil }
            ) {
                conversation?.isCreatingPoll = true
            },
        ])

        // 6. Existing CommandSet.accounts group (4 ledger commands)
        if let login, let conversation {
            appendAll(Self.accounts(login, conversation))
        }

        // 7. Existing CommandSet.chatInfo group (6 commands)
        if let conversation, let inbox {
            appendAll(Self.chatInfo(conversation: conversation, inbox: inbox, openMediaViewer: openMediaViewer))
        } else {
            appendAll(Self.chatInfo(openMediaViewer: openMediaViewer))
        }

        // 8. Navigation commands
        appendAll([
            CourierCommand(
                id: "nav.goToSpace",
                title: String(localized: "Go to Space…"),
                category: .navigation,
                keywords: ["space", "inbox", "switch space", "label", "account"],
                icon: "square.grid.2x2",
                shortcut: nil,
                children: goToSpaceSubCommands(spaces: spaces, inbox: inbox)
            ) {},
            CourierCommand(
                id: "nav.previousChat",
                title: String(localized: "Previous Chat"),
                category: .navigation,
                keywords: ["previous", "chat", "up"],
                icon: "arrow.up",
                shortcut: "⌘[",
                isEnabled: { !(inbox?.rows.isEmpty ?? true) }
            ) {
                inbox?.selectPrevious()
            },
            CourierCommand(
                id: "nav.nextUnreadChat",
                title: String(localized: "Next Unread Chat"),
                category: .navigation,
                keywords: ["next", "unread", "chat"],
                icon: "envelope.badge",
                shortcut: "⌥⌘↓",
                isEnabled: { !(inbox?.rows.isEmpty ?? true) }
            ) {
                inbox?.selectNextUnread()
            },
            CourierCommand(
                id: "nav.jumpToBottom",
                title: String(localized: "Jump to Latest Message"),
                category: .navigation,
                keywords: ["bottom", "latest", "newest", "scroll"],
                icon: "arrow.down.to.line",
                shortcut: "⌘↓",
                isEnabled: hasOpenRoom
            ) {
                conversation?.jumpToBottom()
            },
            CourierCommand(
                id: "nav.toggleSidebar",
                title: String(localized: "Toggle sidebar"),
                category: .navigation,
                keywords: ["sidebar", "space bar", "hide", "show"],
                icon: "sidebar.left",
                shortcut: "⌘S"
            ) {
                inbox?.preferences.showSpaceBar.toggle()
                toggleSidebar()
            },
            CourierCommand(
                id: "nav.focusCourier",
                title: String(localized: "Focus Courier"),
                category: .navigation,
                keywords: ["focus", "bring to front", "activate", "window"],
                icon: "macwindow",
                // The Focus App hotkey has no default: show its keys only once one is set.
                shortcut: resolvedHotkeys.primaryChord(for: "Focus App")?.symbols,
                run: focusApp
            ),
        ])

        // 9. Appearance commands (4.7)
        appendAll([
            CourierCommand(
                id: "appearance.setTheme",
                title: String(localized: "Set Theme…"),
                category: .appearance,
                keywords: ["theme", "dark", "light", "system", "palette", "color"],
                icon: "paintbrush",
                shortcut: nil,
                children: setThemeSubCommands(appearance)
            ) {},
            CourierCommand(
                id: "appearance.loadCustomTheme",
                title: String(localized: "Load Custom Theme"),
                subtitle: String(localized: "Select a custom theme file"),
                category: .appearance,
                keywords: ["custom theme", "css", "load theme"],
                icon: "doc.badge.gearshape",
                shortcut: nil
            ) {
                _ = appearance?.attemptLoadCustomThemeFile(at: URL(fileURLWithPath: "/nonexistent/custom-theme.css"))
                if let notice = appearance?.lastThemeFileNotice {
                    inbox?.announce(notice)
                }
                openCustomThemePicker()
            },
            CourierCommand(
                id: "appearance.reloadCustomTheme",
                title: String(localized: "Reload Custom Theme"),
                category: .appearance,
                keywords: ["reload theme", "refresh theme", "css"],
                icon: "arrow.clockwise",
                shortcut: nil
            ) {
                _ = appearance?.reloadCustomThemeFile()
                if let notice = appearance?.lastThemeFileNotice {
                    inbox?.announce(notice)
                }
            },
            CourierCommand(
                id: "appearance.zoomIn",
                title: String(localized: "Zoom In"),
                category: .appearance,
                keywords: ["zoom", "bigger", "scale", "ui"],
                icon: "plus.magnifyingglass",
                shortcut: "⌘="
            ) {
                appearance?.zoomIn()
            },
            CourierCommand(
                id: "appearance.zoomOut",
                title: String(localized: "Zoom Out"),
                category: .appearance,
                keywords: ["zoom", "smaller", "scale", "ui"],
                icon: "minus.magnifyingglass",
                shortcut: "⌘-"
            ) {
                appearance?.zoomOut()
            },
            CourierCommand(
                id: "appearance.resetZoom",
                title: String(localized: "Reset Zoom"),
                category: .appearance,
                keywords: ["zoom", "actual size", "100%", "reset"],
                icon: "1.magnifyingglass",
                shortcut: "⌘0"
            ) {
                appearance?.resetZoom()
            },
            CourierCommand(
                id: "appearance.increaseFontSize",
                title: String(localized: "Increase Font Size"),
                category: .appearance,
                keywords: ["font", "text size", "bigger"],
                icon: "textformat.size.larger",
                shortcut: "⌘⇧="
            ) {
                appearance?.increaseFontSize()
            },
            CourierCommand(
                id: "appearance.decreaseFontSize",
                title: String(localized: "Decrease Font Size"),
                category: .appearance,
                keywords: ["font", "text size", "smaller"],
                icon: "textformat.size.smaller",
                shortcut: "⌘⇧-"
            ) {
                appearance?.decreaseFontSize()
            },
            CourierCommand(
                id: "appearance.resetFontSize",
                title: String(localized: "Reset Font Size"),
                category: .appearance,
                keywords: ["font", "text size", "default"],
                icon: "textformat.size",
                shortcut: "⌘⌥0"
            ) {
                appearance?.resetFontSize()
            },
            CourierCommand(
                id: "appearance.toggleRedaction",
                title: String(localized: "Toggle Redact Names & Pictures"),
                category: .appearance,
                keywords: ["redact", "privacy", "screenshot", "blur", "anonymize"],
                icon: "eye.slash.circle",
                shortcut: nil
            ) {
                appearance?.redactNamesAndPictures.toggle()
            },
            CourierCommand(
                id: "appearance.toggleCompactList",
                title: String(localized: "Toggle Compact Chat List"),
                category: .appearance,
                keywords: ["compact", "dense", "inbox rows"],
                icon: "list.Resize",
                shortcut: nil
            ) {
                inbox?.preferences.compactList.toggle()
            },
            CourierCommand(
                id: "appearance.fireConfetti",
                title: String(localized: "Fire Confetti 🎉"),
                category: .appearance,
                keywords: ["confetti", "celebrate", "party"],
                icon: "sparkles",
                shortcut: nil
            ) {
                appearance?.fireConfetti()
            },
        ])

        // 10. Existing CommandSet.settingsAndSystem group (17 commands, including Delete Media… with deleteMediaConfirmation)
        if let inbox {
            appendAll(
                Self.settingsAndSystem(
                    navigation: resolvedNavigation,
                    inbox: inbox,
                    lifecycle: lifecycle,
                    hotkeys: resolvedHotkeys,
                    detachedRegistry: detachedRegistry,
                    openSettingsWindow: openSettingsWindow,
                    presentReportProblem: presentReportProblem,
                    restartNotificationCenter: restartNotificationCenter,
                    performDeleteMedia: performDeleteMedia
                )
            )
        } else {
            appendAll([deleteMedia(performDelete: performDeleteMedia)])
        }

        appendAll([
            CourierCommand(
                id: "settings.inbox",
                title: String(localized: "Settings: Inbox"),
                category: .settings,
                keywords: ["settings", "inbox", "labels", "spaces"],
                icon: "tray",
                shortcut: nil
            ) {
                resolvedNavigation.openPane(.general)
                openSettingsWindow()
            },
            CourierCommand(
                id: "settings.messages",
                title: String(localized: "Settings: Messages"),
                category: .settings,
                keywords: ["settings", "messages", "composer"],
                icon: "bubble.left.and.bubble.right",
                shortcut: nil
            ) {
                resolvedNavigation.openPane(.general)
                openSettingsWindow()
            },
            CourierCommand(
                id: "settings.ai",
                title: String(localized: "Settings: AI"),
                category: .settings,
                keywords: ["settings", "ai", "assistant", "transcription"],
                icon: "sparkles",
                shortcut: nil
            ) {
                resolvedNavigation.openPane(.general)
                openSettingsWindow()
                openAISettings("settings")
            },
            CourierCommand(
                id: "Storage",
                title: String(localized: "Storage"),
                category: .settings,
                keywords: ["storage", "disk", "media", "cleanup", "cache"],
                icon: "internaldrive",
                shortcut: nil
            ) {
                resolvedNavigation.openPane(.storage)
                openSettingsWindow()
            },
        ])

        // 11. AI & Intentional Stubs (4.7)
        appendAll([
            CourierCommand(
                id: "ai.summarizeThread",
                title: String(localized: "AI: Summarize Thread"),
                subtitle: String(localized: "Not available in this build"),
                category: .aiAndStubs,
                keywords: ["ai", "summarize", "summary", "thread"],
                icon: "sparkles",
                shortcut: nil
            ) {
                inbox?.announce(String(localized: "AI thread summaries aren’t available in this build."))
                openAISettings("summarize")
            },
            CourierCommand(
                id: "ai.draftReply",
                title: String(localized: "AI: Draft Reply"),
                subtitle: String(localized: "Not available in this build"),
                category: .aiAndStubs,
                keywords: ["ai", "draft", "reply", "compose"],
                icon: "wand.and.stars",
                shortcut: nil
            ) {
                inbox?.announce(String(localized: "AI draft replies aren’t available in this build."))
                openAISettings("draft")
            },
            CourierCommand(
                id: "ai.translateMessage",
                title: String(localized: "AI: Translate Message"),
                subtitle: String(localized: "Not available in this build"),
                category: .aiAndStubs,
                keywords: ["ai", "translate", "language"],
                icon: "character.bubble",
                shortcut: nil
            ) {
                inbox?.announce(String(localized: "AI translation isn’t available in this build."))
                openAISettings("translate")
            },
            CourierCommand(
                id: "ai.talkToType",
                title: String(localized: "Message: Talk to Type"),
                subtitle: String(localized: "Dictation / voice transcription"),
                category: .aiAndStubs,
                keywords: ["talk to type", "dictation", "transcribe", "voice"],
                icon: "Waveform.and.mic",
                shortcut: "⌘⇧D"
            ) {
                inbox?.announce(String(localized: "Talk to Type isn’t available in this build."))
                openAISettings("talkToType")
            },
            CourierCommand(
                id: "plan.manage",
                title: String(localized: "Manage Subscription / Plan"),
                subtitle: String(localized: "Open account plan status"),
                category: .aiAndStubs,
                keywords: ["plan", "subscription", "billing", "plus", "entitlement"],
                icon: "creditcard",
                shortcut: nil
            ) {
                resolvedNavigation.openPane(.accounts)
                openSettingsWindow()
            },
            CourierCommand(
                id: "stub.importFromMatrix",
                title: String(localized: "Import from Matrix"),
                subtitle: String(localized: "Sign in to each network in Settings ▸ Accounts"),
                category: .aiAndStubs,
                keywords: ["import", "beeper", "matrix", "migration"],
                icon: "square.and.arrow.down",
                shortcut: nil
            ) {
                resolvedNavigation.openPane(.accounts)
                openSettingsWindow()
            },
        ])

        return result
    }

    @MainActor
    private static func filterSubCommands(_ inbox: InboxModel) -> [CourierCommand] {
        let items: [(id: String, title: String, filter: InboxFilter?, shortcut: String?)] = [
            ("inbox.filter.all", String(localized: "All Chats"), nil, nil),
            ("inbox.filter.unread", String(localized: "Unread"), .unread, "⌘⇧Y"),
            ("inbox.filter.drafts", String(localized: "Drafts"), .drafts, nil),
            ("inbox.filter.unanswered", String(localized: "Unanswered"), .unanswered, nil),
            ("inbox.filter.dms", String(localized: "Direct Messages (DMs)"), .dms, nil),
            ("inbox.filter.groups", String(localized: "Groups"), .groups, nil),
            ("inbox.filter.archived", String(localized: "Archived"), .archived, nil),
            ("inbox.filter.lowPriority", String(localized: "Low Priority"), .lowPriority, nil),
            ("inbox.filter.hidden", String(localized: "Hidden"), .hidden, nil),
            ("inbox.filter.requests", String(localized: "Message Requests"), .requests, nil),
            ("inbox.filter.reminders", String(localized: "Reminders"), .reminders, nil),
            ("inbox.filter.sendLater", String(localized: "Send Later"), .sendLater, nil),
        ]
        return items.map { item in
            CourierCommand(
                id: item.id,
                title: item.title,
                category: .inbox,
                icon: "line.3.horizontal.decrease.circle",
                shortcut: item.shortcut
            ) {
                if let filter = item.filter {
                    inbox.query.filters = [filter]
                } else {
                    inbox.query.filters = []
                }
            }
        }
    }

    @MainActor
    private static func remindLaterSubCommands(_ inbox: InboxModel?) -> [CourierCommand] {
        let suggestions = inbox?.preferences.timeSuggestions ?? ReminderPresets.defaultSuggestions
        let presets = suggestions.map { suggestion in
            CourierCommand(
                id: "chat.remind.\(suggestion.lowercased().replacingOccurrences(of: " ", with: "_"))",
                title: suggestion,
                category: .chat,
                icon: "alarm",
                shortcut: nil
            ) {
                guard let inbox else { return }
                let now = Date()
                let due = ReminderPresets.resolveDate(for: suggestion, now: now, calendar: .current)
                    ?? now.addingTimeInterval(3600)
                Task { await inbox.remind(at: due, condition: inbox.preferences.remindDefault) }
            }
        }
        let custom = CourierCommand(
            id: "chat.remind.custom",
            title: String(localized: "Custom…"),
            category: .chat,
            icon: "calendar.badge.clock",
            shortcut: nil
        ) {
            guard let inbox, !inbox.targets.isEmpty else { return }
            inbox.customReminder = ReminderRequest(ids: inbox.targets)
        }
        let clear = CourierCommand(
            id: "chat.remind.clear",
            title: String(localized: "Clear Reminder"),
            category: .chat,
            icon: "alarm.waves.left.and.right",
            shortcut: nil
        ) {
            guard let inbox else { return }
            Task { await inbox.dismissReminder() }
        }
        return presets + [custom, clear]
    }

    @MainActor
    private static func labelSubCommands(
        inbox: InboxModel?,
        spaces: SpacesModel?,
        navigation: SettingsNavigationModel,
        openSettingsWindow: @escaping @MainActor () -> Void
    ) -> [CourierCommand] {
        let labelSpaces = (spaces?.spaces ?? []).filter { $0.kind == .label }
        var children: [CourierCommand] = labelSpaces.compactMap { space in
            guard let idStr = space.spaceID.split(separator: ":").last,
                  let labelID = Int64(idStr) else { return nil }
            return CourierCommand(
                id: "chat.label.\(labelID)",
                title: space.title,
                category: .chat,
                icon: space.icon.isEmpty ? "tag" : space.icon,
                shortcut: nil
            ) {
                guard let inbox else { return }
                let hasLabel = inbox.selectedRow?.labels.contains(labelID) ?? false
                Task { await inbox.setLabel(labelID, on: !hasLabel) }
            }
        }
        children.append(
            CourierCommand(
                id: "chat.label.manage",
                title: String(localized: "Manage Labels…"),
                category: .chat,
                icon: "tag.circle",
                shortcut: nil
            ) {
                navigation.openPane(.general)
                openSettingsWindow()
            }
        )
        return children
    }

    @MainActor
    private static func goToSpaceSubCommands(
        spaces: SpacesModel?,
        inbox: InboxModel?
    ) -> [CourierCommand] {
        let visible = spaces?.visible ?? []
        var children: [CourierCommand] = visible.enumerated().map { index, space in
            CourierCommand(
                id: "nav.space.\(space.spaceID)",
                title: space.title.isEmpty ? space.spaceID : space.title,
                category: .navigation,
                icon: space.icon.isEmpty ? "tray" : space.icon,
                shortcut: index < 9 ? "⌘\(index + 1)" : nil
            ) {
                spaces?.select(space.spaceID)
            }
        }
        if children.isEmpty {
            children.append(
                CourierCommand(
                    id: "nav.space.inbox",
                    title: String(localized: "Inbox"),
                    category: .navigation,
                    icon: "tray",
                    shortcut: "⌘1"
                ) {
                    spaces?.select("inbox")
                    inbox?.query.space = "inbox"
                }
            )
        }
        children.append(
            CourierCommand(
                id: "nav.space.next",
                title: String(localized: "Next Space"),
                category: .navigation,
                icon: "arrow.right.circle",
                shortcut: "⌘⇧]"
            ) {
                spaces?.selectNextAccount()
            }
        )
        children.append(
            CourierCommand(
                id: "nav.space.previous",
                title: String(localized: "Previous Space"),
                category: .navigation,
                icon: "arrow.left.circle",
                shortcut: "⌘⇧["
            ) {
                spaces?.selectPreviousAccount()
            }
        )
        children.append(
            CourierCommand(
                id: "nav.space.edit",
                title: String(localized: "Edit Spaces…"),
                category: .navigation,
                icon: "slider.horizontal.3",
                shortcut: nil
            ) {
                spaces?.isEditing = true
            }
        )
        return children
    }

    @MainActor
    private static func setThemeSubCommands(_ appearance: AppearancePreferences?) -> [CourierCommand] {
        let modes = ThemeMode.allCases.map { mode in
            CourierCommand(
                id: "appearance.mode.\(mode.rawValue)",
                title: String(localized: "Appearance: \(mode.label)"),
                category: .appearance,
                icon: mode == .dark ? "moon.fill" : (mode == .light ? "sun.max.fill" : "circle.lefthalf.filled"),
                shortcut: nil
            ) {
                appearance?.themeMode = mode
            }
        }
        let presets = CourierThemePreset.allCases.map { preset in
            CourierCommand(
                id: "appearance.preset.\(preset.rawValue)",
                title: preset.title,
                category: .appearance,
                icon: "paintpalette",
                shortcut: nil
            ) {
                appearance?.themePreset = preset
            }
        }
        return modes + presets
    }

    @MainActor
    private static func disappearingSubCommands(_ conversation: ConversationModel?) -> [CourierCommand] {
        let liveChoices = conversation?.timerChoices ?? []
        if !liveChoices.isEmpty {
            return liveChoices.map { choice in
                CourierCommand(
                    id: "chat.disappearing.\(choice.type.rawValue).\(choice.timerMS)",
                    title: choice.title,
                    category: .chat,
                    icon: "timer",
                    shortcut: nil
                ) {
                    Task { await conversation?.setTimer(choice) }
                }
            }
        }
        let fallback: [(id: String, label: String, ms: Int64)] = [
            ("off", String(localized: "Off"), 0),
            ("5m", String(localized: "5 minutes"), 300_000),
            ("1h", String(localized: "1 hour"), 3_600_000),
            ("1d", String(localized: "1 day"), 86_400_000),
            ("7d", String(localized: "7 days"), 604_800_000),
        ]
        return fallback.map { item in
            CourierCommand(
                id: "chat.disappearing.\(item.id)",
                title: item.label,
                category: .chat,
                icon: "timer",
                shortcut: nil
            ) {
                let choice = DisappearingChoice(
                    type: item.ms == 0 ? .off : .afterSend,
                    timerMS: item.ms,
                    title: item.label,
                    isCurrent: false
                )
                Task { await conversation?.setTimer(choice) }
            }
        }
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
            category: .settings,
            icon: "gearshape",
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
