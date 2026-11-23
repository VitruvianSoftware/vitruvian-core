// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest

@testable import VitruvianCourier
import VitruvianCourierCore

@MainActor
final class PanelMotionViewTests: XCTestCase {
    private func hostInWindow<V: View>(_ view: V, size: NSSize) -> (NSWindow, NSHostingView<V>) {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return (window, host)
    }

    private func pumpRunLoop(until condition: () -> Bool, maxIterations: Int = 50) {
        for _ in 0 ..< maxIterations {
            if condition() { return }
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }

    func testTypingLineReservesConstantHeightWhenHiddenOrShown() {
        let hiddenHost = NSHostingView(rootView: TypingLine(text: nil).frame(width: 400))
        hiddenHost.layoutSubtreeIfNeeded()
        let hiddenHeight = hiddenHost.fittingSize.height

        let shownHost = NSHostingView(rootView: TypingLine(text: "Ana is typing…").frame(width: 400))
        shownHost.layoutSubtreeIfNeeded()
        let shownHeight = shownHost.fittingSize.height

        XCTAssertGreaterThanOrEqual(hiddenHeight, TypingLineMotion.reservedHeight - 0.5)
        XCTAssertEqual(hiddenHeight, shownHeight, accuracy: 0.5)
    }

    func testScrollEdgeFadeTracksScrollViewPositionsAndPreservesHitTesting() throws {
        var latestState = ScrollEdgeFadeState.none
        let tallView = ScrollView {
            VStack(spacing: 4) {
                ForEach(0 ..< 30, id: \.self) { idx in
                    Text("Row \(idx)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.05))
                }
            }
            .padding(6)
        }
        .frame(width: 220, height: 160)
        .courierScrollEdgeFade(refreshToken: 30) { state in
            latestState = state
        }

        let (window, host) = hostInWindow(tallView, size: NSSize(width: 220, height: 160))
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        pumpRunLoop { host.first(NSScrollView.self) != nil && latestState == ScrollEdgeFadeState(top: false, bottom: true) }
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self))
        let docView = try XCTUnwrap(scrollView.documentView)
        XCTAssertEqual(latestState, ScrollEdgeFadeState(top: false, bottom: true))

        // Hit testing in top 10 pt and bottom 10 pt must still reach the scroll view hierarchy.
        let topProbe = scrollView.convert(NSPoint(x: 40, y: 5), to: host)
        let bottomProbe = scrollView.convert(NSPoint(x: 40, y: scrollView.bounds.height - 5), to: host)
        let topHit = try XCTUnwrap(host.hitTest(topProbe))
        let bottomHit = try XCTUnwrap(host.hitTest(bottomProbe))
        XCTAssertTrue(topHit === scrollView || topHit.isDescendant(of: scrollView))
        XCTAssertTrue(bottomHit === scrollView || bottomHit.isDescendant(of: scrollView))

        // Scroll to middle -> both top and bottom edges fade.
        let midY: CGFloat = docView.isFlipped ? 120 : max(0, docView.bounds.height - scrollView.contentView.bounds.height - 120)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: midY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pumpRunLoop { latestState == ScrollEdgeFadeState(top: true, bottom: true) }
        XCTAssertEqual(latestState, ScrollEdgeFadeState(top: true, bottom: true))

        // Scroll to bottom -> top fades, bottom does not.
        let bottomY: CGFloat = docView.isFlipped ? max(0, docView.bounds.height - scrollView.contentView.bounds.height) : 0
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pumpRunLoop { latestState == ScrollEdgeFadeState(top: true, bottom: false) }
        XCTAssertEqual(latestState, ScrollEdgeFadeState(top: true, bottom: false))

        // Short content never fades either edge.
        var shortState = ScrollEdgeFadeState(top: true, bottom: true)
        let shortView = ScrollView {
            VStack(spacing: 4) {
                Text("Short row 1").frame(height: 24)
                Text("Short row 2").frame(height: 24)
            }
        }
        .frame(width: 220, height: 160)
        .courierScrollEdgeFade(refreshToken: 2) { state in
            shortState = state
        }
        let (shortWin, shortHost) = hostInWindow(shortView, size: NSSize(width: 220, height: 160))
        defer {
            shortWin.orderOut(nil)
            shortWin.contentView = nil
        }
        pumpRunLoop { shortHost.first(NSScrollView.self) != nil && shortState == .none }
        XCTAssertEqual(shortState, .none)
    }

    func testScrollEdgeFadeTracksSwiftUIList() throws {
        var latestState = ScrollEdgeFadeState.none
        let listView = List(0 ..< 40, id: \.self) { idx in
            Text("Chat \(idx)")
                .frame(height: 26)
        }
        .listStyle(.inset)
        .frame(width: 240, height: 160)
        .courierScrollEdgeFade(refreshToken: 40) { state in
            latestState = state
        }

        let (window, host) = hostInWindow(listView, size: NSSize(width: 240, height: 160))
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        pumpRunLoop { host.first(NSScrollView.self) != nil && latestState == ScrollEdgeFadeState(top: false, bottom: true) }
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self))
        let docView = try XCTUnwrap(scrollView.documentView)
        XCTAssertEqual(latestState, ScrollEdgeFadeState(top: false, bottom: true))

        let originY = scrollView.contentView.bounds.origin.y
        let targetY = docView.isFlipped ? originY + 120 : max(0, originY - 120)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pumpRunLoop { latestState.top }
        XCTAssertTrue(latestState.top)
    }

    func testSkeletonRowsRenderInLightAndDarkAndRespectReduceMotion() throws {
        let regularSizes = try Snapshot.render("skeleton-rows-regular", width: 280, height: 420) {
            SkeletonRows(compact: false)
        }
        XCTAssertEqual(regularSizes.count, 2)

        let compactSizes = try Snapshot.render("skeleton-rows-compact", width: 280, height: 420) {
            SkeletonRows(compact: true)
        }
        XCTAssertEqual(compactSizes.count, 2)

        XCTAssertFalse(SkeletonShimmerMotion.shouldAnimate(isVisible: true, reduceMotion: true))
        XCTAssertFalse(SkeletonShimmerMotion.shouldAnimate(isVisible: false, reduceMotion: false))
    }

    func testSidePaneEntrancePreservesSplitViewChildWidth() {
        var widths: [SidePane: CGFloat] = [:]
        let view = Color.clear
            .courierSidePaneEntrance()
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 560)
            .reportsSidePaneWidth(.thread)
            .frame(width: 340, height: 400)
            .onPreferenceChange(SidePaneWidthKey.self) { widths = $0 }

        let (window, _) = hostInWindow(view, size: NSSize(width: 340, height: 400))
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        pumpRunLoop { widths[.thread] != nil }
        XCTAssertEqual(widths[.thread] ?? 0, 340, accuracy: 0.5)
    }
}
