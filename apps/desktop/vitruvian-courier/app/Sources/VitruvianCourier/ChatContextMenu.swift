// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// A chat's right-click menu (02 §3.4.1, the 4.1 part), in its order. It acts on `ids`, the chats it was opened
/// on; nil is the chats selected. The items and their order are `ChatMenuPlan`'s, and what each does is
/// `ChatMenuActions`'. This SwiftUI form is the menu under the hover button; a right-click opens the same plan as a
/// native `NSMenu` (`ChatNativeContextMenu`), which leaves out the system's own "Ask Siri" item.
struct ChatContextMenu: View {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    let ui: InboxUI
    let ids: [String]?
    /// Whether the items show their keys. A right-click menu does; the hover button's menu doesn't, since a menu
    /// in a button would take those keys from the Chat menu while the pointer is on the row.
    var showsKeys = true
    var features: ChatFeatures? = nil
    /// The conversation pane's model, whose sheets Edit Chat… and Report as Spam… open.
    var conversation: ConversationModel? = nil
    var onEditChat: ((String) -> Void)? = nil
    var onLeaveGroup: ((String) -> Void)? = nil
    var onDeleteChat: ((String) -> Void)? = nil
    var onReportSpam: ((String) -> Void)? = nil
    var onOpenInNewWindow: ((String) -> Void)? = nil
    var onCustomizeChatTheme: ((String) -> Void)? = nil
    @Environment(\.searchInChat) private var searchInChat
    @Environment(\.openDetachedWindow) private var openDetachedWindow
    @Environment(\.openWindow) private var openWindow

    private var actions: ChatMenuActions {
        var actions = ChatMenuActions(inbox: inbox, spaces: spaces, ui: ui, ids: ids, showsKeys: showsKeys)
        actions.features = features
        actions.conversation = conversation
        actions.onEditChat = onEditChat
        actions.onLeaveGroup = onLeaveGroup
        actions.onDeleteChat = onDeleteChat
        actions.onReportSpam = onReportSpam
        actions.onOpenInNewWindow = onOpenInNewWindow
        actions.onCustomizeChatTheme = onCustomizeChatTheme
        actions.searchInChat = searchInChat
        actions.openDetachedWindow = openDetachedWindow
        actions.openLabelWindow = { openWindow(id: WindowID.label, value: $0) }
        actions.openThemeWindow = { openWindow(id: WindowID.chatTheme, value: $0) }
        return actions
    }

    var body: some View {
        let actions = self.actions
        let sections = actions.sections()
        ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
            if index > 0 { Divider() }
            ForEach(section) { item in
                ChatMenuItemView(item: item) { actions.run($0) }
            }
        }
    }
}

/// One planned menu item as SwiftUI draws it (the hover button's menu).
private struct ChatMenuItemView: View {
    let item: ChatMenuItem
    let run: (ChatMenuCommand) -> Void

    var body: some View {
        if !item.children.isEmpty {
            Menu(item.title) {
                ForEach(item.children) { child in
                    ChatMenuItemView(item: child, run: run)
                }
            }
            .help(item.help ?? "")
        } else if let command = item.command {
            if item.isOn || item.id.hasPrefix("label:") {
                Toggle(item.title, isOn: Binding(get: { item.isOn }, set: { _ in run(command) }))
            } else {
                Button(item.title, role: item.isDestructive ? .destructive : nil) { run(command) }
                    .disabled(!item.isEnabled)
                    .help(item.help ?? "")
                    .modifier(ChatMenuKeyModifier(key: item.key))
            }
        } else if item.isEnabled {
            Text(item.title)
        } else {
            Button(item.title) {}.disabled(true)
        }
    }
}

private struct ChatMenuKeyModifier: ViewModifier {
    let key: ChatMenuKey?

    func body(content: Content) -> some View {
        if let key, let character = key.key.first {
            content.keyboardShortcut(KeyEquivalent(character), modifiers: key.shift ? [.command, .shift] : .command)
        } else {
            content
        }
    }
}

