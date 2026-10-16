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
        Task { @MainActor in
            let side = AppSide.shared
            // An edit from the phone or the CLI that turns a chat source on
            // or off must reach the running poller, not just the settings:
            // through the gate, so a quiet app never starts it.
            ConfigManager.shared.chatMonitor = side.door.monitor
            // The phone (via the Mac agent) and the CLI edit the same file;
            // the menu bar has to notice or it will write stale state back.
            // The choice file sits in the same folder: a choice made in the
            // extension reaches the app within a second.
            ConfigManager.shared.onFolderChange = { side.door.refresh() }
            ConfigManager.shared.startWatchingConfigFile()
            let engine = HomeSpeakerEngine.app
            // `HomeSpeaker --sign-out` runs as another process; without
            // this the menu bar kept showing "Connected" and kept polling.
            // And `--sign-in`, or the Vitruvian tool saving a Slack token:
            // re-read the login and start or restart the monitor with it.
            _ = engine.listenForNotices(monitor: side.door.monitor)
            // Start and Stop from the Vitruvian tool or `--chat-monitor`.
            _ = ChatMonitorControlNotice.listen(
                name: ChatMonitorControlNotice.notificationName(for: engine.profile), monitor: side.door.monitor)
            // A quit says the monitor stopped, so the status file does not
            // go on saying it runs. (A crash cannot; readers check the app.)
            _ = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { ChatMonitorService.shared.stop() }
            }
            // What runs follows the choice (design 7.3): today's start-up
            // while the app is the one in use or nobody has picked; nothing
            // while the extension is.
            side.launch()
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

/// The app's side of the choice, wired to the real parts: `AppDoor` starts
/// and stops them, `AppSwitch` runs the choice, and the window asks.
@MainActor
final class AppSide {
    static let shared = AppSide()

    let door: AppDoor
    let switcher: AppSwitch
    /// The media and volume listeners while the app runs.
    private var listeners: [NSObjectProtocol] = []
    private var timer: Timer?

    private init() {
        let engine = HomeSpeakerEngine.app
        // The app's bundle as it is now: a reference follows the bundle when
        // the person drags it, to the Trash say, while it runs.
        let reference = (Bundle.main.bundleURL as NSURL).fileReferenceURL() as NSURL?
        let bundlePath = { reference?.filePathURL?.path ?? Bundle.main.bundlePath }
        var stopListening: @MainActor () -> Void = {}
        var startListening: @MainActor () -> Void = {}
        door = AppDoor(
            check: DoorCheck(appInstalled: { false }),
            bundlePath: bundlePath,
            monitor: ChatMonitorService.shared,
            effects: AppDoor.Effects(
                // If the user moved the app since installing the hook,
                // re-point it; a choice of the app takes it back from the
                // extension (design 7.6).
                repairHooks: { AgentIntegration.shared.repairHookIfMoved(choice: $0) },
                // Chat monitoring only runs when the user opted in earlier.
                startMonitorIfConfigured: { ChatMonitorService.shared.startIfConfigured() },
                stopMonitor: { ChatMonitorService.shared.stop() },
                // The one long-lived process: it holds paused media for the
                // Stop hook and --say, which exit before an announcement
                // ends, and puts a speaker back after "announce at a set
                // volume".
                startListening: { startListening() },
                stopListening: { stopListening() }))
        switcher = AppSwitch(door: door, parts: AppSwitch.Parts(
            appProfile: engine.profile,
            home: FileManager.default.homeDirectoryForCurrentUser,
            now: { Date() },
            copy: DoorCopy.copy,
            credentialsChangedIn: { CredentialsChangedNotice.post(name: CredentialsChangedNotice.notificationName(for: $0)) },
            turnOffLoginItem: { try LoginItem.setEnabled(false) },
            moveToTrash: {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: URL(fileURLWithPath: bundlePath()), resultingItemURL: &trashed)
            },
            quit: { NSApplication.shared.terminate(nil) },
            openVitruvian: {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppSide.vitruvianBundleID),
                      !OtherDoorPresence.isInTrash(url.path) else { return false }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return true
            }))
        startListening = { [unowned self] in self.listeners = engine.listen() }
        stopListening = { [unowned self] in
            for token in self.listeners { DistributedNotificationCenter.default().removeObserver(token) }
            self.listeners = []
        }
    }

    /// Vitruvian, where the extension is.
    static let vitruvianBundleID = "com.vitruviansoftware.vitruvian"

    /// At launch: what the role says starts, the window when it asks or is
    /// quiet, and a look every five seconds, for what no file event shows
    /// (the extension removed, this app dragged to the Trash).
    func launch() {
        door.refresh()
        DoorWindow.shared.showIfNeeded(door.plan)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { AppSide.shared.door.refresh() }
        }
    }
}
