// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore

/// Owns the app's model, and so the engine: starts it at launch and stops it before the app quits. Closing the
/// window does not quit (spec §2): Courier keeps running, with its Dock icon, to keep receiving.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let inbox: InboxModel
    let conversation: ConversationModel

    override init() {
        let environment = ProcessInfo.processInfo.environment
        let supervisor = EngineSupervisor(
            enginePath: EngineLocation.enginePath(environment: environment),
            dataDir: EngineLocation.dataDirectory(environment: environment),
            environment: environment,
            launcher: FoundationProcessLauncher()
        )
        model = AppModel(supervisor: supervisor)
        let inbox = InboxModel(appModel: model)
        self.inbox = inbox
        // The "New" divider goes above as many messages as the inbox counted unread when the chat was opened.
        conversation = ConversationModel(appModel: model, unreadCount: { id in
            inbox.rows.first { $0.roomID == id }?.unread ?? 0
        })
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Copies made to open received files last until the next launch.
        OpenFileCache.shared.clear()
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting waits for the engine to stop (SIGTERM, then SIGKILL after ten seconds), so it never outlives the
    /// app holding its data directory's lock.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
