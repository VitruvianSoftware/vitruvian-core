// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Timing constants for composer emoji picker hover open/close and button accent tinting.
public enum EmojiPickerHoverMotion {
    public static let openDelay: TimeInterval = 0.15
    public static let closeDelay: TimeInterval = 0.3
    public static let iconTintDuration: TimeInterval = 0.1
}

/// Presentation mode of the composer's emoji picker: closed, open temporarily on hover, or pinned by click/interaction.
public enum EmojiPickerPresentationMode: Equatable, Sendable {
    case closed
    case hoverOpen
    case pinned
}

/// Pure state machine governing hover-to-open (0.15 s), hover-to-close (0.3 s after leaving both button and picker),
/// click-to-pin/toggle, and non-focus-stealing rules for the composer emoji picker.
public struct EmojiPickerHoverState: Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        case none
        case scheduleOpen(TimeInterval)
        case cancelOpen
        case scheduleClose(TimeInterval)
        case cancelClose
        case cancelAll
    }

    public private(set) var mode: EmojiPickerPresentationMode = .closed
    public private(set) var isPointerOnButton: Bool = false
    public private(set) var isPointerOnPicker: Bool = false
    /// The picker was dismissed (click, Escape, an emoji chosen, a chat switch). Hover does not open it again until the
    /// pointer has been seen outside the button and outside where the picker was (`pointerSeenOutside()`) and then
    /// comes back to the button. A short window can put the picker over its own button, so "the button is under the
    /// pointer again" is not enough to open it.
    public private(set) var isDisarmed: Bool = false

    public init() {}

    public var isPresented: Bool { mode != .closed }

    public var isIconAccented: Bool { mode != .closed }

    /// Hover-opened pickers do not steal focus from the composer text box until the user interacts with the picker.
    public var shouldAutoFocusSearch: Bool { mode == .pinned }

    public mutating func buttonHoverChanged(_ inside: Bool, canOpen: Bool) -> Effect {
        isPointerOnButton = inside
        if inside {
            switch mode {
            case .hoverOpen:
                return .cancelClose
            case .closed:
                guard !isDisarmed else { return .none }
                return canOpen ? .scheduleOpen(EmojiPickerHoverMotion.openDelay) : .none
            case .pinned:
                return .none
            }
        } else {
            switch mode {
            case .closed:
                return .cancelOpen
            case .hoverOpen:
                return isPointerOnPicker ? .none : .scheduleClose(EmojiPickerHoverMotion.closeDelay)
            case .pinned:
                return .none
            }
        }
    }

    public mutating func pickerHoverChanged(_ inside: Bool) -> Effect {
        isPointerOnPicker = inside
        if inside {
            return mode == .hoverOpen ? .cancelClose : .none
        } else {
            return (mode == .hoverOpen && !isPointerOnButton)
                ? .scheduleClose(EmojiPickerHoverMotion.closeDelay)
                : .none
        }
    }

    /// Fires when the 0.15 s hover-open delay finishes. Returns `true` if the picker opened.
    public mutating func openDelayFired(canOpen: Bool) -> Bool {
        guard mode == .closed, isPointerOnButton, !isDisarmed, canOpen else { return false }
        mode = .hoverOpen
        return true
    }

    /// Fires when the 0.3 s hover-close delay finishes. Returns `true` if the picker closed.
    public mutating func closeDelayFired() -> Bool {
        guard mode == .hoverOpen, !isPointerOnButton, !isPointerOnPicker else { return false }
        mode = .closed
        return true
    }

    /// Click on the emoji button: toggles closed<->pinned, or pins a hover-opened picker open.
    public mutating func buttonClicked(canOpen: Bool) -> Effect {
        switch mode {
        case .closed:
            if canOpen { mode = .pinned }
            return .cancelAll
        case .hoverOpen:
            mode = .pinned
            return .cancelAll
        case .pinned:
            mode = .closed
            isDisarmed = true
            return .cancelAll
        }
    }

    /// The pointer is outside the button and outside the picker's former frame: hover may open the picker again.
    public mutating func pointerSeenOutside() {
        isDisarmed = false
    }

    /// Interacting inside the picker (typing search, choosing tabs/skin tone) pins a hover-opened picker open.
    public mutating func userInteractedWithPicker() -> Effect {
        guard mode == .hoverOpen else { return .none }
        mode = .pinned
        return .cancelClose
    }

    /// External dismissal (Escape, room switch, emoji chosen, lock, click outside).
    public mutating func externalDismiss() -> Effect {
        mode = .closed
        isPointerOnPicker = false
        isDisarmed = true
        return .cancelAll
    }

    /// External open (e.g. `composer.toggleEmojiPicker()` called programmatically or from tests).
    public mutating func externalOpen() -> Effect {
        guard mode == .closed else { return .none }
        mode = .pinned
        return .cancelAll
    }
}
