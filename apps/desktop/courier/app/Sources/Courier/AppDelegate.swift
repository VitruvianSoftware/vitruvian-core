// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
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
    /// The sheets and popovers the inbox's menus and keys open.
    let inboxUI = InboxUI()
    /// Whether the message keys act on the chat's selected message or the thread pane's.
    let messageFocus = MessageFocus()
    /// Whether the person is looking at the open chat: marking it read and keeping its notifications quiet use it.
    let attention: Attention
    let windowOpener = MainWindowOpener()
    private var signInWindows: SignInWindowPresenter?
    private var notifications: NotificationCoordinator?
    private let notifier = Notifier()
    private var dockBadge: DockBadge?
    /// Held for as long as Courier runs: without it, App Nap slows a Courier whose window is closed or hidden, and
    /// the engine's messages, and so notifications, come late. It still lets the Mac sleep when idle.
    private var appNapActivity: NSObjectProtocol?

    override init() {
        let environment = ProcessInfo.processInfo.environment
        let supervisor = EngineSupervisor(
            enginePath: EngineLocation.enginePath(environment: environment),
            dataDir: EngineLocation.dataDirectory(environment: environment),
            environment: environment,
            launcher: FoundationProcessLauncher()
        )
        model = AppModel(supervisor: supervisor)
        // Telegram's keys: Courier's own, packaged into the app, else the ones the person saved.
        let telegram = TelegramCredentialSource()
        // The person's plan, one for every model that asks (part 4.7 brings plans; until then, everything).
        let entitlement: any EntitlementProvider = AlwaysEntitled()
        let inbox = InboxModel(appModel: model, hasTelegramCredentials: { telegram.hasCredentials },
                              preferences: InboxPreferences(), entitlement: entitlement)
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
        inbox.onSelectedRowLookedUp = { [weak conversation] row in
            conversation?.learnUnreadCount(row.unread, of: row.roomID)
            conversation?.learnChat(row)
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
        spaces = SpacesModel(appModel: model, inbox: inbox)
        labels = LabelsModel(appModel: model)
        search = SearchModel(appModel: model, recents: RecentSearches(), open: { [model] in model.open($0) })
        // The inbox's buttons: Reconnect starts that network's sign-in as Add does (Google Messages warns first).
        inbox.onAddNetwork = { login.showPicker() }
        inbox.onReconnect = { network in login.begin(network: network) }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Courier receives messages and shows notifications while its window is closed")
        // Copies made to open received files last until the next launch.
        OpenFileCache.shared.clear()
        signInWindows = SignInWindowPresenter(login: login)
        dockBadge = DockBadge(spaces: spaces)
        let coordinator = NotificationCoordinator(
            appModel: model, delivery: notifier,
            row: { [inbox] id in inbox.rows.first { $0.roomID == id } },
            isLooking: { [attention] in attention.isLooking },
            isAwayFromLatest: { [conversation] in conversation.isHeldAwayFromLatest },
            restoreDraft: { [conversation] room, text, mayHaveBeenSent in
                conversation.composer.restoreUnsent(text: text, in: room, mayHaveBeenSent: mayHaveBeenSent)
            },
            showWindow: { [windowOpener] in windowOpener.show() },
            // The inbox's own object, which Settings changes: a copy would ignore the change until the next launch.
            preferences: inbox.preferences)
        notifier.coordinator = coordinator
        notifications = coordinator
        coordinator.start()
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting first hands every held (undo send) message to the engine and waits for its answer, for at most
    /// `AppModel.sendHeldAtQuitTimeout` (5 s), so nothing held is left to the next start unless the engine is stuck.
    /// Then it waits for the engine to stop (SIGTERM, then SIGKILL after ten seconds), so it never outlives the app
    /// holding its data directory's lock.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.sendHeldMessages()
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Copy's pasteboard: the system's general one, as plain text.
private final class SystemPasteboard: TextPasteboard {
    func setString(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
