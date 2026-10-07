// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The module's island opens, steps back and follows the session over test
/// doubles (`NotchIslandFixture`): Escape arrives as the open island's own
/// key, and the session changes as the system announces them. Feature
/// choices live only in a disposable test preferences domain.
enum NotchDestinationContract {
    /// The module's launcher over a world of doubles that reads the test's feature switches.
    enum Launcher {
        static var world = QuickLauncherContract.World()
        static var shared: VitruvianServices.QuickLauncherService { world.launcher }
        static func reset(_ defaults: UserDefaults?) {
            world = QuickLauncherContract.World()
            world.defaults = defaults
        }
    }

    private static var defaults: UserDefaults!
    /// Every island a check started; each stops once the checks end.
    private static var started: [NotchIslandFixture] = []
    /// How often the island handed the volume and brightness keys over.
    private static var feedbackRoutingChanges = 0

    /// A started island over this suite's preferences; Tools runs the launcher above.
    private static func island() -> NotchIslandFixture {
        let fixture = NotchIslandFixture(defaults: defaults)
        fixture.services.prepareToolsAction = { Launcher.shared.prepareForPresentation() }
        fixture.start()
        started.append(fixture)
        return fixture
    }

    /// Escape, sent to the open island as the app's own key monitor sends it.
    @discardableResult
    private static func escape(_ fixture: NotchIslandFixture) -> Bool {
        fixture.press(keyCode: UInt16(kVK_Escape))
    }

