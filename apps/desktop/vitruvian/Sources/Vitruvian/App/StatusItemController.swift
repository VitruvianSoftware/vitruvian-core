// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Owns the menu bar presence: the black hole glyph, the optional countdown
/// title and the tooltip. Click handling is delegated back to the AppDelegate.
@MainActor
final class StatusItemController {
    var onLeftClick: (() -> Void)?
    /// Receives the button that was clicked, so a menu can open from it
    /// while the main item is out of the bar.
    var onRightClick: ((NSStatusBarButton?) -> Void)?
    var onMetricClick: ((MenuBarMetric, NSStatusBarButton) -> Void)?
    var onClipboardPreviewClick: (() -> Void)?

    private(set) var statusItem: NSStatusItem!
    /// The optional "show latest copy" item: same shape as a metric item —
    /// independent, opt-in and separately clickable — but not itself a
    /// MenuBarMetric, since its content comes from ClipboardHistoryService
    /// rather than a SystemSnapshot reading.
    // `nonisolated(unsafe)`: `deinit` reads it too, once nothing else holds the object.
    nonisolated(unsafe) private var clipboardPreviewStatusItem: NSStatusItem?
    // `nonisolated(unsafe)`: `deinit` reads it too, once nothing else holds the object.
    nonisolated(unsafe) private var metricStatusItems: [String: NSStatusItem] = [:]
    private var metricStatusItemFocus: [String: MenuBarMetric] = [:]
    private var cancellables = Set<AnyCancellable>()
    // `nonisolated(unsafe)`: `deinit` reads them too, once nothing else holds the object.
    nonisolated(unsafe) private var titleTimer: Timer?
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?
    /// Last combination applied by updateIconAppearance, so refresh ticks
    /// don't re-render an unchanged icon every 2 seconds.
    private var lastIconStateKey = ""
    /// Mirrors only the island's fullscreen presentation state. A notification
    /// avoids loading NotchService when its feature was never installed.
    private(set) var islandHiddenInFullscreen = false
    /// True while the app itself keeps the main item out of the bar, for
    /// Dynamic Island or for separate metrics, as opposed to macOS dropping
    /// it. Recovery leaves such an item alone.
    private(set) var mainItemHiddenByChoice = false
    private var heldMicBadgeActive: Bool?
    /// A settings reply already waiting for the next turn of the run loop.
    private var settingsSyncScheduled = false
    /// How many readings in a row each metric has failed to render, so an
    /// item is kept through a hiccup but not forever.
    private var metricEmptyRenders: [String: Int] = [:]
    /// How many metric items are actually showing a reading. An item kept
    /// through a hiccup shows nothing, so it must not be what makes the main
    /// item step aside: that would leave the menu bar with nothing to click.
    private var renderedMetricItemCount = 0
    /// True while a refresh is running. Anything the menu bar announces back
    /// to us in the middle of one is a consequence of that same work, so it
    /// is answered once afterwards rather than on top of it.
    private var isRefreshing = false
    private var refreshRequestedWhileRunning = false
    /// True once the clipboard preview's own subscriptions are wired up.
    /// Merely referencing ClipboardHistoryService.shared brings the whole
    /// service to life — its saved history file and image folder included —
    /// so bind() only touches it once the feature is actually available,
    /// rather than for every launch regardless of whether anyone uses it.
    private var clipboardBindingsInstalled = false
    private static let mainAutosaveName = "VitruvianMenuBarItem"
    private static let metricAutosavePrefix = "VitruvianMetric"
    private static let clipboardPreviewAutosaveName = "VitruvianClipboardPreview"
    private static let maxPlacementGeneration = 10_000
    private static let emptyStatusImage = NSImage()

    /// Cached so the countdown tooltip doesn't allocate a DateFormatter (expensive)
    /// on every refresh while a keep-awake session is active.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var button: NSStatusBarButton? { statusItem.button }

    func containsStatusItem(at screenPoint: NSPoint) -> Bool {
        // The screens are listed once for the whole scan, not once per item.
        StatusItemRecovery.containsItem(at: screenPoint,
                                        main: statusItem,
                                        clipboardPreview: clipboardPreviewStatusItem,
                                        metrics: Array(metricStatusItems.values),
                                        isVisible: { $0.isVisible },
                                        windowFrame: { $0.button?.window?.frame },
                                        screenFrames: NSScreen.screens.map(\.frame))
    }

