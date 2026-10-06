// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import CoreGraphics

package enum NotchModule: String, CaseIterable, Identifiable {
    case controls, mixer, music, clipboard, captures, files, system, tools, calendar, notifications, timer, camera, downloads, scratchpad, agents, watch
    package var id: String { rawValue }

    package var symbol: String {
        switch self {
        case .controls: return "slider.horizontal.3"
        // A speaker reads as sound at a glance; faders beside the settings
        // gear looked like a second settings button.
        case .mixer: return "speaker.wave.2"
        case .music: return "music.note"
        case .timer: return "timer"
        case .camera: return "web.camera"
        case .downloads: return "arrow.down.circle"
        case .notifications: return "bell"
        case .calendar: return "calendar"
        case .clipboard: return "doc.on.clipboard"
        case .captures: return "camera.viewfinder"
        case .files: return "tray.full"
        case .system: return "gauge.with.dots.needle.50percent"
        case .tools: return "square.grid.2x2"
        case .scratchpad: return "note.text"
        case .agents: return "sparkles"
        case .watch: return "eye"
        }
    }

    /// Stable across ordering and languages; every destination has a direct key.
    package var shortcutKey: String {
        switch self {
        case .controls: return "c"
        case .mixer: return "v"
        case .music: return "m"
        case .clipboard: return "b"
        case .captures: return "s"
        case .files: return "f"
        case .system: return "i"
        case .tools: return "t"
        case .calendar: return "a"
        case .notifications: return "n"
        case .timer: return "r"
        case .camera: return "w"
        case .downloads: return "d"
        case .scratchpad: return "p"
        case .agents: return "g"
        case .watch: return "o"
        }
    }

    package func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .controls, .music: return true
        case .timer: return AppFeature.notchTimer.isAvailable(in: defaults)
        case .camera: return AppFeature.cameraPreview.isAvailable(in: defaults)
        case .downloads: return AppFeature.notchDownloads.isAvailable(in: defaults)
        case .notifications: return AppFeature.notchNotifications.isAvailable(in: defaults)
        case .calendar: return AppFeature.notchCalendar.isAvailable(in: defaults)
        case .mixer: return AppFeature.mixer.isAvailable(in: defaults)
        case .tools: return AppFeature.quickLauncher.isAvailable(in: defaults)
        case .clipboard: return AppFeature.clipboardHistory.isAvailable(in: defaults)
        case .captures:
            return AppFeature.screenshot.isAvailable(in: defaults)
                || AppFeature.screenRecorder.isAvailable(in: defaults)
                || AppFeature.screenOCR.isAvailable(in: defaults)
                || AppFeature.colorPicker.isAvailable(in: defaults)
        case .files: return AppFeature.shelf.isAvailable(in: defaults)
        case .scratchpad: return AppFeature.scratchpad.isAvailable(in: defaults)
        case .agents: return AppFeature.notchAgents.isAvailable(in: defaults)
        case .watch: return AppFeature.notchWatch.isAvailable(in: defaults)
        case .system:
            return [.monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork,
                    .monitorDisk, .monitorPower, .fanControl].contains { (feature: AppFeature) in
                feature.isAvailable(in: defaults)
            }
        }
    }
}

extension NotchModule {
    package func title(_ language: AppLanguage) -> String {
        switch self {
        case .timer: return FeatureStrings.notchActivities(language).timer
        case .camera: return FeatureStrings.notchActivities(language).camera
        case .notifications: return FeatureStrings.notchNotifications(language).title
        case .downloads: return FeatureStrings.notchFiles(language).downloadsTitle
        case .calendar: return FeatureStrings.notchCalendar(language).title
        case .controls: return FeatureStrings.notch(language).controls
        case .mixer: return Strings.localized(language).mixerSection
        case .music: return FeatureStrings.radialMenu(language).mediaNowPlaying
        case .clipboard: return FeatureStrings.clipboard(language).title
        case .captures: return FeatureStrings.recentCaptures(language).title
        case .files: return FeatureStrings.notch(language).files
        case .system: return FeatureStrings.notch(language).system
        case .tools: return FeatureStrings.notch(language).tools
        case .scratchpad: return FeatureStrings.scratchpad(language).pageTitle
        case .agents: return FeatureStrings.notchAgents(language).title
        case .watch: return FeatureStrings.notchWatch(language).title
        }
    }
}

package enum NotchReopeningDestination: String, CaseIterable {
    case appPanel, explore
}

