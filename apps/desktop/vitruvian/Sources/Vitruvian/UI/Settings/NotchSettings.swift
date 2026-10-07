// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import EventKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices

package struct NotchSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var router = SettingsRouter.shared
    @AppStorage(Preferences.notchGesturesEnabled) private var gesturesEnabled: Bool
    @AppStorage(Preferences.notchKeyboardLight) private var keyboardLight: Bool
    @AppStorage(Preferences.notchNotificationsEnabled) private var notificationsEnabled: Bool
    @AppStorage(Preferences.notchDismissNativeNotifications) private var dismissNativeNotifications: Bool
    @AppStorage(Preferences.notchTimerEnabled) private var timerEnabled: Bool
    @AppStorage(Preferences.notchTimerSoundEnabled) private var timerSoundEnabled: Bool
    @AppStorage(Preferences.notchHideTimerCountdown) private var hideTimerCountdown: Bool
    @AppStorage(Preferences.notchCameraEnabled) private var cameraEnabled: Bool
    @AppStorage(Preferences.notchAccessoriesEnabled) private var accessoriesEnabled: Bool
    @AppStorage(Preferences.notchCalendarEnabled) private var calendarEnabled: Bool
    @AppStorage(Preferences.notchCalendarCountdown) private var calendarCountdown: Bool
    @AppStorage(Preferences.notchCalendarTimeLeft) private var calendarTimeLeft: Bool
    @AppStorage(Preferences.notchCalendarWeekNumbers) private var calendarWeekNumbers: Bool
    @AppStorage(Preferences.notchAgentsEnabled) private var agentsEnabled: Bool
    @AppStorage(Preferences.notchWatchEnabled) private var watchEnabled: Bool
    @AppStorage(Preferences.notchLyricsEnabled) private var lyricsEnabled: Bool
    @AppStorage(Preferences.notchLyricsOnline) private var lyricsOnline: Bool
    @AppStorage(Preferences.notchQueueEnabled) private var queueEnabled: Bool
    @AppStorage(Preferences.notchLiveEqualizer) private var liveEqualizer: Bool
    @AppStorage(Preferences.notchEnabled) private var enabled: Bool
    @AppStorage(Preferences.notchMascotEnabled) private var mascotEnabled: Bool
    @AppStorage(Preferences.notchMascotStyle) private var mascotStyle: String
    @AppStorage(Preferences.notchMascotShape) private var mascotShape: String
    @AppStorage(Preferences.notchMascotPalette) private var mascotPalette: String
    @AppStorage(Preferences.notchMascotSide) private var mascotSide: String
    @AppStorage(Preferences.notchDisplay) private var display: String
    @AppStorage(Preferences.notchSilhouette) private var silhouette: String
    @AppStorage(Preferences.notchOpenOnHover) private var hover: Bool
    @AppStorage(Preferences.notchHideInFullscreen) private var hideInFullscreen: Bool
    @AppStorage(Preferences.notchHideUntilHover) private var hideUntilHover: Bool
    @AppStorage(Preferences.notchCoversMenus) private var coversMenus: Bool
    @AppStorage(Preferences.notchHoverDelay) private var hoverDelay: Double
    @AppStorage(Preferences.notchReturnHome) private var returnHome: Bool
    @AppStorage(Preferences.notchHomeModule) private var homeModule: String
    @AppStorage(Preferences.notchOpensActivity) private var opensActivity: Bool
    @AppStorage(Preferences.notchHiddenModules) private var hidden: String
    @AppStorage(Preferences.notchModuleOrder) private var order: String
    @AppStorage(Preferences.notchVolume) private var volume: Bool
    @AppStorage(Preferences.notchMicrophone) private var microphone: Bool
    @AppStorage(Preferences.notchBrightness) private var brightness: Bool
    @AppStorage(Preferences.notchBattery) private var battery: Bool
    @AppStorage(Preferences.notchClipboard) private var clipboard: Bool
    @AppStorage(Preferences.notchClipboardWindow) private var clipboardWindow: Bool
    @AppStorage(Preferences.screenshotDefaultAction) private var captureAction: String
    @AppStorage(Preferences.notchCapture) private var capture: Bool
    @AppStorage(Preferences.notchTrackChange) private var trackChange: Bool
    @AppStorage(Preferences.notchShowPlayingMusic) private var showPlayingMusic: Bool
    @AppStorage(Preferences.notchIncludeOtherPlayers) private var includeOtherPlayers: Bool
    @AppStorage(Preferences.notchIdleContent) private var idle: String
    @AppStorage(Preferences.notchHiddenControls) private var hiddenControls: String
    @AppStorage(Preferences.notchControlOrder) private var controlOrder: String
    @AppStorage(Preferences.notchShowInCaptures) private var showInCaptures: Bool
    @AppStorage(Preferences.notchLockScreen) private var lockScreen: Bool
    @AppStorage(Preferences.notchLockSounds) private var lockSounds: Bool
    @AppStorage(Preferences.notchSize) private var size: String
    @AppStorage(Preferences.notchOutlineEnabled) private var outlineEnabled: Bool
    @AppStorage(Preferences.notchCustomWidth) private var customWidth: Double
    @AppStorage(Preferences.notchCustomHeight) private var customHeight: Double
    @AppStorage(Preferences.notchCameraFitWidth) private var cameraFitWidth: Double
    @AppStorage(Preferences.notchCameraFitHeight) private var cameraFitHeight: Double
    @AppStorage(Preferences.notchCapsuleFitWidth) private var capsuleFitWidth: Double
    @AppStorage(Preferences.notchCapsuleFitHeight) private var capsuleFitHeight: Double
    @AppStorage(Preferences.notchCapsuleFitDrop) private var capsuleFitDrop: Double
    @AppStorage(Preferences.notchHapticFeedback) private var hapticFeedback: Bool
    @AppStorage(Preferences.notchTranslucentBackground) private var translucentBackground: Bool
    @AppStorage(Preferences.notchLiquidGlassEnabled) private var liquidGlass: Bool
    @AppStorage(Preferences.notchShelf) private var shelfWindow: Bool
    @AppStorage(Preferences.notchDragReveal) private var dragReveal: Bool
    @AppStorage(Preferences.notchCaptureControls) private var captureControls: Bool
    @AppStorage(Preferences.notchQuickPanel) private var quickPanel: Bool
    @AppStorage(Preferences.notchAppPanel) private var appPanel: Bool
    @AppStorage(Preferences.notchHidesMenuBarIcon) private var hidesMenuBarIcon: Bool
    @AppStorage(Preferences.notchKeepAwakeActivity) private var keepAwakeActivity: Bool
    @AppStorage(Preferences.notchScratchpad) private var scratchpad: Bool
    @AppStorage(Preferences.brightnessControlEnabled) private var brightnessControlEnabled: Bool
    @AppStorage(Preferences.clipboardHistoryEnabled) private var clipboardHistoryEnabled: Bool
    @AppStorage(Preferences.notchHoverExpands) private var hoverExpand: Bool
    @AppStorage(Preferences.notchQuickAccessLayout) private var accessData: Data
    @State private var tab = NotchSettingsTab.layout
    @State private var selectedModule = NotchModule.controls
    @State private var draggingModule: NotchModule?
    @State private var draggingControl: NotchControlItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }

    private var configuration: [String] {
        [String(enabled), String(calendarEnabled), String(calendarCountdown), String(calendarTimeLeft), String(notificationsEnabled), String(dismissNativeNotifications), String(gesturesEnabled), String(lyricsEnabled), String(lyricsOnline), String(queueEnabled), String(liveEqualizer), String(showPlayingMusic), String(includeOtherPlayers), idle, hiddenControls, controlOrder, size,
         String(timerEnabled), String(timerSoundEnabled), String(hideTimerCountdown), String(cameraEnabled), String(accessoriesEnabled), String(outlineEnabled), String(customWidth), String(customHeight), String(cameraFitWidth), String(cameraFitHeight), String(capsuleFitWidth), String(capsuleFitHeight), String(capsuleFitDrop), String(hapticFeedback), String(shelfWindow), String(dragReveal), String(captureControls), String(quickPanel), String(appPanel), String(hoverExpand), String(hideUntilHover), String(hideInFullscreen), String(coversMenus), display, silhouette, String(hover), hidden, order, String(volume),
         String(brightness), String(keyboardLight), String(microphone), String(battery), String(clipboard), String(clipboardWindow), String(capture), String(trackChange), captureAction, String(showInCaptures), String(returnHome), homeModule, String(opensActivity), String(scratchpad), String(agentsEnabled), String(watchEnabled), String(keepAwakeActivity)]
    }

    private var access: Binding<NotchQuickAccessConfiguration> {
        Binding(get: { NotchQuickAccessConfiguration.stored() }, set: { accessData = $0.encoded })
    }

    private var orderedModules: [NotchModule] {
        let stored = order.split(separator: ",").compactMap { NotchModule(rawValue: String($0)) }
        var seen = Set<NotchModule>()
        return (stored + NotchModule.allCases).filter { seen.insert($0).inserted }
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(text.title).font(.title2.bold())
                    Text(text.description).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Toggle(text.enable, isOn: $enabled).labelsHidden().toggleStyle(.switch)
                    .disabled(!AppFeature.notch.isAvailable).accessibilityLabel(text.enable)
            }
            if enabled, AppFeature.notch.isAvailable, !(hover && hideUntilHover), !notch.geometry.isNotched, !permissions.accessibility {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text.menuBarAccessHint)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PermissionRow(kind: .accessibility)
                }
            }
            NotchSettingsTabRow(tab: $tab, language: l10n.language, showsCompanion: features.isAvailable(.notchMascot),
                                canOpen: enabled) { NotchService.shared.open() }
            if tab == .content {
                GeometryReader { proxy in contentEditor(in: proxy.size) }
            } else if tab == .companion {
                NotchMascotSettings(embedded: true)
            } else {
                pageScroll
            }
        }
        .padding(.horizontal, 22).padding(.top, 22)
        .onChange(of: configuration) { _, _ in sync() }
        .onChange(of: accessData) { _, _ in NotchService.shared.syncWithPreferences() }
        .onChange(of: tab) { _, _ in draggingModule = nil; draggingControl = nil }
        .onAppear(perform: consumeModuleHint)
        .onChange(of: router.notchModule) { _, _ in consumeModuleHint() }
        .onAppear(perform: consumeCompanionHint)
        .onChange(of: router.notchCompanion) { _, _ in consumeCompanionHint() }
        // Uninstalled while its tab shows, the companion leaves the page to the layout.
        .onChange(of: features.isAvailable(.notchMascot)) { _, installed in
            if !installed, tab == .companion { tab = .layout }
        }
    }

    /// The companion's own settings were asked for; the hint is one-shot.
    private func consumeCompanionHint() {
        guard router.notchCompanion else { return }
        router.notchCompanion = false
        if features.isAvailable(.notchMascot) { tab = .companion }
    }

    private var pageScroll: some View {
        ScrollView {
            Group {
                switch tab {
                case .layout: layoutPage
                case .content: EmptyView()
                case .activity: activityPage
                case .behavior: behaviorPage
                case .companion: EmptyView()
                }
            }.padding(.bottom, 22)
        }.id(tab)
    }

    /// A section of the island can ask for its own options; the hint is one-shot.
    private func consumeModuleHint() {
        guard let module = router.notchModule else { return }
        router.notchModule = nil
        selectedModule = module
        tab = .content
    }

    private func sync() {
        NotchService.shared.syncWithPreferences()
        if !NotchLyricsSupport.isEnabled() { NotchLyricsService.shared.stop() }
        NotchMusicService.shared.syncQueuePreference()
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
    }

    private var layoutPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            NotchLayoutEditor(configuration: access, size: $size, width: $customWidth, height: $customHeight) {
                selectedModule = .controls; tab = .content
            }
            SettingsCard(title: text.size) {
                HStack(spacing: 10) {
                    choice(text.compact, symbol: "rectangle.compress.vertical", selected: size == NotchSize.compact.rawValue) { size = NotchSize.compact.rawValue }
                    choice(text.spacious, symbol: "rectangle.expand.vertical", selected: size == NotchSize.spacious.rawValue) { size = NotchSize.spacious.rawValue }
                    choice(text.custom, symbol: "arrow.up.left.and.arrow.down.right", selected: size == NotchSize.custom.rawValue) { size = NotchSize.custom.rawValue }
                }
                if size == NotchSize.custom.rawValue {
                    // One grid starts both sliders at the same edge in every language.
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        dimensionSlider(text.width, value: $customWidth, range: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
                        dimensionSlider(text.maximumHeight, value: $customHeight, range: NotchSize.heightRange, fallback: NotchSize.defaultHeight)
                    }
                    Text(text.sizeHint).font(.caption).foregroundStyle(.secondary)
                }
                // Liquid Glass takes the open island's background when it is
                // on and is already see-through, so the switch reads on and
                // changes nothing then.
                switchRow("drop.halffull", text.translucentBackground,
                          caption: liquidGlassIsOn ? text.translucentBackgroundGlassHint : text.translucentBackgroundHint,
                          isOn: liquidGlassIsOn ? .constant(true) : $translucentBackground)
                    .disabled(liquidGlassIsOn)
            }
            // Only a display without a camera can float the island.
            if NotchSupport.hasDisplayWithoutNotch {
                SettingsCard(title: text.withoutNotch) {
                    HStack(spacing: 10) {
                        silhouetteChoice(.capsule, title: text.capsuleShape)
                        silhouetteChoice(.notch, title: text.notchShape)
                    }
                }
                if NotchSilhouette(rawValue: silhouette) ?? .capsule == .capsule {
                    SettingsCard(title: text.capsuleFit) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            // Even widths keep the capsule centred on whole points.
                            fitSlider(text.width, card: text.capsuleFit, value: $capsuleFitWidth,
                                      range: NotchCapsuleFit.widthRange, step: 2)
                            fitSlider(text.height, card: text.capsuleFit, value: $capsuleFitHeight,
                                      range: NotchCapsuleFit.heightRange, step: 1)
                            fitSlider(text.fromTop, card: text.capsuleFit, value: $capsuleFitDrop,
                                      range: NotchCapsuleFit.dropRange, step: 1)
                        }
                        Text(text.capsuleFitHint).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            SettingsCard {
                switchRow("capsule", text.showOutline, isOn: $outlineEnabled)
            }
            // Only a physical camera has an outline to match.
            if NotchSupport.hasNotchedDisplay {
                SettingsCard(title: text.cameraFit) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        // Whole points keep the island centred on the camera's pixels.
                        fitSlider(text.width, card: text.cameraFit, value: $cameraFitWidth,
                                  range: NotchCameraFit.widthRange, step: 1)
                        fitSlider(text.height, card: text.cameraFit, value: $cameraFitHeight,
                                  range: NotchCameraFit.heightRange, step: 0.5)
                    }
                    Text(text.cameraFitHint).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Whether the open island draws Liquid Glass, by the island's own rule.
    /// Reduce Transparency keeps it black, so the switch then shows the saved
    /// choice as it does with the glass off.
    private var liquidGlassIsOn: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *) { return liquidGlass && !reduceTransparency }
