// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// Only Command-clicks belong to this overlay. All ordinary input passes to
/// the existing sliders, fields and menus underneath it.
package struct MixerAppDragSource: NSViewRepresentable {
    package static let pasteboardType = NSPasteboard.PasteboardType("com.vitruviansoftware.vitruvian.mixer-app")
    package let id: String?
    package let icon: NSImage
    package let onBegin: (String) -> Void
    package let onEnd: () -> Void
    package let canMove: (String, String) -> Bool
    package let onTarget: (MixerAppDropTarget?) -> Void
    package let move: (String, String, Bool) -> Void
    /// Columns running sideways read the insertion side from the pointer's x.
    package var sideways = false

    package func makeNSView(context: Context) -> DragView { DragView() }

    package func updateNSView(_ view: DragView, context: Context) {
        view.source = self
    }

    package final class DragView: NSView, NSDraggingSource {
        package var source: MixerAppDragSource?
        private var start: NSPoint?

        package override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([MixerAppDragSource.pasteboardType])
        }

        package required init?(coder: NSCoder) { nil }
        package override var isFlipped: Bool { true }

        package override func hitTest(_ point: NSPoint) -> NSView? {
            guard source?.id != nil, NSEvent.modifierFlags.contains(.command) else { return nil }
            return super.hitTest(point)
        }

        package override var mouseDownCanMoveWindow: Bool { false }
        package override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        package override func mouseDown(with event: NSEvent) { start = event.locationInWindow }
        package override func mouseUp(with event: NSEvent) { start = nil }

        package override func mouseDragged(with event: NSEvent) {
            guard let start, let source, let id = source.id,
                  hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4 else { return }
            self.start = nil
            let item = NSPasteboardItem()
            item.setString(id, forType: MixerAppDragSource.pasteboardType)
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            let point = convert(start, from: nil)
            draggingItem.setDraggingFrame(NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32), contents: source.icon)
            source.onBegin(id)
            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }

        // The native overlay receiving the mouse must also receive the drop.
        // A SwiftUI drop target underneath it never gets the destination callbacks.
        private func destination(_ sender: NSDraggingInfo) -> (sourceID: String, target: MixerAppDropTarget)? {
            guard let source, let targetID = source.id,
                  let origin = sender.draggingSource as? DragView,
                  let sourceID = origin.source?.id, sourceID != targetID,
                  sender.draggingSourceOperationMask.contains(.move),
                  sender.draggingPasteboard.string(forType: MixerAppDragSource.pasteboardType) == sourceID,
                  source.canMove(sourceID, targetID) else { return nil }
            let point = convert(sender.draggingLocation, from: nil)
            guard bounds.contains(point) else { return nil }
            let after = source.sideways ? point.x > bounds.midX : point.y > bounds.midY
            return (sourceID, MixerAppDropTarget(id: targetID, after: after))
        }

        package override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let destination = destination(sender)
            source?.onTarget(destination?.target)
            return destination == nil ? [] : .move
        }

        package override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            if let event = NSApp.currentEvent { autoscroll(with: event) }
            return draggingEntered(sender)
        }

        package override func draggingExited(_ sender: NSDraggingInfo?) { source?.onTarget(nil) }

        package override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            destination(sender) != nil
        }

        package override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let destination = destination(sender) else { return false }
            source?.move(destination.sourceID, destination.target.id, destination.target.after)
            source?.onTarget(nil)
            return true
        }

        package func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }

        package func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

        package func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            source?.onEnd()
        }
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String?, icon: NSImage, onBegin: @escaping (String) -> Void, onEnd: @escaping () -> Void,
                 canMove: @escaping (String, String) -> Bool, onTarget: @escaping (MixerAppDropTarget?) -> Void,
                 move: @escaping (String, String, Bool) -> Void, sideways: Bool = false) {
        self.id = id
        self.icon = icon
        self.onBegin = onBegin
        self.onEnd = onEnd
        self.canMove = canMove
        self.onTarget = onTarget
        self.move = move
        self.sideways = sideways
    }
}

package struct MixerAppDropTarget: Equatable {
    package let id: String
    package let after: Bool

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, after: Bool) {
        self.id = id
        self.after = after
    }
}

package struct MixerAppReorderModifier: ViewModifier {
    package let id: String?
    package let icon: NSImage
    @Binding package var draggingID: String?
    @Binding package var target: MixerAppDropTarget?
    package let dragChanged: (Bool) -> Void
    package let canMove: (String, String) -> Bool
    package let move: (String, String, Bool) -> Void
    package var sideways = false

    private var markerEdge: Alignment {
        sideways ? (target?.after == true ? .trailing : .leading) : (target?.after == true ? .bottom : .top)
    }

    package func body(content: Content) -> some View {
        content
            .overlay {
                MixerAppDragSource(id: id, icon: icon,
                                   onBegin: { draggingID = $0; dragChanged(true) },
                                   onEnd: { draggingID = nil; target = nil; dragChanged(false) },
                                   canMove: canMove,
                                   onTarget: { next in
                                       if next != nil || target?.id == id { target = next }
                                   },
                                   move: move,
                                   sideways: sideways)
            }
            .overlay(alignment: markerEdge) {
                if target?.id == id, draggingID != nil {
                    Capsule().fill(Color.accentColor)
                        .frame(width: sideways ? 2 : nil, height: sideways ? nil : 2)
                        .allowsHitTesting(false)
                }
            }
            .opacity(draggingID == id && draggingID != nil ? 0.45 : 1)
    }
}
