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

import AppKit
import Foundation

/// Where one HomeSpeaker keeps its settings, sign-ins, history and status,
/// and the names its processes talk to each other on.
///
/// There are two: the standalone app, which keeps today's files exactly,
/// and the Vitruvian extension, which keeps its own in the data folder
/// Vitruvian gives it. The two never share a file, so neither can undo or
/// overwrite what the other saved.
///
/// | | `.app` | `.extension` |
/// |---|---|---|
/// | Settings | `~/.gemini/speaker_broadcast.json` | `<data>/settings.json` |
/// | Sign-ins (0600) | `~/Library/Application Support/HomeSpeaker/secrets.json` | `<data>/secrets.json` |
/// | History | `~/.gemini/speaker_history.json` | `<data>/history.json` |
/// | Chat monitor status | `~/.gemini/speaker_monitor_status.json` | `<data>/speaker_monitor_status.json` |
/// | Messages | `com.vitruviansoftware.homespeaker.*` | `dev.vitruvian.homespeaker.*` |
/// | "Am I alive" | the running app's bundle id | a lock on `<data>/running.lock` |
public struct HomeSpeakerProfile: Sendable, Equatable {
    /// Which HomeSpeaker this is.
    public enum Door: String, Sendable, Equatable {
        /// The standalone menu bar app.
        case app
        /// The Vitruvian extension.
        case `extension`
    }

    /// The app's message names, as they have always been.
    public static let appMessagePrefix = "com.vitruviansoftware.homespeaker"
    /// The extension's: its tool id, so nothing it posts reaches the app.
    public static let extensionMessagePrefix = "dev.vitruvian.homespeaker"

    public let door: Door
    public let settingsURL: URL
    public let historyURL: URL
    public let secretsURL: URL
    /// Cross-process messages are named `<messagePrefix>.<what>`.
    public let messagePrefix: String
    /// Held while this HomeSpeaker's long-lived process runs, so another
    /// process can tell whether anything is alive. Nil for the app, which
    /// is found by its bundle id instead.
    public let liveLockURL: URL?
    /// The extension's installed folder (`…/Tools/<id>`). Nil for the app.
    public let toolFolder: URL?
    /// The bundle of the program that runs this profile. Only the app reads
    /// it, for the sign-in client packaged in its Info.plist; the
    /// extension never does.
    public let bundle: Bundle

    /// The chat monitor's status file, beside the settings.
    public var monitorStatusURL: URL { ChatMonitorStatusFile.url(beside: settingsURL) }

    /// Cross-process speech lock URL: both real doors share
    /// `/tmp/homespeaker_speech.lock` so an app announcement and an extension
    /// announcement never talk over each other, while test profiles (whose
    /// files live in a scratch folder) lock inside their own folder so
    /// parallel tests never contend with each other or with this Mac.
    public var speechLockURL: URL {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if (messagePrefix == Self.appMessagePrefix || messagePrefix == Self.extensionMessagePrefix),
           settingsURL.standardizedFileURL.path.hasPrefix(homePath + "/") {
            return SpeechLock.defaultURL
        }
        return settingsURL.deletingLastPathComponent().appendingPathComponent("speech.lock")
    }

    public init(
        door: Door, settingsURL: URL, historyURL: URL, secretsURL: URL,
        messagePrefix: String, liveLockURL: URL?, toolFolder: URL?, bundle: Bundle = .main
    ) {
        self.door = door
        self.settingsURL = settingsURL
        self.historyURL = historyURL
        self.secretsURL = secretsURL
        self.messagePrefix = messagePrefix
        self.liveLockURL = liveLockURL
        self.toolFolder = toolFolder
        self.bundle = bundle
    }

    /// The standalone app: today's paths and names, byte for byte. The
    /// settings and history are under `home`; the secrets are in the user's
    /// Application Support, wherever `SecretStore.defaultURL()` says.
    /// `bundle` is the app's: its Info.plist may carry the sign-in client it
    /// was packaged with. The app is `Bundle.main`; the tool's program,
    /// which drives the app, passes the app's bundle.
    public static func app(
        home: URL = FileManager.default.homeDirectoryForCurrentUser, bundle: Bundle = .main
    ) -> Self {
        let gemini = home.appendingPathComponent(".gemini")
        return Self(
            door: .app,
            settingsURL: gemini.appendingPathComponent("speaker_broadcast.json"),
            historyURL: gemini.appendingPathComponent("speaker_history.json"),
            secretsURL: SecretStore.defaultURL(),
            messagePrefix: appMessagePrefix,
            liveLockURL: nil,
            toolFolder: nil,
            bundle: bundle)
    }

    /// The Vitruvian extension: everything in `dataFolder`. Tests pass their
    /// own `messagePrefix`, so a real extension on the Mac never hears them.
    /// `bundle` is only the program's own; the extension never reads a
    /// sign-in client from it.
    public static func `extension`(
        dataFolder: URL, toolFolder: URL?, messagePrefix: String = extensionMessagePrefix,
        bundle: Bundle = .main
    ) -> Self {
        Self(
            door: .extension,
            settingsURL: dataFolder.appendingPathComponent("settings.json"),
            historyURL: dataFolder.appendingPathComponent("history.json"),
            secretsURL: dataFolder.appendingPathComponent("secrets.json"),
            messagePrefix: messagePrefix,
            liveLockURL: dataFolder.appendingPathComponent("running.lock"),
            toolFolder: toolFolder,
            bundle: bundle)
    }

