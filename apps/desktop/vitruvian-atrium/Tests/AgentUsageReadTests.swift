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
        codexThreads(suite, folder: folder)

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

    /// Reads Codex logs the way the service does, through its own `read`,
    /// into a store and cursors the test can look at.
    private final class ReadHost {
        var cursors: [String: AgentLogCursor] = [:]
        var store = AgentUsageStore()
        var events: [AgentUsageEvent] = []

        @discardableResult func read(_ path: String, provider: AgentProvider) -> Bool {
            AgentUsageService.read(path, provider: provider, cursors: &cursors, store: store,
                                   isCancelled: { false }, report: { [weak self] in self?.events.append($0) })
        }
    }

    private static func codexThreads(_ suite: TestSuite, folder: URL) {
        let now = Date().timeIntervalSince1970
        let host = ReadHost()
        host.store.reportsTransitions = true
        func write(_ name: String, _ lines: [String], append: Bool = false, into target: ReadHost? = nil) -> URL {
            let file = folder.appending(path: name)
            let data = Data((lines.joined(separator: "\n") + "\n").utf8)
            if append, let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else { try? data.write(to: file) }
            _ = (target ?? host).read(file.path, provider: .codex)
            return file
        }
        // Editing an earlier message reverts the thread: its turn stops, and
        // the thread goes on in a log named after it and a new rollout.
        let thread = "01a14017-9c92-7862-8f2a-2019293313fe"
        let original = write("rollout-2026-10-16T10-00-00-\(thread).jsonl", [
            #"{"type":"session_meta","timestamp":\#(now - 30),"payload":{"id":"\#(thread)","source":"vscode"}}"#,
            #"{"type":"event_msg","timestamp":\#(now - 29),"payload":{"type":"task_started"}}"#
        ])
        suite.expect(host.store.live.count == 1, "a new Codex main thread is live")
        _ = write(original.lastPathComponent, [
            #"{"type":"event_msg","timestamp":\#(now - 20),"payload":{"type":"turn_aborted"}}"#
        ], append: true)
        let reverted = write("rollout-2026-10-16T10-20-00-\(thread)_01a14099-0000-7000-8000-000000000001.jsonl", [
            #"{"type":"session_meta","timestamp":\#(now - 10),"payload":{"id":"\#(thread)","source":"vscode"}}"#,
            #"{"type":"event_msg","timestamp":\#(now - 9),"payload":{"type":"task_started"}}"#,
            #"{"type":"token_usage_record","timestamp":\#(now - 8),"payload":{"response_id":"revert-response","usage":{"input_tokens":10,"output_tokens":4}}}"#,
            #"{"type":"event_msg","timestamp":\#(now - 8),"payload":{"type":"token_count","rate_limits":{"plan_type":"plus","primary":{"used_percent":35,"window_minutes":300}}}}"#
        ])
        suite.expect(host.store.live.count == 1 && host.store.live.first?.id == reverted.path
                        && host.store.live.first?.tokens.total == 14 && host.store.records.count == 1
                        && host.store.limits[.codex] != nil && host.events.isEmpty,
                     "a reverted Codex thread goes on in its underscored log with its live turn, usage and limits")
        // Subagents, Guardian reviews and memory tasks have ordinary log
        // names, and a child can copy its parent's history, metadata included.
        let children = [("spawned", #"{"subagent":{"thread_spawn":{"parent_thread_id":"\#(thread)","depth":1}}}"#),
                        ("guardian", #"{"subagent":{"other":"guardian"}}"#),
                        ("compact", #"{"subagent":"compact"}"#),
                        ("memory", #"{"internal":"memory_consolidation"}"#)]
        for (index, (kind, source)) in children.enumerated() {
            let file = write("child\(index).jsonl", [
                #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"child-\#(index)","source":\#(source)}}"#,
                #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"\#(thread)","source":"vscode"}}"#,
                #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"task_started"}}"#
            ])
            suite.expect(host.cursors[file.path]?.tracksTurns == false
                            && host.cursors[file.path]?.state.session == "child-\(index)" && host.store.live.count == 1,
                         "a Codex \(kind) log keeps its own metadata and owns no turn when its parent's is copied after it")
        }
        // A subagent's responses count toward its thread's turn and keep it
        // working while the thread only waits on it.
        host.store.closeIdleTurns(now: Date(timeIntervalSince1970: now + 600), after: 120)
        suite.expect(host.store.live.isEmpty, "a quiet Codex thread stops showing as working")
        _ = write("worker.jsonl", [
            #"{"type":"session_meta","timestamp":\#(now + 580),"payload":{"id":"worker","session_id":"\#(thread)","parent_thread_id":"\#(thread)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\#(thread)","depth":1}}}}}"#,
            #"{"type":"event_msg","timestamp":\#(now + 580),"payload":{"type":"task_started"}}"#,
            #"{"type":"token_usage_record","timestamp":\#(now + 590),"payload":{"response_id":"worker-response","usage":{"input_tokens":6,"output_tokens":1}}}"#
        ])
        suite.expect(host.store.live.count == 1 && host.store.live.first?.id == reverted.path
                        && host.store.live.first?.tokens.total == 21,
                     "a Codex subagent's responses count toward its thread's turn and keep it working while the thread waits")
        let saved = AgentUsageArchive.Contents(providers: [.codex], store: host.store.saved,
                                                             cursors: host.cursors.values.map(\.saved))
        let encoded = AgentUsageArchive.encode(saved, build: "codex-thread-test")
        let decoded = AgentUsageArchive.decode(encoded, build: "codex-thread-test")
        suite.expect(decoded == saved, "Codex thread identity survives an archive round trip")
        if let decoded {
            let restored = AgentUsageArchive.resume(decoded, logs: Set(host.cursors.keys), since: .distantPast)
            suite.expect(restored.cursors[reverted.path]?.tracksTurns == true
                            && restored.cursors[folder.appending(path: "child0.jsonl").path]?.tracksTurns == false,
                         "restored Codex cursors preserve main and subagent identity without rereading metadata")
            let restoredHost = ReadHost()
            restoredHost.cursors = restored.cursors
            restoredHost.store = restored.store
            _ = write("worker.jsonl", [
                #"{"type":"token_usage_record","timestamp":\#(now + 595),"payload":{"response_id":"worker-response-2","usage":{"input_tokens":2,"output_tokens":1}}}"#
            ], append: true, into: restoredHost)
            suite.expect(restoredHost.store.live.first?.id == reverted.path && restoredHost.store.live.first?.tokens.total == 24,
                         "a restored Codex subagent finds its thread's log again")
            _ = write("child0.jsonl", [
                #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"\#(thread)","source":"vscode"}}"#,
                #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"task_started"}}"#,
                #"{"type":"token_usage_record","timestamp":\#(now),"payload":{"response_id":"child-response","usage":{"input_tokens":3,"output_tokens":2}}}"#
            ], append: true, into: restoredHost)
            _ = write(reverted.lastPathComponent, [
                #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"task_complete"}}"#
            ], append: true, into: restoredHost)
            suite.expect(restoredHost.store.live.isEmpty && restoredHost.store.records.count == 4,
                         "after cache restore a child adds usage without a turn and the reverted thread's task finishes")
        }
        _ = write(reverted.lastPathComponent, [
            #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"task_complete","duration_ms":9000}}"#
        ], append: true)
        suite.expect(host.store.live.isEmpty && host.events.count == 1,
                     "the reverted thread's task ends exactly once and clears the running indicator")
        // A subagent can be read before its thread's log, and that log can move.
        let early = ReadHost()
        let other = "01a14099-2222-7000-8000-000000000003"
        _ = write("early-child.jsonl", [
            #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"early-child","session_id":"\#(other)","source":{"subagent":{"other":"guardian"}}}}"#,
            #"{"type":"token_usage_record","timestamp":\#(now),"payload":{"response_id":"early-1","usage":{"input_tokens":1,"output_tokens":1}}}"#
        ], into: early)
        let otherLog = write("rollout-2026-10-16T11-00-00-\(other).jsonl", [
            #"{"type":"session_meta","timestamp":\#(now - 5),"payload":{"id":"\#(other)","source":"vscode"}}"#,
            #"{"type":"event_msg","timestamp":\#(now - 5),"payload":{"type":"task_started"}}"#
        ], into: early)
        _ = write("early-child.jsonl", [
            #"{"type":"token_usage_record","timestamp":\#(now + 1),"payload":{"response_id":"early-2","usage":{"input_tokens":2,"output_tokens":2}}}"#
        ], append: true, into: early)
        suite.expect(early.store.live.first?.id == otherLog.path && early.store.live.first?.tokens.total == 4,
                     "a Codex subagent read before its thread's log counts toward it once that log is read")
        let moved = folder.appending(path: "moved-\(otherLog.lastPathComponent)")
        try? FileManager.default.moveItem(at: otherLog, to: moved)
        _ = early.read(otherLog.path, provider: .codex)
        _ = early.read(moved.path, provider: .codex)
        _ = write("early-child.jsonl", [
            #"{"type":"token_usage_record","timestamp":\#(now + 2),"payload":{"response_id":"early-3","usage":{"input_tokens":3,"output_tokens":3}}}"#
        ], append: true, into: early)
        suite.expect(early.store.live.first?.id == moved.path && early.store.live.first?.tokens.total == 6,
                     "a Codex subagent follows its thread's log when the log moves")
        // Logs from before per-response records report running totals, which
        // a child's copy of its parent's history repeats.
        let totals = ReadHost()
        let parentTotals = #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#
        _ = write("totals-parent.jsonl", [
            #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"totals-parent","source":"cli"}}"#,
            parentTotals
        ], into: totals)
        _ = write("totals-child.jsonl", [
            #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"totals-child","source":{"subagent":"review"}}}"#,
            #"{"type":"session_meta","timestamp":\#(now),"payload":{"id":"totals-parent","source":"cli"}}"#,
            parentTotals,
            #"{"type":"event_msg","timestamp":\#(now),"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":130,"output_tokens":15},"last_token_usage":{"input_tokens":30,"output_tokens":5}}}}"#
        ], into: totals)
        suite.expect(totals.store.records.count == 2 && totals.store.records.map(\.tokens.total).reduce(0, +) == 145
                        && totals.cursors[folder.appending(path: "totals-child.jsonl").path]?.state.session == "totals-child",
                     "a Codex child's copy of its parent's running totals is not counted again")
        let legacy = AgentLogCursor(path: folder.appending(path: "legacy_main.jsonl").path, provider: .codex)
        _ = AgentLogParser.parseCodex(Data(#"{"type":"session_meta","payload":{"id":"legacy"}}"#.utf8),
                                      state: &legacy.state, now: Date())
        let custom = AgentLogCursor(path: folder.appending(path: "custom_client.jsonl").path, provider: .codex)
        _ = AgentLogParser.parseCodex(Data(#"{"type":"session_meta","payload":{"id":"custom","source":{"custom":"editor"}}}"#.utf8),
                                      state: &custom.state, now: Date())
        suite.expect(legacy.tracksTurns && custom.tracksTurns,
                     "Codex threads with no source or a custom client own their turns whatever the file name")
    }
}
