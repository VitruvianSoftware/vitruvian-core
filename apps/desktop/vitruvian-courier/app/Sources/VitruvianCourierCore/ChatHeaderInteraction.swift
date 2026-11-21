// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation

/// What the mouse does on the chat's picture and name in its header, which is also where the window's title is: it
/// behaves as Finder's title does. A click (the button comes up without the pointer having moved) shows or hides Chat
/// Info; a drag moves the window; a double click does what the person set for a double click on a title bar (zoom,
/// minimise or nothing).
///
/// Pure: the header's view feeds it the mouse's events and does what it answers, so the rule is tested without a window.
public struct ChatHeaderPointer: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Show or hide Chat Info.
        case toggleInfo
        /// Hand the mouse to the window to move it (`NSWindow.performDrag`).
        case beginWindowDrag
        /// A double click: the first click already toggled Chat Info, so undo that, then do the title bar's action.
        case doubleClick
    }

    /// How far the pointer must move from where the button went down before it is a drag, not a click.
    public static let dragThreshold: CGFloat = 4

    private var downAt: CGPoint?
    private var isDragging = false

    public init() {}

    public mutating func mouseDown(at point: CGPoint) {
        downAt = point
        isDragging = false
    }

    /// The window starts moving once, when the pointer first goes past the threshold.
    public mutating func mouseDragged(to point: CGPoint) -> Action? {
        guard let start = downAt, !isDragging else { return nil }
        guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else { return nil }
        isDragging = true
        return .beginWindowDrag
    }

    /// The button came up. `clickCount` is the mouse event's: 1 for a click, 2 for the second click of a double click.
    public mutating func mouseUp(clickCount: Int) -> Action? {
        defer {
            downAt = nil
            isDragging = false
        }
        guard downAt != nil, !isDragging else { return nil }
        return clickCount >= 2 ? .doubleClick : .toggleInfo
    }
}

/// What a double click on a window's title does, as System Settings › Desktop & Dock › "Double-click a window's title
/// bar to" has it.
public enum TitleBarDoubleClickAction: Equatable, Sendable {
    case zoom
    case minimize
    case none

    /// From the system's `AppleActionOnDoubleClick` ("Maximize", "Fill", "Minimize", "None"; absent means zoom) and the
    /// older `AppleMiniaturizeOnDoubleClick` switch, which counts only when the first is absent.
    public static func from(actionValue: String?, miniaturizeOnDoubleClick: Bool?) -> TitleBarDoubleClickAction {
        switch actionValue?.lowercased() {
        case "minimize": return .minimize
        case "none": return .none
        case "maximize", "fill": return .zoom
        case nil: return miniaturizeOnDoubleClick == true ? .minimize : .zoom
        default: return .zoom
        }
    }

    /// The person's setting, read from the system's defaults.
    public static func current(defaults: UserDefaults = .standard) -> TitleBarDoubleClickAction {
        from(actionValue: defaults.string(forKey: "AppleActionOnDoubleClick"),
             miniaturizeOnDoubleClick: defaults.object(forKey: "AppleMiniaturizeOnDoubleClick") as? Bool)
    }
}

/// What VoiceOver reads for the chat's header: the chat's title, then its network and disappearing-message timer, and
/// what a press does.
public enum ChatHeaderAccessibility {
    public static func label(title: String) -> String { title }

    /// The network (with a group's member count) and the timer, as the header shows them under the title.
    public static func value(subtitle: String?, timer: String?) -> String {
        [subtitle, timer].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    public static func hint(isShowing: Bool) -> String {
        isShowing ? String(localized: "Hides chat info") : String(localized: "Shows chat info")
    }
}
