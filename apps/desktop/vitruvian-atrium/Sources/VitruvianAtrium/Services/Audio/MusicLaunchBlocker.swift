// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices
import VitruvianCore
import VitruvianDesign

/// Blocks a new system music-app process only when a trusted media-key
/// observation explains it. Other launches are preserved, including voice,
/// automation, login and headphone commands that deliver no observable key.
/// Nothing runs while the option, feature or required permission is off.
@MainActor
package final class MusicLaunchBlocker: ObservableObject {
    /// A media key as the tap reads it.
    package struct MediaKey {
        package var subtype: Int
        package var data1: Int
        /// When the key was pressed, in seconds of uptime.
        package var timestamp: TimeInterval

        package init(subtype: Int, data1: Int, timestamp: TimeInterval) {
            self.subtype = subtype
            self.data1 = data1
            self.timestamp = timestamp
        }
    }

    /// A launch of an app that may be blocked.
    package struct LaunchedApp {
        package var bundleID: String?
        package var pid: pid_t
        package var forceTerminate: () -> Bool
        package var terminate: () -> Bool

        package init(bundleID: String?, pid: pid_t,
                     forceTerminate: @escaping () -> Bool, terminate: @escaping () -> Bool) {
            self.bundleID = bundleID
            self.pid = pid
            self.forceTerminate = forceTerminate
            self.terminate = terminate
        }

        init(_ app: NSRunningApplication) {
            self.init(bundleID: app.bundleIdentifier, pid: app.processIdentifier,
                      forceTerminate: { app.forceTerminate() }, terminate: { app.terminate() })
        }
    }

    /// What the blocker reads and drives. `system` is the signed-in user's
    /// defaults, Accessibility, the session's event state, the workspace and a
    /// Core Graphics event tap; tests pass their own.
    package struct System {
        package var defaults: UserDefaults
        package var isTrusted: () -> Bool
        package var uptime: () -> TimeInterval
        package var secondsSinceUserGesture: () -> TimeInterval
        package var isRunning: (_ bundleID: String) -> Bool
        package var notificationCenter: NotificationCenter
        /// A tap that hands each media key to the blocker, or nil when none
        /// could be created.
        package var makeTap: (MusicLaunchBlocker) -> (any MusicLaunchKeyTap)?
        package var openReplacement: (_ startingPlayback: Bool) -> Void

        package init(defaults: UserDefaults,
                     isTrusted: @escaping () -> Bool,
                     uptime: @escaping () -> TimeInterval,
                     secondsSinceUserGesture: @escaping () -> TimeInterval,
                     isRunning: @escaping (String) -> Bool,
                     notificationCenter: NotificationCenter,
                     makeTap: @escaping (MusicLaunchBlocker) -> (any MusicLaunchKeyTap)?,
                     openReplacement: @escaping (Bool) -> Void) {
            self.defaults = defaults
            self.isTrusted = isTrusted
            self.uptime = uptime
            self.secondsSinceUserGesture = secondsSinceUserGesture
            self.isRunning = isRunning
            self.notificationCenter = notificationCenter
            self.makeTap = makeTap
            self.openReplacement = openReplacement
        }

        @MainActor
        static var live: System {
            let replacement = MusicReplacementLauncher()
            return System(
                defaults: .standard,
                isTrusted: { AXIsProcessTrusted() },
                uptime: { ProcessInfo.processInfo.systemUptime },
                secondsSinceUserGesture: { MusicLaunchBlocker.secondsSinceUserGesture },
                isRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty },
                notificationCenter: NSWorkspace.shared.notificationCenter,
                makeTap: { MusicLaunchEventTap(handingKeysTo: $0) },
                openReplacement: { replacement.open(startingPlayback: $0) })
        }
    }

    package static let shared = MusicLaunchBlocker(system: .live)

    /// The current and the legacy identifier of the system music app.
    package static let blockedBundleIDs: Set<String> = ["com.apple.Music", "com.apple.iTunes"]

    @Published package private(set) var isMonitoring = false

    private let system: System
    private var observers: [NSObjectProtocol] = []
    private var mediaKeyTap: (any MusicLaunchKeyTap)?
    package private(set) var lastMediaKeyAt: TimeInterval?
    /// Only Play/Pause asks the replacement to play; the other keys open it.
    private var lastMediaKeyCode: UInt16?
    /// The launch already judged at will-launch. Did-launch for the same
    /// process arrives seconds later, once the app is up, by which time the
    /// click that started it is old enough to look like no gesture at all;
    /// judging it again would terminate a launch the user asked for.
    private var judgedLaunchPID: pid_t?

    package init(system: System) {
        self.system = system
    }

    /// The launch observers installed; two while monitoring.
    package var launchObserverCount: Int { observers.count }
    package var hasMediaKeyTap: Bool { mediaKeyTap != nil }

    package func syncWithPreferences() {
        if isEnabled, system.isTrusted() {
            start()
        } else {
            stop()
        }
    }

    private var isEnabled: Bool {
        AppFeature.musicBlock.isAvailable(in: system.defaults)
            && system.defaults[Preferences.musicBlockEnabled]
    }

    private func start() {
        if mediaKeyTap == nil { mediaKeyTap = system.makeTap(self) }
        guard let mediaKeyTap, mediaKeyTap.isEnabled else {
            stop()
            return
        }
        isMonitoring = true
        guard observers.isEmpty else { return }
        let center = system.notificationCenter
        // Will-launch usually wins the race before any window shows;
        // did-launch catches the rare launch that slips past it.
        observers = [NSWorkspace.willLaunchApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // Delivered on the main queue, which alone reads it.
                nonisolated(unsafe) let note = note
                MainActor.assumeIsolated {
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    self?.handleLaunch(app.map(LaunchedApp.init))
                }
            }
        }
    }

    package func stop() {
        isMonitoring = false
        mediaKeyTap?.remove()
        mediaKeyTap = nil
        lastMediaKeyAt = nil
        judgedLaunchPID = nil
        guard !observers.isEmpty else { return }
        let center = system.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
    }

    package func handleLaunch(_ launched: LaunchedApp?) {
        guard isEnabled, system.isTrusted(), !observers.isEmpty else {
            stop()
            return
        }
        guard let mediaKeyTap, mediaKeyTap.isEnabled else {
            lastMediaKeyAt = nil
            isMonitoring = false
            return
        }
        guard let app = launched,
              let bundleID = app.bundleID,
              Self.blockedBundleIDs.contains(bundleID),
              app.pid != judgedLaunchPID else { return }
        judgedLaunchPID = app.pid
        // One observed key may explain one launch, never a second app process
        // or a relaunch requested while that key is still recent.
        let trigger = lastMediaKeyAt
        lastMediaKeyAt = nil
        guard MusicLaunchSupport.shouldBlockLaunch(
            now: system.uptime(),
            lastTriggerAt: trigger,
            secondsSinceUserGesture: system.secondsSinceUserGesture()
        ) else { return }
        guard app.forceTerminate() || app.terminate() else { return }
        system.openReplacement(lastMediaKeyCode == MusicLaunchSupport.playPauseKeyCode
            && system.defaults[Preferences.musicBlockPlayReplacement])
    }

    /// Pointer buttons and ordinary keys can ask to open an app. Modifier
    /// keys are excluded because holding fn may be how a media key is sent.
    private static let userGestureEventTypes: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp, .keyDown,
    ]

    /// Read from the session's event state, which needs no tap and no
    /// permission.
    private static var secondsSinceUserGesture: TimeInterval {
        userGestureEventTypes.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? .infinity
    }

    /// What the tap saw: `key` reads a media key from a system-defined event
    /// and is asked only once the tap is known to be healthy.
    package func observeMediaKey(type: CGEventType, key: () -> MediaKey?) {
        guard isEnabled, system.isTrusted(), let mediaKeyTap else {
            stop()
            return
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // A gap in observation invalidates the pending launch decision.
            lastMediaKeyAt = nil
            mediaKeyTap.enable()
            isMonitoring = mediaKeyTap.isEnabled
            return
        }
        guard mediaKeyTap.isEnabled else {
            lastMediaKeyAt = nil
            isMonitoring = false
            return
        }
        guard type.rawValue == MusicLaunchSupport.systemDefinedEventTypeRawValue,
              let key = key(),
              MusicLaunchSupport.isMusicLaunchTrigger(subtype: key.subtype, data1: key.data1)
        else { return }
        // A key sent to an existing player cannot explain a later new launch.
        // A race with startup errs on the side of leaving the app alone.
        guard !Self.blockedBundleIDs.contains(where: system.isRunning) else {
            lastMediaKeyAt = nil
            return
        }
        // Use the event's time, not delivery time: a delayed callback must
        // not turn an old key press into fresh launch evidence.
        lastMediaKeyAt = key.timestamp
        lastMediaKeyCode = MusicLaunchSupport.keyCode(data1: key.data1)
    }
}

