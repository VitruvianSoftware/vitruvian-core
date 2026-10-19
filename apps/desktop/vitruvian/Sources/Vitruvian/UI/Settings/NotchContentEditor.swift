// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The open island for one section, hanging from a slice of menu bar: the
/// island's own pages at their real size, scaled into Settings, so every
/// option changes the preview the way it changes the island.
package struct NotchIslandPreview: View {
    package let module: NotchModule
    /// The section is switched off, or the feature behind it is.
    package var hidden = false
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(Preferences.notchLiquidGlassEnabled) private var glass: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monitoring = false
    @State private var windowVisible = false
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }
    private static let captionHeight: CGFloat = 28
    private static let margin: CGFloat = 16

    /// One scale for every section, taken from the tallest island, so the
    /// preview keeps its size and choosing a section never moves the list
    /// under the pointer.
    package static func scale(in stage: CGSize) -> CGFloat {
        let largest = NotchService.shared.previewLargestSize
        guard largest.width > 0, largest.height > 0 else { return 1 }
        return max(0.1, min(1, (stage.width - margin * 2) / largest.width, (stage.height - captionHeight) / largest.height))
    }

    /// As tall as the tallest island at the scale that fits the width, within
    /// the limit the page gives it.
    package static func height(width: CGFloat, limit: CGFloat) -> CGFloat {
        NotchService.shared.previewLargestSize.height * scale(in: CGSize(width: width, height: limit)) + captionHeight
    }

    package var body: some View {
        previewSurface
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: module)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(editor.preview)
            .accessibilityValue(module.title(l10n.language) + (hidden ? ", " + editor.hiddenInIsland : ""))
            .onAppear { monitor(windowVisible && module == .system) }
            .onChange(of: module) { _, value in monitor(windowVisible && value == .system) }
            .onChange(of: windowVisible) { _, visible in monitor(visible && module == .system) }
            .onDisappear { monitor(false) }
    }

    private var previewSurface: some View {
        GeometryReader { proxy in stage(in: proxy.size) }
            .background(.quaternary.opacity(0.35))
            .background(WindowVisibilityReader { windowVisible = $0 })
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottomLeading) { caption }
    }

    private func stage(in stageSize: CGSize) -> some View {
        let geometry = notch.previewGeometry(for: module)
        let size = notch.previewSize(for: module)
        let scale = Self.scale(in: stageSize)
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(.primary.opacity(0.06))
                .frame(height: geometry.menuBarHeight * scale)
            if windowVisible {
                island(size: size, geometry: geometry)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .top)
                    .opacity(hidden ? 0.4 : 1)
            }
        }
        .frame(width: stageSize.width, height: stageSize.height, alignment: .top)
    }

    private var caption: some View {
        Label(hidden ? editor.hiddenInIsland : editor.preview, systemImage: hidden ? "eye.slash" : "eye")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    /// The system page reads live metrics, which sample only while a surface
    /// shows them; the preview counts as one, like the menu panel.
    private func monitor(_ wanted: Bool) {
        guard wanted != monitoring else { return }
        monitoring = wanted
        if wanted { SystemMonitor.shared.panelDidAppear() } else { SystemMonitor.shared.panelDidDisappear() }
    }

    private var glassSurface: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *) { return glass && !reduceTransparency }
