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

// MARK: - The chat monitor, behind the role

/// Whether this side's chat monitor may start now. The extension's tool
/// sets it from its role check (`HomeSpeakerTool.refreshRole`), on the kit's
/// thread; the app sets it from `AppDoor.refresh`. Read on the main actor.
public final class MonitorPermission: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = false
    public init() {}
    public var value: Bool { lock.withLock { allowed } }
    public func set(_ value: Bool) { lock.withLock { allowed = value } }
}

/// A chat monitor as everything that can start it sees it: the settings
/// watcher (`ConfigManager.chatMonitor`), the sign-out and
/// credentials-changed notices, the control message, and the Start buttons.
/// A start is ignored unless `permission` says this side may run (design
/// 7.3): a quiet side never runs a monitor beside the other's. A stop
/// always goes through.
@MainActor
public final class GatedMonitor: ChatMonitorControlling {
    private let monitor: any ChatMonitorControlling
    public nonisolated let permission: MonitorPermission

    public init(_ monitor: any ChatMonitorControlling, permission: MonitorPermission = MonitorPermission()) {
        self.monitor = monitor
        self.permission = permission
    }

    public var isRunning: Bool { monitor.isRunning }

    public func start() {
        guard permission.value else { return }
        monitor.start()
    }

    public func stop() {
        monitor.stop()
    }
}
