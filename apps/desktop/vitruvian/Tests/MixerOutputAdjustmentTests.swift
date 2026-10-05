// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The real `MixerOutputControl` against an in-memory output and HAL and main
/// queues the test runs one job at a time. No output device, volume, mute
/// state or event tap is touched.
enum MixerOutputAdjustmentContract {
    nonisolated final class Hardware: @unchecked Sendable {
        struct Write: Equatable {
            let device: AudioObjectID
            let volume: Float?
            let muted: Bool?
        }
        /// The default output.
        var device: AudioObjectID = 1
        var writes: [Write] = []
        var succeeds = true
        /// Runs during the next volume write, on the HAL queue the test runs
        /// on the main thread.
        var afterVolumeWrite: (() -> Void)?
        var volume: Float32? = 0.2
        var settable = true
        var muted: Bool? = false
        var hal: [@Sendable () -> Void] = []
        var main: [@MainActor @Sendable () -> Void] = []
        var later: [@MainActor @Sendable () -> Void] = []
        var listening = true
        var outputsChanged = 0
        var publishedVolume: Double?
        var publishedMuted: Bool?

        func runHAL() { hal.removeFirst()() }
        @MainActor func runMain() { main.removeFirst()() }
        @MainActor func advance() {
            let due = later
            later.removeAll()
            due.forEach { $0() }
        }
    }

    /// What the mixer does when the default output changes: drop the old
    /// output, follow the new one, publish its reading.
    static func select(_ control: MixerOutputControl, _ device: AudioObjectID?,
                       volume: Double?, muted: Bool?) {
        control.end()
        if let device { control.follow(device) }
        control.apply(volume: volume, muted: muted)
    }

