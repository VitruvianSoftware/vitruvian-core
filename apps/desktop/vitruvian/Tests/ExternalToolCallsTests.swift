// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// What a tool that runs as its own program may ask of the app: each
/// request of the protocol against a broker whose services only record, and
/// each way it can be refused.
enum ExternalToolCallsTests {
    static func run(_ suite: TestSuite) {
        smallRequests(suite)
        clipboard(suite)
        keystrokes(suite)
        processes(suite)
        storage(suite)
        refusals(suite)
        overTheLimit(suite)
    }

    /// A tool that lists every service a manifest may, with a preference of
    /// each kind; and one that lists none.
    static let everything = ExternalToolManifestTests.tool(#"""
        {"uses": ["notify", "open", "clipboard.read", "clipboard.write", "keystrokes", "processes", "storage"],
         "preferences": [{"id": "project", "type": "string", "default": "web"},
                         {"id": "loud", "type": "boolean", "default": false},
                         {"id": "count", "type": "integer", "default": 3},
                         {"id": "ratio", "type": "number", "default": 0.5}]}
        """#)!.manifest
    static let nothing = ExternalToolManifestTests.tool(#"{"uses": null, "preferences": null}"#)!.manifest

    /// A request with params the app accepts, for each request a tool makes.
    static let requests: [(ToolMethod, String?)] = [
        (.notifyHUD, #"{"icon": "link", "message": "Copied"}"#),
        (.notifyBeep, nil),
        (.openURL, #"{"url": "https://example.com/a"}"#),
        (.clipboardReadText, nil),
        (.clipboardWriteText, #"{"text": "x"}"#),
        (.keystrokesPaste, #"{"text": "Plain"}"#),
        (.keystrokesPressMenuItem, #"{"equivalents": [{"character": "v", "modifiers": ["shift", "option"]}]}"#),
        (.processesTerminate, #"{"pid": 42, "name": "node", "force": true}"#),
        (.storageGet, #"{"key": "project"}"#),
        (.storageSet, #"{"key": "project", "value": "api"}"#),
        (.uiBadge, #"{"count": 2}"#),
    ]

    /// A broker whose services record what they were asked, and the world
    /// it is told about.
    final class Bench {
        let world = ToolBrokerTests.World()
        let rig = URLCleanerTests.CleanerRig()
        let box = ToolBrokerTests.PreferenceBox()
        let menu = PastePlainTests.MenuLog()
        var said: [String] = []
        var beeps = 0
        var opened: [URL] = []
        var opens = true
        var written: [String] = []
        var writes = true
        var pastes: [String] = []
        var canEnd = true
        var protected: Set<pid_t> = []
        var ended: [String] = []
        private(set) var broker: CapabilityBroker!

        init() {
            let box = self.box
            let bar = PastePlainTests.editMenu(menu, [PastePlainTests.item("Match", key: PastePlainTests.matchStyle,
                                                                           menu)])
            broker = CapabilityBroker(
                environment: .init(isInstalled: { [unowned self] _ in world.installed },
                                   isGranted: { [unowned self] in world.granted.contains($0) },
                                   allows: { [unowned self] _, _ in world.allowed },
                                   reportUndeclared: { [unowned self] _, capability in
                                       world.undeclared.append(capability)
                                   }),
                backings: .init(
                    notify: .init(beep: { [unowned self] in beeps += 1 },
                                  hud: { [unowned self] in said.append("\($0): \($1)") }),
                    open: .init(open: { [unowned self] in
                        opened.append($0)
                        return opens
                    }),
                    clipboard: .init(write: { [unowned self] text, completion in
                        written.append(text)
                        completion(writes)
                    }, watching: rig.watching),
                    processes: .init(startTime: { $0 == 42 ? 1_000 : nil },
                                     listeningSocketsReport: { (0, "") },
                                     terminationAvailable: { [unowned self] in canEnd },
                                     isProtected: { [unowned self] pid, _ in protected.contains(pid) },
                                     terminate: { [unowned self] pid, name, startedAt, force, completion in
                                         ended.append("\(pid) \(name) \(startedAt) \(force)")
                                         completion()
                                     }),
                    storage: .init(read: { key in
                        box.reads.append(key)
                        return box.values[key]
                    }, write: { box.values[$0] = $1 }),
                    keystrokes: .init(paste: { [unowned self] text, _, _ in pastes.append(text) },
                                      requestGrant: {},
                                      menu: .init(frontmostApp: { 7 }, menuBar: { _ in bar }))))
        }

        /// Makes one request as `tool` and gives back its answer: nil when
        /// it was not answered exactly once.
        func ask(_ method: ToolMethod, _ params: String? = nil,
                 as tool: ToolManifest = everything) -> Result<JSONValue, RPCErrorObject>? {
            var answers: [Result<JSONValue, RPCErrorObject>] = []
            let json = params.flatMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
            ExternalToolCalls(manifest: tool, broker: broker).serve(method, json) { answers.append($0) }
            rig.settle()
            return answers.count == 1 ? answers[0] : nil
        }

        func close() {
            rig.close()
        }
    }

    static func result(_ answer: Result<JSONValue, RPCErrorObject>?) -> JSONValue? {
        if case .success(let value)? = answer { return value }
        return nil
    }

    static func error(_ answer: Result<JSONValue, RPCErrorObject>?) -> RPCErrorObject? {
        if case .failure(let error)? = answer { return error }
        return nil
    }

    static func code(_ answer: Result<JSONValue, RPCErrorObject>?) -> Int? {
        error(answer)?.code
    }

    static let done = JSONValue.object([:])

    static func smallRequests(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        suite.expect(result(bench.ask(.notifyHUD, #"{"icon": "link", "message": "Copied"}"#)) == done
                         && bench.said == ["link: Copied"],
                     "notify/hud shows the app's short message, with its symbol")
        suite.expect(result(bench.ask(.notifyBeep)) == done && bench.beeps == 1, "notify/beep is the alert sound")
        suite.expect(result(bench.ask(.openURL, #"{"url": "https://example.com/a"}"#)) == .object(["opened": .bool(true)])
                         && bench.opened == [URL(string: "https://example.com/a")!],
                     "open/url opens a link, and says that it opened")
        bench.opens = false
        suite.expect(result(bench.ask(.openURL, #"{"url": "https://example.com/b"}"#)) == .object(["opened": .bool(false)]),
                     "or that it did not")
        for params in [#"{"url": "no scheme"}"#, #"{"url": ""}"#, #"{"link": "https://example.com"}"#, nil] {
            suite.expect(code(bench.ask(.openURL, params)) == -32602 && bench.opened.count == 2,
                         "open/url with \(params ?? "no params") is answered invalid params, and opens nothing")
        }
        suite.expect(code(bench.ask(.notifyHUD, #"{"icon": "link"}"#)) == -32602 && bench.said.count == 1,
                     "a request with a field missing is answered invalid params, and nothing is done")
        for method in [ToolMethod.initialize, .commandRun, .preferencesChanged, .languageChanged, .shutdown,
                       .commandsState, .log] {
            suite.expect(code(bench.ask(method)) == -32601, "\(method.rawValue) is not a request a tool makes")
        }
    }

    static func clipboard(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.rig.copy("hello")
        suite.expect(result(bench.ask(.clipboardReadText)) == .object(["text": .string("hello")]),
                     "clipboard/readText answers with the clipboard's text, once the clipboard lane has run")
        bench.rig.board.clearContents()
        suite.expect(result(bench.ask(.clipboardReadText)) == done, "and with no text when the clipboard holds none")
        suite.expect(result(bench.ask(.clipboardWriteText, #"{"text": "x"}"#)) == .object(["written": .bool(true)])
                         && bench.written == ["x"],
                     "clipboard/writeText replaces the clipboard, and says that it took")
        bench.writes = false
        suite.expect(result(bench.ask(.clipboardWriteText, #"{"text": "y"}"#)) == .object(["written": .bool(false)]),
                     "or that it did not")
    }

    static func keystrokes(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        suite.expect(result(bench.ask(.keystrokesPaste, #"{"text": "Plain"}"#)) == done && bench.pastes == ["Plain"],
                     "keystrokes/paste hands the text to the app's paste")
        let match = #"{"equivalents": [{"character": "x", "modifiers": []}, "#
            + #"{"character": "v", "modifiers": ["shift", "option"]}]}"#
        suite.expect(result(bench.ask(.keystrokesPressMenuItem, match)) == .object(["pressed": .bool(true)])
                         && bench.menu.pressed == ["Match"],
                     "keystrokes/pressMenuItem presses the item with one of the key equivalents: "
                         + "shift is 1, option is 2 in the mask the menu reports")
        suite.expect(result(bench.ask(.keystrokesPressMenuItem,
                                      #"{"equivalents": [{"character": "v", "modifiers": ["control"]}]}"#))
                         == .object(["pressed": .bool(false)]) && bench.menu.pressed == ["Match"],
                     "and says when no item has them")
        suite.expect(code(bench.ask(.keystrokesPressMenuItem,
                                    #"{"equivalents": [{"character": "v", "modifiers": ["command"]}]}"#)) == -32602,
                     "a modifier the protocol does not name is invalid params")
        bench.world.granted = []
        let refused = error(bench.ask(.keystrokesPaste, #"{"text": "Plain"}"#))
        suite.expect(refused == RPCErrorObject(code: -32003, message: "Vitruvian lacks a macOS permission",
                                               data: .object(["permission": .string("accessibility")]))
                         && bench.pastes == ["Plain"],
                     "without Accessibility a keystroke request is refused with -32003, and names the permission")
        suite.expect(result(bench.ask(.notifyBeep)) == done, "while a service that rides on no permission still works")
    }

    static func processes(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        suite.expect(result(bench.ask(.processesTerminate, #"{"pid": 42, "name": "node", "force": true}"#)) == done
                         && bench.ended == ["42 node 1000 true"],
                     "processes/terminate ends the process, with the start time the app looked up itself")
        for params in [#"{"pid": 7, "name": "gone", "force": false}"#, #"{"pid": 0, "name": "x", "force": false}"#,
                       #"{"pid": -1, "name": "x", "force": false}"#,
                       #"{"pid": 99999999999, "name": "x", "force": false}"#, #"{"pid": 42}"#] {
            suite.expect(code(bench.ask(.processesTerminate, params)) == -32602 && bench.ended.count == 1,
                         "processes/terminate with \(params) is answered invalid params, and ends nothing")
        }
        bench.protected = [42]
        suite.expect(code(bench.ask(.processesTerminate, #"{"pid": 42, "name": "node", "force": true}"#)) == -32004
                         && bench.ended.count == 1,
                     "a process the app protects is not ended: not available")
        bench.protected = []
        bench.canEnd = false
        suite.expect(code(bench.ask(.processesTerminate, #"{"pid": 42, "name": "node", "force": true}"#)) == -32004
                         && bench.ended.count == 1,
                     "nor any process while the app does not offer to end one")
    }

    static func storage(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let project = "com.acme.deploys/project"
        suite.expect(result(bench.ask(.storageGet, #"{"key": "project"}"#)) == .object(["value": .string("web")])
                         && bench.box.reads == [project],
                     "storage/get reads a preference under the tool's id, and answers its default when none is saved")
        suite.expect(result(bench.ask(.storageSet, #"{"key": "project", "value": "api"}"#)) == done
                         && bench.box.values[project] as? String == "api" && bench.box.values.count == 1,
                     "storage/set saves a value under the tool's id")
        suite.expect(result(bench.ask(.storageGet, #"{"key": "project"}"#)) == .object(["value": .string("api")]),
                     "which storage/get then reads")

        suite.expect(result(bench.ask(.storageSet, #"{"key": "count", "value": 4}"#)) == done
                         && bench.box.values["com.acme.deploys/count"] as? Int == 4
                         && result(bench.ask(.storageSet, #"{"key": "ratio", "value": 2}"#)) == done
                         && bench.box.values["com.acme.deploys/ratio"] as? Double == 2
                         && result(bench.ask(.storageSet, #"{"key": "loud", "value": true}"#)) == done
                         && bench.box.values["com.acme.deploys/loud"] as? Bool == true,
                     "a whole number, a number and a yes or no are each saved as what the preference is")
        suite.expect(result(bench.ask(.storageGet, #"{"key": "count"}"#)) == .object(["value": .number(4)])
                         && result(bench.ask(.storageGet, #"{"key": "loud"}"#)) == .object(["value": .bool(true)]),
                     "and read back as that")
        let saved = bench.box.values.count
        for params in [#"{"key": "count", "value": 2.5}"#, #"{"key": "count", "value": "4"}"#,
                       #"{"key": "loud", "value": 1}"#, #"{"key": "project", "value": true}"#,
                       #"{"key": "other", "value": "x"}"#, #"{"key": "project", "value": null}"#,
                       #"{"key": "project", "value": ["x"]}"#, #"{"key": "project"}"#] {
            suite.expect(code(bench.ask(.storageSet, params)) == -32602 && bench.box.values.count == saved
                             && bench.box.values[project] as? String == "api",
                         "storage/set with \(params) is answered invalid params, and saves nothing")
        }
        let reads = bench.box.reads.count
        suite.expect(code(bench.ask(.storageGet, #"{"key": "other"}"#)) == -32602 && bench.box.reads.count == reads,
                     "a preference the manifest does not declare is not read")
        // A key is only ever looked up among the tool's own declared
        // preferences: it is never a path, and never another tool's.
        bench.box.values["com.other.tool/project"] = "theirs"
        bench.box.values["appLanguage"] = "fr"
        var reached = false
        for key in ["../com.other.tool/project", "com.other.tool/project", "com.acme.deploys/project",
                    "/project", "appLanguage", ""] {
            let get = code(bench.ask(.storageGet, #"{"key": "\#(key)"}"#))
            let set = code(bench.ask(.storageSet, #"{"key": "\#(key)", "value": "mine"}"#))
            if get != -32602 || set != -32602 { reached = true }
        }
        suite.expect(!reached && bench.box.reads.count == reads && bench.box.values.count == saved + 2
                         && bench.box.values["com.other.tool/project"] as? String == "theirs"
                         && bench.box.values["appLanguage"] as? String == "fr",
                     "no key reaches another tool's preferences or the app's own: each is invalid params, "
                         + "and nothing is read or written")
        bench.box.values["com.other.tool/project"] = nil
        bench.box.values["appLanguage"] = nil
        bench.box.values["com.acme.deploys/count"] = "four"
        suite.expect(result(bench.ask(.storageGet, #"{"key": "count"}"#)) == .object(["value": .number(3)]),
                     "a saved value of another kind reads as the default")

        let most = String(repeating: "é", count: StorageLimits.maxTextLength)
        let fits = bench.ask(.storageSet, #"{"key": "project", "value": "\#(most)"}"#)
        let over = bench.ask(.storageSet, #"{"key": "project", "value": "\#(most)é"}"#)
        suite.expect(StorageLimits.maxTextLength == 4_096 && result(fits) == done && code(over) == -32602
                         && error(over)?.message == "longer than a preference may be"
                         && bench.box.values[project] as? String == most,
                     "storage/set saves text of 4,096 characters, and answers one character more as invalid params "
                         + "with nothing saved")
    }

    static func refusals(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        bench.rig.copy("secret")
        for (method, params) in requests {
            let refused = error(bench.ask(method, params, as: nothing))
            suite.expect(refused == RPCErrorObject(code: -32001, message: "not listed in uses",
                                                   data: .object(["service": .string(method.service?.rawValue ?? "")])),
                         "\(method.rawValue) from a tool that does not list its service is refused with -32001, "
                             + "which names the service")
        }
        suite.expect(Set(requests.map(\.0)) == Set(ToolMethod.allCases.filter { $0.sender == .tool && $0.isAnswered })
                         && bench.world.undeclared.count == requests.count,
                     "that is every request a tool can make, and each was reported as the tool's mistake")
        suite.expect(bench.said.isEmpty && bench.beeps == 0 && bench.opened.isEmpty && bench.written.isEmpty
                         && bench.pastes.isEmpty && bench.menu.pressed.isEmpty && bench.ended.isEmpty
                         && bench.box.reads.isEmpty && bench.box.values.isEmpty && bench.rig.lane.isEmpty,
                     "and not one of them did anything")

        bench.world.installed = false
        suite.expect(error(bench.ask(.notifyBeep)) == RPCErrorObject(code: -32002, message: "tool not installed")
                         && bench.beeps == 0,
                     "a tool that is not installed is refused with -32002")
        bench.world.installed = true
        bench.world.allowed = false
        suite.expect(error(bench.ask(.notifyBeep)) == RPCErrorObject(code: -32004, message: "not available right now")
                         && bench.beeps == 0,
                     "a service the app does not offer right now is refused with -32004")
        bench.world.allowed = true
        suite.expect(result(bench.ask(.notifyBeep)) == done && bench.beeps == 1, "and otherwise it is done")

        suite.expect(ExternalToolCalls.error(for: .notDeclared(.hotkey))
                         == RPCErrorObject(code: -32001, message: "not listed in uses"),
                     "a capability the protocol has no name for is refused without one")

        let live = CapabilityBroker.Environment.reading(accessibility: { true }, screenRecording: { true })
        live.reportUndeclared(ExternalToolTests.id, .open)
        suite.expect(true, "an outside tool's undeclared request does not stop a development build of the app")

        // The same, with what stops a development build handed in.
        var stops: [String] = []
        let watched = CapabilityBroker.Environment.reading(accessibility: { true }, screenRecording: { true },
                                                           stop: { stops.append($0) })
        watched.reportUndeclared(ExternalToolTests.id, .open)
        let outside = stops.count
        watched.reportUndeclared(ToolID("portManager")!, .open)
        suite.expect(outside == 0 && stops == ["portManager used open without declaring it"],
                     "one of the app's own tools doing the same still stops it, and an outside tool's does not")
    }

    /// A tool that asks faster than the app will work for it, over a link
    /// whose requests go to the broker.
    static func overTheLimit(_ suite: TestSuite) {
        let bench = Bench()
        defer { bench.close() }
        let tool = FakeTool()
        let clock = ManualToolClock()
        let calls = ExternalToolCalls(manifest: everything, broker: bench.broker)
        let link = ToolLink(transport: tool, clock: clock,
                            hello: InitializeParams(protocolVersions: ["1"], language: "en", dataFolder: "/data"),
                            serve: { calls.serve($0, $1, $2) }, events: .init())
        link.start()
        tool.greets()
        clock.advance(by: 1)
        for id in 0..<205 { tool.says(#"{"jsonrpc":"2.0","id":\#(id),"method":"notify/beep"}"#) }
        let refused = RPCErrorObject(code: -32004, message: "not available right now")
        suite.expect(bench.beeps == 200 && link.state == .ready
                         && tool.sent.suffix(6) == [.result(id: .number(199), value: done)]
                         + (200..<205).map { .failure(id: .number($0), error: refused) },
                     "200 requests in a second are done; each one past that is refused as not available, "
                         + "and the broker is not asked")
        link.shutdown()
    }
}
