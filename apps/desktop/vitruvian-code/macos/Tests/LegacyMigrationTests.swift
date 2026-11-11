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

import XCTest

import VitruvianCodeCore

/// The first-launch move from Nexus Agent, over a temporary home: an old
/// install is written into it (settings, both folders with a private `.env`,
/// two automations), the move is run, and every piece is looked for in its
/// new place. A launchctl that only writes down what it was asked stands in
/// for the real one, so no test touches the account's LaunchAgents.
@MainActor
final class LegacyMigrationTests: XCTestCase {
    typealias Migration = VitruvianCodeLegacyMigration

    private var home = ""
    private var defaults: UserDefaults!
    private var suite = ""
    private var launchctl = FakeLaunchctl()
    private let executable = "/Applications/Vitruvian Code.app/Contents/MacOS/VitruvianCode"
    private let fm = FileManager.default

    private let firstTask = "11111111-2222-3333-4444-555555555555"
    private let secondTask = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    /// Writes down each call, and answers from `respond`.
    final class FakeLaunchctl {
        var calls: [[String]] = []
        var respond: ([String]) -> Migration.LaunchctlResult = { _ in .init(status: 0) }

        func run(_ arguments: [String]) -> Migration.LaunchctlResult {
            calls.append(arguments)
            return respond(arguments)
        }
    }

    override func setUp() {
        super.setUp()
        home = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("legacy-migration-\(UUID().uuidString)")
        try? fm.createDirectory(atPath: home, withIntermediateDirectories: true)
        suite = "com.vitruviansoftware.code.tests.migration.\(UUID().uuidString)"
        defaults = ScratchDefaults.suite(named: suite)
        launchctl = FakeLaunchctl()
    }

    override func tearDown() {
        // A read-only folder cannot be emptied until it is let be written in.
        for sub in (fm.subpaths(atPath: home) ?? []) {
            try? fm.setAttributes([.posixPermissions: NSNumber(value: 0o700)],
                                  ofItemAtPath: (home as NSString).appendingPathComponent(sub))
        }
        try? fm.removeItem(atPath: home)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: - A fake old install

    /// Real keys of the old app: ConfigManager's, StandaloneHost's and the
    /// session drawer's, in the types they are saved in.
    private var oldSettings: [String: Any] {
        [
            "autoStart": true,
            "autoCheckUpdates": false,
            "hotkeyKey": "k",
            "hotkeyModifiers": 1_179_648,
            "planMode": true,
            "timelineOnLeft": true,
            "worktreeMode": true,
            "hiddenClaudeSessionIds": ["c1", "c2"],
            "activeProviderId": "00000000-0000-0000-0000-000000000003",
            "chosenModels": ["00000000-0000-0000-0000-000000000001": "gemini-pro"],
            "promptHistory": ["first prompt", "second prompt"],
            "customProviders": Data("[{\"name\":\"Aider\"}]".utf8),
            "builtInProviders_v3": Data("[]".utf8),
            "nexusAgent.pinnedSessionIDs": ["s1", "s2"],
            "nexusAgent.renamedSessionTitles": ["s1": "Better name"],
            "AppleTestingKey": "not the app's",
        ]
    }

    private func write(_ text: String, to relative: String, mode: Int = 0o644) throws {
        let path = (home as NSString).appendingPathComponent(relative)
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path)
    }

    private func read(_ relative: String) -> String? {
        try? String(contentsOfFile: (home as NSString).appendingPathComponent(relative), encoding: .utf8)
    }

    private func mode(_ relative: String) -> Int? {
        let path = (home as NSString).appendingPathComponent(relative)
        return (try? fm.attributesOfItem(atPath: path))?[.posixPermissions] as? Int
    }

    private func exists(_ relative: String) -> Bool {
        fm.fileExists(atPath: (home as NSString).appendingPathComponent(relative))
    }

    private func legacyAutomation(id: String, hour: Int) -> [String: Any] {
        [
            "Label": "nexus-agent.automation.\(id)",
            "ProgramArguments": ["/Applications/NexusAgent.app/Contents/MacOS/NexusAgent", "--run-automation", id.uppercased()],
            "WorkingDirectory": "/tmp/project",
            "RunAtLoad": false,
            "StartCalendarInterval": ["Hour": hour, "Minute": 30],
        ]
    }

