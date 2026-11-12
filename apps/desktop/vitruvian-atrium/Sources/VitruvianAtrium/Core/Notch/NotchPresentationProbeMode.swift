// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Every flag the Developer build's presentation probe dispatches on, in the
/// order it checks them.
package enum NotchPresentationProbeMode: String, CaseIterable {
    case standard = "--notch-presentation-test"
    case mediaLayout = "--media-layout"
    case missionControl = "--mission-control"
    case previewNotice = "--preview-notice"
    case profileOnly = "--profile-only"
    case quickAccessClicks = "--quick-access-clicks"

    /// Any mode selects the probe on its own, so none of them falls through
    /// to launching the whole app.
    package static func isRequested(by arguments: [String]) -> Bool {
        allCases.contains { arguments.contains($0.rawValue) }
    }
}
