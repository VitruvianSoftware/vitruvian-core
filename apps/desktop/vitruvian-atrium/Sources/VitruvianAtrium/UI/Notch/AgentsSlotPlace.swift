// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI

/// The Chat tab's place, kept empty for a tool in the Agents slot. It says
/// where it is on the screen, in AppKit's screen points, each time it is
/// laid out or its window moves, and nil when it leaves its window.
struct AgentsSlotPlace: NSViewRepresentable {
    let measured: @MainActor (CGRect?) -> Void

    func makeNSView(context: Context) -> PlaceView {
        let view = PlaceView()
        view.measured = measured
        return view
    }

    func updateNSView(_ view: PlaceView, context: Context) {
        view.measured = measured
        view.report()
    }

    static func dismantleNSView(_ view: PlaceView, coordinator: ()) {
        view.measured?(nil)
    }

    final class PlaceView: NSView {
        var measured: (@MainActor (CGRect?) -> Void)?
        // Read in `deinit`, which is not on the main actor; only the main
        // actor writes it.
        nonisolated(unsafe) private var moves: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let moves { NotificationCenter.default.removeObserver(moves) }
            moves = nil
            if let window {
                moves = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window,
                                                               queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                }
            }
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        func report() {
            guard let window else { return measured?(nil) ?? () }
            measured?(window.convertToScreen(convert(bounds, to: nil)))
        }

        deinit {
            if let moves { NotificationCenter.default.removeObserver(moves) }
        }
    }
}
