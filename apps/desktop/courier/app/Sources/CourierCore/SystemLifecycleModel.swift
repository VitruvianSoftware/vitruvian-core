// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation
import LocalAuthentication
import ServiceManagement

/// Registration state of Courier's macOS Login Item (`SMAppService.mainApp`).
public enum LoginItemRegistrationStatus: String, Equatable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
}

/// Abstracts `SMAppService.mainApp` so unit tests never register or unregister a real macOS login item.
public protocol LoginItemService: Sendable {
    func status() -> LoginItemRegistrationStatus
    func register() throws
    func unregister() throws
}

extension LoginItemService {
    public var isEnabled: Bool {
        let current = status()
        return current == .enabled || current == .requiresApproval
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try register()
        } else {
            try unregister()
        }
    }
}

/// Production adapter for `SMAppService.mainApp`, guarded by an `.app` bundle check.
public struct MACLoginItemService: LoginItemService {
    public init() {}

    private var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    public func status() -> LoginItemRegistrationStatus {
        guard isAppBundle else { return .notFound }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    public func register() throws {
        guard isAppBundle else { return }
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        guard isAppBundle else { return }
        try SMAppService.mainApp.unregister()
    }
}

/// Abstracts `LAContext` so unit tests never prompt Touch ID or system password dialogs.
public protocol BiometricAuthService: Sendable {
    func canEvaluateBiometricsOrWatch() -> Bool
    func authenticate(reason: String) async throws -> Bool
}

extension BiometricAuthService {
    public func canEvaluateBiometrics() -> Bool {
        canEvaluateBiometricsOrWatch()
    }
}

/// Production adapter for `LAContext` Touch ID / Apple Watch / device passcode authentication.
public struct LAContextBiometricService: BiometricAuthService {
    public init() {}

    public func canEvaluateBiometricsOrWatch() -> Bool {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return true
        }
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

/// Idle/background timeout before Courier locks when `autoLockEnabled` is on.
public enum LockTimeoutChoice: Int, CaseIterable, Codable, Sendable {
    case immediate = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3600

    public var label: String {
        switch self {
        case .immediate: String(localized: "Immediately")
        case .oneMinute: String(localized: "After 1 minute")
        case .fiveMinutes: String(localized: "After 5 minutes")
        case .fifteenMinutes: String(localized: "After 15 minutes")
        case .oneHour: String(localized: "After 1 hour")
        }
    }
}

/// Manages Launch at Login (`SMAppService`), Touch ID App Lock (`LAContext`), and window lifecycle settings.
@MainActor
public final class SystemLifecycleModel: ObservableObject {
    @Published public var launchAtLogin: Bool {
        didSet {
            guard !isApplyingLoginState else { return }
            applyLaunchAtLogin(launchAtLogin, previousValue: oldValue)
        }
    }
    @Published public var startMinimized: Bool {
        didSet {
            guard !isInitializing else { return }
            defaults.set(startMinimized, forKey: Self.key("startMinimized"))
        }
    }
    @Published public var minimizeToTrayOnClose: Bool {
        didSet {
            guard !isInitializing else { return }
            defaults.set(minimizeToTrayOnClose, forKey: Self.key("minimizeToTrayOnClose"))
        }
    }
    @Published public var autoLockEnabled: Bool {
        didSet {
            guard !isApplyingLockState else { return }
            if autoLockEnabled, !biometricService.canEvaluateBiometricsOrWatch() {
                isApplyingLockState = true
                autoLockEnabled = false
                isApplyingLockState = false
                lastErrorMessage = String(localized: "Touch ID or Apple Watch unlock isn’t available on this Mac.")
                return
            }
            defaults.set(autoLockEnabled, forKey: Self.key("autoLockEnabled"))
            if !autoLockEnabled {
                cancelPendingLockTimer()
                isLocked = false
            }
        }
    }
    @Published public var lockTimeout: LockTimeoutChoice {
        didSet {
            guard !isInitializing else { return }
            defaults.set(lockTimeout.rawValue, forKey: Self.key("lockTimeout"))
        }
    }
    @Published public private(set) var isLocked: Bool
    @Published public private(set) var loginItemStatus: LoginItemRegistrationStatus
    @Published public private(set) var lastErrorMessage: String?

