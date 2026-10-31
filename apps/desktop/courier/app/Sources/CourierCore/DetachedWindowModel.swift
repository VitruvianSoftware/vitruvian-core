// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import Foundation

public enum DetachedWindowTarget: Equatable, Hashable, Codable, Identifiable, Sendable {
    case chat(roomID: String)
    case space(spaceID: String)
    case thread(roomID: String, rootEventID: String)

    public var id: String {
        switch self {
        case let .chat(roomID): return "chat:\(roomID)"
        case let .space(spaceID): return "space:\(spaceID)"
        case let .thread(roomID, rootEventID): return "thread:\(roomID):\(rootEventID)"
        }
    }
}

/// Per-window model bundle owned by an open detached window (`01-screens-and-flows.md` §16–18).
/// Closing the detached window removes its session from `DetachedWindowRegistry`, releasing its
/// `ConversationModel`, `ThreadModel`, `MessageActionsModel`, and (for a space window) `InboxModel`.
@MainActor
public final class DetachedWindowSession: ObservableObject {
    public let target: DetachedWindowTarget
    public let appModel: AppModel
    public let lifecycle: SystemLifecycleModel
    public let conversation: ConversationModel
    public let inbox: InboxModel?
    public let hostInbox: InboxModel
    public let composerPreferences: ComposerPreferences
    public let messageActions: MessageActionsModel
    public let scheduled: ScheduledModel
    public let focus: MessageFocus
    public var thread: ThreadModel { conversation.thread }
    public var isLocked: Bool {
        !AppLockGate.shared.canPerform(.other, lifecycle: lifecycle)
    }

