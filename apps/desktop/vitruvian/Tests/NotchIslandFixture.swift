// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Combine
import VitruvianCore
import VitruvianServices

/// A real island, the module's `NotchService`, built over test doubles: a
/// window host that draws nothing, services that record what the island asks
/// of them, one notched built-in display, and notification centers of its
/// own. Its timers wait in `scheduled` until a test runs them, and its open
/// monitors hand their handlers to the test instead of the system.
final class NotchIslandFixture {
    /// A 14-inch built-in display with a camera housing.
    static let display = NotchDisplayInfo(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944), safeAreaTop: 38, cameraWidth: 200,
        backingScale: 2, isBuiltIn: true, hasMenuBar: true)
    /// An external display to the right, with a camera housing of its own.
    static let secondDisplay = NotchDisplayInfo(
        id: 2, frame: CGRect(x: 1512, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 1512, y: 0, width: 1512, height: 944), safeAreaTop: 38, cameraWidth: 200,
        backingScale: 2, isBuiltIn: false, hasMenuBar: false)
    /// A point on the island, just below the top edge of its display.
    static let onIsland = CGPoint(x: display.frame.midX, y: display.frame.maxY - 1)
    /// A point well away from the island.
    static let awayFromIsland = CGPoint(x: display.frame.midX, y: display.frame.midY)

    let defaults: UserDefaults
    let services = RecordingIslandServices()
    /// The app's notifications: menus, windows, screens and preferences.
    let notifications = NotificationCenter()
    /// The workspace's: sleep, wake and the console.
    let workspace = NotificationCenter()
    /// The session's: lock, unlock and the screen saver.
    let session = NotificationCenter()
    let events = Events()
    var pointer = NotchIslandFixture.awayFromIsland
    var displays = [NotchIslandFixture.display]
    /// The displays showing a full-screen Space.
    var fullscreen: Set<CGDirectDisplayID> = []
    /// The room the menus leave beside the camera, as the menu reader
    /// measures it with Accessibility granted; nil grants nothing.
    var menuRoom: CGFloat?
    var hasBattery = true
    var currentSession = NotchSessionState()
    /// Each window the island built, the current one last.
    private(set) var hosts: [RecordingIslandHost] = []
    var host: RecordingIslandHost? { hosts.last }
    /// Each copy's window the island built, in order.
    private(set) var mirrors: [RecordingMirrorHost] = []
    /// Work the island scheduled, with its delay, in order.
    private(set) var scheduled: [(delay: TimeInterval, work: DispatchWorkItem)] = []
    /// The open island's monitors, while it has them.
    private(set) var clickElsewhere: (() -> Void)?
    private(set) var localEvent: ((NSEvent) -> Bool)?
    private(set) lazy var island = NotchService(environment: environment)

    init(defaults: UserDefaults) {
        _ = NSApplication.shared
        self.defaults = defaults
    }

    /// Starts the island as the app does, then forgets what starting asked of
    /// its services, so a test reads only what follows.
    @discardableResult
    func start() -> NotchService {
        island.syncWithPreferences()
        services.reset()
        return island
    }

    /// Runs scheduled work that is still due, earliest first, until none is.
    func runScheduled() {
        while let index = scheduled.firstIndex(where: { !$0.work.isCancelled }) {
            let work = scheduled.remove(at: index).work
            work.perform()
        }
    }

    /// Lets the main queue deliver anything posted to it.
    func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }

    /// Posts a workspace or session notification, as the system would.
    func post(workspace name: Notification.Name) {
        workspace.post(name: name, object: nil)
        settle()
    }

    func post(session name: String) {
        session.post(name: Notification.Name(name), object: nil)
        settle()
    }

    /// Sends a key to the open island as the app's own monitor would.
    @discardableResult
    func press(keyCode: UInt16, characters: String = "") -> Bool {
        guard let localEvent, let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: island.presentationWindow?.windowNumber ?? 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
            keyCode: keyCode) else { return false }
        return localEvent(event)
    }

    private var environment: NotchService.Environment {
        NotchService.Environment(
            defaults: defaults,
            makeHost: { [unowned self] _, geometry, size in
                let host = RecordingIslandHost(geometry: geometry, size: size)
                self.hosts.append(host)
                return host
            },
            makeMirror: { [unowned self] _, _, geometry, size in
                let mirror = RecordingMirrorHost(frame: geometry.frame(for: size))
                self.mirrors.append(mirror)
                return mirror
            },
            pointer: { [unowned self] in self.pointer },
            reducesMotion: { false },
            schedule: { [unowned self] delay, work in self.scheduled.append((delay: delay, work: work)) },
            services: services,
            displays: { [unowned self] in self.displays },
            separateSpaces: { true },
            statusBarThickness: { 24 },
            hasBattery: { [unowned self] in self.hasBattery },
            parts: parts)
    }

    private var parts: NotchService.Environment.Parts {
        let events = self.events
        let silentMovement = NotchMovementWatch.Environment(addMonitors: { _ in [] }, removeMonitor: { _ in })
        return NotchService.Environment.Parts(
            movement: { _, _ in silentMovement },
            events: { events.sources },
            volume: NotchVolumeFeedback.Output(volume: { 0.5 }, muted: { false }, deviceUID: { nil },
                                               changes: { Empty(completeImmediately: false).eraseToAnyPublisher() }),
            menuSpace: NotchMenuSpaceReader.Environment(
                menuBarOwner: { [unowned self] in self.menuRoom == nil ? nil : 1 },
                measure: { [unowned self] _, _ in self.menuRoom },
                background: { $0() }, main: { $0() }, ticks: { _ in {} }),
            pointerFollower: NotchPointerFollower.Environment(
                addMonitors: { _ in [] }, removeMonitor: { _ in }, mouseLocation: { [unowned self] in self.pointer },
                displayCount: { [unowned self] in self.displays.count }, displayWithMouse: { nil },
                schedule: { _, _ in {} }),
            screenRefresh: NotchScreenRefresh.Environment(
                schedule: { _, _ in }, accessibilityGranted: { [unowned self] in self.menuRoom != nil },
                coversMenus: { [unowned self] in NotchSupport.coversMenus(in: self.defaults) },
                frontmostBundleID: { nil }, ownBundleID: nil, mouseLocation: { [unowned self] in self.pointer }),
            fullscreen: NotchFullscreenVisibility.Environment(
                hidesInFullscreen: { [unowned self] in self.defaults.bool(forKey: DefaultsKey.notchHideInFullscreen) },
                showsFullscreen: { [unowned self] in self.fullscreen.contains($0) }),
            screenEdges: { _ in NotchScreenEdgeClicks.Environment(addMonitors: { _ in [] }, removeMonitor: { _ in }) },
            fileDrop: { shelfAccept in
                NotchFileDrop.Environment(offersMedia: { _ in false }, mediaAccepts: { false }, openMedia: { _ in false },
                                          hideMedia: {}, shelfEnabled: { false }, shelfAccept: shelfAccept)
            },
            openEvents: NotchOpenEvents(addMonitors: { [unowned self] clickElsewhere, local in
                self.clickElsewhere = clickElsewhere
                self.localEvent = local
                return ["open monitors"]
            }, removeMonitor: { [unowned self] _ in
                self.clickElsewhere = nil
                self.localEvent = nil
            }),
            fullscreenDisplays: { [unowned self] ids in Set(ids).intersection(self.fullscreen) },
            notifications: notifications, workspaceNotifications: workspace, sessionNotifications: session,
            currentSession: { [unowned self] in self.currentSession })
    }

    /// What the island hears from the app's services, sent when a test says.
    final class Events {
        let timer = PassthroughSubject<Void, Never>()
        let music = PassthroughSubject<(NotchPlayback?, NSImage?, NotchArtworkTint?), Never>()
        let trackEnds = PassthroughSubject<Void, Never>()
        let musicActivity = PassthroughSubject<Void, Never>()
        let songTitles = PassthroughSubject<String?, Never>()
        let trackChanges = PassthroughSubject<Void, Never>()
        let downloads = PassthroughSubject<Void, Never>()
        let calendar = PassthroughSubject<Void, Never>()
        let keepAwake = PassthroughSubject<Void, Never>()
        let systemNotifications = PassthroughSubject<NotchSystemNotification, Never>()

        var sources: NotchEventBindings.Sources {
            NotchEventBindings.Sources(
                timer: { self.timer.eraseToAnyPublisher() },
                watch: { Empty(completeImmediately: false).eraseToAnyPublisher() },
                music: { self.music.eraseToAnyPublisher() },
                trackEnds: { self.trackEnds.eraseToAnyPublisher() },
                musicActivity: { self.musicActivity.eraseToAnyPublisher() },
                songTitles: { self.songTitles.eraseToAnyPublisher() },
                trackChanges: { self.trackChanges.eraseToAnyPublisher() },
                tools: { Empty(completeImmediately: false).eraseToAnyPublisher() },
                fanCard: { Empty(completeImmediately: false).eraseToAnyPublisher() },
                downloads: { self.downloads.eraseToAnyPublisher() },
                setDownloadArrival: { _ in },
                agentActivity: { Empty(completeImmediately: false).eraseToAnyPublisher() },
                calendar: { self.calendar.eraseToAnyPublisher() },
                keepAwake: { self.keepAwake.eraseToAnyPublisher() },
                agentEvents: { Empty(completeImmediately: false).eraseToAnyPublisher() },
                systemNotifications: { self.systemNotifications.eraseToAnyPublisher() },
                hideNativeNotification: { _ in },
                clipboardCaptures: { Empty(completeImmediately: false).eraseToAnyPublisher() })
        }
    }
}