/// ⌘1 to ⌘9 on the island's clipboard page paste the entry at that place in
/// the visible list, as in the quick panel.
package struct NotchClipboardPastePress: Equatable {
    package let serial: Int
    package let index: Int

    /// The digit row by physical key, so every layout keeps the shortcut.
    package static func index(keyCode: UInt16, commandOnly: Bool) -> Int? {
        guard commandOnly else { return nil }
        let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        return digitKeys.firstIndex(of: keyCode)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(serial: Int, index: Int) {
        self.serial = serial
        self.index = index
    }
}

package enum NotchDisplay: String, CaseIterable {
    /// `pointer` moves the closed island to the display the pointer is on.
    /// `all` does too, and every other display shows the closed island.
    case automatic, builtIn, main, pointer, all
}

/// How the island meets the top of a display without a camera housing: a
/// capsule floating in the menu bar, as on the phone, or a cutout hanging
/// from the top edge. A physical camera always keeps the cutout it covers.
package enum NotchSilhouette: String, CaseIterable {
    case capsule, notch

    package static func current(in defaults: UserDefaults = .standard) -> NotchSilhouette {
        NotchSilhouette(rawValue: defaults.string(forKey: DefaultsKey.notchSilhouette) ?? "") ?? .capsule
    }
}

package enum NotchSize: String, CaseIterable {
    case compact, spacious, custom

    package static let widthRange = 360.0...600.0
    package static let heightRange = 260.0...640.0
    package static let defaultWidth = 440.0
    package static let defaultHeight = 480.0

    package static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

/// A correction to the camera housing macOS reports. The report is rounded
/// to points while the cutout follows the panel's own pixels, so on some Macs
/// and resolutions an edge of the real notch can show past the island.
package struct NotchCameraFit: Equatable {
    package static let widthRange = -10.0...10.0
    package static let heightRange = -6.0...6.0
    package static let zero = NotchCameraFit(width: 0, height: 0)

    package let width: CGFloat
    package let height: CGFloat

    /// Whole points keep the island centred on the camera's pixels, and half
    /// points are whole pixels on the notched panels; a value written by hand
    /// is brought back to those steps.
    package init(width: Double, height: Double) {
        self.width = NotchSize.clamped(width, to: Self.widthRange, fallback: 0).rounded()
        self.height = (NotchSize.clamped(height, to: Self.heightRange, fallback: 0) * 2).rounded() / 2
    }

    package static func current(in defaults: UserDefaults = .standard) -> NotchCameraFit {
        NotchCameraFit(width: defaults.double(forKey: DefaultsKey.notchCameraFitWidth),
                       height: defaults.double(forKey: DefaultsKey.notchCameraFitHeight))
    }
}

/// A capsule sized and placed by hand. By itself it takes the height of the
/// menu bar around it; a fit makes it wider or narrower at rest, taller or
/// shorter from its top edge, and lowers it from the top of the display.
package struct NotchCapsuleFit: Equatable {
    package static let widthRange = -40.0...80.0
    package static let heightRange = -4.0...12.0
    package static let dropRange = 0.0...20.0
    package static let zero = NotchCapsuleFit(width: 0, height: 0, drop: 0)

    package let width: CGFloat
    package let height: CGFloat
    package let drop: CGFloat

    /// Whole points keep the capsule's edges on pixels, and even widths keep
    /// it centred; a value written by hand is brought back to those steps.
    package init(width: Double, height: Double, drop: Double) {
        self.width = (NotchSize.clamped(width, to: Self.widthRange, fallback: 0) / 2).rounded() * 2
        self.height = NotchSize.clamped(height, to: Self.heightRange, fallback: 0).rounded()
        self.drop = NotchSize.clamped(drop, to: Self.dropRange, fallback: 0).rounded()
    }

    package static func current(in defaults: UserDefaults = .standard) -> NotchCapsuleFit {
        NotchCapsuleFit(width: defaults.double(forKey: DefaultsKey.notchCapsuleFitWidth),
                        height: defaults.double(forKey: DefaultsKey.notchCapsuleFitHeight),
                        drop: defaults.double(forKey: DefaultsKey.notchCapsuleFitDrop))
    }
}

/// Shared measurements keep the window's content budget and its SwiftUI
/// layout in agreement, including small screens and custom sizes.
package enum NotchLayout {
    package static let shoulder: CGFloat = 14
    package static let horizontalInset: CGFloat = 28
    package static let headerHeight: CGFloat = 36
    // NSFont is immutable once made, so any thread may share these.
    /// The open header's title, and a detail's beside its back button. The
    /// island is laid out from their widths and the header draws them.
    nonisolated(unsafe) package static let headerTitleFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
    nonisolated(unsafe) package static let detailTitleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    /// The island reads its geometry many times on every layout, so each
    /// title is measured once per font. The island lays out on the main
    /// thread, the only one that touches this.
    nonisolated(unsafe) private static var measuredHeaderTitles: [String: CGFloat] = [:]
    /// A header title as wide as drawn, after the icon button and the
    /// spacing that may lead it.
    package static func headerTitleWidth(_ title: String, font: NSFont = headerTitleFont, button: Bool) -> CGFloat {
        let key = "\(font.fontName) \(font.pointSize) \(title)"
        let width = measuredHeaderTitles[key] ?? (title as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        measuredHeaderTitles[key] = width
        return width + (button ? iconButtonSide + headerButtonSpacing : 0)
    }
    package static let navigationHeight: CGFloat = 36
    /// The narrowest compact wing that shows an activity's mark, and the
    /// narrowest that shows its reading; a narrower wing leaves them out.
    package static let compactMarkWing: CGFloat = 28
    package static let compactReadingWing: CGFloat = 42
    /// The room the island keeps to the display's sides, both together, and
    /// below its tallest page.
    package static let displaySideMargins: CGFloat = 24
    package static let displayBottomMargin: CGFloat = 48
    /// The header's square icon buttons, and the space between one and the
    /// title or button beside it.
    package static let iconButtonSide: CGFloat = 28
    package static let headerButtonSpacing: CGFloat = 6
    /// The room a scrolling page keeps below its last row.
    package static let scrollBottomPadding: CGFloat = 4
    /// Each side of the capture controls folded around the camera: the tool
    /// on one, the chevron on the other.
    package static let captureCollapsedSide: CGFloat = 28
    /// The drop hint shown while a file is dragged to the island, and the
    /// room below it.
    package static let dropHintHeight: CGFloat = 52
    package static let dropHintBottomGap: CGFloat = 14
    package static let spacing: CGFloat = 12
    package static let bottomInset: CGFloat = 16
    package static var chromeHeight: CGFloat { headerHeight + spacing + bottomInset }
    /// The island stays a wide strip: pages scroll within the preset's budget.
    package static let compactContentHeight: CGFloat = 180
    package static let spaciousContentHeight: CGFloat = 264
    /// Surfaces that are vertical by nature (the embedded app panel, a metric
    /// detail, a hosted utility) still get a readable page inside a preset.
    package static let pageContentHeight: CGFloat = 320
    package static let rowSpacing: CGFloat = 10
    package static let cardHeight: CGFloat = 96
    package static let minimumCardHeight: CGFloat = 68
    package static let shortcutHeight: CGFloat = 74
    package static let shortcutWidth: CGFloat = 76
    package static let shortcutSpacing: CGFloat = 8
    package static let systemCardHeight: CGFloat = 72
    package static let systemCardWidth: CGFloat = 128
    /// Leave room for the card's hover scale, including a single full-width card.
    package static func systemHoverInset(width: CGFloat) -> CGFloat { ceil(max(0, width) * 0.015) + 1 }
    package static let toolHeight: CGFloat = 72
    package static let toolWidth: CGFloat = 76
    package static let toolSpacing: CGFloat = 6
    /// Three rows fit the gallery's page; two still fill a compact strip.
    package static let sectionTileHeight: CGFloat = 86
    package static let sectionTileWidth: CGFloat = 92
    package static let sectionSpacing: CGFloat = 8
    /// The gallery's row indicator beside the tiles, with its gap.
    package static let sectionIndicatorWidth: CGFloat = 12
    package static let clipboardSearchHeight: CGFloat = 36
    package static let clipboardCardHeight: CGFloat = 104
    package static let emptyHeight: CGFloat = 140
    package static let musicControlsRowHeight: CGFloat = 32
    package static let musicIdleHeight: CGFloat = 84
    package static let timerTopRowHeight: CGFloat = 36
    package static let timerRowSpacing: CGFloat = 8
    /// The Pomodoro's breaks and sessions as one line of readouts under the ruler.
    package static let timerSettingsRowHeight: CGFloat = 28
    package static let timerRulerHeight: CGFloat = 82
    package static let timerMinimumRulerHeight: CGFloat = 56
    package static let timerStartHeight: CGFloat = 36
    /// From this width the start button shares the mode row in every
    /// language; below it the button takes a row of its own.
    package static let timerWideWidth: CGFloat = 400
    /// The month grid a short island opens over its week strip: a header
    /// row, the weekday line and six rows sharing what is left.
    package static let calendarMonthHeaderHeight: CGFloat = 28
    package static let calendarMonthWeekdayHeight: CGFloat = 14
    package static let calendarMonthSpacing: CGFloat = 4
    package static var calendarMonthMinimumHeight: CGFloat {
        calendarMonthHeaderHeight + calendarMonthWeekdayHeight + calendarMonthSpacing * 2 + 6 * 16
    }
    package static func calendarMonthRowHeight(height: CGFloat) -> CGFloat {
        let room = height - calendarMonthHeaderHeight - calendarMonthWeekdayHeight - calendarMonthSpacing * 2
        return min(30, max(16, (room / 6).rounded(.down)))
    }

    /// The preview fills the page. A wide strip crops the camera to 16:9 and a
    /// narrow, tall island to 4:3, so a face stays in frame on either.
    package static func cameraPreviewSize(in size: CGSize) -> CGSize {
        let width = max(0, size.width), height = max(0, size.height)
        return CGSize(width: min(width, height * 16 / 9), height: min(height, width * 3 / 4))
    }
    /// Breathing room every compact strip keeps from its silhouette.
    package static let compactEdgeGap: CGFloat = 5
    /// The compact player's equalizer, spaced by its own bar width.
    package static let compactMusicBarCount = 7
    package static let compactMusicBarWidth: CGFloat = 1.8
    package static var compactMusicBarsWidth: CGFloat {
        compactMusicBarWidth * (CGFloat(compactMusicBarCount) + CGFloat(compactMusicBarCount - 1) * 0.85)
    }
    /// Corners of a surface of this height. A strip as tall as the camera
    /// keeps the cutout's own corners, so the closed island and the last
    /// frames of a collapse sit inside the notch instead of outlining a
    /// rounder one; the open island reaches the full radius and shoulder.
    package static func surfaceRadius(height: CGFloat) -> CGFloat { min(28, height * 0.34) }
    package static func shoulder(height: CGFloat) -> CGFloat { min(shoulder, height * 0.19) }
    /// The optional outline's stroke. Only its inner half, inside the island, shows.
    package static let outlineWidth: CGFloat = 2

    // MARK: Capsule
    // Without a camera the island can float in the menu bar as a capsule.
    // Open, it keeps the hanging island's sizes, so its window, hover, pages
    // and floating controls stay where they are. Closed, its strips run from
    // end to end, as NotchCapsuleLayout measures them.

    /// The menu bar a capsule leaves above and below itself on a standard bar.
    package static let capsuleMargin: CGFloat = 2

    /// A shorter bar leaves less, so the capsule is 20 points tall on a
    /// standard bar and on a display whose bar is hidden.
    package static func capsuleGap(barHeight: CGFloat) -> CGFloat {
        guard barHeight.isFinite else { return 0 }
        return min(capsuleMargin, max(0, ((barHeight - 20) / 2).rounded(.down)))
    }

    /// A closed capsule is round at its ends; an open one keeps the island's corners.
    package static func capsuleRadius(height: CGFloat) -> CGFloat { min(max(0, height) / 2, 28) }

    /// The bare capsule at rest is shorter than the gap between an
    /// activity's wings, closer to the phone's proportions.
    package static let capsuleRestingAspect: CGFloat = 5

    /// The capsule of a surface `rect` in size: `gap` inside its top and
    /// bottom, and as wide as the hanging island's body between its
    /// shoulders, which content and floating controls are laid out around.
    package static func capsuleBody(in rect: CGRect, gap: CGFloat) -> CGRect {
        let width = max(0, rect.width), height = max(0, rect.height)
        let side = min(shoulder(height: height), width / 2)
        let inset = min(max(0, gap), height / 2)
        return CGRect(x: rect.minX + side, y: rect.minY + inset,
                      width: width - side * 2, height: height - inset * 2)
    }

    /// The surface a capsule was drawn for, from the bounds it was drawn in,
    /// so a resize starts from the size on screen.
    package static func capsuleSurface(ofBody body: CGRect, gap: CGFloat) -> CGSize {
        let height = body.height > 0 ? body.maxY + max(0, gap) : body.minY * 2
        return CGSize(width: body.width + shoulder(height: height) * 2, height: max(0, height))
    }

    /// The capsule outline. Every size, down to a line, has the same elements,
    /// so any two frames of a resize blend, and circular corners make a
    /// strip's ends true half circles that its content can be measured from.
    package static func capsulePath(in rect: CGRect, gap: CGFloat) -> CGPath {
        let body = capsuleBody(in: rect, gap: gap)
        let corner = min(capsuleRadius(height: body.height), body.width / 2)
        let handle = corner * (1 - 0.55228475)
        let (left, right, top, bottom) = (body.minX, body.maxX, body.minY, body.maxY)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + corner, y: top))
        path.addLine(to: CGPoint(x: right - corner, y: top))
        path.addCurve(to: CGPoint(x: right, y: top + corner), control1: CGPoint(x: right - handle, y: top),
                      control2: CGPoint(x: right, y: top + handle))
        path.addLine(to: CGPoint(x: right, y: bottom - corner))
        path.addCurve(to: CGPoint(x: right - corner, y: bottom), control1: CGPoint(x: right, y: bottom - handle),
                      control2: CGPoint(x: right - handle, y: bottom))
        path.addLine(to: CGPoint(x: left + corner, y: bottom))
        path.addCurve(to: CGPoint(x: left, y: bottom - corner), control1: CGPoint(x: left + handle, y: bottom),
                      control2: CGPoint(x: left, y: bottom - handle))
        path.addLine(to: CGPoint(x: left, y: top + corner))
        path.addCurve(to: CGPoint(x: left + corner, y: top), control1: CGPoint(x: left, y: top + handle),
                      control2: CGPoint(x: left + handle, y: top))
        path.closeSubpath()
        return path
    }

    /// Content clearance under a camera of the usual height.
    package static let nominalContentTop: CGFloat = 42

    package static func preferredWidth(_ layout: NotchSize, custom: CGFloat) -> CGFloat {
        switch layout {
        case .compact: return 480
        case .spacious: return 560
        case .custom: return custom
        }
    }

    /// The island as a preset presents it on a display whose camera leaves
    /// the usual clearance; custom keeps the chosen height.
    package static func nominalHeight(_ layout: NotchSize, custom: CGFloat) -> CGFloat {
        switch layout {
        case .compact: return nominalContentTop + chromeHeight + compactContentHeight
        case .spacious: return nominalContentTop + chromeHeight + spaciousContentHeight
        case .custom: return custom
        }
    }

    /// Balance complete rows across the available width, keeping reading order
    /// left to right and allowing each row to fill its width without empty cells.
    package static func systemRowRanges(count: Int, width: CGFloat) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let columns = railCapacity(width: width, itemWidth: systemCardWidth, spacing: rowSpacing)
        let rows = (count + columns - 1) / columns
        let base = count / rows
        let remainder = count % rows
        return (0..<rows).map { row in
            let start = row * base + min(row, remainder)
            return start..<(start + base + (row < remainder ? 1 : 0))
        }
    }

    // MARK: Rails
    // Items fill the rows a height allows and continue sideways. Every page
    // and the geometry that sizes it share these three functions, so the
    // window never reserves a row the page cannot draw.

    package static func railCapacity(width: CGFloat, itemWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width.isFinite, itemWidth > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (itemWidth + spacing)).rounded(.down)))
    }

    package static func railRows(count: Int, perRow: Int, rowHeight: CGFloat, spacing: CGFloat, height: CGFloat) -> Int {
        let capacity = max(1, perRow)
        let needed = max(1, (max(0, count) + capacity - 1) / capacity)
        guard rowHeight > 0 else { return 1 }
        guard height.isFinite else { return height > 0 ? needed : 1 }
        let fitting = max(1, Int(((height + spacing) / (rowHeight + spacing)).rounded(.down)))
        return min(needed, fitting)
    }

    /// The System page's grid of `count` cards across `width`, with the room
    /// its hover effect keeps around it.
    package static func systemGridHeight(count: Int, width: CGFloat) -> CGFloat {
        let inset = systemHoverInset(width: width)
        let rows = systemRowRanges(count: count, width: width - inset * 2).count
        return railHeight(rows: rows, rowHeight: systemCardHeight, spacing: rowSpacing) + inset * 2
    }

    package static func railHeight(rows: Int, rowHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        CGFloat(max(1, rows)) * rowHeight + CGFloat(max(0, rows - 1)) * spacing
    }

    /// The columns a rail spreads its items over. A rail whose columns all
    /// fit lays the items out in reading order, this many per row, and
    /// centers a short last row; one that scrolls fills its columns instead.
    package static func railColumns(count: Int, rows: Int) -> Int {
        (max(0, count) + max(1, rows) - 1) / max(1, rows)
    }

    package static func railFits(columns: Int, itemWidth: CGFloat, spacing: CGFloat, width: CGFloat) -> Bool {
        CGFloat(columns) * itemWidth + CGFloat(max(0, columns - 1)) * spacing <= width
    }

    /// The home page's music card: its padding, which also sets the artwork
    /// in from the card's top and bottom, and the gap beside the artwork.
    package static let musicCardPadding: CGFloat = 12
    package static let musicCardSpacing: CGFloat = 12
    /// The three compact transport buttons.
    package static let musicCardTransportWidth: CGFloat = 120

    /// The card's square artwork, never smaller than 40pt.
    package static func musicCardArtworkSide(height: CGFloat) -> CGFloat {
        max(40, height - musicCardPadding * 2)
    }

    /// Square artwork, its gap, the three compact transport buttons, and
    /// horizontal padding. Track titles truncate within the remaining space.
    package static func musicCardMinimumWidth(height: CGFloat) -> CGFloat {
        musicCardArtworkSide(height: height) + musicCardSpacing + musicCardTransportWidth + musicCardPadding * 2
    }

    /// The home page: one row of cards (playback and levels) over a rail of
    /// shortcuts. A tight budget shortens the cards before it drops a row.
    package static func controls(hasCards: Bool, shortcutCount: Int, width: CGFloat, height: CGFloat) -> NotchControlsLayout {
        guard hasCards || shortcutCount > 0 else { return NotchControlsLayout(cardRow: 0, shortcutRows: 0) }
        var rows = 0
        if shortcutCount > 0 {
            let remaining = hasCards ? height - minimumCardHeight - rowSpacing : height
            rows = railRows(count: shortcutCount,
                            perRow: railCapacity(width: width, itemWidth: shortcutWidth, spacing: shortcutSpacing),
                            rowHeight: shortcutHeight, spacing: shortcutSpacing, height: remaining)
        }
        let rail = rows > 0 ? railHeight(rows: rows, rowHeight: shortcutHeight, spacing: shortcutSpacing) + rowSpacing : 0
        let cardRow = hasCards ? min(cardHeight, max(minimumCardHeight, height - rail)) : 0
        return NotchControlsLayout(cardRow: cardRow, shortcutRows: rows)
    }

    /// A running timer: its row of controls and reading, and for the
    /// Pomodoro the line of progress below it, with the room that line keeps.
    package static let timerActiveRowHeight: CGFloat = 96
    package static let timerActiveLineSpacing: CGFloat = 4
    package static let timerActiveProgressHeight: CGFloat = 18
    package static func timerActiveHeight(mode: NotchTimerMode) -> CGFloat {
        mode == .pomodoro ? timerActiveRowHeight + timerActiveLineSpacing + timerActiveProgressHeight
            : timerActiveRowHeight
    }

    /// Setup is the mode row over the ruler's row, the same for every
    /// mode: the timer and the Pomodoro's focus on the ruler, the stopwatch's
    /// clock alone in it. The Pomodoro adds a line of readouts; a narrow
    /// island gives Start the last row, which those readouts share, and lets
    /// the ruler give up height before anything is cut.
    package static func timer(mode: NotchTimerMode, hasSession: Bool, width: CGFloat, height: CGFloat) -> CGFloat {
        if hasSession { return timerActiveHeight(mode: mode) }
        let top = timerTopRowHeight + timerRowSpacing
        return top + timerRulerHeight(mode: mode, width: width, height: height)
            + timerBottomRowHeight(mode: mode, width: width)
    }

    /// The row under the ruler, with its spacing: Start on a narrow island,
    /// the Pomodoro's readouts on a wide one, nothing otherwise.
    package static func timerBottomRowHeight(mode: NotchTimerMode, width: CGFloat) -> CGFloat {
        if width < timerWideWidth { return timerRowSpacing + timerStartHeight }
        return mode == .pomodoro ? timerRowSpacing + timerSettingsRowHeight : 0
    }

    package static func timerRulerHeight(mode: NotchTimerMode = .timer, width: CGFloat, height: CGFloat) -> CGFloat {
        let below = timerBottomRowHeight(mode: mode, width: width)
        guard below > 0 else { return timerRulerHeight }
        let room = height - timerTopRowHeight - timerRowSpacing - below
        return min(timerRulerHeight, max(timerMinimumRulerHeight, room))
    }

    /// The player row keeps the artwork square; the controls row below holds
    /// volume and the lyrics or queue toggles.
    package static func musicPlayerHeight(layout: NotchSize, height: CGFloat) -> CGFloat {
        min(layout == .spacious ? 148 : 120, max(musicPlayerMinimumHeight, height - musicControlsRowHeight - rowSpacing))
    }

    /// The lyrics and queue cards: their padding, the space below their
    /// title row, and that row.
    package static let musicExtraPadding: CGFloat = 12
    package static let musicExtraSpacing: CGFloat = 10
    package static let musicExtraTitleHeight: CGFloat = 18

    /// The room a lyrics or queue card `height` tall leaves for its list.
    package static func musicExtraListHeight(_ height: CGFloat) -> CGFloat {
        height - musicExtraPadding * 2 - musicExtraSpacing - musicExtraTitleHeight
    }

    /// The smallest player the music page draws. Lyrics or the queue take
    /// its place where the page cannot hold both.
    package static let musicPlayerMinimumHeight: CGFloat = 88

    /// The room the music page's row of controls takes with its spacing.
    package static func musicControlsRow(_ hasRow: Bool) -> CGFloat {
        hasRow ? musicControlsRowHeight + rowSpacing : 0
    }

    /// The player, or the idle message when nothing plays, on a page
    /// `height` tall.
    package static func musicMainHeight(hasPlayback: Bool, layout: NotchSize, height: CGFloat) -> CGFloat {
        hasPlayback ? musicPlayerHeight(layout: layout, height: height) : musicIdleHeight
    }
}

