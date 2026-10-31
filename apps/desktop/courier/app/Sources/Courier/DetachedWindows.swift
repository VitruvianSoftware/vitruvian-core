// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import CourierCore
import SwiftUI

private struct OpenDetachedWindowKey: EnvironmentKey {
    static let defaultValue: (@MainActor (DetachedWindowTarget) -> Void)? = nil
}

extension EnvironmentValues {
    var openDetachedWindow: (@MainActor (DetachedWindowTarget) -> Void)? {
        get { self[OpenDetachedWindowKey.self] }
        set { self[OpenDetachedWindowKey.self] = newValue }
    }
}

/// Detached single-chat window (`01-screens-and-flows.md` §16).
/// Owns its own `ConversationModel` via `DetachedWindowSession` and shows `AppLockOverlay` when locked.
struct DetachedChatWindowView: View {
    @ObservedObject var session: DetachedWindowSession
    @ObservedObject var conversation: ConversationModel
    @ObservedObject var lifecycle: SystemLifecycleModel
    var onOpenDetached: ((DetachedWindowTarget) -> Void)?

    init(
        session: DetachedWindowSession,
        lifecycle: SystemLifecycleModel,
        onOpenDetached: ((DetachedWindowTarget) -> Void)? = nil
    ) {
        self.session = session
        self.conversation = session.conversation
        self.lifecycle = lifecycle
        self.onOpenDetached = onOpenDetached
    }

    var body: some View {
        LockableWindowContent(lifecycle: lifecycle) {
            ConversationView(
                conversation: conversation,
                composer: conversation.composer,
                inbox: session.hostInbox,
                messageActions: session.messageActions,
                scheduled: session.scheduled,
                preferences: session.composerPreferences,
                thread: session.thread,
                focus: session.focus,
                appModel: session.appModel
            )
            .environment(\.openDetachedWindow, onOpenDetached)
            .frame(minWidth: 520, minHeight: 420)
            .overlay(alignment: .bottom) {
                ToastView(inbox: session.hostInbox)
            }
        }
    }
}

/// Detached space window (`01-screens-and-flows.md` §17).
/// Scoped to a single space with its own `InboxModel` and `ConversationModel`, covered by `AppLockOverlay` when locked.
struct DetachedSpaceWindowView: View {
    @ObservedObject var session: DetachedWindowSession
    @ObservedObject var inbox: InboxModel
    @ObservedObject var conversation: ConversationModel
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var lifecycle: SystemLifecycleModel
    @StateObject private var ui = InboxUI()
    var onOpenDetached: ((DetachedWindowTarget) -> Void)?
    var onSearchInChat: (@MainActor (String) -> Void)?

    init(
        session: DetachedWindowSession,
        inbox: InboxModel,
        spaces: SpacesModel,
        lifecycle: SystemLifecycleModel,
        onOpenDetached: ((DetachedWindowTarget) -> Void)? = nil,
        onSearchInChat: (@MainActor (String) -> Void)? = nil
    ) {
        self.session = session
        self.inbox = inbox
        self.conversation = session.conversation
        self.spaces = spaces
        self.lifecycle = lifecycle
        self.onOpenDetached = onOpenDetached
        self.onSearchInChat = onSearchInChat
    }

