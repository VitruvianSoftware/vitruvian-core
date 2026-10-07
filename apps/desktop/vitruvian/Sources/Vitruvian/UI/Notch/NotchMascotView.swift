// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianServices

/// The companion on its own, centred in its frame: the Command Bar's face
/// and the Settings preview.
struct NotchMascotView: NSViewRepresentable {
    var look: NotchMascotLook
    var mood: NotchMascotMood = .idle
    var size: CGFloat
    var idles = true
    /// A one-off motion, played whenever `cueID` changes.
    var cue: NotchMascotCue? = nil
    var cueID = 0
    /// Its eyes follow a file being dragged toward the island.
    var followsDrag = false
    /// A reaction it plays once, as it first shows: a notice's.
    var reaction: NotchMascotReaction? = nil

    func makeNSView(context: Context) -> NotchMascotHostView {
        let view = NotchMascotHostView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.followsDrag = followsDrag
        view.configure(look: look, size: size, mood: mood, idles: idles,
                       reduceMotion: context.environment.accessibilityReduceMotion, animated: false)
        if let reaction {
            // Small in a notice, it hops a little higher for its size to read.
            view.react(NotchMascotReactionEvent(id: UUID(), reaction: reaction, start: CACurrentMediaTime()),
                       lift: size * 0.32)
        }
        return view
    }

    func updateNSView(_ view: NotchMascotHostView, context: Context) {
        view.configure(look: look, size: size, mood: mood, idles: idles,
                       reduceMotion: context.environment.accessibilityReduceMotion, animated: true)
        view.place(at: nil, visible: nil)
        if let cue { view.play(cue, id: cueID) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchMascotHostView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? size, height: proposal.height ?? size)
    }
}

/// The companion in a closed strip: resting beside the camera, or strolling
/// through on a visit. It is hidden behind the camera as it passes.
struct NotchMascotTrackView: NSViewRepresentable {
    var look: NotchMascotLook
    var track: NotchMascotTrack
    /// Whether it stands at its resting place, or only comes for the visit.
    var rests: Bool
    var visit: NotchMascotVisit?
    /// The face it keeps at rest: wide awake while Keep Awake holds the Mac up.
    var mood: NotchMascotMood = .idle
    var reaction: NotchMascotReactionEvent?
    /// Switched off, the Settings preview shows it asleep: eyes shut, no
    /// blinking, and no eyes for the pointer.
    var awake = true
    /// Its eyes follow the pointer over the whole open island.
    var followsIsland = false
    /// It rests in the closed island and fades out early as an activity takes its place.
    var yieldsToActivities = false

    func makeNSView(context: Context) -> NotchMascotHostView {
        NotchMascotHostView(frame: CGRect(x: 0, y: 0, width: track.width, height: track.height))
    }

    func updateNSView(_ view: NotchMascotHostView, context: Context) {
        view.configure(look: look, size: track.size, mood: awake ? mood : .sleepy, idles: rests && awake,
                       reduceMotion: context.environment.accessibilityReduceMotion, animated: true)
        // Off stage at the far end once a visit is over, so nothing jumps
        // when its last frame hands back to where it stands.
        let x = rests ? track.rest : track.mirrored ? -track.size * 2 : track.width + track.size * 2
        var visible: [CGRect]?
        if let hidden = track.hidden {
            visible = [CGRect(x: -track.size * 3, y: -track.height, width: hidden.lowerBound + track.size * 3,
                              height: track.height * 3),
                       CGRect(x: hidden.upperBound, y: -track.height, width: track.width - hidden.upperBound + track.size * 3,
                              height: track.height * 3)]
        }
        view.place(at: CGPoint(x: x, y: track.baseline), visible: visible)
        view.followsPointer = rests && awake
        view.followsIsland = followsIsland && rests && awake
        view.yieldsToActivities = yieldsToActivities
        // A countdown is watched from the camera's left whatever the side.
        let stand = visit?.kind.watchesTimer == true ? track.leftSide.rest : track.rest
        view.playVisit(visit, path: NotchMascotMotion.path(for: visit?.kind ?? .pass, on: track),
                       baseline: track.baseline, stand: CGPoint(x: stand, y: track.baseline),
                       lift: track.hop(0.22))
        if rests { view.react(reaction, lift: track.hop(0.22)) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchMascotHostView, context: Context) -> CGSize? {
        CGSize(width: track.width, height: track.height)
    }
}

/// The companion over an activity's closed strip, which steps aside while
/// it visits or comes out to react. `track` is nil when the strip has no
/// room for it.
struct NotchMascotActivityVisit: ViewModifier {
    @ObservedObject var service: NotchService
    let track: NotchMascotTrack?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // A lap or a homecoming ends where it rests, which an activity's
        // strip has no place for, so only what ends out of sight comes over it.
        // A countdown is watched from beside a camera; a capsule copy has
        // none, and stepping its timer aside there would only blank it.
        let visit = track == nil ? nil : service.mascotVisit.flatMap {
            $0.kind.endsOutOfSight && !($0.kind.watchesTimer && track?.hidden == nil) ? $0 : nil
        }
        // Reacting or watching a countdown beside a camera, it covers only
        // the wing it stands in, as the black of the closed island, and the
        // other side stays in view. A capsule has no wings, so what it shows
        // steps aside instead.
        let hidden = track?.hidden
        let ownWing = visit?.kind.takesOnlyItsWing == true && hidden != nil
        let stepsAside = visit != nil && service.mascotStepsAside && !ownWing
        // A countdown is watched from the camera's left whatever the side.
        let rightWing = track?.mirrored == true && visit?.kind.watchesTimer == false
        content
            .opacity(stepsAside ? 0 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: stepsAside)
            .overlay(alignment: .topLeading) {
                // Handed back with the strip, halfway home, so what it covered
                // returns as it goes behind the camera.
                if ownWing, service.mascotStepsAside, let track, let hidden {
                    Color.black
                        .frame(width: rightWing ? track.width - hidden.upperBound : hidden.lowerBound,
                               height: track.height)
                        .offset(x: rightWing ? hidden.upperBound : 0)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: ownWing && service.mascotStepsAside)
            .overlay(alignment: .top) {
                if let track, let visit {
                    NotchMascotTrackView(look: NotchMascotSupport.look(), track: track, rests: false, visit: visit,
                                         mood: service.mascotRestingMood)
                        .frame(width: track.width, height: track.height)
                        .allowsHitTesting(false)
                }
            }
    }
}
