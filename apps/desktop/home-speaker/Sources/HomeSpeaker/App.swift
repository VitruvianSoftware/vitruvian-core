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
            // An edit from the phone or the CLI that turns a chat source on
            // or off must reach the running poller, not just the settings.
            ConfigManager.shared.chatMonitor = ChatMonitorService.shared
            // The phone (via the Mac agent) and the CLI edit the same file;
            // the menu bar has to notice or it will write stale state back.
            ConfigManager.shared.startWatchingConfigFile()
            // The one long-lived process: it holds paused media for the
            // Stop hook and --say, which exit before an announcement ends.
            _ = MediaPauseRequest.listen(with: .shared)
            // Likewise for putting a speaker back after "announce at a set volume".
            _ = VolumeRestoreRequest.listen(with: .shared)
            // `HomeSpeaker --sign-out` runs as another process; without
            // this the menu bar kept showing "Connected" and kept polling.
            _ = SignOutNotice.listen(config: ConfigManager.shared, monitor: ChatMonitorService.shared)
            // And `--sign-in`, or the Vitruvian tool saving a Slack token:
            // re-read the login and start or restart the monitor with it.
            _ = CredentialsChangedNotice.listen(config: ConfigManager.shared, monitor: ChatMonitorService.shared)
            // Start and Stop from the Vitruvian tool or `--chat-monitor`.
            _ = ChatMonitorControlNotice.listen(monitor: ChatMonitorService.shared)
            // A quit says the monitor stopped, so the status file does not
            // go on saying it runs. (A crash cannot; readers check the app.)
            _ = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { ChatMonitorService.shared.stop() }
            }
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