package struct NotchControlsLayout: Equatable {
    package let cardRow: CGFloat
    package let shortcutRows: Int

    package var height: CGFloat {
        let rail = shortcutRows > 0
            ? NotchLayout.railHeight(rows: shortcutRows, rowHeight: NotchLayout.shortcutHeight, spacing: NotchLayout.shortcutSpacing) : 0
        return cardRow + (cardRow > 0 && shortcutRows > 0 ? NotchLayout.rowSpacing : 0) + rail
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(cardRow: CGFloat, shortcutRows: Int) {
        self.cardRow = cardRow
        self.shortcutRows = shortcutRows
    }
}

package enum NotchIdleContent: String, CaseIterable {
    case none, battery, music, agents
}

/// Resizing can send hover exits and entries without any pointer movement.
package struct NotchHoverState {
    package private(set) var suppressed = false

    package mutating func close(pointerInside: Bool) { suppressed = pointerInside }
    package mutating func open() { suppressed = false }
    package mutating func update(pointerInside: Bool) {
        if !pointerInside { suppressed = false }
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(suppressed: Bool = false) {
        self.suppressed = suppressed
    }
}

package enum NotchHoverEmphasis {
    package static func size(from resting: CGSize, geometry: NotchGeometry) -> CGSize {
        // Keep the pulse inside the measured free menu-bar space on each side.
        let occupiedWing = max(0, (resting.width - geometry.cameraWidth) / 2)
        let freeSide = max(0, (geometry.compactSideRoom ?? 0) - occupiedWing)
        let growth = min(10, freeSide)
        // A capsule stretches along the bar and stays inside it.
        return CGSize(width: resting.width + growth * 2, height: resting.height + (geometry.floats ? 0 : 5))
    }
}

package enum NotchCompactActivity: String, Identifiable {
    case timer, watch, downloads, agents, calendar, music, keepAwake

    package var id: String { rawValue }

    package func title(_ language: AppLanguage) -> String {
        switch self {
        case .timer: return FeatureStrings.notchActivities(language).timer
        case .watch: return FeatureStrings.notchWatch(language).title
        case .downloads: return FeatureStrings.notchFiles(language).downloadsTitle
        case .agents: return FeatureStrings.notchAgents(language).title
        case .calendar: return FeatureStrings.notchCalendar(language).title
        case .music: return FeatureStrings.notch(language).music
        case .keepAwake: return Strings.localized(language).keepAwakeTitle
        }
    }

    /// Keep Awake has no page of its own: its tile is on Controls.
    package var module: NotchModule {
        switch self {
        case .timer: return .timer
        case .watch: return .watch
        case .downloads: return .downloads
        case .agents: return .agents
        case .calendar: return .calendar
        case .music: return .music
        case .keepAwake: return .controls
        }
    }

    package var symbol: String {
        self == .keepAwake ? NotchControlItem.keepAwake.symbol : module.symbol
    }
}

/// Two activities sharing the closed island: the primary keeps its reading
/// right of the camera and the companion's mark takes the left.
package struct NotchActivityCombination: Hashable, Identifiable {
    package let primary: NotchCompactActivity
    package let companion: NotchCompactActivity

    package var id: String { primary.rawValue + "+" + companion.rawValue }

    /// Named in the order the island shows them, left to right.
    package func title(_ language: AppLanguage) -> String {
        companion.title(language) + " + " + primary.title(language)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(primary: NotchCompactActivity, companion: NotchCompactActivity) {
        self.primary = primary
        self.companion = companion
    }
}

/// The closed island on a display it is not on, when it shows on every
/// display: that display's geometry, and what the island shows closed at
/// the size it takes there. The service updates it as the island changes.
package final class NotchMirrorModel: ObservableObject {
    @Published package private(set) var geometry: NotchGeometry
    /// A strip beside a camera has its own geometry around it, as the island's does.
    @Published package private(set) var strip: NotchGeometry
    @Published package private(set) var size: CGSize
    @Published package private(set) var activity: NotchCompactActivity?
    package var shown = false
    /// The outline last drawn around it, and whether a timer's color tinted it.
    package var outline: Bool?
    package var timerOutline = false

    package init(geometry: NotchGeometry, size: CGSize) {
        self.geometry = geometry
        strip = geometry
        self.size = size
    }

    /// Whether anything it draws changed, so a copy is only resized when it did.
    package func update(geometry: NotchGeometry, strip: NotchGeometry, size: CGSize, activity: NotchCompactActivity?) -> Bool {
        guard self.geometry != geometry || self.strip != strip || self.size != size || self.activity != activity else {
            return false
        }
        self.geometry = geometry
        self.strip = strip
        self.size = size
        self.activity = activity
        return true
    }
}

/// A choice outlives the gaps in what was chosen, such as a song changing
/// or an agent between turns: the island shows the next activity meanwhile
/// and returns to the chosen one. It ends when nothing is left to show, so
/// work returning later starts from the automatic order again.
package struct NotchActivitySelection {
    package private(set) var preferred: NotchCompactActivity?
    package private(set) var companion: NotchCompactActivity?

    /// `companions` are the pairs `activity` supports now.
    package mutating func select(_ activity: NotchCompactActivity, companion: NotchCompactActivity? = nil,
                         available: [NotchCompactActivity], companions: [NotchCompactActivity] = []) {
        guard available.contains(activity) else { return }
        if let companion, !companions.contains(companion) { return }
        preferred = activity
        self.companion = companion
    }

    package mutating func reconcile(available: [NotchCompactActivity]) {
        guard available.isEmpty else { return }
        preferred = nil
        companion = nil
    }

    /// The chosen pair's companion while it is there to pair with.
    /// `companions` are the pairs the preferred activity supports now.
    package func companion(available companions: [NotchCompactActivity]) -> NotchCompactActivity? {
        guard preferred != nil, let companion, companions.contains(companion) else { return nil }
        return companion
    }

    package func current(available: [NotchCompactActivity]) -> NotchCompactActivity? {
        if let preferred, available.contains(preferred) { return preferred }
        return available.first
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(preferred: NotchCompactActivity? = nil, companion: NotchCompactActivity? = nil) {
        self.preferred = preferred
        self.companion = companion
    }
}

/// A floating capsule has no camera inside it, so its closed content runs in
/// one row from end to end, and the capsule is as wide as that row needs:
/// never shorter than the bare capsule, never wider than its kind allows or
/// than the menu bar leaves free. The views draw with these same measures.
package enum NotchCapsuleLayout {
    /// From the capsule's round end to its first and last content.
    package static let endPadding: CGFloat = 8
    /// Between a mark and its text.
    package static let spacing: CGFloat = 6
    /// Between a title and its detail, or between two groups.
    package static let groupSpacing: CGFloat = 10
    /// A symbol's slot, as wide as the widest symbol draws at its size.
    package static let symbolSize: CGFloat = 12
    package static let symbolWidth: CGFloat = 16
    package static let meterWidth: CGFloat = 56
    package static let meterHeight: CGFloat = 4
    /// The equalizer's bars, as the music strip draws them.
    package static var barsWidth: CGFloat { NotchLayout.compactMusicBarsWidth }
    /// SwiftUI can draw a line a little wider than AppKit measures it.
    package static let air: CGFloat = 2
    /// Between the pieces of one mark, such as an arrow and its percentage.
    package static let markSpacing: CGFloat = 4
    package static let calendarDotSide: CGFloat = 6
    package static let downloadMeterWidth: CGFloat = 36
    /// A progress indicator waiting for a download's size.
    package static let spinnerWidth: CGFloat = 16
    // NSFont is immutable once made, so any thread may share these.
    nonisolated(unsafe) package static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    nonisolated(unsafe) package static let detailFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    /// A level's reading, with digits of one width, so it never jitters.
    nonisolated(unsafe) package static let levelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    nonisolated(unsafe) package static let readingFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    nonisolated(unsafe) package static let smallFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    /// The widest each kind of strip grows, in points of capsule.
    package enum Maximum {
        package static let notification: CGFloat = 380
        package static let notice: CGFloat = 340
        package static let music: CGFloat = 260
        package static let calendar: CGFloat = 300
        package static let download: CGFloat = 280
        package static let activity: CGFloat = 220
    }

    package static func width(_ text: String, font: NSFont) -> CGFloat {
        text.isEmpty ? 0 : (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + air
    }

    /// The island lays out on the main thread, the only one that touches this.
    nonisolated(unsafe) private static var symbolDrops: [String: CGFloat] = [:]

    /// How far a symbol's ink sits below the middle of its frame. SF Symbols
    /// hang low in their frames, a circle almost half a point, so centred by
    /// frame a timer looked a pixel low beside its centred digits. Measured
    /// once per symbol, from its own drawing.
    package static func symbolDrop(_ name: String, size: CGFloat = symbolSize, weight: NSFont.Weight = .medium) -> CGFloat {
        let key = "\(name) \(size) \(weight.rawValue)"
        if let drop = symbolDrops[key] { return drop }
        let drop = measuredSymbolDrop(name, size: size, weight: weight)
        symbolDrops[key] = drop
        return drop
    }

    private static func measuredSymbolDrop(_ name: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let scale: CGFloat = 4
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight)),
              image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((image.size.width * scale).rounded(.up)),
                                         pixelsHigh: Int((image.size.height * scale).rounded(.up)),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32) else { return 0 }
        // In points before the context exists, so the drawing fills the pixels.
        rep.size = image.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return 0 }
        // Rows run from the top; a pixel counts once it is about a third inked.
        var top: Int?, bottom = 0
        for y in 0..<rep.pixelsHigh {
            let row = data + y * rep.bytesPerRow
            if (0..<rep.pixelsWide).contains(where: { row[$0 * 4 + 3] > 80 }) { top = top ?? y; bottom = y + 1 }
        }
        guard let top else { return 0 }
        return CGFloat(top + bottom) / 2 / scale - image.size.height / 2
    }

    /// A cover sits in the capsule's round end, concentric with it.
    package static func artworkSide(_ geometry: NotchGeometry) -> CGFloat { max(0, geometry.stripBodyHeight - 6) }
    package static func artworkInset(_ geometry: NotchGeometry) -> CGFloat { (geometry.stripBodyHeight - artworkSide(geometry)) / 2 }

    /// The capsule's side within its surface, as `capsuleBody` places it.
    package static func side(_ geometry: NotchGeometry) -> CGFloat { NotchLayout.shoulder(height: geometry.stripHeight) }

    /// The widest surface the bar leaves: the display less its margins, and
    /// the menus' free space on both sides of the capsule's middle.
    package static func availableWidth(_ geometry: NotchGeometry) -> CGFloat {
        let room = geometry.compactSideRoom ?? 0
        return max(0, min(geometry.maximumSurfaceWidth, geometry.cameraWidth + 2 * (room.isFinite ? max(0, room) : 0)))
    }

    /// The surface around a row `content` wide between `leading` and
    /// `trailing` insets from the capsule's ends, on whole points like the
    /// window around it.
    package static func surface(content: CGFloat, leading: CGFloat = endPadding, trailing: CGFloat = endPadding,
                        maximum: CGFloat, geometry: NotchGeometry) -> CGSize {
        let side = side(geometry)
        let resting = geometry.restingSize(showsContent: false).width
        let limit = max(resting, min(maximum + side * 2, availableWidth(geometry)).rounded(.down))
        let wanted = (max(0, content.isFinite ? content : 0) + leading + trailing + side * 2).rounded(.up)
        return CGSize(width: min(limit, max(resting, wanted)), height: geometry.stripHeight)
    }

    package static func barsHeight(_ geometry: NotchGeometry) -> CGFloat { min(16, max(6, geometry.stripBodyHeight - 8)) }

    /// Two working agents share a smaller mark, each in a frame wider than it.
    package static func agentMarkSize(working: Int) -> CGFloat { working > 1 ? 10 : 12 }
    package static func agentMarksWidth(working: Int) -> CGFloat {
        NotchAgentSupport.marksWidth(size: agentMarkSize(working: working), count: working)
    }

    /// A level's reading keeps the room of its widest value, so its meter
    /// stays put while the value changes.
    package static func levelReadingWidth(_ detail: String) -> CGFloat {
        max(width(detail, font: levelFont), width("100%", font: levelFont))
    }

    package static func downloadPercentWidth(_ language: AppLanguage) -> CGFloat {
        width((1.0).formatted(NotchDownloadSupport.percentFormat(language)), font: smallFont)
    }

    package static func calendarTitle(_ countdown: NotchCalendarCountdown, language: AppLanguage) -> String {
        let title = countdown.event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? FeatureStrings.notchCalendar(language).untitled : title
    }

    /// The row a notice reads in: its mark, its title and its detail, or a
    /// level's mark, meter and reading.
    package static func noticeContent(title: String, detail: String, level: Bool) -> CGFloat {
        if level { return symbolWidth + spacing + meterWidth + spacing + levelReadingWidth(detail) }
        let detailWidth = width(detail, font: detailFont)
        return symbolWidth + spacing + width(title, font: titleFont) + (detailWidth > 0 ? groupSpacing + detailWidth : 0)
    }

    /// A mirrored banner: the app's icon, the sender and the message.
    package static func notificationContent(title: String, message: String, geometry: NotchGeometry) -> CGFloat {
        let messageWidth = width(message, font: detailFont)
        return notificationIconSide(geometry) + spacing + width(title, font: titleFont)
            + (messageWidth > 0 ? groupSpacing + messageWidth : 0)
    }

    package static func notificationIconSide(_ geometry: NotchGeometry) -> CGFloat { min(16, max(0, geometry.stripBodyHeight - 4)) }

    /// Playing music: the cover in the round end, the title and the bars.
    /// Without a title, only the cover and the bars, at the capsule's ends.
    package static func musicSurface(title: String?, geometry: NotchGeometry) -> CGSize {
        let named = title.map { endPadding + width($0, font: titleFont) + endPadding } ?? endPadding
        let content = artworkSide(geometry) + named + barsWidth
        return surface(content: content, leading: artworkInset(geometry), maximum: Maximum.music, geometry: geometry)
    }

    /// A timer's mark, or the mark of what shares the capsule with a timer
    /// or an event: a download's arrow and percentage, the working agents,
    /// the cover or the event's dot and countdown.
    package static func timerMarkWidth(companion: NotchCompactActivity?, workingAgents: Int, downloadPercent: Bool,
                               geometry: NotchGeometry, language: AppLanguage) -> CGFloat {
        switch companion {
        case .downloads:
            return symbolWidth + (downloadPercent ? markSpacing + downloadPercentWidth(language) : 0)
        case .agents: return agentMarksWidth(working: workingAgents)
        case .music: return artworkSide(geometry)
        case .calendar: return calendarClockWidth
        default: return symbolWidth
        }
    }

    /// An event's dot and its countdown at its widest, as a pair shows it.
    package static var calendarClockWidth: CGFloat { calendarDotSide + markSpacing + width("00:00", font: readingFont) }

    /// Between a mark and the reading beside it; an event's countdown is a
    /// group of its own, so a pair with one keeps two clocks apart.
    package static func markGap(_ companion: NotchCompactActivity?) -> CGFloat { companion == .calendar ? groupSpacing : spacing }

    /// A timer's reading beside its mark, measured by its shape, so the
    /// capsule only moves when a character comes or goes.
    package static func timerSurface(reading: String, companion: NotchCompactActivity?, workingAgents: Int,
                             downloadPercent: Bool, geometry: NotchGeometry, language: AppLanguage) -> CGSize {
        let mark = timerMarkWidth(companion: companion, workingAgents: workingAgents, downloadPercent: downloadPercent,
                                  geometry: geometry, language: language)
        let content = mark + markGap(companion) + width(NotchAgentSupport.readingShape(reading), font: readingFont)
        return surface(content: content, leading: companion == .music ? artworkInset(geometry) : endPadding,
                       maximum: Maximum.activity, geometry: geometry)
    }

    /// An event beside what shares the capsule with it: that activity's
    /// mark, then the event's dot and countdown. Its title moves to the
    /// tooltip and VoiceOver.
    package static func calendarPairSurface(companion: NotchCompactActivity, workingAgents: Int, downloadPercent: Bool,
                                    geometry: NotchGeometry, language: AppLanguage) -> CGSize {
        let mark = timerMarkWidth(companion: companion, workingAgents: workingAgents, downloadPercent: downloadPercent,
                                  geometry: geometry, language: language)
        return surface(content: mark + markGap(.calendar) + calendarClockWidth,
                       leading: companion == .music ? artworkInset(geometry) : endPadding,
                       maximum: Maximum.activity, geometry: geometry)
    }

    /// A Keep Awake session: the cup, wider than other marks, then the time
    /// it has left measured by its shape, or infinity for a session without
    /// an end.
    package static func keepAwakeSurface(reading: String?, geometry: NotchGeometry) -> CGSize {
        let cup = NotchKeepAwakeSupport.symbolWidth(NotchKeepAwakeSupport.symbol, size: symbolSize)
        let right = reading.map { width(NotchAgentSupport.readingShape($0), font: readingFont) }
            ?? NotchKeepAwakeSupport.symbolWidth(NotchKeepAwakeSupport.openSymbol, size: readingFont.pointSize) + air
        return surface(content: cup + spacing + right, maximum: Maximum.activity, geometry: geometry)
    }

    /// Working agents' marks and the reading the person chose.
    package static func agentSurface(reading: String, working: Int, geometry: NotchGeometry) -> CGSize {
        let content = agentMarksWidth(working: working) + spacing
            + width(NotchAgentSupport.readingShape(reading), font: readingFont)
        return surface(content: content, maximum: Maximum.activity, geometry: geometry)
    }

    /// A download's arrow and name, then its meter and percentage, or a
    /// spinner until its size is known.
    package static func downloadSurface(name: String, hasProgress: Bool, geometry: NotchGeometry, language: AppLanguage) -> CGSize {
        let progress = hasProgress ? groupSpacing + downloadMeterWidth + spacing + downloadPercentWidth(language)
            : spacing + spinnerWidth
        let content = symbolWidth + spacing + width(name, font: detailFont) + progress
        return surface(content: content, maximum: Maximum.download, geometry: geometry)
    }

    /// An event's color and title, then its countdown at its widest and the
    /// time it starts or ends.
    package static func calendarSurface(title: String, time: String, geometry: NotchGeometry) -> CGSize {
        let content = calendarDotSide + spacing + width(title, font: titleFont) + groupSpacing
            + width("00:00", font: readingFont) + markSpacing + width(time, font: smallFont)
        return surface(content: content, maximum: Maximum.calendar, geometry: geometry)
    }

    /// A watched area: its eye, then what it reads now, or a spinner until
    /// the first reading.
    package static func watchSurface(reading: String, thumbnail: Bool, geometry: NotchGeometry) -> CGSize {
        let right = thumbnail ? NotchWatchSupport.thumbnailWidth
            : reading.isEmpty ? spinnerWidth : width(reading, font: levelFont)
        return surface(content: symbolWidth + spacing + right, maximum: Maximum.activity, geometry: geometry)
    }

    /// Screen capture controls folded while an area is chosen: the tool and a chevron.
    package static func captureSurface(geometry: NotchGeometry) -> CGSize {
        surface(content: symbolWidth * 2 + spacing, maximum: Maximum.activity, geometry: geometry)
    }
}

package struct NotchActivityPickerLayout {
    package static let rowHeight: CGFloat = 32
    package static let spacing: CGFloat = 6
    package static let horizontalInset: CGFloat = 24
    package static let verticalInset: CGFloat = 12
    package static let combinationHeight: CGFloat = 24
    /// A choice's label, measured in the font it is drawn in.
    package static let labelSize: CGFloat = 12
    // NSFont is immutable once made, so any thread may share it.
    nonisolated(unsafe) package static let labelFont = NSFont.systemFont(ofSize: labelSize, weight: .medium)
    /// What a choice adds around its label: the symbol, its gap and the
    /// button's padding.
    package static let choiceChrome: CGFloat = 48
    package let columns: Int
    package let headerHeight: CGFloat
    package let size: CGSize

    package init(count: Int, labelWidth: CGFloat, stripSize: CGSize, screenWidth: CGFloat,
         hasCombinations: Bool = false) {
        columns = min(3, max(1, count))
        headerHeight = stripSize.height
        let rows = (max(1, count) + columns - 1) / columns
        let width = CGFloat(columns) * (labelWidth + Self.choiceChrome)
            + CGFloat(columns - 1) * Self.spacing + Self.horizontalInset * 2
        // The taller picker has deeper shoulders than a compact strip. Keep
        // the entire original strip inside those shoulders, not at its edge.
        size = CGSize(width: min(max(stripSize.width + Self.horizontalInset * 2, width),
                                 max(1, screenWidth - NotchLayout.displaySideMargins)),
                      height: headerHeight + CGFloat(rows) * Self.rowHeight
                        + CGFloat(rows - 1) * Self.spacing + Self.verticalInset * 2
                        + (hasCombinations ? Self.combinationHeight + Self.spacing : 0))
    }
}

/// Screen capture controls keep their title and buttons where the open
/// island keeps its header: at the top, beside a physical camera when the
/// title and the buttons each fit whole on their side, or in a row below it.
package struct NotchCaptureControlsLayout {
    /// The row below a camera, as tall as its buttons.
    package static let rowHeight: CGFloat = 28
    package static let buttonSpacing: CGFloat = 6
    /// The repeat key, collapse and close at their narrowest, as squares.
    package static let narrowButtonsWidth: CGFloat = rowHeight * 3 + buttonSpacing * 2
    /// Room the title and the buttons keep from the camera.
    package static let cameraClearance: CGFloat = 8
    // NSFont is immutable once made, so any thread may share these.
    /// The title's font: the window is sized from it and the view draws it.
    nonisolated(unsafe) package static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    package static func titleWidth(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: titleFont]).width.rounded(.up)
    }
    /// From the top of the island to the top of the title row.
    package let headerTop: CGFloat
    package let headerHeight: CGFloat
    /// The camera between the title and the buttons; 0 when one row holds both.
    package let cameraGap: CGFloat
    /// Each side of the camera, from the island's inset to the cutout.
    package let sideWidth: CGFloat
    package let size: CGSize

    /// `titleWidth` is measured with the title's font.
    package init(geometry: NotchGeometry, titleWidth: CGFloat, capturesAudio: Bool) {
        let side = geometry.headerSideWidth(contentWidth: geometry.contentWidth) ?? geometry.contentWidth / 2
        let fits = max(titleWidth, Self.narrowButtonsWidth) + Self.cameraClearance <= side
        // Without a camera one row spans the top, as the open header does,
        // below a capsule's rounded top corners.
        if geometry.headerTopInset == 0 || geometry.floats, geometry.headerCameraGap == 0 || fits {
            headerTop = geometry.headerTopInset
            headerHeight = geometry.headerRowHeight
            cameraGap = geometry.headerCameraGap
        } else {
            headerTop = geometry.safeContentTop
            headerHeight = Self.rowHeight
            cameraGap = 0
        }
        sideWidth = cameraGap > 0 ? side : 0
        size = CGSize(width: geometry.expandedWidth,
                      height: headerTop + headerHeight + 12 + NotchLayout.shortcutHeight + 16
                        + (capturesAudio ? 40 : 0))
    }
}