#endif
        return false
    }

    /// The sections in a list of their own, the chosen one's options beside
    /// it, and the island as it will look. A wide window keeps the preview
    /// in a column that never scrolls away; a narrow one puts it above the
    /// options, so they keep the height of the window either way.
    private func contentEditor(in size: CGSize) -> some View {
        let wide = size.width >= 940
        let listWidth: CGFloat = wide ? 216 : 196
        let previewWidth = wide ? min(560, ((size.width - listWidth - 32) * 0.5).rounded()) : 0
        let detailWidth = max(0, size.width - listWidth - 16 - (wide ? previewWidth + 16 : 0))
        return HStack(alignment: .top, spacing: 16) {
            sectionList
                .frame(width: listWidth, height: size.height, alignment: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let module = selectedModule
                    let available = module.isAvailable()
                    NotchSectionHeader(module: module, shown: isShown(module),
                                       reason: available ? nil : moduleFeature(module).map(enableFeatureReason) ?? text.disabled) {
                        SettingsRouter.shared.request(FeatureSettingsDestination(.features), targetFeature: moduleFeature(module))
                    }
                    if !wide { preview(width: detailWidth, limit: 280) }
                    if available, hasOptions(module) {
                        SettingsCard { moduleOptions(module) }
                    } else if available {
                        Text(editor.noOptions).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 22)
            }
            .id(selectedModule)
            .frame(width: detailWidth)
            if wide {
                preview(width: previewWidth, limit: size.height)
                    .frame(width: previewWidth)
            }
        }
    }

    private func preview(width: CGFloat, limit: CGFloat) -> some View {
        NotchIslandPreview(module: selectedModule, hidden: !isShown(selectedModule))
            .frame(height: NotchIslandPreview.height(width: width, limit: limit))
    }

    /// Every section in the island's order, each with the switch that shows it.
    private var sectionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editor.sections).font(.headline)
                Text(editor.sectionsHint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(orderedModules) { module in
                            NotchSectionListRow(module: module, included: moduleBinding(module), available: module.isAvailable(),
                                                selected: selectedModule == module,
                                                order: Binding(get: { orderedModules },
                                                               set: { order = $0.map(\.rawValue).joined(separator: ",") }),
                                                dragging: $draggingModule) { selectedModule = module }
                                .id(module)
                        }
                    }
                }
                .scrollIndicators(.automatic)
                // A section chosen from the island itself may sit low in the list.
                .onAppear { reader.scrollTo(selectedModule) }
                .onChange(of: selectedModule) { _, module in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { reader.scrollTo(module) }
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func isShown(_ module: NotchModule) -> Bool {
        module.isAvailable() && moduleBinding(module).wrappedValue
    }

    /// The mixer, the system page and the tools arrange themselves in the island.
    private func hasOptions(_ module: NotchModule) -> Bool {
        ![.mixer, .system, .tools].contains(module)
    }

    @ViewBuilder private func moduleOptions(_ module: NotchModule) -> some View {
        switch module {
        case .controls:
            let primary = [NotchControlItem.music, .volume, .brightness, .keyboardLight]
            HStack(spacing: 10) {
                ForEach(primary) { item in
                    toggleCard(item.title(l10n), symbol: item.symbol, value: controlBinding(item), available: item.isAvailable(),
                               reason: controlReason(item), reservesReason: !primary.allSatisfy { $0.isAvailable() },
                               unavailableAction: controlUnavailableAction(item))
                }
            }
            Text(text.controlShortcuts).font(.subheadline.weight(.medium))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
                ForEach(orderedShortcuts) { item in
                    PanelReorderableItem(item: item,
                        order: Binding(get: { orderedShortcuts }, set: { controlOrder = $0.map(\.rawValue).joined(separator: ",") }),
                        dragging: $draggingControl) {
                        toggleCard(item.title(l10n), symbol: item.symbol, value: controlBinding(item), available: item.isAvailable(),
                                   reason: controlReason(item), reservesReason: !orderedShortcuts.allSatisfy { $0.isAvailable() },
                                   unavailableAction: controlUnavailableAction(item))
                    }
                }
            }
            Divider()
            let activities = FeatureStrings.notchActivities(l10n.language)
            switchRow(NotchControlItem.keepAwake.symbol, activities.keepAwakeActivity,
                      caption: activities.keepAwakeActivityHint, isOn: $keepAwakeActivity)
                .disabled(!AppFeature.keepAwake.isAvailable)
        case .music:
            let music = FeatureStrings.notchMusicExtras(l10n.language)
            switchRow("music.note", text.playingMusic, isOn: $showPlayingMusic)
            switchRow("play.rectangle", music.includeOtherPlayers, isOn: $includeOtherPlayers)
            switchRow("text.quote", music.enableLyrics, isOn: $lyricsEnabled)
                .disabled(!AppFeature.notchLyrics.isAvailable)
            if lyricsEnabled, AppFeature.notchLyrics.isAvailable {
                switchRow("globe", music.online, caption: music.onlineHint, isOn: $lyricsOnline)
                    .padding(.leading, settingsRowTextInset)
            }
            switchRow("list.bullet", music.enableQueue, caption: music.queueDescription, isOn: $queueEnabled)
                .disabled(!AppFeature.notchQueue.isAvailable)
            switchRow("waveform", music.liveEqualizer,
                      caption: NotchAudioLevelSupport.isSupported ? music.liveEqualizerHint : music.liveEqualizerUnavailable,
                      isOn: $liveEqualizer)
                .disabled(!NotchAudioLevelSupport.isSupported || !AppFeature.notchLiveEqualizer.isAvailable)
        case .notifications:
            let notifications = FeatureStrings.notchNotifications(l10n.language)
            switchRow("bell.slash", notifications.hideSystemBanner, caption: notifications.hideSystemBannerHint,
                      isOn: $dismissNativeNotifications)
            if notificationsEnabled, !permissions.accessibility { PermissionRow(kind: .accessibility) }
        case .downloads:
            NotchDownloadsSettingsControls()
                .toggleStyle(TrailingSwitchToggleStyle())
        case .calendar:
            let calendar = FeatureStrings.notchCalendar(l10n.language)
            Text(calendar.permission).font(.callout).foregroundStyle(.secondary)
            if permissions.calendarAccess == .fullAccess {
                Label(l10n.s.permissionGranted, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(calendar.allow, action: permissions.requestCalendar).disabled(permissions.requestingCalendar)
                Button(calendar.settings, action: permissions.openCalendarSettings)
            }
            Divider()
            switchRow("calendar.badge.clock", calendar.countdown, caption: calendar.countdownHint,
                      isOn: $calendarCountdown)
            switchRow("hourglass", calendar.timeLeft, caption: calendar.timeLeftHint, isOn: $calendarTimeLeft)
            switchRow("number", calendar.weekNumbers, isOn: $calendarWeekNumbers)
            if permissions.calendarAccess == .fullAccess { NotchCalendarSelection() }
        case .timer:
            let activities = FeatureStrings.notchActivities(l10n.language)
            switchRow("eye.slash", activities.hideTimerCountdown,
                      isOn: $hideTimerCountdown)
                .disabled(!AppFeature.notchTimer.isAvailable)
            switchRow("speaker.wave.2", activities.soundEnabled, isOn: $timerSoundEnabled)
                .disabled(!AppFeature.notchTimer.isAvailable)
        case .camera:
            Text(FeatureStrings.notchActivities(l10n.language).cameraHint).font(.callout).foregroundStyle(.secondary)
            if permissions.camera == .granted {
                Label(l10n.s.permissionGranted, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(l10n.s.permissionRequest, action: permissions.requestCamera)
                Button(l10n.s.permissionOpenSettings, action: permissions.openCameraSettings)
            }
        case .files:
            destination(text.files, symbol: "tray.full", value: $shelfWindow, available: AppFeature.shelf.isAvailable)
            if shelfWindow { switchRow("hand.draw", text.dragReveal, isOn: $dragReveal) }
            if AppFeature.mediaTools.isAvailable {
                Text(FeatureStrings.notchFiles(l10n.language).optimizeDropHint)
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .clipboard:
            destination(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboardWindow, available: AppFeature.clipboardHistory.isAvailable)
            switchRow("doc.on.clipboard", text.clipboardActivity, caption: text.privacy, isOn: $clipboard)
        case .captures:
            switchRow("camera.viewfinder", text.captureActivity, isOn: $capture).disabled(!AppFeature.screenshot.isAvailable)
            if capture {
                ScreenshotDefaultActionPicker(strings: FeatureStrings.screenshot(l10n.language), selection: $captureAction)
                    .padding(.leading, settingsRowTextInset)
            }
        case .scratchpad:
            destination(FeatureStrings.scratchpad(l10n.language).pageTitle, symbol: "note.text", value: $scratchpad)
        case .agents:
            NotchAgentsSettingsControls()
        case .watch:
            NotchWatchSettingsControls()
                .toggleStyle(TrailingSwitchToggleStyle())
        case .mixer, .system, .tools:
            EmptyView()
        }
    }

    private var activityPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: editor.resting) {
                HStack(spacing: 10) {
                    // With the companion on, the island rests with it when it
                    // has nothing else to show, so that choice is the companion.
                    idleChoice(.none, title: restsWithMascot ? FeatureStrings.notchMascot(l10n.language).title : text.idleNone,
                               symbol: "minus")
                    if PowerSampler.hasInternalBattery {
                        idleChoice(.battery, title: text.battery, symbol: "battery.75percent")
                    }
                    idleChoice(.music, title: text.music, symbol: "music.note")
                    // Offered once the section is on; the island would show nothing before.
                    if offersAgentsResting {
                        idleChoice(.agents, title: FeatureStrings.notchAgents(l10n.language).restingTitle, symbol: "sparkles")
                    }
                }
                switchRow("menubar.rectangle", text.coverMenus, caption: text.coverMenusHint, isOn: $coversMenus)
            }
            SettingsCard(title: editor.feedback) {
                let volumeAvailable = AppFeature.mixer.isAvailable
                let brightnessAvailable = AppFeature.brightness.isAvailable && brightnessControlEnabled
                let keyboardLightAvailable = AppFeature.brightness.isAvailable && BrightnessService.keyboardLightIsSupported
                let microphoneAvailable = AppFeature.micMute.isAvailable
                // A Mac without a battery has no battery notices, so that card
                // is left out rather than shown waiting for Power.
                let hasBattery = PowerSampler.hasInternalBattery
                let batteryAvailable = AppFeature.monitorPower.isAvailable
                let accessoriesAvailable = AppFeature.notchAccessories.isAvailable && AppFeature.monitorPower.isAvailable
                let clipboardAvailable = AppFeature.clipboardHistory.isAvailable && clipboardHistoryEnabled
                    && NotchSupport.modules().contains(.clipboard)
                let capturesAvailable = AppFeature.screenshot.isAvailable && NotchSupport.modules().contains(.captures)
                let musicAvailable = NotchSupport.modules().contains(.music)
                let reserves = ![volumeAvailable, brightnessAvailable, keyboardLightAvailable, microphoneAvailable,
                                 batteryAvailable || !hasBattery, accessoriesAvailable, clipboardAvailable, capturesAvailable,
                                 musicAvailable].allSatisfy { $0 }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                    toggleCard(text.volume, symbol: "speaker.wave.2", value: $volume, available: volumeAvailable,
                               reason: enableFeatureReason(.mixer), reservesReason: reserves,
                               unavailableAction: { showFeature(.mixer) })
                    toggleCard(text.brightness, symbol: "sun.max", value: $brightness, available: brightnessAvailable,
                               reason: AppFeature.brightness.isAvailable ? editor.enableSetting(FeatureStrings.brightness(l10n.language).enable) : enableFeatureReason(.brightness),
                               reservesReason: reserves,
                               unavailableAction: {
                                   if AppFeature.brightness.isAvailable {
                                       router.request(AppFeature.brightness.settingsDestination)
                                   } else {
                                       showFeature(.brightness)
                                   }
                               })
                    toggleCard(FeatureStrings.brightness(l10n.language).keyboardLight, symbol: "light.max", value: $keyboardLight,
                              available: keyboardLightAvailable,
                              reason: !AppFeature.brightness.isAvailable ? enableFeatureReason(.brightness) : editor.keyboardLightUnavailable,
                              reservesReason: reserves,
                              unavailableAction: !AppFeature.brightness.isAvailable ? { showFeature(.brightness) } : nil)
                    toggleCard(l10n.s.mixerInputTitle, symbol: "mic", value: $microphone, available: microphoneAvailable,
                               reason: enableFeatureReason(.micMute), reservesReason: reserves,
                               unavailableAction: { showFeature(.micMute) })
                    if hasBattery {
                        toggleCard(text.battery, symbol: "battery.75percent", value: $battery, available: batteryAvailable,
                                   reason: enableFeatureReason(.monitorPower), reservesReason: reserves,
                                   unavailableAction: { showFeature(.monitorPower) })
                    }
                    toggleCard(FeatureStrings.notchActivities(l10n.language).accessories, symbol: "headphones", value: $accessoriesEnabled,
                              available: accessoriesAvailable,
                              reason: enableFeatureReason(AppFeature.monitorPower.isAvailable ? .notchAccessories : .monitorPower),
                              reservesReason: reserves,
                              unavailableAction: {
                                  showFeature(AppFeature.monitorPower.isAvailable ? .notchAccessories : .monitorPower)
                              })
                    toggleCard(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboard,
                               available: clipboardAvailable, reason: clipboardFeedbackReason, reservesReason: reserves,
                               unavailableAction: { openClipboardFeedbackSetup() })
                    toggleCard(text.captures, symbol: "camera.viewfinder", value: $capture, available: capturesAvailable,
                               reason: AppFeature.screenshot.isAvailable ? editor.showPage(text.captures) : enableFeatureReason(.screenshot),
                               reservesReason: reserves,
                               unavailableAction: {
                                   if AppFeature.screenshot.isAvailable { showModule(.captures) }
                                   else { showFeature(.screenshot) }
                               })
                    toggleCard(text.newTrack, symbol: "music.note", value: $trackChange, available: musicAvailable,
                               reason: editor.showPage(text.music), reservesReason: reserves,
                               unavailableAction: { showModule(.music) })
                }
                if accessoriesEnabled { Text(FeatureStrings.notchActivities(l10n.language).accessoryDescription).font(.caption).foregroundStyle(.secondary) }
                if enabled, (volume || brightness || keyboardLight), !permissions.accessibility { PermissionRow(kind: .accessibility) }
            }
            let locked = FeatureStrings.notchLockScreen(l10n.language)
            SettingsCard(title: locked.title) {
                switchRow("lock.display", locked.show, caption: locked.showHint, isOn: $lockScreen)
                switchRow("speaker.wave.2", locked.sounds, caption: locked.soundsHint, isOn: $lockSounds)
            }
        }
    }

    private var behaviorPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: editor.opening) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    choice(editor.clickOpen, symbol: "cursorarrow", selected: !hover) { hideUntilHover = false; hover = false }
                    choice(editor.hoverPreview, symbol: "rectangle.topthird.inset.filled", selected: hover && !hoverExpand && !hideUntilHover) { hideUntilHover = false; hover = true; hoverExpand = false }
                    choice(editor.hoverExpand, symbol: "arrow.up.left.and.arrow.down.right", selected: hover && hoverExpand && !hideUntilHover) { hideUntilHover = false; hover = true; hoverExpand = true }
                    choice(editor.hiddenUntilHover, symbol: "eye.slash", selected: hover && hideUntilHover) { hover = true; hoverExpand = true; hideUntilHover = true }
                }
                if hover { hoverDelayControl }
                switchRow("hand.draw", FeatureStrings.notchGestures(l10n.language).title,
                          caption: gesturesEnabled ? FeatureStrings.notchGestures(l10n.language).hint : nil,
                          isOn: $gesturesEnabled)
                    .disabled(!AppFeature.notchGestures.isAvailable)
                switchRow("waveform.path", text.hapticFeedback, isOn: $hapticFeedback)
                SettingsRow(symbol: "arrow.uturn.backward", title: editor.reopening) {
                    Picker(editor.reopening, selection: Binding(get: {
                        guard returnHome else { return "" }
                        return NotchModule(rawValue: homeModule) != nil
                            || NotchReopeningDestination(rawValue: homeModule) != nil
                            ? homeModule : NotchModule.controls.rawValue
                    }, set: { value in
                        returnHome = !value.isEmpty
                        if returnHome { homeModule = value }
                    })) {
                        Text(editor.lastPage).tag("")
                        Text(text.panel).tag(NotchReopeningDestination.appPanel.rawValue)
                        Text(text.sectionsTitle).tag(NotchReopeningDestination.explore.rawValue)
                        ForEach(NotchSupport.modules()) { module in
                            Text(module.title(l10n.language)).tag(module.rawValue)
                        }
                        if let saved = NotchModule(rawValue: homeModule), !NotchSupport.modules().contains(saved) {
                            Text(saved.title(l10n.language)).tag(homeModule).disabled(true)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                switchRow("livephoto", editor.openActivity, caption: editor.openActivityHint, isOn: $opensActivity)
            }
            SettingsCard(title: text.display) {
                switchRow("arrow.up.left.and.arrow.down.right", text.hideInFullscreen, isOn: $hideInFullscreen)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    // A mode this version no longer offers is treated as automatic, as the island does.
                    choice(text.automatic, symbol: "display.2",
                           selected: (NotchDisplay(rawValue: display) ?? .automatic) == .automatic) { display = NotchDisplay.automatic.rawValue }
                    choice(text.builtIn, symbol: "laptopcomputer", selected: display == NotchDisplay.builtIn.rawValue) { display = NotchDisplay.builtIn.rawValue }
                    choice(text.mainDisplay, symbol: "display", selected: display == NotchDisplay.main.rawValue) { display = NotchDisplay.main.rawValue }
                    choice(text.followPointer, symbol: "cursorarrow.motionlines",
                           selected: display == NotchDisplay.pointer.rawValue) { display = NotchDisplay.pointer.rawValue }
                    choice(text.allDisplays, symbol: "rectangle.on.rectangle",
                           selected: display == NotchDisplay.all.rawValue) { display = NotchDisplay.all.rawValue }
                }
            }
            SettingsCard(title: editor.destinations) {
                destination(text.panel, symbol: "bubble.middle.top", value: $appPanel)
                Text(editor.appPanelHint).font(.caption).foregroundStyle(.secondary)
                switchRow("menubar.rectangle", editor.hideMenuBarIcon, caption: editor.hideMenuBarIconHint,
                          isOn: $hidesMenuBarIcon)
                destination(text.tools, symbol: "square.grid.2x2", value: $quickPanel, available: AppFeature.quickLauncher.isAvailable)
                destination(FeatureStrings.clipboard(l10n.language).title, symbol: "doc.on.clipboard", value: $clipboardWindow, available: AppFeature.clipboardHistory.isAvailable)
                destination(text.files, symbol: "tray.full", value: $shelfWindow, available: AppFeature.shelf.isAvailable)
                destination(text.captures, symbol: "camera.viewfinder", value: $captureControls)
                destination(FeatureStrings.scratchpad(l10n.language).pageTitle, symbol: "note.text", value: $scratchpad, available: AppFeature.scratchpad.isAvailable)
            }
            SettingsCard(title: editor.privacy) {
                switchRow("camera.viewfinder", text.showInCaptures, isOn: $showInCaptures)
            }
        }
    }

    private var hoverDelayControl: some View {
        let value = Binding(get: { NotchSupport.sanitizedHoverDelay(hoverDelay) },
                            set: { hoverDelay = NotchSupport.sanitizedHoverDelay($0) })
        let formatted = String(format: editor.activationTimeFormat, locale: Locale(identifier: l10n.language.rawValue), value.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(editor.activationTime)
                Spacer()
                Text(formatted).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: NotchSupport.hoverDelayRange, step: 0.05) {
                Text(editor.activationTime)
            }.labelsHidden().accessibilityValue(formatted)
            Text(editor.activationTimeHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choice(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 68).padding(8)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Each outline in a slice of menu bar, drawn as the island draws it.
    private func silhouetteChoice(_ item: NotchSilhouette, title: String) -> some View {
        let selected = (NotchSilhouette(rawValue: silhouette) ?? .capsule) == item
        return Button { silhouette = item.rawValue } label: {
            VStack(spacing: 10) {
                NotchSilhouetteSample(silhouette: item)
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 68).padding(8)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func enableFeatureReason(_ feature: AppFeature) -> String {
        editor.enableFeature(feature.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language)))
    }

    private func showFeature(_ feature: AppFeature) {
        router.request(FeatureSettingsDestination(.features), targetFeature: feature)
    }

    private func showModule(_ module: NotchModule) {
        selectedModule = module
        tab = .content
    }

    /// A control that opens a page is off while that page is hidden, or while
    /// the feature behind it is disabled; the others follow their feature.
    private func controlReason(_ item: NotchControlItem) -> String {
        // The keyboard light also needs a keyboard that has one.
        if item == .keyboardLight, AppFeature.brightness.isAvailable { return editor.keyboardLightUnavailable }
        switch item.setupRequirement {
        case .feature(let feature): return enableFeatureReason(feature)
        case .page(let module, let feature): return pageReason(module, feature: feature)
        case .none: return text.disabled
        }
    }

    private func controlUnavailableAction(_ item: NotchControlItem) -> (() -> Void)? {
        if item == .keyboardLight, AppFeature.brightness.isAvailable { return nil }
        switch item.setupRequirement {
        case .feature(let feature):
            return { showFeature(feature) }
        case .page(let module, let feature):
            return {
                if let feature, !feature.isAvailable { showFeature(feature) }
                else { showModule(module) }
            }
        case .none: return nil
        }
    }

    /// The one feature a page needs; Captures and System accept any of several.
    private func moduleFeature(_ module: NotchModule) -> AppFeature? {
        switch module {
        case .controls, .music, .captures, .system: return nil
        case .mixer: return .mixer
        case .clipboard: return .clipboardHistory
        case .files: return .shelf
        case .tools: return .quickLauncher
        case .calendar: return .notchCalendar
        case .notifications: return .notchNotifications
        case .timer: return .notchTimer
        case .camera: return .cameraPreview
        case .downloads: return .notchDownloads
        case .scratchpad: return .scratchpad
        case .agents: return .notchAgents
        case .watch: return .notchWatch
        }
    }

    private func pageReason(_ module: NotchModule, feature: AppFeature?) -> String {
        if let feature, !feature.isAvailable { return enableFeatureReason(feature) }
        return editor.showPage(module.title(l10n.language))
    }

    private var clipboardFeedbackReason: String {
        let title = FeatureStrings.clipboard(l10n.language).title
        if !AppFeature.clipboardHistory.isAvailable { return enableFeatureReason(.clipboardHistory) }
        if !clipboardHistoryEnabled { return editor.enableSetting(FeatureStrings.clipboard(l10n.language).enable) }
        return editor.showPage(title)
    }

    private func openClipboardFeedbackSetup() {
        if !AppFeature.clipboardHistory.isAvailable { showFeature(.clipboardHistory) }
        else if !clipboardHistoryEnabled { router.request(AppFeature.clipboardHistory.settingsDestination) }
        else { showModule(.clipboard) }
    }

    private func toggleCard(_ title: String, symbol: String, value: Binding<Bool>, available: Bool, reason: String? = nil,
                            reservesReason: Bool = false, unavailableAction: (() -> Void)? = nil) -> some View {
        NotchEditorItem(symbol: symbol, title: title, included: value, available: available,
                        unavailableReason: available ? nil : reason ?? text.disabled,
                        unavailableAction: unavailableAction, reservesReason: reservesReason) {
            value.wrappedValue.toggle()
        }
    }

    private var offersAgentsResting: Bool { agentsEnabled && NotchAgentSupport.isEnabled() }

    /// What the closed island rests with. A saved AI reading waits, unchanged,
    /// while its section is off, and the island rests empty meanwhile. So does
    /// a saved battery reading on a Mac without a battery.
    private var restingChoice: NotchIdleContent {
        let choice: NotchIdleContent = NotchIdleContent(rawValue: idle) ?? .none
        if choice == .battery, !PowerSampler.hasInternalBattery { return .none }
        return choice == .agents && !offersAgentsResting ? .none : choice
    }

    private var restsWithMascot: Bool { enabled && mascotEnabled && features.isAvailable(.notchMascot) }

    /// The companion where it rests, beside a camera drawn black on black.
    private var restingMascot: some View {
        let look = NotchMascotLook(style: NotchMascotStyle(rawValue: mascotStyle) ?? .minimal,
                                   shape: NotchMascotShape(rawValue: mascotShape) ?? .ball,
                                   palette: NotchMascotPalette(rawValue: mascotPalette) ?? .pearl)
        let right = NotchMascotSide(rawValue: mascotSide) == .right
        return HStack(spacing: 14) {
            if right { Color.clear.frame(width: 12, height: 12) }
            else { NotchMascotView(look: look, size: 12, idles: false).frame(width: 12, height: 12) }
            RoundedRectangle(cornerRadius: 4).fill(.black).frame(width: 20, height: 12)
            if right { NotchMascotView(look: look, size: 12, idles: false).frame(width: 12, height: 12) }
            else { Color.clear.frame(width: 12, height: 12) }
        }
    }

    private func idleChoice(_ item: NotchIdleContent, title: String, symbol: String) -> some View {
        Button { idle = item.rawValue } label: {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    if item == .none, restsWithMascot {
                        restingMascot
                    } else if item != .none {
                        Image(systemName: symbol).font(.system(size: 11))
                        RoundedRectangle(cornerRadius: 4).fill(.black).frame(width: 20, height: 12)
                        if item == .battery || item == .agents { Text(item == .agents ? "62%" : "76%").font(.system(size: 9, weight: .medium)) }
                        else { Image(systemName: item == .music ? "waveform" : "minus").font(.system(size: 9)) }
                    } else { Color.clear.frame(width: 50, height: 12) }
                }.foregroundStyle(.white).padding(10).background(.black, in: Capsule())
                Text(title).font(.system(size: 11, weight: .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(restingChoice == item ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(restingChoice == item ? .isSelected : [])
    }

    private func destination(_ title: String, symbol: String, value: Binding<Bool>, available: Bool = true) -> some View {
        NotchDestinationRow(title, symbol: symbol, value: value, language: l10n.language, available: available)
    }

    /// An option with its icon, one line and a switch, like every other page.
    private func switchRow(_ symbol: String, _ title: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    private func dimensionSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, fallback: Double) -> some View {
        let bounded = Binding(get: { NotchSize.clamped(value.wrappedValue, to: range, fallback: fallback) },
                              set: { value.wrappedValue = NotchSize.clamped($0, to: range, fallback: fallback) })
        return GridRow {
            // The slider carries the name for VoiceOver.
            Text(title).fixedSize().accessibilityHidden(true)
            Slider(value: bounded, in: range, step: 10) { Text(title) }.labelsHidden()
            Text(Int(bounded.wrappedValue), format: .number)
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 38)
        }
    }

    /// A correction around zero, signed so the untouched value reads as none.
    private func fitSlider(_ title: String, card: String, value: Binding<Double>, range: ClosedRange<Double>,
                           step: Double) -> some View {
        let bounded = Binding(get: { NotchSize.clamped(value.wrappedValue, to: range, fallback: 0) },
                              set: { value.wrappedValue = NotchSize.clamped($0, to: range, fallback: 0) })
        let formatted = bounded.wrappedValue.formatted(.number.sign(strategy: .always(includingZero: false))
            .precision(.fractionLength(0...1)).locale(Locale(identifier: l10n.language.rawValue)))
        return GridRow {
            Text(title).fixedSize().accessibilityHidden(true)
            // Other cards have sliders with the same names.
            Slider(value: bounded, in: range, step: step) { Text("\(card), \(title)") }.labelsHidden()
                .accessibilityValue(formatted)
            Text(formatted).monospacedDigit().foregroundStyle(.secondary).frame(width: 38)
        }
    }
    private var orderedShortcuts: [NotchControlItem] {
        let stored = controlOrder.split(separator: ",").compactMap { NotchControlItem(rawValue: String($0)) }
        var seen = Set<NotchControlItem>()
        return (stored + NotchControlItem.allCases).filter {
            !$0.isLevel && $0 != .music && seen.insert($0).inserted
        }
    }

    private func controlBinding(_ item: NotchControlItem) -> Binding<Bool> {
        Binding {
            !hiddenControls.split(separator: ",").contains(Substring(item.rawValue))
        } set: { shown in
            var values = Set(hiddenControls.split(separator: ",").map(String.init))
            if shown { values.remove(item.rawValue) } else { values.insert(item.rawValue) }
            hiddenControls = values.sorted().joined(separator: ",")
        }
    }

    private func moduleBinding(_ module: NotchModule) -> Binding<Bool> {
        Binding {
            (module != .timer || timerEnabled) && (module != .camera || cameraEnabled)
                && (module != .calendar || calendarEnabled) && (module != .notifications || notificationsEnabled)
                && (module != .agents || agentsEnabled) && (module != .watch || watchEnabled)
                && !hidden.split(separator: ",").contains(Substring(module.rawValue))
        } set: { shown in
            if module == .timer { timerEnabled = shown }
            if module == .camera { cameraEnabled = shown }
            if module == .calendar { calendarEnabled = shown }
            if module == .notifications { notificationsEnabled = shown }
            if module == .agents { agentsEnabled = shown }
            if module == .watch { watchEnabled = shown }
            var values = Set(hidden.split(separator: ",").map(String.init))
            if shown { values.remove(module.rawValue) } else { values.insert(module.rawValue) }
            hidden = values.sorted().joined(separator: ",")
        }
    }

}

extension NotchControlItem: PanelOrderItem {}

/// A standard menu bar on a display without a camera, at half size, with
/// the resting island in it.
private struct NotchSilhouetteSample: View {
    let silhouette: NotchSilhouette

    var body: some View {
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0,
                                     cameraWidth: 0, menuBarHeight: 24, silhouette: silhouette)
        let island = geometry.restingSize(showsContent: false)
        ZStack(alignment: .top) {
            Rectangle().fill(.primary.opacity(0.08)).frame(height: geometry.menuBarHeight)
            // Menus on the left and status items on the right, clear of the island.
            HStack(spacing: 9) {
                ForEach([26, 36, 30], id: \.self) { width in
                    Capsule().fill(.primary.opacity(0.22)).frame(width: CGFloat(width), height: 8)
                }
                Spacer(minLength: 0)
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.primary.opacity(0.22)).frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: geometry.menuBarHeight)
            NotchShape.island(height: island.height, geometry: geometry).fill(.black)
                .frame(width: island.width, height: island.height)
        }
        .frame(width: 400, height: 48, alignment: .top)
        .background(.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(0.5)
        .frame(width: 200, height: 24)
        .accessibilityHidden(true)
    }
}
