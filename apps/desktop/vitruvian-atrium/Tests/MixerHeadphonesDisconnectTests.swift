// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation
import VitruvianCore
import VitruvianServices

/// The real headphone disconnect lowering and its restore run against an
/// in-memory pair of outputs. No device volume or mute switch is touched.
enum MixerHeadphonesDisconnectContract {
    typealias Mixer = AppVolumeMixer

    /// Volume and mute per device. A device missing from `volumes` cannot be
    /// lowered; one missing from `mutes` has no mute switch.
    /// Not main-actor isolated: the lowering reads it from `@Sendable` closures,
    /// on the one thread the test runs it on.
    nonisolated final class Outputs: @unchecked Sendable {
        var volumes: [AudioObjectID: Float32] = [:]
        var mutes: [AudioObjectID: Bool] = [:]
        var muteSettable = true
        var muteWrites: [Bool] = []

        var switches: Mixer.OutputSwitches {
            Mixer.OutputSwitches(
                volume: { [self] in volumes[$0] },
                setVolume: { [self] volume, device in
                    guard volumes[device] != nil else { return false }
                    volumes[device] = volume
                    return true
                },
                muted: { [self] in mutes[$0] },
                setMuted: { [self] muted, device in
                    guard mutes[device] != nil, muteSettable else { return false }
                    muteWrites.append(muted)
                    mutes[device] = muted
                    return true
                })
        }
    }

    static func device(_ uid: String, headphones: Bool, id: AudioObjectID) -> MixerOutputDevice {
        MixerOutputDevice(id: uid, uid: uid, name: uid, isDefault: false, isHeadphones: headphones,
                          canBeDefaultOutput: true, canBeDefaultSystemOutput: true,
                          priorityTier: MixerRoutingSupport.PriorityTier(transportType: 0), audioObjectID: id)
    }

    static func run(_ suite: TestSuite) {
        let headphones = device("headphones", headphones: true, id: 1)
        let speakers = device("speakers", headphones: false, id: 2)
        let outputs = Outputs()
        func reset(speakerVolume: Float32 = 0.6, speakerMuted: Bool? = false) {
            outputs.volumes = [1: 0.5, 2: speakerVolume]
            outputs.mutes = [1: false]
            outputs.mutes[2] = speakerMuted
            outputs.muteSettable = true
            outputs.muteWrites = []
        }
        func disconnect(percent: Int) -> Mixer.LoweredOutputState {
            Mixer.loweringOutputVolumeIfHeadphonesDisconnected(
                state: Mixer.LoweredOutputState(),
                previousDefaultUID: "headphones", previousOutputDevices: [headphones, speakers],
                nextDefaultUID: "speakers", nextOutputDevices: [speakers],
                lowerOnDisconnect: true, lowerToPercent: percent, switches: outputs.switches)
        }
        func reconnect(_ state: Mixer.LoweredOutputState) -> Mixer.LoweredOutputState {
            Mixer.loweringOutputVolumeIfHeadphonesDisconnected(
                state: state,
                previousDefaultUID: "speakers", previousOutputDevices: [speakers],
                nextDefaultUID: "headphones", nextOutputDevices: [headphones, speakers],
                lowerOnDisconnect: true, lowerToPercent: 0, switches: outputs.switches)
        }

        reset()
        var state = disconnect(percent: 0)
        suite.expect(outputs.volumes[2] == 0 && outputs.mutes[2] == true
                     && state.loweredOutput?.mutedByLowering == true,
                     "a headphone disconnect lowered to silence also mutes the speakers")
        state = reconnect(state)
        suite.expect(outputs.volumes[2] == 0.6 && outputs.mutes[2] == false && state.loweredOutput == nil,
                     "headphones coming back unmute the speakers the disconnect muted and restore their volume")

        reset()
        _ = disconnect(percent: 5)
        suite.expect(outputs.mutes[2] == false && outputs.muteWrites.isEmpty,
                     "a low but audible disconnect volume never touches the speakers' mute")

        reset(speakerMuted: true)
        state = disconnect(percent: 0)
        suite.expect(state.loweredOutput?.mutedByLowering == false && outputs.muteWrites.isEmpty,
                     "speakers muted before the disconnect are not recorded as muted by it")
        state = reconnect(state)
        suite.expect(outputs.mutes[2] == true && outputs.muteWrites.isEmpty,
                     "speakers muted before the disconnect stay muted when the headphones come back")

        reset()
        state = disconnect(percent: 0)
        outputs.mutes[2] = false
        outputs.muteWrites = []
        state = reconnect(state)
        suite.expect(outputs.muteWrites.isEmpty && outputs.mutes[2] == false,
                     "a mute switched off after the disconnect is not written again when the headphones come back")

        reset()
        state = disconnect(percent: 0)
        outputs.volumes[2] = 0.3
        outputs.muteWrites = []
        state = reconnect(state)
        suite.expect(outputs.volumes[2] == 0.3 && outputs.mutes[2] == true
                     && outputs.muteWrites.isEmpty && state.loweredOutput == nil,
                     "speakers changed after the disconnect keep their volume and their mute when the headphones come back")

        reset()
        outputs.muteSettable = false
        state = disconnect(percent: 0)
        suite.expect(outputs.volumes[2] == 0 && state.loweredOutput?.mutedByLowering == false,
                     "a mute switch that cannot be set is not recorded as muted by the disconnect")

        reset(speakerVolume: 0)
        state = disconnect(percent: 0)
        suite.expect(outputs.mutes[2] == true && state.loweredOutput?.mutedByLowering == true,
                     "speakers already at zero are still remembered as muted by the disconnect")
        state = reconnect(state)
        suite.expect(outputs.mutes[2] == false && state.loweredOutput == nil,
                     "speakers already at zero are unmuted again when the headphones come back")
    }
}
