// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.ps
import SwiftUI
import VitruvianCore
import VitruvianDesign

package struct NotchNotice: Equatable {
    package let event: NotchEvent
    package let title: String
    package let detail: String
    package let symbol: String
    package var level: Double? = nil
    package var notification: NotchNotificationContent? = nil
    package var notificationID: UUID? = nil
    /// The agent an AI notice is about, which tints its mark.
    package var agent: AgentProvider? = nil
    /// A banner that replaces one still on screen keeps at least its width,
    /// so a burst of messages does not resize the island with each one.
    package var minimumWingWidth: CGFloat = 0

    package var preferredWingWidth: CGFloat {
        if let notification { return max(minimumWingWidth, NotchNotificationBannerLayout.wing(for: notification)) }
        let font = NotchNoticeLayout.font
        let leading = ((level == nil ? title : detail) as NSString).size(withAttributes: [.font: font]).width
        let trailing = level == nil ? (detail as NSString).size(withAttributes: [.font: font]).width : 0
        // Reserve enough for the widest percentage without giving the short
        // label the same oversized wing used by text notices.
        if level != nil, event != .accessory { return 80 }
        // Long accessory names still use bounded truncation.
        let maximum: CGFloat = event == .accessory && level == nil ? 160 : 240
        let symbol = NotchNoticeLayout.symbolWidth + NotchNoticeLayout.spacing
        return min(maximum, max(88, ceil(max(leading + symbol, trailing)) + NotchNoticeLayout.inset + cameraGap))
    }

    /// Two lines of text sit at the island's two ends, each as far from its
    /// curved edge, so a short one leaves its spare room beside the camera
    /// rather than at one end. Levels and banners keep their own layout.
    package var readsFromEnds: Bool { level == nil && notification == nil }

    /// Room text keeps from the camera; battery labels need breathing room
    /// at both the curved edge and the camera.
    package var cameraGap: CGFloat { event == .battery ? 16 : readsFromEnds ? 6 : 0 }

    package var accessibilityText: String {
        notification?.accessibilityText ?? [title, detail].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    package func previewContentHeight(width: CGFloat) -> CGFloat {
        guard let notification else { return 0 }
        return NotchNotificationPreviewLayout.contentHeight(for: notification, width: width)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(event: NotchEvent, title: String, detail: String, symbol: String, level: Double? = nil, notification: NotchNotificationContent? = nil, notificationID: UUID? = nil, agent: AgentProvider? = nil, minimumWingWidth: CGFloat = 0) {
        self.event = event
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.level = level
        self.notification = notification
        self.notificationID = notificationID
        self.agent = agent
        self.minimumWingWidth = minimumWingWidth
    }
}

/// Owns presentation only. Clipboard, files, captures, audio and metrics keep
/// their original owners, gates and privacy rules.
@MainActor
package final class NotchService: ObservableObject {
    package static let shared = NotchService()
    /// The services that follow the island. The composition root
    /// (`main.swift`) fills this in before the app runs, so the island names
    /// none of them.
    package static var collaborators = NotchCollaborators()
    nonisolated package static let fullscreenVisibilityDidChange = Notification.Name("NotchFullscreenVisibilityDidChange")

    @Published package private(set) var geometry = NotchGeometry(
        screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0, cameraWidth: 0)
    @Published package private(set) var expanded = false
    @Published package private(set) var peeking = false
    @Published package private(set) var dragPlaceholder = false
    /// A drag onto the island offers the shelf and the media tools.
    package var choosingFileDropDestination: Bool {
        fileDrop.choosingDestination
    }
    /// The pointer is over the media tools' destination.
    package var targetsMediaDrop: Bool {
        fileDrop.targetsMedia
    }
    @Published package private(set) var selectedMetric: MetricDetailKind?
    @Published package private(set) var captureControls: ScreenCaptureSelectionOptions?
    @Published package private(set) var captureControlsCollapsed = false
    @Published package private(set) var captureSelectionInProgress = false
    @Published package var pinned = false
    @Published package private(set) var selected: NotchModule = .controls
    @Published package private(set) var showingAppPanel = false
    @Published package private(set) var showingSections = false
    @Published package private(set) var sectionQuery = ""
    @Published package var highlightedSection: NotchModule? { didSet { revealHighlightedSection() } }
    /// The gallery's first visible row; the rows above it have stepped away.
    @Published package private(set) var sectionRow = 0
    @Published package private(set) var modules: [NotchModule] = []
    @Published package private(set) var notice: NotchNotice?
    @Published package private(set) var noticeExpanded = false
    /// A compact notice stays drawn while the island closes around it.
    @Published package private(set) var departingNotice: NotchNotice?
    @Published package private(set) var departingMusic: NotchCompactMusicSnapshot?
    /// The compact track on screen when a new song arrives, kept while the
    /// song's notice waits for playback to settle, so the notice rather than
    /// the strip is where the new song first appears.
    @Published package private(set) var heldMusic: NotchCompactMusicSnapshot?
    @Published package private(set) var captureActions: AnyView?
    @Published package private(set) var captureContent: AnyView?
    /// Bumped when Command-W asks the Scratchpad page to close its selected
    /// pad, so the confirmation stays in the page as it does in the floating pad.
    @Published package private(set) var scratchpadCloseSerial = 0
    /// Find runs against the island's own text view, which the page holds;
    /// the key arrives here, so it is passed on the way Command-W already is.
    @Published package private(set) var scratchpadFindSerial = 0
    package private(set) var scratchpadFindAction = NSTextFinder.Action.showFindInterface
    /// The last ⌘1–⌘9 pressed on the Clipboard page, which the page turns
    /// into a paste of the entry at that place.
    @Published package private(set) var clipboardPastePress: NotchClipboardPastePress?
    /// Whether the island panel holds the keyboard. Opened by hover, or left
    /// open while another app is active, it does not, and its shortcuts then
    /// reach the app in front instead.
    @Published package private(set) var panelIsKey = false
    @Published private var captureContentHeight: CGFloat?
    /// Kept after closing, so the next Fan Control detail opens at its size.
    @Published private var fanDetailHeight: CGFloat?
    @Published package private(set) var power = PowerReading()
    @Published private var musicDetailVisible = false

    private var windowHost: NotchWindowHost?
    private var panel: NotchPanel? { windowHost?.panel }
    private var captureControlsCancel: (() -> Void)?
    private var captureControlsSubscription: AnyCancellable?
    private var captureControlsWork: DispatchWorkItem?
    private var heldDrag = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var eventMonitors: [Any] = []
    /// Clicks on the menu bar above the closed island (`NotchScreenEdgeClicks`).
    private lazy var screenEdgeClicks: NotchScreenEdgeClicks = NotchScreenEdgeClicks(
        environment: .system(islandWindow: { [weak self] in self?.panel }),
        island: NotchScreenEdgeClicks.Island(
            area: { [weak self] in self?.screenEdgeClickArea },
            floatingGap: { [weak self] in self?.geometry.floatingGap },
            keepsWorkingSurface: { [weak self] in self?.keepsWorkingSurface ?? false },
            containsDestination: { [weak self] in self?.windowHost?.containsDestination($0) == true },
            pressed: { [weak self] in self?.screenEdgePressed() },
            clicked: { [weak self] in self?.open() }))
    /// Files dragged onto the island (`NotchFileDrop`).
    private lazy var fileDrop: NotchFileDrop = NotchFileDrop(
        environment: .system(shelfAccept: { Self.collaborators.shelfAccept($0) }),
        island: NotchFileDrop.Island(
            canAccept: { [weak self] in self?.canAcceptFileDrop ?? false },
            acceptsUserInteraction: { [weak self] in self?.acceptsUserInteraction ?? false },
            mediaArea: { [weak self] in self?.mediaDropArea ?? .null },
            willChange: { [weak self] in self?.objectWillChange.send() },
            openFiles: { [weak self] in self?.open(.files, takeFocus: $0) },
            refreshPresentation: { [weak self] in self?.refreshPresentation() },
            landed: { [weak self] in self?.fileDropLanded() }))
    /// Movement over the capture selection (`installCaptureControlsClickThrough()`).
    private lazy var captureControlsWatch: NotchMovementWatch = NotchMovementWatch(
        environment: .system(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged],
                             inOtherApps: false),
        moved: { [weak self] in self?.updateCaptureControlsClickThrough() })
    /// Movement while the island hides until the pointer reaches it.
    private lazy var hiddenHoverWatch: NotchMovementWatch = NotchMovementWatch(
        environment: .system(matching: .mouseMoved), moved: { [weak self] in self?.hover(true) })
    /// Movement from an unreported exit until AppKit reports the pointer again.
    private lazy var hoverExitWatch: NotchMovementWatch = NotchMovementWatch(
        environment: .system(matching: [.mouseMoved, .leftMouseDragged]), moved: { [weak self] in self?.hover(false) })
    private var hoverWork: DispatchWorkItem?
    private var noticeWork: DispatchWorkItem?
    private var departureWork: DispatchWorkItem?
    private var musicDepartureWork: DispatchWorkItem?
    private var presentedMusic: NotchCompactMusicSnapshot?
    private var trackWork: DispatchWorkItem?
    /// A new song with no strip song to keep in its place stays out of the
    /// closed island until its notice, as scheduleTrackNotice() explains.
    private var awaitsTrackNotice = false
    private var powerSource: CFRunLoopSource?
    private var powerSampler: PowerSampler?
    private var captureID: UUID?
    private var captureFallback: (() -> Void)?
    private var captureClose: (() -> Void)?
    private var captureHover: ((Bool) -> Void)?
    private var captureClosesOnCollapse = false
    private var inside = false
    private var hoverEmphasized = false
    private var activitySelection = NotchActivitySelection()
    private var activityPickerMenuOpen = false
    private var hoverState = NotchHoverState()
    private var openedByHover = false
    /// A click inside the open island, which may be what brings another app forward.
    private var clickedSinceOpening = false
    /// Whether the open detail was reached from inside the island, so Escape
    /// steps back to its page as the Back button does. A detail the island
    /// opened on, from the menu bar for instance, has nothing behind it and
    /// closes like the menu panel.
    private var detailHasPage = false
    /// What a page shows over its own content, such as the mixer's options or
    /// the month grid, and how to close it; Escape closes it before the page.
    private var pageLayers: [NotchModule: () -> Void] = [:]
    private var trackingMenu = false
    private var fileInteractionActive = false
    /// A section's title follows the sections button unless the same action
    /// floats beside the island. Read with the floating buttons rather than on
    /// every layout pass, which would decode them each time.
    private var headerShowsSectionsButton = false
    private var keepsWorkingSurface: Bool {
        pinned || trackingMenu || NSApp.modalWindow != nil || panel?.attachedSheet != nil
            || NotchLyricsService.shared.isImporting
            // Like the lyrics chooser, these panels stand beside the island
            // instead of hanging from it; a click in them is not a click away.
            || (expanded && MediaPanelModal.panelModalActive)
            || (expanded && selected == .downloads && NotchDownloadService.shared.isChoosingFolder)
            || (expanded && selected == .scratchpad && ScratchpadService.shared.modalInteractionActive)
            || (expanded && !showingSections && selected == .calendar && Permissions.shared.keepsCalendarPrompt)
            || (expanded && !showingSections && selected == .files && fileInteractionActive)
            || CameraPreviewService.shared.keepsNotchPermissionPrompt
            || (expanded && !showingSections && selected == .captures && captureContent != nil)
            || (expanded && !showingSections && selected == .tools && (QuickLauncherService.shared.activeUtility != nil || QuickLauncherService.shared.isEditing))
    }
    private var running = false
    private var session = NotchSessionState()
    /// Sleep, display sleep, the console and the lock screen, reported into
    /// `session` through `updateSession`.
    private let sessionTracker = NotchSessionTracker()
    private var suspended: Bool { !session.canPresent }
    @Published package private(set) var hiddenInFullscreen = false {
        didSet {
            guard hiddenInFullscreen != oldValue else { return }
            NotificationCenter.default.post(name: Self.fullscreenVisibilityDidChange, object: self,
                                            userInfo: ["hidden": hiddenInFullscreen])
        }
    }
    private var settingsSignature = ""
    private var gesture = NotchGestureSupport()
    private var sectionScroll = NotchSectionScroll()
    private var volumeBaseline: Double?
    private var muteBaseline: Bool?
    private var volumeDeviceUID: String?
    /// System uptime until which an output change counts as the island's own.
    private var ownVolumeAdjustmentUntil: TimeInterval = 0
    private var notchNeedsMonitor = false
    /// Reads the room the menus leave beside the camera while the island
    /// wants it; `syncMenuSpaceMonitoring()` decides when.
    private lazy var menuSpace: NotchMenuSpaceReader = NotchMenuSpaceReader(
        subject: { [weak self] in
            guard let self else { return nil }
            return NotchMenuSpaceReader.Subject(
                geometry: self.geometry,
                primaryTop: NSScreen.screens.first?.frame.maxY ?? self.geometry.screen.maxY,
                ownWindow: self.panel?.windowNumber ?? -1)
        },
        apply: { [weak self] in self?.applyMenuSpace($0) })
    private var menuBarMeasurements = NotchMenuBarMeasurements()
    private var screenRefreshWork: DispatchWorkItem?
    private var preferenceSyncWork: DispatchWorkItem?
    /// The display the island is on. The pointer choice keeps it there until
    /// the island rests, so a preference sync never moves an open island.
    private var displayID: CGDirectDisplayID?
    private var followsPointer = false
    /// Every other display shows a copy of the closed island.
    private var showsOnAllDisplays = false
    /// A capsule names a song only for a moment as it starts.
    @Published package private(set) var capsuleMusicTitleShown = false
    private var musicTitleWork: DispatchWorkItem?
    private static let musicTitleDuration: TimeInterval = 4
    private typealias Mirrors = NotchMirrors<NotchWindowHost>
    /// The closed island as the other displays draw it (`NotchMirrors`).
    private lazy var mirrors: Mirrors = Mirrors(
        environment: Mirrors.Environment(
            displays: {
                NSScreen.screens.map { screen in
                    Mirrors.Display(id: screen.notchDisplayID,
                                    hasMenuBar: NSScreen.screensHaveSeparateSpaces || NSScreen.withMenuBar == screen)
                }
            },
            baseGeometry: { [weak self] id in
                guard let self, let screen = NSScreen.screens.first(where: { $0.notchDisplayID == id }) else { return nil }
                return self.baseGeometry(for: screen)
            },
            fullscreenDisplays: { ids in
                guard let topology = SpaceWindowBridge.topology() else { return [] }
                let separate = NSScreen.screensHaveSeparateSpaces
                return Set(ids.filter { topology.isFullscreen(on: $0, separateSpaces: separate) })
            },
            hidesUntilHover: { NotchSupport.hidesUntilHover() },
            coversMenus: { NotchSupport.coversMenus() },
            showsInCaptures: { NotchSupport.showsInCaptures() },
            outlineEnabled: { UserDefaults.standard.bool(forKey: DefaultsKey.notchOutlineEnabled) },
            hidesInFullscreen: { UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen) },
            openTitle: { FeatureStrings.notch(L10n.shared.language).open }),
        island: { [weak self] in
            guard let self, self.showsOnAllDisplays, self.running, !self.suspended, self.windowHost != nil else { return nil }
            return Mirrors.Island(displayID: self.displayID, activity: self.compactActivity,
                                  companion: self.compactCompanion, showsIdleContent: self.idleContent != .none)
        },
        stripSize: { [weak self] activity, companion, geometry in
            self?.capsuleStripSize(for: activity, companion: companion, geometry: geometry) ?? .zero
        },
        compactGeometry: { [weak self] activity, companion, base in
            self?.compactGeometry(for: activity, companion: companion, base: base) ?? base
        },
        makeHost: { [unowned self] model, geometry, size in
            let host = NotchWindowHost(content: ServiceViews.factory.notchMirror(self, mirror: model),
                                       geometry: geometry, size: size,
                                       background: { ServiceViews.factory.notchBackground($0) })
            host.panel.title = FeatureStrings.notch(L10n.shared.language).title
            return host
        },
        activate: { [weak self] id in self?.bringIsland(to: id) })
    /// The island following the pointer to another display (`NotchPointerFollower`).
    private lazy var pointerFollower: NotchPointerFollower = NotchPointerFollower(
        environment: .system,
        island: NotchPointerFollower.Island(
            isActive: { [weak self] in self.map { $0.running && !$0.suspended } ?? false },
            followsPointer: { [weak self] in self?.followsPointer ?? false },
            hasWindow: { [weak self] in self?.windowHost != nil },
            screenFrame: { [weak self] in self?.geometry.screen ?? .zero },
            canFollow: { [weak self] in self?.canFollowPointer ?? false },
            isConcealedForMissionControl: { [weak self] in self?.windowHost?.isConcealedForMissionControl != false },
            displayID: { [weak self] in self?.displayID },
            whenSettled: { [weak self] action in self?.windowHost?.whenSettled(action) },
            move: { [weak self] id in
                guard let self, let screen = NSScreen.screens.first(where: { $0.notchDisplayID == id }) else { return }
                self.move(to: screen)
            }))

    private init() {}

    private var hiddenUntilHover: Bool {
        !hiddenInFullscreen && UserDefaults.standard.bool(forKey: DefaultsKey.notchHideUntilHover)
            && UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover)
            && !expanded && !peeking && !dragPlaceholder && captureControls == nil
    }

    /// Full screen keeps a clickable black cutout until the user opens it.
    package var fullscreenCompact: Bool {
        hiddenInFullscreen && !expanded && !peeking
    }

    /// A simulated cutout covers no camera, so in full screen it stays out
    /// of the picture until a shortcut opens it.
    private var hiddenAtRestInFullscreen: Bool {
        fullscreenCompact && !geometry.isNotched
    }

    /// A Mac without a battery has no charge to show, so a saved battery
    /// choice rests empty there; playing music still shows as before.
    package var idleContent: NotchIdleContent {
        let content = NotchSupport.visibleIdleContent(isPlaying: !awaitsTrackNotice && NotchMusicService.shared.playback?.isPlaying == true)
        return content == .battery && !PowerSampler.hasInternalBattery ? .none : content
    }

    package var hasTimerActivity: Bool {
        NotchTimerSupport.isEnabled() && NotchTimerService.shared.session.hasSession
    }

    package var hasWatchActivity: Bool {
        NotchWatchSupport.isEnabled() && NotchWatchService.shared.isActive
    }

    package var hasDownloadActivity: Bool {
        NotchSupport.routes(.download)
            && NotchDownloadService.shared.items.contains { $0.active && !$0.completed }
    }

    package var hasMusicActivity: Bool {
        NotchSupport.showsMusicActivity(isPlaying: NotchMusicService.shared.playback?.isPlaying == true)
    }

    package var hasAgentActivity: Bool {
        NotchAgentSupport.showsLiveActivity() && !AgentUsageService.shared.snapshot.live.isEmpty
    }

    package var hasCalendarActivity: Bool {
        let calendar = NotchCalendarService.shared
        guard let countdown = calendar.countdown,
              countdown.ongoing ? NotchCalendarSupport.showsTimeLeft()
                : NotchCalendarSupport.showsCountdown(chosen: calendar.isChosen(countdown.event))
        else { return false }
        return countdown.isShown(at: Date())
    }

    package var hasKeepAwakeActivity: Bool {
        NotchKeepAwakeSupport.showsActivity() && KeepAwakeManager.shared.isActive
    }

    package var compactActivity: NotchCompactActivity? {
        // A new song waiting for its notice is not drawn yet.
        activitySelection.current(available: awaitsTrackNotice ? compactActivities.filter { $0 != .music } : compactActivities)
    }

    package var compactActivities: [NotchCompactActivity] {
        NotchSupport.compactActivities(timer: hasTimerActivity, watch: hasWatchActivity, downloads: hasDownloadActivity,
                                      agents: hasAgentActivity, calendar: hasCalendarActivity,
                                      music: hasMusicActivity, keepAwake: hasKeepAwakeActivity)
    }

    package var showsCompactActivityPicker: Bool {
        (inside || activityPickerMenuOpen) && !hiddenInFullscreen && !hiddenUntilHover && !expanded && !peeking
            && !dragPlaceholder && notice == nil && captureControls == nil
            && compactActivities.count > 1
    }

    package var compactActivityPickerLayout: NotchActivityPickerLayout {
        let activities = compactActivities
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let labelWidth = activities.map {
            ($0.title(L10n.shared.language) as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        let combinations = compactActivityCombinations
        let sizes = activities.map { compactStripSize(for: $0) }
            + combinations.map { compactStripSize(for: $0.primary, companion: $0.companion) }
        // Switching the chosen strip must not move the buttons under the pointer.
        let strip = CGSize(width: sizes.map(\.width).max() ?? geometry.cameraWidth,
                           height: sizes.map(\.height).max() ?? geometry.stripHeight)
        return NotchActivityPickerLayout(count: activities.count, labelWidth: labelWidth,
                                         stripSize: strip, screenWidth: geometry.screen.width,
                                         hasCombinations: !combinations.isEmpty)
    }

    package func selectCompactActivity(_ activity: NotchCompactActivity) {
        guard compactActivities.contains(activity) else { return }
        hoverWork?.cancel(); hoverWork = nil
        switchCompactSelection {
            activitySelection.select(activity, available: compactActivities)
        }
    }

    /// The picker keeps its size whatever is chosen, so the choice moves inside
    /// the surface, the highlight sliding and the strip changing in place,
    /// instead of the whole content fading through the host.
    private func switchCompactSelection(_ change: () -> Void) {
        let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil : .smooth(duration: 0.26)
        withAnimation(animation) {
            objectWillChange.send()
            change()
        }
        // A song chosen away is not music disappearing, which the host would
        // fade out through the whole picker as another activity takes its place.
        presentedMusic = nil
        refreshPresentation()
    }

    package func selectCompactCombination(_ combination: NotchActivityCombination) {
        let companions = compactCompanions(of: combination.primary)
        guard companions.contains(combination.companion) else { return }
        hoverWork?.cancel(); hoverWork = nil
        switchCompactSelection {
            activitySelection.select(combination.primary, companion: combination.companion,
                                     available: compactActivities, companions: companions)
        }
    }

    /// The pairs `primary` supports now.
    package func compactCompanions(of primary: NotchCompactActivity) -> [NotchCompactActivity] {
        NotchSupport.compactCompanions(of: primary, timer: hasTimerActivity,
                                       running: NotchTimerService.shared.session.isRunning,
                                       downloads: hasDownloadActivity, agents: hasAgentActivity,
                                       calendar: hasCalendarActivity, music: hasMusicActivity)
    }

    /// Every pair the picker offers, in the activities' own order.
    package var compactActivityCombinations: [NotchActivityCombination] {
        compactActivities.flatMap { primary in
            compactCompanions(of: primary).map { NotchActivityCombination(primary: primary, companion: $0) }
        }
    }

    /// A single activity never borrows another activity's wing implicitly.
    package var compactCompanion: NotchCompactActivity? {
        guard let activity = compactActivity, activity == activitySelection.preferred else { return nil }
        return activitySelection.companion(available: compactCompanions(of: activity))
    }

    private var compactActivityIsVisible: Bool {
        !fullscreenCompact && !expanded && !peeking && !dragPlaceholder && notice == nil && captureControls == nil
            && compactActivity != nil
    }

    private var compactMusicIsVisible: Bool { compactActivityIsVisible && compactActivity == .music }

    package var compactActivityGeometry: NotchGeometry {
        compactGeometry(for: compactActivity, companion: compactCompanion)
    }

    /// On the island's own display unless `base` is another display's.
    private func compactGeometry(for activity: NotchCompactActivity?, companion: NotchCompactActivity? = nil,
                                 base: NotchGeometry? = nil) -> NotchGeometry {
        var geometry = base ?? self.geometry
        if base == nil, showsCompactActivityPicker {
            let room = max(0, (geometry.screen.width - 24 - NotchActivityPickerLayout.horizontalInset * 2
                               - geometry.cameraWidth) / 2)
            geometry.compactSideRoom = min(geometry.compactSideRoom ?? 0, room)
        }
        switch activity {
        case .music: return geometry.compactMusicGeometry
        case .timer:
            return geometry.compactTimerGeometry(showsDownloads: companion == .downloads,
                                                 wing: timerStripWing(for: companion, in: geometry))
        case .downloads:
            let name = NotchDownloadService.shared.items.first { $0.active && !$0.completed }?.name
            return geometry.compactDownloadGeometry(wing: NotchDownloadSupport.compactWing(for: name, in: geometry))
        case .agents: return geometry.compactAgentGeometry(wing: agentStripWing(in: geometry))
        case .watch: return geometry.compactWatchGeometry(wing: watchStripWing(in: geometry))
        case .calendar:
            return geometry.compactCalendarGeometry(wing: calendarStripWing(for: companion, in: geometry),
                                                    paired: companion != nil)
        // Its reading is a countdown like the timer's, so it takes the timer's wings.
        case .keepAwake: return geometry.compactTimerGeometry(showsDownloads: false, wing: keepAwakeStripWing(in: geometry))
        default: return geometry
        }
    }

    /// The wider side: the eye at the left end, or the reading, or the
    /// area's own picture when it has no text, with air beside the camera.
    private func watchStripWing(in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactWatchGeometry(wing: NotchWatchSupport.stripWingRange.lowerBound)
        let watch = NotchWatchService.shared
        let size = NotchTimerSupport.stripTextSize(height: provisional.compactActivityContentHeight)
        let reading = watch.showsThumbnail ? NotchWatchSupport.thumbnailWidth
            : (watch.headline as NSString).size(withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            ]).width.rounded(.up)
        let inset = provisional.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        return reading + inset + NotchTimerSupport.stripCameraGap
    }

    private func keepAwakeStripWing(in geometry: NotchGeometry) -> CGFloat {
        NotchKeepAwakeSupport.stripWing(until: KeepAwakeManager.shared.endDate, now: Date(),
                                        locale: Locale(identifier: L10n.shared.language.rawValue), in: geometry)
    }

    /// The wider of the two sides, measured with the strip's fonts and its
    /// clearance from the curve: alone, the event's title or its clock and
    /// the time beside it; paired, the event's dot and clock or the mark of
    /// what shares the island, with air beside the camera.
    private func calendarStripWing(for companion: NotchCompactActivity?, in geometry: NotchGeometry) -> CGFloat {
        guard let countdown = NotchCalendarService.shared.countdown else {
            return NotchGeometry.calendarWingRange.upperBound
        }
        // Measured at the narrowest wing the strip may take.
        let provisional = geometry.compactCalendarGeometry(wing: 0, paired: companion != nil)
        let inset = provisional.compactActivityEdgeInset(boxHeight: 9, radius: 0)
        if let companion {
            let sides = max(inset + calendarClockWidth, companionMarkWidth(companion, in: provisional))
                + NotchTimerSupport.stripCameraGap
            // A download keeps room for its percentage, as beside a timer.
            return companion == .downloads ? max(80, sides) : sides
        }
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        }
        let language = L10n.shared.language
        let trimmed = countdown.event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? FeatureStrings.notchCalendar(language).untitled : trimmed
        let titleSide = NotchCalendarSupport.stripDotWidth + NotchCalendarSupport.stripTitleSpacing
            + width(title, .systemFont(ofSize: 11, weight: .semibold))
        // The widest clock the hour can show, so the island keeps its size
        // while the minutes count down.
        let clockSide = width("00:00", .monospacedDigitSystemFont(ofSize: 13, weight: .medium))
            + NotchCalendarSupport.stripClockSpacing
            + width(NotchCalendarSupport.timeText(countdown, locale: language.formattingLocale()),
                    .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        return inset + max(titleSide, clockSide)
    }

    /// The wider of the two sides, the timer's reading or what shares the
    /// island with it, drawn as the strip draws them, with the clearance
    /// from the silhouette's curve and air beside the camera.
    private func timerStripWing(for companion: NotchCompactActivity?, in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactTimerGeometry(showsDownloads: false,
                                                        wing: NotchTimerSupport.stripWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let timer = NotchTimerService.shared
        let size = NotchTimerSupport.stripTextSize(height: height)
        let text = NotchTimerSupport.compactText(for: timer.session, at: timer.now,
                                                 locale: Locale(identifier: L10n.shared.language.rawValue))
        let reading = (NotchAgentSupport.readingShape(text) as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        ]).width.rounded(.up) + provisional.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        return max(reading, companionMarkWidth(companion, in: provisional)) + NotchTimerSupport.stripCameraGap
    }

    /// The width of the mark at a strip's left end, the timer's own without a
    /// companion, drawn as `NotchCompanionMark` draws it, with its clearance
    /// from the silhouette's curve.
    private func companionMarkWidth(_ companion: NotchCompactActivity?, in provisional: NotchGeometry) -> CGFloat {
        let height = provisional.compactActivityContentHeight
        switch companion {
        case .music:
            return provisional.compactMusicArtworkSide + provisional.compactMusicArtworkInset
        case .agents:
            let working = Set(AgentUsageService.shared.snapshot.live.map(\.provider)).count
            return NotchAgentSupport.stripMarksWidth(working: working, in: provisional)
        case .calendar:
            return provisional.compactActivityEdgeInset(boxHeight: 9, radius: 0) + calendarClockWidth
        default:
            // Every mark the strip shows is about a square of its point size.
            let side = NotchTimerSupport.stripIconSize(height: height)
            return side + provisional.compactActivityEdgeInset(boxHeight: side, radius: side / 2)
        }
    }

    /// An event's dot and the widest clock its hour can show, so the island
    /// keeps its size while the minutes count down.
    private var calendarClockWidth: CGFloat {
        NotchCalendarSupport.stripDotWidth + NotchCalendarSupport.stripClockSpacing
            + ("00:00" as NSString).size(withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            ]).width.rounded(.up)
    }

    /// The wider of the two sides, the reading or the working agents' marks,
    /// with the clearance from the silhouette's curve that the strip keeps
    /// and air beside the camera.
    private func agentStripWing(in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactAgentGeometry(wing: NotchAgentSupport.stripWingRange.lowerBound)
        let size = NotchAgentSupport.stripTextSize(height: provisional.compactActivityContentHeight)
        let shape = NotchAgentSupport.readingShape(NotchAgentSupport.stripReading(
            AgentUsageService.shared.snapshot, readout: NotchAgentSupport.readout(),
            display: NotchAgentSupport.limitDisplay(), focus: NotchAgentSupport.limitFocus(), now: Date()))
        let width = (shape as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        ]).width
        let reading = width.rounded(.up) + provisional.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        // The marks on the other side, drawn as the strip draws them.
        let working = Set(AgentUsageService.shared.snapshot.live.map(\.provider)).count
        let marks = NotchAgentSupport.stripMarksWidth(working: working, in: provisional)
        return max(reading, marks) + NotchAgentSupport.stripCameraGap
    }

    package var expandedSize: CGSize {
        if showingSections {
            return geometry.sectionPickerSize(count: filteredSections.count)
        }
        let musicExtras = NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
        let launcher = QuickLauncherService.shared
        return pageSize(in: expandedGeometry, module: showingAppPanel ? .tools : selected,
                        detail: selectedMetric != nil, panel: showingAppPanel,
                        detailHeight: selectedMetric == .fan ? fanDetailHeight : nil,
                        musicExtraHeight: musicExtras && musicDetailVisible ? geometry.musicExtrasHeight : 0,
                        fileMediaHeight: !choosingFileDropDestination && AppFeature.mediaTools.isAvailable
                            && NotchFileToolsService.shared.mediaPresented ? NotchFileToolsService.shared.mediaContentHeight : nil,
                        toolCount: launcher.isEditing || launcher.activeUtility != nil ? nil : launcher.visibleItems.count,
                        capturePreviewHeight: captureContent == nil ? nil : captureContentHeight)
    }

    /// The open island as Settings previews a section: at rest, with no
    /// detail, app panel, capture or media editor in front of the page.
    package func previewSize(for module: NotchModule) -> CGSize {
        pageSize(in: previewGeometry(for: module), module: module, detail: false, panel: false, detailHeight: nil, musicExtraHeight: 0,
                 fileMediaHeight: nil, toolCount: QuickLauncherService.shared.visibleItems.count, capturePreviewHeight: nil)
    }

    /// The island around a previewed section, whose title sits beside the
    /// camera only where the island's would.
    package func previewGeometry(for module: NotchModule) -> NotchGeometry {
        previewGeometry(for: module, sectionsButton: previewShowsSectionsButton)
    }

    private func previewGeometry(for module: NotchModule, sectionsButton: Bool) -> NotchGeometry {
        var result = geometry
        result.headerTitleWidth = NotchLayout.headerTitleWidth(module.title(L10n.shared.language), button: sectionsButton)
        return result
    }

    /// Settings previews the island while it is off too, when the floating
    /// buttons are not read for it, so a preview reads them as it draws.
    private var previewShowsSectionsButton: Bool {
        !NotchQuickAccessConfiguration.current().actions.contains(.explore)
    }

    /// The tallest island a preview can show: a page that fills the budget,
    /// below the row the widest title may need.
    package var previewLargestSize: CGSize {
        let sectionsButton = previewShowsSectionsButton
        var tallest = geometry
        tallest.headerTitleWidth = NotchModule.allCases
            .map { previewGeometry(for: $0, sectionsButton: sectionsButton).headerTitleWidth }.max() ?? 0
        return tallest.expandedSize(module: .calendar)
    }

    private func pageSize(in geometry: NotchGeometry, module: NotchModule, detail: Bool, panel: Bool,
                          detailHeight: CGFloat?, musicExtraHeight: CGFloat, fileMediaHeight: CGFloat?, toolCount: Int?,
                          capturePreviewHeight: CGFloat?) -> CGSize {
        let controls = NotchSupport.controls()
        let sliders = controls.filter { $0 == .volume || $0 == .brightness }.count
        let shortcuts = controls.filter { $0 != .volume && $0 != .brightness && $0 != .music }.count
        let musicExtras = NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
        return geometry.expandedSize(module: module, detail: detail, panel: panel, detailHeight: detailHeight,
                                     shortcutCount: shortcuts,
                                     sliderCount: sliders, controlsHaveMusic: controls.contains(.music), musicHasContent: NotchMusicService.shared.playback != nil,
                                     musicHasControlsRow: AppFeature.mixer.isAvailable || musicExtras,
                                     musicExtraHeight: musicExtraHeight, fileMediaHeight: fileMediaHeight,
                                     systemCards: NotchSupport.systemCardCount(hasBattery: PowerSampler.hasInternalBattery,
                                                                               fans: SystemMonitor.shared.snapshot.fanSpeeds.count),
                                     toolCount: toolCount, capturePreviewHeight: capturePreviewHeight,
                                     timerHasSession: NotchTimerService.shared.session.hasSession,
                                     timerMode: NotchTimerService.shared.session.hasSession
                                        ? NotchTimerService.shared.session.mode : NotchTimerSupport.savedMode(),
                                     agentsHeight: module == .agents && !detail && !panel
                                        ? agentsContentHeight(width: geometry.contentWidth) : nil)
    }

    /// The AI page is as tall as the cards it shows; nil while the logs are
    /// first read, when the page fills the island with its progress.
    private func agentsContentHeight(width: CGFloat) -> CGFloat? {
        let usage = AgentUsageService.shared.snapshot
        guard usage.loaded else { return nil }
        let providers = NotchAgentSupport.providers().filter(usage.seen.contains)
        guard !providers.isEmpty else { return 0 }
        return NotchAgentSupport.contentHeight(NotchAgentSupport.rows(
            NotchAgentSupport.tiles(cards: NotchAgentSupport.cards(), providers: providers), width: width))
    }
    package var expandedGeometry: NotchGeometry {
        var result = geometry
        // Capture editing has a full toolbar whose actions must stay reachable.
        result.requiresFullWidthHeader = selected == .captures && captureActions != nil
            && !showingSections && !showingAppPanel && selectedMetric == nil
        result.headerTitleWidth = headerTitleWidth
        return result
    }
    /// The open header's title and the button before it, as the header draws
    /// them. Choosing a section shows only its search beside the camera, which
    /// takes the room its side leaves.
    private var headerTitleWidth: CGFloat {
        guard !showingSections else { return 0 }
        let detail = showingAppPanel || selectedMetric != nil
        guard detail || modules.isEmpty else {
            return NotchLayout.headerTitleWidth(selected.title(L10n.shared.language), button: headerShowsSectionsButton)
        }
        return NotchLayout.headerTitleWidth(detailTitle, font: NotchLayout.detailTitleFont, button: detail)
    }
    /// A detail's title, the app panel's, or the island's own with no sections.
    package var detailTitle: String {
        if showingAppPanel { return "Vitruvian" }
        let language = L10n.shared.language
        guard let metric = selectedMetric else { return FeatureStrings.notch(language).title }
        // The fan card opens Fan Control, so its page shares that title.
        return metric == .fan ? FeatureStrings.fanControl(language).title : metric.title(L10n.shared.s)
    }
    package var contentSize: CGSize { expandedGeometry.contentSize(for: expandedSize) }
    package var usesGlassSurface: Bool {
        expanded || peeking || dragPlaceholder || noticeExpanded
            || (captureControls != nil && !captureControlsCollapsed)
    }

    /// The open capture controls, measured with their title's font.
    package var captureControlsLayout: NotchCaptureControlsLayout {
        NotchCaptureControlsLayout(
            geometry: geometry,
            titleWidth: NotchCaptureControlsLayout.titleWidth(FeatureStrings.screenshot(L10n.shared.language).screenCaptureTitle),
            capturesAudio: captureControls?.selectedTool.capturesAudio == true)
    }

    package var surfaceSize: CGSize {
        if let capsule = capsuleSurfaceSize { return capsule }
        if fullscreenCompact { return geometry.bareCutout }
        if captureControls != nil {
            if captureControlsCollapsed {
                return CGSize(width: geometry.cameraWidth + 56, height: geometry.stripHeight)
            }
            return captureControlsLayout.size
        }
        if expanded { return expandedSize }
        if dragPlaceholder { return CGSize(width: geometry.peek.width, height: geometry.safeContentTop + 66) }
        if let notice {
            guard noticeExpanded else { return geometry.noticeSize(wingWidth: notice.preferredWingWidth) }
            return geometry.notificationPreviewSize(
                contentHeight: notice.previewContentHeight(width: geometry.notificationPreviewContentWidth))
        }
        if peeking { return geometry.peek }
        if showsCompactActivityPicker { return compactActivityPickerLayout.size }
        if compactActivity != nil {
            let resting = compactActivityGeometry.compactActivitySize
            return hoverEmphasized ? NotchHoverEmphasis.size(from: resting, geometry: geometry) : resting
        }
        let resting = geometry.restingSize(showsContent: idleContent != .none)
        return hoverEmphasized ? NotchHoverEmphasis.size(from: resting, geometry: geometry) : resting
    }

    /// A floating capsule's closed strips run from one round end to the
    /// other and are as wide as what they show. Open, peeking or choosing an
    /// activity, it takes the island's own sizes. Nil when the island hangs.
    private var capsuleSurfaceSize: CGSize? {
        guard geometry.floats, !fullscreenCompact, !expanded, !dragPlaceholder else { return nil }
        if captureControls != nil { return captureControlsCollapsed ? NotchCapsuleLayout.captureSurface(geometry: geometry) : nil }
        if let notice { return noticeExpanded ? nil : capsuleNoticeSize(notice) }
        if peeking || showsCompactActivityPicker { return nil }
        // At rest the charge or the allowance fits inside the bare capsule.
        let resting = compactActivity.map { capsuleStripSize(for: $0, companion: compactCompanion) }
            ?? geometry.restingSize(showsContent: false)
        return hoverEmphasized ? NotchHoverEmphasis.size(from: resting, geometry: geometry) : resting
    }

    /// The last banner's capsule. A banner replacing it keeps at least its
    /// width, so a burst of messages does not resize the island with each one.
    private var bannerCapsuleWidth: CGFloat = 0

    private func capsuleNoticeSize(_ notice: NotchNotice) -> CGSize {
        var size = capsuleNoticeSurface(notice)
        guard notice.notification != nil else { return size }
        if notice.minimumWingWidth > 0 { size.width = max(size.width, bannerCapsuleWidth) }
        bannerCapsuleWidth = size.width
        return size
    }

    /// A notice's own capsule, which it keeps while the island closes around it.
    package func capsuleNoticeSurface(_ notice: NotchNotice) -> CGSize {
        let layout = NotchCapsuleLayout.self
        guard let content = notice.notification else {
            return layout.surface(content: layout.noticeContent(title: notice.title, detail: notice.detail,
                                                                level: notice.level != nil),
                                  maximum: layout.Maximum.notice, geometry: geometry)
        }
        return layout.surface(content: layout.notificationContent(title: content.compactTitle, message: content.compactDetail,
                                                                 geometry: geometry),
                              maximum: layout.Maximum.notification, geometry: geometry)
    }

    /// The closed strip an activity takes on its own: a capsule as wide as
    /// what it shows, or the hanging strip around the camera.
    package func compactStripSize(for activity: NotchCompactActivity, companion: NotchCompactActivity? = nil) -> CGSize {
        geometry.floats ? capsuleStripSize(for: activity, companion: companion)
            : compactGeometry(for: activity, companion: companion).compactActivitySize
    }

    /// Measured from what the capsule's views show, with their own measures,
    /// on the island's display unless `geometry` is another display's.
    private func capsuleStripSize(for activity: NotchCompactActivity, companion: NotchCompactActivity?,
                                  geometry: NotchGeometry? = nil) -> CGSize {
        let geometry = geometry ?? self.geometry
        let layout = NotchCapsuleLayout.self
        let language = L10n.shared.language
        let download = NotchDownloadService.shared.items.first { $0.active && !$0.completed }
        let working = Set(AgentUsageService.shared.snapshot.live.map(\.provider)).count
        switch activity {
        case .music:
            let playback = heldMusic?.playback ?? NotchMusicService.shared.playback
            return layout.musicSurface(title: capsuleMusicTitleShown
                                        ? playback?.track.title ?? FeatureStrings.radialMenu(language).mediaNowPlaying : nil,
                                       geometry: geometry)
        case .timer:
            let timer = NotchTimerService.shared
            return layout.timerSurface(reading: NotchTimerSupport.compactText(for: timer.session, at: timer.now,
                                                                              locale: Locale(identifier: language.rawValue)),
                                       companion: companion, workingAgents: working,
                                       downloadPercent: download?.fraction != nil, geometry: geometry, language: language)
        case .downloads:
            return layout.downloadSurface(name: download?.name ?? FeatureStrings.notchFiles(language).downloadsTitle,
                                          hasProgress: download?.fraction != nil, geometry: geometry, language: language)
        case .agents:
            let reading = NotchAgentSupport.stripReading(AgentUsageService.shared.snapshot, readout: NotchAgentSupport.readout(),
                                                         display: NotchAgentSupport.limitDisplay(),
                                                         focus: NotchAgentSupport.limitFocus(), now: Date())
            return layout.agentSurface(reading: reading, working: working, geometry: geometry)
        case .calendar:
            guard let countdown = NotchCalendarService.shared.countdown else { return geometry.restingSize(showsContent: false) }
            if let companion {
                return layout.calendarPairSurface(companion: companion, workingAgents: working,
                                                  downloadPercent: download?.fraction != nil, geometry: geometry,
                                                  language: language)
            }
            return layout.calendarSurface(title: layout.calendarTitle(countdown, language: language),
                                          time: NotchCalendarSupport.timeText(countdown, locale: language.formattingLocale()),
                                          geometry: geometry)
        case .watch:
            let watch = NotchWatchService.shared
            return layout.watchSurface(reading: watch.headline, thumbnail: watch.showsThumbnail, geometry: geometry)
        case .keepAwake:
            let reading = KeepAwakeManager.shared.endDate.map {
                NotchKeepAwakeSupport.compactText(until: $0, now: Date(), locale: Locale(identifier: language.rawValue))
            }
            return layout.keepAwakeSurface(reading: reading, geometry: geometry)
        }
    }

    package var presentationWindow: NSPanel? { panel }
    /// User actions can open the island even when automatic full-screen feedback is hidden.
    package var acceptsUserInteraction: Bool {
        running && !suspended && panel != nil
            && windowHost?.isConcealedForMissionControl != true
    }
    package var acceptsSystemFeedback: Bool {
        acceptsUserInteraction && !hiddenInFullscreen
    }
    package var showsSystemFeedback: Bool {
        acceptsSystemFeedback && !hiddenUntilHover
    }

    package var protectedWindowIDs: Set<CGWindowID> {
        NotchSupport.showsInCaptures() ? [] : islandWindowIDs
    }

    package var captureVisibleWindowIDs: Set<CGWindowID> {
        NotchSupport.showsInCaptures() ? islandWindowIDs : []
    }

    /// The island's window and its copies on other displays, as shown.
    private var islandWindowIDs: Set<CGWindowID> {
        var ids = Set(mirrors.visibleWindowIDs)
        if let panel, panel.isVisible, panel.windowNumber > 0 { ids.insert(CGWindowID(panel.windowNumber)) }
        return ids
    }

    /// While a capture is choosing an area on screen, the notch is part of the
    /// capture interface, so its window is kept out of the pixels no matter
    /// what the everyday "show in captures" preference says. This lets people
    /// grab whatever sits behind the notch cleanly.
    package var captureChromeWindowIDs: Set<CGWindowID> {
        running ? islandWindowIDs : []
    }

    package func syncWithPreferences() {
        preferenceSyncWork?.cancel(); preferenceSyncWork = nil
        guard NotchSupport.isEnabled() else { stop(); return }
        if !running {
            running = true
            installObservers()
        }
        if !NotchTimerSupport.isEnabled() { NotchTimerService.shared.stop() }
        // A watch keeps reading while the island is away, as on the lock
        // screen, and says so with a notification if it cannot show itself.
        NotchWatchService.shared.syncWithPreferences()
        // Requested file work can continue while locked, but disabling its
        // feature must still cancel it before presentation resumes.
        NotchFileToolsService.shared.syncWithPreferences()
        if !NotchFileToolsService.shared.offersMediaDrop { endFileDrop() }
        // Paused while the island is away, the section still stops at once
        // when it is turned off.
        if !NotchAgentSupport.isEnabled() { AgentUsageService.shared.stop() }
        guard !suspended else {
            if session.canRunTimer { NotchTimerService.shared.syncWithPreferences() }
            else { NotchTimerService.shared.suspend() }
            NotchLockScreenService.shared.sync(session)
            return
        }
        // Checked before any service starts, so each preference change while
        // the lid is closed does not start and stop them all again.
        guard screenIndex(in: NSScreen.screens) != nil else { withdrawFromMissingScreen(); return }
        refreshModules()
        NotchDownloadService.shared.syncWithPreferences()
        NotchCalendarService.shared.syncWithPreferences()
        NotchNotificationService.shared.syncWithPreferences()
        MainActor.assumeIsolated { NotchAudioLevelService.shared.syncWithPreferences() }
        AgentUsageService.shared.syncWithPreferences()
        followsPointer = displayPreference == .pointer || displayPreference == .all
        showsOnAllDisplays = displayPreference == .all
        updateFullscreenDisplays()
        updateScreen()
        syncPointerFollowing()
        syncGestures()
        NotchTimerService.shared.syncWithPreferences()
        NotchAccessoryService.shared.syncWithPreferences()
        let signature = NotchEvent.allCases.map { String(NotchSupport.routes($0)) }.joined()
            + NotchSupport.idleContent().rawValue + String(NotchSupport.watchesMusicActivity())
            + String(NotchKeepAwakeSupport.showsActivity())
            + modules.map(\.rawValue).joined()
            + String(AppFeature.fanControl.isAvailable)
            + String(NotchSupport.routesShelf()) + String(NotchSupport.revealsShelfDrag())
            + String(NotchSupport.routesCaptureControls())
        if signature != settingsSignature {
            settingsSignature = signature
            bindEvents()
            Self.collaborators.fileRoutingDidChange()
        }
        if !NotchSupport.routes(.capture), captureContent != nil {
            let fallback = captureFallback
            clearCapture()
            fallback?()
        }
        if captureControls != nil, !NotchSupport.routesCaptureControls() { cancelCaptureControls() }
        syncNoticeWithPreferences()
        syncVisibleConsumers()
        refreshPresentation(animated: false)
        // Pages read their preferences as they draw, and a change that keeps
        // the island's size publishes nothing else: hiding a control left the
        // open island, and the preview in Settings, as they were.
        objectWillChange.send()
        Self.collaborators.feedbackRoutingDidChange()
    }

    private func refreshModules() {
        let updated = NotchSupport.modules()
        if modules != updated { modules = updated }
        let selection = modules.contains(selected) ? selected : modules.first ?? .controls
        if selected != selection { selected = selection }
        if let selectedMetric, !metricIsAvailable(selectedMetric) { self.selectedMetric = nil }
    }

    private func metricIsAvailable(_ metric: MetricDetailKind) -> Bool {
        MenuBarMetric.allCases.contains { $0.detailKind == metric && $0.feature.isAvailable }
    }

    package func stop(restoreCapture: Bool = true) {
        preferenceSyncWork?.cancel(); preferenceSyncWork = nil
        NotchLyricsService.shared.stop()
        NotchFileToolsService.shared.stop()
        AgentUsageService.shared.stop()
        guard running else { return }
        running = false
        NotchTimerService.shared.stop()
        NotchAccessoryService.shared.stop()
        NotchWatchService.shared.stop()
        let cancelCapture = captureControlsCancel
        endCaptureControls()
        cancelCapture?()
        let fallback = restoreCapture ? captureFallback : captureClose
        clearCapture()
        tearDownPresentation()
        NotchLockScreenService.shared.close()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        sessionTracker.stop()
        session = NotchSessionState()
        Self.collaborators.feedbackRoutingDidChange()
        Self.collaborators.fileRoutingDidChange()
        fallback?()
    }

    private func tearDownPresentation() {
        screenRefreshWork?.cancel(); screenRefreshWork = nil
        captureControlsWork?.cancel(); captureControlsWork = nil
        musicDetailVisible = false
        pageLayers.removeAll()
        panel?.handleScroll = nil
        gesture = NotchGestureSupport()
        sectionScroll = NotchSectionScroll()
        menuSpace.stop()
        geometry.compactSideRoom = nil
        hoverWork?.cancel(); hoverWork = nil
        noticeWork?.cancel(); noticeWork = nil
        endDeparture()
        finishMusicDeparture()
        presentedMusic = nil
        trackWork?.cancel(); trackWork = nil
        heldMusic = nil
        awaitsTrackNotice = false
        subscriptions.removeAll()
        stopPower()
        NotchMusicService.shared.stop()
        MainActor.assumeIsolated { NotchAudioLevelService.shared.stop() }
        CameraPreviewService.shared.hideEmbedded()
        NotchAccessoryService.shared.suspend()
        NotchDownloadService.shared.stop()
        NotchCalendarService.shared.stop()
        NotchNotificationService.shared.stop()
        AgentUsageService.shared.pause()
        settingsSignature = ""
        expanded = false
        peeking = false
        dragPlaceholder = false
        endFileDrop()
        fileInteractionActive = false
        heldDrag = false
        selectedMetric = nil
        pinned = false
        notice = nil
        noticeExpanded = false
        showingAppPanel = false
        showingSections = false
        sectionQuery = ""
        highlightedSection = nil
        sectionRow = 0
        inside = false
        hoverEmphasized = false
        activitySelection = NotchActivitySelection()
        activityPickerMenuOpen = false
        hoverState = NotchHoverState()
        openedByHover = false
        removeEventMonitors()
        removeScreenEdgeClickMonitors()
        removeCaptureControlsClickThrough()
        removeHiddenHoverMonitors()
        removeHoverExitMonitors()
        removePointerMonitors()
        releaseMonitor()
        musicTitleWork?.cancel(); musicTitleWork = nil
        capsuleMusicTitleShown = false
        closeMirrors()
        windowHost?.close()
        windowHost = nil
        // Shown again, an island that follows the pointer starts on its display.
        displayID = nil
        syncPanelKey()
        hiddenInFullscreen = false
    }

    /// Opening without a page shows what the closed island is already
    /// presenting: a mirrored banner, or an activity unless the user turned
    /// that off. Otherwise the reopening preference decides.
    package var reopeningDestination: (module: NotchModule, appPanel: Bool, sections: Bool) {
        if !expanded {
            let opensActivity = UserDefaults.standard.object(forKey: DefaultsKey.notchOpensActivity) as? Bool ?? true
            let activity = notice?.notificationID != nil ? NotchModule.notifications
                : opensActivity ? compactActivity?.module : nil
            if let activity, modules.contains(activity) { return (activity, false, false) }
            if UserDefaults.standard.bool(forKey: DefaultsKey.notchReturnHome) {
                let saved = UserDefaults.standard.string(forKey: DefaultsKey.notchHomeModule) ?? ""
                switch NotchReopeningDestination(rawValue: saved) {
                case .appPanel: return (modules.contains(.controls) ? .controls : modules.first ?? .controls, true, false)
                case .explore: return (selected, false, true)
                case nil:
                    let home = NotchModule(rawValue: saved) ?? .controls
                    return (modules.contains(home) ? home : modules.first ?? .controls, false, false)
                }
            }
        }
        return (selected, false, false)
    }

    package var reopeningModule: NotchModule {
        reopeningDestination.module
    }

    /// A compact strip opens its activity's page, as opening the island does:
    /// unless the user turned off opening the visible activity, in which case
    /// the reopening choice decides here too.
    package func openActivity(_ module: NotchModule) {
        let opensActivity = UserDefaults.standard.object(forKey: DefaultsKey.notchOpensActivity) as? Bool ?? true
        if opensActivity { open(module) } else { open() }
    }

    package func open(_ module: NotchModule? = nil, pinned: Bool = false, takeFocus: Bool = true,
              appPanel: Bool = false, metric: MetricDetailKind? = nil, feedback: Bool = true, sections: Bool = false) {
        guard NotchSupport.isEnabled(), !suspended else { return }
        if !running || self.panel == nil { syncWithPreferences() }
        else { refreshModules() }
        guard let panel else { return }
        let reopening = reopeningDestination
        let useReopeningSurface = module == nil && !expanded && !appPanel && !sections && metric == nil
        let destination = module.flatMap { modules.contains($0) ? $0 : nil } ?? reopening.module
        let appPanel = appPanel || (useReopeningSurface && reopening.appPanel)
        let sections = sections || (useReopeningSurface && reopening.sections)
        if useReopeningSurface && reopening.appPanel { MainActor.assumeIsolated { MenuPanelFocus.shared.showNormalPanel() } }
        if useReopeningSurface && reopening.sections {
            sectionQuery = ""
            sectionRow = 0
            highlightedSection = destination
        }
        let metric = metric.flatMap { metricIsAvailable($0) ? $0 : nil }
        let changesPresentation = !expanded || selected != destination
            || showingAppPanel != appPanel || selectedMetric != metric || showingSections != sections
        if changesPresentation, destination == .tools, !appPanel, !sections, metric == nil {
            QuickLauncherService.shared.prepareForPresentation()
        }
        MainActor.assumeIsolated { appShell()?.closePopover(preservingNotch: true) }
        if !expanded, modules.contains(.clipboard) { ClipboardHistoryService.shared.rememberPasteTarget() }
        panel.acceptsKeyFocus = true
        hoverState.open()
        hoverWork?.cancel()
        // Entering a detail decides what lies behind it; switching details or
        // passing through the gallery keeps that answer.
        if !expanded { detailHasPage = false }
        else if appPanel || metric != nil, !showingAppPanel, selectedMetric == nil { detailHasPage = true }
        // Following the closed island ends the moment it opens, before a page
        // or a capture preview under the pointer can be told the pointer left.
        // An open page is followed again only from an exit report.
        if !expanded { removeHoverExitMonitors() }
        mutatePresentation(transitionContent: changesPresentation ? (expanded ? .replace : .reveal) : .none) {
            showingAppPanel = appPanel
            showingSections = sections
            if selected != destination { selected = destination }
            if pinned { self.pinned = true }
            selectedMetric = metric
            peeking = false
            openedByHover = !takeFocus
            expanded = true
            // The open island covers a mirrored banner, and the inbox keeps
            // the message; a held one must not reappear after collapsing.
            if notice?.notificationID != nil { noticeWork?.cancel(); noticeWork = nil; notice = nil; noticeExpanded = false }
        }
        inside = windowHost?.containsHover(NSEvent.mouseLocation) == true
        installEventMonitors()
        syncVisibleConsumers()
        if takeFocus { panel.makeKey() }
        if feedback, changesPresentation { provideHapticFeedback() }
    }

    package func collapse() {
        guard captureControls == nil, !heldDrag else { return }
        let closeCapture = detachCaptureIfClosingOnCollapse()
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        pinned = false
        hoverWork?.cancel(); hoverWork = nil
        if noticeExpanded { noticeWork?.cancel(); noticeWork = nil }
        mutatePresentation(transitionContent: expanded || peeking || noticeExpanded ? .dismiss : .none) {
            if noticeExpanded { notice = nil; noticeExpanded = false }
            expanded = false
            openedByHover = false
            peeking = false
            selectedMetric = nil
            showingAppPanel = false
            showingSections = false
            sectionQuery = ""
            highlightedSection = nil
            sectionRow = 0
        }
        panel?.acceptsKeyFocus = false
        panel?.resignKey()
        removeEventMonitors()
        syncVisibleConsumers()
        closeCapture?()
    }

    package func toggle() { expanded ? collapse() : open() }

    package func setMusicDetailsVisible(_ visible: Bool) {
        guard visible != musicDetailVisible else { return }
        mutatePresentation { musicDetailVisible = visible }
    }

    @discardableResult
    package func showClipboard(toggle: Bool = false) -> Bool {
        guard acceptsUserInteraction, NotchSupport.routesClipboardWindow() else { return false }
        if toggle, expanded, selected == .clipboard, !showingAppPanel, !showingSections { collapse() }
        else { open(.clipboard) }
        return true
    }

    package func hover(_ entered: Bool) {
        guard running, !suspended, !hiddenAtRestInFullscreen else { removeHoverExitMonitors(); return }
        let point = NSEvent.mouseLocation
        let wasInside = inside
        let showedPicker = showsCompactActivityPicker
        inside = hiddenUntilHover ? geometry.contains(point, in: geometry.collapsed)
            && windowHost?.isConcealedForMissionControl == false
            : windowHost?.containsHover(point) == true || pointerOverChildWindow(point)
        hoverState.update(pointerInside: inside)
        let emphasize = inside && !hiddenInFullscreen && !hiddenUntilHover && !expanded && !peeking && !dragPlaceholder
            && notice == nil && captureControls == nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if hoverEmphasized != emphasize || showedPicker != showsCompactActivityPicker {
            hoverEmphasized = emphasize
            refreshPresentation()
        }
        syncHoverExitMonitoring(entered: entered, point: point)
        captureHover?(entered)
        if captureControls != nil {
            updateCaptureControlsHover(wasInside: wasInside)
            return
        }
        guard !pinned, !heldDrag, !keepsWorkingSurface else {
            hoverWork?.cancel(); hoverWork = nil
            // A dialog or menu keeps the island, not a banner the pointer left.
            if !inside { releaseNotification() }
            return
        }
        // Overlapping tracking areas can report the same presence repeatedly.
        // Keep the first deadline until the pointer actually crosses the boundary.
        if inside == wasInside, let hoverWork, !hoverWork.isCancelled { return }
        hoverWork?.cancel(); hoverWork = nil
        // The visible choices replace automatic opening while several
        // activities compete. Clicking the strip still opens its full page.
        if showsCompactActivityPicker { return }
        if inside {
            if holdsNotification, let id = notice?.notificationID { holdNotification(id); return }
            guard !hoverState.suppressed, (notice == nil || hiddenUntilHover), !expanded, !peeking, !dragPlaceholder,
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
            if !hiddenInFullscreen, compactActivity != nil, compactActivityGeometry.compactActivityWingWidth > 0,
               !UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                guard self.running, !self.suspended, self.inside, !self.hoverState.suppressed,
                      !self.expanded, !self.peeking, !self.pinned, !self.heldDrag, !self.keepsWorkingSurface,
                      !self.showsCompactActivityPicker,
                      self.captureControls == nil, (self.notice == nil || self.hiddenUntilHover), !self.dragPlaceholder,
                      UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover),
                      self.windowHost?.blocksHoverReveal() == false,
                      self.geometry.contains(NSEvent.mouseLocation, in: self.hiddenUntilHover ? self.geometry.collapsed : self.surfaceSize) else { return }
                // Following the closed island ends as it opens or peeks.
                self.removeHoverExitMonitors()
                if UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) {
                    self.open(takeFocus: false)
                } else {
                    self.mutatePresentation(transitionContent: .reveal) { self.peeking = true }
                    self.provideHapticFeedback()
                }
            }
            hoverWork = work
            let delay = NotchSupport.sanitizedHoverDelay(UserDefaults.standard.double(forKey: DefaultsKey.notchHoverDelay))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else if holdsNotification
                    || NotchSupport.closesOnPointerExit(expanded: expanded, peeking: peeking, openedByHover: openedByHover) {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                guard self.running, !self.suspended, !self.inside,
                      self.windowHost?.containsHover(NSEvent.mouseLocation) != true,
                      !self.pointerOverChildWindow(NSEvent.mouseLocation) else { return }
                self.releaseNotification()
                guard !self.pinned, !self.heldDrag, !self.keepsWorkingSurface, self.captureControls == nil,
                      !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation),
                      NotchSupport.closesOnPointerExit(expanded: self.expanded, peeking: self.peeking, openedByHover: self.openedByHover) else { return }
                self.collapse()
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (expanded || noticeExpanded ? NotchQuickAccessLayout.hoverExitDelay : 0.12), execute: work)
        }
    }

    /// AppKit reports hover from the mouse moves it receives, and those can
    /// stop while the pointer crosses the transparent margin around the
    /// floating controls. One can even carry another window's coordinates.
    /// An exit can then arrive with the pointer still in that margin and be
    /// the last report. From such an exit until AppKit reports the pointer
    /// again, every move is checked here, so leaving still closes the island.
    /// The closed island's hover emphasis has the same gap, and worse: a fast
    /// pass up through the top edge to a display above can report its exit
    /// while the pointer still touches the island, or no exit at all. So while
    /// the emphasis shows, moves are followed from the entry on. A pointer at
    /// rest costs nothing.
    private func syncHoverExitMonitoring(entered: Bool, point: CGPoint) {
        // A timed capture stays attached to the closed island until its timer
        // ends, and each followed move would tell it the pointer left, which
        // restarts its dismissal under a pointer that came back to reopen it.
        let watching = (hoverEmphasized && captureHover == nil
                || !entered && NotchSupport.closesOnPointerExit(expanded: expanded, peeking: peeking, openedByHover: openedByHover))
            && captureControls == nil && !pinned && !heldDrag && !hiddenUntilHover && !keepsWorkingSurface
            // Once watching, a pointer that leaves and slips back unreported is still seen.
            && (hoverExitWatch.isWatching || windowHost?.containsHover(point) == true)
        guard watching else { removeHoverExitMonitors(); return }
        hoverExitWatch.start()
    }

    private func removeHoverExitMonitors() {
        hoverExitWatch.stop()
    }

    /// A mirrored banner the pointer can hold: on screen and not covered.
    /// Hidden mode keeps its notices out of reach, as the surface is not shown.
    private var holdsNotification: Bool {
        notice?.notificationID != nil && noticeCanPresent && !hiddenUntilHover
    }

    /// A mirrored banner waits under the pointer, as the native one does, and
    /// a deliberate hover opens its whole message in place.
    private func holdNotification(_ id: UUID) {
        noticeWork?.cancel(); noticeWork = nil
        guard !noticeExpanded, !hoverState.suppressed,
              UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWork = nil
            guard self.running, !self.suspended, self.inside, !self.hoverState.suppressed, !self.pinned, !self.heldDrag,
                  !self.keepsWorkingSurface, self.holdsNotification, self.notice?.notificationID == id, !self.noticeExpanded,
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover),
                  self.geometry.contains(NSEvent.mouseLocation, in: self.surfaceSize) else { return }
            self.mutatePresentation(transitionContent: .reveal) { self.peeking = false; self.noticeExpanded = true }
            self.provideHapticFeedback()
        }
        hoverWork = work
        let delay = NotchSupport.sanitizedHoverDelay(UserDefaults.standard.double(forKey: DefaultsKey.notchHoverDelay))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Leaving closes an opened preview; a banner that was only held gets its
    /// full time again, so a quick pass over it never cuts it short.
    private func releaseNotification() {
        guard let notice, notice.notificationID != nil else { return }
        if noticeExpanded { dismissNotice() }
        else if noticeWork == nil { scheduleNoticeDismissal(after: notice.event.duration) }
    }

    private func syncNoticeWithPreferences() {
        guard let notice else { return }
        if !NotchSupport.routes(notice.event) || (notice.notificationID != nil && hiddenUntilHover) {
            dismissNotice()
        }
    }

    private func scheduleNoticeDismissal(after duration: TimeInterval) {
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissNotice() }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    package var filteredSections: [NotchModule] {
        NotchSupport.filteredModules(modules, query: sectionQuery) { module in
            let language = L10n.shared.language
            let music = module == .music ? FeatureStrings.notch(language).music : ""
            return [module.title(language), module.rawValue, music].joined(separator: " ")
        }
    }

    package func searchSections(_ query: String) {
        guard sectionQuery != query else { return }
        mutatePresentation {
            sectionQuery = query
            highlightedSection = filteredSections.first
        }
    }

    package func toggleSections() {
        guard captureControls == nil, !heldDrag else { return }
        if showingSections {
            open(appPanel: showingAppPanel, metric: selectedMetric)
        } else {
            sectionQuery = ""
            // The gallery opens from its top, stepping only as far as the
            // current section's row.
            sectionRow = 0
            highlightedSection = selected
            open(appPanel: showingAppPanel, metric: selectedMetric, sections: true)
        }
    }

    private var sectionRowLimits: (rows: Int, visible: Int) {
        let count = filteredSections.count
        return (NotchSectionPaging.rows(count: count, columns: geometry.sectionColumns), geometry.sectionRows(count: count))
    }

    /// Keyboard moves and search results keep the highlighted tile's row in
    /// view, moving the gallery no further than that row needs.
    private func revealHighlightedSection() {
        guard let target = highlightedSection, let index = filteredSections.firstIndex(of: target) else { return }
        let limits = sectionRowLimits
        let row = NotchSectionPaging.revealing(row: index / max(1, geometry.sectionColumns), first: sectionRow,
                                               rows: limits.rows, visible: limits.visible)
        if row != sectionRow { sectionRow = row }
    }

    /// Rest the gallery on `row`, within the rows it has.
    package func showSectionRow(_ row: Int) {
        let limits = sectionRowLimits
        let next = NotchSectionPaging.clamped(row, rows: limits.rows, visible: limits.visible)
        guard next != sectionRow else { return }
        sectionRow = next
        provideHapticFeedback()
    }

    package func scrollSections(by rows: Int) { showSectionRow(sectionRow + rows) }

    private func handleSectionKey(_ event: NSEvent) -> Bool {
        guard showingSections,
              (panel?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 48, modifiers.isEmpty || modifiers == .shift {
            highlightedSection = NotchSupport.adjacentModule(to: highlightedSection, modules: filteredSections,
                                                             backwards: modifiers == .shift)
            return true
        }
        guard modifiers.isEmpty else { return false }
        if event.keyCode == 36 || event.keyCode == 76 {
            if let target = highlightedSection, filteredSections.contains(target) { select(target) }
            return true
        }
        let direction: QuickToolsSupport.GridDirection
        switch event.keyCode {
        case 123 where sectionQuery.isEmpty: direction = .left
        case 124 where sectionQuery.isEmpty: direction = .right
        case 125: direction = .down
        case 126: direction = .up
        default: return false
        }
        let sections = filteredSections
        guard !sections.isEmpty else { return true }
        // While typing, the side arrows keep editing the query and the
        // vertical pair steps through the matches in order.
        guard sectionQuery.isEmpty else {
            highlightedSection = NotchSupport.adjacentModule(to: highlightedSection, modules: sections,
                                                             backwards: direction == .up)
            return true
        }
        let index = highlightedSection.flatMap { sections.firstIndex(of: $0) } ?? 0
        highlightedSection = sections[QuickToolsSupport.gridIndex(after: index, count: sections.count,
                                                                   flow: .rows(columns: geometry.sectionColumns),
                                                                   direction: direction)]
        return true
    }

    /// The floating pad's tab shortcuts work on its page too. With one pad
    /// left, Command-W closes the island the way it hides the pad.
    private func handleScratchpadKey(_ event: NSEvent) -> Bool {
        guard selected == .scratchpad, !showingAppPanel, !showingSections, selectedMetric == nil else { return false }
        let pad = ScratchpadService.shared
        let commandOnly = event.modifierFlags.intersection([.command, .control, .option]) == .command
        let shift = event.modifierFlags.contains(.shift)
        guard let action = ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                                                               commandOnly: commandOnly,
                                                               shift: shift,
                                                               canCreatePad: pad.canCreatePad,
                                                               canClosePad: pad.canClosePad) else {
            // At the tab limit Command-T still belongs to the pad, not the text.
            return commandOnly && !shift && event.charactersIgnoringModifiers?.lowercased() == "t"
        }
        switch action {
        case .createPad: pad.createPad(defaultName: FeatureStrings.scratchpad(L10n.shared.language).pageTitle)
        case .closeSelectedPad: scratchpadCloseSerial += 1
        case .hidePad: collapse()
        case .find: requestScratchpadFind(.showFindInterface)
        case .findNext: requestScratchpadFind(.nextMatch)
        case .findPrevious: requestScratchpadFind(.previousMatch)
        }
        return true
    }

    /// The editor lives in the view, so the request goes out as a serial and
    /// the view reads which of the finder's actions it was for.
    private func requestScratchpadFind(_ action: NSTextFinder.Action) {
        scratchpadFindAction = action
        scratchpadFindSerial += 1
    }

    private func handleClipboardPasteKey(_ event: NSEvent) -> Bool {
        guard selected == .clipboard, !showingAppPanel, !showingSections, selectedMetric == nil else { return false }
        let commandOnly = event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command
        guard let index = NotchClipboardPastePress.index(keyCode: event.keyCode, commandOnly: commandOnly)
        else { return false }
        clipboardPastePress = NotchClipboardPastePress(serial: (clipboardPastePress?.serial ?? 0) &+ 1, index: index)
        return true
    }

    package func activateQuickAction(_ action: NotchQuickAction) {
        guard NotchSupport.isEnabled(), action.isAvailable() else { return }
        switch action {
        case .explore: toggleSections()
        case .settings: openSettings()
        case .pin: pinned.toggle()
        case .module(let module): select(module)
        case .control(let item):
            switch item {
            case .keepAwake: KeepAwakeManager.shared.toggle()
            case .microphone: MicMuteService.shared.toggle()
            case .screenshot: perform { ScreenshotService.shared.capture() }
            case .recording: perform { ScreenRecorderService.shared.toggle() }
            case .speedTest: showMetric(.network)
            case .panel: openAppPanel()
            case .mixer: select(.mixer)
            case .music: select(.music)
            case .timer: select(.timer)
            case .calendar: select(.calendar)
            case .commandBar: perform { CommandBarService.shared.show() }
            case .scratchpad: openScratchpad()
            case .volume, .brightness: select(.controls)
            }
        }
    }

    package func select(_ module: NotchModule) {
        guard modules.contains(module) else { return }
        open(module)
    }

    /// The pad lives in the island when its page is on; otherwise the
    /// shortcut opens the floating pad as it always did.
    package func openScratchpad() {
        if !showScratchpad() { perform { ScratchpadService.shared.show() } }
    }

    @discardableResult
    package func showScratchpad(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesScratchpad(), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .scratchpad, !showingAppPanel, !showingSections,
           selectedMetric == nil, panel?.isKeyWindow == true { collapse() }
        else { open(.scratchpad) }
        return true
    }

    package func openAppPanel(toggle: Bool = false) {
        if toggle, expanded, showingAppPanel, !showingSections { collapse(); return }
        MainActor.assumeIsolated { MenuPanelFocus.shared.showNormalPanel() }
        open(.controls, appPanel: true)
        // The toggling route is the menu bar's. Opened from there, the panel
        // has nothing behind it and closes on Escape, like the menu panel.
        if toggle { detailHasPage = false }
    }

    package func openQuickPanel(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesQuickPanel(), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .tools, !showingSections { collapse() }
        else { open(.tools) }
        return true
    }

    package func openShelf(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesShelf(), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .files, !showingSections { collapse() }
        else { open(.files) }
        return true
    }

    package func showMetric(_ metric: MetricDetailKind, toggle: Bool = false) {
        guard metricIsAvailable(metric) else { return }
        if toggle, expanded, selectedMetric == metric, !showingSections { collapse(); return }
        open(.system, metric: metric)
        // A metric opened from its menu bar item closes on Escape, like the popover.
        if toggle { detailHasPage = false }
    }

    /// Fan Control is a single card, so its detail fits the card instead of
    /// opening a tall, mostly empty page. A taller card still scrolls in it.
    package func updateFanDetailHeight(_ height: CGFloat) {
        guard expanded, selectedMetric == .fan, !showingAppPanel, !showingSections,
              height.isFinite, height > 0 else { return }
        let measured = ceil(height)
        guard fanDetailHeight != measured else { return }
        fanDetailHeight = measured
        refreshPresentation()
    }

    package func goBack() {
        let changesPresentation = selectedMetric != nil || showingAppPanel
        mutatePresentation(transitionContent: changesPresentation ? .replace : .none) { selectedMetric = nil; showingAppPanel = false }
        syncVisibleConsumers()
        if changesPresentation { provideHapticFeedback() }
    }

    /// Escape steps back one level: a detail returns to its page as the Back
    /// button does, a page closes the layer it shows, and the island closes
    /// once nothing lies behind.
    private func stepBack() {
        guard captureControls == nil, !heldDrag else { return }
        if showingAppPanel || selectedMetric != nil {
            if detailHasPage { goBack() } else { collapse() }
        } else if let close = pageLayers[selected] {
            close()
        } else {
            collapse()
        }
    }

    /// A page reports the layer it shows over its content with how to close
    /// it, and nil once the layer or the page is gone.
    package func setPageLayer(_ module: NotchModule, close: (() -> Void)?) {
        pageLayers[module] = close
    }

    package func provideHapticFeedback() {
        guard acceptsUserInteraction, panel?.isVisible == true, NotchSupport.usesHapticFeedback() else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    package func fileDragChanged(_ active: Bool, internalDrag: Bool = false) {
        guard running, !suspended, internalDrag || NotchSupport.routesShelf() else { return }
        heldDrag = active && internalDrag
        if active, !internalDrag, NotchSupport.revealsShelfDrag(), !expanded {
            mutatePresentation { dragPlaceholder = true; peeking = false }
        } else if !active {
            mutatePresentation { dragPlaceholder = false }
            inside = windowHost?.containsHover(NSEvent.mouseLocation) == true
            if !inside, !pinned { hover(false) }
        }
    }

    package func presentCaptureControls(_ options: ScreenCaptureSelectionOptions, cancel: @escaping () -> Void) {
        guard acceptsSystemFeedback else { cancel(); return }
        let closeCapture = detachCaptureIfClosingOnCollapse()
        pinned = false
        captureControlsCancel = cancel
        captureControls = options
        // The controls wait compact around the camera, clear of what is being
        // captured, and open while the pointer rests on them.
        captureControlsCollapsed = true
        captureSelectionInProgress = false
        options.onSelectionProgressChange = { [weak self, weak options] active in
            guard let self, let options, self.captureControls === options else { return }
            self.setCaptureSelectionInProgress(active)
        }
        captureControlsSubscription = options.$selectedTool.dropFirst()
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshPresentation()
                self?.updateCaptureControlsClickThrough()
                self?.scheduleCaptureControlsCollapse()
            }
        expanded = false
        showingSections = false
        peeking = false
        notice = nil
        noticeExpanded = false
        hoverWork?.cancel()
        removeEventMonitors()
        panel?.acceptsKeyFocus = true
        panel?.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        refreshPresentation()
        // A pointer already resting there has not hovered them; it leaves and
        // comes back before they open.
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        panel?.orderFrontRegardless()
        panel?.makeKey()
        installCaptureControlsClickThrough()
        syncVisibleConsumers()
        closeCapture?()
    }

    package func collapseCaptureControls() {
        guard captureControls != nil else { return }
        captureControlsWork?.cancel(); captureControlsWork = nil
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        captureControls?.hasFocusedControl = false
        captureControlsCollapsed = true
        refreshPresentation(animated: !captureSelectionInProgress)
        updateCaptureControlsClickThrough()
    }

    package func expandCaptureControls() {
        guard captureControls != nil, !captureSelectionInProgress else { return }
        hoverWork?.cancel(); hoverWork = nil
        hoverState.open()
        captureControlsCollapsed = false
        refreshPresentation()
        panel?.makeKey()
        updateCaptureControlsClickThrough()
    }

    private func setCaptureSelectionInProgress(_ active: Bool) {
        guard captureControls != nil else { return }
        captureSelectionInProgress = active
        if active { collapseCaptureControls() }
        else {
            refreshPresentation()
            updateCaptureControlsClickThrough()
        }
    }

    /// Open controls close soon after the pointer leaves them. Opened with the
    /// pointer elsewhere, from the keyboard, they wait long enough for a
    /// control to take focus, which then keeps them open.
    package func scheduleCaptureControlsCollapse(after delay: TimeInterval = 3) {
        captureControlsWork?.cancel(); captureControlsWork = nil
        guard let options = captureControls, !captureControlsCollapsed, !captureSelectionInProgress,
              !options.hasFocusedControl, !inside else { return }
        let work = DispatchWorkItem { [weak self, weak options] in
            guard let self, let options, self.captureControls === options else { return }
            self.captureControlsWork = nil
            guard !self.captureControlsCollapsed, !self.captureSelectionInProgress,
                  !options.hasFocusedControl, !self.trackingMenu,
                  self.panel?.attachedSheet == nil,
                  self.windowHost?.containsHover(NSEvent.mouseLocation) != true else { return }
            self.collapseCaptureControls()
        }
        captureControlsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func updateCaptureControlsHover(wasInside: Bool) {
        guard let options = captureControls, !captureSelectionInProgress else { return }
        if !captureControlsCollapsed {
            if inside {
                captureControlsWork?.cancel(); captureControlsWork = nil
            } else if wasInside {
                // Leaving closes them, as it closes an island opened by hover.
                scheduleCaptureControlsCollapse(after: NotchQuickAccessLayout.hoverExitDelay)
            } else if captureControlsWork == nil {
                scheduleCaptureControlsCollapse()
            }
            return
        }
        if inside == wasInside, let hoverWork, !hoverWork.isCancelled { return }
        hoverWork?.cancel(); hoverWork = nil
        guard inside, !hoverState.suppressed else { return }
        let work = DispatchWorkItem { [weak self, weak options] in
            guard let self, let options, self.captureControls === options else { return }
            self.hoverWork = nil
            guard self.captureControlsCollapsed, !self.captureSelectionInProgress,
                  !self.hoverState.suppressed,
                  self.windowHost?.containsHover(NSEvent.mouseLocation) == true else { return }
            self.expandCaptureControls()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// The capture-controls window covers the top center of the screen, over
    /// the selection surface. Only its visible controls should catch the
    /// mouse; everywhere else the click falls through to the selection beneath,
    /// so a region under the notch can still be dragged or a window clicked.
    private func updateCaptureControlsClickThrough() {
        guard let panel, captureControls != nil else { return }
        let point = NSEvent.mouseLocation
        // A collapsing animation still reserves the old window frame. Only
        // the compact target should own clicks while that space is released.
        let overControls = !captureSelectionInProgress && windowHost?.contains(point) == true
            && (!captureControlsCollapsed || windowHost?.containsHover(point) == true)
        windowHost?.setMouseEventsIgnored(!overControls)
        // While the panel catches the mouse it is the window under the pointer
        // across its whole frame, transparent parts included, so it must be the
        // one reporting the move that leaves the controls; otherwise the next
        // click there would be swallowed. Away from the controls the selection
        // surface reports every move itself, and the panel stays quiet.
        if panel.acceptsMouseMovedEvents != overControls { panel.acceptsMouseMovedEvents = overControls }
        hover(overControls)
    }

    private func installCaptureControlsClickThrough() {
        guard !captureControlsWatch.isWatching else { return }
        // The selection surface below is this app's own window and already
        // tracks the pointer, so watching this app sees every move that could
        // reach a control. Watching the others would add a second, system-wide
        // stream of every move at the mouse's full rate, and asking the key
        // panel for moved events on top of that starved the selector: with
        // both installed it received fewer events and trailed the pointer.
        captureControlsWatch.start()
        updateCaptureControlsClickThrough()
    }

    private func removeCaptureControlsClickThrough() {
        captureControlsWatch.stop()
        windowHost?.setMouseEventsIgnored(false)
        panel?.acceptsMouseMovedEvents = false
    }

    private func missionControlDidRestore() {
        if captureControls != nil { updateCaptureControlsClickThrough() }
        else { hover(windowHost?.containsHover(NSEvent.mouseLocation) == true) }
        // A pointer that crossed displays during Mission Control is followed now.
        schedulePointerFollow()
    }

    package func endCaptureControls() {
        guard captureControls != nil else { return }
        captureControlsWork?.cancel(); captureControlsWork = nil
        hoverWork?.cancel(); hoverWork = nil
        captureControls?.onSelectionProgressChange = nil
        geometry.compactSideRoom = nil
        captureControls = nil
        captureControlsCollapsed = false
        captureSelectionInProgress = false
        captureControlsSubscription = nil
        captureControlsCancel = nil
        removeCaptureControlsClickThrough()
        panel?.level = NotchPanel.normalLevel
        panel?.acceptsKeyFocus = false
        panel?.resignKey()
        refreshPresentation()
        syncVisibleConsumers()
    }

    package func cancelCaptureControls() { captureControlsCancel?() }

    package func openSettings() {
        collapse()
        SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
        MainActor.assumeIsolated { appShell()?.openSettingsWindow() }
    }

    /// Opens the Dynamic Island settings on one section's options.
    package func openSettings(showing module: NotchModule) {
        SettingsRouter.shared.notchModule = module
        openSettings()
    }

    package func perform(_ action: @escaping @MainActor () -> Void) {
        collapse()
        if let windowHost { windowHost.whenSettled(action) }
        else { DispatchQueue.main.async { action() } }
    }

    package var canAcceptFileDrop: Bool {
        acceptsUserInteraction && captureControls == nil && modules.contains(.files)
            && AppFeature.shelf.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
    }

    /// Where on the open island the media tools take a drop.
    private var mediaDropArea: CGRect {
        NotchFileToolsSupport.mediaDropArea(in: expandedGeometry, size: surfaceSize)
    }

    // Each forward spans lines so the shelf-drop contract can copy it.
    package func beginFileDrop(_ pasteboard: NSPasteboard) {
        fileDrop.begin(pasteboard)
    }

    @discardableResult
    package func updateFileDrop(at point: CGPoint) -> Bool {
        fileDrop.update(at: point)
    }

    package func endFileDrop() {
        fileDrop.end()
    }

    package func keepFileInteractionOpen(_ active: Bool) {
        fileInteractionActive = active
        hover(false)
    }

    package func accept(_ pasteboard: NSPasteboard) -> Bool {
        fileDrop.accept(pasteboard)
    }

    /// A drop landed: the island no longer holds the drag or its placeholder.
    private func fileDropLanded() {
        heldDrag = false
        dragPlaceholder = false
    }

    @discardableResult
    package func show(_ incoming: NotchNotice) -> Bool {
        guard showsSystemFeedback, NotchSupport.routes(incoming.event),
              NotchSupport.shouldReplace(notice?.event, with: incoming.event, held: noticeExpanded) else { return false }
        noticeWork?.cancel(); noticeWork = nil
        var incoming = incoming
        if incoming.notification != nil, let shown = notice, shown.notification != nil, noticeCanPresent, !noticeExpanded {
            incoming.minimumWingWidth = shown.preferredWingWidth
        }
        let keepsPreview = noticeExpanded && incoming.notificationID != nil
            && windowHost?.containsHover(NSEvent.mouseLocation) == true
        // Slider and key bursts only replace the displayed value. They never
        // restart a window resize or enqueue another layout animation.
        let transition: NotchContentTransition = !noticeCanPresent ? .none
            : notice == nil ? .reveal : notice?.event != incoming.event || noticeExpanded ? .replace : .none
        mutatePresentation(transitionContent: transition) {
            notice = incoming
            noticeExpanded = keepsPreview
        }
        // A banner arriving under the pointer is held at once, whether the
        // pointer was already inside or an opening was pending.
        if let id = incoming.notificationID, holdsNotification, windowHost?.containsHover(NSEvent.mouseLocation) == true {
            hoverWork?.cancel(); hoverWork = nil
            inside = true
            holdNotification(id)
        } else {
            scheduleNoticeDismissal(after: incoming.event.duration)
        }
        return true
    }

    package func activateNotice(_ selectedNotice: NotchNotice) {
        guard notice == selectedNotice else { return }
        if let id = selectedNotice.notificationID {
            guard NotchNotificationService.shared.openingID == nil else { return }
            // The pointer stays where the banner was; like a click on the
            // island itself, this must not turn into a hover opening.
            settleNotificationHover()
            NotchNotificationService.shared.open(id) { [weak self] result in
                guard let self else { return }
                if self.notice?.notificationID == id { self.dismissNotice() }
                if result == .unavailable || result == .uncertain { self.open(.notifications) }
            }
            return
        }
        open(selectedNotice.event == .download ? .downloads : selectedNotice.event == .timer ? .timer
             : selectedNotice.event == .accessory ? .system : selectedNotice.event == .systemNotification ? .notifications
             : selectedNotice.event == .clipboard ? .clipboard : selectedNotice.event == .agents ? .agents
             : selectedNotice.event == .track ? .music : selectedNotice.event == .microphone ? .mixer
             : selectedNotice.event == .watch ? .watch : .controls)
    }

    /// Skipping through songs, or a title that lands before its artist, shows
    /// one notice for where playback settles. Until then the compact strip
    /// keeps the song it showed.
    private func scheduleTrackNotice() {
        trackWork?.cancel()
        if heldMusic == nil, let presentedMusic { heldMusic = presentedMusic }
        // With no song on the strip, as after a long gap between songs, the
        // new one waits too, so the notice is still where it first appears.
        if heldMusic == nil { awaitsTrackNotice = true }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.trackWork = nil
            // Released once the notice covers the strip, or when none can.
            defer { self.releaseTrackHold() }
            // The open island already shows the song, or holds something else
            // the person is doing.
            guard !self.expanded, !self.peeking, !self.dragPlaceholder, self.captureControls == nil,
                  let playback = NotchMusicService.shared.playback, playback.isPlaying,
                  let title = playback.track.title, !title.isEmpty else { return }
            self.show(NotchNotice(event: .track, title: title, detail: playback.track.artist ?? "",
                                  symbol: "music.note"))
        }
        trackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// The reading that ends the song names nothing, another player's song or
    /// the next one paused. Held, the strip leaves as the song it showed, and
    /// its hiding ends the hold.
    private func holdEndingTrack() {
        if heldMusic == nil, let presentedMusic { heldMusic = presentedMusic }
    }

    /// The closed island turns to the live song. A song that waited for its
    /// notice appears now, unless a notice covers it, and the menu room is
    /// read again for the strip it brings.
    private func releaseTrackHold() {
        if heldMusic != nil { heldMusic = nil }
        guard awaitsTrackNotice else { return }
        awaitsTrackNotice = false
        syncMenuSpaceMonitoring()
        if notice == nil { refreshPresentation() }
    }

    package func showBrightness(_ level: Double) -> Bool {
        let text = FeatureStrings.notch(L10n.shared.language)
        return show(NotchNotice(event: .brightness, title: text.brightness,
                                detail: "\(BrightnessSupport.wholePercent(level))%",
                                symbol: "sun.max.fill", level: level))
    }

    @discardableResult
    package func showKeyboardLight(_ level: Double) -> Bool {
        guard level.isFinite, (0...1).contains(level) else { return false }
        return show(NotchNotice(event: .keyboardLight,
                                title: FeatureStrings.brightness(L10n.shared.language).keyboardLight,
                                detail: "\(BrightnessSupport.wholePercent(level))%",
                                symbol: "keyboard", level: level))
    }

    /// The microphone switch reports here the way the volume does: its mark
    /// on one side of the camera, what happened on the other. False leaves
    /// the confirmation to its own panel.
    @discardableResult
    package func showMicrophone(muted: Bool) -> Bool {
        // Only the closed island draws this notice. While it is open or busy
        // the floating confirmation keeps the job.
        guard noticeCanPresent else { return false }
        let text = L10n.shared.s
        return show(NotchNotice(event: .microphone, title: "",
                                detail: muted ? text.micMutedHUD : text.micUnmutedHUD,
                                symbol: muted ? "mic.slash.fill" : "mic.fill"))
    }

    /// A partial result is confirmed by the floating panel alone, so the
    /// notice left by the press before it must not contradict the warning.
    package func retractMicrophoneNotice() {
        guard notice?.event == .microphone else { return }
        dismissNotice()
    }

    /// The close button of a held preview also takes the message out of the
    /// inbox, like the close button of the inbox row.
    package func dismissNotification(_ selectedNotice: NotchNotice) {
        guard notice == selectedNotice, let id = selectedNotice.notificationID else { return }
        settleNotificationHover()
        NotchNotificationService.shared.dismiss(id)
        dismissNotice()
    }

    private func settleNotificationHover() {
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
    }

    private func dismissNotice() {
        noticeWork?.cancel(); noticeWork = nil
        endDeparture()
        let transition: NotchContentTransition = notice == nil || !noticeCanPresent ? .none
            : noticeExpanded ? .dismiss : .depart
        let departing = transition == .depart ? notice : nil
        mutatePresentation(transitionContent: transition) {
            departingNotice = departing
            notice = nil
            noticeExpanded = false
        }
        guard departingNotice != nil else { return }
        // Without motion the host hides the content at once; so does the view.
        guard windowHost?.departsContent == true else { endDeparture(); return }
        let work = DispatchWorkItem { [weak self] in self?.endDeparture() }
        departureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.departureHidden, execute: work)
    }

    private func endDeparture() {
        departureWork?.cancel(); departureWork = nil
        guard departingNotice != nil else { return }
        departingNotice = nil
        windowHost?.finishDeparture()
    }

    private var noticeCanPresent: Bool {
        !expanded && !dragPlaceholder && captureControls == nil
    }

    package func presentCapture(id: UUID, content: AnyView, actions: AnyView? = nil, height: CGFloat,
                        takeFocus: Bool, closeOnCollapse: Bool, fallback: @escaping () -> Void,
                        close: @escaping () -> Void, hover: @escaping (Bool) -> Void) -> Bool {
        guard acceptsSystemFeedback, NotchSupport.routes(.capture) else { return false }
        let keepOpen = expanded && pinned
        captureID = id
        captureContentHeight = height
        captureContent = content
        captureActions = actions
        captureFallback = fallback
        captureClose = close
        captureHover = hover
        captureClosesOnCollapse = closeOnCollapse
        open(.captures, pinned: keepOpen,
             takeFocus: takeFocus, feedback: false)
        captureHover?(inside)
        return true
    }

    package func updateCaptureHeight(id: UUID, height: CGFloat) {
        guard captureID == id, captureContent != nil, height.isFinite, height > 0,
              captureContentHeight != height else { return }
        captureContentHeight = height
        refreshPresentation()
    }

    package func isCaptureVisible(id: UUID) -> Bool {
        acceptsSystemFeedback && expanded && selected == .captures
            && !showingAppPanel && !showingSections && selectedMetric == nil
            && captureControls == nil && captureID == id && captureContent != nil
    }

    package func removeCapture(id: UUID) {
        guard captureID == id else { return }
        clearCapture()
        if expanded, selected == .captures, !showingSections {
            if pinned { refreshPresentation() }
            else { collapse() }
        }
    }

    private func clearCapture() {
        captureID = nil
        captureContent = nil
        captureActions = nil
        captureContentHeight = nil
        captureFallback = nil
        captureClose = nil
        captureHover = nil
        captureClosesOnCollapse = false
    }

    /// Persistent captures must detach before their close callback runs so a
    /// replaced island surface cannot be collapsed again by that callback.
    /// Timed captures remain attached to their existing dismissal timer.
    private func detachCaptureIfClosingOnCollapse() -> (() -> Void)? {
        guard captureClosesOnCollapse else { return nil }
        let close = captureClose
        clearCapture()
        return close
    }

    private func mutatePresentation(transitionContent: NotchContentTransition = .none, _ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
        refreshPresentation(transitionContent: transitionContent)
    }

    private func finishMusicDeparture() {
        musicDepartureWork?.cancel(); musicDepartureWork = nil
        guard departingMusic != nil else { return }
        departingMusic = nil
        if windowHost?.departsContent == true { windowHost?.finishDeparture() }
    }

    private func compactMusicTransition(_ requested: NotchContentTransition, animated: Bool) -> NotchContentTransition {
        let musicVisible = compactMusicIsVisible
        let canKeepDeparting = !musicVisible && compactActivity == nil && !expanded && !peeking
            && notice == nil && !dragPlaceholder && captureControls == nil
        if departingMusic != nil {
            if canKeepDeparting && requested == .none && animated
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return .none }
            musicDepartureWork?.cancel(); musicDepartureWork = nil
            departingMusic = nil
            // A new presentation must replace the departure's forward-filled mask.
            return requested == .none ? (animated ? .reveal : .replace) : requested
        }
        guard requested == .none, animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              panel?.isVisible == true, let presentedMusic, !musicVisible else { return requested }
        if canKeepDeparting {
            // A held track is the one on screen.
            departingMusic = heldMusic ?? presentedMusic
            return .depart
        }
        // Another compact activity took the same place as the disappearing track.
        return !expanded && !peeking && compactActivity != nil && notice == nil ? .replace : requested
    }

    private func rememberPresentedMusic(playback: NotchPlayback?, artwork: NSImage?, tint: NotchArtworkTint?) {
        guard compactMusicIsVisible, panel?.isVisible == true, let playback else {
            presentedMusic = nil
            // Whatever hid the strip ends the hold; it comes back with the live song.
            if heldMusic != nil { heldMusic = nil }
            return
        }
        presentedMusic = NotchCompactMusicSnapshot(playback: playback, artwork: artwork,
                                                  tint: tint, geometry: compactActivityGeometry)
    }

    package func refreshPresentation(animated: Bool = true, transitionContent: NotchContentTransition = .none) {
        activitySelection.reconcile(available: compactActivities)
        if fullscreenCompact {
            finishMusicDeparture()
            presentedMusic = nil
        }
        syncHiddenHoverMonitoring()
        // Closing, or a notice ending, can leave the island at rest away from
        // a pointer that has not moved since; it follows it then. The copies
        // on other displays follow what it shows closed.
        defer {
            schedulePointerFollow()
            syncMirrors()
        }
        if hiddenUntilHover || (captureControls != nil && captureSelectionInProgress) {
            finishMusicDeparture()
            presentedMusic = nil
            // Hiding the strip ends a hold, as rememberPresentedMusic does, so
            // a song held as it ended never comes back over the next one.
            if heldMusic != nil { heldMusic = nil }
            if hiddenUntilHover { windowHost?.hide(animated: animated, transitionContent: transitionContent) }
            else { panel?.orderOut(nil) }
            removeScreenEdgeClickMonitors()
            return
        }
        let open = expanded || peeking || notice != nil || dragPlaceholder || captureControls != nil
        guard open || (!hiddenAtRestInFullscreen && (geometry.isNotched || geometry.compactSideRoom != nil)) else {
            finishMusicDeparture()
            presentedMusic = nil
            if heldMusic != nil { heldMusic = nil }
            windowHost?.hide(animated: animated, transitionContent: transitionContent)
            removeScreenEdgeClickMonitors()
            return
        }
        let access = NotchQuickAccessConfiguration.current()
        let size = surfaceSize
        let contentTransition = compactMusicTransition(transitionContent, animated: animated)
        if captureControls == nil {
            // A simulated cutout yields to the menu bar when it reappears in full screen.
            panel?.level = hiddenInFullscreen && !geometry.isNotched && !NotchSupport.coversMenus()
                ? NotchPanel.fullscreenLevel : NotchPanel.normalLevel
        }
        // Preferences can change computed dimensions without publishing a
        // service property. Update SwiftUI's layout along with the native host.
        if let windowHost, windowHost.targetSize != size { objectWillChange.send() }
        windowHost?.setOutline(enabled: !fullscreenCompact && UserDefaults.standard.bool(forKey: DefaultsKey.notchOutlineEnabled),
                               color: compactActivityIsVisible && compactActivity == .timer ? .systemOrange : .white)
        windowHost?.present(size: size, geometry: expanded ? expandedGeometry : geometry, animated: animated,
                            transitionContent: contentTransition,
                            quickAccess: expanded && captureControls == nil && !access.buttons.isEmpty ? access : nil,
                            revealFromHidden: !hiddenInFullscreen && captureControls == nil
                                && UserDefaults.standard.bool(forKey: DefaultsKey.notchHideUntilHover)
                                && UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover),
                            usesGlass: !fullscreenCompact && usesGlassSurface)
        // The selector lives in a separate full-screen panel. A floating
        // capsule may sit below the display edge, so publish the island's
        // actual bottom inset as the controls collapse or reopen.
        captureControls?.onCaptureControlsSurfaceChange?(
            geometry.screen, geometry.floatingDrop + size.height)
        // Closing can shrink the island away from a pointer that has not moved,
        // with no boundary crossing to report it. Only a pointer still over the
        // island may keep its next approach from opening it.
        if windowHost?.containsHover(NSEvent.mouseLocation) != true { hoverState.update(pointerInside: false) }
        let activationRect: CGRect
        if captureControls != nil {
            activationRect = captureControlsCollapsed ? CGRect(origin: .zero, size: size) : .zero
        } else if notice != nil || dragPlaceholder {
            activationRect = .zero
        } else if showsCompactActivityPicker {
            let strip = compactActivityGeometry.compactActivitySize
            activationRect = compactActivityGeometry.activationArea(
                in: strip, hasHeader: false, compactActivity: true)
                .offsetBy(dx: (size.width - strip.width) / 2, dy: 0)
        } else {
            activationRect = (expanded ? expandedGeometry : compactActivityIsVisible ? compactActivityGeometry : geometry)
                .activationArea(in: size, hasHeader: expanded || peeking, compactActivity: compactActivityIsVisible, expandedHeader: expanded)
        }
        let text = FeatureStrings.notch(L10n.shared.language)
        windowHost?.setActivationArea(activationRect, title: expanded ? text.collapse : text.open,
            willPress: { [weak self] in
                self?.hoverWork?.cancel()
                self?.hoverState.close(pointerInside: true)
            }, activate: { [weak self] in
                guard let self else { return }
                if self.captureControls != nil { self.expandCaptureControls() }
                else { self.toggle() }
            })
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
        let music = NotchMusicService.shared
        rememberPresentedMusic(playback: music.playback, artwork: music.artwork, tint: music.artworkTint)
        if contentTransition == .depart {
            if windowHost?.departsContent == true {
                let work = DispatchWorkItem { [weak self] in self?.finishMusicDeparture() }
                musicDepartureWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.departureHidden, execute: work)
            } else { finishMusicDeparture() }
        }
        syncScreenEdgeClicks()
    }

    private func syncHiddenHoverMonitoring() {
        guard running, !suspended, hiddenUntilHover, windowHost != nil else {
            removeHiddenHoverMonitors()
            return
        }
        // The window is ordered out, so native tracking areas cannot see entry.
        // Observe movement without intercepting the menu bar or polling at rest.
        hiddenHoverWatch.start()
    }

    private func removeHiddenHoverMonitors() {
        hiddenHoverWatch.stop()
    }

    private func syncPointerFollowing() { pointerFollower.sync() }

    private func removePointerMonitors() { pointerFollower.stop() }

    /// Only a closed island moves. A file dragged toward it brings the drop
    /// area along, so the file can land on either display; an open page, a
    /// notice or a drag out of the island stays where it is.
    private var canFollowPointer: Bool {
        // A song held for its New track notice keeps its old display's geometry.
        !expanded && !peeking && notice == nil && captureControls == nil && !heldDrag
            && !choosingFileDropDestination && !keepsWorkingSurface && heldMusic == nil
    }

    private func schedulePointerFollow() { pointerFollower.pointerMoved() }

    private func move(to screen: NSScreen) {
        displayID = screen.notchDisplayID
        updateScreen()
        // The menu space measured so far belongs to the display it left.
        invalidateMenuSpace()
        syncVisibleConsumers()
        refreshPresentation(animated: false)
    }

    /// A new song's title shows in the capsule for a few seconds, then the
    /// capsule keeps only the cover and the bars.
    private func nameCapsuleSong() {
        // The song held for the next one's notice is the one that ended; the
        // next song is named once the notice lets it go.
        guard heldMusic == nil else { return }
        musicTitleWork?.cancel()
        capsuleMusicTitleShown = true
        refreshCapsuleMusic()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.musicTitleWork = nil
            self.capsuleMusicTitleShown = false
            self.refreshCapsuleMusic()
        }
        musicTitleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.musicTitleDuration, execute: work)
    }

    /// A capsule is as wide as what it shows of the song, here or on another display.
    private func refreshCapsuleMusic() {
        guard compactActivity == .music,
              geometry.floats || mirrors.hasCapsule else { return }
        refreshPresentation()
    }

    // MARK: Every display

    /// With the island on every display, each other display shows a copy of
    /// what it shows closed (`NotchMirrors`).
    private func syncMirrors() { mirrors.sync() }

    private func closeMirrors() { mirrors.close() }

    /// Whether another display shows a copy of the closed island now.
    private var showsCopies: Bool { mirrors.showsAny }

    private func updateFullscreenDisplays() {
        mirrors.updateFullscreenDisplays(showsOnAllDisplays: showsOnAllDisplays)
    }

    /// A click on a copy brings the island to its display, open, closing it
    /// on the display it was open on.
    private func bringIsland(to id: CGDirectDisplayID) {
        guard running, !suspended, showsOnAllDisplays, id != displayID else { return }
        if expanded || peeking { collapse() }
        windowHost?.whenSettled { [weak self] in
            guard let self, self.running, !self.suspended, self.canFollowPointer,
                  let screen = NSScreen.screens.first(where: { $0.notchDisplayID == id }) else { return }
            self.move(to: screen)
            self.open()
        }
    }

    private var screenEdgeClickArea: CGRect? {
        guard running, !suspended, !expanded, captureControls == nil, notice == nil,
              !dragPlaceholder, !heldDrag, let panel, panel.isVisible, !panel.ignoresMouseEvents else { return nil }
        let geometry = compactActivityIsVisible ? compactActivityGeometry : self.geometry
        let area = geometry.activationArea(in: surfaceSize, hasHeader: peeking, compactActivity: compactActivityIsVisible)
        guard !area.isEmpty else { return nil }
        let frame = geometry.frame(for: surfaceSize)
        return CGRect(x: frame.minX + area.minX, y: frame.maxY - area.maxY, width: area.width, height: area.height)
    }

    private func syncScreenEdgeClicks() { screenEdgeClicks.sync() }

    private func removeScreenEdgeClickMonitors() { screenEdgeClicks.remove() }

    /// A press began on the menu bar above the island: hover waits for the release.
    private func screenEdgePressed() {
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: true)
    }

    /// Displays that share Spaces show the menu bar on the main one only.
    private var displayHasMenuBar: Bool {
        NSScreen.screensHaveSeparateSpaces || NSScreen.withMenuBar?.frame == geometry.screen
    }

    private func syncMenuSpaceMonitoring() {
        guard !hiddenInFullscreen else { menuSpace.stop(); return }
        // The explicit cover-menus choice also keeps a simulated island at
        // rest. Otherwise its visibility follows AX menu measurements, which
        // can change just because focus moves to another app or display.
        // A display without a menu bar, beside the main one when displays
        // share Spaces, has no menus to leave room for either.
        if running, !suspended, NotchSupport.coversMenus() || !displayHasMenuBar {
            // Nothing to measure: the island keeps the room an empty bar
            // would leave it, over whatever menus and status items are there.
            menuSpace.stop()
            applyMenuSpace(NotchMenuBarLayout.sideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                                       barHeight: geometry.menuBarHeight, occupied: []))
            return
        }
        guard AXIsProcessTrusted() else {
            menuSpace.stop()
            if geometry.compactSideRoom != nil {
                geometry.compactSideRoom = nil
                refreshPresentation(animated: false)
            }
            return
        }
        let wanted = running && !suspended && !hiddenUntilHover && !expanded && captureControls == nil
            && (idleContent != .none || compactActivity != nil || !geometry.isNotched)
        guard wanted else { menuSpace.stop(); return }
        menuSpace.start()
    }

    private func invalidateMenuSpace() {
        menuSpace.invalidate()
        // Keep the last measured layout until its replacement arrives, so a
        // switch does not blink; the read that follows withdraws the cutout
        // once the new menu bar reaches the camera.
        menuSpace.read()
    }

    private func screenParametersDidChange() {
        guard running, !suspended else { return }
        screenRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.screenRefreshWork = nil
            guard self.running, !self.suspended else { return }
            self.invalidateMenuSpace()
            self.syncWithPreferences()
        }
        screenRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func applyMenuSpace(_ room: CGFloat?) {
        guard geometry.compactSideRoom != room else { return }
        let previousSize = surfaceSize
        let grows = (room ?? 0) > (geometry.compactSideRoom ?? 0)
        geometry.compactSideRoom = room
        // Losing a safe center must also hide an unchanged bare cutout.
        if previousSize != surfaceSize || panel?.isVisible != true || room == nil {
            refreshPresentation(animated: grows)
        }
    }

    /// Only a laptop reports its lid, and only a laptop can lose its
    /// built-in screen while it keeps running.
    private static let hasLid = BrightnessService.lidClosed() != nil

    private var displayPreference: NotchDisplay {
        NotchDisplay(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchDisplay) ?? "") ?? .automatic
    }

    private func screenIndex(in screens: [NSScreen]) -> Int? {
        let preference = displayPreference
        var pointer: Int?
        if preference == .pointer || preference == .all {
            // The island stays on its display until it can follow the pointer.
            let mouse = NSEvent.mouseLocation
            pointer = screens.firstIndex { $0.notchDisplayID == displayID }
                ?? screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) }
        }
        return NotchSupport.screenIndex(
            preference: preference,
            builtIn: screens.map { CGDisplayIsBuiltin($0.notchDisplayID) != 0 },
            notched: screens.map { $0.safeAreaInsets.top > 0 },
            main: screens.firstIndex(where: { $0 === NSScreen.withMenuBar }) ?? 0,
            pointer: pointer,
            hasLid: Self.hasLid)
    }

    /// With the chosen display away, as the built-in one with the lid closed,
    /// nothing keeps working for an island that cannot show. The Mac is still
    /// in use elsewhere, so a capture preview moves to its own window, and a
    /// finished timer waits to ring until the island can be dismissed again.
    private func withdrawFromMissingScreen() {
        let cancelCapture = captureControlsCancel
        endCaptureControls()
        cancelCapture?()
        let fallback = captureFallback
        clearCapture()
        tearDownPresentation()
        NotchTimerService.shared.suspend()
        // The keys go back to the system while nothing can show them.
        Self.collaborators.feedbackRoutingDidChange()
        fallback?()
    }

    private func updateScreen() {
        let screens = NSScreen.screens
        menuBarMeasurements.retainDisplays(screens.map(\.notchDisplayID))
        guard let index = screenIndex(in: screens) else { withdrawFromMissingScreen(); return }
        let screen = screens[index]
        displayID = screen.notchDisplayID
        var next = baseGeometry(for: screen)
        let sameMenuBar = next.hasSameMenuBar(as: geometry)
        if sameMenuBar { next.compactSideRoom = geometry.compactSideRoom }
        let access = NotchQuickAccessConfiguration.current()
        next.quickAccessBottomInset = access.hasBottom ? NotchQuickAccessLayout.gutter : 0
        headerShowsSectionsButton = !access.actions.contains(.explore)
        if next != geometry { menuSpace.invalidate(); geometry = next }
        // A new camera or bar, such as a notch fit being adjusted, measures the
        // menus again at once rather than leaving the wings off until the timer.
        if !sameMenuBar { menuSpace.read() }
        if windowHost == nil {
            windowHost = NotchWindowHost(content: ServiceViews.factory.notch(self), geometry: geometry, size: surfaceSize,
                                        background: { ServiceViews.factory.notchBackground($0) },
                                        quickAccess: { ServiceViews.factory.notchQuickAccess(self, motion: $0, backdrop: $1) })
            windowHost?.missionControlDidRestore = { [weak self] in self?.missionControlDidRestore() }
            windowHost?.setHoverHandler { [weak self] in self?.hover($0) }
            panel?.title = FeatureStrings.notch(L10n.shared.language).title
        }
        if modules.contains(.files), AppFeature.shelf.isAvailable {
            windowHost?.setFileDropActions(NotchFileDropActions(
                canAccept: { [weak self] pasteboard in
                    self?.canAcceptFileDrop == true && Self.collaborators.shelfCanAccept(pasteboard)
                },
                enter: { [weak self] in self?.beginFileDrop($0) },
                accept: { [weak self] in self?.accept($0) == true },
                exit: { [weak self] in
                    guard let self else { return }
                    self.endFileDrop()
                    self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
                },
                update: { [weak self] in self?.updateFileDrop(at: $0) == true }))
        } else { windowHost?.setFileDropActions(nil) }
        panel?.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
        updateFullscreenVisibility(displayID: screen.notchDisplayID)
    }

    /// The island's geometry on a display, before its menus are measured.
    private func baseGeometry(for screen: NSScreen) -> NotchGeometry {
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else { cameraWidth = 0 }
        return NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                             cameraWidth: cameraWidth,
                             layout: NotchSize(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchSize) ?? "") ?? .spacious,
                             menuBarHeight: menuBarMeasurements.height(
                                displayID: screen.notchDisplayID, frame: screen.frame,
                                visibleTop: screen.visibleFrame.maxY, scale: screen.backingScaleFactor,
                                statusBarThickness: NSStatusBar.system.thickness),
                             customWidth: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomWidth),
                             customHeight: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomHeight),
                             cameraFit: NotchCameraFit.current(), silhouette: NotchSilhouette.current(),
                             capsuleFit: NotchCapsuleFit.current(),
                             outline: UserDefaults.standard.bool(forKey: DefaultsKey.notchOutlineEnabled))
    }

    private func updateFullscreenVisibility(displayID: CGDirectDisplayID) {
        let hidden = UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)
            && SpaceWindowBridge.topology()?.isFullscreen(on: displayID, separateSpaces: NSScreen.screensHaveSeparateSpaces) == true
        guard hidden != hiddenInFullscreen else { return }
        hiddenInFullscreen = hidden
        if hidden {
            hoverWork?.cancel(); hoverWork = nil
            hoverEmphasized = false
            heldDrag = false
            dragPlaceholder = false
            cancelCaptureControls()
            noticeWork?.cancel(); noticeWork = nil
            endDeparture()
            notice = nil
            noticeExpanded = false
            collapse()
        }
        // Space changes do not run a full preference sync. Restore volume
        // and brightness key routing when the island becomes eligible for
        // feedback again, and hand the keys back while it is away.
        Self.collaborators.feedbackRoutingDidChange()
    }

    private func fullscreenEnvironmentDidChange() {
        // Only the opt-in option depends on Spaces and the active app.
        guard running, !suspended,
              hiddenInFullscreen || UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)
        else { return }
        let wasHidden = hiddenInFullscreen
        updateScreen()
        // Each copy follows full screen on its own display.
        updateFullscreenDisplays()
        syncMirrors()
        // An unchanged state must not cut short a transition on screen, such
        // as the island closing after a click in another app.
        guard hiddenInFullscreen != wasHidden else { return }
        syncVisibleConsumers()
        refreshPresentation(animated: false)
    }

    private func installObservers() {
        observe(.default, NSMenu.didBeginTrackingNotification) { [weak self] in
            guard let self else { return }
            self.activityPickerMenuOpen = self.showsCompactActivityPicker
            self.trackingMenu = true
            self.hoverWork?.cancel()
        }
        observe(.default, NSMenu.didEndTrackingNotification) { [weak self] in
            guard let self else { return }
            self.trackingMenu = false
            self.activityPickerMenuOpen = false
            self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
            self.refreshPresentation()
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.screenParametersDidChange()
        }
        observe(.default, UserDefaults.didChangeNotification) { [weak self] in
            self?.schedulePreferenceSync()
        }
        observe(.default, .menuPanelWillShow) { [weak self] in self?.collapse() }
        observe(.default, NSWindow.didBecomeKeyNotification) { [weak self] in self?.syncPanelKey() }
        observe(.default, NSWindow.didResignKeyNotification) { [weak self] in self?.syncPanelKey() }
        let current = NotchSessionTracker.current()
        session.onConsole = current.onConsole
        session.locked = current.locked
        sessionTracker.start { [weak self] change in self?.updateSession(change) }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in
            self?.schedulePreferenceSync()
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.fullscreenEnvironmentDidChange()
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.applicationDidActivate() }
    }

    /// AppStorage can notify during drawing. A preference import or a group
    /// of edits only needs one deferred pass over the final saved settings.
    private func schedulePreferenceSync() {
        guard running, preferenceSyncWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.preferenceSyncWork = nil
            guard self.running else { return }
            self.syncWithPreferences()
        }
        preferenceSyncWork = work
        DispatchQueue.main.async(execute: work)
    }

    private func applicationDidActivate() {
        guard !suspended else { return }
        fullscreenEnvironmentDidChange()
        invalidateMenuSpace()
        let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard identifier != Bundle.main.bundleIdentifier, identifier != AssistiveKeyboard.bundleID else { return }
        panel?.resignKey()
        if expanded, modules.contains(.clipboard) { ClipboardHistoryService.shared.rememberPasteTarget() }
        if expanded, !pinned, !keepsWorkingSurface, captureControls == nil,
           NotchSupport.closesOnActivation(openedByHover: openedByHover, clicked: clickedSinceOpening,
                                           pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true) {
            collapse()
        }
    }

    private func syncPanelKey() {
        let isKey = panel?.isKeyWindow == true
        if panelIsKey != isKey { panelIsKey = isKey }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    private func updateSession(_ change: (inout NotchSessionState) -> Void) {
        guard running else { return }
        let couldPresent = session.canPresent
        let timerCouldRun = session.canRunTimer
        let wasLocked = session.locked
        change(&session)
        // An unlock is someone at the Mac, even when the display's wake is
        // announced after it.
        if session.locked != wasLocked, session.locked ? session.hearsLockChange : session.onConsole,
           NotchLockScreenSupport.playsSounds() {
            NotchLockScreenService.shared.playSound(locking: session.locked)
        }
        if couldPresent != session.canPresent {
            if session.canPresent {
                syncWithPreferences()
            } else {
                let cancel = captureControlsCancel
                endCaptureControls()
                cancel?()
                captureClose?()
                clearCapture()
                tearDownPresentation()
                // The keys go back to the system while nothing can show them.
                Self.collaborators.feedbackRoutingDidChange()
            }
        }
        // After the island's own teardown or return: what the lock screen
        // starts is not stopped under it, and what the island takes back is
        // not stopped as the lock screen leaves.
        NotchLockScreenService.shared.sync(session)
        // A dark display does not stop an alarm while the same user and Mac
        // remain awake. Privacy changes still apply when presentation is
        // already suspended by the display.
        guard timerCouldRun != session.canRunTimer, !session.canPresent else { return }
        if session.canRunTimer { NotchTimerService.shared.syncWithPreferences() }
        else { NotchTimerService.shared.suspend() }
    }

    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        clickedSinceOpening = false
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            guard let self, !self.keepsWorkingSurface,
                  self.windowHost?.contains(NSEvent.mouseLocation) != true,
                  MainActor.assumeIsolated { appShell()?.isOverStatusItem(NSEvent.mouseLocation) } != true,
                  !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) else { return }
            self.collapse()
        }) { eventMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            // While an input method is composing, Esc belongs to it and
            // drops the candidate; the island takes the next one.
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 53,
               (self.panel?.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
            if event.type == .keyDown, event.window === self.panel, self.captureControls == nil {
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
                    self.toggleSections()
                    return nil
                }
                if modifiers == [.command, .option],
                   let module = NotchSupport.moduleShortcut(event.charactersIgnoringModifiers ?? "", modules: self.modules) {
                    self.select(module)
                    return nil
                }
                if event.keyCode == 48, modifiers == .control || modifiers == [.control, .shift],
                   let module = NotchSupport.adjacentModule(to: self.selected, modules: self.modules,
                                                           backwards: modifiers.contains(.shift)) {
                    self.select(module)
                    return nil
                }
                if event.keyCode == 53, self.showingSections {
                    self.toggleSections()
                    return nil
                }
                if self.handleSectionKey(event) { return nil }
                if self.handleScratchpadKey(event) { return nil }
                if self.handleClipboardPasteKey(event) { return nil }
            }
            if event.type == .keyDown, event.window === self.panel, self.selected == .tools, !self.showingAppPanel, !self.showingSections {
                let launcher = QuickLauncherService.shared
                // The rail reads across its rows until it scrolls, in the
                // rows the open page leaves it below its header; the editing
                // grid keeps its own rows.
                let flow: QuickToolsSupport.GridFlow = launcher.isEditing
                    ? .rows(columns: NotchSupport.toolColumns)
                    : self.expandedGeometry.toolFlow(count: launcher.visibleItems.count)
                return launcher.handlePanelKey(event, flow: flow)
            }
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 53 {
                // A level being typed in the mixer cancels on Escape by
                // itself, and the scratchpad's find bar closes on it; the
                // next one steps back.
                if let editor = self.panel?.firstResponder as? NSTextView, editor.isFieldEditor,
                   (editor.delegate as AnyObject?) is MixerPercentNativeTextField { return event }
                if PlainTextEditor.findBarHasKeyboard(in: self.panel) { return event }
                self.stepBack()
                return nil
            }
            let click = clicks.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue))
            let islandWindow = self.ownsWindow(event.window)
            if click, islandWindow { self.clickedSinceOpening = true }
            if click, !islandWindow, !self.keepsWorkingSurface,
               self.windowHost?.contains(NSEvent.mouseLocation) != true,
               MainActor.assumeIsolated { appShell()?.isOverStatusItem(NSEvent.mouseLocation) } != true,
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) { self.collapse() }
            return event
        }) { eventMonitors.append(token) }
    }

    /// The panel and what hangs from it: a SwiftUI popover opened in the
    /// island is a child window, so a click in it is not a click away.
    private func ownsWindow(_ window: NSWindow?) -> Bool {
        guard let window, let panel else { return false }
        return sequence(first: window, next: { $0.parent }).contains { $0 === panel }
    }

    private func pointerOverChildWindow(_ point: CGPoint) -> Bool {
        panel?.childWindows?.contains { $0.isVisible && $0.frame.contains(point) } == true
    }

    private func syncGestures() {
        if !NotchGestureSupport.isEnabled() { gesture = NotchGestureSupport() }
        panel?.handleScroll = { [weak self] event in self?.handleScroll(event) ?? false }
    }

    /// The gallery steps its rows from the wheel; every other scroll over the
    /// island is a gesture candidate.
    private func handleScroll(_ event: NSEvent) -> Bool {
        handleSectionScroll(event) || handleGesture(event)
    }

    private func handleSectionScroll(_ event: NSEvent) -> Bool {
        guard running, !suspended, expanded, showingSections, let panel, !trackingMenu,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            sectionScroll = NotchSectionScroll()
            return false
        }
        let screenPoint = panel.convertPoint(toScreen: event.locationInWindow)
        // The header keeps its own gesture; the tiles and the rest of the body step rows.
        guard windowHost?.containsSurface(screenPoint) == true,
              panel.frame.maxY - screenPoint.y > expandedGeometry.headerBottom else {
            sectionScroll = NotchSectionScroll()
            return false
        }
        let steps = sectionScroll.steps(deltaY: Double(event.scrollingDeltaY), timestamp: event.timestamp,
                                        precise: event.hasPreciseScrollingDeltas, hasPhase: !event.phase.isEmpty,
                                        began: event.phase.contains(.began),
                                        ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                                        momentum: !event.momentumPhase.isEmpty)
        if steps != 0 { scrollSections(by: steps) }
        return true
    }

    private func handleGesture(_ event: NSEvent) -> Bool {
        guard running, !suspended, NotchGestureSupport.isEnabled(), let panel,
              !trackingMenu, captureControls == nil, !heldDrag,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            gesture = NotchGestureSupport()
            return false
        }
        let screenPoint = panel.convertPoint(toScreen: event.locationInWindow)
        guard windowHost?.contains(screenPoint) == true else { gesture = NotchGestureSupport(); return false }
        let fromTop = panel.frame.maxY - screenPoint.y
        let inHeader = NotchSupport.gestureIsOverHeader(expanded: expanded, peeking: peeking,
                                                       fromTop: fromTop, safeTop: expanded ? expandedGeometry.headerTopInset : geometry.safeContentTop,
                                                       height: expanded ? expandedGeometry.headerRowHeight : NotchLayout.headerHeight)
        let interaction = NotchGestureSupport.nativeInteraction(at: panel.contentView?.hitTest(event.locationInWindow))
        let musicSurface = modules.contains(.music)
            && (compactMusicIsVisible || (expanded && selected == .music && !showingAppPanel && !showingSections))
        let vertical = NotchGestureSupport.allowsVertical(expanded: expanded, inHeader: inHeader,
                                                          musicSurface: musicSurface,
                                                          control: interaction.control, scroll: interaction.scroll)
        let horizontal = !interaction.control && !interaction.scroll && !inHeader && musicSurface
        let x = NotchGestureSupport.movement(Double(event.scrollingDeltaX), precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
        let y = NotchGestureSupport.movement(Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
        guard let action = gesture.handle(x: x, y: y, timestamp: event.timestamp,
                                          began: event.phase.contains(.began),
                                          ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                                          momentum: !event.momentumPhase.isEmpty,
                                          precise: event.hasPreciseScrollingDeltas,
                                          hasPhase: !event.phase.isEmpty,
                                          allowVertical: vertical, allowHorizontal: horizontal, expanded: expanded) else { return false }
        switch action {
        case .open: open()
        case .close: collapse()
        case .nextTrack, .previousTrack:
            guard musicSurface else { gesture = NotchGestureSupport(); return false }
            NotchMusicService.shared.skipFromGesture(forward: action == .nextTrack)
        }
        return true
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    package func showUpdate() {
        // UI passes this as the update control's action, which runs on the main thread.
        let offered = MainActor.assumeIsolated {
            if case .available = UpdateService.shared.state { return true }
            return false
        }
        guard running, !suspended, expanded, offered else { return }
        collapse()
        MainActor.assumeIsolated { appShell()?.showUpdatePreview() }
    }

    private func bindEvents() {
        subscriptions.removeAll()
        if modules.contains(.timer) {
            NotchTimerService.shared.$session.removeDuplicates().receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.watch) {
            // The strip resizes with its reading, and when the area turns
            // out to hold only a picture.
            let watch = NotchWatchService.shared
            Publishers.CombineLatest3(watch.$state.removeDuplicates(), watch.$headline.removeDuplicates(),
                                      watch.$preview.map { $0 != nil }.removeDuplicates())
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.music) {
            let music = NotchMusicService.shared
            music.$playback.combineLatest(music.$artwork, music.$artworkTint)
                .sink { [weak self] playback, artwork, tint in
                    // @Published sends before storing the new value. Keep the last
                    // visible track and cover before playback disappears.
                    guard playback != nil else { return }
                    self?.rememberPresentedMusic(playback: playback, artwork: artwork, tint: tint)
                }.store(in: &subscriptions)
            // Received at once, before the reading that ends the song is
            // published, so the strip leaves as its own song, cover included.
            music.trackEnds
                .sink { [weak self] in self?.holdEndingTrack() }
                .store(in: &subscriptions)
            music.$playback.map { ($0 != nil, $0?.isPlaying == true) }
                .removeDuplicates { $0 == $1 }.receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
            // A capsule names each new song for a moment: the song playing,
            // or the next one once the notice releases the song it held.
            music.$playback.map { $0?.track.title }.removeDuplicates().map { _ in () }
                .merge(with: $heldMusic.map { $0?.playback.track.title }.removeDuplicates().map { _ in () })
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.nameCapsuleSong() }
                .store(in: &subscriptions)
        }
        if NotchSupport.routes(.track) {
            // Received at once, on the main thread, while the strip still
            // shows the previous song.
            NotchMusicService.shared.trackChanges
                .sink { [weak self] in self?.scheduleTrackNotice() }
                .store(in: &subscriptions)
        }
        if modules.contains(.tools) {
            // The tools page is a rail sized by its tiles; editing or a
            // hosted utility turns it into a page.
            let launcher = QuickLauncherService.shared
            launcher.$isEditing.map { _ in () }
                .merge(with: launcher.$activeUtility.map { _ in () }, launcher.$hiddenItemsRaw.map { _ in () })
                .dropFirst(3).receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    guard let self, self.expanded, self.selected == .tools, !self.showingAppPanel, !self.showingSections else { return }
                    self.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.system), AppFeature.fanControl.isAvailable {
            // The fan card only exists once the page's first sample lands; the
            // strip that was sized without it reserves its row again.
            SystemMonitor.shared.$snapshot.map { $0.fanSpeeds.isEmpty }.removeDuplicates().dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self, self.expanded, self.selected == .system, self.selectedMetric == nil,
                          !self.showingAppPanel, !self.showingSections else { return }
                    self.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.download) {
            NotchDownloadService.shared.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.syncMenuSpaceMonitoring()
                self?.objectWillChange.send()
                self?.refreshPresentation()
            }.store(in: &subscriptions)
            NotchDownloadService.shared.onArrival = { [weak self] item in
                self?.show(NotchNotice(event: .download,
                    title: FeatureStrings.notchFiles(L10n.shared.language).completed,
                    detail: item.name, symbol: "arrow.down.circle.fill"))
            }
        }
        if modules.contains(.agents) {
            // Only what changes the island's size or strip: a turn starting or
            // ending, the first read landing, which agents have cards, and
            // which are working, since each one's mark widens the strip.
            AgentUsageService.shared.$snapshot
                .map { ($0.loaded, $0.live.isEmpty, $0.seen, Set($0.live.map(\.provider))) }
                .removeDuplicates(by: ==)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.calendar) {
            NotchCalendarService.shared.$countdown.removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if NotchKeepAwakeSupport.showsActivity() {
            // A session starting or ending, or its end moving, which can
            // change the reading and the wings it needs.
            let awake = KeepAwakeManager.shared
            awake.$isActive.combineLatest(awake.$endDate).removeDuplicates { $0 == $1 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.agents) {
            AgentUsageService.shared.events.receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.showAgentEvent($0) }
                .store(in: &subscriptions)
        }
        stopPower()
        if NotchSupport.routes(.volume) {
            bindVolumeEvents()
        }
        if NotchSupport.routes(.systemNotification) {
            NotchNotificationService.shared.received.sink { [weak self] item in
                guard let self else { return }
                let shown = self.show(NotchNotice(event: .systemNotification, title: item.content.title,
                                                 detail: item.content.body, symbol: "bell.fill", notification: item.content, notificationID: item.id))
                if shown, !self.expanded, self.captureControls == nil, !self.dragPlaceholder {
                    NotchNotificationService.shared.hideNative(item.id)
                }
            }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.clipboard) {
            let history = ClipboardHistoryService.shared
            history.capturedEntry.receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let text = FeatureStrings.clipboard(L10n.shared.language)
                self.show(NotchNotice(event: .clipboard, title: text.copied,
                                      detail: text.title, symbol: "doc.on.clipboard"))
            }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.battery) || idleContent == .battery { startPower() }
    }

    private func showAgentEvent(_ event: AgentUsageEvent) {
        let text = FeatureStrings.notchAgents(L10n.shared.language)
        let locale = L10n.shared.language.formattingLocale()
        let remaining = NotchAgentSupport.limitDisplay() == .remaining
        func window(_ window: AgentLimitWindow) -> String {
            switch window.kind {
            case .session: return text.session
            case .weekly: return window.scope.map { "\(text.weekly) · \($0)" } ?? text.weekly
            case .other: return window.minutes.map { AgentFormat.duration(TimeInterval($0) * 60, locale: locale, units: 1) }
                ?? text.readoutLimit
            }
        }
        switch event {
        case .finished(let provider, let duration, let cost, _, _):
            show(NotchNotice(event: .agents, title: text.finished(provider.displayName),
                             detail: [AgentFormat.duration(duration, locale: locale), cost > 0 ? AgentFormat.cost(cost) : ""]
                                .filter { !$0.isEmpty }.joined(separator: " · "),
                             symbol: provider.symbol, agent: provider))
        case .limitWarning(let provider, let limit):
            let share = AgentFormat.percent(remaining ? limit.remainingFraction : limit.usedFraction)
            show(NotchNotice(event: .agents, title: "\(provider.displayName) · \(window(limit))",
                             detail: remaining ? text.left(share) : text.usedShare(share),
                             symbol: "exclamationmark.triangle.fill", agent: provider))
        case .limitReset(let provider, let limit):
            show(NotchNotice(event: .agents, title: "\(provider.displayName) · \(window(limit))",
                             detail: text.limitRenewed, symbol: "arrow.clockwise", agent: provider))
        case .budgetReached(let spent, _):
            show(NotchNotice(event: .agents, title: text.budgetTitle, detail: AgentFormat.cost(spent),
                             symbol: "dollarsign.circle.fill"))
        }
    }

    package func showCurrentVolume() {
        let mixer = AppVolumeMixer.shared
        guard let volume = mixer.systemOutputVolume else { return }
        showVolume(volume, muted: mixer.systemOutputMuted)
    }

    /// The island's own output controls already show the level they set.
    /// Their changes, and the device's reading that follows, leave the open
    /// header's title in place instead of covering it with the same level.
    package func noteOwnVolumeAdjustment() {
        ownVolumeAdjustmentUntil = ProcessInfo.processInfo.systemUptime + 1
    }

    private func bindVolumeEvents() {
        let mixer = AppVolumeMixer.shared
        volumeDeviceUID = mixer.currentOutputDeviceUID
        volumeBaseline = mixer.systemOutputVolume
        muteBaseline = mixer.systemOutputMuted
        mixer.$systemOutputVolume.combineLatest(mixer.$systemOutputMuted, mixer.$currentOutputDeviceUID)
            .handleEvents(receiveOutput: { [weak self] _, _, deviceUID in
                guard let self, deviceUID != self.volumeDeviceUID else { return }
                self.volumeDeviceUID = deviceUID
                self.volumeBaseline = nil
                self.muteBaseline = nil
            })
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mixer] _ in
                guard let mixer else { return }
                // Published fields arrive separately and before assignment. Read
                // the settled device and controls together on the main queue.
                self?.volumeChanged(mixer.systemOutputVolume, muted: mixer.systemOutputMuted)
            }
            .store(in: &subscriptions)
    }

    private func volumeChanged(_ volume: Double?, muted: Bool?) {
        defer { volumeBaseline = volume; muteBaseline = muted }
        guard volumeDeviceUID != nil, let volume, volumeBaseline != nil,
              volume != volumeBaseline || (muteBaseline != nil && muted != muteBaseline) else { return }
        // Volume keys still announce themselves through showCurrentVolume.
        guard !expanded || ProcessInfo.processInfo.systemUptime >= ownVolumeAdjustmentUntil else { return }
        showVolume(volume, muted: muted)
    }

    /// Levels set outside the island, like Command Bar's, report here
    /// too. The observer skips a level that matches the current one and a new
    /// output's first reading. False leaves the confirmation to the caller.
    @discardableResult
    package func showVolume(_ volume: Double, muted: Bool? = nil) -> Bool {
        guard volume.isFinite else { return false }
        let value = muted == true ? 0 : min(1, max(0, volume))
        return show(NotchNotice(event: .volume, title: FeatureStrings.notch(L10n.shared.language).volume,
                                detail: "\(Int((value * 100).rounded()))%",
                                symbol: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", level: value))
    }

    private func startPower() {
        guard PowerSampler.hasInternalBattery else { return }
        powerSampler = PowerSampler(smc: nil)
        power = powerSampler?.sample() ?? PowerReading()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let owner = Unmanaged<NotchService>.fromOpaque(context).takeUnretainedValue()
            owner.powerChanged()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func stopPower() {
        if let source = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        powerSource = nil
        powerSampler = nil
    }

    private func powerChanged() {
        guard running, !suspended, let sampler = powerSampler else { return }
        let before = power
        let next = sampler.sample()
        power = next
        let low = (next.chargePercent ?? 100) <= 20 && (before.chargePercent ?? 0) > 20
        guard before.externalConnected != next.externalConnected || low
                || (before.isCharging && !next.isCharging && next.chargePercent == 100) else { return }
        let text = FeatureStrings.notch(L10n.shared.language)
        let title = low ? text.lowBattery : next.externalConnected
            ? (next.isCharging ? text.charging : next.chargePercent == 100
                ? text.charged : L10n.shared.s.powerPluggedIn) : text.onBattery
        show(NotchNotice(event: .battery, title: title,
                         detail: next.chargePercent.map { "\($0)%" } ?? "",
                         symbol: next.externalConnected ? "battery.100percent.bolt" : "battery.25percent"))
    }

    private func syncVisibleConsumers() {
        syncMenuSpaceMonitoring()
        guard running, !suspended else { releaseMonitor(); return }
        if fullscreenCompact {
            CameraPreviewService.shared.hideEmbedded()
            // A copy on another display still shows the song playing.
            let copiesShowMusic = showsCopies && NotchSupport.watchesMusicActivity()
            if copiesShowMusic { NotchMusicService.shared.start() } else { NotchMusicService.shared.stop() }
            releaseMonitor()
            return
        }
        if !NotchCameraSupport.canPresent(expanded: expanded && !showingSections, selected: selected,
            appPanel: showingAppPanel, captureControls: captureControls != nil) {
            CameraPreviewService.shared.hideEmbedded()
        }
        let musicWanted = modules.contains(.music) && ((expanded && (selected == .music || (selected == .controls && NotchSupport.controls().contains(.music)))
            && !showingAppPanel && !showingSections)
            || (!hiddenUntilHover && (NotchSupport.watchesMusicActivity() || NotchSupport.routes(.track))))
        if musicWanted { NotchMusicService.shared.start() } else { NotchMusicService.shared.stop() }
        let needs = expanded && selected == .system && selectedMetric == nil && modules.contains(.system) && !showingAppPanel && !showingSections
        var detailNeeds = expanded && !showingSections ? selectedMetric?.monitorNeeds ?? .none : .none
        if needs, AppFeature.monitorDisk.isAvailable { detailNeeds.disk = true }
        if needs, AppFeature.fanControl.isAvailable { detailNeeds.fanSpeed = true }
        SystemMonitor.shared.setNotchDetailNeeds(detailNeeds)
        if needs != notchNeedsMonitor {
            notchNeedsMonitor = needs
            SystemMonitor.shared.setNotchVisible(needs)
        }
    }

    private func releaseMonitor() {
        SystemMonitor.shared.setNotchDetailNeeds(.none)
        guard notchNeedsMonitor else { return }
        notchNeedsMonitor = false
        SystemMonitor.shared.setNotchVisible(false)
    }
}

extension NSScreen {
    package var notchDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