    var body: some View {
        LockableWindowContent(lifecycle: lifecycle) {
            HSplitView {
                InboxList(
                    inbox: inbox,
                    spaces: spaces,
                    preferences: inbox.preferences,
                    ui: ui
                )
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 440)
                if conversation.roomID != nil {
                    ConversationView(
                        conversation: conversation,
                        composer: conversation.composer,
                        inbox: inbox,
                        messageActions: session.messageActions,
                        scheduled: session.scheduled,
                        preferences: session.composerPreferences,
                        thread: session.thread,
                        focus: session.focus,
                        appModel: session.appModel
                    )
                    .frame(minWidth: 420, maxWidth: .infinity)
                } else {
                    Text(String(localized: "Select a chat"))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .environment(\.openDetachedWindow, onOpenDetached)
            .environment(\.searchInChat, onSearchInChat)
            .frame(minWidth: 740, minHeight: 460)
            .sheet(
                item: Binding(
                    get: { ui.customReminder ?? inbox.customReminder },
                    set: { value in
                        ui.customReminder = value
                        inbox.customReminder = value
                    }
                )
            ) { request in
                CustomReminderSheet(request: request, inbox: inbox)
            }
            .sheet(
                isPresented: Binding(
                    get: { inbox.startNewChatDraft != nil },
                    set: { shown in if !shown { inbox.startNewChatDraft = nil } }
                )
            ) {
                if let draft = inbox.startNewChatDraft {
                    StartNewChatView(
                        draft: draft,
                        onQueryChanged: { updated in
                            inbox.updateStartNewChatDraft(updated)
                        },
                        onOpenDirectChat: { candidate in
                            Task { await inbox.openDirectChat(with: candidate) }
                        },
                        onLookup: { action in
                            Task { await inbox.performStartNewChatLookup(action) }
                        },
                        onCreateGroup: { updated in
                            inbox.startNewChatDraft = updated
                            Task { await inbox.submitNewGroupChat() }
                        },
                        onSendBlast: { updated in
                            inbox.startNewChatDraft = updated
                            Task { await inbox.submitBlast() }
                        },
                        onCancel: {
                            inbox.startNewChatDraft = nil
                        }
                    )
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { inbox.mergedChatEditorDraft != nil },
                    set: { shown in if !shown { inbox.mergedChatEditorDraft = nil } }
                )
            ) {
                if let draft = inbox.mergedChatEditorDraft {
                    MergedChatEditorSheet(
                        draft: draft,
                        onSave: { updated in
                            inbox.mergedChatEditorDraft = updated
                            Task { await inbox.saveMergedChatEditor() }
                        },
                        onUnmerge: { mergeID in
                            Task { await inbox.unmergeChat(mergeID) }
                        },
                        onCancel: {
                            inbox.mergedChatEditorDraft = nil
                        }
                    )
                }
            }
        }
    }
}

/// Detached thread window (`01-screens-and-flows.md` §18).
/// Hosts a standalone `ThreadPane` backed by its own `ConversationModel` and `ThreadModel`, covered by `AppLockOverlay` when locked.
struct DetachedThreadWindowView: View {
    @ObservedObject var session: DetachedWindowSession
    @ObservedObject var conversation: ConversationModel
    @ObservedObject var thread: ThreadModel
    @ObservedObject var messageActions: MessageActionsModel
    @ObservedObject var lifecycle: SystemLifecycleModel

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

    init(
        session: DetachedWindowSession,
        lifecycle: SystemLifecycleModel
    ) {
        self.session = session
        self.conversation = session.conversation
        self.thread = session.thread
        self.messageActions = session.messageActions
        self.lifecycle = lifecycle
    }

    var body: some View {
        LockableWindowContent(lifecycle: lifecycle) {
            ThreadPane(
                thread: thread,
                conversation: conversation,
                composer: thread.composer,
                messageActions: messageActions,
                preferences: session.composerPreferences,
                focus: session.focus,
                showsOpenInNewWindowButton: false
            )
            .frame(minWidth: 380, minHeight: 440)
            .sheet(item: sheetRequest) { sheet in
                requestSheet(sheet)
            }
            .alert(confirmPrompt, isPresented: confirming) {
                Button(confirmTitle, role: .destructive) {
                    Task { await messageActions.confirm() }
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    messageActions.dismissRequest()
                }
            }
            .overlay(alignment: .bottom) {
                ToastView(inbox: session.hostInbox)
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
            if value == nil, sheetRequestIsShown {
                messageActions.dismissRequest()
            }
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
            ForwardPicker(
                model: ForwardPickerModel(appModel: session.appModel),
                networkName: session.hostInbox.networkName,
                forward: { rooms in Task { await messageActions.forward(id, to: rooms) } },
                cancel: messageActions.dismissRequest
            )
        case let .react(id):
            ReactionPicker(
                react: { key in
                    messageActions.dismissRequest()
                    Task { await conversation.react(to: id, key: key) }
                },
                cancel: messageActions.dismissRequest
            )
        case .sendLater:
            SendLaterPicker(
                composer: thread.composer,
                preferences: session.composerPreferences,
                done: messageActions.dismissRequest
            )
        case .quickReplyTitle:
            QuickReplyTitleSheet(actions: messageActions)
        }
    }

    private var confirming: Binding<Bool> {
        Binding(get: {
            if case .confirm? = messageActions.request { return true }
            return false
        }, set: { shown in
            if !shown, case .confirm? = messageActions.request {
                messageActions.dismissRequest()
            }
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
}

/// Manages `NSWindow` instances for `DetachedWindowRegistry` targets (`chat`, `space`, `thread`).
@MainActor
final class DetachedWindowManager: NSObject, NSWindowDelegate {
    let registry: DetachedWindowRegistry
    private weak var appModel: AppModel?
    private weak var mainInbox: InboxModel?
    private weak var spaces: SpacesModel?
    private let lifecycle: SystemLifecycleModel
    private let onSearchInChat: (@MainActor (String) -> Void)?
    private(set) var windows: [DetachedWindowTarget: NSWindow] = [:]
    private var unlockedTitles: [DetachedWindowTarget: String] = [:]
    private var closingFromRegistry = Set<DetachedWindowTarget>()
    private var lockStateCancellable: AnyCancellable?
    private var lockObserver: Any?
    private var unlockObserver: Any?

    init(
        registry: DetachedWindowRegistry,
        appModel: AppModel,
        mainInbox: InboxModel,
        spaces: SpacesModel,
        lifecycle: SystemLifecycleModel,
        onSearchInChat: (@MainActor (String) -> Void)? = nil
    ) {
        self.registry = registry
        self.appModel = appModel
        self.mainInbox = mainInbox
        self.spaces = spaces
        self.lifecycle = lifecycle
        self.onSearchInChat = onSearchInChat
        super.init()

        registry.onOpen = { [weak self] target in
            self?.presentWindow(for: target)
        }
        registry.onFocus = { [weak self] target in
            self?.focusWindow(for: target)
        }
        registry.onClose = { [weak self] target in
            self?.closeWindowFromRegistry(for: target)
        }
        lockStateCancellable = lifecycle.$isLocked.sink { [weak self] locked in
            self?.applyLockTitleState(isLocked: locked)
        }
        lockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didLockNotification,
            object: lifecycle,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyLockTitleState(isLocked: true)
            }
        }
        unlockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didUnlockNotification,
            object: lifecycle,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyLockTitleState(isLocked: false)
            }
        }
    }

