// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore

/// Hosts the invisible view the system share sheet is anchored to. SwiftUI
/// creates and owns that view, so the button reaches whichever one is on
/// screen right now through the box below.
package struct ShelfSharePickerAnchor: NSViewRepresentable {
    /// Main-actor isolated, as the view and the presenter it holds are.
    @preconcurrency @MainActor
    package final class Anchor {
        fileprivate weak var view: NSView?
        private let presenter = ShelfSharePresenter()

        // Spelled out because a default initializer never leaves its module.
        package init() {}

        @discardableResult
        package func present(_ urls: [URL], completion: ((Bool) -> Void)? = nil) -> Bool {
            guard let view else { return false }
            return presenter.present(for: urls, from: view, completion: completion)
        }
    }

    package let anchor: Anchor

    package func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    package func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(anchor: Anchor) {
        self.anchor = anchor
    }
}
