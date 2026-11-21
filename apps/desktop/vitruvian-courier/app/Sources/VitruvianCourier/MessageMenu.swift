// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// A message's menu (02 §3.4.2's order, with secondary items in a "More" submenu), from `MessageMenu.sections`:
/// the sections a divider apart, each item with its key, a greyed one with why as its tooltip, and the greyed lines
/// that only say something.
@MainActor
struct MessageMenuItems: View {
    private let makeSections: () -> [[MessageMenuItem]]
    @ObservedObject var hotkeys: HotkeyRegistry
    var hotkeyDispatcher: HotkeyDispatcher? = nil
    let choose: (MessageMenuItem.Command) -> Void

    init(
        sections: @autoclosure @escaping () -> [[MessageMenuItem]],
        hotkeys: HotkeyRegistry? = nil,
        hotkeyDispatcher: HotkeyDispatcher? = nil,
        choose: @escaping (MessageMenuItem.Command) -> Void
    ) {
        self.makeSections = sections
        self._hotkeys = ObservedObject(wrappedValue: hotkeys ?? MessageRowActions.sharedFallbackHotkeys)
        self.hotkeyDispatcher = hotkeyDispatcher
        self.choose = choose
    }

    var body: some View {
        let sections = makeSections()
        ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
            if index > 0 { Divider() }
            ForEach(section) { item in
                menuElement(item)
            }
        }
    }

    private func menuElement(_ item: MessageMenuItem) -> AnyView {
        let locked = hotkeyDispatcher?.lifecycle.isLocked == true
        let enabled = item.isEnabled && !locked
        if !item.children.isEmpty {
            return AnyView(
                Menu(item.title) {
                    ForEach(item.children) { child in
                        menuElement(child)
                    }
                }
                .disabled(!enabled)
                .help(item.help ?? "")
            )
        }
        return AnyView(leafButton(item, locked: locked))
    }

    @ViewBuilder
    private func leafButton(_ item: MessageMenuItem, locked: Bool) -> some View {
        let enabled = item.isEnabled && !locked
        if let key = item.key {
            if let hotkeyID = key.hotkeyID {
                Button(item.title) {
                    guard !locked else { return }
                    choose(item.command)
                }
                .registryShortcut(hotkeyID, in: hotkeys)
                // Do not gate context-menu items on HotkeyDispatcher.canPerform (which requires an already-selected
                // message); a context menu targets the clicked message directly.
                .disabled(!enabled)
                .help(item.help ?? "")
            } else {
                Button(item.title) {
                    guard !locked else { return }
                    choose(item.command)
                }
                .keyboardShortcut(key.shortcut)
                .disabled(!enabled)
                .help(item.help ?? "")
            }
        } else {
            Button(item.title) {
                guard !locked else { return }
                choose(item.command)
            }
            .disabled(!enabled)
            .help(item.help ?? "")
        }
    }
}

