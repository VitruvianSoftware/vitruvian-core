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

    /// `liquidGlass`, on a Mac that can draw it (macOS 26 and later). The layouts that only make sense with glass
    /// (the floating composer, the chat in the window's toolbar) follow this, so an older Mac keeps the plain one even
    /// if the value is set.
    var drawsLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return liquidGlass }
        return false
    }
}

/// The surfaces that turn to glass, each with the background it has without it (the look before the option).
///
/// The glass follows Apple's macOS 26 apps (Messages, Mail, Notes): glass is only for the controls that float over
/// content (the toolbar's buttons, the message box and its plus, the selected message's action bar, a floating panel),
/// and the content scrolls under them. A large flat area (a pane, a strip) is never glass, and glass is never drawn on
/// glass.
enum CourierSurface {
    /// The space bar, inside the sidebar: with glass it has no background of its own, so the sidebar's glass runs
    /// under it as it does under the chat list.
    case sidebarStrip
    /// The composer's area under the messages: a bar without glass; with glass nothing of its own (its field and plus
    /// float, `composerField` and `composerButton`).
    case composerBar
    /// With glass, the message box: its text, its buttons and what sits above them (a reply, files, the pickers) in
    /// one shape, a capsule while it is one line high (`singleLineHeight`), rounded corners when it grows. Nothing
    /// without glass (the bar is `composerBar`).
    case composerField(singleLineHeight: CGFloat)
    /// With glass, a round button beside the message box (its plus). Nothing without glass.
    case composerButton
    /// A pane beside the chat: the thread, Chat Info, the calendar. Content, not a control: never glass.
    case sidePane
    /// A panel floating over the window: search (translucent without glass) and the command bar (opaque without
    /// glass).
    case floatingPanel(cornerRadius: CGFloat, opaque: Bool)
    /// The selected message's action bar (quick reactions, Reply, More).
    case actionBar
    /// Who reacted, over a reaction chip.
    case reactionCard
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
        case .sidebarStrip, .composerBar:
            content
        case let .composerField(singleLineHeight):
            content.glassEffect(.regular, in: ComposerFieldShape(singleLineHeight: singleLineHeight))
        case .composerButton:
            content.glassEffect(.regular.interactive(), in: Circle())
        case .sidePane:
            content.background(Color(nsColor: .textBackgroundColor))
        // Glass is not drawn on glass: what a panel holds is plain.
        case let .floatingPanel(cornerRadius, _):
            content.environment(\.liquidGlass, false)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .actionBar:
            GlassEffectContainer {
                content
                    .padding(.horizontal, 4)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
        case .reactionCard:
            GlassEffectContainer {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func plain(_ content: Content) -> some View {
        switch surface {
        case .composerField, .composerButton:
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
        case .actionBar, .reactionCard:
            content
                .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        }
    }
}

/// The message box's glass: a capsule while it is one line high, then a rounded rectangle (18 points, continuous) as
/// it grows, so a long draft or a reply above the text doesn't bulge into a pill.
struct ComposerFieldShape: Shape {
    let singleLineHeight: CGFloat
    static let grownCornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let radius = rect.height <= singleLineHeight + 0.5 ? rect.height / 2 : Self.grownCornerRadius
        return RoundedRectangle(cornerRadius: min(radius, rect.height / 2), style: .continuous).path(in: rect)
    }
}

extension View {
    /// This surface's background: Liquid Glass when `liquidGlass` is on in the environment, else the plain one.
    func courierSurface(_ surface: CourierSurface) -> some View {
        modifier(CourierSurfaceBackground(surface: surface))
    }

    /// What sits on an edge of a transcript (the composer and what is above it at the bottom; a banner at the top).
    /// Without glass, it is stacked against the transcript, the look before the option. With glass, the transcript
    /// runs under it: it sits in the transcript's safe area, so the last message stays in view above the composer and
    /// scrolls under it, behind the scroll edge (`courierScrollEdges`, on the transcript's scroll view).
    func courierEdgeBar<Bar: View>(_ edge: VerticalEdge, @ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(CourierEdgeBar(edge: edge, bar: bar()))
    }

    /// On a transcript's own scroll view: with glass, the scroll edge effect where content runs under the window's
    /// toolbar and under the floating composer, so messages fade out under the bars instead of showing through the
    /// glass. On the scroll view itself: set on a view around it, it didn't reach it. Nothing without glass.
    func courierScrollEdges() -> some View {
        modifier(CourierScrollEdges())
    }

    /// A background that, with glass, reaches under the bars over the transcript (the toolbar, the composer), as the
    /// messages do. Without glass it stays where it is.
    func courierExtendsUnderBars() -> some View {
        modifier(CourierExtendsUnderBars())
    }

