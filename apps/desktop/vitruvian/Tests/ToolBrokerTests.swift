// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import AppKit
import VitruvianCore
import VitruvianServices

/// The capability broker against services that record what they were asked
/// and do nothing.
@MainActor
enum ToolBrokerTests {
    static func run(_ suite: TestSuite) {
        checks(suite)
        smallCapabilities(suite)
        processes(suite)
        preferences(suite)
        messages(suite)
        oneLook(suite)
        clipboard(suite)
        host(suite)
        runRule(suite)
        grants(suite)
        hostRunsTools(suite)
        portManager(suite)
        manifestsAgree(suite)
    }

    /// What the broker is told about the world, and what it reported.
    final class World {
        var installed = true
        var granted: Set<AppPermission> = Set(AppPermission.allCases)
        var allowed = true
        var undeclared: [Capability] = []
    }

    static func manifest(_ capabilities: [Capability], id: String = "portManager") -> ToolManifest {
        ToolManifest(tool: ToolDescriptor(id: ToolID(id)!, name: id, symbol: "network",
                                          commands: [])!,
                     group: .tools,
                     capabilities: capabilities.map { CapabilityRequest($0, reason: "test")! },
                     preferences: [], activation: [.onShown], enabledBy: nil)!
    }

    static func checks(_ suite: TestSuite) {
        let world = World()
        let broker = bench(world: world)
        let tool = manifest([.open])

        suite.expect(broker.refusal(of: .open, for: tool) == nil,
                     "a declared capability of an installed tool is allowed")
        suite.expect(broker.refusal(of: .processes, for: tool) == .notDeclared(.processes)
                         && world.undeclared == [.processes],
                     "a capability the manifest does not list is refused, and reported as a mistake")
        world.installed = false
        suite.expect(broker.refusal(of: .open, for: tool) == .notInstalled,
                     "a tool removed in the hub is refused")
        suite.expect(broker.refusal(of: .processes, for: tool) == .notDeclared(.processes),
                     "not declared is said before not installed")
        world.installed = true
        world.allowed = false
        suite.expect(broker.refusal(of: .open, for: tool) == .unavailable,
                     "a capability the person has not allowed is refused")
    }

    /// Services that record and do nothing.
    final class Recorder {
        var beeps = 0
        var opened: [URL] = []
        var opens = true
        var written: [String] = []
        var writes = true
    }

    /// A broker over `world` whose services only record. A tool's handle
    /// comes from its `services(for:)`.
    static func bench(world: World = World(), recorder: Recorder = Recorder()) -> CapabilityBroker {
        CapabilityBroker(
            environment: .init(isInstalled: { _ in world.installed },
                               isGranted: { world.granted.contains($0) },
                               allows: { _, _ in world.allowed },
                               reportUndeclared: { _, capability in world.undeclared.append(capability) }),
            backings: .init(
                notify: .init(beep: { recorder.beeps += 1 }),
                open: .init(open: { recorder.opened.append($0); return recorder.opens }),
                clipboard: .init(write: { text, completion in
                    recorder.written.append(text)
                    completion(recorder.writes)
                }),
                processes: .inert))
    }

    static func smallCapabilities(_ suite: TestSuite) {
        let recorder = Recorder()
        let world = World()
        let broker = bench(world: world, recorder: recorder)
        let all = broker.services(for: manifest([.notify, .open, .clipboardWrite]))
        let link = URL(string: "http://localhost:3000")!

        suite.expect(all.notify.beep() == nil && recorder.beeps == 1, "a tool that asks for it can beep")
        suite.expect(all.open.url(link) == .success(true) && recorder.opened == [link],
                     "a tool that asks for it can open a link")
        recorder.opens = false
        suite.expect(all.open.url(link) == .success(false), "a link the system would not open says so")
        var copied: Bool?
        suite.expect(all.clipboard.write("8080") { copied = $0 } == nil && recorder.written == ["8080"]
                         && copied == true,
                     "a tool that asks for it can put text on the clipboard, and hears how it went")

        let none = broker.services(for: manifest([]))
        let before = (recorder.beeps, recorder.opened.count, recorder.written.count)
        var heard = false
        suite.expect(none.notify.beep() == .notDeclared(.notify)
                         && none.open.url(link) == .failure(.notDeclared(.open))
                         && none.clipboard.write("x") { _ in heard = true } == .notDeclared(.clipboardWrite)
                         && (recorder.beeps, recorder.opened.count, recorder.written.count) == before
                         && !heard,
                     "a refused call does no work and calls nothing back")
        world.installed = false
        suite.expect(all.notify.beep() == .notInstalled && recorder.beeps == before.0,
                     "a tool removed in the hub can no longer beep")
    }

