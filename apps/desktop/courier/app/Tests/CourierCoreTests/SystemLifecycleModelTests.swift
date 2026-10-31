// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

@MainActor
final class SystemLifecycleModelTests: XCTestCase {
    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
    }

    func testLaunchAtLoginRegistersAndUnregistersViaInjectedServiceAndHandlesRequiresApproval() throws {
        let suiteName = "courier.test.lifecycle.login.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let loginService = FakeLoginItemService(currentStatus: .notRegistered)
        let bioService = FakeBiometricAuthService(available: true, result: .success(true))
        let model = SystemLifecycleModel(
            loginItemService: loginService,
            biometricService: bioService,
            defaults: defaults
        )

        XCTAssertFalse(model.launchAtLogin)
        XCTAssertEqual(model.loginItemStatus, .notRegistered)
        XCTAssertNil(model.lastErrorMessage)

        // Enabling launchAtLogin calls register() on the injected service
        model.launchAtLogin = true
        XCTAssertEqual(loginService.registerCallCount, 1)
        XCTAssertEqual(model.loginItemStatus, .enabled)
        XCTAssertNil(model.lastErrorMessage)

        // Disabling launchAtLogin calls unregister() on the injected service
        model.launchAtLogin = false
        XCTAssertEqual(loginService.unregisterCallCount, 1)
        XCTAssertEqual(model.loginItemStatus, .notRegistered)

        // When SMAppService reports .requiresApproval, model surfaces a plain-English message
        loginService.statusAfterRegister = .requiresApproval
        model.launchAtLogin = true
        XCTAssertEqual(loginService.registerCallCount, 2)
        XCTAssertEqual(model.loginItemStatus, .requiresApproval)
        let approvalMessage = try XCTUnwrap(model.lastErrorMessage)
        XCTAssertTrue(approvalMessage.contains("System Settings"), "must explain how to approve in System Settings")
        XCTAssertFalse(approvalMessage.contains("Beeper"))

        // When register() throws an error, launchAtLogin reverts to false and surfaces a plain-English error
        model.launchAtLogin = false
        loginService.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1)
        model.launchAtLogin = true
        XCTAssertFalse(model.launchAtLogin)
        let registerError = try XCTUnwrap(model.lastErrorMessage)
        XCTAssertTrue(registerError.contains("Courier"))
        XCTAssertFalse(registerError.contains("SMAppService"))
    }

    func testAutoLockLocksAfterConfiguredTimeoutAndUnlocksOnlyOnBiometricSuccess() async throws {
        let suiteName = "courier.test.lifecycle.lock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let loginService = FakeLoginItemService(currentStatus: .notRegistered)
        let bioService = FakeBiometricAuthService(available: false, result: .success(false))
        let scheduler = ManualNotificationScheduler()
        let model = SystemLifecycleModel(
            loginItemService: loginService,
            biometricService: bioService,
            scheduler: scheduler,
            defaults: defaults
        )

        // 1. Cannot enable autoLockEnabled when Touch ID / Watch / passcode is unavailable
        model.autoLockEnabled = true
        XCTAssertFalse(model.autoLockEnabled, "must refuse to enable auto-lock when biometrics are unavailable")
        let unavailableMessage = try XCTUnwrap(model.lastErrorMessage)
        XCTAssertTrue(unavailableMessage.contains("Touch ID"))

        // 2. When biometrics are available, enabling auto-lock and resigning key locks after lockTimeout
        bioService.available = true
        model.autoLockEnabled = true
        model.lockTimeout = .fiveMinutes
        XCTAssertTrue(model.autoLockEnabled)
        XCTAssertFalse(model.isLocked)

        model.noteWindowResignedKey()
        await scheduler.advance(by: 299)
        XCTAssertFalse(model.isLocked, "must not lock before the 300s timeout expires")

        // Becoming key before timeout cancels the pending lock timer
        model.noteWindowBecameKey()
        await scheduler.advance(by: 10)
        XCTAssertFalse(model.isLocked, "returning to window before timeout must cancel pending lock")

        // Resigning again and waiting full 300s locks the app
        model.noteWindowResignedKey()
        await scheduler.advance(by: 300)
        XCTAssertTrue(model.isLocked, "must lock once the 300s timeout elapses")

        // 3. Fail-closed: cancelled or failed authentication keeps isLocked == true
        bioService.result = .failure(NSError(domain: "LAErrorDomain", code: -2))
        let unlockedOnError = await model.unlock()
        XCTAssertFalse(unlockedOnError)
        XCTAssertTrue(model.isLocked, "app lock must fail closed when LAContext throws")
        XCTAssertNotNil(model.lastErrorMessage)

        bioService.result = .success(false)
        let unlockedOnFalse = await model.unlock()
        XCTAssertFalse(unlockedOnFalse)
        XCTAssertTrue(model.isLocked, "app lock must fail closed when LAContext returns false")

        // 4. Biometric success unlocks the app and clears the error message
        bioService.result = .success(true)
        let unlockedOnSuccess = await model.unlock()
        XCTAssertTrue(unlockedOnSuccess)
        XCTAssertFalse(model.isLocked)
        XCTAssertNil(model.lastErrorMessage)
        XCTAssertEqual(bioService.prompts, ["Unlock Courier", "Unlock Courier", "Unlock Courier"])
    }

    func testStartMinimizedAndCloseToTrayDecisions() throws {
        let suiteName = "courier.test.lifecycle.window.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = SystemLifecycleModel(
            loginItemService: FakeLoginItemService(currentStatus: .notRegistered),
            biometricService: FakeBiometricAuthService(available: true, result: .success(true)),
            defaults: defaults
        )

        XCTAssertFalse(model.startMinimized)
        XCTAssertFalse(model.shouldHideMainWindowOnLaunch)
        XCTAssertTrue(model.minimizeToTrayOnClose)
        XCTAssertFalse(model.shouldTerminateWhenMainWindowClosed)

        model.startMinimized = true
        model.minimizeToTrayOnClose = false
        XCTAssertTrue(model.shouldHideMainWindowOnLaunch)
        XCTAssertTrue(model.shouldTerminateWhenMainWindowClosed)

        // Persisted across a fresh instance backed by the same UserDefaults
        let reloaded = SystemLifecycleModel(
            loginItemService: FakeLoginItemService(currentStatus: .notRegistered),
            biometricService: FakeBiometricAuthService(available: true, result: .success(true)),
            defaults: defaults
        )
        XCTAssertTrue(reloaded.startMinimized)
        XCTAssertTrue(reloaded.shouldHideMainWindowOnLaunch)
        XCTAssertFalse(reloaded.minimizeToTrayOnClose)
        XCTAssertTrue(reloaded.shouldTerminateWhenMainWindowClosed)
    }

    func testRequireTouchIDOnLaunchFailsClosedWhenBiometricsUnavailableAndPromptsAtLaunch() async throws {
        let suiteName = "courier.test.lifecycle.launchlock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: SystemLifecycleModel.key("requireTouchIDOnLaunch"))
        defaults.set(true, forKey: SystemLifecycleModel.key("autoLockEnabled"))

        // 1. When Touch ID & password evaluation report unavailable at launch, app lock MUST fail closed (isLocked == true)
        let unavailableBio = FakeBiometricAuthService(available: false, result: .success(false))
        let lockedWhenUnavailable = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: unavailableBio
        )
        XCTAssertTrue(lockedWhenUnavailable.isLocked, "app lock must fail closed at init even when biometrics report unavailable")
        XCTAssertTrue(lockedWhenUnavailable.requireTouchIDOnLaunch, "requireTouchIDOnLaunch setting must not be silently cleared at launch")
        let unlockedUnavailable = await lockedWhenUnavailable.unlockWithTouchID()
        XCTAssertFalse(unlockedUnavailable)
        XCTAssertTrue(lockedWhenUnavailable.isLocked)
        let err = try XCTUnwrap(lockedWhenUnavailable.lastError)
        XCTAssertFalse(err.isEmpty)
        XCTAssertFalse(err.contains("LAContext"))

        // 2. When biometrics are available and requireTouchIDOnLaunch is true, init starts locked and triggers unlockWithTouchID()
        let failingBio = FakeBiometricAuthService(available: true, result: .success(false))
        let lockedAtLaunch = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: failingBio
        )
        XCTAssertTrue(lockedAtLaunch.isLocked)
        _ = await lockedAtLaunch.launchUnlockTask?.value
        XCTAssertEqual(failingBio.prompts, ["Unlock Courier"], "init must trigger unlockWithTouchID() when requireTouchIDOnLaunch is true")
        XCTAssertTrue(lockedAtLaunch.isLocked, "must remain locked when launch authentication returns false")

        // 3. When launch authentication succeeds, model unlocks after launch prompt completes
        let succeedingBio = FakeBiometricAuthService(available: true, result: .success(true))
        let unlocksAtLaunch = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: succeedingBio
        )
        _ = await unlocksAtLaunch.launchUnlockTask?.value
        XCTAssertEqual(succeedingBio.prompts, ["Unlock Courier"])
        XCTAssertFalse(unlocksAtLaunch.isLocked)
    }

    func testTurningOffAutoLockWhileLockedRequiresAuthenticationAndCannotBypassLock() async throws {
        let suiteName = "courier.test.lifecycle.lockbypass.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bioService = FakeBiometricAuthService(available: true, result: .success(false))
        let model = SystemLifecycleModel(
            loginItemService: FakeLoginItemService(currentStatus: .notRegistered),
            biometricService: bioService,
            defaults: defaults
        )

        model.autoLockEnabled = true
        model.lockNow()
        XCTAssertTrue(model.isLocked)
        XCTAssertTrue(model.autoLockEnabled)

        // 1. Turning the lock off while locked with auth failing (returns false) leaves isLocked == true and autoLockEnabled == true
        model.autoLockEnabled = false
        XCTAssertTrue(model.isLocked, "turning off autoLockEnabled while locked must not synchronously unlock without authentication")
        XCTAssertTrue(model.autoLockEnabled, "turning off autoLockEnabled while locked must keep autoLockEnabled true until auth succeeds")
        _ = await model.disableLockAuthTask?.value
        XCTAssertTrue(model.isLocked, "turning off autoLockEnabled while locked with failing auth must leave isLocked true")
        XCTAssertTrue(model.autoLockEnabled, "turning off autoLockEnabled while locked with failing auth must leave autoLockEnabled true")
        XCTAssertEqual(defaults.object(forKey: SystemLifecycleModel.key("autoLockEnabled")) as? Bool, true)

        // 2. Turning the lock off via requireTouchIDOnLaunch while locked with auth throwing an error also leaves both true
        bioService.result = .failure(NSError(domain: "LAErrorDomain", code: -2))
        model.requireTouchIDOnLaunch = false
        _ = await model.disableLockAuthTask?.value
        XCTAssertTrue(model.isLocked)
        XCTAssertTrue(model.autoLockEnabled)
        XCTAssertTrue(model.requireTouchIDOnLaunch)

        // 3. Turning the lock off while locked with auth succeeding sets both isLocked and autoLockEnabled to false
        bioService.result = .success(true)
        model.autoLockEnabled = false
        _ = await model.disableLockAuthTask?.value
        XCTAssertFalse(model.isLocked, "turning off autoLockEnabled while locked with succeeding auth must unlock the app")
        XCTAssertFalse(model.autoLockEnabled, "turning off autoLockEnabled while locked with succeeding auth must disable auto-lock")
        XCTAssertEqual(defaults.object(forKey: SystemLifecycleModel.key("autoLockEnabled")) as? Bool, false)
    }

    func testEnablingAutoLockAllowsDeviceOwnerAuthWhenOnlyBiometricsUnavailableAndRefusesWhenNeitherAvailable() async throws {
        let suiteName = "courier.test.lifecycle.passwordfallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 1. When neither Touch ID nor Mac password (deviceOwnerAuthentication) can be evaluated, refuse with a plain message
        let bioService = FakeBiometricAuthService(
            biometricsAvailable: false,
            deviceOwnerAuthAvailable: false,
            result: .success(true)
        )
        let model = SystemLifecycleModel(
            loginItemService: FakeLoginItemService(currentStatus: .notRegistered),
            biometricService: bioService,
            defaults: defaults
        )

        model.autoLockEnabled = true
        XCTAssertFalse(model.autoLockEnabled, "must refuse to enable auto-lock when deviceOwnerAuthentication cannot be evaluated")
        let refusalMessage = try XCTUnwrap(model.lastErrorMessage)
        XCTAssertFalse(refusalMessage.isEmpty)
        XCTAssertFalse(refusalMessage.contains("LAContext"))
        XCTAssertFalse(refusalMessage.contains("Beeper"))

        // 2. When only biometrics are unavailable (biometricsAvailable == false) but Mac password (deviceOwnerAuthentication) CAN be evaluated, allow enabling
        bioService.biometricsAvailable = false
        bioService.deviceOwnerAuthAvailable = true
        model.autoLockEnabled = true
        XCTAssertTrue(
            model.autoLockEnabled,
            "must allow enabling auto-lock when biometrics are unavailable but deviceOwnerAuthentication (Mac password) is available"
        )
        XCTAssertNil(model.lastErrorMessage)

        model.lockNow()
        XCTAssertTrue(model.isLocked)
        let unlocked = await model.unlock()
        XCTAssertTrue(unlocked)
        XCTAssertFalse(model.isLocked)
    }
}

