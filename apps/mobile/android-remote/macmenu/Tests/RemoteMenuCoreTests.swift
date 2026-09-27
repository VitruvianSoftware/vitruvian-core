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
import RemoteMenuCore
import XCTest

final class RemoteMenuCoreTests: XCTestCase {
    // Captured from a live agent (v1.8.0) on 2026-09-26.
    let healthJSON = #"{"agent_version":"1.8.0","notify":{"configured":true,"enabled":false,"topic":"vitruvian-remote"},"ok":true,"paired":true,"read_only":false,"sample_age_ms":553,"sampled_at":"2026-09-26T17:43:08.54898-07:00"}"#
    let noPhoneJSON = #"{"connected":false,"device":null,"since":null,"tools":[],"trust_until":null}"#
    let phoneJSON = #"{"connected":true,"device":{"model":"Pixel Fold","android":"16"},"since":"2026-09-26T17:02:00.123-07:00","tools":["sms.list"],"trust_until":null}"#

    func decode<T: Decodable>(_ s: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(s.utf8))
    }

    func testDecodesLiveHealth() throws {
        let h: AgentHealth = try decode(healthJSON)
        XCTAssertTrue(h.ok)
        XCTAssertTrue(h.paired)
        XCTAssertEqual(h.agentVersion, "1.8.0")
        XCTAssertEqual(h.notify, .init(configured: true, enabled: false))
    }

    func testClassify() {
        let ok = AgentHealth(ok: true, agentVersion: "1.8.0", paired: true)
        let stale = AgentHealth(ok: false, agentVersion: "1.8.0", paired: true)
        XCTAssertEqual(StatusSnapshot.classify(installed: false, status: nil, health: nil), .notInstalled)
        XCTAssertEqual(StatusSnapshot.classify(installed: true, status: nil, health: nil), .down)
        XCTAssertEqual(StatusSnapshot.classify(installed: true, status: 200, health: ok), .running(version: "1.8.0"))
        // /healthz answers 503 with a body while readings are old.
        XCTAssertEqual(StatusSnapshot.classify(installed: true, status: 503, health: stale), .stale(version: "1.8.0"))
        // An answer we can't parse is alive but not healthy, never "running".
        XCTAssertEqual(StatusSnapshot.classify(installed: true, status: 200, health: nil), .stale(version: nil))
    }

    func testAgentLine() {
        XCTAssertEqual(StatusSnapshot(state: .running(version: "1.8.0")).agentLine, "Agent running · v1.8.0")
        XCTAssertEqual(StatusSnapshot(state: .running(version: nil)).agentLine, "Agent running")
        XCTAssertEqual(StatusSnapshot(state: .down).agentLine, "Agent not responding")
        XCTAssertEqual(StatusSnapshot(state: .notInstalled).agentLine, "Agent not installed")
    }

    func testPhoneLine() throws {
        let health: AgentHealth = try decode(healthJSON)
        let running = AgentState.running(version: "1.8.0")

        XCTAssertEqual(StatusSnapshot(state: running, health: health, phone: try decode(noPhoneJSON)).phoneLine(),
                       "Phone paired, not connected")

        var unpaired = health
        unpaired.paired = false
        XCTAssertEqual(StatusSnapshot(state: running, health: unpaired, phone: try decode(noPhoneJSON)).phoneLine(),
                       "No phone paired")

        let linked = try XCTUnwrap(StatusSnapshot(state: running, health: health, phone: try decode(phoneJSON)).phoneLine())
        XCTAssertTrue(linked.hasPrefix("Pixel Fold connected since "), linked)

        // Nothing is claimed about a phone while the agent can't be asked.
        XCTAssertNil(StatusSnapshot(state: .down, health: health, phone: try decode(phoneJSON)).phoneLine())
    }

    func testNotificationsLine() {
        func line(_ n: AgentHealth.Notify?) -> String? {
            StatusSnapshot(state: .running(version: nil), health: AgentHealth(ok: true, paired: true, notify: n)).notificationsLine
        }
        XCTAssertEqual(line(.init(configured: true, enabled: true)), "Push notifications on")
        XCTAssertEqual(line(.init(configured: true, enabled: false)), "Push notifications off")
        XCTAssertEqual(line(.init(configured: false, enabled: false)), "Push notifications not set up")
        XCTAssertNil(line(nil))
    }

    func testPairCode() {
        XCTAssertEqual(PairCode.normalize("482917"), "482917")
        XCTAssertEqual(PairCode.normalize(" 482 917 "), "482917")
        XCTAssertEqual(PairCode.normalize("482-917"), "482917")
        XCTAssertNil(PairCode.normalize("48291"))
        XCTAssertNil(PairCode.normalize("4829177"))
        XCTAssertNil(PairCode.normalize("48291a"))
        XCTAssertNil(PairCode.normalize("٤٨٢٩١٧")) // non-ASCII digits: the agent rejects these
    }

    // The other half of this check, that install.sh still writes these same
    // paths, is paths_match_installer_test.sh.
    func testPaths() {
        let p = AgentPaths(home: URL(fileURLWithPath: "/Users/x"))
        XCTAssertEqual(p.binary.path, "/Users/x/.local/bin/vitruvian-remote-agent")
        XCTAssertEqual(p.log.path, "/Users/x/Library/Logs/vitruvian-remote-agent.log")
        XCTAssertEqual(AgentPaths.label, "com.vitruvian.remote-agent")
        XCTAssertEqual(AgentPaths.restartArguments(uid: 501), ["kickstart", "-k", "gui/501/com.vitruvian.remote-agent"])
    }

    func testQRPageURL() {
        XCTAssertEqual(QRPairing.pageURL(address: "100.124.228.116", code: "482917")?.absoluteString,
                       "http://100.124.228.116:7411/pair?code=482917")
        // Only a Tailscale address and a clean six-digit code make a QR.
        XCTAssertNil(QRPairing.pageURL(address: "192.168.1.5", code: "482917"))
        XCTAssertNil(QRPairing.pageURL(address: "100.124.228.116", code: "48291"))
        XCTAssertNil(QRPairing.pageURL(address: "100.124.228.116", code: "482 917"))
    }

    func testTailscaleRange() {
        XCTAssertTrue(QRPairing.isTailscaleIPv4("100.64.0.1"))
        XCTAssertTrue(QRPairing.isTailscaleIPv4("100.127.255.254"))
        XCTAssertFalse(QRPairing.isTailscaleIPv4("100.63.255.255"))
        XCTAssertFalse(QRPairing.isTailscaleIPv4("100.128.0.1"))
        XCTAssertFalse(QRPairing.isTailscaleIPv4("10.0.0.1"))
        XCTAssertFalse(QRPairing.isTailscaleIPv4("100.64.0"))
        XCTAssertFalse(QRPairing.isTailscaleIPv4("100.64.0.256"))
    }

    func testNewCodeIsSixDigits() {
        for _ in 0..<200 {
            XCTAssertNotNil(PairCode.normalize(QRPairing.newCode()))
        }
    }

    func testTailnetLineOnlyWhenBroken() {
        XCTAssertNil(StatusSnapshot(state: .running(version: nil), tailnetReachable: true).tailnetLine)
        XCTAssertNil(StatusSnapshot(state: .running(version: nil), tailnetReachable: nil).tailnetLine)
        XCTAssertEqual(StatusSnapshot(state: .running(version: nil), tailnetReachable: false).tailnetLine,
                       "Phone can't reach it over Tailscale")
    }
}