    static func processes(_ suite: TestSuite) {
        final class Kills {
            var available = true
            var ended: [(pid: pid_t, name: String, startedAt: UInt64, force: Bool)] = []
            var protected: Set<pid_t> = [1]
        }
        let kills = Kills()
        let world = World()
        func services(_ capabilities: [Capability]) -> ToolServices {
            CapabilityBroker(
                environment: .init(isInstalled: { _ in world.installed },
                                   isGranted: { world.granted.contains($0) },
                                   allows: { _, _ in world.allowed },
                                   reportUndeclared: { _, _ in }),
                backings: .init(
                    notify: .init(beep: {}), open: .init(open: { _ in true }),
                    clipboard: .init(write: { _, _ in }),
                    processes: .init(
                        startTime: { $0 == 42 ? 7 : nil },
                        listeningSocketsReport: { (0, "p42\n") },
                        terminationAvailable: { kills.available },
                        isProtected: { pid, _ in kills.protected.contains(pid) },
                        terminate: { pid, name, startedAt, force, completion in
                            kills.ended.append((pid, name, startedAt, force))
                            completion()
                        })))
                .services(for: manifest(capabilities))
        }
        let tool = services([.processes])

        guard case .success(let scanner) = tool.processes.scanner() else {
            suite.expect(false, "a tool that asks for it gets a scanner")
            return
        }
        suite.expect(scanner.startTime(42) == 7 && scanner.startTime(43) == nil
                         && scanner.listeningSocketsReport().output == "p42\n",
                     "the scanner reads start times and the listening sockets")
        if case .failure(let refusal) = services([]).processes.scanner() {
            suite.expect(refusal == .notDeclared(.processes), "a tool that did not ask gets no scanner")
        } else {
            suite.expect(false, "a tool that did not ask gets no scanner")
        }

        var finished = 0
        suite.expect(tool.processes.canTerminate
                         && tool.processes.terminate(pid: 42, name: "node", startedAt: 7, force: true) { finished += 1 } == nil
                         && kills.ended.count == 1 && kills.ended[0].pid == 42 && kills.ended[0].name == "node"
                         && kills.ended[0].startedAt == 7 && kills.ended[0].force && finished == 1,
                     "ending a process passes its identity through and reports back")
        suite.expect(tool.processes.isProtected(pid: 1, name: "launchd") && !tool.processes.isProtected(pid: 42, name: "node"),
                     "the host says which processes may not be ended")

        kills.available = false
        suite.expect(!tool.processes.canTerminate
                         && tool.processes.terminate(pid: 42, name: "node", startedAt: 7, force: false) { finished += 1 } == .unavailable
                         && kills.ended.count == 1 && finished == 1,
                     "without the Kill process feature, ending a process is not offered and does nothing")
        kills.available = true
        let none = services([])
        suite.expect(!none.processes.canTerminate && none.processes.isProtected(pid: 42, name: "node")
                         && none.processes.terminate(pid: 42, name: "node", startedAt: 7, force: false) {} == .notDeclared(.processes)
                         && kills.ended.count == 1,
                     "a tool that did not ask can end nothing, and is told every process is protected")
    }

    /// Saved values a fake reads, and what it was asked. Only the test's own
    /// thread touches it.
    nonisolated final class PreferenceBox: @unchecked Sendable {
        var values: [String: Any] = [:]
        var reads: [String] = []
        var undeclared: [String] = []
    }

    static func preferences(_ suite: TestSuite) {
        let box = PreferenceBox()
        let world = World()
        let broker = CapabilityBroker(
            environment: .init(isInstalled: { _ in world.installed },
                               isGranted: { world.granted.contains($0) },
                               allows: { _, _ in world.allowed },
                               reportUndeclared: { _, capability in world.undeclared.append(capability) }),
            backings: .init(
                notify: .init(beep: {}), open: .init(open: { _ in true }),
                clipboard: .init(write: { _, _ in }), processes: .inert,
                storage: .init(read: { key in
                    box.reads.append(key)
                    return box.values[key]
                }, undeclaredKey: { box.undeclared.append($0) })))
        let declared = ToolManifest(
            tool: ToolDescriptor(id: ToolID("urlCleaner")!, name: "urlCleaner", symbol: "link", commands: [])!,
            group: .tools, capabilities: [CapabilityRequest(.storage, reason: "test")!],
            preferences: [PreferenceDeclaration(key: DefaultsKey.urlCleanerEnabled, default: .bool(false)),
                          PreferenceDeclaration(key: DefaultsKey.urlCleanerCustomParameters, default: .string(""))],
            activation: [.onLaunch], enabledBy: DefaultsKey.urlCleanerEnabled)!

        guard case .success(let reader) = broker.services(for: declared).storage.reader() else {
            suite.expect(false, "a tool that asks for it gets a reader for its preferences")
            return
        }
        suite.expect(reader.value(for: Preferences.urlCleanerEnabled) == false
                         && box.reads == [DefaultsKey.urlCleanerEnabled],
                     "a preference nothing saved reads as its default")
        box.values[DefaultsKey.urlCleanerEnabled] = true
        box.values[DefaultsKey.urlCleanerCustomParameters] = "ref"
        suite.expect(reader.value(for: Preferences.urlCleanerEnabled)
                         && reader.value(for: Preferences.urlCleanerCustomParameters) == "ref",
                     "a tool reads the preferences its manifest declares")
        box.values[DefaultsKey.urlCleanerCustomParameters] = 7
        suite.expect(reader.value(for: Preferences.urlCleanerCustomParameters) == "",
                     "a saved value of another type reads as the default")
        let before = box.reads.count
        suite.expect(reader.value(for: Preferences.urlCleanerSiteParameters) == "" && box.reads.count == before
                         && box.undeclared == [DefaultsKey.urlCleanerSiteParameters],
                     "a preference the manifest does not declare is not read, and is reported as a mistake")

        if case .failure(let refusal) = broker.services(for: manifest([])).storage.reader() {
            suite.expect(refusal == .notDeclared(.storage) && box.reads.count == before,
                         "a tool that did not ask gets no reader")
        } else {
            suite.expect(false, "a tool that did not ask gets no reader")
        }
        world.installed = false
        if case .failure(let refusal) = broker.services(for: declared).storage.reader() {
            suite.expect(refusal == .notInstalled, "a tool removed in the hub gets no reader")
        } else {
            suite.expect(false, "a tool removed in the hub gets no reader")
        }
    }

