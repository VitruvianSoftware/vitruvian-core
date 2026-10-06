// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The cards the AI page can show, in the order a person arranges them. Raw
/// values are stored in the saved order, so cases are never renamed.
package enum NotchAgentCard: String, CaseIterable, Identifiable {
    case limits, spend, live, trend, models, projects, activity, resets

    package var id: String { rawValue }

    package var symbol: String {
        switch self {
        case .limits: return "gauge.with.dots.needle.33percent"
        case .spend: return "dollarsign.circle"
        case .live: return "waveform.path.ecg"
        case .trend: return "chart.bar.xaxis"
        case .models: return "cpu"
        case .projects: return "folder"
        case .activity: return "square.grid.3x3.fill"
        case .resets: return "arrow.counterclockwise.circle"
        }
    }

    /// Charts need the island's width; everything else pairs up.
    package var fullWidth: Bool { self == .trend || self == .activity }
}

/// What the closed island shows beside the camera while an agent works.
package enum NotchAgentReadout: String, CaseIterable, Identifiable {
    case elapsed, tokens, cost, limit
    package var id: String { rawValue }

    /// Tokens and cost change only with a new snapshot. Limits still need
    /// the clock: an allowance can renew, or show elapsed time while unknown.
    package var advancesWithClock: Bool { self == .elapsed || self == .limit }
}

package enum NotchAgentLimitDisplay: String, CaseIterable, Identifiable {
    case remaining, used
    package var id: String { rawValue }
}

/// Which allowance the closed island shows.
package enum NotchAgentLimitFocus: String, CaseIterable, Identifiable {
    case mostUsed, session, weekly
    package var id: String { rawValue }
}

package struct NotchAgentTile: Identifiable, Equatable {
    package let card: NotchAgentCard
    /// The account a limits card belongs to.
    package let provider: AgentProvider?
    package var id: String { card.rawValue + (provider.map { "." + $0.rawValue } ?? "") }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(card: NotchAgentCard, provider: AgentProvider?) {
        self.card = card
        self.provider = provider
    }
}