    /// What the System page asks of the monitor with no detail open.
    private static func pageNeeds(_ defaults: UserDefaults) -> SystemMonitorPanelNeeds {
        var needs = SystemMonitorPanelNeeds.none
        needs.disk = AppFeature.monitorDisk.isAvailable(in: defaults)
        needs.fanSpeed = AppFeature.fanControl.isAvailable(in: defaults)
        needs.connectedDevices = AppFeature.connectedDevices.isAvailable(in: defaults)
        return needs
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.notch-destinations"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        Self.defaults = defaults
        Launcher.reset(defaults)
        NotchService.collaborators = NotchCollaborators(feedbackRoutingDidChange: { feedbackRoutingChanges += 1 })
        defer {
            started.forEach { $0.island.stop() }
            started.removeAll()
            NotchService.collaborators = NotchCollaborators()
            Self.defaults = nil
            defaults.removePersistentDomain(forName: domain)
            Launcher.reset(nil)
        }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        scratchpadContracts(defaults: defaults, suite: suite)
        reopeningContracts(defaults: defaults, suite: suite)
        countdownContracts(defaults: defaults, suite: suite)
        stepBackContracts(suite)
        // A page opened while the Command Bar is in the island takes its place.
        var commandBarClosings = 0
        NotchService.collaborators = NotchCollaborators(feedbackRoutingDidChange: { feedbackRoutingChanges += 1 },
                                                        commandBarIslandDidClose: { commandBarClosings += 1 })
        let barHost = island()
        let barPanel = barHost.island.presentCommandBar()
        barHost.island.open(.controls)
        suite.expect(barPanel != nil && barHost.island.expanded && !barHost.island.showingCommandBar
                     && barHost.island.selected == .controls && commandBarClosings == 1,
                     "opening a page in place of the Command Bar closes the bar once")
        barHost.island.open(.controls)
        suite.expect(commandBarClosings == 1, "opening a page without the bar leaves the bar alone")
        for resting in [NotchIdleContent.none, .music] {
            defaults.set(resting.rawValue, forKey: DefaultsKey.notchIdleContent)
            defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
            let fixture = island()
            let service = fixture.island
            service.open(.music)
            suite.expect(service.expanded && service.selected == .music && fixture.host?.panel.acceptsKeyFocus == true,
                   "hiding automatic music preserves explicit opening of its controls")
            service.open(.controls)
            suite.expect(service.expanded && service.selected == .controls
                   && NotchSupport.controls(in: defaults).contains(.music),
                   "hiding automatic music preserves playback controls on the island's home page")
        }
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        let families: [(MetricDetailKind, AppFeature)] = [
            (.cpu, .monitorCPU), (.gpu, .monitorGPU), (.memory, .monitorMemory),
            (.network, .monitorNetwork), (.disk, .monitorDisk),
            (.battery, .monitorPower), (.power, .monitorPower), (.fan, .fanControl),
            (.connectedDevices, .connectedDevices),
        ]
        for (metric, feature) in families {
            let fixture = island()
            let service = fixture.island
            service.open(.system, pinned: true, metric: metric)
            suite.expect(service.selectedMetric == metric, "an available metric opens its own detail")
            defaults.set(false, forKey: feature.availabilityKey)
            service.syncWithPreferences()
            suite.expect(service.selectedMetric == nil && fixture.services.monitorDetailNeeds == pageNeeds(defaults),
                   "removing the selected metric clears its detail even when other system families remain")
            service.open(.system, metric: metric, sections: true)
            service.open(.system, metric: metric)
            suite.expect(service.selectedMetric == nil,
                   "a retained gallery argument cannot restore a metric removed from the hub")
            defaults.set(true, forKey: feature.availabilityKey)
        }
        // The System page reads connected devices for its card while it shows
        // them, and only while the feature is installed.
        let devices = island()
        devices.island.open(.system)
        suite.expect(devices.services.monitorDetailNeeds.connectedDevices,
               "the island's System page reads connected devices for its card")
        devices.island.open(.system, sections: true)
        suite.expect(!devices.services.monitorDetailNeeds.connectedDevices,
               "the section gallery over the System page stops its device reads")
        defaults.set(false, forKey: AppFeature.connectedDevices.availabilityKey)
        devices.island.syncWithPreferences()
        devices.island.open(.system)
        suite.expect(!devices.services.monitorDetailNeeds.connectedDevices,
               "an uninstalled connected devices feature is not read for the System page")
        defaults.set(true, forKey: AppFeature.connectedDevices.availabilityKey)
        let fixture = island()
        let service = fixture.island
        service.open(.system, metric: .cpu)
        for (_, feature) in families { defaults.set(false, forKey: feature.availabilityKey) }
        service.syncWithPreferences()
        suite.expect(!service.modules.contains(.system) && service.selected == .controls
               && service.selectedMetric == nil && fixture.services.monitorDetailNeeds == SystemMonitorPanelNeeds.none,
               "removing the last system family selects an available module without keeping its old detail")
        defaults.set(true, forKey: AppFeature.fanControl.availabilityKey)
        service.open(.system, metric: .fan)
        suite.expect(service.modules.contains(.system) && service.selectedMetric == .fan,
               "a separately installed fan feature exposes System and retains its direct detail")

        Launcher.reset(defaults)
        let launcher = Launcher.shared
        let firstPresentation = launcher.presentationID
        service.open(.tools)
        suite.expect(service.selected == .tools && launcher.selectedIndex == 0 && launcher.presentationID != firstPresentation,
               "opening Tools inside the island prepares keyboard selection on its first presentation")
        Launcher.world.events.removeAll()
        let enter = QuickLauncherContract.Key(keyCode: UInt16(kVK_Return))
        suite.expect(launcher.takesPanelKey(enter, flow: .columns(rows: 2))
               && Launcher.world.events == ["perform keepAwake"],
               "Return works immediately after the island opens Tools")
        let unchangedPresentation = launcher.presentationID
        service.open(.tools)
        suite.expect(launcher.presentationID == unchangedPresentation,
               "reopening the same visible Tools destination does not reset its working presentation")
        launcher.run(.urlCleaner)
        service.open(.controls)
        service.open(.tools)
        suite.expect(launcher.activeUtility == .urlCleaner,
               "navigation preserves a still-available hosted utility")
        service.open(.controls)
        defaults.set(false, forKey: AppFeature.urlCleaner.availabilityKey)
        service.open(.tools)
        suite.expect(launcher.activeUtility == nil,
               "returning to Tools after removal cannot revive its previous utility")
        service.open(.controls)
        Launcher.world.order = []
        service.open(.tools)
        suite.expect(launcher.selectedIndex == nil, "an empty Tools module leaves keyboard activation without a target")
        sessionContracts(suite)
        lockScreenContracts(defaults: defaults, suite: suite)
    }

