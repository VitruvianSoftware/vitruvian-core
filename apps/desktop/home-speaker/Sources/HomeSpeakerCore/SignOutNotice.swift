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

import Foundation

// `HomeSpeaker --sign-out` runs as a second, short-lived copy of the app: it
// clears the stored login, but the menu bar app that is already running
// would go on showing "Connected" and polling Google Chat with a login that
// is gone. So the CLI tells it, with a distributed notification, the same way
// the Stop hook and `--say` hand media pausing to the app (MediaPauseRequest).

public enum SignOutNotice {
    public static let notificationName = Notification.Name("com.vitruviansoftware.homespeaker.signed-out")

    /// The CLI's side: tell a running HomeSpeaker that the login changed.
    /// `name` is for tests, so they never reach a real running app.
    public static func post(chatOnly: Bool, name: Notification.Name = notificationName) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: ["chatOnly": chatOnly], deliverImmediately: true)
    }

    /// The app's side: run `handle` on the main actor for each notice.
    @MainActor public static func listen(
        name: Notification.Name = notificationName,
        handle: @escaping @MainActor @Sendable (_ chatOnly: Bool) -> Void
    ) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { note in
            let chatOnly = (note.userInfo?["chatOnly"] as? NSNumber)?.boolValue ?? false
            Task { @MainActor in handle(chatOnly) }
        }
    }

    /// The app's side, wired to the shared config manager and chat monitor.
    @MainActor public static func listen(config: ConfigManager, monitor: any ChatMonitorControlling) -> NSObjectProtocol {
        listen { [weak config, weak monitor] chatOnly in
            guard let config, let monitor else { return }
            apply(chatOnly: chatOnly, config: config, monitor: monitor)
        }
    }

    /// What the app does on a notice, as the Settings buttons do: re-read
    /// the login, then stop the chat monitor -- or, after a Chat-only sign
    /// out, restart a running one, so Slack keeps going and Google Chat drops.
    @MainActor public static func apply(chatOnly: Bool, config: ConfigManager, monitor: any ChatMonitorControlling) {
        config.checkConnection()
        if !chatOnly {
            monitor.stop()
        } else if monitor.isRunning {
            monitor.stop()
            monitor.start()
        }
    }
}

// The other way round: a login or token was ADDED or changed by another
// process -- `HomeSpeaker --sign-in [--chat]`, or the Vitruvian tool saving
// or clearing the Slack token or importing the Antigravity login. The
// running app re-reads the login and gets the chat monitor going with what
// is now there: a monitor that could not start for want of a Slack token
// starts once one is saved, with nobody touching the menu bar.

public enum CredentialsChangedNotice {
    public static let notificationName = Notification.Name("com.vitruviansoftware.homespeaker.credentials-changed")

    /// The other process's side. `name` is for tests, so they never reach
    /// a real running app.
    public static func post(name: Notification.Name = notificationName) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// The app's side: run `handle` on the main actor for each notice.
    @MainActor public static func listen(
        name: Notification.Name = notificationName,
        handle: @escaping @MainActor @Sendable () -> Void
    ) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in handle() }
        }
    }

    /// The app's side, wired to the shared config manager and chat monitor.
    @MainActor public static func listen(
        name: Notification.Name = notificationName, config: ConfigManager, monitor: any ChatMonitorControlling
    ) -> NSObjectProtocol {
        listen(name: name) { [weak config, weak monitor] in
            guard let config, let monitor else { return }
            apply(config: config, monitor: monitor)
        }
    }

    /// What a notice does to the chat monitor, pure: a running monitor is
    /// restarted so it reads the new credentials; a stopped one starts when
    /// a source is switched on (it may have been waiting for exactly this
    /// token or sign-in); otherwise it is left alone. Never `.stop`: new
    /// credentials are no reason to stop -- a sign-out has its own notice.
    public static func decide(isRunning: Bool, anySourceEnabled: Bool) -> ChatMonitorReconciliation {
        if isRunning { return .restart }
        return anySourceEnabled ? .start : .none
    }

    /// What the app does on a notice: re-read the login, then act on
    /// `decide`. A restart is stop-then-start, which is what
    /// `ChatMonitorService.restartIfRunning()` does for a running monitor.
    @MainActor public static func apply(config: ConfigManager, monitor: any ChatMonitorControlling) {
        config.checkConnection()
        switch decide(isRunning: monitor.isRunning, anySourceEnabled: config.config.effectiveChatMonitor.anySourceEnabled) {
        case .none, .stop: break
        case .start: monitor.start()
        case .restart:
            monitor.stop()
            monitor.start()
        }
    }
}
