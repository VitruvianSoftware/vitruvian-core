// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// What the inbox's views show that is no model's: the Custom… reminder sheet, the ⌘L Remind Me popover and the
/// ⌘⌥A account popover. The menus, keys and rows set it; the window shows it.
@MainActor
final class InboxUI: ObservableObject {
    @Published var customReminder: ReminderRequest?
    @Published var remindPopover = false
    @Published var accountPopover = false
    /// The main window is open and in front (key). ⌘K closes a panel only then; otherwise it brings the window
    /// forward and opens it.
    var isMainWindowKey = false
    private var lockObserver: NSObjectProtocol?

    init() {
        lockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didLockNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissAllPresentations()
            }
        }
    }

    deinit {
        if let lockObserver {
            NotificationCenter.default.removeObserver(lockObserver)
        }
    }

    func dismissAllPresentations() {
        if customReminder != nil { customReminder = nil }
        if remindPopover { remindPopover = false }
        if accountPopover { accountPopover = false }
    }
}

/// The main window: how the engine is doing until it is up, then the space bar, the chat list and the
/// conversation (01 §2, §3), with ⌘K's search over them (01 §12). (The right pane is a later part's.)
struct MainWindow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var inbox: InboxModel
    @ObservedObject var conversation: ConversationModel
    @ObservedObject var login: LoginFlowModel
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var preferences: InboxPreferences
    @ObservedObject var ui: InboxUI
    @ObservedObject var search: SearchModel
    @ObservedObject var lifecycle: SystemLifecycleModel
    let labels: LabelsModel
    /// The message menu's actions, the open chat's scheduled messages, the composer's settings, and which messages
    /// the keys act on.
    let messageActions: MessageActionsModel
    let scheduled: ScheduledModel
    @ObservedObject var composerPreferences: ComposerPreferences
    let focus: MessageFocus
    var detachedWindows: DetachedWindowRegistry? = nil
    @ObservedObject var hotkeys: HotkeyRegistry = HotkeyRegistry()
    var hotkeyDispatcher: HotkeyDispatcher? = nil
    var onOpenShortcutsSettings: () -> Void = {}
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        LockableWindowContent(lifecycle: lifecycle) {
            content
                .frame(minWidth: 480, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                .overlay {
                    if search.phase != .closed {
                        SearchOverlay(search: search, inbox: inbox, composerPreferences: composerPreferences)
                    }
                }
                .overlay {
                    if conversation.carousel.isPresented {
                        AttachmentCarouselOverlay(
                            model: conversation.carousel,
                            onGoToMessage: { item in
                                conversation.closeLightbox()
                                model.open(.message(roomID: item.roomID, eventID: item.eventID))
                            },
                            onReact: { item, emoji in
                                Task { await conversation.react(to: item.eventID, key: emoji) }
                            },
                            onReply: { item in
                                conversation.closeLightbox()
                                if let msg = conversation.message(item.eventID, from: .chat),
                                   let action = conversation.replyAction(for: msg) {
                                    Task { await messageActions.perform(action, on: item.eventID, from: .chat) }
                                }
                            },
                            onCopyImage: { item in
                                guard !item.viewOnce,
                                      isLocalMediaStorePath(item.mediaPath),
                                      let nsImage = NSImage(contentsOfFile: item.mediaPath)
                                else { return }
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.writeObjects([nsImage])
                                conversation.onToast(String(localized: "Copied image"))
                            },
                            onQuickLook: { item in
                                guard !item.viewOnce, isLocalMediaStorePath(item.mediaPath) else { return }
                                QuickLookPreviewCoordinator.shared.preview(
                                    fileAtPath: item.mediaPath,
                                    suggestedName: item.fileName
                                )
                            },
                            onDownload: { item in
                                guard !item.viewOnce, isLocalMediaStorePath(item.mediaPath) else { return }
                                let downloader = AttachmentDownloader(preferences: composerPreferences)
                                if let saved = try? downloader.download(
                                    sourcePath: item.mediaPath,
                                    suggestedName: item.fileName
                                ) {
                                    conversation.onToast(String(localized: "Saved \(saved.lastPathComponent)"))
                                }
                            },
                            onClose: {
                                conversation.closeLightbox()
                            }
                        )
                    }
                }
                // A chat's right-click menu opens search in that chat.
                .environment(\.searchInChat, { search.show(in: $0) })
                .environment(\.openDetachedWindow, { target in detachedWindows?.open(target) })
                .onChange(of: controlActiveState, initial: true) { _, state in
                    ui.isMainWindowKey = state == .key
                }
                // A closed window takes its panel with it: the next ⌘K opens a fresh one, in view.
                .onDisappear {
                    ui.isMainWindowKey = false
                    search.close()
                    conversation.composer.voiceRecorder.cancelImmediately()
                    conversation.thread.composer.voiceRecorder.cancelImmediately()
                    conversation.composer.isStickerPickerPresented = false
                    conversation.composer.isGIFPickerPresented = false
                    conversation.thread.composer.isStickerPickerPresented = false
                    conversation.thread.composer.isGIFPickerPresented = false
                }
                .sheet(isPresented: addingNetwork) {
                    AddNetworkView(login: login)
                }
                .sheet(item: customReminderBinding) { request in
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
                // The Edit spaces command (and the bar's menus) ask for the window this way.
                .onChange(of: spaces.isEditing) { _, editing in
                    if editing { openWindow(id: WindowID.editSpaces) }
                }
                .sheet(isPresented: $hotkeys.isShortcutsSheetPresented) {
                    KeyboardShortcutsSheet(
                        registry: hotkeys,
                        onCustomize: onOpenShortcutsSettings,
                        onClose: { hotkeys.isShortcutsSheetPresented = false }
                    )
                }
                .navigationTitle("Courier")
                .navigationSubtitle(lifecycle.isLocked ? "" : StatusText.subtitle(for: model.engineState))
        }
    }

    private var customReminderBinding: Binding<ReminderRequest?> {
        Binding(
            get: { ui.customReminder ?? inbox.customReminder },
            set: { value in
                ui.customReminder = value
                inbox.customReminder = value
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch model.engineState {
        case .connected:
            // Before any network is linked the window is already the whole app (its spaces, labels and settings
            // work), with the prompt to add one where a chat would open. A network that could not start shows as a
            // banner above the list.
            panes
        case .updateNeeded:
            message(symbol: "exclamationmark.triangle") {
                Text(String(localized: "This copy of Courier and its engine don’t match. Reinstall Courier to update it."))
            }
        case let .reconnecting(_, problem?):
            // The restarts go on; this says why they have not worked yet.
            message(symbol: "exclamationmark.triangle") {
                Text(StatusText.explanation(of: problem))
            }
        case .starting, .reconnecting:
            VStack(spacing: 12) {
                ProgressView()
                Text(String(localized: "Starting Courier’s engine…"))
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        case .stopped:
            Text(String(localized: "Courier’s engine is stopped."))
                .foregroundStyle(.secondary)
                .padding(40)
        }
    }

    /// The sheet is up while a network is being added. Dismissing it (Esc) ends that, cancelling any sign-in.
    private var addingNetwork: Binding<Bool> {
        Binding(get: { login.screen != .closed }, set: { if !$0 { login.close() } })
    }

    private var panes: some View {
        VStack(spacing: 0) {
            if conversation.audioPlayer.shouldShowGlobalBar {
                GlobalAudioPlayerBar(audioPlayer: conversation.audioPlayer) { roomID, eventID in
                    model.open(.message(roomID: roomID, eventID: eventID))
                }
            }
            NavigationSplitView {
                HStack(spacing: 0) {
                    if preferences.showSpaceBar {
                        SpaceBar(spaces: spaces, inbox: inbox, labels: labels)
                        Divider()
                    }
                    InboxList(
                        inbox: inbox,
                        spaces: spaces,
                        preferences: preferences,
                        composerPreferences: composerPreferences,
                        ui: ui
                    )
                }
                .navigationSplitViewColumnWidth(min: preferences.showSpaceBar ? 260 + SpaceBar.width : 260,
                                                ideal: preferences.showSpaceBar ? 340 + SpaceBar.width : 340,
                                                max: 480 + SpaceBar.width)
            } detail: {
                HStack(spacing: 0) {
                    Group {
                        if inbox.showsAddNetwork {
                            AddNetworkPrompt(add: inbox.addNetwork)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if model.selectedRoomID != nil {
                            ConversationView(conversation: conversation, composer: conversation.composer, inbox: inbox,
                                             messageActions: messageActions, scheduled: scheduled, preferences: composerPreferences,
                                             thread: conversation.thread, focus: focus, appModel: model)
                        } else {
                            NoChatSelected()
                        }
                    }
                    if conversation.isShowingCalendar {
                        Divider()
                        CalendarPane(bridge: conversation.calendarBridge, onClose: conversation.toggleCalendar)
                    }
                }
            }
        }
        .background { alternateShortcuts }
    }

    private var resolvedHotkeyDispatcher: HotkeyDispatcher {
        if let hotkeyDispatcher {
            return hotkeyDispatcher
        }
        return HotkeyDispatcher(
            inbox: inbox,
            spaces: spaces,
            conversation: conversation,
            messageActions: messageActions,
            search: search,
            lifecycle: lifecycle,
            menuCoordinator: AppMenuCoordinator(inbox: inbox, lifecycle: lifecycle),
            focus: focus,
            hotkeys: hotkeys
        )
    }

    /// The second keys for next and previous chat (⌘⌥↓, ⌘⌥↑) and window-scoped shortcuts.
    /// Every binding routes through `HotkeyDispatcher` so lock (`!lifecycle.isLocked`) and entitlements
    /// (`.incognito`, `.reminders`) are enforced in one place.
    private var alternateShortcuts: some View {
        let dispatcher = resolvedHotkeyDispatcher
        return Group {
            ForEach(HotkeyDispatcher.windowShortcutBindings) { binding in
                Button("") {
                    _ = dispatcher.perform(binding)
                }
                .registryShortcut(
                    binding.hotkeyID,
                    in: hotkeys,
                    chordIndex: binding.chordIndex,
                    extraModifiers: binding.reversesCycle ? .shift : []
                )
                .disabled(!dispatcher.canPerform(binding.hotkeyID))
            }
            // ⌘C, here before the Edit menu's: whatever can copy (selected text anywhere, a code block's too)
            // copies; only when nothing can, with the keyboard in the open chat, the selected message is copied.
            Button("", action: copy)
                .keyboardShortcut("c", modifiers: .command)
                .disabled(lifecycle.isLocked)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func copy() {
        guard !lifecycle.isLocked else { return }
        let canCopy = CopyResponder.canCopy()
        // Not the search panel, a sheet over the window, or a window without a chat open.
        let inConversation = ui.isMainWindowKey && search.phase == .closed && model.selectedRoomID != nil
            && NSApp.keyWindow?.attachedSheet == nil
        Task {
            switch await messageActions.copySelected(responderCanCopy: canCopy, inConversation: inConversation,
                                                     focus: focus) {
            case .message: break
            case .text, .nothing: NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
        }
    }

    private func message<Body: View>(symbol: String, @ViewBuilder _ body: () -> Body) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            body()
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

/// The right-hand pane while no chat is open.
private struct NoChatSelected: View {
    var body: some View {
        Text(String(localized: "Select a chat"))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The window before any network is linked.
private struct AddNetworkPrompt: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(String(localized: "Add a network"))
                .font(.title2.weight(.semibold))
            Text(String(localized: "Link WhatsApp, Signal, Telegram, Slack or Google Messages, and your chats appear here."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(String(localized: "Add a network"), action: add)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
    }
}

/// The window's subtitle for each engine state.
enum StatusText {
    static func subtitle(for state: EngineSupervisor.State) -> String {
        switch state {
        case .starting: String(localized: "Connecting…")
        case .reconnecting: String(localized: "Reconnecting…")
        case .updateNeeded: String(localized: "Update needed")
        case .connected: String(localized: "Connected")
        case .stopped: String(localized: "Stopped")
        }
    }

    /// What the person can do about a problem.
    static func explanation(of problem: EngineSupervisor.Problem) -> String {
        switch problem {
        case let .dataDirectoryInUse(message?):
            String(localized: "Courier can’t start its engine: \(message). Quit the other copy of Courier, or the command-line engine, that uses this folder. Courier keeps trying.")
        case .dataDirectoryInUse(nil):
            String(localized: "Courier can’t start its engine: another copy of it is using Courier’s data folder. Quit the other copy of Courier, or the command-line engine. Courier keeps trying.")
        case let .engineFailed(message):
            String(localized: "Courier’s engine stopped while starting: \(message). Courier keeps trying.")
        }
    }
}

/// Opens search in a chat, by its room ID: the chat menu's Search… (⌘F).
private struct SearchInChatKey: EnvironmentKey {
    static let defaultValue: (@MainActor (String) -> Void)? = nil
}

extension EnvironmentValues {
    var searchInChat: (@MainActor (String) -> Void)? {
        get { self[SearchInChatKey.self] }
        set { self[SearchInChatKey.self] = newValue }
    }
}

/// Whether anything in the key window's responder chain can copy now: a text view, a field, or a selectable message
/// text (a code block) with a selection. Asked the way a menu asks: the target for copy:, then its validation.
@MainActor
enum CopyResponder {
    static func canCopy() -> Bool {
        let action = #selector(NSText.copy(_:))
        guard let target = NSApp.target(forAction: action) as AnyObject? else { return false }
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        if let validator = target as? NSMenuItemValidation { return validator.validateMenuItem(item) }
        if let validator = target as? NSUserInterfaceValidations { return validator.validateUserInterfaceItem(item) }
        return true
    }
}
