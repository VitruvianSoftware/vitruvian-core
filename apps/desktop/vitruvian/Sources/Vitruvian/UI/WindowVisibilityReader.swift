// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// A retained SwiftUI hierarchy does not disappear when its NSWindow closes.
/// Report visibility asynchronously so clients can suspend live previews
/// without changing SwiftUI state during a layout pass.
package struct WindowVisibilityReader: NSViewRepresentable {
    package let onChange: (Bool) -> Void

    package func makeNSView(context: Context) -> WindowVisibilityView { WindowVisibilityView() }
    package func updateNSView(_ view: WindowVisibilityView, context: Context) {
        view.onChange = onChange
        view.reportVisibility()
    }
    package static func dismantleNSView(_ view: WindowVisibilityView, coordinator: ()) { view.stop() }
}

package final class WindowVisibilityView: NSView {
    package var onChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    private var reported: Bool?

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    package required init?(coder: NSCoder) { nil }
    package override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        pending?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    package override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                self?.reportVisibility()
            }
        }
        reportVisibility()
    }
    package override func viewDidHide() { super.viewDidHide(); reportVisibility() }
    package override func viewDidUnhide() { super.viewDidUnhide(); reportVisibility() }

    package func reportVisibility() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let onChange = self.onChange else { return }
            let visible = !self.isHiddenOrHasHiddenAncestor
                && self.window?.isVisible == true && self.window?.occlusionState.contains(.visible) == true
            guard self.reported != visible else { return }
            self.reported = visible
            onChange(visible)
        }
        pending = work
        DispatchQueue.main.async(execute: work)
    }

    package func stop() {
        pending?.cancel()
        pending = nil
        onChange = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