package enum NotchControlSetupRequirement: Equatable {
    case feature(AppFeature)
    case page(NotchModule, feature: AppFeature?)
    case none
}

package enum NotchControlItem: String, CaseIterable, Identifiable {
    case volume, brightness, music, mixer, keepAwake, timer, calendar, microphone, screenshot, recording, speedTest, panel, commandBar, scratchpad
    package static let defaultHidden = "microphone,screenshot,recording,speedTest,panel,commandBar,scratchpad"
    package var id: String { rawValue }

    package var symbol: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .keepAwake: return "cup.and.saucer"
        case .microphone: return "mic.fill"
        case .screenshot: return "camera.viewfinder"
        case .recording: return "record.circle"
        case .speedTest: return "speedometer"
        // The app panel opens as a bubble under the menu bar icon.
        case .panel: return "bubble.middle.top"
        case .mixer: return NotchModule.mixer.symbol
        case .commandBar: return "command"
        case .scratchpad: return "note.text"
        case .music: return NotchModule.music.symbol
        case .timer: return NotchModule.timer.symbol
        case .calendar: return NotchModule.calendar.symbol
        }
    }

    package var setupRequirement: NotchControlSetupRequirement {
        switch self {
        case .volume: return .feature(.mixer)
        case .brightness: return .feature(.brightness)
        case .keepAwake: return .feature(.keepAwake)
        case .microphone: return .feature(.micMute)
        case .screenshot: return .feature(.screenshot)
        case .recording: return .feature(.screenRecorder)
        case .commandBar: return .feature(.commandBar)
        case .scratchpad: return .feature(.scratchpad)
        case .panel: return .none
        case .mixer: return .page(.mixer, feature: .mixer)
        case .speedTest: return .page(.system, feature: .monitorNetwork)
        case .music: return .page(.music, feature: nil)
        case .timer: return .page(.timer, feature: .notchTimer)
        case .calendar: return .page(.calendar, feature: .notchCalendar)
        }
    }

    package func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .volume: return AppFeature.mixer.isAvailable(in: defaults)
        case .mixer: return AppFeature.mixer.isAvailable(in: defaults) && NotchSupport.modules(in: defaults).contains(.mixer)
        case .brightness: return AppFeature.brightness.isAvailable(in: defaults)
        case .keepAwake: return AppFeature.keepAwake.isAvailable(in: defaults)
        case .microphone: return AppFeature.micMute.isAvailable(in: defaults)
        case .screenshot: return AppFeature.screenshot.isAvailable(in: defaults)
        case .recording: return AppFeature.screenRecorder.isAvailable(in: defaults)
        case .speedTest: return AppFeature.monitorNetwork.isAvailable(in: defaults) && NotchSupport.modules(in: defaults).contains(.system)
        case .commandBar: return AppFeature.commandBar.isAvailable(in: defaults)
        case .scratchpad: return AppFeature.scratchpad.isAvailable(in: defaults)
        case .panel: return true
        case .music: return NotchSupport.modules(in: defaults).contains(.music)
        case .timer: return NotchSupport.modules(in: defaults).contains(.timer)
        case .calendar: return NotchSupport.modules(in: defaults).contains(.calendar)
        }
    }
}

/// The home page's controls as the page lays them out: the music card and
/// the level cards share a row, and every other control is a shortcut below
/// it. The page's size and its drawing both split them here.
package struct NotchControlGroups: Equatable {
    package let levels: [NotchControlItem]
    package let music: Bool
    package let shortcuts: [NotchControlItem]

    package init(_ items: [NotchControlItem]) {
        levels = items.filter { $0 == .volume || $0 == .brightness }
        music = items.contains(.music)
        shortcuts = items.filter { $0 != .volume && $0 != .brightness && $0 != .music }
    }

    /// Whether the page has its row of cards.
    package var hasCards: Bool { music || !levels.isEmpty }
}

package enum NotchQuickAccessSide: String, CaseIterable, Codable {
    case left, right, bottom
}

package enum NotchQuickAction: Hashable, Identifiable {
    case explore, settings, pin, module(NotchModule), control(NotchControlItem)

    package var id: String {
        switch self {
        case .explore: return "explore"
        case .settings: return "settings"
        case .pin: return "pin"
        case .module(let module): return module.rawValue
        case .control(let item): return "control." + item.rawValue
        }
    }

    package init?(id: String) {
        switch id {
        case "explore": self = .explore
        case "settings": self = .settings
        case "pin": self = .pin
        default:
            if id.hasPrefix("control."), let item = NotchControlItem(rawValue: String(id.dropFirst(8))) {
                self = .control(item)
            } else if let module = NotchModule(rawValue: id) { self = .module(module) }
            else { return nil }
        }
    }

    package static var optionalActions: [Self] {
        [.explore, .settings, .pin] + NotchModule.allCases.map(Self.module)
            + NotchControlItem.allCases.filter { $0 != .volume && $0 != .brightness }.map(Self.control)
    }

    package func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .module(let module): return NotchSupport.modules(in: defaults).contains(module)
        case .control(let item): return item.isAvailable(in: defaults)
        default: return true
        }
    }
}

package struct NotchQuickButton: Codable, Equatable, Identifiable {
    package var id: UUID
    package var actionID: String
    package var side: NotchQuickAccessSide
    package var label: String

    package init(id: UUID = UUID(), action: NotchQuickAction, side: NotchQuickAccessSide, label: String = "") {
        self.id = id
        actionID = action.id
        self.side = side
        self.label = label
    }

    package var action: NotchQuickAction? { NotchQuickAction(id: actionID) }
}

package struct NotchQuickAccessConfiguration: Equatable, Codable {
    package var buttons: [NotchQuickButton]
    private var version = 1
    package static let maximumPerSide = 3
    package static let initial = Self(buttons: [
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, action: .explore, side: .left),
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, action: .module(.timer), side: .left),
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, action: .settings, side: .right),
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, action: .module(.mixer), side: .right),
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000005")!, action: .module(.music), side: .bottom),
    ])
    package var actions: [NotchQuickAction] { buttons.compactMap(\.action) }
    package var hasBottom: Bool { buttons.contains { $0.side == .bottom } }

    package init(buttons: [NotchQuickButton]) { self.buttons = buttons }

    /// Stable IDs allow the previous single-side preferences to remain live
    /// until the first deliberate edit saves the new layout.
    package init(side: NotchQuickAccessSide, actions: [NotchQuickAction]) {
        buttons = actions.enumerated().map { index, action in
            NotchQuickButton(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                             action: action, side: side)
        }
    }

    package func sanitized() -> Self {
        var ids = Set<UUID>()
        var counts: [NotchQuickAccessSide: Int] = [:]
        let safe = buttons.prefix(64).compactMap { button -> NotchQuickButton? in
            guard button.action != nil, ids.insert(button.id).inserted,
                  counts[button.side, default: 0] < Self.maximumPerSide else { return nil }
            counts[button.side, default: 0] += 1
            var result = button
            result.label = String(button.label.components(separatedBy: .newlines).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            return result
        }
        return Self(buttons: safe)
    }

    package var encoded: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(sanitized())) ?? Data()
    }

    package static func stored(in defaults: UserDefaults = .standard) -> Self {
        if let data = defaults.data(forKey: DefaultsKey.notchQuickAccessLayout), !data.isEmpty, data.count <= 32_768,
           let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1 {
            return value.sanitized()
        }
        // These retired keys have no registration defaults, so even an empty
        // saved value is an explicit legacy choice rather than a fresh install.
        let legacyKeys = [DefaultsKey.notchQuickAccessSide, DefaultsKey.notchQuickAccessSecond, DefaultsKey.notchQuickAccessThird]
        guard legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return .initial }
        let side = NotchQuickAccessSide(rawValue: defaults.string(forKey: DefaultsKey.notchQuickAccessSide) ?? "") ?? .left
        var actions: [NotchQuickAction] = [.explore]
        for key in [DefaultsKey.notchQuickAccessSecond, DefaultsKey.notchQuickAccessThird] {
            let id = defaults.string(forKey: key) ?? (key == DefaultsKey.notchQuickAccessSecond ? NotchQuickAction.settings.id : "")
            guard let action = NotchQuickAction(id: id),
                  !actions.contains(action) else { continue }
            actions.append(action)
        }
        return Self(side: side, actions: actions)
    }

    package static func current(in defaults: UserDefaults = .standard) -> Self {
        var configuration = stored(in: defaults)
        configuration.buttons.removeAll { $0.action?.isAvailable(in: defaults) != true }
        return configuration
    }

    package mutating func move(_ id: UUID, to side: NotchQuickAccessSide, before target: UUID? = nil) {
        guard let index = buttons.firstIndex(where: { $0.id == id }),
              buttons[index].side == side || buttons.filter({ $0.side == side }).count < Self.maximumPerSide else { return }
        var item = buttons.remove(at: index)
        item.side = side
        let destination = target.flatMap { target in buttons.firstIndex(where: { $0.id == target && $0.side == side }) }
        buttons.insert(item, at: destination ?? buttons.endIndex)
    }
}