/// The same menu as a list, for a double click set to "Show the menu", and for the snapshots: what the context
/// menu holds, drawn where it can be seen.
struct MessageMenuList: View {
    let sections: [[MessageMenuItem]]
    let choose: (MessageMenuItem.Command) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if index > 0 { Divider().padding(.vertical, 4) }
                ForEach(section) { item in
                    rowView(item)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 240)
    }

    private func rowView(_ item: MessageMenuItem) -> AnyView {
        if !item.children.isEmpty {
            return AnyView(
                Menu {
                    ForEach(item.children) { child in
                        submenuElement(child)
                    }
                } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .foregroundStyle(item.isEnabled ? .primary : .secondary)
                            if let help = item.help {
                                Text(help).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
            )
        }
        return AnyView(
            Button { choose(item.command) } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .foregroundStyle(item.isEnabled ? .primary : .secondary)
                        if let help = item.help {
                            Text(help).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let key = item.key {
                        Text(key.symbols).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!item.isEnabled)
        )
    }

    private func submenuElement(_ item: MessageMenuItem) -> AnyView {
        if !item.children.isEmpty {
            return AnyView(
                Menu(item.title) {
                    ForEach(item.children) { child in
                        submenuElement(child)
                    }
                }
                .disabled(!item.isEnabled)
            )
        }
        return AnyView(
            Button(item.title) {
                choose(item.command)
            }
            .disabled(!item.isEnabled)
        )
    }
}

/// Native AppKit `NSMenu` builder and presenter for message right-click and hover-pill "More" menus.
///
/// Sets `allowsContextMenuPlugIns = false` (suppressing system "Ask Siri" / Services plug-ins) and
/// `autoenablesItems = false` (preventing AppKit's responder chain from disabling items like Reply on unselected rows).
@MainActor
enum MessageContextMenuBuilder {
    final class ActionTarget: NSObject {
        private let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func invoke(_: Any?) { run() }
    }

    static func buildNSMenu(for message: TimelineMessage, actions: MessageActions) -> NSMenu? {
        let isLocked = actions.hotkeyDispatcher?.lifecycle.isLocked == true
        guard !isLocked else { return nil }
        let sections = actions.menu(message)
        let hotkeys = actions.hotkeys ?? MessageRowActions.sharedFallbackHotkeys
        return buildNSMenu(sections: sections, hotkeys: hotkeys, isLocked: isLocked) { command in
            actions.perform(command, message.id)
        }
    }

    static func buildNSMenu(
        sections: [[MessageMenuItem]],
        hotkeys: HotkeyRegistry,
        isLocked: Bool,
        choose: @escaping (MessageMenuItem.Command) -> Void
    ) -> NSMenu? {
        guard !sections.isEmpty, !isLocked else { return nil }
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        menu.autoenablesItems = false
        for (index, section) in sections.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for item in section {
                menu.addItem(makeMenuItem(item, hotkeys: hotkeys, isLocked: isLocked, choose: choose))
            }
        }
        return menu
    }

    /// The More button's action: the same menu a right-click on the message builds, shown below `anchor`. `isOpen`
    /// says true as it opens and false once it has closed (the row keeps its hover pill while it is open).
    static func present(for message: TimelineMessage, actions: MessageActions, anchor: NSView?,
                        isOpen: @escaping (Bool) -> Void) {
        guard let menu = buildNSMenu(for: message, actions: actions) else { return }
        isOpen(true)
        DispatchQueue.main.async {
            defer { isOpen(false) }
            actions.presentMenu(menu, anchor)
        }
    }

    static func popUp(_ menu: NSMenu, relativeTo anchor: NSView?) {
        if let anchor, anchor.window != nil {
            let point = NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.height + 4 : -4)
            menu.popUp(positioning: nil, at: point, in: anchor)
            return
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func makeMenuItem(
        _ item: MessageMenuItem,
        hotkeys: HotkeyRegistry,
        isLocked: Bool,
        choose: @escaping (MessageMenuItem.Command) -> Void
    ) -> NSMenuItem {
        let enabled = item.isEnabled && !isLocked
        if !item.children.isEmpty {
            let nsItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: item.title)
            sub.allowsContextMenuPlugIns = false
            sub.autoenablesItems = false
            for child in item.children {
                sub.addItem(makeMenuItem(child, hotkeys: hotkeys, isLocked: isLocked, choose: choose))
            }
            nsItem.submenu = sub
            nsItem.isEnabled = enabled
            nsItem.toolTip = item.help
            return nsItem
        }

        let nsItem = NSMenuItem(
            title: item.title,
            action: enabled ? #selector(ActionTarget.invoke(_:)) : nil,
            keyEquivalent: ""
        )
        if enabled {
            let target = ActionTarget { choose(item.command) }
            nsItem.target = target
            // Retain the handler directly on the menu item for the lifetime of the menu.
            nsItem.representedObject = target
        }
        nsItem.isEnabled = enabled
        nsItem.toolTip = item.help
        applyKeyEquivalent(item.key, hotkeys: hotkeys, to: nsItem)
        return nsItem
    }

    private static func applyKeyEquivalent(_ key: MenuKey?, hotkeys: HotkeyRegistry, to item: NSMenuItem) {
        guard let key else { return }
        if let hotkeyID = key.hotkeyID {
            guard hotkeys.isEnabled(hotkeyID), let chord = hotkeys.primaryChord(for: hotkeyID) else { return }
            item.keyEquivalent = keyEquivalentString(for: chord.key)
            var mask: NSEvent.ModifierFlags = []
            if chord.command { mask.insert(.command) }
            if chord.shift { mask.insert(.shift) }
            if chord.option { mask.insert(.option) }
            if chord.control { mask.insert(.control) }
            item.keyEquivalentModifierMask = mask
            return
        }
        if key == .commandC {
            item.keyEquivalent = "c"
            item.keyEquivalentModifierMask = [.command]
        }
    }

    private static func keyEquivalentString(for rawKey: String) -> String {
        switch rawKey.lowercased() {
        case "up", "uparrow":
            return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case "down", "downarrow":
            return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        case "left", "leftarrow":
            return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case "right", "rightarrow":
            return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        default:
            if let ch = KeyChord.keyEquivalentCharacter(for: rawKey) {
                return String(ch)
            }
            return rawKey
        }
    }
}

