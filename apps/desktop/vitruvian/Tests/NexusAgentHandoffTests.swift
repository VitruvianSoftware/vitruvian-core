// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// The Nexus Agent feature hands its settings to the Nexus Agent tool
/// once, through the tool's storage, and is hidden while the tool is
/// installed.
enum NexusAgentHandoffTests {
    static func run(_ suite: TestSuite) {
        handsEverythingOnceAndHidesTheFeature(suite)
        whatIsHandedIsWhatTheToolReads(suite)
        otherToolsAndAnUpdateHandNothing(suite)
        removalBringsTheFeatureBackOff(suite)
        theStoreTellsBeforeTheProgramStarts(suite)
        modelsAndSessionsGoWhenThereAreAny(suite)
    }

    /// The Nexus Agent tool's manifest: its preferences, as
    /// `macos/tool/vitruvian-tool.json` in apps/desktop/nexus-agent declares
    /// them, four with a title and four without.
    static let manifest = Data(#"""
        {"id": "dev.vitruvian.nexus-agent", "name": {"en": "Nexus Agent"}, "version": "1.22.0", "protocol": "2",
         "publisher": "VitruvianSoftware", "uses": ["notify", "storage"],
         "contributes": {"commands": [{"id": "quickPrompt", "title": {"en": "Open the Quick Prompt"}}],
                         "panels": [{"id": "agent", "title": {"en": "Nexus Agent"}, "placement": "island"},
                                    {"id": "settings", "title": {"en": "Nexus Agent"}, "placement": "settings"}]},
         "preferences": [
           {"id": "botDirectory", "title": {"en": "Bot folder"}, "type": "string", "default": ""},
           {"id": "autoStart", "title": {"en": "Start the bot when Vitruvian opens"}, "type": "boolean", "default": false},
           {"id": "planMode", "title": {"en": "Plan mode"}, "type": "boolean", "default": false},
           {"id": "worktreeMode", "title": {"en": "Worktree mode"}, "type": "boolean", "default": false},
           {"id": "chosenProvider", "type": "string", "default": ""},
           {"id": "savedProviders", "type": "string", "default": ""},
           {"id": "promptHistory", "type": "string", "default": ""},
           {"id": "hiddenClaudeSessions", "type": "string", "default": ""}
         ],
         "activation": ["onLaunch"], "runtime": {"kind": "external", "exec": "bin/tool"}}
        """#.utf8)

    static func installedTool(manifest: Data = manifest, in root: URL) -> ExternalToolStore.Installed? {
        let folder = root.appendingPathComponent("nexus-agent", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try? manifest.write(to: folder.appendingPathComponent("vitruvian-tool.json"))
        FileManager.default.createFile(atPath: folder.appendingPathComponent("bin/tool").path, contents: Data(),
                                       attributes: [.posixPermissions: 0o755])
        guard case .success(let tool) = ExternalToolManifest.read(folder: folder) else { return nil }
        return ExternalToolStore.Installed(tool: tool, files: folder, data: root.appendingPathComponent("data"))
    }

    /// Defaults of their own, with the feature installed, on and set up as
    /// a person might have it: a bot folder, the bot at launch, plan mode,
    /// a provider of their own chosen, a history, and the shortcut on.
    static func defaults(_ name: String) -> UserDefaults {
        let domain = "com.vitruviansoftware.vitruvian.tests.nexus-agent.handoff.\(name)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        // No register(defaults:): it writes the process's registration domain,
        // which every later suite would read (features' fan and scroll checks).
        defaults.set(true, forKey: AppFeature.nexusAgent.availabilityKey)
        defaults[Preferences.nexusAgentBotDirectory] = "~/bots/nexus"
        defaults[Preferences.nexusAgentAutoStart] = true
        defaults[Preferences.nexusAgentPlanMode] = true
        defaults[Preferences.nexusAgentChosenProvider] = "11111111-1111-1111-1111-111111111111"
        defaults[Preferences.nexusAgentSavedProviders] = Data(#"[{"id":"11111111-1111-1111-1111-111111111111","name":"Mine","commandTemplate":"mine -p \"{prompt}\"","isBuiltIn":false}]"#.utf8)
        defaults[Preferences.nexusAgentPromptHistory] = ["first", "second"]
        defaults[Preferences.nexusAgentShortcutEnabled] = true
        defaults[Preferences.nexusAgentShortcut] = GlobalShortcut(keyCode: 49, modifiers: [.command, .shift]).storageValue
        return defaults
    }

    typealias Box = ToolBrokerTests.PreferenceBox

    static func backing(_ box: Box) -> StorageAccess.Backing {
        StorageAccess.Backing(read: { box.values[$0] }, write: { box.values[$0] = $1 })
    }

    final class Recorder {
        var shortcuts: [GlobalShortcut] = []
        var turnedOff = 0
        var logged: [String] = []
    }

    static func parts(_ defaults: UserDefaults, box: Box, recorder: Recorder,
                      hidden: [String] = ["abc"]) -> NexusAgentHandoff.Parts {
        NexusAgentHandoff.Parts(defaults: defaults, hiddenClaudeSessions: { hidden }, backing: backing(box),
                                saveShortcut: { recorder.shortcuts.append($0) },
                                featureOff: { recorder.turnedOff += 1 },
                                log: { recorder.logged.append($0) })
    }

    static func scratch() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-nexus-agent-handoff-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func handsEverythingOnceAndHidesTheFeature(_ suite: TestSuite) {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = defaults("hands")
        let box = Box()
        let recorder = Recorder()
        guard let tool = installedTool(in: root) else { return suite.expect(false, "the Nexus Agent tool's manifest reads") }
        suite.expect(AppFeature.nexusAgent.isAvailable(in: defaults), "before: the feature is installed")
        let origin = CatalogueOrigin(id: "dev.vitruvian.nexus-agent", version: "1.22.0", source: "https://x", download: "https://x/z.zip")
        let outcome = NexusAgentHandoff.perform(tool, from: origin, parts: parts(defaults, box: box, recorder: recorder))
        suite.expect(outcome == .handed(["autoStart", "botDirectory", "chosenProvider", "hiddenClaudeSessions", "planMode",
                                         "promptHistory", "savedProviders", "worktreeMode"], shortcut: true),
                     "every preference the tool declares is written, and the shortcut goes with them: \(outcome)")
        let key = { ExternalToolManifest.storageKey(tool: NexusAgentHandoff.toolID, preference: $0) }
        suite.expect(box.values[key("botDirectory")] as? String == "~/bots/nexus"
                         && box.values[key("autoStart")] as? Bool == true
                         && box.values[key("planMode")] as? Bool == true
                         && box.values[key("worktreeMode")] as? Bool == false
                         && box.values[key("chosenProvider")] as? String == "11111111-1111-1111-1111-111111111111"
                         && (box.values[key("savedProviders")] as? String)?.contains("\"name\":\"Mine\"") == true
                         && box.values[key("promptHistory")] as? String == #"["first","second"]"#
                         && box.values[key("hiddenClaudeSessions")] as? String == #"["abc"]"#,
                     "under the tool's keys, as the tool reads them: \(box.values)")
        suite.expect(recorder.shortcuts == [GlobalShortcut(keyCode: 49, modifiers: [.command, .shift])],
                     "the Quick Prompt's shortcut is given to the tool's command")
        suite.expect(defaults[Preferences.nexusAgentReplacedByTool] && !defaults[Preferences.nexusAgentShortcutEnabled]
                         && recorder.turnedOff == 1,
                     "the feature is marked replaced, its shortcut off, and told to hide")
        suite.expect(!AppFeature.nexusAgent.isAvailable(in: defaults) && AppFeature.nexusAgent.isReplaced(in: defaults)
                         && defaults.bool(forKey: AppFeature.nexusAgent.availabilityKey)
                         && !AppFeature.notch.isReplaced(in: defaults),
                     "after: the feature is hidden, though still installed; nothing else is")
        suite.expect(recorder.logged.contains { $0.contains("version 1.22.0 from the catalog") },
                     "the log says what was handed over, and from where: \(recorder.logged)")
    }

    static func whatIsHandedIsWhatTheToolReads(_ suite: TestSuite) {
        let defaults = defaults("values")
        defaults[Preferences.nexusAgentSavedProviders] = Data()
        defaults[Preferences.nexusAgentPromptHistory] = []
        let values = NexusAgentHandoff.values(defaults: defaults, hiddenClaudeSessions: [])
        suite.expect(values["savedProviders"] == .string("") && values["promptHistory"] == .string("")
                         && values["hiddenClaudeSessions"] == .string(""),
                     "nothing saved is handed as nothing, not as an empty list: \(values)")
        suite.expect(NexusAgentHandoff.shortcut(defaults: defaults) == GlobalShortcut(keyCode: 49, modifiers: [.command, .shift]),
                     "the shortcut as saved")
        defaults[Preferences.nexusAgentShortcutEnabled] = false
        suite.expect(NexusAgentHandoff.shortcut(defaults: defaults) == nil, "no shortcut while its switch is off")
        defaults[Preferences.nexusAgentShortcutEnabled] = true
        defaults[Preferences.nexusAgentShortcut] = "not a shortcut"
        suite.expect(NexusAgentHandoff.shortcut(defaults: defaults) == .nexusAgentDefault,
                     "an unreadable saved shortcut is the feature's default, as the feature read it")
    }

    static func otherToolsAndAnUpdateHandNothing(_ suite: TestSuite) {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = defaults("others")
        let box = Box()
        let recorder = Recorder()
        let other = Data(String(decoding: manifest, as: UTF8.self)
            .replacingOccurrences(of: "dev.vitruvian.nexus-agent", with: "com.acme.deploys").utf8)
        guard let deploys = installedTool(manifest: other, in: root) else { return suite.expect(false, "the other manifest reads") }
        suite.expect(NexusAgentHandoff.perform(deploys, from: nil, parts: parts(defaults, box: box, recorder: recorder)) == .notTheTool
                         && box.values.isEmpty && !defaults[Preferences.nexusAgentReplacedByTool] && recorder.turnedOff == 0,
                     "another tool gets nothing, and the feature stays")
        guard let nexus = installedTool(in: root) else { return suite.expect(false, "the Nexus Agent tool's manifest reads") }
        _ = NexusAgentHandoff.perform(nexus, from: nil, parts: parts(defaults, box: box, recorder: recorder))
        box.values = [:]
        suite.expect(NexusAgentHandoff.perform(nexus, from: nil, parts: parts(defaults, box: box, recorder: recorder)) == .alreadyReplaced
                         && box.values.isEmpty && recorder.turnedOff == 1,
                     "the tool updated, or added again: nothing is handed a second time")
        // The manifest without its last preference, as an older tool's.
        let older = Data(String(decoding: manifest, as: UTF8.self)
            .replacingOccurrences(of: ",\n   {\"id\": \"hiddenClaudeSessions\", \"type\": \"string\", \"default\": \"\"}", with: "").utf8)
        let fresh = self.defaults("older")
        let older_recorder = Recorder()
        guard let old = installedTool(manifest: older, in: root) else { return suite.expect(false, "the older manifest reads") }
        let outcome = NexusAgentHandoff.perform(old, from: nil, parts: parts(fresh, box: Box(), recorder: older_recorder))
        suite.expect(outcome == .handed(["autoStart", "botDirectory", "chosenProvider", "planMode", "promptHistory",
                                         "savedProviders", "worktreeMode"], shortcut: true)
                         && older_recorder.logged.contains { $0.contains("does not take hiddenClaudeSessions") },
                     "a tool whose manifest lacks a preference is handed the rest, and the log names what it did not take: \(outcome)")
    }

    static func removalBringsTheFeatureBackOff(_ suite: TestSuite) {
        let defaults = defaults("removal")
        defaults[Preferences.nexusAgentReplacedByTool] = true
        defaults[Preferences.nexusAgentShortcutEnabled] = false
        var back = 0
        NexusAgentHandoff.toolRemoved(ToolID("com.acme.deploys")!, defaults: defaults, featureBack: { back += 1 })
        suite.expect(defaults[Preferences.nexusAgentReplacedByTool] && back == 0, "another tool's removal changes nothing")
        NexusAgentHandoff.toolRemoved(NexusAgentHandoff.toolID, defaults: defaults, featureBack: { back += 1 })
        suite.expect(!defaults[Preferences.nexusAgentReplacedByTool] && AppFeature.nexusAgent.isAvailable(in: defaults)
                         && !defaults[Preferences.nexusAgentShortcutEnabled] && back == 1,
                     "the Nexus Agent tool's removal brings the feature back, its shortcut off")
    }

    static func theStoreTellsBeforeTheProgramStarts(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        let folder = bench.folder("nexus-agent", manifest: manifest, exec: "bin/tool")
        guard case .success = bench.add(folder) else { return suite.expect(false, "the Nexus Agent tool is added") }
        suite.expect(bench.added.map(\.id) == [NexusAgentHandoff.toolID] && bench.added.first?.programStarted == false,
                     "the store tells of the added tool before its program starts, so what is handed is there for its first run")
        _ = bench.store.remove(NexusAgentHandoff.toolID, deletingData: true)
        suite.expect(bench.removed == [NexusAgentHandoff.toolID], "and of its removal")
    }

    /// The model chosen for each provider, and the sessions pinned and
    /// renamed, which the chat keeps in keys of the app's own: handed as
    /// JSON text when there are any, to a tool whose manifest declares them.
    static func modelsAndSessionsGoWhenThereAreAny(_ suite: TestSuite) {
        let defaults = defaults("models")
        let none = NexusAgentHandoff.values(defaults: defaults, hiddenClaudeSessions: [])
        suite.expect(none["chosenModels"] == nil && none["pinnedSessions"] == nil && none["renamedSessions"] == nil,
                     "with none chosen, pinned or renamed, nothing is handed for them: \(none.keys.sorted())")
        let provider = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let host = VitruvianNexusAgentHost(defaults: defaults)
        host.chosenModels = [provider: "opus"]
        host.sessionPreferences = NexusAgentSessionPreferences(pinnedSessionIDs: ["s2", "s1"],
                                                               renamedSessionTitles: ["s1": "Release", "s0": "Old"])
        let values = NexusAgentHandoff.values(defaults: defaults, hiddenClaudeSessions: [])
        suite.expect(values["chosenModels"] == .string(#"{"11111111-1111-1111-1111-111111111111":"opus"}"#)
                         && values["pinnedSessions"] == .string(#"["s1","s2"]"#)
                         && values["renamedSessions"] == .string(#"{"s0":"Old","s1":"Release"}"#),
                     "each as JSON text, in order: \(values)")

        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let declaring = Data(String(decoding: manifest, as: UTF8.self).replacingOccurrences(
            of: #"{"id": "hiddenClaudeSessions", "type": "string", "default": ""}"#,
            with: #"{"id": "hiddenClaudeSessions", "type": "string", "default": ""}, "#
                + #"{"id": "chosenModels", "type": "string", "default": ""}, "#
                + #"{"id": "pinnedSessions", "type": "string", "default": ""}, "#
                + #"{"id": "renamedSessions", "type": "string", "default": ""}"#).utf8)
        let box = Box()
        let recorder = Recorder()
        guard let tool = installedTool(manifest: declaring, in: root) else {
            return suite.expect(false, "the manifest that declares them reads")
        }
        let outcome = NexusAgentHandoff.perform(tool, from: nil, parts: parts(defaults, box: box, recorder: recorder))
        let key = { ExternalToolManifest.storageKey(tool: NexusAgentHandoff.toolID, preference: $0) }
        suite.expect(outcome == .handed(["autoStart", "botDirectory", "chosenModels", "chosenProvider", "hiddenClaudeSessions",
                                         "pinnedSessions", "planMode", "promptHistory", "renamedSessions", "savedProviders",
                                         "worktreeMode"], shortcut: true)
                         && box.values[key("pinnedSessions")] as? String == #"["s1","s2"]"#,
                     "a tool that declares them is handed them with the rest: \(outcome)")

        let older = self.defaults("models-older")
        VitruvianNexusAgentHost(defaults: older).chosenModels = [provider: "opus"]
        let olderRecorder = Recorder()
        guard let plain = installedTool(in: root) else { return suite.expect(false, "the manifest reads") }
        let rest = NexusAgentHandoff.perform(plain, from: nil, parts: parts(older, box: Box(), recorder: olderRecorder))
        suite.expect(rest == .handed(["autoStart", "botDirectory", "chosenProvider", "hiddenClaudeSessions", "planMode",
                                      "promptHistory", "savedProviders", "worktreeMode"], shortcut: true)
                         && olderRecorder.logged.contains { $0.contains("does not take chosenModels") },
                     "a tool that does not declare them is handed the rest, and the log says what it did not take")
    }
}
