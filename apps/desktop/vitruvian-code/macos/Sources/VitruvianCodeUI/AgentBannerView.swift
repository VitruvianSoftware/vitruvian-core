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

import SwiftUI
import VitruvianCodeCore

/// Severity styling for an agent notice banner.
public enum AgentBannerSeverity: String, Equatable, Sendable {
    case info
    case warning
    case error

    public init(rawSeverity: String) {
        switch rawSeverity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "error", "critical", "fatal":
            self = .error
        case "warning", "warn":
            self = .warning
        default:
            self = .info
        }
    }

    public var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    public var symbolName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        }
    }
}

/// Pure rules for capping, ordering, dismissing, and rendering untrusted agent notice banners.
public enum AgentBannerLogic: Sendable {
    public static let maxVisibleNotices = 3
    public static let maxTextLines = 3

    /// Returns up to `limit` newest non-dismissed notices (newest first) without altering `notices`.
    public static func visibleNotices(
        from notices: [AgentLiveState.Notice],
        dismissedIDs: Set<Int>,
        limit: Int = maxVisibleNotices
    ) -> [AgentLiveState.Notice] {
        guard limit > 0 else { return [] }
        return Array(notices.filter { !dismissedIDs.contains($0.id) }.reversed().prefix(limit))
    }

    /// Wraps untrusted agent text using `Text(verbatim:)` so markdown and links are never parsed.
    public static func verbatimText(_ text: String) -> Text {
        Text(verbatim: text)
    }

    /// `template` with its first `%@` replaced by `value`.
    public static func format(_ template: String, _ value: String) -> String {
        guard let range = template.range(of: "%@") else { return template }
        return template.replacingCharacters(in: range, with: value)
    }
}

/// Stack above the composer showing up to 3 newest undismissed notices from `liveState.notices`.
public struct AgentBannerView: View {
    public let notices: [AgentLiveState.Notice]
    public let dismissedIDs: Set<Int>
    public let strings: VitruvianCodeChatStrings
    public let onDismiss: (Int) -> Void

    public init(
        notices: [AgentLiveState.Notice],
        dismissedIDs: Set<Int>,
        strings: VitruvianCodeChatStrings,
        onDismiss: @escaping (Int) -> Void
    ) {
        self.notices = notices
        self.dismissedIDs = dismissedIDs
        self.strings = strings
        self.onDismiss = onDismiss
    }

    private var visible: [AgentLiveState.Notice] {
        AgentBannerLogic.visibleNotices(from: notices, dismissedIDs: dismissedIDs)
    }

