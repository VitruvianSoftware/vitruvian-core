// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The AI page: cards the person picked, paired across the strip.
package struct NotchAgentsView: View {
    package let size: CGSize
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var notchService = NotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(Preferences.notchAgentsPeriod) private var period: String
    @AppStorage(Preferences.notchAgentsLimitDisplay) private var display: String
    @AppStorage(Preferences.notchAgentsCardOrder) private var cardOrder: String
    @AppStorage(Preferences.notchAgentsHiddenCards) private var hiddenCards: String
    @AppStorage(Preferences.notchAgentsClaude) private var claude: Bool
    @AppStorage(Preferences.notchAgentsCodex) private var codex: Bool
    @AppStorage(Preferences.notchAgentsOpenCode) private var opencode: Bool
    @AppStorage(Preferences.notchAgentsCopilot) private var copilot: Bool
    @AppStorage(Preferences.notchAgentsAntigravity) private var antigravity: Bool
    @AppStorage(Preferences.notchAgentsTelemetryFilter) private var telemetryFilterRaw: String

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var chosenPeriod: AgentPeriod { AgentPeriod(rawValue: period) ?? .today }
    private var telemetryFilter: NotchTelemetryFilter {
        NotchTelemetryFilter(rawValue: telemetryFilterRaw) ?? .antigravity
    }

    /// Only agents that left something on this Mac get cards, filtered by provider tab.
    private var providers: [AgentProvider] {
        // The switches are read here so a change in Settings redraws the page.
        _ = (claude, codex, opencode, copilot, antigravity)
        return NotchAgentSupport.pageProviders(seen: usage.snapshot.seen, filter: telemetryFilter)
    }

    private var rows: [[NotchAgentTile]] {
        // The strings are read here so a change in Settings redraws the page.
        _ = (cardOrder, hiddenCards)
        return NotchAgentSupport.pageRows(providers: providers, width: size.width)
    }

    /// The chat tab is the place kept for a tool in the Agents slot; with
    /// no tool there the page is its telemetry alone, whatever tab was
    /// chosen (`NotchService.hasAgentsSlotTool`).
    private var chatAvailable: Bool { NotchService.hasAgentsSlotTool() }
    private var tab: NotchAgentTab { chatAvailable ? notchService.agentTab : .telemetry }

    package var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Spacer()
                if chatAvailable {
                    Picker("Mode", selection: $notchService.agentTab) {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right.fill").tag(NotchAgentTab.chat)
                        Label("Telemetry", systemImage: "chart.bar.fill").tag(NotchAgentTab.telemetry)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                if tab == .chat {
                    Button {
                        // The tool in the slot opens its own window when told.
                        AgentsSlotReporter.shared.popOut()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                            .padding(4)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Pop out to floating window (⌃Space)")
                } else {
                    Spacer().frame(width: 25)
                }
                Spacer()
            }
            .padding(.top, 4)
            .padding(.horizontal, 16)

            if tab == .chat {
                // The tool draws here itself, told where by `ui/slot`.
                AgentsSlotPlace { AgentsSlotReporter.shared.measured($0) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                telemetryFilterBar
                telemetryContent
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear {
            usage.pageDidAppear()
            AgentsSlotReporter.shared.start()
        }
    }

    private var telemetryFilterBar: some View {
        HStack {
            Spacer()
            // A segmented picker draws its title beside it, where a narrow
            // island wraps it into the control; the title stays for VoiceOver.
            Picker("Provider", selection: $telemetryFilterRaw) {
                ForEach(NotchTelemetryFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    @ViewBuilder private var telemetryContent: some View {
        if !usage.snapshot.loaded {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(text.loading).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if providers.isEmpty {
            NotchEmptyView(symbol: "sparkles", message: text.empty)
        } else if rows.isEmpty {
            NotchEmptyView(symbol: "square.grid.2x2", message: text.noCards)
        } else {
            let rows = rows
            // Always in a scroll view: squeezed into the island's height, the
            // rows were drawn over one another. It scrolls only when the
            // cards are taller than the room under the switches.
            TimelineView(.periodic(from: .now, by: 15)) { context in
                ScrollView { grid(rows, now: context.date) }
                    .scrollIndicators(.automatic)
                    .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func grid(_ rows: [[NotchAgentTile]], now: Date) -> some View {
        let limitRows = NotchAgentSupport.limitRows(usage.snapshot.limits)
        return VStack(spacing: NotchAgentSupport.spacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(alignment: .top, spacing: NotchAgentSupport.spacing) {
                    ForEach(row) { tile in card(tile, now: now) }
                }
                // A row is as tall as its tallest card, never shorter than
                // the island allowed for, and both cards fill it.
                .frame(minHeight: NotchAgentSupport.height(of: row, limitRows: limitRows))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    @ViewBuilder private func card(_ tile: NotchAgentTile, now: Date) -> some View {
        let snapshot = usage.snapshot
        let shown = chosenPeriod
        let periodUsage = snapshot.usage(shown)
        let scopedFullyPriced = providers.count == 1
            ? (periodUsage.byProvider[providers[0]]?.unpriced ?? 0) == 0
            : periodUsage.fullyPriced
        switch tile.card {
        case .limits:
            if let provider = tile.provider {
                NotchAgentLimitsCard(provider: provider, snapshot: snapshot, now: now,
                                     period: shown,
                                     display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining, text: text)
            }
        case .spend:
            NotchAgentSpendCard(snapshot: snapshot, providers: providers, period: $period, text: text)
        case .live:
            NotchAgentLiveCard(snapshot: snapshot, providers: providers, text: text)
        case .trend:
            NotchAgentTrendCard(snapshot: snapshot, providers: providers, period: shown, text: text)
        case .models:
            let modelShares = providers.count == 1
                ? periodUsage.models.filter { $0.provider == providers[0] }
                : periodUsage.models
            NotchAgentShareCard(title: text.modelsCard, symbol: NotchAgentCard.models.symbol,
                                shares: modelShares, byCost: scopedFullyPriced, text: text)
        case .projects:
            let projectShares = providers.count == 1
                ? (periodUsage.projectsByProvider[providers[0]] ?? [])
                : periodUsage.projects
            NotchAgentShareCard(title: text.projectsCard, symbol: NotchAgentCard.projects.symbol,
                                shares: projectShares, byCost: scopedFullyPriced, text: text)
        case .activity:
            NotchAgentActivityCard(snapshot: snapshot, providers: providers, text: text)
        case .resets:
            NotchAgentResetsCard(now: now, text: text)
        }
    }
}

private struct NotchAgentChip: View {
    let text: String
    var tint: Color = .white
    var truncation: Text.TruncationMode = .tail

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint.opacity(0.9))
            .lineLimit(1)
            .truncationMode(truncation)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.14), in: Capsule(style: .continuous))
    }
}

// MARK: Limits

private struct NotchAgentLimitsCard: View {
    let provider: AgentProvider
    let snapshot: AgentUsageSnapshot
    let now: Date
    var period: AgentPeriod = .today
    let display: NotchAgentLimitDisplay
    let text: NotchAgentStrings
    @Environment(\.locale) private var locale

    /// A reading the Claude app saved a while ago: still the latest known,
    /// shown quieter until the app checks again.
    private var stale: Bool {
        guard let limits = snapshot.limits[provider], limits.source == .claudeApp else { return false }
        return now.timeIntervalSince(limits.observedAt) >= AgentClaudeAppUsage.freshness
    }

    /// The period shown on the OpenCode card: the chosen period when it has
    /// OpenCode activity, falling back to 7d or 30d so historical routing and
    /// mode telemetry stay visible even on days without a new session.
    private var openCodeEffectivePeriod: AgentPeriod {
        for candidate in [period, .week, .month] {
            if let totals = snapshot.usage(candidate).byProvider[.opencode],
               totals.tokens.total > 0 || totals.requests > 0 || totals.cost > 0 {
                return candidate
            }
        }
        return period
    }

    /// Display all active rate windows: all 4 for Antigravity, 3 for Claude, or the binding 2 for others.
    private var windows: [AgentLimitWindow] {
        let all = (snapshot.limits[provider]?.windows ?? []).map { AgentLimitSupport.current($0, at: now) }
        if provider == .antigravity {
            return all.sorted { a, b in
                func rank(_ id: String) -> Int {
                    if id.contains("gemini-5h") { return 0 }
                    if id.contains("gemini-weekly") { return 1 }
                    if id.contains("3p-5h") { return 2 }
                    if id.contains("3p-weekly") { return 3 }
                    return 4
                }
                let ra = rank(a.id), rb = rank(b.id)
                return ra != rb ? ra < rb : a.id < b.id
            }
        } else if provider == .claude {
            return all.sorted { a, b in
                func rank(_ w: AgentLimitWindow) -> Int {
                    if w.kind == .session || w.id.contains("fh") { return 0 }
                    if w.id.contains("fable") { return 2 }
                    if w.kind == .weekly || w.id.contains("sd") { return 1 }
                    return 3
                }
                let ra = rank(a), rb = rank(b)
                return ra != rb ? ra < rb : a.id < b.id
            }
        }
        let session = all.first { $0.kind == .session }
        let longer = all.filter { $0.kind != .session }.max { $0.usedPercent < $1.usedPercent }
        let picked = [session, longer].compactMap { $0 }
        return picked.isEmpty ? all : picked
    }

    var body: some View {
        let windows = windows
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: provider.displayName, symbol: provider.symbol, tint: provider.tint,
                                     provider: provider) {
                    HStack(spacing: 4) {
                        if let identity = snapshot.identities[provider] {
                            // A paired card has no room for the address beside
                            // the plan; it drops out whole and stays in the tooltip.
                            ViewThatFits(in: .horizontal) {
                                identityChips(identity, email: true)
                                identityChips(identity, email: false)
                            }
                            .help([identity.planTier, identity.email].compactMap { $0 }.joined(separator: " · "))
                        } else if let plan = snapshot.plans[provider] {
                            NotchAgentChip(text: plan.name, tint: provider.tint)
                        } else if provider == .opencode {
                            let effective = openCodeEffectivePeriod
                            let usage = snapshot.usage(effective)
                            if usage.openCodeSessions > 0 || usage.openCodeToolCalls > 0 || effective != period {
                                ViewThatFits(in: .horizontal) {
                                    openCodeHeaderChips(usage: usage, effective: effective, includeTools: true, includeSessions: true)
                                    openCodeHeaderChips(usage: usage, effective: effective, includeTools: false, includeSessions: true)
                                    openCodeHeaderChips(usage: usage, effective: effective, includeTools: false, includeSessions: false)
                                }
                            }
                        }
                        if !snapshot.working(provider).isEmpty { NotchAgentPulse(tint: provider.tint, size: 5) }
                    }
                }
                if windows.isEmpty {
                    estimate
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(windows) { row($0) }
                    }
                    .opacity(stale ? 0.6 : 1)
                    if windows.count == 1 { caption }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func identityChips(_ identity: AgentIdentity, email: Bool) -> some View {
        HStack(spacing: 4) {
            if let planTier = identity.planTier { NotchAgentChip(text: planTier, tint: provider.tint) }
            // Without a plan the address is all there is, so it stays and is cut in the middle.
            if let address = identity.email, email || identity.planTier == nil {
                NotchAgentChip(text: address, tint: .secondary, truncation: .middle)
            }
        }
    }

    private func openCodeHeaderChips(usage: AgentPeriodUsage, effective: AgentPeriod,
                                     includeTools: Bool, includeSessions: Bool) -> some View {
        HStack(spacing: 4) {
            if effective != period {
                NotchAgentChip(text: text.period(effective), tint: .secondary)
            }
            if includeSessions, usage.openCodeSessions > 0 {
                NotchAgentChip(text: "\(usage.openCodeSessions) sess", tint: provider.tint)
            }
            if includeTools, usage.openCodeToolCalls > 0 {
                NotchAgentChip(text: "\(AgentFormat.tokens(usage.openCodeToolCalls)) tools", tint: .secondary)
            }
        }
    }

    /// How old a reading is, once it is old enough to have missed use elsewhere.
    @ViewBuilder private var caption: some View {
        if let observed = snapshot.limits[provider]?.observedAt, now.timeIntervalSince(observed) > 600 {
            Text(text.updated(observed.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)
                .locale(locale))))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// A row says what is spent, when the window renews, and under-bar runway forecasting.
    private func row(_ window: AgentLimitWindow) -> some View {
        let all = (snapshot.limits[provider]?.windows ?? []).map { AgentLimitSupport.current($0, at: now) }
        let is3p = window.id.contains("3p") || window.scope == "Claude/GPT"
        let weekly = all.first { w in
            guard w.kind == .weekly && !w.id.contains("fable") else { return false }
            let wIs3p = w.id.contains("3p") || w.scope == "Claude/GPT"
            return wIs3p == is3p
        }
        let session = all.first { w in
            guard w.kind == .session else { return false }
            let sIs3p = w.id.contains("3p") || w.scope == "Claude/GPT"
            return sIs3p == is3p
        }
        let pace = AgentLimitSupport.pace(for: window, now: now, weeklyWindow: weekly, sessionWindow: session)
        let tint = agentLimitTint(provider, usedFraction: window.usedFraction)
        let remaining = display == .remaining
        let fraction = remaining ? window.remainingFraction : window.usedFraction
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(window.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .layoutPriority(1)
                Group {
                    if let resets = window.resetsAt {
                        Label(countdown(to: resets), systemImage: "arrow.clockwise")
                            .labelStyle(NotchAgentInlineLabel())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 9.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                // The figure keeps its width, so every row's ends at the same edge.
                Text(AgentFormat.percent(fraction))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint == provider.tint ? Color.white : tint)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(2)
            }
            NotchAgentMeter(value: fraction, pace: pace.map { remaining ? 1 - $0.elapsed : $0.elapsed },
                            tint: tint, height: 4)
            if let pace, !pace.summary.isEmpty {
                Text(pace.summary)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .help(help(window, forecast: pace?.summary))
    }

    /// What the window covers: its length, or the model it is kept for.
    private func label(_ window: AgentLimitWindow) -> String {
        switch window.kind {
        case .session: return text.session
        case .weekly: return window.scope.map { "\(text.weekly) · \($0)" } ?? text.weekly
        case .other:
            guard let minutes = window.minutes else { return window.scope ?? text.readoutLimit }
            return AgentFormat.duration(TimeInterval(minutes) * 60, locale: locale, units: 1)
        }
    }

    /// How long until the window renews: days and hours, or hours and
    /// minutes, never seconds on a card that redraws every few. The day and
    /// time are in the tooltip.
    private func countdown(to date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        return AgentFormat.duration(max(60, seconds), locale: locale, units: seconds >= 3600 ? 2 : 1)
    }

    /// The forecast is here whole, for a card too narrow to show all of it.
    private func help(_ window: AgentLimitWindow, forecast: String?) -> String {
        var parts = [label(window), text.usedShare(AgentFormat.percent(window.usedFraction)),
                     text.left(AgentFormat.percent(window.remainingFraction))]
        if let forecast, !forecast.isEmpty { parts.append(forecast) }
        if let resets = window.resetsAt {
            parts.append(resets.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))
        }
        if let observed = snapshot.limits[provider]?.observedAt, now.timeIntervalSince(observed) > 600 {
            parts.append(text.updated(observed.formatted(.relative(presentation: .named).locale(locale))))
        }
        return parts.joined(separator: " · ")
    }

    /// Without a recent reading from the Claude app, the session still ends
    /// five hours after its first request, so the window itself is known.
    @ViewBuilder private var estimate: some View {
        if provider == .claude, let block = snapshot.claudeBlock {
            let length = block.end.timeIntervalSince(block.start)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(text.session)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Label(countdown(to: block.end), systemImage: "arrow.clockwise")
                        .labelStyle(NotchAgentInlineLabel())
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text(AgentFormat.cost(block.totals.cost))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                NotchAgentMeter(value: length > 0 ? now.timeIntervalSince(block.start) / length : 0,
                                tint: provider.tint, height: 4, dimmed: true)
            }
            .help(text.estimated)
            setUpLimits
        } else if provider == .claude {
            Text(text.noSession).font(.system(size: 10.5)).foregroundStyle(.secondary)
            setUpLimits
        } else if provider == .opencode {
            openCodeOverview
        } else {
            Text(text.waitingForLimits).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
            lastUsed
        }
    }

    @ViewBuilder private var openCodeOverview: some View {
        let effective = openCodeEffectivePeriod
        let usage = snapshot.usage(effective)
        let ocTotals = usage.byProvider[.opencode]
        if let ocTotals, ocTotals.tokens.total > 0 || ocTotals.requests > 0 || ocTotals.cost > 0 {
            let byCost = ocTotals.unpriced == 0 && ocTotals.cost > 0
            let routes = Array(usage.openCodeRoutes.prefix(2))
            let totalWeight = max(
                usage.openCodeRoutes.reduce(0) { $0 + $1.totals.weight(byCost: byCost) },
                .leastNonzeroMagnitude
            )
            let costPrefix = ocTotals.unpriced > 0 ? "≥ " : ""
            VStack(alignment: .leading, spacing: 5) {
                if !routes.isEmpty {
                    ForEach(routes) { route in
                        let weight = route.totals.weight(byCost: byCost)
                        let share = min(1, max(0, weight / totalWeight))
                        let routeValue = byCost
                            ? AgentFormat.cost(route.totals.cost)
                            : AgentFormat.tokens(route.totals.tokens.total)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(route.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .layoutPriority(1)
                                Text("\(route.totals.requests) req")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Text(routeValue)
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            NotchAgentMeter(value: share, tint: provider.tint, height: 4)
                        }
                        .help([
                            route.name,
                            "\(route.totals.requests) req",
                            text.tokens(AgentFormat.tokens(route.totals.tokens.total)),
                            (route.totals.unpriced > 0 ? "≥ " : "") + AgentFormat.cost(route.totals.cost)
                        ].joined(separator: " · "))
                    }
                }
                if !usage.openCodeModes.isEmpty {
                    let topModes = usage.openCodeModes.prefix(3).map { mode in
                        "\(mode.name) \(mode.totals.requests)"
                    }.joined(separator: " · ")
                    Text(topModes)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                HStack(spacing: 4) {
                    if ocTotals.cost > 0 {
                        Text(costPrefix + AgentFormat.cost(ocTotals.cost))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("·")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                    Text(AgentFormat.tokens(ocTotals.tokens.total))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    if let rate = ocTotals.tokens.cacheHitRate, rate > 0 {
                        Text("· " + text.cached(AgentFormat.percent(rate)))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 2)
                    lastUsed
                }
                .help(ocTotals.unpriced > 0 ? text.unpriced : text.valueNote)
            }
        } else {
            Text(text.noSession).font(.system(size: 10.5)).foregroundStyle(.secondary)
            lastUsed
        }
    }

    /// Claude's plan limits come from the Claude app; the settings say how.
    private var setUpLimits: some View {
        Button {
            NotchService.shared.openSettings(showing: .agents)
        } label: {
            Label(text.claudeLimitsHint, systemImage: "arrow.up.forward")
                .labelStyle(NotchAgentInlineLabel())
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(provider.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var lastUsed: some View {
        if let last = snapshot.lastActivity[provider] {
            Text(last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(locale)))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }
}

/// A glyph and its words, closer together than a stock label.
private struct NotchAgentInlineLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

// MARK: Spending

private struct NotchAgentSpendCard: View {
    let snapshot: AgentUsageSnapshot
    let providers: [AgentProvider]
    @Binding var period: String
    let text: NotchAgentStrings

    private var chosen: AgentPeriod { AgentPeriod(rawValue: period) ?? .today }
    private var scopedTotals: AgentTotals {
        if providers.count == 1, let p = providers.first {
            return snapshot.usage(chosen).byProvider[p] ?? AgentTotals()
        }
        return snapshot.usage(chosen).total
    }
    private var scopedFullyPriced: Bool {
        providers.count == 1 ? scopedTotals.unpriced == 0 : snapshot.usage(chosen).fullyPriced
    }
    private var scopedCredits: Double? {
        providers.count == 1 ? snapshot.credits[providers[0]] : snapshot.credits[.claude]
    }
    private var scopedCostMetrics: AgentCostMetrics? {
        providers.count == 1 ? snapshot.effectiveCostMetrics(for: providers[0]) : snapshot.costMetrics[.claude]
    }

    var body: some View {
        let usage = snapshot.usage(chosen)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 5) {
                NotchAgentCardHeader(title: text.spendCard, symbol: NotchAgentCard.spend.symbol) {
                    HStack(spacing: 5) {
                        if let credits = scopedCredits, credits > 0 {
                            // A paired card shows the amount alone; the menu beside it keeps its width.
                            ViewThatFits(in: .horizontal) {
                                NotchAgentChip(text: "Credits: " + AgentFormat.cost(credits), tint: .green)
                                NotchAgentChip(text: AgentFormat.cost(credits), tint: .green)
                            }
                            .help("Credits: " + AgentFormat.cost(credits))
                        }
                        periodMenu.layoutPriority(1)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text((scopedFullyPriced ? "" : "≥ ") + AgentFormat.cost(scopedTotals.cost))
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(text.apiValue)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if chosen == .month { multiples(usage) }
                }
                .help(scopedFullyPriced ? text.valueNote : text.unpriced)
                if let metrics = scopedCostMetrics {
                    HStack(spacing: 6) {
                        figure("Today", AgentFormat.cost(metrics.todayCost))
                        figure("30d cost", AgentFormat.cost(metrics.thirtyDayCost))
                        figure("Latest tokens", short: "Latest", AgentFormat.tokens(metrics.latestTokens))
                        figure("30d tokens", short: "30d tok.", AgentFormat.tokens(metrics.thirtyDayTokens))
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
                split(usage)
                Text(footer(usage))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .help(text.saved(AgentFormat.cost(scopedTotals.savings)))
            }
        }
    }

    /// One of the four figures under the total. A paired card takes the
    /// short label, so all four read at one size; the tooltip has it whole.
    private func figure(_ label: String, short: String? = nil, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ViewThatFits(in: .horizontal) {
                Text(label)
                Text(short ?? label).minimumScaleFactor(0.85)
            }
            .font(.system(size: 8.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(label + " · " + value)
    }

    private var periodMenu: some View {
        NotchMenuButton(title: text.period(chosen), items: AgentPeriod.allCases.map { option in
            NotchMenuItem(title: text.period(option), checked: option == chosen) { period = option.rawValue }
        }) {
            Text("\(text.period(chosen)) \(Image(systemName: "chevron.down"))")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
    }

    /// Thirty days of API value against a plan's monthly price.
    @ViewBuilder private func multiples(_ usage: AgentPeriodUsage) -> some View {
        HStack(spacing: 3) {
            ForEach(providers) { provider in
                if let plan = snapshot.plans[provider], let price = plan.monthlyPrice, price > 0,
                   let spent = usage.byProvider[provider]?.cost, spent > 0 {
                    let multiple = (spent / price).formatted(.number.precision(.fractionLength(spent / price < 10 ? 1 : 0))) + "×"
                    NotchAgentChip(text: multiple, tint: provider.tint)
                        .help(text.planMultiple(multiple, plan: "\(provider.displayName) \(plan.name)"))
                }
            }
        }
    }

    @ViewBuilder private func split(_ usage: AgentPeriodUsage) -> some View {
        let byCost = scopedFullyPriced
        let parts = providers.map { usage.byProvider[$0]?.weight(byCost: byCost) ?? 0 }
        let total = parts.reduce(0, +)
        let shown = parts.filter { $0 > 0 }.count
        GeometryReader { proxy in
            let gap: CGFloat = 2
            // Every agent keeps a visible sliver; the rest shares what is left.
            let room = max(0, proxy.size.width - gap * CGFloat(max(0, shown - 1)) - 4 * CGFloat(shown))
            HStack(spacing: gap) {
                if total <= 0 {
                    Capsule().fill(.white.opacity(0.13))
                } else {
                    ForEach(providers.indices, id: \.self) { index in
                        if parts[index] > 0 {
                            Capsule(style: .continuous).fill(providers[index].tint.opacity(0.9))
                                .frame(width: 4 + room * parts[index] / total)
                        }
                    }
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private func footer(_ usage: AgentPeriodUsage) -> String {
        var parts = [text.tokens(AgentFormat.tokens(scopedTotals.tokens.total))]
        if let rate = scopedTotals.tokens.cacheHitRate, rate > 0 { parts.append(text.cached(AgentFormat.percent(rate))) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Now

private struct NotchAgentLiveCard: View {
    let snapshot: AgentUsageSnapshot
    let providers: [AgentProvider]
    let text: NotchAgentStrings
    @Environment(\.locale) private var locale

    var body: some View {
        let live = snapshot.live.filter { providers.contains($0.provider) }
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 7) {
                NotchAgentCardHeader(title: text.liveCard, symbol: NotchAgentCard.live.symbol,
                                     tint: live.first?.provider.tint ?? .secondary) {
                    HStack(spacing: 4) {
                        if live.count > 2 { NotchAgentChip(text: "+\(live.count - 2)") }
                        if let first = live.first { NotchAgentPulse(tint: first.provider.tint, size: 5) }
                    }
                }
                if live.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(providers) { idleRow($0) }
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(live.prefix(2)) { row($0, now: context.date) }
                        }
                    }
                }
            }
        }
    }

    private func row(_ session: AgentLiveSession, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                NotchAgentGlyph(provider: session.provider, size: 9)
                Text(session.project.isEmpty ? session.provider.displayName : session.project)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(AgentFormat.clock(now.timeIntervalSince(session.started)))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(session.provider.tint)
            }
            // Tokens the agent wrote, as its own window counts them; every
            // call also reads the whole context again, which the tooltip and
            // the cost include.
            Text([AgentPricing.displayName(session.model),
                  session.tokens.output > 0 ? text.written(AgentFormat.tokens(session.tokens.output)) : "",
                  session.cost > 0 ? AgentFormat.cost(session.cost) : ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(text.tokens(AgentFormat.tokens(session.tokens.total)) + " · "
              + text.cached(AgentFormat.percent(session.tokens.cacheHitRate ?? 0)))
    }

    private func idleRow(_ provider: AgentProvider) -> some View {
        HStack(spacing: 5) {
            NotchAgentGlyph(provider: provider, size: 9, working: false)
            Text(provider.displayName).font(.system(size: 10.5, weight: .medium))
            Spacer(minLength: 4)
            Text(snapshot.lastActivity[provider].map {
                $0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(locale))
            } ?? text.idle)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: Trend

private struct NotchAgentTrendCard: View {
    let snapshot: AgentUsageSnapshot
    let providers: [AgentProvider]
    let period: AgentPeriod
    let text: NotchAgentStrings
    @State private var hovered: Date?
    @Environment(\.locale) private var locale

    private var scopedPeriodTotals: AgentTotals {
        if providers.count == 1, let p = providers.first {
            return snapshot.usage(period).byProvider[p] ?? AgentTotals()
        }
        return snapshot.usage(period).total
    }

    private var scopedCostMetrics: AgentCostMetrics? {
        providers.count == 1 ? snapshot.effectiveCostMetrics(for: providers[0]) : snapshot.costMetrics[.claude]
    }

    private var buckets: [AgentBucket] {
        if period == .today {
            return snapshot.hours
        }
        let explicitDaily = providers.count == 1 ? snapshot.dailySpend[providers[0]] : snapshot.dailySpend[.claude]
        if period == .month, let daily = explicitDaily, !daily.isEmpty {
            let now = snapshot.now
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current
            return daily.suffix(30).compactMap { item in
                let date = dateFormatter.date(from: item.date) ?? now
                let totals = AgentTotals(tokens: AgentTokens(input: item.tokens), cost: item.cost)
                let p = providers.first ?? .claude
                return AgentBucket(start: date, byProvider: [p: totals])
            }
        }
        return Array(snapshot.days.suffix(period.days))
    }

    var body: some View {
        let byCost = providers.count == 1 ? scopedPeriodTotals.unpriced == 0 : snapshot.usage(period).fullyPriced
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.trendCard, symbol: NotchAgentCard.trend.symbol) {
                    HStack(spacing: 4) {
                        if let metrics = scopedCostMetrics {
                            if let peak = metrics.peakDayCost, peak > 0 {
                                Text("Peak: " + AgentFormat.cost(peak))
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            if let top = metrics.topModel {
                                Text("· Top: " + top)
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(caption(byCost: byCost))
                            .font(.system(size: 9.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                NotchAgentBars(buckets: buckets, providers: providers, byCost: byCost, hovered: $hovered)
                axis
            }
        }
    }

    private func scopedBucketTotals(_ bucket: AgentBucket) -> AgentTotals {
        if providers.count == 1, let p = providers.first {
            return bucket.byProvider[p] ?? AgentTotals()
        }
        return bucket.total
    }

    private func caption(byCost: Bool) -> String {
        if let hovered, let bucket = buckets.first(where: { $0.start == hovered }) {
            let bucketTotals = scopedBucketTotals(bucket)
            // A pointed-at bar reads its tokens beside its cost.
            let tokens = byCost ? " · " + value(bucketTotals, byCost: false) : ""
            return label(bucket.start, long: true) + " · " + value(bucketTotals, byCost: byCost) + tokens
        }
        return text.period(period) + " · " + value(scopedPeriodTotals, byCost: byCost)
    }

    private func value(_ totals: AgentTotals, byCost: Bool) -> String {
        byCost ? AgentFormat.cost(totals.cost) : text.tokens(AgentFormat.tokens(totals.tokens.total))
    }

    private func label(_ date: Date, long: Bool) -> String {
        if period == .today { return date.formatted(.dateTime.hour().locale(locale)) }
        if period == .week, !long { return date.formatted(.dateTime.weekday(.narrow).locale(locale)) }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// Every bar a letter over a week; the ends and the middle otherwise.
    private var axis: some View {
        let marks: [Int] = period == .week ? Array(buckets.indices)
            : buckets.isEmpty ? [] : [0, buckets.count / 2, buckets.count - 1]
        return HStack(spacing: 0) {
            if period == .week {
                ForEach(marks, id: \.self) { index in
                    Text(label(buckets[index].start, long: false)).frame(maxWidth: .infinity)
                }
            } else {
                ForEach(Array(marks.enumerated()), id: \.offset) { position, index in
                    if position > 0 { Spacer(minLength: 4) }
                    Text(label(buckets[index].start, long: false))
                }
            }
        }
        .font(.system(size: 8.5, weight: .medium))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .frame(height: 10)
    }
}

// MARK: Models and projects

private struct NotchAgentShareCard: View {
    let title: String
    let symbol: String
    let shares: [AgentShare]
    let byCost: Bool
    let text: NotchAgentStrings

    var body: some View {
        let shown = Array(shares.prefix(3))
        let peak = max(shown.map { $0.totals.weight(byCost: byCost) }.max() ?? 0, .leastNonzeroMagnitude)
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: title, symbol: symbol)
                if shown.isEmpty {
                    Text(text.noActivity).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 5) {
                        ForEach(shown) { share in row(share, peak: peak) }
                    }
                }
            }
        }
    }

    private func row(_ share: AgentShare, peak: Double) -> some View {
        let weight = share.totals.weight(byCost: byCost)
        let tint = share.provider?.tint ?? .white
        return HStack(spacing: 6) {
            Text(share.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule(style: .continuous)
                .fill(tint.opacity(0.85))
                .frame(width: max(3, 44 * weight / peak), height: 4)
                .frame(width: 44, alignment: .leading)
            Text(byCost ? AgentFormat.cost(share.totals.cost) : AgentFormat.tokens(share.totals.tokens.total))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .frame(height: 14)
        .help([share.name, text.tokens(AgentFormat.tokens(share.totals.tokens.total)),
               AgentFormat.cost(share.totals.cost)].joined(separator: " · "))
    }
}

// MARK: Activity

private struct NotchAgentActivityCard: View {
    let snapshot: AgentUsageSnapshot
    var providers: [AgentProvider] = AgentProvider.allCases
    let text: NotchAgentStrings
    @State private var hovered: Date?
    @Environment(\.locale) private var locale

    private var scopedDays: [AgentBucket] {
        guard providers.count == 1, let p = providers.first else { return snapshot.days }
        return snapshot.days.map { day in
            AgentBucket(start: day.start, byProvider: day.byProvider[p].map { [p: $0] } ?? [:])
        }
    }

    /// Days in a row with any use, counting today only once it has some.
    private var streak: Int {
        let days = scopedDays
        var count = 0
        for day in days.reversed() {
            if day.total.requests > 0 { count += 1 }
            else if count > 0 || day.id != days.last?.id { break }
        }
        return count
    }

    var body: some View {
        let days = scopedDays
        let byCost = days.allSatisfy { $0.total.unpriced == 0 }
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.activityCard, symbol: NotchAgentCard.activity.symbol) {
                    if streak > 1 {
                        Label("\(streak)", systemImage: "flame.fill")
                            .labelStyle(NotchAgentInlineLabel())
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.orange)
                            .help(text.streak)
                            .accessibilityLabel(text.streak)
                            .accessibilityValue("\(streak)")
                    }
                }
                GeometryReader { proxy in
                    let map = NotchAgentHeatmap.width(height: proxy.size.height, days: days)
                    HStack(alignment: .top, spacing: 14) {
                        NotchAgentHeatmap(days: days, byCost: byCost, hovered: $hovered)
                            .frame(width: map, height: proxy.size.height)
                        figures(days: days, byCost: byCost)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
    }

    /// The total for the whole map, its active days and its busiest day; a
    /// hovered day takes the place of the busiest one.
    private func figures(days: [AgentBucket], byCost: Bool) -> some View {
        let active = days.filter { $0.total.requests > 0 }
        let busiest = active.max { $0.total.weight(byCost: byCost) < $1.total.weight(byCost: byCost) }
        let pointed = hovered.flatMap { date in days.first { $0.start == date } }
        return VStack(alignment: .leading, spacing: 2) {
            Text(value(days.reduce(into: AgentTotals()) { $0 += $1.total }, byCost: byCost))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(AgentFormat.span(days: days.count, locale: locale))
                .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            figure(text.activeDays, "\(active.count)")
            if let day = pointed ?? busiest {
                figure(pointed == nil ? text.busiestDay : day.start.formatted(.dateTime.weekday(.wide).locale(locale)),
                       day.start.formatted(.dateTime.day().month(.abbreviated).locale(locale)) + " · " + value(day.total, byCost: byCost))
            }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(value).monospacedDigit().lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .minimumScaleFactor(0.85)
    }

    private func value(_ totals: AgentTotals, byCost: Bool) -> String {
        byCost ? AgentFormat.cost(totals.cost) : AgentFormat.tokens(totals.tokens.total)
    }
}

// MARK: Resets

/// Codex's banked resets: how many the account holds, when the next one
/// expires, and a use that asks first. Cancel takes the place of the button
/// that asked, so a double click never spends one.
private struct NotchAgentResetsCard: View {
    let now: Date
    let text: NotchAgentStrings
    @ObservedObject private var resets = AgentCodexResetService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var confirming = false
    @Environment(\.locale) private var locale

    private let tint = AgentProvider.codex.tint

    /// What a use did stays on the card for a minute.
    private var finished: AgentCodexResetService.Finished? {
        resets.finished.flatMap { now.timeIntervalSince($0.date) < 60 ? $0 : nil }
    }

    var body: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: text.resetsCard, symbol: NotchAgentCard.resets.symbol, tint: tint,
                                     provider: .codex) {
                    if let summary = resets.summary, summary.available > 0 {
                        NotchAgentChip(text: summary.available.formatted(.number.locale(locale)), tint: tint)
                    } else if resets.checking {
                        ProgressView().controlSize(.mini)
                    }
                }
                content
            }
        }
        .help(text.resetsHelp)
        .onAppear { resets.refreshIfStale() }
        // A count that changed while the question was open asks again.
        .onChange(of: resets.summary?.available) { _, _ in confirming = false }
    }

    @ViewBuilder private var content: some View {
        if resets.redeeming {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                line(text.resetting)
            }
        } else if confirming, let summary = resets.summary, summary.available > 0 {
            action(text.resetConfirm, emphasized: true) {
                pill(FeatureStrings.clipboard(l10n.language).cancel, prominent: false) { confirming = false }
                pill(text.confirmReset) {
                    confirming = false
                    resets.redeem()
                }
            }
        } else if let finished {
            if finished.outcome == nil, let summary = resets.summary, summary.available > 0 {
                // Trying again repeats the same use, which never spends a second reset.
                VStack(alignment: .leading, spacing: 0) {
                    outcome(nil)
                    Spacer(minLength: 4)
                    useButton
                }
            } else {
                outcome(finished.outcome)
            }
        } else if resets.summary == nil, let failure = resets.failure {
            action(message(failure)) {
                pill(FeatureStrings.notchMusicExtras(l10n.language).retry, prominent: false) {
                    resets.refresh(searchingShell: failure == .missing)
                }
            }
        } else if let summary = resets.summary {
            if summary.available > 0 {
                // A reset a day from expiring is worth using soon.
                let soon = summary.nextExpiry.map { $0.timeIntervalSince(now) < 86_400 } ?? false
                action(summary.nextExpiry.map(expiry) ?? "", tint: soon ? .orange : nil) { useButton }
            } else {
                line(text.resetsNone)
            }
        }
    }

    private var useButton: some View {
        pill(text.useReset, symbol: "arrow.counterclockwise") { confirming = true }
    }

    /// A line above the card's buttons, which keep to its bottom edge.
    private func action<Buttons: View>(_ message: String, emphasized: Bool = false, tint: Color? = nil,
                                       @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 10.5, weight: emphasized ? .medium : .regular))
                    .foregroundStyle(tint.map { AnyShapeStyle($0) }
                                     ?? (emphasized ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary)))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) { buttons() }
        }
    }

    private func expiry(_ date: Date) -> String {
        text.resetsExpiry(date.formatted(.relative(presentation: .named).locale(locale)))
    }

    @ViewBuilder private func outcome(_ outcome: AgentCodexServer.Outcome?) -> some View {
        switch outcome {
        case .reset?:
            line(text.resetDone, symbol: "checkmark.circle.fill", tint: .green)
        case .nothingToReset?:
            line(text.resetNotNeeded, symbol: "info.circle.fill", tint: .secondary)
        case .alreadyRedeemed?:
            line(text.resetTaken, symbol: "info.circle.fill", tint: .secondary)
        case .noCredit?:
            line(text.resetsNone)
        case nil:
            line(text.resetFailed, symbol: "exclamationmark.circle.fill", tint: .orange)
        }
    }

    private func message(_ failure: AgentCodexServer.Failure) -> String {
        switch failure {
        case .missing: return text.resetsNeedCodex
        case .needsSignIn: return text.resetsSignIn
        case .outdated: return text.resetsUpdate
        case .unreachable, .refused: return text.resetsCheckFailed
        }
    }

    private func line(_ message: String, symbol: String? = nil, tint: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let symbol { Image(systemName: symbol).foregroundStyle(tint) }
            Text(message).foregroundStyle(symbol == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white.opacity(0.9)))
        }
        .font(.system(size: 10.5, weight: .medium))
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ title: String, symbol: String? = nil, prominent: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                // A narrow island shrinks a long label before cutting it.
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(.white.opacity(0.85)))
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(prominent ? tint.opacity(0.2) : .white.opacity(0.1), in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 10))
    }
}
