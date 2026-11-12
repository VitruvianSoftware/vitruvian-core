// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

extension View {
    /// SwiftUI's system tooltip bridge crashes on the current macOS 27 beta
    /// while routing hover events. Keep accessibility labels everywhere and
    /// use native hover help on earlier systems.
    @ViewBuilder
    package func screenshotSafeHelp(_ text: String) -> some View {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            self
        } else {
            help(text)
        }
    }
}
