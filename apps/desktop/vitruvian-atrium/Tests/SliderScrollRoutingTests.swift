// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianAtriumServices

/// The production wheel routing over real AppKit views: a level control that
/// takes the wheel keeps it from the sideways strip around it.
enum SliderScrollRoutingTests {
    /// A level control as the router sees it: it takes the wheel while enabled
    /// and scrollable, as `NotchLevelControl` and `SliderScrollArea` do.
    final class Slider: NSView, SliderScrollTarget {
        var isEnabled = true
        var scrollable = true
        var acceptsSliderScroll: Bool { scrollable && isEnabled }
    }

    static func run(_ suite: TestSuite) {
        let slider = Slider(frame: NSRect(x: 0, y: 0, width: 28, height: 80))
        let strip = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 50))
        strip.documentView = document
        document.addSubview(slider)
        let child = NSView(frame: .zero)
        slider.addSubview(child)
        suite.expect(HorizontalWheelScrolling.sidewaysStrip(at: slider) == nil
                     && HorizontalWheelScrolling.sidewaysStrip(at: child) == nil,
                     "an enabled slider and its descendants retain the wheel in an overflowing horizontal strip")
        slider.isEnabled = false
        suite.expect(HorizontalWheelScrolling.sidewaysStrip(at: slider) === strip,
                     "a disabled slider leaves horizontal wheel navigation available")
        slider.isEnabled = true
        slider.scrollable = false
        suite.expect(HorizontalWheelScrolling.sidewaysStrip(at: slider) === strip,
                     "a playback-position control does not claim scroll input")
        slider.scrollable = true
        suite.expect(HorizontalWheelScrolling.sidewaysStrip(at: document) === strip,
                     "scrolling the surrounding app list still navigates the strip")
        document.setFrameSize(NSSize(width: 80, height: 50))
        suite.expect(HorizontalWheelScrolling.sidewaysStrip(at: slider) == nil
                     && HorizontalWheelScrolling.sidewaysStrip(at: document) == nil,
                     "slider priority is independent of whether the app list overflows")
    }
}