    public init(
        target: DetachedWindowTarget,
        appModel: AppModel,
        inboxPreferences: InboxPreferences,
        composerPreferences: ComposerPreferences? = nil,
        mainInbox: InboxModel? = nil,
        quickReplies: QuickReplies? = nil,
        entitlement: (any EntitlementProvider)? = nil,
        pasteboard: TextPasteboard? = nil,
        openURL: (@MainActor (URL) -> Void)? = nil,
        hotkeys: HotkeyRegistry? = nil,
        lifecycle: SystemLifecycleModel? = nil
    ) {
        self.target = target
        self.appModel = appModel
        let resolvedLifecycle = lifecycle ?? mainInbox?.lifecycle ?? appModel.lifecycle
        self.lifecycle = resolvedLifecycle
        let resolvedComposerPrefs = composerPreferences ?? ComposerPreferences()
        self.composerPreferences = resolvedComposerPrefs
        let resolvedEntitlement = entitlement ?? AlwaysEntitled()
        let resolvedQuickReplies = quickReplies ?? QuickReplies()
        let resolvedPasteboard = pasteboard ?? SystemPasteboard()
        let resolvedOpenURL = openURL ?? { url in NSWorkspace.shared.open(url) }
        self.focus = MessageFocus()
        let scheduled = ScheduledModel(appModel: appModel, followsAppSelection: false)
        self.scheduled = scheduled

        switch target {
        case let .chat(roomID):
            self.inbox = nil
            let fallbackInbox = mainInbox ?? InboxModel(
                appModel: appModel,
                preferences: inboxPreferences,
                entitlement: resolvedEntitlement,
                followsAppSelection: false,
                lifecycle: resolvedLifecycle
            )
            self.hostInbox = fallbackInbox
            let conv = ConversationModel(
                appModel: appModel,
                unreadCount: { [weak fallbackInbox] in fallbackInbox?.unreadCount(of: $0) ?? 0 },
                savedDraft: { [weak fallbackInbox] in fallbackInbox?.savedDraft(of: $0) },
                lookUpDraft: { [weak fallbackInbox] in await fallbackInbox?.lookUpDraft($0) },
                chat: { [weak fallbackInbox] in fallbackInbox?.row(of: $0) },
                preferences: resolvedComposerPrefs,
                followsAppSelection: false
            )
            conv.openDetachedRoom(roomID)
            scheduled.openDetachedRoom(roomID)
            self.conversation = conv
            self.messageActions = MessageActionsModel(
                conversation: conv,
                appModel: appModel,
                preferences: resolvedComposerPrefs,
                pasteboard: resolvedPasteboard
            )

        case let .thread(roomID, rootEventID):
            self.inbox = nil
            let fallbackInbox = mainInbox ?? InboxModel(
                appModel: appModel,
                preferences: inboxPreferences,
                entitlement: resolvedEntitlement,
                followsAppSelection: false,
                lifecycle: resolvedLifecycle
            )
            self.hostInbox = fallbackInbox
            let conv = ConversationModel(
                appModel: appModel,
                unreadCount: { [weak fallbackInbox] in fallbackInbox?.unreadCount(of: $0) ?? 0 },
                savedDraft: { [weak fallbackInbox] in fallbackInbox?.savedDraft(of: $0) },
                lookUpDraft: { [weak fallbackInbox] in await fallbackInbox?.lookUpDraft($0) },
                chat: { [weak fallbackInbox] in fallbackInbox?.row(of: $0) },
                preferences: resolvedComposerPrefs,
                followsAppSelection: false
            )
            conv.openDetachedRoom(roomID)
            conv.thread.open(rootEventID, in: roomID)
            scheduled.openDetachedRoom(roomID)
            self.conversation = conv
            self.messageActions = MessageActionsModel(
                conversation: conv,
                appModel: appModel,
                preferences: resolvedComposerPrefs,
                pasteboard: resolvedPasteboard
            )

        case let .space(spaceID):
            let spaceInbox = InboxModel(
                appModel: appModel,
                preferences: inboxPreferences,
                entitlement: resolvedEntitlement,
                followsAppSelection: false,
                lifecycle: resolvedLifecycle
            )
            spaceInbox.query.space = spaceID
            let conv = ConversationModel(
                appModel: appModel,
                unreadCount: { [weak spaceInbox] in spaceInbox?.unreadCount(of: $0) ?? 0 },
                savedDraft: { [weak spaceInbox] in spaceInbox?.savedDraft(of: $0) },
                lookUpDraft: { [weak spaceInbox] in await spaceInbox?.lookUpDraft($0) },
                chat: { [weak spaceInbox] in spaceInbox?.row(of: $0) },
                preferences: resolvedComposerPrefs,
                followsAppSelection: false
            )
            spaceInbox.onSelectDetachedRoom = { [weak conv, weak scheduled] roomID in
                conv?.openDetachedRoom(roomID)
                scheduled?.openDetachedRoom(roomID)
            }
            spaceInbox.isIncognito = { [weak conv] in conv?.incognitoIsOn ?? false }
            spaceInbox.onSelectedRowLookedUp = { [weak conv] row in
                conv?.learnUnreadCount(row.unread, of: row.roomID)
                conv?.learnChat(row)
            }
            spaceInbox.onOpenMergedChat = { [weak conv, weak scheduled] merged in
                conv?.openMergedChat(merged)
                scheduled?.openDetachedRoom(merged.mergeID)
            }
            if let mainInbox {
                spaceInbox.onAddNetwork = { [weak mainInbox] in mainInbox?.onAddNetwork() }
                spaceInbox.onReconnect = { [weak mainInbox] network, accountID in
                    mainInbox?.onReconnect(network, accountID)
                }
            }
            self.inbox = spaceInbox
            self.hostInbox = spaceInbox
            self.conversation = conv
            self.messageActions = MessageActionsModel(
                conversation: conv,
                appModel: appModel,
                preferences: resolvedComposerPrefs,
                pasteboard: resolvedPasteboard
            )
        }

        let host = self.hostInbox
        let conv = self.conversation
        for composer in [conv.composer, conv.thread.composer] {
            composer.entitlement = resolvedEntitlement
            composer.quickReplies = resolvedQuickReplies
            composer.hotkeys = hotkeys
            composer.onArchive = { [weak host] room in await host?.archive(true, ids: [room]) }
            composer.onToast = { [weak host] message in host?.announce(message) }
        }
        conv.onToast = { [weak host] message in host?.announce(message) }
        conv.planAfterToggleRead = { [weak host] in host?.planAfterToggleRead() ?? {} }
        conv.isEntitled = { [weak host] feature in
            host?.isEntitled(feature) ?? resolvedEntitlement.isEntitled(feature)
        }
        self.messageActions.quickReplies = resolvedQuickReplies
        self.messageActions.onToast = { [weak host] message in host?.announce(message) }
        self.messageActions.openURL = resolvedOpenURL
        self.scheduled.onToast = { [weak host] message in host?.announce(message) }
    }
}

@MainActor
public final class DetachedWindowRegistry: ObservableObject {
    @Published public private(set) var openTargets: [DetachedWindowTarget] = []
    @Published public private(set) var focusedTarget: DetachedWindowTarget?

