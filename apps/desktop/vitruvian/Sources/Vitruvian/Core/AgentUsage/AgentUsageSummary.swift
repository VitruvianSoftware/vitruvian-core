// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

package enum AgentPeriod: String, CaseIterable, Identifiable {
    case today, week, month

    package var id: String { rawValue }
    package var days: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        }
    }
}

package struct AgentTotals: Equatable {
    package var tokens = AgentTokens()
    package var cost = 0.0
    package var savings = 0.0
    package var requests = 0
    /// Responses from a model without a known price, left out of `cost`.
    package var unpriced = 0

    package mutating func add(_ record: AgentUsageRecord) {
        tokens += record.tokens
        requests += max(0, record.requests)
        savings += record.savings
        if let price = record.cost { cost += price } else { unpriced += 1 }
    }

    package static func += (lhs: inout AgentTotals, rhs: AgentTotals) {
        lhs.tokens += rhs.tokens
        lhs.cost += rhs.cost
        lhs.savings += rhs.savings
        lhs.requests += rhs.requests
        lhs.unpriced += rhs.unpriced
    }

    /// Cost when every response had a price, tokens otherwise, so shares
    /// and bars never compare dollars with token counts.
    package func weight(byCost: Bool) -> Double { byCost ? cost : Double(tokens.total) }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(tokens: AgentTokens = AgentTokens(), cost: Double = 0.0, savings: Double = 0.0, requests: Int = 0, unpriced: Int = 0) {
        self.tokens = tokens
        self.cost = cost
        self.savings = savings
        self.requests = requests
        self.unpriced = unpriced
    }
}

/// One row of a breakdown: a model or a project.
package struct AgentShare: Equatable, Identifiable {
    package let id: String
    package let name: String
    package let provider: AgentProvider?
    package var totals: AgentTotals

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, name: String, provider: AgentProvider?, totals: AgentTotals) {
        self.id = id
        self.name = name
        self.provider = provider
        self.totals = totals
    }
}

package struct AgentPeriodUsage: Equatable {
    package var total = AgentTotals()
    package var byProvider: [AgentProvider: AgentTotals] = [:]
    package var models: [AgentShare] = []
    package var projects: [AgentShare] = []
    package var projectsByProvider: [AgentProvider: [AgentShare]] = [:]
    package var openCodeRoutes: [AgentShare] = []
    package var openCodeModes: [AgentShare] = []
    package var openCodeSessions = 0
    package var openCodeToolCalls = 0

    /// Whether every response in the period could be priced.
    package var fullyPriced: Bool { total.unpriced == 0 }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(
        total: AgentTotals = AgentTotals(),
        byProvider: [AgentProvider: AgentTotals] = [:],
        models: [AgentShare] = [],
        projects: [AgentShare] = [],
        projectsByProvider: [AgentProvider: [AgentShare]] = [:],
        openCodeRoutes: [AgentShare] = [],
        openCodeModes: [AgentShare] = [],
        openCodeSessions: Int = 0,
        openCodeToolCalls: Int = 0
    ) {
        self.total = total
        self.byProvider = byProvider
        self.models = models
        self.projects = projects
        self.projectsByProvider = projectsByProvider
        self.openCodeRoutes = openCodeRoutes
        self.openCodeModes = openCodeModes
        self.openCodeSessions = openCodeSessions
        self.openCodeToolCalls = openCodeToolCalls
    }
}

