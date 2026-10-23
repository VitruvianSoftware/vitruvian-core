// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore

/// Reads OpenCode database rows as handed over by `AgentOpenCodeReader`.
/// Every session keeps its own turn and model tracking inside the shared
/// state, and a row that arrives after its session went quiet starts a
/// task of its own.
package struct OpenCodeReader: AgentHarnessReader {
    package var provider: AgentProvider { .opencode }

    package init() {}

    package func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard AgentLogParser.contains(line, #""role":""#) || AgentLogParser.contains(line, #""type":"reset""#) else { return [] }
        guard let json = AgentLogParser.object(line) else { return [] }
        if json["type"] as? String == "reset" {
            state.openCodeSessions.removeAll()
            state.turnOpen = false
            return [.reset(now)]
        }
        guard let role = json["role"] as? String, ["user", "assistant", "idle"].contains(role) else { return [] }
        let id = json["id"] as? String ?? ""
        let session = json["session_id"] as? String ?? ""
        let sessionID = session.isEmpty ? state.session : AgentLogParser.native(session)
        state.session = sessionID
        state.parentSession = json["parent_session_id"] as? String ?? ""

        var sessionState = state.openCodeSessions[sessionID] ?? OpenCodeSessionState()

        let cwd = (json["path"] as? [String: Any])?["cwd"] as? String ?? json["directory"] as? String ?? ""
        if !cwd.isEmpty {
            sessionState.project = AgentLogParser.projectName(cwd)
        }

        let timeCreated = (json["time"] as? [String: Any])?["created"] ?? json["time_created"]
        let date = AgentLogParser.seconds(timeCreated) ?? now
        // A session quiet this long with no reply being written starts its
        // next prompt as a task of its own, so what it kept to tell its rows
        // apart can go. Sessions are looked over only as a new one appears.
        if state.openCodeSessions[sessionID] == nil {
            state.openCodeSessions = state.openCodeSessions.filter { _, kept in
                !kept.writingReplyID.isEmpty
                    || date.timeIntervalSince(kept.lastActivity ?? date) < NotchAgentSupport.idleTurn
            }
        }
        let lastActivity = sessionState.lastActivity
        sessionState.lastActivity = max(lastActivity ?? date, date)

        switch role {
        case "user":
            if !id.isEmpty {
                // A prompt read again, as when its summary is saved, is no new one.
                if sessionState.seenUserMessageIDs.contains(id) { return [] }
                remember(id, in: &sessionState.seenUserMessageIDs)
                sessionState.activeUserMessageID = id
            }
            // OpenCode writes prompts of its own in the middle of a task: the
            // request that starts a compaction, the follow up after one, the
            // summary after a command's subtask. A prompt sent while it works
            // joins the running loop too, so inside a turn each is activity.
            var entries: [AgentLogEntry] = []
            // A prompt that arrives after the session went quiet is a task of
            // its own: the one before stopped without a word, as when a tool
            // call was rejected, and nothing finished. While a reply is still
            // being written, as through a long command, the prompt joins it.
            let quiet: Bool
            if let settled = sessionState.settledAt {
                quiet = date.timeIntervalSince(settled) >= AgentLogParser.openCodeSettle
            } else if sessionState.writingReplyID.isEmpty, let lastActivity {
                quiet = date.timeIntervalSince(lastActivity) >= NotchAgentSupport.idleTurn
            } else {
                quiet = false
            }
            sessionState.settledAt = nil
            sessionState.activePromptDate = date
            if sessionState.turnOpen && !quiet {
                entries.append(.turnActive(date))
            } else {
                if sessionState.turnOpen {
                    entries.append(.turnEnded(lastActivity, completed: false, duration: nil))
                }
                sessionState.turnOpen = true
                sessionState.turnStarted = date
                entries.append(.turnBegan(date))
            }
            let userModel = json["model_id"] as? String
                ?? json["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["id"] as? String
                ?? json["model"] as? String
            if let userModel, !userModel.isEmpty {
                sessionState.model = AgentLogParser.native(userModel)
            }
            let userProvider = (json["model"] as? [String: Any])?["providerID"] as? String
                ?? json["providerID"] as? String
            if let userProvider, !userProvider.isEmpty {
                sessionState.upstreamProvider = AgentLogParser.native(userProvider)
            }
            let userAgent = json["agent"] as? String ?? json["mode"] as? String
            if let userAgent, !userAgent.isEmpty {
                sessionState.agentMode = AgentLogParser.native(userAgent)
            }
            state.openCodeSessions[sessionID] = sessionState
            state.project = sessionState.project
            state.model = sessionState.model
            state.turnOpen = true
            return entries

        case "assistant":
            let rawModel = json["model_id"] as? String
                ?? json["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["id"] as? String
                ?? json["model"] as? String
            if let rawModel, !rawModel.isEmpty {
                sessionState.model = AgentLogParser.native(rawModel)
            }
            let rawProvider = (json["model"] as? [String: Any])?["providerID"] as? String
                ?? json["providerID"] as? String
            if let rawProvider, !rawProvider.isEmpty {
                sessionState.upstreamProvider = AgentLogParser.native(rawProvider)
            }
            let rawAgent = json["agent"] as? String ?? json["mode"] as? String
            if let rawAgent, !rawAgent.isEmpty {
                sessionState.agentMode = AgentLogParser.native(rawAgent)
            }
            let tokensDict = json["tokens"] as? [String: Any] ?? [:]
            let input = AgentLogParser.int(tokensDict["input"])
            let output = AgentLogParser.int(tokensDict["output"])
            let reasoning = AgentLogParser.int(tokensDict["reasoning"])
            let cacheDict = tokensDict["cache"] as? [String: Any] ?? [:]
            let cacheRead = AgentLogParser.int(cacheDict["read"])
            let cacheWrite = AgentLogParser.int(cacheDict["write"])
            let tokens = AgentTokens(input: input, cacheWrite: cacheWrite, cacheRead: cacheRead,
                                     output: output + reasoning, reasoning: reasoning)
            let billable = AgentBillable(tokens: tokens)
            let priced = AgentPricing.cost(billable, model: sessionState.model)
            let recordedCost = (json["cost"] as? NSNumber)?.doubleValue
            let reportedCostVal = recordedCost ?? 0
            // A model the list does not know costs what OpenCode recorded.
            // Local and free models record zero, which stays an estimate so
            // a price the list learns later still applies.
            let cost: Double?
            let isReported: Bool
            if let calculated = priced.cost {
                cost = calculated
                isReported = false
            } else if let recordedCost {
                cost = recordedCost
                isReported = recordedCost > 0
            } else {
                cost = nil
                isReported = false
            }

            let parentID = json["parentID"] as? String ?? ""
            let isAlreadyCompleted = (!id.isEmpty && sessionState.completedAssistantMessageIDs.contains(id))
                || (!parentID.isEmpty && sessionState.completedUserMessageIDs.contains(parentID))
            let matchesActivePrompt = parentID.isEmpty || parentID == sessionState.activeUserMessageID

            let timeCompleted = (json["time"] as? [String: Any])?["completed"]
            let completed = AgentLogParser.seconds(timeCompleted)
            let hasError = json["error"].map { !($0 is NSNull) } ?? false
            let finish = json["finish"] as? String
            if let completed { sessionState.lastActivity = max(sessionState.lastActivity ?? completed, completed) }
            // A step that starts after the last one settled is the loop going on.
            if let settled = sessionState.settledAt, date >= settled { sessionState.settledAt = nil }

            var entries: [AgentLogEntry] = []
            // OpenCode completes each reply before it answers a prompt sent
            // meanwhile. A reply to a newer prompt while an older one never
            // completed means OpenCode stopped in the middle of it, as when
            // it was killed, and the newer prompt started a task of its own.
            if !id.isEmpty, !sessionState.writingReplyID.isEmpty, sessionState.writingReplyID != id,
               sessionState.turnOpen, !parentID.isEmpty, parentID == sessionState.activeUserMessageID,
               let prompt = sessionState.activePromptDate, let started = sessionState.turnStarted, prompt > started {
                entries.append(.turnEnded(nil, completed: false, duration: nil))
                entries.append(.turnBegan(prompt))
                sessionState.turnStarted = prompt
            }
            if completed == nil && finish == nil && !hasError && !id.isEmpty {
                sessionState.writingReplyID = id
            } else if sessionState.writingReplyID == id {
                sessionState.writingReplyID = ""
            }
            if !isAlreadyCompleted && matchesActivePrompt && !sessionState.turnOpen {
                sessionState.turnOpen = true
                sessionState.turnStarted = date
                entries.append(.turnBegan(date))
            }
            // A reply is saved before its answer arrives, and a shell command
            // run from the prompt, the reply that hands work to a subtask and
            // a request that failed or was stopped never hold any usage.
            let toolCallCount = AgentLogParser.int(json["tool_call_count"])
            if tokens.total > 0 || reportedCostVal > 0 {
                let key = "opencode:\(sessionID):\(id.isEmpty ? "\(date.timeIntervalSince1970)" : id)"
                let record = AgentUsageRecord(
                    provider: .opencode, date: date, model: sessionState.model, project: sessionState.project,
                    session: sessionID, tokens: tokens, cost: cost, savings: priced.savings,
                    reportedCost: isReported, upstreamProvider: sessionState.upstreamProvider,
                    agentMode: sessionState.agentMode, toolCalls: toolCallCount
                )
                entries.append(.usage(key: key, record: record, billable: billable))
            }

            // OpenCode's loop goes on after tool calls, after a reply that
            // still holds calls whatever its finish says, and after the
            // summary of a compaction it started on its own. Any other finish
            // stops it, as does an error or a reply that completes without a
            // finish, like a shell command's.
            let ends: Bool
            if hasError {
                ends = true
            } else if let finish {
                ends = !["tool-calls", "unknown"].contains(finish)
                    && json["tool_calls"] as? Bool != true && json["auto_compaction"] as? Bool != true
            } else {
                ends = completed != nil
                    && json["tool_calls"] as? Bool != true && json["auto_compaction"] as? Bool != true
            }

            if ends {
                if !isAlreadyCompleted && matchesActivePrompt && sessionState.turnOpen {
                    let endDate = completed ?? AgentLogParser.seconds(json["time_updated"]) ?? date
                    var duration: TimeInterval?
                    if let turnStarted = sessionState.turnStarted {
                        if endDate >= turnStarted {
                            duration = endDate.timeIntervalSince(turnStarted)
                        }
                    } else if endDate >= date {
                        duration = endDate.timeIntervalSince(date)
                    }
                    sessionState.turnOpen = false
                    sessionState.turnStarted = nil
                    sessionState.activeUserMessageID = ""
                    sessionState.settledAt = nil
                    entries.append(.turnEnded(endDate, completed: !hasError, duration: duration))
                }
                if !id.isEmpty { remember(id, in: &sessionState.completedAssistantMessageIDs) }
                if !parentID.isEmpty { remember(parentID, in: &sessionState.completedUserMessageIDs) }
            } else if !isAlreadyCompleted && matchesActivePrompt {
                // A step that completed hands over to the next one at once,
                // unless the loop stopped there.
                if let completed, sessionState.turnOpen {
                    sessionState.settledAt = completed
                    entries.append(.turnSettled(completed))
                } else {
                    entries.append(.turnActive(date))
                }
            }
            state.openCodeSessions[sessionID] = sessionState
            state.project = sessionState.project
            state.model = sessionState.model
            state.turnOpen = sessionState.turnOpen
            return entries

        case "idle":
            guard sessionState.turnOpen else {
                state.openCodeSessions[sessionID] = sessionState
                return []
            }
            let outcome = json["outcome"] as? String
            let completed = outcome == nil || outcome == "succeeded"
            var duration: TimeInterval?
            if let turnStarted = sessionState.turnStarted, date >= turnStarted {
                duration = date.timeIntervalSince(turnStarted)
            }
            sessionState.turnOpen = false
            sessionState.turnStarted = nil
            sessionState.activeUserMessageID = ""
            sessionState.settledAt = nil
            sessionState.writingReplyID = ""
            state.openCodeSessions[sessionID] = sessionState
            state.project = sessionState.project
            state.model = sessionState.model
            state.turnOpen = false
            return [.turnEnded(date, completed: completed, duration: duration)]

        default:
            state.openCodeSessions[sessionID] = sessionState
            return []
        }
    }

    /// Keeps a bounded number of message ids a session has settled.
    private func remember(_ id: String, in ids: inout Set<String>) {
        if ids.count > 100 { ids.removeFirst() }
        ids.insert(id)
    }
}
