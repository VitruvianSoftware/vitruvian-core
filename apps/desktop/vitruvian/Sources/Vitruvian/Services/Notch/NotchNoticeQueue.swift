// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreGraphics
import VitruvianCore

/// The island's notice: the one on screen, whether its message is open in
/// place, and the one still drawn while the island closes around it. It
/// decides which notice may take the screen and how each arrives and leaves.
/// `NotchService` animates what it returns and keeps the timers.
package struct NotchNoticeQueue: Equatable {
    package private(set) var notice: NotchNotice?
    /// The message is open in place, as a deliberate hover over a held
    /// banner leaves it.
    package private(set) var expanded = false
    /// A compact notice stays drawn while the island closes around it.
    package private(set) var departing: NotchNotice?

    package init() {}

    /// A notice on its way to the screen.
    package struct Arrival: Equatable {
        package let notice: NotchNotice
        /// A message open in place stays open for the one replacing it.
        package let expanded: Bool
        package let transition: NotchContentTransition
        /// The same notice with a new reading only fits its width, steadily.
        package let fitsInPlace: Bool
    }

    /// A notice leaving the screen.
    package struct Departure: Equatable {
        /// What stays drawn while the island closes, if anything.
        package let departing: NotchNotice?
        package let transition: NotchContentTransition
    }

    /// Whether a notice for `event` may take the screen. A message open in
    /// place gives way only to its own kind or to a more urgent one.
    package func admits(_ event: NotchEvent) -> Bool {
        NotchSupport.shouldReplace(notice?.event, with: event, held: expanded)
    }

    /// How `incoming` arrives on a closed strip drawn with `geometry`.
    /// `canPresent` is whether the closed island can show a notice now;
    /// `pointerOver`, whether the pointer is over the island, is read only
    /// when an open message could stay open.
    package func arrival(of incoming: NotchNotice, in geometry: NotchGeometry, canPresent: Bool,
                         pointerOver: @autoclosure () -> Bool) -> Arrival {
        var incoming = incoming
        // A banner replacing one still on screen keeps its wings, so a burst
        // does not resize the island with each message.
        if incoming.notification != nil, let shown = notice, shown.notification != nil, canPresent, !expanded {
            incoming.minimumWings = shown.wings(in: geometry)
        }
        let keepsPreview = expanded && incoming.notificationID != nil && pointerOver()
        // Slider and key bursts only replace the displayed value. They never
        // restart a window resize or enqueue another layout animation.
        let transition: NotchContentTransition = !canPresent ? .none
            : notice == nil ? .reveal : notice?.event != incoming.event || expanded ? .replace : .none
        let fitsInPlace = canPresent && !expanded && !keepsPreview && notice?.event == incoming.event
        return Arrival(notice: incoming, expanded: keepsPreview, transition: transition, fitsInPlace: fitsInPlace)
    }

    package mutating func show(_ arrival: Arrival) {
        notice = arrival.notice
        expanded = arrival.expanded
    }

    /// How the notice leaves: a compact one stays drawn while the island
    /// closes around it, an open message closes with the island, and one the
    /// island cannot show goes at once.
    package func departure(canPresent: Bool) -> Departure {
        let transition: NotchContentTransition = notice == nil || !canPresent ? .none
            : expanded ? .dismiss : .depart
        return Departure(departing: transition == .depart ? notice : nil, transition: transition)
    }

    package mutating func leave(_ departure: Departure) {
        departing = departure.departing
        notice = nil
        expanded = false
    }

    /// The message held under the pointer opens in place.
    package mutating func open() {
        expanded = true
    }

    /// The notice goes without a departure, as when the island opens over
    /// it, collapses an open message or stops.
    package mutating func clear() {
        notice = nil
        expanded = false
    }

    /// Ends the departure under way. False when there was none.
    package mutating func finishDeparture() -> Bool {
        guard departing != nil else { return false }
        departing = nil
        return true
    }

    /// Whether the pointer can hold the notice: a mirrored banner on screen,
    /// not covered, and not hidden away with the island.
    package func holdable(canPresent: Bool, hidden: Bool) -> Bool {
        notice?.notificationID != nil && canPresent && !hidden
    }

    /// Whether the notice still belongs on screen once the preferences
    /// change: its kind still routes to the island, and a mirrored banner
    /// stays reachable.
    package func survives(routes: (NotchEvent) -> Bool, hidden: Bool) -> Bool {
        guard let notice else { return true }
        return routes(notice.event) && !(notice.notificationID != nil && hidden)
    }
}