package struct NotchQuickAccessPlacement: Equatable, Identifiable {
    package let button: NotchQuickButton
    package let index: Int
    package let edge: CGFloat
    package let top: CGFloat
    package var id: UUID { button.id }
    package var side: NotchQuickAccessSide { button.side }
    package func center(progress: CGFloat) -> CGPoint {
        NotchQuickAccessLayout.center(index: index, progress: progress, edge: edge, top: top, side: side)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(button: NotchQuickButton, index: Int, edge: CGFloat, top: CGFloat) {
        self.button = button
        self.index = index
        self.edge = edge
        self.top = top
    }
}

/// All coordinates are in the flipped presentation container, including the
/// transparent space reserved beside the black notch.
package enum NotchQuickAccessLayout {
    package static let diameter: CGFloat = 44
    package static let gap: CGFloat = 12
    package static let gutter: CGFloat = 72
    package static let rowSpacing: CGFloat = 54
    package static let withdrawalDuration = 0.16
    package static let hoverMargin: CGFloat = 16
    package static let hoverExitDelay = 0.18

    package static func center(index: Int, progress: CGFloat, edge: CGFloat, top: CGFloat,
                       side: NotchQuickAccessSide) -> CGPoint {
        let phase = progress.isFinite ? min(1.1, max(0, progress)) : 0
        let offset = -14 + phase * (14 + gap + diameter / 2)
        if side == .bottom { return CGPoint(x: top + CGFloat(index) * rowSpacing, y: edge + offset) }
        return CGPoint(x: edge + (side == .left ? -offset : offset), y: top + CGFloat(index) * rowSpacing)
    }

    /// Hover is a continuous corridor, including the gaps and a forgiving rim.
    /// Clicks still use the exact circles below.
    package static func hoverRect(count: Int, edge: CGFloat, top: CGFloat,
                          side: NotchQuickAccessSide) -> CGRect {
        guard count > 0 else { return .null }
        let first = center(index: 0, progress: 1, edge: edge, top: top, side: side)
        let last = center(index: min(3, count) - 1, progress: 1, edge: edge, top: top, side: side)
        let radius = diameter / 2
        if side == .bottom {
            return CGRect(x: first.x - radius, y: edge, width: last.x - first.x + diameter,
                          height: first.y + radius - edge).insetBy(dx: -hoverMargin, dy: -hoverMargin)
        }
        return CGRect(x: min(first.x - radius, edge), y: first.y - radius,
                      width: max(first.x + radius, edge) - min(first.x - radius, edge),
                      height: last.y - first.y + diameter)
            .insetBy(dx: -hoverMargin, dy: -hoverMargin)
    }

    package static func placements(_ configuration: NotchQuickAccessConfiguration, body: CGRect, headerTop: CGFloat) -> [NotchQuickAccessPlacement] {
        var indices: [NotchQuickAccessSide: Int] = [:]
        return configuration.buttons.map { button in
            let index = indices[button.side, default: 0]
            indices[button.side] = index + 1
            let count = configuration.buttons.filter { $0.side == button.side }.count
            let edge = button.side == .bottom ? body.maxY : button.side == .left ? body.minX : body.maxX
            let span = CGFloat(count - 1) * rowSpacing
            // Short pages lift a crowded column to balance its top and bottom
            // margins. Keep the usual header alignment when there is room.
            let sideTop = max(body.minY + diameter / 2 + gap, min(headerTop, body.midY - span / 2))
            let top = button.side == .bottom ? body.midX - span / 2 : sideTop
            return NotchQuickAccessPlacement(button: button, index: index, edge: edge, top: top)
        }
    }

    package static func hitTest(_ point: CGPoint, count: Int, edge: CGFloat, top: CGFloat,
                        side: NotchQuickAccessSide) -> Bool {
        (0..<max(0, min(3, count))).contains { index in
            let center = center(index: index, progress: 1, edge: edge, top: top, side: side)
            return hypot(point.x - center.x, point.y - center.y) <= diameter / 2
        }
    }
}

package enum NotchEvent: String, CaseIterable {
    case volume, brightness, battery, clipboard, capture, systemNotification, keyboardLight, timer, accessory, download, agents, track, microphone, watch

    package var preferenceKey: String {
        switch self {
        case .microphone: return DefaultsKey.notchMicrophone
        case .track: return DefaultsKey.notchTrackChange
        case .timer: return DefaultsKey.notchTimerEnabled
        case .watch: return DefaultsKey.notchWatchEnabled
        case .accessory: return DefaultsKey.notchAccessoriesEnabled
        case .download: return DefaultsKey.notchDownloadsEnabled
        case .agents: return DefaultsKey.notchAgentsEnabled
        case .systemNotification: return DefaultsKey.notchNotificationsEnabled
        case .keyboardLight: return DefaultsKey.notchKeyboardLight
        case .volume: return DefaultsKey.notchVolume
        case .brightness: return DefaultsKey.notchBrightness
        case .battery: return DefaultsKey.notchBattery
        case .clipboard: return DefaultsKey.notchClipboard
        case .capture: return DefaultsKey.notchCapture
        }
    }

    package var priority: Int {
        switch self {
        case .volume, .brightness, .keyboardLight, .microphone: return 3
        case .capture, .timer, .watch: return 2
        case .battery, .systemNotification, .accessory, .agents: return 1
        case .clipboard, .download, .track: return 0
        }
    }

    package var duration: TimeInterval {
        switch self {
        case .volume, .brightness, .keyboardLight, .microphone: return 1.6
        case .systemNotification, .track: return 3
        case .timer, .download, .watch: return 6
        case .agents: return 5
        case .battery, .accessory: return 4
        case .clipboard: return 2.5
        case .capture: return 12
        }
    }
}

package enum NotchSupport {
    /// Whether a connected display has a camera housing, wherever the island
    /// is: it can be off, withdrawn with the lid closed or on another display.
    @preconcurrency @MainActor
    package static var hasNotchedDisplay: Bool {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    /// Whether a connected display, such as an external monitor, has no
    /// camera housing, so the island can float there as a capsule.
    @preconcurrency @MainActor
    package static var hasDisplayWithoutNotch: Bool {
        NSScreen.screens.contains { !($0.safeAreaInsets.top > 0) }
    }

    package static let toolColumns = 5
    package static let defaultHoverDelay = 0.25
    package static let hoverDelayRange = 0.10...1.0

    /// Whether a screen point lies in a top-edge click area, whose top edge
    /// belongs to it as in the flipped native view.
    package static func screenEdgeArea(_ area: CGRect, contains point: CGPoint) -> Bool {
        CGRect(origin: .zero, size: area.size).contains(CGPoint(x: point.x - area.minX, y: area.maxY - point.y))
    }

    package static func sanitizedHoverDelay(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? min(hoverDelayRange.upperBound, max(hoverDelayRange.lowerBound, value)) : defaultHoverDelay
    }

    package static func moduleShortcut(_ characters: String, modules: [NotchModule]) -> NotchModule? {
        modules.first { $0.shortcutKey == characters.lowercased() }
    }

    package static func filteredModules(_ modules: [NotchModule], query: String,
                                title: (NotchModule) -> String) -> [NotchModule] {
        let terms = CommandBarSearch.normalized(query).split(separator: " ")
        guard !terms.isEmpty else { return modules }
        return modules.filter { module in
            let name = CommandBarSearch.normalized(title(module))
            return terms.allSatisfy { name.contains($0) }
        }
    }

    package static func adjacentModule(to selected: NotchModule?, modules: [NotchModule], backwards: Bool) -> NotchModule? {
        guard !modules.isEmpty else { return nil }
        guard let selected, let index = modules.firstIndex(of: selected) else { return modules.first }
        return modules[(index + (backwards ? modules.count - 1 : 1)) % modules.count]
    }

    /// The arrow keys step through a searched list without wrapping; the
    /// first press, or one after the highlighted row left the list, lands on
    /// the top result.
    package static func steppedItem<ID: Equatable>(from current: ID?, in ids: [ID], backwards: Bool) -> ID? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return ids.first }
        return ids[min(max(index + (backwards ? -1 : 1), 0), ids.count - 1)]
    }

    /// Return can paste before an arrow is pressed. A stale highlight falls
    /// back to the first visible entry, never to a filtered-out row.
    package static func clipboardPasteTarget<ID: Equatable>(highlighted: ID?, in ids: [ID]) -> ID? {
        if let highlighted, ids.contains(highlighted) { return highlighted }
        return ids.first
    }

    /// The row a search leaves highlighted: the current one while it is still
    /// listed, otherwise the top result of a typed search, so Return pastes it
    /// like the history window does. An empty search waits for the first arrow.
    package static func searchHighlight<ID: Equatable>(keeping current: ID?, in ids: [ID], query: String) -> ID? {
        if let current, ids.contains(current) { return current }
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ids.first
    }

    /// Automatic order until the user chooses one of the live activities.
    package static func compactActivity(timer: Bool, downloads: Bool, agents: Bool = false,
                                calendar: Bool = false, music: Bool, keepAwake: Bool = false) -> NotchCompactActivity? {
        compactActivities(timer: timer, downloads: downloads, agents: agents,
                          calendar: calendar, music: music, keepAwake: keepAwake).first
    }

    /// Keep Awake comes last: a session can run all day, even more than
    /// music plays, and it only says that the Mac stays awake. A watch
    /// follows the timer: the person started both and is waiting on them.
    package static func compactActivities(timer: Bool, watch: Bool = false, downloads: Bool, agents: Bool,
                                  calendar: Bool, music: Bool, keepAwake: Bool = false) -> [NotchCompactActivity] {
        let candidates: [(Bool, NotchCompactActivity)] = [
            (timer, .timer), (watch, .watch), (downloads, .downloads), (agents, .agents),
            (calendar, .calendar), (music, .music), (keepAwake, .keepAwake)
        ]
        return candidates.compactMap { $0.0 ? $0.1 : nil }
    }

    /// Supported, explicit pairs for the activity that keeps its reading
    /// right of the camera. A paused or finished timer needs its own mark
    /// beside agents, an event or music; downloads already carry their
    /// status. An event's clock always runs, so a download, agents or music
    /// can take the side its title had.
    package static func compactCompanions(of primary: NotchCompactActivity, timer: Bool, running: Bool, downloads: Bool,
                                  agents: Bool, calendar: Bool, music: Bool) -> [NotchCompactActivity] {
        let pairs: [(Bool, NotchCompactActivity)]
        switch primary {
        case .timer where timer:
            pairs = [(downloads, .downloads), (running && agents, .agents), (running && calendar, .calendar),
                     (running && music, .music)]
        case .calendar where calendar:
            pairs = [(downloads, .downloads), (agents, .agents), (music, .music)]
        default:
            pairs = []
        }
        return pairs.compactMap { $0.0 ? $0.1 : nil }
    }

    package static func gestureIsOverHeader(expanded: Bool, peeking: Bool, fromTop: CGFloat, safeTop: CGFloat,
                                    height: CGFloat = NotchLayout.headerHeight) -> Bool {
        (expanded || peeking) && (safeTop...safeTop + height).contains(fromTop)
    }

    package static func keepsPermissionSurface(requesting: Bool, resolvedAt: TimeInterval?, now: TimeInterval) -> Bool {
        if requesting { return true }
        guard let resolvedAt, now.isFinite, resolvedAt.isFinite else { return false }
        return (0..<1).contains(now - resolvedAt)
    }

    package static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.notch.isAvailable(in: defaults)
            && defaults[Preferences.notchEnabled]
    }

    package static func usesHapticFeedback(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults[Preferences.notchHapticFeedback]
    }

    package static func modules(in defaults: UserDefaults = .standard) -> [NotchModule] {
        let hidden = Set((defaults.string(forKey: DefaultsKey.notchHiddenModules) ?? "")
            .split(separator: ",").map(String.init))
        let stored = (defaults.string(forKey: DefaultsKey.notchModuleOrder) ?? "")
            .split(separator: ",").compactMap { NotchModule(rawValue: String($0)) }
        var seen = Set<NotchModule>()
        return (stored + NotchModule.allCases).filter {
            seen.insert($0).inserted && !hidden.contains($0.rawValue) && $0.isAvailable(in: defaults)
                && ($0 != .timer || defaults[Preferences.notchTimerEnabled])
                && ($0 != .camera || defaults[Preferences.notchCameraEnabled])
                && ($0 != .calendar || defaults[Preferences.notchCalendarEnabled])
                && ($0 != .notifications || defaults[Preferences.notchNotificationsEnabled])
                && ($0 != .agents || defaults[Preferences.notchAgentsEnabled])
                && ($0 != .watch || defaults[Preferences.notchWatchEnabled])
        }
    }

    package static func watchesMusicActivity(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && modules(in: defaults).contains(.music)
            && idleContent(in: defaults) != .none
            && (defaults.object(forKey: DefaultsKey.notchShowPlayingMusic) as? Bool ?? true)
    }

    package static func showsMusicActivity(isPlaying: Bool, in defaults: UserDefaults = .standard) -> Bool {
        isPlaying && watchesMusicActivity(in: defaults)
    }

    package static func showsInCaptures(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchShowInCaptures) as? Bool ?? true
    }

    /// The closed island may cover the menus instead of giving way to them.
    package static func coversMenus(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchCoversMenus) as? Bool ?? true
    }

    /// The closed island stays out of sight until the pointer reaches it, and
    /// shows no notices while it waits.
    package static func hidesUntilHover(in defaults: UserDefaults = .standard) -> Bool {
        defaults[Preferences.notchHideUntilHover] && defaults[Preferences.notchOpenOnHover]
    }

    package static func idleContent(in defaults: UserDefaults = .standard) -> NotchIdleContent {
        let choice = NotchIdleContent(rawValue: defaults.string(forKey: DefaultsKey.notchIdleContent) ?? "") ?? .none
        if choice == .battery, !AppFeature.monitorPower.isAvailable(in: defaults) { return .none }
        if choice == .music, !modules(in: defaults).contains(.music) { return .none }
        if choice == .agents, !NotchAgentSupport.isEnabled(in: defaults) { return .none }
        return choice
    }

    package static func visibleIdleContent(isPlaying: Bool, in defaults: UserDefaults = .standard) -> NotchIdleContent {
        let choice = idleContent(in: defaults)
        return choice == .music && !showsMusicActivity(isPlaying: isPlaying, in: defaults) ? .none : choice
    }

    package static func controls(in defaults: UserDefaults = .standard) -> [NotchControlItem] {
        let hidden = Set((defaults.string(forKey: DefaultsKey.notchHiddenControls) ?? NotchControlItem.defaultHidden)
            .split(separator: ",").map(String.init))
        let stored = (defaults.string(forKey: DefaultsKey.notchControlOrder) ?? "")
            .split(separator: ",").compactMap { NotchControlItem(rawValue: String($0)) }
        var seen = Set<NotchControlItem>()
        return (stored + NotchControlItem.allCases).filter {
            seen.insert($0).inserted && !hidden.contains($0.rawValue) && $0.isAvailable(in: defaults)
        }
    }

    /// Power draw has a card of its own beside the battery; fans join once
    /// the monitor reports one.
    package static func systemCardCount(hasBattery: Bool, fans: Int = 0, in defaults: UserDefaults = .standard) -> Int {
        [.monitorCPU, .monitorGPU, .monitorMemory, .monitorDisk].filter {
            (feature: AppFeature) in feature.isAvailable(in: defaults)
        }.count + (AppFeature.monitorNetwork.isAvailable(in: defaults) ? 1 : 0)
            + (hasBattery && AppFeature.monitorPower.isAvailable(in: defaults) ? 1 : 0)
            + (AppFeature.monitorPower.isAvailable(in: defaults) ? 1 : 0)
            + (fans > 0 && AppFeature.fanControl.isAvailable(in: defaults) ? 1 : 0)
    }

    /// Direct openings are dismissed explicitly, never by the pointer's
    /// initial position at the menu bar or in the application being used.
    package static func closesOnPointerExit(expanded: Bool, peeking: Bool, openedByHover: Bool) -> Bool {
        peeking || (expanded && openedByHover)
    }

    /// Another app becoming active closes the open island like a click away.
    /// One opened by hover stays while the pointer rests on it unclicked:
    /// reaching the island can itself make the app beneath it active, such as
    /// a full-screen app on a display without focus, and leaving closes it
    /// anyway. A click inside may be what brought the other app forward.
    package static func closesOnActivation(openedByHover: Bool, clicked: Bool, pointerInside: Bool) -> Bool {
        !openedByHover || clicked || !pointerInside
    }

    package static func routes(_ event: NotchEvent, in defaults: UserDefaults = .standard) -> Bool {
        guard isEnabled(in: defaults), defaults.bool(forKey: event.preferenceKey) else { return false }
        switch event {
        case .timer: return NotchTimerSupport.isEnabled(in: defaults)
        case .watch: return NotchWatchSupport.isEnabled(in: defaults)
        case .accessory: return NotchAccessorySupport.isEnabled(in: defaults)
        case .download: return AppFeature.notchDownloads.isAvailable(in: defaults)
            && modules(in: defaults).contains(.downloads)
        case .agents: return AppFeature.notchAgents.isAvailable(in: defaults)
            && modules(in: defaults).contains(.agents)
        case .systemNotification: return NotchNotificationSupport.isEnabled(in: defaults)
        case .keyboardLight: return AppFeature.brightness.isAvailable(in: defaults)
        case .volume: return AppFeature.mixer.isAvailable(in: defaults)
        case .microphone: return AppFeature.micMute.isAvailable(in: defaults)
        case .brightness:
            return AppFeature.brightness.isAvailable(in: defaults)
                && defaults[Preferences.brightnessControlEnabled]
        case .battery: return AppFeature.monitorPower.isAvailable(in: defaults)
        case .clipboard:
            return modules(in: defaults).contains(.clipboard)
                && defaults[Preferences.clipboardHistoryEnabled]
        case .capture:
            return AppFeature.screenshot.isAvailable(in: defaults)
                && modules(in: defaults).contains(.captures)
        case .track: return modules(in: defaults).contains(.music)
        }
    }

    package static func routesClipboardWindow(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults[Preferences.notchClipboardWindow]
            && modules(in: defaults).contains(.clipboard)
    }

    /// Whether the island is on and shows its Files module, whichever window
    /// the user chose for the shelf.
    package static func showsFiles(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && modules(in: defaults).contains(.files)
    }

    package static func routesShelf(in defaults: UserDefaults = .standard) -> Bool {
        showsFiles(in: defaults) && defaults[Preferences.notchShelf]
    }

    package static func revealsShelfDrag(in defaults: UserDefaults = .standard) -> Bool {
        routesShelf(in: defaults) && defaults[Preferences.notchDragReveal]
    }

    package static func routesCaptureControls(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults[Preferences.notchCaptureControls]
            && modules(in: defaults).contains(.captures)
    }

    package static func routesQuickPanel(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults[Preferences.notchQuickPanel]
            && AppFeature.quickLauncher.isAvailable(in: defaults)
            && modules(in: defaults).contains(.tools)
    }

    package static func routesAppPanel(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults[Preferences.notchAppPanel]
    }

    package static func routesScratchpad(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && (defaults.object(forKey: DefaultsKey.notchScratchpad) as? Bool ?? true)
            && modules(in: defaults).contains(.scratchpad)
    }

    /// A notice the pointer holds open is being read. Only the same kind of
    /// message or something the user just did may take its place.
    package static func shouldReplace(_ current: NotchEvent?, with incoming: NotchEvent, held: Bool = false) -> Bool {
        guard let current else { return true }
        if held { return incoming == current || incoming.priority > current.priority }
        return incoming.priority >= current.priority
    }

    package static func volumeLevel(current: Double, direction: Int, fine: Bool) -> Double {
        guard current.isFinite else { return 0 }
        return min(1, max(0, current + Double(direction.signum()) / (fine ? 64 : 16)))
    }

    /// A laptop with its lid closed has no built-in screen to show on, so the
    /// built-in choice hides the island there. A Mac without a built-in panel
    /// never has one, so that choice keeps the main display. The pointer
    /// choice takes the display it last followed the pointer to, if any, and
    /// so does the choice of every display for the island that responds.
    package static func screenIndex(preference: NotchDisplay, builtIn: [Bool], notched: [Bool], main: Int,
                            pointer: Int? = nil, hasLid: Bool = true) -> Int? {
        guard !builtIn.isEmpty, builtIn.count == notched.count else { return nil }
        let fallback = builtIn.indices.contains(main) ? main : 0
        switch preference {
        case .main: return fallback
        case .builtIn: return builtIn.firstIndex(of: true) ?? (hasLid ? nil : fallback)
        case .automatic:
            return builtIn.indices.first { builtIn[$0] && notched[$0] }
                ?? notched.firstIndex(of: true) ?? fallback
        case .pointer, .all: return pointer.flatMap { builtIn.indices.contains($0) ? $0 : nil } ?? fallback
        }
    }
}

