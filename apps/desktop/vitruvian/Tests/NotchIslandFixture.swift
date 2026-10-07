// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Combine
import VitruvianCore
import VitruvianServices

/// A real island, the module's `NotchService`, built over test doubles: a
/// window host that draws nothing, services that record what the island asks
/// of them, one notched built-in display, and notification centers of its
/// own. Its timers run on a clock the test advances, and its monitors hand
/// their handlers to the test instead of the system.
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
    /// Accessibility is granted, so the menu reader measures the menus.
    var menusReadable = false
    /// The room the menus leave beside the camera, as the reader measures it;
    /// nil when they cover the center.
    var menuRoom: CGFloat?
    var hasBattery = true
    var reducesMotion = false
    var currentSession = NotchSessionState()
    /// Each window the island built, the current one last.
    private(set) var hosts: [RecordingIslandHost] = []
    var host: RecordingIslandHost? { hosts.last }
    /// Each copy's window the island built, in order.
    private(set) var mirrors: [RecordingMirrorHost] = []
    /// The island's clock, in seconds, which only `advance` moves.
    private(set) var now: TimeInterval = 0
    /// Work the island scheduled, with when it is due and its delay, in order.
    private(set) var scheduled: [(due: TimeInterval, delay: TimeInterval, work: DispatchWorkItem)] = []
    /// The open island's monitors, while it has them.
    private(set) var clickElsewhere: (() -> Void)?
    private(set) var localEvent: ((NSEvent) -> Bool)?
    /// The pointer watches installed now, each with what a move runs.
    private var movementWatches: [Int: () -> Void] = [:]
    private var nextWatch = 0
    var watchesMovement: Bool { !movementWatches.isEmpty }
    var movementWatchCount: Int { movementWatches.count }
    /// The screen-edge click monitors installed now.
    private(set) var edgeMonitors = 0
    private var menuTick: (() -> Void)?
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

    /// Moves the clock on, running the work that falls due, earliest first.
    func advance(_ seconds: TimeInterval) {
        let end = now + seconds
        while let next = scheduled.indices.filter({ !scheduled[$0].work.isCancelled && scheduled[$0].due <= end })
                .min(by: { scheduled[$0].due < scheduled[$1].due }) {
            let item = scheduled.remove(at: next)
            now = max(now, item.due)
            item.work.perform()
        }
        now = end
        scheduled.removeAll { $0.work.isCancelled }
    }

    /// Runs everything scheduled, and what that schedules, in order.
    func runScheduled() {
        while scheduled.contains(where: { !$0.work.isCancelled }) {
            advance(scheduled.filter { !$0.work.isCancelled }.map(\.due).max()! - now)
        }
    }

    /// Work still waiting to run.
    var pendingWork: Int { scheduled.filter { !$0.work.isCancelled }.count }

    /// The delays of the work still waiting, in order.
    var pendingDelays: [TimeInterval] { scheduled.filter { !$0.work.isCancelled }.map(\.delay) }

    /// Moves the pointer as the mouse would: the island's window reports
    /// entering or leaving it, then each pointer watch sees the move.
    func move(to point: CGPoint) {
        let wasOver = host?.containsHover(pointer) == true
        pointer = point
        if let host, host.containsHover(point) != wasOver { host.hoverHandler?(!wasOver) }
        for moved in movementWatches.values { moved() }
    }

    /// Moves the pointer with no report from the island's window, as when it
    /// leaves over transparent pixels: only the pointer watches see it.
    func drift(to point: CGPoint) {
        pointer = point
        for moved in movementWatches.values { moved() }
    }

    /// The menu reader's next timed reading.
    func measureMenus() { menuTick?() }

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
            reducesMotion: { [unowned self] in self.reducesMotion },
            schedule: { [unowned self] delay, work in
                self.scheduled.append((due: self.now + delay, delay: delay, work: work))
            },
            services: services,
            displays: { [unowned self] in self.displays },
            separateSpaces: { true },
            statusBarThickness: { 24 },
            hasBattery: { [unowned self] in self.hasBattery },
            parts: parts)
    }

    private var parts: NotchService.Environment.Parts {
        let events = self.events
        let movement = NotchMovementWatch.Environment(addMonitors: { [unowned self] moved in
            self.nextWatch += 1
            self.movementWatches[self.nextWatch] = moved
            return [self.nextWatch]
        }, removeMonitor: { [unowned self] token in
            if let id = token as? Int { self.movementWatches[id] = nil }
        })
        return NotchService.Environment.Parts(
            movement: { _, _ in movement },
            events: { events.sources },
            volume: NotchVolumeFeedback.Output(volume: { 0.5 }, muted: { false }, deviceUID: { nil },
                                               changes: { Empty(completeImmediately: false).eraseToAnyPublisher() }),
            menuSpace: NotchMenuSpaceReader.Environment(
                menuBarOwner: { [unowned self] in self.menusReadable ? 1 : nil },
                measure: { [unowned self] _, _ in self.menuRoom },
                background: { $0() }, main: { $0() },
                ticks: { [unowned self] tick in
                    self.menuTick = tick
                    return { [unowned self] in self.menuTick = nil }
                }),
            pointerFollower: NotchPointerFollower.Environment(
                addMonitors: { _ in [] }, removeMonitor: { _ in }, mouseLocation: { [unowned self] in self.pointer },
                displayCount: { [unowned self] in self.displays.count }, displayWithMouse: { nil },
                schedule: { _, _ in {} }),
            screenRefresh: NotchScreenRefresh.Environment(
                schedule: { _, _ in }, accessibilityGranted: { [unowned self] in self.menusReadable },
                coversMenus: { [unowned self] in NotchSupport.coversMenus(in: self.defaults) },
                frontmostBundleID: { nil }, ownBundleID: nil, mouseLocation: { [unowned self] in self.pointer }),
            fullscreen: NotchFullscreenVisibility.Environment(
                hidesInFullscreen: { [unowned self] in self.defaults.bool(forKey: DefaultsKey.notchHideInFullscreen) },
                showsFullscreen: { [unowned self] in self.fullscreen.contains($0) }),
            screenEdges: { [unowned self] _ in
                NotchScreenEdgeClicks.Environment(addMonitors: { [unowned self] _ in
                    self.edgeMonitors += 1
                    return ["edge"]
                }, removeMonitor: { [unowned self] _ in self.edgeMonitors -= 1 })
            },
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
/// real but transparent; the pointer is over the island when it is inside the
/// frame last presented, and a hide orders the panel out at once.
final class RecordingIslandHost: NotchIslandHost {
    let panel: NotchPanel
    private(set) var targetSize: CGSize
    private(set) var frame: CGRect
    /// The frame a resize is still animating away from, which keeps its hits.
    var animatingFrame: CGRect?
    /// Further rects that count as over the island, as floating controls do.
    var hoverExtras: [CGRect] = []
    var departsContent = false
    /// Who takes the mouse, by the host's own rules.
    private(set) var input = NotchWindowInputPolicy()
    var isConcealedForMissionControl: Bool { input.concealed }
    var missionControlDidRestore: (() -> Void)?
    var hasKeyboard = false
    private(set) var keyboardRequests = 0
    private(set) var presents = 0
    /// Whether each hide was animated, in order.
    private(set) var hideAnimations: [Bool] = []
    private(set) var transitions: [NotchContentTransition] = []
    /// Whether each presentation only eased a strip to a new reading's width.
    private(set) var steadies: [Bool] = []
    private(set) var usesGlass = false
    private(set) var revealFromHidden = false
    private(set) var outlineEnabled = false
    private(set) var outlineColor = NSColor.white
    private(set) var activationRect = CGRect.zero
    private(set) var closed = false
    private(set) var hoverHandler: ((Bool) -> Void)?
    /// A press on the activation area, before it activates.
    private(set) var willPress: (() -> Void)?
    private(set) var activate: (() -> Void)?
    /// How often the island asked whether Mission Control blocks a reveal.
    private(set) var revealChecks = 0
    private(set) var fileDropActions: NotchFileDropActions?
    /// Runs as each present arrives, with its size.
    var onPresent: ((CGSize) -> Void)?

    init(geometry: NotchGeometry, size: CGSize) {
        frame = geometry.frame(for: size)
        targetSize = size
        panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.alphaValue = 0
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
    }

    /// The top edge belongs to the island, as the flipped native view has it.
    private static func holds(_ rect: CGRect, _ point: CGPoint) -> Bool {
        rect.insetBy(dx: 0, dy: -1).contains(point)
    }
    /// As the real host has it, only a window on screen and outside Mission Control holds the pointer.
    private var presented: Bool { panel.isVisible && !isConcealedForMissionControl }
    func containsHover(_ screenPoint: CGPoint) -> Bool {
        presented && (Self.holds(frame, screenPoint) || hoverExtras.contains { $0.contains(screenPoint) })
    }
    func contains(_ screenPoint: CGPoint) -> Bool {
        presented && Self.holds(animatingFrame ?? frame, screenPoint)
    }
    func containsDestination(_ screenPoint: CGPoint) -> Bool { contains(screenPoint) }
    func containsSurface(_ screenPoint: CGPoint) -> Bool { contains(screenPoint) }
    func blocksHoverReveal() -> Bool {
        revealChecks += 1
        return isConcealedForMissionControl
    }

    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition,
                 quickAccess: NotchQuickAccessConfiguration?, revealFromHidden: Bool,
                 hideWhenSettled: Bool, usesGlass: Bool, steady: Bool) {
        presents += 1
        steadies.append(steady)
        let ignoresMouse = input.present(hidingWhenSettled: hideWhenSettled, panelIgnores: panel.ignoresMouseEvents)
        if panel.ignoresMouseEvents != ignoresMouse { panel.ignoresMouseEvents = ignoresMouse }
        transitions.append(transitionContent)
        // Departing content stays on screen while the shape closes around it.
        departsContent = transitionContent == .depart
        self.usesGlass = usesGlass
        self.revealFromHidden = revealFromHidden
        onPresent?(size)
        targetSize = size
        frame = geometry.frame(for: size)
    }
    func hide(animated: Bool, transitionContent: NotchContentTransition) {
        hideAnimations.append(animated)
        panel.orderOut(nil)
    }
    func finishDeparture() { departsContent = false }
    func whenSettled(_ action: @escaping @MainActor () -> Void) { action() }
    func close() {
        closed = true
        panel.orderOut(nil)
    }

    func takeKeyboard() {
        keyboardRequests += 1
        if panel.acceptsKeyFocus { hasKeyboard = true }
    }
    func releaseKeyboard() { hasKeyboard = false }

    func setMouseEventsIgnored(_ ignored: Bool) {
        let effective = input.ask(ignored: ignored)
        if panel.ignoresMouseEvents != effective { panel.ignoresMouseEvents = effective }
    }

    /// Mission Control starts, as the real host's sampling finds it.
    func concealForMissionControl() {
        panel.ignoresMouseEvents = input.conceal(panelIgnores: panel.ignoresMouseEvents)
    }

    /// Mission Control ends; a visible island fades back in until `finishMissionControlFade()`.
    func restoreFromMissionControl() {
        panel.ignoresMouseEvents = input.restore(panelVisible: panel.isVisible)
        missionControlDidRestore?()
    }

    func finishMissionControlFade() { input.finishRestore() }
    func setFileDropActions(_ actions: NotchFileDropActions?) { fileDropActions = actions }
    func setOutline(enabled: Bool, color: NSColor) {
        outlineEnabled = enabled
        outlineColor = color
    }
    func setHoverHandler(_ handler: @escaping (Bool) -> Void) { hoverHandler = handler }
    func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void,
                           activate: @escaping () -> Void) {
        activationRect = rect
        self.willPress = willPress
        self.activate = activate
    }
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
    /// The event the island last asked the Calendar page to scroll to.
    private(set) var revealedCalendarEvent: String?
    func revealCalendarEvent(_ id: String?) { revealedCalendarEvent = id }
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
    var headerShowsUpdate = false
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
    /// The Accessibility Keyboard covers the pointer.
    var assistiveKeyboardActive = false
    func assistiveKeyboardOwns(_ point: CGPoint) -> Bool { assistiveKeyboardActive }
    func closeMenuPopover() { log("closeMenuPopover") }
    func openSettingsWindow() { log("openSettingsWindow") }
    func showUpdatePreview() { log("showUpdatePreview") }
}
