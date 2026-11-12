// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// The tool host holding its second kind of tool, one handed over already
/// made, and the registry listing such a tool's commands.
enum ExternalToolHostTests {
    static func run(_ suite: TestSuite) {
        holding(suite)
        commands(suite)
        runRule(suite)
        quitting(suite)
        quittingRealPrograms(suite)
        listing(suite)
        toolsGrid(suite)
    }

    /// Something the host can hold that only records what it was asked.
    final class StandIn: HostedTool {
        var started = 0
        var stopped = 0
        var ran: [CommandID] = []
        var asked = 0
        var runnable = true
        /// False for a tool whose program is still running.
        var ended = true
        var escalations = 0
        /// How many times it must be escalated before it ends.
        var endsAfter = Int.max

        func start() { started += 1 }
        func stop() { stopped += 1 }
        func run(_ command: CommandID) { ran.append(command) }

        func canRun(_ command: CommandID) -> Bool {
            asked += 1
            return runnable
        }

        var hasEnded: Bool { ended }

        func escalate() {
            escalations += 1
            if escalations >= endsAfter { ended = true }
        }
    }

    /// A host over a broker whose world a test sets, and the waits the
    /// host asked for at quit.
    final class Bench {
        let world = ToolBrokerTests.World()
        var waits: [TimeInterval] = []
        /// What happens during a wait.
        var during: (TimeInterval) -> Void = { _ in }
        private(set) var host: ToolHost!

        init() {
            host = ToolHost(broker: ToolBrokerTests.bench(world: world), wait: { [unowned self] seconds, done in
                waits.append(seconds)
                during(seconds)
                _ = done()
            })
        }
    }

    static let deploys = ExternalToolManifestTests.tool()!
    static let id = ExternalToolTests.id
    static let copy = ExternalToolTests.copy

    static func holding(_ suite: TestSuite) {
        let bench = Bench()
        let tool = StandIn()
        suite.expect(bench.host.manifest(for: id) == nil && !bench.host.canRun(copy),
                     "a host knows nothing of a tool it was not handed")
        suite.expect(bench.host.add(tool, manifest: deploys.manifest) && bench.host.manifest(for: id) == deploys.manifest
                         && bench.host.built == [id] && tool.started == 0,
                     "an outside tool is handed over made, with its manifest, and is not started by that")
        suite.expect(!bench.host.add(StandIn(), manifest: deploys.manifest) && bench.host.built == [id],
                     "a second tool under the same id is refused")
        suite.expect(!bench.host.add(StandIn(), manifest: ToolBrokerTests.manifest([.open]))
                         && bench.host.manifest(for: ToolID("portManager")!) == nil,
                     "a tool under an id with no dot, the form of the app's own, is refused")

        bench.host.sync(id)
        bench.host.remove(id)
        suite.expect(tool.stopped == 1 && bench.host.manifest(for: id) == nil && bench.host.built.isEmpty
                         && bench.host.running.isEmpty && !bench.host.canRun(copy),
                     "removing it stops it and forgets it")
        bench.host.remove(id)
        suite.expect(tool.stopped == 1, "once")
    }

    static func commands(_ suite: TestSuite) {
        let bench = Bench()
        let tool = StandIn()
        bench.host.add(tool, manifest: deploys.manifest)
        suite.expect(bench.host.canRun(copy) && tool.asked == 1 && tool.started == 0,
                     "a command of an outside tool can run when the tool says so, and asking starts nothing")
        suite.expect(!bench.host.canRun(CommandID(tool: id, name: "other")!) && tool.asked == 1,
                     "a command its manifest does not declare cannot, and the tool is not asked")
        bench.host.run(copy)
        suite.expect(tool.ran == [copy], "the host runs a command on the tool")
        tool.runnable = false
        bench.host.run(copy)
        suite.expect(!bench.host.canRun(copy) && tool.ran == [copy], "and not one the tool says cannot run")
        tool.runnable = true
        bench.world.installed = false
        let asked = tool.asked
        bench.host.run(copy)
        suite.expect(!bench.host.canRun(copy) && tool.asked == asked && tool.ran == [copy],
                     "nor any command of a tool that is not installed, whatever the tool says")
    }

