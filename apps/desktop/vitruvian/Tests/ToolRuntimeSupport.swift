// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// A clock a test moves by hand. Nothing on it happens until `advance`.
final class ManualToolClock: ToolClock {
    private final class Due: ToolTimer {
        let due: TimeInterval
        let order: Int
        var work: (@MainActor () -> Void)?

        init(due: TimeInterval, order: Int, work: @escaping @MainActor () -> Void) {
            self.due = due
            self.order = order
            self.work = work
        }

        func cancel() {
            work = nil
        }
    }

    private(set) var now: TimeInterval = 1_000
    private var timers: [Due] = []
    private var made = 0

    /// How many timers have still to run.
    var waiting: Int { timers.filter { $0.work != nil }.count }

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any ToolTimer {
        made += 1
        let timer = Due(due: now + max(0, delay), order: made, work: work)
        timers.append(timer)
        return timer
    }

    /// Moves time on by `seconds`. Each timer runs when its moment comes, the
    /// earliest first, and one that a timer sets runs too when it falls due.
    func advance(by seconds: TimeInterval) {
        let end = now + seconds
        while let next = timers.filter({ $0.work != nil && $0.due <= end })
            .min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) {
            now = max(now, next.due)
            let work = next.work
            next.work = nil
            work?()
        }
        timers.removeAll { $0.work == nil }
        now = end
    }
}

/// A tool that is no program: a test says what it writes and sees what it
/// was sent. It goes where a process and its pipes would, so everything
/// above the transport runs as it does for a real tool.
final class FakeTool: ToolTransport {
    /// False for a program that cannot be started.
    var starts = true
    /// False for a tool that has stopped reading its input.
    var reads = true
    /// The status it exits with when its input closes, when asked to end,
    /// and when killed. Nil for a tool that does not.
    var exitsOnClose: Int32?
    var exitsOnTerminate: Int32?
    var exitsOnKill: Int32?

    private(set) var started = 0
    /// Every message the app wrote, in order.
    private(set) var sent: [RPCMessage] = []
    private(set) var inputClosed = false
    /// "terminate" and "kill", as each was sent.
    private(set) var signals: [String] = []
    private(set) var isRunning = false

    private var reader = ToolLineReader()
    private var onItems: (@MainActor ([ToolInbound]) -> Void)?
    private var onErrorOutput: (@MainActor (Data) -> Void)?
    private var onExit: (@MainActor (Int32) -> Void)?

    func start(onItems: @escaping @MainActor ([ToolInbound]) -> Void,
               onErrorOutput: @escaping @MainActor (Data) -> Void,
               onExit: @escaping @MainActor (Int32) -> Void) -> Bool {
        started += 1
        guard starts else { return false }
        self.onItems = onItems
        self.onErrorOutput = onErrorOutput
        self.onExit = onExit
        isRunning = true
        return true
    }

    func send(_ line: Data) -> Bool {
        guard reads, !inputClosed, line.last == 0x0A,
              let message = try? LineFraming.message(from: line.dropLast()) else { return false }
        sent.append(message)
        return true
    }

    func closeInput() {
        inputClosed = true
        if let status = exitsOnClose { ends(status) }
    }

    func terminate() {
        signals.append("terminate")
        if let status = exitsOnTerminate { ends(status) }
    }

    func kill() {
        signals.append("kill")
        if let status = exitsOnKill { ends(status) }
    }

    // MARK: The tool's side

    /// The tool writes one line.
    func says(_ json: String) {
        writes(ToolRuntimeSupport.line(json))
    }

    func writes(_ bytes: Data) {
        guard isRunning else { return }
        onItems?(reader.read(bytes))
    }

    /// The tool writes to its standard error.
    func complains(_ text: String) {
        onErrorOutput?(Data(text.utf8))
    }

    /// The tool's program ends.
    func ends(_ status: Int32) {
        guard isRunning else { return }
        isRunning = false
        onExit?(status)
    }

    /// Answers `initialize` as a tool should.
    func greets(protocolVersion: String = "1") {
        says(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"\#(protocolVersion)","toolVersion":"0.1.0"}}"#)
    }

    /// Answers the app's request `id` with a result.
    func answers(_ id: Int, _ result: String = "{}") {
        says(#"{"jsonrpc":"2.0","id":\#(id),"result":\#(result)}"#)
    }

    /// Answers the app's request `id` with a failure.
    func refuses(_ id: Int, code: Int = RefusalCode.commandRefused.rawValue) {
        says(#"{"jsonrpc":"2.0","id":\#(id),"error":{"code":\#(code),"message":"no"}}"#)
    }

    /// The id of the last request the app sent, as a number.
    var lastRequest: Int? {
        for message in sent.reversed() {
            if case .request(.number(let id), _, _) = message { return id }
        }
        return nil
    }
}

enum ToolRuntimeSupport {
    /// Turns the run loop until `done` says so, for at most `seconds` of
    /// real time. True when it did. Only what starts a real program or
    /// reads the Mac's own clock needs this; everything else is moved by
    /// hand and never waits.
    @discardableResult
    static func wait(upTo seconds: TimeInterval = 20, until done: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while !done(), Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        return done()
    }

    /// One line of JSON, as the bytes a tool would write.
    static func line(_ json: String) -> Data {
        Data((json + "\n").utf8)
    }
}
