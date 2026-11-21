// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore

/// Lays over the chat's picture and name in the header and takes the mouse for it, as Finder's window title does: a
/// click shows or hides Chat Info, a drag moves the window, a double click does the system's title bar action. (A
/// plain SwiftUI button there took the drags and the double clicks from the window.) What each event means is
/// `ChatHeaderPointer`'s; this view only feeds it and does what it answers.
class ChatHeaderPointerNSView: NSView {
    var onToggle: () -> Void = {}
    /// Moves the window with the mouse event that started the drag.
    var beginWindowDrag: (NSEvent) -> Void = { event in event.window?.performDrag(with: event) }
    /// The person's double-click-a-title-bar setting, read when a double click happens.
    var doubleClickAction: () -> TitleBarDoubleClickAction = { .current() }
    /// Does the title bar's action to the window.
    var perform: (TitleBarDoubleClickAction, NSWindow?) -> Void = { action, window in
        switch action {
        case .zoom: window?.zoom(nil)
        case .minimize: window?.miniaturize(nil)
        case .none: break
        }
    }

    private var pointer = ChatHeaderPointer()

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { false }

    override func mouseDown(with event: NSEvent) {
        pointer.mouseDown(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        if pointer.mouseDragged(to: event.locationInWindow) == .beginWindowDrag {
            beginWindowDrag(event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch pointer.mouseUp(clickCount: event.clickCount) {
        case .toggleInfo:
            onToggle()
        case .doubleClick:
            // The first click of the pair already toggled Chat Info: a double click on a title is the title's.
            onToggle()
            perform(doubleClickAction(), window)
        case .beginWindowDrag, nil:
            break
        }
    }

    /// The pointing hand over the whole view, by a cursor rect: the system sets and restores the cursor as the
    /// pointer enters and leaves, so it cannot stick (a pushed cursor can, if the view goes while it is pushed).
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }
}

struct ChatHeaderPointerArea: NSViewRepresentable {
    let onToggle: () -> Void

    func makeNSView(context: Context) -> ChatHeaderPointerNSView {
        let view = ChatHeaderPointerNSView()
        view.onToggle = onToggle
        return view
    }

    func updateNSView(_ view: ChatHeaderPointerNSView, context: Context) {
        view.onToggle = onToggle
    }
}
