// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianToolKit
import VitruvianToolProtocol

/// The app, as the tool reaches it: the requests the tool makes, behind a
/// protocol so the tests stand in for the app. `main.swift` makes one over
/// the kit's `App` and `Panel`s.
public protocol ToolHost: AnyObject {
    var language: String { get }
    /// One of the manifest's preferences; nil when the app refused.
    func value(_ key: String) -> JSONValue?
    func setValue(_ value: JSONValue, for key: String)
    func showMessage(_ message: String, icon: String)
    @discardableResult
    func open(_ url: String) -> Bool
    func log(_ message: String)
    func badge(count: Int?, dot: Bool)
    /// A new page for a panel, when it is open; nothing otherwise.
    func render(panel: String, _ tree: UITree)
}

/// The tool: what it knows and what it does. One instance, used from the
/// one thread the kit runs on. The kit's handlers and timer call in; the
/// pages are read from `Pages`.
public final class GitHubTool {
    public static let islandPanel = "status"
    public static let settingsPanel = "settings"
    /// How often the kit's timer calls `tick()`; the polls are paced on it.
    public static let tickSeconds: TimeInterval = 5

    /// The manifest's preferences, by id.
    public enum Preference {
        public static let watchlist = "watchlist"
        public static let pollInterval = "pollInterval"
        public static let pollActiveInterval = "pollActiveInterval"
        public static let mouseIndicator = "mouseIndicator"
        public static let mouseCommand = "mouseCommand"
        public static let mouseSuccess = "mouseSuccess"
        public static let mouseRunning = "mouseRunning"
        public static let mouseFailure = "mouseFailure"
        public static let mouseApproval = "mouseApproval"
        public static let mouseIdle = "mouseIdle"
        public static let clientID = "clientID"
        /// The app's GitHub feature's token, handed over once (no title, so
        /// it is never shown). The tool moves it to its secret store and
        /// clears it.
        public static let migratedToken = "migratedToken"
    }

    /// What the tool is made of, so a test gives it a host that records, a
    /// transport that answers itself, a mouse that records and files of
    /// its own.
    public struct Parts {
        public var host: ToolHost
        public var api: GitHubAPI
        public var secrets: SecretStore
        public var cliHosts: URL
        public var now: () -> Date
        public var environment: [String: String]
        public var home: String
        public var isExecutable: (String) -> Bool
        /// Runs the mouse command at a path with arguments.
        public var runMouse: (String, [String]) -> Void

        public init(host: ToolHost, api: GitHubAPI, secrets: SecretStore, cliHosts: URL = CLIAccount.defaultHostsURL,
                    now: @escaping () -> Date = { Date() },
                    environment: [String: String] = ProcessInfo.processInfo.environment,
                    home: String = Paths.home,
                    isExecutable: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                    runMouse: @escaping (String, [String]) -> Void = MouseDriver.run(binary:arguments:)) {
            self.host = host
            self.api = api
            self.secrets = secrets
            self.cliHosts = cliHosts
            self.now = now
            self.environment = environment
            self.home = home
            self.isExecutable = isExecutable
            self.runMouse = runMouse
        }
    }

    public private(set) var auth: AuthState = .signedOut
    public private(set) var states: [RepoKey: RepoState] = [:]
    public private(set) var summary = GitHubSummary(states: [:], watched: [])
    /// When the next poll is due; nil until signed in.
    public private(set) var nextPollAt: Date?

    private let parts: Parts
    private let mouse: MouseDriver
    private var token: String?
    private var identity: GitHubIdentity?
    private var deviceFlow: DeviceFlowState = .idle
    private var clientIDInFlow = ""
    /// The first snapshot after a start always writes the mouse.
    private var firstSnapshot = true
    /// The person signed out on purpose this run: the CLI's login must not
    /// sign them straight back in.
    private var cliDeclined = false
    /// The last token GitHub answered 401 to; never tried again by itself.
    private var rejectedToken: String?

