// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
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
    }

    /// What the broker is told about the world, and what it reported.
    final class World {
        var installed = true
        var granted: Set<AppPermission> = Set(AppPermission.allCases)
        var allowed = true
        var undeclared: [Capability] = []
    }

    static func manifest(_ capabilities: [Capability]) -> ToolManifest {
        ToolManifest(tool: ToolDescriptor(id: ToolID("portManager")!, name: "portManager", symbol: "network",
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
}
