// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// The main window: how the engine is doing until it is up, then two panes, the inbox and the conversation.
/// (The conversation is the next task's; the space bar and the right pane are milestone 4's.)
struct MainWindow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var inbox: InboxModel

    var body: some View {
        content
            .frame(minWidth: 480, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
            .navigationTitle("Courier")
            .navigationSubtitle(StatusText.subtitle(for: model.engineState))
    }

    @ViewBuilder
    private var content: some View {
        switch model.engineState {
        case .connected:
            if inbox.showsAddNetwork {
                VStack(spacing: 0) {
                    // Telegram's "Set up" is here too: it has to be set up before it can be linked.
                    ForEach(inbox.banners) { banner in
                        AccountBannerView(banner: banner) { inbox.perform(banner) }
                    }
                    AddNetworkPrompt(add: inbox.addNetwork)
                }
            } else {
                panes
            }
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

    private var panes: some View {
        NavigationSplitView {
            InboxList(inbox: inbox)
                .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 480)
        } detail: {
            ConversationPlaceholder(name: inbox.selectedRow?.name)
        }
        .background { alternateShortcuts }
    }

    /// The second keys for next and previous chat (⌘⌥↓, ⌘⌥↑). The menu shows ⌘] and ⌘[, and a menu item has only
    /// one key, so these are buttons nobody sees.
    private var alternateShortcuts: some View {
        Group {
            Button("", action: inbox.selectNext)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("", action: inbox.selectPrevious)
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
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

/// The right-hand pane until the conversation view exists.
private struct ConversationPlaceholder: View {
    let name: String?

    var body: some View {
        VStack(spacing: 8) {
            if let name {
                Text(name).font(.title2)
            } else {
                Text(String(localized: "Select a chat"))
                    .foregroundStyle(.secondary)
            }
        }
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
