// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import AVFoundation
import Combine
import CoreGraphics
import EventKit
import UserNotifications
import VitruvianCore
import VitruvianDesign

/// Central place to check, request and watch the TCC permissions the app uses.
/// Accessibility powers the scroll inverter and the switcher's event tap;
/// Screen Recording powers window titles and thumbnails in the switcher.
@MainActor
package final class Permissions: ObservableObject {
    package static let shared = Permissions()

    @Published package private(set) var accessibility = false {
        didSet { Self.grantLock.withLock { Self.grantedAccessibility = accessibility } }
    }
    @Published package private(set) var screenRecording = false {
        didSet { Self.grantLock.withLock { Self.grantedScreenRecording = screenRecording } }
    }

    /// The window activator, the preview provider and the window capture read
    /// these two grants from their own threads, so each is mirrored here as
    /// it is published.
    nonisolated private static let grantLock = NSLock()
    // The two below are guarded by grantLock.
    nonisolated(unsafe) private static var grantedAccessibility = false
    nonisolated(unsafe) private static var grantedScreenRecording = false
    /// Accessibility as last published, from any thread.
    nonisolated package static var accessibilityGranted: Bool {
        grantLock.withLock { grantedAccessibility }
    }
    /// Screen Recording as last published, from any thread.
    nonisolated package static var screenRecordingGranted: Bool {
        grantLock.withLock { grantedScreenRecording }
    }
    /// Optional — only used to make the uninstaller's scan more thorough by
    /// reaching protected locations. There is no API prompt for it; the user
    /// grants it in System Settings.
    @Published package private(set) var fullDiskAccess = false
    /// Refreshed inside refresh() only (launch and activation); notifications
    /// have no cheap poll and the portal calls refresh() when it appears.
    @Published package private(set) var notifications: NotificationPermissionState = .unknown
    /// Camera access for the preview mirror. The status read is free, so it
    /// rides the same refresh() moments as the rest.
    @Published package private(set) var camera: CameraPermissionState = .unknown
    @Published package private(set) var calendarAccess = EKEventStore.authorizationStatus(for: .event)
    @Published package private(set) var requestingCalendar = false
    @Published package private(set) var calendarRequestFailed = false
    private var calendarPermissionResolution: TimeInterval?

    package var keepsCalendarPrompt: Bool {
        NotchSupport.keepsPermissionSurface(requesting: requestingCalendar,
                                            resolvedAt: calendarPermissionResolution,
                                            now: ProcessInfo.processInfo.systemUptime)
    }
    /// Optional microphone access, used only while a recording that asked for
    /// it is active.
    @Published package private(set) var microphone: MicrophonePermissionState = .unknown

    package enum NotificationPermissionState {
        case granted, denied, undetermined, unknown
    }

    package enum CameraPermissionState {
        case granted, denied, undetermined, unknown
    }

    package enum MicrophonePermissionState {
        case granted, denied, undetermined, unknown
    }

    // `nonisolated(unsafe)`: `deinit` reads them too, once nothing else holds the object.
    nonisolated(unsafe) private var activePermissionTimer: Timer?
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?
    private var permissionSurfaceDemands: Set<UUID> = []
    private var currentPollInterval: TimeInterval?

    private init() {
        refresh()
        // Watch Accessibility and Screen Recording only while a running
        // feature or visible permission surface can use the result. One-shot
        // tools refresh when invoked, so their mere availability must not keep
        // a timer alive in the background.
        // Full Disk Access is deliberately NOT polled here: it can only change
        // across a relaunch (a running process never gains or is meant to lose
        // it mid-session), and probing it touches protected paths, so polling it
        // would just be repeated denied accesses for no gain.
        scheduleActivePermissionPolling()
        // Re-check everything the instant the user returns from System Settings
        // (e.g. after relaunching for Full Disk Access), so the state reflects
        // immediately instead of waiting for the next poll.
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            // Delivered on the main queue.
            MainActor.assumeIsolated {
                self?.refresh()
                self?.scheduleActivePermissionPolling()
            }
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            // Delivered on the main queue.
            MainActor.assumeIsolated { self?.scheduleActivePermissionPolling() }
        }
    }

    deinit {
        activePermissionTimer?.invalidate()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    private var desiredPollInterval: TimeInterval? {
        let accessibilityIsNeeded = AppFeature.activeFeatures(using: .accessibility)
            .contains { $0.monitorsPermissionChanges }
        let screenRecordingIsNeeded = AppFeature.activeFeatures(using: .screenRecording)
            .contains { $0.monitorsPermissionChanges }
        return PermissionPollingSupport.interval(
            visibleSurfaceCount: permissionSurfaceDemands.count,
            accessibilityIsNeeded: accessibilityIsNeeded,
            screenRecordingIsNeeded: screenRecordingIsNeeded,
            accessibilityIsGranted: accessibility,
            screenRecordingIsGranted: screenRecording)
    }

    private func scheduleActivePermissionPolling() {
        let interval = desiredPollInterval
        guard interval != currentPollInterval else { return }
        currentPollInterval = interval
        activePermissionTimer?.invalidate()
        activePermissionTimer = nil
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Added to the main run loop below, so it fires on the main thread.
            MainActor.assumeIsolated { self?.refreshActivePermissions() }
        }
        timer.tolerance = interval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        activePermissionTimer = timer
    }

    /// Visible permission UI owns a stable demand identifier so repeated
    /// SwiftUI appearances cannot accidentally leave an unbalanced timer.
    package func setActivePermissionSurface(_ id: UUID, visible: Bool) {
        if visible {
            permissionSurfaceDemands.insert(id)
            refreshActivePermissions()
        } else {
            permissionSurfaceDemands.remove(id)
        }
        scheduleActivePermissionPolling()
    }

    /// Full refresh including Full Disk Access. Runs at launch and on activation.
    package func refresh() {
        refreshActivePermissions()
        refreshNotificationPermission()
        refreshCameraPermission()
        calendarAccess = EKEventStore.authorizationStatus(for: .event)
        refreshMicrophonePermission()
        // Checking Full Disk Access means asking the system about protected
        // folders, and every refused answer costs time. Doing that where the
        // app is starting up holds back the menu bar icon, so it moves off
        // and reports back.
        DispatchQueue.global(qos: .utility).async {
            let granted = Self.probeFullDiskAccess()
            DispatchQueue.main.async {
                if self.fullDiskAccess != granted { self.fullDiskAccess = granted }
            }
        }
    }

    private func refreshCameraPermission() {
        let state: CameraPermissionState
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: state = .granted
        case .denied, .restricted: state = .denied
        case .notDetermined: state = .undetermined
        @unknown default: state = .unknown
        }
        DispatchQueue.main.async {
            if self.camera != state { self.camera = state }
        }
    }

    private func refreshMicrophonePermission() {
        let state: MicrophonePermissionState
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: state = .granted
        case .denied, .restricted: state = .denied
        case .notDetermined: state = .undetermined
        @unknown default: state = .unknown
        }
        DispatchQueue.main.async {
            if self.microphone != state { self.microphone = state }
        }
    }

    private func refreshNotificationPermission() {
        // Asking the system for the notification centre ends the process
        // outright when it cannot resolve this app, which is what happens
        // when the bundle is replaced or moved out from under a running copy.
        // An update does exactly that, so reporting nothing beats dying.
        guard Bundle.main.bundleIdentifier != nil,
              FileManager.default.fileExists(atPath: Bundle.main.bundlePath) else {
            if notifications != .unknown { notifications = .unknown }
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let state: NotificationPermissionState
            switch settings.authorizationStatus {
            case .authorized, .provisional: state = .granted
            case .denied: state = .denied
            case .notDetermined: state = .undetermined
            @unknown default: state = .unknown
            }
            DispatchQueue.main.async {
                if self?.notifications != state { self?.notifications = state }
            }
        }
    }

    /// Accessibility and Screen Recording only — free, side-effect-free checks
    /// suitable for frequent polling.
    private func refreshActivePermissions() {
        let ax = AXIsProcessTrusted()
        let sr = CGPreflightScreenCaptureAccess()
        DispatchQueue.main.async {
            if self.accessibility != ax { self.accessibility = ax }
            if self.screenRecording != sr { self.screenRecording = sr }
            // A flip can change which cadence applies (e.g. the last grant
            // landed while the app was in the background).
            self.scheduleActivePermissionPolling()
        }
    }

    /// Protected directories safe to use both as access probes and as
    /// registration attempts. Request-only paths stay separate because every
    /// entry here must remain a reliable signal that access was granted.
    nonisolated private static let fdaGatedDirectories = [
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
        "Library/Cookies",
        "Library/Suggestions",
        "Library/Application Support/MobileSync",
    ]

    /// Detects Full Disk Access without a prompt. Reading the TCC database is the
    /// classic signal, but that file is absent on some macOS versions (so a
    /// missing file would read as "no access" forever, even once granted). The
    /// dependable fallback is to list a protected directory that exists: that
    /// listing is denied without Full Disk Access and succeeds with it.
    nonisolated private static func probeFullDiskAccess() -> Bool {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        // Preferred when present: the TCC database is readable only with access.
        let tccDB = (home as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        if let handle = FileHandle(forReadingAtPath: tccDB) {
            let ok = (try? handle.read(upToCount: 1)) != nil
            try? handle.close()
            if ok { return true }
        }

        // Works on every version: each of these is gated by Full Disk Access, so
        // a successful listing (even of an empty directory) means it is granted.
        let gatedDirs = fdaGatedDirectories.map { (home as NSString).appendingPathComponent($0) }
        return gatedDirs.contains { (try? fm.contentsOfDirectory(atPath: $0)) != nil }
    }

    /// Shows the system Accessibility prompt (once per TCC reset) and floats
    /// the little guide card for the System Settings round trip.
    package func requestAccessibility() {
        // `kAXTrustedCheckOptionPrompt`'s value: Swift 6 refuses to read the
        // imported constant, which comes in as a mutable C global.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refreshActivePermissions()
        if !accessibility {
            MainActor.assumeIsolated { appShell()?.showPermissionGuide(for: .accessibility) }
        }
    }

    /// Shows the system Screen Recording prompt (once per TCC reset) and
    /// floats the guide card, like the Accessibility path.
    package func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        refreshActivePermissions()
        if !screenRecording {
            MainActor.assumeIsolated { appShell()?.showPermissionGuide(for: .screenRecording) }
        }
    }

    /// Drops this app's entry from the list and asks again. The entry macOS
    /// keeps is bound to the app's code signature, so a copy signed
    /// differently (a local build, an update signed another way) finds the
    /// switch on and the permission gone; nothing short of removing the entry
    /// makes the system ask afresh. `tccutil` does that for the calling
    /// user's own entries with no privilege, and is the command Apple
    /// documents for the purpose.
    package func startOver(_ kind: PermissionKind) {
        guard kind == .accessibility || kind == .screenRecording,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let service = kind == .accessibility ? "Accessibility" : "ScreenCapture"
        // Off the main thread through the bounded runner, like
        // `SelfUninstall.resetTCC`: a stuck tccutil must not hang the UI. The
        // hop back also lets the button's click finish before the card that
        // holds the button is rebuilt by the new request.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = Shell.run("/usr/bin/tccutil", ["reset", service, bundleID])
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshActivePermissions()
                if kind == .accessibility { self.requestAccessibility() } else { self.requestScreenRecording() }
            }
        }
    }

    package func openAccessibilitySettings() {
        open(pane: "Privacy_Accessibility")
    }

    package func openScreenRecordingSettings() {
        open(pane: "Privacy_ScreenCapture")
    }

    package func openFullDiskAccessSettings() {
        open(pane: "Privacy_AllFiles")
    }

    package func openFilesAndFoldersSettings() {
        open(pane: "Privacy_FilesAndFolders")
    }

    /// Full Disk Access has no prompt API, and an app only shows up (toggled
    /// off) in its System Settings list once it has attempted to read a
    /// protected location. Touch likely protected paths to register the app,
    /// then open the pane after a short delay so tccd has recorded the denial
    /// before System Settings reads the list. If it still does not appear, the
    /// user can add the app with the list's "+" button.
    package func requestFullDiskAccess() {
        DispatchQueue.global(qos: .userInitiated).async {
            let home = NSHomeDirectory()
            let fm = FileManager.default
            // The TCC database is the classic trigger when present. Some macOS
            // versions omit it, so the protected directories below are the
            // fallback registration attempts.
            let tccDB = (home as NSString)
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
            _ = try? Data(contentsOf: URL(fileURLWithPath: tccDB), options: .mappedIfSafe)
            if let handle = FileHandle(forReadingAtPath: tccDB) {
                _ = try? handle.read(upToCount: 1)
                try? handle.close()
            }
            // Protected locations, harmless when absent. The TCC directory is
            // useful for registration but is not part of the access probe.
            let dirs = (["Library/Application Support/com.apple.TCC"] + Self.fdaGatedDirectories)
                .map { (home as NSString).appendingPathComponent($0) }
            for path in dirs { _ = try? fm.contentsOfDirectory(atPath: path) }

            // Let tccd persist the denial before the pane loads its list.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.openFullDiskAccessSettings()
            }
        }
    }

    /// Reading calendar events requires full access even though the app never writes them.
    package func requestCalendar() {
        guard !requestingCalendar else { return }
        requestingCalendar = true
        calendarRequestFailed = false
        let store = EKEventStore()
        store.requestFullAccessToEvents { [weak self, store] _, error in
            _ = store
            DispatchQueue.main.async {
                self?.calendarPermissionResolution = ProcessInfo.processInfo.systemUptime
                self?.requestingCalendar = false
                let status = EKEventStore.authorizationStatus(for: .event)
                self?.calendarRequestFailed = NotchCalendarSupport.requestFailed(status: status, hasError: error != nil)
                self?.calendarAccess = status
            }
        }
    }

    package func openCalendarSettings() {
        open(pane: "Privacy_Calendars")
    }

    package func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    package func requestMicrophone(completion: ((Bool) -> Void)? = nil) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphone = granted ? .granted : .denied
                completion?(granted)
            }
        }
    }

    package func openCameraSettings() {
        open(pane: "Privacy_Camera")
    }

    package func openMicrophoneSettings() {
        open(pane: "Privacy_Microphone")
    }

    package func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    package func openAutomationSettings() {
        open(pane: "Privacy_Automation")
    }

    package func openAudioCaptureSettings() {
        open(pane: "Privacy_AudioCapture")
    }

    package func openAppManagementSettings() {
        let pane = URL(string:
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AppBundles")!
        if NSWorkspace.shared.open(pane) { return }

        // A general Privacy & Security page is still useful if a future macOS
        // version stops accepting the pane identifier.
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(fallback)
    }

    private func open(pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Automation (Apple Events)

    package enum AutomationTarget: String, CaseIterable {
        case finder = "com.apple.finder"
        case terminal = "com.apple.Terminal"
    }

    package enum AutomationStatus {
        case granted, denied, undetermined, notDeterminable
    }

    /// Never prompts (askUserIfNeeded false). A target that is not running
    /// cannot be checked and reads as notDeterminable. Call off the main
    /// thread; the check can block briefly.
    nonisolated package static func automationStatus(for target: AutomationTarget) -> AutomationStatus {
        var descriptor = AEAddressDesc()
        let bundleID = target.rawValue
        let created = bundleID.withCString { pointer in
            AECreateDesc(typeApplicationBundleID, pointer, bundleID.utf8.count, &descriptor)
        }
        guard created == noErr else { return .notDeterminable }
        defer { AEDisposeDesc(&descriptor) }
        switch AEDeterminePermissionToAutomateTarget(&descriptor, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .undetermined
        default: return .notDeterminable
        }
    }
}