    static func messages(_ suite: TestSuite) {
        var said: [String] = []
        let broker = CapabilityBroker(
            environment: .init(isInstalled: { _ in true }, isGranted: { _ in true }, allows: { _, _ in true },
                               reportUndeclared: { _, _ in }),
            backings: .init(
                notify: .init(beep: {}, hud: { icon, message in said.append("\(icon): \(message)") }),
                open: .init(open: { _ in true }), clipboard: .init(write: { _, _ in }), processes: .inert))
        suite.expect(broker.services(for: manifest([.notify])).notify.hud(icon: "link", message: "Cleaned") == nil
                         && said == ["link: Cleaned"],
                     "a tool that asks for it can say something on screen")
        suite.expect(broker.services(for: manifest([])).notify.hud(icon: "link", message: "x") == .notDeclared(.notify)
                         && said.count == 1,
                     "a refused message is not shown")
    }

    final class ProbeTool: BundledTool {
        static let manifest = ToolBrokerTests.manifest([.notify])
        static var built = 0
        let services: ToolServices
        var starts = 0
        var stops = 0
        init(services: ToolServices) {
            self.services = services
            Self.built += 1
        }
        func start() { starts += 1 }
        func stop() {
            stops += 1
            ToolBrokerTests.events.append("portManager stop")
        }
        func run(_ command: CommandID) {}
        func canRun(_ command: CommandID) -> Bool { false }
    }

    static func host(_ suite: TestSuite) {
        let recorder = Recorder()
        ProbeTool.built = 0
        let host = ToolHost(broker: bench(recorder: recorder))
        suite.expect(host.built.isEmpty && ProbeTool.built == 0, "a tool nobody asked for is never built")

        let first = host.tool(ProbeTool.self)
        let second = host.tool(ProbeTool.self)
        suite.expect(first === second && ProbeTool.built == 1 && host.built == [ProbeTool.manifest.id],
                     "everyone who asks for a tool gets the same one")
        suite.expect(first.services.notify.beep() == nil && recorder.beeps == 1,
                     "a tool is handed services checked against its own manifest")
        suite.expect(first.services.open.url(URL(string: "http://localhost")!) == .failure(.notDeclared(.open)),
                     "and against nothing more")

        host.stopAll()
        host.stopAll()
        suite.expect(first.stops == 2 && ProbeTool.built == 1, "quitting stops every built tool, and builds none")
    }

    /// What the probes below were asked, in order.
    static var events: [String] = []

    /// A tool with a switch and a command, to watch the host start, stop
    /// and run it.
    final class LifecycleProbe: BundledTool {
        static let probe = CommandID("homebrew/probe")!
        static let manifest = ToolManifest(
            tool: ToolDescriptor(id: ToolID("homebrew")!, name: "homebrew", symbol: "shippingbox",
                                 commands: [CommandDescriptor(id: probe, title: "probe", symbol: "shippingbox",
                                                              surfaces: [])!])!,
            group: .tools, capabilities: [],
            preferences: [PreferenceDeclaration(key: "probeSwitch", default: .bool(false))],
            activation: [.onLaunch, .onCommand], enabledBy: "probeSwitch")!
        static var built = 0
        init(services: ToolServices) { Self.built += 1 }
        func start() { ToolBrokerTests.events.append("start") }
        func stop() { ToolBrokerTests.events.append("stop") }
        func run(_ command: CommandID) { ToolBrokerTests.events.append("run \(command.name)") }
        func canRun(_ command: CommandID) -> Bool { true }
    }

    /// The rule itself, against every combination of what it is told. A
    /// tool with no switch is `nil`.
    static func runRule(_ suite: TestSuite) {
        for installed in [false, true] {
            for switchedOn in [nil, false, true] as [Bool?] {
                for holdsGrants in [false, true] {
                    let runs = installed && switchedOn != false && holdsGrants
                    let name = switchedOn.map { "switched \($0 ? "on" : "off")" } ?? "no switch"
                    suite.expect(ToolHost.shouldRun(installed: installed, switchedOn: switchedOn,
                                                    holdsGrants: holdsGrants) == runs,
                                 "installed \(installed), \(name), grants held \(holdsGrants): the tool "
                                     + (runs ? "should run" : "should not run"))
                }
            }
        }
        var asked: [String] = []
        let stopsEarly = ToolHost.shouldRun(installed: false,
                                            switchedOn: { asked.append("switch"); return true }(),
                                            holdsGrants: { asked.append("grants"); return true }())
        suite.expect(!stopsEarly && asked.isEmpty,
                     "a tool that is not installed is not asked about its switch or its grants")
    }