/// What a chat menu's context holds and what its items do. Shared by the SwiftUI and the native forms, so a right-click
/// and the hover button's menu can never differ.
@MainActor
struct ChatMenuActions {
    let inbox: InboxModel
    let spaces: SpacesModel
    let ui: InboxUI
    let ids: [String]?
    var showsKeys = true
    /// The chat's features when the caller already has them (Chat Info does); else what the inbox has asked the engine.
    var features: ChatFeatures?
    var conversation: ConversationModel?
    var onEditChat: ((String) -> Void)?
    var onLeaveGroup: ((String) -> Void)?
    var onDeleteChat: ((String) -> Void)?
    var onReportSpam: ((String) -> Void)?
    var onOpenInNewWindow: ((String) -> Void)?
    var onCustomizeChatTheme: ((String) -> Void)?
    var searchInChat: (@MainActor (String) -> Void)?
    var openDetachedWindow: (@MainActor (DetachedWindowTarget) -> Void)?
    var openLabelWindow: ((LabelWindowTarget) -> Void)?
    var openThemeWindow: ((ChatThemeWindowTarget) -> Void)?

    init(inbox: InboxModel, spaces: SpacesModel, ui: InboxUI, ids: [String]?, showsKeys: Bool = true) {
        self.inbox = inbox
        self.spaces = spaces
        self.ui = ui
        self.ids = ids
        self.showsKeys = showsKeys
    }

    var rows: [InboxRow] { inbox.targetRows(ids) }

    func context() -> ChatMenuContext {
        let rows = rows
        var context = ChatMenuContext(rows: rows)
        context.accounts = inbox.accounts
        context.isSelecting = inbox.isSelecting
        context.showsKeys = showsKeys
        context.lowPriorityEntitled = inbox.isEntitled(.lowPriority)
        context.remindersEntitled = inbox.isEntitled(.reminders)
        if context.remindersEntitled {
            context.reminderPresets = ReminderPresets.presets(
                now: Date(), calendar: .current, lastUsed: inbox.preferences.lastUsedReminder,
                suggestions: inbox.preferences.timeSuggestions
            ).map(\.title)
        }
        context.labels = spaces.spaces.filter { $0.kind == .label }.map { ($0.labelID, $0.title) }
        context.canSearchInChat = searchInChat != nil
        context.isMerged = { inbox.mergedChat(for: $0) != nil }
        let known = features
        context.features = { row in known ?? inbox.cachedFeatures(for: row.roomID) }
        context.chatName = { inbox.displayTitle(for: $0) }
        context.canLeaveGroups = onLeaveGroup != nil
        // A chat whose network hasn't been asked what it can do is asked now, for the next menu.
        if rows.count == 1, features == nil { inbox.prefetchFeatures(for: rows[0]) }
        return context
    }

    func sections() -> [[ChatMenuItem]] {
        ChatMenuPlan.sections(context())
    }

    /// A native menu is built on the spot, so a chat whose network hasn't been asked yet is asked first.
    var isCold: Bool {
        guard features == nil, let row = rows.first, rows.count == 1, row.mergeID.isEmpty else { return false }
        return inbox.cachedFeatures(for: row.roomID) == nil
    }

    /// Gives a cold menu a moment (up to 150 ms) to learn what the chat's network can do.
    func warmUp() async {
        guard isCold, let row = rows.first else { return }
        _ = await inbox.featuresWaiting(for: row.roomID, upTo: ChatMenuActions.warmUpLimit)
    }

    static let warmUpLimit: TimeInterval = 0.15

    func run(_ command: ChatMenuCommand) {
        let inbox = inbox
        let ids = ids
        switch command {
        case .accept: Task { await inbox.acceptRequest(ids: ids) }
        case .decline: Task { await inbox.declineRequest(ids: ids) }
        case let .archive(on): Task { await inbox.archive(on, ids: ids) }
        case .mute: Task { await inbox.toggleMute(ids: ids) }
        case let .markRead(read): Task { await inbox.setRead(read, ids: ids) }
        case .pin: Task { await inbox.togglePin(ids: ids) }
        case let .searchInChat(roomID): searchInChat?(roomID)
        case let .hide(on): Task { await inbox.setHidden(on, ids: ids) }
        case let .lowPriority(on): Task { await inbox.setLowPriority(on, ids: ids) }
        case let .toggleLabel(id, on): Task { await inbox.setLabel(id, on: on, ids: ids) }
        case .newLabel: openLabelWindow?(LabelWindowTarget.new(applyTo: ids ?? inbox.targets))
        case let .remind(title): RemindMeItems.remind(title, inbox: inbox, ids: ids)
        case .remindCustom:
            let request = ReminderRequest(ids: ids ?? inbox.targets)
            inbox.customReminder = request
            ui.customReminder = request
        case .dismissReminder: Task { await inbox.dismissReminder(ids: ids) }
        case let .openInNewWindow(roomID):
            if let onOpenInNewWindow { onOpenInNewWindow(roomID) } else { openDetachedWindow?(.chat(roomID: roomID)) }
        case let .chatTheme(roomID, title):
            if let onCustomizeChatTheme {
                onCustomizeChatTheme(roomID)
            } else {
                openThemeWindow?(ChatThemeWindowTarget(roomID: roomID, chatTitle: title))
            }
        case let .copyChatName(name), let .copyChatLink(name):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(name, forType: .string)
        case .beginSelecting:
            // Selecting starts with the chats right-clicked, not the open one.
            inbox.beginSelecting()
            if let ids {
                for id in inbox.selection where !ids.contains(id) { inbox.toggleSelected(id) }
                for id in ids where !inbox.selection.contains(id) { inbox.toggleSelected(id) }
            }
        case .mergeChat:
            if let row = rows.first { inbox.openMergeEditor(for: row) }
        case let .editChat(roomID):
            if let onEditChat {
                onEditChat(roomID)
            } else if let conversation {
                Task { await ChatRoomActions.editChat(roomID: roomID, conversation: conversation) }
            }
        case let .leaveGroup(roomID): onLeaveGroup?(roomID)
        case let .deleteChat(roomID):
            if let onDeleteChat { onDeleteChat(roomID) } else { confirmAndDelete(roomID) }
        case let .reportSpam(roomID):
            if let onReportSpam {
                onReportSpam(roomID)
            } else if let conversation {
                Task { await ChatRoomActions.reportSpam(roomID: roomID, conversation: conversation) }
            }
        }
    }

