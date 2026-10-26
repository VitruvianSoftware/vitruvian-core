// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// What the island asks of the window that draws it. `NotchWindowHost` is the
/// real one; `NotchService.Environment.makeHost` builds it, and a test can
/// build another.
@MainActor
package protocol NotchIslandHost: AnyObject {
    var panel: NotchPanel { get }
    /// The size the island is shown at, or is heading to.
    var targetSize: CGSize { get }
    /// Leaving content stays on screen while the shape closes around it.
    var departsContent: Bool { get }
    var isConcealedForMissionControl: Bool { get }
    var missionControlDidRestore: (() -> Void)? { get set }
    /// The island's window holds the keyboard.
    var hasKeyboard: Bool { get }
    /// Asks for the keyboard, which the window takes while it accepts key focus.
    func takeKeyboard()
    func releaseKeyboard()

    func containsHover(_ screenPoint: CGPoint) -> Bool
    func contains(_ screenPoint: CGPoint) -> Bool
    func containsDestination(_ screenPoint: CGPoint) -> Bool
    func containsSurface(_ screenPoint: CGPoint) -> Bool
    func blocksHoverReveal() -> Bool

    /// `steady` eases a strip that only fits a new reading to its width,
    /// without the island's usual swing.
    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition,
                 quickAccess: NotchQuickAccessConfiguration?, revealFromHidden: Bool,
                 hideWhenSettled: Bool, usesGlass: Bool, steady: Bool)
    func hide(animated: Bool, transitionContent: NotchContentTransition)
    func finishDeparture()
    func whenSettled(_ action: @escaping @MainActor () -> Void)
    func close()

    func setMouseEventsIgnored(_ ignored: Bool)
    func setFileDropActions(_ actions: NotchFileDropActions?)
    func setOutline(enabled: Bool, color: NSColor)
    func setHoverHandler(_ handler: @escaping (Bool) -> Void)
    func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void)

    /// The island on screen as it is drawn now, a moving one included.
    var visibleFrame: CGRect { get }
    /// The companion in the window's own layer while the island opens or
    /// closes around it (`NotchWindowHost.bridgeMascot`).
    func bridgeMascot(look: NotchMascotLook, size: CGFloat, mood: NotchMascotMood, from: CGFloat, to: CGFloat,
                      baseline: CGFloat, duration: CFTimeInterval, scale: (from: CGFloat, to: CGFloat),
                      trailsGrowth: Bool, hop: CGFloat)
    func endMascotBridge(fading: Bool)
    func reactMascotBridge(_ event: NotchMascotReactionEvent, lift: CGFloat)

    /// The window is on screen and nothing attached to it would be lost, so it
    /// can leave and come back when the island changes displays.
    func canRelocateOnScreen() -> Bool
    /// Orders the window out so its frame moves offscreen, which the window
    /// server would otherwise animate across the displays. False when it was
    /// not on screen and needs no return.
    func orderOutForRelocation() -> Bool
    /// Brings a window ordered out for a move back, once its content has been
    /// drawn for the display it is moving to.
    func orderFrontForRelocation()
    /// Drops a pending return, as when a hide or a stop takes over.
    func cancelRelocation()
    /// Repeats the music bars already on `other`, so covering them does not
    /// change that wave for a frame.
    func matchWave(from other: NSView?)
}

/// A host that draws no companion of its own, as a test's, has nothing to
/// show or take away.
extension NotchIslandHost {
    package var visibleFrame: CGRect { .zero }
    package func bridgeMascot(look: NotchMascotLook, size: CGFloat, mood: NotchMascotMood, from: CGFloat, to: CGFloat,
                              baseline: CGFloat, duration: CFTimeInterval, scale: (from: CGFloat, to: CGFloat),
                              trailsGrowth: Bool, hop: CGFloat) {}
    package func endMascotBridge(fading: Bool) {}
    package func reactMascotBridge(_ event: NotchMascotReactionEvent, lift: CGFloat) {}
    package func endMascotBridge() { endMascotBridge(fading: false) }
    package func canRelocateOnScreen() -> Bool { false }
    package func orderOutForRelocation() -> Bool { false }
    package func orderFrontForRelocation() {}
    package func cancelRelocation() {}
    package func matchWave(from other: NSView?) {}
    package func hide(animated: Bool) { hide(animated: animated, transitionContent: .dismiss) }
}

extension NotchWindowHost: NotchIslandHost {
    /// Without a regular window to take the keyboard back, `releaseKeyboard()`
    /// leaves AppKit keeping the island as its key window while the panel's
    /// own flag is clear. AppKit's record still means the island has it.
    package var hasKeyboard: Bool { panel.isKeyWindow || NSApp.keyWindow === panel }
    package func takeKeyboard() { panel.makeKey() }
    package func releaseKeyboard() {
        panel.resignKey()
        NotchKeyboardHandoff.successor(
            of: panel, keyWindow: NSApp.keyWindow,
            appIsFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier,
            ordered: NSApp.orderedWindows,
            takesKeyboard: { $0.isVisible && $0.isOnActiveSpace && $0.canBecomeMain })?.makeKey()
    }
}

/// Where the keyboard goes when the island lets go of it.
@MainActor
package enum NotchKeyboardHandoff {
    /// While this app stays in front, resigning the panel leaves AppKit's key
    /// window as it was, so the Scratchpad's caret and shortcut kept going to
    /// a closed island. The frontmost window that can take the keyboard gets
    /// it back. Nothing is handed over when the island no longer holds the
    /// keyboard or another app is taking over.
    package static func successor<Window: AnyObject>(of panel: Window, keyWindow: Window?, appIsFrontmost: Bool,
                                                     ordered: [Window],
                                                     takesKeyboard: (Window) -> Bool) -> Window? {
        guard keyWindow === panel, appIsFrontmost else { return nil }
        return ordered.first { $0 !== panel && takesKeyboard($0) }
    }
}
