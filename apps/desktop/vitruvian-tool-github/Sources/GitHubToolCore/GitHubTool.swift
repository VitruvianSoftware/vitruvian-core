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
    /// The tool's status on the closed island (`ui/status`). An app without
    /// it (before 3.48) is sent nothing.
    func status(_ status: IslandStatus)
    /// A new page for a panel, when it is open; nothing otherwise.
    func render(panel: String, _ tree: UITree)
    /// Whether the app named this at hello. An app before 3.48 names
    /// nothing, and draws a `choice` as words nobody can change.
    func supports(_ feature: ProtocolFeature) -> Bool
    /// Puts `text` on the clipboard (`clipboard.write`); false when the app
    /// would not.
    @discardableResult
    func copyText(_ text: String) -> Bool
}

/// What the tool's mark on the closed island says: a state, the tool's
/// words for it, a glyph in place of the state's own, and the few words
/// drawn beside the mark (`activity`, from Vitruvian 3.50).
public struct IslandStatus: Equatable, Sendable {
    public let state: StatusState
    public let text: UIText?
    public let icon: String?
    /// Busy: how many checks run, as digits. Nil in every other state, so
    /// the app shows its percent there.
    public let activity: UIText?

    public init(state: StatusState, text: UIText? = nil, icon: String? = nil, activity: UIText? = nil) {
        self.state = state
        self.text = text
        self.icon = icon
        self.activity = activity
    }

    /// No mark: what a program shows when it starts.
    public static let noMark = IslandStatus(state: .none)
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
        /// The zone the island's "Updated at" time is written in.
        public var timeZone: TimeZone