    static func run(_ suite: TestSuite) {
        var hardware = Hardware()
        func make() -> MixerOutputControl {
            let machine = Hardware()
            hardware = machine
            let control = MixerOutputControl(host: .init(
                hal: { machine.hal.append($0) },
                main: { machine.main.append($0) },
                after: { _, work in machine.later.append(work) },
                defaultOutput: { machine.device },
                volumeIsSettable: { _ in machine.settable },
                volume: { _ in machine.volume },
                muted: { _ in machine.muted },
                setVolume: { value, device in
                    machine.writes.append(.init(device: device, volume: value, muted: nil))
                    let after = machine.afterVolumeWrite
                    machine.afterVolumeWrite = nil
                    after?()
                    return machine.succeeds
                },
                setMuted: { value, device in
                    machine.writes.append(.init(device: device, volume: nil, muted: value))
                    return machine.succeeds
                },
                isListening: { machine.listening },
                volumeChanged: { machine.publishedVolume = $0 },
                mutedChanged: { machine.publishedMuted = $0 },
                outputsChanged: { machine.outputsChanged += 1 }))
            select(control, 1, volume: 0.2, muted: false)
            return control
        }
        func finish(_ control: MixerOutputControl) {
            while !hardware.hal.isEmpty || !hardware.main.isEmpty {
                if !hardware.hal.isEmpty { hardware.runHAL() }
                if !hardware.main.isEmpty { hardware.runMain() }
            }
        }

        var mixer = make()
        var completions: [Bool] = []
        mixer.requestAdjustment(volume: 0.3) { completions.append($0) }
        mixer.requestAdjustment(volume: 0.5) { completions.append($0) }
        mixer.requestAdjustment(volume: 0.8) { completions.append($0) }
        mixer.apply(volume: 0.2, muted: true)
        suite.expect(mixer.volume == 0.8 && mixer.muted == false,
                     "an old volume read does not overwrite the newest pending adjustment")
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume) == [Float(0.3), Float(0.8)]
                     && completions == [true, true, true],
                     "one current write and the newest queued level apply once each")

        mixer = make()
        completions = []
        mixer.requestAdjustment(volume: 0.3) { completions.append($0) }
        mixer.requestAdjustment(volume: 0.6) { completions.append($0) }
        hardware.device = 2
        select(mixer, 2, volume: 0.1, muted: true)
        suite.expect(mixer.volume == 0.1 && mixer.muted == true,
                     "the new output publishes its own volume while an old write is pending")
        mixer.requestAdjustment(volume: 0.8) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 2, volume: 0.8, muted: nil),
                                         .init(device: 2, volume: nil, muted: false)],
                     "a new-output adjustment survives completion of the previous output's write")
        suite.expect(completions.count == 3 && completions.allSatisfy { $0 },
                     "discarded old keys settle without replaying onto the new output")

        mixer = make()
        mixer.requestAdjustment(volume: 0.9)
        select(mixer, nil, volume: nil, muted: nil)
        select(mixer, 1, volume: 0.15, muted: false)
        mixer.requestAdjustment(volume: 0.25)
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume) == [Float(0.25)],
                     "reusing a device ID after stop cannot revive a previous lifetime's volume")

        mixer = make()
        var failed: Bool?
        hardware.succeeds = false
        mixer.requestAdjustment(volume: 0.4) { failed = $0 }
        finish(mixer)
        suite.expect(failed == false, "a current-output write failure remains available for native key fallback")
        suite.expect(hardware.later.count == 1, "a failed current write asks for the output's actual state")
        hardware.volume = 0.25
        hardware.advance()
        finish(mixer)
        suite.expect(mixer.volume == 0.25 && hardware.publishedVolume == 0.25,
                     "the output's own level replaces the one that failed to apply")

        // The output's volume listeners fire in bursts; the control reads once
        // after the last one, and only for the output it follows.
        mixer = make()
        hardware.volume = 0.75
        mixer.refresh(1)
        mixer.refresh(1)
        mixer.refresh(2)
        hardware.advance()
        suite.expect(hardware.hal.count == 1, "a burst of output notifications reads the output once")
        finish(mixer)
        suite.expect(mixer.volume == 0.75 && hardware.publishedVolume == 0.75 && hardware.publishedMuted == false,
                     "the reading after a burst reaches the mixer's published state")
        hardware.listening = false
        mixer.refresh(1)
        suite.expect(hardware.later.isEmpty, "a mixer that stopped listening ignores the output's notifications")
        hardware.listening = true
        mixer.refresh(1)
        hardware.advance()
        mixer.requestAdjustment(volume: 0.3)
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume) == [Float(0.3)] && mixer.volume == 0.3,
                     "a reading queued before this control's own write cannot pull the level back")

        mixer = make()
        hardware.volume = 0.75
        mixer.refresh(1)
        hardware.advance()
        select(mixer, 2, volume: 0.1, muted: false)
        finish(mixer)
        suite.expect(mixer.volume == 0.1, "a reading of the previous output is dropped once another is followed")

        mixer = make()
        mixer.refresh(1)
        select(mixer, nil, volume: nil, muted: nil)
        select(mixer, 1, volume: 0.15, muted: false)
        hardware.advance()
        suite.expect(hardware.hal.isEmpty, "a notification from before the output was followed again reads nothing")
        hardware.settable = false
        mixer.refresh(1)
        hardware.advance()
        finish(mixer)
        suite.expect(mixer.volume == nil && mixer.muted == false,
                     "an output whose volume cannot be set reads as having none")

        mixer = make()
        select(mixer, nil, volume: 0.2, muted: false)
        var unfollowed: [Bool] = []
        mixer.requestAdjustment(volume: 0.4) { unfollowed.append($0) }
        mixer.requestStep(level: { $0 }) { unfollowed.append($0) }
        suite.expect(unfollowed == [false, false] && hardware.hal.isEmpty,
                     "with no output followed, adjustments and keys go back to the system")

        mixer = make()
        mixer.requestAdjustment(volume: 1.5)
        finish(mixer)
        mixer.requestAdjustment(volume: -0.5)
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume) == [1, 0] && mixer.volume == 0,
                     "requests beyond the output's range clamp to it")

        mixer = make()
        completions = []
        mixer.requestStep(level: { $0 + 0.25 }) { completions.append($0) }
        finish(mixer)
        mixer.requestStep(level: { $0 + 0.25 }) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume).count == 2 && completions == [true, true],
                     "a key after the previous one finished reads and steps again")

        mixer = make()
        var refusedWrite: Bool?
        mixer.requestAdjustment(volume: 0.4) { refusedWrite = $0 }
        hardware.device = 2
        finish(mixer)
        suite.expect(hardware.writes.isEmpty && refusedWrite == false,
                     "a write for an output that stopped being the default is refused and left to the system")

        mixer = make()
        mixer.requestAdjustment(volume: 0.4)
        hardware.afterVolumeWrite = { select(mixer, 2, volume: 0.1, muted: false) }
        finish(mixer)
        suite.expect(hardware.outputsChanged == 1 && mixer.volume == 0.1,
                     "a write that outlived its output asks the mixer to read the outputs again")

        mixer = make()
        mixer.requestAdjustment(muted: true)
        finish(mixer)
        mixer.adopt(volume: 0)
        suite.expect(mixer.volume == 0 && mixer.muted == true, "a silent level the mixer writes leaves mute on")
        mixer.adopt(volume: 0.5)
        suite.expect(mixer.volume == 0.5 && mixer.muted == false && hardware.publishedMuted == false,
                     "a level the mixer writes itself unmutes the reading")
        mixer.forget()
        var refused: [Bool] = []
        mixer.requestAdjustment(volume: 0.4) { refused.append($0) }
        mixer.requestStep(level: { $0 }) { refused.append($0) }
        suite.expect(mixer.volume == nil && mixer.muted == nil && hardware.publishedVolume == nil
                     && refused == [false, false],
                     "a stopped mixer forgets the reading and leaves the keys to the system")

        mixer = make()
        var settled: [Bool] = []
        mixer.requestAdjustment(volume: 0.4) { settled.append($0) }
        hardware.afterVolumeWrite = {
            hardware.device = 2
            select(mixer, 2, volume: 0.1, muted: true)
            mixer.requestAdjustment(muted: false) { settled.append($0) }
        }
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0.4, muted: nil),
                                         .init(device: 2, volume: nil, muted: false)],
                     "a switch during a driver write preserves the new mute request and skips stale unmute")
        suite.expect(settled == [true, true], "both in-progress and new-output requests settle once")

        func step(_ delta: Double) -> (Double) -> Double { { $0 + delta } }

        mixer = make()
        completions = []
        hardware.volume = 0.02
        mixer.requestStep(level: step(0.01)) { completions.append($0) }
        suite.expect(mixer.volume == 0.2 && hardware.writes.isEmpty,
                     "a volume key waits for the output's own reading before stepping")
        mixer.requestStep(level: step(0.01)) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [3, 4]
                     && completions == [true, true],
                     "keys step from the device's level, not a stale reading from before sleep")

        for directMute in [true, false] {
            mixer = make()
            completions = []
            hardware.volume = 0.7
            mixer.requestStep(level: step(0.1)) { completions.append($0) }
            if directMute {
                mixer.requestAdjustment(muted: true) { completions.append($0) }
            } else {
                mixer.requestAdjustment(volume: 0.35) { completions.append($0) }
            }
            finish(mixer)
            suite.expect(hardware.writes.compactMap(\.volume) == (directMute ? [] : [Float(0.35)])
                         && mixer.muted == directMute
                         && completions == [true, true],
                         "a newer direct \(directMute ? "mute" : "level") supersedes a key awaiting its HAL read")
        }

        mixer = make()
        completions = []
        hardware.volume = 0.7
        mixer.requestStep(level: step(0.1)) { completions.append($0) }
        mixer.requestAdjustment(volume: 0.35) { completions.append($0) }
        mixer.requestStep(level: step(0.1)) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [35, 45]
                     && completions == [true, true, true],
                     "a key after a direct level change follows that level rather than the stale HAL read")

        for directMute in [true, false] {
            mixer = make()
            completions = []
            hardware.volume = nil
            mixer.requestStep(level: step(0.1)) { completions.append($0) }
            if directMute {
                mixer.requestAdjustment(muted: true) { completions.append($0) }
            } else {
                mixer.requestAdjustment(volume: 0.35) { completions.append($0) }
            }
            mixer.requestStep(level: step(0.1)) { completions.append($0) }
            finish(mixer)
            suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() }
                            == (directMute ? [10] : [35, 45])
                         && mixer.muted == false
                         && completions == [true, true, true],
                         "a key after a direct \(directMute ? "mute" : "level") follows it when the superseded read fails")
        }

        mixer = make()
        completions = []
        hardware.volume = 0.5
        mixer.requestAdjustment(volume: 0.3) { completions.append($0) }
        mixer.requestStep(level: step(0.1)) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 10).rounded() } == [3, 4],
                     "a key during this app's own write continues from the level it requested")

        mixer = make()
        completions = []
        hardware.volume = 0.4
        hardware.muted = true
        mixer.requestStep(level: step(0.1)) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes.first?.volume.map { ($0 * 10).rounded() } == 1
                     && mixer.muted == false,
                     "a key on a muted output steps up from silence and unmutes")

        mixer = make()
        completions = []
        for _ in 0..<3 { mixer.requestStep(level: step(0.1)) { completions.append($0) } }
        hardware.device = 2
        finish(mixer)
        suite.expect(hardware.writes.isEmpty && completions == [true, true, true] && hardware.outputsChanged == 1,
                     "keys piled up for an output that is no longer the default settle instead of replaying natively")

        mixer = make()
        completions = []
        for _ in 0..<3 { mixer.requestStep(level: step(0.1)) { completions.append($0) } }
        hardware.device = 2
        select(mixer, 2, volume: 0.1, muted: false)
        finish(mixer)
        suite.expect(hardware.writes.isEmpty && completions == [true, true, true],
                     "keys whose output was replaced during the read never step the output that took over")

        for oldReadFinished in [false, true] {
            mixer = make()
            completions = []
            mixer.requestStep(level: step(0.1)) { completions.append($0) }
            if oldReadFinished { hardware.runHAL() }
            hardware.device = 2
            hardware.volume = 0.4
            select(mixer, 2, volume: 0.4, muted: false)
            mixer.requestStep(level: step(0.1)) { completions.append($0) }
            finish(mixer)
            suite.expect(hardware.writes.compactMap { write in
                write.volume.map { (write.device, Int(($0 * 10).rounded())) }
            }.contains { $0 == (2, 5) } && completions == [true, true],
                         "a key on the new output survives an old read, including one awaiting its main callback")
        }

        mixer = make()
        completions = []
        hardware.volume = nil
        mixer.requestStep(level: step(0.1)) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes.isEmpty && completions == [false],
                     "an output without software volume leaves the key to the system")

        mixer = make()
        completions = []
        hardware.muted = true
        mixer.requestMuteToggle { completions.append($0) }
        suite.expect(mixer.muted == false && hardware.writes.isEmpty,
                     "the mute key waits for the output's own reading before toggling")
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: nil, muted: false)] && completions == [true],
                     "the mute key toggles the device's state, not a stale reading from before sleep")

        mixer = make()
        completions = []
        mixer.requestMuteToggle { completions.append($0) }
        mixer.requestMuteToggle { completions.append($0) }
        finish(mixer)
        suite.expect(mixer.muted == false && completions == [true, true],
                     "two quick mute presses cancel out instead of both reading the same state")

        mixer = make()
        completions = []
        hardware.muted = true
        hardware.volume = 0.02
        mixer.requestMuteToggle { completions.append($0) }
        mixer.requestStep(level: step(0.01)) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [3]
                     && mixer.muted == false && completions == [true, true],
                     "a volume key right after an unmuting press steps from the level the same read fetched")

        mixer = make()
        completions = []
        hardware.volume = nil
        mixer.requestMuteToggle { completions.append($0) }
        mixer.requestStep(level: step(0.1)) { completions.append($0) }
        finish(mixer)
        suite.expect(completions.count == 2 && completions.filter { $0 }.count == 1 && mixer.muted == true,
                     "an output with mute but no software volume still toggles mute and leaves volume to the system")

        mixer = make()
        completions = []
        mixer.requestMuteToggle { completions.append($0) }
        mixer.requestStep(level: step(0.1)) { completions.append($0) }
        hardware.device = 2
        finish(mixer)
        suite.expect(hardware.writes.isEmpty && completions == [false, true] && hardware.outputsChanged == 1,
                     "a mute key for an output that is no longer the default goes back to the system while its volume keys settle")

        mixer = make()
        completions = []
        mixer.requestMuteToggle { completions.append($0) }
        hardware.runHAL()
        hardware.device = 2
        hardware.volume = 0.4
        hardware.muted = true
        select(mixer, 2, volume: 0.4, muted: true)
        mixer.requestMuteToggle { completions.append($0) }
        mixer.requestStep(level: step(0.1)) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes.contains { $0.device == 2 && $0.muted == false }
                     && hardware.writes.contains { $0.device == 2 && $0.volume == 0.5 }
                     && completions == [true, true, true],
                     "an old mute read cannot swallow the new output's mute and volume keys")

        mixer = make()
        completions = []
        for value in [Double.nan, .infinity, -.infinity] {
            mixer.requestAdjustment(volume: value) { completions.append($0) }
        }
        suite.expect(completions == [false, false, false] && hardware.hal.isEmpty,
                     "nonfinite output requests never reach the driver")
    }
}
