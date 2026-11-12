// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The headers of the window's columns (the chat list, the chat, the thread, Chat Info), drawn one way so they line
/// up across the window.
///
/// With glass, every column's header is in the window's toolbar, on the line of the traffic lights: the chat's
/// picture and name where the title was, and a pane's title and buttons as a toolbar item as wide as the pane, so the
/// title sits over the pane's own content. (A header drawn by the pane in the toolbar's band can't be clicked: the
/// toolbar takes every click across the band, checked on macOS 27.2.) Without glass, each column has a strip of the
/// same height under the toolbar, so the strips' titles share a line.
enum PaneHeaderMetrics {
    /// A header strip's height without glass, the same in every column.
    static let stripHeight: CGFloat = 48
    /// The space before a header's title and after its last button, the same as the pane's content inset, so the
    /// title lines up with what is under it.
    static let inset: CGFloat = 14
    /// How much narrower than its pane a pane's toolbar item is: the toolbar puts a little space between items, and an
    /// item a point too wide is pushed into the toolbar's overflow menu.
    static let toolbarItemSlack: CGFloat = 6
}

/// The panes beside the chat whose headers go in the toolbar with glass.
enum SidePane: Hashable {
    case thread
    case chatInfo
    case ai
}

/// Each side pane's width, measured where it is laid out, for its toolbar item.
struct SidePaneWidthKey: PreferenceKey {
    static let defaultValue: [SidePane: CGFloat] = [:]
    static func reduce(value: inout [SidePane: CGFloat], nextValue: () -> [SidePane: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this pane's width to `SidePaneWidthKey`.
    func reportsSidePaneWidth(_ pane: SidePane) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: SidePaneWidthKey.self, value: [pane: proxy.size.width])
        })
    }
}

/// A pane's title, as the chat's name is drawn: headline weight, with an optional quieter part after it on the same
/// line (the thread's chat). One line, so every title in the toolbar shares a baseline: a second line under it lifted
/// "Thread" above "Chat Info" and the chat's name.
struct PaneHeaderTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A pane's header: its title on the leading edge and its buttons on the trailing edge.
///
/// In the toolbar (`inToolbar`) the buttons share one glass capsule, as the chat's own toolbar buttons do, and the
/// header is exactly as wide as it is given (the pane's width). Otherwise it is a strip of the shared height with
/// plain buttons.
struct PaneHeader<Buttons: View>: View {
    let title: String
    var subtitle: String?
    var inToolbar: Bool
    @ViewBuilder var buttons: Buttons

    var body: some View {
        HStack(spacing: 8) {
            PaneHeaderTitle(title: title, subtitle: subtitle)
            Spacer(minLength: 0)
            if inToolbar {
                PaneHeaderButtonGroup { buttons }
            } else {
                HStack(spacing: 10) { buttons }
                    .buttonStyle(.borderless)
            }
        }
        // In the toolbar the item starts a few points into the pane (measured on macOS 27.2), so the title takes a
        // little less than the content inset to sit over the content's edge; the toolbar already keeps the last item
        // off the window's edge.
        .padding(.leading, inToolbar ? PaneHeaderMetrics.inset - 3 : PaneHeaderMetrics.inset)
        .padding(.trailing, inToolbar ? 0 : PaneHeaderMetrics.inset)
        .frame(height: inToolbar ? nil : PaneHeaderMetrics.stripHeight)
    }
}

/// A header's buttons in the toolbar: borderless symbols in one glass capsule, the size of the toolbar's own groups.
private struct PaneHeaderButtonGroup<Buttons: View>: View {
    @ViewBuilder var buttons: Buttons

    var body: some View {
        if #available(macOS 26.0, *) {
            HStack(spacing: 0) { buttons }
                .buttonStyle(PaneHeaderToolbarButtonStyle())
                .padding(.horizontal, 2)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            HStack(spacing: 10) { buttons }
                .buttonStyle(.borderless)
        }
    }
}

/// A symbol button in a header's glass capsule: the toolbar's button size, dimmed while pressed.
private struct PaneHeaderToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
