// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import SwiftUI
import HomeSpeakerCore

struct HomeSpeakerApp: App {
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var monitor = ChatMonitorService.shared

    init() {
        // If the user moved the app since installing the hook, re-point it.
        AgentIntegration.shared.repairHookIfMoved()
        // Chat monitoring only runs when the user opted in earlier.
        Task { @MainActor in
            ChatMonitorService.shared.startIfConfigured()
            // The phone (via the Mac agent) and the CLI edit the same file;
            // the menu bar has to notice or it will write stale state back.
            ConfigManager.shared.startWatchingConfigFile()
            // The one long-lived process: it holds paused media for the
            // Stop hook and --say, which exit before an announcement ends.
            _ = MediaPauseRequest.listen(with: .shared)
            // Likewise for putting a speaker back after "announce at a set volume".
            _ = VolumeRestoreRequest.listen(with: .shared)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: configManager.config.enabled ? "dot.radiowaves.left.and.right" : "speaker.slash.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
