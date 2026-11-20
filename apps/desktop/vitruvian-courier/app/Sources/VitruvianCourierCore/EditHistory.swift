// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Which versions of an edited message Edit History lists.
public enum EditHistory {
    /// `versions` (the message as first sent, then each live edit, oldest first) without the silent ones: an edit whose
    /// text and formatting equal the version before it (a link preview added) changed nothing to read, so it is not a
    /// version, the same rule that decides whether the message says "Edited".
    public static func visibleVersions(_ versions: [Version]) -> [Version] {
        var kept: [Version] = []
        for version in versions {
            if let last = kept.last, last.body == version.body, last.rich == version.rich { continue }
            kept.append(version)
        }
        return kept
    }
}
