// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

package enum FinderRenameSupport {
    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField",
    ]

    package static func acceptsFocusedRole(_ role: String?) -> Bool {
        guard let role else { return false }
        return !editableRoles.contains(role)
    }
}
