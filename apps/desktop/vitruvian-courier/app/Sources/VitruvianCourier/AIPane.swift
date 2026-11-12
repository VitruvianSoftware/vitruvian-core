// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// `AIPane.tsx` (`01` §13, `docs/ai-providers.md`): unified pane header (`PaneHeader`), single active provider/model
/// status row, Summarize action with collapsible one-line summary card (`"Summary of N messages · on this Mac"`),
/// selectable summary text and Copy button, or a single calm setup prompt with **Open AI Settings** when no provider is configured.
public struct AIPane: View {
    public let chatTitle: String
    @ObservedObject public var preferences: AIPreferences
    /// The active `AIProvider` from `AIProviderStore` (`composer.aiProvider` in `ConversationView`).
    public let provider: any AIProvider
    public var isSummarizing: Bool
    public var summarizingMessageCount: Int
    public var summary: ChatAISummary?
    public var summaryError: String?
    public var isSummaryExpanded: Bool
    public var onSummarize: () -> Void
    public var onCancelSummarize: () -> Void
    public var onToggleSummaryExpanded: () -> Void
    public var onCopySummary: (String) -> Void
    public var onReadAloudSummary: (String) -> Void
    public var onOpenAISettings: () -> Void
    public var onClose: () -> Void
    /// With glass in the main window the header is a toolbar item (`AIPaneHeader`, placed by `ConversationView`), so
    /// the pane draws none of its own.
    public var headerInToolbar: Bool = false

    /// Creates the Vitruvian Courier AI side pane.
    /// - Parameter provider: The live `AIProvider` from `AIProviderStore` (for example `composer.aiProvider`).
    ///   Defaults to `UnavailableAIProvider()` only for standalone previews and snapshot tests that do not own a store;
    ///   app callers must pass the store-backed provider so configured providers are reflected.
    public init(
        chatTitle: String,
        preferences: AIPreferences,
        provider: any AIProvider = UnavailableAIProvider(),
        isSummarizing: Bool = false,
        summarizingMessageCount: Int = 0,
        summary: ChatAISummary? = nil,
        summaryError: String? = nil,
        isSummaryExpanded: Bool = true,
        onSummarize: @escaping () -> Void = {},
        onCancelSummarize: @escaping () -> Void = {},
        onToggleSummaryExpanded: @escaping () -> Void = {},
        onCopySummary: @escaping (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        },
        onReadAloudSummary: @escaping (String) -> Void = { _ in },
        onOpenAISettings: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {},
        headerInToolbar: Bool = false
    ) {
        self.chatTitle = chatTitle
        self.preferences = preferences
        self.provider = provider
        self.isSummarizing = isSummarizing
        self.summarizingMessageCount = summarizingMessageCount
        self.summary = summary
        self.summaryError = summaryError
        self.isSummaryExpanded = isSummaryExpanded
        self.onSummarize = onSummarize
        self.onCancelSummarize = onCancelSummarize
        self.onToggleSummaryExpanded = onToggleSummaryExpanded
        self.onCopySummary = onCopySummary
        self.onReadAloudSummary = onReadAloudSummary
        self.onOpenAISettings = onOpenAISettings
        self.onClose = onClose
        self.headerInToolbar = headerInToolbar
    }