    private func seedOldInstall(workingDirectory: String? = nil) throws {
        try write("old bot log\n", to: "Library/Application Support/NexusAgent/bot.log")
        try write("[{\"id\":\"1\"}]", to: "Library/Application Support/NexusAgent/automations.json")
        try write("{}", to: "Library/Application Support/NexusAgent/accounts.json", mode: 0o600)
        try write("deep", to: "Library/Application Support/NexusAgent/sessions/2026/s1.json")
        try write("4242", to: "Library/Application Support/NexusAgent/.bot.pid")
        let working = workingDirectory ?? "\(home)/code/project"
        try write("TELEGRAM_BOT_TOKEN=123:abc\nALLOWED_USER_IDS=7\nAGY_WORKING_DIR=\(working)\n",
                  to: ".config/nexus-agent/.env", mode: 0o600)
        try write("module.exports = {}\n", to: ".config/nexus-agent/bot.js", mode: 0o755)
        try write("x", to: ".config/nexus-agent/state/cache.txt")
        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o700)],
                             ofItemAtPath: (home as NSString).appendingPathComponent(".config/nexus-agent/state"))

        let agents = (home as NSString).appendingPathComponent("Library/LaunchAgents")
        try fm.createDirectory(atPath: agents, withIntermediateDirectories: true)
        for (id, hour) in [(firstTask, 9), (secondTask, 17)] {
            let data = try PropertyListSerialization.data(fromPropertyList: legacyAutomation(id: id, hour: hour),
                                                          format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: agents + "/nexus-agent.automation.\(id).plist"))
        }
        // Somebody else's agent, which the move must not touch.
        try write("<plist/>", to: "Library/LaunchAgents/com.example.other.plist")
    }

    private func migration(old: [String: Any]? = nil, canRewriteAutomations: Bool = true) -> Migration {
        let legacy = old ?? oldSettings
        return Migration(environment: .init(
            home: home,
            userID: 501,
            executablePath: executable,
            settings: .init(value: { [defaults] in defaults?.object(forKey: $0) },
                            set: { [defaults] in defaults?.set($0, forKey: $1) }),
            readLegacyDefaults: { legacy },
            launchctl: { [launchctl] in launchctl.run($0) },
            log: { _ in },
            canRewriteAutomations: canRewriteAutomations))
    }

    // MARK: - Everything arrives

    func testAnOldInstallArrivesWholeAndTheFlagIsSet() throws {
        try seedOldInstall()
        let outcome = migration().run()

        XCTAssertTrue(outcome.completed, "\(outcome.failures.map(\.line))")
        XCTAssertFalse(outcome.alreadyDone)
        XCTAssertTrue(outcome.oldInstallFound)
        XCTAssertTrue(defaults.bool(forKey: "migratedFromNexusAgent"))

        // Settings: every key, with its value; the two that carried the old
        // name carry the new one; the system's own key stayed behind.
        XCTAssertEqual(defaults.bool(forKey: "autoStart"), true)
        XCTAssertEqual(defaults.bool(forKey: "autoCheckUpdates"), false)
        XCTAssertNotNil(defaults.object(forKey: "autoCheckUpdates"))
        XCTAssertEqual(defaults.string(forKey: "hotkeyKey"), "k")
        XCTAssertEqual(defaults.integer(forKey: "hotkeyModifiers"), 1_179_648)
        XCTAssertEqual(defaults.bool(forKey: "planMode"), true)
        XCTAssertEqual(defaults.bool(forKey: "timelineOnLeft"), true)
        XCTAssertEqual(defaults.bool(forKey: "worktreeMode"), true)
        XCTAssertEqual(defaults.stringArray(forKey: "hiddenClaudeSessionIds"), ["c1", "c2"])
        XCTAssertEqual(defaults.string(forKey: "activeProviderId"), "00000000-0000-0000-0000-000000000003")
        XCTAssertEqual(defaults.dictionary(forKey: "chosenModels") as? [String: String],
                       ["00000000-0000-0000-0000-000000000001": "gemini-pro"])
        XCTAssertEqual(defaults.stringArray(forKey: "promptHistory"), ["first prompt", "second prompt"])
        XCTAssertEqual(defaults.data(forKey: "customProviders"), Data("[{\"name\":\"Aider\"}]".utf8))
        XCTAssertEqual(defaults.data(forKey: "builtInProviders_v3"), Data("[]".utf8))
        XCTAssertEqual(defaults.stringArray(forKey: VitruvianCodeSessionPreferences.pinnedKey), ["s1", "s2"])
        XCTAssertEqual(defaults.dictionary(forKey: VitruvianCodeSessionPreferences.renamedKey) as? [String: String],
                       ["s1": "Better name"])
        XCTAssertNil(defaults.object(forKey: "nexusAgent.pinnedSessionIDs"))
        XCTAssertNil(defaults.object(forKey: "AppleTestingKey"))

        // Folders: contents, modes, and the old ones still there.
        XCTAssertEqual(read("Library/Application Support/Vitruvian Code/bot.log"), "old bot log\n")
        XCTAssertEqual(read("Library/Application Support/Vitruvian Code/automations.json"), "[{\"id\":\"1\"}]")
        XCTAssertEqual(read("Library/Application Support/Vitruvian Code/sessions/2026/s1.json"), "deep")
        XCTAssertEqual(mode("Library/Application Support/Vitruvian Code/accounts.json"), 0o600)
        XCTAssertFalse(exists("Library/Application Support/Vitruvian Code/.bot.pid"), "a process id is not data")
        XCTAssertEqual(read(".config/vitruvian-code/.env"),
                       "TELEGRAM_BOT_TOKEN=123:abc\nALLOWED_USER_IDS=7\nAGY_WORKING_DIR=\(home)/code/project\n")
        XCTAssertEqual(mode(".config/vitruvian-code/.env"), 0o600)
        XCTAssertEqual(mode(".config/vitruvian-code/bot.js"), 0o755)
        XCTAssertEqual(read(".config/vitruvian-code/state/cache.txt"), "x")
        XCTAssertEqual(mode(".config/vitruvian-code/state"), 0o700)
        XCTAssertTrue(exists(".config/nexus-agent/.env"))
        XCTAssertTrue(exists("Library/Application Support/NexusAgent/bot.log"))
        let leftovers = (fm.subpaths(atPath: home) ?? []).filter { $0.contains(".migrating-") }
        XCTAssertEqual(leftovers, [])

        // Automations: moved under the new label and program; the rest kept.
        for (id, hour) in [(firstTask, 9), (secondTask, 17)] {
            XCTAssertFalse(exists("Library/LaunchAgents/nexus-agent.automation.\(id).plist"))
            let data = try XCTUnwrap(fm.contents(atPath: "\(home)/Library/LaunchAgents/com.vitruviansoftware.code.automation.\(id).plist"))
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
            XCTAssertEqual(plist["Label"] as? String, "com.vitruviansoftware.code.automation.\(id)")
            XCTAssertEqual(plist["ProgramArguments"] as? [String], [executable, "--run-automation", id.uppercased()])
            XCTAssertEqual(plist["WorkingDirectory"] as? String, "/tmp/project")
            XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
            XCTAssertEqual((plist["StartCalendarInterval"] as? [String: Int]), ["Hour": hour, "Minute": 30])
        }
        XCTAssertEqual(read("Library/LaunchAgents/com.example.other.plist"), "<plist/>")

        // launchctl was asked, per automation: unload the old, clear the new,
        // load the new, in that order and for this user.
        let first = "\(home)/Library/LaunchAgents/com.vitruviansoftware.code.automation.\(firstTask).plist"
        XCTAssertEqual(launchctl.calls.filter { $0.first == "bootout" || $0.first == "bootstrap" }.prefix(3).map { $0 }, [
            ["bootout", "gui/501/nexus-agent.automation.\(firstTask)"],
            ["bootout", "gui/501/com.vitruviansoftware.code.automation.\(firstTask)"],
            ["bootstrap", "gui/501", first],
        ])
        XCTAssertEqual(launchctl.calls.count, 6)

        // What the person is to be told.
        XCTAssertEqual(outcome.permissions, [.accessibility, .notifications])
        XCTAssertTrue(outcome.needsNotice)
        XCTAssertEqual(defaults.stringArray(forKey: "legacyPermissionsToRegrant"), ["accessibility", "notifications"])
    }

    func testARunAfterItHasFinishedChangesNothing() throws {
        try seedOldInstall()
        _ = migration().run()
        let callsAfterFirst = launchctl.calls.count

        // The person changes the new app's files; a second launch leaves them.
        try write("TELEGRAM_BOT_TOKEN=changed\n", to: ".config/vitruvian-code/.env", mode: 0o600)
        defaults.set("j", forKey: "hotkeyKey")

        let again = migration().run()
        XCTAssertTrue(again.alreadyDone)
        XCTAssertTrue(again.changes.isEmpty)
        XCTAssertEqual(launchctl.calls.count, callsAfterFirst, "launchctl is not asked again")
        XCTAssertEqual(read(".config/vitruvian-code/.env"), "TELEGRAM_BOT_TOKEN=changed\n")
        XCTAssertEqual(defaults.string(forKey: "hotkeyKey"), "j")
    }

    func testEveryStepIsIdempotentEvenWhenTheFlagWasLost() throws {
        try seedOldInstall()
        _ = migration().run()
        defaults.removeObject(forKey: "migratedFromNexusAgent")

        try write("TELEGRAM_BOT_TOKEN=changed\n", to: ".config/vitruvian-code/.env", mode: 0o600)
        defaults.set("j", forKey: "hotkeyKey")
        let before = (fm.subpaths(atPath: home) ?? []).sorted()
        let callsBefore = launchctl.calls.count

        let again = migration().run()
        XCTAssertFalse(again.alreadyDone)
        XCTAssertTrue(again.completed)
        XCTAssertEqual(again.changes, [], "nothing left to do, nothing done")
        XCTAssertEqual((fm.subpaths(atPath: home) ?? []).sorted(), before)
        XCTAssertEqual(launchctl.calls.count, callsBefore)
        XCTAssertEqual(read(".config/vitruvian-code/.env"), "TELEGRAM_BOT_TOKEN=changed\n", "never overwritten")
        XCTAssertEqual(defaults.string(forKey: "hotkeyKey"), "j", "the new app's own value wins")
        XCTAssertTrue(defaults.bool(forKey: "migratedFromNexusAgent"))
    }

    // MARK: - Failures are surfaced and retried

    func testAFailedLoadKeepsTheFlagUnsetAndSaysSo() throws {
        try seedOldInstall()
        launchctl.respond = { arguments in
            arguments.first == "bootstrap" ? .init(status: 5, output: "Bootstrap failed: 5: Input/output error") : .init(status: 0)
        }
        let outcome = migration().run()

        XCTAssertFalse(outcome.completed)
        XCTAssertFalse(defaults.bool(forKey: "migratedFromNexusAgent"), "the flag waits for every step")
        XCTAssertTrue(outcome.needsNotice)
        XCTAssertEqual(outcome.failures.count, 2)
        XCTAssertEqual(outcome.failures.first?.step, .automations)
        XCTAssertTrue(outcome.failures.first?.message.contains("Input/output error") ?? false, "\(outcome.failures)")
        // The old file stays until its replacement is loaded.
        XCTAssertTrue(exists("Library/LaunchAgents/nexus-agent.automation.\(firstTask).plist"))
        // The steps that worked are done all the same.
        XCTAssertEqual(defaults.string(forKey: "hotkeyKey"), "k")
        XCTAssertEqual(mode(".config/vitruvian-code/.env"), 0o600)

        // The next launch, with launchctl well, finishes the job.
        launchctl.respond = { _ in .init(status: 0) }
        let retry = migration().run()
        XCTAssertTrue(retry.completed, "\(retry.failures.map(\.line))")
        XCTAssertTrue(defaults.bool(forKey: "migratedFromNexusAgent"))
        XCTAssertFalse(exists("Library/LaunchAgents/nexus-agent.automation.\(firstTask).plist"))
        XCTAssertFalse(exists("Library/LaunchAgents/nexus-agent.automation.\(secondTask).plist"))
        XCTAssertEqual(retry.changes.count, 2, "only the two automations were left: \(retry.changes)")
    }

    func testAnOldAgentThatWillNotUnloadIsNotReplacedBehindItsBack() throws {
        try seedOldInstall()
        launchctl.respond = { arguments in
            arguments == ["bootout", "gui/501/nexus-agent.automation.\(self.firstTask)"]
                ? .init(status: 1, output: "Operation not permitted") : .init(status: 0)
        }
        let outcome = migration().run()

        XCTAssertEqual(outcome.failures.map(\.step), [.automations])
        XCTAssertTrue(exists("Library/LaunchAgents/nexus-agent.automation.\(firstTask).plist"))
        XCTAssertFalse(launchctl.calls.contains { $0.first == "bootstrap" && $0.last?.contains(self.firstTask) == true },
                       "the new one is not loaded while the old one still runs")
        // The other automation moved regardless.
        XCTAssertFalse(exists("Library/LaunchAgents/nexus-agent.automation.\(secondTask).plist"))
        XCTAssertFalse(defaults.bool(forKey: "migratedFromNexusAgent"))
    }

    func testAnAgentThatIsNotLoadedCountsAsUnloaded() throws {
        try seedOldInstall()
        launchctl.respond = { arguments in
            arguments.first == "bootout" ? .init(status: 113, output: "Boot-out failed: 113: Could not find service") : .init(status: 0)
        }
        let outcome = migration().run()
        XCTAssertTrue(outcome.completed, "\(outcome.failures.map(\.line))")
        XCTAssertTrue(defaults.bool(forKey: "migratedFromNexusAgent"))
    }

    func testAFolderThatCannotBeCopiedIsReportedNotSkipped() throws {
        try seedOldInstall()
        // A file where the new bot folder has to go.
        try write("in the way", to: ".config/vitruvian-code")
        let outcome = migration().run()

        XCTAssertFalse(outcome.completed)
        XCTAssertTrue(outcome.failures.contains { $0.step == .folders && $0.item.hasSuffix(".config/vitruvian-code") },
                      "\(outcome.failures)")
        XCTAssertFalse(defaults.bool(forKey: "migratedFromNexusAgent"))
        XCTAssertEqual(read(".config/vitruvian-code"), "in the way")
        // Application Support, which could be copied, was.
        XCTAssertEqual(read("Library/Application Support/Vitruvian Code/bot.log"), "old bot log\n")
    }

    // MARK: - Nothing to move, and nothing to overwrite

    func testNoOldInstallMeansNothingToMoveAndNothingToSay() {
        let outcome = migration(old: [:]).run()
        XCTAssertTrue(outcome.completed)
        XCTAssertFalse(outcome.oldInstallFound)
        XCTAssertTrue(outcome.reports.isEmpty)
        XCTAssertTrue(outcome.permissions.isEmpty)
        XCTAssertFalse(outcome.needsNotice)
        XCTAssertTrue(defaults.bool(forKey: "migratedFromNexusAgent"))
        XCTAssertTrue(launchctl.calls.isEmpty)
        XCTAssertFalse(exists(".config/vitruvian-code"))
    }

    func testWhatTheNewAppAlreadyHasIsKept() throws {
        try seedOldInstall()
        defaults.set("p", forKey: "hotkeyKey")
        try write("TELEGRAM_BOT_TOKEN=new\n", to: ".config/vitruvian-code/.env", mode: 0o600)

        let outcome = migration().run()
        XCTAssertTrue(outcome.completed)
        XCTAssertEqual(defaults.string(forKey: "hotkeyKey"), "p")
        XCTAssertEqual(read(".config/vitruvian-code/.env"), "TELEGRAM_BOT_TOKEN=new\n")
        // What it lacked still arrives, into the folder that was there.
        XCTAssertEqual(read(".config/vitruvian-code/state/cache.txt"), "x")
    }

    // MARK: - Privacy grants

    func testAGuardedWorkingFolderAddsFilesAndFolders() throws {
        try seedOldInstall(workingDirectory: "\(home)/Documents/work")
        XCTAssertEqual(migration().run().permissions, [.accessibility, .notifications, .filesAndFolders])
    }

    func testTheNoticeIsOnceOnly() throws {
        try seedOldInstall()
        let first = migration()
        XCTAssertTrue(first.run().needsNotice)
        // Shown again at the next launch until the person has read it ...
        XCTAssertTrue(migration().run().needsNotice)
        first.markPermissionsExplained()
        // ... and never after.
        let after = migration().run()
        XCTAssertTrue(after.alreadyDone)
        XCTAssertFalse(after.needsNotice)
    }

    func testEachPermissionPointsAtItsPaneOfSystemSettings() {
        for permission in Migration.Permission.allCases {
            XCTAssertTrue(permission.settingsURL.hasPrefix("x-apple.systempreferences:"), permission.rawValue)
            XCTAssertNotNil(URL(string: permission.settingsURL), permission.rawValue)
        }
        XCTAssertTrue(Migration.Permission.accessibility.settingsURL.hasSuffix("Privacy_Accessibility"))
    }

    // MARK: - launchd

    func testAFailedLoadOfTheNewJobLoadsTheOldOneAgain() throws {
        try seedOldInstall()
        let oldPath = "\(home)/Library/LaunchAgents/nexus-agent.automation.\(firstTask).plist"
        launchctl.respond = { arguments in
            arguments.first == "bootstrap" && (arguments.last ?? "").contains("com.vitruviansoftware.code.automation.\(self.firstTask)")
                ? .init(status: 5, output: "Bootstrap failed: 5: Input/output error") : .init(status: 0)
        }
        let outcome = migration().run()

        XCTAssertFalse(defaults.bool(forKey: "migratedFromNexusAgent"), "the flag waits")
        XCTAssertEqual(outcome.failures.map(\.step), [.automations])
        XCTAssertTrue(exists("Library/LaunchAgents/nexus-agent.automation.\(firstTask).plist"), "the old file is kept")
        let calls = launchctl.calls
        let failedNew = try XCTUnwrap(calls.firstIndex { $0.first == "bootstrap" && ($0.last ?? "").contains("com.vitruviansoftware.code.automation.\(firstTask)") })
        let reloaded = try XCTUnwrap(calls.lastIndex(of: ["bootstrap", "gui/501", oldPath]))
        XCTAssertGreaterThan(reloaded, failedNew, "the old job is loaded again after the new one failed")
        XCTAssertTrue(outcome.failures.first?.message.contains("the old one is loaded again") ?? false, "\(outcome.failures)")
        // The other automation moved on its own.
        XCTAssertFalse(exists("Library/LaunchAgents/nexus-agent.automation.\(secondTask).plist"))
    }

    func testAnOldJobThatWasNotLoadedIsNotLoadedByAFailure() throws {
        try seedOldInstall()
        launchctl.respond = { arguments in
            if arguments.first == "bootout" { return .init(status: 113, output: "Could not find service") }
            return arguments.first == "bootstrap" ? .init(status: 5, output: "no") : .init(status: 0)
        }
        _ = migration().run()
        XCTAssertFalse(launchctl.calls.contains { $0.first == "bootstrap" && ($0.last ?? "").contains("nexus-agent.automation") },
                       "what was not running is not started by a failure")
    }

    func testAutomationsWaitWhenTheAppIsNotInstalled() throws {
        try seedOldInstall()
        let waiting = migration(canRewriteAutomations: false).run()

        XCTAssertFalse(waiting.completed)
        XCTAssertTrue(waiting.needsNotice)
        XCTAssertEqual(waiting.failures.count, 0, "waiting is not failing")
        XCTAssertEqual(waiting.deferrals.count, 1)
        XCTAssertTrue(waiting.deferrals[0].contains("Applications"), "\(waiting.deferrals)")
        XCTAssertFalse(defaults.bool(forKey: "migratedFromNexusAgent"))
        XCTAssertTrue(launchctl.calls.isEmpty)
        XCTAssertTrue(exists("Library/LaunchAgents/nexus-agent.automation.\(firstTask).plist"))
        XCTAssertFalse(exists("Library/LaunchAgents/com.vitruviansoftware.code.automation.\(firstTask).plist"))
        // The rest moved all the same.
        XCTAssertEqual(defaults.string(forKey: "hotkeyKey"), "k")
        XCTAssertEqual(read(".config/vitruvian-code/bot.js"), "module.exports = {}\n")

        let installed = migration().run()
        XCTAssertTrue(installed.completed, "\(installed.failures.map(\.line)) \(installed.deferrals)")
        XCTAssertTrue(defaults.bool(forKey: "migratedFromNexusAgent"))
        XCTAssertFalse(exists("Library/LaunchAgents/nexus-agent.automation.\(firstTask).plist"))
    }

    func testOnlyAnAppInApplicationsMayHaveAgentsPointAtIt() {
        typealias Env = Migration.Environment
        XCTAssertTrue(Env.isInstalledForAutomations(bundlePath: "/Applications/Vitruvian Code.app", home: "/Users/a"))
        XCTAssertTrue(Env.isInstalledForAutomations(bundlePath: "/Users/a/Applications/Vitruvian Code.app", home: "/Users/a"))
        XCTAssertFalse(Env.isInstalledForAutomations(
            bundlePath: "/private/var/folders/x/T/AppTranslocation/ABC/d/Vitruvian Code.app", home: "/Users/a"))
        XCTAssertFalse(Env.isInstalledForAutomations(bundlePath: "/Applications/AppTranslocation/x/Vitruvian Code.app", home: "/Users/a"))
        XCTAssertFalse(Env.isInstalledForAutomations(bundlePath: "/Users/a/Downloads/Vitruvian Code.app", home: "/Users/a"))
        XCTAssertFalse(Env.isInstalledForAutomations(bundlePath: "/Volumes/Disk/Vitruvian Code.app", home: "/Users/a"))
    }

    // MARK: - Folder copy details

    func testUnfinishedCopiesAreCleanedUpAndTheFileIsCopiedAgain() throws {
        try seedOldInstall()
        let stale = ".config/vitruvian-code/.env.migrating-\(UUID().uuidString)"
        try write("half", to: stale)
        let notOurs = ".config/vitruvian-code/notes.migrating-today"
        try write("someone's", to: notOurs)

        let outcome = migration().run()
        XCTAssertTrue(outcome.completed, "\(outcome.failures.map(\.line))")
        XCTAssertFalse(exists(stale), "an unfinished copy of ours is removed")
        XCTAssertTrue(exists(notOurs), "a file that merely looks like one is not")
        XCTAssertEqual(read(".config/vitruvian-code/.env")?.hasPrefix("TELEGRAM_BOT_TOKEN=123:abc"), true)
    }

    func testAReadOnlyFolderIsFilledAndThenGivenItsMode() throws {
        try seedOldInstall()
        try write("locale", to: ".config/nexus-agent/vendor/locale/en.txt")
        try write("more", to: ".config/nexus-agent/vendor/locale/deep/fr.txt")
        for folder in ["vendor/locale/deep", "vendor/locale"] {
            try fm.setAttributes([.posixPermissions: NSNumber(value: 0o500)],
                                 ofItemAtPath: "\(home)/.config/nexus-agent/\(folder)")
        }
        let outcome = migration().run()
        XCTAssertTrue(outcome.completed, "\(outcome.failures.map(\.line))")
        XCTAssertEqual(read(".config/vitruvian-code/vendor/locale/en.txt"), "locale")
        XCTAssertEqual(read(".config/vitruvian-code/vendor/locale/deep/fr.txt"), "more")
        XCTAssertEqual(mode(".config/vitruvian-code/vendor/locale"), 0o500)
        XCTAssertEqual(mode(".config/vitruvian-code/vendor/locale/deep"), 0o500)
    }

    func testAFolderLeftWritableByACutShortRunIsGivenItsModeNow() throws {
        try seedOldInstall()
        try write("x", to: ".config/nexus-agent/ro/a.txt")
        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o500)], ofItemAtPath: "\(home)/.config/nexus-agent/ro")
        // What a run cut short leaves: the folder, still owner-writable, with its file.
        try write("x", to: ".config/vitruvian-code/ro/a.txt")
        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: "\(home)/.config/vitruvian-code/ro")
        _ = migration().run()
        XCTAssertEqual(mode(".config/vitruvian-code/ro"), 0o500)
    }

    // MARK: - A real install, by hand

    /// An install shaped like a real one, in this test's own home: every
    /// saved setting the old app's sources name (read from `ConfigManager` and
    /// `StandaloneHost`, so a key added there is in it), in a preferences file
    /// as macOS writes it; Application Support with its state; and a bot folder
    /// with the private `.env`, a `node_modules` with links, a program and a
    /// read-only folder.
    ///
    /// Set `VITRUVIAN_CODE_REAL_HOME` to a folder laid out like a home that
    /// holds a copy of a real install, and that is used instead, copied in
    /// first, so the folder named is only ever read. Run it with
    /// `bazel test ... --test_env=VITRUVIAN_CODE_REAL_HOME=<folder>`.
    func testAnInstallShapedLikeARealOneArrivesWhole() throws {
        var keys: Set<String> = []
        for name in ["ConfigManager.swift", "StandaloneHost.swift"] {
            keys.formUnion(try savedKeys(inAppSource: name))
        }
        for sentinel in ["autoStart", "hotkeyKey", "hotkeyModifiers", "autoCheckUpdates", "planMode", "chosenModels",
                         "promptHistory", "customProviders", "builtInProviders_v3", "activeProviderId"] {
            XCTAssertTrue(keys.contains(sentinel), "the key list read from the app's sources lacks \(sentinel)")
        }

        let plistPath: String
        if let source = ProcessInfo.processInfo.environment["VITRUVIAN_CODE_REAL_HOME"], !source.isEmpty {
            for relative in ["Library/Application Support/NexusAgent", ".config/nexus-agent"] {
                let from = (source as NSString).appendingPathComponent(relative)
                guard fm.fileExists(atPath: from) else { continue }
                let to = (home as NSString).appendingPathComponent(relative)
                try fm.createDirectory(atPath: (to as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try fm.copyItem(atPath: from, toPath: to)
            }
            plistPath = source + "/Library/Preferences/com.vitruviansoftware.nexusagent.plist"
        } else {
            plistPath = try writeRealShapedInstall(keys: keys.union(["nexusAgent.pinnedSessionIDs", "nexusAgent.renamedSessionTitles"]))
        }
        let plistData = try XCTUnwrap(fm.contents(atPath: plistPath), "no old preferences file")
        let old = try XCTUnwrap(PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any])
        XCTAssertGreaterThan(old.count, 10)

        let outcome = migration(old: old).run()
        XCTAssertTrue(outcome.completed, "\(outcome.failures.map(\.line))")

        // Every setting.
        var copied = 0
        for (key, value) in old where !key.hasPrefix("Apple") {
            let target = Migration.newKey(forLegacy: key)
            let got = try XCTUnwrap(defaults.object(forKey: target), "setting \(key) did not arrive")
            XCTAssertTrue((got as AnyObject).isEqual(value), "setting \(key) changed on the way")
            copied += 1
        }

        // Every file, byte for byte, with its mode; and the old ones untouched.
        var files = 0
        for (oldRelative, newRelative) in [("Library/Application Support/NexusAgent", "Library/Application Support/Vitruvian Code"),
                                           (".config/nexus-agent", ".config/vitruvian-code")] {
            let oldRoot = (home as NSString).appendingPathComponent(oldRelative)
            guard fm.fileExists(atPath: oldRoot) else { continue }
            for sub in try fm.subpathsOfDirectory(atPath: oldRoot).sorted() where sub != ".bot.pid" {
                let oldPath = oldRoot + "/" + sub
                let newPath = (home as NSString).appendingPathComponent(newRelative) + "/" + sub
                let oldAttributes = try fm.attributesOfItem(atPath: oldPath)
                let newAttributes = try fm.attributesOfItem(atPath: newPath)
                XCTAssertEqual(newAttributes[.type] as? FileAttributeType, oldAttributes[.type] as? FileAttributeType, sub)
                XCTAssertEqual(newAttributes[.posixPermissions] as? Int, oldAttributes[.posixPermissions] as? Int, "mode of \(sub)")
                if oldAttributes[.type] as? FileAttributeType == .typeSymbolicLink {
                    XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: newPath), try fm.destinationOfSymbolicLink(atPath: oldPath), sub)
                }
                if oldAttributes[.type] as? FileAttributeType == .typeRegular {
                    XCTAssertEqual(fm.contents(atPath: newPath), fm.contents(atPath: oldPath), "bytes of \(sub)")
                    files += 1
                }
            }
        }
        XCTAssertGreaterThan(files, 20)
        XCTAssertEqual(mode(".config/vitruvian-code/.env"), 0o600)
        XCTAssertEqual((fm.subpaths(atPath: home) ?? []).filter { $0.contains(".migrating-") }, [])
        // Counts only; a real install's files hold a bot token.
        print("real-shaped install check: \(copied) settings and \(files) files arrived")
        XCTAssertTrue(defaults.bool(forKey: "migratedFromNexusAgent"))
    }

    /// The names a source file of the app saves settings under.
    private func savedKeys(inAppSource name: String) throws -> Set<String> {
        let relative = "apps/desktop/vitruvian-code/macos/Sources/VitruvianCode/\(name)"
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let here = (#filePath as NSString).deletingLastPathComponent
        candidates.append((here as NSString).deletingLastPathComponent + "/Sources/VitruvianCode/\(name)")
        let path = try XCTUnwrap(candidates.first { fm.fileExists(atPath: $0) }, "cannot find \(name)")
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"(?:forKey|set\(|object\(forKey):\s*"([A-Za-z0-9_.]+)""#)
        let found = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
        return Set(found)
    }

    /// Writes the install into `home` and returns the old preferences file.
    private func writeRealShapedInstall(keys: Set<String>) throws -> String {
        var settings: [String: Any] = ["AppleLanguages": ["en"]]
        for (index, key) in keys.sorted().enumerated() {
            switch index % 4 {
            case 0: settings[key] = true
            case 1: settings[key] = "value of \(key)"
            case 2: settings[key] = ["a \(index)", "b \(index)"]
            default: settings[key] = Data("blob \(key)".utf8)
            }
        }
        let preferences = (home as NSString).appendingPathComponent("Library/Preferences")
        try fm.createDirectory(atPath: preferences, withIntermediateDirectories: true)
        let plistPath = preferences + "/com.vitruviansoftware.nexusagent.plist"
        try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
            .write(to: URL(fileURLWithPath: plistPath))

        try write("log\n", to: "Library/Application Support/NexusAgent/bot.log")
        try write("[]", to: "Library/Application Support/NexusAgent/automations.json")
        try write("{}", to: "Library/Application Support/NexusAgent/accounts.json", mode: 0o600)

        let bot = ".config/nexus-agent"
        try write("TELEGRAM_BOT_TOKEN=123:abc\nALLOWED_USER_IDS=7\nAGY_WORKING_DIR=\(home)/code\n", to: bot + "/.env", mode: 0o600)
        try write("TELEGRAM_BOT_TOKEN=\n", to: bot + "/.env.example")
        try write("{\"name\":\"bot\"}", to: bot + "/package.json")
        for index in 0..<40 {
            try write("module \(index)\n", to: bot + "/node_modules/pkg\(index)/index.js")
            try write("{\"v\":\(index)}", to: bot + "/node_modules/pkg\(index)/package.json")
        }
        try write("#!/usr/bin/env node\n", to: bot + "/node_modules/pkg0/cli.js", mode: 0o755)
        try fm.createDirectory(atPath: "\(home)/\(bot)/node_modules/.bin", withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: "\(home)/\(bot)/node_modules/.bin/pkg0", withDestinationPath: "../pkg0/cli.js")
        try write("locale", to: bot + "/node_modules/pkg1/locale/en.txt")
        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o500)], ofItemAtPath: "\(home)/\(bot)/node_modules/pkg1/locale")
        return plistPath
    }

    // MARK: - The new names

    func testTheNewNamesAreTheBrandedOnes() {
        XCTAssertEqual(VitruvianCodeSupport.defaultStateDirectory(home: "/Users/x"),
                       "/Users/x/Library/Application Support/Vitruvian Code")
        XCTAssertEqual(VitruvianCodeSupport.defaultBotDirectory(home: "/Users/x"), "/Users/x/.config/vitruvian-code")
        XCTAssertEqual(VitruvianCodeAutomationManager.launchdLabel(forTaskID: UUID(uuidString: firstTask)!),
                       "com.vitruviansoftware.code.automation.\(firstTask)")
        XCTAssertEqual(Migration.newKey(forLegacy: "nexusAgent.pinnedSessionIDs"), "vitruvianCode.pinnedSessionIDs")
        XCTAssertEqual(Migration.newKey(forLegacy: "hotkeyKey"), "hotkeyKey")
    }
}
