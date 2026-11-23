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
    public var notices: [Notice] = []
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
            compaction = Compaction(id: id, status: status, summary: summary)
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

    /// Clears all live state when starting or switching to another chat.
    public mutating func reset() {
        self = AgentLiveState(maxNotices: maxNotices)
    }
}