    init() {
        installStatusItem()
        bind()
    }

    /// Creates the status item and configures its button. The menu bar item is the
    /// app's entry point unless the person lets Dynamic Island stand in for it, so
    /// an empty behavior set keeps it from being dragged off the bar (reordering
    /// still works), and forcing isVisible undoes any hidden state macOS may have
    /// persisted. If it ever goes missing, re-opening the app recovers access (see
    /// applicationShouldHandleReopen) and the "Show menu bar icon" button in
    /// Settings rebuilds it.
    private func installStatusItem() {
        // Nothing here may touch the saved placement. 3.3.3 retired a legacy
        // 64pt offset on every launch and took working coordinates with it;
        // giving up a spot is now something only an explicit recovery does.
        //
        // A fresh NSStatusItem starts blank; the memoized icon state belongs
        // to the previous instance and must not suppress the first apply.
        lastIconStateKey = ""
        // Recovery must place the full content from the start. A square slot
        // can fit while its expanded title is dropped, leaving a stale frame
        // that incorrectly makes the recovery look successful.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A stable identity so macOS remembers the item's position across launches
        // and across rebuilds, instead of re-placing it at the crowded default spot.
        statusItem.autosaveName = StatusItemPlacementSupport.mainAutosaveName(in: .standard)
        statusItem.behavior = []
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = BlackHoleGlyph.image(active: false)
            button.font = MenuBarRenderer.statusFont(stacked: false)
            button.alignment = .left
            button.cell?.lineBreakMode = .byClipping
            button.cell?.usesSingleLineMode = false
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh()
        syncMonitorMode()
        updateIconAppearance()
    }

    /// Tears the status item down and builds a fresh one, dropping the hidden state
    /// macOS remembered for it so the rebuilt one is not put straight back out of
    /// sight — while keeping the spot the person arranged, which a brand new
    /// identity would throw away.
    func recreateStatusItem() {
        // The item goes away first: AppKit writes its placement and remembered
        // visibility back under its own name as it is removed, which would put
        // back whatever was cleared a moment earlier.
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        StatusItemPlacementSupport.clearRememberedVisibility(in: .standard)
        installStatusItem()
    }

