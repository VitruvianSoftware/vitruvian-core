// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A feature that is part of a plan (spec §3). The engine has the same list and answers -32022 for a feature the
/// plan doesn't include; the app asks first, so a denied action calls nothing and says "Available with a plan".
public enum Feature: String, CaseIterable, Sendable {
    case reminders
    case sendLater = "send_later"
    case undoSend = "undo_send"
    case incognito
    case lowPriority = "low_priority"
    case autoArchive = "auto_archive"
}

/// Says whether the person's plan includes a feature. The subscription screen is part 4.7; until then the only
/// provider says yes.
public protocol EntitlementProvider: Sendable {
    func isEntitled(_ feature: Feature) -> Bool
}

/// Every feature, for everyone.
public struct AlwaysEntitled: EntitlementProvider {
    public init() {}

    public func isEntitled(_ feature: Feature) -> Bool { true }
}

/// No feature: what a model is given until it is told the person's plan, so a forgotten wiring fails closed.
public struct NoPlan: EntitlementProvider {
    public init() {}

    public func isEntitled(_ feature: Feature) -> Bool { false }
}

public struct PlanFeatureComparisonRow: Equatable, Sendable, Identifiable {
    public let feature: Feature
    public let title: String
    public let summary: String
    public let freeValue: String
    public let planValue: String
    public let isAllowedNow: Bool
    public var id: Feature { feature }

    public init(
        feature: Feature,
        title: String,
        summary: String,
        freeValue: String,
        planValue: String,
        isAllowedNow: Bool
    ) {
        self.feature = feature
        self.title = title
        self.summary = summary
        self.freeValue = freeValue
        self.planValue = planValue
        self.isAllowedNow = isAllowedNow
    }
}

public enum SubscriptionExpiryBannerState: Equatable, Sendable {
    case activeIncluded
    case trialActive(daysRemaining: Int)
    case expiringSoon(dateText: String)
    case expired
}

public struct SubscriptionPlanSummary: Equatable, Sendable {
    public let badgeTitle: String
    public let headline: String
    public let detail: String
    public let accountsPerNetworkLimit: String
    public let totalAccountsLimit: String
    public let mergedChatsLimit: String
    public let bannerState: SubscriptionExpiryBannerState
    public let featureRows: [PlanFeatureComparisonRow]

    public init(
        badgeTitle: String,
        headline: String,
        detail: String,
        accountsPerNetworkLimit: String,
        totalAccountsLimit: String,
        mergedChatsLimit: String,
        bannerState: SubscriptionExpiryBannerState,
        featureRows: [PlanFeatureComparisonRow]
    ) {
        self.badgeTitle = badgeTitle
        self.headline = headline
        self.detail = detail
        self.accountsPerNetworkLimit = accountsPerNetworkLimit
        self.totalAccountsLimit = totalAccountsLimit
        self.mergedChatsLimit = mergedChatsLimit
        self.bannerState = bannerState
        self.featureRows = featureRows
    }
}

extension EntitlementProvider {
    public static var unavailableMessage: String {
        String(localized: "Available with a plan")
    }

    public func freebieNudgeText(for feature: Feature) -> String? {
        isEntitled(feature) ? nil : String(localized: "Available with a plan")
    }

    public var planSummary: SubscriptionPlanSummary {
        let rows: [PlanFeatureComparisonRow] = Feature.allCases.map { feature in
            let allowed = isEntitled(feature)
            switch feature {
            case .reminders:
                return PlanFeatureComparisonRow(
                    feature: .reminders,
                    title: String(localized: "Chat Reminders"),
                    summary: String(localized: "Snooze a conversation until a chosen time or until the other person replies."),
                    freeValue: String(localized: "Available with a plan"),
                    planValue: String(localized: "Included"),
                    isAllowedNow: allowed
                )
            case .sendLater:
                return PlanFeatureComparisonRow(
                    feature: .sendLater,
                    title: String(localized: "Send Later"),
                    summary: String(localized: "Schedule outgoing messages to be delivered at a future time."),
                    freeValue: String(localized: "Available with a plan"),
                    planValue: String(localized: "Included"),
                    isAllowedNow: allowed
                )
            case .undoSend:
                return PlanFeatureComparisonRow(
                    feature: .undoSend,
                    title: String(localized: "Undo Send"),
                    summary: String(localized: "Hold sent messages briefly on this Mac so you can cancel or edit before delivery."),
                    freeValue: String(localized: "Available with a plan"),
                    planValue: String(localized: "Included"),
                    isAllowedNow: allowed
                )
            case .incognito:
                return PlanFeatureComparisonRow(
                    feature: .incognito,
                    title: String(localized: "Incognito Mode"),
                    summary: String(localized: "Read chats without marking them read or sending read receipts until you reply."),
                    freeValue: String(localized: "Available with a plan"),
                    planValue: String(localized: "Included"),
                    isAllowedNow: allowed
                )
            case .lowPriority:
                return PlanFeatureComparisonRow(
                    feature: .lowPriority,
                    title: String(localized: "Low Priority Inbox"),
                    summary: String(localized: "Move noisy chats out of your main inbox while keeping them searchable."),
                    freeValue: String(localized: "Available with a plan"),
                    planValue: String(localized: "Included"),
                    isAllowedNow: allowed
                )
            case .autoArchive:
                return PlanFeatureComparisonRow(
                    feature: .autoArchive,
                    title: String(localized: "Auto-Archive Timers"),
                    summary: String(localized: "Automatically archive inactive chats after a configurable duration."),
                    freeValue: String(localized: "Available with a plan"),
                    planValue: String(localized: "Included"),
                    isAllowedNow: allowed
                )
            }
        }

        let allEntitled = rows.allSatisfy(\.isAllowedNow)
        if allEntitled {
            return SubscriptionPlanSummary(
                badgeTitle: String(localized: "Included"),
                headline: String(localized: "All Courier features are included on this Mac"),
                detail: String(localized: "Every messaging, scheduling, and inbox organization feature is unlocked in Courier."),
                accountsPerNetworkLimit: String(localized: "Unlimited"),
                totalAccountsLimit: String(localized: "Unlimited"),
                mergedChatsLimit: String(localized: "Unlimited"),
                bannerState: .activeIncluded,
                featureRows: rows
            )
        } else {
            return SubscriptionPlanSummary(
                badgeTitle: String(localized: "Free"),
                headline: String(localized: "Available with a plan"),
                detail: String(localized: "Plan management isn’t available yet in Courier."),
                accountsPerNetworkLimit: "1",
                totalAccountsLimit: "5",
                mergedChatsLimit: "0",
                bannerState: .expired,
                featureRows: rows
            )
        }
    }
}
