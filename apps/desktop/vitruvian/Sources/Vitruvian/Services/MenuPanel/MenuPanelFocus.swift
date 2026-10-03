// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI
import VitruvianCore
import VitruvianDesign

extension Notification.Name {
    package static let menuPanelWillShow = Notification.Name("VitruvianMenuPanelWillShow")
}

package struct MenuPanelFocusRequest: Equatable {
    package let target: MenuPanelFocusTarget
    package let serial: Int

    // Spelled out because a memberwise initializer never leaves its module.
    package init(target: MenuPanelFocusTarget, serial: Int) {
        self.target = target
        self.serial = serial
    }
}

package enum MenuPanelFocusTarget: Equatable {
    case normal
    case section(PanelSectionID)
    case metric(MetricDetailKind)
}

package final class MenuPanelFocus: ObservableObject {
    package static let shared = MenuPanelFocus()

    @Published package private(set) var request: MenuPanelFocusRequest?
    @Published package private(set) var activeMetric: MetricDetailKind?
    @Published package private(set) var isSwitchingMetricAnchor = false
    @Published package private(set) var popoverIsVisible = false
    private var serial = 0

    private init() {}

    package func showNormalPanel() {
        serial += 1
        activeMetric = nil
        request = MenuPanelFocusRequest(target: .normal, serial: serial)
    }

    package func focus(_ section: PanelSectionID) {
        serial += 1
        activeMetric = nil
        request = MenuPanelFocusRequest(target: .section(section), serial: serial)
    }

    package func focus(_ metric: MetricDetailKind) {
        serial += 1
        activeMetric = metric
        request = MenuPanelFocusRequest(target: .metric(metric), serial: serial)
    }

    package func clearMetricFocus() {
        activeMetric = nil
    }

    package func setSwitchingMetricAnchor(_ switching: Bool) {
        isSwitchingMetricAnchor = switching
    }

    package func setPopoverVisible(_ visible: Bool) {
        guard popoverIsVisible != visible else { return }
        popoverIsVisible = visible
    }
}
