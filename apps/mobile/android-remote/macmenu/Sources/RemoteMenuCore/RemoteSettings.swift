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

/// Persisted configuration for `vitruvian-remote-agent` (`settings.json`).
public struct RemoteSettings: Codable, Equatable, Sendable {
    public static let minIntervalSeconds = 1
    public static let maxIntervalSeconds = 60
    public static let defaultIntervalSeconds = 2

    public static let minPermissionWaitSeconds = 5
    public static let maxPermissionWaitSeconds = 140
    public static let defaultPermissionWaitSeconds = 120

    public var tailscale: Bool
    public var intervalSeconds: Int
    public var permissionWaitSeconds: Int
    public var kubeconfig: String
    public var kubeContext: String
    public var prometheusURL: String
    public var ntfyURL: String
    public var ntfyTopic: String
    public var ghExtraRepos: String
    public var execDir: String
    public var autoStartAgent: Bool

    public init(
        tailscale: Bool = true,
        intervalSeconds: Int = Self.defaultIntervalSeconds,
        permissionWaitSeconds: Int = Self.defaultPermissionWaitSeconds,
        kubeconfig: String = "",
        kubeContext: String = "",
        prometheusURL: String = "",
        ntfyURL: String = "",
        ntfyTopic: String = "",
        ghExtraRepos: String = "",
        execDir: String = "",
        autoStartAgent: Bool = true
    ) {
        self.tailscale = tailscale
        self.intervalSeconds = Self.clampInterval(intervalSeconds)
        self.permissionWaitSeconds = Self.clampPermissionWait(permissionWaitSeconds)
        self.kubeconfig = kubeconfig.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kubeContext = kubeContext.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prometheusURL = prometheusURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ntfyURL = ntfyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ntfyTopic = ntfyTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ghExtraRepos = ghExtraRepos.trimmingCharacters(in: .whitespacesAndNewlines)
        self.execDir = execDir.trimmingCharacters(in: .whitespacesAndNewlines)
        self.autoStartAgent = autoStartAgent
    }

    public static func clampInterval(_ seconds: Int) -> Int {
        min(maxIntervalSeconds, max(minIntervalSeconds, seconds))
    }

    public static func clampPermissionWait(_ seconds: Int) -> Int {
        min(maxPermissionWaitSeconds, max(minPermissionWaitSeconds, seconds))
    }

    public var clampedIntervalSeconds: Int { Self.clampInterval(intervalSeconds) }
    public var clampedPermissionWaitSeconds: Int { Self.clampPermissionWait(permissionWaitSeconds) }

