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

    /// The island as it opens on this section: the page, and its top row
    /// with what the page puts there, around the camera where the island has
    /// one. The row's own way to the sections leads it when nothing floats
    /// beside the island for that.
    private func island(size: CGSize, geometry: NotchGeometry) -> some View {
        let content = geometry.contentSize(for: size)
        let band = NotchBand(geometry: geometry, contentWidth: content.width)
        let wraps = geometry.pageTop == .wrapsCamera
        return NotchPagePreview(module: module, size: content)
            .frame(width: content.width, height: content.height, alignment: .top)
            .clipped()
            .padding(.top, geometry.pageTopInset - geometry.headerTopInset)
            .overlayPreferenceValue(NotchBandKey.self, alignment: .top) { items in
                if geometry.headerRowHeight > 0 {
                    NotchBandRow(band: band) {
                        if !wraps {
                            if !NotchQuickAccessConfiguration.current().actions.contains(.explore) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 28, height: 28)
                            }
                            items.leading
                        }
                    } trailing: {
                        items.trailing
                    }
                }
            }
            .environment(\.notchBand, band)
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
        // The island hands these rows their clearing from outside the page.
        case .notifications:
            NotchNotificationsView(size: size).notchBand(trailing: { NotchClearNotificationsButton() })
        case .downloads: NotchDownloadsView(size: size)
        case .calendar: NotchCalendarView(size: size)
        case .controls: NotchControlsView(service: notch, size: size)
        case .mixer: NotchMixerView(size: size)
        case .music: NotchMusicView(size: size, extrasHeight: notch.geometry.musicExtrasHeight)
        case .clipboard: NotchClipboardView(service: notch, size: size)
        case .captures:
            RecentCapturesView(onClose: nil, notchSize: size).notchBand(trailing: { NotchClearCapturesButton() })
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

