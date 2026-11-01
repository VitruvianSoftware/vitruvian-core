// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// `AIPane.tsx`, `AIMessageContent.tsx`, `AIMessageFooterActions.tsx`, `AIMessageParts.tsx`,
/// `AIModelButton.tsx`, `AISpinnerVerb.tsx`, `AIToolCallsPanel.tsx` (`01` §13).
public struct AIPane: View {
    public let chatTitle: String
    @ObservedObject public var preferences: AIPreferences
    public let provider: any AIProvider
    public var onClose: () -> Void = {}

    @State private var selectedTone: AIRewriteTone = .moreConcise
    @State private var lastActionNotice: String?

    public init(
        chatTitle: String,
        preferences: AIPreferences,
        provider: any AIProvider = UnavailableAIProvider(),
        onClose: @escaping () -> Void = {}
    ) {
        self.chatTitle = chatTitle
        self.preferences = preferences
        self.provider = provider
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    unavailableCard
                    quickActionsSection
                    rewriteToneSection
                    if let lastActionNotice {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.secondary)
                            Text(lastActionNotice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.1))
                        )
                    }
                }
                .padding(14)
            }
            Divider()
            footerComposerBar
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Courier AI"))
                    .font(.subheadline.weight(.semibold))
                Text(chatTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(preferences.selectedModel)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.14)))
                .foregroundStyle(.secondary)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Close AI pane"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.accentColor)
                Text(String(localized: "On this Mac only"))
                    .font(.caption.weight(.semibold))
            }
            Text(provider.unavailableReason)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Suggested Actions"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach([
                (String(localized: "Summarize recent messages"), "text.redaction"),
                (String(localized: "Draft a reply"), "pencil.and.outline"),
                (String(localized: "Translate conversation"), "globe"),
            ], id: \.0) { title, icon in
                Button {
                    lastActionNotice = provider.unavailableReason
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18)
                        Text(title)
                            .font(.caption.weight(.medium))
                        Spacer(minLength: 0)
                        Text(String(localized: "Not available yet"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rewriteToneSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Draft Tone"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(String(localized: "Tone"), selection: $selectedTone) {
                ForEach(AIRewriteTone.allCases, id: \.self) { tone in
                    Text(tone.label).tag(tone)
                }
            }
            .labelsHidden()
        }
    }

    private var footerComposerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: "AI assistant isn’t available yet in Courier."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }
}

/// `MessageTranslations.tsx` and `MessageTranslationRow.tsx` (`01` §8, §13): inline translation row shown under a message bubble.
public struct MessageTranslationRowView: View {
    public let targetLanguage: String
    public let disposition: AIProviderDisposition
    public var onDismiss: () -> Void = {}

    public init(
        targetLanguage: String,
        disposition: AIProviderDisposition,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.targetLanguage = targetLanguage
        self.disposition = disposition
        self.onDismiss = onDismiss
    }

    private var displayBody: String {
        switch disposition {
        case let .unavailable(reason):
            reason
        case let .text(translated):
            translated
        }
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "globe")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Translation (\(targetLanguage))"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(displayBody)
                    .font(.caption)
                    .foregroundStyle(.primary)
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
