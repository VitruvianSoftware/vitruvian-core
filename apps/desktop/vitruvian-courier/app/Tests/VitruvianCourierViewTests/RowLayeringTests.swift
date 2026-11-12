// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest

/// A selected message row draws above its neighbours (its action bar and reaction card reach past its top). Its zIndex
/// is set inside MessageRowView, two views below the timeline's LazyVStack (TimelineItemView, then the row) and under
/// the `.id` and `.popover` the chat puts on each item. These check that SwiftUI honours a zIndex set that deep: the
/// first row draws a block reaching down into the second, which covers it unless the first is raised.
@MainActor
final class RowLayeringTests: XCTestCase {
    /// As TimelineItemView: a switch over the item, the row one of its cases.
    private struct Item: View {
        let index: Int
        let raised: Bool

        var body: some View {
            switch index {
            case 0: Row(raised: raised)
            default: Color.green.frame(height: 20)
            }
        }
    }

    /// As MessageRowView: the zIndex is its body's last modifier.
    private struct Row: View {
        let raised: Bool

        var body: some View {
            Color.red.frame(height: 20)
                .overlay(alignment: .top) { Color.blue.frame(height: 20).offset(y: 20) }
                .accessibilityElement(children: .contain)
                .zIndex(raised ? 1 : 0)
        }
    }

    /// The colour in the middle of the second row, in a scrolling LazyVStack as the chat's (with each item's popover)
    /// or the thread pane's (without).
    private func colourOverSecondRow(raised: Bool, popover: Bool) throws -> NSColor {
        _ = NSApplication.shared
        let size = NSSize(width: 100, height: 80)
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0 ..< 3, id: \.self) { index in
                    if popover {
                        Item(index: index, raised: raised)
                            .id(index)
                            .popover(isPresented: .constant(false)) { Text(verbatim: "") }
                    } else {
                        Item(index: index, raised: raised).id(index)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        for _ in 0 ..< 25 {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
            host.layoutSubtreeIfNeeded()
        }
        window.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        let colour = try XCTUnwrap(bitmap.colorAt(x: Int(50 * scale), y: Int(30 * scale))?.usingColorSpace(.sRGB))
        window.contentView = nil
        return colour
    }

    private func isBlue(_ colour: NSColor) -> Bool { colour.blueComponent > 0.7 && colour.greenComponent < 0.7 }
    private func isGreen(_ colour: NSColor) -> Bool { colour.greenComponent > 0.6 && colour.blueComponent < 0.6 }

    func testWithoutAZIndexTheNextRowCoversTheFirst() throws {
        // The control: shows the check can tell the two apart.
        XCTAssertTrue(isGreen(try colourOverSecondRow(raised: false, popover: true)))
        XCTAssertTrue(isGreen(try colourOverSecondRow(raised: false, popover: false)))
    }

    func testARaisedRowDrawsOverTheNextInTheChat() throws {
        XCTAssertTrue(isBlue(try colourOverSecondRow(raised: true, popover: true)))
    }

    func testARaisedRowDrawsOverTheNextInTheThreadPane() throws {
        XCTAssertTrue(isBlue(try colourOverSecondRow(raised: true, popover: false)))
    }
}
