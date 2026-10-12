// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianServices

/// When the monitor reads connected devices and every CPU core, through the
/// rules its sampling plan uses, against a scratch defaults suite.
enum SystemMonitorPlanTests {
    static func run(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.system-monitor-plan"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: AppFeature.connectedDevices.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.menuBarConnectedDevices)
        func reads(fullMonitorVisible: Bool = false, panel: SystemMonitorPanelNeeds = .none,
                   island: SystemMonitorPanelNeeds = .none) -> Bool {
            SystemMonitor.readsConnectedDevices(fullMonitorVisible: fullMonitorVisible,
                                                panelNeeds: panel.merging(island), defaults: defaults)
        }

        suite.expect(!reads(), "connected devices are not read while no surface shows them")
        defaults.set(true, forKey: DefaultsKey.monitorSysConnectedDevices)
        suite.expect(reads(panel: SystemMonitorPanelNeeds(system: true)),
                     "the panel's System card reads connected devices for its device row")
        defaults.set(false, forKey: DefaultsKey.monitorSysConnectedDevices)
        suite.expect(!reads(panel: SystemMonitorPanelNeeds(system: true)),
                     "a hidden device row stops the System card's USB reads")
        suite.expect(reads(panel: SystemMonitorPanelNeeds(connectedDevices: true)),
                     "the device list still reads connected devices with the System row hidden")
        suite.expect(reads(island: SystemMonitorPanelNeeds(connectedDevices: true)),
                     "the island System page's device card ignores the panel row's toggle")
        suite.expect(reads(fullMonitorVisible: true),
                     "the Settings island preview reads connected devices for its card")
        defaults.set(true, forKey: DefaultsKey.menuBarConnectedDevices)
        suite.expect(reads(), "a connected devices item in the menu bar reads them on its own")
        defaults.set(false, forKey: AppFeature.connectedDevices.availabilityKey)
        suite.expect(!reads(fullMonitorVisible: true, panel: SystemMonitorPanelNeeds(connectedDevices: true)),
                     "an uninstalled connected devices feature is not read, even for the preview")

        let system = SystemMonitorPanelNeeds(system: true)
        func readsCores(_ needs: SystemMonitorPanelNeeds) -> Bool {
            SystemMonitor.readsCPUCores(panelNeeds: needs, defaults: defaults)
        }
        defaults.set(true, forKey: AppFeature.monitorCPU.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.menuBarCPU)
        defaults.set(true, forKey: DefaultsKey.monitorSysCPU)
        defaults.set(true, forKey: DefaultsKey.monitorSysCPUCores)
        suite.expect(readsCores(system), "the panel's CPU row reads every core for its per-core bars")
        defaults.set(false, forKey: DefaultsKey.monitorSysCPU)
        suite.expect(!readsCores(system),
                     "a CPU shown only in the menu bar does not read every core while the panel hides its CPU row")
        defaults.set(true, forKey: DefaultsKey.monitorSysCPU)
        defaults.set(false, forKey: DefaultsKey.monitorSysCPUCores)
        suite.expect(!readsCores(system), "the Per core switch stops reading every core")
        defaults.set(true, forKey: DefaultsKey.monitorSysCPUCores)
        suite.expect(!readsCores(.none), "a closed panel does not read every core")
        defaults.set(false, forKey: AppFeature.monitorCPU.availabilityKey)
        suite.expect(!readsCores(system), "an uninstalled CPU monitor does not read every core")
    }
}
