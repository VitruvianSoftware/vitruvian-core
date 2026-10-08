// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the service's production read method, parser, cursor and store. The
/// readers passed in only observe when a complete line is handed over.
enum AgentUsageReadTests {
    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vitru-streaming-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { suite.expect(false, "the streaming fixture creates its folder: \(error)"); return }
        let now = Date()
        let timestamp = now.timeIntervalSince1970
        let cases: [(AgentProvider, [String])] = [
            (.claude, [
                #"{"type":"user","timestamp":\#(timestamp),"sessionId":"s","message":{"content":"work"}}"#,
                #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":2}}}"#,
                #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-opus-5-5","stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5}}}"#,
                #"{"type":"assistant","timestamp":\#(timestamp),"sessionId":"s","requestId":"r2","message":{"id":"m2","model":"claude-opus-5-5","stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":7}}}"#
            ]),
            (.codex, [
                #"{"type":"session_meta","timestamp":\#(timestamp),"payload":{"id":"s","cwd":"/tmp/example"}}"#,
                #"{"type":"turn_context","timestamp":\#(timestamp),"payload":{"model":"gpt-5.2-codex"}}"#,
                #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"task_started"}}"#,
                #"{"type":"token_usage_record","timestamp":\#(timestamp),"payload":{"response_id":"r","usage":{"input_tokens":10,"output_tokens":2}}}"#,
                #"{"type":"token_usage_record","timestamp":\#(timestamp),"payload":{"response_id":"r","usage":{"input_tokens":10,"output_tokens":5}}}"#,
                #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"token_count","rate_limits":{"plan_type":"pro","primary":{"used_percent":42,"window_minutes":300}}}}"#,
                #"{"type":"event_msg","timestamp":\#(timestamp),"payload":{"type":"task_complete","duration_ms":20000}}"#
            ]),
            (.copilot, [
                #"{"id":"start","timestamp":\#(timestamp),"type":"session.start","data":{"sessionId":"s","selectedModel":"gpt-6-sol","context":{"cwd":"/tmp/example"}}}"#,
                #"{"id":"turn","timestamp":\#(timestamp),"type":"user.message","data":{"turnId":"0","content":"private"}}"#,
                #"{"id":"message","timestamp":\#(timestamp),"type":"assistant.message","data":{"model":"gpt-6-sol","content":"private"}}"#,
                #"{"id":"checkpoint","timestamp":\#(timestamp),"type":"session.usage_checkpoint","data":{"totalPremiumRequests":1}}"#,
                #"{"id":"end","timestamp":\#(timestamp),"type":"assistant.turn_end","data":{"turnId":"0"}}"#,
                #"{"id":"usage","timestamp":\#(timestamp),"type":"session.shutdown","data":{"modelMetrics":{"gpt-6-sol":{"requests":{"count":1},"tokenDetails":{"input":{"tokenCount":10},"cache_read":{"tokenCount":20},"cache_write":{"tokenCount":0},"output":{"tokenCount":5}},"usage":{"reasoningTokens":2}}}}}"#,
                #"{"id":"final-checkpoint","timestamp":\#(timestamp),"type":"session.usage_checkpoint","data":{}}"#
            ])
        ]
        for (provider, lines) in cases {
            // A canonical filename, not a Codex side-thread filename.
            let file = folder.appending(path: "\(provider.rawValue).jsonl")
            do { try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file) }
            catch { suite.expect(false, "the streaming fixture writes its log: \(error)"); continue }

