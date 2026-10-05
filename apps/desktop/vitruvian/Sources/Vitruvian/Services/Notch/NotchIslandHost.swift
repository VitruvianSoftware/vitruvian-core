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

    func containsHover(_ screenPoint: CGPoint) -> Bool
    func contains(_ screenPoint: CGPoint) -> Bool
    func containsDestination(_ screenPoint: CGPoint) -> Bool
    func containsSurface(_ screenPoint: CGPoint) -> Bool
    func blocksHoverReveal() -> Bool

    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition,
                 quickAccess: NotchQuickAccessConfiguration?, revealFromHidden: Bool,
                 hideWhenSettled: Bool, usesGlass: Bool)
    func hide(animated: Bool, transitionContent: NotchContentTransition)
    func finishDeparture()
    func whenSettled(_ action: @escaping @MainActor () -> Void)
    func close()

    func setMouseEventsIgnored(_ ignored: Bool)
    func setFileDropActions(_ actions: NotchFileDropActions?)
    func setOutline(enabled: Bool, color: NSColor)
    func setHoverHandler(_ handler: @escaping (Bool) -> Void)
    func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void)
}

extension NotchWindowHost: NotchIslandHost {}
