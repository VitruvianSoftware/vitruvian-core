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
}

extension NotchWindowHost: NotchIslandHost {
    package var hasKeyboard: Bool { panel.isKeyWindow }
    package func takeKeyboard() { panel.makeKey() }
    package func releaseKeyboard() { panel.resignKey() }
}
