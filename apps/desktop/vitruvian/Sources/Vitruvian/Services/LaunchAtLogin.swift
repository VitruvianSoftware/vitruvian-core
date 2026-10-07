// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
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
    /// Service Management can stall while answering, so every read and
    /// change runs here, off the main thread. The queue is serial, so a change
    /// made in Settings always runs after the startup repair.
    private static let operationQueue = DispatchQueue(
        label: "com.vitruviansoftware.vitruvian.launch-at-login", qos: .userInitiated)

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

    /// Registration can succeed while macOS still denies permission, including
    /// when Allow in the Background is off. Only the user can approve it.
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

    /// Runs `work` on the queue every read and change of the login item goes
    /// through, after any repair or change queued before it.
    package static func enqueue(_ work: @escaping @Sendable () -> Void) {
        operationQueue.async(execute: work)
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
        operationQueue.async { repairNow() }
    }

    private static func repairNow() {
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


/// What the General page shows for launch at login. Service Management can
/// stall while answering (upstream issue #2539), so the status is read, and a
/// toggle applied, off the main thread, and the page never waits on the
/// system; a toggle made since a read started wins over that read, and a
/// newer read over an older one. Kept out of the view so a contract can drive
/// it.
@MainActor
package final class LaunchAtLoginSettingsModel: ObservableObject {
    /// The system the page reads and writes. `live` is this app's login item.
    package struct Environment: Sendable {
        package var registration: @Sendable () -> LaunchAtLoginSupport.Registration
        package var setEnabled: @Sendable (Bool) throws -> Void
        /// Runs reads and changes in order, after the startup repair.
        package var background: @Sendable (@escaping @Sendable () -> Void) -> Void
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

        // Spelled out because a memberwise initializer never leaves its module.
        package init(registration: @escaping @Sendable () -> LaunchAtLoginSupport.Registration,
                     setEnabled: @escaping @Sendable (Bool) throws -> Void,
                     background: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void) {
            self.registration = registration
            self.setEnabled = setEnabled
            self.background = background
            self.main = main
        }

        package static let live = Environment(
            registration: { LaunchAtLogin.registration },
            setEnabled: { try LaunchAtLogin.setEnabled($0, system: .live) },
            background: { LaunchAtLogin.enqueue($0) },
            main: { work in DispatchQueue.main.async { work() } })
    }

    @Published package private(set) var registration: LaunchAtLoginSupport.Registration
    /// Why the last toggle did not take, when it says something the
    /// approval guidance does not.
    @Published package private(set) var errorText: String?
    /// What the switch shows. Waiting on approval the item is still
    /// registered, so it reads on, and switching it off unregisters it, which
    /// also clears the note.
    package var isOn: Bool { registration != .off }
    /// True while a toggle waits on the system; the switch holds still.
    @Published package private(set) var isPending = false
    private var refreshID = UUID()
    private let environment: Environment

    /// Seeded from the stored choice so the switch does not flash off while
    /// the status read is still on its way.
    package init(wanted: Bool, environment: Environment = .live) {
        registration = wanted ? .enabled : .off
        self.environment = environment
    }

    package func refresh() {
        let requestID = UUID()
        refreshID = requestID
        let read = environment.registration, main = environment.main
        environment.background {
            let registration = read()
            main { [weak self] in
                guard let self, self.refreshID == requestID else { return }
                self.registration = registration
                self.errorText = nil
                // A read that replaces a change's answer runs after that
                // change, so it frees the switch too.
                self.isPending = false
            }
        }
    }

    package func setEnabled(_ enabled: Bool) {
        let requestID = UUID()
        refreshID = requestID
        // Hold the switch where the user put it while the system answers,
        // instead of letting it spring back until the change lands.
        registration = enabled ? .enabled : .off
        errorText = nil
        isPending = true
        let change = environment.setEnabled, read = environment.registration, main = environment.main
        environment.background {
            let failure: Error?
            do {
                try change(enabled)
                failure = nil
            } catch {
                failure = error
            }
            // A register call that succeeds can still leave the item waiting
            // for approval, so the page shows what the change left behind.
            let registration = read()
            main { [weak self] in
                guard let self, self.refreshID == requestID else { return }
                self.registration = registration
                // Approval guidance follows current system status, including
                // on a fresh page, instead of retaining an error from a
                // previous attempt. The message is read here, on the main
                // thread, in the current language.
                self.errorText = registration == .needsApproval ? nil : failure?.localizedDescription
                self.isPending = false
            }
        }
    }
}
