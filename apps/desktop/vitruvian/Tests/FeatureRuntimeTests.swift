// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The Features hub's runtime (`FeatureRuntime`) over its own defaults, with
/// the binding actions recorded instead of run, so no service comes to life.
enum FeatureRuntimeContract {
    /// What the runtime asked of the live services.
    private final class Log {
        var actions: [FeatureBindingAction] = []
        var changes = 0
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.feature-runtime"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let log = Log()
        func runtime() -> FeatureRuntime {
            FeatureRuntime(environment: .init(defaults: defaults, perform: { log.actions.append($0) },
                                              availabilityDidChange: { log.changes += 1 },
                                              savedPreferences: { [:] }))
        }
        func actions(_ feature: AppFeature) -> [FeatureBindingAction] {
            FeatureRuntime.actions(for: feature, in: defaults)
        }

        // Install all, from nothing installed (registered defaults would
        // otherwise show through).
        for feature in AppFeature.allCases { defaults.set(false, forKey: feature.availabilityKey) }
        let hub = runtime()
        hub.setAllAvailable(true)
        let installable = AppFeature.allCases.filter(\.isHardwareSupported)
        suite.expect(installable.allSatisfy { defaults.bool(forKey: $0.availabilityKey) },
                     "install all makes every feature this Mac can run available")
        // Registered defaults show through every domain, so only what this
        // one wrote tells a switch turned on.
        let written = defaults.persistentDomain(forName: domain) ?? [:]
        suite.expect(Set(AppFeature.allCases.flatMap(\.enabledKeys)).allSatisfy { written[$0] == nil },
                     "install all makes features available without switching on their behavior")
        suite.expect(log.changes == 1 && log.actions.contains(.mouseClickDebounce) && log.actions.contains(.notch),
                     "install all runs each feature's binding and reports one change")

        // One install switches its own control on; a saved choice survives.
        hub.setAvailable([.middleClick], false)
        hub.setAvailable([.middleClick], true)
        suite.expect(defaults.bool(forKey: DefaultsKey.middleClickEnabled),
                     "installing one feature switches on its main control")
        let saved = FeatureRuntime(environment: .init(
            defaults: defaults, perform: { _ in }, availabilityDidChange: {},
            savedPreferences: { [DefaultsKey.middleClickEnabled: false] }))
        defaults.set(false, forKey: DefaultsKey.middleClickEnabled)
        saved.setAvailable([.middleClick], false)
        saved.setAvailable([.middleClick], true)
        suite.expect(!defaults.bool(forKey: DefaultsKey.middleClickEnabled),
                     "a reinstall keeps the switch the person saved")

        // Undoing the never-used offer.
        defaults.set(false, forKey: DefaultsKey.middleClickEnabled)
        hub.setAvailable([.middleClick], false)
        hub.reinstallKept([.middleClick])
        suite.expect(defaults.bool(forKey: AppFeature.middleClick.availabilityKey)
                     && !defaults.bool(forKey: DefaultsKey.middleClickEnabled)
                     && hub.neverSwitchedOnFeatures().allSatisfy { $0 != .middleClick },
                     "undoing the offer reinstalls without switching on what was never on, and keeps the feature")

        // Which services each feature drives.
        suite.expect(actions(.mouseClickDebounce) == [.mouseClickDebounce],
                     "the Features hub owns the click debounce runtime lifecycle")
        suite.expect(Set(AppFeature.allCases.filter { actions($0).contains(.recentCaptures) })
                        == [.screenshot, .screenRecorder],
                     "the capture history follows both capture producers and nothing else")
        suite.expect([AppFeature.monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
                      .connectedDevices].allSatisfy { actions($0) == [.monitorPlan, .monitorAlerts] },
                     "every metric family and connected devices recompute the sampling plan")
        suite.expect([AppFeature.quickToggles, .cleaningMode, .uninstaller, .homebrew, .killProcess, .portManager]
                        .allSatisfy { actions($0).isEmpty },
                     "an on-demand tool has nothing to start or stop")
        suite.expect(actions(.urlCleaner) == [.tool(URLCleanerService.manifest.id)],
                     "a feature that has become a tool is handed to the tool host")

        // The island's extensions follow the island.
        let extensions: [AppFeature: FeatureBindingAction] = [
            .notchTimer: .stopNotchTimer, .notchAccessories: .stopNotchAccessories,
            .notchNotifications: .stopNotchNotifications, .notchDownloads: .stopNotchDownloads,
            .notchCalendar: .stopNotchCalendar, .notchAgents: .stopAgentUsage, .notchWatch: .stopNotchWatch,
        ]
        defaults.set(true, forKey: AppFeature.notch.availabilityKey)
        suite.expect(extensions.keys.allSatisfy { actions($0) == [.notch] } && actions(.notchGestures) == [.notch],
                     "an island extension resyncs the island while it shows")
        defaults.set(false, forKey: AppFeature.notch.availabilityKey)
        suite.expect(extensions.allSatisfy { actions($0.key) == [$0.value] } && actions(.notchGestures).isEmpty,
                     "without the island each extension stops its own service")

        // Uninstalling stops work in flight.
        defaults.set(false, forKey: AppFeature.mediaTools.availabilityKey)
        suite.expect(actions(.mediaTools) == [.fileTools, .cancelMedia, .closeMediaEditors],
                     "uninstalling media tools cancels their work and closes their editors")
        defaults.set(true, forKey: AppFeature.mediaTools.availabilityKey)
        suite.expect(actions(.mediaTools) == [.fileTools], "installed media tools only resync the file tools")
        defaults.set(true, forKey: AppFeature.cleaner.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.whatsAppDownloadsEnabled)
        suite.expect(!actions(.cleaner).contains(.resetWhatsAppDownloads), "kept WhatsApp downloads stay")
        defaults.set(false, forKey: DefaultsKey.whatsAppDownloadsEnabled)
        suite.expect(actions(.cleaner).suffix(2) == [.resetWhatsAppDownloads, .stopWhatsAppOrganizer],
                     "switching WhatsApp downloads off resets and stops them")
    }
}
