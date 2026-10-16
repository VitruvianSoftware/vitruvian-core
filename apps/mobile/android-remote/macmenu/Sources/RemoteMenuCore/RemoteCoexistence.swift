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

/// The shared choice file (`~/.config/vitruvian-remote-agent/remote_door.json`)
/// that records whether the user chose the standalone app or the Vitruvian extension,
/// and where the extension is installed.
public struct RemoteChoice: Codable, Equatable, Sendable {
    public struct ExtensionRecord: Codable, Equatable, Sendable {
        public var program: String
        public var dataFolder: String
        public var version: String

        enum CodingKeys: String, CodingKey {
            case program
            case dataFolder = "data_folder"
            case version
        }

        public init(program: String, dataFolder: String, version: String) {
            self.program = program
            self.dataFolder = dataFolder
            self.version = version
        }
    }

    public var chosen: RemoteProfile.Door?
    public var extensionRecord: ExtensionRecord?

    enum CodingKeys: String, CodingKey {
        case chosen
        case extensionRecord = "extension"
    }

    public init(chosen: RemoteProfile.Door? = nil, extensionRecord: ExtensionRecord? = nil) {
        self.chosen = chosen
        self.extensionRecord = extensionRecord
    }
}

/// Reads and updates `remote_door.json` atomically under `FileLock`.
public enum RemoteChoiceFile {
    public static func read(at url: URL) -> RemoteChoice {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(RemoteChoice.self, from: data)
        else {
            return RemoteChoice()
        }
        return decoded
    }

    @discardableResult
    public static func update(
        at url: URL,
        _ transform: (inout RemoteChoice) -> Void
    ) throws -> RemoteChoice {
        try FileLock.withExclusiveLock(for: url) {
            var current = read(at: url)
            transform(&current)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(current)
            try FileLock.writeAtomically(data, to: url, permissions: 0o600)
            return current
        }
    }

    @discardableResult
    public static func recordExtension(
        program: String,
        dataFolder: String,
        version: String = RemoteVersion.current,
        at url: URL
    ) throws -> RemoteChoice {
        try update(at: url) { choice in
            choice.extensionRecord = .init(
                program: program,
                dataFolder: dataFolder,
                version: version
            )
        }
    }

    @discardableResult
    public static func choose(
        _ door: RemoteProfile.Door?,
        at url: URL
    ) throws -> RemoteChoice {
        try update(at: url) { choice in
            choice.chosen = door
        }
    }
}

/// The operating role of one side (`.app` or `.extension`) given what is installed
/// and what the user has chosen in `remote_door.json`.
public enum RemoteRole: String, Equatable, Sendable {
    /// Only this side is installed; it runs as normal.
    case activeAlone
    /// This side was explicitly chosen; it runs as normal.
    case activeChosen
    /// Both are installed and neither has been chosen yet; `.app` keeps running as
    /// today so existing users experience no outage before answering, and asks which
    /// side to use.
    case activeAsking
    /// Both are installed and neither has been chosen yet; `.extension` stays quiet
    /// so it does not collide on port `7411`, and asks which side to use.
    case quietAsking
    /// The other side was chosen; this side stays quiet and offers a one-click switch.
    case quietChosen

    /// Whether this side should run `vitruvian-remote-agent` and poll live status.
    public var isActive: Bool {
        switch self {
        case .activeAlone, .activeChosen, .activeAsking:
            return true
        case .quietAsking, .quietChosen:
            return false
        }
    }

    /// Whether both sides are installed and the user has not picked one yet.
    public var needsChoicePrompt: Bool {
        switch self {
        case .activeAsking, .quietAsking:
            return true
        case .activeAlone, .activeChosen, .quietChosen:
            return false
        }
    }

    /// Computes the role for `door` given `choice`, `appInstalled`, and `extensionInstalled`.
    /// If the chosen side is no longer installed on disk (e.g. the user deleted the app or
    /// removed the extension), the remaining installed side becomes `.activeAlone`.
    public static func resolve(
        for door: RemoteProfile.Door,
        choice: RemoteChoice,
        appInstalled: Bool,
        extensionInstalled: Bool
    ) -> RemoteRole {
        let otherInstalled = (door == .app) ? extensionInstalled : appInstalled
        if !otherInstalled {
            return .activeAlone
        }
        guard let chosen = choice.chosen else {
            return (door == .app) ? .activeAsking : .quietAsking
        }
        return (chosen == door) ? .activeChosen : .quietChosen
    }
}