    public static func key(_ name: String) -> String { "courier.lifecycle." + name }

    private let loginItemService: any LoginItemService
    private let biometricService: any BiometricAuthService
    private let scheduler: any NotificationTimerScheduling
    private let defaults: UserDefaults
    private var isInitializing = true
    private var isApplyingLoginState = true
    private var isApplyingLockState = true
    private var pendingLockTimerID: UUID?
    public private(set) var launchUnlockTask: Task<Bool, Never>?

    public init(
        loginItemService: any LoginItemService = MACLoginItemService(),
        biometricService: any BiometricAuthService = LAContextBiometricService(),
        scheduler: (any NotificationTimerScheduling)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.loginItemService = loginItemService
        self.biometricService = biometricService
        self.scheduler = scheduler ?? TaskNotificationTimerScheduler(sleep: { await waitForInboxWindow($0) })
        self.defaults = defaults

        let currentLoginStatus = loginItemService.status()
        self.loginItemStatus = currentLoginStatus
        self.launchAtLogin = (currentLoginStatus == .enabled || currentLoginStatus == .requiresApproval)
        let storedStartMinimized = (defaults.object(forKey: Self.key("startMinimized")) as? Bool)
            ?? (defaults.object(forKey: Self.key("keepMinimizedOnLaunch")) as? Bool)
            ?? false
        self.startMinimized = storedStartMinimized
        let storedMinimizeToTray: Bool
        if let minToTray = defaults.object(forKey: Self.key("minimizeToTrayOnClose")) as? Bool {
            storedMinimizeToTray = minToTray
        } else if let quitOnClose = defaults.object(forKey: Self.key("quitOnMainWindowClose")) as? Bool {
            storedMinimizeToTray = !quitOnClose
        } else {
            storedMinimizeToTray = true
        }
        self.minimizeToTrayOnClose = storedMinimizeToTray

        let storedAutoLock = (defaults.object(forKey: Self.key("autoLockEnabled")) as? Bool)
            ?? (defaults.object(forKey: Self.key("requireTouchIDOnLaunch")) as? Bool)
            ?? false
        self.autoLockEnabled = storedAutoLock
        let rawTimeout = defaults.object(forKey: Self.key("lockTimeout")) as? Int ?? LockTimeoutChoice.fiveMinutes.rawValue
        self.lockTimeout = LockTimeoutChoice(rawValue: rawTimeout) ?? .fiveMinutes
        self.isLocked = storedAutoLock

        if currentLoginStatus == .requiresApproval {
            self.lastErrorMessage = Self.requiresApprovalMessage
        } else if storedAutoLock, !biometricService.canEvaluateBiometricsOrWatch() {
            self.lastErrorMessage = String(localized: "Touch ID or your Mac password isn’t available right now.")
        }

        isInitializing = false
        isApplyingLoginState = false
        isApplyingLockState = false

        if storedAutoLock {
            self.launchUnlockTask = Task { @MainActor [weak self] in
                await self?.unlockWithTouchID() ?? false
            }
        }
    }

    public convenience init(
        defaults: UserDefaults = .standard,
        loginItem: any LoginItemService,
        biometrics: any BiometricAuthService
    ) {
        self.init(
            loginItemService: loginItem,
            biometricService: biometrics,
            scheduler: nil,
            defaults: defaults
        )
    }

    public var openAtLogin: Bool {
        get { launchAtLogin }
        set { launchAtLogin = newValue }
    }

    public var keepMinimizedOnLaunch: Bool {
        get { startMinimized }
        set {
            startMinimized = newValue
            defaults.set(newValue, forKey: Self.key("keepMinimizedOnLaunch"))
        }
    }

