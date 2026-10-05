// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// What a button pressed while Mouse settings wait for one means. The
/// shortcut capture and the Spaces drag capture each refuse what they cannot
/// take, in their own words, and take the rest.
package enum MouseButtonCapture {
    package enum Kind: Equatable {
        case shortcut
        case spaces
    }

    package enum Outcome: Equatable {
        /// The capture cannot use this input at all.
        case unsupported
        /// The radial menu already opens on it.
        case wheel
        /// Another mapping, or one half-way through becoming a shortcut, holds it.
        case taken
        case accept
    }

    /// - Parameters:
    ///   - mapped: whether the button already has a shortcut.
    ///   - pending: the button half-way through becoming a shortcut. The drag
    ///     capture refuses it too: finishing that shortcut would otherwise
    ///     leave the drag's row naming a button the shortcut took.
    ///   - spacesButton: the drag's button while the drag is switched on.
    package static func outcome(_ kind: Kind, button: Int64, mapped: (Int64) -> Bool, pending: Int64?,
                                spacesButton: Int64? = nil,
                                wheelClaims: (Int64) -> Bool = { RadialMenuSupport.claimsMouseButton($0) }) -> Outcome {
        let usable = kind == .shortcut ? MouseButtonShortcutSupport.canMap(button)
            : MouseSpacesGestureSupport.canBind(button)
        if !usable { return .unsupported }
        if wheelClaims(button) { return .wheel }
        if mapped(button) || pending == button { return .taken }
        if kind == .shortcut, spacesButton == button { return .taken }
        return .accept
    }

    /// What the capture says about a button it refuses. The drag's refusals
    /// recommend only what the drag takes and point at no list, since the
    /// shortcut list may be off screen.
    package static func feedback(_ outcome: Outcome, _ kind: Kind, text: MouseButtonFeatureStrings) -> String? {
        switch (outcome, kind) {
        case (.accept, _): return nil
        case (.unsupported, .shortcut): return text.captureUnsupported
        case (.unsupported, .spaces): return text.spacesCaptureUnsupported
        case (.wheel, _): return text.captureWheel
        case (.taken, .shortcut): return text.captureExists
        case (.taken, .spaces): return text.spacesCaptureExists
        }
    }

    /// The prompt while the capture waits. The shortcut's invites the side
    /// wheel, which the drag refuses, so the drag has its own.
    package static func waitingPrompt(_ kind: Kind, text: MouseButtonFeatureStrings) -> String {
        kind == .shortcut ? text.captureWaiting : text.spacesCaptureWaiting
    }

    /// The drag's button once its switch changes. Switching the drag off
    /// drops its binding: its row is gone, so a kept binding could only act
    /// unseen, refusing the button to shortcut capture and coming back dead
    /// under a shortcut recorded meanwhile.
    package static func spacesButton(afterSwitch on: Bool, current: Int) -> Int {
        on ? current : 0
    }

    /// Whether either mouse-button switch is on. Both drive the same tap and
    /// need the same grant (issue #1012), so every surface reads them
    /// together; widening one and not the rest leaves a row asking for a
    /// permission its own button cannot grant.
    package static func isEngaged(shortcuts: Bool, spaces: Bool) -> Bool {
        shortcuts || spaces
    }
}
