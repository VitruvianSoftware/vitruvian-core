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