    /// Whether both `ntfyURL` and `ntfyTopic` are configured so push notifications can work.
    public var notificationsConfigured: Bool {
        !ntfyURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ntfyTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether this settings struct has any non-default values configured.
    public var hasCustomConfiguration: Bool {
        self != RemoteSettings()
    }

    enum CodingKeys: String, CodingKey {
        case tailscale
        case intervalSeconds = "interval_seconds"
        case permissionWaitSeconds = "permission_wait_seconds"
        case kubeconfig
        case kubeContext = "kube_context"
        case prometheusURL = "prometheus_url"
        case ntfyURL = "ntfy_url"
        case ntfyTopic = "ntfy_topic"
        case ghExtraRepos = "gh_extra_repos"
        case execDir = "exec_dir"
        case autoStartAgent = "auto_start_agent"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tailscale = try c.decodeIfPresent(Bool.self, forKey: .tailscale) ?? true
        let interval = try c.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? Self.defaultIntervalSeconds
        let permWait = try c.decodeIfPresent(Int.self, forKey: .permissionWaitSeconds) ?? Self.defaultPermissionWaitSeconds
        let kubeconfig = try c.decodeIfPresent(String.self, forKey: .kubeconfig) ?? ""
        let kubeContext = try c.decodeIfPresent(String.self, forKey: .kubeContext) ?? ""
        let prometheusURL = try c.decodeIfPresent(String.self, forKey: .prometheusURL) ?? ""
        let ntfyURL = try c.decodeIfPresent(String.self, forKey: .ntfyURL) ?? ""
        let ntfyTopic = try c.decodeIfPresent(String.self, forKey: .ntfyTopic) ?? ""
        let ghExtraRepos = try c.decodeIfPresent(String.self, forKey: .ghExtraRepos) ?? ""
        let execDir = try c.decodeIfPresent(String.self, forKey: .execDir) ?? ""
        let autoStartAgent = try c.decodeIfPresent(Bool.self, forKey: .autoStartAgent) ?? true
        self.init(
            tailscale: tailscale,
            intervalSeconds: interval,
            permissionWaitSeconds: permWait,
            kubeconfig: kubeconfig,
            kubeContext: kubeContext,
            prometheusURL: prometheusURL,
            ntfyURL: ntfyURL,
            ntfyTopic: ntfyTopic,
            ghExtraRepos: ghExtraRepos,
            execDir: execDir,
            autoStartAgent: autoStartAgent
        )
    }

    /// Builds the command-line flags for `vitruvian-remote-agent` from these settings
    /// and `profile`. Never emits `--ntfy-url` without `--ntfy-topic`, never emits
    /// `--ntfy-token-file` or `--prometheus-token-file` unless the file exists and is
    /// non-empty, and never emits `--exec-dir` unless the directory exists on disk,
    /// because `vitruvian-remote-agent` treats any of those mismatches as fatal at startup.
    public func agentArguments(
        for profile: RemoteProfile,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        nonEmptyFileExists: (URL) -> Bool = RemoteSettings.defaultNonEmptyFileExists,
        directoryExists: (String) -> Bool = RemoteSettings.defaultDirectoryExists
    ) -> [String] {
        var args: [String] = []
        let defaultConfigDir = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("vitruvian-remote-agent", isDirectory: true)
            .standardizedFileURL.path
        let profileConfigDir = profile.configDirURL.standardizedFileURL.path
        if profile.door == .extension || profileConfigDir != defaultConfigDir {
            args += ["--config-dir", profileConfigDir]
        }
        if !tailscale {
            args.append("--tailscale=false")
        }
        let interval = clampedIntervalSeconds
        if interval != Self.defaultIntervalSeconds {
            args += ["--interval", "\(interval)s"]
        }
        let wait = clampedPermissionWaitSeconds
        if wait != Self.defaultPermissionWaitSeconds {
            args += ["--permission-wait", "\(wait)s"]
        }
        let kcfg = kubeconfig.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kcfg.isEmpty {
            args += ["--kubeconfig", kcfg]
        }
        let kctx = kubeContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kctx.isEmpty {
            args += ["--kube-context", kctx]
        }
        let prom = prometheusURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prom.isEmpty {
            args += ["--prometheus-url", prom]
            if nonEmptyFileExists(profile.prometheusTokenURL) {
                args += ["--prometheus-token-file", profile.prometheusTokenURL.path]
            }
        }
        let nurl = ntfyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let ntopic = ntfyTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nurl.isEmpty, !ntopic.isEmpty {
            args += ["--ntfy-url", nurl, "--ntfy-topic", ntopic]
            if nonEmptyFileExists(profile.ntfyTokenURL) {
                args += ["--ntfy-token-file", profile.ntfyTokenURL.path]
            }
        }
        let repos = ghExtraRepos.trimmingCharacters(in: .whitespacesAndNewlines)
        if !repos.isEmpty {
            args += ["--gh-extra-repos", repos]
        }
        let dir = execDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dir.isEmpty {
            let expanded = Self.expandTilde(dir, home: home)
            if directoryExists(expanded) {
                args += ["--exec-dir", expanded]
            }
        }
        return args
    }

    public static func defaultNonEmptyFileExists(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func defaultDirectoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    public static func expandTilde(
        _ path: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        if path == "~" { return home.path }
        if path.hasPrefix("~/") {
            return home.path + String(path.dropFirst(1))
        }
        return path
    }

    // MARK: - Importing from ~/Library/LaunchAgents/com.vitruvian.remote-agent.plist

    public struct ImportedPlistConfiguration: Equatable, Sendable {
        public var settings: RemoteSettings
        public var prometheusTokenFile: String?
        public var ntfyTokenFile: String?

        public init(
            settings: RemoteSettings,
            prometheusTokenFile: String? = nil,
            ntfyTokenFile: String? = nil
        ) {
            self.settings = settings
            self.prometheusTokenFile = prometheusTokenFile
            self.ntfyTokenFile = ntfyTokenFile
        }
    }

    /// Reads `ProgramArguments` from a LaunchAgent plist (`com.vitruvian.remote-agent.plist`)
    /// and turns its flags into a `RemoteSettings` struct plus any external token file paths.
    public static func importFromLaunchAgentPlist(at plistURL: URL) -> ImportedPlistConfiguration? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let programArgs = plist["ProgramArguments"] as? [String],
              !programArgs.isEmpty
        else {
            return nil
        }
        return parseProgramArguments(programArgs)
    }

    /// Parses `ProgramArguments` from `vitruvian-remote-agent` (supports both `--flag value`
    /// and `--flag=value` syntax).
    public static func parseProgramArguments(_ programArgs: [String]) -> ImportedPlistConfiguration {
        var settings = RemoteSettings()
        var promTokFile: String?
        var ntfyTokFile: String?

        let flags = Array(programArgs.dropFirst())
        var idx = 0
        while idx < flags.count {
            let arg = flags[idx]
            let key: String
            let inlineValue: String?
            if let eq = arg.firstIndex(of: "=") {
                key = String(arg[..<eq])
                inlineValue = String(arg[arg.index(after: eq)...])
            } else {
                key = arg
                inlineValue = nil
            }
            func nextValue() -> String? {
                if let inlineValue { return inlineValue }
                guard idx + 1 < flags.count else { return nil }
                idx += 1
                return flags[idx]
            }
            switch key {
            case "--tailscale", "-tailscale":
                if let inlineValue {
                    settings.tailscale = (inlineValue.lowercased() != "false" && inlineValue != "0")
                } else if idx + 1 < flags.count, !flags[idx + 1].hasPrefix("-") {
                    idx += 1
                    let v = flags[idx].lowercased()
                    settings.tailscale = (v != "false" && v != "0")
                } else {
                    settings.tailscale = true
                }
            case "--interval", "-interval":
                if let v = nextValue(), let secs = parseDurationSeconds(v) {
                    settings.intervalSeconds = clampInterval(secs)
                }
            case "--permission-wait", "-permission-wait":
                if let v = nextValue(), let secs = parseDurationSeconds(v) {
                    settings.permissionWaitSeconds = clampPermissionWait(secs)
                }
            case "--kubeconfig", "-kubeconfig":
                if let v = nextValue() { settings.kubeconfig = v }
            case "--kube-context", "-kube-context":
                if let v = nextValue() { settings.kubeContext = v }
            case "--prometheus-url", "-prometheus-url":
                if let v = nextValue() { settings.prometheusURL = v }
            case "--prometheus-token-file", "-prometheus-token-file":
                if let v = nextValue(), !v.isEmpty { promTokFile = v }
            case "--ntfy-url", "-ntfy-url":
                if let v = nextValue() { settings.ntfyURL = v }
            case "--ntfy-topic", "-ntfy-topic":
                if let v = nextValue() { settings.ntfyTopic = v }
            case "--ntfy-token-file", "-ntfy-token-file":
                if let v = nextValue(), !v.isEmpty { ntfyTokFile = v }
            case "--gh-extra-repos", "-gh-extra-repos":
                if let v = nextValue() { settings.ghExtraRepos = v }
            case "--exec-dir", "-exec-dir":
                if let v = nextValue() { settings.execDir = v }
            default:
                break
            }
            idx += 1
        }
        return ImportedPlistConfiguration(
            settings: settings,
            prometheusTokenFile: promTokFile,
            ntfyTokenFile: ntfyTokFile
        )
    }

    /// Parses Go `time.Duration` strings like `"2s"`, `"2m"`, `"120s"`, or plain integer seconds.
    public static func parseDurationSeconds(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let plain = Int(trimmed) { return plain }
        if trimmed.hasSuffix("ms") {
            guard let ms = Double(trimmed.dropLast(2)) else { return nil }
            return Int((ms / 1000.0).rounded())
        }
        if trimmed.hasSuffix("s") {
            guard let secs = Double(trimmed.dropLast(1)) else { return nil }
            return Int(secs.rounded())
        }
        if trimmed.hasSuffix("m") {
            guard let mins = Double(trimmed.dropLast(1)) else { return nil }
            return Int((mins * 60.0).rounded())
        }
        return nil
    }
}

/// Manages reading and writing `RemoteSettings` (`settings.json`) and the `0600`
/// token/state files inside a `RemoteProfile`'s `configDirURL`.
public final class RemoteSettingsStore: @unchecked Sendable {
    public let profile: RemoteProfile
    private let lock = NSLock()

