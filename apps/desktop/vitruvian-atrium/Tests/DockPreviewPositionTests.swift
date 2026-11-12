// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Where a shown Dock Preview goes when its cards change size, from the
/// frame rules the service places it with. No native windows, Dock changes
/// or synthetic input are used.
enum DockPreviewPositionTests {
    static func run(_ suite: TestSuite) {
        let screen = CGRect(x: -1440, y: 120, width: 1440, height: 900)
        let icons: [(DockPreviewOrientation, CGRect)] = [
            (.bottom, CGRect(x: -780, y: 120, width: 80, height: 80)),
            (.left, CGRect(x: -1440, y: 500, width: 80, height: 80)),
            (.right, CGRect(x: -80, y: 500, width: 80, height: 80)),
        ]
        let configurations: [(Bool, CGFloat)] = [(true, 72), (true, 96), (false, 72), (false, 96)]
        for (orientation, icon) in icons {
            for (autohide, dockThickness) in configurations {
                // A visible Dock's work area, which expands when auto-hide
                // removes the Dock while the pointer is on the panel.
                var withDock = screen
                switch orientation {
                case .bottom:
                    withDock.origin.y += dockThickness
                    withDock.size.height -= dockThickness
                case .left:
                    withDock.origin.x += dockThickness
                    withDock.size.width -= dockThickness
                case .right:
                    withDock.size.width -= dockThickness
                }
                let gap = autohide ? DockPreviewSupport.autohidePanelGap : DockPreviewSupport.panelGap
                func size(_ items: Int, in visible: CGRect) -> CGSize {
                    DockPreviewSupport.panelSize(itemCount: items, screenVisibleFrame: visible, isPinned: false,
                                                 orientation: orientation)
                }
                let opened = DockPreviewSupport.panelFrame(anchor: icon, panelSize: size(3, in: withDock),
                                                           screenVisibleFrame: withDock, orientation: orientation,
                                                           gap: gap)
                let visible = autohide ? screen : withDock
                let resized = DockPreviewSupport.resizedPanelFrame(anchor: icon, panelSize: size(1, in: visible),
                                                                   screenVisibleFrame: visible,
                                                                   orientation: orientation, gap: gap,
                                                                   openedAt: opened)
                let keepsDockFacingEdge: Bool
                switch orientation {
                case .bottom: keepsDockFacingEdge = resized.minY == opened.minY
                case .left: keepsDockFacingEdge = resized.minX == opened.minX
                case .right: keepsDockFacingEdge = resized.maxX == opened.maxX
                }
                suite.expect(resized.size != opened.size && keepsDockFacingEdge,
                             "closing a window resizes the \(orientation) preview at its opening anchor")
            }
        }
    }
}