    /// Escape steps back through what the island shows, then closes it.
    private static func stepBackContracts(_ suite: TestSuite) {
        let metricIsland = island()
        let metric = metricIsland.island
        metric.open(.system)
        metric.open(.system, metric: .cpu)
        suite.expect(escape(metricIsland), "the open island takes Escape as its own key")
        suite.expect(metric.expanded && metric.selected == .system && metric.selectedMetric == nil,
                     "Escape steps back from a detail opened on its page, as the Back button does")
        escape(metricIsland)
        suite.expect(!metric.expanded, "Escape closes the island once nothing lies behind the page")

        let panelIsland = island()
        let panel = panelIsland.island
        panel.open(.music)
        panel.open(.controls, appPanel: true)
        escape(panelIsland)
        suite.expect(panel.expanded && panel.selected == .controls && !panel.showingAppPanel,
                     "Escape steps back from the app panel opened inside the island")

        // Closing passes for any page, so these first check a detail is open.
        for appPanel in [false, true] {
            let directIsland = island()
            let direct = directIsland.island
            direct.open(appPanel ? .controls : .system, appPanel: appPanel, metric: appPanel ? nil : .cpu)
            let detail = direct.showingAppPanel || direct.selectedMetric == .cpu
            escape(directIsland)
            suite.expect(detail && !direct.expanded,
                         "a detail the island opened on closes on Escape like the menu panel (app panel: \(appPanel))")
        }

        for route in ["a metric", "the app panel"] {
            let menuBarIsland = island()
            let menuBar = menuBarIsland.island
            menuBar.open(.music)
            if route == "a metric" { menuBar.showMetric(.cpu, toggle: true) } else { menuBar.openAppPanel(toggle: true) }
            let detail = menuBar.selectedMetric == .cpu || menuBar.showingAppPanel
            escape(menuBarIsland)
            suite.expect(detail && !menuBar.expanded,
                         "\(route) opened from the menu bar over an open island closes on Escape like the menu panel")
        }
        let tileIsland = island()
        let tile = tileIsland.island
        tile.open(.system)
        tile.showMetric(.cpu)
        escape(tileIsland)
        suite.expect(tile.expanded && tile.selected == .system && tile.selectedMetric == nil,
                     "a metric opened from its tile inside the island steps back to the page")

        let switchedIsland = island()
        let switched = switchedIsland.island
        switched.open(.system, metric: .cpu)
        switched.toggleSections()
        switched.toggleSections()
        switched.open(.system, metric: .memory)
        let switchedDetail = switched.selectedMetric == .memory && !switched.showingSections
        escape(switchedIsland)
        suite.expect(switchedDetail && !switched.expanded,
                     "passing through the gallery or switching details keeps a direct detail closing on Escape")

        let galleryIsland = island()
        let gallery = galleryIsland.island
        gallery.open(.system)
        gallery.open(.system, metric: .cpu)
        gallery.toggleSections()
        gallery.toggleSections()
        escape(galleryIsland)
        suite.expect(gallery.expanded && gallery.selected == .system && gallery.selectedMetric == nil,
                     "the gallery opened over a detail keeps its way back to the page")

        let reopenedIsland = island()
        let reopened = reopenedIsland.island
        reopened.open(.system)
        reopened.open(.system, metric: .cpu)
        // Capture controls close the island without clearing its detail.
        reopened.presentCaptureControls(captureOptions(), cancel: {})
        reopened.endCaptureControls()
        let closedOnDetail = !reopened.expanded && reopened.selectedMetric == .cpu
        reopened.open(.system, metric: .cpu)
        let reopenedDetail = reopened.expanded && reopened.selectedMetric == .cpu
        escape(reopenedIsland)
        suite.expect(closedOnDetail && reopenedDetail && !reopened.expanded,
                     "a detail the island reopens on has nothing behind it")

        var closes: [NotchModule] = []
        let layeredIsland = island()
        let layered = layeredIsland.island
        layered.open(.music)
        layered.setPageLayer(.music) { closes.append(.music); layered.setPageLayer(.music, close: nil) }
        layered.setPageLayer(.calendar) { closes.append(.calendar) }
        escape(layeredIsland)
        suite.expect(layered.expanded && closes == [.music], "Escape closes the page's own layer before the island")
        escape(layeredIsland)
        suite.expect(!layered.expanded && closes == [.music], "only the visible page's layer answers Escape")

        let coveredIsland = island()
        let covered = coveredIsland.island
        covered.open(.system)
        covered.setPageLayer(.system) { closes.append(.system) }
        covered.open(.system, metric: .cpu)
        escape(coveredIsland)
        suite.expect(covered.selectedMetric == nil && closes == [.music],
                     "a detail steps back before a layer of the page it covers")

        let heldIsland = island()
        let held = heldIsland.island
        held.open(.system)
        held.open(.system, metric: .cpu)
        held.fileDragChanged(true, internalDrag: true)
        escape(heldIsland)
        suite.expect(held.expanded && held.selectedMetric == .cpu,
                     "Escape leaves the island as it is during a drag, like closing does")

        // Capture controls take the island's keys for themselves.
        let capturingIsland = island()
        let capturing = capturingIsland.island
        capturing.open(.system)
        capturing.open(.system, metric: .cpu)
        capturing.presentCaptureControls(captureOptions(), cancel: {})
        let escaped = escape(capturingIsland)
        capturing.collapse()
        suite.expect(!escaped && capturing.captureControls != nil && capturing.selectedMetric == .cpu,
                     "Escape leaves the island as it is during a capture, like closing does")
        capturing.endCaptureControls()
    }

    private static func captureOptions() -> ScreenCaptureSelectionOptions {
        ScreenCaptureSelectionOptions(availableTools: [.screenshot], selectedTool: .screenshot, showsCaptureMenu: false)
    }