/// Overlay used in SwiftUI fallback timelines and `ThreadPane` to present the native `NSMenu` (with
/// `allowsContextMenuPlugIns = false`) on right-click. Inside `TimelineTableView`, `TimelineHostingView` handles
/// `menu(for:)` directly and this view lets every event pass through.
struct MessageContextMenuOverlay: NSViewRepresentable {
    let message: TimelineMessage
    let actions: MessageActions

    func makeNSView(context _: Context) -> CatcherView {
        let view = CatcherView()
        view.message = message
        view.actions = actions
        return view
    }

    func updateNSView(_ nsView: CatcherView, context _: Context) {
        nsView.message = message
        nsView.actions = actions
    }

    final class CatcherView: NSView {
        var message: TimelineMessage?
        var actions: MessageActions?

        private var isInsideTimelineTableHost: Bool {
            var cursor = superview
            while let view = cursor {
                if view is TimelineHostingView { return true }
                cursor = view.superview
            }
            return false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !isInsideTimelineTableHost,
                  let event = NSApp.currentEvent,
                  event.type == .rightMouseDown
                      || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            else { return nil }
            return super.hitTest(point)
        }

        override func menu(for _: NSEvent) -> NSMenu? {
            guard let message, let actions else { return nil }
            return MessageContextMenuBuilder.buildNSMenu(for: message, actions: actions)
        }
    }
}

