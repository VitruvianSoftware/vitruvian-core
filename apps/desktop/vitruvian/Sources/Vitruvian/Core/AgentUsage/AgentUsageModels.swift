// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The coding agents whose session logs the island reads. Their names are
/// product names and stay untranslated.
package enum AgentProvider: String, CaseIterable, Identifiable, Codable {
    case claude, codex, opencode, copilot, antigravity

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .copilot: return "GitHub Copilot"
        case .antigravity: return "Antigravity"
        }
    }

    package var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .opencode: return "terminal"
        case .copilot: return "infinity"
        case .antigravity: return "sparkles"
        }
    }

    /// Whether the provider records a plan allowance in its local logs.
    package var reportsLimits: Bool { self != .copilot }
}

/// Token counts in the shape both logs can be reduced to. `input` excludes
/// cache traffic, and `output` already contains the reasoning tokens.
package struct AgentTokens: Equatable {
    package var input = 0
    package var cacheWrite = 0
    package var cacheRead = 0
    package var output = 0
    package var reasoning = 0

    package var total: Int { input + cacheWrite + cacheRead + output }
    /// Everything the model read, cached or not.
    package var prompt: Int { input + cacheWrite + cacheRead }
    package var cacheHitRate: Double? { prompt > 0 ? Double(cacheRead) / Double(prompt) : nil }

    package static func += (lhs: inout AgentTokens, rhs: AgentTokens) {
        lhs.input += rhs.input
        lhs.cacheWrite += rhs.cacheWrite
        lhs.cacheRead += rhs.cacheRead
        lhs.output += rhs.output
        lhs.reasoning += rhs.reasoning
    }

    /// Streamed replies are logged once per content block, and the earlier
    /// blocks carry the output counted so far. The largest reading is final.
    package func merged(with other: AgentTokens) -> AgentTokens {
        AgentTokens(input: max(input, other.input), cacheWrite: max(cacheWrite, other.cacheWrite),
                    cacheRead: max(cacheRead, other.cacheRead), output: max(output, other.output),
                    reasoning: max(reasoning, other.reasoning))
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(input: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0, output: Int = 0, reasoning: Int = 0) {
        self.input = input
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
        self.output = output
        self.reasoning = reasoning
    }
}

/// One billed model response.
package struct AgentUsageRecord: Equatable {
    package let provider: AgentProvider
    package let date: Date
    package let model: String
    package let project: String
    package let session: String
    /// Model requests represented by this record; checkpoints may hold several.
    package let requests: Int
    package var tokens: AgentTokens
    /// What the response would cost at API list prices, in US dollars. Nil
    /// when the model has no known price.
    package var cost: Double?
    /// What cache reads saved against paying the full input price.
    package var savings: Double
    /// Whether cost was reported directly by the provider rather than derived from list pricing.
    package var reportedCost: Bool = false
    /// Upstream backend route for multi-provider routers like OpenCode (e.g. "google", "anthropic").
    package var upstreamProvider: String = ""
    /// Active agent mode or persona when recorded (e.g. "build", "explore", "coder", "plan").
    package var agentMode: String = ""
    /// Tool invocations executed within this response when recorded.
    package var toolCalls: Int = 0

    // Spelled out because a memberwise initializer never leaves its module.
    package init(provider: AgentProvider, date: Date, model: String, project: String, session: String,
                 requests: Int = 1, tokens: AgentTokens, cost: Double? = nil, savings: Double,
                 reportedCost: Bool = false, upstreamProvider: String = "", agentMode: String = "",
                 toolCalls: Int = 0) {
        self.provider = provider
        self.date = date
        self.model = model
        self.project = project
        self.session = session
        self.requests = requests
        self.tokens = tokens
        self.cost = cost
        self.savings = savings
        self.reportedCost = reportedCost
        self.upstreamProvider = upstreamProvider
        self.agentMode = agentMode
        self.toolCalls = toolCalls
    }
}

/// A usage allowance and how much of it is spent, as the provider reports it.
package struct AgentLimitWindow: Equatable, Identifiable, Sendable {
    package enum Kind: String, Sendable {
        case session, weekly, other
    }

    package let id: String
    package let kind: Kind
    /// How long the window lasts, when the provider says so.
    package let minutes: Int?
    /// A model the allowance applies to; nil when it covers everything.
    package let scope: String?
    package let usedPercent: Double
    package let resetsAt: Date?
    /// A presentation estimate, never a deadline for clearing usage or alerts.
    package var estimatedResetsAt: Date? = nil

    package var usedFraction: Double { min(1, max(0, usedPercent / 100)) }
    package var remainingFraction: Double { 1 - usedFraction }

    /// A human-readable display title for this window, matching CodexBar conventions.
    package var name: String {
        if id.contains("gemini-5h") { return "Gemini 5-hour" }
        if id.contains("gemini-weekly") { return "Gemini weekly" }
        if id.contains("3p-5h") { return "Claude/GPT 5-hour" }
        if id.contains("3p-weekly") { return "Claude/GPT weekly" }
        if id.contains("fable") { return "Fable weekly" }
        if id == "claude.fh" { return "Session" }
        if id == "claude.sd" { return "Weekly" }
        if id == "claude.sn" { return "Sonnet weekly" }
        if id == "claude.so" { return "Opus weekly" }
        switch kind {
        case .session: return "Session"
        case .weekly: return scope.map { "\($0) weekly" } ?? "Weekly"
        case .other: return scope ?? "Limit"
        }
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, kind: Kind, minutes: Int?, scope: String?, usedPercent: Double, resetsAt: Date?,
                 estimatedResetsAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.minutes = minutes
        self.scope = scope
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.estimatedResetsAt = estimatedResetsAt
    }
}

package struct AgentLimits: Equatable, Sendable {
    package enum Source: Equatable, Sendable {
        /// Saved on this Mac by the Claude app, which checks them itself.
        case claudeApp
        /// Copied by the agent into its session log with each response.
        case sessionLog
        /// Asked of the agent on request, which checks the account itself.
        case account
    }

    package let provider: AgentProvider
    package var windows: [AgentLimitWindow]
    package let observedAt: Date
    package let source: Source

    // Spelled out because a memberwise initializer never leaves its module.
    package init(provider: AgentProvider, windows: [AgentLimitWindow], observedAt: Date, source: Source) {
        self.provider = provider
        self.windows = windows
        self.observedAt = observedAt
        self.source = source
    }
}

/// The subscription an account is on, when the agent's local files say.
package struct AgentPlan: Equatable {
    package let name: String
    /// Monthly list price in US dollars, used only to compare API value.
    package let monthlyPrice: Double?

    // Spelled out because a memberwise initializer never leaves its module.
    package init(name: String, monthlyPrice: Double?) {
        self.name = name
        self.monthlyPrice = monthlyPrice
    }
}

/// A turn an agent is working on right now, from its session log.
package struct AgentLiveSession: Equatable, Identifiable {
    package let id: String
    package let provider: AgentProvider
    package let started: Date
    package var lastActivity: Date
    package var model: String
    package var project: String
    package var tokens: AgentTokens
    package var cost: Double

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, provider: AgentProvider, started: Date, lastActivity: Date, model: String, project: String, tokens: AgentTokens, cost: Double) {
        self.id = id
        self.provider = provider
        self.started = started
        self.lastActivity = lastActivity
        self.model = model
        self.project = project
        self.tokens = tokens
        self.cost = cost
    }
}

