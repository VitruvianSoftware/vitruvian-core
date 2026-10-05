// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the island's volume notice with real Combine delivery, a controlled
/// audio source and a clock of its own, without changing hardware volume.
enum NotchVolumeFeedbackTests {
    final class Mixer {
        @Published var currentOutputDeviceUID: String? = "speakers"
        @Published var systemOutputVolume: Double? = 0.3
        @Published var systemOutputMuted: Bool? = false

        func publish(device: String?, volume: Double?, muted: Bool?, identityFirst: Bool = true) {
            if identityFirst { currentOutputDeviceUID = device }
            systemOutputVolume = volume
            systemOutputMuted = muted
            if !identityFirst { currentOutputDeviceUID = device }
        }
    }

    /// The island as the notice sees it: open or closed, able to show system
    /// feedback or not, and the uptime its own controls are measured against.
    final class Island {
        var expanded = false
        var showsSystemFeedback = true
        var notice: NotchNotice?
        var presented: [NotchNotice] = []
        var now: TimeInterval = 1_000

        func show(_ incoming: NotchNotice) -> Bool {
            guard showsSystemFeedback,
                  NotchSupport.shouldReplace(notice?.event, with: incoming.event) else { return false }
            notice = incoming
            presented.append(incoming)
            return true
        }
    }

    static func makeFeedback(_ mixer: Mixer, _ island: Island) -> NotchVolumeFeedback {
        NotchVolumeFeedback(
            output: .init(volume: { mixer.systemOutputVolume }, muted: { mixer.systemOutputMuted },
                          deviceUID: { mixer.currentOutputDeviceUID },
                          changes: {
                              mixer.$systemOutputVolume
                                  .combineLatest(mixer.$systemOutputMuted, mixer.$currentOutputDeviceUID)
                                  .map { $0.2 }
                                  .eraseToAnyPublisher()
                          }),
            island: .init(isExpanded: { island.expanded }, show: { island.show($0) }, uptime: { island.now }))
    }