    /// Delete Chat…: finds out whether the chat's network can delete it (the menu shows the item until the network
    /// has said it can't), asks first, then deletes through the engine.
    private func confirmAndDelete(_ roomID: String) {
        guard let row = inbox.targetRows([roomID]).first else { return }
        let features = features
        let networkName = inbox.networkName(row.network)
        let chatName = inbox.displayTitle(for: row)
        Task {
            let resolution: InboxModel.DeleteResolution
            if let features {
                resolution = features.canDelete ? .ask(features) : .unsupported
            } else {
                resolution = await inbox.resolveDelete(roomID: roomID)
            }
            guard case let .ask(known) = resolution else {
                Confirm.tell(ChatDeleteConfirmation.unavailable(resolution, networkName: networkName))
                return
            }
            let text = ChatDeleteConfirmation.text(chatName: chatName, networkName: networkName, features: known)
            guard Confirm.ask(text.title, detail: text.detail, action: String(localized: "Delete"), destructive: true) else {
                return
            }
            await inbox.deleteChat(roomID: roomID)
        }
    }
}

/// A chat's right-click menu as a native `NSMenu`, built from the plan, so the system's "Ask Siri" and other
/// context-menu plug-ins are left out (`allowsContextMenuPlugIns = false`, as the message menu does).
@MainActor
enum ChatContextNSMenu {
    static func build(_ sections: [[ChatMenuItem]], run: @escaping (ChatMenuCommand) -> Void) -> NSMenu? {
        guard !sections.isEmpty else { return nil }
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        menu.autoenablesItems = false
        for (index, section) in sections.enumerated() where !section.isEmpty {
            if index > 0, menu.numberOfItems > 0 { menu.addItem(.separator()) }
            for item in section { menu.addItem(makeItem(item, run: run)) }
        }
        return menu
    }

    private static func makeItem(_ item: ChatMenuItem, run: @escaping (ChatMenuCommand) -> Void) -> NSMenuItem {
        if !item.children.isEmpty {
            let parent = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: item.title)
            sub.allowsContextMenuPlugIns = false
            sub.autoenablesItems = false
            for child in item.children { sub.addItem(makeItem(child, run: run)) }
            parent.submenu = sub
            parent.toolTip = item.help
            return parent
        }
        let enabled = item.isEnabled && item.command != nil
        let nsItem = NSMenuItem(
            title: item.title,
            action: enabled ? #selector(MessageContextMenuBuilder.ActionTarget.invoke(_:)) : nil,
            keyEquivalent: ""
        )
        if enabled, let command = item.command {
            let target = MessageContextMenuBuilder.ActionTarget { run(command) }
            nsItem.target = target
            // Held by the item for as long as the menu lives.
            nsItem.representedObject = target
        }
        nsItem.isEnabled = enabled
        nsItem.state = item.isOn ? .on : .off
        nsItem.toolTip = item.help
        if let key = item.key {
            nsItem.keyEquivalent = key.key
            var mask: NSEvent.ModifierFlags = []
            if key.command { mask.insert(.command) }
            if key.shift { mask.insert(.shift) }
            nsItem.keyEquivalentModifierMask = mask
        }
        return nsItem
    }
}

