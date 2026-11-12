// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianServices

/// What a window strip reads from the switcher: every window in order, and
/// which one is selected.
@MainActor
package protocol SwitcherStripModel: ObservableObject, Sendable {
    associatedtype Window: Identifiable
    var windows: [Window] { get }
    var selectedIndex: Int { get }
}

extension AppSwitcher: SwitcherStripModel {}

/// One app's windows side by side, scrolling to keep the selected window in
/// view. It reads the selection from the switcher itself, so a reveal queued
/// behind a resize finds the current selection, not the one it was queued for.
package struct SwitcherWindowStrip<Model: SwitcherStripModel, Tile: View>: View {
    @ObservedObject private var switcher: Model
    /// The app's windows, with their positions among all the switcher's.
    private let windows: [(offset: Int, element: Model.Window)]
    private let spacing: CGFloat
    private let padding: CGFloat
    private let rowHeight: CGFloat?
    private let scrollDisabled: Bool
    private let size: CGSize?
    private let instantSelection: Bool
    private let tile: (Int, Model.Window) -> Tile

    package init(switcher: Model, windows: [(offset: Int, element: Model.Window)], spacing: CGFloat,
                 padding: CGFloat = 0, rowHeight: CGFloat? = nil, scrollDisabled: Bool = false,
                 size: CGSize? = nil, instantSelection: Bool,
                 @ViewBuilder tile: @escaping (Int, Model.Window) -> Tile) {
        self.switcher = switcher
        self.windows = windows
        self.spacing = spacing
        self.padding = padding
        self.rowHeight = rowHeight
        self.scrollDisabled = scrollDisabled
        self.size = size
        self.instantSelection = instantSelection
        self.tile = tile
    }

    package var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(windows, id: \.element.id) { index, window in
                        tile(index, window)
                            .id(window.id)
                    }
                }
                .padding(.horizontal, padding)
                .frame(height: rowHeight, alignment: .center)
            }
            .scrollDisabled(scrollDisabled)
            .frame(width: size?.width, height: size?.height)
            .onAppear { revealSelection(in: proxy, animated: false) }
            .onChange(of: switcher.selectedIndex) { _, _ in
                revealSelection(in: proxy, animated: true)
            }
            .onChange(of: windows.map(\.element.id)) { _, _ in
                revealSelection(in: proxy, animated: true)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
                DispatchQueue.main.async {
                    revealSelection(in: proxy, animated: false)
                }
            }
        }
    }

    /// A search can resize the strip without moving the selection, and closing
    /// a window can replace the selected item at the same index. Reveal after
    /// the viewport's actual geometry changes, allowing its native scroll view
    /// to finish resizing before the queued reveal reads the current selection.
    /// Resize corrections are unanimated. SwiftUI before macOS 26 can also drop
    /// animated reveals during rapid navigation, so use immediate scrolling there.
    private func revealSelection(in proxy: ScrollViewProxy, animated: Bool) {
        let index = switcher.selectedIndex
        guard switcher.windows.indices.contains(index) else { return }
        let id = switcher.windows[index].id
        guard animated, !instantSelection, #available(macOS 26, *) else {
            proxy.scrollTo(id, anchor: .center)
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}