#endif
        return false
    }

    private func island(size: CGSize, geometry: NotchGeometry) -> some View {
        let content = geometry.contentSize(for: size)
        return VStack(spacing: NotchLayout.spacing) {
            header(geometry: geometry, width: content.width)
            NotchPagePreview(module: module, size: content)
                .frame(width: content.width, height: content.height, alignment: .top)
                .clipped()
        }
        .padding(.horizontal, NotchLayout.horizontalInset)
        .padding(.top, geometry.headerTopInset)
        .padding(.bottom, NotchLayout.bottomInset)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background {
            NotchShape.island(height: size.height, geometry: geometry).fill(.black)
        }
        .foregroundStyle(.white)
        .tint(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.notchPresentation, true)
        .environment(\.notchGlassSurface, glassSurface)
        .environment(\.notchSettingsPreview, true)
        .allowsHitTesting(false)
    }

    /// The island's title row: the section's name, the camera between the
    /// halves, and the actions that wait for the pointer.
    private func header(geometry: NotchGeometry, width: CGFloat) -> some View {
        let half = geometry.headerSideWidth(contentWidth: width)
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if !NotchQuickAccessConfiguration.current().actions.contains(.explore) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                }
                Text(module.title(l10n.language))
                    .font(Font(NotchLayout.headerTitleFont as CTFont))
                    .lineLimit(1)
            }
            .frame(width: half, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            if geometry.headerCameraGap > 0 {
                Color.clear.frame(width: geometry.headerCameraGap)
            }
            // In a row of its own the title takes the width the actions leave.
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 28, height: 28)
                .frame(width: half, alignment: .trailing)
                .frame(maxWidth: half == nil ? nil : .infinity, alignment: .trailing)
        }
        .frame(height: geometry.headerRowHeight)
    }
}

/// A section's page as the island draws it. The camera and the scratchpad
/// show a still instead: a preview must never turn the camera on or give a
/// text editor the keyboard.
package struct NotchPagePreview: View {
    package let module: NotchModule
    package let size: CGSize
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var l10n = L10n.shared

    package var body: some View {
        switch module {
        case .timer: NotchTimerView(size: size)
        case .camera: camera
        case .notifications: NotchNotificationsView(size: size)
        case .downloads: NotchDownloadsView(size: size)
        case .calendar: NotchCalendarView(size: size)
        case .controls: NotchControlsView(service: notch, size: size)
        case .mixer: NotchMixerView(size: size)
        case .music: NotchMusicView(size: size, extrasHeight: notch.geometry.musicExtrasHeight)
        case .clipboard: NotchClipboardView(service: notch, size: size)
        case .captures: RecentCapturesView(onClose: nil, notchSize: size)
        case .files: NotchFilesView(service: notch)
        case .system: NotchSystemView(size: size) { _ in }
        case .tools: QuickLauncherView(notchSize: size)
        case .scratchpad: NotchScratchpadStill()
        case .agents:
            // Off, nothing reads the logs, so the page would wait forever.
            if NotchAgentSupport.isEnabled() {
                NotchAgentsView(size: size)
            } else {
                NotchEmptyView(symbol: "sparkles", message: FeatureStrings.notchEditor(l10n.language).agentsSummary)
            }
        // The live area belongs to the island; the preview explains it instead.
        case .watch: NotchWatchView(size: size)
        }
    }

    private var camera: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text(FeatureStrings.notchEditor(l10n.language).cameraPreview)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(NotchControlSurface(cornerRadius: 18, interactive: false))
    }
}

