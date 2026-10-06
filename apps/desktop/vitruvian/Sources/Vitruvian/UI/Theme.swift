// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

// Shared look & feel: brand colors, card styling and the brand mark.

package enum PanelMetricColor {
    package static func green(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.18) : .green
    }

    package static func cyan(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.43, blue: 0.54) : .cyan
    }

    package static func mint(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.40) : .mint
    }

    package static func yellow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.56, green: 0.36, blue: 0.00) : .yellow
    }

    package static func red(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.08, blue: 0.10) : .red
    }

    package static func orange(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.30, blue: 0.00) : .orange
    }

    package static func pink(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.06, blue: 0.34) : .pink
    }
}

private struct NotchPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    package var notchPresentation: Bool {
        get { self[NotchPresentationKey.self] }
        set { self[NotchPresentationKey.self] = newValue }
    }
}

package enum PanelSurface {
    /// Whether the menu popover hosts the panel across its whole balloon, so the
    /// panel's own surface can reach the arrow (#1030). Only macOS 26 lays the
    /// content out that way. On macOS 15, `hasFullSizeContent` publishes the
    /// full-size safe area but leaves the view at its content size in the frame's
    /// lower-left corner: the popover grows by that safe area, the panel sits off
    /// center, and a band of system material shows along the top and right edges.
    package static var popoverHostsFullSizeContent: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Hosts the panel across the popover's whole balloon, arrow band
    /// included, where AppKit lays full-size content out; see
    /// `popoverHostsFullSizeContent`.
    @MainActor
    package static func hostFullSizeContent(in popover: NSPopover) {
        popover.hasFullSizeContent = popoverHostsFullSizeContent
    }

    package static func baseFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.68) : Color.black.opacity(0.42)
    }

    package static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.38) : Color.white.opacity(0.075)
    }

    package static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.055) : Color.white.opacity(0.085)
    }

    /// Raised contrast is asked for by someone who cannot see a hairline at a
    /// tenth of an opacity, so the outlines that separate one card from the
    /// next are the ones that answer: this and `raisedBorder`, and no other
    /// surface. A panel is rebuilt every time it opens, which is when a change
    /// to this setting shows. `increasedContrast` is the system's setting
    /// unless a caller passes one.
    package static func border(
        for scheme: ColorScheme,
        increasedContrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    ) -> Color {
        scheme == .light
            ? Color.black.opacity(increasedContrast ? 0.24 : 0.09)
            : Color.white.opacity(increasedContrast ? 0.28 : 0.11)
    }

    /// A control that sits ON a glass surface rather than in it: the system's
    /// own round toggles read as physical because they are lighter than what
    /// is behind them and carry their own shadow.
    package static func raisedFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.88) : Color.white.opacity(0.14)
    }

    package static func raisedBorder(
        for scheme: ColorScheme,
        increasedContrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    ) -> Color {
        scheme == .light
            ? Color.black.opacity(increasedContrast ? 0.22 : 0.07)
            : Color.white.opacity(increasedContrast ? 0.32 : 0.16)
    }

    package static func raisedShadow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.14) : Color.black.opacity(0.38)
    }

    /// The lit edge of a glass surface: bright where the light comes from,
    /// gone by the bottom. Without it a translucent panel reads as paper.
    package static func rimHighlight(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [Color.white.opacity(scheme == .light ? 0.95 : 0.30),
                                Color.white.opacity(scheme == .light ? 0.12 : 0.04)],
                       startPoint: .top,
                       endPoint: .bottom)
    }
}

/// How the panel's glass surface meets what hosts it.
///
/// AppKit hands the hosted panel a safe area for the popover's border and
/// arrow, and draws the arrow on the frame itself, so a surface that stopped at
/// the panel would leave the tip in the plain system material. The panel's
/// content keeps that inset and never sits under the arrow; only the surface
/// may reach into it.
package enum PanelSurfaceFit: Equatable, Sendable {
    /// In the island, which supplies the surface the panel sits on.
    case island
    /// Across a popover's whole balloon, arrow band included; see
    /// `PanelSurface.popoverHostsFullSizeContent`.
    case balloon
    /// A card inside a popover that still insets its content.
    case card

    package init(notchPresentation: Bool,
                 popoverHostsFullSizeContent: Bool = PanelSurface.popoverHostsFullSizeContent) {
        if notchPresentation {
            self = .island
        } else if popoverHostsFullSizeContent {
            self = .balloon
        } else {
            self = .card
        }
    }

    /// Whether the surface paints past the safe area, up into the arrow. Only
    /// a popover that hosts the panel full size has a balloon under it to
    /// reach; anywhere else the bleed would land outside the panel.
    package var paintsPastSafeArea: Bool { self == .balloon }

    /// The corner radius of the surface's own shape, or nil where it has none.
    /// The popover clips a balloon surface to its own balloon, so that surface
    /// is a plain rectangle, Liquid Glass or not: rounding would expose the
    /// system material at the corners. The balloon's rounding never reaches a
    /// card inside it, so the card carries its own.
    package var cornerRadius: CGFloat? { self == .card ? 18 : nil }

    /// The width of the rim the surface draws on its own edge, or nil where it
    /// draws none. AppKit already outlines the balloon, so a stroke there
    /// would duplicate it; a card inside the balloon needs an edge of its own.
    package var rimWidth: CGFloat? { self == .card ? 0.8 : nil }
}