/// Opens `makeMenu`'s menu on a right-click (or control-click) of the view it covers, and lets every other event
/// through, as `MessageContextMenuOverlay` does for a message. A menu that is `isCold` (it doesn't yet know what the
/// chat's network can do) gets a moment to find out first, then opens where the click was.
struct ChatNativeContextMenu: NSViewRepresentable {
    let makeMenu: @MainActor () -> NSMenu?
    var isCold: @MainActor () -> Bool = { false }
    var warmUp: @MainActor () async -> Void = {}

    func makeNSView(context _: Context) -> CatcherView {
        let view = CatcherView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: CatcherView, context _: Context) {
        apply(to: nsView)
    }

    private func apply(to view: CatcherView) {
        view.makeMenu = makeMenu
        view.isCold = isCold
        view.warmUp = warmUp
    }

    final class CatcherView: NSView {
        var makeMenu: (@MainActor () -> NSMenu?)?
        var isCold: (@MainActor () -> Bool)?
        var warmUp: (@MainActor () async -> Void)?
        /// Shows a menu where the click was; a test records it.
        var present: @MainActor (NSMenu, NSPoint, NSView) -> Void = { menu, point, view in
            menu.popUp(positioning: nil, at: point, in: view)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown
                      || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            else { return nil }
            return super.hitTest(point)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard isCold?() == true else { return makeMenu?() }
            // Cold: wait a moment for the network's answer, then open the menu where the click was.
            let point = convert(event.locationInWindow, from: nil)
            Task { @MainActor [weak self] in
                await self?.warmUp?()
                guard let self, let menu = self.makeMenu?() else { return }
                self.present(menu, point, self)
            }
            return nil
        }
    }
}

/// A chat row's right-click menu: the native form of `ChatContextMenu`'s plan.
private struct ChatRowContextMenu: ViewModifier {
    let inbox: InboxModel
    let spaces: SpacesModel
    let ui: InboxUI
    let ids: () -> [String]?
    let conversation: ConversationModel?
    @Environment(\.searchInChat) private var searchInChat
    @Environment(\.openDetachedWindow) private var openDetachedWindow
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.overlay(ChatNativeContextMenu(makeMenu: { buildMenu() }, isCold: { actions().isCold },
                                              warmUp: { await actions().warmUp() }))
    }

    @MainActor
    private func actions() -> ChatMenuActions {
        var actions = ChatMenuActions(inbox: inbox, spaces: spaces, ui: ui, ids: ids())
        actions.conversation = conversation
        actions.searchInChat = searchInChat
        actions.openDetachedWindow = openDetachedWindow
        actions.openLabelWindow = { openWindow(id: WindowID.label, value: $0) }
        actions.openThemeWindow = { openWindow(id: WindowID.chatTheme, value: $0) }
        return actions
    }

    @MainActor
    private func buildMenu() -> NSMenu? {
        let actions = actions()
        return ChatContextNSMenu.build(actions.sections()) { actions.run($0) }
    }
}

extension View {
    /// Right-clicking this chat row or tile opens the chat menu as a native menu. `ids` says which chats it acts on
    /// (nil: the chats selected), read when the menu opens.
    func chatRowContextMenu(inbox: InboxModel, spaces: SpacesModel, ui: InboxUI, conversation: ConversationModel? = nil,
                            ids: @escaping () -> [String]?) -> some View {
        modifier(ChatRowContextMenu(inbox: inbox, spaces: spaces, ui: ui, ids: ids, conversation: conversation))
    }
}

/// Single-chat room management actions in `ChatContextMenu` (Task 10):
/// **Edit Chat…** / **Edit Group…**, **Leave Group…** (when `!row.isDirect && features.canLeave`),
/// **Delete Chat…** (when `features.canDelete`), and **Report as Spam…**.
public struct ChatRoomManagementMenuSection: View {
    public let row: InboxRow
    public var features: ChatFeatures?
    public var onEditChat: ((String) -> Void)?
    public var onLeaveGroup: ((String) -> Void)?
    public var onDeleteChat: ((String) -> Void)?
    public var onReportSpam: ((String) -> Void)?