extension MenuKey {
    var shortcut: KeyboardShortcut {
        switch self {
        case .commandT: KeyboardShortcut("t", modifiers: .command)
        case .commandR: KeyboardShortcut("r", modifiers: .command)
        case .commandDown: KeyboardShortcut(.downArrow, modifiers: .command)
        case .commandC: KeyboardShortcut("c", modifiers: .command)
        case .commandShiftH: KeyboardShortcut("h", modifiers: [.command, .shift])
        case .commandShiftF: KeyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}

/// What a message row does, for the chat's rows and the thread pane's: its menu from `MessageMenu`, its items through
/// `MessageActionsModel.perform(_:on:from:)` (the pane's `from: .thread`, the chat's `.chat`), its poll votes, its
/// thread, and a click on a held message when "Click pending messages to undo send" is on.
@MainActor
enum MessageRowActions {
    static let sharedFallbackHotkeys = HotkeyRegistry()

    static func make(conversation: ConversationModel, messageActions: MessageActionsModel,
                     preferences: ComposerPreferences, composer: ComposerModel, ui: MessageUI, source: MessageSource,
                     deselect: @escaping () -> Void = {},
                     select: @escaping (String) -> Void) -> MessageActions {
        func perform(_ action: MessageAction, _ id: String) {
            Task { await messageActions.perform(action, on: id, from: source) }
        }
        /// Reply, or where the chat's replies are thread replies, Reply in Thread.
        func reply(_ id: String) {
            guard let message = conversation.message(id, from: source),
                  let action = conversation.replyAction(for: message) else { return }
            perform(action, id)
        }
        func resolvedChatTitle(for msg: TimelineMessage) -> String {
            conversation.otherPerson ?? conversation.chatInfo?.name ?? msg.senderName
        }
        func resolvedTranscript(for msg: TimelineMessage) -> String? {
            guard case let .transcribed(text, _, _)? = conversation.voiceNoteTranscripts.entry(for: msg.id) else {
                return nil
            }
            return text
        }
        let dispatcher = composer.hotkeyDispatcher
        let registry = dispatcher?.hotkeys ?? HotkeyRegistry()
        return MessageActions(
            select: select,
            deselect: deselect,
            reply: reply,
            react: { id, key in Task { await conversation.react(to: id, key: key) } },
            unreact: { event in Task { await conversation.unreact(eventID: event) } },
            isPickingReaction: { id in messageActions.request == .reactionPicker(messageID: id) },
            retry: { id in Task { await conversation.retry(id) } },
            discard: { id in Task { await conversation.discard(id) } },
            dontSend: { id in Task { await messageActions.dontSend(id, from: source) } },
            waitingHelp: { StatusLine.waitingHelp(network: conversation.network) },
            menu: { message in
                guard dispatcher?.lifecycle.isLocked != true else { return [] }
                let transcript = resolvedTranscript(for: message)
                let canReadAloud = ReadAloudText.forMessage(
                    message,
                    transcript: transcript,
                    chatTitle: resolvedChatTitle(for: message)
                ) != nil
                return MessageMenu.sections(
                    for: message,
                    available: conversation.availableActions(for: message),
                    features: conversation.features,
                    disappearsIn: conversation.disappearsIn(message),
                    time: { preferences.formatDateTime($0, dateStyle: .medium) },
                    includeDiagnostics: true,
                    isAIAvailable: composer.aiProvider.isAvailable,
                    responseLanguage: composer.aiPreferences.responseLanguage,
                    translationLanguages: composer.aiPreferences.translationLanguages,
                    canReadAloud: canReadAloud,
                    isReadingAloud: messageActions.readAloud.isReadingOnVitruvianSpeaker,
                    hasSummarizableLink: preferences.showLinkPreviews
                        && ArticleSummaryRequest.first(in: message, isEmbed: ArticleSummaryControls.isEmbed) != nil
                )
            },
            perform: { command, id in
                guard dispatcher?.lifecycle.isLocked != true else { return }
                switch command {
                case let .action(action): perform(action, id)
                case .showReplies: conversation.openThread(id)
                case .copyMessageDetails: messageActions.copyMessageDetails(id, from: source)
                case .reportProblem: messageActions.reportProblem(for: id, from: source)
                case .translate:
                    let lang = composer.aiPreferences.responseLanguage
                    if composer.aiProvider.isAvailable {
                        messageActions.translateMessage(eventID: id, targetLanguage: lang)
                    } else {
                        messageActions.translateMessage(eventID: id, targetLanguage: lang)
                        messageActions.onOpenAISettings()
                    }
                case let .translateTo(lang):
                    if composer.aiProvider.isAvailable {
                        messageActions.translateMessage(eventID: id, targetLanguage: lang)
                    } else {
                        messageActions.translateMessage(eventID: id, targetLanguage: lang)
                        messageActions.onOpenAISettings()
                    }
                case .summarizeLink:
                    guard preferences.showLinkPreviews, let msg = conversation.message(id, from: source),
                          let request = ArticleSummaryRequest.first(in: msg, isEmbed: ArticleSummaryControls.isEmbed)
                    else { return }
                    messageActions.summarizeLink(request)
                case .transcribeVoiceNote:
                    guard let msg = conversation.message(id, from: source) else { return }
                    let store = conversation.voiceNoteTranscripts
                    Task { await store.transcribe(eventID: msg.id, mediaPath: msg.mediaPath) }
                case .readAloud:
                    guard let msg = conversation.message(id, from: source) else { return }
                    messageActions.readAloudMessage(
                        id,
                        transcript: resolvedTranscript(for: msg),
                        chatTitle: resolvedChatTitle(for: msg),
                        from: source
                    )
                case .more, .info: break
                }
            },
            hotkeys: registry,
            hotkeyDispatcher: dispatcher,
            undoHeld: preferences.clickPendingToUndo ? { id in Task { await composer.undoHeld(id) } } : nil,
            vote: { id, options in Task { await messageActions.vote(id, options: options) } },
            openThread: source == .chat ? { conversation.openThread($0) } : nil,
            timerNote: { conversation.timerChangeNote(for: $0) },
            callCaller: { conversation.callCaller(for: $0) },
            disappearsIn: { conversation.disappearsIn($0) },
            timerChoices: { conversation.timerChoices },
            setTimer: { choice in Task { await conversation.setTimer(choice) } },
            doubleClick: { id in
                switch preferences.doubleClickMessage {
                case .reply: reply(id)
                case .nothing, .menu: break // .menu: the row shows the menu itself
                case .reactionPicker: perform(.react, id)
                case .forward: perform(.forward, id)
                case .reactWith: Task { await conversation.react(to: id, key: preferences.quickReaction) }
                }
            },
            doubleClickShowsMenu: preferences.doubleClickMessage == .menu,
            hoverSender: { hovering, message in
                conversation.setTriggerHovered(hovering, for: message)
            },
            now: { conversation.currentTime },
            calendarBridge: conversation.calendarBridge,
            openLightbox: { conversation.openLightbox($0) },
            openViewOnce: { conversation.openViewOnce($0) },
            audioPlayer: conversation.audioPlayer,
            voiceNoteTranscripts: conversation.voiceNoteTranscripts,
            copyPlainText: { text in messageActions.copyPlainText(text) },
            readAloudTranscript: { msg, text in
                messageActions.readAloudTranscript(text, message: msg, chatTitle: resolvedChatTitle(for: msg))
            },
            chatTitle: { msg in resolvedChatTitle(for: msg) },
            voiceNoteQueue: { id in
                conversation.voiceNoteQueue(
                    startingAt: id,
                    in: source == .thread ? conversation.thread.items : conversation.items
                )
            },
            loadExternalEmbedsAutomatically: preferences.loadExternalEmbedsAutomatically,
            showLinkPreviews: preferences.showLinkPreviews,
            linkPreviewImages: conversation.linkPreviewImages,
            timeFormat: preferences.timeFormat,
            showMessageTimestamps: preferences.showMessageTimestamps,
            composerPreferences: preferences,
            translation: { id in
                let isTranslating = messageActions.translatingEventIDs.contains(id)
                guard isTranslating || messageActions.translations[id] != nil else { return nil }
                let lang = messageActions.translationTargetLanguages[id] ?? composer.aiPreferences.responseLanguage
                let disp = messageActions.translations[id] ?? .text("")
                return (lang, disp)
            },
            isTranslating: { id in
                messageActions.translatingEventIDs.contains(id)
            },
            translationProvenance: { id in
                messageActions.translationProvenance[id]
            },
            retryTranslation: { id in
                let lang = messageActions.translationTargetLanguages[id] ?? composer.aiPreferences.responseLanguage
                messageActions.translateMessage(eventID: id, targetLanguage: lang)
            },
            openAISettings: {
                messageActions.onOpenAISettings()
            },
            dismissTranslation: { id in
                messageActions.dismissTranslation(eventID: id)
            },
            articleSummary: ArticleSummaryControls(
                canSummarize: { url in
                    messageActions.articleSummaries.canSummarize(url, showLinkPreviews: preferences.showLinkPreviews)
                },
                state: { messageActions.articleSummaries.state(for: $0) },
                hasAny: { !messageActions.articleSummaries.states.isEmpty },
                summarize: { messageActions.summarizeLink($0) },
                dismiss: { messageActions.articleSummaries.dismiss($0) },
                retry: { messageActions.articleSummaries.retry($0) },
                copy: { text in messageActions.copyPlainText(text) },
                aiIsAvailable: { messageActions.articleSummaries.aiProvider.isAvailable },
                providerName: {
                    messageActions.articleSummaries.aiProvider.summarizerName(preferences: messageActions.aiPreferences)
                },
                suggestionsHeight: { messageActions.articleSummaries.suggestionsHeight(for: $0) },
                setSuggestionsHeight: { messageActions.articleSummaries.setSuggestionsHeight($1, for: $0) }
            ))
    }
}