    /// With glass, the open chat in the window's toolbar: `identity` (its picture, name and network) where the window's
    /// title was, plain, and `actions` (Chat Info and the rest) as the toolbar's own grouped glass buttons, so there
    /// is one bar and not a header strip under the title. Without glass nothing: the chat's header strip shows them.
    ///
    /// `panes` is the open side panes' headers (the thread, Chat Info), one item after the chat's buttons, at the
    /// toolbar's trailing edge over the panes (`PaneHeader`).
    func courierChatToolbar<Identity: View, Actions: View, Panes: View>(
        @ViewBuilder identity: () -> Identity,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder panes: () -> Panes
    ) -> some View {
        modifier(CourierChatToolbar(identity: identity(), actions: actions(), panes: panes()))
    }

    /// The chat list, in the window's sidebar: with glass its own opaque background goes, so the sidebar's floating
    /// glass shows under it, as in Mail; without, the inset list's background stays.
    func courierSidebarList() -> some View {
        modifier(CourierSidebarList())
    }

    /// With no chat open and the engine connected, hide the window's own title ("Courier", "Connected").
    func courierEmptyChatToolbar(isConnected: Bool = true) -> some View {
        modifier(CourierEmptyChatToolbar(isConnected: isConnected))
    }

    /// The send button: the prominent glass style tinted with the accent colour, with glass; plain without.
    func courierSendButtonStyle() -> some View {
        modifier(CourierSendButtonStyle())
    }
}

private struct CourierEdgeBar<Bar: View>: ViewModifier {
    let edge: VerticalEdge
    let bar: Bar
    @Environment(\.liquidGlass) private var liquidGlass

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), liquidGlass {
            content
                .safeAreaBar(edge: edge, spacing: 0) { bar }
        } else {
            VStack(spacing: 0) {
                if edge == .top { bar }
                content
                if edge == .bottom { bar }
            }
        }
    }
}

private struct CourierScrollEdges: ViewModifier {
    @Environment(\.liquidGlass) private var liquidGlass

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), liquidGlass {
            // Hard, as Mail's and Finder's: the soft style left messages showing through the glass behind the chat's
            // name in the toolbar (checked in the test copy on macOS 27.2).
            content.scrollEdgeEffectStyle(.hard, for: [.top, .bottom])
        } else {
            content
        }
    }
}

private struct CourierExtendsUnderBars: ViewModifier {
    @Environment(\.drawsLiquidGlass) private var drawsLiquidGlass

    func body(content: Content) -> some View {
        if drawsLiquidGlass {
            content.ignoresSafeArea(.container, edges: .vertical)
        } else {
            content
        }
    }
}

private struct CourierChatToolbar<Identity: View, Actions: View, Panes: View>: ViewModifier {
    let identity: Identity
    let actions: Actions
    let panes: Panes
    @Environment(\.liquidGlass) private var liquidGlass

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), liquidGlass {
            content
                .toolbar {
                    ToolbarItem(placement: .navigation) { identity }
                        .sharedBackgroundVisibility(.hidden)
                    // On the toolbar's trailing edge, as Mail's and Messages' buttons are (a Mac's `.primaryAction`
                    // is its leading edge, next to the name).
                    ToolbarSpacer(.flexible)
                    ToolbarItemGroup(placement: .automatic) { actions }
                    // The panes' own titles and buttons draw their glass themselves (`PaneHeader`).
                    ToolbarItem(placement: .automatic) { panes }
                        .sharedBackgroundVisibility(.hidden)
                }
                // The chat's name is the title now: the window's own ("Courier", "Connected") would be a second one.
                .toolbar(removing: .title)
        } else {
            content
        }
    }
}

private struct CourierSidebarList: ViewModifier {
    @Environment(\.drawsLiquidGlass) private var drawsLiquidGlass

    func body(content: Content) -> some View {
        if drawsLiquidGlass {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

private struct CourierEmptyChatToolbar: ViewModifier {
    let isConnected: Bool
    @Environment(\.liquidGlass) private var liquidGlass

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), liquidGlass, isConnected {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

private struct CourierSendButtonStyle: ViewModifier {
    @Environment(\.liquidGlass) private var liquidGlass
    @Environment(\.themeAccentColor) private var themeAccent

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), liquidGlass {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(themeAccent)
        } else {
            content.buttonStyle(.plain)
        }
    }
}

/// With glass, a `GlassEffectContainer` around neighbouring glass shapes (the message box and its plus), so they
/// blend as one group as they near each other; without, just the content.
struct CourierGlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content
    @Environment(\.liquidGlass) private var liquidGlass

    var body: some View {
        if #available(macOS 26.0, *), liquidGlass {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