/// Detects whether the standalone app/agent and the Vitruvian extension are installed
/// on this Mac, summarizes what each side holds, and copies settings + `0600` tokens across.
public enum RemoteCoexistence {
    /// Standard locations where `VitruvianRemote.app` may be installed.
    public static func defaultAppBundlePaths(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        [
            "/Applications/VitruvianRemote.app",
            home.appendingPathComponent("Applications/VitruvianRemote.app").path,
        ]
    }

    /// True when the standalone app bundle, `~/.local/bin/vitruvian-remote-agent`, or
    /// `~/Library/LaunchAgents/com.vitruvian.remote-agent.plist` exists on disk.
    public static func isStandaloneInstalled(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appBundlePaths: [String]? = nil,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        let bundles = appBundlePaths ?? defaultAppBundlePaths(home: home)
        if bundles.contains(where: { fileExists($0) }) {
            return true
        }
        let paths = AgentPaths(home: home)
        if fileExists(paths.binary.path) {
            return true
        }
        let plistPath = home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(AgentPaths.label).plist")
            .path
        return fileExists(plistPath)
    }

    /// True when `remote_door.json` names an extension whose `bin/tool` executable exists on disk.
    public static func isExtensionInstalled(
        choice: RemoteChoice,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Bool {
        guard let record = choice.extensionRecord, !record.program.isEmpty else {
            return false
        }
        return fileExists(record.program)
    }

    /// Resolves the extension's `RemoteProfile` from `remote_door.json` when called from
    /// the standalone app.
    public static func extensionProfile(
        from choice: RemoteChoice,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        choiceFileURL: URL? = nil
    ) -> RemoteProfile? {
        guard let record = choice.extensionRecord, !record.dataFolder.isEmpty else {
            return nil
        }
        let dataURL = URL(fileURLWithPath: record.dataFolder, isDirectory: true)
        let programURL = URL(fileURLWithPath: record.program)
        let toolFolder = RemoteProfile.extensionFolders(program: programURL)?.tool
            ?? programURL.deletingLastPathComponent().deletingLastPathComponent()
        return .extension(
            dataFolder: dataURL,
            toolFolder: toolFolder,
            home: home,
            choiceFileURL: choiceFileURL
        )
    }
}

/// Human-readable summary of what one side (`.app` or `.extension`) currently has configured,
/// shown in the choice/copy prompt so the user knows what will be copied.
public struct RemoteSideSummary: Equatable, Sendable {
    public var door: RemoteProfile.Door
    public var isPaired: Bool
    public var pairedAt: String?
    public var notificationsConfigured: Bool
    public var ntfyTopic: String
    public var kubeContext: String
    public var prometheusConfigured: Bool
    public var ghExtraRepos: String
    public var hasMCPToken: Bool
    public var hasHookToken: Bool

    public init(
        door: RemoteProfile.Door,
        isPaired: Bool = false,
        pairedAt: String? = nil,
        notificationsConfigured: Bool = false,
        ntfyTopic: String = "",
        kubeContext: String = "",
        prometheusConfigured: Bool = false,
        ghExtraRepos: String = "",
        hasMCPToken: Bool = false,
        hasHookToken: Bool = false
    ) {
        self.door = door
        self.isPaired = isPaired
        self.pairedAt = pairedAt
        self.notificationsConfigured = notificationsConfigured
        self.ntfyTopic = ntfyTopic
        self.kubeContext = kubeContext
        self.prometheusConfigured = prometheusConfigured
        self.ghExtraRepos = ghExtraRepos
        self.hasMCPToken = hasMCPToken
        self.hasHookToken = hasHookToken
    }