    public init(profile: RemoteProfile) {
        self.profile = profile
    }

    /// Reads `settings.json` for this profile. For `.app`, if `settings.json` does not
    /// exist yet, falls back to importing the flags from `com.vitruvian.remote-agent.plist`
    /// so an existing LaunchAgent installation's flags show up automatically.
    public func load() -> RemoteSettings {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? Data(contentsOf: profile.settingsURL),
           let decoded = try? JSONDecoder().decode(RemoteSettings.self, from: data)
        {
            return decoded
        }
        if profile.door == .app,
           let plistURL = profile.launchAgentPlistURL,
           let imported = RemoteSettings.importFromLaunchAgentPlist(at: plistURL)
        {
            return imported.settings
        }
        return RemoteSettings()
    }

    /// Saves `settings` atomically under `FileLock` with `0600` permissions.
    public func save(_ settings: RemoteSettings) throws {
        lock.lock()
        defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileLock.withExclusiveLock(for: profile.settingsURL) {
            try FileLock.writeAtomically(data, to: profile.settingsURL, permissions: 0o600)
        }
    }

    /// Mutates the stored settings atomically and returns the updated value.
    @discardableResult
    public func update(_ transform: (inout RemoteSettings) -> Void) throws -> RemoteSettings {
        var current = load()
        transform(&current)
        try save(current)
        return current
    }

