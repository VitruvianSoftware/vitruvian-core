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
        offering(suite)
        tooBigOrQuarantined(suite)
        adding(suite)
        throughTheBroker(suite)
        refusals(suite)
        removing(suite)
        installedOrNot(suite)
        remembering(suite)
        switching(suite)
        updating(suite)
        heldBack(suite)
        unreadableRecords(suite)
        aRealTool(suite)
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
        private(set) var host: ToolHost!
        private(set) var store: ExternalToolStore!

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
            host = ToolHost(broker: broker)
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
                language: { "fr" },
                stoppedWorking: { [unowned self] in stoppedWorking.append($0) }))
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
        let hello = JSONValue.object(["protocolVersions": .array([.string("1")]), "language": .string("fr"),
                                      "dataFolder": .string(bench.data.path)])
        suite.expect(bench.current.sent == [.request(id: .number(1), method: "initialize", params: hello)],
                     "it is greeted with the versions the app speaks, the app's language and its data folder")
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
        bench.store.remove(id)
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

    static func removing(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.add(bench.folder())
        bench.registry.run(copy)
        bench.current.greets()
        bench.store.remove(id)
        suite.expect(bench.current.sent.last == .notice(method: "shutdown", params: nil) && bench.current.inputClosed
                         && !bench.store.isInstalled(id) && bench.registry.tool(id) == nil
                         && bench.host.manifest(for: id) == nil && bench.store.tool(id) == nil,
                     "removing a tool stops its program and takes it out of the host and the registry")
        suite.expect(bench.exists(bench.files) && bench.exists(bench.data), "its files, and what it saved, stay")
        bench.store.remove(id)
        bench.current.ends(0)
        if case .success = bench.add(bench.folder()) {
            suite.expect(bench.registry.canRun(copy), "and it can be added again")
        } else {
            suite.expect(false, "and it can be added again")
        }

        let early = Bench()
        defer { early.close() }
        early.add(early.folder(manifest: ExternalToolManifestTests.file(#"{"activation": ["onLaunch"]}"#)))
        suite.expect(early.started.count == 1 && early.store.tool(id)?.standing == .starting,
                     "a tool that starts with the app is started as soon as it is added")
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
}
