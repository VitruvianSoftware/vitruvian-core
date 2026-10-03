// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The preferences declared with their defaults (see `Preference`). Each one
/// is registered from here and read through it. The others still pair a
/// `DefaultsKey` with a default in `Defaults.registeredDefaults`, until they
/// move here (REFACTOR.md step 6).
package enum Preferences {
    /// Owner's call: compact by default in 3.1.8.
    package static let menuBarMetricSpacing = Preference(DefaultsKey.menuBarMetricSpacing, default: "compact")
    package static let menuBarMetricOrder = Preference(
        DefaultsKey.menuBarMetricOrder, default: Defaults.defaultMenuBarMetricOrder.joined(separator: ","))
    /// Owner's call: on by default in 3.1.8. The badge only shows while the
    /// microphone is muted.
    package static let micMuteMenuBarIndicator = Preference(DefaultsKey.micMuteMenuBarIndicator, default: true)
    package static let screenshotPreviewPosition = Preference(
        DefaultsKey.screenshotPreviewPosition, default: ScreenshotSupport.QuickPreviewPosition.automatic.rawValue)
    package static let windowLayoutShortcutsEnabled = Preference(DefaultsKey.windowLayoutShortcutsEnabled, default: false)
}