    /// A tool that cannot start without Accessibility. It has no switch, so
    /// only the grant decides.
    final class NeedsGrantProbe: BundledTool {
        static let manifest = ToolManifest(
            tool: ToolDescriptor(id: ToolID("wallpaper")!, name: "wallpaper", symbol: "photo", commands: [])!,
            group: .tools, capabilities: [CapabilityRequest(.keystrokes, reason: "test")!],
            preferences: [], activation: [.onLaunch], enabledBy: nil)!
        init(services: ToolServices) {}
        func start() { ToolBrokerTests.events.append("needs start") }
        func stop() { ToolBrokerTests.events.append("needs stop") }
        func run(_ command: CommandID) {}
        func canRun(_ command: CommandID) -> Bool { false }
    }

    /// A tool that says it starts without Accessibility, and asks later.
    final class AsksLaterProbe: BundledTool {
        static let manifest = ToolManifest(
            tool: ToolDescriptor(id: ToolID("mediaTools")!, name: "mediaTools", symbol: "film", commands: [])!,
            group: .tools,
            capabilities: [CapabilityRequest(.keystrokes, reason: "test", startsWithoutGrant: true)!],
            preferences: [], activation: [.onLaunch], enabledBy: nil)!
        init(services: ToolServices) {}
        func start() { ToolBrokerTests.events.append("later start") }
        func stop() { ToolBrokerTests.events.append("later stop") }
        func run(_ command: CommandID) {}
        func canRun(_ command: CommandID) -> Bool { false }
    }

    /// The first capability that rides on a macOS grant: the broker's
    /// refusal, where the app's broker gets its answer, and the run rule's
    /// grant clause through the host.
    static func grants(_ suite: TestSuite) {
        let world = World()
        let broker = bench(world: world)
        let typing = manifest([.keystrokes, .notify], id: "wallpaper")

        world.granted = []
        suite.expect(broker.refusal(of: .keystrokes, for: typing) == .notGranted(.accessibility),
                     "a capability that rides on a macOS grant is refused without it")
        suite.expect(broker.refusal(of: .notify, for: typing) == nil,
                     "a capability that rides on nothing is not held back by another's grant")
        world.granted = [.accessibility]
        suite.expect(broker.refusal(of: .keystrokes, for: typing) == nil,
                     "the grant is asked about at every call: given while the app runs, it holds from the next one")
        world.granted = [.screenRecording]
        suite.expect(broker.refusal(of: .keystrokes, for: typing) == .notGranted(.accessibility),
                     "and taken away, it is missed at the next one")
        world.installed = false
        suite.expect(broker.refusal(of: .keystrokes, for: typing) == .notInstalled,
                     "not installed is said before a missing grant")
        world.installed = true
        world.allowed = false
        suite.expect(broker.refusal(of: .keystrokes, for: typing) == .notGranted(.accessibility),
                     "a missing grant is said before what the person allows")
        world.allowed = true

        // The app's own broker, with the two questions it puts to macOS
        // answered here.
        var accessibility = false
        var screen = false
        let live = CapabilityBroker.Environment.reading(accessibility: { accessibility },
                                                        screenRecording: { screen })
        suite.expect(!live.isGranted(.accessibility) && !live.isGranted(.screenRecording)
                         && live.isGranted(.notifications),
                     "the app's broker asks about the two grants the app watches, and takes the others as given")
        accessibility = true
        suite.expect(live.isGranted(.accessibility) && !live.isGranted(.screenRecording),
                     "it asks at the moment of the call: a grant holds the instant it is given, with no hop and no poll to wait for")
        accessibility = false
        screen = true
        suite.expect(!live.isGranted(.accessibility) && live.isGranted(.screenRecording),
                     "each grant is asked of its own source")

        // The run rule's grant clause, through the host.
        let needs = NeedsGrantProbe.manifest.id
        let later = AsksLaterProbe.manifest.id
        for granted in [false, true] {
            events = []
            world.granted = granted ? [.accessibility] : []
            let host = ToolHost(broker: broker, tools: [NeedsGrantProbe.self, AsksLaterProbe.self])
            host.sync(needs)
            host.sync(later)
            suite.expect(events == (granted ? ["needs start", "later start"] : ["later start"])
                             && host.built == (granted ? [needs, later] : [later]),
                         "Accessibility \(granted): a tool that needs it " + (granted ? "starts" : "waits")
                             + ", and a tool that says it starts without it starts")
        }

        events = []
        world.granted = []
        let host = ToolHost(broker: broker, tools: [NeedsGrantProbe.self, AsksLaterProbe.self])
        func decide() {
            host.sync(needs)
            host.sync(later)
        }
        decide()
        world.granted = [.accessibility]
        decide()
        suite.expect(events == ["later start", "needs start", "later start"] && host.running == [later, needs],
                     "a grant given while the app runs starts the tool that waited for it, at the next decision")
        world.granted = []
        decide()
        suite.expect(events.suffix(2) == ["needs stop", "later start"] && host.running == [later],
                     "a grant taken away stops the tool that needs it, and leaves the other running")
        suite.expect(broker.refusal(of: .keystrokes, for: AsksLaterProbe.manifest) == .notGranted(.accessibility),
                     "starting without the grant does not open the capability: each call is still refused")

        // Suspending.
        events = []
        host.suspend(later)
        host.suspend(needs)
        host.suspend(ToolID("screenshot")!)
        suite.expect(events == ["later stop", "needs stop"] && host.running.isEmpty,
                     "suspending stops a built tool at once, whatever the run rule says")
        decide()
        suite.expect(events.suffix(1) == ["later start"] && host.running == [later],
                     "and the next decision starts it again")
        let unbuilt = ToolHost(broker: broker, tools: [AsksLaterProbe.self])
        unbuilt.suspend(later)
        suite.expect(unbuilt.built.isEmpty, "suspending a tool that was never built builds nothing")
    }