/// The island's window as the island sees it, drawing nothing. Its panel is
/// real but transparent and ignores the mouse; the pointer is over the island
/// when it is inside the frame last presented.
final class RecordingIslandHost: NotchIslandHost {
    let panel: NotchPanel
    private(set) var targetSize: CGSize
    private(set) var frame: CGRect
    var departsContent = false
    var isConcealedForMissionControl = false
    var missionControlDidRestore: (() -> Void)?
    var hasKeyboard = false
    private(set) var presents = 0
    private(set) var hides = 0
    private(set) var closed = false
    private(set) var hoverHandler: ((Bool) -> Void)?
    private(set) var activate: (() -> Void)?
    private(set) var fileDropActions: NotchFileDropActions?

    init(geometry: NotchGeometry, size: CGSize) {
        frame = geometry.frame(for: size)
        targetSize = size
        panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
    }

    func containsHover(_ screenPoint: CGPoint) -> Bool { contains(screenPoint) }
    func contains(_ screenPoint: CGPoint) -> Bool {
        // The top edge belongs to the island, as the flipped native view has it.
        frame.insetBy(dx: 0, dy: -1).contains(screenPoint)
    }
    func containsDestination(_ screenPoint: CGPoint) -> Bool { contains(screenPoint) }
    func containsSurface(_ screenPoint: CGPoint) -> Bool { contains(screenPoint) }
    func blocksHoverReveal() -> Bool { false }

    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition,
                 quickAccess: NotchQuickAccessConfiguration?, revealFromHidden: Bool,
                 hideWhenSettled: Bool, usesGlass: Bool) {
        presents += 1
        targetSize = size
        frame = geometry.frame(for: size)
    }
    func hide(animated: Bool, transitionContent: NotchContentTransition) { hides += 1 }
    func finishDeparture() {}
    func whenSettled(_ action: @escaping @MainActor () -> Void) { action() }
    func close() {
        closed = true
        panel.orderOut(nil)
    }

    func takeKeyboard() { if panel.acceptsKeyFocus { hasKeyboard = true } }
    func releaseKeyboard() { hasKeyboard = false }

    func setMouseEventsIgnored(_ ignored: Bool) {}
    func setFileDropActions(_ actions: NotchFileDropActions?) { fileDropActions = actions }
    func setOutline(enabled: Bool, color: NSColor) {}
    func setHoverHandler(_ handler: @escaping (Bool) -> Void) { hoverHandler = handler }
    func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void,
                           activate: @escaping () -> Void) { self.activate = activate }
}

