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

    /// The chat monitor's status file, beside the settings.
    public var monitorStatusURL: URL { ChatMonitorStatusFile.url(beside: settingsURL) }

    public init(
        door: Door, settingsURL: URL, historyURL: URL, secretsURL: URL,
        messagePrefix: String, liveLockURL: URL?, toolFolder: URL?
    ) {
        self.door = door
        self.settingsURL = settingsURL
        self.historyURL = historyURL
        self.secretsURL = secretsURL
        self.messagePrefix = messagePrefix
        self.liveLockURL = liveLockURL
        self.toolFolder = toolFolder
    }

    /// The standalone app: today's paths and names, byte for byte. The
    /// settings and history are under `home`; the secrets are in the user's
    /// Application Support, wherever `SecretStore.defaultURL()` says.
    public static func app(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        let gemini = home.appendingPathComponent(".gemini")
        return Self(
            door: .app,
            settingsURL: gemini.appendingPathComponent("speaker_broadcast.json"),
            historyURL: gemini.appendingPathComponent("speaker_history.json"),
            secretsURL: SecretStore.defaultURL(),
            messagePrefix: appMessagePrefix,
            liveLockURL: nil,
            toolFolder: nil)
    }

    /// The Vitruvian extension: everything in `dataFolder`. Tests pass their
    /// own `messagePrefix`, so a real extension on the Mac never hears them.
    public static func `extension`(
        dataFolder: URL, toolFolder: URL?, messagePrefix: String = extensionMessagePrefix
    ) -> Self {
        Self(
            door: .extension,
            settingsURL: dataFolder.appendingPathComponent("settings.json"),
            historyURL: dataFolder.appendingPathComponent("history.json"),
            secretsURL: dataFolder.appendingPathComponent("secrets.json"),
            messagePrefix: messagePrefix,
            liveLockURL: dataFolder.appendingPathComponent("running.lock"),
            toolFolder: toolFolder)
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