package func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(.secondary)
}

extension View {
    /// The rounded card background used by every panel section. A card
    /// holding a list of rows is not padded: each row brings its own insets,
    /// so hover highlights and separators can reach the card's edges.
    package func panelCard(interactive: Bool = true, padded: Bool = true) -> some View {
        modifier(PanelCardModifier(interactive: interactive, padded: padded))
    }

    /// A restrained glass base for the menu panel: still translucent, but with a
    /// stable tint so text and controls do not depend too much on the wallpaper.
    /// It reaches the popover's arrow; see PanelGlassSurface.
    package func panelGlassSurface() -> some View {
        background(PanelGlassSurface())
    }
}

private struct PanelCardModifier: ViewModifier {
    var interactive: Bool
    var padded = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchPresentation) private var notchPresentation

    func body(content: Content) -> some View {
        if notchPresentation {
            content.padding(padded ? 12 : 0).modifier(NotchControlSurface(cornerRadius: 18, interactive: interactive))
        } else {
        content
            .padding(padded ? 10 : 0)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PanelSurface.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
            )
        }
    }
}

private struct PanelGlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchPresentation) private var notchPresentation
    @Environment(\.notchGlassSurface) private var notchGlassSurface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(Preferences.liquidGlassEnabled) private var liquidGlassEnabled: Bool

    var body: some View {
        // Where it reaches, and what shape it takes, is PanelSurfaceFit's call.
        let fit = PanelSurfaceFit(notchPresentation: notchPresentation)
        if fit.paintsPastSafeArea {
            surface(fit).ignoresSafeArea()
        } else {
            surface(fit)
        }
    }

    @ViewBuilder
    private func surface(_ fit: PanelSurfaceFit) -> some View {
        switch fit {
        case .island:
            Rectangle().fill(notchGlassSurface ? Color.clear : .black)
        case .balloon:
            balloonSurface
        case .card:
            cardSurface(cornerRadius: fit.cornerRadius ?? 0, rimWidth: fit.rimWidth ?? 0)
        }
    }

    /// The surface across the whole balloon: a plain rectangle the popover
    /// clips and outlines, in Liquid Glass where it is on.
    @ViewBuilder
    private var balloonSurface: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), liquidGlassEnabled, !reduceTransparency {
            Rectangle()
                .fill(Color.clear)
                .glassEffect(.regular, in: Rectangle())
                .overlay(
                    Rectangle()
                        .fill(PanelSurface.baseFill(for: colorScheme).opacity(colorScheme == .light ? 0.35 : 0.45))
                )
        } else {
            standardSurface
        }
#else
        standardSurface
#endif
    }

    @ViewBuilder
    private var standardSurface: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(Rectangle().fill(PanelSurface.baseFill(for: colorScheme)))
    }

    /// The panel as a card inside a popover that insets its content (before
    /// macOS 26): the balloon's rounding never reaches it there, so it carries
    /// its own rounding and rim. Liquid Glass needs macOS 26, so this is always
    /// the standard material.
    private func cardSurface(cornerRadius: CGFloat, rimWidth: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(.regularMaterial)
            .overlay(shape.fill(PanelSurface.baseFill(for: colorScheme)))
            .overlay(shape.strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: rimWidth))
    }
}

/// The official mark (Resources/Brand/logo.png, trimmed at build time),
/// tintable for light or dark surfaces.
package struct BrandMark: View {
    package var width: CGFloat
    package var tint: Color = .white

    private static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    package var body: some View {
        if let mark = Self.mark {
            Image(nsImage: mark)
                .renderingMode(.template)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: width)
        } else {
            Image(systemName: "circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: width * 0.5)
        }
    }
}

package struct DiscordMark: View {
    package var width: CGFloat

    private static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "discord-symbol",
                                        withExtension: "svg",
                                        subdirectory: "Images") else { return nil }
        return NSImage(contentsOf: url)
    }()

    package var body: some View {
        if let mark = Self.mark {
            Image(nsImage: mark)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width)
        }
    }
}

/// Squircle badge with the mark on the space gradient — the app's face in the
/// About tab and onboarding.
package struct BrandBadge: View {
    package var size: CGFloat

    package var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.spaceGradient)
            BrandMark(width: size * 0.8)
        }
        .frame(width: size, height: size)
    }
}
