// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

extension NotchArtworkTint {
    package var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

/// The bars with the live levels attached. Only this small view observes the
/// audio service, so its thirty updates a second never re-render the island.
package struct NotchLiveEqualizerBars: View {
    package var isPlaying = true
    package var bars = 4
    package var barWidth: CGFloat = 2.5
    package var height: CGFloat = 14
    package var tint: Color = .white
    @ObservedObject private var audio = NotchAudioLevelService.shared

    package var body: some View {
        NotchEqualizerBars(isPlaying: isPlaying, bars: bars, barWidth: barWidth, height: height, tint: tint,
                           live: audio.levels)
    }
}

/// A level readout in the same language as the notch's sliders, instead of the
/// thin system bar, so every meter in the panel matches.
package struct NotchMeter: View {
    package let value: Double
    package var height: CGFloat = 5
    package var tint: Color = .white

    package var body: some View {
        let fraction = value.isFinite ? min(1, max(0, value)) : 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(.white.opacity(0.14))
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.9))
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A clock's digits roll into the next reading, downward while it counts
/// down and upward while it counts up; Reduce Motion changes them in place.
package struct NotchRollingDigits: ViewModifier {
    package let value: String
    package let countsDown: Bool
    /// Off in the closed island, where only the part above the seconds rolls.
    package var everySecond = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package func body(content: Content) -> some View {
        content
            .contentTransition(.numericText(countsDown: countsDown))
            .animation(reduceMotion ? nil : .smooth(duration: 0.3),
                       value: NotchTimerSupport.rollingValue(value, everySecond: everySecond))
    }
}

package struct NotchIconButton: View {
    package let symbol: String
    package let title: String
    package var selected = false
    package let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? .white : .white.opacity(0.55))
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: symbol)
                .frame(width: NotchLayout.iconButtonSide, height: NotchLayout.iconButtonSide)
                .background(.white.opacity(selected ? 0.12 : 0),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(symbol: String, title: String, selected: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.selected = selected
        self.action = action
    }
}

/// A short island puts the glyph beside its message; taller ones stack them.
package struct NotchEmptyView: View {
    package let symbol: String
    package let message: String

    package var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 12) {
                glyph
                label.frame(maxWidth: 250)
            }
            HStack(spacing: 14) {
                glyph
                label.frame(maxWidth: 260, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(.white.opacity(0.65))
            .frame(width: 56, height: 56)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }

    private var label: some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(symbol: String, message: String) {
        self.symbol = symbol
        self.message = message
    }
}

