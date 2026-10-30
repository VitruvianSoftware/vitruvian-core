// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

private final class DetachedSessionPasteboard: TextPasteboard {
    var lastCopied: String?
    func setString(_ text: String) {
        lastCopied = text
    }
}

public enum DetachedWindowTarget: Equatable, Hashable, Identifiable, Sendable {
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
    public let conversation: ConversationModel
    public let inbox: InboxModel?
    public let hostInbox: InboxModel
    public let composerPreferences: ComposerPreferences
    public let messageActions: MessageActionsModel
    public let scheduled: ScheduledModel
    public let focus: MessageFocus
    public var thread: ThreadModel { conversation.thread }

    public init(
        target: DetachedWindowTarget,
        appModel: AppModel,
        inboxPreferences: InboxPreferences,
        composerPreferences: ComposerPreferences? = nil,
        mainInbox: InboxModel? = nil,
        pasteboard: TextPasteboard? = nil
    ) {
        self.target = target
        self.appModel = appModel
        let resolvedComposerPrefs = composerPreferences ?? ComposerPreferences()
        self.composerPreferences = resolvedComposerPrefs
        self.focus = MessageFocus()
        self.scheduled = ScheduledModel(appModel: appModel)

        switch target {
        case let .chat(roomID):
            self.inbox = nil
            let fallbackInbox = mainInbox ?? InboxModel(
                appModel: appModel,
                preferences: inboxPreferences,
                followsAppSelection: false
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
            self.conversation = conv
            self.messageActions = MessageActionsModel(
                conversation: conv,
                appModel: appModel,
                preferences: resolvedComposerPrefs,
                pasteboard: pasteboard ?? DetachedSessionPasteboard()
            )

        case let .thread(roomID, rootEventID):
            self.inbox = nil
            let fallbackInbox = mainInbox ?? InboxModel(
                appModel: appModel,
                preferences: inboxPreferences,
                followsAppSelection: false
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
            self.conversation = conv
            self.messageActions = MessageActionsModel(
                conversation: conv,
                appModel: appModel,
                preferences: resolvedComposerPrefs,
                pasteboard: pasteboard ?? DetachedSessionPasteboard()
            )

        case let .space(spaceID):
            let spaceInbox = InboxModel(
                appModel: appModel,
                preferences: inboxPreferences,
                followsAppSelection: false
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
            spaceInbox.onSelectDetachedRoom = { [weak conv] roomID in
                conv?.openDetachedRoom(roomID)
            }
            self.inbox = spaceInbox
            self.hostInbox = spaceInbox
            self.conversation = conv
            self.messageActions = MessageActionsModel(
                conversation: conv,
                appModel: appModel,
                preferences: resolvedComposerPrefs,
                pasteboard: pasteboard ?? DetachedSessionPasteboard()
            )
        }
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
    private weak var lifecycle: SystemLifecycleModel?
    private let inboxPreferences: InboxPreferences
    private let composerPreferences: ComposerPreferences?
    private var lifecycleSubscription: AnyCancellable?

    public var onOpen: ((DetachedWindowTarget) -> Void)?
    public var onFocus: ((DetachedWindowTarget) -> Void)?
    public var onClose: ((DetachedWindowTarget) -> Void)?

    public init(
        appModel: AppModel? = nil,
        mainInbox: InboxModel? = nil,
        lifecycle: SystemLifecycleModel? = nil,
        inboxPreferences: InboxPreferences? = nil,
        composerPreferences: ComposerPreferences? = nil,
        onOpen: ((DetachedWindowTarget) -> Void)? = nil,
        onFocus: ((DetachedWindowTarget) -> Void)? = nil,
        onClose: ((DetachedWindowTarget) -> Void)? = nil
    ) {
        self.appModel = appModel
        self.mainInbox = mainInbox
        self.lifecycle = lifecycle
        self.inboxPreferences = inboxPreferences ?? mainInbox?.preferences ?? InboxPreferences()
        self.composerPreferences = composerPreferences
        self.onOpen = onOpen
        self.onFocus = onFocus
        self.onClose = onClose
        if let lifecycle {
            self.lifecycleSubscription = lifecycle.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }

    public func open(_ target: DetachedWindowTarget) {
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
                mainInbox: mainInbox
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
        return lifecycle?.isLocked ?? false
    }
}
