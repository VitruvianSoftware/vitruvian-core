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
import VitruvianCodeCore
import XCTest

/// What the CLIs print becomes tool steps, results,
/// slash commands and thinking; the arguments carry effort, files and
/// forks; sessions are filtered, pinned and renamed; and a turn can be
/// undone through a git checkpoint.
final class StreamParityTests: XCTestCase {
    // MARK: - Claude stream-json (shapes from Claude Code 2.1.306)

    func testAToolStartingIsActivityNotAnApproval() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"Read","input":{}}}}"#
        XCTAssertEqual(AgentEvent.parseAll(line), [.tool(name: "Read", finished: false)])
    }

    func testAnAssistantToolUseIsAStepWithItsInput() {
        let line = #"{"type":"assistant","message":{"model":"claude-haiku-5-5","content":[{"type":"tool_use","id":"toolu_1","name":"Edit","input":{"file_path":"/r/a.swift","old_string":"a","new_string":"b"}},{"type":"tool_use","id":"toolu_2","name":"Bash","input":{"command":"ls -la\nmore"}}],"usage":{"input_tokens":2,"cache_read_input_tokens":10,"output_tokens":5}}}"#
        let events = AgentEvent.parseAll(line)
        XCTAssertEqual(events.count, 3)
        guard case .contextUsage = events.first else { return XCTFail("usage first, for parse's sake: \(events)") }
        guard case .toolStep(let edit) = events[1], case .toolStep(let bash) = events[2] else {
            return XCTFail("two steps: \(events)")
        }
        XCTAssertEqual(edit.id, "toolu_1")
        XCTAssertEqual(edit.kind, .edit)
        XCTAssertEqual(edit.filePath, "/r/a.swift")
        XCTAssertEqual(edit.diffOld, "a")
        XCTAssertEqual(edit.diffNew, "b")
        XCTAssertFalse(edit.isFinished)
        XCTAssertEqual(bash.kind, .bash)
        XCTAssertEqual(bash.title, "ls -la")
        XCTAssertEqual(AgentEvent.parse(line), events.first, "parse keeps giving the first")
    }

    func testAnAssistantMessageDoesNotRepeatTheTextTheDeltasSent() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"banana"},{"type":"thinking","thinking":"hm"}]}}"#
        XCTAssertEqual(AgentEvent.parseAll(line), [])
    }

    func testAToolResultFinishesItsStep() {
        let text = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_1","type":"tool_result","content":"1\tbanana split\n"}]},"parent_tool_use_id":null}"#
        XCTAssertEqual(AgentEvent.parseAll(text),
                       [.toolStepResult(id: "toolu_1", output: "1\tbanana split\n", isError: false)])
        let parts = #"{"type":"user","message":{"content":[{"tool_use_id":"t2","type":"tool_result","is_error":true,"content":[{"type":"text","text":"no"},{"type":"text","text":"such file"}]}]}}"#
        XCTAssertEqual(AgentEvent.parseAll(parts),
                       [.toolStepResult(id: "t2", output: "no\nsuch file", isError: true)])
    }

    func testLongOutputIsCut() {
        let long = String(repeating: "x", count: 10_000)
        let cut = VitruvianCodeToolStep.truncatedOutput(long)
        XCTAssertLessThan(cut?.count ?? 0, 4_100)
        XCTAssertTrue(cut?.hasPrefix(String(repeating: "x", count: 4_000)) ?? false)
    }

    func testASubagentsLinesStayOutOfTheReply() {
        let line = #"{"type":"assistant","parent_tool_use_id":"toolu_agent","message":{"content":[{"type":"tool_use","id":"inner","name":"Read","input":{}}],"usage":{"input_tokens":2,"output_tokens":1}}}"#
        XCTAssertEqual(AgentEvent.parseAll(line), [])
    }

    func testInitGivesTheSessionAndItsSlashCommands() {
        let line = #"{"type":"system","subtype":"init","cwd":"/r","session_id":"s1","slash_commands":["compact","review","antigravity:delegate"]}"#
        XCTAssertEqual(AgentEvent.parseAll(line),
                       [.started(conversationID: "s1"), .slashCommands(["compact", "review", "antigravity:delegate"])])
        XCTAssertEqual(AgentEvent.parse(line), .started(conversationID: "s1"))
        let changed = #"{"type":"system","subtype":"commands_changed","commands":[{"name":"bitwarden","description":"x","argumentHint":""}],"session_id":"s1"}"#
        XCTAssertEqual(AgentEvent.parseAll(changed), [.started(conversationID: "s1"), .slashCommands(["bitwarden"])])
    }

    func testThinkingDeltasAndTokens() {
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me see"}}}"#
        XCTAssertEqual(AgentEvent.parseAll(delta), [.thinking("Let me see")])
        let redacted = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"","estimated_tokens":50}}}"#
        XCTAssertEqual(AgentEvent.parseAll(redacted), [])
        let tokens = #"{"type":"system","subtype":"thinking_tokens","estimated_tokens":216,"estimated_tokens_delta":166,"session_id":"s1"}"#
        XCTAssertEqual(AgentEvent.parseAll(tokens), [.thinkingTokens(216)])
        let result = #"{"type":"result","stop_reason":"end_turn","session_id":"s1","result":"ok","usage":{"input_tokens":4,"output_tokens":174,"output_tokens_details":{"thinking_tokens":105}}}"#
        let events = AgentEvent.parseAll(result)
        guard case .finished? = events.first else { return XCTFail("finished first: \(events)") }
        XCTAssertEqual(events.last, .thinkingTokens(105))
    }

    func testOnlyAnExplicitPromptIsAnApproval() {
        let request = #"{"type":"permission_request","id":"p1","tool_name":"Bash","input":{"command":"rm -rf build"}}"#
        XCTAssertEqual(AgentEvent.parseAll(request), [.approval(VitruvianCodeApprovalRequest(
            id: "p1", toolName: "Bash", commandOrPath: "rm -rf build", status: .pending))])
        let control = #"{"type":"control_request","request_id":"r1","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/r/x"},"tool_use_id":"t9"}}"#
        XCTAssertEqual(AgentEvent.parseAll(control), [.approval(VitruvianCodeApprovalRequest(
            id: "t9", toolName: "Write", commandOrPath: "/r/x", status: .pending, requestID: "r1"))])
    }

    // MARK: - agy and OpenCode live (shapes from agy 1.4.4)

    func testAnAgyToolStepAndItsResult() {
        let active = #"{"event":"step_update","step_update":{"conversation_id":"c","step_index":4,"state":"ACTIVE","step_type":"tool","tool_name":"read_file","tool_info":{"name":"read_file","parameters":{"Path":"/tmp/x.txt"}}}}"#
        guard case .toolStep(let step)? = AgentEvent.parseAll(active).first else { return XCTFail() }
        XCTAssertEqual(step.id, "agy-c-4")
        XCTAssertEqual(step.kind, .read)
        XCTAssertEqual(step.filePath, "/tmp/x.txt")
        let done = #"{"event":"step_update","step_update":{"conversation_id":"c","step_index":4,"state":"DONE","step_type":"tool","tool_name":"read_file","tool_info":{"name":"read_file","parameters":{"Path":"/tmp/x.txt"},"output":"1 lines, 13 bytes"}}}"#
        XCTAssertEqual(AgentEvent.parseAll(done).last,
                       .toolStepResult(id: "agy-c-4", output: "1 lines, 13 bytes", isError: false))
    }

    func testAnOpenCodeToolPartIsAStep() {
        let line = #"{"type":"tool_use","sessionID":"ses","part":{"tool":"bash","callID":"call_1","state":{"status":"completed","input":{"command":"pwd"},"output":"/r\n"}}}"#
        let events = AgentEvent.parseAll(line)
        guard case .toolStep(let step)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(step.kind, .bash)
        XCTAssertEqual(events.last, .toolStepResult(id: "call_1", output: "/r\n", isError: false))
    }

    // MARK: - Tool step mapping

    func testToolNamesMapToKindsForEveryProvider() {
        let cases: [(String, VitruvianCodeToolStep.Kind)] = [
            ("Edit", .edit), ("MultiEdit", .edit), ("str_replace", .edit), ("edit", .edit),
            ("replace_file_content", .edit), ("Write", .write), ("write", .write), ("create", .write),
            ("write_to_file", .write), ("Bash", .bash), ("shell", .bash), ("run_command", .bash),
            ("Read", .read), ("view", .read), ("view_file", .read), ("Grep", .search), ("Glob", .search),
            ("search", .search), ("find", .search), ("list", .search), ("grep_search", .search),
            ("Agent", .subagent), ("Task", .subagent), ("invoke_subagent", .subagent),
            ("WebFetch", .other), ("todowrite", .other),
        ]
        for (name, kind) in cases {
            XCTAssertEqual(VitruvianCodeToolStep.kind(forToolNamed: name), kind, name)
        }
    }

    func testInputKeysOfEveryProvider() {
        let claude = VitruvianCodeToolStep.from(id: "1", name: "Write", input: ["file_path": "/a", "content": "hi"])
        XCTAssertEqual([claude.filePath, claude.diffNew], ["/a", "hi"])
        let opencode = VitruvianCodeToolStep.from(id: "2", name: "edit",
                                               input: ["filePath": "/b", "oldString": "x", "newString": "y"])
        XCTAssertEqual([opencode.filePath, opencode.diffOld, opencode.diffNew], ["/b", "x", "y"])
        // agy writes arguments as JSON text.
        let agy = VitruvianCodeToolStep.from(id: "3", name: "write_to_file",
                                          input: ["TargetFile": "\"/c\"", "CodeContent": "\"line\\nline2\""])
        XCTAssertEqual([agy.filePath, agy.diffNew], ["/c", "line\nline2"])
        let multi = VitruvianCodeToolStep.from(id: "4", name: "MultiEdit", input: [
            "file_path": "/d", "edits": [["old_string": "a", "new_string": "b"], ["old_string": "c", "new_string": "d"]],
        ])
        XCTAssertEqual(multi.diffOld, "a\n…\nc")
        let read = VitruvianCodeToolStep.from(id: "5", name: "Read", input: ["file_path": "/e", "content": "no"])
        XCTAssertNil(read.diffNew, "only edits and writes have a diff")
        let agent = VitruvianCodeToolStep.from(id: "6", name: "Agent", input: ["description": "Review it", "prompt": "…"])
        XCTAssertEqual(agent.title, "Review it")
    }

    // MARK: - Subagents

    func testAgentAndTaskSubagentsRunUntilTheirResult() {
        let spawn = { (name: String, id: String) in
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":{"subagent_type":"scout","description":"Watch CI","prompt":"go"}}]}}"#
        }
        let progress = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Completed the first step; Watch CI is still going."}]}}"#
        var transcript = [spawn("Agent", "a1"), spawn("Task", "t1"), progress].joined(separator: "\n")
        XCTAssertEqual(VitruvianCodeEngine.parseActiveSubagents(from: transcript).map(\.id), ["a1", "t1"],
                       "both names start one, and 'Completed' in text finishes neither")
        transcript += "\n" + #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a1","content":"done"}]}}"#
        XCTAssertEqual(VitruvianCodeEngine.parseActiveSubagents(from: transcript).map(\.id), ["t1"])
        transcript += "\n" + #"{"type":"user","message":{"content":"next question"}}"#
        XCTAssertEqual(VitruvianCodeEngine.parseActiveSubagents(from: transcript), [], "the turn ended")
    }

    func testAgySubagentsFinishByTheirOwnMessage() {
        let lines = [
            #"{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"invoke_subagent","args":{"Model":"\"flash\"","Prompt":"\"Watch PR\"","Role":"\"PR monitor\"","TypeName":"\"scout\""}}]}"#,
            #"{"type":"GENERIC","source":"MODEL","content":"Created At: x\nCompleted At: y\nCreated the following subagent:\n{\n  \"conversationId\": \"conv-9\",\n  \"workspaceUris\": []\n}"}"#,
            #"{"type":"GENERIC","source":"MODEL","content":"Created At: x\nCompleted At: y\nPR monitor output"}"#,
        ]
        let running = VitruvianCodeEngine.parseActiveSubagents(from: lines.joined(separator: "\n"))
        XCTAssertEqual(running.map(\.typeName), ["scout"], "Completed At: in a tool result finishes nothing")
        let done = lines + [#"{"type":"SYSTEM_MESSAGE","content":"<SYSTEM_MESSAGE>\n[Message] timestamp=t sender=conv-9 priority=HIGH content=finished"}"#]
        XCTAssertEqual(VitruvianCodeEngine.parseActiveSubagents(from: done.joined(separator: "\n")), [])
    }

    /// Two agy subagents, PR monitor (conv-1) and CI watch (conv-2), still at work.
    private static let twoAgySubagents = [
        #"{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"invoke_subagent","args":{"Model":"\"flash\"","Prompt":"\"Watch PR\"","Role":"\"PR monitor\"","TypeName":"\"self\""}}]}"#,
        #"{"type":"GENERIC","source":"MODEL","content":"Created At: x\nCompleted At: y\nCreated the following subagent:\n{\n  \"conversationId\":  \"conv-1\"\n}"}"#,
        #"{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"invoke_subagent","args":{"Model":"\"flash\"","Prompt":"\"Watch CI\"","Role":"\"CI watch\"","TypeName":"\"self\""}}]}"#,
        #"{"type":"GENERIC","source":"MODEL","content":"Created At: x\nCompleted At: y\nCreated the following subagent:\n{\n  \"conversationId\":  \"conv-2\"\n}"}"#,
    ]

    private func running(after lines: [String]) -> [String] {
        VitruvianCodeEngine.parseActiveSubagents(from: (Self.twoAgySubagents + lines).joined(separator: "\n")).map(\.role)
    }

    func testAgySubagentsThatWereKilledAreNoLongerRunning() {
        XCTAssertEqual(running(after: []), ["PR monitor", "CI watch"])
        // What agy's manage_subagents kill_all gives back, as in a real transcript.
        XCTAssertEqual(running(after: [
            #"{"type":"GENERIC","source":"MODEL","content":"Created At: x\nCompleted At: y\nSuccessfully killed 2 subagent(s) and their descendants.\nKilled roles: PR monitor, CI watch"}"#,
        ]), [], "a killed subagent never sends a message back")
        XCTAssertEqual(running(after: [
            #"{"type":"GENERIC","source":"MODEL","content":"Created At: x\nCompleted At: y\nSuccessfully killed 1 subagent(s) and their descendants.\nKilled roles: CI watch"}"#,
        ]), ["PR monitor"], "only the roles it names")
    }

    func testAgySubagentsStopWhenAgyRestarts() {
        XCTAssertEqual(running(after: [
            #"{"type":"SYSTEM_MESSAGE","content":"<SYSTEM_MESSAGE>\n[Message] timestamp=t sender=system priority=MESSAGE_PRIORITY_LOW content=[Notice] All your subagents and background tasks have been stopped due to server restart.\n</SYSTEM_MESSAGE>"}"#,
        ]), [])
    }

    func testAgysOwnListOfActiveSubagentsIsBelieved() {
        XCTAssertEqual(running(after: [
            #"{"type":"GENERIC","source":"MODEL","content":"Created At: x\nCompleted At: y\nYou have 1 active subagent(s):\n[{\"role\":\"CI watch\",\"type\":\"self\",\"conversationId\":\"conv-2\",\"state\":\"running\"}]"}"#,
        ]), ["CI watch"], "one agy no longer lists has finished")
        XCTAssertEqual(running(after: [
            #"{"type":"GENERIC","source":"MODEL","content":"Created At: x\nCompleted At: y\nYou have 0 active subagent(s)."}"#,
        ]), [])
    }

    func testAClaudeTranscriptStepCarriesItsResult() throws {
        let transcript = [
            #"{"type":"user","message":{"content":"read it"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/x"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"banana"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"ls"}},{"type":"text","text":"Found it."}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":"file.txt"}]}}"#,
        ].joined(separator: "\n")
        let messages = try XCTUnwrap(VitruvianCodeEngine.parseClaudeTranscript(transcript))
        XCTAssertEqual(messages.count, 2, "consecutive assistant steps in one turn coalesce into a single reply bubble")
        let steps = try XCTUnwrap(messages.last?.toolSteps)
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].kind, .read)
        XCTAssertEqual(steps[0].output, "banana")
        XCTAssertEqual(steps[1].kind, .bash)
        XCTAssertEqual(steps[1].output, "file.txt")
        XCTAssertEqual(messages.last?.text, "Found it.")
    }

    func testMergingTranscriptReloadPreservesInMemoryTurnMetrics() {
        let liveUser = VitruvianCodeChatMessage(role: .user, text: "hello")
        let liveAgent = VitruvianCodeChatMessage(role: .agent, text: "world", durationMs: 1200,
                                              inputTokens: 100, outputTokens: 50, totalCostUSD: 0.02,
                                              thinkingDurationMs: 400)
        let reloadedSameTurn = [
            VitruvianCodeChatMessage(role: .user, text: "hello"),
            VitruvianCodeChatMessage(role: .agent, text: "world"),
        ]
        let kept = VitruvianCodeQuickPromptSession.mergingTranscriptReload(existing: [liveUser, liveAgent],
                                                                        reloaded: reloadedSameTurn)
        XCTAssertEqual(kept, [liveUser, liveAgent], "reloading the same turn does not wipe live metrics")

        let externalTurn = reloadedSameTurn + [
            VitruvianCodeChatMessage(role: .user, text: "external follow-up"),
            VitruvianCodeChatMessage(role: .agent, text: "external answer"),
        ]
        let appended = VitruvianCodeQuickPromptSession.mergingTranscriptReload(existing: [liveUser, liveAgent],
                                                                            reloaded: externalTurn)
        XCTAssertEqual(appended.count, 4)
        XCTAssertEqual(appended[1].totalCostUSD, 0.02, "earlier live turn keeps its cost and metrics")
        XCTAssertEqual(appended[3].text, "external answer")
    }

    func testClaudeErrorResultPopulatesErrorWithoutDuplicatingResponse() {
        let errLine = #"{"type":"result","is_error":true,"stop_reason":"error","session_id":"s1","result":"API Error: Overloaded"}"#
        let events = AgentEvent.parseAll(errLine)
        guard case .finished(_, let response, let error, _, _)? = events.first else {
            return XCTFail("expected finished event: \(events)")
        }
        XCTAssertNil(response, "error result text must not also populate response")
        XCTAssertEqual(error, "API Error: Overloaded")
    }

    @MainActor
    func testThinkingDurationIsStampedWhenThinkingEndsNotDuringDeltas() {
        let rig = ComposerRig()
        let session = rig.session()
        session.send("think first", configuration: VitruvianCodeConfiguration(activeProvider: .claude), agentPath: "/fake/claude")
        let thinkDelta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" analyzing..."}}}"# + "\n"
        rig.agentOutput?(Data(thinkDelta.utf8))
        XCTAssertEqual(session.messages.last?.thinkingText, " analyzing...")
        XCTAssertNil(session.messages.last?.thinkingDurationMs,
                     "nil while thinking deltas are still streaming so the active spinner is shown")

        let textDelta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Answer"}}}"# + "\n"
        rig.agentOutput?(Data(textDelta.utf8))
        XCTAssertNotNil(session.messages.last?.thinkingDurationMs,
                        "stamped as soon as thinking ends and reply text begins")
        rig.finishCleanly()
        session.stopTranscriptFollower()
    }

    // MARK: - Arguments

    private func configuration(_ provider: VitruvianCodeCLIProvider, effort: VitruvianCodeEffort = .automatic)
        -> VitruvianCodeConfiguration {
        var configuration = VitruvianCodeConfiguration(approvalMode: .standard, effort: effort)
        configuration.activeProvider = provider
        return configuration
    }

    func testEffortFlagsPerProvider() {
        for effort in VitruvianCodeEffort.allCases {
            let expected = effort == .automatic ? [] : ["--effort", effort.rawValue]
            let claude = VitruvianCodeSupport.agentArguments(prompt: "hi", configuration: configuration(.claude, effort: effort),
                                                          conversationID: nil)
            XCTAssertEqual(claude.contains("--effort"), effort != .automatic, "claude \(effort)")
            if let at = claude.firstIndex(of: "--effort") { XCTAssertEqual(Array(claude[at...at + 1]), expected) }
            let ollama = VitruvianCodeSupport.agentArguments(prompt: "hi", configuration: configuration(.ollama, effort: effort),
                                                          conversationID: nil)
            XCTAssertEqual(ollama.contains("--effort"), effort != .automatic, "ollama runs claude \(effort)")
            let agy = VitruvianCodeSupport.agentArguments(prompt: "hi", configuration: configuration(.antigravity, effort: effort),
                                                       conversationID: nil)
            XCTAssertEqual(agy.contains("--effort"), effort != .automatic, "agy \(effort)")
            let opencode = VitruvianCodeSupport.agentArguments(prompt: "hi",
                                                            configuration: configuration(.opencode, effort: effort),
                                                            conversationID: nil)
            XCTAssertFalse(opencode.contains("--effort"), "opencode run has no effort flag")
        }
        // A hand-written word Claude does not take is sent as a level it does.
        let written = VitruvianCodeEnvFile.parse("AGY_EFFORT=ultra\n")
        var claude = written
        claude.activeProvider = .claude
        let args = VitruvianCodeSupport.agentArguments(prompt: "hi", configuration: claude, conversationID: nil)
        XCTAssertEqual(args.firstIndex(of: "--effort").map { args[$0 + 1] }, "max")
    }

    func testAttachmentsPerProvider() {
        let files = [VitruvianCodeAttachment(url: URL(fileURLWithPath: "/r/a.swift")),
                     VitruvianCodeAttachment(url: URL(fileURLWithPath: "/r/shot.png"))]
        let opencode = VitruvianCodeSupport.agentArguments(prompt: "look", configuration: configuration(.opencode),
                                                        conversationID: nil, attachments: files)
        XCTAssertEqual(opencode.suffix(5), ["--file", "/r/a.swift", "--file", "/r/shot.png", "look"])
        for provider in [VitruvianCodeCLIProvider.claude, .antigravity] {
            var asYolo = configuration(provider)
            asYolo.approvalMode = .yolo
            let args = VitruvianCodeSupport.agentArguments(prompt: "look", configuration: asYolo,
                                                        conversationID: nil, attachments: files)
            XCTAssertEqual(args[1], "@/r/a.swift\n@/r/shot.png\n\nlook", provider.name)
        }
        let ollama = VitruvianCodeSupport.agentArguments(prompt: "look", configuration: configuration(.ollama),
                                                      conversationID: nil, attachments: files)
        XCTAssertTrue(ollama.contains("@/r/a.swift\n@/r/shot.png\n\nlook"))
        var claude = configuration(.claude)
        claude.approvalMode = .yolo
        XCTAssertEqual(VitruvianCodeSupport.agentArguments(prompt: "look", configuration: claude,
                                                        conversationID: nil)[1], "look", "no attachments, no prefix")
    }

    func testForkArguments() {
        let claude = VitruvianCodeSupport.agentArguments(prompt: "hi", configuration: configuration(.claude),
                                                      conversationID: "s1", forkSession: true)
        XCTAssertEqual(claude.suffix(3), ["--resume", "s1", "--fork-session"])
        let fresh = VitruvianCodeSupport.agentArguments(prompt: "hi", configuration: configuration(.claude),
                                                     conversationID: nil, forkSession: true)
        XCTAssertFalse(fresh.contains("--fork-session"), "only valid with --resume")
        let opencode = VitruvianCodeSupport.agentArguments(prompt: "hi", configuration: configuration(.opencode),
                                                        conversationID: "ses", forkSession: true)
        XCTAssertTrue(opencode.contains("--fork") && opencode.contains("ses"))
        let agy = VitruvianCodeSupport.agentArguments(prompt: "hi", configuration: configuration(.antigravity),
                                                   conversationID: "c", forkSession: true)
        XCTAssertEqual(agy, VitruvianCodeSupport.agentArguments(prompt: "hi", configuration: configuration(.antigravity),
                                                             conversationID: "c"), "agy has no fork")
    }

    // MARK: - Sessions

    func testFilterMatchesTitlePreviewAndWorkspace() {
        let sessions = [
            VitruvianCodeSessionSummary(id: "1", title: "Fix login", preview: "the flaky test", steps: 1, modified: nil,
                                     workspace: "/Users/j/vitruvian-core"),
            VitruvianCodeSessionSummary(id: "2", title: "Notes", steps: 1, modified: nil, workspace: "/Users/j/other"),
        ]
        XCTAssertEqual(VitruvianCodeSessionSummary.filter(sessions, by: "VITRUVIAN").map(\.id), ["1"])
        XCTAssertEqual(VitruvianCodeSessionSummary.filter(sessions, by: "flaky login").map(\.id), ["1"])
        XCTAssertEqual(VitruvianCodeSessionSummary.filter(sessions, by: "other notes").map(\.id), ["2"])
        XCTAssertEqual(VitruvianCodeSessionSummary.filter(sessions, by: "nowhere"), [])
    }

    func testListersFillWorkspaceAndLive() {
        let now = Date()
        let rows: [[String: Any]] = [
            ["id": "live", "title": "a", "directory": "/r", "time_updated": NSNumber(value: now.timeIntervalSince1970 * 1000)],
            ["id": "old", "title": "b", "directory": "/r", "time_updated": NSNumber(value: (now.timeIntervalSince1970 - 60) * 1000)],
        ]
        let summaries = VitruvianCodeSessionSummary.parseOpenCodeSessions(rows, directory: "", now: now)
        XCTAssertEqual(summaries.map(\.isLive), [true, false])
        XCTAssertEqual(summaries.first?.workspace, "/r")
        let agy = #"[{"conversation_id":"c1","title":"t","step_count":1,"last_modified_time":"2020-01-01T00:00:00Z","workspace_uris":"[\"file:///Users/j/repo\"]"}]"#
        let parsed = VitruvianCodeSessionSummary.parse(Data(agy.utf8), directory: "")
        XCTAssertEqual(parsed.first?.workspace, "/Users/j/repo")
        XCTAssertEqual(parsed.first?.isLive, false)
        XCTAssertEqual(VitruvianCodeSessionSummary.liveThreshold, 15)
    }

    func testPreferencesPinRenameAndSort() throws {
        var preferences = VitruvianCodeSessionPreferences(stored: [:])
        XCTAssertEqual(preferences, VitruvianCodeSessionPreferences())
        preferences.togglePin("c")
        preferences.togglePin("a")
        preferences.togglePin("a")
        preferences.rename(id: "b", to: "  Better name ")
        // The property-list form a host saves, under the agreed keys.
        let stored = preferences.stored
        XCTAssertEqual(stored["vitruvianCode.pinnedSessionIDs"] as? [String], ["c"])
        XCTAssertEqual(stored["vitruvianCode.renamedSessionTitles"] as? [String: String], ["b": "Better name"])
        let loaded = VitruvianCodeSessionPreferences(stored: stored)
        XCTAssertEqual(loaded, preferences)
        let coded = try JSONDecoder().decode(VitruvianCodeSessionPreferences.self,
                                             from: JSONEncoder().encode(preferences))
        XCTAssertEqual(coded, preferences, "the Codable form round-trips too")
        // A host that keeps nothing (the protocol's default) gives empty preferences.
        XCTAssertEqual(VitruvianCodeSessionPreferences(stored: ["other": 1]), VitruvianCodeSessionPreferences())
        XCTAssertEqual(loaded.pinnedSessionIDs, ["c"])
        XCTAssertEqual(loaded.renamedSessionTitles, ["b": "Better name"])
        let sessions = ["a", "b", "c", "d"].map { VitruvianCodeSessionSummary(id: $0, title: $0.uppercased(), steps: 1, modified: nil) }
        let applied = loaded.apply(to: sessions)
        XCTAssertEqual(applied.map(\.id), ["c", "a", "b", "d"])
        XCTAssertEqual(applied.map(\.isPinned), [true, false, false, false])
        XCTAssertEqual(applied[2].title, "Better name")
        var cleared = loaded
        cleared.rename(id: "b", to: "")
        XCTAssertEqual(cleared.apply(to: sessions).first { $0.id == "b" }?.title, "B", "an empty name restores the CLI's")
    }

    // MARK: - Workspace files

    func testFilterWorkspaceFilesRanksNamesFirst() {
        let files = ["docs/session-notes.md", "Sources/Session.swift", "Sources/Layout.swift", "Tests/MySessionTests.swift"]
        XCTAssertEqual(VitruvianCodeSupport.filterWorkspaceFiles(files, query: "session", limit: 10),
                       ["docs/session-notes.md", "Sources/Session.swift", "Tests/MySessionTests.swift"])
        XCTAssertEqual(VitruvianCodeSupport.filterWorkspaceFiles(files, query: "SOURCES", limit: 1), ["Sources/Session.swift"])
        XCTAssertEqual(VitruvianCodeSupport.filterWorkspaceFiles(files, query: "", limit: 2), Array(files.prefix(2)))
    }

    // MARK: - Git checkpoints

    private func git(_ arguments: [String], in directory: String) throws {
        let git = try XCTUnwrap(VitruvianCodeSupport.gitPath())
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments)")
    }

    func testCheckpointAndRestoreInATempRepository() throws {
        guard VitruvianCodeSupport.gitPath() != nil else { throw XCTSkip("git is not installed") }
        let fm = FileManager.default
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("track1-git-\(UUID().uuidString)")
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: root) }
        func write(_ name: String, _ text: String) throws {
            let path = (root as NSString).appendingPathComponent(name)
            try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        func read(_ name: String) -> String? {
            try? String(contentsOfFile: (root as NSString).appendingPathComponent(name), encoding: .utf8)
        }

        XCTAssertNil(VitruvianCodeSupport.gitCheckpoint(in: root), "not a repository yet")
        XCTAssertTrue(VitruvianCodeSupport.listWorkspaceFiles(in: root).isEmpty)
        try git(["init", "-q"], in: root)
        try write(".gitignore", "ignored.log\n")
        try write("tracked.txt", "one\n")
        try write("deleted.txt", "keep me\n")
        try git(["add", "-A"], in: root)
        try git(["commit", "-q", "-m", "base"], in: root)
        try write("tracked.txt", "one, edited by me\n")    // uncommitted change before the turn
        try write("mine-untracked.txt", "draft\n")          // untracked before the turn
        try write("ignored.log", "before\n")

        let files = VitruvianCodeSupport.listWorkspaceFiles(in: root)
        XCTAssertEqual(Set(files), [".gitignore", "tracked.txt", "deleted.txt", "mine-untracked.txt"])

        let sha = try XCTUnwrap(VitruvianCodeSupport.gitCheckpoint(in: root))
        XCTAssertEqual(sha.count, 40)

        // The turn: edits, deletes, creates (and stages one), touches an ignored file.
        try write("tracked.txt", "agent rewrote\n")
        try fm.removeItem(atPath: (root as NSString).appendingPathComponent("deleted.txt"))
        try write("dir/new.txt", "agent made\n")
        try write("staged-new.txt", "agent staged\n")
        try git(["add", "staged-new.txt"], in: root)
        try write("ignored.log", "after\n")

        XCTAssertTrue(VitruvianCodeSupport.restoreGitCheckpoint(sha, in: root))
        XCTAssertEqual(read("tracked.txt"), "one, edited by me\n", "back to the user's uncommitted edit")
        XCTAssertEqual(read("deleted.txt"), "keep me\n")
        XCTAssertEqual(read("mine-untracked.txt"), "draft\n", "the user's own untracked file stays")
        XCTAssertNil(read("dir/new.txt"), "a file the turn made is gone")
        XCTAssertNil(read("staged-new.txt"), "even one it staged")
        XCTAssertEqual(read("ignored.log"), "after\n", "ignored files are not touched")

        XCTAssertFalse(VitruvianCodeSupport.restoreGitCheckpoint("0000000000000000000000000000000000000000", in: root))
        XCTAssertFalse(VitruvianCodeSupport.restoreGitCheckpoint("--help", in: root))
    }
}
