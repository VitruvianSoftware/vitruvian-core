// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import XCTest

import VitruvianCodeCore
import VitruvianCodeToolCore

/// Darwin marks `fork` unavailable to Swift; the child here only registers
/// a handler, writes a byte and ends, which is safe after a fork.
@_silgen_name("fork") private func forkProcess() -> pid_t

/// Where the child's atexit handler writes, if it runs.
nonisolated(unsafe) private var handlerPipe: Int32 = -1

/// The app gives a tool two seconds from `shutdown` to exit. These hold the
/// tool to that when the main thread is busy, and check that it ends without
/// the atexit handlers, one of which (CoreAnalytics') waits on a daemon.
final class ToolExitTests: XCTestCase {
    /// What `leave` ended with, and when.
    private final class Ending: @unchecked Sendable {
        let lock = NSLock()
        var status: Int32?
        var after: TimeInterval?
        var stopped = false
        func ended(_ value: Int32, _ seconds: TimeInterval) { lock.lock(); status = value; after = seconds; lock.unlock() }
        func stop() { lock.lock(); stopped = true; lock.unlock() }
        var snapshot: (Int32?, TimeInterval?, Bool) { lock.lock(); defer { lock.unlock() }; return (status, after, stopped) }
    }

    func testTheBudgetsFitInsideTheProtocolsTwoSeconds() {
        XCTAssertLessThan(ToolExit.stopBudget, ToolExit.deadline)
        XCTAssertLessThanOrEqual(ToolExit.deadline, 1.5)
    }

    /// A stop that finishes ends the program right after it, not at the deadline.
    func testEndsOnceTheStopHasFinished() {
        let ending = Ending()
        let done = expectation(description: "ended")
        let start = ProcessInfo.processInfo.systemUptime
        Thread.detachNewThread {
            ToolExit.leave(status: 0, deadline: 5, stop: { ending.stop() }, end: { status in
                ending.ended(status, ProcessInfo.processInfo.systemUptime - start)
                done.fulfill()
            })
        }
        wait(for: [done], timeout: 5)
        let (status, after, stopped) = ending.snapshot
        XCTAssertEqual(status, 0)
        XCTAssertTrue(stopped)
        XCTAssertLessThan(after ?? .infinity, 2, "waited for the deadline after the stop had finished")
    }

    /// A stop that does not finish, as when the main thread is busy or a
    /// chat's program will not die, ends the program at the deadline.
    func testEndsAtTheDeadlineWhenTheStopDoesNotFinish() {
        let ending = Ending()
        let done = expectation(description: "ended")
        let start = ProcessInfo.processInfo.systemUptime
        Thread.detachNewThread {
            ToolExit.leave(status: 3, deadline: 0.2, stop: {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                ending.stop()
            }, end: { status in
                ending.ended(status, ProcessInfo.processInfo.systemUptime - start)
                done.fulfill()
            })
        }
        wait(for: [done], timeout: 3)
        let (status, after, stopped) = ending.snapshot
        XCTAssertEqual(status, 3)
        XCTAssertFalse(stopped)
        XCTAssertGreaterThanOrEqual(after ?? 0, 0.2)
        XCTAssertLessThan(after ?? .infinity, 2)
    }

    /// The main thread held busy: `leave` on the kit's thread still ends,
    /// although the stop it hands the main actor cannot start.
    func testEndsAtTheDeadlineWhileTheMainThreadIsBusy() {
        let ending = Ending()
        let ended = DispatchSemaphore(value: 0)
        let start = ProcessInfo.processInfo.systemUptime
        Thread.detachNewThread {
            ToolExit.leave(status: 0, deadline: 0.2, stop: { ending.stop() }, end: { status in
                ending.ended(status, ProcessInfo.processInfo.systemUptime - start)
                ended.signal()
            })
        }
        // The test runs on the main thread, and holds it.
        XCTAssertEqual(ended.wait(timeout: .now() + 3), .success, "never ended while the main thread was busy")
        let (status, after, stopped) = ending.snapshot
        XCTAssertEqual(status, 0)
        XCTAssertFalse(stopped)
        XCTAssertLessThan(after ?? .infinity, 2)
    }

