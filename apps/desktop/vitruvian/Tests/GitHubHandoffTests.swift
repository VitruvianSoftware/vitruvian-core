// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import Security
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// What the GitHub feature kept goes to the GitHub tool once, through the
/// tool's storage, when the tool is added.
enum GitHubHandoffTests {
    static func run(_ suite: TestSuite) {
        handsEverythingOnce(suite)
        whatIsHandedIsWhatTheToolReads(suite)
        otherToolsAndAnUpdateHandNothing(suite)
        removalLetsItBeHandedAgain(suite)
        theStoreTellsBeforeTheProgramStarts(suite)
        addingNeverWaitsForTheKeychain(suite)
        aRefusedKeychainHandsOverWithoutAToken(suite)
        removalWhileTheKeychainIsAskedDropsTheAdd(suite)
        agreeingTwiceAddsAndHandsOverOnce(suite)
        anUpdateAsksTheKeychainNothing(suite)
    }

    /// The GitHub tool's manifest: its preferences, as `vitruvian-tool.json`
    /// in apps/desktop/vitruvian-tool-github declares them, with the one
    /// that has no title.
    static let manifest = Data(#"""
        {"id": "dev.vitruvian.github", "name": {"en": "GitHub"}, "version": "1.0.0", "protocol": "2",
         "publisher": "VitruvianSoftware", "uses": ["notify", "open", "storage"],
         "contributes": {"commands": [{"id": "refresh", "title": {"en": "Refresh GitHub"}}],
                         "panels": [{"id": "status", "title": {"en": "GitHub"}, "placement": "island"},
                                    {"id": "settings", "title": {"en": "GitHub"}, "placement": "settings"}]},
         "preferences": [
           {"id": "watchlist", "title": {"en": "Watched repositories"}, "type": "string", "default": "VitruvianSoftware/vitruvian-core"},
           {"id": "pollInterval", "title": {"en": "Poll every (seconds)"}, "type": "integer", "default": 30},
           {"id": "pollActiveInterval", "title": {"en": "Poll every while checks run (seconds)"}, "type": "integer", "default": 10},
           {"id": "mouseIndicator", "title": {"en": "Show status on the GravaStar mouse"}, "type": "boolean", "default": true},
           {"id": "mouseCommand", "title": {"en": "Mouse command"}, "type": "string", "default": ""},
           {"id": "mouseSuccess", "title": {"en": "Mouse when green"}, "type": "string", "default": "green"},
           {"id": "mouseRunning", "title": {"en": "Mouse when amber"}, "type": "string", "default": "breathe orange"},
           {"id": "mouseFailure", "title": {"en": "Mouse when red"}, "type": "string", "default": "breathe red"},
           {"id": "mouseApproval", "title": {"en": "Mouse while waiting for approval"}, "type": "string", "default": "breathe blue 9"},
           {"id": "mouseIdle", "title": {"en": "Mouse when nothing is watched (restore or off)"}, "type": "string", "default": "restore"},
           {"id": "clientID", "title": {"en": "Client ID"}, "type": "string", "default": ""},
           {"id": "migratedToken", "type": "string", "default": ""}
         ],
         "activation": ["onLaunch"], "runtime": {"kind": "external", "exec": "bin/tool"}}
        """#.utf8)

    /// A folder holding the GitHub tool's manifest and an empty program,
    /// read as the store reads it; nil when the manifest is refused.
    static func installedTool(manifest: Data = manifest, in root: URL) -> ExternalToolStore.Installed? {
        let folder = root.appendingPathComponent("github", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try? manifest.write(to: folder.appendingPathComponent("vitruvian-tool.json"))
        FileManager.default.createFile(atPath: folder.appendingPathComponent("bin/tool").path, contents: Data(),
                                       attributes: [.posixPermissions: 0o755])
        guard case .success(let tool) = ExternalToolManifest.read(folder: folder) else { return nil }
        return ExternalToolStore.Installed(tool: tool, files: folder, data: root.appendingPathComponent("data"))
    }

    /// Defaults of their own, with the feature installed, on and set up as
    /// a person might have it.
    static func defaults(_ name: String) -> UserDefaults {
        let domain = "com.vitruviansoftware.vitruvian.tests.github.handoff.\(name)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defaults.set(true, forKey: AppFeature.notch.availabilityKey)
        defaults[Preferences.githubWatchedRepositories] = #"["acme/web", "Acme/API"]"#
        defaults[Preferences.githubPollInterval] = 45
        defaults[Preferences.githubMouseRunningMode] = "fixed"
        defaults[Preferences.githubMouseApprovalColor] = "Purple"
        defaults[Preferences.githubMouseApprovalSpeed] = 12
        defaults[Preferences.githubMouseIdleBehavior] = "off"
        defaults[Preferences.githubMouseBinaryPath] = "~/bin/gm"
        defaults[Preferences.githubClientID] = "Iv1.app"
        return defaults
    }

    /// A storage backing over a dictionary, with what it was given.
    typealias Box = ToolBrokerTests.PreferenceBox

    static func backing(_ box: Box) -> StorageAccess.Backing {
        StorageAccess.Backing(read: { box.values[$0] }, write: { box.values[$0] = $1 })
    }

    static func parts(_ defaults: UserDefaults, token: String?, box: Box,
                      log: @escaping (String) -> Void = { _ in }) -> GitHubHandoff.Parts {
        GitHubHandoff.Parts(defaults: defaults, token: { token }, backing: backing(box), log: log)
    }

    static func scratch() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-github-handoff-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func handsEverythingOnce(_ suite: TestSuite) {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = defaults("hands")
        let box = Box()
        var logged: [String] = []
        guard let tool = installedTool(in: root) else { return suite.expect(false, "the GitHub tool's manifest reads") }
        let origin = CatalogueOrigin(id: "dev.vitruvian.github", version: "1.0.0", source: "https://x", download: "https://x/z.zip")
        let outcome = GitHubHandoff.perform(tool, from: origin, parts: parts(defaults, token: "gho_feature", box: box,
                                                                              log: { logged.append($0) }))
        suite.expect(outcome == .handed(["clientID", "migratedToken", "mouseApproval", "mouseCommand", "mouseFailure",
                                         "mouseIdle", "mouseIndicator", "mouseRunning", "mouseSuccess", "pollActiveInterval",
                                         "pollInterval", "watchlist"]),
                     "every preference the tool declares is written, the token among them: \(outcome)")
        let key = { ExternalToolManifest.storageKey(tool: GitHubHandoff.toolID, preference: $0) }
        suite.expect(box.values[key("migratedToken")] as? String == "gho_feature"
                         && box.values[key("watchlist")] as? String == "acme/web, Acme/API"
                         && box.values[key("pollInterval")] as? Int == 45
                         && box.values[key("pollActiveInterval")] as? Int == 10
                         && box.values[key("mouseIndicator")] as? Bool == true
                         && box.values[key("mouseCommand")] as? String == "~/bin/gm"
                         && box.values[key("clientID")] as? String == "Iv1.app",
                     "under the tool's keys, as the tool reads them: \(box.values)")
        suite.expect(defaults[Preferences.githubReplacedByTool], "it is marked handed, so it is not handed twice")
        suite.expect(logged.contains { $0.contains("version 1.0.0 from the catalog") },
                     "the log says what was handed over, and from where: \(logged)")
    }

    static func whatIsHandedIsWhatTheToolReads(_ suite: TestSuite) {
        let defaults = defaults("values")
        let values = GitHubHandoff.values(defaults: defaults, token: "gho_x")
        suite.expect(values["mouseSuccess"] == .string("green") && values["mouseRunning"] == .string("orange")
                         && values["mouseFailure"] == .string("breathe red") && values["mouseApproval"] == .string("breathe purple 9")
                         && values["mouseIdle"] == .string("off"),
                     "each mouse light is one line the tool reads: the colour, breathe before it, the speed after, held to 9: \(values)")
        suite.expect(GitHubHandoff.values(defaults: defaults, token: nil)["migratedToken"] == nil
                         && GitHubHandoff.values(defaults: defaults, token: "")["migratedToken"] == nil,
                     "no token, nothing handed as one")
        defaults[Preferences.githubWatchedRepositories] = "garbage"
        suite.expect(GitHubHandoff.values(defaults: defaults, token: nil)["watchlist"] == .string("VitruvianSoftware/vitruvian-core"),
                     "an unreadable watchlist is handed as the feature read it: the default")
    }

    static func otherToolsAndAnUpdateHandNothing(_ suite: TestSuite) {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = defaults("others")
        let box = Box()
        let other = Data(String(decoding: manifest, as: UTF8.self)
            .replacingOccurrences(of: "dev.vitruvian.github", with: "com.acme.deploys").utf8)
        guard let deploys = installedTool(manifest: other, in: root) else { return suite.expect(false, "the other manifest reads") }
        suite.expect(GitHubHandoff.perform(deploys, from: nil, parts: parts(defaults, token: "gho_x", box: box)) == .notTheTool
                         && box.values.isEmpty && !defaults[Preferences.githubReplacedByTool],
                     "another tool gets nothing")
        guard let github = installedTool(in: root) else { return suite.expect(false, "the GitHub tool's manifest reads") }
        _ = GitHubHandoff.perform(github, from: nil, parts: parts(defaults, token: "gho_x", box: box))
        box.values = [:]
        suite.expect(GitHubHandoff.perform(github, from: nil, parts: parts(defaults, token: "gho_y", box: box)) == .alreadyHanded
                         && box.values.isEmpty,
                     "the tool updated, or added again: nothing is handed a second time")
        // The manifest without its last preference, as an older tool's.
        let older = Data(String(decoding: manifest, as: UTF8.self)
            .replacingOccurrences(of: ",\n   {\"id\": \"migratedToken\", \"type\": \"string\", \"default\": \"\"}", with: "").utf8)
        let fresh = self.defaults("older")
        var logged: [String] = []
        guard let old = installedTool(manifest: older, in: root) else { return suite.expect(false, "the older manifest reads") }
        let outcome = GitHubHandoff.perform(old, from: nil, parts: parts(fresh, token: "gho_x", box: Box(), log: { logged.append($0) }))
        suite.expect(outcome == .handed(["clientID", "mouseApproval", "mouseCommand", "mouseFailure", "mouseIdle", "mouseIndicator",
                                         "mouseRunning", "mouseSuccess", "pollActiveInterval", "pollInterval", "watchlist"])
                         && logged.contains { $0.contains("does not take migratedToken") },
                     "a tool whose manifest lacks a preference is handed the rest, and the log names what it did not take: \(outcome)")
    }

    static func removalLetsItBeHandedAgain(_ suite: TestSuite) {
        let defaults = defaults("removal")
        defaults[Preferences.githubReplacedByTool] = true
        GitHubHandoff.toolRemoved(ToolID("com.acme.deploys")!, defaults: defaults)
        suite.expect(defaults[Preferences.githubReplacedByTool], "another tool's removal changes nothing")
        GitHubHandoff.toolRemoved(GitHubHandoff.toolID, defaults: defaults)
        suite.expect(!defaults[Preferences.githubReplacedByTool], "the GitHub tool's removal lets it be handed the settings again")
    }

    static func theStoreTellsBeforeTheProgramStarts(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        let folder = bench.folder("github", manifest: manifest, exec: "bin/tool")
        guard case .success = bench.add(folder) else { return suite.expect(false, "the GitHub tool is added") }
        suite.expect(bench.added.map(\.id) == [GitHubHandoff.toolID] && bench.added.first?.programStarted == false,
                     "the store tells of the added tool before its program starts, so what is handed is there for its first run")
        _ = bench.store.remove(GitHubHandoff.toolID, deletingData: true)
        suite.expect(bench.removed == [GitHubHandoff.toolID], "and of its removal")
    }

    // MARK: - The Keychain may hold the token's read

    /// The store, the hand-off and the reader of the feature's saved token
    /// as the app wires them (`ExternalToolStore.Parts.live`,
    /// `GitHubHandoff.Parts.live`, `GitHubSavedToken`),
    /// over a Keychain that holds its answer the way the real one does while
    /// "Vitruvian wants to use your confidential information" is on screen.
    private final class Rig {
        let bench = ExternalToolStoreTests.Bench()
        let held: HeldGitHubTokenStore
        let defaults: UserDefaults
        let saved: GitHubSavedToken
        /// What each add answered, in the order they answered; nil for one
        /// that was dropped.
        var answers: [Result<ExternalToolStore.Installed, ExternalToolStore.Refusal>?] = []
        var outcomes: [GitHubHandoff.Outcome] = []

        init(_ name: String, keychain: Result<String?, GitHubTokenStoreError>) {
            held = HeldGitHubTokenStore(answer: keychain)
            defaults = GitHubHandoffTests.defaults(name)
            saved = GitHubSavedToken(store: held)
            let parts = GitHubHandoff.Parts(
                defaults: defaults,
                readToken: { [saved] ready in saved.load { _ in ready() } },
                token: { [saved] in saved.current() },
                backing: GitHubHandoffTests.backing(bench.box), log: { _ in })
            bench.beforeAdding = { id, ready in GitHubHandoff.prepare(id, parts: parts, then: ready) }
            bench.handOver = { [unowned self] installed, origin in
                outcomes.append(GitHubHandoff.perform(installed, from: origin, parts: parts))
            }
        }

        /// The person presses Add Tool on the sheet. How long it took to return.
        @discardableResult
        func agree(_ folder: String = "github") -> TimeInterval {
            guard case .success(let offer) = bench.store.offer(
                from: bench.folder(folder, manifest: GitHubHandoffTests.manifest, exec: "bin/tool")) else { return .infinity }
            let began = ProcessInfo.processInfo.systemUptime
            bench.store.add(ToolConsent(to: offer)) { [unowned self] in answers.append($0) }
            return ProcessInfo.processInfo.systemUptime - began
        }

        var isAdded: Bool { bench.store.isInstalled(GitHubHandoff.toolID) }
        var handedToken: String? {
            bench.box.values[ExternalToolManifest.storageKey(tool: GitHubHandoff.toolID, preference: "migratedToken")] as? String
        }
        /// True once anything of the feature's was written for the tool.
        var handedAnything: Bool { bench.box.values.keys.contains { $0.hasPrefix(GitHubHandoff.toolID.rawValue + "/") } }

        /// Lets the main queue run until `done`, or for two seconds.
        func pump(until done: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 2)
            while !done(), Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
            }
        }

        /// The person answers the Keychain's prompt, and the answer
        /// reaches the main thread.
        func answerTheKeychain() {
            held.answerNow()
            pump { held.finished == held.started }
            var delivered = false
            DispatchQueue.main.async { delivered = true }
            pump { delivered }
        }

        func close() { bench.close() }
    }

    static func addingNeverWaitsForTheKeychain(_ suite: TestSuite) {
        let rig = Rig("held", keychain: .success("gho_saved"))
        defer { rig.close() }
        let waited = rig.agree()
        suite.expect(waited < rig.held.patience / 2,
                     "Add Tool returns while the Keychain still holds the token's read (\(waited)s)")
        rig.pump { rig.held.started == 1 }
        suite.expect(rig.held.started == 1 && rig.held.readsOnMainThread == 0,
                     "the feature's token is read, and never on the main thread")
        suite.expect(rig.bench.store.isAdding(GitHubHandoff.toolID) && rig.answers.isEmpty && !rig.isAdded
                         && !rig.handedAnything && !rig.defaults[Preferences.githubReplacedByTool]
                         && rig.bench.started.isEmpty,
                     "while the Keychain is asked the tool is being added: nothing is handed or started yet")

        rig.answerTheKeychain()
        suite.expect(rig.answers.count == 1 && (try? rig.answers[0]?.get()) != nil && rig.isAdded
                         && !rig.bench.store.isAdding(GitHubHandoff.toolID),
                     "once the Keychain answers, the tool is added: \(rig.answers)")
        suite.expect(rig.handedToken == "gho_saved" && rig.outcomes.count == 1
                         && rig.defaults[Preferences.githubReplacedByTool],
                     "and handed the token the Keychain gave, once: \(rig.outcomes)")
        suite.expect(rig.bench.added.map(\.programStarted) == [false],
                     "still before its program starts, so the token is there for its first run")
        suite.expect(rig.held.started == 1, "the Keychain was asked once")
    }

    static func aRefusedKeychainHandsOverWithoutAToken(_ suite: TestSuite) {
        for (name, keychain) in [("denied", Result<String?, GitHubTokenStoreError>.failure(.init(status: errSecAuthFailed))),
                                 ("empty", .success(nil))] {
            let rig = Rig(name, keychain: keychain)
            defer { rig.close() }
            rig.agree()
            rig.pump { rig.held.started == 1 }
            rig.answerTheKeychain()
            suite.expect(rig.isAdded && rig.answers.count == 1 && rig.defaults[Preferences.githubReplacedByTool],
                         "\(name): the tool is added and the feature's settings handed over all the same")
            suite.expect(rig.handedToken == nil && rig.handedAnything && rig.outcomes.count == 1,
                         "\(name): with the feature's settings and no token, so the tool starts signed out: \(rig.outcomes)")
            suite.expect(rig.saved.current() == nil && rig.held.started == 1,
                         "\(name): no token is kept, and the Keychain was asked once")
        }
    }

    static func removalWhileTheKeychainIsAskedDropsTheAdd(_ suite: TestSuite) {
        let rig = Rig("removed", keychain: .success("gho_saved"))
        defer { rig.close() }
        rig.agree()
        rig.pump { rig.held.started == 1 }
        suite.expect(rig.bench.store.remove(GitHubHandoff.toolID, deletingData: true) == .notAdded
                         && !rig.bench.store.isAdding(GitHubHandoff.toolID),
                     "removing a tool that is still being added stops the add")
        rig.answerTheKeychain()
        suite.expect(rig.held.finished == 1, "the held read did return")
        suite.expect(rig.answers.count == 1 && rig.answers[0] == nil,
                     "the Keychain's late answer is dropped, and whoever asked is told so: \(rig.answers)")
        suite.expect(!rig.isAdded && rig.bench.records.isEmpty && !rig.handedAnything && rig.outcomes.isEmpty
                         && !rig.defaults[Preferences.githubReplacedByTool],
                     "nothing is added and nothing handed over, so the tool added later is handed everything")
    }

    static func agreeingTwiceAddsAndHandsOverOnce(_ suite: TestSuite) {
        let rig = Rig("twice", keychain: .success("gho_saved"))
        defer { rig.close() }
        rig.agree("first")
        rig.agree("second")
        rig.pump { rig.held.started == 1 }
        rig.answerTheKeychain()
        suite.expect(rig.held.started == 1, "two adds waiting ask the Keychain once: \(rig.held.started)")
        suite.expect(rig.answers.count == 2 && rig.answers[0] == nil && (try? rig.answers[1]?.get()) != nil,
                     "the later agreement is the one that adds; the earlier is dropped: \(rig.answers)")
        suite.expect(rig.bench.added.count == 1 && rig.outcomes.count == 1 && rig.handedToken == "gho_saved"
                         && rig.bench.records.count == 1,
                     "so the tool is added once and handed over to once: \(rig.outcomes)")
    }

    static func anUpdateAsksTheKeychainNothing(_ suite: TestSuite) {
        let rig = Rig("update", keychain: .success("gho_saved"))
        defer { rig.close() }
        rig.defaults[Preferences.githubReplacedByTool] = true
        rig.agree()
        suite.expect(rig.answers.count == 1 && rig.isAdded && rig.outcomes == [.alreadyHanded],
                     "a tool whose feature is handed over already is added before Add Tool returns: \(rig.answers)")
        rig.pump { rig.held.started > 0 }
        suite.expect(rig.held.started == 0 && rig.handedToken == nil,
                     "and the Keychain is not asked: there is nothing to hand a second time")
        let other = ExternalToolStoreTests.Bench()
        defer { other.close() }
        var ready = 0
        GitHubHandoff.prepare(ToolID("com.acme.deploys")!, parts: parts(defaults("update-other"), token: nil, box: Box()),
                              then: { ready += 1 })
        suite.expect(ready == 1, "another tool waits for nothing either")
    }
}

/// A Keychain that does not answer a read until the test lets it, the way
/// the real one waits for the person to answer "Vitruvian wants to use your
/// confidential information". It gives up after `patience`, so code that
/// reads on the main thread fails its checks instead of hanging the run.
nonisolated final class HeldGitHubTokenStore: GitHubTokenStore, @unchecked Sendable {
    // Guarded by `lock`.
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var startedCount = 0
    private var finishedCount = 0
    private var mainThreadReads = 0
    private var saved: String?
    /// What a read answers once it is let go: the token, none, or the
    /// Keychain's refusal when the person presses Deny.
    private let answer: Result<String?, GitHubTokenStoreError>
    let patience: TimeInterval

    init(answer: Result<String?, GitHubTokenStoreError>, patience: TimeInterval = 3) {
        self.answer = answer
        self.patience = patience
    }

    var started: Int { lock.withLock { startedCount } }
    var finished: Int { lock.withLock { finishedCount } }
    var readsOnMainThread: Int { lock.withLock { mainThreadReads } }

    func load() throws -> String? {
        lock.withLock {
            startedCount += 1
            if Thread.isMainThread { mainThreadReads += 1 }
        }
        _ = gate.wait(timeout: .now() + patience)
        lock.withLock { finishedCount += 1 }
        return try answer.get()
    }

    func save(_ token: String) throws { lock.withLock { saved = token } }
    func delete() throws { lock.withLock { saved = nil } }

    /// The person answers the prompt: one waiting read returns.
    func answerNow() { gate.signal() }
}
