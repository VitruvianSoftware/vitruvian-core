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


import XCTest

import NexusAgentCore

/// How full the context window is, as the chat's header shows it: the
/// latest step's tokens (never a sum over steps) against the model's window.
final class ContextUsageTests: XCTestCase {
    private func usage(_ input: Int, _ cached: Int, _ output: Int, window: Int = 200_000) -> NexusAgentContextUsage {
        NexusAgentContextUsage(inputTokens: input, cachedTokens: cached, outputTokens: output, contextWindow: window)
    }

    func testFormatting() {
        // The resumed OpenCode chat in the screenshot: 679 + 32,640 + 124.
        let shown = usage(679, 32_640, 124)
        XCTAssertEqual(shown.totalTokens, 33_443)
        XCTAssertEqual(shown.compactTokens, "33.4k")
        XCTAssertEqual(shown.usedPercent, 17)
        XCTAssertEqual(shown.badgeLabel, "33.4k · 17%")
        XCTAssertEqual(shown.tooltipText,
                       "Context: 33,443 / 200,000 tokens (17%)\nInput: 679 · Cached: 32,640 · Output: 124")

        XCTAssertEqual(usage(850, 0, 0).compactTokens, "850")
        XCTAssertEqual(usage(2_000, 0, 0).compactTokens, "2k")
        XCTAssertEqual(usage(142_000, 0, 0).badgeLabel, "142k · 71%")
        XCTAssertEqual(usage(1_200_000, 0, 0, window: 1_000_000).compactTokens, "1.2M")
        XCTAssertEqual(usage(999_700, 0, 0, window: 1_000_000).compactTokens, "1M")
    }

    func testPercentIsClampedAndNeverZeroOnceUsed() {
        XCTAssertEqual(usage(0, 0, 0).usedPercent, 0)
        XCTAssertEqual(usage(10, 0, 0, window: 1_000_000).usedPercent, 1, "any use shows as at least 1%")
        XCTAssertEqual(usage(300_000, 0, 0).usedPercent, 100)
        XCTAssertEqual(usage(300_000, 0, 0).usedFraction, 1.0)
        XCTAssertEqual(usage(50_000, 0, 0).usedFraction, 0.25)
        XCTAssertEqual(usage(5, 0, 0, window: 0).usedPercent, 100, "an unknown window never divides by zero")
    }

    func testAnEstimateSaysSo() {
        let estimate = NexusAgentContextUsage.estimate(characters: 4_000, contextWindow: 200_000)
        XCTAssertTrue(estimate.isEstimate)
        XCTAssertEqual(estimate.totalTokens, 1_000)
        XCTAssertEqual(estimate.badgeLabel, "~1k · 1%")
        XCTAssertTrue(estimate.tooltipText.contains("Estimated"))
        XCTAssertEqual(NexusAgentContextUsage.estimate(characters: 2, contextWindow: 1).totalTokens, 1)
    }

    func testDefaultContextWindow() {
        func window(_ model: String?, _ provider: NexusAgentCLIProvider) -> Int {
            NexusAgentContextUsage.defaultContextWindow(for: model, provider: provider)
        }
        XCTAssertEqual(window(nil, .claude), 200_000)
        XCTAssertEqual(window("claude-opus-5-5", .claude), 200_000)
        XCTAssertEqual(window("opus[1m]", .claude), 1_000_000)
        XCTAssertEqual(window("gemini-3.7-flash", .antigravity), 1_000_000)
        XCTAssertEqual(window(nil, .antigravity), 1_000_000, "Antigravity runs Gemini unless told otherwise")
        XCTAssertEqual(window("claude-sonnet-5-5", .antigravity), 200_000)
        XCTAssertEqual(window("qwen3", .ollama), 128_000)
        XCTAssertEqual(window("deepseek/deepseek-v4", .opencode), 128_000)
        XCTAssertEqual(window("glm-5.3-flash-free", .opencode), 200_000)
        XCTAssertEqual(window(nil, .opencode), 200_000)
    }

    func testAWindowIsFilledInOnlyWhenUnknown() {
        XCTAssertEqual(usage(1, 0, 0, window: 0).resolved(model: nil, provider: .ollama).contextWindow, 128_000)
        XCTAssertEqual(usage(1, 0, 0, window: 500).resolved(model: nil, provider: .ollama).contextWindow, 500)
    }

    // MARK: - Claude

    func testClaudeUsageCountsBothCacheKinds() {
        let context = NexusAgentContextUsage.claude(usage: [
            "input_tokens": 2, "cache_creation_input_tokens": 68_627, "cache_read_input_tokens": 10_718,
            "output_tokens": 422,
        ])
        XCTAssertEqual(context, usage(2, 79_345, 422, window: 0))
        XCTAssertNil(NexusAgentContextUsage.claude(usage: ["input_tokens": 0]))
    }

