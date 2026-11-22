// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// How wide a message bubble may grow: about 60% of the conversation, never narrower than 640 pt (so a medium window
/// keeps the width it always had) and never wider than 960 pt (long lines get hard to read). The window's own room
/// still caps it from the other side.
public enum BubbleWidth {
    /// The share of the conversation's width a bubble may take.
    public static let fractionOfRow: CGFloat = 0.6
    /// The narrowest cap, in points.
    public static let floor: CGFloat = 640
    /// The widest cap, in points.
    public static let ceiling: CGFloat = 960
    /// What a row keeps beside its bubble: the 60 pt spacer on the far side and the 8 pt gap before it.
    public static let sideSpace: CGFloat = 68
    /// A group chat's picture column (28 pt) and the 8 pt gap after it.
    public static let avatarColumn: CGFloat = 36

    /// The most a bubble may be in a row that is `rowWidth` wide.
    public static func maxWidth(rowWidth: CGFloat) -> CGFloat {
        min(ceiling, max(floor, fractionOfRow * rowWidth))
    }

    /// The same, from the room the row left for the bubble itself (`offered`): the row is that plus its spacer and, in
    /// a group chat, the picture column.
    public static func maxWidth(offered: CGFloat, hasAvatarColumn: Bool) -> CGFloat {
        maxWidth(rowWidth: offered + sideSpace + (hasAvatarColumn ? avatarColumn : 0))
    }
}