/// The scratchpad page without its editor: the current note, or the prompt a
/// new one shows, and in the island's row the pads and the note's actions as
/// the page puts them there.
private struct NotchScratchpadStill: View {
    @ObservedObject private var pad = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchBand) private var band
    @AppStorage(Preferences.scratchpadTextSize) private var storedTextSize: Double
    var body: some View {
        let text = FeatureStrings.scratchpad(l10n.language)
        Text(pad.text.isEmpty ? text.placeholder : pad.text)
            .font(.system(size: ScratchpadSupport.sanitizedTextSize(storedTextSize)))
            .foregroundStyle(.white.opacity(pad.text.isEmpty ? 0.35 : 0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .notchBand(leading: {
                if band.besideCamera {
                    HStack(spacing: 4) {
                        Text(pad.selectedPadName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 7)
                } else {
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            let names = pad.pads.isEmpty ? [text.pageTitle] : pad.pads.map(\.name)
                            ForEach(Array(names.prefix(4).enumerated()), id: \.offset) { index, name in
                                tab(name, selected: pad.pads.isEmpty || pad.pads[index].id == pad.selectedPadID)
                            }
                        }
                        Spacer(minLength: 0)
                        glyph("plus")
                    }
                }
            }, trailing: {
                HStack(spacing: 6) {
                    ForEach(["textformat", "eye", "doc.on.doc"], id: \.self) { glyph($0) }
                }
            })
    }

    private func tab(_ name: String, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if selected {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .foregroundStyle(selected ? .white : .white.opacity(0.6))
        .padding(.leading, 10)
        .padding(.trailing, selected ? 8 : 10)
        .frame(height: 22)
        .background(.white.opacity(selected ? 0.14 : 0.05), in: Capsule())
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .frame(width: 28, height: 28)
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
    /// Whether Settings can be seen: the page is let go while it cannot.
    @ObservedObject private var window: SettingsWindowVisibility
    /// What this preview holds open with the panel host.
    @State private var viewing = NotchPaneViewer()
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }
    /// The widest the live page is drawn: about the open island's.
    private static let islandWidth: CGFloat = 400

    package init(title: String, symbol: String, hidden: Bool, page: ToolPanelHost.Key? = nil,
                 host: ToolPanelHost = .shared, window: SettingsWindowVisibility = .shared) {
        self.title = title
        self.symbol = symbol
        self.hidden = hidden
        self.page = page
        self.host = host
        self.window = window
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

    // The open and close hooks sit on one stack, never on a `Group`: a
    // `Group` hands its modifiers to each view it draws, so they would fire
    // again each time the tile gives way to the page, and the preview would
    // close the page it had just opened (`MenuPanelExtensionPage` says the
    // same). The stack is one view whatever it holds.
    package var body: some View {
        VStack(spacing: 0) {
            if let page, Self.drawsLive(host.shown[page], defersToIsland: host.defersToIsland(page)) {
                live(page)
            } else {
                tile
            }
        }
        // Exactly the room it is given, never its page's height.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
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
        .onAppear {
            viewing.onScreen = true
            look()
        }
        .onDisappear {
            viewing.onScreen = false
            look()
        }
        .onChange(of: page) { _, _ in look() }
        .onChange(of: window.isVisible) { _, _ in look() }
    }

    /// Holds the page open while the preview is on screen and Settings can
    /// be seen, and only then.
    private func look() {
        viewing.hold(page, in: .island, while: viewing.onScreen && window.isVisible, host: host)
    }

    /// The page as the island draws it, in the island's black, from its
    /// top, cut off at the card's foot when it is taller. Only a picture, as
    /// the island's own previews beside it are: nothing in it can be
    /// pressed, so a click never reaches the tool (a speaker extension would
    /// speak).
    ///
    /// The page is drawn at its own height and the card never at more than
    /// the room it is given: a frame with only a maximum takes its
    /// content's height when that is taller, so a page taller than the card
    /// drew past it, centred, over the pane's header above and its settings
    /// below (3.63.0).
    private func live(_ page: ToolPanelHost.Key) -> some View {
        ToolPanelView(key: page, size: .island, host: host)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .environment(\.notchSettingsPreview, true)
            .allowsHitTesting(false)
            .padding(14)
            .frame(maxWidth: Self.islandWidth)
            .background(.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            // Clear of the caption under it.
            .padding(.bottom, 32)
            // One element to VoiceOver too, whose controls it cannot press.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(editor.preview)
            .accessibilityValue(Text(verbatim: title))
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

/// What one view of the extension's pane holds open with the panel host:
/// the page it shows, while the view is on screen and Settings can be seen.
/// Settings keeps its window when it closes, and the page that was showing
/// is never removed, so its `onDisappear` is not sure to run on close nor
/// its `onAppear` on reopening: the window's visibility says when to let go
/// and when to ask again. A reference, so what it holds is known at once.
@MainActor
final class NotchPaneViewer {
    /// The view's own token with the host: it lets go of its own view of
    /// the page, never another's.
    let viewer = UUID()
    /// The view is on screen: between its onAppear and its onDisappear.
    var onScreen = false
    /// The page held open now.
    private(set) var held: ToolPanelHost.Key?

    /// Holds `page` open in `place` while `wanted`, letting go of any other
    /// page held; lets go when not `wanted`.
    func hold(_ page: ToolPanelHost.Key?, in place: ToolPanelPlacement, while wanted: Bool, host: ToolPanelHost) {
        let next = wanted ? page : nil
        guard next != held else { return }
        if let held { host.closeAsViewer(held, viewer: viewer) }
        if let next { host.openAsViewer(next, in: place, viewer: viewer) }
        held = next
    }
}

/// The chosen section's column of the Content tab, which scrolls: its
/// header, its options and, in a narrow window, its preview.
package struct NotchSectionScroll<Content: View>: View {
    let content: Content

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    package var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.bottom, 22)
        }
    }
}

/// An extension's island page in the Content tab's column, top to bottom
/// as `NotchExtensionPane` orders it: its header, the live preview of its
/// island page (in a narrow window; a wide one draws it in a column of its
/// own), its settings page and the button to Extensions.
package struct NotchExtensionDetail: View {
    package let pane: NotchExtensionPane
    package let title: String
    package let symbol: String
    /// Whether the island lists the page.
    package let shown: Bool
    /// The preview's height in this column; nil when the page draws the
    /// preview in a column of its own.
    package let previewHeight: CGFloat?
    /// Opens the extension in Extensions.
    package let manage: () -> Void
    @ObservedObject private var l10n = L10n.shared
    private let host: ToolPanelHost
    private let window: SettingsWindowVisibility
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }

    package init(pane: NotchExtensionPane, title: String, symbol: String, shown: Bool, previewHeight: CGFloat?,
                 host: ToolPanelHost = .shared, window: SettingsWindowVisibility = .shared,
                 manage: @escaping () -> Void) {
        self.pane = pane
        self.title = title
        self.symbol = symbol
        self.shown = shown
        self.previewHeight = previewHeight
        self.host = host
        self.window = window
        self.manage = manage
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(pane.parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .header:
                    NotchSectionHeader(title: title, summary: editor.extensionSummary,
                                       tile: NotchSectionTile(extensionSymbol: symbol, shown: shown, side: 38),
                                       reason: nil, openFeatures: manage)
                case .preview(let page):
                    if let previewHeight {
                        NotchExtensionPreview(title: title, symbol: symbol, hidden: !shown, page: page, host: host,
                                              window: window)
                            .frame(height: previewHeight)
                    }
                case .settings(let key):
                    SettingsCard { NotchExtensionSettings(key: key, host: host, window: window) }
                case .manage:
                    Button(editor.manageInExtensions, action: manage).controlSize(.small)
                }
            }
        }
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
    /// Whether Settings can be seen: the page is let go while it cannot.
    @ObservedObject private var window: SettingsWindowVisibility
    /// What this card holds open with the panel host.
    @State private var viewing = NotchPaneViewer()
    /// Set while the page is asked for, so a page that is gone (its tool
    /// stopped) reads as not shown rather than as still coming.
    @State private var asked = false
    @State private var query = ""
    @FocusState private var focus: ExternalToolDetail.Focus?
    /// How tall the region the page scrolls in is.
    private static let height: CGFloat = 360

    package init(key: ToolPanelHost.Key, host: ToolPanelHost = .shared, window: SettingsWindowVisibility = .shared) {
        self.key = key
        self.host = host
        self.window = window
    }

    package var body: some View {
        let text = FeatureStrings.externalTools(l10n.language)
        let title = l10n.s.panelSettings
        // On one stack, never a `Group`, so the hooks fire once for each time
        // the page is on screen, not each time the spinner gives way to it.
        VStack(alignment: .leading, spacing: 0) {
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
                        ExtensionSettingsPanel(key: key, title: title, kept: kept, text: text, focus: $focus,
                                               host: host)
                    }
                }
                // Escape clears a search.
                .onExitCommand { query = "" }
            }
        }
        .onAppear {
            viewing.onScreen = true
            ask()
        }
        .onDisappear {
            viewing.onScreen = false
            ask()
        }
        .onChange(of: window.isVisible) { _, _ in ask() }
    }

    /// Holds the page open while the card is on screen and Settings can be
    /// seen, and only then.
    private func ask() {
        viewing.hold(key, in: .settings, while: viewing.onScreen && window.isVisible, host: host)
        asked = viewing.held != nil
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