    static func hostRunsTools(_ suite: TestSuite) {
        let rig = URLCleanerTests.CleanerRig()
        defer { rig.close() }
        let feature = AppFeature.homebrew
        let id = LifecycleProbe.manifest.id
        let command = LifecycleProbe.probe
        func set(installed: Bool, on: Bool) {
            rig.defaults.set(installed, forKey: feature.availabilityKey)
            rig.defaults.set(on, forKey: "probeSwitch")
        }

        // The run rule, against every combination.
        for installed in [false, true] {
            for on in [false, true] {
                LifecycleProbe.built = 0
                events = []
                let host = ToolHost(broker: rig.broker(), tools: [LifecycleProbe.self])
                set(installed: installed, on: on)
                host.sync(id)
                let runs = installed && on
                suite.expect(host.shouldRun(LifecycleProbe.manifest) == runs && events == (runs ? ["start"] : [])
                                 && LifecycleProbe.built == (runs ? 1 : 0) && host.running == (runs ? [id] : []),
                             "installed \(installed), switched on \(on): the host "
                                 + (runs ? "starts the tool" : "leaves the tool unbuilt"))
            }
        }

        LifecycleProbe.built = 0
        ProbeTool.built = 0
        events = []
        let host = ToolHost(broker: rig.broker(), tools: [LifecycleProbe.self, ProbeTool.self])
        rig.defaults.set(false, forKey: AppFeature.portManager.availabilityKey)
        set(installed: true, on: false)
        host.sync(ProbeTool.manifest.id)
        host.sync(id)
        host.sync(ToolID("screenshot")!)
        host.stopAll()
        suite.expect(events.isEmpty && host.built.isEmpty && LifecycleProbe.built == 0 && ProbeTool.built == 0,
                     "a tool that should not run and was never built is not built to be stopped")
        rig.defaults.set(true, forKey: AppFeature.portManager.availabilityKey)
        set(installed: true, on: true)
        host.sync(ProbeTool.manifest.id)
        host.sync(id)
        host.sync(id)
        suite.expect(events == ["start", "start"] && host.running == [ProbeTool.manifest.id, id]
                         && LifecycleProbe.built == 1 && host.tool(ProbeTool.self).starts == 1,
                     "deciding again while a tool runs starts the same tool again, as a sync always did")
        set(installed: true, on: false)
        host.sync(id)
        host.sync(id)
        suite.expect(events.suffix(2) == ["stop", "stop"] && host.running == [ProbeTool.manifest.id],
                     "switching a tool off stops it, and stopping twice is safe")
        set(installed: true, on: true)
        host.sync(id)
        events = []
        host.stopAll()
        suite.expect(events == ["stop", "portManager stop"] && host.running.isEmpty && LifecycleProbe.built == 1,
                     "quitting stops what is running, last started first, and builds nothing")

        // Commands.
        set(installed: true, on: false)
        events = []
        suite.expect(host.canRun(command),
                     "a command can run while the tool's switch is off: the switch is for background work")
        host.run(command)
        suite.expect(events == ["run probe"], "the host hands a command to its tool")
        suite.expect(!host.canRun(CommandID("homebrew/unknown")!) && !host.canRun(CommandID("screenshot/capture")!),
                     "the host runs only a command that a manifest it holds declares")

        // The registry runs a tool's command through the host, which it
        // reaches only when a command is run or asked about.
        let registry = ToolRegistry(isAvailable: { $0.isAvailable(in: rig.defaults) })
        var reached = 0
        BuiltinTools.install(into: registry, tools: [LifecycleProbe.self, ProbeTool.self], host: {
            reached += 1
            return host
        })
        suite.expect(reached == 0 && LifecycleProbe.built == 1 && events == ["run probe"],
                     "installing the built-in tools reaches for no host and builds no tool")
        suite.expect(registry.tool(id) == LifecycleProbe.manifest.tool && registry.hasHandler(for: command)
                         && registry.name(for: id, language: .systemDefault)
                             == feature.hubTitle(Strings.localized(.systemDefault), hub: FeatureStrings.hub(.systemDefault)),
                     "a tool the host holds is registered as its manifest describes it, under the hub's name")
        suite.expect(ToolSurface.allCases.allSatisfy { surface in
            !registry.commands(on: surface).contains { $0.id == command }
        }, "a command that asks for no surface is listed on none")
        suite.expect(reached == 0, "listing commands reaches for no host")
        suite.expect(registry.run(command) && events == ["run probe", "run probe"] && reached > 0,
                     "the registry runs a tool's command through the host")
        set(installed: false, on: true)
        host.run(command)
        reached = 0
        suite.expect(!host.canRun(command) && !registry.run(command) && events == ["run probe", "run probe"]
                         && reached == 0,
                     "a tool removed in the hub runs no command, and the registry says so before asking the host")
    }

