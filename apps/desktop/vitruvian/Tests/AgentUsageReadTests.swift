// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the service's production read method, parser, cursor and store. The
/// reader passed in only observes when a complete line is handed over.
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
            ])
        ]
        for (provider, lines) in cases {
            // A canonical filename, not a Codex side-thread filename.
            let file = folder.appending(path: "\(provider.rawValue).jsonl")
            do { try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file) }
            catch { suite.expect(false, "the streaming fixture writes its log: \(error)"); continue }

            let cursor = AgentLogCursor(path: file.path, provider: provider)
            var entries: [AgentLogEntry] = []
            AgentLogReader.readAppended(cursor) { line in
                switch provider {
                case .claude: entries += AgentLogParser.parseClaude(line, state: &cursor.state, now: now)
                case .codex: entries += AgentLogParser.parseCodex(line, state: &cursor.state, now: now)
                case .opencode: entries += AgentLogParser.parseOpenCode(line, state: &cursor.state, now: now)
                }
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
                                       isCancelled: { cancelled }, report: { events.append($0) }) {
                    logCursor, horizon, shouldContinue, line in
                    AgentLogReader.readAppended(logCursor, since: horizon, shouldContinue: shouldContinue) {
                        counts.append(store.records.count)
                        line($0)
                    }
                }
            }
            suite.expect(read(), "a \(provider.rawValue) log reports parsed entries")
            suite.expect(counts.contains(where: { $0 > 0 }),
                         "\(provider.rawValue) records are applied before the rest of the log is read")
            suite.expect(store.records == reference.records && store.turns == reference.turns
                            && store.waiting == reference.waiting && store.limits == reference.limits
                            && store.codexPlan == reference.codexPlan && events == expectedEvents,
                         "streaming \(provider.rawValue) preserves duplicate merging, usage, turns, limits, plans and event order")
            suite.expect(!expectedEvents.isEmpty && cursors[file.path]?.state == cursor.state,
                         "\(provider.rawValue) finishes the same turn and retains the same parser context")
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
    }
}