/// The scratchpad page without its editor: the pads' tabs and the current
/// note, or the prompt a new one shows.
private struct NotchScratchpadStill: View {
    @ObservedObject private var pad = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(Preferences.scratchpadTextSize) private var storedTextSize: Double
    var body: some View {
        let text = FeatureStrings.scratchpad(l10n.language)
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                let names = pad.pads.isEmpty ? [text.pageTitle] : pad.pads.map(\.name)
                ForEach(Array(names.prefix(4).enumerated()), id: \.offset) { index, name in
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(.white.opacity(pad.pads.isEmpty || pad.pads[index].id == pad.selectedPadID ? 0.12 : 0),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Spacer(minLength: 0)
                ForEach(["textformat", "plus", "eye", "doc.on.doc", "ellipsis"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                }
            }
            Text(pad.text.isEmpty ? text.placeholder : pad.text)
                .font(.system(size: ScratchpadSupport.sanitizedTextSize(storedTextSize)))
                .foregroundStyle(.white.opacity(pad.text.isEmpty ? 0.35 : 0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
                .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One section in the list beside its options: the box that shows it in the
/// island, its icon and its name. A row drags to a new place; choosing one
/// opens its options and its preview. A box rather than a switch leaves the
/// name its whole line even in the narrowest window. A tool's island page
/// is a row like the island's own, in the tool's words.
package struct NotchSectionListRow: View {
    package let item: NotchSectionItem
    package let title: String
    package let summary: String
    package let tile: NotchSectionTile
    @Binding package var included: Bool
    package let available: Bool
    package let selected: Bool
    @Binding package var order: [NotchSectionItem]
    @Binding package var dragging: NotchSectionItem?
    package let select: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @State private var hovering = false

    package init(item: NotchSectionItem, title: String, summary: String, tile: NotchSectionTile, included: Binding<Bool>,
                 available: Bool, selected: Bool, order: Binding<[NotchSectionItem]>,
                 dragging: Binding<NotchSectionItem?>, select: @escaping () -> Void) {
        self.item = item
        self.title = title
        self.summary = summary
        self.tile = tile
        self._included = included
        self.available = available
        self.selected = selected
        self._order = order
        self._dragging = dragging
        self.select = select
    }

    package var body: some View {
        PanelReorderableItem(item: item, order: $order, dragging: $dragging) {
            HStack(spacing: 8) {
                // A section whose feature is off cannot show, whatever was chosen.
                Toggle(title, isOn: available ? $included : .constant(false))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(!available)
                Button(action: select) {
                    HStack(spacing: 8) {
                        tile.shown(included && available)
                        Text(verbatim: title)
                            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(available ? .primary : .secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 2)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(summary)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityValue(summary)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityAction(named: FeatureStrings.clipboard(l10n.language).moveUp) { move(by: -1) }
                .accessibilityAction(named: FeatureStrings.clipboard(l10n.language).moveDown) { move(by: 1) }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(selected ? Color.accentColor.opacity(0.16) : hovering ? Color.primary.opacity(0.05) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .opacity(dragging == item ? 0.45 : 1)
        }
    }

    private func move(by offset: Int) {
        guard let index = order.firstIndex(of: item), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
    }
}

/// What the chosen section is, above its options: its icon, name and one
/// line on what it shows, and why it cannot show while its feature is off.
package struct NotchSectionHeader: View {
    package let title: String
    package let summary: String
    package let tile: NotchSectionTile
    /// Why an unavailable section cannot show.
    package let reason: String?
    package let openFeatures: () -> Void
    @ObservedObject private var l10n = L10n.shared
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }

    package init(title: String, summary: String, tile: NotchSectionTile, reason: String?,
                 openFeatures: @escaping () -> Void) {
        self.title = title
        self.summary = summary
        self.tile = tile
        self.reason = reason
        self.openFeatures = openFeatures
    }

    package var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.title3.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason {
                    HStack(spacing: 10) {
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(editor.openFeatures, action: openFeatures).controlSize(.small)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A section's icon on its own color; grey while the section is hidden.
package struct NotchSectionTile: View {
    package let symbol: String
    package let tint: Color
    package let glyph: Color
    package var isShown: Bool
    package let side: CGFloat

    package init(symbol: String, tint: Color, glyph: Color = .white, shown: Bool, side: CGFloat) {
        self.symbol = symbol
        self.tint = tint
        self.glyph = glyph
        self.isShown = shown
        self.side = side
    }

    package init(module: NotchModule, shown: Bool, side: CGFloat) {
        self.init(symbol: module.symbol, tint: module.settingsTint, glyph: module.settingsGlyph, shown: shown, side: side)
    }

    /// A tool's island page, on the grey of the island's Tools.
    package init(extensionSymbol symbol: String, shown: Bool, side: CGFloat) {
        self.init(symbol: symbol, tint: NotchModule.tools.settingsTint, shown: shown, side: side)
    }

    /// The same tile, shown or hidden.
    package func shown(_ shown: Bool) -> Self {
        var tile = self
        tile.isShown = shown
        return tile
    }

    package var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.46, weight: .semibold))
            .foregroundStyle(isShown ? glyph : Color.secondary)
            .frame(width: side, height: side)
            .background(isShown ? tint : Color.secondary.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: side * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// What the Dynamic Island page's pane shows for an extension's island
/// page, top to bottom. Plain values, so a test reads the order without
/// drawing it. There is one settings page per extension: the pane shows the
/// same page the Extensions sheet does, and a change in either place is the
/// same change. What only that sheet holds, updating, removing and the log,
/// is a button away.
package struct NotchExtensionPane: Equatable {
    package enum Part: Equatable {
        /// The page's name and summary, with its tile.
        case header
        /// The extension's real island page, drawn live at the island's
        /// size; nil for the placeholder, a tile of its icon and name.
        case preview(ToolPanelHost.Key?)
        /// The extension's own settings page, with its search and links.
        case settings(ToolPanelHost.Key)
        /// The button that opens the extension in Extensions.
        case manage
    }

    package let parts: [Part]

    /// `manifest` is the tool's, nil for one that is not switched on;
    /// `shown` is whether the island lists its page. A page hidden from
    /// the island, or a tool with none, keeps the placeholder: nothing is
    /// started to draw it.
    package init(manifest: ExternalToolManifest?, shown: Bool) {
        let tool = manifest?.manifest.id
        let island = shown ? manifest?.panel(in: .island) : nil
        let settings = manifest?.panel(in: .settings)
        var parts: [Part] = [.header]
        parts.append(.preview(tool.flatMap { tool in island.map { ToolPanelHost.Key(tool: tool, panel: $0.id) } }))
        if let tool, let settings { parts.append(.settings(ToolPanelHost.Key(tool: tool, panel: settings.id))) }
        parts.append(.manage)
        self.parts = parts
    }

    /// The live preview's page, nil for the placeholder.
    package var preview: ToolPanelHost.Key? {
        for case .preview(let key) in parts { return key }
        return nil
    }
}

/// A tool's island page in the Content tab's preview column: the real page,
/// drawn live at the island's size in a black island, while the tool sends
/// it. In its place, a tile of the page's icon and name, as Explore shows
/// it: for a page hidden from the island, a tool with none, or one whose
/// page could not be shown. The preview is one more viewer of the page the
/// island and the menu bar panel show (`ToolPanelHost.openAsViewer`): it
/// never closes the page they show.
package struct NotchExtensionPreview: View {
    package let title: String
    package let symbol: String
    package let hidden: Bool
    /// The tool's island page, drawn live; nil for the tile.
    package let page: ToolPanelHost.Key?
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var host: ToolPanelHost
    /// This preview's own token with the panel host: it lets go of its own
    /// view of the page, never another's.
    @State private var viewer = UUID()
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }
    /// The widest the live page is drawn: about the open island's.
    private static let islandWidth: CGFloat = 400

    package init(title: String, symbol: String, hidden: Bool, page: ToolPanelHost.Key? = nil,
                 host: ToolPanelHost = .shared) {
        self.title = title
        self.symbol = symbol
        self.hidden = hidden
        self.page = page
        self.host = host
    }

    /// Whether the page is drawn live: it is coming, or here. A web page
    /// the island shows stays with the island, which holds its one web
    /// view, as the menu bar panel leaves it.
    package static func drawsLive(_ shown: ToolPanelHost.Shown?, defersToIsland: Bool) -> Bool {
        switch shown {
        case .waiting?, .page?: return true
        case .web?: return !defersToIsland
        case .notShown?, nil: return false
        }
    }

    package var body: some View {
        Group {
            if let page, Self.drawsLive(host.shown[page], defersToIsland: host.defersToIsland(page)) {
                live(page)
            } else {
                tile
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Label(hidden ? editor.hiddenInIsland : editor.preview, systemImage: hidden ? "eye.slash" : "eye")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
        }
        .onAppear { look(at: page) }
        .onDisappear { lookAway(from: page) }
        .onChange(of: page) { old, new in
            lookAway(from: old)
            look(at: new)
        }
    }

    private func look(at page: ToolPanelHost.Key?) {
        if let page { host.openAsViewer(page, in: .island, viewer: viewer) }
    }

    private func lookAway(from page: ToolPanelHost.Key?) {
        if let page { host.closeAsViewer(page, viewer: viewer) }
    }

    /// The page as the island draws it, in the island's black, scrolling
    /// when it is taller than the preview.
    private func live(_ page: ToolPanelHost.Key) -> some View {
        ScrollView(showsIndicators: false) {
            ToolPanelView(key: page, size: .island, host: host)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(14)
        .frame(maxWidth: Self.islandWidth)
        .background(.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        // Clear of the caption under it.
        .padding(.bottom, 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: editor.preview + ", " + title))
    }

    private var tile: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(minWidth: 160, minHeight: 120)
        .background(.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(hidden ? 0.4 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(editor.preview)
        .accessibilityValue(Text(verbatim: title + (hidden ? ", " + editor.hiddenInIsland : "")))
    }
}

/// An extension's own settings page on the Dynamic Island page: the same
/// page, search field and row of links the Extensions sheet shows
/// (`ExtensionSettingsOnePage`), so a change here is the change made
/// there. Vitruvian's own rows are left out: the Dynamic Island page has
/// its own switch for the page, and the rest is in Extensions. It is one
/// more viewer of the page the sheet shows (`ToolPanelHost.openAsViewer`).
package struct NotchExtensionSettings: View {
    package let key: ToolPanelHost.Key
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var host: ToolPanelHost
    @State private var viewer = UUID()
    /// Set once the page has been asked for, so a page that is gone (its
    /// tool stopped) reads as not shown rather than as still coming.
    @State private var asked = false
    @State private var query = ""
    @FocusState private var focus: ExternalToolDetail.Focus?
    /// How tall the region the page scrolls in is.
    private static let height: CGFloat = 360

    package init(key: ToolPanelHost.Key, host: ToolPanelHost = .shared) {
        self.key = key
        self.host = host
    }

    package var body: some View {
        let text = FeatureStrings.externalTools(l10n.language)
        let title = l10n.s.panelSettings
        Group {
            if host.shown[key] == nil {
                if asked {
                    ToolPanelNotShown(size: .standard)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 44)
                }
            } else {
                ExtensionSettingsOnePage(index: index(title: title), query: $query, height: Self.height, text: text,
                                         focus: $focus) { kept in
                    VStack(alignment: .leading, spacing: 16) {
                        if kept.nothingFound {
                            SettingsSheetNoMatch(text: text, query: query)
                        }
                        ExtensionSettingsPanel(key: key, title: title, kept: kept, text: text, focus: $focus)
                    }
                }
                // Escape clears a search.
                .onExitCommand { query = "" }
            }
        }
        .onAppear {
            host.openAsViewer(key, in: .settings, viewer: viewer)
            asked = true
        }
        .onDisappear {
            host.closeAsViewer(key, viewer: viewer)
            asked = false
        }
    }

    /// What the page holds, as its search and its links read it.
    private func index(title: String) -> SettingsSheetIndex {
        switch host.shown[key] {
        case .page(let tree)?:
            let page = BlockTreeContent(tree: tree, language: l10n.language.rawValue, folder: nil, size: .standard)
            return SettingsSheetIndex(page: page, isWeb: false, title: title)
        case .web?:
            return SettingsSheetIndex(page: nil, isWeb: true, title: title)
        case .waiting?, .notShown?, nil:
            return SettingsSheetIndex(page: nil, isWeb: false, title: title)
        }
    }
}

extension NotchModule {
    /// A color per section, like the icons of System Settings, so a long list
    /// can be scanned by eye.
    package var settingsTint: Color {
        switch self {
        case .controls: return .blue
        case .mixer: return .purple
        case .music: return .pink
        case .clipboard: return .brown
        case .captures: return .indigo
        case .files: return .cyan
        case .system: return .green
        case .tools: return .gray
        case .calendar: return .red
        case .notifications: return .orange
        case .timer: return .mint
        case .camera: return .teal
        case .downloads: return .blue
        case .scratchpad: return .yellow
        case .agents: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .watch: return .purple
        }
    }

    package var settingsGlyph: Color { self == .scratchpad ? .black.opacity(0.75) : .white }
}