    static func portManager(_ suite: TestSuite) {
        final class Kills {
            var available = true
            var ended: [(pid: pid_t, startedAt: UInt64, force: Bool)] = []
            var finish: [@MainActor @Sendable () -> Void] = []
        }
        let kills = Kills()
        let recorder = Recorder()
        let reports = PortManagerRefreshTests.Processes()
        func broker(installed: Bool, reports: PortManagerRefreshTests.Processes) -> CapabilityBroker {
            CapabilityBroker(
                environment: .init(isInstalled: { _ in installed }, isGranted: { _ in true }, allows: { _, _ in true },
                                   reportUndeclared: { _, capability in
                                       suite.expect(false, "the Port manager used \(capability.rawValue) without declaring it")
                                   }),
                backings: .init(
                    notify: .init(beep: { recorder.beeps += 1 }),
                    open: .init(open: { recorder.opened.append($0); return recorder.opens }),
                    clipboard: .init(write: { text, completion in
                        recorder.written.append(text)
                        completion(recorder.writes)
                    }),
                    processes: .init(
                        startTime: { reports.current[$0] },
                        listeningSocketsReport: { reports.listing() },
                        terminationAvailable: { kills.available },
                        isProtected: { pid, _ in pid == 1 },
                        terminate: { pid, _, startedAt, force, completion in
                            kills.ended.append((pid, startedAt, force))
                            kills.finish.append(completion)
                        })))
        }
        let tool = ToolHost(broker: broker(installed: true, reports: reports)).tool(PortManagerService.self)
        let stable = PortManagerEntry(port: 3000, protocolName: "TCP", address: "*", pid: 42,
                                      processName: "node", startedAt: 7)
        let unstable = PortManagerEntry(port: 3001, protocolName: "TCP", address: "*", pid: 43,
                                        processName: "node", startedAt: nil)

        suite.expect(Set(PortManagerService.manifest.capabilities.map(\.capability))
                         == [.processes, .clipboardWrite, .open, .notify],
                     "the Port manager asks for exactly what it uses")

        // A tool the hub does not hold is refused its scan. Nothing runs, so
        // the fake listing can be read here; `refused` is touched nowhere else.
        let refused = PortManagerRefreshTests.Processes()
        let removed = ToolHost(broker: broker(installed: false, reports: refused)).tool(PortManagerService.self)
        removed.refresh()
        suite.expect(removed.refreshFailed && !removed.isRefreshing && !removed.hasLoadedOnce
                         && removed.entries.isEmpty && refused.calls == 0,
                     "a refused scan reads nothing and ends as a timed-out one does")

        tool.terminate(unstable, force: false)
        suite.expect(kills.ended.isEmpty, "an entry with no stable identity is never ended")
        tool.terminate(stable, force: true)
        suite.expect(kills.ended.count == 1 && kills.ended[0].pid == 42 && kills.ended[0].startedAt == 7
                         && kills.ended[0].force,
                     "ending a process passes its identity and force through")
        // The scan this starts runs on a real background queue, so `reports`
        // is not read from here on: the scan owns it.
        let idle = !tool.isRefreshing
        kills.finish.forEach { $0() }
        suite.expect(idle && tool.isRefreshing, "the list refreshes after a process is ended")

        suite.expect(tool.canTerminate && tool.isProtected(PortManagerEntry(
                         port: 1, protocolName: "TCP", address: "*", pid: 1, processName: "launchd", startedAt: 1))
                         && !tool.isProtected(stable),
                     "the views ask the tool what may be ended")
        kills.available = false
        tool.terminate(stable, force: false)
        suite.expect(!tool.canTerminate && kills.ended.count == 1,
                     "without the Kill process feature nothing is offered and nothing is ended")

        tool.copy("3000")
        suite.expect(recorder.written == ["3000"] && recorder.beeps == 0, "a row copies its value")
        recorder.writes = false
        tool.copy("3001")
        suite.expect(recorder.beeps == 1, "a copy that did not take beeps")
        let link = URL(string: "http://localhost:3000")!
        tool.open(link)
        suite.expect(recorder.opened == [link] && recorder.beeps == 1, "a row opens its port in the browser")
        recorder.opens = false
        tool.open(link)
        suite.expect(recorder.beeps == 2, "a link that would not open beeps")
    }