package enum NotchAgentSupport {
    package static let defaultFinishMinimum: TimeInterval = 60
    package static let finishMinimums: [TimeInterval] = [0, 30, 60, 120, 300]
    package static let defaultLimitThreshold = 80.0
    package static let limitThresholds = [50.0, 75.0, 80.0, 90.0, 95.0]
    package static let budgets = [0.0, 5, 10, 25, 50, 100, 250]
    /// A turn silent for this long is not shown as working.
    package static let idleTurn: TimeInterval = 10 * 60

    package static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchAgents.isAvailable(in: defaults)
            && defaults[Preferences.notchAgentsEnabled]
            && NotchSupport.modules(in: defaults).contains(.agents)
    }

    package static func providers(in defaults: UserDefaults = .standard) -> [AgentProvider] {
        AgentProvider.allCases.filter {
            defaults.object(forKey: key(for: $0)) as? Bool ?? true
        }
    }

    package static func key(for provider: AgentProvider) -> String {
        switch provider {
        case .claude: return DefaultsKey.notchAgentsClaude
        case .codex: return DefaultsKey.notchAgentsCodex
        case .opencode: return DefaultsKey.notchAgentsOpenCode
        }
    }

    /// Every card in the saved order; cards added later join at the end.
    package static func orderedCards(in defaults: UserDefaults = .standard) -> [NotchAgentCard] {
        let stored = (defaults.string(forKey: DefaultsKey.notchAgentsCardOrder) ?? "")
            .split(separator: ",").compactMap { NotchAgentCard(rawValue: String($0)) }
        var seen = Set<NotchAgentCard>()
        return (stored + NotchAgentCard.allCases).filter { seen.insert($0).inserted }
    }

    package static func hiddenCards(in defaults: UserDefaults = .standard) -> Set<NotchAgentCard> {
        Set((defaults.string(forKey: DefaultsKey.notchAgentsHiddenCards) ?? "")
            .split(separator: ",").compactMap { NotchAgentCard(rawValue: String($0)) })
    }

    package static func cards(in defaults: UserDefaults = .standard) -> [NotchAgentCard] {
        let hidden = hiddenCards(in: defaults)
        return orderedCards(in: defaults).filter { !hidden.contains($0) }
    }

    package static func period(in defaults: UserDefaults = .standard) -> AgentPeriod {
        AgentPeriod(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsPeriod) ?? "") ?? .today
    }

    package static func limitDisplay(in defaults: UserDefaults = .standard) -> NotchAgentLimitDisplay {
        NotchAgentLimitDisplay(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsLimitDisplay) ?? "") ?? .remaining
    }

    package static func limitFocus(in defaults: UserDefaults = .standard) -> NotchAgentLimitFocus {
        NotchAgentLimitFocus(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsLimitFocus) ?? "") ?? .mostUsed
    }

    /// The allowance the closed island shows: the window the person chose,
    /// or the one closest to running out while the account reports no such
    /// window. A model's own allowance is never the chosen one.
    package static func focusedLimit(_ limits: AgentLimits?, focus: NotchAgentLimitFocus, now: Date) -> AgentLimitWindow? {
        chosenLimit(limits, focus: focus, now: now) ?? AgentLimitSupport.binding(limits, now: now)
    }

    /// The plan-wide window of the chosen kind; nil for the most used one or
    /// while the account reports no such window.
    private static func chosenLimit(_ limits: AgentLimits?, focus: NotchAgentLimitFocus, now: Date) -> AgentLimitWindow? {
        let kind: AgentLimitWindow.Kind
        switch focus {
        case .mostUsed: return nil
        case .session: kind = .session
        case .weekly: kind = .weekly
        }
        return limits?.windows.first { $0.kind == kind && $0.scope == nil }.map { AgentLimitSupport.current($0, at: now) }
    }

    /// The resting island's allowance across every account: the most spent
    /// of the chosen windows, or of each account's most used window while no
    /// account reports the chosen one.
    package static func restingLimit(_ snapshot: AgentUsageSnapshot, focus: NotchAgentLimitFocus,
                             now: Date) -> (provider: AgentProvider, window: AgentLimitWindow)? {
        func mostSpent(_ pick: (AgentLimits) -> AgentLimitWindow?) -> (provider: AgentProvider, window: AgentLimitWindow)? {
            snapshot.limits.compactMap { provider, limits in pick(limits).map { (provider: provider, window: $0) } }.max {
                $0.window.usedPercent != $1.window.usedPercent ? $0.window.usedPercent < $1.window.usedPercent
                    : $0.provider.rawValue > $1.provider.rawValue
            }
        }
        return mostSpent { chosenLimit($0, focus: focus, now: now) }
            ?? mostSpent { AgentLimitSupport.binding($0, now: now) }
    }

    package static func showsLiveActivity(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && (defaults.object(forKey: DefaultsKey.notchAgentsLiveActivity) as? Bool ?? true)
    }

    package static func readout(in defaults: UserDefaults = .standard) -> NotchAgentReadout {
        NotchAgentReadout(rawValue: defaults.string(forKey: DefaultsKey.notchAgentsReadout) ?? "") ?? .elapsed
    }

    /// The shortest turn worth a notice when it ends; nil while those are off.
    package static func finishMinimum(in defaults: UserDefaults = .standard) -> TimeInterval? {
        guard defaults.object(forKey: DefaultsKey.notchAgentsFinishAlert) as? Bool ?? true else { return nil }
        let value = defaults.object(forKey: DefaultsKey.notchAgentsFinishMinimum) as? Double ?? defaultFinishMinimum
        return value.isFinite ? min(3600, max(0, value)) : defaultFinishMinimum
    }

    /// Percent used that earns a warning; nil while warnings are off.
    package static func limitThreshold(in defaults: UserDefaults = .standard) -> Double? {
        guard defaults.object(forKey: DefaultsKey.notchAgentsLimitAlert) as? Bool ?? true else { return nil }
        let value = defaults.object(forKey: DefaultsKey.notchAgentsLimitThreshold) as? Double ?? defaultLimitThreshold
        return value.isFinite ? min(100, max(1, value)) : defaultLimitThreshold
    }

    package static func dailyBudget(in defaults: UserDefaults = .standard) -> Double? {
        let value = defaults.double(forKey: DefaultsKey.notchAgentsDailyBudget)
        return value.isFinite && value > 0 ? value : nil
    }

    /// Whether the public price list may be downloaded once a day.
    package static func updatesPrices(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchAgentsPriceUpdates) as? Bool ?? true
    }

    // MARK: Strip

    /// A wing is never narrower than the music strip's, nor wide enough to
    /// crowd the menus beside the camera.
    package static let stripWingRange: ClosedRange<CGFloat> = 44...80
    /// Air between the camera and what sits beside it.
    package static let stripCameraGap: CGFloat = 6

    package static func stripTextSize(height: CGFloat) -> CGFloat { min(15, height - 7) }
    /// A working agent's mark on a strip: two working agents share a smaller
    /// mark, and a short strip shrinks it to fit between its edge gaps.
    package static func stripMarkSize(height: CGFloat, working: Int) -> CGFloat {
        min(working > 1 ? 11 : 14, max(8, height - NotchLayout.compactEdgeGap * 2 - 4))
    }
    /// The square a mark is drawn in; the widest mark, Claude's, reaches past its size.
    package static func markFrame(size: CGFloat) -> CGFloat { size * 1.45 + 1 }
    /// Marks side by side, one point apart, keeping room for one when none works.
    package static func marksWidth(size: CGFloat, count: Int) -> CGFloat {
        let count = max(1, count)
        return CGFloat(count) * markFrame(size: size) + CGFloat(count - 1)
    }
    /// The working agents' marks at a strip's end, with their clearance from
    /// the silhouette's curve, as the agent and timer strips draw them.
    package static func stripMarksWidth(working: Int, in geometry: NotchGeometry) -> CGFloat {
        let size = stripMarkSize(height: geometry.compactActivityContentHeight, working: working)
        return marksWidth(size: size, count: working)
            + geometry.compactMarkInset(side: size + 4)
    }

    /// What the strip shows beside the camera while agents work: the reading
    /// the person chose, or the time elapsed while that one is unknown.
    package static func stripReading(_ snapshot: AgentUsageSnapshot, readout: NotchAgentReadout,
                             display: NotchAgentLimitDisplay, focus: NotchAgentLimitFocus = .mostUsed,
                             now: Date) -> String {
        let live = snapshot.live
        func elapsed() -> String { AgentFormat.clock(now.timeIntervalSince(live.map(\.started).min() ?? now)) }
        switch readout {
        case .elapsed:
            return elapsed()
        case .tokens:
            // What the agent wrote, the count its own window shows; the
            // context it reads again on every call is in the cost.
            return AgentFormat.tokens(live.reduce(0) { $0 + $1.tokens.output })
        case .cost:
            return AgentFormat.cost(live.reduce(0) { $0 + $1.cost })
        case .limit:
            guard let provider = AgentProvider.allCases.first(where: { provider in live.contains { $0.provider == provider } }),
                  let window = focusedLimit(snapshot.limits[provider], focus: focus, now: now) else { return elapsed() }
            return AgentFormat.percent(display == .used ? window.usedFraction : window.remainingFraction)
        }
    }

    /// Every digit takes the same width, so a reading's shape, not its value,
    /// sets the strip's width: "12:34" and "59:59" match, "1:00:00" is wider.
    package static func readingShape(_ reading: String) -> String {
        String(reading.map { $0.isNumber ? "0" : $0 })
    }

    // MARK: Layout

    package static let spacing: CGFloat = 10
    package static let cardHeight: CGFloat = 96
    package static let chartHeight: CGFloat = 118
    /// Below this width every card takes a row of its own.
    package static let pairWidth: CGFloat = 390

    package static func tiles(cards: [NotchAgentCard], providers: [AgentProvider]) -> [NotchAgentTile] {
        cards.flatMap { card -> [NotchAgentTile] in
            switch card {
            case .limits: return providers.map { NotchAgentTile(card: .limits, provider: $0) }
            // Banked resets belong to a Codex account.
            case .resets: return providers.contains(.codex) ? [NotchAgentTile(card: .resets, provider: .codex)] : []
            default: return [NotchAgentTile(card: card, provider: nil)]
            }
        }
    }

    /// The agents the AI page shows: only those that left something on this
    /// Mac get cards. The island's size and the page both ask here.
    package static func pageProviders(seen: Set<AgentProvider>, in defaults: UserDefaults = .standard) -> [AgentProvider] {
        providers(in: defaults).filter(seen.contains)
    }

    /// The AI page's rows for `providers` across `width`.
    package static func pageRows(providers: [AgentProvider], width: CGFloat,
                                 in defaults: UserDefaults = .standard) -> [[NotchAgentTile]] {
        rows(tiles(cards: cards(in: defaults), providers: providers), width: width)
    }

    /// Cards pair up in reading order; a chart, or a card left without a
    /// partner, takes the whole row.
    package static func rows(_ tiles: [NotchAgentTile], width: CGFloat) -> [[NotchAgentTile]] {
        let pairs = width >= pairWidth
        var rows: [[NotchAgentTile]] = []
        var waiting: NotchAgentTile?
        for tile in tiles {
            if tile.card.fullWidth || !pairs {
                if let waiting { rows.append([waiting]) }
                waiting = nil
                rows.append([tile])
            } else if let partner = waiting {
                rows.append([partner, tile])
                waiting = nil
            } else {
                waiting = tile
            }
        }
        if let waiting { rows.append([waiting]) }
        return rows
    }

    package static func height(of row: [NotchAgentTile]) -> CGFloat {
        row.contains { $0.card.fullWidth } ? chartHeight : cardHeight
    }

    package static func contentHeight(_ rows: [[NotchAgentTile]]) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        return rows.map(height).reduce(0, +) + spacing * CGFloat(rows.count - 1)
    }
}