/// A day or an hour of use.
package struct AgentBucket: Equatable, Identifiable {
    package let start: Date
    package var byProvider: [AgentProvider: AgentTotals] = [:]
    package var id: Date { start }

    package var total: AgentTotals {
        byProvider.values.reduce(into: AgentTotals()) { $0 += $1 }
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(start: Date, byProvider: [AgentProvider: AgentTotals] = [:]) {
        self.start = start
        self.byProvider = byProvider
    }
}

/// Claude's allowance renews five hours after the first request that
/// follows a renewal. Local activity alone places that window closely.
package struct AgentBlock: Equatable {
    package let start: Date
    package let end: Date
    package var totals: AgentTotals

    // Spelled out because a memberwise initializer never leaves its module.
    package init(start: Date, end: Date, totals: AgentTotals) {
        self.start = start
        self.end = end
        self.totals = totals
    }
}

package struct AgentUsageSnapshot: Equatable {
    package static let dayCount = 91

    package var loaded = false
    package var now = Date.distantPast
    package var periods: [AgentPeriod: AgentPeriodUsage] = [:]
    /// Oldest first, ending with today.
    package var days: [AgentBucket] = []
    /// Today's hours, from midnight.
    package var hours: [AgentBucket] = []
    package var limits: [AgentProvider: AgentLimits] = [:]
    package var plans: [AgentProvider: AgentPlan] = [:]
    package var live: [AgentLiveSession] = []
    package var claudeBlock: AgentBlock?
    /// The last half hour, scaled to an hour.
    package var burnRate: [AgentProvider: AgentTotals] = [:]
    package var lastActivity: [AgentProvider: Date] = [:]
    /// Providers with anything on disk: usage, limits or a turn.
    package var seen: Set<AgentProvider> = []
    package var identities: [AgentProvider: AgentIdentity] = [:]
    package var credits: [AgentProvider: Double] = [:]
    package var costMetrics: [AgentProvider: AgentCostMetrics] = [:]
    package var dailySpend: [AgentProvider: [AgentDailyCost]] = [:]

    package func usage(_ period: AgentPeriod) -> AgentPeriodUsage { periods[period] ?? AgentPeriodUsage() }
    package func working(_ provider: AgentProvider) -> [AgentLiveSession] { live.filter { $0.provider == provider } }

    /// Returns explicit cost metrics when available, or derives them from
    /// recorded usage for `provider` so single-provider tabs show that
    /// provider's own figures rather than falling back to another provider's.
    package func effectiveCostMetrics(for provider: AgentProvider) -> AgentCostMetrics? {
        if let explicit = costMetrics[provider] { return explicit }
        let monthTotals = usage(.month).byProvider[provider] ?? AgentTotals()
        let todayTotals = usage(.today).byProvider[provider] ?? AgentTotals()
        guard monthTotals.tokens.total > 0 || monthTotals.cost > 0 || todayTotals.tokens.total > 0 || todayTotals.cost > 0 else {
            return nil
        }
        let peak = days.suffix(AgentPeriod.month.days).compactMap { $0.byProvider[provider]?.cost }.max()
        let topModel = usage(.month).models.first(where: { $0.provider == provider })?.name
        return AgentCostMetrics(
            todayCost: todayTotals.cost,
            thirtyDayCost: monthTotals.cost,
            latestTokens: todayTotals.tokens.total,
            thirtyDayTokens: monthTotals.tokens.total,
            topModel: topModel,
            peakDayCost: (peak ?? 0) > 0 ? peak : nil
        )
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(
        loaded: Bool = false,
        now: Date = Date.distantPast,
        periods: [AgentPeriod: AgentPeriodUsage] = [:],
        days: [AgentBucket] = [],
        hours: [AgentBucket] = [],
        limits: [AgentProvider: AgentLimits] = [:],
        plans: [AgentProvider: AgentPlan] = [:],
        live: [AgentLiveSession] = [],
        claudeBlock: AgentBlock? = nil,
        burnRate: [AgentProvider: AgentTotals] = [:],
        lastActivity: [AgentProvider: Date] = [:],
        seen: Set<AgentProvider> = [],
        identities: [AgentProvider: AgentIdentity] = [:],
        credits: [AgentProvider: Double] = [:],
        costMetrics: [AgentProvider: AgentCostMetrics] = [:],
        dailySpend: [AgentProvider: [AgentDailyCost]] = [:]
    ) {
        self.loaded = loaded
        self.now = now
        self.periods = periods
        self.days = days
        self.hours = hours
        self.limits = limits
        self.plans = plans
        self.live = live
        self.claudeBlock = claudeBlock
        self.burnRate = burnRate
        self.lastActivity = lastActivity
        self.seen = seen
        self.identities = identities
        self.credits = credits
        self.costMetrics = costMetrics
        self.dailySpend = dailySpend
    }
}

package enum AgentUsageSummary {
    package static let blockLength: TimeInterval = 5 * 3600
    /// Each window starts where the one before it ended, so a chain cut
    /// short lands on other hours; a day of history covers any real stretch.
    package static let blockHistory: TimeInterval = 24 * 3600
    package static let burnWindow: TimeInterval = 30 * 60

    package static func snapshot(records: [AgentUsageRecord], limits: [AgentProvider: AgentLimits],
                         live: [AgentLiveSession], plans: [AgentProvider: AgentPlan],
                         providers: Set<AgentProvider>, now: Date,
                         calendar: Calendar = .autoupdatingCurrent) -> AgentUsageSnapshot {
        var snapshot = AgentUsageSnapshot(loaded: true, now: now)
        snapshot.limits = limits.filter { providers.contains($0.key) }
        snapshot.plans = plans.filter { providers.contains($0.key) }
        snapshot.live = live.filter { providers.contains($0.provider) }.sorted { $0.started < $1.started }
        snapshot.seen = Set(snapshot.limits.keys).union(snapshot.live.map(\.provider))

        let today = calendar.startOfDay(for: now)
        let starts: [Date] = (0..<AgentUsageSnapshot.dayCount).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let hourStarts: [Date] = (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: today) }
        var days = starts.map { AgentBucket(start: $0) }
        var hours = hourStarts.map { AgentBucket(start: $0) }
        var periods: [AgentPeriod: AgentPeriodUsage] = [:]
        var models: [AgentPeriod: [String: AgentShare]] = [:]
        var projects: [AgentPeriod: [String: AgentShare]] = [:]
        var projectsByProvider: [AgentPeriod: [AgentProvider: [String: AgentShare]]] = [:]
        var openCodeRoutes: [AgentPeriod: [String: AgentShare]] = [:]
        var openCodeModes: [AgentPeriod: [String: AgentShare]] = [:]
        var openCodeSessions: [AgentPeriod: Set<String>] = [:]
        var claude: [AgentUsageRecord] = []
        var names: [String: String] = [:]
        let recent = now.addingTimeInterval(-burnWindow)
        let lastDay = starts.count - 1

        for record in records where providers.contains(record.provider) {
            snapshot.seen.insert(record.provider)
            snapshot.lastActivity[record.provider] = max(snapshot.lastActivity[record.provider] ?? .distantPast, record.date)
            if record.provider == .claude, record.date > now.addingTimeInterval(-blockHistory), record.date <= now {
                claude.append(record)
            }
            if record.date >= recent, record.date <= now {
                snapshot.burnRate[record.provider, default: AgentTotals()].add(record)
            }
            guard let first = starts.first, record.date >= first, record.date < tomorrow,
                  let day = index(of: record.date, in: starts) else { continue }
            days[day].byProvider[record.provider, default: AgentTotals()].add(record)
            if day == lastDay, let hour = index(of: record.date, in: hourStarts) {
                hours[hour].byProvider[record.provider, default: AgentTotals()].add(record)
            }
            // One name per model string, not per response: the history can
            // hold tens of thousands of them.
            let name: String
            if let known = names[record.model] {
                name = known
            } else {
                name = AgentPricing.displayName(record.model)
                names[record.model] = name
            }
            let modelID = record.provider.rawValue + ":" + name
            let openCodeRouteName = record.provider == .opencode
                ? AgentPricing.upstreamDisplayName(providerID: record.upstreamProvider, model: record.model)
                : ""
            let openCodeRouteID = "opencode.route:" + openCodeRouteName
            for period in AgentPeriod.allCases where day > lastDay - period.days {
                periods[period, default: AgentPeriodUsage()].total.add(record)
                periods[period, default: AgentPeriodUsage()].byProvider[record.provider, default: AgentTotals()].add(record)
                models[period, default: [:]][modelID, default: AgentShare(
                    id: modelID, name: name.isEmpty ? "?" : name, provider: record.provider, totals: AgentTotals())]
                    .totals.add(record)
                if !record.project.isEmpty {
                    projects[period, default: [:]][record.project, default: AgentShare(
                        id: record.project, name: record.project, provider: nil, totals: AgentTotals())]
                        .totals.add(record)
                    projectsByProvider[period, default: [:]][record.provider, default: [:]][record.project, default: AgentShare(
                        id: record.project, name: record.project, provider: record.provider, totals: AgentTotals())]
                        .totals.add(record)
                }
                if record.provider == .opencode {
                    openCodeRoutes[period, default: [:]][openCodeRouteID, default: AgentShare(
                        id: openCodeRouteID, name: openCodeRouteName, provider: .opencode, totals: AgentTotals())]
                        .totals.add(record)
                    if !record.agentMode.isEmpty {
                        let modeID = "opencode.mode:" + record.agentMode
                        openCodeModes[period, default: [:]][modeID, default: AgentShare(
                            id: modeID, name: record.agentMode, provider: .opencode, totals: AgentTotals())]
                            .totals.add(record)
                    }
                    periods[period, default: AgentPeriodUsage()].openCodeToolCalls += max(0, record.toolCalls)
                    if !record.session.isEmpty {
                        openCodeSessions[period, default: []].insert(record.session)
                    }
                }
            }
        }
        for period in AgentPeriod.allCases {
            var usage = periods[period] ?? AgentPeriodUsage()
            let byCost = usage.fullyPriced
            usage.models = sorted(models[period].map { Array($0.values) } ?? [], byCost: byCost)
            usage.projects = sorted(projects[period].map { Array($0.values) } ?? [], byCost: byCost)
            for (provider, map) in projectsByProvider[period] ?? [:] {
                let providerByCost = (usage.byProvider[provider]?.unpriced ?? 0) == 0
                usage.projectsByProvider[provider] = sorted(Array(map.values), byCost: providerByCost)
            }
            let ocTotals = usage.byProvider[.opencode]
            let openCodeByCost = (ocTotals?.unpriced ?? 0) == 0 && (ocTotals?.cost ?? 0) > 0
            usage.openCodeRoutes = sorted(openCodeRoutes[period].map { Array($0.values) } ?? [], byCost: openCodeByCost)
            usage.openCodeModes = sorted(openCodeModes[period].map { Array($0.values) } ?? [], byCost: openCodeByCost)
            usage.openCodeSessions = openCodeSessions[period]?.count ?? 0
            periods[period] = usage
        }
        for provider in Array(snapshot.burnRate.keys) {
            guard var rate = snapshot.burnRate[provider] else { continue }
            let scale = 3600 / burnWindow
            rate.cost *= scale
            rate.savings *= scale
            rate.tokens = AgentTokens(input: Int(Double(rate.tokens.input) * scale),
                                      cacheWrite: Int(Double(rate.tokens.cacheWrite) * scale),
                                      cacheRead: Int(Double(rate.tokens.cacheRead) * scale),
                                      output: Int(Double(rate.tokens.output) * scale),
                                      reasoning: Int(Double(rate.tokens.reasoning) * scale))
            snapshot.burnRate[provider] = rate
        }
        snapshot.periods = periods
        snapshot.days = days
        snapshot.hours = hours
        snapshot.claudeBlock = currentBlock(claude, now: now)
        return snapshot
    }

    /// Whether a snapshot reads differently at `now` with nothing new read:
    /// the last half hour slides, a Claude window can end and a new day
    /// moves every total. The rest changes only with what the logs say.
    package static func movesWithClock(_ snapshot: AgentUsageSnapshot, now: Date,
                               calendar: Calendar = .autoupdatingCurrent) -> Bool {
        !snapshot.burnRate.isEmpty || snapshot.claudeBlock != nil || !calendar.isDate(snapshot.now, inSameDayAs: now)
    }

    package static func sorted(_ shares: [AgentShare], byCost: Bool) -> [AgentShare] {
        shares.sorted {
            let left = $0.totals.weight(byCost: byCost), right = $1.totals.weight(byCost: byCost)
            return left != right ? left > right : $0.name < $1.name
        }
    }

    /// The last start at or before `date`, by bisection.
    package static func index(of date: Date, in starts: [Date]) -> Int? {
        guard let first = starts.first, date >= first else { return nil }
        var low = 0, high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= date { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Windows start at the first request after the previous one ended and
    /// last five hours from that moment, the renewal time the provider's own
    /// usage page shows.
    package static func currentBlock(_ records: [AgentUsageRecord], now: Date) -> AgentBlock? {
        var block: AgentBlock?
        // Sorting positions moves no strings: a day of records is thousands.
        for position in records.indices.sorted(by: { records[$0].date < records[$1].date }) {
            let record = records[position]
            if let current = block, record.date < current.end {
                block?.totals.add(record)
                continue
            }
            var next = AgentBlock(start: record.date, end: record.date.addingTimeInterval(blockLength), totals: AgentTotals())
            next.totals.add(record)
            block = next
        }
        guard let block, block.end > now else { return nil }
        return block
    }
}

/// Queue-confined history totals. Ordinary log updates add only new responses
/// or the difference from a streamed response. Calendar changes, pruning and
/// repricing rebuild from the authoritative store instead of trying to undo
/// old buckets. The short sliding windows are evaluated at publication time.
package final class AgentUsageSummaryCache {
    private var history: AgentUsageSnapshot?
    private var calendar: Calendar?
    private var providers: Set<AgentProvider> = []
    private var models: [AgentPeriod: [String: AgentShare]] = [:]
    private var projects: [AgentPeriod: [String: AgentShare]] = [:]
    private var projectsByProvider: [AgentPeriod: [AgentProvider: [String: AgentShare]]] = [:]
    private var openCodeRoutes: [AgentPeriod: [String: AgentShare]] = [:]
    private var openCodeModes: [AgentPeriod: [String: AgentShare]] = [:]
    private var openCodeSessions: [AgentPeriod: Set<String>] = [:]
    private var names: [String: String] = [:]
    private var starts: [Date] = []
    private var hourStarts: [Date] = []
    private var tomorrow = Date.distantPast
    private struct Change { let previous: AgentUsageRecord? }
    private var changes: [Int: Change] = [:]
    private var recentPositions: Set<Int> = []
    private var lastTime = Date.distantPast
    /// Records accumulated on the last publication, for performance contracts.
    package private(set) var accumulatedRecords = 0

    package func invalidate() {
        history = nil
        changes.removeAll(keepingCapacity: true)
        recentPositions.removeAll(keepingCapacity: true)
    }

    package func recordChanged(at position: Int, previous: AgentUsageRecord?) {
        guard history != nil, changes[position] == nil else { return }
        // Keep the value before the first change, including a response added
        // and streamed again before the next publication.
        changes[position] = Change(previous: previous)
    }

    package func snapshot(records: [AgentUsageRecord], limits: [AgentProvider: AgentLimits],
                  live: [AgentLiveSession], plans: [AgentProvider: AgentPlan],
                  providers: Set<AgentProvider>, now: Date,
                  calendar: Calendar = .current) -> AgentUsageSnapshot {
        accumulatedRecords = 0
        let rebuild = history == nil || self.calendar != calendar || self.providers != providers
            || now < lastTime || !calendar.isDate(lastTime, inSameDayAs: now)
        if rebuild {
            self.calendar = calendar
            self.providers = providers
            models.removeAll(keepingCapacity: true)
            projects.removeAll(keepingCapacity: true)
            projectsByProvider.removeAll(keepingCapacity: true)
            openCodeRoutes.removeAll(keepingCapacity: true)
            openCodeModes.removeAll(keepingCapacity: true)
            openCodeSessions.removeAll(keepingCapacity: true)
            names.removeAll(keepingCapacity: true)
            recentPositions.removeAll(keepingCapacity: true)
            history = AgentUsageSummary.snapshot(records: [], limits: [:], live: [], plans: [:],
                                                 providers: providers, now: now, calendar: calendar)
            starts = history!.days.map(\.start)
            hourStarts = history!.hours.map(\.start)
            let today = calendar.startOfDay(for: now)
            tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
            for position in records.indices {
                accumulate(records[position], previous: nil)
                if isRecent(records[position], now: now) { recentPositions.insert(position) }
            }
        } else {
            for position in changes.keys.sorted() {
                accumulate(records[position], previous: changes[position]?.previous)
                if isRecent(records[position], now: now) { recentPositions.insert(position) }
            }
        }
        if rebuild || !changes.isEmpty {
            for period in AgentPeriod.allCases {
                let byCost = history!.periods[period]!.fullyPriced
                history!.periods[period]!.models = AgentUsageSummary.sorted(
                    models[period].map { Array($0.values) } ?? [], byCost: byCost)
                history!.periods[period]!.projects = AgentUsageSummary.sorted(
                    projects[period].map { Array($0.values) } ?? [], byCost: byCost)
                for (provider, map) in projectsByProvider[period] ?? [:] {
                    let providerByCost = (history!.periods[period]!.byProvider[provider]?.unpriced ?? 0) == 0
                    history!.periods[period]!.projectsByProvider[provider] = AgentUsageSummary.sorted(
                        Array(map.values), byCost: providerByCost)
                }
                let ocTotals = history!.periods[period]!.byProvider[.opencode]
                let openCodeByCost = (ocTotals?.unpriced ?? 0) == 0 && (ocTotals?.cost ?? 0) > 0
                history!.periods[period]!.openCodeRoutes = AgentUsageSummary.sorted(
                    openCodeRoutes[period].map { Array($0.values) } ?? [], byCost: openCodeByCost)
                history!.periods[period]!.openCodeModes = AgentUsageSummary.sorted(
                    openCodeModes[period].map { Array($0.values) } ?? [], byCost: openCodeByCost)
                history!.periods[period]!.openCodeSessions = openCodeSessions[period]?.count ?? 0
            }
        }
        changes.removeAll(keepingCapacity: true)
        lastTime = now
        var result = history!
        result.now = now
        result.limits = limits.filter { providers.contains($0.key) }
        result.plans = plans.filter { providers.contains($0.key) }
        result.live = live.filter { providers.contains($0.provider) }.sorted { $0.started < $1.started }
        result.seen.formUnion(result.limits.keys)
        result.seen.formUnion(result.live.map(\.provider))
        var claude: [AgentUsageRecord] = []
        // Stable store order also preserves the original accumulation order.
        for position in recentPositions.sorted() {
            let record = records[position]
            guard isRecent(record, now: now) else { recentPositions.remove(position); continue }
            guard record.date <= now else { continue }
            if record.provider == .claude { claude.append(record) }
            if record.date >= now.addingTimeInterval(-AgentUsageSummary.burnWindow) {
                result.burnRate[record.provider, default: AgentTotals()].add(record)
            }
        }
        for provider in Array(result.burnRate.keys) {
            let total = result.burnRate[provider]!
            // Scale amounts, not the number of responses or unpriced entries.
            result.burnRate[provider]!.tokens += total.tokens
            result.burnRate[provider]!.cost *= 2
            result.burnRate[provider]!.savings *= 2
        }
        result.claudeBlock = AgentUsageSummary.currentBlock(claude, now: now)
        return result
    }

    private func isRecent(_ record: AgentUsageRecord, now: Date) -> Bool {
        guard providers.contains(record.provider) else { return false }
        return record.provider == .claude
            ? record.date > now.addingTimeInterval(-AgentUsageSummary.blockHistory)
            : record.date >= now.addingTimeInterval(-AgentUsageSummary.burnWindow)
    }

    private func accumulate(_ record: AgentUsageRecord, previous: AgentUsageRecord?) {
        guard providers.contains(record.provider) else { return }
        accumulatedRecords += 1
        history!.seen.insert(record.provider)
        history!.lastActivity[record.provider] = max(history!.lastActivity[record.provider] ?? .distantPast, record.date)
        guard record.date < tomorrow, let day = AgentUsageSummary.index(of: record.date, in: starts) else { return }
        var delta = AgentTotals()
        delta.add(record)
        if let previous {
            delta.tokens += AgentTokens(input: -previous.tokens.input, cacheWrite: -previous.tokens.cacheWrite,
                                        cacheRead: -previous.tokens.cacheRead, output: -previous.tokens.output,
                                        reasoning: -previous.tokens.reasoning)
            delta.cost -= previous.cost ?? 0
            delta.savings -= previous.savings
            delta.requests -= previous.requests
            delta.unpriced -= previous.cost == nil ? 1 : 0
        }
        history!.days[day].byProvider[record.provider, default: AgentTotals()] += delta
        if day == starts.count - 1, let hour = AgentUsageSummary.index(of: record.date, in: hourStarts) {
            history!.hours[hour].byProvider[record.provider, default: AgentTotals()] += delta
        }
        let name = names[record.model] ?? AgentPricing.displayName(record.model)
        names[record.model] = name
        let modelID = record.provider.rawValue + ":" + name
        let openCodeRouteName = record.provider == .opencode
            ? AgentPricing.upstreamDisplayName(providerID: record.upstreamProvider, model: record.model)
            : ""
        let openCodeRouteID = "opencode.route:" + openCodeRouteName
        let toolDelta = max(0, record.toolCalls) - max(0, previous?.toolCalls ?? 0)
        for period in AgentPeriod.allCases where day > starts.count - 1 - period.days {
            history!.periods[period]!.total += delta
            history!.periods[period]!.byProvider[record.provider, default: AgentTotals()] += delta
            models[period, default: [:]][modelID, default: AgentShare(
                id: modelID, name: name.isEmpty ? "?" : name, provider: record.provider, totals: AgentTotals())].totals += delta
            if !record.project.isEmpty {
                projects[period, default: [:]][record.project, default: AgentShare(
                    id: record.project, name: record.project, provider: nil, totals: AgentTotals())].totals += delta
                projectsByProvider[period, default: [:]][record.provider, default: [:]][record.project, default: AgentShare(
                    id: record.project, name: record.project, provider: record.provider, totals: AgentTotals())].totals += delta
            }
            if record.provider == .opencode {
                openCodeRoutes[period, default: [:]][openCodeRouteID, default: AgentShare(
                    id: openCodeRouteID, name: openCodeRouteName, provider: .opencode, totals: AgentTotals())].totals += delta
                if !record.agentMode.isEmpty {
                    let modeID = "opencode.mode:" + record.agentMode
                    openCodeModes[period, default: [:]][modeID, default: AgentShare(
                        id: modeID, name: record.agentMode, provider: .opencode, totals: AgentTotals())].totals += delta
                }
                history!.periods[period]!.openCodeToolCalls += toolDelta
                if !record.session.isEmpty {
                    openCodeSessions[period, default: []].insert(record.session)
                }
            }
        }
    }

    // Spelled out because a default initializer never leaves its module.
    package init() {}
}

/// How spending compares with the time a window has left.
package struct AgentPace: Equatable {
    /// How much of the window's time has passed, from 0 to 1.
    package let elapsed: Double
    package let expectedUsedPercent: Double
    package let deltaPercent: Double
    package let reservePercent: Double
    package let willLastToReset: Bool
    package let reserveText: String
    package let sessionQuotasLeft: Double?
    package let windowsUntilReset: Int?
    package let summary: String

    // Spelled out because a memberwise initializer never leaves its module.
    package init(
        elapsed: Double,
        expectedUsedPercent: Double = 0,
        deltaPercent: Double = 0,
        reservePercent: Double = 0,
        willLastToReset: Bool = true,
        reserveText: String = "On pace",
        sessionQuotasLeft: Double? = nil,
        windowsUntilReset: Int? = nil,
        summary: String = ""
    ) {
        self.elapsed = elapsed
        self.expectedUsedPercent = expectedUsedPercent
        self.deltaPercent = deltaPercent
        self.reservePercent = reservePercent
        self.willLastToReset = willLastToReset
        self.reserveText = reserveText
        self.sessionQuotasLeft = sessionQuotasLeft
        self.windowsUntilReset = windowsUntilReset
        self.summary = summary
    }
}

package enum AgentLimitSupport {
    /// A window that renewed since it was read has nothing spent on it yet.
    package static func current(_ window: AgentLimitWindow, at now: Date) -> AgentLimitWindow {
        guard let resets = window.resetsAt, resets <= now else { return window }
        return AgentLimitWindow(id: window.id, kind: window.kind, minutes: window.minutes,
                                scope: window.scope, usedPercent: 0, resetsAt: nil)
    }

    /// Once an estimate has passed, the countdown is unknown until another
    /// reading places it. That does not mean the allowance has renewed.
    package static func displayedReset(_ window: AgentLimitWindow, now: Date) -> Date? {
        guard let reset = window.estimatedResetsAt ?? window.resetsAt, reset > now else { return nil }
        return reset
    }

    package static func pace(
        for window: AgentLimitWindow,
        now: Date,
        weeklyWindow: AgentLimitWindow? = nil,
        sessionWindow: AgentLimitWindow? = nil
    ) -> AgentPace? {
        guard let minutes = window.minutes, minutes > 0,
              let resets = displayedReset(window, now: now) else { return nil }
        let length = TimeInterval(minutes) * 60
        let elapsed = now.timeIntervalSince(resets.addingTimeInterval(-length))
        guard elapsed > 0 else { return nil }
        let fraction = min(1.0, max(0.0, elapsed / length))
        let expectedUsed = fraction * 100.0
        let delta = window.usedPercent - expectedUsed
        let reserve = expectedUsed - window.usedPercent
        let willLast = window.usedPercent <= expectedUsed || window.usedPercent <= 0

        let reserveText: String
        if abs(delta) <= 2.0 {
            reserveText = "On pace"
        } else if reserve > 0 {
            reserveText = "\(Int(round(reserve)))% in reserve"
        } else {
            reserveText = "\(Int(round(-reserve)))% in deficit"
        }

        var sessionQuotas: Double? = nil
        var windowsCount: Int? = nil

        let targetWeekly = (window.kind == .weekly) ? window : weeklyWindow
        if let weekly = targetWeekly, let weeklyResets = weekly.resetsAt, weeklyResets > now {
            let secondsUntilWeeklyReset = weeklyResets.timeIntervalSince(now)
            windowsCount = max(0, Int(floor(secondsUntilWeeklyReset / (5 * 3600))))
            let remainingWeeklyPercent = max(0.0, 100.0 - weekly.usedPercent)
            let sessionBurn = sessionWindow?.usedPercent ?? 0
            if sessionBurn > 0 {
                sessionQuotas = remainingWeeklyPercent / max(1.0, sessionBurn)
            } else {
                sessionQuotas = remainingWeeklyPercent / 8.0
            }
        }

        var summaryParts: [String] = [reserveText]
        summaryParts.append(willLast ? "Lasts until reset" : "Will exhaust early")
        if window.kind == .weekly {
            if let sessionQuotas {
                summaryParts.append("Est. \(String(format: "%.1f", locale: Locale.current, sessionQuotas)) session quotas left")
            }
            if let windowsCount {
                summaryParts.append("\(windowsCount) windows until reset")
            }
        }
        let summary = summaryParts.joined(separator: " · ")

        return AgentPace(
            elapsed: fraction,
            expectedUsedPercent: expectedUsed,
            deltaPercent: delta,
            reservePercent: reserve,
            willLastToReset: willLast,
            reserveText: reserveText,
            sessionQuotasLeft: sessionQuotas,
            windowsUntilReset: windowsCount,
            summary: summary
        )
    }

    /// The window that will stop work first: the most spent, and on a tie the
    /// one renewing last.
    package static func binding(_ limits: AgentLimits?, now: Date) -> AgentLimitWindow? {
        limits?.windows.map { current($0, at: now) }.max {
            $0.usedPercent != $1.usedPercent ? $0.usedPercent < $1.usedPercent
                : ($0.resetsAt ?? .distantPast) < ($1.resetsAt ?? .distantPast)
        }
    }

    /// Windows that reached `threshold` percent between two readings of the
    /// same account. A renewed window starts again from zero.
    package static func crossings(previous: AgentLimits?, current: AgentLimits, threshold: Double) -> [AgentLimitWindow] {
        guard threshold > 0 else { return [] }
        return current.windows.filter { window in
            guard window.usedPercent >= threshold else { return false }
            guard let previous, let before = previous.windows.first(where: { $0.id == window.id }) else { return false }
            return before.usedPercent < threshold || renewed(before, to: window, observedAt: current.observedAt)
                || current.source == .account && began(window, after: previous.observedAt)
        }
    }

    /// Whether the account's exact renewal places the start of `window`
    /// after `time`. Read after a gap, a session the reading before never saw
    /// is a new one, however late that reading placed the old one's end.
    private static func began(_ window: AgentLimitWindow, after time: Date) -> Bool {
        guard let minutes = window.minutes, let resets = window.resetsAt else { return false }
        return resets.addingTimeInterval(-TimeInterval(minutes) * 60) > time
    }

    /// Whether `window`, read at `observedAt`, comes after the one `before`
    /// saw: its usage fell, as a renewal or a reset used early leaves it, or
    /// its renewal moved on once the old one went by. A renewal that only
    /// moves before then is the same window read another way, as the Claude
    /// app's latest possible end is the account's exact one minutes later.
    package static func renewed(_ before: AgentLimitWindow, to window: AgentLimitWindow, observedAt: Date) -> Bool {
        if window.usedPercent + 1 < before.usedPercent { return true }
        guard let was = before.resetsAt, let resets = window.resetsAt else { return false }
        return resets.timeIntervalSince(was) > 60 && observedAt >= was
    }
}