/// A hidden menu bar retains only a measurement from the same display and mode.
/// Until that display has a visible bar, use the native fallback rather than
/// borrowing the application's main-menu height from another display.
package struct NotchMenuBarMeasurements {
    private struct Reading {
        let size: CGSize
        let scale: CGFloat
        let height: CGFloat

        // Spelled out because a memberwise initializer never leaves its module.
        package init(size: CGSize, scale: CGFloat, height: CGFloat) {
            self.size = size
            self.scale = scale
            self.height = height
        }
    }
    private static let range: ClosedRange<CGFloat> = 16...64
    private var readings: [UInt32: Reading] = [:]

    /// A bar that hides until the pointer reveals it reserves nothing at the
    /// top of the visible frame, and neither does a display without a bar.
    package static func showsBar(frame: CGRect, visibleTop: CGFloat) -> Bool {
        let gap = frame.maxY - visibleTop
        return gap.isFinite && range.contains(gap)
    }

    package mutating func retainDisplays(_ ids: [UInt32]) {
        readings = readings.filter { ids.contains($0.key) }
    }

    package mutating func height(displayID: UInt32, frame: CGRect, visibleTop: CGFloat,
                         scale: CGFloat, statusBarThickness: CGFloat) -> CGFloat {
        let range = Self.range
        let gap = frame.maxY - visibleTop
        let canRemember = displayID != 0 && scale.isFinite && scale > 0
        if let previous = readings[displayID], previous.size != frame.size || previous.scale != scale {
            readings[displayID] = nil
        }
        if Self.showsBar(frame: frame, visibleTop: visibleTop) {
            if canRemember { readings[displayID] = Reading(size: frame.size, scale: scale, height: gap) }
            return gap
        }
        if canRemember, let previous = readings[displayID] { return previous.height }
        return statusBarThickness.isFinite && range.contains(statusBarThickness) ? statusBarThickness : 24
    }

    // Spelled out because a default initializer never leaves its module.
    package init() {}
}

