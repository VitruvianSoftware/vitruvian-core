// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// `Settings ▸ Courier Plan` & `Settings ▸ Integrations`: covers `setting:beeper-plus Go Unlimited`,
/// `PlusPill.tsx`, `FreebieNudge.tsx`, `SubscriptionExpiryBanners.tsx`, `BrowserExtPrefsSubView.tsx`,
/// `MobileAppsPrefsSubView.tsx`, `SecretPrefsSubView.tsx`, `DebugPreferencesIndex.tsx`, and `setting:integrations *`.
public struct PlusSettingsPane: View {
    public let entitlement: any EntitlementProvider
    public var highlightedSettingID: String? = nil

    public init(
        entitlement: any EntitlementProvider = AlwaysEntitled(),
        highlightedSettingID: String? = nil
    ) {
        self.entitlement = entitlement
        self.highlightedSettingID = highlightedSettingID
    }

    private var summary: SubscriptionPlanSummary {
        entitlement.planSummary
    }

    public var body: some View {
        ScrollViewReader { proxy in
            Form {
                planOverviewSection
                planFeaturesSection
            }
            .formStyle(.grouped)
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                if let targetID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }

    private var planOverviewSection: some View {
        Section(String(localized: "Courier Plan")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: summary.bannerState == .activeIncluded ? "checkmark.seal.fill" : "sparkles")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(summary.headline)
                                .font(.headline)
                            PlusPillView(
                                title: summary.badgeTitle,
                                isUnlimited: summary.bannerState == .activeIncluded
                            )
                        }
                        Text(summary.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                if summary.bannerState != .expired {
                    SubscriptionExpiryBannerView(state: summary.bannerState)
                }

                HStack(spacing: 12) {
                    limitMetricCard(
                        title: String(localized: "Accounts per Network"),
                        value: summary.accountsPerNetworkLimit
                    )
                    limitMetricCard(
                        title: String(localized: "Total Accounts"),
                        value: summary.totalAccountsLimit
                    )
                    limitMetricCard(
                        title: String(localized: "Merged Chats"),
                        value: summary.mergedChatsLimit
                    )
                }
            }
            .settingAnchor("plan.overview", highlighted: highlightedSettingID)
        }
    }

    private func limitMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var planFeaturesSection: some View {
        Section(String(localized: "Included Features")) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(summary.featureRows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: row.isAllowedNow ? "checkmark.circle.fill" : "lock.circle")
                            .foregroundStyle(row.isAllowedNow ? Color.green : Color.secondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(row.title)
                                    .font(.subheadline.weight(.medium))
                                PlusPillView(
                                    title: row.isAllowedNow ? row.planValue : row.freeValue,
                                    isUnlimited: row.isAllowedNow
                                )
                            }
                            Text(row.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }
            .settingAnchor("plan.features", highlighted: highlightedSettingID)
        }
    }
}

public struct PlusPillView: View {
    public let title: String
    public let isUnlimited: Bool

    public init(title: String, isUnlimited: Bool = true) {
        self.title = title
        self.isUnlimited = isUnlimited
    }

    public var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(isUnlimited ? Color.accentColor.opacity(0.16) : Color.orange.opacity(0.16))
            )
            .foregroundStyle(isUnlimited ? Color.accentColor : Color.orange)
    }
}

public struct SubscriptionExpiryBannerView: View {
    public let state: SubscriptionExpiryBannerState
    public var onAction: () -> Void = {}

    public init(state: SubscriptionExpiryBannerState, onAction: @escaping () -> Void = {}) {
        self.state = state
        self.onAction = onAction
    }

    private var bannerText: String {
        switch state {
        case .activeIncluded:
            String(localized: "Included on this Mac — no subscription or remote account required.")
        case let .trialActive(daysRemaining):
            String(localized: "Trial active (\(daysRemaining) days remaining).")
        case let .expiringSoon(dateText):
            String(localized: "Plan expires on \(dateText).")
        case .expired:
            String(localized: "Available with a plan — subscription management isn’t available yet in Courier.")
        }
    }

    private var bannerIcon: String {
        switch state {
        case .activeIncluded: "checkmark.shield.fill"
        case .trialActive: "clock.fill"
        case .expiringSoon, .expired: "info.circle.fill"
        }
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: bannerIcon)
                .foregroundStyle(state == .activeIncluded ? Color.green : Color.secondary)
            Text(bannerText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

public struct IntegrationsSettingsPane: View {
    public var highlightedSettingID: String? = nil

    public init(highlightedSettingID: String? = nil) {
        self.highlightedSettingID = highlightedSettingID
    }

    public var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section(String(localized: "Browser Extension")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Browser Companion Extension"))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(String(localized: "Not available yet"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(String(localized: "Browser extension pairing isn’t available yet in Courier. Links and attachments open directly on this Mac."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .settingAnchor("integrations.browserExtension", highlighted: highlightedSettingID)
                }

                Section(String(localized: "Mobile Companion Apps")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Mobile Companion Sync"))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(String(localized: "Not available yet"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(String(localized: "Courier connects directly to your chat networks on this Mac without a cloud relay or mobile companion app."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .settingAnchor("integrations.mobileApps", highlighted: highlightedSettingID)
                }

                Section(String(localized: "Advanced & Local Diagnostics")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Local-First Diagnostics"))
                            .font(.subheadline.weight(.medium))
                        Text(String(localized: "Use View ▸ Toggle Bridge Logs or Help ▸ Report a Problem… (⌘⇧P) to inspect local bridge activity and save scrubbed diagnostic bundles on this Mac."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .settingAnchor("integrations.developer", highlighted: highlightedSettingID)
                }
            }
            .formStyle(.grouped)
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                if let targetID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }
}
