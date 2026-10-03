// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign

package enum MetricDetailKind: String, Equatable, Identifiable {
    case cpu, gpu, memory, network, disk, battery, power, fan, connectedDevices

    package var id: String { rawValue }

    package var panelSection: PanelSectionID {
        switch self {
        case .cpu, .gpu, .memory, .connectedDevices:
            return .system
        case .network:
            return .network
        case .disk:
            return .disk
        case .battery, .power:
            return .power
        case .fan:
            return .fanControl
        }
    }

    package var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "rectangle.connected.to.line.below"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .battery: return "battery.100"
        case .power: return "powerplug.fill"
        case .fan: return "fanblades"
        case .connectedDevices: return "cable.connector"
        }
    }

    package var monitorNeeds: SystemMonitorPanelNeeds {
        switch self {
        case .cpu:
            return SystemMonitorPanelNeeds(cpu: true, cpuTemperature: true)
        case .gpu:
            return SystemMonitorPanelNeeds(gpu: true, gpuTemperature: true)
        case .memory:
            return SystemMonitorPanelNeeds(memory: true)
        case .network:
            return SystemMonitorPanelNeeds(network: true)
        case .disk:
            return SystemMonitorPanelNeeds(disk: true)
        case .battery:
            if PowerSampler.hasInternalBattery {
                return SystemMonitorPanelNeeds(power: true,
                                               battery: true,
                                               peripheralBattery: true,
                                               batteryTemperature: true)
            }
            return SystemMonitorPanelNeeds(peripheralBattery: true)
        case .power:
            return SystemMonitorPanelNeeds(power: true)
        case .fan:
            return SystemMonitorPanelNeeds(fanSpeed: true)
        case .connectedDevices:
            return SystemMonitorPanelNeeds(connectedDevices: true)
        }
    }

    package func title(_ s: Strings) -> String {
        switch self {
        case .cpu: return s.cpuLabel
        case .gpu: return s.gpuLabel
        case .memory: return s.memorySection
        case .network: return s.networkSection
        case .disk: return s.diskSection
        case .battery: return s.batteryLabel
        case .power: return s.powerSection
        case .fan: return FeatureStrings.fanControl(L10n.shared.language).menuBarTitle
        case .connectedDevices: return FeatureStrings.connectedDevices(L10n.shared.language).title
        }
    }

    package var processKind: BreakdownKind? {
        switch self {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .memory: return .memory
        case .power: return .energy
        case .network: return .network
        case .disk, .battery, .fan, .connectedDevices: return nil
        }
    }
}

extension MenuBarMetric {
    package var detailKind: MetricDetailKind {
        switch self {
        case .cpu, .cpuTemperature:
            return .cpu
        case .gpu, .gpuTemperature:
            return .gpu
        case .memory:
            return .memory
        case .network:
            return .network
        case .diskUsage, .diskActivity:
            return .disk
        case .battery, .batteryTemperature, .peripheralBattery:
            return .battery
        case .batteryTime, .power:
            return .power
        case .fanSpeed:
            return .fan
        case .connectedDevices:
            return .connectedDevices
        }
    }
}
