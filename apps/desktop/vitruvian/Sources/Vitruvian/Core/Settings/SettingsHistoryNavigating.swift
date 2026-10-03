// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The Settings window's Back and Forward menu actions. The window conforms, so
/// a service can find those menu items by selector without naming the window,
/// and the compiler still checks that the selectors are the window's own.
@objc package protocol SettingsHistoryNavigating {
    func goBack(_ sender: Any?)
    func goForward(_ sender: Any?)
}