    public init(parts: Parts) {
        self.parts = parts
        let run = parts.runMouse
        var binary: String?
        mouse = MouseDriver { arguments in
            if let binary { run(binary, arguments) }
        }
        locateMouse = { binary = $0 }
    }

    /// Tells the mouse driver which command to run; set at each use.
    private var locateMouse: (String?) -> Void

    // MARK: Preferences

    private var host: ToolHost { parts.host }

    private func string(_ key: String, _ fallback: String = "") -> String {
        host.value(key)?.stringValue ?? fallback
    }

    private func int(_ key: String, _ fallback: Int) -> Int {
        host.value(key)?.numberValue.flatMap { Int(exactly: $0) } ?? fallback
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        host.value(key)?.boolValue ?? fallback
    }

    /// The watched repositories. An empty preference watches the default,
    /// as the app's feature did.
    public var watched: [RepoKey] {
        let parsed = Watchlist.parse(string(Preference.watchlist, Watchlist.defaultText))
        return parsed.isEmpty ? [Watchlist.defaultRepository] : parsed
    }

    private var mouseSettings: MouseSettings {
        let defaults = MouseSettings.defaults
        return MouseSettings(success: string(Preference.mouseSuccess, defaults.success),
                             running: string(Preference.mouseRunning, defaults.running),
                             failure: string(Preference.mouseFailure, defaults.failure),
                             approval: string(Preference.mouseApproval, defaults.approval),
                             idle: string(Preference.mouseIdle, defaults.idle))
    }

    /// The mouse command this Mac would run now, or nil when none is found.
    public func mouseCommand() -> String? {
        MouseCommand.locate(configured: string(Preference.mouseCommand), environment: parts.environment,
                            home: parts.home, isExecutable: parts.isExecutable)
    }

    // MARK: Starting

    /// After the app's hello: takes what the app's feature handed over,
    /// signs in with what is saved or with the GitHub CLI's login, and polls.
    public func start() {
        takeHandedToken()
        if let saved = parts.secrets.token() {
            signIn(with: saved, save: false)
        } else {
            signInWithCLIIfPossible()
        }
    }

    private func takeHandedToken() {
        let handed = string(Preference.migratedToken)
        guard !handed.isEmpty else { return }
        if parts.secrets.token() == nil {
            do {
                try parts.secrets.save(token: handed)
                host.log("took the sign-in the app handed over")
            } catch {
                host.log("could not keep the sign-in the app handed over: \(error)")
                return
            }
        }
        host.setValue(.string(""), for: Preference.migratedToken)
    }

    private func signInWithCLIIfPossible() {
        guard !cliDeclined, let account = CLIAccount.read(hostsFile: parts.cliHosts),
              account.token != rejectedToken else { return }
        signIn(with: account.token, save: true)
    }

    /// `GET /user` with the token. Signed in on 200, and the token is kept;
    /// on 401 the token is dropped; on no answer the token stays and the
    /// next poll tries again.
    private func signIn(with token: String, save: Bool) {
        auth = .checking
        self.token = token
        identity = nil
        renderSettings()
        do {
            let me = try parts.api.identity(token: token)
            identity = me
            auth = .signedIn(login: me.login)
            if save { try? parts.secrets.save(token: token) }
            nextPollAt = parts.now()
            poll()
        } catch APIError.refused(status: 401) {
            rejectedToken = token
            self.token = nil
            parts.secrets.clear()
            auth = .failed(.tokenRejected)
        } catch APIError.refused(let status) {
            auth = .failed(.refused(status: status))
        } catch {
            auth = .failed(.unreachable)
            nextPollAt = parts.now().addingTimeInterval(TimeInterval(int(Preference.pollInterval, 30)))
        }
        renderSettings()
    }

