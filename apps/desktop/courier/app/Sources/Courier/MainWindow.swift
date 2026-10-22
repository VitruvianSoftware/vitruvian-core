// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

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
    let labels: LabelsModel
    /// The message menu's actions, the open chat's scheduled messages, the composer's settings, and which messages
    /// the keys act on.
    let messageActions: MessageActionsModel
    let scheduled: ScheduledModel
    let composerPreferences: ComposerPreferences
    let focus: MessageFocus
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        content
            .frame(minWidth: 480, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
            .overlay {
                if search.phase != .closed {
                    SearchOverlay(search: search, inbox: inbox)
                }
            }
            // A chat's right-click menu opens search in that chat.
            .environment(\.searchInChat, { search.show(in: $0) })
            .onChange(of: controlActiveState, initial: true) { _, state in ui.isMainWindowKey = state == .key }
            // A closed window takes its panel with it: the next ⌘K opens a fresh one, in view.
            .onDisappear {
                ui.isMainWindowKey = false
                search.close()
            }
            .sheet(isPresented: addingNetwork) {
                AddNetworkView(login: login)
            }
            .sheet(item: $ui.customReminder) { request in
                CustomReminderSheet(request: request, inbox: inbox)
            }
            // The Edit spaces command (and the bar's menus) ask for the window this way.
            .onChange(of: spaces.isEditing) { _, editing in
                if editing { openWindow(id: WindowID.editSpaces) }
            }
            .navigationTitle("Courier")
            .navigationSubtitle(StatusText.subtitle(for: model.engineState))
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
        NavigationSplitView {
            HStack(spacing: 0) {
                if preferences.showSpaceBar {
                    SpaceBar(spaces: spaces, inbox: inbox, labels: labels)
                    Divider()
                }
                InboxList(inbox: inbox, spaces: spaces, preferences: preferences, ui: ui)
            }
            .navigationSplitViewColumnWidth(min: preferences.showSpaceBar ? 260 + SpaceBar.width : 260,
                                            ideal: preferences.showSpaceBar ? 340 + SpaceBar.width : 340,
                                            max: 480 + SpaceBar.width)
        } detail: {
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
        .background { alternateShortcuts }
    }

    /// The second keys for next and previous chat (⌘⌥↓, ⌘⌥↑). The menu shows ⌘] and ⌘[, and a menu item has only
    /// one key, so these are buttons nobody sees.
    ///
    /// ⌘F is here too, as well as on the Chat menu's Search in Chat…: the window reads its own keys before the menu
    /// bar's, so ⌘F is search's even where the Edit menu's Find would take it (the composer, say).
    private var alternateShortcuts: some View {
        Group {
            Button("", action: inbox.selectNext)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("", action: inbox.selectPrevious)
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("") { search.show(in: model.selectedRoomID) }
                .keyboardShortcut("f", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
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