            let cursor = AgentLogCursor(path: file.path, provider: provider)
            var entries: [AgentLogEntry] = []
            let consume: (Data) -> Void = { line in
                switch provider {
                case .claude: entries += AgentLogParser.parseClaude(line, state: &cursor.state, now: now)
                case .codex: entries += AgentLogParser.parseCodex(line, state: &cursor.state, now: now)
                case .opencode: entries += AgentLogParser.parseOpenCode(line, state: &cursor.state, now: now)
                case .copilot: entries += AgentLogParser.parseCopilot(line, state: &cursor.state, now: now)
                case .antigravity: break
                }
            }
            if provider == .copilot {
                AgentLogReader.readCopilotHistory(cursor, line: consume)
            } else {
                AgentLogReader.readAppended(cursor, line: consume)
            }
            let reference = AgentUsageStore()
            reference.reportsTransitions = true
            let expectedEvents = reference.apply(entries, file: file.path, provider: provider,
                                                 tracksTurns: cursor.tracksTurns, parent: cursor.parent,
                                                 modified: cursor.modified, now: now)
            let store = AgentUsageStore()
            store.reportsTransitions = true
            var cursors: [String: AgentLogCursor] = [:]
            var events: [AgentUsageEvent] = []
            var cancelled = false
            var counts: [Int] = []
            func read() -> Bool {
                AgentUsageService.read(file.path, provider: provider, cursors: &cursors, store: store,
                                       isCancelled: { cancelled }, report: { events.append($0) },
                                       lines: { logCursor, horizon, shouldContinue, line in
                    AgentLogReader.readAppended(logCursor, since: horizon, shouldContinue: shouldContinue) {
                        counts.append(store.records.count)
                        line($0)
                    }
                }, history: { logCursor, shouldContinue, line in
                    AgentLogReader.readCopilotHistory(logCursor, shouldContinue: shouldContinue) {
                        counts.append(store.records.count)
                        line($0)
                    }
                })
            }
            suite.expect(read(), "a \(provider.rawValue) log reports parsed entries")
            suite.expect(counts.contains(where: { $0 > 0 }),
                         "\(provider.rawValue) records are applied before the rest of the log is read")
            suite.expect(store.records == reference.records && store.turns == reference.turns
                            && store.waiting == reference.waiting && store.limits == reference.limits
                            && store.codexPlan == reference.codexPlan && events == expectedEvents,
                         "streaming \(provider.rawValue) preserves duplicate merging, usage, turns, limits, plans and event order")
            suite.expect((provider == .copilot || !expectedEvents.isEmpty)
                            && cursors[file.path]?.state == cursor.state,
                         "\(provider.rawValue) retains the same parser context without replaying historical finishes")
            suite.expect(!read() && events == expectedEvents,
                         "an unchanged \(provider.rawValue) file neither changes the store nor replays events")
            // Something to read, so only the cancellation stops it.
            if let handle = try? FileHandle(forWritingTo: file) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data((lines[0] + "\n").utf8))
                try? handle.close()
            }
            cancelled = true
            let delivered = counts.count
            suite.expect(!read() && counts.count == delivered, "a cancelled reading consumes no more entries")
        }

        let openFile = folder.appending(path: "copilot-open.jsonl")
        let openLines = [
            #"{"id":"start","timestamp":"2026-09-27T15:00:00.000Z","type":"session.start","data":{"sessionId":"open","selectedModel":"gpt-6-sol","context":{"cwd":"/tmp/open-project"}}}"#,
            #"{"id":"turn","timestamp":"2026-09-27T15:01:00.000Z","type":"user.message","data":{"content":"still working"}}"#,
            #"{"id":"iteration","timestamp":"2026-09-27T15:01:01.000Z","type":"assistant.turn_start","data":{"turnId":"0"}}"#,
            #"{"id":"reply","timestamp":"2026-09-27T15:01:30.000Z","type":"assistant.message","data":{"model":"gpt-6-sol","content":"in progress","toolRequests":[{"name":"read_file","toolCallId":"tool"}]}}"#,
            #"{"id":"checkpoint","timestamp":"2026-09-27T15:01:45.000Z","type":"session.usage_checkpoint","data":{"totalPremiumRequests":0}}"#,
            #"{"id":"intermediate-end","timestamp":"2026-09-27T15:01:46.000Z","type":"assistant.turn_end","data":{"turnId":"0"}}"#,
            #"{"id":"next-iteration","timestamp":"2026-09-27T15:01:47.000Z","type":"assistant.turn_start","data":{"turnId":"1"}}"#
        ]
        try? Data((openLines.joined(separator: "\n") + "\n").utf8).write(to: openFile)
        let openStore = AgentUsageStore()
        var openCursors: [String: AgentLogCursor] = [:]
        func readOpen() -> Bool {
            AgentUsageService.read(openFile.path, provider: .copilot, cursors: &openCursors, store: openStore,
                                   isCancelled: { false }, report: { _ in })
        }
        suite.expect(readOpen()
                        && openStore.turns[openFile.path]?.project == "open-project"
                        && openStore.turns[openFile.path]?.model == "gpt-6-sol"
                        && openCursors[openFile.path]?.state.turnOpen == true
                        && openStore.records.count == 1,
                     "startup restores ongoing Copilot work after a checkpoint and an intermediate tool turn-end")
        if let handle = try? FileHandle(forWritingTo: openFile) {
            _ = try? handle.seekToEnd()
            let end = [
                #"{"id":"final","timestamp":"2026-09-27T15:01:59.000Z","type":"assistant.message","data":{"content":"done"}}"#,
                #"{"id":"end","timestamp":"2026-09-27T15:02:00.000Z","type":"assistant.turn_end","data":{"turnId":"1"}}"#
            ]
            try? handle.write(contentsOf: Data((end.joined(separator: "\n") + "\n").utf8))
            try? handle.close()
        }
        openStore.reportsTransitions = true
        suite.expect(readOpen()
                        && openCursors[openFile.path]?.state.turnOpen == false
                        && openStore.turns[openFile.path] == nil,
                     "the restored Copilot turn finishes when its root assistant turn-end arrives")

        // The watcher callback and rescans both admit a path through
        // AgentLogRoot.accepts, and rescans find logs through discover.
        let state = folder.appending(path: "session-state")
        try? FileManager.default.createDirectory(at: state.appending(path: "demo/workspace/nested"),
                                                 withIntermediateDirectories: true)
        // Listings report the real path, /private included, as file events do.
        let root = AgentLogRoot.canonical(state)
        let session = root.appending(path: "demo")
        let workspace = session.appending(path: "workspace/nested")
        let real = session.appending(path: "events.jsonl")
        let nested = workspace.appending(path: "events.jsonl")
        let arbitrary = session.appending(path: "data.jsonl")
        let bytes = Data((openLines.joined(separator: "\n") + "\n").utf8)
        for file in [real, nested, arbitrary] { try? bytes.write(to: file) }
        let copilotRoot = AgentLogRoot(provider: .copilot, url: root)
        suite.expect(copilotRoot.accepts(real.path) && !copilotRoot.accepts(nested.path)
                        && !copilotRoot.accepts(arbitrary.path),
                     "Copilot file watching admits only each session's event log and never its workspace JSONL")
        suite.expect(AgentLogReader.discover([copilotRoot], since: .distantPast).map(\.path) == [real.path],
                     "Copilot rescans use the same path boundary")
    }
}