    /// Starts the item over under a brand new identity, giving up the saved
    /// position along with everything else macOS remembered about it. Last
    /// resort: the item lands wherever macOS puts a first-time item, which on
    /// a crowded bar can be a worse place than the one it came from, so this
    /// is only for an icon that stayed away after keeping its spot.
    func resetStatusItemPlacementIdentity() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        StatusItemPlacementSupport.bumpPlacementGeneration(in: .standard)
        installStatusItem()
    }

    private func bind() {
        KeepAwakeManager.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIconAppearance()
                self?.refresh()
            }
            .store(in: &cancellables)

        UpdateService.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIconAppearance() }
            .store(in: &cancellables)

        MicMuteService.shared.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIconAppearance() }
            .store(in: &cancellables)

        KeepAwakeManager.shared.$endDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        L10n.shared.$language
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard MenuBarMetric.anyEnabled(in: .standard) else { return }
                self?.refresh()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NotchService.fullscreenVisibilityDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, let hidden = notification.userInfo?["hidden"] as? Bool,
                      hidden != self.islandHiddenInFullscreen else { return }
                self.islandHiddenInFullscreen = hidden
                self.refresh()
            }
            .store(in: &cancellables)

        bindClipboardPreviewIfAvailable()

        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil,
                                                                  queue: .main) { [weak self] _ in
            // Showing a status item writes its own remembered position into
            // this same domain and announces it right there on the stack, so
            // reacting immediately would call back into the work that is
            // still running. The reply waits for the next turn of the run
            // loop, and a burst of writes collapses into one. The observer
            // is on the main queue.
            MainActor.assumeIsolated { self?.scheduleSettingsSync() }
        }
    }

    private func scheduleSettingsSync() {
        guard !settingsSyncScheduled else { return }
        settingsSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settingsSyncScheduled = false
            self.syncMonitorMode()
            self.updateIconAppearance()
            self.refresh()
            self.bindClipboardPreviewIfAvailable()
            self.syncClipboardPreviewItem()
        }
    }

    /// Wires up the clipboard preview's own subscriptions the first time the
    /// feature is actually available — at launch if it already is, or the
    /// moment a settings change (installing it from the hub, included) makes
    /// it so. Referencing ClipboardHistoryService.shared any earlier would
    /// bring the service to life for every launch, reading its saved history
    /// file and scanning its image folder even for someone who never turned
    /// the feature on.
    private func bindClipboardPreviewIfAvailable() {
        guard !clipboardBindingsInstalled, AppFeature.clipboardHistory.isAvailable else { return }
        clipboardBindingsInstalled = true
        ClipboardHistoryService.shared.$latestPasteboardEntry
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncClipboardPreviewItem() }
            .store(in: &cancellables)

        ClipboardHistoryService.shared.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncClipboardPreviewItem() }
            .store(in: &cancellables)
    }

    deinit {
        // The controller lives for the whole process today, but tear down cleanly
        // so a future "recreate the status item" path can't leak a firing timer or
        // a block observer that outlives this instance.
        titleTimer?.invalidate()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        for item in metricStatusItems.values {
            NSStatusBar.system.removeStatusItem(item)
        }
        if let clipboardPreviewStatusItem {
            NSStatusBar.system.removeStatusItem(clipboardPreviewStatusItem)
        }
    }

    /// Keeps the background sampler in step with the menu bar settings: it runs
    /// continuously only while at least one metric is pinned to the menu bar.
    private func syncMonitorMode() {
        let defaults = UserDefaults.standard
        let interval = Defaults.sanitizedMonitorInterval(defaults[Preferences.monitorInterval])
        SystemMonitor.shared.setInterval(seconds: interval)
        SystemMonitor.shared.setMenuBarActive(MenuBarMetric.anyEnabled(in: defaults))
    }

    private func syncTitleTimer(keepAwakeActive: Bool,
                                showsCountdown: Bool,
                                endDate: Date?) {
        let shouldRun = MenuBarSpacingSupport.needsTitleRefreshTimer(
            keepAwakeActive: keepAwakeActive,
            showsCountdown: showsCountdown,
            hasEndDate: endDate != nil)
        guard shouldRun else {
            titleTimer?.invalidate()
            titleTimer = nil
            return
        }
        guard titleTimer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            // Added to the main run loop below, so it fires on the main thread.
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
    }

    private var currentMicBadgeActive: Bool {
        MicMuteService.shared.isMuted
            && UserDefaults.standard[Preferences.micMuteMenuBarIndicator]
    }

    private var renderedMicBadgeActive: Bool {
        heldMicBadgeActive ?? currentMicBadgeActive
    }

    /// Keeps the variable-width mic badge unchanged while any status item is
    /// anchoring an open panel. The current state is rendered after it closes.
    func setMicBadgeHeld(_ held: Bool) {
        if held {
            guard heldMicBadgeActive == nil else { return }
            heldMicBadgeActive = currentMicBadgeActive
            return
        }
        guard heldMicBadgeActive != nil else { return }
        heldMicBadgeActive = nil
        updateIconAppearance()
    }

    /// Reflects keep-awake state and an available update in the icon. Updates
    /// keep the blue attention glyph; an active session uses the chosen icon.
    /// With the mute indicator option on, a red slashed mic joins the glyph
    /// while the microphone is muted, whatever the underlying state. The
    /// glyph can also hide entirely while metrics render in the title (user
    /// option); the decision reads the button's actual title, so it must run
    /// AFTER refresh() writes it — refresh() calls this at its end.
    private func updateIconAppearance() {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        let updateAvailable: Bool
        if case .available = UpdateService.shared.state {
            updateAvailable = true
        } else {
            updateAvailable = false
        }
        let micBadgeActive = renderedMicBadgeActive
        let optionEnabled = defaults[Preferences.menuBarHideIconWithMetrics]
        let separateMetrics = defaults[Preferences.menuBarSeparateMetrics]
        let signal = updateAvailable || micBadgeActive
        let islandHides = MenuBarSpacingSupport.islandHidesStatusIcon(
            in: defaults, hiddenInFullscreen: islandHiddenInFullscreen) && !signal
        let hidden = islandHides || MenuBarSpacingSupport.shouldHideStatusIcon(
            optionEnabled: optionEnabled,
            separateMetrics: separateMetrics,
            metricsEnabled: MenuBarMetric.anyEnabled(in: defaults),
            renderedTitleLength: button.attributedTitle.length,
            mustShowForSignal: signal)
        // In the separate-items mode the metrics are their own clickable
        // items, so hiding means the whole main item steps aside instead of
        // just its image (which is all that item has). With Dynamic Island
        // standing in, the item goes whenever it has no text of its own.
        let mainItemHidden = (islandHides && button.attributedTitle.length == 0)
            || MenuBarSpacingSupport.shouldHideMainStatusItem(
                optionEnabled: optionEnabled,
                separateMetrics: separateMetrics,
                metricItemsShown: renderedMetricItemCount,
                renderedTitleLength: button.attributedTitle.length,
                mustShowForSignal: signal)
        mainItemHiddenByChoice = mainItemHidden
        let keepAwakeActive = KeepAwakeManager.shared.isActive

        // refresh() runs on every monitor tick and lands here; re-rendering
        // the same image every 2 seconds would be wasted composition, so the
        // image is only touched when some ingredient actually changed.
        let stateKey = [String(hidden), String(mainItemHidden), String(updateAvailable),
                        String(keepAwakeActive), KeepAwakeIconTint.current.rawValue,
                        KeepAwakeActiveIcon.current.rawValue, BlackHoleGlyph.chosenSymbolName,
                        String(micBadgeActive)].joined(separator: "|")
        guard stateKey != lastIconStateKey else { return }
        lastIconStateKey = stateKey

        statusItem.isVisible = !mainItemHidden

        guard !hidden else {
            // A non-nil image lets macOS apply the inactive-display appearance
            // to the title while keeping the glyph visually absent.
            button.image = Self.emptyStatusImage
            return
        }
        let stateImage: NSImage?
        if updateAvailable {
            stateImage = BlackHoleGlyph.attentionImage()
        } else {
            stateImage = BlackHoleGlyph.image(active: keepAwakeActive)
        }
        if micBadgeActive {
            button.image = BlackHoleGlyph.micMutedImage(over: stateImage) ?? stateImage
        } else {
            button.image = stateImage
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?(statusItem.button)
        } else {
            onLeftClick?()
        }
    }

    /// The item a right-click menu opens from: the main one while it is in
    /// the bar, otherwise the item that was clicked. A menu set on an item
    /// that is out of the bar has nowhere on screen to open from.
    func menuHost(for button: NSStatusBarButton?) -> NSStatusItem {
        guard !statusItem.isVisible, let button else { return statusItem }
        let others = [clipboardPreviewStatusItem].compactMap { $0 } + Array(metricStatusItems.values)
        return others.first { $0.button === button } ?? statusItem
    }

    /// Updates the countdown title and tooltip from the current session state.
    func refresh() {
        guard !isRefreshing else {
            refreshRequestedWhileRunning = true
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshRequestedWhileRunning {
                refreshRequestedWhileRunning = false
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
        }
        performRefresh()
    }

    private func performRefresh() {
        guard let button = statusItem?.button else { return }
        let manager = KeepAwakeManager.shared
        let strings = L10n.shared.s
        let defaults = UserDefaults.standard
        let snapshot = SystemMonitor.shared.snapshot
        let metrics = MenuBarMetric.enabled(in: defaults)
        let separateMetrics = defaults[Preferences.menuBarSeparateMetrics]

        syncTitleTimer(keepAwakeActive: manager.isActive,
                       showsCountdown: defaults[Preferences.showCountdown],
                       endDate: manager.endDate)

        // Compose the title from the keep-awake countdown (when shown) followed by
        // the pinned live metrics. Built attributed so the memory pressure dot can
        // carry its green/yellow/red color; all other runs stay adaptive.
        let title = NSMutableAttributedString()
        var includesCountdown = false
        if manager.isActive, defaults[Preferences.showCountdown] {
            let countdown: String
            if let end = manager.endDate {
                let remaining = max(0, Int(end.timeIntervalSinceNow))
                let hours = remaining / 3600
                let minutes = (remaining % 3600) / 60
                countdown = hours > 0 ? String(format: "%d:%02d", hours, minutes) : "\(max(minutes, 1)) min"
            } else {
                countdown = "∞"
            }
            title.append(NSAttributedString(string: countdown))
            includesCountdown = true
        }
        if separateMetrics {
            refreshMetricStatusItems(metrics: metrics, snapshot: snapshot, strings: strings)
        } else {
            removeMetricStatusItems(except: Set<String>())
            renderedMetricItemCount = 0
        }
        if !separateMetrics, !metrics.isEmpty {
            let metricsTitle = MenuBarRenderer.attributed(for: snapshot,
                                                          metrics: metrics,
                                                          allowStacked: !includesCountdown,
                                                          linePrefix: " ")
            if metricsTitle.length > 0 {
                if title.length > 0 { title.append(NSAttributedString(string: "  ")) }
                title.append(metricsTitle)
            }
        }

        // Every write below invalidates the button's layout and redraws the
        // status window even when the value is identical — and this runs on
        // every monitor tick and defaults change. Rounded metric strings
        // repeat most ticks, so skipping no-op writes skips that churn.
        if statusItem.length != NSStatusItem.variableLength {
            statusItem.length = NSStatusItem.variableLength
        }

        if title.length == 0 {
            if button.attributedTitle.length != 0 {
                button.attributedTitle = NSAttributedString(string: "")
            }
            if button.imagePosition != .imageOnly {
                button.imagePosition = .imageOnly
            }
        } else {
            // The leading space separates the glyph from the text; with the
            // glyph hidden by the metrics-only option or by Dynamic Island it
            // would be pure dead padding on the item's left edge. Same
            // decision inputs as updateIconAppearance, with a sentinel length:
            // the title is known non-empty on this branch.
            let updateAvailable: Bool
            if case .available = UpdateService.shared.state {
                updateAvailable = true
            } else {
                updateAvailable = false
            }
            let signal = updateAvailable || renderedMicBadgeActive
            let glyphHidden = (MenuBarSpacingSupport.islandHidesStatusIcon(
                in: defaults, hiddenInFullscreen: islandHiddenInFullscreen) && !signal)
                || MenuBarSpacingSupport.shouldHideStatusIcon(
                    optionEnabled: defaults[Preferences.menuBarHideIconWithMetrics],
                    separateMetrics: separateMetrics,
                    metricsEnabled: !metrics.isEmpty,
                    renderedTitleLength: 1,
                    mustShowForSignal: signal)
            let full = NSMutableAttributedString(string: glyphHidden ? "" : " ")
            full.append(title)
            let stacked = full.string.contains("\n")
            let font = MenuBarRenderer.statusFont(stacked: stacked)
            full.addAttribute(.font, value: font, range: NSRange(location: 0, length: full.length))
            if stacked {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .left
                paragraph.lineBreakMode = .byClipping
                paragraph.minimumLineHeight = MenuBarRenderer.statusLineHeight(stacked: true)
                paragraph.maximumLineHeight = MenuBarRenderer.statusLineHeight(stacked: true)
                full.addAttribute(.paragraphStyle,
                                  value: paragraph,
                                  range: NSRange(location: 0, length: full.length))
                full.addAttribute(.baselineOffset,
                                  value: -0.4,
                                  range: NSRange(location: 0, length: full.length))
            }
            if !full.isEqual(to: button.attributedTitle) {
                button.font = font
                button.attributedTitle = full
            }
            if button.imagePosition != .imageLeading {
                button.imagePosition = .imageLeading
            }
        }

        let toolTip: String
        if manager.isActive {
            if manager.sessionTrigger == .automation {
                toolTip = FeatureStrings.keepAwakeAutomation(L10n.shared.language)
                    .activeStatus(for: manager.activeAutomationConditions)
            } else if let end = manager.endDate {
                toolTip = "\(strings.statusActiveUntil) \(Self.timeFormatter.string(from: end))"
            } else {
                toolTip = strings.statusActiveIndefinite
            }
        } else {
            toolTip = strings.statusIdleTooltip
        }
        if button.toolTip != toolTip {
            button.toolTip = toolTip
        }

        // The icon decision depends on the title just written (the glyph may
        // hide only while metrics actually render), so it re-runs here — the
        // one place where title and icon can never get out of step.
        updateIconAppearance()
    }

    private func refreshMetricStatusItems(metrics: [MenuBarMetric],
                                          snapshot: SystemSnapshot,
                                          strings: Strings) {
        let groups = MenuBarRenderer.metricStatusGroups(for: metrics, strings: strings)
        let wanted = Set(groups.map(\.id))
        removeMetricStatusItems(except: wanted)
        var rendered = 0
        defer { renderedMetricItemCount = rendered }

        for group in groups {
            let title = MenuBarRenderer.attributed(for: snapshot,
                                                   metrics: group.metrics,
                                                   allowStacked: false)
            let empties = title.length > 0 ? 0 : (metricEmptyRenders[group.id] ?? 0) + 1
            metricEmptyRenders[group.id] = empties
            guard MenuBarSpacingSupport.keepsMetricStatusItem(
                hasRenderedTitle: title.length > 0,
                itemExists: metricStatusItems[group.id] != nil,
                consecutiveEmptyRenders: empties) else {
                // The reading has been gone long enough to call it gone.
                removeMetricStatusItem(for: group.id)
                continue
            }
            if title.length > 0 { rendered += 1 }

            metricStatusItemFocus[group.id] = group.focusMetric
            let item = metricStatusItems[group.id] ?? installMetricStatusItem(for: group)
            if item.length != NSStatusItem.variableLength {
                item.length = NSStatusItem.variableLength
            }
            guard let button = item.button else { continue }

            let full = NSMutableAttributedString(attributedString: title)
            let font = MenuBarRenderer.statusFont(stacked: false)
            full.addAttribute(.font,
                              value: font,
                              range: NSRange(location: 0, length: full.length))
            if button.font?.isEqual(font) != true {
                button.font = font
            }
            if !full.isEqual(to: button.attributedTitle) {
                button.attributedTitle = full
            }
            if button.image !== Self.emptyStatusImage {
                button.image = Self.emptyStatusImage
            }
            if button.imagePosition != .noImage {
                button.imagePosition = .noImage
            }
            if button.toolTip != group.title {
                button.toolTip = group.title
            }
        }
    }

    private func installMetricStatusItem(for group: MenuBarRenderer.MetricStatusGroup) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "\(Self.metricAutosavePrefix).\(group.id)"
        item.behavior = []
        // Registered before it is shown: showing it writes its remembered
        // position and announces that write while this call is still on the
        // stack, and an unregistered item would be built all over again by
        // whoever answers that announcement.
        metricStatusItems[group.id] = item
        metricStatusItemFocus[group.id] = group.focusMetric
        item.isVisible = true
        if let button = item.button {
            button.font = MenuBarRenderer.statusFont(stacked: false)
            button.alignment = .left
            button.cell?.lineBreakMode = .byClipping
            button.cell?.usesSingleLineMode = true
            button.target = self
            button.action = #selector(metricClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.identifier = NSUserInterfaceItemIdentifier("\(Self.metricAutosavePrefix).\(group.id)")
        }
        return item
    }

    @objc private func metricClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?(sender)
            return
        }
        guard let metric = focusMetric(from: sender) else {
            onLeftClick?()
            return
        }
        onMetricClick?(metric, sender)
    }

    private func focusMetric(from button: NSStatusBarButton) -> MenuBarMetric? {
        let prefix = "\(Self.metricAutosavePrefix)."
        guard let identifier = button.identifier?.rawValue,
              identifier.hasPrefix(prefix) else { return nil }
        return metricStatusItemFocus[String(identifier.dropFirst(prefix.count))]
    }

    private func removeMetricStatusItems(except wanted: Set<String>) {
        let staleMetrics = metricStatusItems.keys.filter { !wanted.contains($0) }
        for id in staleMetrics {
            removeMetricStatusItem(for: id)
        }
    }

    private func removeMetricStatusItem(for id: String) {
        metricStatusItemFocus.removeValue(forKey: id)
        metricEmptyRenders.removeValue(forKey: id)
        guard let item = metricStatusItems.removeValue(forKey: id) else { return }
        NSStatusBar.system.removeStatusItem(item)
    }

    // MARK: - Clipboard preview item

    /// Creates or removes the clipboard preview item for the feature itself
    /// being on or off, and keeps its text current while it exists — hidden
    /// rather than removed when there is simply nothing to show, so it never
    /// sits in the bar as a bare empty gap.
    /// Runs on every entries/isRunning change and on every settings sync, so
    /// toggling the option or the character limit takes effect immediately.
    private func syncClipboardPreviewItem() {
        let defaults = UserDefaults.standard
        // Checked before ever touching ClipboardHistoryService.shared: merely
        // referencing it brings the whole service to life — its saved history
        // file and image folder included — and this runs on every settings
        // change, not just clipboard ones.
        guard AppFeature.clipboardHistory.isAvailable,
              defaults[Preferences.clipboardHistoryEnabled],
              defaults[Preferences.clipboardHistoryMenuBarPreview]
        else {
            removeClipboardPreviewStatusItem()
            return
        }
        let history = ClipboardHistoryService.shared
        guard history.isRunning else {
            removeClipboardPreviewStatusItem()
            return
        }

        // The feature itself is on; keep the item itself alive even with
        // nothing to show right now (e.g. right after Clear All) rather than
        // removing it — macOS does not reliably restore a dragged position
        // for an item recreated later, so removing it would land it back at
        // the default spot the next time something is copied. Hidden rather
        // than shown blank, though: an empty title would otherwise sit in
        // the bar as a bare gap.
        //
        // No fallback to recentEntries here: latestPasteboardEntry is
        // matched against the pasteboard's real content as soon as history
        // starts watching (at launch, and whenever the feature is toggled
        // back on) and kept correct from then on (nil means the pasteboard
        // was actually cleared, or the last change was deliberately not
        // recorded), so falling back to history would undo exactly that —
        // e.g. auto clear wiping the pasteboard while the entry stays in
        // history.
        let entry = history.latestPasteboardEntry
        let maxCharacters = Defaults.sanitizedClipboardMenuBarPreviewLength(
            defaults[Preferences.clipboardHistoryMenuBarPreviewLength])
        let text = entry?.menuBarText(maxCharacters: maxCharacters) ?? ""

        let item = clipboardPreviewStatusItem ?? installClipboardPreviewStatusItem()
        if item.length != NSStatusItem.variableLength {
            item.length = NSStatusItem.variableLength
        }
        if item.isVisible != (entry != nil) {
            item.isVisible = entry != nil
        }
        guard let button = item.button else { return }
        // A non-nil empty image, not the metric items' actual glyph: same
        // reasoning as their own emptyStatusImage use, so this text also
        // dims correctly on an inactive display instead of staying full
        // strength beside metrics that do.
        if button.image !== Self.emptyStatusImage {
            button.image = Self.emptyStatusImage
        }
        if button.imagePosition != .noImage {
            button.imagePosition = .noImage
        }
        let font = MenuBarRenderer.statusFont(stacked: false)
        if button.font?.isEqual(font) != true {
            button.font = font
        }
        if button.title != text {
            button.title = text
        }
        // menuBarText again rather than entry.preview directly: preview's
        // .files case joins every file name with no bound of its own, so a
        // large batch of files would otherwise make an unbounded tooltip.
        // tooltipCharacters, not previewCharacters: previewCharacters is
        // sized for a list row's three lines, which would still let a whole
        // page of copied prose through as a hover tooltip.
        let tooltip = entry?.menuBarText(maxCharacters: ClipboardHistoryEditing.tooltipCharacters) ?? ""
        if button.toolTip != tooltip {
            button.toolTip = tooltip
        }
    }

    private func installClipboardPreviewStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.clipboardPreviewAutosaveName
        item.behavior = []
        // Registered before it is shown, for the same reason as
        // installMetricStatusItem: showing it writes and announces its
        // remembered position while this call is still on the stack.
        clipboardPreviewStatusItem = item
        item.isVisible = true
        if let button = item.button {
            button.font = MenuBarRenderer.statusFont(stacked: false)
            button.alignment = .left
            button.cell?.lineBreakMode = .byClipping
            button.cell?.usesSingleLineMode = true
            button.target = self
            button.action = #selector(clipboardPreviewClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        return item
    }

    @objc private func clipboardPreviewClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?(clipboardPreviewStatusItem?.button)
            return
        }
        onClipboardPreviewClick?()
    }

    private func removeClipboardPreviewStatusItem() {
        guard let item = clipboardPreviewStatusItem else { return }
        clipboardPreviewStatusItem = nil
        NSStatusBar.system.removeStatusItem(item)
    }
}