    private static func scratchpadContracts(defaults: UserDefaults, suite: TestSuite) {
        let fixture = island()
        let service = fixture.island
        suite.expect(service.showScratchpad(toggle: true) && service.expanded && service.selected == .scratchpad,
                     "the Scratchpad shortcut opens its configured island destination")
        fixture.host?.hasKeyboard = false
        suite.expect(service.showScratchpad(toggle: true) && service.expanded && fixture.host?.hasKeyboard == true,
                     "a visible Scratchpad without keyboard focus is focused instead of closed")
        suite.expect(service.showScratchpad(toggle: true) && !service.expanded,
                     "the shortcut closes a Scratchpad that already owns the keyboard")
        defaults.set(false, forKey: DefaultsKey.notchScratchpad)
        suite.expect(!service.showScratchpad() && !service.expanded,
                     "choosing a separate Scratchpad window leaves the island untouched")
        defaults.set(true, forKey: DefaultsKey.notchScratchpad)
        let hidesInFullscreen = defaults.bool(forKey: DefaultsKey.notchHideInFullscreen)
        defaults.set(true, forKey: DefaultsKey.notchHideInFullscreen)
        defer { defaults.set(hidesInFullscreen, forKey: DefaultsKey.notchHideInFullscreen) }
        fixture.fullscreen = [NotchIslandFixture.display.id]
        service.syncWithPreferences()
        suite.expect(service.hiddenInFullscreen && service.showScratchpad() && service.expanded,
                     "a full-screen user shortcut opens Scratchpad despite hidden automatic feedback")
        service.collapse()
        fixture.host?.concealForMissionControl()
        suite.expect(!service.showScratchpad() && !service.expanded,
                     "an unavailable island hands Scratchpad opening back to its ordinary window")
    }