    public func signOut() {
        cliDeclined = true
        token = nil
        identity = nil
        rejectedToken = nil
        parts.secrets.clear()
        deviceFlow = .idle
        auth = .signedOut
        states = [:]
        summary = GitHubSummary(states: [:], watched: watched)
        nextPollAt = nil
        host.badge(count: nil, dot: false)
        if bool(Preference.mouseIndicator, true) {
            locateMouse(mouseCommand())
            mouse.restore()
        }
        renderIsland()
        renderSettings()
    }

    // MARK: Polling

    /// The kit's timer: a device flow's poll when one is due, else a poll
    /// of GitHub when one is due.
    public func tick() {
        let now = parts.now()
        if case .awaitingUser = deviceFlow {
            deviceFlow = deviceFlow.next(.tick, now: now)
            if deviceFlow.shouldPoll(now: now), case .awaitingUser(let waiting) = deviceFlow {
                let result = parts.api.pollDeviceCode(clientID: clientIDInFlow, deviceCode: waiting.deviceCode)
                deviceFlow = deviceFlow.next(.poll(result), now: parts.now())
            }
            switch deviceFlow {
            case .authorized(let token):
                deviceFlow = .idle
                signIn(with: token.value, save: true)
            case .failed(let failure):
                deviceFlow = .idle
                auth = .failed(.deviceFlow(failure))
                renderSettings()
            case .awaitingUser, .idle, .requestingCode:
                break
            }
            return
        }
        if let due = nextPollAt, now >= due, token != nil {
            if identity == nil, let token { signIn(with: token, save: false) } else { poll() }
        }
    }

    /// Asks GitHub now, whatever the pace.
    public func refresh() {
        guard token != nil else { return }
        if identity == nil, let token { signIn(with: token, save: false) } else { poll() }
        host.showMessage(Words.plain("refreshed", language: host.language), icon: "arrow.triangle.branch")
    }

    /// Opens the person's pull requests on GitHub.
    public func openPulls() {
        host.open("https://github.com/pulls")
    }

    private func poll() {
        guard let token, identity != nil else { return }
        let watched = watched
        var next = states
        for repo in watched {
            do {
                if let updated = try parts.api.snapshot(repo: repo, token: token, known: states[repo], now: parts.now()) {
                    next[repo] = updated
                } else {
                    host.log("could not read \(repo.fullName): GitHub did not give it")
                }
            } catch APIError.refused(status: 401) {
                rejectedToken = token
                self.token = nil
                identity = nil
                parts.secrets.clear()
                auth = .failed(.tokenRejected)
                nextPollAt = nil
                renderSettings()
                return
            } catch {
                host.log("could not read \(repo.fullName): \(error)")
            }
        }
        states = next.filter { watched.contains($0.key) }
        summary = GitHubSummary(states: states, watched: watched)
        let active = summary.repositories.contains { $0.running > 0 }
        let seconds = max(5, active ? int(Preference.pollActiveInterval, 10) : int(Preference.pollInterval, 30))
        nextPollAt = parts.now().addingTimeInterval(TimeInterval(seconds))
        host.badge(count: summary.badgeCount == 0 ? nil : summary.badgeCount, dot: false)
        if bool(Preference.mouseIndicator, true) {
            locateMouse(mouseCommand())
            mouse.update(summary: summary, settings: mouseSettings, force: firstSnapshot)
        }
        firstSnapshot = false
        renderIsland()
    }

    /// The person changed a preference in the tool's detail.
    public func preferencesChanged(_ ids: [String]) {
        if ids.contains(Preference.watchlist) {
            summary = GitHubSummary(states: states, watched: watched)
            nextPollAt = parts.now()
            renderIsland()
        }
        if ids.contains(Preference.mouseIndicator) {
            locateMouse(mouseCommand())
            if bool(Preference.mouseIndicator, true) {
                mouse.update(summary: summary, settings: mouseSettings, force: true)
            } else {
                mouse.restore()
            }
        }
        if ids.contains(where: { $0.hasPrefix("mouse") }) {
            locateMouse(mouseCommand())
            if bool(Preference.mouseIndicator, true) { mouse.update(summary: summary, settings: mouseSettings, force: true) }
            renderSettings()
        }
    }

