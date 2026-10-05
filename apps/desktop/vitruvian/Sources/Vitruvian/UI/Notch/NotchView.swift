// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

package struct NotchView: View {
    @ObservedObject package var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var launcher = QuickLauncherService.shared
    @ObservedObject private var updates = UpdateService.shared
    @AppStorage(Preferences.notchLiquidGlassEnabled) private var glass: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var headerHovered = false
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }

    package var body: some View {
        surface
            .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            .foregroundStyle(.white)
            // The window server leaves Liquid Glass out of its hit test, so a
            // click or a wheel over empty glass would reach the window behind:
            // the page stops scrolling between cards and the island loses
            // focus. A fill too faint to see keeps the surface in this window,
            // as the black backdrop does.
            .background(shape.fill(Color.black.opacity(0.01)))
            .contentShape(shape)
            // The backdrop is a separate, non-interactive hosting view. Claim
            // empty space here so clicks and wheel events stay in this window.
            .onTapGesture { }
            .onChange(of: reduceTransparency) {
                DispatchQueue.main.async { service.refreshPresentation(animated: false) }
            }
            .onChange(of: contrast) {
                DispatchQueue.main.async { service.refreshPresentation(animated: false) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .environment(\.notchPresentation, true)
            .environment(\.notchGlassSurface, usesGlassSurface)
            .tint(.white)
            .accessibilityIdentifier("notch.surface")
    }

    private var usesGlassSurface: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *), glass, !reduceTransparency {
            // Resting wings, compact activities and small status notices keep
            // blending into the physical camera cutout.
            return service.usesGlassSurface
        }
#endif
        return false
    }

    private var shape: NotchShape {
        NotchShape.island(height: service.surfaceSize.height, geometry: service.geometry)
    }

    @ViewBuilder private var surface: some View {
        if service.fullscreenCompact {
            Color.clear.accessibilityHidden(true)
        } else if let options = service.captureControls {
            if service.captureControlsCollapsed, floats {
                NotchCapsuleCaptureStrip(symbol: options.selectedTool.systemImageName, geometry: service.geometry,
                                         size: service.surfaceSize)
            } else if service.captureControlsCollapsed {
                HStack(spacing: 0) {
                    Image(systemName: options.selectedTool.systemImageName).frame(width: NotchLayout.captureCollapsedSide)
                    Color.clear.frame(width: service.geometry.cameraWidth)
                    Image(systemName: "chevron.down").frame(width: NotchLayout.captureCollapsedSide)
                }
                .font(.system(size: 10, weight: .semibold))
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            } else {
                NotchCaptureControlsView(options: options, service: service, layout: service.captureControlsLayout)
            }
        } else if service.expanded {
            expanded
        } else if service.dragPlaceholder {
            Label(text.dropHint, systemImage: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: NotchLayout.dropHintHeight)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.24),
                                      style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 18)
                .padding(.top, service.geometry.safeContentTop)
        } else if let notice = service.notice ?? (service.peeking ? nil : service.departingNotice) {
            if service.noticeExpanded, let content = notice.notification {
                NotchNotificationPreviewView(notice: notice, content: content, service: service)
                    .padding(.horizontal, NotchLayout.horizontalInset)
                    .padding(.top, service.geometry.safeContentTop)
                    .padding(.bottom, NotchLayout.bottomInset)
                    .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            } else {
                Button {
                    service.activateNotice(notice)
                } label: {
                    Group {
                        if floats {
                            // A departing notice keeps its own row while the capsule closes.
                            NotchCapsuleNoticeView(notice: notice, geometry: service.geometry,
                                                   size: service.notice == nil ? service.capsuleNoticeSurface(notice)
                                                       : service.surfaceSize)
                        } else {
                            NotchNoticeView(notice: notice, geometry: service.geometry)
                        }
                    }
                    .contentShape(Rectangle())
                }
                // A floating capsule lights up under the pointer. Beside a
                // camera the wash would outline the housing, so the notch keeps
                // its notices plain, as its other strips are.
                .buttonStyle(NotchButtonStyle(cornerRadius: 14, lifts: false, highlights: floats))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(notice.accessibilityText)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { service.activateNotice(notice) }
                .accessibilityHint(text.open)
                .transition(.opacity)
            }
        } else if service.peeking {
            HStack {
                navigation
                Spacer(minLength: 8)
                NotchIconButton(symbol: "chevron.down", title: text.open) { service.open() }
            }
            .padding(.horizontal, NotchLayout.horizontalInset).padding(.top, service.geometry.safeContentTop)
        } else if let activity = service.compactActivity {
            if service.showsCompactActivityPicker {
                let layout = service.compactActivityPickerLayout
                VStack(spacing: 0) {
                    let strip = service.compactStripSize(for: activity, companion: service.compactCompanion)
                    ZStack(alignment: .top) {
                        activityStrip(activity, size: strip)
                            .frame(width: strip.width, height: layout.headerHeight, alignment: .top)
                            .id(NotchPickedStrip(activity: activity, companion: service.compactCompanion))
                            .transition(.blurReplace)
                    }
                    .frame(height: layout.headerHeight, alignment: .top)
                    NotchActivityPicker(activities: service.compactActivities, selected: activity,
                                        combinations: service.compactActivityCombinations,
                                        combination: service.compactCompanion.map {
                                            NotchActivityCombination(primary: activity, companion: $0)
                                        },
                                        columns: layout.columns, language: l10n.language,
                                        select: service.selectCompactActivity, combine: service.selectCompactCombination)
                        .padding(.horizontal, NotchActivityPickerLayout.horizontalInset)
                        .padding(.vertical, NotchActivityPickerLayout.verticalInset)
                }
            } else {
                // Hover grows the capsule around its strip, as it grows the
                // notch around its wings. Drawn at the grown size, a song's
                // cover and bars jumped out at once while the shape still grew.
                activityStrip(activity, size: service.compactStripSize(for: activity, companion: service.compactCompanion))
            }
        } else if let departingMusic = service.departingMusic {
            Group {
                if floats { NotchCapsuleMusicStrip(service: service, snapshot: departingMusic) }
                else { NotchMusicStrip(service: service, snapshot: departingMusic) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if floats {
            NotchCapsuleRestingView(service: service, size: service.surfaceSize)
                .transition(.opacity)
        } else {
            compact
                .transition(.opacity)
        }
    }

    /// The island floats as a capsule, whose strips run end to end.
    private var floats: Bool { service.geometry.floats }

    /// `size` is the capsule's; a hanging strip keeps the camera's geometry.
    @ViewBuilder private func activityStrip(_ activity: NotchCompactActivity, size: CGSize) -> some View {
        if floats {
            switch activity {
            case .timer: NotchCapsuleTimerStrip(service: service, size: size)
            case .watch: NotchCapsuleWatchStrip(service: service, size: size)
            case .downloads: NotchCapsuleDownloadStrip(service: service, size: size)
            case .agents: NotchCapsuleAgentStrip(service: service, size: size)
            case .calendar: NotchCapsuleCalendarStrip(service: service, size: size)
            case .music: NotchCapsuleMusicStrip(service: service, size: size)
            case .keepAwake: NotchCapsuleKeepAwakeStrip(service: service, size: size)
            }
        } else {
            switch activity {
            case .timer: NotchTimerStrip(service: service)
            case .watch: NotchWatchStrip(service: service)
            case .downloads: NotchDownloadStrip(service: service)
            case .agents: NotchAgentStrip(service: service)
            case .calendar: NotchCalendarStrip(service: service)
            case .music: NotchMusicStrip(service: service)
            case .keepAwake: NotchKeepAwakeStrip(service: service)
            }
        }
    }

    private var compact: some View { NotchRestingStrip(service: service) }

    private var showsDetail: Bool { service.showingAppPanel || service.selectedMetric != nil }

    private var expanded: some View {
        VStack(spacing: NotchLayout.spacing) {
            header.zIndex(1)
            Group {
                if service.showingSections {
                    NotchSectionsView(service: service)
                } else if scrollsVertically {
                    ScrollView {
                        content
                            .frame(height: contentOverflows ? pageSize.height : nil)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.bottom, NotchLayout.scrollBottomPadding)
                            .contentShape(Rectangle())
                    }
                    .scrollIndicators(.automatic)
                    .notchScrollEdgeFade()
                } else {
                    content
                }
            }
            .frame(width: service.contentSize.width, height: service.contentSize.height, alignment: .top)
            .clipShape(NotchPageClip(top: service.expandedGeometry.pageTop))
        }
        .padding(.horizontal, NotchLayout.horizontalInset)
        .padding(.top, service.expandedGeometry.headerTopInset)
        .padding(.bottom, NotchLayout.bottomInset)
        .frame(width: service.expandedSize.width, height: service.expandedSize.height, alignment: .top)
    }

    /// Keep each page's minimum usable layout reachable when a custom height
    /// or the display leaves less room. The outer silhouette stays unchanged.
    private var pageSize: CGSize {
        let session = NotchTimerService.shared.session
        return NotchLayout.pageSize(
            content: service.contentSize, module: service.selected, detail: showsDetail,
            controls: NotchSupport.controls(),
            timerMode: session.hasSession ? session.mode : NotchTimerSupport.savedMode(),
            timerHasSession: session.hasSession,
            hasPlayback: music.playback != nil,
            musicControlsRow: NotchMusicControls().hasRow,
            layout: service.geometry.layout)
    }

    private var contentOverflows: Bool { pageSize.height > service.contentSize.height }

    private var scrollsVertically: Bool {
        guard !service.showingAppPanel else { return false }
        return contentOverflows || service.selectedMetric != nil
            || (service.selected == .captures && service.captureContent != nil)
            || (service.selected == .tools && launcher.isEditing && launcher.activeUtility == nil)
    }

    private var headerFeedback: NotchNotice? {
        guard let notice = service.notice, notice.level != nil,
              [.volume, .brightness, .keyboardLight].contains(notice.event) else { return nil }
        return notice
    }

    private var header: some View {
        HStack(spacing: service.expandedGeometry.headerCameraGap > 0 ? 0 : 6) {
            let quickActions = NotchQuickAccessConfiguration.current().actions
            HStack(spacing: NotchLayout.headerButtonSpacing) {
                if service.showingSections {
                    NotchIconButton(symbol: "chevron.left", title: l10n.s.obBack, action: service.toggleSections)
                    if service.expandedGeometry.headerCameraGap == 0 {
                        Text(text.sectionsTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    // Beside the camera the field takes the rest of its side,
                    // stopping a little short of the cutout.
                    NotchSectionSearch(service: service,
                                       maximumFieldWidth: service.expandedGeometry.headerCameraGap > 0 ? .infinity : 150)
                        .padding(.trailing, service.expandedGeometry.headerCameraGap > 0 ? 6 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if showsDetail || service.modules.isEmpty {
                    if showsDetail {
                        NotchIconButton(symbol: "chevron.left", title: l10n.s.obBack, action: service.goBack)
                    }
                    Text(service.detailTitle)
                        .font(Font(NotchLayout.detailTitleFont as CTFont))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    if !quickActions.contains(.explore) {
                        NotchIconButton(symbol: "square.grid.2x2", title: text.sectionsTitle, action: service.toggleSections)
                    }
                    Text(service.selected.title(l10n.language))
                        .font(Font(NotchLayout.headerTitleFont as CTFont))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: service.expandedGeometry.headerSideWidth(contentWidth: service.contentSize.width))
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep search mounted so a media key never discards its focus.
            .opacity(headerFeedback == nil ? 1 : 0)
            .allowsHitTesting(headerFeedback == nil)
            .accessibilityHidden(headerFeedback != nil)
            .overlay(alignment: .leading) {
                if let notice = headerFeedback { NotchExpandedLevelView(notice: notice) }
            }
            .clipped()
            if service.expandedGeometry.headerCameraGap > 0 {
                Color.clear.frame(width: service.expandedGeometry.headerCameraGap)
            }
            HStack(spacing: 6) {
                if service.selected == .captures, !showsDetail, !service.showingSections,
                   let actions = service.captureActions {
                    actions.fixedSize()
                    overflowMenu(items: overflowItems(tools: false, clear: false))
                } else if service.expandedGeometry.headerCameraGap > 0 {
                    cameraHeaderActions
                } else {
                    headerActions(quickActions: quickActions)
                }
            }
            .frame(width: service.expandedGeometry.headerSideWidth(contentWidth: service.contentSize.width),
                   alignment: .trailing)
        }
        .frame(height: service.expandedGeometry.headerRowHeight)
        .contentShape(Rectangle())
        .onHover { headerHovered = $0 }
        .onAppear { UpdateService.shared.checkIfStale() }
        // Collapsing under the pointer takes the row away without a final
        // hover(false); the next opening starts with the actions out of sight.
        .onDisappear { headerHovered = false }
    }

    /// The island's history page shows only the cards, so its clear action
    /// sits in the header, where the panel's own header keeps it.
    private var showsCapturesClear: Bool {
        service.selected == .captures && service.captureContent == nil && !showsDetail
            && !service.showingSections && !service.modules.isEmpty
    }

    private var cameraHeaderActions: some View {
        ViewThatFits(in: .horizontal) {
            cameraHeaderActions(compactUpdate: false).fixedSize(horizontal: true, vertical: false)
            cameraHeaderActions(compactUpdate: true).fixedSize(horizontal: true, vertical: false)
        }
    }

    private func cameraHeaderActions(compactUpdate: Bool) -> some View {
        HStack(spacing: 6) {
            NotchUpdateControl(action: service.showUpdate, compact: compactUpdate)
            overflowMenu(items: overflowItems(
                tools: service.selected == .tools && !showsDetail && !service.showingSections && launcher.activeUtility == nil,
                clear: showsCapturesClear))
        }
    }

    /// The header's overflow entries, each with the glyph its own button
    /// wears when the pointer row shows them separately.
    private func overflowItems(tools: Bool, clear: Bool) -> [NotchMenuItem] {
        var items: [NotchMenuItem] = []
        if tools {
            items.append(NotchMenuItem(title: text.customizeTools, checked: launcher.isEditing,
                                       symbol: "slider.horizontal.3") { launcher.isEditing.toggle() })
        }
        if clear {
            // As the header draws, the pointer on its way to this menu included,
            // and again when chosen: this view does not observe the history.
            let empty = { RecentCapturesView.visible(RecentCaptureService.shared.entries).isEmpty }
            items.append(NotchMenuItem(title: FeatureStrings.recentCaptures(l10n.language).clear, symbol: "trash",
                                       enabled: !empty(), action: {
                guard !empty() else { return }
                RecentCapturesView.confirmClearAboveIsland()
            }))
        }
        if !items.isEmpty { items.append(.separator) }
        items.append(NotchMenuItem(title: service.pinned ? text.unpin : text.pin,
                                   symbol: service.pinned ? "pin.slash" : "pin") { service.pinned.toggle() })
        items.append(NotchMenuItem(title: l10n.s.menuSettings, symbol: "gearshape", action: service.openSettings))
        items.append(NotchMenuItem(title: text.collapse, symbol: "chevron.up", action: service.collapse))
        return items
    }

    /// A native menu drawn in the island's dark appearance, so it reads as part
    /// of it, and each entry carries its glyph.
    private func overflowMenu(items: [NotchMenuItem]) -> some View {
        NotchMenuButton(title: text.title, items: items, cornerRadius: 8) {
            Image(systemName: service.pinned ? "pin.fill" : "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// The header's actions keep their room but stay out of sight until the
    /// pointer reaches the row: a title, not a toolbar. An available update
    /// leaves a dot so it is never missed, and a download stays in view.
    /// The fade follows the value instead of the hover callback's transaction,
    /// which reached the screen without its animation once the island was key.
    private func headerActions(quickActions: [NotchQuickAction]) -> some View {
        let updating = updates.state.isInProgress
        let revealed = headerHovered || updating
        return HStack(spacing: 6) {
            NotchUpdateControl(action: service.showUpdate)
            if service.selected == .tools, !service.showingAppPanel, !service.showingSections, service.selectedMetric == nil,
               !service.modules.isEmpty, launcher.activeUtility == nil {
                NotchIconButton(symbol: launcher.isEditing ? "checkmark" : "slider.horizontal.3",
                                title: text.customizeTools, selected: launcher.isEditing) {
                    withAnimation(.easeOut(duration: 0.15)) { launcher.isEditing.toggle() }
                }
            }
            if showsCapturesClear { NotchClearCapturesButton() }
            // Keeping the island open is one click, like the floating buttons;
            // a header button steps aside when the same action floats beside it.
            if !quickActions.contains(.pin) {
                NotchIconButton(symbol: service.pinned ? "pin.fill" : "pin",
                                title: service.pinned ? text.unpin : text.pin, selected: service.pinned) {
                    service.pinned.toggle()
                }
            }
            if !quickActions.contains(.settings) {
                NotchIconButton(symbol: "gearshape", title: l10n.s.menuSettings, action: service.openSettings)
            }
            NotchIconButton(symbol: "chevron.up", title: text.collapse, action: service.collapse)
        }
        .opacity(revealed ? 1 : 0)
        .overlay(alignment: .trailing) {
            if !revealed {
                HStack(spacing: 5) {
                    if case .available(let version) = updates.state {
                        Circle()
                            .fill(UpdateServiceSupport.SemanticVersion(raw: version)?.isPrerelease == true ? Color.orange : Color.blue)
                            .frame(width: 6, height: 6)
                    }
                    // A kept-open island says so at rest, not only under the pointer.
                    if service.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 28, height: 28)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: revealed)
    }

    private var navigationTitle: String {
        let destination = service.reopeningDestination
        return destination.appPanel || destination.sections
            ? text.sectionsTitle : destination.module.title(l10n.language)
    }

    private var navigation: some View {
        Button(action: service.toggleSections) {
            HStack(spacing: 9) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(navigationTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: NotchLayout.navigationHeight)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12, lifts: false))
        .accessibilityLabel(text.switchSection)
        .accessibilityValue(navigationTitle)
        .accessibilityIdentifier("notch.navigation")
        .help(text.switchSection + "  ⌘K")
    }

    @ViewBuilder private var content: some View {
        if service.showingAppPanel {
            MenuPanelView(notchSize: pageSize)
        } else if let metric = service.selectedMetric {
            if metric == .fan {
                NotchFanControlView()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { service.updateFanDetailHeight($0) }
            } else {
                MetricDetailView(kind: metric)
            }
        } else if service.modules.isEmpty {
            NotchEmptyView(symbol: "slider.horizontal.3", message: text.empty)
        } else {
            switch service.selected {
            case .timer: NotchTimerView(size: pageSize)
            case .camera: NotchCameraView(size: pageSize)
            case .notifications: NotchNotificationsView(size: pageSize)
            case .downloads: NotchDownloadsView(size: pageSize)
            case .calendar: NotchCalendarView(size: pageSize)
            case .controls: NotchControlsView(service: service, size: pageSize)
            case .mixer: NotchMixerView(size: pageSize)
            case .music: NotchMusicView(size: pageSize, extrasHeight: service.geometry.musicExtrasHeight)
            case .clipboard: NotchClipboardView(service: service, size: pageSize)
            case .captures:
                if let capture = service.captureContent {
                    capture.frame(maxWidth: .infinity)
                } else {
                    RecentCapturesView(onClose: nil, notchSize: pageSize)
                }
            case .files: NotchFilesView(service: service)
            case .system:
                NotchSystemView(size: pageSize) { service.showMetric($0) }
            case .tools: QuickLauncherView(notchSize: pageSize)
            case .scratchpad: NotchScratchpadView(service: service)
            case .agents: NotchAgentsView(size: pageSize)
            case .watch: NotchWatchView(size: pageSize)
            }
        }
    }
}

/// Observes the history on its own, so a new capture does not redraw the island.
private struct NotchClearCapturesButton: View {
    @ObservedObject private var history = RecentCaptureService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        NotchIconButton(symbol: "trash", title: FeatureStrings.recentCaptures(l10n.language).clear,
                        action: RecentCapturesView.confirmClearAboveIsland)
            .disabled(RecentCapturesView.visible(history.entries).isEmpty)
    }
}

/// Read-only RPM telemetry stays available when the protected fan helper fails.
private struct NotchFanControlView: View {
    @ObservedObject private var monitor = SystemMonitor.shared

    var body: some View {
        FanControlSection(collapsible: false, fallbackFanSpeeds: monitor.snapshot.fanSpeeds)
    }
}

private extension UpdateService.State {
    /// A download or install stays in view; an offer waits behind the dot.
    var isInProgress: Bool {
        switch self {
        case .downloading, .installing: return true
        default: return false
        }
    }
}

/// The closed island at rest beside a camera: the wings with the charge,
/// the song or the AI allowance the person chose, when the menus leave room.
package struct NotchRestingStrip: View {
    @ObservedObject package var service: NotchService
    /// Another display's strip, when the island shows on every display.
    package var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var music = NotchMusicService.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.geometry }

    /// Centre battery content inside the wing's visible area, past its curved shoulder.
    private var restingBatteryInset: CGFloat {
        // Leave enough of the 44-point wing for the full 100% label at every height.
        min(16, NotchLayout.shoulder(height: geometry.stripHeight) + NotchLayout.compactEdgeGap)
    }

    package var body: some View {
        HStack(spacing: 0) {
            if service.idleContent != .none, geometry.restingWingWidth > 0 {
                Group {
                    switch service.idleContent {
                    case .music:
                        if let artwork = music.artwork {
                            Image(nsImage: artwork).resizable().scaledToFill()
                                .frame(width: min(22, geometry.stripHeight - 6), height: min(22, geometry.stripHeight - 6))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    case .battery:
                        Image(systemName: "battery.100percent").font(.system(size: 12))
                            .padding(.leading, restingBatteryInset)
                    case .agents:
                        NotchAgentRestingWing(leading: true)
                            .padding(.leading, restingBatteryInset)
                    case .none: EmptyView()
                    }
                }.frame(width: geometry.restingWingWidth, alignment: .trailing)
                Color.clear.frame(width: geometry.cameraWidth)
                Group {
                    switch service.idleContent {
                    case .music:
                        if music.playback?.isPlaying == true {
                            NotchLiveEqualizerBars(bars: 3, barWidth: 2, height: 11,
                                                   tint: music.artworkTint?.color ?? .white)
                        }
                    case .battery:
                        if let percent = service.power.chargePercent {
                            Text("\(percent)%").font(.system(size: 9, weight: .medium)).monospacedDigit()
                                .lineLimit(1)
                                .padding(.trailing, restingBatteryInset)
                        }
                    case .agents:
                        NotchAgentRestingWing(leading: false)
                            .padding(.trailing, restingBatteryInset)
                    case .none: EmptyView()
                    }
                }.frame(width: geometry.restingWingWidth, alignment: .leading)
            } else { Color.clear }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

extension NotchModule: PanelOrderItem {}

/// A page may draw into the island's own margins and behind its header, which
/// the silhouette already bounds: the artwork's halo and hover growth fade out
/// there instead of ending at a hard edge. The header stays above the page.
private struct NotchPageClip: Shape {
    /// From the top of the page to the top of the island.
    let top: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - NotchLayout.horizontalInset, y: rect.minY - top,
                    width: rect.width + NotchLayout.horizontalInset * 2,
                    height: rect.height + top + NotchLayout.bottomInset))
    }
}

/// The strip the picker shows, a new one for each choice.
private struct NotchPickedStrip: Hashable {
    let activity: NotchCompactActivity
    let companion: NotchCompactActivity?
}

/// Named choices appear below the camera, with the current activity highlighted.
package struct NotchActivityPicker: View {
    @Namespace private var choice
    package let activities: [NotchCompactActivity]
    package let selected: NotchCompactActivity
    package let combinations: [NotchActivityCombination]
    package let combination: NotchActivityCombination?
    package let columns: Int
    package let language: AppLanguage
    package let select: (NotchCompactActivity) -> Void
    package let combine: (NotchActivityCombination) -> Void

    package var body: some View {
        VStack(spacing: NotchActivityPickerLayout.spacing) {
            individualChoices
            if !combinations.isEmpty {
                Menu {
                    ForEach(combinations) { pair in
                        Button { combine(pair) } label: {
                            Label(pair.title(language),
                                  systemImage: combination == pair ? "checkmark" : pair.companion.symbol)
                        }
                    }
                } label: {
                    Label(combination?.title(language) ?? FeatureStrings.notch(language).combineActivities,
                          systemImage: combination == nil ? "plus" : "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(combination == nil ? 0.75 : 1))
                        .frame(height: NotchActivityPickerLayout.combinationHeight)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("notch.activity.combine")
            }
        }
    }

    private var individualChoices: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NotchActivityPickerLayout.spacing),
                                 count: columns), spacing: NotchActivityPickerLayout.spacing) {
            ForEach(activities) { activity in
                let chosen = activity == selected && combination == nil
                Button { select(activity) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: activity.symbol)
                        Text(activity.title(language)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: NotchActivityPickerLayout.rowHeight)
                    .foregroundStyle(chosen ? Color.black : Color.white)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12))
                            if chosen {
                                RoundedRectangle(cornerRadius: 8).fill(Color.white)
                                    .matchedGeometryEffect(id: "choice", in: choice)
                            }
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(activity.title(language))
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("notch.activity.\(activity.rawValue)")
            }
        }
    }
}