    deinit {
        if let lockObserver {
            NotificationCenter.default.removeObserver(lockObserver)
        }
        if let unlockObserver {
            NotificationCenter.default.removeObserver(unlockObserver)
        }
    }

    private func applyLockTitleState(isLocked: Bool) {
        let lockedTitle = String(localized: "Courier")
        for (target, window) in windows {
            if isLocked {
                if window.title != lockedTitle {
                    unlockedTitles[target] = window.title
                }
                window.title = lockedTitle
                window.subtitle = ""
            } else if let restored = unlockedTitles[target] {
                window.title = restored
            }
        }
    }

    private func presentWindow(for target: DetachedWindowTarget) {
        if let existing = windows[target] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        guard let session = registry.session(for: target) else { return }

        let contentRect: NSRect
        let title: String
        let controller: NSViewController

        switch target {
        case let .chat(roomID):
            contentRect = NSRect(x: 0, y: 0, width: 720, height: 620)
            let rawName = mainInbox?.row(of: roomID)?.name ?? ""
            title = rawName.isEmpty ? String(localized: "Chat") : rawName
            let view = DetachedChatWindowView(
                session: session,
                lifecycle: lifecycle,
                onOpenDetached: { [weak registry] childTarget in
                    registry?.open(childTarget)
                }
            )
            controller = NSHostingController(rootView: view)

        case let .space(spaceID):
            contentRect = NSRect(x: 0, y: 0, width: 960, height: 660)
            let spaceTitle = spaces?.spaces.first(where: { $0.spaceID == spaceID })?.title
                ?? String(localized: "Space")
            title = spaceTitle
            guard let spaceInbox = session.inbox, let spaces else { return }
            let view = DetachedSpaceWindowView(
                session: session,
                inbox: spaceInbox,
                spaces: spaces,
                lifecycle: lifecycle,
                onOpenDetached: { [weak registry] childTarget in
                    registry?.open(childTarget)
                },
                onSearchInChat: onSearchInChat
            )
            controller = NSHostingController(rootView: view)

        case let .thread(roomID, _):
            contentRect = NSRect(x: 0, y: 0, width: 460, height: 600)
            let rawName = mainInbox?.row(of: roomID)?.name ?? ""
            let chatTitle = rawName.isEmpty ? String(localized: "Chat") : rawName
            title = String(localized: "Thread — \(chatTitle)")
            let view = DetachedThreadWindowView(
                session: session,
                lifecycle: lifecycle
            )
            controller = NSHostingController(rootView: view)
        }

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        unlockedTitles[target] = title
        window.title = lifecycle.isLocked ? String(localized: "Courier") : title
        window.subtitle = ""
        window.identifier = NSUserInterfaceItemIdentifier("courier.detached.\(target.id)")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = controller
        window.center()
        windows[target] = window
        window.makeKeyAndOrderFront(nil)
    }

    private func focusWindow(for target: DetachedWindowTarget) {
        guard let window = windows[target] else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func closeWindowFromRegistry(for target: DetachedWindowTarget) {
        unlockedTitles.removeValue(forKey: target)
        guard let window = windows.removeValue(forKey: target) else { return }
        closingFromRegistry.insert(target)
        window.close()
        closingFromRegistry.remove(target)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        guard let entry = windows.first(where: { $0.value === closingWindow }) else { return }
        let target = entry.key
        unlockedTitles.removeValue(forKey: target)
        windows.removeValue(forKey: target)
        if !closingFromRegistry.contains(target) {
            registry.close(target)
        }
    }
}