/// The tap that watches media keys for the blocker. It listens only, so the
/// keys always reach the app they were meant for.
@MainActor
package protocol MusicLaunchKeyTap: AnyObject {
    var isEnabled: Bool { get }
    func enable()
    /// Stops the tap for good.
    func remove()
}

/// A listen-only Core Graphics tap on system-defined events, on the main run
/// loop.
@MainActor
private final class MusicLaunchEventTap: MusicLaunchKeyTap {
    private let tap: CFMachPort
    private let source: CFRunLoopSource

    init?(handingKeysTo blocker: MusicLaunchBlocker) {
        let systemDefined = CGEventType(rawValue: MusicLaunchSupport.systemDefinedEventTypeRawValue)!
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let blocker = Unmanaged<MusicLaunchBlocker>.fromOpaque(userInfo).takeUnretainedValue()
            // Taps on the main run loop are called on the main thread.
            MainActor.assumeIsolated {
                blocker.observeMediaKey(type: type) {
                    NSEvent(cgEvent: event).map {
                        MusicLaunchBlocker.MediaKey(subtype: Int($0.subtype.rawValue), data1: $0.data1,
                                                    timestamp: $0.timestamp)
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << systemDefined.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(blocker).toOpaque()
        ) else { return nil }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    var isEnabled: Bool { CGEvent.tapIsEnabled(tap: tap) }

    func enable() { CGEvent.tapEnable(tap: tap, enable: true) }

    func remove() {
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(tap)
    }
}

/// Opens the replacement app chosen in place of the music app, at most once
/// a second: one media key press produces both a will-launch and a
/// did-launch notification.
@MainActor
private final class MusicReplacementLauncher {
    private var lastLaunch: TimeInterval = 0

    func open(startingPlayback: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLaunch > 1.0 else { return }
        lastLaunch = now

        let path = UserDefaults.standard[Preferences.musicBlockReplacementPath]
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        // The replacement must never be the app being blocked, or the two
        // settings would chase each other in a launch-and-kill loop.
        guard let replacementID = Bundle(url: url)?.bundleIdentifier,
              !MusicLaunchBlocker.blockedBundleIDs.contains(replacementID),
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, _ in
            // Called on a background queue; the setting is read on the main one.
            DispatchQueue.main.async {
                // Play/Pause asked for music, not just a window.
                guard startingPlayback, AppFeature.musicBlock.isAvailable,
                      UserDefaults.standard[Preferences.musicBlockEnabled],
                      UserDefaults.standard[Preferences.musicBlockPlayReplacement],
                      let app else { return }
                MusicReplacementPlayback.start(app)
            }
        }
    }
}

/// Starts playback in the app opened in place of the music app. The command
/// comes from that app's own scripting dictionary, so an app that declares
/// none is only opened, as before, and the media key is never replayed.
private enum MusicReplacementPlayback {
    private static let queue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.music-block.playback",
                                             qos: .userInitiated)

    static func start(_ app: NSRunningApplication) {
        guard let url = app.bundleURL,
              let command = NotchMusicAutomationCapabilities.load(bundleURL: url)?.playCommand else { return }
        let launching = !app.isFinishedLaunching
        let deadline = ProcessInfo.processInfo.systemUptime + MusicLaunchSupport.replacementLaunchTimeout
        queue.async { waitForLaunch(app, command: command, launching: launching, deadline: deadline) }
    }

    private static func waitForLaunch(_ app: NSRunningApplication,
                                      command: NotchMusicAutomationCapabilities.Event,
                                      launching: Bool, deadline: TimeInterval) {
        guard !app.isTerminated, ProcessInfo.processInfo.systemUptime < deadline else { return }
        guard app.isFinishedLaunching else {
            queue.asyncAfter(deadline: .now() + 0.1) {
                waitForLaunch(app, command: command, launching: launching, deadline: deadline)
            }
            return
        }
        // A player that just started may not take commands the moment it is up.
        let settle = launching ? MusicLaunchSupport.replacementSettleDelay : 0
        queue.asyncAfter(deadline: .now() + settle) {
            send(command, to: app, attemptsLeft: MusicLaunchSupport.playbackAttempts)
        }
    }

    private static func send(_ command: NotchMusicAutomationCapabilities.Event,
                             to app: NSRunningApplication, attemptsLeft: Int) {
        guard !app.isTerminated else { return }
        let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
        // Consent is asked once per app, right after the key that needs it;
        // a refusal leaves the app opened, as before.
        var status = Int(AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true))
        if status == Int(noErr) {
            let event = NSAppleEventDescriptor(eventClass: command.eventClass, eventID: command.eventID,
                                               targetDescriptor: target,
                                               returnID: AEReturnID(kAutoGenerateReturnID),
                                               transactionID: AETransactionID(kAnyTransactionID))
            do {
                _ = try event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 2)
                return
            } catch {
                status = (error as NSError).code
            }
        }
        guard attemptsLeft > 1, MusicLaunchSupport.playbackNeverArrived(status) else { return }
        queue.asyncAfter(deadline: .now() + 0.5) {
            send(command, to: app, attemptsLeft: attemptsLeft - 1)
        }
    }
}