    /// Waits up to `seconds` for `pgid` to be gone; true once it is.
    private func gone(_ pgid: pid_t, within seconds: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while AgentProcess.processGroupExists(pgid) {
            if ProcessInfo.processInfo.systemUptime > deadline { return false }
            usleep(10_000)
        }
        return true
    }

    /// A chat's program that ignores SIGTERM, with one it started in its
    /// group, as the Claude helper and its `claude`: a stop cut short by the
    /// deadline leaves neither running.
    func testKillsTheChatsProgramsWhenTheDeadlineCutsTheStopShort() throws {
        let child = try AgentProcess(AgentProcessLaunchSpec(
            executable: "/bin/sh", arguments: ["-c", "trap '' TERM; /bin/sleep 30 & wait"]))
        let pgid = child.processGroupID
        defer { _ = kill(-pgid, SIGKILL) }
        XCTAssertTrue(ChildProcesses.shared.pids.contains(child.pid))
        // It does ignore a polite ask.
        usleep(100_000)
        _ = kill(-pgid, SIGTERM)
        XCTAssertFalse(gone(pgid, within: 0.3), "the fake chat program ended on SIGTERM")

        let ended = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            ToolExit.leave(status: 0, deadline: 0.2, stop: {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }, end: { _ in ended.signal() })
        }
        XCTAssertEqual(ended.wait(timeout: .now() + 3), .success)
        XCTAssertTrue(gone(pgid, within: 2), "the chat's programs outlived the tool's end")
        XCTAssertFalse(ChildProcesses.shared.pids.contains(child.pid), "a reaped program was kept")
    }

    /// A stop that finishes in time kills nothing.
    func testAStopThatFinishesKillsNothing() throws {
        let children = ChildProcesses()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }
        children.add(process.processIdentifier, leadsGroup: false)
        let ended = expectation(description: "ended")
        Thread.detachNewThread {
            ToolExit.leave(status: 0, deadline: 5, children: children, stop: {}, end: { _ in ended.fulfill() })
        }
        wait(for: [ended], timeout: 5)
        XCTAssertTrue(process.isRunning, "a program was killed although the stop finished")
    }

    /// A program in the caller's own group, as a provider's command is, is
    /// killed alone: the group would be the tool itself.
    func testKillAllKillsAProgramThatSharesTheCallersGroup() throws {
        let children = ChildProcesses()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; while :; do /bin/sleep 1; done"]
        try process.run()
        children.add(process.processIdentifier, leadsGroup: false)
        XCTAssertEqual(children.killAll(), 1)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
        XCTAssertEqual(process.terminationStatus, SIGKILL)
    }

    /// `exit` would run every atexit handler, CoreAnalytics' among them,
    /// which waits on analyticsd. `endProcess` runs none, and keeps the status.
    func testEndProcessSkipsTheAtexitHandlers() throws {
        var fds: [Int32] = [-1, -1]
        XCTAssertEqual(pipe(&fds), 0)
        let child = forkProcess()
        if child == 0 {
            close(fds[0])
            handlerPipe = fds[1]
            atexit {
                var byte: UInt8 = 1
                _ = write(handlerPipe, &byte, 1)
            }
            ToolExit.endProcess(7)
        }
        XCTAssertGreaterThan(child, 0)
        close(fds[1])
        defer { close(fds[0]) }
        var status: Int32 = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while waitpid(child, &status, WNOHANG) == 0 {
            if ProcessInfo.processInfo.systemUptime > deadline {
                kill(child, SIGKILL)
                _ = waitpid(child, &status, 0)
                return XCTFail("the child did not end within 10 seconds")
            }
            usleep(10_000)
        }
        XCTAssertEqual(status & 0x7f, 0, "the child was killed by a signal")
        XCTAssertEqual((status >> 8) & 0xff, 7)
        var byte: UInt8 = 0
        XCTAssertEqual(read(fds[0], &byte, 1), 0, "an atexit handler ran")
    }
}