/// Something worth a moment in the closed island.
package enum AgentUsageEvent: Equatable {
    case finished(provider: AgentProvider, duration: TimeInterval, cost: Double, tokens: Int, project: String)
    case limitWarning(provider: AgentProvider, window: AgentLimitWindow)
    case limitReset(provider: AgentProvider, window: AgentLimitWindow)
    case budgetReached(spent: Double, budget: Double)
}

/// An account's identity and subscription tier badge.
package struct AgentIdentity: Equatable, Sendable {
    package let email: String?
    package let planTier: String?

    package init(email: String? = nil, planTier: String? = nil) {
        self.email = email
        self.planTier = planTier
    }
}

/// Detailed token and cost metrics grid matching CodexBar.
package struct AgentCostMetrics: Equatable, Sendable {
    package let todayCost: Double
    package let thirtyDayCost: Double
    package let latestTokens: Int
    package let thirtyDayTokens: Int
    package let topModel: String?
    package let peakDayCost: Double?

    package init(
        todayCost: Double,
        thirtyDayCost: Double,
        latestTokens: Int,
        thirtyDayTokens: Int,
        topModel: String? = nil,
        peakDayCost: Double? = nil
    ) {
        self.todayCost = todayCost
        self.thirtyDayCost = thirtyDayCost
        self.latestTokens = latestTokens
        self.thirtyDayTokens = thirtyDayTokens
        self.topModel = topModel
        self.peakDayCost = peakDayCost
    }
}

/// A single day's cost and token usage for the 30-day spend bar chart.
package struct AgentDailyCost: Equatable, Identifiable, Sendable {
    package var id: String { date }
    package let date: String
    package let cost: Double
    package let tokens: Int
    package let topModel: String?

    package init(date: String, cost: Double, tokens: Int, topModel: String? = nil) {
        self.date = date
        self.cost = cost
        self.tokens = tokens
        self.topModel = topModel
    }
}

