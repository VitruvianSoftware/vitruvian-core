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
        /// The level a volume write lands on. Nil accepts the requested level.
        var accepts: ((Float32) -> Float32)?
        var settable = true
        var muted: Bool? = false
        /// A simulated HAL conversion, independent of whether writes are applied.
        /// Nil means identity; a closure may return nil for unavailable conversion.
        var quantizes: ((Float32) -> Float32?)?
        var supportsScalarConversion = true
        var requiresQuantizedKeys = false
        var scalarWrites = 0
        var queries: [Float32] = []
        var uptime: TimeInterval = 0
        var volumeReads = 0
        var muteReads = 0
        var readVolume: (() -> Float32?)?
        var readMute: (() -> Bool?)?
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
            @Sendable func writeVolume(_ value: Float32, _ device: AudioObjectID) -> Bool {
                machine.writes.append(.init(device: device, volume: value, muted: nil))
                if machine.succeeds { machine.volume = machine.accepts?(value) ?? value }
                let after = machine.afterVolumeWrite
                machine.afterVolumeWrite = nil
                after?()
                return machine.succeeds
            }
            let control = MixerOutputControl(host: .init(
                hal: { machine.hal.append($0) },
                halAfter: { _, work in machine.hal.append(work) },
                main: { machine.main.append($0) },
                after: { _, work in machine.later.append(work) },
                defaultOutput: { machine.device },
                volumeIsSettable: { _ in machine.settable },
                volume: { _ in
                    machine.volumeReads += 1
                    if let read = machine.readVolume { return read() }
                    return machine.volume
                },
                muted: { _ in
                    machine.muteReads += 1
                    if let read = machine.readMute { return read() }
                    return machine.muted
                },
                setVolume: { value, device in writeVolume(value, device) },
                setVolumeWithoutFallback: { value, device in writeVolume(value, device) },
                setMuted: { value, device in
                    guard machine.muted != nil else { return false }
                    machine.writes.append(.init(device: device, volume: nil, muted: value))
                    if machine.succeeds { machine.muted = value }
                    return machine.succeeds
                },
                requiresQuantizedKeys: { _ in machine.requiresQuantizedKeys },
                hasSettableScalar: { _, _ in machine.supportsScalarConversion },
                quantizedVolume: { value, _ in
                    let level = Float32(value)
                    machine.queries.append(level)
                    if let quantizes = machine.quantizes { return quantizes(level).map(Double.init) }
                    return Double(level)
                },
                setScalarVolume: { value, device in
                    machine.scalarWrites += 1
                    return writeVolume(Float32(value), device)
                },
                uptime: { machine.uptime },
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
        hardware.volume = 0.02
        var zeroResult: Bool?
        mixer.requestStep(level: { $0 - 0.1 }) { zeroResult = $0.handled }
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: true)]
                     && mixer.volume == 0 && mixer.muted == true && zeroResult == true,
                     "a volume key that reaches or crosses zero mutes the output")
        hardware.volume = 0
        hardware.muted = true
        hardware.writes = []
        mixer.requestStep(level: { $0 + 0.1 })
        finish(mixer)
        suite.expect(hardware.writes.last?.muted == false
                     && mixer.volume == 0.1 && mixer.muted == false,
                     "the next positive volume key unmutes an output muted at zero")

        mixer = make()
        hardware.muted = nil
        select(mixer, 1, volume: 0.2, muted: nil)
        mixer.requestAdjustment(volume: 0)
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0, muted: nil)],
                     "zero volume on an output without mute writes only the volume")

        mixer = make()
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
        mixer.requestStep(level: { $0 }) { unfollowed.append($0.handled) }
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
        mixer.requestStep(level: { $0 + 0.25 }) { completions.append($0.handled) }
        finish(mixer)
        mixer.requestStep(level: { $0 + 0.25 }) { completions.append($0.handled) }
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
        mixer.requestAdjustment(volume: 0)
        suite.expect(mixer.volume == 0 && mixer.muted == true, "a silent level the mixer writes leaves mute on")
        finish(mixer)
        mixer.requestAdjustment(volume: 0.5)
        suite.expect(mixer.volume == 0.5 && mixer.muted == false,
                     "a level the mixer writes itself unmutes the reading")
        finish(mixer)
        suite.expect(hardware.publishedMuted == false, "the unmuted reading reaches the mixer's published state")
        mixer.forget()
        var refused: [Bool] = []
        mixer.requestAdjustment(volume: 0.4) { refused.append($0) }
        mixer.requestStep(level: { $0 }) { refused.append($0.handled) }
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
        mixer.requestStep(level: step(0.01)) { completions.append($0.handled) }
        suite.expect(mixer.volume == 0.2 && hardware.writes.isEmpty,
                     "a volume key waits for the output's own reading before stepping")
        mixer.requestStep(level: step(0.01)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [3, 4]
                     && completions == [true, true],
                     "keys step from the device's level, not a stale reading from before sleep")

        for directMute in [true, false] {
            mixer = make()
            completions = []
            hardware.volume = 0.7
            mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
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
        mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
        mixer.requestAdjustment(volume: 0.35) { completions.append($0) }
        mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [35, 45]
                     && completions == [true, true, true],
                     "a key after a direct level change follows that level rather than the stale HAL read")

        for directMute in [true, false] {
            mixer = make()
            completions = []
            hardware.volume = nil
            mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
            if directMute {
                mixer.requestAdjustment(muted: true) { completions.append($0) }
            } else {
                mixer.requestAdjustment(volume: 0.35) { completions.append($0) }
            }
            mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
            finish(mixer)
            suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() }
                            == (directMute ? [] : [35, 45])
                         && mixer.muted == directMute
                         && completions == (directMute ? [true, true, false] : [true, true, true]),
                         "after a direct \(directMute ? "mute" : "level"), a key uses a fresh reading or falls back when volume is unavailable")
        }

        mixer = make()
        completions = []
        hardware.volume = 0.5
        mixer.requestAdjustment(volume: 0.3) { completions.append($0) }
        mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 10).rounded() } == [3, 4],
                     "a key during this app's own write continues from the level it requested")

        mixer = make()
        completions = []
        hardware.volume = 0.4
        hardware.muted = true
        mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(hardware.writes.first?.volume.map { ($0 * 10).rounded() } == 1
                     && mixer.muted == false,
                     "a key on a muted output steps up from silence and unmutes")

        // An output that takes only a few levels, like USB speakers that step
        // in 3 dB: a write lands on the nearest one, so a key's step can come
        // back to the level it started from.
        let coarseLevels: [Float32] = [0, 0.05, 0.12, 0.2, 0.3, 0.45, 0.65, 1]
        func coarse(_ value: Float32) -> Float32 {
            coarseLevels.min { abs($0 - value) < abs($1 - value) }!
        }
        func press(_ mixer: MixerOutputControl, _ delta: Double, times: Int) -> [Float32?] {
            (0..<times).map { _ in
                mixer.requestStep(level: step(delta))
                finish(mixer)
                return hardware.volume
            }
        }

        mixer = make()
        hardware.accepts = coarse
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { coarse($0) }
        hardware.volume = 0.3
        suite.expect(press(mixer, 1.0 / 16, times: 4) == [0.45, 0.65, 1, 1],
                     "every volume-up press advances a coarse output until full volume")

        mixer = make()
        hardware.accepts = coarse
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { coarse($0) }
        hardware.volume = 1
        suite.expect(press(mixer, -1.0 / 16, times: 3) == [0.65, 0.45, 0.3],
                     "every volume-down press advances a coarse output, including the first press at full volume")

        mixer = make()
        hardware.accepts = coarse
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { coarse($0) }
        hardware.volume = 0.3
        _ = press(mixer, 1.0 / 16, times: 1)
        hardware.volume = 0.05
        hardware.writes = []
        _ = press(mixer, 1.0 / 16, times: 1)
        suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 10000).rounded() } == [1200],
                     "a key steps from a level the output moved to on its own, not from a step it rounded back")

        mixer = make()
        hardware.accepts = coarse
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { coarse($0) }
        hardware.volume = 0.3
        _ = press(mixer, 1.0 / 16, times: 1)
        mixer.requestAdjustment(volume: 0.3)
        finish(mixer)
        hardware.writes = []
        _ = press(mixer, 1.0 / 16, times: 1)
        suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 10000).rounded() } == [4500],
                     "a direct level change starts the next key from that level")

        mixer = make()
        hardware.accepts = coarse
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { coarse($0) }
        hardware.volume = 0.3
        _ = press(mixer, 1.0 / 16, times: 1)
        mixer.apply(volume: 0.3, muted: false)
        suite.expect(press(mixer, 1.0 / 16, times: 1) == [0.65],
                     "a stale snapshot cannot undo the accepted level the next key reads from the device")

        mixer = make()
        hardware.accepts = coarse
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { coarse($0) }
        hardware.volume = 0.3
        _ = press(mixer, 1.0 / 16, times: 1)
        suite.expect(press(mixer, -1.0 / 16, times: 1) == [0.3],
                     "reversing direction returns to the previous hardware level in one press")

        mixer = make()
        hardware.accepts = { $0 }
        hardware.volume = 0.5
        _ = press(mixer, 1.0 / 16, times: 1)
        mixer.apply(volume: 0.5625, muted: false)
        hardware.volume = 0.5
        hardware.writes = []
        _ = press(mixer, 1.0 / 16, times: 1)
        suite.expect(hardware.writes.compactMap(\.volume) == [0.5625],
                     "a step the output took carries nothing over after another control returns it to where the key started")

        mixer = make()
        hardware.accepts = { $0 }
        hardware.volume = 0.5
        _ = press(mixer, 1.0 / 16, times: 1)
        mixer.requestAdjustment(volume: 0.5)
        finish(mixer)
        hardware.writes = []
        _ = press(mixer, 1.0 / 16, times: 1)
        suite.expect(hardware.writes.compactMap(\.volume) == [0.5625],
                     "a level set from the menu bar before the step's own reading starts the next key from that level")

        mixer = make()
        hardware.accepts = coarse
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { coarse($0) }
        hardware.volume = 0.3
        hardware.succeeds = false
        _ = press(mixer, 1.0 / 16, times: 1)
        hardware.succeeds = true
        hardware.writes = []
        var nextAfterRefusal: MixerOutputControl.KeyResult?
        mixer.requestStep(level: step(1.0 / 16)) { nextAfterRefusal = $0 }
        finish(mixer)
        suite.expect(nextAfterRefusal == .fallback && hardware.writes.isEmpty,
                     "a refused write keeps later keys native even when the driver recovers")

        for delta in [1.0 / 16, 1.0 / 64, -1.0 / 16, -1.0 / 64] {
            for initial in coarseLevels {
                mixer = make()
                hardware.accepts = coarse
                hardware.requiresQuantizedKeys = true
                hardware.quantizes = { coarse($0) }
                hardware.volume = initial
                var accepted: MixerOutputControl.KeyResult?
                mixer.requestStep(level: step(delta)) { accepted = $0 }
                finish(mixer)
                let actual = Double(hardware.volume!)
                let atLimit = delta > 0 ? initial == 1 : initial == 0
                suite.expect(accepted == .applied && (atLimit || (actual - Double(initial)) * delta > 0),
                             "one \(delta) key moves the hardware from \(initial), unless already at its endpoint")
                suite.expectClose(mixer.volume ?? -1, actual,
                                  "feedback shows the accepted hardware level")
                suite.expect(hardware.writes.compactMap(\.volume).count <= 1 && hardware.queries.count <= 11
                             && hardware.scalarWrites == hardware.writes.compactMap(\.volume).count,
                             "a coarse or fine key plans with bounded conversions and writes volume at most once")
            }
        }

        mixer = make()
        hardware.accepts = coarse
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { coarse($0) }
        hardware.volume = 0.3
        var burstLevels: [Double] = []
        for _ in 0..<3 {
            mixer.requestStep(level: step(1.0 / 16)) { applied in
                suite.expect(applied == .applied, "each key in a burst completes successfully")
                burstLevels.append(mixer.volume ?? -1)
            }
        }
        finish(mixer)
        suite.expect(burstLevels.map { ($0 * 100).rounded() } == [45, 65, 100],
                     "queued keys each advance from the hardware level accepted by the previous key")

        mixer = make()
        hardware.accepts = { _ in 0.3 }
        hardware.volume = 0.3
        var ignored: MixerOutputControl.KeyResult?
        mixer.requestStep(level: step(1.0 / 64)) { ignored = $0 }
        finish(mixer)
        suite.expect(ignored == .unconfirmed && hardware.writes.compactMap(\.volume).count == 1
                     && !hardware.writes.contains { $0.muted != nil },
                     "an ignored successful write is not retried, unmuted or replayed natively")

        mixer = make()
        hardware.accepts = coarse
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { coarse($0) }
        hardware.volume = 0.3
        hardware.afterVolumeWrite = {
            hardware.device = 2
            select(mixer, 2, volume: 0.2, muted: false)
        }
        mixer.requestStep(level: step(1.0 / 64))
        finish(mixer)
        suite.expect(hardware.writes.count == 1 && hardware.writes[0].device == 1,
                     "switching output during a rounded write stops further attempts and skips stale mute")

        // A level of zero also throws the mute switch, as the system's own
        // keys and the Control Center slider do, because the bottom of the
        // range alone is not silence on every output.
        mixer = make()
        completions = []
        mixer.requestAdjustment(volume: 0) { completions.append($0) }
        suite.expect(mixer.volume == 0 && mixer.muted == true,
                     "a level of zero publishes the output as muted before the driver confirms it")
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: true)]
                     && completions == [true],
                     "a level of zero writes the level and then mutes the output, as the system's own keys do")

        mixer = make()
        completions = []
        hardware.volume = 0.015625
        mixer.requestStep(level: { NotchSupport.volumeLevel(current: $0, direction: -1, fine: true) }) {
            completions.append($0.handled)
        }
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: true)]
                     && mixer.muted == true && completions == [true],
                     "a volume key stepping down to zero mutes the output and stays handled")
        hardware.volume = 0
        hardware.muted = true
        mixer.requestStep(level: { NotchSupport.volumeLevel(current: $0, direction: 1, fine: false) }) {
            completions.append($0.handled)
        }
        finish(mixer)
        suite.expect(Array(hardware.writes.suffix(2)) == [.init(device: 1, volume: 0.0625, muted: nil),
                                                          .init(device: 1, volume: nil, muted: false)]
                     && mixer.muted == false && completions == [true, true],
                     "a volume key from muted zero unmutes and steps up to the first level")

        mixer = make()
        completions = []
        hardware.volume = 0.03125
        mixer.requestStep(level: { NotchSupport.volumeLevel(current: $0, direction: -1, fine: true) }) {
            completions.append($0.handled)
        }
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0.015625, muted: nil)]
                     && mixer.muted == false && completions == [true],
                     "the finest key step above zero keeps the output audible")

        mixer = make()
        completions = []
        hardware.volume = 0.0627
        mixer.requestStep(level: { NotchSupport.volumeLevel(current: $0, direction: -1, fine: false) }) {
            completions.append($0.handled)
        }
        finish(mixer)
        suite.expect(hardware.writes.map(\.muted) == [nil, true]
                     && mixer.muted == true && completions == [true],
                     "a coarse key step from a reading a hair above one step lands on 0% and mutes")

        mixer = make()
        completions = []
        hardware.muted = nil
        select(mixer, 1, volume: 0.2, muted: nil)
        mixer.requestAdjustment(volume: 0) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0, muted: nil)]
                     && completions == [true] && mixer.muted == nil,
                     "an output without a mute switch takes the zero level alone and reports the request handled")

        mixer = make()
        completions = []
        mixer.requestAdjustment(volume: 0.5) { completions.append($0) }
        mixer.requestAdjustment(volume: 0.3) { completions.append($0) }
        mixer.requestAdjustment(volume: 0) { completions.append($0) }
        suite.expect(mixer.muted == true, "a drag that ends at zero publishes the output as muted")
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0.5, muted: nil),
                                         .init(device: 1, volume: nil, muted: false),
                                         .init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: true)]
                     && completions == [true, true, true],
                     "a drag that ends at zero mutes even when it coalesces with an audible level")

        mixer = make()
        completions = []
        mixer.requestAdjustment(volume: 0.5) { completions.append($0) }
        mixer.requestAdjustment(volume: 0) { completions.append($0) }
        mixer.requestAdjustment(volume: 0.1) { completions.append($0) }
        suite.expect(mixer.volume == 0.1 && mixer.muted == false,
                     "a drag through zero and back up publishes the audible level unmuted")
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0.5, muted: nil),
                                         .init(device: 1, volume: nil, muted: false),
                                         .init(device: 1, volume: 0.1, muted: nil),
                                         .init(device: 1, volume: nil, muted: false)]
                     && completions == [true, true, true],
                     "a drag through zero and back up drains once, unmuted at the level it ends on")

        mixer = make()
        completions = []
        mixer.requestAdjustment(volume: 0, muted: false) { completions.append($0) }
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                         .init(device: 1, volume: nil, muted: false)]
                     && mixer.muted == false && completions == [true],
                     "an explicit mute request wins over the one a level of zero implies")

        // Direct slider requests use the serialized queue; the command bar
        // keeps its standalone synchronous volume API.
        mixer = make()
        mixer.requestAdjustment(volume: 0)
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0, muted: nil),
                                            .init(device: 1, volume: nil, muted: true)]
                     && mixer.volume == 0 && mixer.muted == true,
                     "the panel's slider at zero mutes the output and publishes it")
        hardware.writes = []
        mixer.requestAdjustment(volume: 0.3)
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0.3, muted: nil),
                                            .init(device: 1, volume: nil, muted: false)]
                     && mixer.muted == false,
                     "the panel's slider above zero unmutes the output")

        mixer = make()
        hardware.muted = nil
        select(mixer, 1, volume: 0.2, muted: nil)
        mixer.requestAdjustment(volume: 0)
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0, muted: nil)]
                     && mixer.muted == nil,
                     "the panel's slider at zero invents no mute state for an output without a mute switch")

        mixer = make()
        mixer.requestAdjustment(volume: 0.004)
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0.004, muted: nil),
                                            .init(device: 1, volume: nil, muted: true)]
                     && mixer.muted == true,
                     "the panel's slider at a level the labels show as 0% mutes the output")

        mixer = make()
        mixer.requestAdjustment(volume: 0.005)
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: 0.005, muted: nil),
                                            .init(device: 1, volume: nil, muted: false)]
                     && mixer.muted == false,
                     "the panel's slider at the first level the labels show as 1% keeps the output audible")


        mixer = make()
        completions = []
        for _ in 0..<3 { mixer.requestStep(level: step(0.1)) { completions.append($0.handled) } }
        hardware.device = 2
        finish(mixer)
        suite.expect(hardware.writes.isEmpty && completions == [true, true, true] && hardware.outputsChanged == 1,
                     "keys piled up for an output that is no longer the default settle instead of replaying natively")

        mixer = make()
        completions = []
        for _ in 0..<3 { mixer.requestStep(level: step(0.1)) { completions.append($0.handled) } }
        hardware.device = 2
        select(mixer, 2, volume: 0.1, muted: false)
        finish(mixer)
        suite.expect(hardware.writes.isEmpty && completions == [true, true, true],
                     "keys whose output was replaced during the read never step the output that took over")

        for oldReadFinished in [false, true] {
            mixer = make()
            completions = []
            mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
            if oldReadFinished { hardware.runHAL() }
            hardware.device = 2
            hardware.volume = 0.4
            select(mixer, 2, volume: 0.4, muted: false)
            mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
            finish(mixer)
            suite.expect(hardware.writes.compactMap { write in
                write.volume.map { (write.device, Int(($0 * 10).rounded())) }
            }.contains { $0 == (2, 5) } && completions == [true, true],
                         "a key on the new output survives an old read, including one awaiting its main callback")
        }

        mixer = make()
        completions = []
        hardware.volume = nil
        mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(hardware.writes.isEmpty && completions == [false],
                     "an output without software volume leaves the key to the system")

        mixer = make()
        completions = []
        hardware.muted = true
        mixer.requestMuteToggle { completions.append($0.handled) }
        suite.expect(mixer.muted == false && hardware.writes.isEmpty,
                     "the mute key waits for the output's own reading before toggling")
        finish(mixer)
        suite.expect(hardware.writes == [.init(device: 1, volume: nil, muted: false)] && completions == [true],
                     "the mute key toggles the device's state, not a stale reading from before sleep")

        mixer = make()
        completions = []
        mixer.requestMuteToggle { completions.append($0.handled) }
        mixer.requestMuteToggle { completions.append($0.handled) }
        finish(mixer)
        suite.expect(mixer.muted == false && completions == [true, true],
                     "two quick mute presses cancel out instead of both reading the same state")

        mixer = make()
        completions = []
        hardware.muted = true
        hardware.volume = 0.02
        mixer.requestMuteToggle { completions.append($0.handled) }
        mixer.requestStep(level: step(0.01)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(hardware.writes.compactMap(\.volume).map { ($0 * 100).rounded() } == [3]
                     && mixer.muted == false && completions == [true, true],
                     "a volume key right after an unmuting press steps from the level the same read fetched")

        mixer = make()
        completions = []
        hardware.volume = nil
        mixer.requestMuteToggle { completions.append($0.handled) }
        mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(completions.count == 2 && completions.filter { $0 }.count == 1 && mixer.muted == true,
                     "an output with mute but no software volume still toggles mute and leaves volume to the system")

        mixer = make()
        var replacedOutputKeys: [MixerOutputControl.KeyResult] = []
        mixer.requestMuteToggle { replacedOutputKeys.append($0) }
        mixer.requestStep(level: step(0.1)) { replacedOutputKeys.append($0) }
        hardware.device = 2
        finish(mixer)
        suite.expect(hardware.writes.isEmpty && replacedOutputKeys == [.superseded, .superseded]
                     && hardware.outputsChanged == 1,
                     "mute and volume for a replaced output are consumed without native replay onto its replacement")

        mixer = make()
        completions = []
        mixer.requestMuteToggle { completions.append($0.handled) }
        hardware.runHAL()
        hardware.device = 2
        hardware.volume = 0.4
        hardware.muted = true
        select(mixer, 2, volume: 0.4, muted: true)
        mixer.requestMuteToggle { completions.append($0.handled) }
        mixer.requestStep(level: step(0.1)) { completions.append($0.handled) }
        finish(mixer)
        suite.expect(hardware.writes.contains { $0.device == 2 && $0.muted == false }
                     && hardware.writes.contains { $0.device == 2 && $0.volume == 0.5 }
                     && completions == [true, true, true],
                     "an old mute read cannot swallow the new output's mute and volume keys")

        // Conversion describes the driver's levels; it is deliberately separate
        // from write acceptance so an ignored write cannot confirm itself.
        mixer = make()
        hardware.volume = 0.3
        hardware.muted = true
        hardware.accepts = coarse
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { coarse($0) }
        var keyResult: MixerOutputControl.KeyResult?
        mixer.requestStep(level: step(1.0 / 64)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && hardware.volume == 0.05 && hardware.muted == false,
                     "one fine key from muted nonzero volume reaches the first audible coarse level")
        suite.expect(hardware.writes.compactMap(\.volume) == [0.05] && hardware.scalarWrites == 1
                     && hardware.writes.last?.muted == false,
                     "coarse unmute plans its level before the only volume write")

        mixer = make()
        hardware.volume = 0.3
        hardware.muted = true
        keyResult = nil
        mixer.requestStep(level: step(-1.0 / 64)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && hardware.volume == 0.3 && hardware.muted == true
                     && hardware.writes.isEmpty,
                     "volume down while muted preserves the stored level without another write")

        mixer = make()
        hardware.volume = 0.05
        let floorLevels: [Float32] = [0.05, 0.12, 0.3, 1]
        let floor: (Float32) -> Float32 = { value in
            floorLevels.min { abs($0 - value) < abs($1 - value) }!
        }
        hardware.accepts = floor
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { floor($0) }
        keyResult = nil
        mixer.requestStep(level: step(-1.0 / 64)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && hardware.volume == 0.05 && hardware.muted == true
                     && !hardware.writes.contains { $0.muted == false },
                     "reaching the bottom mutes even when the driver's minimum scalar is positive")

        mixer = make()
        hardware.volume = 0.9
        hardware.muted = true
        hardware.accepts = { _ in 0.9 }
        keyResult = nil
        mixer.requestStep(level: step(1.0 / 64)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .unconfirmed && hardware.muted == true
                     && hardware.writes.compactMap(\.volume).count == 1
                     && !hardware.writes.contains { $0.muted != nil },
                     "an ignored fine key never unmutes at the old high stored volume")
        suite.expectClose(mixer.volume ?? -1, 0.9,
                          "an unconfirmed key leaves no optimistic target in the published volume")

        for missingControl in [true, false] {
            mixer = make()
            hardware.requiresQuantizedKeys = true
            hardware.supportsScalarConversion = !missingControl
            if !missingControl { hardware.quantizes = { _ in nil } }
            keyResult = nil
            mixer.requestStep(level: step(1.0 / 16)) { keyResult = $0 }
            finish(mixer)
            suite.expect(keyResult == .fallback && hardware.writes.isEmpty,
                         "missing scalar control or conversion returns the key before writing")
        }

        mixer = make()
        hardware.supportsScalarConversion = false
        hardware.quantizes = { _ in nil }
        keyResult = nil
        mixer.requestStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && hardware.queries.isEmpty && hardware.scalarWrites == 0
                     && hardware.writes.compactMap(\.volume).count == 1,
                     "ordinary outputs keep native virtual-volume control without a USB conversion")

        for delta in [1.0 / 16, -1.0 / 16] {
            mixer = make()
            hardware.accepts = { ($0 * 100).rounded() / 100 }
            keyResult = nil
            mixer.requestStep(level: step(delta)) { keyResult = $0 }
            finish(mixer)
            suite.expect(keyResult == .applied && hardware.scalarWrites == 0
                         && hardware.writes.compactMap(\.volume).count == 1 && hardware.queries.isEmpty,
                         "ordinary outputs confirm a rounded readback without USB conversion or another write")
            suite.expectClose(mixer.volume ?? -1, delta > 0 ? 0.26 : 0.14,
                              "ordinary output feedback publishes the accepted rounded level")
        }

        mixer = make()
        hardware.volume = 0.5
        hardware.muted = true
        hardware.accepts = { ($0 * 100).rounded() / 100 }
        keyResult = nil
        mixer.requestStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && hardware.volume == 0.06 && hardware.muted == false
                     && hardware.writes.compactMap(\.volume) == [0.0625],
                     "an ordinary output may unmute after confirming a nearby rounded low level")
        suite.expectClose(mixer.volume ?? -1, 0.06,
                          "rounded unmute feedback uses the hardware level")

        mixer = make()
        hardware.requiresQuantizedKeys = true
        keyResult = nil
        mixer.requestStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .fallback && hardware.writes.isEmpty,
                     "a continuous USB conversion is not treated as evidence of hardware quantization")

        for replacement in [AudioObjectID(1), AudioObjectID(2)] {
            mixer = make()
            hardware.requiresQuantizedKeys = true
            var keyResults: [MixerOutputControl.KeyResult] = []
            mixer.requestStep(level: step(1.0 / 16)) { keyResults.append($0) }
            mixer.requestMuteToggle { keyResults.append($0) }
            finish(mixer)
            suite.expect(keyResults == [.fallback, .fallback] && hardware.writes.isEmpty,
                         "mute follows a continuous USB volume key into native handling instead of overtaking it")

            hardware.device = replacement
            hardware.volume = 0.4
            hardware.requiresQuantizedKeys = false
            select(mixer, replacement, volume: 0.4, muted: false)
            keyResults = []
            mixer.requestStep(level: step(0.1)) { keyResults.append($0) }
            mixer.requestMuteToggle { keyResults.append($0) }
            finish(mixer)
            suite.expect(keyResults == [.applied, .applied] && hardware.volume == 0.5
                         && hardware.muted == true && hardware.writes.allSatisfy { $0.device == replacement },
                         "a new output lifetime clears native-only key handling, including a reused device ID")
        }

        mixer = make()
        hardware.succeeds = false
        var keysAfterWriteFailure: [MixerOutputControl.KeyResult] = []
        mixer.requestStep(level: step(0.1)) {
            keysAfterWriteFailure.append($0)
            hardware.succeeds = true
        }
        mixer.requestMuteToggle { keysAfterWriteFailure.append($0) }
        finish(mixer)
        suite.expect(keysAfterWriteFailure == [.fallback, .fallback]
                     && hardware.writes.count == 1 && hardware.writes[0].volume != nil
                     && hardware.writes[0].muted == nil && hardware.muted == false,
                     "mute stays native after a failed volume write even when the driver recovers before the next key")

        mixer = make()
        var validAfterInvalid: [MixerOutputControl.KeyResult] = []
        mixer.requestStep(level: { _ in .nan }) { validAfterInvalid.append($0) }
        mixer.requestStep(level: step(0.1)) { validAfterInvalid.append($0) }
        finish(mixer)
        suite.expect(validAfterInvalid == [.fallback, .applied]
                     && hardware.writes.compactMap(\.volume).count == 1,
                     "an invalid key target does not strand the next valid key in the queue")
        suite.expectClose(mixer.volume ?? -1, 0.3,
                          "the valid key after an invalid target still publishes its accepted level")

        for invalid in [Float32.nan, .infinity, -0.1, 1.1] {
            mixer = make()
            hardware.requiresQuantizedKeys = true
            hardware.quantizes = { _ in invalid }
            keyResult = nil
            mixer.requestStep(level: step(1.0 / 16)) { keyResult = $0 }
            finish(mixer)
            suite.expect(keyResult == .fallback && hardware.writes.isEmpty,
                         "an invalid converted scalar never reaches the output")
        }

        mixer = make()
        hardware.volume = 0.3
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { $0 <= 0.4 ? 0.3 : 0.2 }
        keyResult = nil
        mixer.requestStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .fallback && hardware.writes.isEmpty && hardware.queries.count <= 11,
                     "a conversion that reverses direction cannot authorize a volume write")

        mixer = make()
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = {
            if abs($0 - 0.2) < 0.002 { return 0.2 }
            if abs($0 - 0.3) < 0.0001 { return 0.4 }
            return 0.3
        }
        keyResult = nil
        mixer.requestStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .fallback && hardware.writes.isEmpty,
                     "a conversion that cannot represent its own predicted level is rejected")

        mixer = make()
        hardware.requiresQuantizedKeys = true
        hardware.quantizes = { value in hardware.uptime += 0.06; return value }
        keyResult = nil
        mixer.requestStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .fallback && hardware.queries.count == 1 && hardware.writes.isEmpty,
                     "a conversion that exhausts the time budget starts no further query or write")

        mixer = make()
        var missingReads = 0
        hardware.afterVolumeWrite = {
            hardware.readVolume = { missingReads += 1; return nil }
        }
        keyResult = nil
        mixer.requestStep(level: step(0.1)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .unconfirmed && missingReads > 0 && missingReads <= 4
                     && hardware.writes.compactMap(\.volume).count == 1
                     && !hardware.writes.contains { $0.muted != nil },
                     "missing readback uses bounded reads without another write, mute or native fallback")
        suite.expectClose(mixer.volume ?? -1, 0.2,
                          "missing readback does not publish the requested key target")

        mixer = make()
        hardware.afterVolumeWrite = { hardware.readVolume = { 0.2 } }
        var keysAfterTimeout: [MixerOutputControl.KeyResult] = []
        mixer.requestStep(level: step(0.1)) {
            keysAfterTimeout.append($0)
            hardware.readVolume = nil
        }
        mixer.requestStep(level: step(0.1)) { keysAfterTimeout.append($0) }
        mixer.requestMuteToggle { keysAfterTimeout.append($0) }
        finish(mixer)
        suite.expect(keysAfterTimeout == [.unconfirmed, .fallback, .fallback]
                     && hardware.writes.count == 1 && hardware.writes[0].volume != nil
                     && hardware.writes[0].muted == nil,
                     "an accepted write that times out is not replayed and later volume and mute keys stay native")

        mixer = make()
        var delayedReads = 0
        hardware.afterVolumeWrite = {
            hardware.readVolume = {
                delayedReads += 1
                return delayedReads < 3 ? 0.2 : hardware.volume
            }
        }
        keyResult = nil
        mixer.requestStep(level: step(0.1)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && delayedReads == 3
                     && hardware.writes.compactMap(\.volume).count == 1,
                     "delayed volume confirmation rechecks the original write instead of advancing it")
        suite.expectClose(mixer.volume ?? -1, 0.3,
                          "a delayed key publishes only the level confirmed by the driver")

        mixer = make()
        var delayedMuteReads = 0
        hardware.readMute = {
            guard hardware.writes.contains(where: { $0.muted != nil }) else { return hardware.muted }
            delayedMuteReads += 1
            return delayedMuteReads < 3 ? false : hardware.muted
        }
        keyResult = nil
        mixer.requestMuteToggle { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied && delayedMuteReads == 3
                     && hardware.writes == [.init(device: 1, volume: nil, muted: true)]
                     && mixer.muted == true,
                     "a delayed mute confirmation never repeats the toggle")

        mixer = make()
        hardware.afterVolumeWrite = { hardware.device = 2 }
        keyResult = nil
        mixer.requestStep(level: step(1.0 / 64)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .superseded && hardware.writes.count == 1
                     && hardware.writes[0].device == 1 && hardware.outputsChanged > 0,
                     "a default change before listener delivery consumes the old key without stale mute or fallback")

        mixer = make()
        keyResult = nil
        mixer.requestStep(level: step(0.1)) { keyResult = $0 }
        hardware.runHAL()
        hardware.runMain()
        hardware.device = 2
        finish(mixer)
        suite.expect(keyResult == .superseded && hardware.writes.isEmpty,
                     "a default change between the fresh read and write never adjusts the replacement")

        mixer = make()
        var sliderReadbacks = 0
        hardware.afterVolumeWrite = {
            hardware.readVolume = {
                sliderReadbacks += 1
                return sliderReadbacks < 3 ? 0.2 : hardware.volume
            }
        }
        keyResult = nil
        mixer.requestAdjustment(volume: 0.8)
        mixer.requestStep(level: step(1.0 / 16)) { keyResult = $0 }
        finish(mixer)
        suite.expect(keyResult == .applied
                     && hardware.writes.compactMap(\.volume).map { ($0 * 10000).rounded() } == [8000, 8625],
                     "a key behind an asynchronous slider waits for its accepted level instead of stepping the old reading")
        suite.expectClose(mixer.volume ?? -1, 0.8625,
                          "feedback follows the slider's confirmed level plus the queued key")

        mixer = make()
        hardware.accepts = { _ in 0.2 }
        var keysBehindUnconfirmedSlider: [MixerOutputControl.KeyResult] = []
        var keysAtSliderCompletion: [MixerOutputControl.KeyResult] = []
        mixer.requestAdjustment(volume: 0.8) { _ in
            keysAtSliderCompletion = keysBehindUnconfirmedSlider
            mixer.requestStep(level: step(1.0 / 16)) { keysBehindUnconfirmedSlider.append($0) }
        }
        mixer.requestStep(level: step(1.0 / 16)) { keysBehindUnconfirmedSlider.append($0) }
        mixer.requestMuteToggle { keysBehindUnconfirmedSlider.append($0) }
        finish(mixer)
        suite.expect(keysBehindUnconfirmedSlider == [.unconfirmed, .unconfirmed, .fallback]
                     && keysAtSliderCompletion == [.unconfirmed, .unconfirmed]
                     && hardware.writes.compactMap(\.volume) == [0.8],
                     "a slider timeout consumes old keys before its callback, whose new key goes native without replaying the old ones")
        let writesAtSliderTimeout = hardware.writes
        mixer.requestStep(level: step(1.0 / 16)) { keysBehindUnconfirmedSlider.append($0) }
        mixer.requestMuteToggle { keysBehindUnconfirmedSlider.append($0) }
        finish(mixer)
        suite.expect(keysBehindUnconfirmedSlider == [.unconfirmed, .unconfirmed, .fallback, .fallback, .fallback]
                     && hardware.writes == writesAtSliderTimeout,
                     "new volume and mute presses after a slider timeout use native handling without more HAL writes")
        hardware.volume = 0.45
        hardware.accepts = nil
        mixer.requestStep(level: step(1.0 / 16)) { keysBehindUnconfirmedSlider.append($0) }
        finish(mixer)
        suite.expect(keysBehindUnconfirmedSlider == [.unconfirmed, .unconfirmed, .fallback, .fallback, .fallback, .fallback]
                     && hardware.writes == writesAtSliderTimeout && hardware.volume == 0.45,
                     "an external volume change needs no stale slider acknowledgement before a new native key")

        mixer = make()
        var directResult: Bool?
        var publishedWhenSuperseded: Double?
        hardware.afterVolumeWrite = {
            mixer.requestAdjustment(volume: 0.7) { directResult = $0 }
        }
        keyResult = nil
        mixer.requestStep(level: step(0.1)) {
            keyResult = $0
            publishedWhenSuperseded = mixer.volume
        }
        finish(mixer)
        suite.expect(keyResult == .superseded && directResult == true
                     && hardware.writes.compactMap(\.volume).map { ($0 * 10).rounded() } == [3, 7],
                     "a newer direct slider supersedes key confirmation and retains its own write")
        suite.expectClose(publishedWhenSuperseded ?? -1, 0.7,
                          "the old key callback cannot overwrite a newer optimistic slider level")
        suite.expectClose(mixer.volume ?? -1, 0.7,
                          "the direct slider remains published after the old key completes")

        mixer = make()
        var replacedBurst: [MixerOutputControl.KeyResult] = []
        hardware.afterVolumeWrite = { hardware.device = 2 }
        for _ in 0..<3 {
            mixer.requestStep(level: step(1.0 / 16)) { replacedBurst.append($0) }
        }
        finish(mixer)
        suite.expect(replacedBurst == [.superseded, .superseded, .superseded]
                     && hardware.writes.compactMap(\.volume).count == 1,
                     "a default change before its listener settles the old burst without replay or stranded keys")
        hardware.device = 1
        var afterReturn: MixerOutputControl.KeyResult?
        mixer.requestStep(level: step(1.0 / 16)) { afterReturn = $0 }
        finish(mixer)
        suite.expect(afterReturn == .applied,
                     "returning to the same default before resubscription does not keep an old burst stuck")

        mixer = make()
        completions = []
        for value in [Double.nan, .infinity, -.infinity] {
            mixer.requestAdjustment(volume: value) { completions.append($0) }
        }
        suite.expect(completions == [false, false, false] && hardware.hal.isEmpty,
                     "nonfinite output requests never reach the driver")
    }
}
