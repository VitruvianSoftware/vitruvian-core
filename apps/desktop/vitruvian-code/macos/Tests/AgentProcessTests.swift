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

import Darwin
import Foundation
import os
@testable import VitruvianCodeCore
import XCTest

final class AgentProcessTests: XCTestCase {
    private static func pidExists(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func nextLine(from stream: AsyncStream<Data>, timeout: TimeInterval = 3.0) async throws -> String {
        let lines = AgentProcess.lines(from: stream)
        return try await withACPTestTimeout(seconds: timeout, description: "process stdout line") {
            var iterator = lines.makeAsyncIterator()
            return await iterator.next() ?? ""
        }
    }

    func testDefaultTerminationGraceMatchesT3Code() {
        // `AcpSessionRuntime.ts:1611`: `processGroupTerminationGrace ?? "1 second"`.
        XCTAssertEqual(AgentProcess.defaultTerminationGrace, 1.0)
    }

    func testTerminateEndsBothChildAndGrandchildInOwnProcessGroup() async throws {
        let process = try AgentProcess(
            AgentProcessLaunchSpec(
                executable: "/bin/sh",
                arguments: ["-c", "sleep 60 & echo $!; wait"]
            )
        )
        let grandchildLine = try await Self.nextLine(from: process.stdout)
        guard let grandchildPID = Int32(grandchildLine.trimmingCharacters(in: .whitespacesAndNewlines)),
              grandchildPID > 0 else {
            await process.terminate(grace: 0.1)
            XCTFail("Expected grandchild PID on stdout, got '\(grandchildLine)'")
            return
        }

        // Child was spawned in its own process group (`pgid == child.pid`), and grandchild inherited it.
        XCTAssertEqual(getpgid(process.pid), process.pid)
        XCTAssertEqual(getpgid(grandchildPID), process.pid)
        XCTAssertTrue(Self.pidExists(process.pid))
        XCTAssertTrue(Self.pidExists(grandchildPID))

        try await withACPTestTimeout(seconds: 3.0, description: "terminate child + grandchild") {
            await process.terminate(grace: 0.15)
        }

        // Poll briefly for the kernel to reap any reparented grandchild after SIGTERM/SIGKILL.
        try await withACPTestTimeout(seconds: 2.0, description: "grandchild reap") {
            while Self.pidExists(process.pid) || Self.pidExists(grandchildPID)
                || AgentProcess.processGroupExists(process.processGroupID) {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        XCTAssertFalse(Self.pidExists(process.pid))
        XCTAssertFalse(Self.pidExists(grandchildPID))
        XCTAssertFalse(AgentProcess.processGroupExists(process.processGroupID))
    }

    /// A write blocked on a full stdin pipe holds the input lock. Terminate
    /// must still signal the group (and so free the write), not wait on that
    /// lock to close stdin first.
    func testTerminateEndsGroupWhileAStdinWriteIsBlockedOnAFullPipe() async throws {
        let process = try AgentProcess(
            AgentProcessLaunchSpec(
                executable: "/bin/sh",
                arguments: ["-c", "echo ready; exec sleep 60"]
            )
        )
        let realPGID = process.pid
        defer { _ = Darwin.kill(-realPGID, SIGKILL) }

        let readyLine = try await Self.nextLine(from: process.stdout)
        XCTAssertEqual(readyLine.trimmingCharacters(in: .whitespacesAndNewlines), "ready")

        // 1 MiB is far more than a pipe buffer; nobody reads it, so this blocks.
        let writeReturned = OSAllocatedUnfairLock(initialState: false)
        Thread.detachNewThread {
            process.sendInput(Data(count: 1 << 20))
            writeReturned.withLock { $0 = true }
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(writeReturned.withLock { $0 }, "The write should still be blocked on the full pipe")

        try await withACPTestTimeout(seconds: 3.0, description: "terminate with a blocked stdin write") {
            await process.terminate(grace: 0.1)
        }
        XCTAssertFalse(AgentProcess.processGroupExists(process.processGroupID))

        let deadline = ProcessInfo.processInfo.systemUptime + 2.0
        while !writeReturned.withLock({ $0 }) && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(writeReturned.withLock { $0 }, "Ending the group should fail the blocked write")
    }

    func testChildIgnoringSIGTERMIsKilledAfterShortGracePeriod() async throws {
        let process = try AgentProcess(
            AgentProcessLaunchSpec(
                executable: "/bin/sh",
                arguments: ["-c", "trap '' TERM; echo ready; while :; do sleep 1; done"]
            )
        )
        let realPGID = process.pid
        defer { _ = Darwin.kill(-realPGID, SIGKILL) }

        let readyLine = try await Self.nextLine(from: process.stdout)
        XCTAssertEqual(readyLine.trimmingCharacters(in: .whitespacesAndNewlines), "ready")

        let startUptime = ProcessInfo.processInfo.systemUptime
        try await withACPTestTimeout(seconds: 3.0, description: "terminate SIGTERM-ignoring process") {
            await process.terminate(grace: 0.12)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - startUptime

        let exit = try await withACPTestTimeout(seconds: 1.0, description: "waitForExit") {
            try await process.waitForExit(timeout: 0.5)
        }
        XCTAssertGreaterThanOrEqual(elapsed, 0.10, "Should wait for the grace window before sending SIGKILL")
        XCTAssertEqual(exit.signal, SIGKILL)
        XCTAssertEqual(exit.signalName, "SIGKILL")
        XCTAssertFalse(AgentProcess.processGroupExists(process.processGroupID))
    }

    func testDroppingSIGKILLFailsFastWithoutHanging() async throws {
        let process = try AgentProcess(
            AgentProcessLaunchSpec(
                executable: "/bin/sh",
                arguments: ["-c", "trap '' TERM; echo ready; while :; do sleep 1; done"]
            ),
            signalProcessGroup: { pgid, sig in
                if sig == SIGKILL {
                    return 0
                }
                return Darwin.kill(-pgid, sig)
            }
        )
        let realPGID = process.pid
        defer { _ = Darwin.kill(-realPGID, SIGKILL) }

        let readyLine = try await Self.nextLine(from: process.stdout)
        XCTAssertEqual(readyLine.trimmingCharacters(in: .whitespacesAndNewlines), "ready")

        let startUptime = ProcessInfo.processInfo.systemUptime
        await process.terminate(grace: 0.05, postKillTimeout: 0.08)
        do {
            _ = try await process.waitForExit(timeout: 0.08)
            XCTFail("waitForExit must fail fast with waitTimedOut when SIGKILL is dropped")
        } catch let error as AgentProcessError {
            XCTAssertEqual(error, .waitTimedOut(0.08))
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
        XCTAssertLessThan(elapsed, 2.0, "Dropped SIGKILL must fail fast instead of hanging")

        // Also prove `withACPTestTimeout` returns immediately even when an operation hangs in an uncancelled continuation.
        let parked = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)
        defer {
            parked.withLock { cont in
                cont?.resume()
                cont = nil
            }
        }
        let timeoutStart = ProcessInfo.processInfo.systemUptime
        do {
            try await withACPTestTimeout(
                seconds: 0.06,
                description: "simulated hung continuation",
                recordFailureOnTimeout: false
            ) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    parked.withLock { $0 = continuation }
                }
            }
            XCTFail("withACPTestTimeout must throw on hung continuation")
        } catch let error as ACPTestTimeoutError {
            XCTAssertEqual(error, .timedOut(description: "simulated hung continuation", seconds: 0.06))
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - timeoutStart, 1.0)
    }

    func testWorkingDirectoryEnvironmentAndStdinPipeRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var env = ProcessInfo.processInfo.environment
        env["ACP_TEST_TOKEN"] = "hello-env"

        let process = try AgentProcess(
            AgentProcessLaunchSpec(
                executable: "/bin/sh",
                arguments: ["-c", "pwd; printf '%s\\n' \"$ACP_TEST_TOKEN\"; cat"],
                environment: env,
                workingDirectory: tempDir.path
            )
        )
        try process.write(Data("from-stdin\n".utf8))
        process.closeInput()

        let collectedLines = try await withACPTestTimeout(seconds: 3.0, description: "collect stdout lines") {
            var out: [String] = []
            for await line in AgentProcess.lines(from: process.stdout) {
                out.append(line)
            }
            return out
        }
        let exit = try await withACPTestTimeout(seconds: 2.0, description: "waitForExit") {
            try await process.waitForExit(timeout: 2.0)
        }

        XCTAssertEqual(exit, AgentProcessExit(exitCode: 0, signal: nil))
        XCTAssertEqual(collectedLines.count, 3)
        XCTAssertEqual(
            ACPClientFiles.canonicalPathForContainment(collectedLines[0]),
            ACPClientFiles.canonicalPathForContainment(tempDir.path)
        )
        XCTAssertEqual(collectedLines[1], "hello-env")
        XCTAssertEqual(collectedLines[2], "from-stdin")
    }
}
