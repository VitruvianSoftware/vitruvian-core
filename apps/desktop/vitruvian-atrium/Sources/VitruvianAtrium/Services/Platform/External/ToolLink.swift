// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianToolProtocol

/// One run of one tool's program, from its start to its end: the greeting,
/// requests in both directions with their deadlines, and the goodbye.
///
/// It lives on the main actor and never waits. Everything that takes time
/// is a timer on its clock, so a tool that hangs costs the app a timer.
/// A link is used once: when it has ended, whoever wants the tool again
/// makes another.
@MainActor
package final class ToolLink {
    package enum State: Equatable, Sendable {
        /// Not started yet.
        case idle
        /// The program runs and has not answered `initialize`.
        case starting
        case ready
        /// The program is being ended.
        case stopping
        case ended
    }

    /// What a tool did that the app will not put up with.
    package enum Fault: Equatable, Sendable {
        /// It answered `initialize` wrongly, or said something before it.
        case badHandshake
        /// It did not answer in time: its first message, or several in a row.
        case silent
        case flood
        case lineTooLong
        /// Too many lines that are not messages.
        case notMessages
        /// It does not read what the app writes.
        case notReading
    }

    /// How a link ended.
    package enum End: Equatable, Sendable {
        /// The app asked it to stop.
        case stopped
        /// The program ended by itself, with this status; nil when it could
        /// not be started at all.
        case exited(Int32?)
        /// The app stopped it for what it did.
        case misbehaved(Fault)
    }

    /// Why a request the app made was not done.
    package enum Failure: Error, Equatable, Sendable {
        /// The link is not ready, or is over.
        case notReady
        /// The tool answered with a failure.
        case refused(RPCErrorObject)
        /// The tool did not answer in time.
        case noAnswer
    }

    /// Answers one request a tool made. Called once.
    package typealias Reply = @MainActor (Result<JSONValue, RPCErrorObject>) -> Void
    /// Does what a tool asked of the app, and answers through `Reply`,
    /// at once or later.
    package typealias Serve = @MainActor (ToolMethod, JSONValue?, @escaping Reply) -> Void

    package struct Events {
        /// `state` changed.
        package var onChange: @MainActor () -> Void
        /// The tool said which of its commands can run now.
        package var onRunnable: @MainActor ([String]) -> Void
        package var onLog: @MainActor (String, ToolLog.Source) -> Void
        /// The tool asked something of the app.
        package var onAsked: @MainActor () -> Void
        /// The tool sent a page for one of its panels, by the panel's id.
        /// The page is as the tool wrote it: reading it is for whoever draws.
        package var onRender: @MainActor (String, JSONValue) -> Void
        /// The link is over. Called once, last.
        package var onEnd: @MainActor (End) -> Void

        package init(onChange: @escaping @MainActor () -> Void = {},
                     onRunnable: @escaping @MainActor ([String]) -> Void = { _ in },
                     onLog: @escaping @MainActor (String, ToolLog.Source) -> Void = { _, _ in },
                     onAsked: @escaping @MainActor () -> Void = {},
                     onRender: @escaping @MainActor (String, JSONValue) -> Void = { _, _ in },
                     onEnd: @escaping @MainActor (End) -> Void = { _ in }) {
            self.onChange = onChange
            self.onRunnable = onRunnable
            self.onLog = onLog
            self.onAsked = onAsked
            self.onRender = onRender
            self.onEnd = onEnd
        }
    }

    private struct Waiting {
        let timer: any ToolTimer
        let then: @MainActor (Result<JSONValue, Failure>) -> Void
    }

    private let transport: any ToolTransport
    private let clock: any ToolClock
    private let limits: ToolLimits
    private let hello: InitializeParams
    private let serve: Serve
    private let events: Events

    package private(set) var state: State = .idle
    /// The version the tool gave of itself in its greeting.
    package private(set) var toolVersion: String?
    /// Lines and answers that were dropped because they made no sense.
    package private(set) var dropped = 0

    private var lastID = 0
    /// The app's requests the tool has not answered yet.
    private var waiting: [RPCID: Waiting] = [:]
    /// Requests that ran out of time. An answer that still comes is late,
    /// not nonsense.
    private var late: Set<RPCID> = []
    /// The tool's requests the app has not answered yet.
    private var serving: Set<RPCID> = []
    private var unansweredInARow = 0
    /// The language the tool was last told the app is in: by `initialize`,
    /// then by each `language/changed`.
    private var language: String
    /// What the tool did that made the app stop it, once it has.
    package private(set) var fault: Fault?
    private var askedToStop = false
    /// How far ending the program has gone: 0 its input is closed, 1 it was
    /// asked to end, 2 it was killed.
    private var step = 0
    private var stepTimer: (any ToolTimer)?

    // The second being counted, how many lines it has had, and how many
    // seconds before it, in a row, had too many.
    private var secondStart: TimeInterval = 0
    private var linesThisSecond = 0
    private var busySeconds = 0
    /// When each recent line that was not a message arrived.
    private var junk: [TimeInterval] = []
    /// For each panel, the second its pages are being counted in and how
    /// many it has had.
    private var renders: [String: (second: TimeInterval, count: Int)] = [:]

    package init(transport: any ToolTransport, clock: any ToolClock, limits: ToolLimits = .standard,
                 hello: InitializeParams, serve: @escaping Serve, events: Events) {
        self.transport = transport
        self.clock = clock
        self.limits = limits
        self.hello = hello
        language = hello.language
        self.serve = serve
        self.events = events
    }

    // MARK: - Starting

    /// Starts the program and greets it. Does nothing the second time.
    package func start() {
        guard state == .idle else { return }
        state = .starting
        secondStart = clock.now
        let started = transport.start(
            onItems: { [weak self] items in self?.receive(items) },
            onErrorOutput: { [weak self] bytes in
                self?.events.onLog(String(decoding: bytes, as: UTF8.self), .standardError)
            },
            onExit: { [weak self] status in self?.exited(status) })
        guard started else {
            finish(.exited(nil))
            return
        }
        events.onChange()
        ask(.initialize, hello, within: limits.firstAnswer) { [weak self] answer in self?.greeted(answer) }
    }

    private func greeted(_ answer: Result<JSONValue, Failure>) {
        guard state == .starting else { return }
        switch answer {
        case .success(let value):
            // A version the app did not offer is one it cannot speak.
            guard let result = try? value.decode(InitializeResult.self),
                  hello.protocolVersions.contains(result.protocolVersion) else {
                fail(.badHandshake)
                return
            }
            toolVersion = result.toolVersion
            state = .ready
            // The app's language changed after `initialize` was written:
            // the tool was greeted in one the app no longer has.
            if language != hello.language { tell(.languageChanged, LanguageChangedParams(language: language)) }
            events.onChange()
        case .failure(.refused):
            fail(.badHandshake)
        case .failure(.noAnswer), .failure(.notReady):
            // `unanswered` and `finish` have dealt with these.
            break
        }
    }

    // MARK: - What the app asks

    /// Has the tool run one of its commands. `then` hears how it went, once.
    package func run(_ command: String, then: @escaping @MainActor (Result<Void, Failure>) -> Void) {
        guard state == .ready else {
            then(.failure(.notReady))
            return
        }
        ask(.commandRun, CommandRunParams(command: command), within: limits.answer) { answer in
            then(answer.map { _ in })
        }
    }

    /// Tells the tool that preferences of its own have new values.
    package func preferencesChanged(_ values: [String: JSONValue]) {
        tell(.preferencesChanged, PreferencesChangedParams(values: values))
    }

    /// Tells the tool the person changed the app's language: once for each
    /// change, never the language it already has. A tool that has not
    /// answered `initialize` yet is told when it has, if the language is
    /// then another than the one it was greeted in. A tool that is being
    /// stopped is told nothing.
    package func languageChanged(_ language: String) {
        guard language != self.language else { return }
        self.language = language
        tell(.languageChanged, LanguageChangedParams(language: language))
    }

    // MARK: - Panels

    /// Asks the tool for a panel's first page. `then` hears the answer as
    /// the tool wrote it, or why there is none, once.
    package func open(panel: String, then: @escaping @MainActor (Result<JSONValue, Failure>) -> Void) {
        guard state == .ready else { return then(.failure(.notReady)) }
        ask(.uiOpen, UIOpenParams(panel: panel), within: limits.answer, then: then)
    }

    /// Tells the tool what the person did in an open panel. `then` hears
    /// the answer as the tool wrote it, or why there is none, once.
    package func event(_ event: UIEventParams, then: @escaping @MainActor (Result<JSONValue, Failure>) -> Void) {
        guard state == .ready else { return then(.failure(.notReady)) }
        ask(.uiEvent, event, within: limits.answer, then: then)
    }

    /// Tells the tool a panel went away.
    package func close(panel: String) {
        tell(.uiClose, UICloseParams(panel: panel))
    }

    /// Tells the tool where its slot is now, or that it went.
    package func slot(_ params: UISlotParams) {
        tell(.uiSlot, params)
    }

    /// A page the tool sent unprompted. Its panel is named and the page is
    /// handed on as written, to be read away from the main thread. More
    /// than `UILimits.floodRendersPerSecond` for one panel in one second is
    /// a flood: the tool is stopped, as for any other.
    private func rendered(_ params: JSONValue?) {
        guard let panel = params?["panel"]?.stringValue, let tree = params?["tree"] else { return drop() }
        let now = clock.now
        var counted = renders[panel] ?? (second: now, count: 0)
        if now - counted.second >= 1 { counted = (second: now, count: 0) }
        counted.count += 1
        renders[panel] = counted
        guard counted.count <= UILimits.floodRendersPerSecond else { return fail(.flood) }
        events.onRender(panel, tree)
    }

    private func tell<Params: Encodable>(_ method: ToolMethod, _ params: Params) {
        guard state == .ready else { return }
        write(.notice(method: method.rawValue, params: try? JSONValue(encoding: params)))
    }

    private func ask<Params: Encodable>(_ method: ToolMethod, _ params: Params, within seconds: TimeInterval,
                                        then: @escaping @MainActor (Result<JSONValue, Failure>) -> Void) {
        lastID += 1
        let id = RPCID.number(lastID)
        let timer = clock.after(seconds) { [weak self] in self?.unanswered(id) }
        waiting[id] = Waiting(timer: timer, then: then)
        write(.request(id: id, method: method.rawValue, params: try? JSONValue(encoding: params)))
    }

    private func unanswered(_ id: RPCID) {
        guard let request = waiting.removeValue(forKey: id) else { return }
        late.insert(id)
        unansweredInARow += 1
        request.then(.failure(.noAnswer))
        // With no greeting there is no link; after it, a few misses in a
        // row mean the tool has hung.
        if state == .starting || unansweredInARow >= limits.unansweredInARow { fail(.silent) }
    }

    // MARK: - What the tool says

    private func receive(_ items: [ToolInbound]) {
        for item in items {
            guard state == .starting || state == .ready else { return }
            let tooMany = countLine()
            guard state == .starting || state == .ready else { return }
            switch item {
            case .tooLong:
                fail(.lineTooLong)
            case .notAMessage:
                drop()
            case .message(.result(let id, let value)):
                answered(id, .success(value))
            case .message(.failure(let id, let error)):
                if let id { answered(id, .failure(.refused(error))) } else { drop() }
            case .message(.request(let id, let method, let params)):
                asked(id, method, params, tooMany: tooMany)
            case .message(.notice(let method, let params)):
                told(method, params)
            }
        }
    }

    private func answered(_ id: RPCID, _ answer: Result<JSONValue, Failure>) {
        if let request = waiting.removeValue(forKey: id) {
            request.timer.cancel()
            unansweredInARow = 0
            request.then(answer)
        } else if late.remove(id) == nil {
            // An answer to nothing the app asked.
            drop()
        }
    }

    private func asked(_ id: RPCID, _ name: String, _ params: JSONValue?, tooMany: Bool) {
        // Until the greeting is done, neither side says anything else.
        guard state == .ready else {
            fail(.badHandshake)
            return
        }
        guard let method = ToolMethod(rawValue: name), method.sender == .tool, method.isAnswered else {
            write(.failure(id: id, error: RPCErrorObject(code: RPCErrorCode.methodNotFound,
                                                         message: "unknown method")))
            return
        }
        guard !serving.contains(id) else {
            write(.failure(id: id, error: RPCErrorObject(code: RPCErrorCode.invalidRequest,
                                                         message: "this id is still being answered")))
            return
        }
        // Over the limit for this second: the tool is answered, and the app
        // does no work for it.
        guard !tooMany else {
            write(.failure(id: id, error: RefusalCode.unavailable.error()))
            return
        }
        serving.insert(id)
        events.onAsked()
        serve(method, params) { [weak self] answer in self?.reply(id, answer) }
    }

    private func reply(_ id: RPCID, _ answer: Result<JSONValue, RPCErrorObject>) {
        // Once: and not at all when the link has moved on.
        guard serving.remove(id) != nil, state == .ready else { return }
        switch answer {
        case .success(let value):
            // An answer too long to send is still an answer: a failure.
            if !write(.result(id: id, value: value)), state == .ready {
                write(.failure(id: id, error: RPCErrorObject(code: RPCErrorCode.internalError,
                                                             message: "the answer is too long to send")))
            }
        case .failure(let error):
            write(.failure(id: id, error: error))
        }
    }

    private func told(_ name: String, _ params: JSONValue?) {
        guard state == .ready else {
            fail(.badHandshake)
            return
        }
        switch ToolMethod(rawValue: name) {
        case .commandsState?:
            guard let told = try? params?.decode(CommandsStateParams.self) else { return drop() }
            events.onRunnable(told.runnable)
        case .log?:
            guard let line = try? params?.decode(LogParams.self) else { return drop() }
            events.onLog(line.message, .message)
        case .uiRender?:
            rendered(params)
        default:
            // A notice the app does not know is ignored: a later protocol
            // may add one.
            break
        }
    }

    // MARK: - Limits

    /// Counts one line against the second it arrived in. True when that
    /// second has had too many. Enough such seconds in a row is a flood.
    private func countLine() -> Bool {
        let now = clock.now
        let elapsed = now - secondStart
        if elapsed >= 1 {
            // The second that just closed was busy or not; a second with
            // nothing in it breaks the run.
            let wasBusy = linesThisSecond > limits.messagesPerSecond
            busySeconds = wasBusy && elapsed < 2 ? busySeconds + 1 : 0
            secondStart = elapsed < 2 ? secondStart + 1 : now
            linesThisSecond = 0
        }
        linesThisSecond += 1
        guard linesThisSecond > limits.messagesPerSecond else { return false }
        if busySeconds + 1 >= limits.floodSeconds { fail(.flood) }
        return true
    }

    /// Drops something that made no sense, and counts it.
    private func drop() {
        dropped += 1
        let now = clock.now
        junk = junk.filter { now - $0 < limits.junkWindow } + [now]
        if junk.count >= limits.junkLines { fail(.notMessages) }
    }

    // MARK: - Writing

    /// Sends one message. False when it was not sent: it is too long, or
    /// the tool is not reading, which ends the link.
    @discardableResult
    private func write(_ message: RPCMessage) -> Bool {
        guard let line = try? LineFraming.line(for: message) else { return false }
        guard transport.send(line) else {
            fail(.notReading)
            return false
        }
        return true
    }

    // MARK: - Ending

    /// Says goodbye and ends the program: its input is closed, then it is
    /// asked to end, then it is killed, each after its wait.
    package func shutdown() {
        switch state {
        case .idle:
            finish(.stopped)
        case .starting, .ready:
            askedToStop = true
            if let goodbye = try? LineFraming.line(for: .notice(method: ToolMethod.shutdown.rawValue, params: nil)) {
                _ = transport.send(goodbye)
            }
            windDown(after: limits.goodbyeWait)
        case .stopping:
            askedToStop = true
        case .ended:
            break
        }
    }

    /// Takes the next step in ending the program, now. The link takes each
    /// step by itself on its clock; at quit, when no timer will run again,
    /// the host calls this.
    package func escalate() {
        guard state == .stopping else { return }
        stepTimer?.cancel()
        switch step {
        case 0:
            step = 1
            transport.terminate()
        case 1:
            step = 2
            transport.kill()
        default:
            // Killed, and still no word that it ended: it is over as far
            // as the app can tell.
            finish(ending)
            return
        }
        guard state == .stopping else { return }
        // Held strongly, here and in `windDown`: a link nobody else holds
        // any more still sees its program out.
        stepTimer = clock.after(limits.endWait) { [self] in escalate() }
    }

    /// Stops the tool for something it did that the link itself cannot
    /// see: a flood of calls from one of its web panels.
    package func misbehaved(_ fault: Fault) {
        fail(fault)
    }

    /// True when nothing of the program is left running.
    package var hasEnded: Bool {
        state == .idle || state == .ended || !transport.isRunning
    }

    private func fail(_ fault: Fault) {
        guard state == .starting || state == .ready else { return }
        self.fault = fault
        // Nothing is said to a tool that misbehaves: it is ended.
        windDown(after: nil)
    }

    private func windDown(after grace: TimeInterval?) {
        state = .stopping
        abandon()
        events.onChange()
        transport.closeInput()
        // A program may be gone the moment its input closes.
        guard state == .stopping else { return }
        if let grace {
            stepTimer = clock.after(grace) { [self] in escalate() }
        } else {
            escalate()
        }
    }

    private func exited(_ status: Int32) {
        guard state != .ended else { return }
        finish(state == .stopping ? ending : .exited(status))
    }

    /// How a link that was being stopped ended.
    private var ending: End {
        if askedToStop { return .stopped }
        return fault.map(End.misbehaved) ?? .stopped
    }

    /// Fails every request still waiting, and forgets the tool's own.
    private func abandon() {
        let requests = waiting.values
        waiting = [:]
        serving = []
        for request in requests {
            request.timer.cancel()
            request.then(.failure(.notReady))
        }
    }

    private func finish(_ end: End) {
        guard state != .ended else { return }
        stepTimer?.cancel()
        stepTimer = nil
        state = .ended
        abandon()
        events.onChange()
        events.onEnd(end)
    }
}
