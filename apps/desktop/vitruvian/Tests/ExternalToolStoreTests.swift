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
        developmentSwitch(suite)
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

        init(supportFolder: Bool = true, limits: ToolLimits = .standard) {
            root = FileManager.default.temporaryDirectory
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

        func close() {
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
        guard case .success(let installed) = bench.store.install(from: bench.folder()) else {
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
        bench.store.install(from: bench.folder())
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
        suite.expect(refusal(bench.store.install(from: empty)) == .manifest(.noManifest),
                     "a folder with no manifest is not added")
        let bad = bench.folder("bad", manifest: ExternalToolManifestTests.file(#"{"uses": ["camera"]}"#))
        suite.expect(refusal(bench.store.install(from: bad)) == .manifest(.invalid(.unknownService("camera")))
                         && !bench.exists(bench.support) && bench.store.installed.isEmpty
                         && bench.registry.tool(id) == nil,
                     "a manifest that breaks a rule is refused with what is wrong, and nothing is copied")

        let linked = bench.folder("linked")
        let outside = bench.root.appendingPathComponent("elsewhere")
        FileManager.default.createFile(atPath: outside.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        try? FileManager.default.removeItem(at: linked.appendingPathComponent("bin/deploys"))
        try? FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("bin/deploys"),
                                                    withDestinationURL: outside)
        suite.expect(refusal(bench.store.install(from: linked)) == .manifest(.programOutsideFolder("bin/deploys"))
                         && !bench.exists(bench.support),
                     "a program that is a link out of the folder is refused before anything is copied")

        let homeless = Bench(supportFolder: false)
        defer { homeless.close() }
        suite.expect(refusal(homeless.store.install(from: bench.folder("nowhere"))) == .noSupportFolder
                         && homeless.store.installed.isEmpty,
                     "with no support folder to copy into, nothing is added")

        bench.store.install(from: bench.folder())
        try? Data("in use".utf8).write(to: bench.files.appendingPathComponent("marker"))
        suite.expect(refusal(bench.store.install(from: bench.folder("again"))) == .alreadyInstalled(id)
                         && bench.store.installed.count == 1 && bench.exists(bench.files.appendingPathComponent("marker")),
                     "a tool whose id is installed already is not added a second time, and its copy is left alone")
    }

    static func removing(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.store.install(from: bench.folder())
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
        if case .success = bench.store.install(from: bench.folder()) {
            suite.expect(bench.registry.canRun(copy), "and it can be added again")
        } else {
            suite.expect(false, "and it can be added again")
        }

        let early = Bench()
        defer { early.close() }
        early.store.install(from: early.folder(manifest: ExternalToolManifestTests.file(#"{"activation": ["onLaunch"]}"#)))
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

    static func developmentSwitch(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let domain = "com.vitruviansoftware.vitruvian.tests.tool-store"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(ExternalToolStore.developmentToolFolderKey == "developmentToolFolder"
                         && bench.store.installDevelopmentTool(defaults: defaults) == nil
                         && bench.store.installed.isEmpty && !bench.exists(bench.support),
                     "with the hidden preference not set, the development switch adds nothing and touches nothing")

        let picked = bench.folder()
        try? Data("one".utf8).write(to: picked.appendingPathComponent("notes"))
        defaults.set(picked.path, forKey: ExternalToolStore.developmentToolFolderKey)
        if case .success(let installed)? = bench.store.installDevelopmentTool(defaults: defaults) {
            suite.expect(installed.tool.manifest.id == id && bench.registry.canRun(copy) && bench.started.isEmpty,
                         "with it naming a tool's folder, that tool is added with no screen, and starts on its first command")
        } else {
            suite.expect(false, "with it naming a tool's folder, that tool is added")
        }

        // The next launch: the store has forgotten the tool, and the
        // folder has changed.
        try? Data("kept".utf8).write(to: bench.data.appendingPathComponent("saved"))
        try? Data("two".utf8).write(to: picked.appendingPathComponent("notes"))
        bench.store.remove(id)
        _ = bench.store.installDevelopmentTool(defaults: defaults)
        suite.expect((try? String(contentsOf: bench.files.appendingPathComponent("notes"), encoding: .utf8)) == "two"
                         && bench.exists(bench.data.appendingPathComponent("saved")) && bench.store.isInstalled(id),
                     "each launch adds the folder afresh: the copy is the folder as it is now, and what the tool saved is kept")

        bench.store.remove(id)
        defaults.set(bench.root.appendingPathComponent("no such folder").path,
                     forKey: ExternalToolStore.developmentToolFolderKey)
        suite.expect(bench.store.installDevelopmentTool(defaults: defaults).flatMap(refusal) == .manifest(.noManifest)
                         && bench.store.installed.isEmpty,
                     "a folder that is no tool is refused, and the app carries on without it")
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
        guard case .success = bench.store.install(from: bench.folder(manifest: manifest, exec: "bin/fixture",
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