    public var quitOnMainWindowClose: Bool {
        get { !minimizeToTrayOnClose }
        set {
            minimizeToTrayOnClose = !newValue
            defaults.set(newValue, forKey: Self.key("quitOnMainWindowClose"))
        }
    }

    public var requireTouchIDOnLaunch: Bool {
        get { autoLockEnabled }
        set {
            autoLockEnabled = newValue
            defaults.set(autoLockEnabled, forKey: Self.key("requireTouchIDOnLaunch"))
        }
    }

    public var lastError: String? {
        lastErrorMessage
    }

    public func setOpenAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
    }

    public func lockApp() {
        lockNow()
    }

    @discardableResult
    public func unlockWithTouchID() async -> Bool {
        await unlock()
    }

    private static var requiresApprovalMessage: String {
        String(localized: "Approve Courier in System Settings › General › Login Items to finish turning on Launch at Login.")
    }

    public func refreshLoginItemStatus() {
        let status = loginItemService.status()
        loginItemStatus = status
        isApplyingLoginState = true
        launchAtLogin = (status == .enabled || status == .requiresApproval)
        isApplyingLoginState = false
        if status == .requiresApproval {
            lastErrorMessage = Self.requiresApprovalMessage
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool, previousValue: Bool) {
        do {
            if enabled {
                try loginItemService.register()
            } else {
                try loginItemService.unregister()
            }
            let newStatus = loginItemService.status()
            loginItemStatus = newStatus
            defaults.set(enabled, forKey: Self.key("launchAtLogin"))
            if newStatus == .requiresApproval {
                lastErrorMessage = Self.requiresApprovalMessage
            } else {
                lastErrorMessage = nil
            }
        } catch {
            isApplyingLoginState = true
            launchAtLogin = previousValue
            isApplyingLoginState = false
            loginItemStatus = loginItemService.status()
            lastErrorMessage = String(localized: "Courier couldn’t update your Login Items setting. Check System Settings › General › Login Items.")
        }
    }

    public func lockNow() {
        cancelPendingLockTimer()
        isLocked = true
    }

    public func noteWindowResignedKey() {
        scheduleAutoLockIfNeeded()
    }

    public func noteWindowBecameKey() {
        cancelPendingLockTimer()
    }

    public func noteUserIdle() {
        scheduleAutoLockIfNeeded()
    }

    public func noteUserActive() {
        cancelPendingLockTimer()
    }

    private func scheduleAutoLockIfNeeded() {
        guard autoLockEnabled, !isLocked else { return }
        cancelPendingLockTimer()
        if lockTimeout == .immediate {
            isLocked = true
            return
        }
        let id = scheduler.schedule(after: TimeInterval(lockTimeout.rawValue)) { [weak self] in
            guard let self else { return }
            self.pendingLockTimerID = nil
            guard self.autoLockEnabled else { return }
            self.isLocked = true
        }
        pendingLockTimerID = id
    }

    private func cancelPendingLockTimer() {
        if let id = pendingLockTimerID {
            scheduler.cancel(id)
            pendingLockTimerID = nil
        }
    }

    @discardableResult
    public func unlock() async -> Bool {
        guard biometricService.canEvaluateBiometricsOrWatch() else {
            isLocked = true
            lastErrorMessage = String(localized: "Touch ID or your Mac password isn’t available right now.")
            return false
        }
        do {
            let success = try await biometricService.authenticate(reason: String(localized: "Unlock Courier"))
            if success {
                cancelPendingLockTimer()
                isLocked = false
                lastErrorMessage = nil
                return true
            } else {
                isLocked = true
                lastErrorMessage = String(localized: "Authentication was cancelled or failed.")
                return false
            }
        } catch {
            isLocked = true
            lastErrorMessage = String(localized: "Authentication was cancelled or failed.")
            return false
        }
    }

    public var shouldHideMainWindowOnLaunch: Bool {
        startMinimized
    }

    public var shouldTerminateWhenMainWindowClosed: Bool {
        quitOnMainWindowClose
    }
}