    static func run(_ suite: TestSuite) {
        func drain() {
            var delivered = false
            DispatchQueue.main.async { delivered = true }
            let deadline = Date().addingTimeInterval(1)
            while !delivered && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            }
            suite.expect(delivered, "queued volume publications settle within the test deadline")
        }
        let connection = NotchNotice(event: .accessory, title: "Wireless Headphones",
                                     detail: "Connected", symbol: "headphones")
        for identityFirst in [false, true] {
            let mixer = Mixer()
            let island = Island()
            let feedback = makeFeedback(mixer, island)
            let subscription = feedback.follow()
            drain()
            suite.expect(island.presented.isEmpty, "starting volume observation establishes a silent baseline")
            island.notice = connection
            mixer.publish(device: "headphones", volume: 0.75, muted: true, identityFirst: identityFirst)
            drain()
            suite.expect(island.notice == connection && island.presented.isEmpty,
                   "switching output never replaces its connection notice with stored volume or mute")
            mixer.systemOutputVolume = 0.8
            mixer.systemOutputMuted = false
            drain()
            suite.expect(island.notice?.event == .volume && island.notice?.level == 0.8 && island.presented.count == 1,
                   "a real adjustment on the new output appears once with its final mute state")
            island.presented.removeAll()
            island.notice = connection
            mixer.publish(device: "another-output", volume: 0.8, muted: false, identityFirst: identityFirst)
            drain()
            suite.expect(island.notice == connection && island.presented.isEmpty,
                   "an output switch at the same level is also silent")
            mixer.systemOutputMuted = true
            drain()
            suite.expect(island.notice?.event == .volume && island.notice?.level == 0,
                   "the first real mute change after an equal-volume switch is not swallowed")
            island.presented.removeAll()
            island.notice = connection
            mixer.publish(device: nil, volume: nil, muted: nil)
            mixer.publish(device: "headphones", volume: nil, muted: nil)
            drain()
            mixer.publish(device: "headphones", volume: 0.5, muted: false)
            drain()
            suite.expect(island.notice == connection && island.presented.isEmpty,
                   "disconnecting and receiving a delayed initial reading remain silent")
            mixer.publish(device: "old-output", volume: 0.9, muted: true)
            mixer.publish(device: "latest-output", volume: 0.2, muted: false)
            drain()
            suite.expect(island.notice == connection && island.presented.isEmpty,
                   "queued publications from superseded outputs cannot flash a volume notice")
            mixer.publish(device: nil, volume: nil, muted: nil)
            mixer.publish(device: "latest-output", volume: 0.4, muted: false)
            drain()
            suite.expect(island.notice == connection && island.presented.isEmpty,
                   "a quick reconnect to the same output invalidates its old baseline before queued delivery")
            feedback.showCurrentVolume()
            suite.expect(island.notice?.event == .volume && island.notice?.level == 0.4,
                   "an explicit volume key still shows feedback even when the level has not changed")
            island.expanded = true
            island.presented.removeAll()
            mixer.systemOutputVolume = 0.6
            drain()
            suite.expect(island.notice?.level == 0.6 && island.presented.count == 1,
                   "volume changes supply header feedback while the island is open on any page")
            island.presented.removeAll()
            // Each step of the island's slider or mute button marks its change.
            feedback.noteOwnAdjustment()
            mixer.systemOutputVolume = 0.35
            drain()
            feedback.noteOwnAdjustment()
            mixer.systemOutputMuted = true
            drain()
            suite.expect(island.presented.isEmpty,
                   "the island's own level and mute controls leave the open header's title alone")
            feedback.showCurrentVolume()
            suite.expect(island.presented.count == 1 && island.notice?.level == 0,
                   "a volume key right after an own adjustment still shows feedback")
            island.presented.removeAll()
            island.now += 0.5
            mixer.systemOutputMuted = false
            drain()
            suite.expect(island.presented.isEmpty, "the island's own adjustment is its own for a second")
            island.now += 0.5
            mixer.systemOutputVolume = 0.45
            drain()
            suite.expect(island.presented.count == 1 && island.notice?.level == 0.45,
                   "a change after the own adjustment's moment shows in the open header again")
            island.presented.removeAll()
            island.expanded = false
            feedback.noteOwnAdjustment()
            mixer.systemOutputVolume = 0.5
            drain()
            suite.expect(island.presented.count == 1,
                   "a closed island keeps its volume feedback whatever changed the level")
            island.presented.removeAll()
            subscription.cancel()
            mixer.publish(device: "stopped-output", volume: 0.1, muted: false)
            drain()
            suite.expect(island.presented.isEmpty, "stopping observation cancels volume feedback")
            withExtendedLifetime(feedback) {}
        }

        // The command bar writes a level and then reports it, because the
        // observer can have nothing new to show for that write.
        let mixer = Mixer()
        let island = Island()
        let feedback = makeFeedback(mixer, island)
        let subscription = feedback.follow()
        drain()
        mixer.systemOutputVolume = 0.3
        drain()
        suite.expect(island.presented.isEmpty, "rewriting the current level gives the observer nothing to show")
        suite.expect(feedback.showVolume(0.3) && island.notice?.level == 0.3,
               "a level set outside the island shows even when it matches the current one")
        island.presented.removeAll()
        mixer.publish(device: "headphones", volume: 0.6, muted: false)
        drain()
        suite.expect(island.presented.isEmpty && feedback.showVolume(0.6) && island.notice?.level == 0.6,
               "a level set outside the island shows when it is a new output's silent first reading")
        island.presented.removeAll()
        mixer.publish(device: nil, volume: 0.5, muted: false)
        drain()
        mixer.systemOutputVolume = 0.7
        drain()
        suite.expect(island.presented.isEmpty, "a level read with no output device shows nothing")
        island.expanded = true
        suite.expect(feedback.showVolume(0.2) && island.notice?.level == 0.2,
               "a level set outside the open island supplies its header feedback")
        island.showsSystemFeedback = false
        suite.expect(!feedback.showVolume(0.9) && island.notice?.level == 0.2,
               "an island that cannot show volume leaves the confirmation to the caller")
        subscription.cancel()
    }
}
