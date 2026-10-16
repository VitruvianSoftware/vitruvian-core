// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

@main
struct CourierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Courier", id: "main") {
            MainWindow(model: delegate.model)
        }
        .defaultSize(width: 960, height: 640)
    }
}

/// The main window. For now it shows only how the engine is doing; the inbox and the conversation come next.
struct MainWindow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            switch model.engineState {
            case .connected:
                Text(String(localized: "Courier is running. Your chats will appear here."))
                    .foregroundStyle(.secondary)
            case .updateNeeded:
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(String(localized: "This copy of Courier and its engine don’t match. Reinstall Courier to update it."))
                    .multilineTextAlignment(.center)
            case let .reconnecting(_, problem?):
                // The restarts go on; this says why they have not worked yet.
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(StatusText.explanation(of: problem))
                    .multilineTextAlignment(.center)
            case .starting, .reconnecting:
                ProgressView()
                Text(String(localized: "Starting Courier’s engine…"))
                    .foregroundStyle(.secondary)
            case .stopped:
                Text(String(localized: "Courier’s engine is stopped."))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .navigationTitle("Courier")
        .navigationSubtitle(StatusText.subtitle(for: model.engineState))
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
        }
    }
}