    func testClaudeUsageFallsBackToTheLastIteration() {
        let context = NexusAgentContextUsage.claude(usage: [
            "input_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0, "output_tokens": 9,
            "iterations": [
                ["input_tokens": 1, "cache_read_input_tokens": 100, "output_tokens": 1],
                ["input_tokens": 4, "cache_read_input_tokens": 900, "cache_creation_input_tokens": 50, "output_tokens": 30],
            ],
        ])
        XCTAssertEqual(context, usage(4, 950, 30, window: 0))
    }

    func testAClaudeTranscriptPutsEachStepsUsageOnItsReply() throws {
        let transcript = [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"Hello"}],"usage":{"input_tokens":3,"cache_read_input_tokens":10000,"cache_creation_input_tokens":2000,"output_tokens":40}}}"#,
            #"{"type":"user","message":{"role":"user","content":"more"}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"Sure"}],"usage":{"input_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":5,"iterations":[{"input_tokens":5,"cache_read_input_tokens":12100,"cache_creation_input_tokens":300,"output_tokens":60}]}}}"#,
        ].joined(separator: "\n")
        let messages = try XCTUnwrap(NexusAgentEngine.parseClaudeTranscript(transcript))
        XCTAssertEqual(messages.map(\.text), ["hi", "Hello", "more", "Sure"])
        XCTAssertEqual(messages[1].contextUsage, usage(3, 12_000, 40, window: 0))
        XCTAssertEqual(messages[3].contextUsage, usage(5, 12_400, 60, window: 0))
        XCTAssertEqual(messages[3].modelName, "claude-opus-5-5")
        XCTAssertNil(messages[0].contextUsage)

        let current = try XCTUnwrap(NexusAgentQuickPromptSession.contextUsage(of: messages, provider: .claude, model: nil))
        XCTAssertEqual(current, usage(5, 12_400, 60), "the latest step, not a sum, with Claude's window")
        XCTAssertEqual(NexusAgentQuickPromptSession.contextUsage(of: messages, provider: .claude, model: "opus[1m]")?
                        .contextWindow, 1_000_000, "the model the settings name says more than the transcript's")
    }

    // MARK: - OpenCode

    func testAnOpenCode2TranscriptCarriesTheLastStepsTokens() throws {
        let rows: [[String: Any]] = [
            ["type": "user", "data": #"{"text":"hi"}"#],
            ["type": "assistant", "data": #"{"model":{"id":"glm-5.3-flash-free","providerID":"opencode"},"content":[{"type":"text","text":"Hi there! I am ready to help."}],"tokens":{"input":679,"output":124,"reasoning":0,"cache":{"read":32640,"write":0}}}"#],
        ]
        let messages = try XCTUnwrap(NexusAgentEngine.parseOpenCodeMessages(rows))
        XCTAssertEqual(messages[1].contextUsage, usage(679, 32_640, 124, window: 0))
        XCTAssertEqual(messages[1].modelName, "glm-5.3-flash-free")
        XCTAssertEqual(NexusAgentQuickPromptSession.contextUsage(of: messages, provider: .opencode, model: "")?.badgeLabel,
                       "33.4k · 17%")
    }

    func testTheStepsOfAnOpenCodeTurnKeepTheLatestCount() throws {
        let rows: [[String: Any]] = [
            ["type": "user", "data": #"{"text":"fix it"}"#],
            ["type": "assistant", "data": #"{"content":[{"type":"tool","tool":"bash","state":{"input":{"command":"ls"}}}],"tokens":{"input":10,"output":5,"cache":{"read":1000,"write":0}}}"#],
            ["type": "assistant", "data": #"{"content":[],"tokens":{"input":20,"output":7,"cache":{"read":1500,"write":100}}}"#],
            ["type": "assistant", "data": #"{"content":[{"type":"text","text":"Done."}],"tokens":{"input":30,"output":9,"cache":{"read":2000,"write":0}}}"#],
        ]
        let messages = try XCTUnwrap(NexusAgentEngine.parseOpenCodeMessages(rows))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[1].contextUsage, usage(30, 2_000, 9, window: 0))
    }

    func testAnOpenCode1TranscriptReadsTheTokensColumn() throws {
        XCTAssertTrue(NexusAgentEngine.opencodeTranscriptQueries(conversationID: "s")[1]
                        .contains("json_extract(m.data, '$.tokens') AS tokens"))
        let rows: [[String: Any]] = [
            ["message_id": "m1", "role": "user", "data": #"{"type":"text","text":"hi"}"#],
            ["message_id": "m2", "role": "assistant", "data": #"{"type":"text","text":"Hello"}"#,
             "tokens": #"{"input":100,"output":20,"cache":{"read":5000,"write":0}}"#, "model_id": "gpt-5"],
        ]
        let messages = try XCTUnwrap(NexusAgentEngine.parseOpenCodeMessages(rows))
        XCTAssertEqual(messages[1].contextUsage, usage(100, 5_000, 20, window: 0))
        XCTAssertEqual(messages[1].modelName, "gpt-5")
    }

    // MARK: - Antigravity

    func testAntigravityReadsOneTurnsShareOfItsTelemetry() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: home) }
        let id = "9a8e2d2b"
        let logs = home + "/.gemini/antigravity/brain/\(id)/.system_generated/logs"
        try FileManager.default.createDirectory(atPath: logs, withIntermediateDirectories: true)
        try #"{"type":"USER_INPUT","content":"hi"}"#.appending("\n")
            .appending(#"{"type":"PLANNER_RESPONSE","content":"Hello"}"#)
            .write(toFile: logs + "/transcript.jsonl", atomically: true, encoding: .utf8)
        XCTAssertNil(NexusAgentEngine.readAntigravityContextUsage(conversationID: id, home: home), "no telemetry, no count")

        let state: [String: Any] = [logs + "/transcript.jsonl": [
            "turns": 5, "model": "gemini-3.7-flash",
            "tokens": ["input": 22_500, "output": 1_750, "cached": 160_000, "thinking": 13],
        ]]
        try JSONSerialization.data(withJSONObject: state)
            .write(to: URL(fileURLWithPath: home + "/.gemini/antigravity/.telemetry_state.json"))
        let read = try XCTUnwrap(NexusAgentEngine.readAntigravityContextUsage(conversationID: id, home: home))
        XCTAssertEqual(read.usage, usage(4_500, 32_000, 352, window: 1_000_000))
        XCTAssertEqual(read.model, "gemini-3.7-flash")

        let messages = try XCTUnwrap(NexusAgentEngine.readTranscript(home: home, conversationID: id))
        XCTAssertEqual(messages.last?.contextUsage, read.usage, "the transcript's last reply carries it")
    }

    // MARK: - Live

    func testAClaudeStepSaysItsContextAsItEnds() {
        let line = #"{"type":"assistant","message":{"model":"claude-opus-5-5","content":[],"usage":{"input_tokens":3,"cache_read_input_tokens":30000,"cache_creation_input_tokens":2000,"output_tokens":100}}}"#
        XCTAssertEqual(NexusAgentStreamEvent.parse(line), .contextUsage(usage(3, 32_000, 100, window: 0)))
        XCTAssertNil(NexusAgentStreamEvent.parse(#"{"type":"assistant","message":{"content":[]}}"#))
    }

    func testAClaudeResultGivesOneStepsShareAndTheExactWindow() throws {
        let line = #"{"type":"result","num_turns":2,"usage":{"input_tokens":10,"cache_read_input_tokens":60000,"cache_creation_input_tokens":4000,"output_tokens":200},"modelUsage":{"claude-haiku":{"inputTokens":50,"contextWindow":200000},"claude-opus-5-5":{"inputTokens":10,"cacheReadInputTokens":60000,"contextWindow":1000000}},"result":"ok"}"#
        guard case .finished(_, _, _, _, let metrics)? = NexusAgentStreamEvent.parse(line) else {
            return XCTFail("a result finishes the turn")
        }
        XCTAssertEqual(metrics?.contextUsage, usage(5, 32_000, 100, window: 1_000_000),
                       "the summed usage halved, with the main model's window")
    }

    func testAnOpenCodeToolStepSaysItsContext() {
        let line = #"{"type":"step_finish","sessionID":"ses_1","part":{"reason":"tool-calls","tokens":{"input":5,"output":2,"cache":{"read":100,"write":10}}}}"#
        XCTAssertEqual(NexusAgentStreamEvent.parse(line), .contextUsage(usage(5, 110, 2, window: 0)))
    }

    func testAnAntigravityResultGivesOneTurnsShare() {
        let line = #"{"event":"result","result":{"status":"ok","num_turns":2,"usage":{"input_tokens":400,"output_tokens":60,"cache_read_tokens":8000}}}"#
        guard case .finished(_, _, _, _, let metrics)? = NexusAgentStreamEvent.parse(line) else {
            return XCTFail("a result finishes the turn")
        }
        XCTAssertEqual(metrics?.contextUsage, usage(200, 4_000, 30, window: 0))
    }

    func testAConversationWithNoCountsIsEstimated() throws {
        let messages = [NexusAgentChatMessage(role: .user, text: String(repeating: "a", count: 400))]
        let estimate = try XCTUnwrap(NexusAgentQuickPromptSession.contextUsage(of: messages, provider: .opencode, model: nil))
        XCTAssertTrue(estimate.isEstimate)
        XCTAssertEqual(estimate.totalTokens, 100)
        XCTAssertEqual(estimate.contextWindow, 200_000)
        XCTAssertNil(NexusAgentQuickPromptSession.contextUsage(of: [], provider: .opencode, model: nil))
    }
}