/// A copy of the closed island on another display, drawing nothing.
nonisolated final class RecordingMirrorHost: NotchMirrorHost {
    private(set) var frame: CGRect
    var panelSharingType: NSWindow.SharingType = .readOnly
    private(set) var panelIsVisible = false
    var visibleWindowID: CGWindowID? { nil }
    private(set) var closed = false

    init(frame: CGRect) {
        self.frame = frame
    }

    func orderPanelFront() { panelIsVisible = true }
    func presentCopy(size: CGSize, geometry: NotchGeometry, animated: Bool,
                     transitionContent: NotchContentTransition) {
        frame = geometry.frame(for: size)
        panelIsVisible = true
    }
    func hideCopy() { panelIsVisible = false }
    func close() {
        closed = true
        panelIsVisible = false
    }
    func setOutline(enabled: Bool, color: NSColor) {}
    func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void,
                           activate: @escaping () -> Void) {}
}

/// The island's services as readings a test sets, and a log of what the
/// island asked of them, in order.
final class RecordingIslandServices: NotchIslandServices {
    private(set) var calls: [String] = []
    /// The timer runs until the island suspends it, and again once synced.
    private(set) var timerRunning = true
    /// The playback reader runs between the island's start and stop.
    private(set) var musicRunning = false
    private(set) var lockScreenSyncs: [NotchSessionState] = []
    private(set) var lockSounds: [Bool] = []
    private(set) var monitorDetailNeeds = SystemMonitorPanelNeeds.none
    /// Runs as the island syncs the lock screen, before the sync is logged.
    var onSyncLockScreen: ((NotchSessionState) -> Void)?
    var prepareToolsAction: () -> Void = {}
    var toolsKey: (NSEvent, QuickToolsSupport.GridFlow) -> Bool = { _, _ in false }

    func reset() {
        calls.removeAll()
        lockScreenSyncs.removeAll()
        lockSounds.removeAll()
    }

    func count(_ call: String) -> Int { calls.filter { $0 == call }.count }

    private func log(_ call: String) { calls.append(call) }

    // MARK: Readings

