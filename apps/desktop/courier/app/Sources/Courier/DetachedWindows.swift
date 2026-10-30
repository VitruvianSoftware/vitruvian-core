// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
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
        .overlay {
            if lifecycle.isLocked {
                AppLockOverlay(model: lifecycle)
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

    init(
        session: DetachedWindowSession,
        inbox: InboxModel,
        spaces: SpacesModel,
        lifecycle: SystemLifecycleModel,
        onOpenDetached: ((DetachedWindowTarget) -> Void)? = nil
    ) {
        self.session = session
        self.inbox = inbox
        self.conversation = session.conversation
        self.spaces = spaces
        self.lifecycle = lifecycle
        self.onOpenDetached = onOpenDetached
    }

    var body: some View {
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
        .frame(minWidth: 740, minHeight: 460)
        .overlay {
            if lifecycle.isLocked {
                AppLockOverlay(model: lifecycle)
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
    @ObservedObject var lifecycle: SystemLifecycleModel

    init(
        session: DetachedWindowSession,
        lifecycle: SystemLifecycleModel
    ) {
        self.session = session
        self.conversation = session.conversation
        self.thread = session.thread
        self.lifecycle = lifecycle
    }

    var body: some View {
        ThreadPane(
            thread: thread,
            conversation: conversation,
            composer: thread.composer,
            messageActions: session.messageActions,
            preferences: session.composerPreferences,
            focus: session.focus,
            showsOpenInNewWindowButton: false
        )
        .frame(minWidth: 380, minHeight: 440)
        .overlay {
            if lifecycle.isLocked {
                AppLockOverlay(model: lifecycle)
            }
        }
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
    private var windows: [DetachedWindowTarget: NSWindow] = [:]
    private var closingFromRegistry = Set<DetachedWindowTarget>()

    init(
        registry: DetachedWindowRegistry,
        appModel: AppModel,
        mainInbox: InboxModel,
        spaces: SpacesModel,
        lifecycle: SystemLifecycleModel
    ) {
        self.registry = registry
        self.appModel = appModel
        self.mainInbox = mainInbox
        self.spaces = spaces
        self.lifecycle = lifecycle
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
                }
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
        window.title = title
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
        guard let window = windows.removeValue(forKey: target) else { return }
        closingFromRegistry.insert(target)
        window.close()
        closingFromRegistry.remove(target)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        guard let entry = windows.first(where: { $0.value === closingWindow }) else { return }
        let target = entry.key
        windows.removeValue(forKey: target)
        if !closingFromRegistry.contains(target) {
            registry.close(target)
        }
    }
}