    private var activeProviderModelLine: String {
        let model = (preferences.model(for: preferences.selectedEngine) ?? preferences.selectedModel)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            return preferences.selectedEngine.label
        }
        return "\(preferences.selectedEngine.label) · \(model)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !headerInToolbar {
                AIPaneHeader(onClose: onClose, inToolbar: false)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if provider.isAvailable {
                        providerStatusCard
                        summarizeSection
                    } else {
                        unavailableCard
                    }
                }
                .padding(PaneHeaderMetrics.inset)
            }
            .courierScrollEdges()
        }
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 380)
        .courierSurface(.sidePane)
    }

    private var providerStatusCard: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(activeProviderModelLine)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(preferences.selectedEngine.summaryLocationNote())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Set up a local or cloud AI provider in Settings to summarize chats, draft replies, and translate messages."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(String(localized: "Open AI Settings"), action: onOpenAISettings)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var summarizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onSummarize) {
                HStack(spacing: 8) {
                    Image(systemName: "text.redaction")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)
                    Text(String(localized: "Summarize"))
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
            .disabled(isSummarizing)

            if isSummarizing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Summarizing \(summarizingMessageCount) messages…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(String(localized: "Cancel"), action: onCancelSummarize)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                )
            }

            if let summary {
                summaryCard(summary)
            }

            if let summaryError {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(summaryError)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 10) {
                        Button(String(localized: "Retry"), action: onSummarize)
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.medium))
                        Button(String(localized: "Open AI Settings"), action: onOpenAISettings)
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
            }
        }
    }

    private func summaryCard(_ summary: ChatAISummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggleSummaryExpanded) {
                HStack(spacing: 6) {
                    Image(systemName: isSummaryExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(summary.collapsedHeader)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSummaryExpanded {
                Divider()
                Text(AIOutputFormatter.attributed(summary.text))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(summary.provenance)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button(String(localized: "Read aloud")) {
                        onReadAloudSummary(AIOutputFormatter.plainText(summary.text))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    Button(String(localized: "Copy")) {
                        onCopySummary(AIOutputFormatter.plainText(summary.text))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.5)
        )
    }
}

/// Vitruvian Courier AI pane header: its title and Close button. A strip at the pane's top, or with glass, the pane's item in the
/// window's toolbar (`inToolbar`), aligned with the chat, thread, and Chat Info headers.
struct AIPaneHeader: View {
    var onClose: () -> Void = {}
    var inToolbar: Bool

    var body: some View {
        PaneHeader(title: String(localized: "Vitruvian Courier AI"), inToolbar: inToolbar) {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help(String(localized: "Close AI pane"))
            .accessibilityLabel(String(localized: "Close AI pane"))
        }
    }
}

/// `MessageTranslations.tsx` and `MessageTranslationRow.tsx` (`01` §8, §13): inline translation row shown under a message bubble.
public struct MessageTranslationRowView: View {
    public let targetLanguage: String
    public let disposition: AIProviderDisposition?
    public var isTranslating: Bool
    public var provenance: String?
    public var onRetry: (() -> Void)?
    public var onOpenAISettings: (() -> Void)?
    public var onDismiss: () -> Void

    public init(
        targetLanguage: String,
        disposition: AIProviderDisposition,
        isTranslating: Bool = false,
        provenance: String? = nil,
        onRetry: (() -> Void)? = nil,
        onOpenAISettings: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.targetLanguage = targetLanguage
        self.disposition = disposition
        self.isTranslating = isTranslating
        self.provenance = provenance
        self.onRetry = onRetry
        self.onOpenAISettings = onOpenAISettings
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isTranslating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Translating into \(targetLanguage)…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let disposition {
                Image(systemName: "globe")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Translation (\(targetLanguage))"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    switch disposition {
                    case let .text(translated):
                        Text(AIOutputFormatter.attributed(translated))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                        if let provenance, !provenance.isEmpty {
                            Text(provenance)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    case let .unavailable(reason):
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        if onRetry != nil || onOpenAISettings != nil {
                            HStack(spacing: 10) {
                                if let onRetry {
                                    Button(String(localized: "Retry"), action: onRetry)
                                        .buttonStyle(.borderless)
                                        .font(.caption2.weight(.semibold))
                                }
                                if let onOpenAISettings {
                                    Button(String(localized: "Open AI Settings"), action: onOpenAISettings)
                                        .buttonStyle(.borderless)
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Dismiss translation"))
            .accessibilityLabel(String(localized: "Dismiss translation"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 0.5)
        )
    }
}
