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

/// The resting island's wings: the chosen allowance, by default the one
/// closest to running out, as a ring and a number, or today's API value when
/// no allowance is known.
package struct NotchAgentRestingWing: View {
    package let leading: Bool
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var nexusSession = NexusAgentService.shared.session
    @ObservedObject private var gitHub = GitHubService.shared
    @AppStorage(Preferences.notchAgentsLimitDisplay) private var display: String
    @AppStorage(Preferences.notchAgentsLimitFocus) private var focus: String

    package var body: some View {
        TimelineView(.periodic(from: .now, by: nexusSession.isRunning ? 1 : 6)) { context in
            content(now: context.date)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if gitHub.summary.aggregate == .red || gitHub.summary.aggregate == .amber {
                NotchService.shared.select(.github)
            } else {
                NotchService.shared.agentTab = .chat
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
        if nexusSession.isRunning {
            if leading {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .scaleEffect(nexusSession.elapsedSeconds % 2 == 0 ? 1.15 : 0.85)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: nexusSession.elapsedSeconds)
            } else {
                let badge = nexusSession.activity ?? "\(nexusSession.elapsedSeconds)s"
                Text(badge)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } else {
            let snapshot = usage.snapshot
            let providers = activeRestingProviders(snapshot: snapshot)
            let provider = activeProvider(from: providers, now: now)
            let (remaining, used) = remainingUsageFraction(for: provider, snapshot: snapshot, now: now)
            let tint = agentLimitTint(provider, usedFraction: used)
            if leading {
                HStack(spacing: 3) {
                    NotchAgentMark(provider: provider, size: 10, tint: tint)
                    NotchGitHubRestingIndicator()
                }
            } else {
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

package typealias NotchRestingWing = NotchAgentRestingWing

/// Live activity indicator in the resting wing showing GitHub repository pipeline status:
/// - Green checkmark when watched repo pipeline on `main` is clean.
/// - Amber breathing spinner (`arrow.triangle.branch`) when presubmits are running.
/// - Red alert glyph (`exclamationmark.triangle.fill`) when a check fails on watched branches.
package struct NotchGitHubRestingIndicator: View {
    @ObservedObject private var gitHub = GitHubService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    package init() {}

    private var indicatorVerdict: Verdict? {
        guard !gitHub.watchedRepositories.isEmpty else { return nil }
        return gitHub.summary.aggregate
    }

    package var body: some View {
        if let verdict = indicatorVerdict {
            switch verdict {
            case .green:
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
            case .amber:
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.orange)
                    .scaleEffect(breathing && !reduceMotion ? 1.15 : 0.9)
                    .opacity(breathing && !reduceMotion ? 1.0 : 0.65)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            breathing = true
                        }
                    }
            case .red:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.red)
            case .grey:
                EmptyView()
            }
        }
    }
}