    var playback: NotchPlayback?
    var artwork: NSImage?
    var artworkTint: NotchArtworkTint?
    var timerSession = NotchTimerSession()
    var timerNow: TimeInterval = 1_000
    var watchActive = false
    var watchHeadline = ""
    var watchShowsThumbnail = false
    var downloads: [NotchDownloadItem] = []
    var choosingDownloadFolder = false
    var agentUsage = AgentUsageSnapshot()
    var keepAwakeActive = false
    var keepAwakeEndDate: Date?
    var calendarCountdown: NotchCalendarCountdown?
    var chosenCalendarEvent = false
    func calendarIsChosen(_ event: NotchCalendarEvent) -> Bool { chosenCalendarEvent }
    var importingLyrics = false
    var scratchpadModal = false
    var canCreatePad = true
    var canClosePad = true
    var keepsCalendarPrompt = false
    var keepsCameraPrompt = false
    var activeUtility: QuickLauncherItem?
    var editingTools = false
    var visibleTools: [QuickLauncherItem] = []
    var mediaPresented = false
    var mediaContentHeight: CGFloat?
    var offersMediaDrop = false
    var systemSnapshot = SystemSnapshot()
    var updateOffered = false
    var openingNotification: UUID?

    // MARK: Starting and stopping

    func startMusic() { musicRunning = true; log("startMusic") }
    func stopMusic() { musicRunning = false; log("stopMusic") }
    func syncTimer() { timerRunning = true; log("syncTimer") }
    func suspendTimer() { timerRunning = false; log("suspendTimer") }
    func stopTimer() { log("stopTimer") }
    func syncWatch() { log("syncWatch") }
    func stopWatch() { log("stopWatch") }
    func syncDownloads() { log("syncDownloads") }
    func stopDownloads() { log("stopDownloads") }
    func syncCalendar() { log("syncCalendar") }
    func stopCalendar() { log("stopCalendar") }
    func syncNotifications() { log("syncNotifications") }
    func stopNotifications() { log("stopNotifications") }
    func syncAudioLevel() { log("syncAudioLevel") }
    func stopAudioLevel() { log("stopAudioLevel") }
    func syncAgentUsage() { log("syncAgentUsage") }
    func pauseAgentUsage() { log("pauseAgentUsage") }
    func stopAgentUsage() { log("stopAgentUsage") }
    func syncAccessories() { log("syncAccessories") }
    func suspendAccessories() { log("suspendAccessories") }
    func stopAccessories() { log("stopAccessories") }
    func syncFileTools() { log("syncFileTools") }
    func stopFileTools() { log("stopFileTools") }
    func stopLyrics() { log("stopLyrics") }
    func hideCamera() { log("hideCamera") }
    func setMonitorDetailNeeds(_ needs: SystemMonitorPanelNeeds) { monitorDetailNeeds = needs }
    func setMonitorVisible(_ visible: Bool) { log("setMonitorVisible \(visible)") }
    func syncLockScreen(_ session: NotchSessionState) {
        onSyncLockScreen?(session)
        lockScreenSyncs.append(session)
        log("syncLockScreen")
    }
    func closeLockScreen() { log("closeLockScreen") }
    func playLockSound(locking: Bool) { lockSounds.append(locking) }

    // MARK: Actions

    func rememberPasteTarget() { log("rememberPasteTarget") }
    func prepareTools() { log("prepareTools"); prepareToolsAction() }
    func takesToolsKey(_ event: NSEvent, flow: QuickToolsSupport.GridFlow) -> Bool { toolsKey(event, flow) }
    func createPad(defaultName: String) { log("createPad") }
    func showNormalMenuPanel() { log("showNormalMenuPanel") }
    func skipTrack(forward: Bool) { log("skipTrack \(forward)") }
    func openNotification(_ id: UUID,
                          completion: @escaping @MainActor @Sendable (NotchNotificationReader.ActionResult) -> Void) {
        log("openNotification")
    }
    func dismissNotification(_ id: UUID) { log("dismissNotification") }
    func toggleKeepAwake() { log("toggleKeepAwake") }
    func toggleMicrophone() { log("toggleMicrophone") }
    func captureScreenshot() { log("captureScreenshot") }
    func toggleRecording() { log("toggleRecording") }
    func showCommandBar() { log("showCommandBar") }
    func showScratchpad() { log("showScratchpad") }
    func openNotchSettings() { log("openNotchSettings") }
    func showSettingsModule(_ module: NotchModule) { log("showSettingsModule \(module.rawValue)") }

    // MARK: The app around the island

    var hasModalWindow = false
    func isOverStatusItem(_ point: CGPoint) -> Bool { false }
    func assistiveKeyboardOwns(_ point: CGPoint) -> Bool { false }
    func closeMenuPopover() { log("closeMenuPopover") }
    func openSettingsWindow() { log("openSettingsWindow") }
    func showUpdatePreview() { log("showUpdatePreview") }
}
