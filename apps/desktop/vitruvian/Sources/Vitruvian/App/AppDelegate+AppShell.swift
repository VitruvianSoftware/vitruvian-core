// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore
import VitruvianDesign

/// The app shell services and views reach through `appShell()`. Every other
/// requirement is met by `AppDelegate`'s existing methods.
extension AppDelegate: AppShell {
    func showOnboarding() {
        showOnboarding(mode: .full)
    }

    func showPermissionGuide(for kind: PermissionKind) {
        PermissionGuideOverlay.shared.show(for: kind)
    }
}
