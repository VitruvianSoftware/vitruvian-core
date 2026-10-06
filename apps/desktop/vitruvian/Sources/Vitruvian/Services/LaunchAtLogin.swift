// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ServiceManagement
import VitruvianCore
import VitruvianDesign

/// Launch at login, remembered and self-repairing.
///
/// All UI goes through here so the choice stored in preferences and the real
/// registration never drift apart. `LaunchAtLoginSupport` explains why the
/// system record alone cannot be trusted across relaunches.
package enum LaunchAtLogin {
    /// What the system holds for this app right now.
    package static var registration: LaunchAtLoginSupport.Registration {
        LaunchAtLoginSupport.Registration(SMAppService.mainApp.status)
    }

    /// What the system will actually do at the next login.
    package static var isEnabled: Bool { registration == .enabled }

    /// Thrown when the app runs from a place whose registration cannot
    /// survive a relaunch; the message tells the user how to fix it.
    package struct UnstableLocationError: LocalizedError {
        package var errorDescription: String? { L10n.shared.s.launchAtLoginNeedsApplications }

        // Spelled out because a memberwise initializer never leaves its module.
        package init() {
        }
    }

    /// Thrown when the item is registered but System Settings still has it
    /// switched off. Only the user can approve it there, so the toggle would
    /// otherwise flip straight back with nothing said (issue #260).
    package struct NeedsApprovalError: LocalizedError {
        package var errorDescription: String? { L10n.shared.s.launchAtLoginNeedsApproval }

        // Spelled out because a memberwise initializer never leaves its module.
        package init() {
        }
    }

    /// The system calls `setEnabled` makes and where it stores the wish.
    /// `live` is this app's login item and the standard defaults.
    package struct System {
        package var register: () throws -> Void
        package var unregister: () throws -> Void
        package var registration: () -> LaunchAtLoginSupport.Registration
        package var locationIsUnstable: () -> Bool
        package var defaults: UserDefaults

        // Spelled out because a memberwise initializer never leaves its module.
        package init(register: @escaping () throws -> Void,
                     unregister: @escaping () throws -> Void,
                     registration: @escaping () -> LaunchAtLoginSupport.Registration,
                     locationIsUnstable: @escaping () -> Bool,
                     defaults: UserDefaults) {
            self.register = register
            self.unregister = unregister
            self.registration = registration
            self.locationIsUnstable = locationIsUnstable
            self.defaults = defaults
        }

        package static var live: System {
            System(register: { try SMAppService.mainApp.register() },
                   unregister: { try SMAppService.mainApp.unregister() },
                   registration: { LaunchAtLogin.registration },
                   locationIsUnstable: { LaunchAtLogin.locationIsUnstable },
                   defaults: .standard)
        }
    }

    package static func setEnabled(_ enabled: Bool) throws {
        try setEnabled(enabled, system: .live)
    }

    package static func setEnabled(_ enabled: Bool, system: System) throws {
        if enabled, system.locationIsUnstable() { throw UnstableLocationError() }
        system.defaults[Preferences.launchAtLoginWanted] = enabled
        var failure: Error?
        do {
            if enabled {
                try system.register()
            } else {
                try system.unregister()
            }
        } catch {
            failure = error
        }
        // Registering over an item the user switched off in System Settings
        // leaves the app closed at login whether or not the call reports an
        // error. Only the user can approve it there, so the wish stays stored
        // and the message says where to finish the job.
        if enabled, system.registration() == .needsApproval { throw NeedsApprovalError() }
        // Only surface failures that leave the system out of step with the
        // user's choice. Unregistering an item that was already gone reports
        // an error even though the end state is exactly what the user asked
        // for.
        if let failure, (system.registration() == .enabled) != enabled {
            // The stored intent must match what the user actually got;
            // keeping the failed wish would make the startup repair register
            // an item the UI showed as off.
            system.defaults[Preferences.launchAtLoginWanted] = system.registration() == .enabled
            throw failure
        }
    }

    /// Redoes a registration the system lost and adopts an enable made in
    /// the system's own settings. Called once at startup.
    package static func repairAtStartup() {
        let defaults = UserDefaults.standard
        switch LaunchAtLoginSupport.startupAction(
            wanted: defaults[Preferences.launchAtLoginWanted],
            registration: registration,
            locationIsUnstable: locationIsUnstable) {
        case .none:
            break
        case .adoptEnabled:
            defaults[Preferences.launchAtLoginWanted] = true
        case .register:
            try? SMAppService.mainApp.register()
        }
    }

    private static var locationIsUnstable: Bool {
        UpdateInstallerSupport.runsFromImmutableLocation(
            appPath: Bundle.main.bundlePath,
            volumeIsReadOnly: { path in
                let values = try? URL(fileURLWithPath: path)
                    .resourceValues(forKeys: [.volumeIsReadOnlyKey])
                return values?.volumeIsReadOnly ?? true
            })
    }
}

extension LaunchAtLoginSupport.Registration {
    /// Reads the system's status. An item awaiting approval is its own state,
    /// neither working nor gone: it exists but is switched off in System
    /// Settings, where only the user can turn it back on.
    package init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .needsApproval
        default: self = .off
        }
    }
}
