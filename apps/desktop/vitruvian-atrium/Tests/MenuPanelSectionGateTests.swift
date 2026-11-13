// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

/// A tab leaves the panel and the Dynamic Island once none of its gate
/// features is installed, so a row whose feature the gate leaves out is
/// unreachable when that feature is the only one installed. The sections and
/// rows are the shipped enums.
enum MenuPanelSectionGateContract {
    static func run(_ suite: TestSuite) {
        suite.expect(MenuPanelRowFeatures.controls.contains(.smoothScroll),
                     "installed smooth scrolling has a menu bar control")
        suite.expect(PanelSectionID.controls.featureGate.contains(.smoothScroll),
                     "smooth scrolling alone keeps the Controls tab available")
        // The panel sanitizes a layout of distinct control ids (ControlPanelItem,
        // private here), so the saved order it merges against has no repeats;
        // some control features map from more than one item (dockClick), so the
        // feature list is deduplicated before standing in for that layout.
        var seenControls = Set<String>()
        let controlOrder = MenuPanelRowFeatures.controls.map(\.rawValue)
            .filter { seenControls.insert($0).inserted }
        let savedOrder = controlOrder.filter { $0 != AppFeature.smoothScroll.rawValue }
        suite.expect(Defaults.sanitizedPanelItemOrder(savedOrder.joined(separator: ","), defaultOrder: savedOrder
                         + [AppFeature.smoothScroll.rawValue]) == savedOrder + [AppFeature.smoothScroll.rawValue],
                     "existing custom control orders gain a new control without losing their order")
        func expectGate(_ section: PanelSectionID, keeps features: [AppFeature], _ rows: String) {
            let missing = features.filter { !section.featureGate.contains($0) }.map(\.rawValue)
            suite.expect(missing.isEmpty,
                         "every \(rows) row keeps the \(section.rawValue) tab available, missing \(missing)")
        }
        expectGate(.controls, keeps: MenuPanelRowFeatures.controls, "control")
        expectGate(.utilities, keeps: MenuPanelRowFeatures.utilities, "utility")
        expectGate(.toggles, keeps: QuickToggleAction.allCases.map(\.feature), "quick toggle")
        expectGate(.system, keeps: [.connectedDevices], "connected devices")
    }
}
