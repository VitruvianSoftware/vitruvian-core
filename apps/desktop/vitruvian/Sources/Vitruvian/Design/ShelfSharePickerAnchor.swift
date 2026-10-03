// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore

/// Hosts the invisible view the system share sheet is anchored to. SwiftUI
/// creates and owns that view, so the button reaches whichever one is on
/// screen right now through the box below.
struct ShelfSharePickerAnchor: NSViewRepresentable {
    final class Anchor {
        fileprivate weak var view: NSView?
        private let presenter = ShelfSharePresenter()

        @discardableResult
        func present(_ urls: [URL], completion: ((Bool) -> Void)? = nil) -> Bool {
            guard let view else { return false }
            return presenter.present(for: urls, from: view, completion: completion)
        }
    }

    let anchor: Anchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}