    static func runRule(_ suite: TestSuite) {
        let bench = Bench()
        let tool = StandIn()
        let typing = ExternalToolManifestTests.tool(#"{"uses": ["keystrokes"]}"#)!.manifest
        bench.host.add(tool, manifest: typing)
        bench.world.granted = []
        bench.host.sync(id)
        suite.expect(tool.started == 1 && bench.host.running == [id] && bench.host.shouldRun(typing),
                     "an installed outside tool is started, and is not held back for a macOS grant")
        bench.host.sync(id)
        suite.expect(tool.started == 2 && bench.host.running == [id], "the host may start it again; that is safe")
        bench.world.installed = false
        bench.host.sync(id)
        suite.expect(tool.stopped == 1 && bench.host.running.isEmpty, "one that is no longer installed is stopped")
        bench.world.installed = true
        bench.host.sync(id)
        bench.host.suspend(id)
        suite.expect(tool.stopped == 2 && bench.host.running.isEmpty && bench.host.manifest(for: id) != nil,
                     "and it can be stopped at once without being forgotten")
    }

    static func quitting(_ suite: TestSuite) {
        let quiet = Bench()
        let gone = StandIn()
        quiet.host.add(gone, manifest: deploys.manifest)
        quiet.host.sync(id)
        quiet.host.stopAll()
        suite.expect(gone.stopped == 1 && quiet.waits.isEmpty && gone.escalations == 0,
                     "at quit a tool with no program left is stopped, and the host waits for nothing")

        let polite = Bench()
        let leaving = StandIn()
        leaving.ended = false
        polite.host.add(leaving, manifest: deploys.manifest)
        polite.during = { _ in leaving.ended = true }
        polite.host.stopAll()
        suite.expect(leaving.stopped == 1 && polite.waits == [2] && leaving.escalations == 0,
                     "a program still running is given two seconds to leave; one that does is left alone")

        let slow = Bench()
        let lingering = StandIn()
        lingering.ended = false
        lingering.endsAfter = 1
        slow.host.add(lingering, manifest: deploys.manifest)
        slow.host.stopAll()
        suite.expect(slow.waits == [2] && lingering.escalations == 1,
                     "one that has not left is asked to end; when that ends it, the host waits no more")

        let stubborn = Bench()
        let ignoring = StandIn()
        ignoring.ended = false
        stubborn.host.add(ignoring, manifest: deploys.manifest)
        stubborn.host.stopAll()
        suite.expect(stubborn.waits == [2, 1] && ignoring.escalations == 2,
                     "one that ignores that is given one more second, then killed: three seconds at most")

        let started = ProcessInfo.processInfo.systemUptime
        ToolHost.wait(upTo: 30) { true }
        ToolHost.wait(upTo: 0.05) { false }
        let took = ProcessInfo.processInfo.systemUptime - started
        suite.expect(took >= 0.05 && took < 20,
                     "the wait returns as soon as its condition holds, and when its time is up")
    }

    /// The fixture tool as a real child process, held by a host that waits
    /// at quit as the app does: on the Mac's own clock, without turning the
    /// run loop. The tool's own deadlines are on a clock nobody moves, as
    /// at quit, when no timer fires again.
    final class RealBench {
        static let manifest = ExternalToolManifestTests.tool(#"""
            {"activation": ["onLaunch"],
             "contributes": {"commands": [
                {"id": "stubborn", "title": {"en": "Stubborn"}, "icon": "link", "surfaces": ["commandBar"]},
                {"id": "flood", "title": {"en": "Flood"}, "icon": "link", "surfaces": ["commandBar"]}]}}
            """#)!.manifest

        let clock = ManualToolClock()
        let folder: URL
        let host: ToolHost
        private(set) var transport: ProcessTransport?
        private(set) var tool: ExternalTool!

        init(program: URL, limits: ToolLimits = .standard) {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitruvian-tool-quit-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            host = ToolHost(broker: ToolBrokerTests.bench(), limits: limits)
            tool = ExternalTool(manifest: Self.manifest, clock: clock, makeLink: { [unowned self] events in
                let transport = ProcessTransport(program: program, directory: folder)
                self.transport = transport
                return ToolLink(transport: transport, clock: clock,
                                hello: InitializeParams(protocolVersions: ProtocolVersion.supported, language: "en",
                                                        dataFolder: folder.path),
                                serve: { _, _, reply in reply(.success(.object([:]))) }, events: events)
            })
        }

        /// Hands the tool to the host, which starts it, and waits for its
        /// greeting.
        func start() -> Bool {
            host.add(tool, manifest: Self.manifest)
            host.sync(ExternalToolTests.id)
            return ToolRuntimeSupport.wait { self.tool.standing == .running }
        }

        /// Runs a command of the fixture and waits until its log holds
        /// `count` lines that say `text`.
        func run(_ name: String, untilLogged text: String, count: Int = 1) -> Bool {
            guard let command = CommandID(tool: ExternalToolTests.id, name: name) else { return false }
            host.run(command)
            return ToolRuntimeSupport.wait {
                self.tool.log.entries.lazy.filter { $0 == .init(source: .message, text: text) }.count >= count
            }
        }

        /// Quits, as `applicationWillTerminate` does. How long the main
        /// thread was kept, in seconds.
        func quit() -> TimeInterval {
            let started = ProcessInfo.processInfo.systemUptime
            host.stopAll()
            return ProcessInfo.processInfo.systemUptime - started
        }

        /// True when the process is gone: ended, and collected by the app.
        var isGone: Bool {
            guard let transport, let pid = transport.processIdentifier else { return true }
            return !transport.isRunning && Darwin.kill(pid, 0) == -1 && errno == ESRCH
        }

        /// The status the program ended with, once the app has seen it go.
        func status() -> Int32? {
            ToolRuntimeSupport.wait { self.isGone }
            return transport?.exitStatus
        }

        /// Ends the process whatever state the test left it in, and says
        /// whether it is gone.
        func close() -> Bool {
            transport?.kill()
            let gone = ToolRuntimeSupport.wait { self.isGone }
            host.remove(ExternalToolTests.id)
            try? FileManager.default.removeItem(at: folder)
            return gone
        }
    }

    /// Quit against real programs. The host's two waits are 0.4 and 0.2
    /// seconds here where the app's are 2 and 1, so that no test sits out
    /// the app's own; the code that waits is the same.
    static func quittingRealPrograms(_ suite: TestSuite) {
        guard let fixture = ToolProcessTests.fixture else {
            suite.expect(false, "the fixture tool is there for the host to quit with")
            return
        }
        var short = ToolLimits()
        short.goodbyeWait = 0.4
        short.endWait = 0.2

        let polite = RealBench(program: fixture)
        if polite.start() {
            let took = polite.quit()
            suite.expect(took < 1 && polite.tool.hasEnded && polite.status() == 0,
                         "at quit a real tool that leaves on goodbye costs well under a second, and needs no signal")
        } else {
            suite.expect(false, "the tool starts, to be quit politely")
        }
        let politeGone = polite.close()

        let stubborn = RealBench(program: fixture, limits: short)
        if stubborn.start(), stubborn.run("stubborn", untilLogged: "stubborn") {
            let took = stubborn.quit()
            suite.expect(took >= 0.6 && took < 3 && stubborn.status() == 128 + SIGKILL,
                         "at quit a real tool that ignores goodbye and being asked to end is killed, "
                             + "and the host waited its two waits and no longer")
        } else {
            suite.expect(false, "the tool starts, to be stubborn at quit")
        }
        let stubbornGone = stubborn.close()

        // The tool writes without end, so the reading queue is handing the
        // main thread lines, or waiting to, when quit comes. The host's
        // wait must not need that queue: the main thread is not turning.
        let flooding = RealBench(program: fixture, limits: short)
        if flooding.start(), flooding.run("flood", untilLogged: "flood", count: 400) {
            let took = flooding.quit()
            suite.expect(took >= 0.4 && took < 3 && flooding.tool.hasEnded && flooding.status() == 128 + SIGTERM,
                         "at quit a real tool in the middle of a flood is ended within the host's waits, "
                             + "though the main thread reads none of what it writes")
        } else {
            suite.expect(false, "the tool starts, to flood at quit")
        }
        suite.expect(flooding.close() && politeGone && stubbornGone, "and no process is left by any of them")
    }

    static func listing(_ suite: TestSuite) {
        let bench = Bench()
        let tool = StandIn()
        let registry = ToolRegistry(isAvailable: { _ in true })
        bench.host.add(tool, manifest: deploys.manifest)
        do {
            try registry.register(deploys, host: { bench.host })
        } catch {
            suite.expect(false, "an outside tool is listed in the registry")
        }
        suite.expect(registry.commands(on: .commandBar).map(\.id) == [copy]
                         && registry.commands(on: .radial).map(\.id) == [copy]
                         && registry.commands(on: .shortcut).map(\.id) == [copy]
                         && registry.commands(on: .quickPanel).isEmpty,
                     "its commands are offered on the surfaces its manifest names, and no other")
        suite.expect(registry.name(for: id, language: .fr) == "Déploiements"
                         && registry.name(for: id, language: .ptBR) == "Deploys"
                         && registry.title(for: copy, language: .fr) == "Copy latest deploy",
                     "its name and titles are the author's words in the person's language, English where there are none")
        suite.expect(registry.canRun(copy) && tool.started == 0, "whether a command can run is the host's answer")
        tool.runnable = false
        suite.expect(!registry.canRun(copy) && !registry.run(copy) && tool.ran.isEmpty,
                     "a command the tool says cannot run is not run")
        tool.runnable = true
        suite.expect(registry.run(copy) && tool.ran == [copy], "and one that can is run through the host")
        var refused = false
        do {
            try registry.register(deploys, host: { bench.host })
        } catch {
            refused = error as? ToolRegistry.RegistrationError == .duplicateTool(id)
        }
        suite.expect(refused, "a tool cannot be listed twice")
    }

    /// The island's Tools grid holds the app's own tools and outside tools
    /// with no island page; an outside tool with one keeps its actions on
    /// that page, and on every other surface it asks for.
    static func toolsGrid(_ suite: TestSuite) {
        let bench = Bench()
        let registry = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: registry)
        let builtinTiles = registry.commands(on: .quickPanel).map(\.id)
        let everywhere = #"[{"id": "go", "title": {"en": "Go"}, "surfaces": ["quickPanel", "commandBar", "radial"]}]"#
        func outside(_ id: String, panels: String?) -> ExternalToolManifest? {
            let drawn = panels.map { #", "protocol": "2", "contributes": {"commands": \#(everywhere), "panels": \#($0)}"# }
            return ExternalToolManifestTests.tool(#"{"id": "\#(id)""# + (drawn ?? #", "contributes": {"commands": \#(everywhere)}"#) + "}")
        }
        let paged = outside("com.acme.paged", panels: #"[{"id": "p", "title": {"en": "P"}, "placement": "island"}]"#)
        let windowed = outside("com.acme.windowed", panels: #"[{"id": "w", "title": {"en": "W"}, "placement": "window"}]"#)
        let headless = outside("com.acme.headless", panels: nil)
        guard let paged, let windowed, let headless else {
            return suite.expect(false, "the three outside tools' manifests are read")
        }
        do {
            for tool in [paged, windowed, headless] { try registry.register(tool, host: { bench.host }) }
        } catch {
            return suite.expect(false, "the three outside tools are listed, got \(error)")
        }
        func go(_ tool: ExternalToolManifest) -> CommandID { CommandID(tool: tool.manifest.id, name: "go")! }
        let grid = registry.extraCommands(on: .quickPanel).map(\.id)
        suite.expect(registry.hasIslandPage(paged.manifest.id) && !registry.hasIslandPage(windowed.manifest.id)
                         && !registry.hasIslandPage(headless.manifest.id),
                     "only a manifest with an island panel gives a tool an island page")
        suite.expect(!grid.contains(go(paged)),
                     "an outside tool with an island page has no tile in the Tools grid, though it asks for one")
        suite.expect(grid == [go(windowed), go(headless)],
                     "an outside tool with no island page keeps its tile, a window or Settings panel or none")
        suite.expect(registry.extraCommands(on: .commandBar).map(\.id) == [go(paged), go(windowed), go(headless)]
                         && registry.extraCommands(on: .radial).map(\.id) == [go(paged), go(windowed), go(headless)],
                     "the command bar and the wheel still offer every outside tool's command")
        suite.expect(registry.commands(on: .quickPanel).filter { $0.id.tool.isBundledForm }.map(\.id) == builtinTiles
                         && !builtinTiles.isEmpty
                         && !builtinTiles.contains { registry.hasIslandPage($0.tool) },
                     "the app's own tiles are untouched")
        do {
            try registry.setHasIslandPage(for: builtinTiles[0].tool)
        } catch {
            suite.expect(false, "a registered built-in tool can be named, got \(error)")
        }
        suite.expect(!registry.hasIslandPage(builtinTiles[0].tool), "and none of the app's own tools is ever noted as one")

        registry.unregister(paged.manifest.id)
        let plain = ExternalToolManifestTests.tool(#"{"id": "com.acme.paged", "contributes": {"commands": \#(everywhere)}}"#)
        do {
            if let plain { try registry.register(plain, host: { bench.host }) }
        } catch {
            suite.expect(false, "the tool lists again once removed, got \(error)")
        }
        suite.expect(plain != nil && !registry.hasIslandPage(paged.manifest.id)
                         && registry.extraCommands(on: .quickPanel).map(\.id).contains(go(paged)),
                     "removing a tool forgets its island page: updated to have none, its tile is back")
    }
}
