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
import NexusAgentCore
import XCTest

/// Claude Code in the Standard or Accept edits mode asks before a tool runs:
/// it reads the prompt as stream-json on standard input, prints a
/// `can_use_tool` control request, and waits for the answer on the same
/// input. Shapes from Claude Code 2.1.306, probed live.
@MainActor
final class BidirectionalApprovalTests: XCTestCase {
    private static let askBash = #"{"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool","tool_name":"Bash","display_name":"Bash","input":{"command":"echo probe-ok > out.txt","description":"Write"},"tool_use_id":"toolu_1"}}"#
    private static let askBashAgain = #"{"type":"control_request","request_id":"req-2","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"},"tool_use_id":"toolu_2"}}"#
    private static let askWrite = #"{"type":"control_request","request_id":"req-3","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/r/x"},"tool_use_id":"toolu_3"}}"#
    private static let result = #"{"type":"result","subtype":"success","stop_reason":"end_turn","session_id":"s1","result":"done"}"#

    private func json(_ data: Data) throws -> [String: Any] {
        XCTAssertEqual(data.last, 0x0A, "one line, ended")
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func claude(_ mode: NexusAgentApprovalMode) -> NexusAgentConfiguration {
        NexusAgentConfiguration(approvalMode: mode, activeProvider: .claude)
    }

    private func feed(_ rig: ComposerRig, _ lines: String...) {
        for line in lines { rig.agentOutput?(Data((line + "\n").utf8)) }
    }

    // MARK: - Parsing and the wire format

    func testACanUseToolRequestCarriesItsRequestID() {
        XCTAssertEqual(NexusAgentStreamEvent.parseAll(Self.askBash), [.approval(NexusAgentApprovalRequest(
            id: "toolu_1", toolName: "Bash", commandOrPath: "echo probe-ok > out.txt", status: .pending,
            requestID: "req-1"))])
    }

    func testAllowAndDenyAreControlResponses() throws {
        let request = NexusAgentApprovalRequest(toolName: "Bash", commandOrPath: "ls", requestID: "req-1")
        for decision in [NexusAgentApprovalRequest.Status.approved, .sessionAllowed] {
            let line = try json(XCTUnwrap(NexusAgentSupport.approvalResponseJSON(for: request, decision: decision)))
            XCTAssertEqual(line["type"] as? String, "control_response")
            let response = try XCTUnwrap(line["response"] as? [String: Any])
            XCTAssertEqual(response["subtype"] as? String, "success")
            XCTAssertEqual(response["request_id"] as? String, "req-1")
            XCTAssertEqual(response["response"] as? [String: String], ["behavior": "allow"])
        }
        let denied = try json(XCTUnwrap(NexusAgentSupport.approvalResponseJSON(for: request, decision: .denied)))
        let answer = try XCTUnwrap((denied["response"] as? [String: Any])?["response"] as? [String: Any])
        XCTAssertEqual(answer["behavior"] as? String, "deny")
        XCTAssertNotNil(answer["message"] as? String, "a deny tells the model why")
    }

    func testNothingIsSentWithoutARequestIDOrADecision() {
        let unanswerable = NexusAgentApprovalRequest(toolName: "Bash", commandOrPath: "ls")
        XCTAssertNil(NexusAgentSupport.approvalResponseJSON(for: unanswerable, decision: .approved))
        let pending = NexusAgentApprovalRequest(toolName: "Bash", commandOrPath: "ls", requestID: "r")
        XCTAssertNil(NexusAgentSupport.approvalResponseJSON(for: pending, decision: .pending))
    }

    func testThePromptIsOneStreamJSONUserMessage() throws {
        let line = try json(NexusAgentSupport.stdinUserMessage("hi \"there\""))
        XCTAssertEqual(line["type"] as? String, "user")
        let message = try XCTUnwrap(line["message"] as? [String: Any])
        XCTAssertEqual(message["role"] as? String, "user")
        XCTAssertEqual(message["content"] as? String, "hi \"there\"")
    }

    // MARK: - Which turns ask

    func testOnlyClaudeInAnAskingModeReadsStandardInput() {
        for mode in [NexusAgentApprovalMode.standard, .acceptEdits] {
            let args = NexusAgentSupport.agentArguments(prompt: "hi", configuration: claude(mode), conversationID: nil)
            XCTAssertEqual(Array(args.prefix(5)), ["-p", "--input-format", "stream-json", "--permission-prompt-tool", "stdio"])
            XCTAssertFalse(args.contains("hi"), "the prompt goes on standard input, not the command line")
        }
        for mode in [NexusAgentApprovalMode.yolo, .plan] {
            let args = NexusAgentSupport.agentArguments(prompt: "hi", configuration: claude(mode), conversationID: nil)
            XCTAssertEqual(Array(args.prefix(2)), ["-p", "hi"])
            XCTAssertFalse(args.contains("--input-format"))
        }
        let planned = NexusAgentSupport.agentArguments(prompt: "hi", configuration: claude(.standard),
                                                       conversationID: nil, planMode: true)
        XCTAssertFalse(planned.contains("--input-format"), "plan mode runs no tools, so asks nothing")
        let agy = NexusAgentConfiguration(approvalMode: .standard, activeProvider: .antigravity)
        XCTAssertFalse(NexusAgentSupport.agentArguments(prompt: "hi", configuration: agy, conversationID: nil)
            .contains("--input-format"))
    }

    // MARK: - The session answers on standard input

    func testTheTurnSendsItsPromptAndClosesItsInputAtTheResult() throws {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("hello", configuration: claude(.standard), agentPath: "/bin/claude")
        XCTAssertEqual(rig.inputs.count, 1)
        let first = try json(rig.inputs[0])
        XCTAssertEqual((first["message"] as? [String: Any])?["content"] as? String, "hello")
        XCTAssertEqual(rig.inputCloses, 0, "open while the turn may still ask")
        feed(rig, Self.result)
        XCTAssertEqual(rig.inputCloses, 1, "Claude waits for more input until it ends")
    }

    func testAllowAndDenyUnblockTheWaitingAgent() throws {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("go", configuration: claude(.standard), agentPath: "/bin/claude")
        feed(rig, Self.askBash)
        let card = try XCTUnwrap(session.messages.last(where: { $0.approvalRequest != nil }))
        XCTAssertEqual(card.approvalRequest?.status, .pending)
        XCTAssertEqual(rig.inputs.count, 1, "nothing is sent before the user decides")
        session.decideApproval(messageID: card.id, decision: .approved)
        XCTAssertEqual(rig.inputs.count, 2)
        let allow = try json(rig.inputs[1])
        XCTAssertEqual((allow["response"] as? [String: Any])?["request_id"] as? String, "req-1")
        session.decideApproval(messageID: card.id, decision: .denied)
        XCTAssertEqual(rig.inputs.count, 2, "a decided card is not answered twice")

        feed(rig, Self.askWrite)
        let second = try XCTUnwrap(session.messages.last(where: { $0.approvalRequest?.requestID == "req-3" }))
        session.decideApproval(messageID: second.id, decision: .denied)
        let deny = try json(rig.inputs[2])
        let answer = (deny["response"] as? [String: Any])?["response"] as? [String: Any]
        XCTAssertEqual(answer?["behavior"] as? String, "deny")
        XCTAssertEqual(session.messages.first(where: { $0.id == second.id })?.approvalRequest?.status, .denied)
    }

    func testAllowForSessionAnswersTheSameToolByItself() throws {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("go", configuration: claude(.standard), agentPath: "/bin/claude")
        feed(rig, Self.askBash)
        let card = try XCTUnwrap(session.messages.last(where: { $0.approvalRequest != nil }))
        session.decideApproval(messageID: card.id, decision: .sessionAllowed)
        XCTAssertEqual(session.sessionAllowedTools, ["Bash"])
        XCTAssertEqual(rig.inputs.count, 2)

        feed(rig, Self.askBashAgain)
        XCTAssertEqual(rig.inputs.count, 3, "answered without asking")
        let auto = try json(rig.inputs[2])
        let response = auto["response"] as? [String: Any]
        XCTAssertEqual(response?["request_id"] as? String, "req-2")
        XCTAssertEqual((response?["response"] as? [String: Any])?["behavior"] as? String, "allow")
        let shown = session.messages.compactMap(\.approvalRequest).first(where: { $0.requestID == "req-2" })
        XCTAssertEqual(shown?.status, .sessionAllowed)

        feed(rig, Self.askWrite)
        XCTAssertEqual(rig.inputs.count, 3, "another tool is still asked about")

        session.newChat()
        XCTAssertTrue(session.sessionAllowedTools.isEmpty, "a new chat asks again")
    }

    func testParallelRequestsEachKeepTheirCard() throws {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("go", configuration: claude(.standard), agentPath: "/bin/claude")
        feed(rig, Self.askBash, Self.askWrite)
        let cards = session.messages.compactMap(\.approvalRequest)
        XCTAssertEqual(cards.map(\.requestID), ["req-1", "req-3"])
        for message in session.messages where message.approvalRequest != nil {
            session.decideApproval(messageID: message.id, decision: .approved)
        }
        XCTAssertEqual(rig.inputs.count, 3, "prompt, then one answer per request")
    }

    func testAYoloTurnWritesNothing() {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("go", configuration: claude(.yolo), agentPath: "/bin/claude")
        XCTAssertTrue(rig.inputs.isEmpty)
    }
}
