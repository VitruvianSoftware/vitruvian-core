// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Exercises `FoundationVitruvianSpeakerCommandRunner` against real system binaries without invoking speech output.
final class ReadAloudRunnerTests: XCTestCase {
    private let runner = FoundationVitruvianSpeakerCommandRunner()

    func testPrintfExitZeroAndStdout() async throws {
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", "hi"],
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "hi")
    }

    func testArgumentsArePassedWithoutAShell() async throws {
        let literal = "-x ; $(echo pwned) `id` 'q\"\nend"
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", literal],
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), literal)
    }

    func testLargeOutputDoesNotDeadlock() async throws {
        let started = Date()
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/head"),
            arguments: ["-c", "2000000", "/dev/zero"],
            timeout: 20
        )
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, 2_000_000)
        XCTAssertFalse(result.timedOut)
        XCTAssertLessThan(elapsed, 20)
    }

    func testTimeoutKillsSleepingProcess() async throws {
        let started = Date()
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"],
            timeout: 1
        )
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(elapsed, 10)
    }

    func testTimeoutKillsProcessIgnoringSIGTERM() async throws {
        let started = Date()
        let result = try await runner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; sleep 30"],
            timeout: 1
        )
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(elapsed, 10)
    }

    func testMissingExecutableThrows() async {
        do {
            _ = try await runner.run(
                executableURL: URL(fileURLWithPath: "/nonexistent/VitruvianSpeaker"),
                arguments: [],
                timeout: 1
            )
            XCTFail("Expected missing executable to throw")
        } catch {
            // Expected launch failure for missing binary.
        }
    }
}
