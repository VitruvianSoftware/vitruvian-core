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
                                 band: @autoclosure () -> NotchBand,
                                 timerMode: @autoclosure () -> NotchTimerMode,
                                 timerHasSession: @autoclosure () -> Bool,
                                 hasPlayback: @autoclosure () -> Bool,
                                 musicBand: @autoclosure () -> CGFloat) -> CGSize {
        var size = content
        guard !detail else { return size }
        switch module {
        case .controls:
            // The levels that do not fit the top row take a row of their own.
            let groups = NotchControlGroups(controls())
            let levels = groups.levels.count
            size.height = max(size.height, NotchLayout.controls(
                hasCards: groups.music, levelRow: NotchLayout.bandLevelCount(levels, band: band()) < levels,
                shortcutCount: groups.shortcuts.count, width: size.width, height: size.height).height)
        case .timer:
            size.height = max(size.height, NotchLayout.timer(
                mode: timerMode(), hasSession: timerHasSession(), height: size.height))
        case .calendar:
            size.height = max(size.height, NotchLayout.calendarMonthMinimumHeight)
        case .clipboard:
            // A complete card with its action row; the search is in the top row.
            size.height = max(size.height, NotchLayout.clipboardCardHeight)
        case .camera:
            // Keep permission and error messages reachable.
            size.height = max(size.height, 144)
        case .mixer:
            // Shorten the tracks before pushing mute and level controls offscreen.
            size.height = max(size.height, NotchLayout.mixerMinimumHeight)
        case .music:
            size.height = max(size.height, NotchLayout.musicPlayerHeight(band: musicBand(), playing: hasPlayback()))
        case .files:
            // One shelf tile and its vertical insets; the actions are in the top row.
            size.height = max(size.height, ShelfTileLayout.tileSize.height + ShelfTileLayout.inset * 2)
        default: break
        }
        return size
    }
}
