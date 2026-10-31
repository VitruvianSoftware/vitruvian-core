// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
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
    func canEvaluateDeviceOwnerAuthentication() -> Bool
    func authenticate(reason: String) async throws -> Bool
}

extension BiometricAuthService {
    public func canEvaluateBiometrics() -> Bool {
        canEvaluateBiometricsOrWatch()
    }

    public func canEvaluateDeviceOwnerAuthentication() -> Bool {
        canEvaluateBiometricsOrWatch()
    }
}

/// Production adapter for `LAContext` Touch ID / Apple Watch / device passcode authentication.
public struct LAContextBiometricService: BiometricAuthService {
    public init() {}

    public func canEvaluateBiometricsOrWatch() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    public func canEvaluateDeviceOwnerAuthentication() -> Bool {
        let context = LAContext()
        var error: NSError?
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

/// Injectable abstraction over Courier's floating Picture-in-Picture window (`PictureInPictureController`)
/// so app-lock tests can verify PiP pause/close behavior deterministically.
@MainActor
public protocol PictureInPictureControlling: AnyObject {
    var isPresentingPiP: Bool { get }
    func pauseAndCloseForAppLock()
}

/// Injectable abstraction over `QLPreviewPanel` so unit tests can verify Quick Look presentation and
/// app-lock dismissal without requiring a live WindowServer `QLPreviewPanel`.
@MainActor
public protocol QuickLookPanelControlling: AnyObject {
    var isVisible: Bool { get }
    func presentPreview(for coordinator: AnyObject)
    func closePreview()
}

/// Coordinator that presents Quick Look previews and closes them when Courier locks.
@MainActor
public protocol QuickLookPreviewCoordinating: AnyObject {
    var currentPreviewURL: URL? { get }
    func preview(url: URL)
    func closeForAppLock()
}

/// Categories of user-initiated actions gated by `AppLockGate` and `SystemLifecycleModel`.
public enum UserActionKind: String, CaseIterable, Sendable {
    case send
    case reply
    case markRead
    case react
    case archive
    case export
    case download
    case settingsChange
    case copyCode
    case openChat
    case other
}

/// Modal panel or alert that can be aborted synchronously when Courier enters App Lock.
@MainActor
public protocol LockAbortableModal: AnyObject {
    func abortForAppLock()
}

extension NSSavePanel: LockAbortableModal {
    @MainActor
    public func abortForAppLock() {
        cancel(nil)
        if NSApp?.modalWindow === self {
            NSApp?.abortModal()
        }
    }
}

extension NSAlert: LockAbortableModal {
    @MainActor
    public func abortForAppLock() {
        if NSApp?.modalWindow === window {
            NSApp?.abortModal()
        }
        window.orderOut(nil)
    }
}

/// Central action-layer lock gate in `CourierCore` that every user-initiated action, modal panel,
/// Picture-in-Picture controller, and Quick Look coordinator routes through.
@MainActor
public final class AppLockGate {
    public static let shared = AppLockGate()

    private struct WeakModal {
        weak var value: (any LockAbortableModal)?
    }

    private struct WeakPiP {
        weak var value: (any PictureInPictureControlling)?
    }

    private struct WeakQuickLook {
        weak var value: (any QuickLookPreviewCoordinating)?
    }

    private final class UnlockedFallbackLoginItemService: LoginItemService {
        func status() -> LoginItemRegistrationStatus { .notRegistered }
        func register() throws {}
        func unregister() throws {}
    }

    private final class UnlockedFallbackBiometricService: BiometricAuthService {
        func canEvaluateBiometricsOrWatch() -> Bool { true }
        func canEvaluateDeviceOwnerAuthentication() -> Bool { true }
        func authenticate(reason _: String) async throws -> Bool { true }
    }

    private weak var boundLifecycle: SystemLifecycleModel?
    private lazy var fallbackLifecycle: SystemLifecycleModel = {
        let suiteName = "courier.lockgate.fallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(false, forKey: SystemLifecycleModel.key("autoLockEnabled"))
        defaults.set(false, forKey: SystemLifecycleModel.key("requireTouchIDOnLaunch"))
        return SystemLifecycleModel(
            loginItemService: UnlockedFallbackLoginItemService(),
            biometricService: UnlockedFallbackBiometricService(),
            scheduler: nil,
            defaults: defaults,
            bindToSharedGate: false
        )
    }()

    private var activeModals: [WeakModal] = []
    private var pipControllers: [WeakPiP] = []
    private var quickLookCoordinators: [WeakQuickLook] = []

    private init() {}

    /// Non-optional active `SystemLifecycleModel` observed across models and detached window sessions.
    public var lifecycle: SystemLifecycleModel {
        boundLifecycle ?? fallbackLifecycle
    }

    public var isLocked: Bool {
        lifecycle.isLocked
    }

    public func bind(_ lifecycle: SystemLifecycleModel) {
        boundLifecycle = lifecycle
    }

    public func bindIfUnbound(_ lifecycle: SystemLifecycleModel) {
        guard boundLifecycle == nil else { return }
        boundLifecycle = lifecycle
    }

    nonisolated public static var isCurrentActionAllowedForSettings: Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                AppLockGate.shared.canPerform(.settingsChange)
            }
        }
        return true
    }

    public func resetForTesting() {
        boundLifecycle = nil
        activeModals.removeAll()
    }

    /// Central gate check for user-initiated actions outside the lock screen.
    public func canPerform(
        _ action: UserActionKind = .other,
        lifecycle explicitLifecycle: SystemLifecycleModel? = nil
    ) -> Bool {
        _ = action
        let resolved = explicitLifecycle ?? lifecycle
        return !resolved.isLocked && !isLocked
    }

    /// Throws `EngineError.rpc(.badValue, message: "Courier is locked", reason: "locked")` if locked.
    public func ensureUnlocked(
        _ action: UserActionKind = .other,
        lifecycle explicitLifecycle: SystemLifecycleModel? = nil
    ) throws {
        guard canPerform(action, lifecycle: explicitLifecycle) else {
            throw EngineError.rpc(.badValue, message: "Courier is locked", reason: "locked")
        }
    }

    public func registerModal(_ modal: any LockAbortableModal) {
        activeModals.removeAll { $0.value == nil || $0.value === modal }
        activeModals.append(WeakModal(value: modal))
        if isLocked {
            modal.abortForAppLock()
        }
    }

    public func unregisterModal(_ modal: any LockAbortableModal) {
        activeModals.removeAll { $0.value == nil || $0.value === modal }
    }

    public func registerPiPController(_ controller: any PictureInPictureControlling) {
        pipControllers.removeAll { $0.value == nil || $0.value === controller }
        pipControllers.append(WeakPiP(value: controller))
        if isLocked {
            controller.pauseAndCloseForAppLock()
        }
    }

    public func registerQuickLookCoordinator(_ coordinator: any QuickLookPreviewCoordinating) {
        quickLookCoordinators.removeAll { $0.value == nil || $0.value === coordinator }
        quickLookCoordinators.append(WeakQuickLook(value: coordinator))
        if isLocked {
            coordinator.closeForAppLock()
        }
    }

    /// Runs an AppKit modal (`NSSavePanel`, `NSOpenPanel`, `NSAlert`) while registered for lock abort,
    /// and verifies the lock gate both before presenting and after the modal returns.
    public func runModal<T>(
        _ modal: any LockAbortableModal,
        action: UserActionKind = .other,
        lifecycle explicitLifecycle: SystemLifecycleModel? = nil,
        body: @MainActor () -> T
    ) -> T? {
        guard canPerform(action, lifecycle: explicitLifecycle) else { return nil }
        registerModal(modal)
        defer { unregisterModal(modal) }
        let result = body()
        guard canPerform(action, lifecycle: explicitLifecycle) else { return nil }
        return result
    }

    public func runSavePanel(
        action: UserActionKind = .download,
        lifecycle explicitLifecycle: SystemLifecycleModel? = nil,
        configure: @MainActor (NSSavePanel) -> Void
    ) -> URL? {
        guard canPerform(action, lifecycle: explicitLifecycle) else { return nil }
        let panel = NSSavePanel()
        configure(panel)
        guard let url = runModal(panel, action: action, lifecycle: explicitLifecycle, body: {
            panel.runModal() == .OK ? panel.url : nil
        }) else {
            return nil
        }
        return url
    }

    public func runOpenPanel(
        action: UserActionKind = .other,
        lifecycle explicitLifecycle: SystemLifecycleModel? = nil,
        configure: @MainActor (NSOpenPanel) -> Void
    ) -> [URL]? {
        guard canPerform(action, lifecycle: explicitLifecycle) else { return nil }
        let panel = NSOpenPanel()
        configure(panel)
        guard let urls = runModal(panel, action: action, lifecycle: explicitLifecycle, body: {
            panel.runModal() == .OK ? panel.urls : nil
        }) else {
            return nil
        }
        return urls
    }

    public func runAlertModal(
        _ alert: NSAlert,
        action: UserActionKind = .other,
        lifecycle explicitLifecycle: SystemLifecycleModel? = nil
    ) -> NSApplication.ModalResponse? {
        runModal(alert, action: action, lifecycle: explicitLifecycle) {
            alert.runModal()
        }
    }

    public func handleDidLock(from source: SystemLifecycleModel) {
        boundLifecycle = source
        let modals = activeModals.compactMap(\.value)
        activeModals.removeAll()
        for modal in modals {
            modal.abortForAppLock()
        }
        if NSApp?.modalWindow != nil {
            NSApp?.abortModal()
        }
        pipControllers.removeAll { $0.value == nil }
        for entry in pipControllers {
            entry.value?.pauseAndCloseForAppLock()
        }
        quickLookCoordinators.removeAll { $0.value == nil }
        for entry in quickLookCoordinators {
            entry.value?.closeForAppLock()
        }
    }
}