    private static func reopeningContracts(defaults: UserDefaults, suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchReturnHome] as? Bool == false,
               "returning home is opt-in and preserves the existing opening behavior")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHomeModule] as? String == NotchModule.controls.rawValue,
               "the previously available home option keeps Controls as its initial destination")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchOpensActivity] as? Bool == true,
               "opening the visible activity stays the default")
        for returnHome in [false, true] {
            defaults.set(returnHome, forKey: DefaultsKey.notchReturnHome)
            let payload = SettingsBackupSupport.payload(appVersion: "test") {
                if $0 == DefaultsKey.notchReturnHome { return returnHome }
                if $0 == DefaultsKey.notchHomeModule { return NotchModule.music.rawValue }
                if $0 == DefaultsKey.notchOpensActivity { return false }
                if $0 == DefaultsKey.notchHideUntilHover { return true }
                if $0 == DefaultsKey.notchHoverDelay { return 0.65 }
                return nil
            }
            let data = try? JSONSerialization.data(withJSONObject: payload)
            let decoded = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            let restored = decoded.flatMap { SettingsBackupSupport.sanitizedSettings(from: $0) }
            suite.expect(restored?[DefaultsKey.notchReturnHome] as? Bool == returnHome
                   && restored?[DefaultsKey.notchHomeModule] as? String == NotchModule.music.rawValue
                   && restored?[DefaultsKey.notchOpensActivity] as? Bool == false
                   && restored?[DefaultsKey.notchHoverDelay] as? Double == 0.65
                   && restored?[DefaultsKey.notchHideUntilHover] as? Bool == true,
                   "the opening behavior, selected page, activity choice and activation time survive backup and restore")

            let service = island().island
            service.open(.files)
            service.open()
            suite.expect(service.selected == .files, "an already open island does not jump away from the current page")
            service.collapse()
            service.open()
            suite.expect(service.selected == (returnHome ? .controls : .files),
                   "reopening either restores the last page or returns home according to the preference")
            service.collapse()
            service.open(.music)
            suite.expect(service.selected == .music, "an explicit destination always wins over the opening preference")
            defaults.set("controls", forKey: DefaultsKey.notchHiddenModules)
            defaults.set("files,music", forKey: DefaultsKey.notchModuleOrder)
            service.collapse()
            service.open()
            suite.expect(service.selected == (returnHome ? .files : .music),
                   "a hidden home page falls back to the first visible page without unhiding controls")
            defaults.set("", forKey: DefaultsKey.notchHiddenModules)
            defaults.set("", forKey: DefaultsKey.notchModuleOrder)
        }
        defaults.set(true, forKey: DefaultsKey.notchReturnHome)
        for page in NotchSupport.modules(in: defaults) {
            defaults.set(page.rawValue, forKey: DefaultsKey.notchHomeModule)
            let service = island().island
            service.open()
            suite.expect(service.selected == page, "each available page can be chosen for reopening: \(page.rawValue)")
            service.open(.files)
            suite.expect(service.selected == .files, "a saved opening page never overrides explicit navigation")
            defaults.set(page.rawValue, forKey: DefaultsKey.notchHiddenModules)
            service.collapse()
            service.open()
            suite.expect(service.selected == NotchSupport.modules(in: defaults).first,
                   "hiding the saved opening page falls back to an available page")
            defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        }
        for destination in NotchReopeningDestination.allCases {
            defaults.set(destination.rawValue, forKey: DefaultsKey.notchHomeModule)
            let fixture = island()
            let service = fixture.island
            service.open(.files)
            service.collapse()
            let focusRequests = fixture.services.count("showNormalMenuPanel")
            service.open()
            suite.expect(service.showingAppPanel == (destination == .appPanel)
                   && service.showingSections == (destination == .explore),
                   "reopening shows the selected app panel or Explore destination")
            if destination == .explore {
                suite.expect(service.highlightedSection == .files && service.sectionQuery.isEmpty,
                       "reopening Explore highlights its current page for keyboard navigation")
            }
            suite.expect(fixture.services.count("showNormalMenuPanel") - focusRequests == (destination == .appPanel ? 1 : 0),
                   "only opening the app panel resets its panel focus")
            service.collapse()
            service.open(.music)
            suite.expect(service.selected == .music && !service.showingAppPanel && !service.showingSections,
                   "explicit page navigation wins over a saved app panel or Explore destination")

            service.collapse()
            show(.timer, on: fixture)
            service.open()
            suite.expect(service.selected == .timer && !service.showingAppPanel && !service.showingSections,
                   "a visible activity wins over a saved app panel or Explore destination")

            defaults.set(false, forKey: DefaultsKey.notchOpensActivity)
            service.collapse()
            service.open()
            suite.expect(service.showingAppPanel == (destination == .appPanel)
                   && service.showingSections == (destination == .explore),
                   "with activities turned off, a visible activity leaves the saved app panel or Explore destination")
            service.collapse()
            service.openActivity(.timer)
            suite.expect(service.showingAppPanel == (destination == .appPanel)
                   && service.showingSections == (destination == .explore),
                   "with activities turned off, a tap on the activity's strip follows the reopening choice too")
            defaults.set(true, forKey: DefaultsKey.notchOpensActivity)
            service.collapse()
            service.openActivity(.timer)
            suite.expect(service.selected == .timer && !service.showingAppPanel && !service.showingSections,
                   "a tap on the activity's strip opens its page while activities open")
        }
        defaults.set("unknown-page", forKey: DefaultsKey.notchHomeModule)
        let invalid = island().island
        invalid.open()
        suite.expect(invalid.selected == .controls, "a malformed saved page falls back to Controls")
        defaults.set(NotchModule.controls.rawValue, forKey: DefaultsKey.notchHomeModule)
        defaults.set(false, forKey: DefaultsKey.notchReturnHome)
        activityContracts(defaults: defaults) { suite.expect($0, $1) }
    }

    /// Has the island's services report `activity` as the only one under way,
    /// so the closed island shows it; nil clears them all.
    private static func show(_ activity: NotchCompactActivity?, on fixture: NotchIslandFixture) {
        let services = fixture.services
        services.timerSession = NotchTimerSession()
        services.downloads = []
        services.calendarCountdown = nil
        services.playback = nil
        services.keepAwakeActive = false
        let now = Date()
        switch activity {
        case .timer:
            services.timerSession = NotchTimerSession(anchor: services.timerNow + 300)
        case .downloads:
            services.downloads = [NotchDownloadItem(id: "archive", url: URL(fileURLWithPath: "/tmp/archive.zip"),
                                                    name: "archive.zip", receivedBytes: 512, fraction: 0.5,
                                                    completed: false)]
        case .calendar:
            let event = NotchCalendarEvent(id: "standup", title: "Standup", calendar: "Personal",
                                           start: now.addingTimeInterval(-300), end: now.addingTimeInterval(300),
                                           allDay: false, location: "")
            services.calendarCountdown = NotchCalendarCountdown(event: event, ongoing: true)
        case .music:
            services.playback = NotchPlayback(
                track: RadialNowPlayingSnapshot(title: "Song", artist: "Artist", album: nil, artworkData: nil,
                                                appBundleIdentifier: "org.example.player", appPID: 42),
                isPlaying: true, elapsed: 0, duration: 200, rate: 1, sampledAt: now, canSeek: false)
        case .keepAwake:
            services.keepAwakeActive = true
        default:
            break
        }
    }

    /// A click on the closed island's countdown opens Calendar on its event;
    /// a page that opens in Calendar's place keeps no event for a later visit.
    private static func countdownContracts(defaults: UserDefaults, suite: TestSuite) {
        let keys = [DefaultsKey.notchCalendarTimeLeft, DefaultsKey.notchOpensActivity,
                    DefaultsKey.notchReturnHome, DefaultsKey.notchHomeModule]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        defaults.set(true, forKey: DefaultsKey.notchCalendarTimeLeft)
        defaults.set(true, forKey: DefaultsKey.notchOpensActivity)
        let fixture = island()
        let service = fixture.island
        show(.calendar, on: fixture)
        let event = fixture.services.calendarCountdown?.event.id
        service.openCountdownEvent()
        suite.expect(event != nil && service.expanded && service.selected == .calendar
                     && fixture.services.revealedCalendarEvent == event,
                     "a click on the event countdown opens Calendar on its event")
        service.collapse()
        // With activities turned off the island reopens its home page instead.
        defaults.set(false, forKey: DefaultsKey.notchOpensActivity)
        defaults.set(true, forKey: DefaultsKey.notchReturnHome)
        defaults.set(NotchModule.controls.rawValue, forKey: DefaultsKey.notchHomeModule)
        service.openCountdownEvent()
        suite.expect(service.expanded && service.selected != .calendar
                     && fixture.services.revealedCalendarEvent == nil,
                     "a page opened in Calendar's place keeps no event for later")
    }

    /// What the closed island is already showing is what opening it shows,
    /// unless the user turned that off for activities.
    private static func activityContracts(defaults: UserDefaults, expect: (Bool, String) -> Void) {
        let banner = NotchNotice(event: .systemNotification, title: "Alex", detail: "Hello", symbol: "bell.fill",
                                 notification: NotchNotificationContent(app: "Chat", title: "Alex", subtitle: "", body: "Hello"),
                                 notificationID: UUID())
        // Each activity the closed island can show is turned on.
        let switches = [DefaultsKey.notchNotificationsEnabled, DefaultsKey.notchCalendarTimeLeft,
                        DefaultsKey.notchKeepAwakeActivity, DefaultsKey.notchShowPlayingMusic,
                        DefaultsKey.notchOpenOnHover, NotchEvent.download.preferenceKey,
                        NotchEvent.systemNotification.preferenceKey, NotchEvent.volume.preferenceKey]
        let saved = switches.map { defaults.object(forKey: $0) }
        let idleContent = defaults.object(forKey: DefaultsKey.notchIdleContent)
        for key in switches { defaults.set(true, forKey: key) }
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        defer {
            for (key, value) in zip(switches, saved) { defaults.set(value, forKey: key) }
            defaults.set(idleContent, forKey: DefaultsKey.notchIdleContent)
        }
        for returnHome in [false, true] {
            defaults.set(returnHome, forKey: DefaultsKey.notchReturnHome)
            defaults.set(NotchModule.controls.rawValue, forKey: DefaultsKey.notchHomeModule)
            for activity in [NotchCompactActivity.timer, .downloads, .calendar, .music, .keepAwake] {
                let fixture = island()
                let service = fixture.island
                service.open(.files)
                service.collapse()
                show(activity, on: fixture)
                expect(service.compactActivity == activity && service.reopeningModule == activity.module,
                       "a visible activity is what a peek names before opening (\(activity))")
                service.open()
                expect(service.selected == activity.module,
                       "hovering or clicking an island that shows \(activity) opens that activity, not the reopening page")
                service.open()
                expect(service.selected == activity.module, "an already open island stays on the activity's page")
                service.open(.files)
                expect(service.selected == .files, "an explicit page still wins over the visible activity")
                service.collapse()
                show(nil, on: fixture)
                service.open()
                expect(service.selected == (returnHome ? .controls : .files),
                       "once the activity ends, reopening follows the saved preference again")

                defaults.set(false, forKey: DefaultsKey.notchOpensActivity)
                service.open(.files)
                service.collapse()
                show(activity, on: fixture)
                expect(service.reopeningModule == (returnHome ? .controls : .files),
                       "with activities turned off, a peek over \(activity) names the reopening page")
                service.open()
                expect(service.selected == (returnHome ? .controls : .files),
                       "with activities turned off, opening an island that shows \(activity) follows the saved preference")
                service.open(activity.module)
                expect(service.selected == activity.module,
                       "with activities turned off, the page of \(activity) still opens when named")
                defaults.set(true, forKey: DefaultsKey.notchOpensActivity)
            }
            let hiddenIsland = island()
            let hidden = hiddenIsland.island
            defaults.set("timer", forKey: DefaultsKey.notchHiddenModules)
            hidden.syncWithPreferences()
            show(.timer, on: hiddenIsland)
            hidden.open()
            expect(hidden.selected == .controls && !hidden.modules.contains(.timer),
                   "an activity whose page is hidden cannot open it and falls back to the reopening rule")
            defaults.set("", forKey: DefaultsKey.notchHiddenModules)

            // A banner arriving under the pointer is held, and a deliberate
            // hover opens its whole message in place.
            let mirroredIsland = island()
            let mirrored = mirroredIsland.island
            mirroredIsland.pointer = NotchIslandFixture.onIsland
            let shown = mirrored.show(banner)
            mirroredIsland.runScheduled()
            expect(shown && mirrored.noticeExpanded && mirrored.reopeningModule == .notifications,
                   "a mirrored banner on the island points at the inbox")
            mirrored.open()
            expect(mirrored.selected == .notifications && mirrored.notice == nil && !mirrored.noticeExpanded,
                   "opening over a held banner shows the inbox and retires the banner so it cannot return after collapsing")
            mirrored.collapse()
            mirroredIsland.runScheduled()
            expect(mirrored.notice == nil, "a retired banner does not come back once the island closes")
            defaults.set(false, forKey: DefaultsKey.notchOpensActivity)
            let bannerIsland = island()
            let bannerOverMusic = bannerIsland.island
            show(.music, on: bannerIsland)
            let bannerShown = bannerOverMusic.show(banner)
            bannerOverMusic.open()
            expect(bannerShown && bannerOverMusic.selected == .notifications && bannerOverMusic.notice == nil,
                   "turning activities off still opens the inbox over a mirrored banner, which is not an activity")
            defaults.set(true, forKey: DefaultsKey.notchOpensActivity)
            let volume = island().island
            let volumeShown = volume.show(NotchNotice(event: .volume, title: "Volume", detail: "50%",
                                                      symbol: "speaker.wave.2.fill", level: 0.5))
            volume.open()
            expect(volumeShown && volume.notice != nil && volume.selected == .controls,
                   "system feedback keeps its own timer and never redirects an opening")
        }
        defaults.set(false, forKey: DefaultsKey.notchReturnHome)
    }

    /// The system's announcements of each session change, as
    /// `NotchSessionTracker` hears them.
    private enum Announcement {
        case lock, unlock, displaysSleep, displaysWake, sleep, wake, leaveConsole, returnToConsole
        case screenSaverStart, screenSaverStop
    }

    private static func announce(_ announcement: Announcement, to fixture: NotchIslandFixture) {
        switch announcement {
        case .lock: fixture.post(session: "com.apple.screenIsLocked")
        case .unlock: fixture.post(session: "com.apple.screenIsUnlocked")
        case .displaysSleep: fixture.post(workspace: NSWorkspace.screensDidSleepNotification)
        case .displaysWake: fixture.post(workspace: NSWorkspace.screensDidWakeNotification)
        case .sleep: fixture.post(workspace: NSWorkspace.willSleepNotification)
        case .wake: fixture.post(workspace: NSWorkspace.didWakeNotification)
        case .leaveConsole: fixture.post(workspace: NSWorkspace.sessionDidResignActiveNotification)
        case .returnToConsole: fixture.post(workspace: NSWorkspace.sessionDidBecomeActiveNotification)
        case .screenSaverStart: fixture.post(session: "com.apple.screensaver.didstart")
        case .screenSaverStop: fixture.post(session: "com.apple.screensaver.didstop")
        }
    }

    /// The lock screen follows the island's own teardown, so what it starts is
    /// never stopped under it. On unlock it starts leaving before the island
    /// returns and stops nothing the island takes back. The padlock plays only
    /// for a lock or unlock made at the Mac.
    private static func lockScreenContracts(defaults: UserDefaults, suite: TestSuite) {
        defer { defaults.set(false, forKey: DefaultsKey.notchLockSounds) }
        let fixture = island()
        let services = fixture.services
        // A teardown stops the island's notifications; a return syncs its calendar.
        var order: [String] = []
        services.onSyncLockScreen = { _ in
            order.append("sync after \(services.count("stopNotifications")) teardowns, \(services.count("syncCalendar")) returns")
        }
        defaults.set(true, forKey: DefaultsKey.notchLockSounds)
        announce(.lock, to: fixture)
        suite.expect(order == ["sync after 1 teardowns, 0 returns"] && services.lockScreenSyncs.last?.showsLockScreen == true,
                     "the lock screen takes over after the island has stopped its own sources")
        announce(.unlock, to: fixture)
        // The first sync is the scene leaving: canPresent tells it to stop
        // none of the sources the island is about to take back.
        suite.expect(order == ["sync after 1 teardowns, 0 returns", "sync after 1 teardowns, 0 returns",
                               "sync after 1 teardowns, 1 returns"]
                     && services.lockScreenSyncs.count == 3
                     && services.lockScreenSyncs.dropFirst().allSatisfy { !$0.locked && $0.canPresent },
                     "on unlock the lock screen starts leaving before the island returns and stops nothing it takes back")
        suite.expect(services.lockSounds == [true, false], "locking and unlocking at the Mac each play their padlock")
        announce(.displaysSleep, to: fixture)
        announce(.lock, to: fixture)
        suite.expect(services.lockSounds == [true, false] && services.lockScreenSyncs.last?.showsLockScreen == false,
                     "a lock that comes with a dark display plays nothing and shows nothing")
        announce(.displaysWake, to: fixture)
        suite.expect(services.lockScreenSyncs.last?.showsLockScreen == true, "waking the display shows the lock screen")
        announce(.screenSaverStart, to: fixture)
        suite.expect(services.lockScreenSyncs.last?.showsLockScreen == false && services.lockSounds.count == 2,
                     "a screen saver hides the lock screen without a sound")
        announce(.screenSaverStop, to: fixture)
        defaults.set(false, forKey: DefaultsKey.notchLockSounds)
        announce(.unlock, to: fixture)
        suite.expect(services.lockSounds.count == 2, "with the sounds off, unlocking is silent")
        defaults.set(true, forKey: DefaultsKey.notchLockSounds)
        announce(.lock, to: fixture)
        announce(.displaysSleep, to: fixture)
        announce(.unlock, to: fixture)
        announce(.displaysWake, to: fixture)
        suite.expect(services.lockSounds == [true, false, true, false],
                     "an unlock announced before the display wakes still plays its padlock")
        fixture.island.stop()
        let syncs = services.lockScreenSyncs.count
        announce(.lock, to: fixture)
        suite.expect(services.lockScreenSyncs.count == syncs && services.lockSounds.count == 4,
                     "a stopped island leaves the lock screen alone")
    }

    /// A teardown stops the island's notifications and a return syncs its
    /// calendar; the timer runs until suspended.
    private static func sessionContracts(_ suite: TestSuite) {
        let fixture = island()
        let service = fixture.island
        let services = fixture.services
        feedbackRoutingChanges = 0
        announce(.displaysSleep, to: fixture)
        suite.expect(services.timerRunning && services.count("suspendTimer") == 0 && services.count("syncTimer") == 0
               && services.count("stopNotifications") == 1 && !service.acceptsUserInteraction,
               "display sleep removes presentation while leaving the timer and alarm uninterrupted")
        suite.expect(feedbackRoutingChanges == 1,
               "the brightness keys go back to the system while the island is torn down")
        announce(.sleep, to: fixture)
        suite.expect(!services.timerRunning && services.count("suspendTimer") == 1 && services.count("stopNotifications") == 1,
               "system sleep suspends the timer even after the display already hid the island")
        announce(.lock, to: fixture)
        announce(.displaysWake, to: fixture)
        announce(.wake, to: fixture)
        suite.expect(!services.timerRunning && services.count("syncTimer") == 0 && services.count("syncCalendar") == 0,
               "display and system wake cannot resume an alarm or presentation while the session is locked")
        announce(.unlock, to: fixture)
        suite.expect(services.timerRunning && services.count("syncTimer") == 1 && services.count("syncCalendar") == 1,
               "unlocking after every sleep condition clears resumes through the normal presentation path once")

        announce(.displaysSleep, to: fixture)
        announce(.leaveConsole, to: fixture)
        suite.expect(!services.timerRunning && services.count("suspendTimer") == 2,
               "switching users suspends an alarm even when the display is already asleep")
        announce(.returnToConsole, to: fixture)
        suite.expect(services.timerRunning && services.count("syncTimer") == 2 && services.count("syncCalendar") == 1
               && !service.acceptsUserInteraction,
               "returning to the same awake session resumes only the timer while its display remains asleep")
        announce(.displaysWake, to: fixture)
        suite.expect(services.timerRunning && services.count("syncCalendar") == 2,
               "the island returns only after the display also wakes")
        announce(.displaysSleep, to: fixture)
        announce(.lock, to: fixture)
        announce(.leaveConsole, to: fixture)
        announce(.unlock, to: fixture)
        announce(.displaysWake, to: fixture)
        suite.expect(!services.timerRunning && services.count("syncCalendar") == 2,
               "unlock and display wake cannot resume work while another login session owns the console")
        service.stop()
        announce(.returnToConsole, to: fixture)
        suite.expect(!services.timerRunning && services.count("syncCalendar") == 2,
               "late session notifications cannot restart a stopped island or timer")
    }
}