package struct NotchArtwork: View {
    package let image: NSImage?
    package let size: CGFloat

    package var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.black.overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// Items fill each column top to bottom and continue sideways, so a short
/// island scrolls to the side and never down. Whenever everything fits
/// without scrolling, the items read left to right instead, in rows of equal
/// cells across the full width, and a short last row sits centered.
package struct NotchRail<Item: Identifiable, Content: View>: View {
    package let items: [Item]
    package let rows: Int
    package let itemWidth: CGFloat
    package let width: CGFloat
    package var spacing: CGFloat = 8
    package var rowSpacing: CGFloat = 8
    package var scrollTarget: Item.ID? = nil
    @ViewBuilder package let content: (Item) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Spelled out because a memberwise initializer never leaves its module.
    package init(items: [Item], rows: Int, itemWidth: CGFloat, width: CGFloat, spacing: CGFloat = 8,
                 rowSpacing: CGFloat = 8, scrollTarget: Item.ID? = nil,
                 @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.rows = rows
        self.itemWidth = itemWidth
        self.width = width
        self.spacing = spacing
        self.rowSpacing = rowSpacing
        self.scrollTarget = scrollTarget
        self.content = content
    }

    private var columns: Int { NotchLayout.railColumns(count: items.count, rows: rows) }
    private var starts: [Int] { Array(stride(from: 0, to: items.count, by: max(1, rows))) }
    private var rowStarts: [Int] { Array(stride(from: 0, to: items.count, by: max(1, columns))) }
    private var fits: Bool {
        NotchLayout.railFits(columns: columns, itemWidth: itemWidth, spacing: spacing, width: width)
    }

    // Scroll to the column itself: its identity is known before lazy children
    // are created, including a target well outside the current viewport.
    private var targetColumn: Int? {
        guard let scrollTarget, let index = items.firstIndex(where: { $0.id == scrollTarget }) else { return nil }
        return index / max(1, rows) * max(1, rows)
    }

    package var body: some View {
        if fits {
            let cell = (width - CGFloat(max(0, columns - 1)) * spacing) / CGFloat(max(1, columns))
            VStack(spacing: rowSpacing) {
                ForEach(rowStarts, id: \.self) { start in row(start, cell: cell) }
            }
        } else {
            ScrollViewReader { proxy in
                // Legacy scroll bars would take a row's worth of height; the
                // column cut at the edge is the cue that more follows.
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: spacing) {
                        ForEach(starts, id: \.self) { start in column(start).frame(width: itemWidth).id(start) }
                    }
                    .contentShape(Rectangle())
                }
                .scrollIndicators(.never)
                .notchScrollEdgeFade(.horizontal)
                .onAppear {
                    if let targetColumn { proxy.scrollTo(targetColumn, anchor: .center) }
                }
                .onChange(of: targetColumn) { _, target in
                    guard let target else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(_ start: Int, cell: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(items[start..<min(items.count, start + max(1, columns))]) { item in
                content(item).frame(width: cell)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func column(_ start: Int) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(items[start..<min(items.count, start + max(1, rows))]) { item in
                content(item)
            }
        }
    }
}

private struct NotchGlassSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    package var notchGlassSurface: Bool {
        get { self[NotchGlassSurfaceKey.self] }
        set { self[NotchGlassSurfaceKey.self] = newValue }
    }

    /// A page drawn in Settings to preview the island. It shows what the
    /// island shows but must leave the island's state and the keyboard alone.
    package var notchSettingsPreview: Bool {
        get { self[NotchSettingsPreviewKey.self] }
        set { self[NotchSettingsPreviewKey.self] = newValue }
    }
}

private struct NotchSettingsPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

package struct NotchBackdropShape: Shape {
    package var contour: Path
    package func path(in rect: CGRect) -> Path { contour }
}

package struct NotchWindowBackground: View {
    @ObservedObject package var presentation: NotchBackdropPresentation
    @AppStorage(Preferences.notchLiquidGlassEnabled) private var glass: Bool
    @AppStorage(Preferences.notchTranslucentBackground) private var translucent: Bool

    package var body: some View {
        NotchSurfaceBackground(presentation: presentation, glass: glass, translucent: translucent)
    }
}

/// Keep the upper content dark and open the lower surface into a refractive lip.
package struct NotchSurfaceBackground: View {
    @ObservedObject package var presentation: NotchBackdropPresentation
    package let glass: Bool
    package var translucent = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var offersGlass: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *) { return glass && !reduceTransparency }
#endif
        return false
    }

    private var showsGlass: Bool { offersGlass && presentation.usesGlass }
    private var showsTranslucent: Bool {
        translucent && !offersGlass && presentation.usesGlass && !reduceTransparency
    }

    package var body: some View {
        ZStack {
            // The black the island rests in stays beneath the glass until
            // the glass has opened, and the glass exists only while that
            // black lets it show, so the window's resizes at either end of a
            // transition happen in plain black.
            Color.black.opacity(showsGlass || showsTranslucent ? presentation.restingBlack : 1)
#if compiler(>=6.2)
            if #available(macOS 26, *), showsGlass, presentation.restingBlack < 1 {
                let shape = NotchBackdropShape(contour: presentation.contour)
                Color.clear
                    .glassEffect(.clear, in: shape)
                    .environment(\.appearsActive, true)
                    .materialActiveAppearance(.active)
                    .overlay {
                        LinearGradient(stops: Self.shade(openness: presentation.openness, contrast: contrast,
                                                             height: presentation.contourBottom),
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: presentation.contourBottom)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .mask(shape)
                    }
            }
#endif
            if showsTranslucent, presentation.restingBlack < 1 {
                translucentOrBlack
            }
        }
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The dimming over the glass, from the top of the island to its lip. Near
    /// a black strip the lip closes up, so the last frames of a collapse
    /// already match the resting island.
    /// The black holds over the whole page, and the lip opens in the margin
    /// below it (NotchGlassLip), measured in points over an island `height` tall.
    package static func shade(openness: Double, contrast: ColorSchemeContrast, height: CGFloat) -> [Gradient.Stop] {
        NotchGlassLip.stops(height: height, openness: openness, increasedContrast: contrast == .increased)
            .map { Gradient.Stop(color: .black.opacity($0.opacity), location: $0.location) }
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(presentation: NotchBackdropPresentation, glass: Bool, translucent: Bool = false) {
        self._presentation = ObservedObject(wrappedValue: presentation)
        self.glass = glass
        self.translucent = translucent
    }
}

extension NotchSurfaceBackground {
    /// The system's behind-window blur while the island is open, black over
    /// the camera strip so every open state meets the housing as the resting
    /// island does. Reduce Transparency keeps it black.
    @ViewBuilder package var translucentOrBlack: some View {
        if translucent, presentation.usesGlass, !reduceTransparency {
            let shape = NotchBackdropShape(contour: presentation.contour)
            let height = presentation.contourBottom
            let stops = NotchTranslucentTint.stops(height: height, stripHeight: presentation.stripHeight,
                                                   openness: presentation.openness,
                                                   increasedContrast: contrast == .increased)
                .map { Gradient.Stop(color: .black.opacity($0.opacity), location: $0.location) }
            // The blur covers only the island's box. Its mask image is drawn
            // again on every frame of a resize, and at the stage's size it
            // would be as large as the largest display.
            let box = presentation.contour.boundingRect.integral
            ZStack(alignment: .topLeading) {
                if !box.isNull, box.width > 0, box.height > 0 {
                    NotchTranslucentMaterial(contour: presentation.contour.offsetBy(dx: -box.minX, dy: -box.minY).cgPath)
                        .frame(width: box.width, height: box.height)
                        .padding(EdgeInsets(top: box.minY, leading: box.minX, bottom: 0, trailing: 0))
                }
                LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .mask(shape)
            }
        } else {
            Color.black
        }
    }
}

/// `NSVisualEffectView` blurs behind the window only inside its mask image,
/// so the mask follows the island's contour as it animates.
private struct NotchTranslucentMaterial: NSViewRepresentable {
    let contour: CGPath

    func makeNSView(context: Context) -> NotchTranslucentView {
        let view = NotchTranslucentView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NotchTranslucentView, context: Context) {
        view.contour = contour
    }
}

private final class NotchTranslucentView: NSVisualEffectView {
    var contour: CGPath? {
        didSet { if contour != oldValue { updateMask() } }
    }

    override var isFlipped: Bool { true }

    /// The view follows the island's box, so each new size gets its mask at
    /// once. Without one the whole view would blur.
    override func setFrameSize(_ newSize: NSSize) {
        let resized = newSize != frame.size
        super.setFrameSize(newSize)
        if resized { updateMask() }
    }

    private func updateMask() {
        guard let contour, bounds.width > 0, bounds.height > 0 else {
            maskImage = nil
            return
        }
        maskImage = NSImage(size: bounds.size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(contour)
            context.setFillColor(.black)
            context.fillPath()
            return true
        }
    }
}

/// Controls on the glass shell use quiet translucent fills, leaving the
/// refraction to the island rather than stacking separate glass lenses.
package struct NotchControlSurface: ViewModifier {
    package let cornerRadius: CGFloat
    package var selected = false
    package var interactive = true
    @AppStorage(Preferences.notchLiquidGlassEnabled) private var glass: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.notchGlassSurface) private var glassSurface

    package func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if glassSurface {
                content
                    .background(.white.opacity(selected ? 0.11 : 0.045), in: shape)
                    .overlay {
                        shape.strokeBorder(.white.opacity(selected ? 0.16 : 0.065), lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
            } else {
#if compiler(>=6.2)
                if #available(macOS 26, *), glass, !reduceTransparency {
                    content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
                        .glassEffect(.regular.interactive(interactive), in: shape)
                } else {
                    content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
                }
#else
                content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
#endif
            }
        }
        .overlay {
            shape.strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(cornerRadius: CGFloat, selected: Bool = false, interactive: Bool = true) {
        self.cornerRadius = cornerRadius
        self.selected = selected
        self.interactive = interactive
    }
}

/// One entry of a native menu popped up from a SwiftUI control.
package struct NotchMenuItem {
    package let title: String
    package var checked = false
    package var symbol: String? = nil
    package var enabled = true
    package var action: () -> Void = {}

    /// A line between groups of entries. Never changed, and its action does nothing.
    nonisolated(unsafe) package static let separator = NotchMenuItem(title: "")
    package var isSeparator: Bool { title.isEmpty }
}

/// A control SwiftUI draws in full that pops up a native menu. `Menu`
/// cannot do this: its borderless style turns the label into a pop-up
/// button title, one line cut with an ellipsis, images moved to the front
/// and frames ignored, so anything but a lone glyph loses its shape.
package struct NotchMenuButton<Label: View>: View {
    package let title: String
    package let items: [NotchMenuItem]
    package var cornerRadius: CGFloat = 6
    @ViewBuilder package let label: () -> Label
    @State private var anchor = NotchMenuAnchor()

    package var body: some View {
        Button { anchor.popUp(items) } label: { label() }
            .buttonStyle(NotchButtonStyle(cornerRadius: cornerRadius, lifts: false))
            .background(NotchMenuAnchorView(anchor: anchor))
            .accessibilityLabel(title)
    }
}

/// A chooser whose current choice reads in full: up to two centred lines, or
/// one line cut in the middle, with the list as a native menu below it.
package struct NotchDeviceMenu: View {
    package let title: String
    package let current: String
    package var width: CGFloat = 100
    package var lines = 2
    package var alignment: TextAlignment = .center
    package let items: [NotchMenuItem]

    package var body: some View {
        NotchMenuButton(title: title, items: items) {
            Text("\(current) \(Image(systemName: "chevron.down"))")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(lines)
                .multilineTextAlignment(alignment)
                .truncationMode(lines > 1 ? .tail : .middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: width, alignment: frameAlignment)
                .padding(.horizontal, 4)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .help(current)
        .accessibilityValue(current)
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// Owns the native menu's targets while it is up and remembers the view it
/// pops up from. Menu tracking keeps the island open on its own.
@MainActor package final class NotchMenuAnchor: NSObject {
    fileprivate weak var view: NSView?
    private var actions: [() -> Void] = []

    package func popUp(_ items: [NotchMenuItem]) {
        guard let view else { return }
        actions = items.map(\.action)
        let menu = NSMenu()
        menu.autoenablesItems = false
        // The island is dark whatever the system is, so its menus are too.
        menu.appearance = NSAppearance(named: .darkAqua)
        for (index, item) in items.enumerated() {
            guard !item.isSeparator else { menu.addItem(.separator()); continue }
            let entry = NSMenuItem(title: item.title, action: #selector(choose(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            entry.state = item.checked ? .on : .off
            entry.isEnabled = item.enabled
            if let symbol = item.symbol {
                entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            menu.addItem(entry)
        }
        // A menu whose top lands on the menu bar's edge opens scrolled past its
        // first entry, so a button against the bar opens it a little below.
        var location = NSPoint.zero
        if let window = view.window, let screen = window.screen {
            let bottom = window.convertPoint(toScreen: view.convert(location, to: nil)).y
            let edge = screen.visibleFrame.maxY - 3
            if bottom > edge { location.y -= bottom - edge }
        }
        menu.popUp(positioning: nil, at: location, in: view)
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

private struct NotchMenuAnchorView: NSViewRepresentable {
    let anchor: NotchMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

extension NSAlert {
    /// A SwiftUI alert or confirmation dialog hangs from the island as a
    /// sheet, which moves and reskins the borderless surface. Inside the
    /// island a tool asks the same question on its own, just above it, like
    /// the Scratchpad page does, and the island gets the keyboard back after.
    package static func confirmAboveIsland(_ title: String, message: String, action: String,
                                   destructive: Bool, cancel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action).hasDestructiveAction = destructive
        // Escape cancels in every language, like the dialog's cancel role.
        alert.addButton(withTitle: cancel).keyEquivalent = "\u{1b}"
        return alert.runAboveIsland() == .alertFirstButtonReturn
    }

    private func runAboveIsland() -> NSApplication.ModalResponse {
        let island = NotchService.shared.presentationWindow
        var observers: [NSObjectProtocol] = []
        if let island {
            // The modal session puts the alert at the modal panel level, below
            // the island, and puts it back there when it activates the app or
            // makes the alert key. Raise it once running and after each of those.
            let level = NSWindow.Level(rawValue: island.level.rawValue + 1)
            let alertWindow = window
            let raise: @Sendable (Notification) -> Void = { _ in
                MainActor.assumeIsolated { alertWindow.level = level }
            }
            observers = [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main, using: raise)
            }
            DispatchQueue.main.async { alertWindow.level = level }
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = runModal()
        observers.forEach(NotificationCenter.default.removeObserver)
        // A closed island declines key status, so this only returns to an open one.
        if let island, island.isVisible { island.makeKey() }
        return response
    }
}
