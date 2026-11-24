// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

/// How wide the chat's header (its picture, name and network) may be in the window's toolbar with glass.
///
/// A toolbar item is as wide as its content wants, and an item the toolbar has no room for goes into its ">>"
/// overflow menu. A long chat name made the header wider than the chat column, so the toolbar moved the header, and
/// the Chat Info button with it, into that menu and the chat showed no header at all. Capped at the room the column
/// leaves after its buttons, the name truncates with "…" instead, as Beeper's does.
enum ChatHeaderWidth {
    /// Room for each of the chat's toolbar buttons (Chat Info, and Disappearing Messages where the network has it):
    /// a glass button and the space the toolbar puts around it.
    static let perButton: CGFloat = 44
    /// The toolbar's spacing between the header and the buttons, and after the last button.
    static let spacing: CGFloat = 24
    /// The toolbar's own ">>" button, which it shows at its trailing edge when anything else has gone into its
    /// overflow menu (a narrow chat list's Filter menu, say): the header must leave room for it too, or the chat's
    /// items follow into the menu.
    static let overflowButton: CGFloat = 44
    /// All the room the header leaves after it besides its buttons.
    static var slack: CGFloat { spacing + overflowButton }
    /// Never narrower than this: the picture and a few letters of the name.
    static let minimum: CGFloat = 96
    /// Where the header starts in the window before it has been measured on the toolbar: after the traffic lights and
    /// the sidebar button when the chat list is hidden, a little after the column's edge otherwise.
    static let leadingChromeWithoutSidebar: CGFloat = 150
    static let leadingInset: CGFloat = 16

    /// The header's widest: from where it starts (`headerMinX`, in the window; nil before it is measured) to the chat
    /// column's trailing edge (`columnMaxX`), less the buttons after it; the minimum for a column not laid out yet.
    static func maximum(columnMinX: CGFloat, columnMaxX: CGFloat, headerMinX: CGFloat?, buttons: Int) -> CGFloat {
        guard columnMaxX > columnMinX else { return minimum }
        let start = headerMinX ?? (columnMinX < leadingChromeWithoutSidebar
            ? leadingChromeWithoutSidebar : columnMinX + leadingInset)
        let room = columnMaxX - start - CGFloat(buttons) * perButton - slack
        return max(minimum, room.rounded(.down))
    }
}

/// Where the chat column and the chat's header are in the window (`WindowFrameReader`). An object the chat view holds
/// without observing it, so a move redraws only the header (`ToolbarChatHeader`), never the timeline.
@MainActor
final class ChatHeaderLayout: ObservableObject {
    @Published var columnFrame: CGRect?
    @Published var headerFrame: CGRect?
    /// The width the header was last replaced at (`ToolbarChatHeader`), so it is replaced once for each width.
    var replacedAt: CGFloat?

    func maximumWidth(buttons: Int) -> CGFloat {
        guard let column = columnFrame else { return ChatHeaderWidth.minimum }
        return ChatHeaderWidth.maximum(columnMinX: column.minX, columnMaxX: column.maxX,
                                       headerMinX: headerFrame?.minX, buttons: buttons)
    }

    /// True when the header should be put back in the toolbar as a new item: the window shrank faster than the
    /// header's limit followed it, so the toolbar moved the header (and the buttons after it) into its overflow menu,
    /// where it stays even once it is narrow enough. Once for each width, so a window too narrow for any header does
    /// not keep replacing it.
    func needsReplacing(buttons: Int) -> Bool {
        guard columnFrame != nil else { return false }
        guard headerFrame == nil else {
            replacedAt = nil
            return false
        }
        let width = maximumWidth(buttons: buttons)
        guard replacedAt != width else { return false }
        replacedAt = width
        return true
    }
}

/// The chat's header as the toolbar item holds it: no wider than the room the chat column leaves it, so a long name
/// truncates, and put back as a new item if the toolbar moves it into its overflow menu anyway.
struct ToolbarChatHeader<Content: View>: View {
    @ObservedObject var layout: ChatHeaderLayout
    let buttons: Int
    let onOverflow: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: layout.maximumWidth(buttons: buttons), alignment: .leading)
            .background(WindowFrameReader { frame in
                layout.headerFrame = frame
                if layout.needsReplacing(buttons: buttons) { onOverflow() }
            })
            .onChange(of: layout.columnFrame) {
                if layout.needsReplacing(buttons: buttons) { onOverflow() }
            }
    }
}

/// Reports the frame of the view it is the background of, in its window's coordinates and cut to the window (nil out
/// of a window): for a view in a toolbar item, which SwiftUI's own coordinate spaces only place inside the item.
struct WindowFrameReader: NSViewRepresentable {
    let onChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        ReaderView(onChange: onChange)
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onChange = onChange
        // Something around it changed (the window, the sidebar, the panes): it may have moved without a layout of
        // its own.
        DispatchQueue.main.async { nsView.measure() }
    }

    final class ReaderView: NSView {
        var onChange: (CGRect?) -> Void
        private var resizeObserver: NSObjectProtocol?
        private var lastReported: CGRect?? = .none

        init(onChange: @escaping (CGRect?) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        deinit {
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        }

        override func hitTest(_: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
            resizeObserver = nil
            if let window {
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.measure() }
                }
            }
            measure()
        }

        override func layout() {
            super.layout()
            measure()
        }

        func measure() {
            // Only the part inside the window: a column laid out wider than the window (as a shrinking window can
            // leave it for a moment) has no more room in the toolbar than the window shows.
            let frame: CGRect? = window.map { window in
                convert(bounds, to: nil).intersection(CGRect(origin: .zero, size: window.frame.size)).integral
            }
            if case let .some(last) = lastReported, last == frame { return }
            lastReported = .some(frame)
            DispatchQueue.main.async { [weak self] in self?.onChange(frame) }
        }
    }
}