    private var sessions: [DetachedWindowTarget: DetachedWindowSession] = [:]
    private var focusCounts: [DetachedWindowTarget: Int] = [:]
    private weak var appModel: AppModel?
    private weak var mainInbox: InboxModel?
    private weak var explicitLifecycle: SystemLifecycleModel?
    public var lifecycle: SystemLifecycleModel {
        explicitLifecycle ?? mainInbox?.lifecycle ?? appModel?.lifecycle ?? AppLockGate.shared.lifecycle
    }
    public var isLocked: Bool {
        !AppLockGate.shared.canPerform(.other, lifecycle: lifecycle)
    }
    private let inboxPreferences: InboxPreferences
    private let composerPreferences: ComposerPreferences?
    private let quickReplies: QuickReplies?
    private let entitlement: (any EntitlementProvider)?
    private let makePasteboard: (@MainActor () -> TextPasteboard)?
    private let openURL: (@MainActor (URL) -> Void)?
    private weak var hotkeys: HotkeyRegistry?
    private var lifecycleSubscription: AnyCancellable?

    public var onOpen: ((DetachedWindowTarget) -> Void)?
    public var onOpenWindow: ((DetachedWindowTarget) -> Void)? {
        get { onOpen }
        set { onOpen = newValue }
    }
    public var onFocus: ((DetachedWindowTarget) -> Void)?
    public var onClose: ((DetachedWindowTarget) -> Void)?

    public init(
        appModel: AppModel? = nil,
        mainInbox: InboxModel? = nil,
        lifecycle: SystemLifecycleModel? = nil,
        inboxPreferences: InboxPreferences? = nil,
        composerPreferences: ComposerPreferences? = nil,
        quickReplies: QuickReplies? = nil,
        entitlement: (any EntitlementProvider)? = nil,
        makePasteboard: (@MainActor () -> TextPasteboard)? = nil,
        openURL: (@MainActor (URL) -> Void)? = nil,
        hotkeys: HotkeyRegistry? = nil,
        onOpen: ((DetachedWindowTarget) -> Void)? = nil,
        onFocus: ((DetachedWindowTarget) -> Void)? = nil,
        onClose: ((DetachedWindowTarget) -> Void)? = nil
    ) {
        self.appModel = appModel
        self.mainInbox = mainInbox
        self.explicitLifecycle = lifecycle
        self.inboxPreferences = inboxPreferences ?? mainInbox?.preferences ?? InboxPreferences()
        self.composerPreferences = composerPreferences
        self.quickReplies = quickReplies
        self.entitlement = entitlement
        self.makePasteboard = makePasteboard
        self.openURL = openURL
        self.hotkeys = hotkeys
        self.onOpen = onOpen
        self.onFocus = onFocus
        self.onClose = onClose
        let resolvedLifecycle = lifecycle ?? mainInbox?.lifecycle ?? appModel?.lifecycle ?? AppLockGate.shared.lifecycle
        self.lifecycleSubscription = resolvedLifecycle.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public func open(_ target: DetachedWindowTarget) {
        guard !isLocked else { return }
        if openTargets.contains(target) {
            focusCounts[target, default: 0] += 1
            focusedTarget = target
            onFocus?(target)
            return
        }
        if let appModel {
            sessions[target] = DetachedWindowSession(
                target: target,
                appModel: appModel,
                inboxPreferences: inboxPreferences,
                composerPreferences: composerPreferences,
                mainInbox: mainInbox,
                quickReplies: quickReplies,
                entitlement: entitlement,
                pasteboard: makePasteboard?(),
                openURL: openURL,
                hotkeys: hotkeys,
                lifecycle: lifecycle
            )
        }
        openTargets.append(target)
        focusCounts[target] = 1
        focusedTarget = target
        onOpen?(target)
        onFocus?(target)
    }

    public func close(_ target: DetachedWindowTarget) {
        let wasOpen = openTargets.contains(target)
        openTargets.removeAll { $0 == target }
        sessions.removeValue(forKey: target)
        focusCounts.removeValue(forKey: target)
        if focusedTarget == target {
            focusedTarget = openTargets.last
        }
        if wasOpen {
            onClose?(target)
        }
    }

    public func closeAll() {
        let closing = openTargets
        openTargets.removeAll()
        sessions.removeAll()
        focusCounts.removeAll()
        focusedTarget = nil
        for target in closing {
            onClose?(target)
        }
    }

    public func session(for target: DetachedWindowTarget) -> DetachedWindowSession? {
        sessions[target]
    }

    public func focusCount(for target: DetachedWindowTarget) -> Int {
        focusCounts[target] ?? 0
    }

    /// Whether the detached window for `target` is covered by the app lock overlay (`SystemLifecycleModel.isLocked`).
    public func showsLockOverlay(for target: DetachedWindowTarget) -> Bool {
        guard openTargets.contains(target) else { return false }
        return isLocked
    }
}