        public init(host: ToolHost, api: GitHubAPI, secrets: SecretStore, cliHosts: URL = CLIAccount.defaultHostsURL,
                    now: @escaping () -> Date = { Date() },
                    environment: [String: String] = ProcessInfo.processInfo.environment,
                    home: String = Paths.home,
                    isExecutable: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                    runMouse: @escaping (String, [String]) -> Void = MouseDriver.run(binary:arguments:),
                    timeZone: TimeZone = .current) {
            self.host = host
            self.api = api
            self.secrets = secrets
            self.cliHosts = cliHosts
            self.now = now
            self.environment = environment
            self.home = home
            self.isExecutable = isExecutable
            self.runMouse = runMouse
            self.timeZone = timeZone
        }
    }

    public private(set) var auth: AuthState = .signedOut
    public private(set) var states: [RepoKey: RepoState] = [:]
    public private(set) var summary = GitHubSummary(states: [:], watched: [])
    /// The pull request open in the island panel, or nil on the main island page.
    public private(set) var selectedPull: (repo: RepoKey, number: Int)?
    /// The repository whose default branch is open in the island panel, or
    /// nil. A pull request open outranks it.
    public private(set) var selectedRepo: RepoKey?
    /// The repository picked on the island page; nil (or one no longer
    /// watched) is the first watched.
    public private(set) var focusedRepo: RepoKey?
    /// When GitHub was last read, by `Parts.now`; nil until signed in and read.
    public private(set) var lastUpdatedAt: Date?
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
    /// The status last sent. The app shows none until one is sent.
    private var lastStatus = IslandStatus.noMark

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
        selectedPull = nil
        selectedRepo = nil
        lastUpdatedAt = nil
        nextPollAt = nil
        host.badge(count: nil, dot: false)
        showStatus()
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
        guard let token, let identity else { return }
        let watched = watched
        var next = states
        for repo in watched {
            do {
                if let updated = try parts.api.snapshot(repo: repo, token: token, identity: identity, known: states[repo],
                                                        now: parts.now()) {
                    next[repo] = updated
                } else {
                    host.log("could not read \(repo.fullName): GitHub did not give it")
                }
            } catch APIError.refused(status: 401) {
                rejectedToken = token
                self.token = nil
                self.identity = nil
                parts.secrets.clear()
                auth = .failed(.tokenRejected)
                selectedPull = nil
                selectedRepo = nil
                nextPollAt = nil
                renderIsland()
                renderSettings()
                return
            } catch {
                host.log("could not read \(repo.fullName): \(error)")
            }
        }
        states = next.filter { watched.contains($0.key) }
        summary = GitHubSummary(states: states, watched: watched)
        lastUpdatedAt = parts.now()
        clearGoneSelectedPull()
        let active = summary.repositories.contains { $0.running > 0 }
        let seconds = max(5, active ? int(Preference.pollActiveInterval, 10) : int(Preference.pollInterval, 30))
        nextPollAt = parts.now().addingTimeInterval(TimeInterval(seconds))
        host.badge(count: summary.badgeCount == 0 ? nil : summary.badgeCount, dot: false)
        showStatus()
        if bool(Preference.mouseIndicator, true) {
            locateMouse(mouseCommand())
            mouse.update(summary: summary, settings: mouseSettings, force: firstSnapshot)
        }
        firstSnapshot = false
        renderIsland()
    }

    private func clearGoneSelectedPull() {
        if let repo = selectedRepo, !summary.repositories.contains(where: { $0.repo == repo }) { selectedRepo = nil }
        guard let selected = selectedPull else { return }
        if !summary.pullRequests.contains(where: { $0.repo == selected.repo && $0.pullRequest.number == selected.number }) {
            selectedPull = nil
        }
    }

    // MARK: The status on the closed island

    /// The mark for a summary. The rule is the mouse's, so the island and
    /// the mouse agree: a check waiting for approval outranks every colour.
    public static func status(for summary: GitHubSummary, signedIn: Bool) -> IslandStatus {
        status(verdict: summary.aggregate, awaitingApproval: summary.awaitingApproval,
               running: summary.repositories.reduce(0) { $0 + $1.running }, signedIn: signedIn)
    }

    /// Signed out, or grey (nothing read yet, or nothing watched), is no
    /// mark; then approval, red, amber and green, as the app's own GitHub
    /// mark draws them. Busy carries `running`, the checks running across
    /// the watched repositories, as its words: digits, "99+" over 99, none
    /// at 0. No other state carries words.
    public static func status(verdict: Verdict, awaitingApproval: Bool, running: Int = 0,
                              signedIn: Bool) -> IslandStatus {
        guard signedIn else { return .noMark }
        if awaitingApproval {
            return IslandStatus(state: .attention, text: Words.text("statusAttention"), icon: "hand.raised.fill")
        }
        switch verdict {
        case .red: return IslandStatus(state: .failure, text: Words.text("statusFailure"))
        case .amber:
            return IslandStatus(state: .busy, text: Words.text("statusBusy"), icon: "arrow.triangle.branch",
                                activity: runningWords(running))
        case .green: return IslandStatus(state: .ok, text: Words.text("statusOK"))
        case .grey: return .noMark
        }
    }

    /// How many checks run, as the closed island shows it: digits, "99+"
    /// over 99, nothing at 0. Digits need no translation.
    static func runningWords(_ running: Int) -> UIText? {
        guard running > 0 else { return nil }
        return .plain(running > 99 ? "99+" : String(running))
    }

    /// Sends the status the tool is in now, when it is not the one sent last.
    private func showStatus() {
        let next = Self.status(for: summary, signedIn: auth.isSignedIn)
        guard next != lastStatus else { return }
        lastStatus = next
        host.status(next)
    }

    /// The person changed a preference in the tool's detail.
    public func preferencesChanged(_ ids: [String]) {
        if ids.contains(Preference.watchlist) {
            summary = GitHubSummary(states: states, watched: watched)
            clearGoneSelectedPull()
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
        if auth.isSignedIn, let selected = selectedPull,
           let pull = states[selected.repo]?.pullRequests[selected.number],
           summary.pullRequests.contains(where: { $0.repo == selected.repo && $0.pullRequest.number == selected.number }) {
            return Pages.pullDetail(repo: selected.repo, pull: pull)
        }
        if auth.isSignedIn, let repo = selectedRepo, summary.repositories.contains(where: { $0.repo == repo }) {
            return Pages.repoDetail(repo: repo, state: states[repo])
        }
        return Pages.island(summary: summary, auth: auth, focus: focusedRepo, offersPicker: host.supports(.choice),
                            lastUpdated: lastUpdatedAt, timeZone: parts.timeZone)
    }

    /// The repository the island is about: the one picked, or the first.
    public var focusedRepository: RepoKey? {
        Pages.focused(summary, focus: focusedRepo)?.repo
    }

    public func islandEvent(_ event: PanelEvent) -> PanelAnswer {
        switch (event.block, event.kind) {
        case (Pages.backButton?, .tap):
            selectedPull = nil
            selectedRepo = nil
            return .page(islandPage())
        case (Pages.refreshButton?, .tap):
            refresh()
            return .page(islandPage())
        case (Pages.openRepoButton?, .tap):
            if let repo = focusedRepository { host.open(Pages.webURL(repo)) }
            return .keep
        case (Pages.repoPicker?, .change):
            guard let picked = event.text.flatMap(RepoKey.init(fullName:)),
                  summary.repositories.contains(where: { $0.repo == picked }) else { return .keep }
            focusedRepo = picked
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
                  states[named.repo]?.pullRequests[named.number] != nil,
                  summary.pullRequests.contains(where: { $0.repo == named.repo && $0.pullRequest.number == named.number })
            else { return .keep }
            selectedPull = named
            selectedRepo = nil
            return .page(islandPage())
        case (Pages.checksList?, .tap):
            guard let id = event.row else { return .keep }
            if let check = Pages.check(ofRow: id),
               let url = states[check.repo]?.pullRequests[check.number]?.checks[check.runID]?.htmlURL {
                host.open(url.absoluteString)
            } else if let detail = Pages.pullDetail(ofRow: id),
                      let url = states[detail.repo]?.pullRequests[detail.number]?.htmlURL {
                host.open(url.absoluteString)
            }
            return .keep
        case (Pages.branchChecksList?, .tap):
            guard let id = event.row else { return .keep }
            if let check = Pages.branchCheck(ofRow: id) {
                // A check run without a page of its own opens the Actions page.
                let url = states[check.repo]?.checks[check.runID]?.htmlURL?.absoluteString
                    ?? (states[check.repo] != nil ? "\(Pages.webURL(check.repo))/actions" : nil)
                if let url { host.open(url) }
            } else if let repo = Pages.repoDetail(ofRow: id) {
                host.open("\(Pages.webURL(repo))/actions")
            }
            return .keep
        case (Pages.queueList?, .tap):
            guard let id = event.row else { return .keep }
            if let named = Pages.queueEntry(ofRow: id),
               let entry = states[named.repo]?.mergeQueue?.entries.first(where: { $0.number == named.number }) {
                host.open(entry.htmlURL?.absoluteString ?? "\(Pages.webURL(named.repo))/pull/\(named.number)")
            } else if let repo = Pages.queuePage(ofRow: id), let state = states[repo], let queue = state.mergeQueue {
                host.open(queue.htmlURL?.absoluteString ?? "\(Pages.webURL(repo))/queue/\(state.defaultBranch)")
            }
            return .keep
        case (let id?, .tap):
            if let detail = Pages.pullDetail(ofRow: id),
               let url = states[detail.repo]?.pullRequests[detail.number]?.htmlURL {
                host.open(url.absoluteString)
                return .keep
            }
            if let repo = Pages.repoDetail(ofRow: id) {
                host.open("\(Pages.webURL(repo))/actions")
                return .keep
            }
            guard let repo = Pages.repo(ofRow: id), summary.repositories.contains(where: { $0.repo == repo })
            else { return .keep }
            selectedPull = nil
            selectedRepo = repo
            return .page(islandPage())
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
                                                                     home: parts.home, isExecutable: parts.isExecutable),
            mouseIndicator: bool(Preference.mouseIndicator, true))
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
        case (Pages.copyCodeButton?, .tap):
            copyCode()
            return .keep
        case (let id?, .tap):
            guard let test = MouseTest(rawValue: id) else { return .keep }
            testMouse(test)
            return .keep
        default:
            return .keep
        }
        return .page(settingsPage())
    }

    /// Puts the code being shown on the clipboard, and says so.
    public func copyCode() {
        guard case .deviceFlow(let userCode, _) = auth else { return }
        if host.copyText(userCode) {
            host.showMessage(Words.plain("codeCopied", language: host.language), icon: "doc.on.doc")
        } else {
            host.log("the app did not take the code onto the clipboard")
        }
    }

    /// Shows one state's light on the mouse now, from the person's settings.
    /// Nothing without a mouse command, or with the mouse not showing the
    /// status. The next poll puts the real state back.
    public func testMouse(_ test: MouseTest) {
        guard bool(Preference.mouseIndicator, true), let command = mouseCommand() else { return }
        locateMouse(command)
        mouse.test(test, settings: mouseSettings)
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