/// Manages Launch at Login (`SMAppService`), Touch ID App Lock (`LAContext`), and window lifecycle settings.
@MainActor
public final class SystemLifecycleModel: ObservableObject {
    @Published public var launchAtLogin: Bool {
        didSet {
            guard !isApplyingLoginState else { return }
            guard canPerformUserAction(.settingsChange) else {
                isApplyingLoginState = true
                launchAtLogin = oldValue
                isApplyingLoginState = false
                return
            }
            applyLaunchAtLogin(launchAtLogin, previousValue: oldValue)
        }
    }
    @Published public var startMinimized: Bool {
        didSet {
            guard !isInitializing, !isRevertingLockedSetting else { return }
            guard canPerformUserAction(.settingsChange) else {
                isRevertingLockedSetting = true
                startMinimized = oldValue
                isRevertingLockedSetting = false
                return
            }
            defaults.set(startMinimized, forKey: Self.key("startMinimized"))
        }
    }
    @Published public var minimizeToTrayOnClose: Bool {
        didSet {
            guard !isInitializing, !isRevertingLockedSetting else { return }
            guard canPerformUserAction(.settingsChange) else {
                isRevertingLockedSetting = true
                minimizeToTrayOnClose = oldValue
                isRevertingLockedSetting = false
                return
            }
            defaults.set(minimizeToTrayOnClose, forKey: Self.key("minimizeToTrayOnClose"))
        }
    }
    @Published public var autoLockEnabled: Bool {
        didSet {
            guard !isApplyingLockState else { return }
            if autoLockEnabled {
                guard biometricService.canEvaluateDeviceOwnerAuthentication() else {
                    isApplyingLockState = true
                    autoLockEnabled = false
                    isApplyingLockState = false
                    lastErrorMessage = String(localized: "Touch ID or your Mac password isn’t available on this Mac.")
                    return
                }
                lastErrorMessage = nil
                persistAutoLockEnabled(true)
            } else {
                if isLocked {
                    isApplyingLockState = true
                    autoLockEnabled = true
                    isApplyingLockState = false
                    disableLockAuthTask?.cancel()
                    disableLockAuthTask = Task { @MainActor [weak self] in
                        await self?.authenticateAndDisableLock() ?? false
                    }
                    return
                }
                cancelPendingLockTimer()
                persistAutoLockEnabled(false)
            }
        }
    }
    @Published public var lockTimeout: LockTimeoutChoice {
        didSet {
            guard !isInitializing, !isRevertingLockedSetting else { return }
            guard canPerformUserAction(.settingsChange) else {
                isRevertingLockedSetting = true
                lockTimeout = oldValue
                isRevertingLockedSetting = false
                return
            }
            defaults.set(lockTimeout.rawValue, forKey: Self.key("lockTimeout"))
        }
    }
    @Published public private(set) var isLocked: Bool {
        didSet {
            if isLocked {
                notifyLocked()
            } else if oldValue {
                NotificationCenter.default.post(name: Self.didUnlockNotification, object: self)
            }
        }
    }
    @Published public private(set) var loginItemStatus: LoginItemRegistrationStatus
    @Published public private(set) var lastErrorMessage: String?

