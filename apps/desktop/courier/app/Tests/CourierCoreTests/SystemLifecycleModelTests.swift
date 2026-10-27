// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

@MainActor
final class SystemLifecycleModelTests: XCTestCase {
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
    var available: Bool
    var result: Result<Bool, Error>
    private(set) var prompts: [String] = []

    init(available: Bool, result: Result<Bool, Error>) {
        self.available = available
        self.result = result
    }

    func canEvaluateBiometricsOrWatch() -> Bool {
        available
    }

    func authenticate(reason: String) async throws -> Bool {
        prompts.append(reason)
        return try result.get()
    }
}
