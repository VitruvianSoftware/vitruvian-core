// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import XCTest

@testable import GitHubToolCore

final class AuthTests: XCTestCase {
    func testTheCLIsHostsFileGivesItsLoginAndToken() {
        let account = CLIAccount.parse("""
            github.com:
                user: james
                oauth_token: gho_abc
                git_protocol: https
            """)
        XCTAssertEqual(account?.login, "james")
        XCTAssertEqual(account?.token, "gho_abc")
        XCTAssertNil(CLIAccount.parse("github.com:\n    user: james\n"), "no token, no account")
        XCTAssertEqual(CLIAccount.parse("github.com:\n    oauth_token: gho_x\n")?.login, "", "a token without a user")
        XCTAssertNil(CLIAccount.read(hostsFile: URL(fileURLWithPath: "/nonexistent/hosts.yml")))
    }

    func testTheHomeFolderIsTheEnvironmentsFirst() {
        let before = ProcessInfo.processInfo.environment["HOME"]
        defer { if let before { setenv("HOME", before, 1) } else { unsetenv("HOME") } }
        setenv("HOME", "/tmp/a-scratch-home", 1)
        XCTAssertEqual(Paths.home, "/tmp/a-scratch-home")
        XCTAssertEqual(CLIAccount.defaultHostsURL.path, "/tmp/a-scratch-home/.config/gh/hosts.yml",
                       "a test's scratch home never finds the person's real login")
        setenv("HOME", "", 1)
        XCTAssertEqual(Paths.home, NSHomeDirectory(), "an empty HOME is the account's")
    }

    func testDeviceFlowStateMachine() {
        let start = Date(timeIntervalSince1970: 1_000)
        let code = DeviceCode(deviceCode: "dev", userCode: "ABCD-1234", verificationURI: URL(string: "https://github.com/login/device")!,
                              expiresIn: 900, interval: 5)
        var flow = DeviceFlowState.idle.next(.start, now: start)
        XCTAssertEqual(flow, .requestingCode)
        flow = flow.next(.codeIssued(code), now: start)
        guard case .awaitingUser(let waiting) = flow else { return XCTFail("\(flow)") }
        XCTAssertEqual(waiting.userCode, "ABCD-1234")
        XCTAssertEqual(waiting.nextPollAt, start.addingTimeInterval(5))
        XCTAssertEqual(waiting.expiresAt, start.addingTimeInterval(900))
        XCTAssertFalse(flow.shouldPoll(now: start.addingTimeInterval(4)))
        XCTAssertTrue(flow.shouldPoll(now: start.addingTimeInterval(5)))
        flow = flow.next(.poll(.slowDown), now: start.addingTimeInterval(5))
        guard case .awaitingUser(let slower) = flow else { return XCTFail("\(flow)") }
        XCTAssertEqual(slower.interval, 10, "slow_down adds five seconds")
        XCTAssertEqual(slower.nextPollAt, start.addingTimeInterval(15))
        XCTAssertEqual(flow.next(.poll(.pending), now: start.addingTimeInterval(1_000)), .failed(.expired),
                       "a poll after the expiry is expired, whatever it says")
        XCTAssertEqual(flow.next(.tick, now: start.addingTimeInterval(901)), .failed(.expired))
        XCTAssertEqual(flow.next(.poll(.denied), now: start.addingTimeInterval(20)), .failed(.denied))
        XCTAssertEqual(flow.next(.poll(.token(AccessToken("gho_t"))), now: start.addingTimeInterval(20)),
                       .authorized(AccessToken("gho_t")))
        XCTAssertEqual(flow.next(.cancel, now: start), .idle)
        XCTAssertEqual(DeviceFlowState.requestingCode.next(.codeRequestFailed("device_flow_disabled"), now: start),
                       .failed(.other("device_flow_disabled")))
        XCTAssertEqual(DeviceFlowState.failed(.denied).next(.start, now: start), .requestingCode)
        XCTAssertEqual(DeviceFlowState.idle.next(.tick, now: start), .idle, "an input a state does not take changes nothing")
    }

    func testPollResultsReadGitHubsErrors() {
        XCTAssertEqual(DevicePollResult(errorCode: "authorization_pending"), .pending)
        XCTAssertEqual(DevicePollResult(errorCode: "slow_down"), .slowDown)
        XCTAssertEqual(DevicePollResult(errorCode: "access_denied"), .denied)
        XCTAssertEqual(DevicePollResult(errorCode: "expired_token"), .expired)
        XCTAssertEqual(DevicePollResult(errorCode: "token_expired"), .expired)
        XCTAssertEqual(DevicePollResult(errorCode: "weird"), .failure("weird"))
    }
}
