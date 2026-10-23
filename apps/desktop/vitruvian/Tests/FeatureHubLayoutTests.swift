// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianUI

/// The hub's scroll layout, on the page's own scroll page and stable groups,
/// with inert cards in place of the real ones: installing a feature must not
/// start services just to check where its row is drawn.
@MainActor
enum FeatureHubLayoutTests {
    final class Runtime: ObservableObject {
        @Published var needsRestartToUnload = false
        @Published var offersNeverUsed = false
    }

    /// The Features page in the order the hub builds it, its cards standing in.
    struct Page: View {
        @ObservedObject var runtime: Runtime
        var body: some View {
            FeatureHubScrollPage {
                FeatureHubStableGroup {
                    Text("Features").font(.title2.bold())
                    if runtime.needsRestartToUnload { Text("Restart").frame(height: 70) }
                }
                FeatureHubStableGroup {
                    Text("Installed features").frame(height: 90)
                    if runtime.offersNeverUsed { Text("Never used").frame(height: 120) }
                }
                Text("Dynamic Island").frame(height: 900)
                Text("Presets").frame(height: 180)
                ForEach(FeatureGroup.allCases.filter { $0 != .dynamicIsland }, id: \.self) { group in
                    SettingsCard {
                        Text(group.rawValue)
                        ForEach(AppFeature.features(in: group), id: \.self) { feature in
                            if feature == .fanControl {
                                FanRow().frame(height: 44)
                            } else {
                                Text(feature.rawValue).frame(height: 44)
                            }
                        }
                    }
                    .id(group)
                }
            }
        }
    }

    final class FanRowView: NSView {}
    struct FanRow: NSViewRepresentable {
        func makeNSView(context: Context) -> FanRowView { FanRowView() }
        func updateNSView(_ view: FanRowView, context: Context) {}
    }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        let runtime = Runtime()
        runtime.offersNeverUsed = true
        let host = NSHostingView(rootView: Page(runtime: runtime))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 848),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func settle() {
            let deadline = Date().addingTimeInterval(0.3)
            while Date() < deadline {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.01)))
            }
        }
        settle()
        guard let scroll = descendant(NSScrollView.self, in: host) else {
            suite.expect(false, "the Features page draws a scroll view")
            return
        }
        // Visit the intervening cards, as when scrolling down to Fan Control.
        for _ in 0..<24 {
            let bottom = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(bottom, scroll.contentView.bounds.minY + 500)))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle()
        }
        func rowFrame() -> NSRect? {
            guard let row = descendant(FanRowView.self, in: host) else { return nil }
            return row.convert(row.bounds, to: host)
        }
        guard let initial = rowFrame(), host.bounds.contains(initial) else {
            suite.expect(false, "Fan Control is visible before changing availability")
            return
        }
        // Uninstall adds the restart notice above the viewport; reinstall
        // removes it. Repeat without scrolling, as in the reported failure.
        for restart in [true, false, true, false] {
            withAnimation(.easeOut(duration: 0.22)) {
                runtime.needsRestartToUnload = restart
            }
            settle()
            let current = rowFrame()
            suite.expect(current.map { host.bounds.contains($0) } == true,
                         "Fan Control stays visible when the offscreen restart notice is \(restart ? "added" : "removed")")
            suite.expect(current.map { abs($0.midY - initial.midY) < 2 } == true,
                         "changing the restart notice preserves the visible row's position: \(String(describing: current)) vs \(initial)")
        }
        // Uninstalling the last of three never-used features takes that offer
        // away above the viewport too, along with the restart notice or while
        // an earlier uninstall already shows it.
        for (offers, restart) in [(false, true), (true, false), (false, true), (true, true), (false, true)] {
            withAnimation(.easeOut(duration: 0.22)) {
                runtime.offersNeverUsed = offers
                runtime.needsRestartToUnload = restart
            }
            settle()
            let current = rowFrame()
            suite.expect(current.map { host.bounds.contains($0) } == true,
                         "Fan Control stays visible when the offscreen never-used offer is \(offers ? "added" : "removed")")
            suite.expect(current.map { abs($0.midY - initial.midY) < 2 } == true,
                         "changing the never-used offer preserves the visible row's position: \(String(describing: current)) vs \(initial)")
        }
    }

    private static func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }
}