    public var body: some View {
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visible) { notice in
                    noticeRow(notice)
                }
            }
        }
    }

    private func noticeRow(_ notice: AgentLiveState.Notice) -> some View {
        let severity = AgentBannerSeverity(rawSeverity: notice.severity)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: severity.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(severity.color)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                AgentBannerLogic.verbatimText(notice.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(AgentBannerLogic.maxTextLines)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = notice.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !detail.isEmpty {
                    AgentBannerLogic.verbatimText(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(AgentBannerLogic.maxTextLines)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDismiss(notice.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(strings.dismissNotice)
            .accessibilityLabel(strings.dismissNotice)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(severity.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(severity.color.opacity(0.26), lineWidth: 0.75)
        )
    }
}

/// Compact one-line timeline row for a compaction event (in progress, done, failed, or interrupted).
public struct AgentCompactionRowView: View {
    public let compaction: AgentLiveState.Compaction
    public let strings: VitruvianCodeChatStrings

    public init(compaction: AgentLiveState.Compaction, strings: VitruvianCodeChatStrings) {
        self.compaction = compaction
        self.strings = strings
    }

    private var labelText: String {
        if compaction.isInProgress { return strings.compactingContext }
        if compaction.isFailed { return strings.compactionFailed }
        if compaction.isInterrupted { return strings.compactionStopped }
        return strings.contextCompacted
    }

    public var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)

            HStack(spacing: 5) {
                if compaction.isInProgress {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 10, height: 10)
                } else if compaction.isFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                } else if compaction.isInterrupted {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }

                Text(labelText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let summary = compaction.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !summary.isEmpty {
                    Text("·")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    AgentBannerLogic.verbatimText(summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }
}

/// Idle suggestion chip offering Compact (`/compact`) or Keep when Claude context exceeds 200k tokens.
public struct AgentCompactionChipView: View {
    public let strings: VitruvianCodeChatStrings
    public let onCompact: () -> Void
    public let onKeep: () -> Void

    public init(
        strings: VitruvianCodeChatStrings,
        onCompact: @escaping () -> Void,
        onKeep: @escaping () -> Void
    ) {
        self.strings = strings
        self.onCompact = onCompact
        self.onKeep = onKeep
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VitruvianCodeTheme.warmCoral)

            Text(strings.compactionSuggestion)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Button {
                onCompact()
            } label: {
                Text(strings.compactAction)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(VitruvianCodeTheme.warmCoral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(VitruvianCodeTheme.warmCoral.opacity(0.14)))
            }
            .buttonStyle(.plain)

            Button {
                onKeep()
            } label: {
                Text(strings.keepAction)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75)
        )
    }
}

/// Banner showing an active Claude usage limit, local reset time, live countdown, and Resume gate.
public struct AgentUsageLimitBannerView: View {
    public let limit: AgentLiveState.UsageLimit
    public let strings: VitruvianCodeChatStrings
    public let nowOverride: Date?
    public let onResume: () -> Void
    public let onDismiss: () -> Void

    public init(
        limit: AgentLiveState.UsageLimit,
        strings: VitruvianCodeChatStrings,
        nowOverride: Date? = nil,
        onResume: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.limit = limit
        self.strings = strings
        self.nowOverride = nowOverride
        self.onResume = onResume
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if let fixedNow = nowOverride {
            content(now: fixedNow)
        } else {
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                content(now: context.date)
            }
        }
    }

    private func content(now: Date) -> some View {
        let canResume = AgentUsageLimitState.canResume(limit, now: now)
        let remaining = AgentUsageLimitState.remainingSeconds(limit, now: now)
        return HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(strings.usageLimitReached)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let resetsAt = limit.resetsAt {
                    if canResume {
                        Text(strings.usageLimitReady)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        let localTime = AgentUsageLimitState.formattedLocalResetTime(resetsAt, now: now)
                        let countdown = AgentUsageLimitState.formattedCountdown(seconds: remaining ?? 0)
                        AgentBannerLogic.verbatimText("\(strings.usageLimitResetsAtPrefix)\(localTime) · \(countdown)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if limit.resetsAt != nil {
                Button {
                    onResume()
                } label: {
                    Text(strings.usageLimitResume)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(canResume ? VitruvianCodeTheme.warmCoral : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(
                                canResume ? VitruvianCodeTheme.warmCoral.opacity(0.15) : Color.primary.opacity(0.06)
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canResume)
                .opacity(canResume ? 1.0 : 0.55)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(strings.dismissNotice)
            .accessibilityLabel(strings.dismissNotice)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.75)
        )
    }
}

/// Error card shown when a live connection fails, crashes, or locks after 3 failures.
public struct AgentErrorCardView: View {
    public let failure: AgentLiveFailure
    public let strings: VitruvianCodeChatStrings
    public let onRetry: () -> Void
    /// Nil for an agent with no command line (one from the ACP registry): no button.
    public let onUseCommandLine: (() -> Void)?
    public let onDismiss: () -> Void
    /// Signs in with one of `failure.signInMethods` (`ACPAuth`).
    public let onSignIn: ((AgentSignInMethod) -> Void)?

    public init(
        failure: AgentLiveFailure,
        strings: VitruvianCodeChatStrings,
        onRetry: @escaping () -> Void,
        onUseCommandLine: (() -> Void)?,
        onDismiss: @escaping () -> Void,
        onSignIn: ((AgentSignInMethod) -> Void)? = nil
    ) {
        self.failure = failure
        self.strings = strings
        self.onRetry = onRetry
        self.onUseCommandLine = onUseCommandLine
        self.onDismiss = onDismiss
        self.onSignIn = onSignIn
    }

    /// The sign-in buttons the card shows: one per method, when the agent asked for sign-in.
    public var signInMethodsShown: [AgentSignInMethod] {
        guard onSignIn != nil, failure.needsSignIn, !failure.isLocked else { return [] }
        return failure.signInMethods
    }

    private var iconName: String {
        if failure.isLocked { return "lock.fill" }
        if failure.needsSignIn { return "key.fill" }
        switch failure.source {
        case .interrupted: return "bolt.slash.fill"
        case .generic, .helperCrash, .claudeCrash: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        failure.isLocked ? .red : .orange
    }

    private var headerTitle: String {
        if failure.isLocked { return strings.connectionLockedTitle }
        if failure.needsSignIn { return strings.signInNeededTitle }
        switch failure.source {
        case .helperCrash: return strings.helperCrashTitle
        case .claudeCrash: return strings.claudeCrashTitle
        case .interrupted: return strings.turnInterrupted
        case .generic: return strings.agentFailed
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundStyle(iconColor)

                Text(headerTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .help(strings.dismissNotice)
                .accessibilityLabel(strings.dismissNotice)
            }

            if !failure.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AgentBannerLogic.verbatimText(failure.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if failure.isLocked {
                Text(strings.connectionLockedExplanation)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !signInMethodsShown.isEmpty {
                HStack(spacing: 8) {
                    ForEach(signInMethodsShown) { method in
                        Button {
                            onSignIn?(method)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.crop.circle")
                                    .font(.caption)
                                Text(AgentBannerLogic.format(strings.signInWithFormat, method.name))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(VitruvianCodeTheme.warmCoral)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(method.description ?? AgentBannerLogic.format(strings.signInWithFormat, method.name))
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 8) {
                Button {
                    onRetry()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text(strings.retry)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(failure.isLocked ? Color.secondary : VitruvianCodeTheme.warmCoral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(failure.isLocked ? Color.primary.opacity(0.05) : VitruvianCodeTheme.warmCoral.opacity(0.14))
                    )
                }
                .buttonStyle(.plain)
                .disabled(failure.isLocked)
                .opacity(failure.isLocked ? 0.5 : 1.0)
                .help(strings.retry)

                if let onUseCommandLine {
                Button {
                    onUseCommandLine()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                            .font(.caption)
                        Text(strings.useCommandLineForChat)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help(strings.useCommandLineForChat)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.red.opacity(0.22), lineWidth: 0.75)
        )
    }
}