// MARK: - Fakes

final class FakeLoginItemService: LoginItemService, @unchecked Sendable {
    var currentStatus: LoginItemRegistrationStatus
    var statusAfterRegister: LoginItemRegistrationStatus = .enabled
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(currentStatus: LoginItemRegistrationStatus) {
        self.currentStatus = currentStatus
    }

    func status() -> LoginItemRegistrationStatus {
        currentStatus
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        currentStatus = statusAfterRegister
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        currentStatus = .notRegistered
    }
}

final class FakeBiometricAuthService: BiometricAuthService, @unchecked Sendable {
    var biometricsAvailable: Bool
    var deviceOwnerAuthAvailable: Bool
    var available: Bool {
        get { deviceOwnerAuthAvailable }
        set {
            biometricsAvailable = newValue
            deviceOwnerAuthAvailable = newValue
        }
    }
    var result: Result<Bool, Error>
    private(set) var prompts: [String] = []

    init(available: Bool, result: Result<Bool, Error>) {
        self.biometricsAvailable = available
        self.deviceOwnerAuthAvailable = available
        self.result = result
    }

    init(biometricsAvailable: Bool, deviceOwnerAuthAvailable: Bool, result: Result<Bool, Error>) {
        self.biometricsAvailable = biometricsAvailable
        self.deviceOwnerAuthAvailable = deviceOwnerAuthAvailable
        self.result = result
    }

    func canEvaluateBiometricsOrWatch() -> Bool {
        biometricsAvailable
    }

    func canEvaluateDeviceOwnerAuthentication() -> Bool {
        deviceOwnerAuthAvailable
    }

    func authenticate(reason: String) async throws -> Bool {
        prompts.append(reason)
        return try result.get()
    }
}
