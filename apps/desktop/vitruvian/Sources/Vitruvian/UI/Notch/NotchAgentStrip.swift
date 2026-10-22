// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The closed island while an agent works: its mark on one side of the
/// camera, one reading the person chose on the other. The wings are as wide
/// as the reading, and both sit at the ends, where the island shows.
package struct NotchAgentStrip: View {
    @ObservedObject package var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    package var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(Preferences.notchAgentsReadout) private var readout: String
    @AppStorage(Preferences.notchAgentsLimitDisplay) private var display: String
    @AppStorage(Preferences.notchAgentsLimitFocus) private var focus: String

    private func working(_ live: [AgentLiveSession]) -> [AgentProvider] {
        AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
    }

    package var body: some View {
        // The last agent stopping empties the list before the strip has left.
        NotchStripHold(usage.snapshot.live, shows: !usage.snapshot.live.isEmpty) { strip(live: $0) }
    }

    @ViewBuilder private func strip(live: [AgentLiveSession]) -> some View {
        // Resolve layout once per presentation update. The timeline captures
        // these values, so ticking the clock never remeasures the island or
        // walks the preferences for every font, inset and frame.
        let geometry = displayGeometry ?? service.compactActivityGeometry
        let working = working(live)
        let tint = working.first?.tint ?? .white
        let iconSize = NotchAgentSupport.stripMarkSize(height: geometry.compactActivityContentHeight,
                                                       working: working.count)
        let textSize = NotchAgentSupport.stripTextSize(height: geometry.compactActivityContentHeight)
        let iconInset = !geometry.compactActivityUsesFooter
            ? geometry.compactMarkInset(side: iconSize + 4) : 0
        let textInset = !geometry.compactActivityUsesFooter
            ? geometry.compactReadingInset(textSize: textSize) : 0
        HStack(spacing: 0) {
            Button { service.openActivity(.agents) } label: {
                HStack(spacing: 1) {
                    if geometry.compactActivityWingWidth >= NotchLayout.compactMarkWing {
                        ForEach(working) { NotchAgentGlyph(provider: $0, size: iconSize) }
                    }
                }
                .padding(.leading, iconInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            Button { service.openActivity(.agents) } label: {
                Group {
                    if geometry.compactActivityWingWidth >= NotchLayout.compactReadingWing {
                        NotchAgentReadoutTimeline(readout: NotchAgentReadout(rawValue: readout) ?? .elapsed) { date in
                            let text = reading(at: date, live: live)
                            Text(text)
                                .font(.system(size: textSize, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(tint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                // A reading that gains a digit, like an hour
                                // passing, needs wider wings; the service
                                // measures the same reading.
                                .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                                    DispatchQueue.main.async { service.refreshPresentation() }
                                }
                        }
                    }
                }
                .padding(.trailing, textInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .trailing)
                .contentShape(Rectangle())
            }
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(working.map(\.displayName).joined(separator: ", "))
        .accessibilityValue(reading(at: Date(), live: live))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { service.openActivity(.agents) }
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private func reading(at now: Date, live: [AgentLiveSession]) -> String {
        var snapshot = usage.snapshot
        snapshot.live = live
        return NotchAgentSupport.stripReading(snapshot, readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                              display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining,
                                              focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: now)
    }
}

/// Keep the original one-second cadence for time-dependent readings, but
/// install no clock at all for values updated by the observed usage snapshot.
package struct NotchAgentReadoutTimeline<Content: View>: View {
    package let readout: NotchAgentReadout
    @ViewBuilder package var content: (Date) -> Content

    package var body: some View {
        if readout.advancesWithClock {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(context.date)
            }
        } else {
            content(.now)
        }
    }
}

/// The Nexus session's sparkles on the closed island: they swing between 85 %
/// and 115 % of their size each second, eased over 0.8 seconds. Under Reduce
/// Motion they keep still at their own size, as the tools' breathing marks do.
package enum NexusSparkleMotion {
    package static func scale(elapsedSeconds: Int, reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        return elapsedSeconds % 2 == 0 ? 1.15 : 0.85
    }

    package static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    }
}

/// The resting island's wings: the chosen allowance, by default the one
/// closest to running out, as a ring and a number, or today's API value when
/// no allowance is known.
package struct NotchAgentRestingWing: View {
    package let leading: Bool
    @ObservedObject private var usage = AgentUsageService.shared
    /// The tools' statuses, and the list of tools: a status set, a tool
    /// switched off, or its status switched off, draws the wing again.
    @ObservedObject private var panels = ToolPanelHost.shared
    @ObservedObject private var registry = ToolRegistry.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(Preferences.notchAgentsLimitDisplay) private var display: String
    @AppStorage(Preferences.notchAgentsLimitFocus) private var focus: String

    /// The one status mark the wing shows: the worst of every tool's
    /// status.
    private var statusMark: RestingMark? {
        RestingStatus.winner(tools: RestingStatus.shown(of: ExternalToolStore.shared.statusTools(),
                                                        statuses: panels.statuses))
    }

    /// What the right-hand wing draws: the shown mark's words, the seconds
    /// since its start time, or the allowance percent.
    private var restingWing: RestingStatus.RightWing? {
        RestingStatus.rightWing(tools: RestingStatus.shown(of: ExternalToolStore.shared.statusTools(),
                                                           statuses: panels.statuses),
                                nexusRunning: false, language: l10n.language)
    }

    package var body: some View {
        TimelineView(.periodic(from: .now, by: RestingStatus.ticksEverySecond(restingWing) ? 1 : 6)) { context in
            content(now: context.date)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // A tool's mark that is not green opens that tool's island
            // page, one of the island's sections, when the island lists it.
            // Anything else is as before.
            if let page = RestingStatus.opens(statusMark, pages: ExternalToolStore.shared.islandPanels(),
                                              nexusRunning: false) {
                NotchService.shared.openExtensionSection(page)
            } else {
                // The chat tab is a slot tool's; with no tool in the Agents
                // slot, the page has only its telemetry.
                NotchService.shared.agentTab = NotchService.hasAgentsSlotTool() ? .chat : .telemetry
                NotchService.shared.select(.agents)
            }
        }
    }

    private func activeRestingProviders(snapshot: AgentUsageSnapshot) -> [AgentProvider] {
        let candidates: [AgentProvider] = [.claude, .antigravity]
        let filtered = candidates.filter { snapshot.seen.contains($0) || snapshot.limits[$0] != nil }
        return filtered.isEmpty ? candidates : filtered
    }

    private func activeProvider(from providers: [AgentProvider], now: Date) -> AgentProvider {
        guard !providers.isEmpty else { return .claude }
        let cycleIndex = Int(now.timeIntervalSince1970 / 6) % providers.count
        return providers[cycleIndex]
    }

    private func remainingUsageFraction(for provider: AgentProvider, snapshot: AgentUsageSnapshot, now: Date) -> (remaining: Double, used: Double) {
        if let window = NotchAgentSupport.focusedLimit(snapshot.limits[provider],
                                                       focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed,
                                                       now: now) {
            return (window.remainingFraction, window.usedFraction)
        }
        if provider == .claude, let block = snapshot.claudeBlock {
            let length = max(1, block.end.timeIntervalSince(block.start))
            let elapsed = max(0, min(length, now.timeIntervalSince(block.start)))
            let remaining = max(0.0, 1.0 - (elapsed / length))
            return (remaining, 1.0 - remaining)
        }
        return (1.0, 0.0)
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let snapshot = usage.snapshot
        let providers = activeRestingProviders(snapshot: snapshot)
        let provider = activeProvider(from: providers, now: now)
        let (remaining, used) = remainingUsageFraction(for: provider, snapshot: snapshot, now: now)
        let tint = agentLimitTint(provider, usedFraction: used)
        if leading {
            HStack(spacing: 3) {
                if RestingStatus.showsAgentMark(restingWing) {
                    NotchAgentMark(provider: provider, size: 10, tint: tint)
                }
                NotchRestingStatusMark(mark: statusMark, language: l10n.language)
            }
        } else {
            switch restingWing {
            case .words(let words)?:
                // A tool's own words, drawn as Nexus Agent's text is.
                restingText(words)
            case .seconds(let since)?:
                restingText(RestingStatus.seconds(since: since, now: now, language: l10n.language))
            case .allowance?, nil:
                Text(AgentFormat.percent(remaining))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(tint == provider.tint ? .white : tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

extension NotchAgentRestingWing {
    /// The right-hand wing's text for a tool's words or seconds: the look of
    /// Nexus Agent's text, drawn as written, with no markup.
    fileprivate func restingText(_ words: String) -> some View {
        Text(verbatim: words)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

package typealias NotchRestingWing = NotchAgentRestingWing

/// The one status mark of the resting wing: a tool's, or nothing, as
/// `RestingStatus.winner` picked.
private struct NotchRestingStatusMark: View {
    let mark: RestingMark?
    let language: AppLanguage

    var body: some View {
        switch mark {
        case .tool(let id, let status)?:
            ToolStatusMark(content: ToolStatusMarkContent(status, toolName: name(of: id), language: language,
                                                          strings: FeatureStrings.externalTools(language)))
        case nil:
            EmptyView()
        }
    }

    /// The tool's name in the person's language, as the tool wrote it.
    private func name(of id: ToolID) -> String {
        let tool = ExternalToolStore.shared.installed[id]?.tool
        return tool?.name.text(for: language.rawValue) ?? tool?.manifest.tool.name ?? id.rawValue
    }
}