    public init(
        row: InboxRow,
        features: ChatFeatures? = nil,
        onEditChat: ((String) -> Void)? = nil,
        onLeaveGroup: ((String) -> Void)? = nil,
        onDeleteChat: ((String) -> Void)? = nil,
        onReportSpam: ((String) -> Void)? = nil
    ) {
        self.row = row
        self.features = features
        self.onEditChat = onEditChat
        self.onLeaveGroup = onLeaveGroup
        self.onDeleteChat = onDeleteChat
        self.onReportSpam = onReportSpam
    }

    public var body: some View {
        Button(row.isDirect ? String(localized: "Edit Chat…") : String(localized: "Edit Group…")) {
            onEditChat?(row.roomID)
        }
        if let features, !row.isDirect, features.canLeave {
            Button(String(localized: "Leave Group…"), role: .destructive) {
                onLeaveGroup?(row.roomID)
            }
        }
        if let features, features.canDelete {
            Button(String(localized: "Delete Chat…"), role: .destructive) {
                onDeleteChat?(row.roomID)
            }
        }
        Button(String(localized: "Report as Spam…"), role: .destructive) {
            onReportSpam?(row.roomID)
        }
    }
}

/// Label ▸: each label, ticked when every chat has it, and New Label….
struct LabelMenu: View {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    let ids: [String]?
    let rows: [InboxRow]
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu(String(localized: "Label")) {
            ForEach(spaces.spaces.filter { $0.kind == .label }) { label in
                let has = !rows.isEmpty && rows.allSatisfy { $0.labels.contains(label.labelID) }
                Toggle(label.title, isOn: Binding(get: { has }, set: { on in
                    Task { await inbox.setLabel(label.labelID, on: on, ids: ids) }
                }))
            }
            Divider()
            Button(String(localized: "New Label…")) {
                openWindow(id: WindowID.label, value: LabelWindowTarget.new(applyTo: ids ?? inbox.targets))
            }
        }
        .help(String(localized: "A label puts the chat in a space of its own, on this Mac."))
    }
}

/// Asking before doing something to many chats, and saying what went wrong.
@MainActor
enum Confirm {
    /// A yes-or-no question: true for `action`, false for Cancel.
    static func ask(_ message: String, detail: String? = nil, action: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail ?? ""
        let button = alert.addButton(withTitle: action)
        button.hasDestructiveAction = destructive
        alert.addButton(withTitle: String(localized: "Cancel"))
        return AppLockGate.shared.runAlertModal(alert) == .alertFirstButtonReturn
    }

    static func tell(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: String(localized: "OK"))
        _ = AppLockGate.shared.runAlertModal(alert)
    }

    /// Runs a command, after its confirmation when it has one (a bulk command): only an OK runs it.
    static func run(_ command: CourierCommand) {
        guard command.isEnabled() else { return }
        if let question = command.confirmation {
            guard ask(question, action: command.title) else { return }
        }
        command.run()
    }

    /// ⌘⇧E: "Archive N read chats?" for the space shown, counted as below.
    static func archiveAllRead(_ inbox: InboxModel) async {
        guard inbox.canArchiveAll else { return }
        await sweep(inbox, readOnly: true)
    }

    /// An archive-all: counts it with a dry run of the same sweep, asks "Archive N chats?" ("Archive N read
    /// chats?"), and archives only on OK, with Undo in the toast. With none to archive it beeps; when the count
    /// can't be had it asks without one. `space` nil is the space shown.
    static func sweep(_ inbox: InboxModel, readOnly: Bool, olderThanDays days: Int = 0, space: String? = nil) async {
        let question: String
        var detail: String? = String(localized: "Pinned chats stay where they are. You can undo this.")
        switch await inbox.archiveAllCount(readOnly: readOnly, olderThanDays: days, space: space) {
        case 0?:
            NSSound.beep()
            return
        case let count?:
            switch (readOnly, count) {
            case (true, 1): question = String(localized: "Archive 1 read chat?")
            case (true, _): question = String(localized: "Archive \(count) read chats?")
            case (false, 1): question = String(localized: "Archive 1 chat?")
            case (false, _): question = String(localized: "Archive \(count) chats?")
            }
        case nil:
            question = String(localized: "Archive these chats? Pinned chats stay where they are. You can undo this.")
            detail = nil
        }
        guard ask(question, detail: detail, action: String(localized: "Archive")) else { return }
        _ = await inbox.archiveAll(readOnly: readOnly, olderThanDays: days, space: space)
    }
}

extension View {
    /// A key shown on a menu item, when `shown`.
    @ViewBuilder
    func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers, if shown: Bool) -> some View {
        if shown { keyboardShortcut(key, modifiers: modifiers) } else { self }
    }
}
