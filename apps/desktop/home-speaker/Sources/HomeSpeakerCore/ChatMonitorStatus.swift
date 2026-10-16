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

// The chat monitor runs inside HomeSpeaker.app. Other processes -- the
// Vitruvian tool above all -- could only guess at it from the settings file:
// "a source is on" said nothing about whether anything was polling, when it
// last did, or what went wrong. So the app writes what it is doing to a file
// of its own, and takes start and stop requests over a distributed
// notification, the way the sign-out and credentials notices already work.

/// What the running monitor is doing, as the app last wrote it.
public struct ChatMonitorStatus: Codable, Equatable, Sendable {
    public var isRunning: Bool
    /// When the last poll finished.
    public var lastPollDate: Date?
    /// What went wrong while running: a poll or an announcement that failed.
    /// Never the setup problems (no token, no Chat permission): every reader
    /// works those out from the settings and credentials it can see.
    public var lastError: String?
    /// The Slack user the token belongs to, once Slack has said.
    public var slackIdentity: String?
    /// How Google Chat is being read: "api" or "gws"; nil when it is not.
    public var activeGoogleChatBackend: String?
    /// The app process that wrote it.
    public var pid: Int32

    public init(isRunning: Bool = false, lastPollDate: Date? = nil, lastError: String? = nil, slackIdentity: String? = nil,
                activeGoogleChatBackend: String? = nil, pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.isRunning = isRunning
        self.lastPollDate = lastPollDate
        self.lastError = lastError
        self.slackIdentity = slackIdentity
        self.activeGoogleChatBackend = activeGoogleChatBackend
        self.pid = pid
    }

    /// snake_case, as the other files in `~/.gemini` are.
    enum CodingKeys: String, CodingKey {
        case isRunning = "is_running"
        case lastPollDate = "last_poll_date"
        case lastError = "last_error"
        case slackIdentity = "slack_identity"
        case activeGoogleChatBackend = "active_google_chat_backend"
        case pid
    }

    /// What a reader should believe: a status that says "running" from an
    /// owner (the app, or the extension's process) that is not running is a
    /// crash or a kill, never a monitor.
    public func believed(ownerRunning: Bool) -> ChatMonitorStatus {
        guard !ownerRunning else { return self }
        var status = self
        status.isRunning = false
        status.lastError = nil
        return status
    }
}

/// `~/.gemini/speaker_monitor_status.json`, beside the settings file.
/// Written under an exclusive `FileLock` on its own `.lock` file, replaced
/// atomically, so a reader takes no lock and never sees half a file.
public struct ChatMonitorStatusFile: Sendable {
    public static let fileName = "speaker_monitor_status.json"

    public let url: URL
    public var lockURL: URL { url.appendingPathExtension("lock") }

    public init(url: URL) {
        self.url = url
    }

    /// The status file in the folder `settingsURL` is in.
    public static func url(beside settingsURL: URL) -> URL {
        settingsURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    public static func defaultURL() -> URL {
        url(beside: ConfigManager.defaultConfigURL())
    }

    /// Nil when there is no file, or none that reads.
    public func read() -> ChatMonitorStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(ChatMonitorStatus.self, from: data)
    }

    public func write(_ status: ChatMonitorStatus) throws {
        let data = try Self.encoder.encode(status)
        try FileLock.withExclusiveLock(at: lockURL) {
            try data.write(to: url, options: .atomic)
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Start or stop the monitor in a running HomeSpeaker.
public enum ChatMonitorAction: String, CaseIterable, Sendable {
    case start, stop
}

/// The request, over a distributed notification: from the Vitruvian tool,
/// or from `HomeSpeaker --chat-monitor start|stop`.
public enum ChatMonitorControlNotice {
    /// The name the request travels under for `profile`.
    public static func notificationName(for profile: HomeSpeakerProfile) -> Notification.Name {
        profile.messageName(.chatMonitorControl)
    }

    public static let flag = "--chat-monitor"

    /// The other process's side. `name` is the process's profile's unless
    /// given; tests give their own, so they never reach a real running app.
    public static func post(_ action: ChatMonitorAction, name: Notification.Name = notificationName(for: .current)) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: ["action": action.rawValue], deliverImmediately: true)
    }

    /// The app's side: run `handle` on the main actor for each request
    /// that names an action. Anything else is ignored.
    @MainActor public static func listen(
        name: Notification.Name = notificationName(for: .current),
        handle: @escaping @MainActor @Sendable (ChatMonitorAction) -> Void
    ) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { note in
            guard let action = (note.userInfo?["action"] as? String).flatMap(ChatMonitorAction.init(rawValue:)) else { return }
            Task { @MainActor in handle(action) }
        }
    }

    /// The app's side, wired to the chat monitor.
    @MainActor public static func listen(
        name: Notification.Name = notificationName(for: .current), monitor: any ChatMonitorControlling
    ) -> NSObjectProtocol {
        listen(name: name) { [weak monitor] action in
            guard let monitor else { return }
            apply(action, monitor: monitor)
        }
    }

    /// What a request does: exactly what the Settings buttons do.
    @MainActor public static func apply(_ action: ChatMonitorAction, monitor: any ChatMonitorControlling) {
        switch action {
        case .start: monitor.start()
        case .stop: monitor.stop()
        }
    }

    /// `--chat-monitor start|stop`, which must come first. Nil when the
    /// arguments do not start with it.
    public static func parse(_ arguments: [String]) -> Result<ChatMonitorAction, UsageError>? {
        guard arguments.first == flag else { return nil }
        let rest = arguments.dropFirst()
        let valid = ChatMonitorAction.allCases.map(\.rawValue).joined(separator: " or ")
        guard rest.count == 1, let word = rest.first else {
            return .failure(UsageError("\(flag) takes one of \(valid)"))
        }
        guard let action = ChatMonitorAction(rawValue: word) else {
            return .failure(UsageError("\(flag) takes one of \(valid), not \"\(word)\""))
        }
        return .success(action)
    }

    /// What the CLI prints once it has asked.
    public static func askedLine(_ action: ChatMonitorAction) -> String {
        "asked a running HomeSpeaker to \(action.rawValue) the chat monitor"
    }
}
