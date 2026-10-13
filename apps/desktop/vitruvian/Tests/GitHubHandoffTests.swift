// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// The GitHub feature hands its sign-in and settings to the GitHub tool
/// once, through the tool's storage, and is hidden while the tool is
/// installed.
enum GitHubHandoffTests {
    static func run(_ suite: TestSuite) {
        handsEverythingOnceAndHidesTheFeature(suite)
        whatIsHandedIsWhatTheToolReads(suite)
        otherToolsAndAnUpdateHandNothing(suite)
        removalBringsTheFeatureBackOff(suite)
        theStoreTellsBeforeTheProgramStarts(suite)
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
        defaults.register(defaults: Defaults.registeredDefaults)
        defaults.set(true, forKey: AppFeature.notchGitHub.availabilityKey)
        defaults.set(true, forKey: AppFeature.notch.availabilityKey)
        defaults[Preferences.notchGitHubEnabled] = true
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

    static func parts(_ defaults: UserDefaults, token: String?, box: Box, off: @escaping () -> Void = {},
                      changed: @escaping () -> Void = {},
                      log: @escaping (String) -> Void = { _ in }) -> GitHubHandoff.Parts {
        GitHubHandoff.Parts(defaults: defaults, token: { token }, backing: backing(box), featureOff: off,
                            availabilityChanged: changed, log: log)
    }

    static func scratch() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-github-handoff-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func handsEverythingOnceAndHidesTheFeature(_ suite: TestSuite) {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = defaults("hands")
        let box = Box()
        var turnedOff = 0
        var told = 0
        /// Whether the feature was hidden already each time the runtime was told.
        var hiddenWhenTold: [Bool] = []
        var logged: [String] = []
        guard let tool = installedTool(in: root) else { return suite.expect(false, "the GitHub tool's manifest reads") }
        suite.expect(AppFeature.notchGitHub.isAvailable(in: defaults) && NotchModule.github.isAvailable(in: defaults),
                     "before: the feature is installed and its island page is there")
        let origin = CatalogueOrigin(id: "dev.vitruvian.github", version: "1.0.0", source: "https://x", download: "https://x/z.zip")
        let outcome = GitHubHandoff.perform(tool, from: origin, parts: parts(
            defaults, token: "gho_feature", box: box, off: { turnedOff += 1 },
            changed: {
                told += 1
                hiddenWhenTold.append(!AppFeature.notchGitHub.isAvailable(in: defaults))
            },
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
        suite.expect(defaults[Preferences.githubReplacedByTool] && !defaults[Preferences.notchGitHubEnabled] && turnedOff == 1,
                     "the feature is marked replaced, its switch off, and its sign-in stopped")
        suite.expect(!AppFeature.notchGitHub.isAvailable(in: defaults) && !NotchModule.github.isAvailable(in: defaults)
                         && AppFeature.notchGitHub.isReplaced(in: defaults) && defaults.bool(forKey: AppFeature.notchGitHub.availabilityKey)
                         && AppFeature.notch.isAvailable(in: defaults) && !AppFeature.notch.isReplaced(in: defaults),
                     "after: the feature and its island page are hidden, though still installed; nothing else is")
        suite.expect(told == 1 && hiddenWhenTold == [true],
                     "a hand-off that hides the feature tells the feature runtime once, after it is hidden, "
                         + "so Settings stops listing it without a restart: told \(told), hidden then \(hiddenWhenTold)")
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
        var told = 0
        let other = Data(String(decoding: manifest, as: UTF8.self)
            .replacingOccurrences(of: "dev.vitruvian.github", with: "com.acme.deploys").utf8)
        guard let deploys = installedTool(manifest: other, in: root) else { return suite.expect(false, "the other manifest reads") }
        suite.expect(GitHubHandoff.perform(deploys, from: nil, parts: parts(defaults, token: "gho_x", box: box,
                                                                            changed: { told += 1 })) == .notTheTool
                         && box.values.isEmpty && !defaults[Preferences.githubReplacedByTool],
                     "another tool gets nothing, and the feature stays")
        suite.expect(told == 0, "another tool hides nothing, so the feature runtime is told nothing: told \(told)")
        guard let github = installedTool(in: root) else { return suite.expect(false, "the GitHub tool's manifest reads") }
        _ = GitHubHandoff.perform(github, from: nil, parts: parts(defaults, token: "gho_x", box: box))
        box.values = [:]
        suite.expect(GitHubHandoff.perform(github, from: nil, parts: parts(defaults, token: "gho_y", box: box,
                                                                           changed: { told += 1 })) == .alreadyReplaced
                         && box.values.isEmpty,
                     "the tool updated, or added again: nothing is handed a second time")
        suite.expect(told == 0, "a feature hidden already is hidden still, so the feature runtime is told nothing: told \(told)")
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

    static func removalBringsTheFeatureBackOff(_ suite: TestSuite) {
        let defaults = defaults("removal")
        defaults[Preferences.githubReplacedByTool] = true
        defaults[Preferences.notchGitHubEnabled] = false
        var told = 0
        /// Whether the feature was back already each time the runtime was told.
        var backWhenTold: [Bool] = []
        let changed = {
            told += 1
            backWhenTold.append(AppFeature.notchGitHub.isAvailable(in: defaults))
        }
        GitHubHandoff.toolRemoved(ToolID("com.acme.deploys")!, defaults: defaults, availabilityChanged: changed)
        suite.expect(defaults[Preferences.githubReplacedByTool], "another tool's removal changes nothing")
        suite.expect(told == 0, "another tool's removal brings nothing back, so the feature runtime is told nothing: told \(told)")
        GitHubHandoff.toolRemoved(GitHubHandoff.toolID, defaults: defaults, availabilityChanged: changed)
        suite.expect(!defaults[Preferences.githubReplacedByTool] && AppFeature.notchGitHub.isAvailable(in: defaults)
                         && !defaults[Preferences.notchGitHubEnabled],
                     "the GitHub tool's removal brings the feature back, switched off")
        suite.expect(told == 1 && backWhenTold == [true],
                     "a removal that brings the feature back tells the feature runtime once, after it is back, "
                         + "so Settings lists it again without a restart: told \(told), back then \(backWhenTold)")
        GitHubHandoff.toolRemoved(GitHubHandoff.toolID, defaults: defaults, availabilityChanged: changed)
        suite.expect(told == 1, "a removal with the feature there already tells the feature runtime nothing more: told \(told)")
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
}
