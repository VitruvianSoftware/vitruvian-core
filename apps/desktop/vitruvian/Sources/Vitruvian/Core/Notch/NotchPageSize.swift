// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreGraphics

extension NotchLayout {
    /// The size an open page lays out in: the island's content size, made
    /// taller where the page needs more than a short island gives it, so the
    /// page scrolls instead of clipping. It keeps the content's width, and a
    /// detail page keeps the content size.
    ///
    /// Only the selected page's own inputs are read: the others are
    /// autoclosures, so the island does not read every page's preferences on
    /// each layout pass.
    package static func pageSize(content: CGSize, module: NotchModule, detail: Bool,
                                 controls: @autoclosure () -> [NotchControlItem],
                                 timerMode: @autoclosure () -> NotchTimerMode,
                                 timerHasSession: @autoclosure () -> Bool,
                                 hasPlayback: @autoclosure () -> Bool,
                                 musicControlsRow: @autoclosure () -> Bool,
                                 layout: NotchSize) -> CGSize {
        var size = content
        guard !detail else { return size }
        switch module {
        case .controls:
            let groups = NotchControlGroups(controls())
            size.height = max(size.height, NotchLayout.controls(
                hasCards: groups.hasCards, shortcutCount: groups.shortcuts.count,
                width: size.width, height: size.height).height)
        case .timer:
            size.height = max(size.height, NotchLayout.timer(
                mode: timerMode(), hasSession: timerHasSession(), width: size.width, height: size.height))
        case .calendar:
            size.height = max(size.height, NotchLayout.calendarMonthMinimumHeight)
        case .clipboard:
            // Search, spacing and a complete card with its action row.
            size.height = max(size.height, NotchLayout.clipboardSearchHeight + NotchLayout.rowSpacing
                              + NotchLayout.clipboardCardHeight)
        case .camera:
            // Keep permission and error messages, and the stop button, reachable.
            size.height = max(size.height, 144)
        case .mixer:
            // Shorten the tracks before pushing mute and level controls offscreen.
            size.height = max(size.height, 144)
        case .music:
            let controlsRow = NotchLayout.musicControlsRow(musicControlsRow())
            let player = NotchLayout.musicMainHeight(hasPlayback: hasPlayback(), layout: layout, height: size.height)
            size.height = max(size.height, player + controlsRow)
        case .files:
            // One shelf tile, its vertical insets, the footer and their gap.
            size.height = max(size.height, ShelfTileLayout.tileSize.height + ShelfTileLayout.inset * 2
                              + NotchLayout.iconButtonSide + NotchLayout.rowSpacing)
        default: break
        }
        return size
    }
}