    /// Posted synchronously on `@MainActor` whenever `SystemLifecycleModel` enters the locked state.
    public nonisolated static let didLockNotification = Notification.Name("CourierSystemLifecycleDidLock")
    /// Posted synchronously on `@MainActor` whenever `SystemLifecycleModel` transitions from locked to unlocked.
    public nonisolated static let didUnlockNotification = Notification.Name("CourierSystemLifecycleDidUnlock")

    public static func key(_ name: String) -> String { "courier.lifecycle." + name }

    private let loginItemService: any LoginItemService
    private let biometricService: any BiometricAuthService
    private let scheduler: any NotificationTimerScheduling
    private let defaults: UserDefaults
    private var isInitializing = true
    private var isApplyingLoginState = true
    private var isApplyingLockState = true
    private var isRevertingLockedSetting = false
    private var pendingLockTimerID: UUID?
    private var lockHandlers: [@MainActor () -> Void] = []
    public private(set) var launchUnlockTask: Task<Bool, Never>?
    public private(set) var disableLockAuthTask: Task<Bool, Never>?

    public init(
        loginItemService: any LoginItemService = MACLoginItemService(),
        biometricService: any BiometricAuthService = LAContextBiometricService(),
        scheduler: (any NotificationTimerScheduling)? = nil,
        defaults: UserDefaults = .standard,
        bindToSharedGate: Bool = true
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
        } else if storedAutoLock, !biometricService.canEvaluateDeviceOwnerAuthentication() {
            self.lastErrorMessage = String(localized: "Touch ID or your Mac password isn’t available right now.")
        }

