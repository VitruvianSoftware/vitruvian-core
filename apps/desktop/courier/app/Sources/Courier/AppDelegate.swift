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
    /// The sheets and popovers the inbox's menus and keys open.
    let inboxUI = InboxUI()
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
        let inbox = InboxModel(appModel: model, hasTelegramCredentials: { telegram.hasCredentials })
        self.inbox = inbox
        let attention = Attention(source: SystemPresence())
        self.attention = attention
        // The "New" divider goes above as many messages as the inbox counted unread when the chat was opened.
        // A chat opened with no text in the composer's memory takes the draft the engine keeps: its row's, or for a
        // chat the inbox hasn't loaded (a notification opened it from another space, say), one looked up by id.
        conversation = ConversationModel(appModel: model, unreadCount: { id in
            inbox.rows.first { $0.roomID == id }?.unread ?? 0
        }, attention: attention, savedDraft: { id in
            inbox.rows.first { $0.roomID == id }?.draft
        }, lookUpDraft: { id in
            await inbox.lookUpDraft(id)
        })
        let login = LoginFlowModel(appModel: model)
        self.login = login
        spaces = SpacesModel(appModel: model, inbox: inbox)
        labels = LabelsModel(appModel: model)
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
        dockBadge = DockBadge(inbox: inbox)
        let coordinator = NotificationCoordinator(
            appModel: model, delivery: notifier,
            row: { [inbox] id in inbox.rows.first { $0.roomID == id } },
            isLooking: { [attention] in attention.isLooking },
            restoreDraft: { [conversation] room, text, mayHaveBeenSent in
                conversation.composer.restoreUnsent(text: text, in: room, mayHaveBeenSent: mayHaveBeenSent)
            },
            showWindow: { [windowOpener] in windowOpener.show() })
        notifier.coordinator = coordinator
        notifications = coordinator
        coordinator.start()
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting waits for the engine to stop (SIGTERM, then SIGKILL after ten seconds), so it never outlives the
    /// app holding its data directory's lock.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
