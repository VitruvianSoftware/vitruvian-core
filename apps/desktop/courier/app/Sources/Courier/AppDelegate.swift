// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import CourierCore

/// Owns the app's model, and so the engine: starts it at launch and stops it before the app quits. Closing the
/// window does not quit (spec §2): Courier keeps running, with its Dock icon, to keep receiving.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let inbox: InboxModel
    let conversation: ConversationModel
    let login: LoginFlowModel
    /// The spaces bar, and the labels with their auto-archive rules.
    let spaces: SpacesModel
    let labels: LabelsModel
    /// ⌘K and ⌘F. Opening a result opens its chat through the app's model, at the message for a message.
    let search: SearchModel
    /// The message menu, its keys and commands; the open chat's scheduled messages.
    let messageActions: MessageActionsModel
    let scheduled: ScheduledModel
    /// Settings ▸ Messages: one object for the composers, the conversation and Settings, which reads the defaults
    /// once (a copy would miss a change until the next launch). The same for the quick replies.
    let composerPreferences: ComposerPreferences
    let quickReplies: QuickReplies
    /// Launch at login, Touch ID app lock, and window lifecycle settings.
    let lifecycle = SystemLifecycleModel()
    /// Dock badge mode and menu-bar status item settings.
    let dockPreferences = DockAndTrayPreferences()
    /// Shared Appearance preferences (`AppearancePreferences`: themes, zoom, fonts, confetti).
    let appearance = AppearancePreferences()
    /// Shared ⌘J Command Bar model (`CommandBarModel`).
    let commandBar: CommandBarModel
    /// Shared Settings navigation and search model (`⌘,`).
    let settingsNavigation = SettingsNavigationModel()
    /// Shared per-account and global notification preferences (the single instance owned by `inbox.preferences`).
    var notificationPreferences: NotificationPreferences { inbox.preferences.notifications }
    /// Accounts and Bridges settings model (`AccountsAndBridgesModel`).
    let accountsAndBridges: AccountsAndBridgesModel
    /// Local storage breakdown and media cleanup model (`StorageModel`).
    let storage: StorageModel
    /// Local problem report bundle model (`ProblemReportModel`).
    let problemReport: ProblemReportModel
    /// Shared keyboard shortcut registry read by menus, the ⌘/ sheet, and the Settings ▸ Shortcuts recorder.
    let hotkeys: HotkeyRegistry
    /// Detached chat, space, and thread window registry and presenter.
    let detachedWindows: DetachedWindowRegistry
    private var detachedWindowManager: DetachedWindowManager?
    /// Shared menu coordinator invoked by the main menu bar, Dock menu, and menu-bar status item.
    private(set) lazy var menuCoordinator = AppMenuCoordinator(
        inbox: inbox,
        lifecycle: lifecycle,
        settingsNavigation: settingsNavigation,
        showMainWindow: { [weak self] in self?.windowOpener.show() },
        showSettingsWindow: {
            NSApp.activate()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        },
        hideApp: { NSApp.hide(nil) },
        closeKeyWindow: { NSApp.keyWindow?.performClose(nil) },
        closeAllAppWindows: { [weak self] in
            self?.detachedWindows.closeAll()
            NSApp.windows.forEach { $0.performClose(nil) }
        },
        openDetachedChat: { [weak self] roomID in self?.detachedWindows.open(.chat(roomID: roomID)) },
        quitApplication: { NSApp.terminate(nil) }
    )
    /// Single live dispatcher for all menu commands, window-scoped shortcuts, composer Return handling, and global hotkeys.
    private(set) lazy var hotkeyDispatcher = HotkeyDispatcher(
        inbox: inbox,
        spaces: spaces,
        conversation: conversation,
        messageActions: messageActions,
        search: search,
        lifecycle: lifecycle,
        menuCoordinator: menuCoordinator,
        focus: messageFocus,
        hotkeys: hotkeys,
        commandBar: commandBar,
        appearance: appearance,
        bringMainWindowForward: { [weak self] in
            guard let self else { return true }
            guard !self.inboxUI.isMainWindowKey else { return true }
            self.windowOpener.show()
            return false
        },
        onFilterByAccount: { [weak self] in self?.inboxUI.accountPopover = true },
        onRemindLater: { [weak self] in self?.inboxUI.remindPopover = true },
        onAttachFiles: { composer in AttachmentPicker.run(into: composer) },
        onArchiveAllRead: { [weak self] in
            guard let self else { return }
            await Confirm.archiveAllRead(self.inbox)
        }
    )
    private var globalHotkeyMonitor: GlobalHotkeyMonitor?
    /// The sheets and popovers the inbox's menus and keys open.
    let inboxUI = InboxUI()
    /// Whether the message keys act on the chat's selected message or the thread pane's.
    let messageFocus = MessageFocus()
    /// Whether the person is looking at the open chat: marking it read and keeping its notifications quiet use it.
    let attention: Attention
    let windowOpener = MainWindowOpener()
    private var signInWindows: SignInWindowPresenter?
    private var notifications: NotificationCoordinator?
    let notifier = Notifier()
    private var dockBadge: DockBadge?
    private var statusItem: NSStatusItem?
    private var statusItemSubscriptions = Set<AnyCancellable>()
    /// Held for as long as Courier runs: without it, App Nap slows a Courier whose window is closed or hidden, and
    /// the engine's messages, and so notifications, come late. It still lets the Mac sleep when idle.
    private var appNapActivity: NSObjectProtocol?
    /// "Also hide that you're typing?", for every way Incognito is turned on.
    private var hideTypingQuestion: HideTypingQuestion?

    override init() {
        let environment = ProcessInfo.processInfo.environment
        let supervisor = EngineSupervisor(
            enginePath: EngineLocation.enginePath(environment: environment),
            dataDir: EngineLocation.dataDirectory(environment: environment),
            environment: environment,
            launcher: FoundationProcessLauncher()
        )
        model = AppModel(supervisor: supervisor, lifecycle: lifecycle)
        // Telegram's keys: Courier's own, packaged into the app, else the ones the person saved.
        let telegram = TelegramCredentialSource()
        // The person's plan, one for every model that asks (part 4.7 brings plans; until then, everything).
        let entitlement: any EntitlementProvider = AlwaysEntitled()
        let inbox = InboxModel(appModel: model, hasTelegramCredentials: { telegram.hasCredentials },
                              preferences: InboxPreferences(), entitlement: entitlement, lifecycle: lifecycle)
        self.inbox = inbox
        let attention = Attention(source: SystemPresence())
        self.attention = attention
        // The "New" divider goes above as many messages as the inbox counted unread when the chat was opened.
        // A chat opened with no text in the composer's memory takes the draft the engine keeps: its row's, or for a
        // chat the inbox hasn't loaded (a notification opened it from another space, say), one looked up by id. A
        // chat outside the list (a search result in the archive) has its row looked up as it opens; its unread
        // count reaches the conversation when that answer does.
        let composerPreferences = ComposerPreferences()
        self.composerPreferences = composerPreferences
        let quickReplies = QuickReplies()
        self.quickReplies = quickReplies
        // Its network, its name and whether it is one-to-one come from the chat's row: the composers need them for
        // what the chat allows and for quick replies.
        let conversation = ConversationModel(appModel: model, unreadCount: { id in
            inbox.unreadCount(of: id)
        }, attention: attention, savedDraft: { id in
            inbox.savedDraft(of: id)
        }, lookUpDraft: { id in
            await inbox.lookUpDraft(id)
        }, chat: { id in
            inbox.row(of: id)
        }, preferences: composerPreferences)
        self.conversation = conversation
        // Both composers (the chat's and the thread pane's): the plan, the quick replies, ⌘↩ archiving as the inbox's
        // Archive does, and toasts where the inbox's show.
        for composer in [conversation.composer, conversation.thread.composer] {
            composer.entitlement = entitlement
            composer.quickReplies = quickReplies
            composer.onArchive = { [weak inbox] room in await inbox?.archive(true, ids: [room]) }
            composer.onToast = { [weak inbox] message in inbox?.announce(message) }
        }
        conversation.onToast = { [weak inbox] message in inbox?.announce(message) }
        // Mark as Unread from a message goes where the inbox's own Mark as Unread goes (one rule).
        conversation.planAfterToggleRead = { [weak inbox] in inbox?.planAfterToggleRead() ?? {} }
        // Incognito is part of the plan: the conversation asks the inbox, which holds the person's plan (C42).
        conversation.isEntitled = { [weak inbox] feature in inbox?.isEntitled(feature) ?? false }
        // Incognito wins over "Mark chats read when I archive them".
        inbox.isIncognito = { [weak conversation] in conversation?.incognitoIsOn ?? false }
        inbox.onSelectedRowLookedUp = { [weak conversation] row in
            conversation?.learnUnreadCount(row.unread, of: row.roomID)
            conversation?.learnChat(row)
        }
        inbox.onOpenMergedChat = { [weak conversation] merged in
            conversation?.openMergedChat(merged)
        }
        let messageActions = MessageActionsModel(conversation: conversation, appModel: model,
                                                 preferences: composerPreferences, pasteboard: SystemPasteboard())
        messageActions.quickReplies = quickReplies
        messageActions.onToast = { [weak inbox] message in inbox?.announce(message) }
        messageActions.openURL = { url in NSWorkspace.shared.open(url) }
        self.messageActions = messageActions
        let scheduled = ScheduledModel(appModel: model)
        scheduled.onToast = { [weak inbox] message in inbox?.announce(message) }
        self.scheduled = scheduled
        let login = LoginFlowModel(appModel: model)
        self.login = login
        let accountsAndBridges = AccountsAndBridgesModel(appModel: model, lifecycle: lifecycle)
        self.accountsAndBridges = accountsAndBridges
        settingsNavigation.bind(accountsAndBridges: accountsAndBridges)
        storage = StorageModel(appModel: model, lifecycle: lifecycle)
        problemReport = ProblemReportModel(appModel: model)
        spaces = SpacesModel(appModel: model, inbox: inbox, lifecycle: lifecycle)
        labels = LabelsModel(appModel: model, lifecycle: lifecycle)
        let lifecycleRef = lifecycle
        hotkeys = HotkeyRegistry(isAppLocked: { lifecycleRef.isLocked })
        for composer in [conversation.composer, conversation.thread.composer] {
            composer.hotkeys = hotkeys
        }
        detachedWindows = DetachedWindowRegistry(
            appModel: model,
            mainInbox: inbox,
            lifecycle: lifecycle,
            inboxPreferences: inbox.preferences,
            composerPreferences: composerPreferences,
            quickReplies: quickReplies,
            entitlement: entitlement,
            makePasteboard: { SystemPasteboard() },
            openURL: { url in NSWorkspace.shared.open(url) },
            hotkeys: hotkeys
        )
        search = SearchModel(appModel: model, recents: RecentSearches(), open: { [model] in model.open($0) })
        let commandBar = CommandBarModel(
            lifecycle: lifecycle,
            recentChatsProvider: { [weak inbox] in
                guard let inbox else { return [] }
                let byID = Dictionary(uniqueKeysWithValues: inbox.rows.map { ($0.roomID, $0) })
                let recents = inbox.recentlyViewedRoomIDs.compactMap { byID[$0] }
                return recents.isEmpty ? Array(inbox.rows.prefix(15)) : recents
            },
            onSelectRecentChat: { [weak inbox] roomID in
                inbox?.select(roomID)
            }
        )
        self.commandBar = commandBar
        // The inbox's buttons: Reconnect signs that account in again (the banner's account, or with none the network's
        // own sign-in), as Add does (Google Messages warns first).
        inbox.onAddNetwork = { login.showPicker() }
        inbox.onReconnect = { network, accountID in login.begin(network: network, accountID: accountID) }
        super.init()
        commandBar.commandsProvider = { [weak self] in
            guard let self else { return [] }
            return CommandSet.all(
                inbox: self.inbox,
                spaces: self.spaces,
                search: self.search,
                actions: self.messageActions,
                conversation: self.conversation,
                composer: self.conversation.composer,
                login: self.login,
                appearance: self.appearance,
                navigation: self.settingsNavigation,
                lifecycle: self.lifecycle,
                hotkeys: self.hotkeys,
                detachedRegistry: self.detachedWindows,
                openSettingsWindow: { [weak self] in self?.menuCoordinator.openSettings(.general) },
                presentReportProblem: { [weak self] in self?.menuCoordinator.openSettings(.reportProblem) },
                restartNotificationCenter: { [weak self] in self?.notifier.restartNotificationCenter() },
                performDeleteMedia: { [weak self] in
                    guard let self else { return }
                    self.menuCoordinator.openSettings(.storage)
                    Task { await self.storage.deleteMedia(olderThan: .allTime) }
                },
                openRecentlyViewedChats: { [weak self] in self?.commandBar.openInRecentChatsMode() },
                toggleSidebar: { [weak self] in self?.menuCoordinator.toggleSidebar() },
                focusApp: { [weak self] in self?.menuCoordinator.focusApp() }
            )
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuCoordinator.onOpenCommandBar = { [weak self] in
            self?.commandBar.toggle()
        }
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Courier receives messages and shows notifications while its window is closed")
        // The Dock shows the bundle's icon until the one chosen in Settings ▸ Appearance is put back.
        appearance.applySavedAppIcon()
        // Copies made to open received files last until the next launch.
        OpenFileCache.shared.clear()
        PictureInPictureController.shared.onReturnToChat = { [windowOpener, model] roomID, messageID in
            windowOpener.show()
            model.open(.message(roomID: roomID, eventID: messageID))
        }
        signInWindows = SignInWindowPresenter(login: login)
        globalHotkeyMonitor = GlobalHotkeyMonitor(registry: hotkeys, dispatcher: hotkeyDispatcher)
        detachedWindowManager = DetachedWindowManager(
            registry: detachedWindows,
            appModel: model,
            mainInbox: inbox,
            spaces: spaces,
            lifecycle: lifecycle,
            onSearchInChat: { [weak self] roomID in
                self?.windowOpener.show()
                self?.search.show(in: roomID)
            }
        )
        hideTypingQuestion = HideTypingQuestion(conversation: conversation, present: Self.askToHideTyping)
        dockBadge = DockBadge(spaces: spaces, dockPreferences: dockPreferences, lifecycle: lifecycle)
        configureStatusItemObservers()
        let coordinator = NotificationCoordinator(
            appModel: model, delivery: notifier,
            row: { [inbox] id in inbox.rows.first { $0.roomID == id } },
            isLooking: { [attention] in attention.isLooking },
            isAwayFromLatest: { [conversation] in conversation.isHeldAwayFromLatest },
            isIncognito: { [conversation] in conversation.incognitoIsOn },
            isAppLocked: { [lifecycle] in lifecycle.isLocked },
            restoreDraft: { [conversation] room, text, mayHaveBeenSent in
                conversation.composer.restoreUnsent(text: text, in: room, mayHaveBeenSent: mayHaveBeenSent)
            },
            showWindow: { [windowOpener] in windowOpener.show() },
            // The inbox's own object, which Settings changes: a copy would ignore the change until the next launch.
            preferences: inbox.preferences,
            clipboard: PasteboardClipboardSink(),
            soundEffects: SoundEffectPlayer())
        notifier.coordinator = coordinator
        notifications = coordinator
        coordinator.start()
        model.start()
        if lifecycle.shouldHideMainWindowOnLaunch {
            DispatchQueue.main.async { NSApp.hide(nil) }
        }
    }

    func minimizeToMenuBar() {
        menuCoordinator.minimizeToMenuBar()
    }

    private func configureStatusItemObservers() {
        guard Notifier.isAvailable else { return }
        Publishers.CombineLatest4(
            dockPreferences.$showMenuBarIcon,
            spaces.$spaces,
            dockPreferences.$badgeMode,
            lifecycle.$isLocked
        )
        .sink { [weak self] showIcon, spacesList, badgeMode, isLocked in
            self?.updateStatusItem(
                showIcon: showIcon,
                spacesList: spacesList,
                badgeMode: badgeMode,
                isLocked: isLocked
            )
        }
        .store(in: &statusItemSubscriptions)
    }

    private func updateStatusItem(
        showIcon: Bool,
        spacesList: [Space],
        badgeMode: DockBadgeMode,
        isLocked: Bool
    ) {
        guard Notifier.isAvailable else { return }
        guard showIcon else {
            if let existing = statusItem {
                NSStatusBar.system.removeStatusItem(existing)
                statusItem = nil
            }
            return
        }
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
        let count = isLocked ? 0 : SpacesModel.badgeCount(of: spacesList, mode: badgeMode)
        let symbolName = count > 0 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: String(localized: "Courier"))
        image?.isTemplate = true
        button.image = image
        button.toolTip = String(localized: "Courier")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRightClick, let item = statusItem {
            let menu = buildStatusItemMenu()
            item.menu = menu
            sender.performClick(nil)
            item.menu = nil
        } else {
            windowOpener.show()
        }
    }

    private func buildStatusItemMenu() -> NSMenu {
        let menu = NSMenu(title: "Courier")
        menu.autoenablesItems = false

        let unreadTitle: String
        if lifecycle.isLocked {
            unreadTitle = String(localized: "Courier is locked")
        } else {
            let count = SpacesModel.badgeCount(of: spaces.spaces, mode: dockPreferences.badgeMode)
            switch count {
            case 0: unreadTitle = String(localized: "No unread chats")
            case 1: unreadTitle = String(localized: "1 unread chat")
            default: unreadTitle = String(localized: "\(count) unread chats")
            }
        }
        let statusHeader = NSMenuItem(title: unreadTitle, action: nil, keyEquivalent: "")
        statusHeader.isEnabled = false
        menu.addItem(statusHeader)

        let dockMenu = DockMenuModel.build(
            isLocked: lifecycle.isLocked,
            inboxRows: inbox.rows,
            recentlyViewedRoomIDs: inbox.recentlyViewedRoomIDs,
            currentRoomID: model.selectedRoomID
        )
        if !dockMenu.unreadChats.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: String(localized: "Unread Chats"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for chat in dockMenu.unreadChats {
                let item = NSMenuItem(title: chat.title, action: #selector(selectDockMenuChat(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = chat.roomID
                item.isEnabled = true
                menu.addItem(item)
            }
        }
        if !dockMenu.recentChats.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: String(localized: "Recent Chats"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for chat in dockMenu.recentChats {
                let item = NSMenuItem(title: chat.title, action: #selector(selectDockMenuChat(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = chat.roomID
                item.isEnabled = true
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let openItem = NSMenuItem(title: String(localized: "Open Courier"), action: #selector(openCourierFromMenu(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.isEnabled = true
        menu.addItem(openItem)

        let minItem = NSMenuItem(title: String(localized: "Minimize to Menu Bar"), action: #selector(minimizeFromMenu(_:)), keyEquivalent: "")
        applyMenuChord(hotkeys.primaryChord(for: "Minimize To Menu Bar"), to: minItem, enabled: !lifecycle.isLocked)
        minItem.target = self
        minItem.isEnabled = !lifecycle.isLocked
        menu.addItem(minItem)

        let lockTitle = lifecycle.isLocked ? String(localized: "Unlock Courier…") : String(localized: "Lock App")
        let lockItem = NSMenuItem(title: lockTitle, action: #selector(lockOrUnlockFromMenu(_:)), keyEquivalent: "")
        lockItem.target = self
        lockItem.isEnabled = true
        menu.addItem(lockItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: String(localized: "Quit Courier"), action: #selector(quitFromMenu(_:)), keyEquivalent: "")
        applyMenuChord(hotkeys.primaryChord(for: "Quit App"), to: quitItem, enabled: !lifecycle.isLocked)
        quitItem.target = self
        quitItem.isEnabled = !lifecycle.isLocked
        menu.addItem(quitItem)
        return menu
    }

    private func applyMenuChord(_ chord: KeyChord?, to item: NSMenuItem, enabled: Bool) {
        guard enabled, let chord else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.keyEquivalent = chord.key
        var mask: NSEvent.ModifierFlags = []
        if chord.command { mask.insert(.command) }
        if chord.shift { mask.insert(.shift) }
        if chord.option { mask.insert(.option) }
        if chord.control { mask.insert(.control) }
        item.keyEquivalentModifierMask = mask
    }

    @objc private func openCourierFromMenu(_ sender: NSMenuItem) {
        windowOpener.show()
    }

    @objc private func minimizeFromMenu(_ sender: NSMenuItem) {
        menuCoordinator.minimizeToMenuBar()
    }

    @objc private func quitFromMenu(_ sender: NSMenuItem) {
        menuCoordinator.quitApp()
    }

    @objc private func lockOrUnlockFromMenu(_ sender: NSMenuItem) {
        if lifecycle.isLocked {
            windowOpener.show()
        }
        Task { await menuCoordinator.lockOrUnlockApp() }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        if lifecycle.isLocked {
            let menu = NSMenu(title: "Courier")
            menu.autoenablesItems = false
            let unlockItem = NSMenuItem(
                title: String(localized: "Unlock Courier…"),
                action: #selector(lockOrUnlockFromMenu(_:)),
                keyEquivalent: ""
            )
            unlockItem.target = self
            unlockItem.isEnabled = true
            menu.addItem(unlockItem)
            return menu
        }

        let dockMenu = DockMenuModel.build(
            isLocked: lifecycle.isLocked,
            inboxRows: inbox.rows,
            recentlyViewedRoomIDs: inbox.recentlyViewedRoomIDs,
            currentRoomID: model.selectedRoomID
        )
        guard !dockMenu.isEmpty else { return nil }

        let menu = NSMenu(title: "Courier")
        menu.autoenablesItems = false

        if !dockMenu.unreadChats.isEmpty {
            let header = NSMenuItem(title: String(localized: "Unread Chats"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for chat in dockMenu.unreadChats {
                let item = NSMenuItem(title: chat.title, action: #selector(selectDockMenuChat(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = chat.roomID
                item.isEnabled = true
                menu.addItem(item)
            }
        }

        if !dockMenu.recentChats.isEmpty {
            if !dockMenu.unreadChats.isEmpty {
                menu.addItem(.separator())
            }
            let header = NSMenuItem(title: String(localized: "Recent Chats"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for chat in dockMenu.recentChats {
                let item = NSMenuItem(title: chat.title, action: #selector(selectDockMenuChat(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = chat.roomID
                item.isEnabled = true
                menu.addItem(item)
            }
        }

        return menu
    }

    @objc private func selectDockMenuChat(_ sender: NSMenuItem) {
        guard let roomID = sender.representedObject as? String else { return }
        Task {
            _ = await menuCoordinator.openChatFromExternalMenu(roomID)
        }
    }

    /// The question as an alert: a sheet on the window in front (Settings, or the main window for the command bar),
    /// or on its own when no window is. Esc is Keep Showing. It returns how to take the alert down, for Incognito
    /// turned off while it is up (HideTypingQuestion): ending the sheet, or stopping the app-modal alert.
    private static func askToHideTyping(_ answer: @escaping @MainActor (Bool) -> Void) -> (@MainActor () -> Void) {
        let alert = NSAlert()
        alert.messageText = ConversationModel.hideTypingQuestion
        alert.addButton(withTitle: ConversationModel.hideTypingButton)
        alert.addButton(withTitle: ConversationModel.keepShowingTypingButton).keyEquivalent = "\u{1b}"
        if let window = NSApp.keyWindow {
            var lockObserver: NSObjectProtocol?
            lockObserver = NotificationCenter.default.addObserver(
                forName: SystemLifecycleModel.didLockNotification,
                object: nil,
                queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated {
                    guard let window, window.attachedSheet === alert.window else { return }
                    window.endSheet(alert.window, returnCode: .abort)
                }
            }
            alert.beginSheetModal(for: window) { response in
                if let lockObserver { NotificationCenter.default.removeObserver(lockObserver) }
                let hide = response == .alertFirstButtonReturn
                Task { @MainActor in answer(hide) }
            }
            return { [weak window] in
                if let lockObserver { NotificationCenter.default.removeObserver(lockObserver) }
                guard let window, window.attachedSheet === alert.window else { return }
                window.endSheet(alert.window, returnCode: .abort)
            }
        }
        var lockObserver: NSObjectProtocol?
        lockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didLockNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if NSApp.modalWindow === alert.window { NSApp.abortModal() }
            }
        }
        // Run on the next turn, so the way to take it down is handed back first: runModal doesn't return until the
        // alert is answered or stopped.
        DispatchQueue.main.async {
            let response = alert.runModal()
            if let lockObserver { NotificationCenter.default.removeObserver(lockObserver) }
            Task { @MainActor in answer(response == .alertFirstButtonReturn) }
        }
        return {
            if let lockObserver { NotificationCenter.default.removeObserver(lockObserver) }
            if NSApp.modalWindow === alert.window { NSApp.abortModal() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        lifecycle.shouldTerminateWhenMainWindowClosed
    }

    /// Quitting first tells each chat I'm typing in that I stopped (both composers), then hands every held (undo
    /// send) message to the engine and waits for its answer, for at most `AppModel.sendHeldAtQuitTimeout` (5 s), so
    /// nothing held is left to the next start unless the engine is stuck. Then it waits for the engine to stop
    /// (SIGTERM, then SIGKILL after ten seconds), so it never outlives the app holding its data directory's lock.
    /// `AppModel.quit` does all three.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        PictureInPictureController.shared.stopForApplicationTermination()
        conversation.audioPlayer.stopForApplicationTermination()
        Task {
            await model.quit(conversation)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
