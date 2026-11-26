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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Foundation

/// Value type holding the per-chat live session state produced by `AgentEvent` updates
/// (plan steps, config options, compaction status, notices, session metadata, and usage limits).
public struct AgentLiveState: Equatable, Sendable {
    public static let defaultMaxNotices = 20

    public struct Compaction: Identifiable, Equatable, Sendable {
        public var id: String
        public var status: String
        public var summary: String?

        public init(id: String, status: String, summary: String? = nil) {
            self.id = id
            self.status = status
            self.summary = summary
        }

        public var isInProgress: Bool {
            let lower = status.lowercased()
            return lower == "running" || lower == "in_progress" || lower == "compacting"
        }

        public var isFailed: Bool {
            let lower = status.lowercased()
            return lower == "failed" || lower == "error"
        }

        public var isInterrupted: Bool {
            let lower = status.lowercased()
            return lower == "interrupted" || lower == "cancelled" || lower == "stopped"
        }
    }

    public struct Notice: Identifiable, Equatable, Sendable {
        public var id: Int
        public var severity: String
        public var title: String
        public var detail: String?

        public init(id: Int, severity: String, title: String, detail: String? = nil) {
            self.id = id
            self.severity = severity
            self.title = title
            self.detail = detail
        }
    }

    public struct SessionInfo: Equatable, Sendable {
        public var title: String?
        public var updatedAt: String?

        public init(title: String? = nil, updatedAt: String? = nil) {
            self.title = title
            self.updatedAt = updatedAt
        }
    }

    public struct UsageLimit: Equatable, Sendable {
        public var resetsAt: Date?

        public init(resetsAt: Date? = nil) {
            self.resetsAt = resetsAt
        }
    }

    public var plan: [PlanEntry] = []
    public var configOptions: [AgentConfigOption] = []
    public var compaction: Compaction?
    public var compactions: [Compaction] = []
    public var notices: [Notice] = []
    public var dismissedNoticeIDs: Set<Int> = []
    public var sessionInfo: SessionInfo?
    public var usageLimit: UsageLimit?
    public let maxNotices: Int

    private var nextNoticeID: Int = 1

    public init(maxNotices: Int = AgentLiveState.defaultMaxNotices) {
        self.maxNotices = max(1, maxNotices)
    }

    /// Applies one `AgentEvent` to this state, ignoring events owned by the message stream.
    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case .planReplaced(let entries):
            plan = entries
        case .configOptions(let options):
            configOptions = options
        case .compaction(let id, let status, let summary):
            let updated = upsertCompaction(id: id, status: status, summary: summary)
            compaction = updated
        case .notice(let severity, let title, let detail):
            notices.append(Notice(id: nextNoticeID, severity: severity, title: title, detail: detail))
            nextNoticeID += 1
            if notices.count > maxNotices {
                notices.removeFirst(notices.count - maxNotices)
            }
        case .sessionInfo(let title, let updatedAt):
            var info = sessionInfo ?? SessionInfo()
            if let title {
                info.title = title
            }
            if let updatedAt {
                info.updatedAt = updatedAt
            }
            sessionInfo = info
        case .usageLimit(let resetsAt):
            usageLimit = UsageLimit(resetsAt: resetsAt)
        default:
            break
        }
    }

    /// Dismisses one notice without reordering or removing items from `notices`.
    public mutating func dismissNotice(id: Int) {
        dismissedNoticeIDs.insert(id)
    }

    /// Clears the active usage limit.
    public mutating func clearUsageLimit() {
        usageLimit = nil
    }

    /// Clears the active usage limit when its reset timestamp has already passed.
    @discardableResult
    public mutating func clearUsageLimitIfExpired(now: Date = Date()) -> Bool {
        guard let reset = usageLimit?.resetsAt, now >= reset else {
            return false
        }
        usageLimit = nil
        return true
    }

    @discardableResult
    private mutating func upsertCompaction(id: String, status: String, summary: String?) -> Compaction {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = Compaction(id: id, status: status, summary: summary)
        if !trimmedID.isEmpty,
           let idx = compactions.lastIndex(where: { $0.id == trimmedID }) {
            let merged = Compaction(
                id: compactions[idx].id,
                status: status,
                summary: summary ?? compactions[idx].summary
            )
            compactions[idx] = merged
            return merged
        }
        if trimmedID.isEmpty,
           !incoming.isInProgress,
           let idx = compactions.lastIndex(where: { $0.isInProgress }) {
            let merged = Compaction(
                id: compactions[idx].id,
                status: status,
                summary: summary ?? compactions[idx].summary
            )
            compactions[idx] = merged
            return merged
        }
        let assignedID = trimmedID.isEmpty ? "compaction-\(compactions.count + 1)" : id
        let created = Compaction(id: assignedID, status: status, summary: summary)
        compactions.append(created)
        return created
    }

    /// Clears all live state when starting or switching to another chat.
    public mutating func reset() {
        self = AgentLiveState(maxNotices: maxNotices)
    }
}