    public static func inspect(_ profile: RemoteProfile) -> RemoteSideSummary {
        let store = RemoteSettingsStore(profile: profile)
        let settings = store.load()
        return RemoteSideSummary(
            door: profile.door,
            isPaired: store.isPairedOnDisk,
            pairedAt: store.pairedTimestampString,
            notificationsConfigured: settings.notificationsConfigured,
            ntfyTopic: settings.ntfyTopic,
            kubeContext: settings.kubeContext,
            prometheusConfigured: !settings.prometheusURL.isEmpty,
            ghExtraRepos: settings.ghExtraRepos,
            hasMCPToken: RemoteSettings.defaultNonEmptyFileExists(profile.mcpTokenURL),
            hasHookToken: RemoteSettings.defaultNonEmptyFileExists(profile.hookTokenURL)
        )
    }

    /// True if this side has any pairing, tokens, or non-default settings worth copying.
    public var hasDataToCopy: Bool {
        isPaired || notificationsConfigured || !kubeContext.isEmpty || prometheusConfigured || !ghExtraRepos.isEmpty
    }

    /// Concise one-line description of what this side holds.
    public var summaryLine: String {
        var parts: [String] = []
        parts.append(isPaired ? "Phone paired" : "No phone paired")
        if notificationsConfigured {
            parts.append("push topic \(ntfyTopic)")
        }
        if !kubeContext.isEmpty {
            parts.append("k8s \(kubeContext)")
        }
        if prometheusConfigured {
            parts.append("Prometheus")
        }
        if !ghExtraRepos.isEmpty {
            parts.append("extra repos")
        }
        return parts.joined(separator: " · ")
    }
}

/// Copies settings and `0600` credentials/state between `.app` and `.extension` so a
/// paired phone and registered `/mcp/phone` client keep working without re-pairing.
public enum RemoteDataCopy {
    public struct CopyResult: Equatable, Sendable {
        public var copiedSettings: RemoteSettings
        public var copiedFiles: [String]

        public init(copiedSettings: RemoteSettings, copiedFiles: [String]) {
            self.copiedSettings = copiedSettings
            self.copiedFiles = copiedFiles
        }
    }

    @discardableResult
    public static func copy(
        from source: RemoteProfile,
        to destination: RemoteProfile,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> CopyResult {
        let sourceStore = RemoteSettingsStore(profile: source)
        let settings = sourceStore.load()
        let destStore = RemoteSettingsStore(profile: destination)
        try destStore.save(settings)

        try FileManager.default.createDirectory(
            at: destination.configDirURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )

        var copiedFiles: [String] = []
        for fileName in RemoteProfile.portableConfigFileNames {
            let srcURL = source.configDirURL.appendingPathComponent(fileName)
            let dstURL = destination.configDirURL.appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: srcURL), !data.isEmpty {
                try FileLock.writeAtomically(data, to: dstURL, permissions: 0o600)
                copiedFiles.append(fileName)
            }
        }

        // If copying from .app and the LaunchAgent plist pointed --prometheus-token-file
        // or --ntfy-token-file at a custom path outside configDirURL, import those files too.
        if source.door == .app,
           let plistURL = source.launchAgentPlistURL,
           let imported = RemoteSettings.importFromLaunchAgentPlist(at: plistURL)
        {
            if !copiedFiles.contains("prometheus-token"),
               let customProm = imported.prometheusTokenFile
            {
                let expanded = RemoteSettings.expandTilde(customProm, home: home)
                if let data = try? Data(contentsOf: URL(fileURLWithPath: expanded)), !data.isEmpty {
                    try FileLock.writeAtomically(data, to: destination.prometheusTokenURL, permissions: 0o600)
                    copiedFiles.append("prometheus-token")
                }
            }
            if !copiedFiles.contains("ntfy-token"),
               let customNtfy = imported.ntfyTokenFile
            {
                let expanded = RemoteSettings.expandTilde(customNtfy, home: home)
                if let data = try? Data(contentsOf: URL(fileURLWithPath: expanded)), !data.isEmpty {
                    try FileLock.writeAtomically(data, to: destination.ntfyTokenURL, permissions: 0o600)
                    copiedFiles.append("ntfy-token")
                }
            }
        }

        return CopyResult(copiedSettings: settings, copiedFiles: copiedFiles)
    }
}
