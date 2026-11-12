// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The island's notice queue (`NotchNoticeQueue`) on its own: which notice
/// may take the screen, and how each arrives and leaves.
enum NotchNoticeQueueTests {
    /// A notched MacBook's closed strip, which notices arrive on.
    private static var geometry: NotchGeometry {
        NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, cameraWidth: 185)
    }

    private static func plain(_ event: NotchEvent, _ title: String = "Notice") -> NotchNotice {
        NotchNotice(event: event, title: title, detail: "50%", symbol: "speaker.wave.2.fill")
    }

    private static func banner(_ body: String) -> NotchNotice {
        NotchNotice(event: .systemNotification, title: "Alex", detail: body, symbol: "bell.fill",
                    notification: NotchNotificationContent(app: "Chat", title: "Alex", subtitle: "", body: body),
                    notificationID: UUID())
    }

    /// A queue showing `notice`, open in place when `expanded`.
    private static func showing(_ notice: NotchNotice, expanded: Bool = false) -> NotchNoticeQueue {
        var queue = NotchNoticeQueue()
        queue.show(queue.arrival(of: notice, in: geometry, canPresent: true, pointerOver: true))
        if expanded { queue.open() }
        return queue
    }

    static func run(_ suite: TestSuite) {
        var queue = NotchNoticeQueue()
        suite.expect(queue.admits(.track) && queue.admits(.volume), "an empty island takes any notice")
        var read = false
        let first = queue.arrival(of: plain(.volume), in: geometry, canPresent: true, pointerOver: { read = true; return true }())
        suite.expect(first.transition == .reveal && !first.expanded && !read,
                     "the first notice reveals the island, and the pointer is not read for it")
        queue.show(first)
        suite.expect(queue.notice?.event == .volume, "the arriving notice is the one on screen")
        suite.expect(queue.arrival(of: plain(.volume, "Louder"), in: geometry, canPresent: true, pointerOver: false).transition == .none,
                     "a burst of the same kind only replaces the value on screen")
        suite.expect(queue.arrival(of: plain(.brightness), in: geometry, canPresent: true, pointerOver: false).transition == .replace,
                     "another kind of notice replaces the one on screen")
        suite.expect(queue.arrival(of: plain(.timer), in: geometry, canPresent: false, pointerOver: false).transition == .none,
                     "a notice the closed island cannot show changes nothing on screen")
        suite.expect(!queue.admits(.track) && queue.admits(.volume) && queue.admits(.brightness),
                     "a notice gives way only to one as urgent or more")

        // A message open in place.
        let held = showing(banner("Hello"), expanded: true)
        suite.expect(!held.admits(.track) && held.admits(.systemNotification) && held.admits(.volume)
                     && !held.admits(.battery),
                     "an open message gives way only to its own kind or a more urgent one")
        let replacement = banner("Again")
        suite.expect(held.arrival(of: replacement, in: geometry, canPresent: true, pointerOver: true).expanded,
                     "a new message under the pointer keeps the open message open")
        suite.expect(!held.arrival(of: replacement, in: geometry, canPresent: true, pointerOver: false).expanded,
                     "a new message with the pointer elsewhere arrives as a timed banner")
        suite.expect(held.arrival(of: plain(.volume), in: geometry, canPresent: true, pointerOver: true).transition == .replace
                     && !held.arrival(of: plain(.volume), in: geometry, canPresent: true, pointerOver: true).expanded,
                     "feedback takes the place of an open message as a plain notice")

        // A burst of banners keeps the first one's width.
        let wide = banner(String(repeating: "A long message in a busy chat ", count: 8))
        let burst = showing(wide)
        let short = banner("ok")
        suite.expect(burst.arrival(of: short, in: geometry, canPresent: true, pointerOver: false).notice.preferredWingWidth
                     == wide.wings(in: geometry).widest && short.preferredWingWidth < wide.preferredWingWidth,
                     "a message replacing a banner still on screen keeps its width")
        suite.expect(NotchNoticeQueue().arrival(of: short, in: geometry, canPresent: true, pointerOver: false).notice.preferredWingWidth
                     == short.preferredWingWidth,
                     "a message on its own takes only the width it needs")
        suite.expect(burst.arrival(of: short, in: geometry, canPresent: false, pointerOver: false).notice.preferredWingWidth
                     == short.preferredWingWidth,
                     "a message the island cannot show does not inherit a width")

        // Leaving.
        var compact = showing(plain(.track))
        let departure = compact.departure(canPresent: true)
        suite.expect(departure.transition == .depart && departure.departing?.event == .track,
                     "a compact notice stays drawn while the island closes around it")
        compact.leave(departure)
        suite.expect(compact.notice == nil && compact.departing?.event == .track,
                     "the departing notice is kept apart from the screen's")
        suite.expect(compact.admits(.clipboard), "a departing notice holds nothing back")
        let ended = compact.finishDeparture()
        let endedAgain = compact.finishDeparture()
        suite.expect(ended && compact.departing == nil && !endedAgain, "the departure ends once")
        var open = showing(banner("Hello"), expanded: true)
        let closing = open.departure(canPresent: true)
        suite.expect(closing.transition == .dismiss && closing.departing == nil,
                     "an open message closes with the island instead of departing")
        open.leave(closing)
        suite.expect(open.notice == nil && !open.expanded, "a closed message leaves nothing open")
        suite.expect(showing(plain(.track)).departure(canPresent: false).transition == .none
                     && NotchNoticeQueue().departure(canPresent: true).transition == .none,
                     "a notice the island cannot show, or none, leaves at once")
        var cleared = showing(banner("Hello"), expanded: true)
        cleared.clear()
        suite.expect(cleared.notice == nil && !cleared.expanded && cleared.departing == nil,
                     "a notice cleared by the island goes without a departure")

        // Holding and preferences.
        let message = showing(banner("Hello"))
        suite.expect(message.holdable(canPresent: true, hidden: false), "the pointer can hold a mirrored banner")
        suite.expect(!message.holdable(canPresent: false, hidden: false) && !message.holdable(canPresent: true, hidden: true)
                     && !showing(plain(.volume)).holdable(canPresent: true, hidden: false),
                     "a covered, hidden or plain notice cannot be held")
        suite.expect(message.survives(routes: { _ in true }, hidden: false)
                     && !message.survives(routes: { _ in true }, hidden: true)
                     && !message.survives(routes: { $0 != .systemNotification }, hidden: false),
                     "a banner leaves when its kind stops routing or the island hides")
        suite.expect(showing(plain(.volume)).survives(routes: { _ in true }, hidden: true)
                     && NotchNoticeQueue().survives(routes: { _ in false }, hidden: true),
                     "hiding keeps a plain notice, and an empty island has nothing to drop")
    }
}