/// Numbers in the reader's region; costs in US dollars, the currency both
/// providers list their prices in.
package enum AgentFormat {
    package static func cost(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "$0" }
        let magnitude = abs(value)
        if magnitude >= 10_000 { return "$" + scaled(magnitude / 1000, locale: locale) + "K" }
        let digits = magnitude >= 100 ? 0 : 2
        return "$" + value.formatted(.number.precision(.fractionLength(digits)).grouping(.automatic).locale(locale))
    }

    package static func tokens(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let magnitude = Double(max(0, value))
        switch magnitude {
        case ..<1000: return Int(magnitude).formatted(.number.locale(locale))
        case ..<1_000_000: return scaled(magnitude / 1000, locale: locale) + "K"
        case ..<1_000_000_000: return scaled(magnitude / 1_000_000, locale: locale) + "M"
        default: return scaled(magnitude / 1_000_000_000, locale: locale) + "B"
        }
    }

    /// One decimal below ten, none above: "4.2", "48", "120".
    private static func scaled(_ value: Double, locale: Locale) -> String {
        let digits = value < 10 ? 1 : 0
        let rounded = (value * (digits == 1 ? 10 : 1)).rounded(.down) / (digits == 1 ? 10 : 1)
        return rounded.formatted(.number.precision(.fractionLength(0...digits)).locale(locale))
    }

    package static func percent(_ fraction: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// "4m 12s", "1h 05m", "2d 3h", in the app's language.
    package static func duration(_ seconds: TimeInterval, locale: Locale, units: Int = 2,
                         style: DateComponentsFormatter.UnitsStyle = .abbreviated) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = style
        formatter.maximumUnitCount = units
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: max(0, seconds.isFinite ? seconds : 0)) ?? ""
    }

    /// "13 weeks" or "30 days", spelled out in the app's language.
    package static func span(days: Int, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        let weeks = days % 7 == 0
        formatter.allowedUnits = weeks ? [.weekOfMonth] : [.day]
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        // Components, not an interval: an interval is measured from today and
        // can lose a week across a month.
        let count = max(0, days)
        return formatter.string(from: weeks ? DateComponents(weekOfMonth: count / 7) : DateComponents(day: count)) ?? ""
    }

    /// A running stopwatch: "0:42", "12:05", "1:02:05".
    package static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// A calendar day kept in UTC, like the price list's, read as that same
    /// day wherever the Mac is.
    package static func day(_ date: Date, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        style.timeZone = .gmt
        return date.formatted(style)
    }
}
