// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// The parts the tool runtime is built from: the lines a tool writes, the
/// clock every limit is counted on, the log, and the limits themselves.
enum ToolRuntimeTests {
    static func run(_ suite: TestSuite) {
        lines(suite)
        clocks(suite)
        log(suite)
        limits(suite)
    }

    static func lines(_ suite: TestSuite) {
        let state = #"{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":["hello"]}}"#
        let done = #"{"jsonrpc":"2.0","id":2,"result":{}}"#
        var reader = ToolLineReader()
        suite.expect(reader.read(Data((state + "\n" + done + "\n").utf8))
                         == [.message(.notice(method: "commands/state",
                                              params: .object(["runnable": .array([.string("hello")])]))),
                             .message(.result(id: .number(2), value: .object([:])))],
                     "two lines read at once are two messages, in order")

        let accented = Array(#"{"jsonrpc":"2.0","method":"log","params":{"message":"déjà"}}"#.utf8) + [0x0A]
        let cut = accented.firstIndex(of: 0xC3)! + 1
        suite.expect(reader.read(Data(accented[..<cut])).isEmpty
                         && reader.read(Data(accented[cut...]))
                         == [.message(.notice(method: "log", params: .object(["message": .string("déjà")])))],
                     "a line cut in the middle of a character is one message once the rest arrives")

        suite.expect(reader.read(Data("\n  \n\t\n".utf8)).isEmpty, "a blank line is nothing")
        suite.expect(reader.read(Data("hello\n[]\n{\"jsonrpc\":\"1.0\",\"method\":\"log\"}\n".utf8))
                         == [.notAMessage, .notAMessage, .notAMessage],
                     "text, JSON that is no object, and another JSON-RPC are each a line that is not a message")
        suite.expect(reader.read(Data((done + "\r\n").utf8)) == [.message(.result(id: .number(2), value: .object([:])))],
                     "a carriage return before the line break does not spoil a message")

        suite.expect(reader.read(Data(done.utf8)).isEmpty && reader.read(Data()).isEmpty,
                     "a last line with no line break is never given out")
        suite.expect(reader.read(Data("\n".utf8)) == [.message(.result(id: .number(2), value: .object([:])))],
                     "until its line break comes")

        var small = ToolLineReader(limit: 48)
        let long = #"{"jsonrpc":"2.0","method":"log","params":{"message":"0123456789"}}"#
        suite.expect(small.read(Data(long.utf8)) == [.tooLong] && small.read(Data((long + long + "\n").utf8)).isEmpty,
                     "a line over the limit is reported once, as soon as it is known, and the rest of it is dropped")
        suite.expect(small.read(Data((done + "\n").utf8)) == [.message(.result(id: .number(2), value: .object([:])))],
                     "and the line after it is read as usual")
        suite.expect(WireLimits.maxLineBytes == 1_048_576, "a line may be 1 MB")
    }

    static func clocks(_ suite: TestSuite) {
        let clock = ManualToolClock()
        let start = clock.now
        var ran: [String] = []
        _ = clock.after(2) { ran.append("two") }
        let never = clock.after(1) { ran.append("never") }
        _ = clock.after(1) {
            ran.append("one")
            _ = clock.after(0.5) { ran.append("one and a half") }
            _ = clock.after(5) { ran.append("six") }
        }
        never.cancel()
        clock.advance(by: 0.5)
        suite.expect(ran.isEmpty && clock.waiting == 2, "nothing on a hand-moved clock runs before its moment")
        clock.advance(by: 2)
        suite.expect(ran == ["one", "one and a half", "two"] && clock.now == start + 2.5 && clock.waiting == 1,
                     "timers run in the order they fall due, one set on the way runs too, and a cancelled one never")

        let system = SystemToolClock()
        var fired = 0
        var onMain = false
        let before = system.now
        _ = system.after(0.01) {
            fired += 1
            onMain = Thread.isMainThread
        }
        let called = system.after(0.01) { fired += 100 }
        called.cancel()
        called.cancel()
        var later = false
        _ = system.after(0.05) { later = true }
        suite.expect(ToolRuntimeSupport.wait(until: { later }) && fired == 1 && onMain && system.now > before,
                     "the Mac's clock runs a timer once, on the main thread, and never one that was called off")
    }

    static func log(_ suite: TestSuite) {
        let log = ToolLog(limit: 16)
        log.add("one", from: .standardError)
        log.add("two", from: .message)
        suite.expect(log.entries == [.init(source: .standardError, text: "one"), .init(source: .message, text: "two")]
                         && log.text == "one\ntwo",
                     "the log keeps what a tool said, in order, and where each line came from")
        log.add("0123456789", from: .runtime)
        suite.expect(log.entries.map(\.text) == ["two", "0123456789"], "past its size the oldest lines go first")
        log.add("abcdefghijklmnopqrstuvwxyz", from: .message)
        suite.expect(log.entries.map(\.text) == ["klmnopqrstuvwxyz"],
                     "one line longer than the whole log keeps its end")

        let busy = ToolLog(limit: 64)
        for index in 0..<20_000 { busy.add(index.isMultiple(of: 2) ? "" : "x", from: .message) }
        suite.expect(busy.entries.count <= 64 && busy.entries.last?.text == "x",
                     "a great many short lines are still held to the size, empty ones too")
    }

    static func limits(_ suite: TestSuite) {
        let limits = ToolLimits.standard
        suite.expect(limits.firstAnswer == 10 && limits.answer == 2 && limits.unansweredInARow == 3,
                     "a tool has 10 seconds for its first answer and 2 for the rest; three misses in a row stop it")
        suite.expect(limits.messagesPerSecond == 200 && limits.floodSeconds == 5,
                     "more than 200 messages a second for 5 seconds is a flood")
        suite.expect(limits.junkLines == 20 && limits.junkWindow == 60,
                     "twenty lines that are not messages within a minute stop a tool")
        suite.expect(limits.logBytes == 262_144, "256 KB of a tool's log is kept")
        suite.expect(limits.goodbyeWait == 2 && limits.endWait == 1,
                     "a tool has 2 seconds after goodbye before it is ended, and 1 more before it is killed")
        suite.expect(limits.idleStop == 120, "a tool started by a command is stopped after two idle minutes")
        suite.expect(limits.firstRestartWait == 1 && limits.longestRestartWait == 300
                         && limits.crashesBeforeGivingUp == 3 && limits.crashWindow == 60,
                     "after a crash the wait doubles from 1 second to 5 minutes; three in a minute and it stays stopped")
    }
}