    /// The Google sign-in client shipped with this HomeSpeaker, read each
    /// time it is asked for. The app's is in its bundle's Info.plist; the
    /// extension's is `google-oauth-client.json` in its tool folder, and
    /// nothing else: a client in whatever bundle runs the extension is not
    /// its own. Nil when none is shipped.
    public var shippedClient: OAuthClient? {
        switch door {
        case .app:
            return OAuthClient.inInfoPlist(of: bundle)
        case .extension:
            guard let toolFolder else { return nil }
            return OAuthClientFile.read(toolFolder.appendingPathComponent(OAuthClientFile.fileName))
        }
    }

    /// The extension's folders, worked out from its program's own path:
    /// `…/Tools/<id>/bin/tool` gives `…/Tools/<id>` and `…/ToolData/<id>`,
    /// the data folder Vitruvian keeps for that tool.
    ///
    /// Nil for any other shape (a build in `bazel-bin`, the app's program, a
    /// relative path), so a program that is not the installed extension
    /// never guesses a data folder.
    public static func extensionFolders(program: URL) -> (tool: URL, data: URL)? {
        guard program.isFileURL, program.baseURL == nil, program.path.hasPrefix("/") else { return nil }
        let parts = program.standardizedFileURL.pathComponents
        // "/", …, parent, "Tools", <id>, "bin", "tool": the parent must be
        // a real folder, not the root.
        guard parts.count >= 6 else { return nil }
        let tail = Array(parts.suffix(4))
        guard tail[0] == "Tools", tail[2] == "bin", tail[3] == "tool" else { return nil }
        let id = tail[1]
        guard !id.isEmpty, id != ".", id != ".." else { return nil }
        let parent = URL(fileURLWithPath: NSString.path(withComponents: Array(parts.dropLast(4))), isDirectory: true)
        return (
            tool: parent.appendingPathComponent("Tools").appendingPathComponent(id),
            data: parent.appendingPathComponent("ToolData").appendingPathComponent(id))
    }
}

// MARK: - Messages between processes

/// The messages HomeSpeaker's processes send each other, as distributed
/// notifications. Each is named `<messagePrefix>.<rawValue>`.
public enum HomeSpeakerMessage: String, CaseIterable, Sendable {
    /// Pause, extend or resume media (`MediaPauseRequest`).
    case mediaPause = "media-pause"
    /// Put a speaker back after an announcement (`VolumeRestoreRequest`).
    case volumeRestore = "volume-restore"
    /// A login was removed (`SignOutNotice`).
    case signedOut = "signed-out"
    /// A login or token was added or changed (`CredentialsChangedNotice`).
    case credentialsChanged = "credentials-changed"
    /// Start or stop the chat monitor (`ChatMonitorControlNotice`).
    case chatMonitorControl = "chat-monitor-control"
}

extension HomeSpeakerProfile {
    /// The name `message` travels under for this HomeSpeaker.
    public func messageName(_ message: HomeSpeakerMessage) -> Notification.Name {
        Notification.Name("\(messagePrefix).\(message.rawValue)")
    }
}

// MARK: - The process's profile

extension HomeSpeakerProfile {
    private final class ProcessProfile: @unchecked Sendable {
        let lock = NSLock()
        var profile: HomeSpeakerProfile?
    }

    private static let processProfile = ProcessProfile()

    /// The profile this process runs as: whatever the program set with
    /// `useForThisProcess(_:)`, or the app's. Every message a caller posts
    /// or listens for without naming a profile goes by it.
    public static var current: HomeSpeakerProfile {
        processProfile.lock.lock()
        defer { processProfile.lock.unlock() }
        return processProfile.profile ?? .app()
    }

    /// Set once, by the program, at its start, before anything posts or
    /// listens. Only entry points call it (the app, the tool's program);
    /// tests pass their profile instead, so they never change the process's.
    public static func useForThisProcess(_ profile: HomeSpeakerProfile) {
        processProfile.lock.lock()
        defer { processProfile.lock.unlock() }
        processProfile.profile = profile
    }
}

// MARK: - Is this side's long-lived process alive

extension HomeSpeakerProfile {
    /// The standalone app's bundle id.
    public static let appBundleID = "com.vitruviansoftware.homespeaker"

    /// One running application, as `NSRunningApplication` describes it.
    public typealias RunningApp = (bundleIdentifier: String?, activationPolicy: NSApplication.ActivationPolicy)

    /// This Mac's running applications with the app's bundle id.
    public static func runningApps() -> [RunningApp] {
        NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID)
            .map { ($0.bundleIdentifier, $0.activationPolicy) }
    }

    /// HomeSpeaker.app is running as an app: a process with its bundle id
    /// whose activation policy is not `.prohibited`. The menu bar app is
    /// `.accessory`; its short-lived command-line runs (`--say`, `--volume`,
    /// the tool's own jobs) carry the same bundle id but never become apps,
    /// and must not count, or a `--volume` read would say it is running.
    public static func isAppRunning(among apps: [RunningApp]) -> Bool {
        apps.contains { $0.bundleIdentifier == appBundleID && $0.activationPolicy != .prohibited }
    }

    /// Is the process that runs this side's chat monitor, and puts volumes
    /// back, alive? The app's is its running app; the extension's holds the
    /// lock on `liveLockURL`. `runningApps` is asked only for the app.
    public func ownerRunning(runningApps: () -> [RunningApp] = HomeSpeakerProfile.runningApps) -> Bool {
        switch door {
        case .app:
            return Self.isAppRunning(among: runningApps())
        case .extension:
            guard let liveLockURL else { return false }
            return LiveLock.isHeld(at: liveLockURL)
        }
    }
}