    // MARK: The island

    public func islandPage() -> UITree {
        Pages.island(summary: summary, auth: auth)
    }

    public func islandEvent(_ event: PanelEvent) -> PanelAnswer {
        switch (event.block, event.kind) {
        case (Pages.refreshButton?, .tap):
            refresh()
            return .page(islandPage())
        case (Pages.rerunButton?, .tap):
            guard let token else { return .keep }
            var started = 0
            for repository in summary.repositories where !repository.failedRunIDs.isEmpty {
                started += parts.api.rerunFailedJobs(repo: repository.repo, runIDs: repository.failedRunIDs, token: token).count
            }
            host.showMessage(Words.plain("rerunStartedFormat", language: host.language, String(started)),
                             icon: "arrow.clockwise")
            nextPollAt = parts.now()
            return .keep
        case (Pages.pullsList?, .tap):
            guard let id = event.row, let named = Pages.pull(ofRow: id),
                  let url = states[named.repo]?.pullRequests[named.number]?.htmlURL else { return .keep }
            host.open(url.absoluteString)
            return .keep
        case (let id?, .tap):
            guard let repo = Pages.repo(ofRow: id) else { return .keep }
            host.open("https://github.com/\(repo.fullName)/actions")
            return .keep
        default:
            return .keep
        }
    }

    private func renderIsland() {
        host.render(panel: Self.islandPanel, islandPage())
    }

    // MARK: Settings

    public func settingsInput() -> Pages.SettingsInput {
        Pages.SettingsInput(
            auth: auth,
            cliLogin: auth.isSignedIn ? nil : CLIAccount.read(hostsFile: parts.cliHosts)?.login,
            mouseCommand: mouseCommand(),
            mouseConfiguredIgnored: MouseCommand.configuredIsIgnored(configured: string(Preference.mouseCommand),
                                                                     home: parts.home, isExecutable: parts.isExecutable))
    }

    public func settingsPage() -> UITree {
        Pages.settings(settingsInput())
    }

    public func settingsEvent(_ event: PanelEvent) -> PanelAnswer {
        switch (event.block, event.kind) {
        case (Pages.useCLIButton?, .tap):
            guard let account = CLIAccount.read(hostsFile: parts.cliHosts) else { return .keep }
            cliDeclined = false
            signIn(with: account.token, save: true)
        case (Pages.tokenField?, .submit):
            let typed = (event.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !typed.isEmpty else { return .keep }
            signIn(with: typed, save: true)
        case (Pages.useCodeButton?, .tap):
            startCode()
        case (Pages.cancelButton?, .tap):
            deviceFlow = .idle
            auth = .signedOut
        case (Pages.signOutButton?, .tap):
            signOut()
        default:
            return .keep
        }
        return .page(settingsPage())
    }

    private func startCode() {
        let clientID = string(Preference.clientID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            auth = .failed(.notConfigured)
            return
        }
        clientIDInFlow = clientID
        deviceFlow = DeviceFlowState.idle.next(.start, now: parts.now())
        do {
            let issued = try parts.api.deviceCode(clientID: clientID)
            deviceFlow = deviceFlow.next(.codeIssued(issued), now: parts.now())
            auth = .deviceFlow(userCode: issued.userCode, verificationURL: issued.verificationURI)
        } catch let refused as GitHubAPI.DeviceCodeRefused {
            deviceFlow = .idle
            auth = .failed(.deviceFlow(.other(refused.reason)))
        } catch {
            deviceFlow = .idle
            auth = .failed(.unreachable)
        }
    }

    private func renderSettings() {
        host.render(panel: Self.settingsPanel, settingsPage())
    }
}
