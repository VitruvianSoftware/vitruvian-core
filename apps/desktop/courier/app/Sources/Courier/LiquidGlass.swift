// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

/// Settings ▸ Appearance ▸ Use Liquid Glass, as the views read it: true when the window should draw its surfaces in
/// Apple's Liquid Glass (`AppearancePreferences.liquidGlassIsActive`). The main window sets it; anything outside it
/// keeps the plain look.
private struct LiquidGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var liquidGlass: Bool {
        get { self[LiquidGlassKey.self] }
        set { self[LiquidGlassKey.self] = newValue }
    }
}

/// The surfaces that turn to glass, each with the background it has without it (the look before the option).
enum CourierSurface {
    /// The space bar, inside the sidebar: with glass it has no background of its own, so the sidebar's glass runs
    /// under it as it does under the chat list.
    case sidebarStrip
    /// The open chat's header, the window's toolbar row for the chat: plain (no background) without glass.
    case headerBar
    /// The composer's bar under the messages.
    case composerBar
    /// A pane beside the chat: the thread, Chat Info, the calendar.
    case sidePane
    /// A panel floating over the window: search (translucent without glass) and the command bar (opaque without
    /// glass).
    case floatingPanel(cornerRadius: CGFloat, opaque: Bool)
}

private struct CourierSurfaceBackground: ViewModifier {
    let surface: CourierSurface
    @Environment(\.liquidGlass) private var liquidGlass

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), liquidGlass {
            glass(content)
        } else {
            plain(content)
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        switch surface {
        case .sidebarStrip:
            content
        case .headerBar, .composerBar:
            content.glassEffect(.regular, in: Rectangle())
        // Glass is not drawn on glass: what a pane or a panel holds (the thread pane's own composer) is plain.
        case .sidePane:
            content.environment(\.liquidGlass, false).glassEffect(.regular, in: Rectangle())
        case let .floatingPanel(cornerRadius, _):
            content.environment(\.liquidGlass, false)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func plain(_ content: Content) -> some View {
        switch surface {
        case .headerBar:
            content
        case .sidebarStrip, .composerBar:
            content.background(.bar)
        case .sidePane:
            content.background(Color(nsColor: .textBackgroundColor).opacity(0.4))
        case let .floatingPanel(cornerRadius, false):
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        case let .floatingPanel(cornerRadius, true):
            content.background(
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Rectangle().fill(.ultraThinMaterial)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

extension View {
    /// This surface's background: Liquid Glass when `liquidGlass` is on in the environment, else the plain one.
    func courierSurface(_ surface: CourierSurface) -> some View {
        modifier(CourierSurfaceBackground(surface: surface))
    }
}
