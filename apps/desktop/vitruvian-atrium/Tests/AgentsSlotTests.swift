// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// The Agents page's slot: when it shows, and what the tools in it are told
/// (`ui/slot`) as it shows, moves and goes.
enum AgentsSlotTests {
    static func run(_ suite: TestSuite) {
        whenItShows(suite)
        whatTheToolIsTold(suite)
    }

    static let place = CGRect(x: 512, y: 640.5, width: 420, height: 300)

    static func whenItShows(_ suite: TestSuite) {
        func state(expanded: Bool = true, section: NotchSectionItem = .module(.agents), tab: NotchAgentTab = .chat,
                   slotTool: Bool = true, rect: CGRect? = place) -> AgentsSlot {
            AgentsSlot.state(expanded: expanded, section: section, tab: tab, slotTool: slotTool, rect: rect)
        }
        suite.expect(state() == .shown(place), "the island open on the Agents page's Chat tab, with a tool in the slot")
        suite.expect(state(expanded: false) == .hidden, "a closed island shows no slot")
        suite.expect(state(section: .module(.music)) == .hidden, "another page of the island shows none")
        suite.expect(state(section: .tool(ToolID("com.acme.deploys")!)) == .hidden, "nor does a tool's page")
        suite.expect(state(tab: .telemetry) == .hidden, "the Telemetry tab shows none")
        suite.expect(state(slotTool: false) == .hidden, "with no tool in the slot there is no slot")
        suite.expect(state(rect: nil) == .hidden && state(rect: CGRect(x: 1, y: 1, width: 0, height: 10)) == .hidden,
                     "a place not measured yet, or with no size, is not shown")
    }

    static func whatTheToolIsTold(_ suite: TestSuite) {
        let moved = place.offsetBy(dx: 10, dy: 0)
        suite.expect(AgentsSlot.message(from: .hidden, to: .shown(place))
                         == UISlotParams(visible: true, x: 512, y: 640.5, width: 420, height: 300),
                     "the slot showing is told with its place in screen points")
        suite.expect(AgentsSlot.message(from: .shown(place), to: .shown(place)) == nil
                         && AgentsSlot.message(from: .hidden, to: .hidden) == nil,
                     "nothing that did not change is told twice")
        suite.expect(AgentsSlot.message(from: .shown(place), to: .shown(moved))?.x == 522,
                     "a slot that moved is told its new place")
        suite.expect(AgentsSlot.message(from: .shown(place), to: .hidden) == UISlotParams(visible: false, popOut: false),
                     "the slot going, because the island closed or another tab or page was chosen, says it was not "
                         + "popped out")
        suite.expect(AgentsSlot.message(from: .shown(place), to: .hidden, poppedOut: true)
                         == UISlotParams(visible: false, popOut: true),
                     "popped out, it says so, so the tool opens its own window")
    }
}