    // MARK: - 0600 Token & State Files

    public var hasNtfyToken: Bool {
        RemoteSettings.defaultNonEmptyFileExists(profile.ntfyTokenURL)
    }

    public var hasPrometheusToken: Bool {
        RemoteSettings.defaultNonEmptyFileExists(profile.prometheusTokenURL)
    }

    public var isPairedOnDisk: Bool {
        RemoteSettings.defaultNonEmptyFileExists(profile.pairedURL)
    }

    public var pairedTimestampString: String? {
        guard let data = try? Data(contentsOf: profile.pairedURL) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Reads `notify-enabled` from `configDirURL`. Matches `Store.NotifyEnabled()` in `macagent`:
    /// `"0"` means muted (`false`); anything else (including missing file) means enabled (`true`).
    public var notifyEnabledOnDisk: Bool {
        guard let data = try? Data(contentsOf: profile.notifyEnabledURL) else { return true }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text != "0"
    }

    public func setNotifyEnabledOnDisk(_ enabled: Bool) throws {
        let value = enabled ? "1\n" : "0\n"
        try FileLock.writeAtomically(Data(value.utf8), to: profile.notifyEnabledURL, permissions: 0o600)
    }

    public func saveNtfyToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try clearNtfyToken()
            return
        }
        try FileLock.writeAtomically(Data((trimmed + "\n").utf8), to: profile.ntfyTokenURL, permissions: 0o600)
    }

    public func clearNtfyToken() throws {
        if FileManager.default.fileExists(atPath: profile.ntfyTokenURL.path) {
            try FileManager.default.removeItem(at: profile.ntfyTokenURL)
        }
    }

    public func savePrometheusToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try clearPrometheusToken()
            return
        }
        try FileLock.writeAtomically(Data((trimmed + "\n").utf8), to: profile.prometheusTokenURL, permissions: 0o600)
    }

    public func clearPrometheusToken() throws {
        if FileManager.default.fileExists(atPath: profile.prometheusTokenURL.path) {
            try FileManager.default.removeItem(at: profile.prometheusTokenURL)
        }
    }
}
