// Copyright (c) 2026 VitruvianSoftware

import SwiftUI
import HomeSpeakerCore

@main
struct HomeSpeakerApp: App {
    @StateObject private var configManager = ConfigManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: configManager.config.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