        isInitializing = false
        isApplyingLoginState = false
        isApplyingLockState = false

        if bindToSharedGate {
            AppLockGate.shared.bindIfUnbound(self)
        }

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
            guard canPerformUserAction(.settingsChange) else { return }
            startMinimized = newValue
            defaults.set(newValue, forKey: Self.key("keepMinimizedOnLaunch"))
        }
    }

    public var quitOnMainWindowClose: Bool {
        get { !minimizeToTrayOnClose }
        set {
            guard canPerformUserAction(.settingsChange) else { return }
            minimizeToTrayOnClose = !newValue
            defaults.set(newValue, forKey: Self.key("quitOnMainWindowClose"))
        }
    }

    public var requireTouchIDOnLaunch: Bool {
        get { autoLockEnabled }
        set { autoLockEnabled = newValue }
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

    @discardableResult
    public func setAutoLockEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            autoLockEnabled = true
            return autoLockEnabled
        }
        guard autoLockEnabled else { return true }
        if isLocked {
            return await authenticateAndDisableLock()
        }
        autoLockEnabled = false
        return !autoLockEnabled
    }

    private func persistAutoLockEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key("autoLockEnabled"))
        defaults.set(enabled, forKey: Self.key("requireTouchIDOnLaunch"))
    }

    private func authenticateAndDisableLock() async -> Bool {
        let unlocked = await unlock()
        guard unlocked, !isLocked else {
            isApplyingLockState = true
            autoLockEnabled = true
            isApplyingLockState = false
            persistAutoLockEnabled(true)
            return false
        }
        cancelPendingLockTimer()
        isApplyingLockState = true
        autoLockEnabled = false
        isApplyingLockState = false
        persistAutoLockEnabled(false)
        return true
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

    /// Registers a callback invoked synchronously on `@MainActor` whenever Courier locks.
    public func onLock(_ handler: @escaping @MainActor () -> Void) {
        lockHandlers.append(handler)
        if isLocked {
            handler()
        }
    }

    public func canPerformUserAction(_ action: UserActionKind = .other) -> Bool {
        AppLockGate.shared.canPerform(action, lifecycle: self)
    }

    public func ensureUnlocked(_ action: UserActionKind = .other) throws {
        try AppLockGate.shared.ensureUnlocked(action, lifecycle: self)
    }

    private func notifyLocked() {
        AppLockGate.shared.handleDidLock(from: self)
        for handler in lockHandlers {
            handler()
        }
        NotificationCenter.default.post(name: Self.didLockNotification, object: self)
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
        guard biometricService.canEvaluateDeviceOwnerAuthentication() else {
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