/// Screen coordinates stay in points, including displays to the left or above
/// the primary display. No model name or pixel density is assumed.
package struct NotchGeometry: Equatable {
    package let screen: CGRect
    package let cameraWidth: CGFloat
    package let cameraHeight: CGFloat
    package let isNotched: Bool
    package let layout: NotchSize
    package let customWidth: CGFloat
    package let customHeight: CGFloat
    package let menuBarHeight: CGFloat
    /// Nil hangs the island from the top edge. A capsule floats this far
    /// inside the menu bar, above and below its strips.
    package let floatingGap: CGFloat?
    /// How far a fitted capsule sits below the top of the display, open or closed.
    package let floatingDrop: CGFloat
    /// How far past a physical camera an outlined island reaches on each side
    /// and below. The line is drawn inside the island's edge, so an island
    /// that only covers the camera would hide it behind the housing.
    package let outlineRoom: CGFloat
    private let capsuleWidthFit: CGFloat
    package var compactSideRoom: CGFloat?
    package var quickAccessBottomInset: CGFloat = 0
    package var requiresFullWidthHeader = false
    /// The open page's title with the button before it, as the header draws them.
    package var headerTitleWidth: CGFloat = 0
    private var allowsActivityFooter = true
    private var minimumCompactWidth: CGFloat = 0
    /// Narrower wings than this are dropped rather than drawn cramped.
    private var minimumWing: CGFloat = 44

    package init(screen: CGRect, safeAreaTop: CGFloat, cameraWidth: CGFloat, layout: NotchSize = .compact,
         menuBarHeight: CGFloat = 24, compactSideRoom: CGFloat? = nil,
         customWidth: Double = NotchSize.defaultWidth, customHeight: Double = NotchSize.defaultHeight,
         cameraFit: NotchCameraFit = .zero, silhouette: NotchSilhouette = .notch, capsuleFit: NotchCapsuleFit = .zero,
         outline: Bool = false) {
        self.screen = screen
        self.layout = layout
        self.customWidth = NotchSize.clamped(customWidth, to: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
        self.customHeight = NotchSize.clamped(customHeight, to: NotchSize.heightRange, fallback: NotchSize.defaultHeight)
        let barHeight = menuBarHeight.isFinite ? min(64, max(16, menuBarHeight)) : 24
        isNotched = safeAreaTop.isFinite && safeAreaTop > 0 && cameraWidth.isFinite && cameraWidth > 0
        // Only a physical camera has an outline to match; a simulated one follows the bar.
        let fit = isNotched ? cameraFit : .zero
        // A capsule replaces only a simulated cutout. It is as wide as the
        // cutout of the bar it sits in with its usual margins, so a bar hidden
        // on one display and shown on another draws the same capsule on both.
        let gap: CGFloat? = !isNotched && silhouette == .capsule ? NotchLayout.capsuleGap(barHeight: barHeight) : nil
        floatingGap = gap
        // A fitted capsule grows from its top edge, keeping its margins.
        let capsuleFit = gap == nil ? NotchCapsuleFit.zero : capsuleFit
        floatingDrop = capsuleFit.drop
        capsuleWidthFit = capsuleFit.width
        let stripHeight = gap.map { max(barHeight + capsuleFit.height, $0 * 2 + 12) } ?? barHeight
        let profileHeight = gap.map { stripHeight - ($0 - NotchLayout.capsuleMargin) * 2 } ?? barHeight
        // A capsule's camera is only the room it keeps, on whole points.
        let simulated = 180 * profileHeight / 32
        // A simulated cutout sits on the menu bar, where its outline already shows.
        let room = isNotched && outline ? NotchLayout.outlineWidth : 0
        outlineRoom = room
        self.cameraWidth = min(isNotched ? max(0, cameraWidth + fit.width + room * 2)
                               : gap == nil ? simulated : (simulated + capsuleFit.width).rounded(),
                               screen.width * 0.7)
        cameraHeight = isNotched ? min(max(0, safeAreaTop + fit.height + room), 64) : stripHeight
        self.menuBarHeight = max(cameraHeight, barHeight)
        self.compactSideRoom = compactSideRoom
    }

    /// The island floats in the menu bar instead of hanging from the top edge.
    package var floats: Bool { floatingGap != nil }

    package func hasSameMenuBar(as other: NotchGeometry) -> Bool {
        screen == other.screen && cameraWidth == other.cameraWidth
            && menuBarHeight == other.menuBarHeight && isNotched == other.isNotched
    }

    /// Below a camera, or below the space it would take. A capsule has
    /// neither, so what it shows keeps even margins inside it.
    package var safeContentTop: CGFloat { floats ? NotchLayout.bottomInset : cameraHeight + 10 }
    /// The camera sits between the title and the compact actions only when each
    /// fits whole on its side. The actions need a 100-point wing, which the
    /// compact preset leaves, and the title its own width. Narrower layouts and
    /// longer titles keep a full row below the camera.
    package var headerCameraGap: CGFloat {
        isNotched && !requiresFullWidthHeader && contentWidth >= cameraWidth + 200
            && headerTitleWidth <= (contentWidth - cameraWidth) / 2 ? cameraWidth : 0
    }
    /// A capsule's header keeps clear of its rounded top corners, its
    /// icon buttons as far from the top edge as the page is from the bottom.
    package var headerTopInset: CGFloat {
        if floats { return NotchLayout.bottomInset - (NotchLayout.headerHeight - NotchLayout.iconButtonSide) / 2 }
        return !isNotched || headerCameraGap > 0 ? 0 : safeContentTop
    }
    package var headerRowHeight: CGFloat { headerCameraGap > 0 ? max(cameraHeight, NotchLayout.headerHeight) : NotchLayout.headerHeight }
    package var headerChromeHeight: CGFloat { headerRowHeight + NotchLayout.spacing + NotchLayout.bottomInset }
    /// Where the open island's header row ends, and where its page starts below it.
    package var headerBottom: CGFloat { headerTopInset + headerRowHeight }
    package var pageTop: CGFloat { headerBottom + NotchLayout.spacing }
    /// Each side of the open header beside the camera, or nil when one row
    /// spans the top.
    package func headerSideWidth(contentWidth: CGFloat) -> CGFloat? {
        headerCameraGap > 0 ? (contentWidth - headerCameraGap) / 2 : nil
    }
    /// Floating circles sit below the menu bar even when the title fits beside the camera.
    package var quickAccessCenterY: CGFloat {
        max(headerTopInset + headerRowHeight / 2,
            menuBarHeight + 6 + NotchQuickAccessLayout.diameter / 2)
    }
    /// One row beside the camera. It extends the cutout, whose height a
    /// physical camera sets and a simulated one shares with the bar: a bar
    /// even a point taller would leave a dark line under the notch.
    package var stripHeight: CGFloat { cameraHeight }
    /// What a strip shows inside: all of it, or the capsule within its margins.
    package var stripBodyHeight: CGFloat { max(0, stripHeight - (floatingGap ?? 0) * 2) }
    package func activationArea(in size: CGSize, hasHeader: Bool, compactActivity: Bool, expandedHeader: Bool = false) -> CGRect {
        // Only a camera beside the open header toggles the island.
        if expandedHeader, headerTopInset == 0 || floats {
            return CGRect(x: (size.width - headerCameraGap) / 2, y: 0,
                          width: headerCameraGap, height: min(cameraHeight, size.height))
        }
        // A capsule has no camera to toggle from: all of it opens the island.
        let width = compactActivity && !floats ? cameraWidth : size.width
        let height = hasHeader ? min(safeContentTop, size.height)
            : compactActivity && compactActivityUsesFooter ? compactActivityTopPadding : size.height
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
    }

    package var restingWingWidth: CGFloat {
        let available = min(44, max(0, compactSideRoom ?? 0)).rounded(.down)
        return available >= 44 ? available : 0
    }
    package var collapsed: CGSize {
        CGSize(width: min(maximumSurfaceWidth, cameraWidth + restingWingWidth * 2), height: stripHeight)
    }
    package func restingSize(showsContent: Bool) -> CGSize {
        if showsContent { return collapsed }
        // Bare, a capsule is shorter than the gap between an activity's
        // wings, closer to the phone's proportions, and on whole points,
        // as the window around it is.
        guard floats else { return CGSize(width: cameraWidth, height: cameraHeight) }
        let shoulders = NotchLayout.shoulder(height: stripHeight) * 2
        let capsule = max(NotchLayout.capsuleRestingAspect * stripBodyHeight + capsuleWidthFit, stripBodyHeight * 2)
        return CGSize(width: min(cameraWidth, (capsule + shoulders).rounded()), height: cameraHeight)
    }
    /// Full screen and the Lock Screen draw no outline, so their black cutout
    /// keeps to the camera instead of showing the outline's room below it.
    package var bareCutout: CGSize {
        let resting = restingSize(showsContent: false)
        return CGSize(width: max(0, resting.width - outlineRoom * 2), height: max(0, resting.height - outlineRoom))
    }
    /// Music remains one row high, with the physical camera between its wings.
    /// Insufficient menu space hides the wings instead of growing below the camera.
    /// Beside a physical camera each wing is just wide enough for the cover or
    /// the bars, kept as far from the strip's end as from its top and bottom.
    package var compactMusicGeometry: NotchGeometry {
        var compact = self
        compact.allowsActivityFooter = false
        let room = compactSideRoom ?? 0
        let wing = isNotched ? compact.compactMusicContentWing : 44
        compact.compactSideRoom = room.isFinite && room >= wing ? min(isNotched ? wing : 56, room) : 0
        compact.minimumWing = wing
        return compact
    }
    /// The cover takes the strip's height less an even gap above and below.
    package var compactMusicArtworkSide: CGFloat {
        max(0, min(26, compactActivityContentHeight - NotchLayout.compactEdgeGap * 2))
    }
    /// A cover that fills the strip keeps the same gap from its end as from
    /// its top and bottom, and its corners share a centre with the strip's
    /// lower corners, so both curves run parallel. A cover well short of a
    /// tall strip keeps the usual edge gap and a tile's own corners.
    private var compactMusicArtworkFills: Bool {
        compactActivityContentHeight - compactMusicArtworkSide <= NotchLayout.compactEdgeGap * 4
    }
    package var compactMusicArtworkRadius: CGFloat {
        let side = compactMusicArtworkSide
        guard compactMusicArtworkFills else { return side * 0.28 }
        let concentric = NotchLayout.surfaceRadius(height: compactActivitySize.height)
            - (compactActivityContentHeight - side) / 2
        return min(side / 2, max(side * 0.2, concentric))
    }
    package var compactMusicArtworkInset: CGFloat {
        let gap = compactMusicArtworkFills ? (compactActivityContentHeight - compactMusicArtworkSide) / 2
            : NotchLayout.compactEdgeGap
        return compactActivityEdgeInset(boxHeight: compactMusicArtworkSide, radius: compactMusicArtworkRadius, gap: gap)
    }
    package var compactMusicBarHeight: CGFloat {
        min(16, max(6, compactActivityContentHeight - NotchLayout.compactEdgeGap * 2))
    }
    package var compactMusicBarsInset: CGFloat {
        compactActivityEdgeInset(boxHeight: compactMusicBarHeight, radius: NotchLayout.compactMusicBarWidth / 2)
    }
    private var compactMusicContentWing: CGFloat {
        max(compactMusicArtworkInset + compactMusicArtworkSide,
            compactMusicBarsInset + NotchLayout.compactMusicBarsWidth).rounded(.up)
    }
    package var musicCameraGap: CGFloat { cameraWidth }
    package var compactMusicLabelInset: CGFloat {
        let height = compactActivityContentHeight
        let shoulder = NotchLayout.shoulder(height: height)
        let bottom = NotchLayout.surfaceRadius(height: height)
        // Wings normally provide this room. When menus hide them, the center
        // text must also clear the silhouette's shoulders and bottom corners.
        return max(4, shoulder + bottom + 4 - compactActivityWingWidth)
    }
    /// Both timer wings take the width the wider side needs, so a short
    /// reading leaves no band of empty black at the ends. A download beside
    /// the clock keeps room for its percentage.
    package func compactTimerGeometry(showsDownloads: Bool,
                              wing fitted: CGFloat = NotchTimerSupport.stripWingRange.upperBound) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        let range = NotchTimerSupport.stripWingRange
        let wing = showsDownloads ? NotchDownloadSupport.companionWing : min(range.upperBound, max(range.lowerBound, fitted.isFinite ? fitted.rounded(.up) : 0))
        compact.compactSideRoom = room.isFinite && room >= 64 ? min(wing, room) : 0
        // A wider simulated camera must not consume the timer's text budget.
        compact.minimumCompactWidth = cameraWidth + wing * 2
        // Menu changes, including full-screen transitions, must not push the
        // timer below the camera. Its expanded view remains available by click.
        compact.allowsActivityFooter = false
        return compact
    }
    /// A download keeps its arrow and progress beside the camera. Where the
    /// menus leave room, its name can take a wider wing without a fixed band.
    package func compactDownloadGeometry(wing: CGFloat = 56) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        compact.compactSideRoom = room.isFinite && room >= 44 ? min(wing, room) : 0
        compact.minimumCompactWidth = cameraWidth + wing * 2
        return compact
    }
    package static let calendarWingRange: ClosedRange<CGFloat> = 72...120
    /// Give the title useful space beside the camera, as wide as the title or
    /// the clock needs, so neither wing ends in a band of empty black. When
    /// menus leave less than a readable wing, a physical notch uses one row
    /// below the camera. Paired with another activity, the wings hold no
    /// title, only the event's clock and the other's mark, so they fit those
    /// as a timer's pair does instead of keeping a title's minimum.
    package var compactCalendarGeometry: NotchGeometry { compactCalendarGeometry(wing: Self.calendarWingRange.upperBound) }
    package func compactCalendarGeometry(wing: CGFloat, paired: Bool = false) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        let range = Self.calendarWingRange
        let lowest = paired ? NotchTimerSupport.stripWingRange.lowerBound : range.lowerBound
        let fitted = min(range.upperBound, max(lowest, wing.isFinite ? wing.rounded(.up) : 0))
        // The narrowest wing still drawn: a readable title, or a whole pair.
        let readable = min(fitted, range.lowerBound)
        compact.compactSideRoom = room.isFinite && room >= readable ? min(fitted, room) : 0
        compact.minimumCompactWidth = cameraWidth + fitted * 2
        compact.minimumWing = readable
        return compact
    }
    /// A working agent keeps its mark and one reading beside the camera,
    /// never below it, like the timer. Both wings take the width the reading
    /// needs, so a short one leaves no band of empty black at the ends.
    package func compactAgentGeometry(wing: CGFloat) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        let fitted = min(NotchAgentSupport.stripWingRange.upperBound,
                         max(NotchAgentSupport.stripWingRange.lowerBound, wing.isFinite ? wing.rounded(.up) : 0))
        compact.compactSideRoom = room.isFinite && room >= NotchAgentSupport.stripWingRange.lowerBound ? min(fitted, room) : 0
        compact.minimumCompactWidth = cameraWidth + fitted * 2
        compact.allowsActivityFooter = false
        return compact
    }
    /// A watched area keeps its mark and its reading beside the camera,
    /// never below it, with wings as wide as the reading needs.
    package func compactWatchGeometry(wing: CGFloat) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        let range = NotchWatchSupport.stripWingRange
        let fitted = min(range.upperBound, max(range.lowerBound, wing.isFinite ? wing.rounded(.up) : 0))
        compact.compactSideRoom = room.isFinite && room >= range.lowerBound ? min(fitted, room) : 0
        compact.minimumCompactWidth = cameraWidth + fitted * 2
        compact.allowsActivityFooter = false
        return compact
    }
    package var musicStrip: CGSize {
        let preferred = min(max(layout == .spacious ? 520 : 440, cameraWidth + 88, minimumCompactWidth), maximumSurfaceWidth)
        let measuredRoom = compactSideRoom ?? 0
        let room = measuredRoom.isFinite ? max(0, measuredRoom).rounded(.down) : 0
        let wings = min(max(0, preferred - cameraWidth), room * 2)
        return CGSize(width: cameraWidth + (wings >= minimumWing * 2 ? wings : 0), height: stripHeight)
    }
    package var musicWingWidth: CGFloat { max(0, (musicStrip.width - musicCameraGap) / 2) }

    /// Only a physical camera may need a footer. A simulated cutout and all
    /// of its compact activity stay within the real menu bar's height.
    package var compactActivityUsesFooter: Bool { isNotched && allowsActivityFooter && musicWingWidth < 44 }
    package var compactActivityContentHeight: CGFloat { compactActivityUsesFooter ? 32 : stripHeight }
    package var compactActivityTopPadding: CGFloat { compactActivityUsesFooter ? stripHeight : 0 }
    package var compactActivityHorizontalPadding: CGFloat { compactActivityUsesFooter ? 4 : 0 }
    package var compactActivityCameraGap: CGFloat { compactActivityUsesFooter ? 0 : musicCameraGap }
    package var compactActivitySize: CGSize {
        compactActivityUsesFooter
            ? CGSize(width: cameraWidth, height: compactActivityTopPadding + compactActivityContentHeight)
            : musicStrip
    }
    package var compactActivityWingWidth: CGFloat {
        max(0, (compactActivitySize.width - compactActivityCameraGap - compactActivityHorizontalPadding * 2) / 2)
    }
    /// Where the silhouette's straight edge sits, once its shoulder has flared.
    package var compactActivityShoulder: CGFloat {
        NotchLayout.shoulder(height: compactActivitySize.height)
    }
    /// Inset that keeps a round mark `side` across an even gap from the
    /// strip's silhouette.
    package func compactMarkInset(side: CGFloat) -> CGFloat {
        compactActivityEdgeInset(boxHeight: side, radius: side / 2)
    }

    /// Inset that keeps a line of digits `textSize` tall an even gap from the
    /// strip's silhouette. Digits carry no descenders, so their ink is about
    /// the cap height. Every compact reading is measured and drawn with it.
    package func compactReadingInset(textSize: CGFloat) -> CGFloat {
        compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0)
    }

    /// Inset that keeps a vertically centred box of `boxHeight`, itself rounded
    /// by `radius`, an even `gap` away from the strip's silhouette.
    /// A strip is barely taller than its corners, so its lower half is one long
    /// arc: padding measured against the straight edge still leaves artwork and
    /// meters grazing the curve. Push the box in until its own corner keeps the
    /// same distance from the arc that its top keeps from the shoulder.
    package func compactActivityEdgeInset(boxHeight: CGFloat, radius: CGFloat,
                                  gap: CGFloat = NotchLayout.compactEdgeGap) -> CGFloat {
        let shoulder = compactActivityShoulder
        let corner = min(NotchLayout.surfaceRadius(height: compactActivitySize.height),
                         (compactActivitySize.width - shoulder * 2) / 2)
        let flat = shoulder + gap - compactActivityHorizontalPadding
        let below = (compactActivityContentHeight - boxHeight) / 2
        // Both corner centres, grown by the gap, decide the horizontal offset.
        let reach = corner - radius - gap
        let drop = corner - radius - below
        guard reach > 0, drop > 0 else { return max(0, flat) }
        let span = reach > drop ? (reach * reach - drop * drop).squareRoot() : 0
        return max(0, flat, shoulder + corner - radius - span - compactActivityHorizontalPadding)
    }
    package var notice: CGSize {
        noticeSize(wingWidth: 80)
    }
    package var noticeCameraGap: CGFloat { cameraWidth }

    package func noticeSize(wingWidth: CGFloat) -> CGSize {
        CGSize(width: min(maximumSurfaceWidth, noticeCameraGap + wingWidth * 2), height: stripHeight)
    }

    package func noticeWingWidth(preferred: CGFloat) -> CGFloat {
        max(0, (noticeSize(wingWidth: preferred).width - noticeCameraGap) / 2)
    }
    /// A held notification opens as a card about as wide as a native banner,
    /// never wider than the island itself.
    package var notificationPreviewWidth: CGFloat { min(max(400, cameraWidth + 200), expandedWidth) }
    package var notificationPreviewContentWidth: CGFloat {
        max(0, notificationPreviewWidth - NotchLayout.horizontalInset * 2)
    }
    package func notificationPreviewSize(contentHeight: CGFloat) -> CGSize {
        let height = safeContentTop + max(0, contentHeight) + NotchLayout.bottomInset
        return CGSize(width: notificationPreviewWidth, height: min(height, maximumSurfaceHeight))
    }
    /// The widest and tallest the island grows: the display less the room
    /// it keeps to the sides and below its tallest page.
    package var maximumSurfaceWidth: CGFloat { screen.width - NotchLayout.displaySideMargins }
    package var maximumSurfaceHeight: CGFloat { screen.height - NotchLayout.displayBottomMargin }
    package var peek: CGSize {
        CGSize(width: min(maximumSurfaceWidth, max(cameraWidth + 110, 340)),
               height: safeContentTop + NotchLayout.navigationHeight + NotchLayout.bottomInset)
    }
    /// The island holding the drop hint while a file is dragged to it.
    package var dropPlaceholder: CGSize {
        CGSize(width: peek.width, height: safeContentTop + NotchLayout.dropHintHeight + NotchLayout.dropHintBottomGap)
    }
    /// The capture controls folded around the camera.
    package var collapsedCaptureControls: CGSize {
        CGSize(width: cameraWidth + NotchLayout.captureCollapsedSide * 2, height: stripHeight)
    }
    package var expanded: CGSize { expandedSize(module: .controls) }
    package var expandedWidth: CGFloat {
        let preferred = NotchLayout.preferredWidth(layout, custom: customWidth)
        return min(max(preferred, cameraWidth + 36), maximumSurfaceWidth - NotchQuickAccessLayout.gutter * 2)
    }
    package var contentWidth: CGFloat { max(0, expandedWidth - NotchLayout.horizontalInset * 2) }
    /// Content height available before a page needs to scroll.
    package var contentBudget: CGFloat {
        switch layout {
        case .compact: return NotchLayout.compactContentHeight
        case .spacious: return NotchLayout.spaciousContentHeight
        case .custom: return max(0, customHeight - headerTopInset - headerChromeHeight)
        }
    }
    /// Room a vertical surface gets: the budget, or a readable page where a
    /// preset's strip would leave it a few lines.
    package var pageBudget: CGFloat { layout == .custom ? contentBudget : max(contentBudget, NotchLayout.pageContentHeight) }
    /// Lyrics and the queue open below the player; custom heights keep them
    /// within the chosen limit and the page swaps the player out instead.
    package var musicExtrasHeight: CGFloat { layout == .custom ? min(216, contentBudget) : 216 }


    package func toolRows(count: Int) -> Int {
        NotchLayout.railRows(count: count,
                             perRow: NotchLayout.railCapacity(width: contentWidth, itemWidth: NotchLayout.toolWidth, spacing: NotchLayout.toolSpacing),
                             rowHeight: NotchLayout.toolHeight, spacing: NotchLayout.toolSpacing, height: contentBudget)
    }

    /// The arrows walk the tiles the way the rail draws them: reading order
    /// while every column fits, the columns it fills once it scrolls.
    package func toolFlow(count: Int) -> QuickToolsSupport.GridFlow {
        let rows = toolRows(count: count)
        let columns = NotchLayout.railColumns(count: count, rows: rows)
        return NotchLayout.railFits(columns: columns, itemWidth: NotchLayout.toolWidth,
                                    spacing: NotchLayout.toolSpacing, width: contentWidth)
            ? .rows(columns: columns) : .columns(rows: rows)
    }

    /// `toolCount` is nil while the launcher edits its grid or hosts a
    /// utility: those need the page, not a rail. `detailHeight` is a
    /// detail's measured content, which it fits instead of the whole page.
    package func expandedSize(module: NotchModule, detail: Bool = false, panel: Bool = false,
                      detailHeight: CGFloat? = nil, shortcutCount: Int = 4,
                      sliderCount: Int = 2, controlsHaveMusic: Bool = false, musicHasContent: Bool = true,
                      musicHasControlsRow: Bool = true, musicExtraHeight: CGFloat = 0,
                      fileMediaHeight: CGFloat? = nil, systemCards: Int = 6, toolCount: Int? = 8,
                      capturePreviewHeight: CGFloat? = nil,
                      timerHasSession: Bool = false, timerMode: NotchTimerMode = .timer,
                      agentsHeight: CGFloat? = nil) -> CGSize {
        let budget = contentBudget
        let showsCapturePreview = module == .captures && !detail && capturePreviewHeight != nil
        let showsFileMedia = module == .files && !detail && fileMediaHeight != nil
        let contentHeight: CGFloat
        if detail, !panel, let detailHeight {
            contentHeight = min(pageBudget, max(0, detailHeight) + NotchLayout.scrollBottomPadding)
        } else if detail || panel {
            contentHeight = pageBudget
        } else if showsFileMedia {
            // Measured surfaces keep their own height; the custom limit and
            // the display bound them below.
            contentHeight = max(0, fileMediaHeight ?? 0)
        } else if showsCapturePreview {
            contentHeight = max(0, capturePreviewHeight ?? 0) + NotchLayout.scrollBottomPadding
        } else {
            switch module {
            case .controls:
                let sliders = min(2, max(0, sliderCount))
                let home = NotchLayout.controls(hasCards: controlsHaveMusic || sliders > 0, shortcutCount: max(0, shortcutCount),
                                                width: contentWidth, height: budget)
                contentHeight = min(budget, home.height == 0 ? NotchLayout.emptyHeight : home.height)
            case .music:
                let controlsRow = NotchLayout.musicControlsRow(musicHasControlsRow)
                let player = NotchLayout.musicMainHeight(hasPlayback: musicHasContent, layout: layout, height: budget)
                contentHeight = min(budget, player + controlsRow) + max(0, musicExtraHeight)
            case .system:
                let cards = max(0, systemCards)
                contentHeight = min(budget, cards == 0 ? NotchLayout.emptyHeight
                    : NotchLayout.systemGridHeight(count: cards, width: contentWidth))
            case .tools:
                guard let toolCount else { contentHeight = pageBudget; break }
                contentHeight = min(budget, toolCount == 0 ? NotchLayout.emptyHeight
                    : NotchLayout.railHeight(rows: toolRows(count: toolCount), rowHeight: NotchLayout.toolHeight, spacing: NotchLayout.toolSpacing))
            case .timer:
                contentHeight = min(budget, NotchLayout.timer(mode: timerMode, hasSession: timerHasSession, width: contentWidth, height: budget))
            case .agents:
                // Only the cards a person chose; a short set leaves a short island.
                contentHeight = min(budget, agentsHeight.map { $0 > 0 ? $0 : NotchLayout.emptyHeight } ?? budget)
            // Lists and previews fill the chosen content budget.
            case .mixer, .calendar, .clipboard, .captures, .files, .notifications, .downloads, .camera, .scratchpad, .watch:
                contentHeight = budget
            }
        }
        var preferredHeight = headerTopInset + headerChromeHeight + contentHeight
        if layout == .custom { preferredHeight = min(preferredHeight, customHeight) }
        return CGSize(width: expandedWidth,
                      height: min(preferredHeight, maximumSurfaceHeight - quickAccessBottomInset))
    }

    /// Leave room for the row indicator without narrowing the tiles below
    /// their readable width. Keyboard navigation uses these same columns.
    package var sectionColumns: Int {
        NotchLayout.railCapacity(width: contentWidth - NotchLayout.sectionIndicatorWidth, itemWidth: NotchLayout.sectionTileWidth,
                                 spacing: NotchLayout.sectionSpacing)
    }

    /// Visible rows. The gallery is a page like the app panel, so a preset
    /// shows three rows before any row has to step in; the rest step in whole.
    package func sectionRows(count: Int) -> Int {
        NotchLayout.railRows(count: count,
                             perRow: sectionColumns,
                             rowHeight: NotchLayout.sectionTileHeight, spacing: NotchLayout.sectionSpacing, height: pageBudget)
    }

    package func sectionPickerSize(count: Int) -> CGSize {
        let content = min(pageBudget, count == 0 ? NotchLayout.emptyHeight
            : NotchLayout.railHeight(rows: sectionRows(count: count), rowHeight: NotchLayout.sectionTileHeight, spacing: NotchLayout.sectionSpacing))
        let desiredHeight = headerTopInset + headerChromeHeight + content
        return CGSize(width: expandedWidth, height: min(desiredHeight, maximumSurfaceHeight - quickAccessBottomInset))
    }

    package func contentSize(for size: CGSize) -> CGSize {
        CGSize(width: max(0, size.width - NotchLayout.horizontalInset * 2),
               height: max(0, size.height - headerTopInset - headerChromeHeight))
    }
    package var appPanelSize: CGSize { contentSize(for: expandedSize(module: .tools, panel: true)) }
    package func frame(for size: CGSize) -> CGRect {
        CGRect(x: screen.midX - size.width / 2,
               y: screen.maxY - floatingDrop - size.height,
               width: size.width, height: size.height)
    }

    package func contains(_ point: CGPoint, in size: CGSize) -> Bool {
        let frame = self.frame(for: size)
        // Match the flipped native view: the top edge belongs to the island.
        return CGRect(origin: .zero, size: size).contains(
            CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y))
    }
}

