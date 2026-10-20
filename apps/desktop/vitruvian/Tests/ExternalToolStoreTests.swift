// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// Adding a tool from a folder: its two folders, the store that holds what
/// is installed, and the whole path from a command in the registry to a
/// program and back. The folders are made under the temporary folder. Only
/// the last test starts a program, the fixture tool.
enum ExternalToolStoreTests {
    static func run(_ suite: TestSuite) {
        folders(suite)
        links(suite)
        readOnlyFolders(suite)
        offering(suite)
        tooBigOrQuarantined(suite)
        adding(suite)
        theStoreTellsBeforeTheProgramStarts(suite)
        addingThatWaitsNeverHolds(suite)
        removalWhileWaitingDropsTheAdd(suite)
        agreeingTwiceAddsOnce(suite)
        throughTheBroker(suite)
        refusals(suite)
        deleting(suite)
        deletingMore(suite)
        removing(suite)
        goneBeforeDeleted(suite)
        saysWhatWasKept(suite)
        saysWhatCouldNotBeDeleted(suite)
        shortcutsOfARemovedTool(suite)
        installedOrNot(suite)
        remembering(suite)
        switching(suite)
        updating(suite)
        heldBack(suite)
        unreadableRecords(suite)
        toldOnce(suite)
        saysNothing(suite)
        languageChanges(suite)
        aRealTool(suite)
        aRealToolRemoved(suite)
        aRealToolWithAHelper(suite)
        panels(suite)
        theHelloNamesOnlyWhatTheAppHas(suite)
        theAppHasEveryFeatureOfTheProtocol(suite)
        theStatusSwitchIsYesUntilTurnedOff(suite)
        aRecordFromBeforeReadsAsItDid(suite)
        statusToolsLeavesOutASwitchedOffAndAnUndeclaredTool(suite)
        aStatusReachesTheHostAndGoesWithTheProgram(suite)
        aSettingCarriesItsOptions(suite)
        aValueThatIsNoOptionIsStillSaved(suite)
        homeSpeakerDoorClearedOnRemove(suite)
    }

    static let id = ExternalToolTests.id
    static let copy = ExternalToolTests.copy

    /// A store over a support folder of its own, a host, a registry and a
    /// broker whose services record. Each program it would start is a tool
    /// that is no program, unless `transport` says otherwise.
    final class Bench {
        let root: URL
        let clock = ManualToolClock()
        let registry = ToolRegistry(isAvailable: { _ in true })
        let box = ToolBrokerTests.PreferenceBox()
        var runs: [FakeTool] = []
        /// The file each run was to start, and the folder it was to run in.
        var started: [(program: URL, data: URL)] = []
        var transport: ((URL, URL) -> any ToolTransport)?
        var said: [String] = []
        var beeps = 0
        var stoppedWorking: [ToolID] = []
        /// Each wait the host made for a program to be gone, in seconds. It
        /// only really waits for a real program: a tool that is no program
        /// changes when the test says so, never while the host looks.
        var waits: [TimeInterval] = []
        /// The language the app is in, as the store reads it.
        var language = "fr"
        /// Each tool the store said it added, with whether a program had
        /// been started by then, and each it said it removed.
        var added: [(id: ToolID, programStarted: Bool)] = []
        var removed: [ToolID] = []
        /// What the store waits for before it adds a tool, when a test
        /// stands in for it; nothing otherwise.
        var beforeAdding: ((ToolID, @escaping @MainActor () -> Void) -> Void)?
        /// What the store asked to be told of a change of language with.
        var languageWatcher: (@MainActor (String) -> Void)?
        /// The shortcuts people gave to tool commands, over this bench's
        /// registry: what is saved, and hotkeys that register nothing.
        private(set) lazy var keys = ToolPlatformTests.RegistrarBench(registry: registry)
        private(set) var host: ToolHost!
        private(set) var store: ExternalToolStore!
        /// What draws the tools' panels, over this store, reading each page
        /// at once.
        private(set) var panels: ToolPanelHost!

        /// A bench over the folders of another, as the app is at its next
        /// launch: a new store, host and registry, and the same files.
        private let relaunchOf: Bench?

        init(supportFolder: Bool = true, limits: ToolLimits = .standard, relaunchOf: Bench? = nil) {
            self.relaunchOf = relaunchOf
            root = relaunchOf?.root ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("vitruvian-tool-store-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let box = self.box
            let broker = CapabilityBroker(
                environment: .init(isInstalled: { [unowned self] in store.isInstalled($0) },
                                   isGranted: { _ in true }, allows: { _, _ in true },
                                   reportUndeclared: { _, _ in }),
                backings: .init(notify: .init(beep: { [unowned self] in beeps += 1 },
                                              hud: { [unowned self] in said.append("\($0): \($1)") }),
                                open: .init(open: { _ in true }), clipboard: .init(write: { _, _ in }),
                                processes: .inert,
                                storage: .init(read: { box.values[$0] }, write: { box.values[$0] = $1 })))
            host = ToolHost(broker: broker, wait: { [unowned self] seconds, done in
                waits.append(seconds)
                if transport != nil { ToolHost.wait(upTo: seconds, until: done) }
            })
            store = ExternalToolStore(parts: .init(
                folders: supportFolder ? ToolFolders(root: support) : nil,
                host: { [unowned self] in host }, registry: { [unowned self] in registry }, broker: { broker },
                clock: clock, limits: limits,
                makeTransport: { [unowned self] program, data in
                    started.append((program, data))
                    if let transport { return transport(program, data) }
                    let run = FakeTool()
                    runs.append(run)
                    return run
                },
                language: { [unowned self] in language },
                stoppedWorking: { [unowned self] in stoppedWorking.append($0) },
                forgetPreferences: { id in
                    box.values = box.values.filter { !$0.key.hasPrefix(id.rawValue + "/") }
                },
                forgetShortcuts: { [unowned self] in keys.registrar.forget($0) },
                watchLanguage: { [unowned self] in
                    languageWatcher = $0
                    return nil
                },
                panels: { [unowned self] in panels },
                beforeAdding: { [unowned self] id, ready in
                    if let beforeAdding { beforeAdding(id, ready) } else { ready() }
                },
                added: { [unowned self] installed, _ in
                    added.append((installed.tool.manifest.id, !started.isEmpty))
                },
                removed: { [unowned self] in removed.append($0) }))
            panels = ToolPanelHost(parts: .init(
                clock: clock, limits: limits,
                tool: { [unowned self] in store.tool($0) },
                described: { [unowned self] in store.installed[$0]?.tool },
                folder: { [unowned self] in store.installed[$0]?.files },
                read: { value, then in then(ToolPanelTree.read(value)) }))
        }

        /// The app's support folder, as the store sees it.
        var support: URL { root.appendingPathComponent("support", isDirectory: true) }
        var files: URL { support.appendingPathComponent("Tools/com.acme.deploys", isDirectory: true) }
        var data: URL { support.appendingPathComponent("ToolData/com.acme.deploys", isDirectory: true) }
        var current: FakeTool { runs[runs.count - 1] }

        /// A folder a person might pick: the manifest, and a program. The
        /// program is `program`'s bytes, or an empty file that is never run.
        func folder(_ name: String = "picked", manifest: Data = ExternalToolManifestTests.file(),
                    exec: String = "bin/deploys", program: URL? = nil) -> URL {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            let file = folder.appendingPathComponent(exec)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? manifest.write(to: folder.appendingPathComponent("vitruvian-tool.json"))
            let bytes = program.flatMap { try? Data(contentsOf: $0) } ?? Data()
            FileManager.default.createFile(atPath: file.path, contents: bytes, attributes: [.posixPermissions: 0o755])
            return folder
        }

        func exists(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
        }

        /// Both steps of adding a tool, with the consent a person would
        /// give on the sheet.
        @discardableResult
        func add(_ folder: URL, on date: Date = Date(timeIntervalSince1970: 1_760_000_000))
            -> Result<ExternalToolStore.Installed, ExternalToolStore.Refusal> {
            store.offer(from: folder).flatMap { store.add(ToolConsent(to: $0, on: date)) }
        }

        /// The app, started again over the same files. Its store has read
        /// nothing yet: `restore` is the caller's to call.
        func relaunched() -> Bench {
            Bench(relaunchOf: self)
        }

        /// The file the store keeps its records in, and what it holds.
        var recordsFile: URL { support.appendingPathComponent("InstalledTools.json") }
        var records: [ToolRecord] {
            if case .records(let records) = ToolRecords.read(at: recordsFile) { return records }
            return []
        }

        func close() {
            guard relaunchOf == nil else { return }
            try? FileManager.default.removeItem(at: root)
        }
    }

    static func refusal<Added>(_ result: Result<Added, ExternalToolStore.Refusal>) -> ExternalToolStore.Refusal? {
        if case .failure(let refusal) = result { return refusal }
        return nil
    }

    static func folders(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let folders = ToolFolders(root: bench.support)
        suite.expect(folders.place(for: id) == .init(files: bench.files, data: bench.data)
                         && folders.place(for: ToolID("portManager")!) == nil,
                     "a tool from outside has two folders under the app's support folder, named by its id; "
                         + "one of the app's own has none")

        let picked = bench.folder()
        try? Data("notes".utf8).write(to: picked.appendingPathComponent("README"))
        guard case .success(let place) = folders.install(id, from: picked) else {
            suite.expect(false, "a tool's folder is copied into the app's own")
            return
        }
        let mode = (try? FileManager.default.attributesOfItem(atPath: bench.data.path))?[.posixPermissions] as? Int
        suite.expect(place == folders.place(for: id) && bench.exists(bench.files.appendingPathComponent("README"))
                         && FileManager.default.isExecutableFile(atPath: bench.files.appendingPathComponent("bin/deploys").path)
                         && bench.exists(picked.appendingPathComponent("README")) && mode == 0o700,
                     "the copy holds every file, the program can still be run, the picked folder is untouched, "
                         + "and the data folder is the person's alone")

        try? Data("kept".utf8).write(to: bench.data.appendingPathComponent("saved"))
        try? FileManager.default.removeItem(at: picked.appendingPathComponent("README"))
        _ = folders.install(id, from: picked)
        suite.expect(!bench.exists(bench.files.appendingPathComponent("README"))
                         && bench.exists(bench.data.appendingPathComponent("saved"))
                         && !bench.exists(bench.support.appendingPathComponent("Tools/.incoming")),
                     "adding it again replaces the copy whole, keeps what the tool saved, and leaves nothing half-made")

        suite.expect(folders.install(id, from: bench.files) == .failure(.insideTheApp)
                         && folders.install(id, from: bench.data) == .failure(.insideTheApp)
                         && bench.exists(bench.files.appendingPathComponent("bin/deploys")),
                     "the app's own copy cannot be added over itself, which would lose it")
        suite.expect(folders.install(id, from: bench.root.appendingPathComponent("missing")) == .failure(.notCopied)
                         && bench.exists(bench.files.appendingPathComponent("bin/deploys")),
                     "a folder that cannot be copied leaves the old copy as it was")
        suite.expect(folders.install(ToolID("portManager")!, from: picked) == .failure(.notAnOutsideTool),
                     "and an id with no dot is given no folder")
    }

