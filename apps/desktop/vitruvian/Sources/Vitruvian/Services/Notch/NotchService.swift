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
    /// What the island reads from outside itself. The app passes `.system`.
    package struct Environment {
        /// The preferences the island follows.
        package var defaults: UserDefaults
        /// Builds the window that draws the island, at its geometry and size.
        package var makeHost: @MainActor (NotchService, NotchGeometry, CGSize) -> any NotchIslandHost
        /// Where the pointer is, in screen coordinates.
        package var pointer: @MainActor () -> CGPoint
        /// The Reduce Motion accessibility setting.
        package var reducesMotion: @MainActor () -> Bool
        /// Runs work on the main queue after a delay, in seconds.
        package var schedule: @MainActor (TimeInterval, DispatchWorkItem) -> Void
        /// The services the island reads, starts, stops and asks to act.
        package var services: any NotchIslandServices

        package init(defaults: UserDefaults,
                     makeHost: @escaping @MainActor (NotchService, NotchGeometry, CGSize) -> any NotchIslandHost,
                     pointer: @escaping @MainActor () -> CGPoint,
                     reducesMotion: @escaping @MainActor () -> Bool,
                     schedule: @escaping @MainActor (TimeInterval, DispatchWorkItem) -> Void,
                     services: any NotchIslandServices) {
            self.defaults = defaults
            self.makeHost = makeHost
            self.pointer = pointer
            self.reducesMotion = reducesMotion
            self.schedule = schedule
            self.services = services
        }

        @MainActor package static var system: Environment {
            Environment(
                defaults: .standard,
                makeHost: { island, geometry, size in
                    NotchWindowHost(content: ServiceViews.factory.notch(island), geometry: geometry, size: size,
                                    background: { ServiceViews.factory.notchBackground($0) },
                                    quickAccess: { ServiceViews.factory.notchQuickAccess(island, motion: $0, backdrop: $1) })
                },
                pointer: { NSEvent.mouseLocation },
                reducesMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
                schedule: { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) },
                services: SystemNotchIslandServices())
        }
    }

    package static let shared = NotchService(environment: .system)
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

    private var windowHost: (any NotchIslandHost)?
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
            acceptsUserInteraction: { [weak self] in self?.acceptsUserInteraction ?? false },
            capturing: { [weak self] in self?.captureControls != nil },
            showsFiles: { [weak self] in self?.modules.contains(.files) == true },
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
    /// What the island hears from the services it shows (`NotchEventBindings`).
    private lazy var eventBindings: NotchEventBindings = NotchEventBindings(
        sources: .system(),
        island: NotchEventBindings.Island(
            resize: { [weak self] in
                self?.syncMenuSpaceMonitoring()
                self?.objectWillChange.send()
                self?.refreshPresentation()
            },
            rememberMusic: { [weak self] in self?.rememberPresentedMusic(playback: $0, artwork: $1, tint: $2) },
            holdEndingTrack: { [weak self] in self?.holdEndingTrack() },
            nameSong: { [weak self] in self?.nameCapsuleSong() },
            trackChanged: { [weak self] in self?.scheduleTrackNotice() },
            toolsChanged: { [weak self] in
                guard let self, self.expanded, self.selected == .tools, !self.showingAppPanel, !self.showingSections else { return }
                self.refreshPresentation()
            },
            fanCardChanged: { [weak self] in
                guard let self, self.expanded, self.selected == .system, self.selectedMetric == nil,
                      !self.showingAppPanel, !self.showingSections else { return }
                self.refreshPresentation()
            },
            downloadArrived: { [weak self] item in
                self?.show(NotchNotice(event: .download,
                    title: FeatureStrings.notchFiles(L10n.shared.language).completed,
                    detail: item.name, symbol: "arrow.down.circle.fill"))
            },
            agentEvent: { [weak self] in self?.showAgentEvent($0) },
            systemNotification: { [weak self] item in
                guard let self else { return false }
                let shown = self.show(NotchNotice(event: .systemNotification, title: item.content.title,
                                                 detail: item.content.body, symbol: "bell.fill", notification: item.content, notificationID: item.id))
                return shown && !self.expanded && self.captureControls == nil && !self.dragPlaceholder
            },
            clipboardCaptured: { [weak self] in
                guard let self else { return }
                let text = FeatureStrings.clipboard(L10n.shared.language)
                self.show(NotchNotice(event: .clipboard, title: text.copied,
                                      detail: text.title, symbol: "doc.on.clipboard"))
            }))
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
            || services.importingLyrics
            // Like the lyrics chooser, these panels stand beside the island
            // instead of hanging from it; a click in them is not a click away.
            || (expanded && MediaPanelModal.panelModalActive)
            || (expanded && selected == .downloads && services.choosingDownloadFolder)
            || (expanded && selected == .scratchpad && services.scratchpadModal)
            || (expanded && !showingSections && selected == .calendar && services.keepsCalendarPrompt)
            || (expanded && !showingSections && selected == .files && fileInteractionActive)
            || services.keepsCameraPrompt
            || (expanded && !showingSections && selected == .captures && captureContent != nil)
            || (expanded && !showingSections && selected == .tools && (services.activeUtility != nil || services.editingTools))
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
    private lazy var volumeFeedback: NotchVolumeFeedback = NotchVolumeFeedback(output: .system, island: .init(
        isExpanded: { [weak self] in self?.expanded ?? false },
        show: { [weak self] in self?.show($0) ?? false },
        uptime: { ProcessInfo.processInfo.systemUptime }))
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
            hidesUntilHover: { [defaults] in NotchSupport.hidesUntilHover(in: defaults) },
            coversMenus: { [defaults] in NotchSupport.coversMenus(in: defaults) },
            showsInCaptures: { [defaults] in NotchSupport.showsInCaptures(in: defaults) },
            outlineEnabled: { [defaults] in defaults.bool(forKey: DefaultsKey.notchOutlineEnabled) },
            hidesInFullscreen: { [defaults] in defaults.bool(forKey: DefaultsKey.notchHideInFullscreen) },
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
        activate: { [weak self] id in self?.summons.bring(to: id) })
    /// A click on a copy bringing the island to its display (`NotchIslandSummons`).
    private lazy var summons: NotchIslandSummons = NotchIslandSummons(island: .init(
        showsCopies: { [weak self] in self.map { $0.running && !$0.suspended && $0.showsOnAllDisplays } ?? false },
        displayID: { [weak self] in self?.displayID },
        isOpen: { [weak self] in self.map { $0.expanded || $0.peeking } ?? false },
        collapse: { [weak self] in self?.collapse() },
        whenSettled: { [weak self] action in
            // Copies are clicked on the main thread, so `action` never leaves it.
            nonisolated(unsafe) let action = action
            self?.windowHost?.whenSettled { action() }
        },
        canMove: { [weak self] in self.map { $0.running && !$0.suspended && $0.canFollowPointer } ?? false },
        move: { [weak self] id in
            guard let self, let screen = NSScreen.screens.first(where: { $0.notchDisplayID == id }) else { return false }
            self.move(to: screen)
            return true
        },
        open: { [weak self] in self?.open() }))
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
            whenSettled: { [weak self] action in
                // The follower runs on the main thread, so `action` never leaves it.
                nonisolated(unsafe) let action = action
                self?.windowHost?.whenSettled { action() }
            },
            move: { [weak self] id in
                guard let self, let screen = NSScreen.screens.first(where: { $0.notchDisplayID == id }) else { return }
                self.move(to: screen)
            }))

    /// The deferred refreshes, the menu reader's schedule, activations and
    /// moves between displays (`NotchScreenRefresh`).
    private lazy var screenRefresh: NotchScreenRefresh = NotchScreenRefresh(
        environment: .system,
        island: NotchScreenRefresh.Island(
            running: { [weak self] in self?.running ?? false },
            suspended: { [weak self] in self?.suspended ?? true },
            hiddenInFullscreen: { [weak self] in self?.hiddenInFullscreen ?? false },
            hiddenUntilHover: { [weak self] in self?.hiddenUntilHover ?? false },
            expanded: { [weak self] in self?.expanded ?? false },
            peeking: { [weak self] in self?.peeking ?? false },
            showsNotice: { [weak self] in self?.notice != nil },
            showsCaptureControls: { [weak self] in self?.captureControls != nil },
            holdsDrag: { [weak self] in self?.heldDrag ?? false },
            choosingFileDropDestination: { [weak self] in self?.choosingFileDropDestination ?? false },
            keepsWorkingSurface: { [weak self] in self?.keepsWorkingSurface ?? false },
            holdsMusic: { [weak self] in self?.heldMusic != nil },
            pinned: { [weak self] in self?.pinned ?? false },
            openedByHover: { [weak self] in self?.openedByHover ?? false },
            clickedSinceOpening: { [weak self] in self?.clickedSinceOpening ?? false },
            showsClipboard: { [weak self] in self?.modules.contains(.clipboard) ?? false },
            idleContent: { [weak self] in self?.idleContent ?? .none },
            hasCompactActivity: { [weak self] in self?.compactActivity != nil },
            geometry: { [weak self] in self?.geometry ?? NotchGeometry(screen: .zero, safeAreaTop: 0, cameraWidth: 0) },
            displayHasMenuBar: { [weak self] in self?.displayHasMenuBar ?? false },
            containsHover: { [weak self] in self?.windowHost?.containsHover($0) == true },
            syncWithPreferences: { [weak self] in self?.syncWithPreferences() },
            fullscreenEnvironmentDidChange: { [weak self] in self?.fullscreenEnvironmentDidChange() },
            applyMenuSpace: { [weak self] in self?.applyMenuSpace($0) },
            withdrawMenuSpace: { [weak self] in
                guard let self else { return }
                self.geometry.compactSideRoom = nil
                self.refreshPresentation(animated: false)
            },
            refreshPresentation: { [weak self] in self?.refreshPresentation(animated: false) },
            resignKey: { [weak self] in self?.panel?.resignKey() },
            rememberPasteTarget: { [services] in services.rememberPasteTarget() },
            collapse: { [weak self] in self?.collapse() },
            takeDisplay: { [weak self] id in
                self?.displayID = id
                self?.updateScreen()
            },
            syncVisibleConsumers: { [weak self] in self?.syncVisibleConsumers() },
            startMenuSpace: { [weak self] in self?.menuSpace.start() },
            stopMenuSpace: { [weak self] in self?.menuSpace.stop() },
            invalidateMenuSpace: { [weak self] in self?.menuSpace.invalidate() },
            readMenuSpace: { [weak self] in self?.menuSpace.read() }))

    /// Stepping aside for a full-screen Space (`NotchFullscreenVisibility`).
    private lazy var fullscreen: NotchFullscreenVisibility = NotchFullscreenVisibility(
        environment: .system,
        island: NotchFullscreenVisibility.Island(
            hidden: { [weak self] in self?.hiddenInFullscreen ?? false },
            setHidden: { [weak self] in self?.hiddenInFullscreen = $0 },
            isActive: { [weak self] in self.map { $0.running && !$0.suspended } ?? false },
            cancelHover: { [weak self] in
                guard let self else { return }
                self.hoverWork?.cancel(); self.hoverWork = nil
                self.hoverEmphasized = false
            },
            releaseDrag: { [weak self] in
                self?.heldDrag = false
                self?.dragPlaceholder = false
            },
            cancelCaptureControls: { [weak self] in self?.cancelCaptureControls() },
            dismissNotice: { [weak self] in
                guard let self else { return }
                self.noticeWork?.cancel(); self.noticeWork = nil
                self.endDeparture()
                self.notice = nil
                self.noticeExpanded = false
            },
            collapse: { [weak self] in self?.collapse() },
            feedbackRoutingDidChange: { Self.collaborators.feedbackRoutingDidChange() },
            updateScreen: { [weak self] in self?.updateScreen() },
            updateFullscreenDisplays: { [weak self] in self?.updateFullscreenDisplays() },
            syncMirrors: { [weak self] in self?.syncMirrors() },
            syncVisibleConsumers: { [weak self] in self?.syncVisibleConsumers() },
            refreshPresentation: { [weak self] in self?.refreshPresentation(animated: false) }))

    /// The preferences the island follows (`Environment.defaults`).
    private let defaults: UserDefaults
    /// Builds the island's window (`Environment.makeHost`).
    private let makeHost: @MainActor (NotchService, NotchGeometry, CGSize) -> any NotchIslandHost
    /// The pointer, Reduce Motion and the main queue's timers (`Environment`).
    private let pointer: @MainActor () -> CGPoint
    private let reducesMotion: @MainActor () -> Bool
    private let schedule: @MainActor (TimeInterval, DispatchWorkItem) -> Void
    /// The services the island reads and drives (`Environment.services`).
    private let services: any NotchIslandServices

    package init(environment: Environment) {
        defaults = environment.defaults
        makeHost = environment.makeHost
        pointer = environment.pointer
        reducesMotion = environment.reducesMotion
        schedule = environment.schedule
        services = environment.services
    }

    private var hiddenUntilHover: Bool {
        !hiddenInFullscreen && defaults.bool(forKey: DefaultsKey.notchHideUntilHover)
            && defaults.bool(forKey: DefaultsKey.notchOpenOnHover)
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
        let content = NotchSupport.visibleIdleContent(isPlaying: !awaitsTrackNotice && services.playback?.isPlaying == true, in: defaults)
        return content == .battery && !PowerSampler.hasInternalBattery ? .none : content
    }

    package var hasTimerActivity: Bool {
        NotchTimerSupport.isEnabled() && services.timerSession.hasSession
    }

    package var hasWatchActivity: Bool {
        NotchWatchSupport.isEnabled() && services.watchActive
    }

    package var hasDownloadActivity: Bool {
        NotchSupport.routes(.download, in: defaults)
            && services.downloads.contains { $0.active && !$0.completed }
    }

    package var hasMusicActivity: Bool {
        NotchSupport.showsMusicActivity(isPlaying: services.playback?.isPlaying == true, in: defaults)
    }

    package var hasAgentActivity: Bool {
        NotchAgentSupport.showsLiveActivity() && !services.agentUsage.live.isEmpty
    }

    package var hasCalendarActivity: Bool {
        guard let countdown = services.calendarCountdown,
              countdown.ongoing ? NotchCalendarSupport.showsTimeLeft()
                : NotchCalendarSupport.showsCountdown(chosen: services.calendarIsChosen(countdown.event))
        else { return false }
        return countdown.isShown(at: Date())
    }

    package var hasKeepAwakeActivity: Bool {
        NotchKeepAwakeSupport.showsActivity() && services.keepAwakeActive
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
        let animation: Animation? = reducesMotion()
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
                                       running: services.timerSession.isRunning,
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
            let name = services.downloads.first { $0.active && !$0.completed }?.name
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
        let size = NotchTimerSupport.stripTextSize(height: provisional.compactActivityContentHeight)
        let reading = services.watchShowsThumbnail ? NotchWatchSupport.thumbnailWidth
            : (services.watchHeadline as NSString).size(withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            ]).width.rounded(.up)
        let inset = provisional.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        return reading + inset + NotchTimerSupport.stripCameraGap
    }

    private func keepAwakeStripWing(in geometry: NotchGeometry) -> CGFloat {
        NotchKeepAwakeSupport.stripWing(until: services.keepAwakeEndDate, now: Date(),
                                        locale: Locale(identifier: L10n.shared.language.rawValue), in: geometry)
    }

    /// The wider of the two sides, measured with the strip's fonts and its
    /// clearance from the curve: alone, the event's title or its clock and
    /// the time beside it; paired, the event's dot and clock or the mark of
    /// what shares the island, with air beside the camera.
    private func calendarStripWing(for companion: NotchCompactActivity?, in geometry: NotchGeometry) -> CGFloat {
        guard let countdown = services.calendarCountdown else {
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
        let size = NotchTimerSupport.stripTextSize(height: height)
        let text = NotchTimerSupport.compactText(for: services.timerSession, at: services.timerNow,
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
            let working = Set(services.agentUsage.live.map(\.provider)).count
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
            services.agentUsage, readout: NotchAgentSupport.readout(),
            display: NotchAgentSupport.limitDisplay(), focus: NotchAgentSupport.limitFocus(), now: Date()))
        let width = (shape as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        ]).width
        let reading = width.rounded(.up) + provisional.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        // The marks on the other side, drawn as the strip draws them.
        let working = Set(services.agentUsage.live.map(\.provider)).count
        let marks = NotchAgentSupport.stripMarksWidth(working: working, in: provisional)
        return max(reading, marks) + NotchAgentSupport.stripCameraGap
    }

    package var expandedSize: CGSize {
        if showingSections {
            return geometry.sectionPickerSize(count: filteredSections.count)
        }
        let musicExtras = NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
        return pageSize(in: expandedGeometry, module: showingAppPanel ? .tools : selected,
                        detail: selectedMetric != nil, panel: showingAppPanel,
                        detailHeight: selectedMetric == .fan ? fanDetailHeight : nil,
                        musicExtraHeight: musicExtras && musicDetailVisible ? geometry.musicExtrasHeight : 0,
                        fileMediaHeight: !choosingFileDropDestination && AppFeature.mediaTools.isAvailable(in: defaults)
                            && services.mediaPresented ? services.mediaContentHeight : nil,
                        toolCount: services.editingTools || services.activeUtility != nil ? nil : services.visibleTools.count,
                        capturePreviewHeight: captureContent == nil ? nil : captureContentHeight)
    }

    /// The open island as Settings previews a section: at rest, with no
    /// detail, app panel, capture or media editor in front of the page.
    package func previewSize(for module: NotchModule) -> CGSize {
        pageSize(in: previewGeometry(for: module), module: module, detail: false, panel: false, detailHeight: nil, musicExtraHeight: 0,
                 fileMediaHeight: nil, toolCount: services.visibleTools.count, capturePreviewHeight: nil)
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
        let controls = NotchSupport.controls(in: defaults)
        let sliders = controls.filter { $0 == .volume || $0 == .brightness }.count
        let shortcuts = controls.filter { $0 != .volume && $0 != .brightness && $0 != .music }.count
        let musicExtras = NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
        return geometry.expandedSize(module: module, detail: detail, panel: panel, detailHeight: detailHeight,
                                     shortcutCount: shortcuts,
                                     sliderCount: sliders, controlsHaveMusic: controls.contains(.music), musicHasContent: services.playback != nil,
                                     musicHasControlsRow: AppFeature.mixer.isAvailable(in: defaults) || musicExtras,
                                     musicExtraHeight: musicExtraHeight, fileMediaHeight: fileMediaHeight,
                                     systemCards: NotchSupport.systemCardCount(hasBattery: PowerSampler.hasInternalBattery,
                                                                               fans: services.systemSnapshot.fanSpeeds.count, in: defaults),
                                     toolCount: toolCount, capturePreviewHeight: capturePreviewHeight,
                                     timerHasSession: services.timerSession.hasSession,
                                     timerMode: services.timerSession.hasSession
                                        ? services.timerSession.mode : NotchTimerSupport.savedMode(),
                                     agentsHeight: module == .agents && !detail && !panel
                                        ? agentsContentHeight(width: geometry.contentWidth) : nil)
    }

    /// The AI page is as tall as the cards it shows; nil while the logs are
    /// first read, when the page fills the island with its progress.
    private func agentsContentHeight(width: CGFloat) -> CGFloat? {
        let usage = services.agentUsage
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
        let download = services.downloads.first { $0.active && !$0.completed }
        let working = Set(services.agentUsage.live.map(\.provider)).count
        switch activity {
        case .music:
            let playback = heldMusic?.playback ?? services.playback
            return layout.musicSurface(title: capsuleMusicTitleShown
                                        ? playback?.track.title ?? FeatureStrings.radialMenu(language).mediaNowPlaying : nil,
                                       geometry: geometry)
        case .timer:
            return layout.timerSurface(reading: NotchTimerSupport.compactText(for: services.timerSession, at: services.timerNow,
                                                                              locale: Locale(identifier: language.rawValue)),
                                       companion: companion, workingAgents: working,
                                       downloadPercent: download?.fraction != nil, geometry: geometry, language: language)
        case .downloads:
            return layout.downloadSurface(name: download?.name ?? FeatureStrings.notchFiles(language).downloadsTitle,
                                          hasProgress: download?.fraction != nil, geometry: geometry, language: language)
        case .agents:
            let reading = NotchAgentSupport.stripReading(services.agentUsage, readout: NotchAgentSupport.readout(),
                                                         display: NotchAgentSupport.limitDisplay(),
                                                         focus: NotchAgentSupport.limitFocus(), now: Date())
            return layout.agentSurface(reading: reading, working: working, geometry: geometry)
        case .calendar:
            guard let countdown = services.calendarCountdown else { return geometry.restingSize(showsContent: false) }
            if let companion {
                return layout.calendarPairSurface(companion: companion, workingAgents: working,
                                                  downloadPercent: download?.fraction != nil, geometry: geometry,
                                                  language: language)
            }
            return layout.calendarSurface(title: layout.calendarTitle(countdown, language: language),
                                          time: NotchCalendarSupport.timeText(countdown, locale: language.formattingLocale()),
                                          geometry: geometry)
        case .watch:
            return layout.watchSurface(reading: services.watchHeadline, thumbnail: services.watchShowsThumbnail,
                                       geometry: geometry)
        case .keepAwake:
            let reading = services.keepAwakeEndDate.map {
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
        NotchSupport.showsInCaptures(in: defaults) ? [] : islandWindowIDs
    }

    package var captureVisibleWindowIDs: Set<CGWindowID> {
        NotchSupport.showsInCaptures(in: defaults) ? islandWindowIDs : []
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
        screenRefresh.cancelPreferenceSync()
        guard NotchSupport.isEnabled(in: defaults) else { stop(); return }
        if !running {
            running = true
            installObservers()
        }
        if !NotchTimerSupport.isEnabled() { services.stopTimer() }
        // A watch keeps reading while the island is away, as on the lock
        // screen, and says so with a notification if it cannot show itself.
        services.syncWatch()
        // Requested file work can continue while locked, but disabling its
        // feature must still cancel it before presentation resumes.
        services.syncFileTools()
        if !services.offersMediaDrop { endFileDrop() }
        // Paused while the island is away, the section still stops at once
        // when it is turned off.
        if !NotchAgentSupport.isEnabled() { services.stopAgentUsage() }
        guard !suspended else {
            if session.canRunTimer { services.syncTimer() }
            else { services.suspendTimer() }
            services.syncLockScreen(session)
            return
        }
        // Checked before any service starts, so each preference change while
        // the lid is closed does not start and stop them all again.
        guard screenIndex(in: NSScreen.screens) != nil else { withdrawFromMissingScreen(); return }
        refreshModules()
        services.syncDownloads()
        services.syncCalendar()
        services.syncNotifications()
        MainActor.assumeIsolated { services.syncAudioLevel() }
        services.syncAgentUsage()
        followsPointer = displayPreference == .pointer || displayPreference == .all
        showsOnAllDisplays = displayPreference == .all
        updateFullscreenDisplays()
        updateScreen()
        syncPointerFollowing()
        syncGestures()
        services.syncTimer()
        services.syncAccessories()
        let signature = NotchEvent.allCases.map { String(NotchSupport.routes($0, in: defaults)) }.joined()
            + NotchSupport.idleContent(in: defaults).rawValue + String(NotchSupport.watchesMusicActivity(in: defaults))
            + String(NotchKeepAwakeSupport.showsActivity())
            + modules.map(\.rawValue).joined()
            + String(AppFeature.fanControl.isAvailable(in: defaults))
            + String(NotchSupport.routesShelf(in: defaults)) + String(NotchSupport.revealsShelfDrag(in: defaults))
            + String(NotchSupport.routesCaptureControls(in: defaults))
        if signature != settingsSignature {
            settingsSignature = signature
            bindEvents()
            Self.collaborators.fileRoutingDidChange()
        }
        if !NotchSupport.routes(.capture, in: defaults), captureContent != nil {
            let fallback = captureFallback
            clearCapture()
            fallback?()
        }
        if captureControls != nil, !NotchSupport.routesCaptureControls(in: defaults) { cancelCaptureControls() }
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
        let updated = NotchSupport.modules(in: defaults)
        if modules != updated { modules = updated }
        let selection = modules.contains(selected) ? selected : modules.first ?? .controls
        if selected != selection { selected = selection }
        if let selectedMetric, !metricIsAvailable(selectedMetric) { self.selectedMetric = nil }
    }

    private func metricIsAvailable(_ metric: MetricDetailKind) -> Bool {
        MenuBarMetric.allCases.contains { $0.detailKind == metric && $0.feature.isAvailable(in: defaults) }
    }

    package func stop(restoreCapture: Bool = true) {
        screenRefresh.cancelPreferenceSync()
        services.stopLyrics()
        services.stopFileTools()
        services.stopAgentUsage()
        guard running else { return }
        running = false
        services.stopTimer()
        services.stopAccessories()
        services.stopWatch()
        let cancelCapture = captureControlsCancel
        endCaptureControls()
        cancelCapture?()
        let fallback = restoreCapture ? captureFallback : captureClose
        clearCapture()
        tearDownPresentation()
        services.closeLockScreen()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        sessionTracker.stop()
        session = NotchSessionState()
        Self.collaborators.feedbackRoutingDidChange()
        Self.collaborators.fileRoutingDidChange()
        fallback?()
    }

    private func tearDownPresentation() {
        screenRefresh.cancelScreenRefresh()
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
        eventBindings.unbind()
        stopPower()
        services.stopMusic()
        MainActor.assumeIsolated { services.stopAudioLevel() }
        services.hideCamera()
        services.suspendAccessories()
        services.stopDownloads()
        services.stopCalendar()
        services.stopNotifications()
        services.pauseAgentUsage()
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
            let opensActivity = defaults.object(forKey: DefaultsKey.notchOpensActivity) as? Bool ?? true
            let activity = notice?.notificationID != nil ? NotchModule.notifications
                : opensActivity ? compactActivity?.module : nil
            if let activity, modules.contains(activity) { return (activity, false, false) }
            if defaults.bool(forKey: DefaultsKey.notchReturnHome) {
                let saved = defaults.string(forKey: DefaultsKey.notchHomeModule) ?? ""
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
        let opensActivity = defaults.object(forKey: DefaultsKey.notchOpensActivity) as? Bool ?? true
        if opensActivity { open(module) } else { open() }
    }

    package func open(_ module: NotchModule? = nil, pinned: Bool = false, takeFocus: Bool = true,
              appPanel: Bool = false, metric: MetricDetailKind? = nil, feedback: Bool = true, sections: Bool = false) {
        guard NotchSupport.isEnabled(in: defaults), !suspended else { return }
        if !running || self.panel == nil { syncWithPreferences() }
        else { refreshModules() }
        guard let panel else { return }
        let reopening = reopeningDestination
        let useReopeningSurface = module == nil && !expanded && !appPanel && !sections && metric == nil
        let destination = module.flatMap { modules.contains($0) ? $0 : nil } ?? reopening.module
        let appPanel = appPanel || (useReopeningSurface && reopening.appPanel)
        let sections = sections || (useReopeningSurface && reopening.sections)
        if useReopeningSurface && reopening.appPanel { MainActor.assumeIsolated { services.showNormalMenuPanel() } }
        if useReopeningSurface && reopening.sections {
            sectionQuery = ""
            sectionRow = 0
            highlightedSection = destination
        }
        let metric = metric.flatMap { metricIsAvailable($0) ? $0 : nil }
        let changesPresentation = !expanded || selected != destination
            || showingAppPanel != appPanel || selectedMetric != metric || showingSections != sections
        if changesPresentation, destination == .tools, !appPanel, !sections, metric == nil {
            services.prepareTools()
        }
        MainActor.assumeIsolated { appShell()?.closePopover(preservingNotch: true) }
        if !expanded, modules.contains(.clipboard) { services.rememberPasteTarget() }
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
        inside = windowHost?.containsHover(pointer()) == true
        installEventMonitors()
        syncVisibleConsumers()
        if takeFocus { panel.makeKey() }
        if feedback, changesPresentation { provideHapticFeedback() }
    }

    package func collapse() {
        guard captureControls == nil, !heldDrag else { return }
        let closeCapture = detachCaptureIfClosingOnCollapse()
        hoverState.close(pointerInside: windowHost?.containsHover(pointer()) == true)
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
        guard acceptsUserInteraction, NotchSupport.routesClipboardWindow(in: defaults) else { return false }
        if toggle, expanded, selected == .clipboard, !showingAppPanel, !showingSections { collapse() }
        else { open(.clipboard) }
        return true
    }

    package func hover(_ entered: Bool) {
        guard running, !suspended, !hiddenAtRestInFullscreen else { removeHoverExitMonitors(); return }
        let point = pointer()
        let wasInside = inside
        let showedPicker = showsCompactActivityPicker
        inside = hiddenUntilHover ? geometry.contains(point, in: geometry.collapsed)
            && windowHost?.isConcealedForMissionControl == false
            : windowHost?.containsHover(point) == true || pointerOverChildWindow(point)
        hoverState.update(pointerInside: inside)
        let emphasize = inside && !hiddenInFullscreen && !hiddenUntilHover && !expanded && !peeking && !dragPlaceholder
            && notice == nil && captureControls == nil
            && !reducesMotion()
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
                  defaults.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
            if !hiddenInFullscreen, compactActivity != nil, compactActivityGeometry.compactActivityWingWidth > 0,
               !defaults.bool(forKey: DefaultsKey.notchHoverExpands) { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                guard self.running, !self.suspended, self.inside, !self.hoverState.suppressed,
                      !self.expanded, !self.peeking, !self.pinned, !self.heldDrag, !self.keepsWorkingSurface,
                      !self.showsCompactActivityPicker,
                      self.captureControls == nil, (self.notice == nil || self.hiddenUntilHover), !self.dragPlaceholder,
                      self.defaults.bool(forKey: DefaultsKey.notchOpenOnHover),
                      self.windowHost?.blocksHoverReveal() == false,
                      self.geometry.contains(self.pointer(), in: self.hiddenUntilHover ? self.geometry.collapsed : self.surfaceSize) else { return }
                // Following the closed island ends as it opens or peeks.
                self.removeHoverExitMonitors()
                if self.defaults.bool(forKey: DefaultsKey.notchHoverExpands) {
                    self.open(takeFocus: false)
                } else {
                    self.mutatePresentation(transitionContent: .reveal) { self.peeking = true }
                    self.provideHapticFeedback()
                }
            }
            hoverWork = work
            let delay = NotchSupport.sanitizedHoverDelay(defaults.double(forKey: DefaultsKey.notchHoverDelay))
            schedule(delay, work)
        } else if holdsNotification
                    || NotchSupport.closesOnPointerExit(expanded: expanded, peeking: peeking, openedByHover: openedByHover) {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                guard self.running, !self.suspended, !self.inside,
                      self.windowHost?.containsHover(self.pointer()) != true,
                      !self.pointerOverChildWindow(self.pointer()) else { return }
                self.releaseNotification()
                guard !self.pinned, !self.heldDrag, !self.keepsWorkingSurface, self.captureControls == nil,
                      !AssistiveKeyboard.ownsCocoaPoint(self.pointer()),
                      NotchSupport.closesOnPointerExit(expanded: self.expanded, peeking: self.peeking, openedByHover: self.openedByHover) else { return }
                self.collapse()
            }
            hoverWork = work
            schedule((expanded || noticeExpanded ? NotchQuickAccessLayout.hoverExitDelay : 0.12), work)
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
              defaults.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWork = nil
            guard self.running, !self.suspended, self.inside, !self.hoverState.suppressed, !self.pinned, !self.heldDrag,
                  !self.keepsWorkingSurface, self.holdsNotification, self.notice?.notificationID == id, !self.noticeExpanded,
                  self.defaults.bool(forKey: DefaultsKey.notchOpenOnHover),
                  self.geometry.contains(self.pointer(), in: self.surfaceSize) else { return }
            self.mutatePresentation(transitionContent: .reveal) { self.peeking = false; self.noticeExpanded = true }
            self.provideHapticFeedback()
        }
        hoverWork = work
        let delay = NotchSupport.sanitizedHoverDelay(defaults.double(forKey: DefaultsKey.notchHoverDelay))
        schedule(delay, work)
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
        if !NotchSupport.routes(notice.event, in: defaults) || (notice.notificationID != nil && hiddenUntilHover) {
            dismissNotice()
        }
    }

    private func scheduleNoticeDismissal(after duration: TimeInterval) {
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissNotice() }
        noticeWork = work
        schedule(duration, work)
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
        let commandOnly = event.modifierFlags.intersection([.command, .control, .option]) == .command
        let shift = event.modifierFlags.contains(.shift)
        guard let action = ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                                                               commandOnly: commandOnly,
                                                               shift: shift,
                                                               canCreatePad: services.canCreatePad,
                                                               canClosePad: services.canClosePad) else {
            // At the tab limit Command-T still belongs to the pad, not the text.
            return commandOnly && !shift && event.charactersIgnoringModifiers?.lowercased() == "t"
        }
        switch action {
        case .createPad: services.createPad(defaultName: FeatureStrings.scratchpad(L10n.shared.language).pageTitle)
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
        guard NotchSupport.isEnabled(in: defaults), action.isAvailable() else { return }
        switch action {
        case .explore: toggleSections()
        case .settings: openSettings()
        case .pin: pinned.toggle()
        case .module(let module): select(module)
        case .control(let item):
            switch item {
            case .keepAwake: services.toggleKeepAwake()
            case .microphone: services.toggleMicrophone()
            case .screenshot: perform { [services] in services.captureScreenshot() }
            case .recording: perform { [services] in services.toggleRecording() }
            case .speedTest: showMetric(.network)
            case .panel: openAppPanel()
            case .mixer: select(.mixer)
            case .music: select(.music)
            case .timer: select(.timer)
            case .calendar: select(.calendar)
            case .commandBar: perform { [services] in services.showCommandBar() }
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
        if !showScratchpad() { perform { [services] in services.showScratchpad() } }
    }

    @discardableResult
    package func showScratchpad(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesScratchpad(in: defaults), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .scratchpad, !showingAppPanel, !showingSections,
           selectedMetric == nil, panel?.isKeyWindow == true { collapse() }
        else { open(.scratchpad) }
        return true
    }

    package func openAppPanel(toggle: Bool = false) {
        if toggle, expanded, showingAppPanel, !showingSections { collapse(); return }
        MainActor.assumeIsolated { services.showNormalMenuPanel() }
        open(.controls, appPanel: true)
        // The toggling route is the menu bar's. Opened from there, the panel
        // has nothing behind it and closes on Escape, like the menu panel.
        if toggle { detailHasPage = false }
    }

    package func openQuickPanel(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesQuickPanel(in: defaults), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .tools, !showingSections { collapse() }
        else { open(.tools) }
        return true
    }

    package func openShelf(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesShelf(in: defaults), acceptsUserInteraction else { return false }
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
        guard acceptsUserInteraction, panel?.isVisible == true, NotchSupport.usesHapticFeedback(in: defaults) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    package func fileDragChanged(_ active: Bool, internalDrag: Bool = false) {
        guard running, !suspended, internalDrag || NotchSupport.routesShelf(in: defaults) else { return }
        heldDrag = active && internalDrag
        if active, !internalDrag, NotchSupport.revealsShelfDrag(in: defaults), !expanded {
            mutatePresentation { dragPlaceholder = true; peeking = false }
        } else if !active {
            mutatePresentation { dragPlaceholder = false }
            inside = windowHost?.containsHover(pointer()) == true
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
        hoverState.close(pointerInside: windowHost?.containsHover(pointer()) == true)
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
        hoverState.close(pointerInside: windowHost?.containsHover(pointer()) == true)
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
                  self.windowHost?.containsHover(self.pointer()) != true else { return }
            self.collapseCaptureControls()
        }
        captureControlsWork = work
        schedule(delay, work)
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
                  self.windowHost?.containsHover(self.pointer()) == true else { return }
            self.expandCaptureControls()
        }
        hoverWork = work
        schedule(0.25, work)
    }

    /// The capture-controls window covers the top center of the screen, over
    /// the selection surface. Only its visible controls should catch the
    /// mouse; everywhere else the click falls through to the selection beneath,
    /// so a region under the notch can still be dragged or a window clicked.
    private func updateCaptureControlsClickThrough() {
        guard let panel, captureControls != nil else { return }
        let point = pointer()
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
        else { hover(windowHost?.containsHover(pointer()) == true) }
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
        services.openNotchSettings()
        MainActor.assumeIsolated { appShell()?.openSettingsWindow() }
    }

    /// Opens the Dynamic Island settings on one section's options.
    package func openSettings(showing module: NotchModule) {
        services.showSettingsModule(module)
        openSettings()
    }

    package func perform(_ action: @escaping @MainActor () -> Void) {
        collapse()
        if let windowHost { windowHost.whenSettled(action) }
        else { DispatchQueue.main.async { action() } }
    }

    package var canAcceptFileDrop: Bool {
        fileDrop.canAccept
    }

    /// Where on the open island the media tools take a drop.
    private var mediaDropArea: CGRect {
        NotchFileToolsSupport.mediaDropArea(in: expandedGeometry, size: surfaceSize)
    }

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
        guard showsSystemFeedback, NotchSupport.routes(incoming.event, in: defaults),
              NotchSupport.shouldReplace(notice?.event, with: incoming.event, held: noticeExpanded) else { return false }
        noticeWork?.cancel(); noticeWork = nil
        var incoming = incoming
        if incoming.notification != nil, let shown = notice, shown.notification != nil, noticeCanPresent, !noticeExpanded {
            incoming.minimumWingWidth = shown.preferredWingWidth
        }
        let keepsPreview = noticeExpanded && incoming.notificationID != nil
            && windowHost?.containsHover(pointer()) == true
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
        if let id = incoming.notificationID, holdsNotification, windowHost?.containsHover(pointer()) == true {
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
            guard services.openingNotification == nil else { return }
            // The pointer stays where the banner was; like a click on the
            // island itself, this must not turn into a hover opening.
            settleNotificationHover()
            services.openNotification(id) { [weak self] result in
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
                  let playback = self.services.playback, playback.isPlaying,
                  let title = playback.track.title, !title.isEmpty else { return }
            self.show(NotchNotice(event: .track, title: title, detail: playback.track.artist ?? "",
                                  symbol: "music.note"))
        }
        trackWork = work
        schedule(0.5, work)
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
        services.dismissNotification(id)
        dismissNotice()
    }

    private func settleNotificationHover() {
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: windowHost?.containsHover(pointer()) == true)
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
        schedule(NotchMotion.departureHidden, work)
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
        guard acceptsSystemFeedback, NotchSupport.routes(.capture, in: defaults) else { return false }
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

    /// What decides whether a capture's keys belong to it.
    package struct CaptureFocus {
        package var acceptsSystemFeedback: Bool
        package var expanded: Bool
        package var selected: NotchModule
        package var showingAppPanel: Bool
        package var showingSections: Bool
        package var showingMetric: Bool
        /// A capture's area or window is being chosen.
        package var choosing: Bool
        package var captureID: UUID?
        package var hasContent: Bool

        package init(acceptsSystemFeedback: Bool, expanded: Bool, selected: NotchModule, showingAppPanel: Bool,
                     showingSections: Bool, showingMetric: Bool, choosing: Bool, captureID: UUID?, hasContent: Bool) {
            self.acceptsSystemFeedback = acceptsSystemFeedback
            self.expanded = expanded
            self.selected = selected
            self.showingAppPanel = showingAppPanel
            self.showingSections = showingSections
            self.showingMetric = showingMetric
            self.choosing = choosing
            self.captureID = captureID
            self.hasContent = hasContent
        }

        /// The island is open on its captures, nothing in front of them, and
        /// shows this one.
        package func shows(_ id: UUID) -> Bool {
            acceptsSystemFeedback && expanded && selected == .captures
                && !showingAppPanel && !showingSections && !showingMetric
                && !choosing && captureID == id && hasContent
        }
    }

    package var captureFocus: CaptureFocus {
        CaptureFocus(acceptsSystemFeedback: acceptsSystemFeedback, expanded: expanded, selected: selected,
                     showingAppPanel: showingAppPanel, showingSections: showingSections,
                     showingMetric: selectedMetric != nil, choosing: captureControls != nil,
                     captureID: captureID, hasContent: captureContent != nil)
    }

    package func isCaptureVisible(id: UUID) -> Bool {
        captureFocus.shows(id)
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
                && !reducesMotion() { return .none }
            musicDepartureWork?.cancel(); musicDepartureWork = nil
            departingMusic = nil
            // A new presentation must replace the departure's forward-filled mask.
            return requested == .none ? (animated ? .reveal : .replace) : requested
        }
        guard requested == .none, animated, !reducesMotion(),
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
            panel?.level = hiddenInFullscreen && !geometry.isNotched && !NotchSupport.coversMenus(in: defaults)
                ? NotchPanel.fullscreenLevel : NotchPanel.normalLevel
        }
        // Preferences can change computed dimensions without publishing a
        // service property. Update SwiftUI's layout along with the native host.
        if let windowHost, windowHost.targetSize != size { objectWillChange.send() }
        windowHost?.setOutline(enabled: !fullscreenCompact && defaults.bool(forKey: DefaultsKey.notchOutlineEnabled),
                               color: compactActivityIsVisible && compactActivity == .timer ? .systemOrange : .white)
        windowHost?.present(size: size, geometry: expanded ? expandedGeometry : geometry, animated: animated,
                            transitionContent: contentTransition,
                            quickAccess: expanded && captureControls == nil && !access.buttons.isEmpty ? access : nil,
                            revealFromHidden: !hiddenInFullscreen && captureControls == nil
                                && defaults.bool(forKey: DefaultsKey.notchHideUntilHover)
                                && defaults.bool(forKey: DefaultsKey.notchOpenOnHover),
                            hideWhenSettled: false,
                            usesGlass: !fullscreenCompact && usesGlassSurface)
        // The selector lives in a separate full-screen panel. A floating
        // capsule may sit below the display edge, so publish the island's
        // actual bottom inset as the controls collapse or reopen.
        captureControls?.onCaptureControlsSurfaceChange?(
            geometry.screen, geometry.floatingDrop + size.height)
        // Closing can shrink the island away from a pointer that has not moved,
        // with no boundary crossing to report it. Only a pointer still over the
        // island may keep its next approach from opening it.
        if windowHost?.containsHover(pointer()) != true { hoverState.update(pointerInside: false) }
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
        rememberPresentedMusic(playback: services.playback, artwork: services.artwork, tint: services.artworkTint)
        if contentTransition == .depart {
            if windowHost?.departsContent == true {
                let work = DispatchWorkItem { [weak self] in self?.finishMusicDeparture() }
                musicDepartureWork = work
                schedule(NotchMotion.departureHidden, work)
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
    private var canFollowPointer: Bool { screenRefresh.canFollowPointer }

    private func schedulePointerFollow() { pointerFollower.pointerMoved() }

    private func move(to screen: NSScreen) {
        screenRefresh.move(to: screen.notchDisplayID)
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
        schedule(Self.musicTitleDuration, work)
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

    private var screenEdgeClickArea: CGRect? {
        NotchScreenEdgeClicks.area(for: .init(
            running: running, suspended: suspended, expanded: expanded, peeking: peeking,
            hasCaptureControls: captureControls != nil, hasNotice: notice != nil,
            dragPlaceholder: dragPlaceholder, heldDrag: heldDrag,
            panelTakesClicks: panel.map { $0.isVisible && !$0.ignoresMouseEvents },
            compactActivityIsVisible: compactActivityIsVisible, geometry: geometry,
            compactActivityGeometry: compactActivityGeometry, surfaceSize: surfaceSize))
    }

    private func syncScreenEdgeClicks() { screenEdgeClicks.sync() }

    private func removeScreenEdgeClickMonitors() { screenEdgeClicks.remove() }

    /// A press began on the menu bar above the island: hover waits for the release.
    private func screenEdgePressed() {
        NotchScreenEdgeClicks.pressed(hoverWork: &hoverWork, hoverState: &hoverState)
    }

    /// Displays that share Spaces show the menu bar on the main one only.
    private var displayHasMenuBar: Bool {
        NSScreen.screensHaveSeparateSpaces || NSScreen.withMenuBar?.frame == geometry.screen
    }

    private func syncMenuSpaceMonitoring() { screenRefresh.syncMenuSpaceMonitoring() }

    private func invalidateMenuSpace() { screenRefresh.invalidateMenuSpace() }

    private func screenParametersDidChange() { screenRefresh.screenParametersDidChange() }

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
        NotchDisplay(rawValue: defaults.string(forKey: DefaultsKey.notchDisplay) ?? "") ?? .automatic
    }

    private func screenIndex(in screens: [NSScreen]) -> Int? {
        let preference = displayPreference
        var pointer: Int?
        if preference == .pointer || preference == .all {
            // The island stays on its display until it can follow the pointer.
            let mouse = pointer()
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
        services.suspendTimer()
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
            windowHost = makeHost(self, geometry, surfaceSize)
            windowHost?.missionControlDidRestore = { [weak self] in self?.missionControlDidRestore() }
            windowHost?.setHoverHandler { [weak self] in self?.hover($0) }
            panel?.title = FeatureStrings.notch(L10n.shared.language).title
        }
        if modules.contains(.files), AppFeature.shelf.isAvailable(in: defaults) {
            windowHost?.setFileDropActions(NotchFileDropActions(
                canAccept: { [weak self] pasteboard in
                    self?.canAcceptFileDrop == true && Self.collaborators.shelfCanAccept(pasteboard)
                },
                enter: { [weak self] in self?.beginFileDrop($0) },
                accept: { [weak self] in self?.accept($0) == true },
                exit: { [weak self] in
                    guard let self else { return }
                    self.endFileDrop()
                    self.hover(self.windowHost?.contains(self.pointer()) == true)
                },
                update: { [weak self] in self?.updateFileDrop(at: $0) == true }))
        } else { windowHost?.setFileDropActions(nil) }
        panel?.sharingType = NotchSupport.showsInCaptures(in: defaults) ? .readOnly : .none
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
                             layout: NotchSize(rawValue: defaults.string(forKey: DefaultsKey.notchSize) ?? "") ?? .spacious,
                             menuBarHeight: menuBarMeasurements.height(
                                displayID: screen.notchDisplayID, frame: screen.frame,
                                visibleTop: screen.visibleFrame.maxY, scale: screen.backingScaleFactor,
                                statusBarThickness: NSStatusBar.system.thickness),
                             customWidth: defaults.double(forKey: DefaultsKey.notchCustomWidth),
                             customHeight: defaults.double(forKey: DefaultsKey.notchCustomHeight),
                             cameraFit: NotchCameraFit.current(), silhouette: NotchSilhouette.current(),
                             capsuleFit: NotchCapsuleFit.current(),
                             outline: defaults.bool(forKey: DefaultsKey.notchOutlineEnabled))
    }

    private func updateFullscreenVisibility(displayID: CGDirectDisplayID) {
        fullscreen.update(displayID: displayID)
    }

    private func fullscreenEnvironmentDidChange() {
        fullscreen.environmentDidChange()
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
            self.hover(self.windowHost?.contains(self.pointer()) == true)
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
    private func schedulePreferenceSync() { screenRefresh.schedulePreferenceSync() }

    private func applicationDidActivate() { screenRefresh.applicationDidActivate() }

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
           NotchLockScreenSupport.playsSounds(in: defaults) {
            services.playLockSound(locking: session.locked)
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
        services.syncLockScreen(session)
        // A dark display does not stop an alarm while the same user and Mac
        // remain awake. Privacy changes still apply when presentation is
        // already suspended by the display.
        guard timerCouldRun != session.canRunTimer, !session.canPresent else { return }
        if session.canRunTimer { services.syncTimer() }
        else { services.suspendTimer() }
    }

    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        clickedSinceOpening = false
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            guard let self, self.clickIsAway() else { return }
            self.collapse()
        }) { eventMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            return self.localEvents.handle(event) ? nil : event
        }) { eventMonitors.append(token) }
    }

    /// A click lands away from the island: not on it, its status item or the
    /// Accessibility Keyboard, while nothing keeps its working surface open.
    private func clickIsAway() -> Bool {
        !keepsWorkingSurface
            && windowHost?.contains(pointer()) != true
            && appShell()?.isOverStatusItem(pointer()) != true
            && !AssistiveKeyboard.ownsCocoaPoint(pointer())
    }

    /// The island's own keys and the clicks that close it (`NotchLocalEventRoute`).
    private lazy var localEvents: NotchLocalEventRoute<NSEvent> = NotchLocalEventRoute(island: .init(
        panel: { [weak self] in self?.panel },
        isComposing: { [weak self] in (self?.panel?.firstResponder as? NSTextView)?.hasMarkedText() == true },
        fieldTakesEscape: { [weak self] in
            if let editor = self?.panel?.firstResponder as? NSTextView, editor.isFieldEditor,
               (editor.delegate as AnyObject?) is MixerPercentNativeTextField { return true }
            return PlainTextEditor.findBarHasKeyboard(in: self?.panel)
        },
        isCapturing: { [weak self] in self?.captureControls != nil },
        modules: { [weak self] in self?.modules ?? [] },
        selected: { [weak self] in self?.selected ?? .controls },
        showingSections: { [weak self] in self?.showingSections ?? false },
        showingAppPanel: { [weak self] in self?.showingAppPanel ?? false },
        geometry: { [weak self] in self?.expandedGeometry ?? NotchGeometry(screen: .zero, safeAreaTop: 0, cameraWidth: 0) },
        tools: { [services] in (services.editingTools, services.visibleTools.count) },
        ownsWindow: { [weak self] in self?.ownsWindow($0 as? NSWindow) ?? false },
        clickIsAway: { [weak self] in self?.clickIsAway() ?? false },
        toggleSections: { [weak self] in self?.toggleSections() },
        select: { [weak self] in self?.select($0) },
        sectionKey: { [weak self] in self?.handleSectionKey($0) ?? false },
        scratchpadKey: { [weak self] in self?.handleScratchpadKey($0) ?? false },
        clipboardPasteKey: { [weak self] in self?.handleClipboardPasteKey($0) ?? false },
        toolsKey: { [services] in services.takesToolsKey($0, flow: $1) },
        stepBack: { [weak self] in self?.stepBack() },
        collapse: { [weak self] in self?.collapse() },
        clickedInside: { [weak self] in self?.clickedSinceOpening = true }))

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
        var surface: NotchSectionScrollSurface?
        if running, !suspended, expanded, showingSections, !trackingMenu, let panel {
            let host = windowHost
            surface = NotchSectionScrollSurface(frame: panel.frame, toScreen: { panel.convertPoint(toScreen: $0) },
                                                containsSurface: { host?.containsSurface($0) == true },
                                                geometry: expandedGeometry)
        }
        guard let steps = sectionScroll.route(event, over: surface) else { return false }
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
            services.skipTrack(forward: action == .nextTrack)
        }
        return true
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    /// Only a current offer, in the open island that is running, opens its
    /// release notes; the resting island never opens for one.
    package static func opensUpdatePreview(offered: Bool, running: Bool, suspended: Bool, expanded: Bool) -> Bool {
        running && !suspended && expanded && offered
    }

    package func showUpdate() {
        // UI passes this as the update control's action, which runs on the main thread.
        let offered = MainActor.assumeIsolated { services.updateOffered }
        guard Self.opensUpdatePreview(offered: offered, running: running, suspended: suspended,
                                      expanded: expanded) else { return }
        collapse()
        MainActor.assumeIsolated { appShell()?.showUpdatePreview() }
    }

    private func bindEvents() {
        subscriptions.removeAll()
        eventBindings.bind(NotchEventBindings.Settings(modules: modules,
                                                       routes: { [defaults] in NotchSupport.routes($0, in: defaults) },
                                                       keepAwakeActivity: NotchKeepAwakeSupport.showsActivity(),
                                                       fanControl: AppFeature.fanControl.isAvailable(in: defaults)),
                           heldSongTitles: $heldMusic.map { $0?.playback.track.title }.eraseToAnyPublisher())
        stopPower()
        if NotchSupport.routes(.volume, in: defaults) {
            volumeFeedback.follow().store(in: &subscriptions)
        }
        if NotchSupport.routes(.battery, in: defaults) || idleContent == .battery { startPower() }
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
        volumeFeedback.showCurrentVolume()
    }

    /// The island's own output controls already show the level they set.
    package func noteOwnVolumeAdjustment() {
        volumeFeedback.noteOwnAdjustment()
    }

    /// Levels set outside the island, like Command Bar's, report here too.
    /// False leaves the confirmation to the caller.
    @discardableResult
    package func showVolume(_ volume: Double, muted: Bool? = nil) -> Bool {
        volumeFeedback.showVolume(volume, muted: muted)
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
            services.hideCamera()
            // A copy on another display still shows the song playing.
            let copiesShowMusic = showsCopies && NotchSupport.watchesMusicActivity(in: defaults)
            if copiesShowMusic { services.startMusic() } else { services.stopMusic() }
            releaseMonitor()
            return
        }
        if !NotchCameraSupport.canPresent(expanded: expanded && !showingSections, selected: selected,
            appPanel: showingAppPanel, captureControls: captureControls != nil) {
            services.hideCamera()
        }
        let musicWanted = modules.contains(.music) && ((expanded && (selected == .music || (selected == .controls && NotchSupport.controls(in: defaults).contains(.music)))
            && !showingAppPanel && !showingSections)
            || (!hiddenUntilHover && (NotchSupport.watchesMusicActivity(in: defaults) || NotchSupport.routes(.track, in: defaults))))
        if musicWanted { services.startMusic() } else { services.stopMusic() }
        let needs = expanded && selected == .system && selectedMetric == nil && modules.contains(.system) && !showingAppPanel && !showingSections
        var detailNeeds = expanded && !showingSections ? selectedMetric?.monitorNeeds ?? .none : .none
        if needs, AppFeature.monitorDisk.isAvailable(in: defaults) { detailNeeds.disk = true }
        if needs, AppFeature.fanControl.isAvailable(in: defaults) { detailNeeds.fanSpeed = true }
        services.setMonitorDetailNeeds(detailNeeds)
        if needs != notchNeedsMonitor {
            notchNeedsMonitor = needs
            services.setMonitorVisible(needs)
        }
    }

    private func releaseMonitor() {
        services.setMonitorDetailNeeds(.none)
        guard notchNeedsMonitor else { return }
        notchNeedsMonitor = false
        services.setMonitorVisible(false)
    }
}

extension NSScreen {
    package var notchDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