    /// A manifest and the `AppFeature` it stands beside describe one thing.
    static func manifestsAgree(_ suite: TestSuite) {
        let manifests = [PortManagerService.manifest, URLCleanerService.manifest]
        suite.expect(BundledTools.all.map { $0.manifest.id } == manifests.map(\.id),
                     "every tool the host holds is checked here")
        let registry = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: registry)
        var keys: [String] = []
        for manifest in manifests {
            guard let feature = AppFeature(rawValue: manifest.id.rawValue) else {
                suite.expect(false, "\(manifest.id) names a feature")
                continue
            }
            suite.expect(manifest.group == feature.group && manifest.tool.symbol == feature.symbolName,
                         "\(manifest.id) is filed and drawn as its feature is")
            suite.expect(Set(manifest.capabilities.flatMap(\.capability.ridesOn)) == Set(feature.permissions),
                         "\(manifest.id) needs the macOS grants its feature declares, and no others")
            suite.expect(registry.tool(manifest.id) == manifest.tool,
                         "\(manifest.id) is the tool the registry already holds")
            suite.expect(manifest.preferences.allSatisfy { declared in
                (Defaults.registeredDefaults[declared.key] as? NSObject)
                    == (declared.defaultValue.defaultsValue as? NSObject)
            }, "\(manifest.id) declares each preference with the default the app registers")
            suite.expect((manifest.enabledBy.map { [$0] } ?? []) == feature.enabledKeys,
                         "\(manifest.id) is switched on by the key its feature names")
            suite.expect(FeatureRuntime.actions(for: feature, in: .standard).contains(.tool(manifest.id))
                             == manifest.activation.contains(.onLaunch),
                         "\(manifest.id) is handed to the tool host at launch exactly when its manifest says so")
            keys += manifest.preferences.map(\.key)
        }
        suite.expect(Set(keys).count == keys.count, "no preference belongs to two tools")
    }

    /// What a rule was asked, in order. Only the test's own thread touches
    /// it.
    nonisolated final class RuleLog: @unchecked Sendable {
        var asked: [String] = []
    }

    static func oneLook(_ suite: TestSuite) {
        // Handed to the rules below, which the look calls on this thread.
        nonisolated(unsafe) let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let log = RuleLog()
        func rule(reads: Bool = true, replacement: String? = "clean", drops: Bool = true,
                  during: @escaping @Sendable () -> Void = {}) -> ClipboardRewriteRule {
            ClipboardRewriteRule(
                readsText: { _ in
                    log.asked.append("types")
                    return reads
                },
                replacement: { text in
                    log.asked.append("text \(text)")
                    during()
                    return replacement.map { ClipboardReplacement(text: $0, note: ["n"]) }
                },
                dropsMarkup: { _, text in
                    log.asked.append("markup \(text)")
                    return drops
                })
        }
        func look(_ rule: ClipboardRewriteRule, token: ClipboardPollToken = ClipboardPollToken()) -> ClipboardPoll? {
            log.asked = []
            return ClipboardRewrite.poll(since: -1, token: token, rule: rule, pasteboard: board)
        }
        func copy(_ text: String, html: String? = nil) {
            board.clearContents()
            board.setString(text, forType: .string)
            if let html { board.setString(html, forType: .html) }
        }

        copy("dirty")
        var result = look(rule(reads: false))
        suite.expect(result?.replaced == nil && log.asked == ["types"] && board.string(forType: .string) == "dirty",
                     "a rule that says no to the types is never shown the text")
        result = look(rule(replacement: nil))
        suite.expect(result?.replaced == nil && log.asked == ["types", "text dirty"],
                     "a rule that offers nothing leaves the copy alone")

        copy("dirty", html: "<b>dirty</b>")
        result = look(rule(replacement: nil))
        suite.expect(log.asked == ["types", "text dirty"], "the HTML is not read for a copy the rule leaves alone")
        result = look(rule(drops: false))
        suite.expect(result?.replaced == nil && log.asked == ["types", "text dirty", "markup dirty"]
                         && board.string(forType: .html) != nil,
                     "a rule that will not drop the HTML leaves the copy alone")
        result = look(rule())
        suite.expect(result?.replaced == ClipboardReplacement(text: "clean", note: ["n"])
                         && board.string(forType: .string) == "clean" && board.string(forType: .URL) == "clean"
                         && board.string(forType: .html) == nil && result?.changeCount == board.changeCount,
                     "a replacement is written as text and as a link, and the look answers with the count after it")

        copy("dirty")
        result = look(rule(during: {
            board.clearContents()
            board.setString("other", forType: .string)
        }))
        suite.expect(result?.replaced == nil && board.string(forType: .string) == "other",
                     "a copy that changed while the rule was deciding is not overwritten")

        copy("dirty")
        let token = ClipboardPollToken()
        result = look(rule(during: { token.cancel() }), token: token)
        suite.expect(result?.replaced == nil && board.string(forType: .string) == "dirty",
                     "a look called off while the rule was deciding writes nothing")

        board.clearContents()
        board.writeObjects(["a" as NSString, "b" as NSString])
        result = look(rule())
        suite.expect(result?.replaced == nil && log.asked == ["types"] && board.pasteboardItems?.count == 2,
                     "a copy of several items is not read")
    }

    static func clipboard(_ suite: TestSuite) {
        let rig = URLCleanerTests.CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: false)
        rig.defaults.set(true, forKey: AppFeature.portManager.availabilityKey)
        let broker = rig.broker()
        let tool = broker.services(for: manifest([.clipboardRead, .clipboardWrite, .clipboardRewrite],
                                                 id: "urlCleaner")).clipboard
        let other = broker.services(for: manifest([.clipboardRead, .clipboardRewrite])).clipboard
        let none = broker.services(for: manifest([], id: "urlCleaner")).clipboard
        // Marks whatever is copied, every time it is asked: a watch that
        // took its own rewrite for a new copy would mark it twice.
        let mark = ClipboardRewriteRule(readsText: { _ in true },
                                        replacement: { ClipboardReplacement(text: $0 + "!", note: [$0]) },
                                        dropsMarkup: { _, _ in true })
        let never = ClipboardRewriteRule(readsText: { _ in false }, replacement: { _ in nil },
                                         dropsMarkup: { _, _ in true })
        var heard: [String] = []

        suite.expect(none.readText { _ in heard.append("read") } == .notDeclared(.clipboardRead)
                         && none.writeLink("x") { heard.append("wrote") } == .notDeclared(.clipboardWrite)
                         && none.rewriteLinks(rule: mark) { _ in heard.append("rewrote") } == .notDeclared(.clipboardRewrite)
                         && rig.lane.isEmpty && rig.started.isEmpty && heard.isEmpty,
                     "a refused clipboard call does no work and calls nothing back")
        let rewriteOnly = broker.services(for: manifest([.clipboardRewrite], id: "urlCleaner")).clipboard
        suite.expect(rewriteOnly.rewriteLinks(rule: mark) { _ in } == .notDeclared(.clipboardRead) && rig.started.isEmpty,
                     "watching reads what it rewrites, so it needs both capabilities")

        rig.copy("hello")
        var texts: [String?] = []
        suite.expect(tool.readText { texts.append($0) } == nil && texts.isEmpty && rig.lane.count == 1,
                     "reading waits for the clipboard lane")
        rig.settle()
        rig.board.clearContents()
        tool.readText { texts.append($0) }
        rig.settle()
        suite.expect(texts == ["hello", nil],
                     "a tool that asks for it reads the clipboard's text, and nothing from an empty one")

        var wrote = 0
        tool.writeLink("https://example.com/x") { wrote += 1 }
        rig.settle()
        suite.expect(rig.text == "https://example.com/x" && rig.board.string(forType: .URL) == "https://example.com/x"
                         && rig.board.string(forType: .source) == Bundle.main.bundleIdentifier && wrote == 1,
                     "a link a tool writes is on the clipboard as text and as a link, signed as the app's own")

        rig.copy("abc")
        suite.expect(tool.rewriteLinks(rule: mark) { heard.append($0.text) } == nil
                         && rig.started.count == 1 && rig.started[0].interval == ClipboardWatcher.interval
                         && rig.started[0].tolerance == ClipboardWatcher.tolerance && rig.lane.count == 1,
                     "the first watch starts the one timer and takes one look, to know where the clipboard stands")
        suite.expect(ClipboardWatcher.interval == 0.8 && ClipboardWatcher.tolerance == 0.25,
                     "the clipboard is looked at every 0.8 seconds, give or take a quarter")
        tool.rewriteLinks(rule: mark) { heard.append($0.text) }
        other.rewriteLinks(rule: never) { _ in heard.append("other") }
        suite.expect(rig.started.count == 1 && rig.ticks.count == 1,
                     "a tool watched for already keeps its watch, and a second tool shares the timer")
        rig.settle()
        rig.tick()
        rig.settle()
        suite.expect(rig.text == "abc" && heard.isEmpty,
                     "what was on the clipboard when a watch started is not a new copy")

        rig.copy("def")
        rig.tick()
        suite.expect(rig.lane.count == 2 && rig.text == "def", "a tick puts one look per watching tool on the lane")
        rig.settle()
        rig.tick()
        rig.settle()
        suite.expect(rig.text == "def!" && heard == ["def!"],
                     "a copy is rewritten once: the watch's own rewrite is not a new copy to it")

        rig.copy("ghi")
        rig.tick()
        tool.writeLink("own")
        rig.settle()
        suite.expect(rig.text == "own" && heard == ["def!"], "a tool's own write calls off its look that was waiting")
        rig.tick()
        rig.settle()
        suite.expect(rig.text == (URLCleanerTests.signingMovesTheCount() ? "own!" : "own"),
                     "after its own write a tool's watch looks again only if signing the write moved the clipboard's count")

        rig.copy("jkl")
        rig.tick()
        tool.stopRewritingLinks()
        suite.expect(rig.ticks.count == 1, "the timer runs while any tool is watched for")
        rig.settle()
        suite.expect(rig.text == "jkl", "a look that was waiting when its watch stopped changes nothing")
        rig.set(installed: false, enabled: false)
        suite.expect(tool.rewriteLinks(rule: mark) { _ in } == .notInstalled,
                     "a tool removed in the hub is refused a watch")
        suite.expect(tool.readText { _ in heard.append("read") } == .notInstalled
                         && tool.writeLink("x") == .notInstalled && rig.lane.isEmpty,
                     "a tool removed in the hub can no longer read or write the clipboard")
        other.stopRewritingLinks()
        other.stopRewritingLinks()
        suite.expect(rig.ticks.isEmpty && rig.stopped == 1,
                     "the timer stops with the last watch, and stopping twice is safe")
    }
}