/// Threshold rules matching T3 Code's `COMPACTION_SUGGESTION_MIN_TOKENS` (`packages/shared/src/claudeCompaction.ts`).
public enum AgentCompactionSuggestion: Sendable {
    public static let minContextTokens = 200_000

    public static func shouldShow(
        isIdle: Bool,
        isLiveChat: Bool,
        isClaude: Bool,
        isCompacting: Bool,
        isDismissed: Bool,
        contextUsage: VitruvianCodeContextUsage?
    ) -> Bool {
        guard isIdle, isLiveChat, isClaude, !isCompacting, !isDismissed,
              let usage = contextUsage,
              !usage.isEstimate else {
            return false
        }
        return usage.totalTokens >= minContextTokens
    }
}

/// Formatting and resume-gate helpers for an active usage limit wait.
public enum AgentUsageLimitState: Sendable {
    public static func isResetPassed(_ limit: AgentLiveState.UsageLimit, now: Date = Date()) -> Bool {
        guard let resetsAt = limit.resetsAt else { return false }
        return now >= resetsAt
    }

    public static func canResume(_ limit: AgentLiveState.UsageLimit, now: Date = Date()) -> Bool {
        isResetPassed(limit, now: now)
    }

    public static func remainingSeconds(_ limit: AgentLiveState.UsageLimit, now: Date = Date()) -> Int? {
        guard let resetsAt = limit.resetsAt else { return nil }
        return max(0, Int(ceil(resetsAt.timeIntervalSince(now))))
    }

    public static func formattedCountdown(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, secs)
        }
        return "\(secs)s"
    }

    public static func formattedLocalResetTime(
        _ date: Date,
        now: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar.current
        calendar.locale = locale
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }
}

/// Structured live-connection failure surfaced in the chat error card.
public struct AgentLiveFailure: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        case generic
        case helperCrash = "helper_crash"
        case claudeCrash = "claude_crash"
        case interrupted
    }

    public var message: String
    public var detail: String?
    public var source: Source
    public var isLocked: Bool
    public var restartFailureCount: Int
    /// The agent needs the user to sign in, and these are the ways the card offers (`ACPAuth`).
    public var signInMethods: [AgentSignInMethod]
    /// True when the failure was the agent asking for sign-in.
    public var needsSignIn: Bool

    public init(
        message: String,
        detail: String? = nil,
        source: Source = .generic,
        isLocked: Bool = false,
        restartFailureCount: Int = 0,
        signInMethods: [AgentSignInMethod] = [],
        needsSignIn: Bool = false
    ) {
        self.message = message
        self.detail = detail
        self.source = source
        self.isLocked = isLocked
        self.restartFailureCount = restartFailureCount
        self.signInMethods = signInMethods
        self.needsSignIn = needsSignIn || !signInMethods.isEmpty
    }
}
