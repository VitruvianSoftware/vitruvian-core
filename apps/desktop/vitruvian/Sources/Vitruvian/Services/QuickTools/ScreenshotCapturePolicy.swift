// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import VitruvianCore
import VitruvianDesign

/// Decides which of this process's windows ScreenCaptureKit must exclude.
/// Protected IDs are intersected with the actual own IDs from the same
/// shareable-content snapshot, so stale window numbers cannot affect another app.
package enum ScreenshotCapturePolicy {
    /// The app's own windows one capture has to keep out before the "Hide
    /// Vitruvian windows" preference narrows what is left.
    ///
    /// Workflow surfaces — the selection overlays, the countdown and scrolling
    /// HUDs and the quick preview — are the tool taking the capture and can
    /// never be its subject, so they stay out whatever the preference says.
    /// Content windows — editors and pinned captures — are ordinary windows
    /// somebody left on screen, so the preference owns them (issue #780).
    ///
    /// Recording is exempt from that preference in
    /// `ScreenshotSupport.unifiedCapturePolicy`, so it passes
    /// `honoursVisibilityPreference: false` and keeps both kinds out.
    package static func protectedWindowIDs(workflowWindowIDs: Set<CGWindowID>,
                                   contentWindowIDs: Set<CGWindowID>,
                                   honoursVisibilityPreference: Bool) -> Set<CGWindowID> {
        honoursVisibilityPreference
            ? workflowWindowIDs
            : workflowWindowIDs.union(contentWindowIDs)
    }

    package static func excludedWindowIDs(hideVitruvianWindows: Bool,
                                  ownWindowIDs: Set<CGWindowID>,
                                  protectedWindowIDs: Set<CGWindowID>) -> Set<CGWindowID> {
        hideVitruvianWindows ? ownWindowIDs : ownWindowIDs.intersection(protectedWindowIDs)
    }

    package static func canPickWindow(_ windowID: CGWindowID,
                              isOwnWindow: Bool,
                              hideVitruvianWindows: Bool,
                              protectedWindowIDs: Set<CGWindowID>) -> Bool {
        !isOwnWindow
            || (!hideVitruvianWindows && !protectedWindowIDs.contains(windowID))
    }

    /// One on-screen window as the capture decision needs it.
    package struct CaptureWindow: Equatable {
        package let id: CGWindowID
        package let ownerPID: pid_t
        package let frame: CGRect
        /// The window list gives it no title. Decorations have none; almost
        /// every window a person works in does.
        package var isUntitled = false

        // Spelled out because a memberwise initializer never leaves its module.
        package init(id: CGWindowID, ownerPID: pid_t, frame: CGRect, isUntitled: Bool = false) {
            self.id = id
            self.ownerPID = ownerPID
            self.frame = frame
            self.isUntitled = isUntitled
        }
    }

    /// How far past the window it frames a decoration may reach on each side.
    package static let decorationMargin: ClosedRange<CGFloat> = 1...32

    /// Windows another process draws around a window, such as a focus border.
    /// Picking one captures only the painted frame, so a click there has to
    /// reach the window it surrounds. A decoration has no title, sits directly
    /// in front of or behind that window and reaches past it by the same small
    /// margin on every side. Ordinary windows miss at least one of those: two
    /// maximized apps share a frame, and a window over one maximized with a
    /// gap has a title.
    package static func decorationWindowIDs(frontToBack windows: [CaptureWindow]) -> Set<CGWindowID> {
        var decorations: Set<CGWindowID> = []
        for (index, window) in windows.enumerated() where window.isUntitled {
            let neighbours = [index - 1, index + 1].filter(windows.indices.contains)
            if neighbours.contains(where: { frames(window, around: windows[$0]) }) {
                decorations.insert(window.id)
            }
        }
        return decorations
    }

    private static func frames(_ decoration: CaptureWindow, around window: CaptureWindow) -> Bool {
        guard decoration.ownerPID != window.ownerPID else { return false }
        let margins = [window.frame.minX - decoration.frame.minX,
                       window.frame.minY - decoration.frame.minY,
                       decoration.frame.maxX - window.frame.maxX,
                       decoration.frame.maxY - window.frame.maxY]
        guard let smallest = margins.min(), let largest = margins.max() else { return false }
        // A point of slack absorbs rounding.
        return decorationMargin.contains(smallest) && decorationMargin.contains(largest)
            && largest - smallest <= 1
    }

    /// The windows a capture of one clicked window has to draw. The area is
    /// the clicked window's own, so the shot stays the one that was asked for.
    package struct AttachedCapturePlan: Equatable {
        /// The clicked window first, then what sits on it, back to front.
        package let windowIDs: [CGWindowID]
        package let bounds: CGRect

        // Spelled out because a memberwise initializer never leaves its module.
        package init(windowIDs: [CGWindowID], bounds: CGRect) {
            self.windowIDs = windowIDs
            self.bounds = bounds
        }
    }

    /// What a sheet, alert or modal dialog stacked on the clicked window adds
    /// to its capture (issue #1098).
    ///
    /// macOS gives a sheet a window of its own, so asking the window server or
    /// ScreenCaptureKit for the one window that was clicked returns it without
    /// whatever the app put on top — the capture comes back showing a dialog
    /// that is plainly on screen as missing. The relationship is not in the
    /// window list, so this first pass finds the shape it has there: same
    /// application, in front of the window, and lying entirely within it.
    ///
    /// Containment bounds the first pass to the clicked window's area. Anything
    /// reaching past its edge is left to the ordinary capture, while a sheet
    /// the full width of its parent still qualifies.
    ///
    /// `nil` when nothing is attached, which leaves the ordinary single-window
    /// capture to answer.
    package static func attachedCapturePlan(target: CaptureWindow,
                                    frontToBack: [CaptureWindow]) -> AttachedCapturePlan? {
        guard target.frame.width > 0, target.frame.height > 0,
              let position = frontToBack.firstIndex(where: { $0.id == target.id })
        else { return nil }
        let attached = frontToBack[..<position].filter { candidate in
            candidate.ownerPID == target.ownerPID
                && target.frame.contains(candidate.frame)
        }
        guard !attached.isEmpty else { return nil }
        // Back to front, so the clicked window is drawn first and what the app
        // stacked on it lands on top in the order it is shown.
        let ordered = Array(attached.reversed())
        return AttachedCapturePlan(windowIDs: [target.id] + ordered.map(\.id),
                                   bounds: target.frame)
    }

    /// Narrows a geometric plan to the attached windows Accessibility named.
    /// A missing answer leaves geometry alone; an answer with no matches leaves
    /// the ordinary single-window capture to answer.
    package static func confirmedAttachment(_ plan: AttachedCapturePlan,
                                    confirmedIDs: Set<CGWindowID>?) -> AttachedCapturePlan? {
        guard let confirmedIDs else { return plan }
        guard let targetID = plan.windowIDs.first else { return nil }
        let attachedIDs = plan.windowIDs.dropFirst().filter(confirmedIDs.contains)
        guard !attachedIDs.isEmpty else { return nil }
        return AttachedCapturePlan(windowIDs: [targetID] + attachedIDs,
                                   bounds: plan.bounds)
    }

    /// The plan a capture of one clicked window draws: the geometric one,
    /// narrowed by what Accessibility confirms only when the app already
    /// holds that grant. Without it, window capture never starts an
    /// Accessibility round trip merely because geometry found a candidate.
    /// `confirmedIDs` is asked only then, with the geometric plan.
    package static func attachedCapturePlan(
        target: CaptureWindow,
        frontToBack: [CaptureWindow],
        accessibilityGranted: @autoclosure () -> Bool,
        confirmedIDs: (AttachedCapturePlan) -> Set<CGWindowID>?) -> AttachedCapturePlan? {
        guard let geometricPlan = attachedCapturePlan(target: target, frontToBack: frontToBack)
        else { return nil }
        guard accessibilityGranted() else { return geometricPlan }
        return confirmedAttachment(geometricPlan, confirmedIDs: confirmedIDs(geometricPlan))
    }

    /// Subroles Accessibility gives the windows people work in. A candidate
    /// it names this way is a window of its own, not something stacked on
    /// the clicked one. The set matches what the auto-quit and enumeration
    /// paths already read.
    package static let standardWindowSubroles: Set<String> = ["AXStandardWindow", "AXFullScreenWindow"]

    /// The geometric candidates Accessibility does not positively identify as
    /// standard windows. `subroles` holds the subrole of each candidate
    /// Accessibility resolved and could read; a candidate it had no answer
    /// for stays in, since only a window it names as standard is filtered out.
    package static func accessibilityAttachedWindowIDs(candidateWindowIDs: [CGWindowID],
                                                       subroles: [CGWindowID: String]) -> Set<CGWindowID> {
        Set(candidateWindowIDs.filter { id in
            subroles[id].map { !standardWindowSubroles.contains($0) } ?? true
        })
    }

    /// The one display a composited capture of `bounds` is cropped from: the
    /// index of the only display frame it touches. A window straddling two
    /// displays has no single display to crop from, while one hanging off a
    /// lone display's edge still does, since the crop clamps the part that is
    /// on screen. `nil` leaves the single-window routes to answer.
    package static func attachedCaptureDisplayIndex(displayFrames: [CGRect],
                                                    bounds: CGRect) -> Int? {
        let hits = displayFrames.indices.filter { displayFrames[$0].intersects(bounds) }
        return hits.count == 1 ? hits[0] : nil
    }
}