    /// What a link can and cannot do to the copy, and that no id names a
    /// folder other than its own.
    static func links(_ suite: TestSuite) {
        suite.expect(["", ".", "..", "../x", "com.acme/x", "com.acme/../x", ".incoming", "com..acme", "/tmp", "com.acme."]
                         .allSatisfy { ToolID($0) == nil },
                     "no id is empty, holds a slash or two dots in a row, or starts with a dot: an id is one folder name")

        let bench = Bench()
        defer { bench.close() }
        let folders = ToolFolders(root: bench.support)
        let elsewhere = bench.root.appendingPathComponent("elsewhere", isDirectory: true)
        let theirs = elsewhere.appendingPathComponent("com.acme.deploys/theirs")
        try? FileManager.default.createDirectory(at: theirs.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
        try? Data("theirs".utf8).write(to: theirs)
        func mode(_ url: URL) -> Int? {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
        }

        let picked = bench.folder()
        try? FileManager.default.createSymbolicLink(at: picked.appendingPathComponent("out"),
                                                    withDestinationURL: elsewhere)
        _ = folders.install(id, from: picked)
        let copied = bench.files.appendingPathComponent("out")
        suite.expect((try? FileManager.default.attributesOfItem(atPath: copied.path))?[.type] as? FileAttributeType
                         == .typeSymbolicLink
                         && (try? FileManager.default.destinationOfSymbolicLink(atPath: copied.path)) == elsewhere.path
                         && bench.exists(theirs),
                     "a link in the picked folder is copied as a link: what it points at is not copied and not touched")

        let tools = bench.support.appendingPathComponent("Tools", isDirectory: true)
        try? FileManager.default.removeItem(at: tools)
        try? FileManager.default.createSymbolicLink(at: tools, withDestinationURL: elsewhere)
        suite.expect(folders.install(id, from: picked) == .failure(.linkedElsewhere) && bench.exists(theirs)
                         && !bench.exists(elsewhere.appendingPathComponent(".incoming")),
                     "a Tools folder that is a link to another place is not copied into, and nothing there is deleted")

        try? FileManager.default.removeItem(at: tools)
        try? FileManager.default.removeItem(at: bench.data)
        try? FileManager.default.createSymbolicLink(at: bench.data,
                                                    withDestinationURL: theirs.deletingLastPathComponent())
        suite.expect(folders.install(id, from: picked) == .failure(.linkedElsewhere) && !bench.exists(bench.files)
                         && mode(theirs.deletingLastPathComponent()) == 0o755,
                     "a data folder that is a link to another place is refused before anything is copied or changed")
    }

    /// The first of the two steps: reading a folder, with nothing done.
    static func offering(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let picked = bench.folder()
        let bytes = (try? Data(contentsOf: picked.appendingPathComponent("vitruvian-tool.json"))) ?? Data()
        guard case .success(let offer) = bench.store.offer(from: picked) else {
            suite.expect(false, "a tool's folder is read into an offer")
            return
        }
        suite.expect(offer.tool.manifest.id == id && offer.tool.version == "1.2.0"
                         && offer.folder == picked.resolvingSymlinksInPath().standardizedFileURL
                         && offer.fingerprint == ToolFingerprint.of(bytes) && offer.fingerprint.count == 64
                         && ToolFingerprint.of(Data("abc".utf8))
                         == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                     "an offer says what the folder holds, where it is, and names its manifest's exact bytes")
        suite.expect(!bench.exists(bench.support) && bench.store.installed.isEmpty && !bench.store.isInstalled(id)
                         && bench.registry.tool(id) == nil && bench.host.manifest(for: id) == nil
                         && bench.started.isEmpty,
                     "making an offer copies nothing, adds nothing and starts nothing: the person has not agreed yet")

        // The folder changes while the person reads the sheet.
        try? ExternalToolManifestTests.file(#"{"version": "6.6.6"}"#)
            .write(to: picked.appendingPathComponent("vitruvian-tool.json"))
        suite.expect(refusal(bench.store.add(ToolConsent(to: offer))) == .changedSinceOffered
                         && !bench.exists(bench.support) && bench.store.installed.isEmpty,
                     "a folder whose manifest changed after it was shown is not added: what is added is what was agreed to")
        try? bytes.write(to: picked.appendingPathComponent("vitruvian-tool.json"))
        if case .success(let installed) = bench.store.add(ToolConsent(to: offer)) {
            suite.expect(installed.tool == offer.tool && bench.store.isInstalled(id) && bench.registry.canRun(copy),
                         "with the person's consent to that offer, the tool is added")
        } else {
            suite.expect(false, "with the person's consent to that offer, the tool is added")
        }
        suite.expect(refusal(bench.store.offer(from: bench.files)) == .files(.insideTheApp),
                     "the app's own copy of a tool is not offered: it cannot be added over itself")

        // The person picks a link to the tool's folder.
        let linked = Bench()
        defer { linked.close() }
        let real = linked.folder()
        let alias = linked.root.appendingPathComponent("alias")
        try? FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        guard case .success(let followed) = linked.store.offer(from: alias),
              case .success = linked.store.add(ToolConsent(to: followed)) else {
            suite.expect(false, "a link to a tool's folder is followed, and the tool added")
            return
        }
        let kind = (try? FileManager.default.attributesOfItem(atPath: linked.files.path))?[.type] as? FileAttributeType
        let followedTo = real.resolvingSymlinksInPath().standardizedFileURL
        try? FileManager.default.removeItem(at: real)
        suite.expect(followed.folder == followedTo && kind == .typeDirectory
                         && linked.exists(linked.files.appendingPathComponent("bin/deploys")),
                     "picking a link to a folder copies the folder, not the link: the copy outlives the folder it came from")
    }

    /// The two things an offer refuses that the manifest cannot know: a
    /// folder too large to copy, and a program macOS has quarantined.
    static func tooBigOrQuarantined(_ suite: TestSuite) {
        var limits = ToolLimits.standard
        // The folder a bench makes holds three things: the manifest, `bin`
        // and the program in it. The manifest is its only bytes.
        let manifest = ExternalToolManifestTests.file()
        limits.folderItems = 4
        limits.folderBytes = manifest.count + 10
        let bench = Bench(limits: limits)
        defer { bench.close() }
        let picked = bench.folder()
        try? Data(count: 10).write(to: picked.appendingPathComponent("fourth"))
        suite.expect(ToolFolders.weight(of: picked, within: .init(bytes: .max, items: .max))
                         == .init(bytes: manifest.count + 10, items: 4)
                         && refusal(bench.store.offer(from: picked)) == nil,
                     "a folder that holds exactly as much as a tool's folder may is offered")
        try? Data(count: 11).write(to: picked.appendingPathComponent("fourth"))
        suite.expect(refusal(bench.store.offer(from: picked)) == .tooBig(bytes: manifest.count + 10, items: 4),
                     "one byte more is refused, with the most a folder may hold")
        try? Data(count: 10).write(to: picked.appendingPathComponent("fourth"))
        try? FileManager.default.createSymbolicLink(at: picked.appendingPathComponent("fifth"),
                                                    withDestinationURL: bench.root)
        suite.expect(refusal(bench.store.offer(from: picked)) == .tooBig(bytes: manifest.count + 10, items: 4)
                         && !bench.exists(bench.support),
                     "one thing more is refused too, a link counted as one thing and not followed; nothing is copied")
        suite.expect(ToolLimits.standard.folderBytes == 256 * 1_048_576 && ToolLimits.standard.folderItems == 10_000,
                     "the app's own limits are 256 MB and 10,000 things")

        let downloaded = Bench()
        defer { downloaded.close() }
        let folder = downloaded.folder()
        let program = folder.appendingPathComponent("bin/deploys")
        let mark = Array("0081;00000000;Safari;".utf8)
        suite.expect(setxattr(program.path, "com.apple.quarantine", mark, mark.count, 0, 0) == 0
                         && ToolFolders.isQuarantined(program)
                         && refusal(downloaded.store.offer(from: folder))
                         == .quarantined(folder.resolvingSymlinksInPath().standardizedFileURL)
                         && !downloaded.exists(downloaded.support),
                     "a program macOS has quarantined is refused before anything is copied, with the folder to clear")
        suite.expect(removexattr(program.path, "com.apple.quarantine", 0) == 0 && !ToolFolders.isQuarantined(program)
                         && refusal(downloaded.store.offer(from: folder)) == nil,
                     "once the person has cleared the quarantine themselves, the folder is offered")
    }

    static func theStoreTellsBeforeTheProgramStarts(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        guard case .success = bench.add(bench.folder()) else { return suite.expect(false, "the tool is added") }
        suite.expect(bench.added.map(\.id) == [id] && bench.added.first?.programStarted == false,
                     "the store tells of the added tool before its program starts, so what it is handed is there for its first run")
        _ = bench.store.remove(id, deletingData: true)
        suite.expect(bench.removed == [id], "and of its removal")
    }

    /// A bench whose store waits, before each add, until the test says
    /// what it waits for is ready (`Parts.beforeAdding`), and what each add
    /// answered, in the order they answered; nil for one that was dropped.
    final class WaitingBench {
        let bench = Bench()
        var waiting: [@MainActor () -> Void] = []
        var answers: [Result<ExternalToolStore.Installed, ExternalToolStore.Refusal>?] = []

        init() {
            bench.beforeAdding = { [unowned self] _, ready in waiting.append(ready) }
        }

        /// The person presses Add Tool on the sheet.
        func agree(_ folder: String = "picked") {
            guard case .success(let offer) = bench.store.offer(from: bench.folder(folder)) else { return }
            bench.store.add(ToolConsent(to: offer)) { [unowned self] in answers.append($0) }
        }

        /// What the store waits for is ready, for every add that waits.
        func ready() {
            let now = waiting
            waiting = []
            for ready in now { ready() }
        }

        func close() { bench.close() }
    }

    static func addingThatWaitsNeverHolds(_ suite: TestSuite) {
        let rig = WaitingBench()
        defer { rig.close() }
        rig.agree()
        suite.expect(rig.waiting.count == 1 && rig.answers.isEmpty && rig.bench.store.isAdding(id)
                         && !rig.bench.store.isInstalled(id) && rig.bench.added.isEmpty && rig.bench.started.isEmpty,
                     "Add Tool returns while the add waits, and nothing is added, handed or started yet")
        rig.ready()
        suite.expect(rig.answers.count == 1 && (try? rig.answers[0]?.get()) != nil && rig.bench.store.isInstalled(id)
                         && !rig.bench.store.isAdding(id) && rig.bench.added.map(\.programStarted) == [false],
                     "once the wait ends the tool is added, once, before its program starts: \(rig.answers)")
    }

    static func removalWhileWaitingDropsTheAdd(_ suite: TestSuite) {
        let rig = WaitingBench()
        defer { rig.close() }
        rig.agree()
        suite.expect(rig.bench.store.remove(id, deletingData: true) == .notAdded && !rig.bench.store.isAdding(id),
                     "removing a tool that is still being added stops the add")
        rig.ready()
        suite.expect(rig.answers.count == 1 && rig.answers[0] == nil,
                     "an add whose wait ends after the tool was removed is dropped, and whoever asked is told so: \(rig.answers)")
        suite.expect(!rig.bench.store.isInstalled(id) && rig.bench.records.isEmpty && rig.bench.added.isEmpty,
                     "nothing is added and nothing handed over")
    }

    static func agreeingTwiceAddsOnce(_ suite: TestSuite) {
        let rig = WaitingBench()
        defer { rig.close() }
        rig.agree("first")
        rig.agree("second")
        rig.ready()
        suite.expect(rig.answers.count == 2 && rig.answers[0] == nil && (try? rig.answers[1]?.get()) != nil,
                     "the later agreement is the one that adds; the earlier is dropped: \(rig.answers)")
        suite.expect(rig.bench.added.count == 1 && rig.bench.records.count == 1,
                     "so the tool is added once and told of once: \(rig.bench.added.count)")
    }

    static func adding(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        guard case .success(let installed) = bench.add(bench.folder()) else {
            suite.expect(false, "the tool of the design's example is added from a folder")
            return
        }
        suite.expect(installed.files == bench.files && installed.data == bench.data
                         && bench.store.installed[id] == installed && bench.store.isInstalled(id)
                         && bench.exists(bench.files.appendingPathComponent("vitruvian-tool.json")),
                     "an added tool is installed, and the store knows where its copy and its data are")
        suite.expect(bench.host.manifest(for: id) == installed.tool.manifest && bench.host.running == [id]
                         && bench.registry.commands(on: .commandBar).map(\.id) == [copy] && bench.registry.canRun(copy)
                         && bench.started.isEmpty,
                     "the host holds it, the registry lists its command as one that can run, and no program has started")

        suite.expect(bench.registry.run(copy) && bench.started.count == 1
                         && bench.started[0].program == bench.files.appendingPathComponent("bin/deploys")
                         && bench.started[0].data == bench.data,
                     "running its command starts the program of the app's copy, in the tool's data folder")
        let hello = JSONValue.object(["protocolVersions": .array([.string("1"), .string("2")]), "language": .string("fr"),
                                      "dataFolder": .string(bench.data.path),
                                      "features": .array([.string("ui.status"), .string("ui.choice"),
                                                          .string("preferences.options"),
                                                          .string("ui.status.activity"),
                                                          .string("ui.open.settings"), .string("ui.chips"),
                                                          .string("ui.sections")])])
        suite.expect(bench.current.sent == [.request(id: .number(1), method: "initialize", params: hello)],
                     "it is greeted with the versions the app speaks, the app's language, its data folder, and "
                         + "what the app has beyond the first release of the version")
        bench.current.greets()
        suite.expect(bench.current.sent.last == .request(id: .number(2), method: "command/run",
                                                         params: .object(["command": .string("copyLatest")])),
                     "and then sent the command")
        bench.current.refuses(2)
        suite.expect(bench.beeps == 1, "a command the tool refuses beeps, as a built-in one does")

        let revision = bench.registry.revision
        bench.current.ends(1)
        suite.expect(bench.stoppedWorking == [id] && !bench.registry.canRun(copy) && bench.registry.revision > revision
                         && bench.store.tool(id)?.standing == .waiting,
                     "when its program dies the store is told once, its command greys out, and lists are told to redraw")
    }

    static func throughTheBroker(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.add(bench.folder())
        bench.registry.run(copy)
        bench.current.greets()
        bench.current.says(#"{"jsonrpc":"2.0","id":1,"method":"notify/hud","params":{"icon":"link","message":"Copied"}}"#)
        suite.expect(bench.said == ["link: Copied"] && bench.current.sent.last == .result(id: .number(1), value: .object([:])),
                     "what an installed tool asks is done by the broker and answered")
        bench.current.says(#"{"jsonrpc":"2.0","id":2,"method":"storage/set","params":{"key":"project","value":"api"}}"#)
        suite.expect(bench.box.values["com.acme.deploys/project"] as? String == "api",
                     "a preference it writes is saved under its id")
        bench.current.says(#"{"jsonrpc":"2.0","id":3,"method":"open/url","params":{"url":"https://example.com"}}"#)
        suite.expect(bench.current.sent.last
                         == .failure(id: .number(3), error: RefusalCode.notInUses.error(service: .open)),
                     "a service its manifest does not list is refused by the broker, with the protocol's code")
        bench.store.remove(id, deletingData: false)
        suite.expect(ExternalToolCalls.error(for: .notInstalled).code == -32002
                         && bench.host.manifest(for: id) == nil,
                     "and a tool that was removed is no longer served")
    }

    static func refusals(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let empty = bench.root.appendingPathComponent("empty", isDirectory: true)
        try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        suite.expect(refusal(bench.add(empty)) == .manifest(.noManifest),
                     "a folder with no manifest is not added")
        let bad = bench.folder("bad", manifest: ExternalToolManifestTests.file(#"{"uses": ["camera"]}"#))
        suite.expect(refusal(bench.add(bad)) == .manifest(.invalid(.unknownService("camera")))
                         && !bench.exists(bench.support) && bench.store.installed.isEmpty
                         && bench.registry.tool(id) == nil,
                     "a manifest that breaks a rule is refused with what is wrong, and nothing is copied")

        let linked = bench.folder("linked")
        let outside = bench.root.appendingPathComponent("elsewhere")
        FileManager.default.createFile(atPath: outside.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        try? FileManager.default.removeItem(at: linked.appendingPathComponent("bin/deploys"))
        try? FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("bin/deploys"),
                                                    withDestinationURL: outside)
        suite.expect(refusal(bench.add(linked)) == .manifest(.programOutsideFolder("bin/deploys"))
                         && !bench.exists(bench.support),
                     "a program that is a link out of the folder is refused before anything is copied")

        let homeless = Bench(supportFolder: false)
        defer { homeless.close() }
        suite.expect(refusal(homeless.add(bench.folder("nowhere"))) == .noSupportFolder
                         && homeless.store.installed.isEmpty,
                     "with no support folder to copy into, nothing is added")

        // Something else in the app answers to the id already.
        let taken = Bench()
        defer { taken.close() }
        if let tool = ExternalToolManifestTests.tool() { try? taken.registry.register(tool.manifest.tool) }
        suite.expect(refusal(taken.add(taken.folder())) == .alreadyInstalled(id) && !taken.exists(taken.support)
                         && taken.store.listed.isEmpty,
                     "a tool whose id something else in the app answers to is not added, and nothing is copied")
    }

    /// What may be deleted for a tool, and what may not.
    static func deleting(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let folders = ToolFolders(root: bench.support)
        let other = ToolID("com.acme.other")!
        for tool in [id, other] {
            _ = folders.install(tool, from: bench.folder("picked-\(tool.rawValue)"))
            if let place = folders.place(for: tool) { try? Data("kept".utf8).write(to: place.data.appendingPathComponent("saved")) }
        }
        let theirs = folders.place(for: other)!
        suite.expect(folders.delete(id, data: false) && !bench.exists(bench.files)
                         && bench.exists(bench.data.appendingPathComponent("saved"))
                         && bench.exists(theirs.files) && bench.exists(theirs.data),
                     "deleting a tool's copy leaves what it saved, and leaves every other tool alone")
        suite.expect(folders.delete(id, data: true) && !bench.exists(bench.data)
                         && bench.exists(theirs.files.appendingPathComponent("bin/deploys"))
                         && bench.exists(theirs.data.appendingPathComponent("saved"))
                         && bench.exists(bench.support.appendingPathComponent("Tools"))
                         && bench.exists(bench.support.appendingPathComponent("ToolData")),
                     "deleting what it saved too takes its data folder and nothing else: the two roots stand")
        suite.expect(folders.delete(id, data: true) && !folders.delete(ToolID("portManager")!, data: true)
                         && bench.exists(theirs.files),
                     "deleting what is not there is done; one of the app's own tools has nothing to delete")

        // A link where the tool's copy should be.
        let elsewhere = bench.root.appendingPathComponent("elsewhere", isDirectory: true)
        try? FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try? Data("theirs".utf8).write(to: elsewhere.appendingPathComponent("precious"))
        try? FileManager.default.createSymbolicLink(at: bench.files, withDestinationURL: elsewhere)
        suite.expect(folders.delete(id, data: false) && !bench.exists(bench.files)
                         && bench.exists(elsewhere.appendingPathComponent("precious")),
                     "a copy that is a link is deleted as a link: what it points at is not touched")

        // A link where `Tools` should be.
        let tools = bench.support.appendingPathComponent("Tools", isDirectory: true)
        let away = bench.root.appendingPathComponent("away", isDirectory: true)
        try? FileManager.default.moveItem(at: tools, to: away)
        try? FileManager.default.createSymbolicLink(at: tools, withDestinationURL: away)
        suite.expect(!folders.delete(other, data: false)
                         && bench.exists(away.appendingPathComponent("com.acme.other/bin/deploys")),
                     "with Tools a link to another place, nothing there is deleted")
    }

    /// More of what a removal may and may not reach.
    static func deletingMore(_ suite: TestSuite) {
        suite.expect(["", ".", "..", "../x", "a/b", "/", "com..acme", ".com.acme", "com.acme.", "com.acme/..", "~", "a b.c"]
                         .allSatisfy { ToolID($0) == nil },
                     "no id is empty, climbs out of its folder, or holds a slash, a space or a tilde")
        let bench = Bench()
        defer { bench.close() }
        let folders = ToolFolders(root: bench.support)
        bench.add(bench.folder())
        suite.expect(!folders.delete(ToolID("Tools")!, data: true) && !folders.delete(ToolID("ToolData")!, data: true)
                         && bench.exists(bench.files) && bench.exists(bench.data),
                     "an id with no dot deletes nothing: neither folder of tools can be named")

        let bytes = Data((0..<4096).map { UInt8($0 % 251) })
        try? bytes.write(to: bench.data.appendingPathComponent("saved"))
        bench.box.values["com.acme.deploys/project"] = "api"
        let keys = bench.box.values.keys.sorted()
        suite.expect(bench.store.remove(id, deletingData: false).removed
                         && (try? Data(contentsOf: bench.data.appendingPathComponent("saved"))) == bytes
                         && (try? FileManager.default.contentsOfDirectory(atPath: bench.data.path)) == ["saved"]
                         && bench.box.values.keys.sorted() == keys
                         && bench.box.values["com.acme.deploys/project"] as? String == "api",
                     "keeping what a tool saved leaves its data folder and its preferences byte for byte")

        // A link where what the tool saved should be.
        let elsewhere = bench.root.appendingPathComponent("elsewhere-data", isDirectory: true)
        try? FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try? Data("theirs".utf8).write(to: elsewhere.appendingPathComponent("precious"))
        try? FileManager.default.removeItem(at: bench.data)
        try? FileManager.default.createSymbolicLink(at: bench.data, withDestinationURL: elsewhere)
        suite.expect(folders.delete(id, data: true)
                         && (try? FileManager.default.attributesOfItem(atPath: bench.data.path)) == nil
                         && bench.exists(elsewhere.appendingPathComponent("precious")),
                     "a data folder that is a link is deleted as a link: what it points at is not touched")

        // A copy that cannot be deleted: the folder of copies is read-only.
        let half = Bench()
        defer { half.close() }
        half.add(half.folder())
        let tools = half.support.appendingPathComponent("Tools")
        try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: tools.path)
        let removed = half.store.remove(id, deletingData: true).removed
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tools.path)
        let next = half.relaunched()
        next.store.restore()
        suite.expect(removed && half.exists(half.files) && half.records.isEmpty && !half.exists(half.data)
                         && next.store.listed.isEmpty && next.registry.tool(id) == nil
                         && next.host.manifest(for: id) == nil && next.runs.isEmpty,
                     "a copy that could not be deleted is forgotten all the same: the next launch starts nothing")
    }

    static func removing(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let picked = bench.folder()
        bench.add(picked)
        try? Data("kept".utf8).write(to: bench.data.appendingPathComponent("saved"))
        bench.box.values["com.acme.deploys/project"] = "api"
        bench.box.values["com.acme.deploys2/project"] = "theirs"
        bench.box.values["project"] = "the app's"
        bench.registry.run(copy)
        bench.current.greets()
        suite.expect(bench.store.remove(id, deletingData: false).removed
                         && bench.current.sent.last == .notice(method: "shutdown", params: nil) && bench.current.inputClosed
                         && !bench.store.isInstalled(id) && bench.registry.tool(id) == nil
                         && bench.host.manifest(for: id) == nil && bench.store.tool(id) == nil,
                     "removing a tool stops its program and takes it out of the host and the registry")
        suite.expect(bench.store.listed.isEmpty && bench.records.isEmpty && !bench.exists(bench.files)
                         && bench.exists(bench.support.appendingPathComponent("Tools")),
                     "it is forgotten, and the app's copy of its files is deleted")
        suite.expect(bench.exists(bench.data.appendingPathComponent("saved"))
                         && bench.box.values["com.acme.deploys/project"] as? String == "api"
                         && bench.exists(picked.appendingPathComponent("bin/deploys")),
                     "what it saved is kept when the person says so, and the folder it came from is not touched")
        suite.expect(!bench.store.remove(id, deletingData: true).removed
                         && bench.exists(bench.data.appendingPathComponent("saved")),
                     "removing a tool nobody added does nothing, and deletes nothing")
        bench.current.ends(0)

        if case .success = bench.add(picked) {
            suite.expect(bench.registry.canRun(copy) && bench.exists(bench.data.appendingPathComponent("saved")),
                         "it can be added again, and finds what it saved")
        } else {
            suite.expect(false, "it can be added again, and finds what it saved")
        }
        suite.expect(bench.store.remove(id, deletingData: true).removed && !bench.exists(bench.files)
                         && !bench.exists(bench.data)
                         && bench.box.values["com.acme.deploys/project"] == nil
                         && bench.box.values["com.acme.deploys2/project"] as? String == "theirs"
                         && bench.box.values["project"] as? String == "the app's"
                         && bench.exists(bench.support.appendingPathComponent("ToolData"))
                         && bench.exists(picked.appendingPathComponent("bin/deploys")),
                     "removing it with what it saved deletes its data folder and its own preferences, and no other")
        let next = bench.relaunched()
        next.store.restore()
        suite.expect(next.store.listed.isEmpty && next.registry.tool(id) == nil,
                     "and the next launch does not bring it back")

        // A tool that is held back can still be removed.
        let held = Bench()
        defer { held.close() }
        held.add(held.folder())
        try? Data("{}".utf8).write(to: held.files.appendingPathComponent("vitruvian-tool.json"))
        let after = held.relaunched()
        after.store.restore()
        suite.expect(after.store.listed.map(\.isHeld) == [true] && after.store.remove(id, deletingData: true).removed
                         && after.store.listed.isEmpty && !after.exists(after.files) && !after.exists(after.data),
                     "a tool that is held back is removed like any other")

        let domain = "com.vitruviansoftware.vitruvian.tests.tool-store"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("api", forKey: "com.acme.deploys/project")
        defaults.set(3, forKey: "com.acme.deploys/count")
        defaults.set("theirs", forKey: "com.acme.deploys2/project")
        defaults.set("the app's", forKey: "com.acme.deploys")
        ExternalToolStore.forgetPreferences(of: id, in: defaults)
        suite.expect(defaults.object(forKey: "com.acme.deploys/project") == nil
                         && defaults.object(forKey: "com.acme.deploys/count") == nil
                         && defaults.string(forKey: "com.acme.deploys2/project") == "theirs"
                         && defaults.string(forKey: "com.acme.deploys") == "the app's",
                     "forgetting a tool's preferences deletes the keys under its id and a slash, and no other key")

        let early = Bench()
        defer { early.close() }
        early.add(early.folder(manifest: ExternalToolManifestTests.file(#"{"activation": ["onLaunch"]}"#)))
        suite.expect(early.started.count == 1 && early.store.tool(id)?.standing == .starting,
                     "a tool that starts with the app is started as soon as it is added")
    }

    /// Nothing of a tool is deleted while its program runs: each step the
    /// app takes to end it, with a tool that is no program.
    static func goneBeforeDeleted(_ suite: TestSuite) {
        func running(_ prepare: (FakeTool) -> Void) -> Bench {
            let bench = Bench()
            bench.add(bench.folder())
            try? Data("kept".utf8).write(to: bench.data.appendingPathComponent("saved"))
            bench.box.values["com.acme.deploys/project"] = "api"
            bench.registry.run(copy)
            bench.current.greets()
            prepare(bench.current)
            return bench
        }
        func isGone(_ bench: Bench) -> Bool {
            !bench.exists(bench.files) && !bench.exists(bench.data) && bench.box.values["com.acme.deploys/project"] == nil
                && bench.records.isEmpty
        }

        let polite = running { $0.exitsOnClose = 0 }
        defer { polite.close() }
        suite.expect(polite.store.remove(id, deletingData: true).removed && polite.waits.isEmpty
                         && polite.current.signals.isEmpty && isGone(polite),
                     "a tool that leaves when it is told goodbye is removed with no wait")

        let slow = running { $0.exitsOnTerminate = 15 }
        defer { slow.close() }
        suite.expect(slow.store.remove(id, deletingData: true).removed && slow.waits == [0.5]
                         && slow.current.signals == ["terminate"] && isGone(slow),
                     "one that does not leave is waited for half a second, then asked to end")

        let deaf = running { $0.exitsOnKill = 9 }
        defer { deaf.close() }
        suite.expect(deaf.store.remove(id, deletingData: true).removed && deaf.waits == [0.5, 0.25]
                         && deaf.current.signals == ["terminate", "kill"] && isGone(deaf),
                     "one that ignores that is killed a quarter of a second later, and deleted once it is dead")

        let undead = running { _ in }
        defer { undead.close() }
        suite.expect(undead.store.remove(id, deletingData: true).removed && undead.waits == [0.5, 0.25, 0.25]
                         && undead.current.signals == ["terminate", "kill"]
                         && undead.store.listed.isEmpty && undead.records.isEmpty && !undead.exists(undead.files)
                         && (try? Data(contentsOf: undead.data.appendingPathComponent("saved"))) == Data("kept".utf8)
                         && undead.box.values["com.acme.deploys/project"] as? String == "api",
                     "a program still there after the kill keeps what it saved, whatever was asked: "
                         + "only its copy and its record go")

        let idle = Bench()
        defer { idle.close() }
        idle.add(idle.folder())
        suite.expect(idle.store.remove(id, deletingData: true).removed && idle.waits.isEmpty && idle.runs.isEmpty
                         && !idle.exists(idle.data),
                     "a tool whose program is not running is removed with no wait")
    }

    /// What removing a tool says it did, so that the person can be told
    /// when what a tool saved was kept against what they asked.
    static func saysWhatWasKept(_ suite: TestSuite) {
        func outcome(deletingData: Bool, _ prepare: (FakeTool) -> Void)
            -> (said: ExternalToolStore.Removal, saved: Bool, preference: Bool, kept: String) {
            let bench = Bench()
            defer { bench.close() }
            bench.add(bench.folder())
            try? Data("kept".utf8).write(to: bench.data.appendingPathComponent("saved"))
            bench.box.values["com.acme.deploys/project"] = "api"
            bench.registry.run(copy)
            bench.current.greets()
            prepare(bench.current)
            let said = bench.store.remove(id, deletingData: deletingData)
            return (said, bench.exists(bench.data.appendingPathComponent("saved")),
                    bench.box.values["com.acme.deploys/project"] != nil, bench.data.standardizedFileURL.path)
        }
        let leaves = outcome(deletingData: true) { $0.exitsOnClose = 0 }
        suite.expect(leaves.said == .deleted && leaves.said.removed && !leaves.saved && !leaves.preference,
                     "a tool whose program leaves has what it saved deleted when that was asked, and removing it says so")
        let stays = outcome(deletingData: true) { _ in }
        var folder: String?
        if case .keptStillRunning(let data) = stays.said { folder = data?.standardizedFileURL.path }
        suite.expect(stays.said != .deleted && stays.said.removed && stays.saved && stays.preference
                         && folder == stays.kept && folder?.hasSuffix("/support/ToolData/com.acme.deploys") == true,
                     "a tool whose program never leaves keeps its data folder and its settings, and removing it says so: "
                         + "kept, though deleting was asked, and in which folder")
        let asked = outcome(deletingData: false) { _ in }
        suite.expect(asked.said == .keptAsAsked && asked.said.removed && asked.saved && asked.preference,
                     "what a tool saved is kept as asked whether or not its program leaves, and that is no news")
        let nobody = Bench()
        defer { nobody.close() }
        suite.expect(nobody.store.remove(id, deletingData: true) == .notAdded
                         && !nobody.store.remove(id, deletingData: true).removed,
                     "removing a tool nobody added says nothing was removed")
    }

    /// A folder that could not be deleted, with the tool's program gone: a
    /// read-only folder under the temporary folder stands in for it. The
    /// outcome says which folder is left, and the next launch starts
    /// nothing of a tool that is half deleted.
    static func saysWhatCouldNotBeDeleted(_ suite: TestSuite) {
        let manager = FileManager.default
        func lock(_ folder: URL) { try? manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path) }
        func unlock(_ folder: URL) { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        // A folder that may not be written in is deleted all the same. One
        // macOS holds as it is, as Finder's Locked does, is not.
        func hold(_ folder: URL) { _ = chflags(folder.path, UInt32(UF_IMMUTABLE)) }
        func release(_ folder: URL) { _ = chflags(folder.path, 0) }
        func added() -> Bench {
            let bench = Bench()
            bench.add(bench.folder())
            try? Data("kept".utf8).write(to: bench.data.appendingPathComponent("saved"))
            bench.box.values["com.acme.deploys/project"] = "api"
            return bench
        }
        func paths(_ removal: ExternalToolStore.Removal) -> [String]? {
            guard case .notDeleted(let folders) = removal else { return nil }
            return folders.map(\.standardizedFileURL.path)
        }

        // What the tool saved cannot be deleted; its copy can.
        let data = added()
        defer {
            release(data.data)
            data.close()
        }
        hold(data.data)
        let said = data.store.remove(id, deletingData: true)
        suite.expect(said != .deleted && said.removed && paths(said) == [data.data.standardizedFileURL.path]
                         && paths(said)?.first?.hasSuffix("/support/ToolData/com.acme.deploys") == true,
                     "a tool whose data folder could not be deleted is removed, and removing it says so, and which folder is left")
        suite.expect(data.store.listed.isEmpty && data.records.isEmpty && !data.exists(data.files)
                         && data.registry.tool(id) == nil && data.host.manifest(for: id) == nil
                         && (try? Data(contentsOf: data.data.appendingPathComponent("saved"))) == Data("kept".utf8)
                         && data.box.values["com.acme.deploys/project"] as? String == "api",
                     "its record and its copy are gone; the tool's settings stay as long as the folder of what it saved does")
        let after = data.relaunched()
        after.store.restore()
        suite.expect(after.store.listed.isEmpty && after.registry.tool(id) == nil && after.host.manifest(for: id) == nil
                         && after.started.isEmpty && !after.store.isInstalled(id),
                     "the next launch has no record of a tool that is half deleted, and starts nothing of it")
        release(data.data)
        if case .success = data.add(data.folder("again")) {
            suite.expect(data.exists(data.data.appendingPathComponent("saved"))
                             && data.box.values["com.acme.deploys/project"] as? String == "api"
                             && data.store.remove(id, deletingData: true) == .deleted && !data.exists(data.data)
                             && data.box.values["com.acme.deploys/project"] == nil,
                         "added again it finds both, and removed again with the folder writable, both go")
        } else {
            suite.expect(false, "added again it finds both, and removed again with the folder writable, both go")
        }

        // The app's copy cannot be deleted: its folder may not be changed.
        let copyStuck = added()
        let tools = copyStuck.support.appendingPathComponent("Tools", isDirectory: true)
        defer {
            unlock(tools)
            copyStuck.close()
        }
        lock(tools)
        let kept = copyStuck.store.remove(id, deletingData: false)
        suite.expect(kept != .keptAsAsked && kept.removed && paths(kept) == [copyStuck.files.standardizedFileURL.path]
                         && copyStuck.records.isEmpty && copyStuck.exists(copyStuck.data.appendingPathComponent("saved"))
                         && copyStuck.box.values["com.acme.deploys/project"] as? String == "api",
                     "a copy that could not be deleted is said too, also when what the tool saved was to be kept")
        let relaunched = copyStuck.relaunched()
        relaunched.store.restore()
        suite.expect(copyStuck.exists(copyStuck.files) && relaunched.store.listed.isEmpty
                         && relaunched.registry.tool(id) == nil && relaunched.started.isEmpty,
                     "a copy left on disk with no record is not a tool at the next launch: it is never listed or started")

        // Neither can be deleted.
        let both = added()
        let bothTools = both.support.appendingPathComponent("Tools", isDirectory: true)
        defer {
            unlock(bothTools)
            release(both.data)
            both.close()
        }
        lock(bothTools)
        hold(both.data)
        suite.expect(paths(both.store.remove(id, deletingData: true))
                         == [both.files.standardizedFileURL.path, both.data.standardizedFileURL.path],
                     "when neither folder could be deleted both are named, the app's copy first")

        // The program would not stop: that is what is said, as before.
        let running = added()
        defer { running.close() }
        running.registry.run(copy)
        running.current.greets()
        var folder: String?
        if case .keptStillRunning(let left) = running.store.remove(id, deletingData: true) {
            folder = left?.standardizedFileURL.path
        }
        suite.expect(folder == running.data.standardizedFileURL.path
                         && running.box.values["com.acme.deploys/project"] as? String == "api",
                     "a tool whose program would not stop is still said to have kept what it saved, with its settings")
    }

    /// Every `language/changed` the app has sent a run of a tool, as the
    /// tag each carried.
    static func languages(_ tool: FakeTool) -> [String] {
        tool.sent.compactMap { message in
            guard case .notice(let method, let params) = message, method == "language/changed" else { return nil }
            return params?["language"]?.stringValue ?? "?"
        }
    }

    /// The person changes the app's language: each tool that is running
    /// is told once, with the protocol's own params, and no other tool is
    /// told or started.
    static func languageChanges(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.add(bench.folder())
        let other = ToolID("com.acme.other")!
        bench.add(bench.folder("other", manifest: ExternalToolManifestTests.file(#"{"id": "com.acme.other"}"#)))
        suite.expect(bench.languageWatcher != nil, "the store asks to be told when the app's language changes")

        // Nothing runs yet.
        bench.language = "de"
        bench.languageWatcher?("de")
        suite.expect(bench.runs.isEmpty && bench.started.isEmpty
                         && bench.store.listed.allSatisfy { $0.standing == .resting },
                     "a change of language starts no tool: one that is not running is told nothing")

        // Started after the change: it is greeted in the new language.
        bench.registry.run(copy)
        let run = bench.current
        var greeted: String?
        if case .request(_, "initialize", let params)? = run.sent.first { greeted = params?["language"]?.stringValue }
        suite.expect(greeted == "de" && run.sent.count == 1,
                     "a tool started after the language changed is greeted in the new language")

        // Changed while it has not answered initialize yet.
        bench.language = "it"
        bench.languageWatcher?("it")
        suite.expect(run.sent.count == 1 && languages(run).isEmpty,
                     "a tool that has not answered initialize yet is told nothing of the language: "
                         + "until then neither side says anything else")
        run.greets()
        suite.expect(languages(run) == ["it"],
                     "once it has answered, a tool greeted in a language that changed meanwhile is told the new one, once")

        // Running: once for each change.
        bench.language = "de"
        bench.languageWatcher?("de")
        bench.language = "fr"
        bench.languageWatcher?("fr")
        let whole = run.sent.last.flatMap { try? JSONValue(encoding: $0) }
        let example = ExternalToolSettingsTests.example(of: "language/changed")
        suite.expect(languages(run) == ["it", "de", "fr"] && example != nil && whole == example
                         && whole == .object(["jsonrpc": .string("2.0"), "method": .string("language/changed"),
                                              "params": .object(["language": .string("fr")])]),
                     "a running tool is sent language/changed once for each change, and what it is sent is the "
                         + "protocol's own example of the message: a notice with no id, whose params hold the tag")
        bench.languageWatcher?("fr")
        bench.store.languageChanged("fr")
        suite.expect(languages(run) == ["it", "de", "fr"] && !run.inputClosed
                         && bench.store.listed.first?.standing == .running && bench.runs.count == 1,
                     "the language it already has is not sent again, and the tool runs on: it is not restarted to hear it")

        // Two tools running: each is told, once.
        bench.registry.run(CommandID(tool: other, name: "copyLatest")!)
        let second = bench.current
        second.greets()
        bench.language = "ja"
        bench.languageWatcher?("ja")
        suite.expect(bench.runs.count == 2 && languages(second) == ["ja"] && languages(run) == ["it", "de", "fr", "ja"],
                     "every tool that is running is told, each once")

        // Crashed and waiting, switched off, and being stopped: nobody to tell.
        run.ends(1)
        let sent = run.sent.count
        bench.store.setOn(other, false)
        let goodbye = second.sent.count
        bench.language = "ko"
        bench.languageWatcher?("ko")
        suite.expect(run.sent.count == sent && second.sent.count == goodbye && bench.runs.count == 2
                         && bench.store.listed.first?.standing == .waiting
                         && second.sent.last == .notice(method: "shutdown", params: nil),
                     "a tool that stopped, and one that is switched off and being told goodbye, are told nothing "
                         + "and are not started")

        // What the app hands the store: each change, and only a change.
        final class Setting: ObservableObject {
            @Published var language: AppLanguage = .enUS
        }
        let setting = Setting()
        var heard: [String] = []
        let watching = ExternalToolStore.watch(setting.$language) { heard.append($0) }
        setting.language = .enUS
        setting.language = .de
        setting.language = .de
        setting.language = .ptBR
        ToolRuntimeSupport.wait { heard.count >= 2 }
        suite.expect(heard == ["de", "pt-BR"],
                     "the store hears each language the app changes to, as its tag: not the one it starts with, "
                         + "and not the same one set again")
        watching.cancel()

        // Held back: never started, never told.
        let held = Bench()
        defer { held.close() }
        held.add(held.folder())
        try? Data("{}".utf8).write(to: held.files.appendingPathComponent("vitruvian-tool.json"))
        let after = held.relaunched()
        after.store.restore()
        after.languageWatcher?("de")
        suite.expect(after.store.listed.map(\.isHeld) == [true] && after.runs.isEmpty && after.started.isEmpty,
                     "a tool that is held back is told nothing and is not started")
    }

    /// The shortcut the person gave a tool's command: gone with a tool
    /// they remove, kept for one they switch off or update.
    static func shortcutsOfARemovedTool(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let other = CommandID("com.acme.other/open")!
        func bench() -> (Bench, URL) {
            let bench = Bench()
            let picked = bench.folder()
            bench.add(picked)
            try? bench.registry.register(ToolDescriptor(id: other.tool, name: "Other", symbol: "star", commands: [
                CommandDescriptor(id: other, title: "Open", symbol: "star", surfaces: [.shortcut])!,
            ])!)
            try? bench.registry.setHandler(.init(title: { _ in "Open" }, run: {}), for: other)
            bench.keys.registrar.assign(optionB, to: copy)
            bench.keys.registrar.assign(optionN, to: other)
            return (bench, picked)
        }
        func key(_ bench: Bench, _ shortcut: GlobalShortcut) -> Bool {
            bench.keys.live.contains { $0.registered?.shortcut == shortcut }
        }

        for deletingData in [false, true] {
            let (removed, _) = bench()
            defer { removed.close() }
            suite.expect(key(removed, optionB) && removed.keys.registrar.assign(optionB, to: other) == .occupied(copy.rawValue),
                         "the command of a tool that is added holds the keys the person gave it")
            removed.keys.takeOvers = []
            removed.store.remove(id, deletingData: deletingData)
            suite.expect(removed.keys.saved == [other.rawValue: optionN] && !key(removed, optionB) && key(removed, optionN)
                             && removed.keys.takeOvers == ["\(ToolCommandShortcuts.takeOverKey(for: copy))=false"],
                         "removing a tool clears the shortcut of each of its commands, whether or not what it saved "
                             + "is kept, and no other command's")
            suite.expect(removed.keys.registrar.assign(optionB, to: other) == nil && key(removed, optionB),
                         "and the keys can be given to another command")
        }

        let (switched, _) = bench()
        defer { switched.close() }
        switched.store.setOn(id, false)
        suite.expect(switched.keys.saved[copy.rawValue] == optionB && !key(switched, optionB)
                         && switched.keys.registrar.heldShortcuts == [other.rawValue: optionN],
                     "a tool that is switched off keeps its shortcut saved; meanwhile it is no key and holds no combination")
        switched.store.setOn(id, true)
        suite.expect(switched.keys.saved[copy.rawValue] == optionB && key(switched, optionB)
                         && switched.keys.registrar.assign(optionB, to: other) == .occupied(copy.rawValue),
                     "and switched on again it has its key back")

        let (updated, picked) = bench()
        defer { updated.close() }
        try? ExternalToolManifestTests.file(#"{"version": "1.3.0"}"#).write(to: picked.appendingPathComponent("vitruvian-tool.json"))
        updated.add(picked)
        suite.expect(updated.store.installed[id]?.tool.version == "1.3.0" && updated.keys.saved[copy.rawValue] == optionB
                         && key(updated, optionB),
                     "a tool that is updated keeps its shortcut, and its key")
        suite.expect(updated.store.remove(ToolID("com.acme.nobody")!, deletingData: true) == .notAdded
                         && updated.keys.saved[copy.rawValue] == optionB,
                     "removing a tool nobody added clears nothing")
    }

    static func installedOrNot(_ suite: TestSuite) {
        var asked: [ToolID] = []
        let live = CapabilityBroker.Environment.reading(accessibility: { true }, screenRecording: { true },
                                                        outsideToolIsInstalled: {
                                                            asked.append($0)
                                                            return $0 == id
                                                        })
        suite.expect(live.isInstalled(id) && !live.isInstalled(ToolID("com.acme.other")!)
                         && asked == [id, ToolID("com.acme.other")!],
                     "whether a tool from outside is installed is the tool store's answer")
        suite.expect(!live.isInstalled(ToolID("nonsense")!) && asked.count == 2,
                     "an id with no dot that names no feature of the app is not installed, and the store is not asked")
        let unasked = CapabilityBroker.Environment.reading(accessibility: { true }, screenRecording: { true })
        suite.expect(!unasked.isInstalled(id), "with no store to ask, no tool from outside is installed")
    }

    /// What the store writes down, and what the next launch does with it.
    static func remembering(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        suite.expect(!bench.exists(bench.recordsFile) && bench.store.listed.isEmpty,
                     "with nothing added there is no file of records, and nothing is listed")
        bench.store.restore()
        suite.expect(!bench.exists(bench.support), "a launch with nothing added reads one file that is not there, and makes nothing")

        let picked = bench.folder()
        let bytes = (try? Data(contentsOf: picked.appendingPathComponent("vitruvian-tool.json"))) ?? Data()
        _ = bench.store.offer(from: picked)
        suite.expect(!bench.exists(bench.recordsFile), "an offer writes nothing down")
        let agreedOn = Date(timeIntervalSince1970: 1_760_000_000)
        bench.add(picked, on: agreedOn)
        let agreement = ToolAgreement(date: agreedOn, name: "Deploys", version: "1.2.0", publisher: "Acme",
                                      fingerprint: ToolFingerprint.of(bytes),
                                      source: picked.resolvingSymlinksInPath().standardizedFileURL.path)
        let mode = (try? FileManager.default.attributesOfItem(atPath: bench.recordsFile.path))?[.posixPermissions] as? Int
        let written = (try? String(contentsOf: bench.recordsFile, encoding: .utf8)) ?? ""
        suite.expect(bench.records == [ToolRecord(id: "com.acme.deploys", isOn: true, agreement: agreement)]
                         && mode == 0o600 && written.contains(#""version" : 1"#)
                         && written.contains(#""date" : "2025-10-09T08:53:20Z""#),
                     "adding a tool writes down, for the person alone, that it is on and what was agreed: "
                         + "when, the name, version and publisher shown, the manifest's bytes and the folder")
        suite.expect(bench.store.listed.map(\.id) == [id] && bench.store.listed.first?.record.agreement == agreement
                         && bench.store.listed.first?.isHeld == false
                         && bench.store.listed.first?.standing == .resting
                         && bench.store.listed.first?.tool?.publisher == "Acme",
                     "and Settings is given the tool, what was agreed, and how its program stands")

        // The next launch.
        let next = bench.relaunched()
        suite.expect(!next.store.isInstalled(id) && next.registry.tool(id) == nil && next.store.listed.isEmpty,
                     "a store that has not read its file yet holds nothing")
        next.store.restore()
        suite.expect(next.store.isInstalled(id) && next.registry.canRun(copy) && next.host.running == [id]
                         && next.store.listed.first?.record.agreement == agreement && next.started.isEmpty,
                     "at the next launch the tool is back, with what was agreed, and no program has started")
        suite.expect(next.registry.run(copy) && next.started.count == 1
                         && next.started[0].program == bench.files.appendingPathComponent("bin/deploys"),
                     "and its command starts the program of the app's copy, as before")
        next.store.restore()
        suite.expect(next.store.listed.count == 1 && next.started.count == 1, "restoring twice changes nothing")

        let early = Bench()
        defer { early.close() }
        early.add(early.folder(manifest: ExternalToolManifestTests.file(#"{"activation": ["onLaunch"]}"#)))
        let again = early.relaunched()
        again.store.restore()
        suite.expect(again.started.count == 1 && again.store.tool(id)?.standing == .starting,
                     "a tool that starts with the app is started when the launch brings it back")
    }

    /// The tool's switch in Settings.
    static func switching(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.add(bench.folder())
        bench.registry.run(copy)
        bench.current.greets()
        let revision = bench.registry.revision
        bench.store.setOn(id, false)
        suite.expect(bench.current.sent.last == .notice(method: "shutdown", params: nil) && bench.current.inputClosed
                         && !bench.store.isInstalled(id) && bench.registry.tool(id) == nil
                         && bench.registry.commands(on: .commandBar).isEmpty && bench.host.manifest(for: id) == nil
                         && bench.registry.revision > revision,
                     "switching a tool off stops its program at once and takes its commands out of every list")
        suite.expect(bench.store.listed.first?.record.isOn == false && bench.store.listed.first?.standing == nil
                         && bench.store.listed.first?.tool?.manifest.id == id && bench.records.first?.isOn == false
                         && bench.exists(bench.files) && bench.exists(bench.data),
                     "it is still listed, by its own name, and written down as off; its files are not touched")
        bench.current.ends(0)

        let next = bench.relaunched()
        next.store.restore()
        suite.expect(!next.store.isInstalled(id) && next.registry.tool(id) == nil
                         && next.store.listed.first?.record.isOn == false && next.store.listed.first?.isHeld == false,
                     "a tool that is switched off stays off at the next launch")
        next.store.setOn(id, true)
        suite.expect(next.store.isInstalled(id) && next.registry.canRun(copy) && next.records.first?.isOn == true
                         && next.store.listed.first?.standing == .resting,
                     "switching it on brings its commands back, with no question asked: the person agreed already")
        next.store.setOn(ToolID("com.acme.other")!, true)
        suite.expect(next.store.listed.count == 1 && next.records.count == 1,
                     "a switch for a tool nobody added changes nothing")
    }

    /// Choosing a tool's folder again.
    static func updating(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let picked = bench.folder()
        bench.add(picked)
        try? Data("kept".utf8).write(to: bench.data.appendingPathComponent("saved"))
        bench.registry.run(copy)
        bench.current.greets()

        guard case .success(let same) = bench.store.offer(from: picked) else {
            suite.expect(false, "the folder of a tool that is added already is offered again")
            return
        }
        suite.expect(same.replaces == bench.records.first?.agreement && same.replaces?.version == "1.2.0"
                         && !same.manifestChanged && bench.store.isInstalled(id),
                     "an offer for a tool that is added says what was agreed before; with the same manifest, "
                         + "byte for byte, it says nothing changed; and the tool goes on running meanwhile")

        try? ExternalToolManifestTests.file(#"{"version": "1.3.0", "uses": ["notify", "open"]}"#)
            .write(to: picked.appendingPathComponent("vitruvian-tool.json"))
        try? Data("new".utf8).write(to: picked.appendingPathComponent("notes"))
        guard case .success(let newer) = bench.store.offer(from: picked) else {
            suite.expect(false, "a newer version of an added tool is offered")
            return
        }
        suite.expect(newer.manifestChanged && newer.replaces?.version == "1.2.0" && newer.tool.version == "1.3.0"
                         && bench.store.installed[id]?.tool.version == "1.2.0"
                         && !bench.exists(bench.files.appendingPathComponent("notes")),
                     "a manifest with other bytes counts as changed, and until the person agrees the old tool stands")

        let old = bench.current
        let later = Date(timeIntervalSince1970: 1_770_000_000)
        guard case .success = bench.store.add(ToolConsent(to: newer, on: later)) else {
            suite.expect(false, "with consent to the newer offer, the tool is updated")
            return
        }
        suite.expect(old.sent.last == .notice(method: "shutdown", params: nil)
                         && old.signals == ["terminate", "kill"] && bench.waits == [0.5, 0.25, 0.25]
                         && bench.store.installed[id]?.tool.version == "1.3.0"
                         && bench.exists(bench.files.appendingPathComponent("notes"))
                         && bench.exists(bench.data.appendingPathComponent("saved")),
                     "updating stops the old program, replaces the app's copy, and keeps what the tool saved")
        suite.expect(bench.records.count == 1 && bench.records.first?.agreement.version == "1.3.0"
                         && bench.records.first?.agreement.date == later
                         && bench.records.first?.agreement.fingerprint == newer.fingerprint
                         && bench.store.listed.count == 1 && bench.registry.canRun(copy),
                     "what was agreed is now the newer manifest, and the tool is listed once")
        old.ends(0)
        suite.expect(bench.registry.run(copy) && bench.runs.count == 2,
                     "and the next command starts the new program")

        // An update the person is shown and that then changes.
        guard case .success(let third) = bench.store.offer(from: picked) else { return }
        try? ExternalToolManifestTests.file(#"{"version": "9.9.9"}"#)
            .write(to: picked.appendingPathComponent("vitruvian-tool.json"))
        suite.expect(refusal(bench.store.add(ToolConsent(to: third))) == .changedSinceOffered
                         && bench.store.installed[id]?.tool.version == "1.3.0" && bench.registry.canRun(copy)
                         && bench.records.first?.agreement.version == "1.3.0",
                     "an update refused before anything is copied leaves the tool as it was, still running")

        // Updated while it is switched off.
        bench.store.setOn(id, false)
        try? ExternalToolManifestTests.file(#"{"version": "1.4.0"}"#)
            .write(to: picked.appendingPathComponent("vitruvian-tool.json"))
        bench.add(picked)
        suite.expect(!bench.store.isInstalled(id) && bench.registry.tool(id) == nil
                         && bench.records.first?.agreement.version == "1.4.0" && bench.records.first?.isOn == false
                         && bench.store.listed.first?.tool?.version == "1.4.0",
                     "a tool updated while it is switched off stays off")
    }

    /// A copy that is not what the person agreed to.
    static func heldBack(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let picked = bench.folder()
        bench.add(picked)
        // The tool, or anything else, rewrites the manifest of the app's copy.
        try? ExternalToolManifestTests.file(#"{"uses": ["notify", "keystrokes"]}"#)
            .write(to: bench.files.appendingPathComponent("vitruvian-tool.json"))
        let next = bench.relaunched()
        next.store.restore()
        suite.expect(!next.store.isInstalled(id) && next.registry.tool(id) == nil && next.host.manifest(for: id) == nil
                         && next.store.listed.map(\.isHeld) == [true] && next.store.listed.first?.tool == nil
                         && next.store.listed.first?.record.agreement.name == "Deploys" && next.started.isEmpty,
                     "a copy whose manifest is not, byte for byte, the one agreed to is held back at launch: "
                         + "listed by the name agreed to, and never started")
        next.store.setOn(id, false)
        next.store.setOn(id, true)
        suite.expect(!next.store.isInstalled(id) && next.store.listed.first?.isHeld == true
                         && next.exists(next.files) && next.exists(next.data),
                     "its switch does not bring it back, and nothing of it is deleted")
        next.add(picked)
        suite.expect(next.store.isInstalled(id) && next.store.listed.map(\.isHeld) == [false] && next.registry.canRun(copy),
                     "choosing its folder again, and agreeing again, does")

        let gone = Bench()
        defer { gone.close() }
        gone.add(gone.folder())
        try? FileManager.default.removeItem(at: gone.files)
        let after = gone.relaunched()
        after.store.restore()
        suite.expect(after.store.listed.map(\.isHeld) == [true] && !after.store.isInstalled(id)
                         && after.records.count == 1,
                     "a tool whose copy has gone is held back too, and still remembered")

        let moved = Bench()
        defer { moved.close() }
        moved.add(moved.folder())
        let elsewhere = moved.root.appendingPathComponent("elsewhere", isDirectory: true)
        try? FileManager.default.moveItem(at: moved.files, to: elsewhere)
        try? FileManager.default.createSymbolicLink(at: moved.files, withDestinationURL: elsewhere)
        let linked = moved.relaunched()
        linked.store.restore()
        suite.expect(linked.store.listed.map(\.isHeld) == [true] && !linked.store.isInstalled(id),
                     "and so is one whose copy has become a link to another place: the app runs nothing from there")
    }

    /// A file of records the app cannot read.
    static func unreadableRecords(_ suite: TestSuite) {
        for (what, text) in [("damaged", "{ not json"),
                             ("from a later version", #"{"version": 2, "tools": []}"#),
                             ("naming one of the app's own tools",
                              #"{"version": 1, "tools": [{"id": "portManager", "isOn": true, "agreement": "#
                                  + #"{"date": "2025-10-09T08:53:20Z", "name": "x", "version": "1", "publisher": "x", "#
                                  + #""fingerprint": "x", "source": "/x"}}]}"#)] {
            let bench = Bench()
            defer { bench.close() }
            bench.add(bench.folder())
            try? Data("kept".utf8).write(to: bench.data.appendingPathComponent("saved"))
            try? Data(text.utf8).write(to: bench.recordsFile)
            suite.expect(ToolRecords.read(at: bench.recordsFile) == .unreadable,
                         "a file of records that is \(what) is not read")

            let next = bench.relaunched()
            next.store.restore()
            suite.expect(next.store.listed.isEmpty && !next.store.isInstalled(id) && next.registry.tool(id) == nil
                             && next.started.isEmpty,
                         "with a file of records that is \(what), no tool from outside is loaded")
            suite.expect((try? String(contentsOf: next.recordsFile, encoding: .utf8)) == text
                             && next.exists(next.files.appendingPathComponent("bin/deploys"))
                             && next.exists(next.data.appendingPathComponent("saved")),
                         "and nothing is deleted: the file, the tool's copy and what it saved are as they were (\(what))")

            next.add(next.folder("again"))
            let aside = next.support.appendingPathComponent("InstalledTools.unreadable.json")
            suite.expect((try? String(contentsOf: aside, encoding: .utf8)) == text && next.records.count == 1
                             && next.store.isInstalled(id) && next.exists(next.data.appendingPathComponent("saved")),
                         "adding a tool then puts the old file aside, whole, and starts a new one (\(what))")
        }
        suite.expect(ToolRecords.fileName == "InstalledTools.json" && ToolRecords.version == 1
                         && ToolID("InstalledTools.json")?.isBundledForm == false
                         && ToolFolders(root: URL(fileURLWithPath: "/s")).records.path == "/s/InstalledTools.json"
                         && ToolFolders(root: URL(fileURLWithPath: "/s")).place(for: ToolID("InstalledTools.json")!)?.files.path
                         == "/s/Tools/InstalledTools.json",
                     "the file is beside the tools' folders, not in one: a tool named like it gets its own folder")
    }

    /// The one sentence a person is shown when a tool stops working, and
    /// the button that starts it again.
    static func toldOnce(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let picked = bench.folder(manifest: ExternalToolManifestTests.file(#"{"uses": []}"#))
        bench.add(picked)
        bench.registry.run(copy)
        bench.current.greets()
        bench.current.ends(1)
        suite.expect(bench.said == ["exclamationmark.triangle: «\u{00A0}Déploiements\u{00A0}» a cessé de fonctionner"]
                         && bench.stoppedWorking == [id],
                     "at a tool's first crash the person is told, in one sentence in the app's language, "
                         + "by the name the tool gives itself in that language, whatever the tool says it uses")
        bench.clock.advance(by: 1)
        bench.registry.run(copy)
        bench.current.ends(1)
        suite.expect(bench.said.count == 1 && bench.stoppedWorking == [id],
                     "a second crash says nothing more: once for each tool, in each run of the app")
        bench.clock.advance(by: 2)
        bench.registry.run(copy)
        bench.current.ends(1)
        suite.expect(bench.store.listed.first?.standing == .gaveUp && !bench.registry.canRun(copy) && bench.said.count == 1,
                     "after three crashes within a minute it stays stopped, and Settings is told so")

        let revision = bench.registry.revision
        bench.store.startAgain(id)
        suite.expect(bench.store.listed.first?.standing == .resting && bench.registry.canRun(copy)
                         && bench.registry.revision > revision && bench.registry.run(copy) && bench.runs.count == 4,
                     "starting it again from Settings lets its commands run, and the next one starts its program")
        bench.current.greets()
        bench.store.startAgain(id)
        suite.expect(bench.store.listed.first?.standing == .running && bench.runs.count == 4,
                     "starting again a tool that is running does nothing")
        bench.store.startAgain(ToolID("com.acme.other")!)

        // The same tool, updated in the same run of the app, crashes again.
        bench.add(picked)
        bench.registry.run(copy)
        bench.current.ends(1)
        suite.expect(bench.said.count == 1, "a tool that was updated is still the same tool: the person was told already")

        let next = bench.relaunched()
        next.store.restore()
        next.registry.run(copy)
        next.current.ends(1)
        suite.expect(next.said.count == 1, "at the next launch the person is told again, once")
    }

    /// When nothing is said, and when Start Again does nothing.
    static func saysNothing(_ suite: TestSuite) {
        let idle = Bench()
        defer { idle.close() }
        idle.add(idle.folder())
        idle.registry.run(copy)
        idle.current.greets()
        idle.current.exitsOnClose = 0
        idle.clock.advance(by: 121)
        suite.expect(idle.runs.count == 1 && idle.current.inputClosed && idle.said.isEmpty && idle.stoppedWorking.isEmpty,
                     "a tool stopped for being idle is not said to have stopped working")
        idle.registry.run(copy)
        idle.current.greets()
        idle.store.setOn(id, false)
        idle.current.ends(9)
        suite.expect(idle.runs.count == 2 && idle.said.isEmpty && idle.stoppedWorking.isEmpty,
                     "nor is one the person switched off, however its program then ends")

        let gone = Bench()
        defer { gone.close() }
        gone.add(gone.folder())
        gone.registry.run(copy)
        gone.current.greets()
        gone.store.remove(id, deletingData: true)
        gone.current.ends(1)
        suite.expect(gone.said.isEmpty && gone.stoppedWorking.isEmpty, "nor one that was removed")

        let quit = Bench()
        defer { quit.close() }
        quit.add(quit.folder())
        quit.registry.run(copy)
        quit.current.greets()
        quit.current.exitsOnClose = 1
        quit.host.stopAll()
        suite.expect(quit.current.inputClosed && quit.said.isEmpty && quit.stoppedWorking.isEmpty,
                     "and nothing is said at quit, even when a program leaves with an error")

        let early = Bench()
        defer { early.close() }
        early.add(early.folder())
        early.registry.run(copy)
        early.current.greets()
        early.current.ends(1)
        let revision = early.registry.revision
        early.store.startAgain(id)
        suite.expect(early.store.listed.first?.standing == .waiting && early.runs.count == 1
                         && !early.registry.canRun(copy) && early.registry.revision == revision && early.said.count == 1,
                     "starting again a tool the app has not given up on does nothing: it is still waiting")

        let held = Bench()
        defer { held.close() }
        held.add(held.folder())
        try? Data("{}".utf8).write(to: held.files.appendingPathComponent("vitruvian-tool.json"))
        let after = held.relaunched()
        after.store.restore()
        after.store.startAgain(id)
        suite.expect(after.store.listed.map(\.isHeld) == [true] && after.store.listed.first?.standing == nil
                         && after.runs.isEmpty && after.started.isEmpty && after.registry.tool(id) == nil
                         && !after.registry.canRun(copy) && after.host.manifest(for: id) == nil,
                     "starting again cannot start a tool that is held back")
    }

    /// The whole path with a real program: the fixture tool, added from a
    /// folder, run from the registry, killed, started again, and stopped
    /// as the app stops it at quit.
    static func aRealTool(_ suite: TestSuite) {
        guard let fixture = ToolProcessTests.fixture else {
            suite.expect(false, "the fixture tool is built and handed to the tests in VITRUVIAN_TOOL_FIXTURE")
            return
        }
        let bench = Bench()
        var processes: [ProcessTransport] = []
        bench.transport = { program, data in
            let process = ProcessTransport(program: program, directory: data)
            processes.append(process)
            return process
        }
        defer {
            for process in processes { process.kill() }
            _ = ToolRuntimeSupport.wait { processes.allSatisfy { !$0.isRunning } }
            bench.close()
        }
        let manifest = ExternalToolManifestTests.file(#"""
            {"id": "dev.vitruvian.fixture", "uses": ["notify"],
             "runtime": {"kind": "external", "exec": "bin/fixture"},
             "contributes": {"commands": [
               {"id": "hello", "title": {"en": "Hello"}, "surfaces": ["commandBar"]},
               {"id": "quick", "title": {"en": "Quick"}, "surfaces": ["commandBar"]},
               {"id": "hang", "title": {"en": "Hang"}, "surfaces": ["commandBar"]}]}}
            """#)
        let tool = ToolID("dev.vitruvian.fixture")!
        let hello = CommandID(tool: tool, name: "hello")!
        let quick = CommandID(tool: tool, name: "quick")!
        let hang = CommandID(tool: tool, name: "hang")!
        guard case .success = bench.add(bench.folder(manifest: manifest, exec: "bin/fixture",
                                                                      program: fixture)) else {
            suite.expect(false, "the fixture tool is added from a folder")
            return
        }

        suite.expect(bench.registry.run(hello)
                         && ToolRuntimeSupport.wait { bench.said == ["hand.wave: Hello from the fixture"] }
                         && processes.count == 1,
                     "a command run from the registry starts the real program, which has the app show its message")
        // The fixture logs this after it has answered the command, on the
        // same pipe, so the answer has arrived when the line has.
        let answered = ToolLog.Entry(source: .message, text: "hello answered")
        suite.expect(ToolRuntimeSupport.wait { bench.store.tool(tool)?.log.entries.contains(answered) == true }
                         && bench.store.tool(tool)?.standing == .running && bench.beeps == 0,
                     "and the command was answered: nothing beeped")

        bench.registry.run(hang)
        if let pid = processes[0].processIdentifier { Darwin.kill(pid, SIGKILL) }
        suite.expect(ToolRuntimeSupport.wait { bench.store.tool(tool)?.standing == .waiting }
                         && !bench.registry.canRun(hello) && bench.stoppedWorking == [tool] && bench.beeps == 1,
                     "killed while it runs a command, the tool is held back, its commands grey out, "
                         + "the command beeps and the store is told")
        bench.clock.advance(by: 1)
        suite.expect(bench.registry.canRun(quick) && bench.registry.run(quick)
                         && ToolRuntimeSupport.wait { bench.store.tool(tool)?.standing == .running }
                         && processes.count == 2 && processes[1].isRunning,
                     "after its wait the next command starts the program again: the app's side recovered")

        bench.host.stopAll()
        suite.expect(processes.allSatisfy { !$0.isRunning } && processes[1].exitStatus == 0,
                     "at quit the host stops it and waits for it without turning the run loop: no process is left")
    }

    /// Removing with a real program: one that leaves when told, and one
    /// that ignores the goodbye and being asked to end, and writes into its
    /// data folder for as long as it lives.
    static func aRealToolRemoved(_ suite: TestSuite) {
        guard let fixture = ToolProcessTests.fixture else {
            suite.expect(false, "the fixture tool is built and handed to the tests in VITRUVIAN_TOOL_FIXTURE")
            return
        }
        let manifest = ExternalToolManifestTests.file(#"""
            {"id": "dev.vitruvian.fixture", "uses": [],
             "runtime": {"kind": "external", "exec": "bin/fixture"},
             "contributes": {"commands": [
               {"id": "quick", "title": {"en": "Quick"}, "surfaces": ["commandBar"]},
               {"id": "scribble", "title": {"en": "Scribble"}, "surfaces": ["commandBar"]}]}}
            """#)
        let tool = ToolID("dev.vitruvian.fixture")!
        var processes: [ProcessTransport] = []
        var benches: [Bench] = []
        defer {
            for process in processes { process.kill() }
            _ = ToolRuntimeSupport.wait { processes.allSatisfy { !$0.isRunning } }
            for bench in benches { bench.close() }
        }
        /// A bench with the fixture added and `command` run, its program
        /// started.
        func running(_ command: String) -> Bench? {
            let bench = Bench()
            benches.append(bench)
            bench.transport = { program, data in
                let process = ProcessTransport(program: program, directory: data)
                processes.append(process)
                return process
            }
            guard case .success = bench.add(bench.folder(manifest: manifest, exec: "bin/fixture", program: fixture)),
                  let run = CommandID(tool: tool, name: command), bench.registry.run(run),
                  ToolRuntimeSupport.wait(until: { bench.store.tool(tool)?.standing == .running }) else {
                suite.expect(false, "the fixture tool is added and started (\(command))")
                return nil
            }
            return bench
        }
        func files(_ bench: Bench) -> URL { bench.support.appendingPathComponent("Tools/dev.vitruvian.fixture") }
        func saved(_ bench: Bench) -> URL { bench.support.appendingPathComponent("ToolData/dev.vitruvian.fixture") }

        guard let polite = running("quick") else { return }
        var began = ProcessInfo.processInfo.systemUptime
        var outcome = polite.store.remove(tool, deletingData: true)
        var removed = outcome.removed
        let politely = outcome
        var took = ProcessInfo.processInfo.systemUptime - began
        suite.expect(removed && took < 0.5 && processes.count == 1 && !processes[0].isRunning
                         && processes[0].exitStatus == 0 && polite.waits.count <= 1
                         && !polite.exists(files(polite)) && !polite.exists(saved(polite)),
                     "a real tool that leaves when told goodbye is removed in well under a second, "
                         + "its program gone by itself before its folders are")

        guard let stubborn = running("scribble") else { return }
        let scribbling = ToolLog.Entry(source: .message, text: "scribbling")
        guard ToolRuntimeSupport.wait(until: { stubborn.store.tool(tool)?.log.entries.contains(scribbling) == true }),
              stubborn.exists(saved(stubborn).appendingPathComponent("scribbled")) else {
            suite.expect(false, "the fixture writes into its data folder while it runs")
            return
        }
        began = ProcessInfo.processInfo.systemUptime
        outcome = stubborn.store.remove(tool, deletingData: true)
        removed = outcome.removed
        took = ProcessInfo.processInfo.systemUptime - began
        suite.expect(removed && processes.count == 2 && !processes[1].isRunning
                         && processes[1].exitStatus == 128 + SIGKILL && stubborn.waits == [0.5, 0.25, 0.25]
                         && took < 2,
                     "a real tool that ignores the goodbye and being asked to end is dead, killed, "
                         + "when removing it returns, within the three short waits")
        suite.expect(politely == .deleted && outcome == .deleted,
                     "removing a real tool says what it saved was deleted: when it left by itself, and when it was killed")
        // Alive, it makes the folder again every half a millisecond. So a
        // folder that is gone and stays gone was deleted after it died.
        suite.expect(!stubborn.exists(saved(stubborn)) && !stubborn.exists(files(stubborn))
                         && !ToolRuntimeSupport.wait(upTo: 0.2, until: { stubborn.exists(saved(stubborn)) }),
                     "and what it saved was deleted after that: the folder it kept writing into is gone, and stays gone")
    }

    /// A real tool that started a program of its own, which writes into the
    /// tool's data folder for as long as it lives: removed, switched off,
    /// and at quit, the helper ends with its tool.
    static func aRealToolWithAHelper(_ suite: TestSuite) {
        guard let fixture = ToolProcessTests.fixture else {
            suite.expect(false, "the fixture tool is built and handed to the tests in VITRUVIAN_TOOL_FIXTURE")
            return
        }
        let manifest = ExternalToolManifestTests.file(#"""
            {"id": "dev.vitruvian.fixture", "uses": [],
             "runtime": {"kind": "external", "exec": "bin/fixture"},
             "contributes": {"commands": [
               {"id": "helper", "title": {"en": "Helper"}, "surfaces": ["commandBar"]},
               {"id": "helper-deaf", "title": {"en": "Deaf helper"}, "surfaces": ["commandBar"]}]}}
            """#)
        let tool = ToolID("dev.vitruvian.fixture")!
        var processes: [ProcessTransport] = []
        var benches: [Bench] = []
        var helpers: [ToolProcessTests.Helper] = []
        defer {
            for process in processes { process.kill() }
            _ = ToolRuntimeSupport.wait { processes.allSatisfy { !$0.isRunning } }
            for helper in helpers { helper.end() }
            for bench in benches { bench.close() }
        }
        /// A bench with the fixture added and running, and the helper it
        /// started with `command`, once the helper has written its file.
        func running(_ command: String) -> (Bench, ToolProcessTests.Helper)? {
            let bench = Bench()
            benches.append(bench)
            bench.transport = { program, data in
                let process = ProcessTransport(program: program, directory: data)
                processes.append(process)
                return process
            }
            let program = bench.support.appendingPathComponent("Tools/dev.vitruvian.fixture/bin/fixture")
            var helper: ToolProcessTests.Helper?
            guard case .success = bench.add(bench.folder(manifest: manifest, exec: "bin/fixture", program: fixture)),
                  let run = CommandID(tool: tool, name: command), bench.registry.run(run),
                  ToolRuntimeSupport.wait(until: {
                      helper = ToolProcessTests.Helper(logged: bench.store.tool(tool)?.log.entries.map(\.text) ?? [],
                                                       program: program)
                      return (helper?.count ?? 0) > 0
                  }), let helper else {
                // A helper that was started is ended, whatever went wrong after.
                if let helper { helpers.append(helper) }
                suite.expect(false, "the fixture tool is added and starts a helper (\(command)): it stands "
                    + "\(String(describing: bench.store.tool(tool)?.standing)) and logged "
                    + "\(bench.store.tool(tool)?.log.entries.map(\.text) ?? [])")
                return nil
            }
            helpers.append(helper)
            return (bench, helper)
        }
        func saved(_ bench: Bench) -> URL { bench.support.appendingPathComponent("ToolData/dev.vitruvian.fixture") }

        // Removed, with what it saved.
        guard let (removed, writer) = running("helper") else { return }
        suite.expect(writer.file.deletingLastPathComponent().standardizedFileURL.path == saved(removed).standardizedFileURL.path
                         && writer.stillWrites(),
                     "a real tool's helper writes into the tool's data folder while the tool runs")
        let outcome = removed.store.remove(tool, deletingData: true)
        suite.expect(outcome == .deleted && writer.isGone && !removed.exists(saved(removed))
                         && !ToolRuntimeSupport.wait(upTo: 0.2, until: { removed.exists(saved(removed)) }),
                     "removing a real tool with what it saved ends the helper it started: the helper is gone, and "
                         + "the folder it wrote into is deleted and stays gone")

        // Switched off.
        guard let (switched, idle) = running("helper") else { return }
        switched.store.setOn(tool, false)
        suite.expect(ToolRuntimeSupport.wait { processes.allSatisfy { !$0.isRunning } } && idle.isGone
                         && !idle.stillWrites(upTo: 0.2),
                     "switching a real tool off ends its helper with it: its file stops changing")

        // At quit, with a helper that ignores being asked to end.
        guard let (quitting, deaf) = running("helper-deaf") else { return }
        quitting.host.stopAll()
        suite.expect(processes.allSatisfy { !$0.isRunning } && deaf.isGone,
                     "at quit the host stops a real tool and waits for it, and no helper of it is left")
    }
}

extension ExternalToolStoreTests {
    /// The store hands each tool's pages, badge and end to the panel host,
    /// and takes a tool's panels away when it is switched off.
    static func panels(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let manifest = ExternalToolManifestTests.file(#"""
            {"protocol": "2", "uses": ["notify"], "contributes": {"panels": [
              {"id": "deploys", "title": {"en": "Deploys"}, "placement": "island"}]}}
            """#)
        bench.add(bench.folder(manifest: manifest))
        let island = ToolPanelHost.Key(tool: id, panel: "deploys")
        suite.expect(bench.store.installed[id]?.tool.panel(in: .island)?.id == "deploys" && bench.runs.isEmpty,
                     "a tool of protocol 2 is added with its panels, and nothing is started")
        bench.panels.open(island, in: .island)
        bench.current.greets()
        bench.current.answers(2, #"{"tree":{"blocks":[{"type":"heading","text":"Today"}]}}"#)
        suite.expect(bench.panels.shown[island].map { if case .page = $0 { return true } else { return false } } == true,
                     "opening its island panel starts its program and draws the page it answers with")
        bench.current.says(#"{"jsonrpc":"2.0","id":"b","method":"ui/badge","params":{"count":4}}"#)
        suite.expect(bench.panels.badges[id] == .count(4)
                         && bench.current.sent.last == .result(id: .string("b"), value: .object([:])),
                     "its badge reaches the host, and the tool is answered")
        bench.current.says(#"{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"deploys","tree":{"blocks":[]}}}"#)
        suite.expect(bench.panels.shown[island] == .page(UITree(blocks: [])),
                     "a page it sends unprompted reaches the host")
        bench.store.setOn(id, false)
        suite.expect(bench.panels.shown.isEmpty && bench.panels.badges[id] == nil,
                     "switched off, its panels close and its badge goes")
    }
}

extension ExternalToolStoreTests {
    /// A tool of protocol 2 that declares a status, with an island page.
    static let withStatus = #"""
        {"protocol": "2", "uses": ["notify", "storage"], "contributes": {
          "commands": [{"id": "copyLatest", "title": {"en": "Copy latest deploy"}, "surfaces": ["commandBar"]}],
          "panels": [{"id": "deploys", "title": {"en": "Deploys"}, "placement": "island"}],
          "status": {"placement": "island"}},
         "preferences": [
           {"id": "light", "title": {"en": "Light", "fr": "Lumière"}, "type": "string", "default": "green",
            "options": [{"value": "green", "title": {"en": "Green", "fr": "Vert"}},
                        {"value": "breathe green", "title": {"en": "Pulsing green"}}]},
           {"id": "project", "title": {"en": "Project"}, "type": "string", "default": "web"}]}
        """#

    /// Every name of the protocol is in exactly one of the app's two lists:
    /// what it has, or what it knows and does not draw yet. A name added to
    /// the protocol fails here until the app decides whether it draws it,
    /// and says so in one of them.
    static func theAppHasEveryFeatureOfTheProtocol(_ suite: TestSuite) {
        let has = ExternalToolStore.features
        let notYet = ExternalToolStore.notDrawnYet
        suite.expect(Set(has).union(notYet) == Set(ProtocolFeature.allCases)
                         && Set(has).isDisjoint(with: notYet)
                         && has.count + notYet.count == ProtocolFeature.allCases.count,
                     "the app has or knows every feature of the protocol, each once: a name added to it fails "
                         + "here until the app decides whether it draws it")
    }

    /// The app names its features from a list of its own, not from every
    /// name the protocol has: a name added to the protocol is not claimed
    /// until the app draws it.
    static func theHelloNamesOnlyWhatTheAppHas(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.add(bench.folder())
        bench.registry.run(copy)
        var said: [String] = []
        if case .request(_, "initialize", let params)? = bench.current.sent.first {
            said = params?["features"]?.arrayValue?.compactMap(\.stringValue) ?? []
        }
        suite.expect(said == ["ui.status", "ui.choice", "preferences.options", "ui.status.activity", "ui.open.settings",
                              "ui.chips", "ui.sections"]
                         && said == ExternalToolStore.features.map(\.rawValue),
                     "the hello names what this app has: a status, a choice block, options on a preference, a "
                         + "status's words, a tool's own settings opened from its panel, chips, and sections and help")
        let example = ExternalToolSettingsTests.example(of: "initialize")
        suite.expect(example == nil || example?["params"]?.objectValue?.keys.sorted()
                         == ["dataFolder", "language", "protocolVersions"],
                     "the protocol's first example of the hello is an older app's: it names none")
    }

    static func theStatusSwitchIsYesUntilTurnedOff(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: ExternalToolManifestTests.file(withStatus)))
        suite.expect(bench.store.showsStatus(id) && bench.store.statusTools() == [id]
                         && bench.records.first?.showsStatus == nil,
                     "a tool's status is shown until the person turns it off, and nothing is written down for that")
        let revision = bench.registry.revision
        bench.store.setShowsStatus(id, false)
        suite.expect(!bench.store.showsStatus(id) && bench.store.statusTools().isEmpty
                         && bench.records.first?.showsStatus == false && bench.registry.revision > revision,
                     "turned off, it is written down, the tool is listed no more, and whoever draws is told to look")
        let next = bench.relaunched()
        next.store.restore()
        suite.expect(!next.store.showsStatus(id) && next.store.statusTools().isEmpty,
                     "and it stays off at the next launch")
        next.store.setShowsStatus(id, true)
        suite.expect(next.store.showsStatus(id) && next.store.statusTools() == [id] && next.records.first?.showsStatus == nil,
                     "turned on again, the record is as it was before it was ever turned off")
        next.store.setShowsStatus(ToolID("com.acme.other")!, false)
        suite.expect(next.records.count == 1 && next.store.showsStatus(ToolID("com.acme.other")!),
                     "a switch for a tool nobody added changes nothing")
    }

    static func aRecordFromBeforeReadsAsItDid(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: ExternalToolManifestTests.file(withStatus)))
        let before = (try? String(contentsOf: bench.recordsFile, encoding: .utf8)) ?? ""
        suite.expect(!before.isEmpty && !before.contains("showsStatus") && !before.contains("showsInIsland"),
                     "a record is written with no word about the status, as a file from before it is")
        // The next launch reads that file, and writing it again adds nothing.
        let next = bench.relaunched()
        next.store.restore()
        next.store.setOn(id, false)
        next.store.setOn(id, true)
        let after = (try? String(contentsOf: bench.recordsFile, encoding: .utf8)) ?? ""
        suite.expect(next.store.showsStatus(id) && after == before,
                     "a file from before the switch loads with the status shown, and saving it writes no such key")
        next.store.setShowsStatus(id, false)
        let off = (try? String(contentsOf: bench.recordsFile, encoding: .utf8)) ?? ""
        suite.expect(off.contains(#""showsStatus" : false"#) && !off.contains("showsInIsland"),
                     "only turning it off writes the key")
    }

    static func statusToolsLeavesOutASwitchedOffAndAnUndeclaredTool(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        func manifest(_ id: String, status: Bool) -> Data {
            ExternalToolManifestTests.file(#"""
                {"id": "\#(id)", "protocol": "2",
                 "contributes": {\#(status ? #""status": {"placement": "island"}"# : "")}}
                """#)
        }
        let names = ["com.acme.first", "com.acme.plain", "com.acme.second", "com.acme.third"]
        for (index, name) in names.enumerated() {
            bench.add(bench.folder("picked-\(index)", manifest: manifest(name, status: name != "com.acme.plain")))
        }
        let ids = names.compactMap { ToolID($0) }
        suite.expect(bench.store.statusTools() == [ids[0], ids[2], ids[3]],
                     "the tools whose status may be drawn are the ones that declare one, in the order added")
        bench.store.setShowsStatus(ids[2], false)
        suite.expect(bench.store.statusTools() == [ids[0], ids[3]],
                     "a tool whose status the person switched off is left out")
        bench.store.setOn(ids[0], false)
        suite.expect(bench.store.statusTools() == [ids[3]], "and so is a tool that is switched off")
        bench.store.setOn(ids[0], true)
        bench.store.setShowsStatus(ids[2], true)
        suite.expect(bench.store.statusTools() == [ids[0], ids[2], ids[3]],
                     "each comes back in its place, where it was added")
        // A tool held back, whose copy is not what the person agreed to.
        try? Data("{}".utf8).write(to: bench.support.appendingPathComponent("Tools/com.acme.third/vitruvian-tool.json"))
        let next = bench.relaunched()
        next.store.restore()
        suite.expect(next.store.listed.first { $0.id == ids[3] }?.isHeld == true
                         && next.store.statusTools() == [ids[0], ids[2]],
                     "and a tool that is held back, which is never started, has no status to draw")
    }

    static func aStatusReachesTheHostAndGoesWithTheProgram(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: ExternalToolManifestTests.file(withStatus)))
        bench.registry.run(copy)
        bench.current.greets(protocolVersion: "2")
        bench.current.says(#"{"jsonrpc":"2.0","id":"s","method":"ui/status","params":{"state":"failure","text":"main is red"}}"#)
        suite.expect(bench.panels.statuses[id] == ToolStatus(state: .failure, text: "main is red", icon: nil)
                         && bench.current.sent.last == .result(id: .string("s"), value: .object([:])),
                     "a tool's status reaches the host, and the tool is answered with {}")
        bench.store.setShowsStatus(id, false)
        bench.clock.advance(by: 1)
        bench.current.says(#"{"jsonrpc":"2.0","id":"t","method":"ui/status","params":{"state":"busy"}}"#)
        suite.expect(bench.panels.statuses[id]?.state == .busy
                         && bench.current.sent.last == .result(id: .string("t"), value: .object([:]))
                         && bench.store.statusTools().isEmpty,
                     "switched off by the person, a status is still answered with {} and still kept; "
                         + "the tool is no longer among those whose status is drawn")
        bench.store.setShowsStatus(id, true)
        suite.expect(bench.store.statusTools() == [id] && bench.panels.statuses[id]?.state == .busy,
                     "switched on again, the status it last sent is there to draw, with no restart")
        bench.current.ends(0)
        suite.expect(bench.panels.statuses[id] == nil, "and it goes when the tool's program ends")

        // A tool that declares none is refused, through the same door.
        let plain = Bench()
        defer { plain.close() }
        plain.add(plain.folder(manifest: ExternalToolManifestTests.file(#"{"protocol": "2"}"#)))
        plain.registry.run(copy)
        plain.current.greets(protocolVersion: "2")
        plain.current.says(#"{"jsonrpc":"2.0","id":"s","method":"ui/status","params":{"state":"failure"}}"#)
        suite.expect(plain.panels.statuses.isEmpty
                         && plain.current.sent.last
                         == .failure(id: .string("s"), error: RPCErrorObject(code: -32602,
                                                                             message: "the manifest declares no status")),
                     "a status from a tool whose manifest declares none is answered -32602, and none is kept")
    }

    static func aSettingCarriesItsOptions(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: ExternalToolManifestTests.file(withStatus)))
        let settings = bench.store.settings(of: id)
        suite.expect(settings.map(\.id) == ["light", "project"]
                         && settings.first?.options
                         == [PreferenceOption(value: "green", title: LocalizedText(["en": "Green", "fr": "Vert"])),
                             PreferenceOption(value: "breathe green", title: LocalizedText(["en": "Pulsing green"]))]
                         && settings.last?.options.isEmpty == true,
                     "a setting carries its options, in order, each title in its languages; one with none has none")
        suite.expect(settings.first?.value == .string("green"), "and its value is text, the default until one is saved")
    }

    static func aValueThatIsNoOptionIsStillSaved(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.add(bench.folder(manifest: ExternalToolManifestTests.file(withStatus)))
        let key = ExternalToolManifest.storageKey(tool: id, preference: "light")
        suite.expect(bench.store.setSetting(.string("breathe blue 5"), for: "light", of: id) == nil
                         && bench.box.values[key] as? String == "breathe blue 5"
                         && bench.store.settings(of: id).first?.value == .string("breathe blue 5")
                         && bench.store.settings(of: id).first?.options.count == 2,
                     "a value that is none of the options is saved as written and read back: the app never "
                         + "refuses it and never changes it")
        // One saved before the tool had options, by the tool or by a hand-off.
        bench.box.values[key] = "typed by hand"
        suite.expect(bench.store.settings(of: id).first?.value == .string("typed by hand")
                         && bench.box.values[key] as? String == "typed by hand",
                     "and one that was there already is read as it is, and left as it is")
    }

    static func homeSpeakerDoorClearedOnRemove(_ suite: TestSuite) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-door-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let doorURL = dir.appendingPathComponent("speaker_door.json")
        func writeDoor(chosen: String) {
            let payload: [String: Any] = [
                "version": 1,
                "chosen": chosen,
                "chosen_at": "2026-10-20T09:12:00Z",
                "chosen_by": "HomeSpeaker \(chosen) 1.19.0",
                "extension": [
                    "program": "/Users/test/Tools/dev.vitruvian.homespeaker/bin/tool",
                    "data_folder": "/Users/test/ToolData/dev.vitruvian.homespeaker",
                    "version": "1.19.0",
                    "door": 1,
                ],
            ]
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try? data?.write(to: doorURL, options: [.atomic])
        }
        func readDoor() -> [String: Any]? {
            guard let data = try? Data(contentsOf: doorURL) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }

        // 1. toolID != "dev.vitruvian.homespeaker": leaves the file untouched.
        writeDoor(chosen: "extension")
        ExternalToolStore.clearHomeSpeakerDoorOnRemove(toolID: "com.acme.deploys", doorFileURL: doorURL)
        let untouched = readDoor()
        suite.expect(untouched?["chosen"] as? String == "extension"
                         && untouched?["extension"] != nil,
                     "removing another tool leaves speaker_door.json untouched")

        // 2. chosen == "extension": removes extension, chosen, chosen_at, and chosen_by.
        ExternalToolStore.clearHomeSpeakerDoorOnRemove(toolID: "dev.vitruvian.homespeaker", doorFileURL: doorURL)
        let clearedExtension = readDoor()
        suite.expect(clearedExtension?["version"] as? Int == 1
                         && clearedExtension?["extension"] == nil
                         && clearedExtension?["chosen"] == nil
                         && clearedExtension?["chosen_at"] == nil
                         && clearedExtension?["chosen_by"] == nil
                         && FileManager.default.fileExists(atPath: doorURL.appendingPathExtension("lock").path),
                     "removing dev.vitruvian.homespeaker when chosen is extension clears extension and chosen fields under the lock")

        // 3. chosen == "app": removes extension, preserves chosen, chosen_at, and chosen_by.
        writeDoor(chosen: "app")
        ExternalToolStore.clearHomeSpeakerDoorOnRemove(toolID: "dev.vitruvian.homespeaker", doorFileURL: doorURL)
        let clearedApp = readDoor()
        suite.expect(clearedApp?["version"] as? Int == 1
                         && clearedApp?["extension"] == nil
                         && clearedApp?["chosen"] as? String == "app"
                         && clearedApp?["chosen_at"] as? String == "2026-10-20T09:12:00Z"
                         && clearedApp?["chosen_by"] as? String == "HomeSpeaker app 1.19.0",
                     "removing dev.vitruvian.homespeaker when chosen is app removes extension and keeps the app choice")

        // 4. File does not exist: no-op and does not create the file.
        let missingURL = dir.appendingPathComponent("nonexistent/speaker_door.json")
        ExternalToolStore.clearHomeSpeakerDoorOnRemove(toolID: "dev.vitruvian.homespeaker", doorFileURL: missingURL)
        suite.expect(!FileManager.default.fileExists(atPath: missingURL.path)
                         && !FileManager.default.fileExists(atPath: missingURL.appendingPathExtension("lock").path),
                     "removing dev.vitruvian.homespeaker when speaker_door.json does not exist writes nothing")
    }
}