package struct NotchSessionState {
    package var locked = false
    package var sleeping = false
    package var displaysSleeping = false
    package var onConsole = true
    /// Only the lock screen gives way to a screen saver, which it would
    /// otherwise float over; the island keeps its own rules.
    package var screenSaverRunning = false
    package var canRunTimer: Bool { !locked && !sleeping && onConsole }
    package var canPresent: Bool { canRunTimer && !displaysSleeping }
    /// The lock screen itself is on screen, awake and in front of this user.
    package var showsLockScreen: Bool { locked && !sleeping && onConsole && !displaysSleeping && !screenSaverRunning }
    /// Someone is at the Mac to hear it lock or unlock, rather than closing
    /// the lid or leaving it to a screen saver or to fall asleep.
    package var hearsLockChange: Bool { !sleeping && onConsole && !displaysSleeping && !screenSaverRunning }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(locked: Bool = false, sleeping: Bool = false, displaysSleeping: Bool = false, onConsole: Bool = true, screenSaverRunning: Bool = false) {
        self.locked = locked
        self.sleeping = sleeping
        self.displaysSleeping = displaysSleeping
        self.onConsole = onConsole
        self.screenSaverRunning = screenSaverRunning
    }
}

/// Reserve enough backing space for both ends. The visible silhouette moves
/// inside it; the native window only shrinks after the transition finishes.
///
/// Each side follows its own spring, as the phone's island does. Growing, the
/// island drops a little ahead of widening and passes its size before it
/// settles; shrinking, it pulls up ahead of narrowing and never passes its
/// target, which for a resting island is the camera it hugs.
package enum NotchMotion {
    /// Departing content has faded out by 0.16 s; the view then swaps it for
    /// the next content, which fades in once the swap is on screen.
    package static let departureHidden: TimeInterval = 0.2

    package struct Spring: Equatable {
        /// Perceptual duration and bounce, as SwiftUI and Core Animation define them.
        package var duration: TimeInterval
        package var bounce: Double

        /// Progress from rest at 0 toward 1.
        package func progress(at time: TimeInterval) -> Double {
            guard time > 0 else { return 0 }
            let natural = 2 * Double.pi / duration
            let damping = 1 - bounce
            if damping >= 1 { return 1 - exp(-natural * time) * (1 + natural * time) }
            let damped = natural * (1 - damping * damping).squareRoot()
            return 1 - exp(-damping * natural * time)
                * (cos(damped * time) + damping * natural / damped * sin(damped * time))
        }

        /// How far past the target the spring swings, as a share of its travel.
        package var overshoot: Double {
            guard bounce > 0 else { return 0 }
            let damping = 1 - bounce
            return exp(-Double.pi * damping / (1 - damping * damping).squareRoot())
        }

        /// This spring, with only as much bounce as keeps the swing within `limit` points.
        package func limited(travel: CGFloat, limit: CGFloat) -> Spring {
            guard bounce > 0, travel > 0, Double(travel) * overshoot > Double(limit) else { return self }
            let share = log(Double(max(limit, 0.01) / travel))
            return Spring(duration: duration, bounce: 1 + share / (Double.pi * Double.pi + share * share).squareRoot())
        }

        // Spelled out because a memberwise initializer never leaves its module.
        package init(duration: TimeInterval, bounce: Double) {
            self.duration = duration
            self.bounce = bounce
        }
    }

    package static let growingWidth = Spring(duration: 0.44, bounce: 0.25)
    package static let growingHeight = Spring(duration: 0.38, bounce: 0.22)
    package static let shrinkingWidth = Spring(duration: 0.30, bounce: 0)
    package static let shrinkingHeight = Spring(duration: 0.26, bounce: 0)
    /// The farthest a side may pass its target. The display always keeps at
    /// least this much free around the island and its floating controls.
    package static let overshootLimit: CGFloat = 12
    /// Sides closer than this to their targets read as settled.
    package static let settledDistance: CGFloat = 0.5

    package static func spring(from: CGFloat, to: CGFloat, width: Bool) -> Spring {
        let spring = to > from ? (width ? growingWidth : growingHeight) : (width ? shrinkingWidth : shrinkingHeight)
        return spring.limited(travel: abs(to - from), limit: overshootLimit)
    }

    /// The spring carrying the island's sides, for controls that ride along them.
    package static func sideSpring(from: CGSize, to: CGSize) -> Spring {
        from.width != to.width ? spring(from: from.width, to: to.width, width: true)
            : spring(from: from.height, to: to.height, width: false)
    }

    /// The perceptual duration of the slower side that moves.
    package static func duration(from: CGSize, to: CGSize) -> TimeInterval {
        var durations: [TimeInterval] = []
        if from.width != to.width { durations.append(spring(from: from.width, to: to.width, width: true).duration) }
        if from.height != to.height { durations.append(spring(from: from.height, to: to.height, width: false).duration) }
        return durations.max() ?? growingWidth.duration
    }

    package static func size(at time: TimeInterval, from: CGSize, to: CGSize) -> CGSize {
        func side(_ start: CGFloat, _ end: CGFloat, width: Bool) -> CGFloat {
            guard start != end else { return end }
            return max(0, start + (end - start) * CGFloat(spring(from: start, to: end, width: width).progress(at: time)))
        }
        return CGSize(width: side(from.width, to.width, width: true), height: side(from.height, to.height, width: false))
    }

    /// When every side that moves first comes within 1% of its travel from
    /// its target: the island has arrived, though it may still swing.
    package static func arrivalTime(from: CGSize, to: CGSize) -> TimeInterval {
        let sides = [(from.width, to.width, true), (from.height, to.height, false)].filter { $0.0 != $0.1 }
        let step = 1.0 / 240
        var time = step
        while time < 2, !sides.allSatisfy({ spring(from: $0.0, to: $0.1, width: $0.2).progress(at: time) >= 0.99 }) {
            time += step
        }
        return sides.isEmpty ? 0 : time
    }

    /// When both sides stay within `settledDistance` of their targets for good.
    package static func settlingTime(from: CGSize, to: CGSize) -> TimeInterval {
        let step = 1.0 / 240
        var settled = step
        var time = step
        while time < 2 {
            let size = size(at: time, from: from, to: to)
            if abs(size.width - to.width) > settledDistance || abs(size.height - to.height) > settledDistance {
                settled = time + step
            }
            time += step
        }
        return settled
    }

    /// Sizes at a steady rate, ending exactly at `to`, and where each falls
    /// within the duration.
    package static func frames(from: CGSize, to: CGSize) -> (sizes: [CGSize], keyTimes: [Double], duration: TimeInterval) {
        let duration = settlingTime(from: from, to: to)
        let count = max(1, Int((duration * 120).rounded(.up)))
        let keyTimes = (0...count).map { Double($0) / Double(count) }
        let sizes = keyTimes.map { $0 == 1 ? to : size(at: duration * $0, from: from, to: to) }
        return (sizes, keyTimes, duration)
    }

    /// Whole, equal margins around `size`, so the island keeps its exact
    /// pixels when the window returns to that size; half a point would round
    /// to a one-pixel jump on a standard-resolution display.
    package static func reservation(_ reserved: CGSize, centring size: CGSize) -> CGSize {
        CGSize(width: size.width + 2 * max(0, (reserved.width - size.width) / 2).rounded(.up),
               height: max(reserved.height, size.height))
    }

    package static func envelope(from: CGSize, to: CGSize) -> CGSize {
        func side(_ start: CGFloat, _ end: CGFloat, width: Bool) -> CGFloat {
            let swing = end > start ? spring(from: start, to: end, width: width).overshoot : 0
            guard swing > 0 else { return max(start, end) }
            return (end + (end - start) * CGFloat(swing)).rounded(.up)
        }
        return CGSize(width: side(from.width, to.width, width: true), height: side(from.height, to.height, width: false))
    }
}

/// How open the glass lip is at each height of a resize. The page leaves the
/// island as soon as it starts closing, so glass closing into a black strip
/// shuts at once: open, the empty glass showed the windows beneath it through
/// the whole collapse. Glass leaving a black strip stays shut until the last
/// stretch, where the page fades in over it. An opening that interrupts a
/// close starts from the openness already on screen.
package struct NotchGlassFade: Equatable {
    /// Where the lip is shut, and the height over which it opens from there.
    package var solidHeight: CGFloat = 0
    package var range: CGFloat = 1

    package static let open = NotchGlassFade()
    package static let stretch: CGFloat = 48

    package func openness(atHeight height: CGFloat) -> CGFloat {
        guard height.isFinite, range > 0 else { return 1 }
        return min(1, max(0, (height - solidHeight) / range))
    }

    /// `current` is the openness on screen at `start`: zero while black.
    package static func plan(from start: CGFloat, to end: CGFloat, endsInGlass: Bool, current: CGFloat) -> NotchGlassFade {
        guard start.isFinite, end.isFinite else { return .open }
        let current = min(1, max(0, current.isFinite ? current : 1))
        let travel = abs(end - start)
        if endsInGlass {
            guard end > start, current < 1 else { return .open }
            if current == 0 {
                let range = min(stretch, travel)
                return NotchGlassFade(solidHeight: end - range, range: max(1, range))
            }
            let range = travel / (1 - current)
            return NotchGlassFade(solidHeight: start - current * range, range: max(1, range))
        }
        return NotchGlassFade(solidHeight: max(start, end), range: 1)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(solidHeight: CGFloat = 0, range: CGFloat = 1) {
        self.solidHeight = solidHeight
        self.range = range
    }
}

/// Free room on both sides of the camera, in Cocoa screen coordinates.
/// Unknown/occupied camera space is distinct from a known zero-width wing.
package enum NotchMenuBarLayout {
    /// A successful AX read can contain menu items from another display.
    /// Without an item on this display, its menu space remains unknown.
    package static func measuredSideRoom(screen: CGRect, cameraWidth: CGFloat, barHeight: CGFloat,
                                 menuItems: [CGRect], statusItems: [CGRect]) -> CGFloat? {
        let bar = CGRect(x: screen.minX, y: screen.maxY - barHeight, width: screen.width, height: barHeight)
        guard menuItems.contains(where: { $0.intersects(bar) }) else { return nil }
        return sideRoom(screen: screen, cameraWidth: cameraWidth, barHeight: barHeight,
                        occupied: menuItems + statusItems)
    }

    package static func sideRoom(screen: CGRect, cameraWidth: CGFloat, barHeight: CGFloat,
                         occupied: [CGRect]) -> CGFloat? {
        let bar = CGRect(x: screen.minX, y: screen.maxY - barHeight, width: screen.width, height: barHeight)
        let camera = CGRect(x: screen.midX - cameraWidth / 2, y: bar.minY,
                            width: cameraWidth, height: barHeight)
        var left = screen.minX + 8
        var right = screen.maxX - 8
        for rect in occupied where rect.intersects(bar) {
            guard rect.minX.isFinite, rect.maxX.isFinite, rect.width > 0 else { return nil }
            if rect.intersects(camera) { return nil }
            if rect.maxX <= camera.minX { left = max(left, rect.maxX + 8) }
            if rect.minX >= camera.maxX { right = min(right, rect.minX - 8) }
        }
        return max(0, min(camera.minX - left, right - camera.maxX))
    }
}

/// The dimming over the island's Liquid Glass, top to bottom. The glass is
/// clear, not blurred, so wherever the black thins a window's text behind it
/// reads through the island's own. The page and its cards stay over black,
/// and only the margin below the page opens into the glass lip.
package enum NotchGlassLip {
    /// The margin below the page, which holds no content.
    package static let depth = NotchLayout.bottomInset
    /// How much of the glass the lip lets through at its lowest edge.
    package static let transparency = 0.45
    package static let increasedContrastTransparency = 0.10

    package static func opacity(atDepth depth: CGFloat, height: CGFloat,
                        openness: Double, increasedContrast: Bool) -> Double {
        let lipTop = height - Self.depth
        guard depth > lipTop else { return 1 }
        let ramp = Double(min(1, (depth - lipTop) / Self.depth))
        let eased = ramp * ramp * (3 - 2 * ramp)
        return 1 - min(1, max(0, openness))
            * (increasedContrast ? increasedContrastTransparency : transparency) * eased
    }

    /// Gradient stops over an island `height` points tall, top to bottom.
    package static func stops(height: CGFloat, openness: Double,
                      increasedContrast: Bool) -> [(location: Double, opacity: Double)] {
        guard height > 0 else { return [(0, 1), (1, 1)] }
        let lipTop = max(0, height - Self.depth)
        let depths = [0, lipTop] + (1...8).map { lipTop + (height - lipTop) * CGFloat($0) / 8 }
        return depths.map {
            (Double($0 / height), opacity(atDepth: $0, height: height,
                                          openness: openness, increasedContrast: increasedContrast))
        }
    }
}

/// The black tint over the open island's translucent background, measured in
/// points from the top: fully black over the camera strip at every island
/// height (the hover preview is only the strip plus 62 points), then easing
/// toward the translucent body.
package enum NotchTranslucentTint {
    package static let rampLength: CGFloat = 36

    package static func opacity(atDepth depth: CGFloat, stripHeight: CGFloat,
                        openness: Double, increasedContrast: Bool) -> Double {
        guard depth > stripHeight else { return 1 }
        let ramp = Double(min(1, (depth - stripHeight) / rampLength))
        let eased = ramp * ramp * (3 - 2 * ramp)
        return 1 - min(1, max(0, openness)) * (increasedContrast ? 0.3 : 0.62) * eased
    }

    /// Gradient stops over an island `height` points tall, top to bottom.
    package static func stops(height: CGFloat, stripHeight: CGFloat, openness: Double,
                      increasedContrast: Bool) -> [(location: Double, opacity: Double)] {
        guard height > 0 else { return [(0, 1), (1, 1)] }
        let depths = [0, stripHeight] + (1...8).map { stripHeight + rampLength * CGFloat($0) / 8 } + [height]
        return depths.filter { $0 >= 0 && $0 <= height }.map {
            (Double($0 / height), opacity(atDepth: $0, stripHeight: stripHeight,
                                          openness: openness, increasedContrast: increasedContrast))
        }
    }
}
