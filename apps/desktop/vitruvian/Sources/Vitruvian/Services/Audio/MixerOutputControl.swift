// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreAudio
import Foundation
import VitruvianCore

/// The default output's volume and mute as the panel, the island and the keys
/// change them, for the output `AppVolumeMixer` follows.
///
/// UI feedback is immediate; one HAL write runs at a time and a burst retains
/// only its newest requested level. Keys step from the output's own reading
/// and wait for each write to be confirmed. Each output followed is a lifetime
/// of its own, so nothing meant for one output reaches the one that replaced it.
@MainActor
package final class MixerOutputControl {
    /// What a key came to. Only `fallback` hands the key back to the system.
    package enum KeyResult: Equatable, Sendable {
        /// The output took the level, as read back.
        case applied
        /// The output changed, or a newer request replaced this one.
        case superseded
        /// The write was accepted but never showed in the readback.
        case unconfirmed
        /// The output cannot take this key; the system should.
        case fallback
        package var handled: Bool { self != .fallback }
    }

    package struct Host: Sendable {
        /// The queue every HAL read and write runs on.
        package var hal: @Sendable (@escaping @Sendable () -> Void) -> Void
        /// The same queue, after a delay, for a readback that has to wait.
        package var halAfter: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        package var after: @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void
        package var defaultOutput: @Sendable () -> AudioObjectID?
        package var volumeIsSettable: @Sendable (AudioObjectID) -> Bool
        package var volume: @Sendable (AudioObjectID) -> Float32?
        package var muted: @Sendable (AudioObjectID) -> Bool?
        package var setVolume: @Sendable (Float32, AudioObjectID) -> Bool
        /// The same write, without trying the output's other volume controls.
        package var setVolumeWithoutFallback: @Sendable (Float32, AudioObjectID) -> Bool
        package var setMuted: @Sendable (Bool, AudioObjectID) -> Bool
        /// Whether the output is USB, whose drivers may step in plateaus.
        package var requiresQuantizedKeys: @Sendable (AudioObjectID) -> Bool
        /// Whether the output has a settable main scalar reading `volume`.
        package var hasSettableScalar: @Sendable (AudioObjectID, Double) -> Bool
        /// The level the driver's own scalar and decibel conversions round to.
        package var quantizedVolume: @Sendable (Double, AudioObjectID) -> Double?
        package var setScalarVolume: @Sendable (Double, AudioObjectID) -> Bool
        package var uptime: @Sendable () -> TimeInterval
        /// Whether the mixer still listens to the HAL.
        package var isListening: @MainActor () -> Bool
        /// Each assignment of the reading, for the mixer to publish.
        package var volumeChanged: @MainActor (Double?) -> Void
        package var mutedChanged: @MainActor (Bool?) -> Void
        /// The default output may have changed; the mixer reads its devices again.
        package var outputsChanged: @MainActor () -> Void

        package init(hal: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     halAfter: @escaping @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     after: @escaping @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void,
                     defaultOutput: @escaping @Sendable () -> AudioObjectID?,
                     volumeIsSettable: @escaping @Sendable (AudioObjectID) -> Bool,
                     volume: @escaping @Sendable (AudioObjectID) -> Float32?,
                     muted: @escaping @Sendable (AudioObjectID) -> Bool?,
                     setVolume: @escaping @Sendable (Float32, AudioObjectID) -> Bool,
                     setVolumeWithoutFallback: @escaping @Sendable (Float32, AudioObjectID) -> Bool,
                     setMuted: @escaping @Sendable (Bool, AudioObjectID) -> Bool,
                     requiresQuantizedKeys: @escaping @Sendable (AudioObjectID) -> Bool,
                     hasSettableScalar: @escaping @Sendable (AudioObjectID, Double) -> Bool,
                     quantizedVolume: @escaping @Sendable (Double, AudioObjectID) -> Double?,
                     setScalarVolume: @escaping @Sendable (Double, AudioObjectID) -> Bool,
                     uptime: @escaping @Sendable () -> TimeInterval,
                     isListening: @escaping @MainActor () -> Bool,
                     volumeChanged: @escaping @MainActor (Double?) -> Void,
                     mutedChanged: @escaping @MainActor (Bool?) -> Void,
                     outputsChanged: @escaping @MainActor () -> Void) {
            self.hal = hal
            self.halAfter = halAfter
            self.main = main
            self.after = after
            self.defaultOutput = defaultOutput
            self.volumeIsSettable = volumeIsSettable
            self.volume = volume
            self.muted = muted
            self.setVolume = setVolume
            self.setVolumeWithoutFallback = setVolumeWithoutFallback
            self.setMuted = setMuted
            self.requiresQuantizedKeys = requiresQuantizedKeys
            self.hasSettableScalar = hasSettableScalar
            self.quantizedVolume = quantizedVolume
            self.setScalarVolume = setScalarVolume
            self.uptime = uptime
            self.isListening = isListening
            self.volumeChanged = volumeChanged
            self.mutedChanged = mutedChanged
            self.outputsChanged = outputsChanged
        }
    }

    // The closures in these are called on the main thread only; the HAL queue
    // just carries the values.
    private struct Adjustment: @unchecked Sendable {
        let device: AudioObjectID
        let lifetime: UUID
        let keyGeneration: Int
        var volume: Double?
        var muted: Bool?
        var step: Step?
        var completion: (KeyResult) -> Void
    }

    /// One volume or mute key waiting on the output's own reading. A nil
    /// `level` toggles mute.
    private struct Step: @unchecked Sendable {
        let level: ((Double) -> Double)?
        let completion: (KeyResult) -> Void
    }

    /// A key's write while the HAL applies it, until its readback agrees.
    private struct KeyWrite: Sendable {
        let adjustment: Adjustment
        let expectedVolume: Double?
        var volumeTolerance: Double = 0.0001
        let muted: Bool?
        let volumeWritten: Bool
        var muteWritten = false
    }

    /// The output followed, whose volume and mute listeners the mixer holds.
    package private(set) var device: AudioObjectID?
    /// The followed output's volume, nil while it has none to set.
    package private(set) var volume: Double? {
        didSet { host.volumeChanged(volume) }
    }
    package private(set) var muted: Bool? {
        didSet { host.mutedChanged(muted) }
    }

    nonisolated private let host: Host
    private var refreshGeneration = 0
    private var pending: Adjustment?
    private var writeInFlight: Adjustment?
    private var queuedSteps: [Step] = []
    private var stepReadInFlight = false
    private var stepReadGeneration = 0
    private let lock = NSLock()
    /// Guarded by `lock`; the HAL queue checks it too.
    nonisolated(unsafe) private var lifetime = UUID()
    /// Bumped by every direct change, so a key meant for the level before it
    /// goes stale. Guarded by `lock`.
    nonisolated(unsafe) private var keyGeneration = 0
    /// HAL queue only. Once a lifetime needs native keys, its volume and
    /// mute presses must keep the same ordering through the system.
    nonisolated(unsafe) private var nativeKeyLifetime: UUID?

    package init(host: Host) {
        self.host = host
    }

    // MARK: - The output followed

    /// Starts following an output whose listeners the mixer just registered.
    package func follow(_ device: AudioObjectID) {
        self.device = device
    }

    /// Stops following the output. Its pending level and keys settle as
    /// handled: replaying them would adjust whatever output comes next.
    package func end() {
        device = nil
        refreshGeneration &+= 1
        lock.withLock { lifetime = UUID() }
        let pending = self.pending
        self.pending = nil
        // Superseded keys are handled: replaying them would adjust the new output.
        pending?.completion(.superseded)
        stepReadInFlight = false
        settleQueuedSteps(result: .superseded)
    }

    /// Clears the reading, as when the mixer stops.
    package func forget() {
        if volume != nil { volume = nil }
        if muted != nil { muted = nil }
    }

    /// A reading of the output, unless this control is changing it.
    package func apply(volume: Double?, muted: Bool?) {
        guard !hasCurrentAdjustment else { return }
        if self.volume != volume { self.volume = volume }
        if self.muted != muted { self.muted = muted }
    }

    /// The followed output's volume or mute changed. A drag and the volume
    /// keys can emit several properties for each step. Read once after the
    /// burst so an older callback cannot pull the slider back while a newer
    /// value is already on screen.
    package func refresh(_ device: AudioObjectID) {
        guard host.isListening(), self.device == device else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        host.after(0.03) { [weak self] in
            guard let self,
                  self.host.isListening(),
                  self.device == device,
                  self.refreshGeneration == generation else { return }
            let host = self.host
            host.hal { [weak self] in
                let volume = host.volumeIsSettable(device)
                    ? host.volume(device).map(Double.init)
                    : nil
                let muted = host.muted(device)
                host.main {
                    guard let self,
                          self.host.isListening(),
                          self.device == device,
                          self.refreshGeneration == generation else { return }
                    self.apply(volume: volume, muted: muted)
                }
            }
        }
    }

    // MARK: - Requests

    /// UI feedback is immediate; one HAL write runs at a time and a burst
    /// retains only its newest requested level. Device changes never inherit
    /// a write intended for the previous output.
    package func requestAdjustment(volume: Double? = nil, muted: Bool? = nil,
                                   completion: @escaping (Bool) -> Void = { _ in }) {
        enqueueAdjustment(volume: volume, muted: muted) { completion($0.handled) }
    }

    private func enqueueAdjustment(volume: Double? = nil, muted: Bool? = nil, step: Step? = nil,
                                   completion: @escaping (KeyResult) -> Void) {
        guard let device,
              volume?.isFinite != false,
              volume == nil || self.volume != nil,
              muted == nil || self.muted != nil else { completion(.fallback); return }
        // A direct control change supersedes keys pressed before it. The HAL
        // read for those keys may still finish later, so invalidate its value.
        if step == nil {
            stepReadGeneration &+= 1
            lock.withLock { keyGeneration &+= 1 }
            settleQueuedSteps(result: .superseded)
        }
        refreshGeneration &+= 1
        let previous = pending
        var adjustment = previous ?? Adjustment(device: device,
            lifetime: lock.withLock { lifetime },
            keyGeneration: lock.withLock { keyGeneration }, completion: completion)
        adjustment.completion = completion
        adjustment.step = step
        if let volume {
            let value = min(1, max(0, volume))
            adjustment.volume = value
            if step == nil { self.volume = value }
            // Many outputs still play faintly at a scalar of zero; macOS mutes
            // there, so do the same. A level the percent labels show as 0%
            // counts: a key steps from the level the output reports, so a
            // coarse step from a hair above one step lands just above zero.
            if self.muted != nil, muted == nil {
                let mutes = MixerRoutingSupport.mutesOutput(atVolume: value)
                adjustment.muted = mutes
                if step == nil { self.muted = mutes }
            }
        }
        if let muted {
            adjustment.muted = muted
            if step == nil { self.muted = muted }
        }
        pending = adjustment
        previous?.completion(.superseded)
        drainAdjustment()
    }

    /// A key reads the output before stepping. Keys wait for the previous
    /// write and its readback, so a USB device's rounded level becomes the
    /// starting point for the next press. `level` receives zero while muted.
    package func requestStep(level: @escaping (Double) -> Double,
                             completion: @escaping (KeyResult) -> Void = { _ in }) {
        enqueueKey(Step(level: level, completion: completion), isAvailable: volume != nil)
    }

    /// The mute key rides the same read and queue as the volume keys, so it
    /// toggles the state the output reports now. A following volume key waits
    /// for that toggle and then reads the resulting audible level.
    package func requestMuteToggle(completion: @escaping (KeyResult) -> Void = { _ in }) {
        enqueueKey(Step(level: nil, completion: completion), isAvailable: muted != nil)
    }

    private func enqueueKey(_ step: Step, isAvailable: Bool) {
        guard device != nil, isAvailable else {
            step.completion(.fallback)
            return
        }
        queuedSteps.append(step)
        readForQueuedKeys()
    }

    private func readForQueuedKeys() {
        guard let device, !queuedSteps.isEmpty, !stepReadInFlight else { return }
        guard !hasCurrentAdjustment else { return }
        stepReadInFlight = true
        let readGeneration = stepReadGeneration
        let lifetime = lock.withLock { self.lifetime }
        let host = self.host
        host.hal { [weak self] in
            let isDefault = host.defaultOutput() == device
            let volume = isDefault && host.volumeIsSettable(device)
                ? host.volume(device).map(Double.init)
                : nil
            let muted = isDefault ? host.muted(device) : nil
            host.main {
                guard let self else { return }
                let current = self.device == device
                    && self.lock.withLock { self.lifetime == lifetime }
                // Ending the old output already settled that lifetime's keys.
                // Its callback must not drain the new output's queue.
                guard current else { return }
                self.stepReadInFlight = false
                guard isDefault else {
                    // Both mute and volume belong to the output that was
                    // selected when pressed. Never replay either on its replacement.
                    self.settleQueuedSteps(result: .superseded)
                    self.host.outputsChanged()
                    return
                }
                // A direct control change since the read began already set
                // the level these keys continue from, read or not. A control
                // the default output lacks leaves its keys to the system; the
                // others still apply.
                let superseded = self.stepReadGeneration != readGeneration
                let fresh = !superseded && !self.hasCurrentAdjustment
                if fresh {
                    if self.volume != volume { self.volume = volume }
                    if self.muted != muted { self.muted = muted }
                }
                self.applyQueuedSteps()
            }
        }
    }

    private func settleQueuedSteps(result: KeyResult) {
        let steps = queuedSteps
        queuedSteps.removeAll()
        for step in steps { step.completion(result) }
    }

    /// Apply one key at a time. The driver's accepted level, rather than the
    /// requested scalar, is needed before the next key can choose its target.
    private func applyQueuedSteps() {
        guard !hasCurrentAdjustment, !queuedSteps.isEmpty else { return }
        let step = queuedSteps.removeFirst()
        if let level = step.level, let volume {
            let target = level(muted == true ? 0 : volume)
            guard target.isFinite else {
                step.completion(.fallback)
                applyQueuedSteps()
                return
            }
            enqueueAdjustment(volume: target, step: step, completion: step.completion)
        } else if step.level == nil, let muted {
            enqueueAdjustment(muted: !muted, step: step, completion: step.completion)
        } else {
            step.completion(.fallback)
            applyQueuedSteps()
        }
    }

    // MARK: - Writing

    nonisolated private func isCurrent(_ adjustment: Adjustment) -> Bool {
        lock.withLock { lifetime == adjustment.lifetime }
    }

    nonisolated private func isCurrentKey(_ adjustment: Adjustment) -> Bool {
        lock.withLock { lifetime == adjustment.lifetime && keyGeneration == adjustment.keyGeneration }
    }

    private var hasCurrentAdjustment: Bool {
        pending != nil || writeInFlight.map(isCurrent) == true
    }

    private func drainAdjustment() {
        guard writeInFlight == nil, let adjustment = pending else { return }
        pending = nil
        guard isCurrent(adjustment), device == adjustment.device else {
            adjustment.completion(.superseded)
            return
        }
        writeInFlight = adjustment
        let host = self.host
        host.hal { [weak self] in
            guard let self else { return }
            if adjustment.step != nil {
                self.beginKeyAdjustment(adjustment)
                return
            }
            let device = adjustment.device
            guard self.isCurrent(adjustment), host.defaultOutput() == device else {
                self.finishAdjustment(adjustment, result: .superseded)
                return
            }
            var confirmation = adjustment
            // A coarse output may round a slider too. This is only an ACK
            // target; the slider still writes exactly the level requested.
            if let volume = adjustment.volume, host.requiresQuantizedKeys(device),
               let current = host.volume(device).map(Double.init),
               host.hasSettableScalar(device, current),
               let converted = host.quantizedVolume(volume, device),
               converted.isFinite, (0...1).contains(converted) {
                confirmation.volume = converted
            }
            var success = self.isCurrent(adjustment) && host.defaultOutput() == device
            if success, let volume = adjustment.volume { success = host.setVolume(Float32(volume), device) }
            let volumeWritten = success && adjustment.volume != nil
            if success, let muted = adjustment.muted, self.isCurrent(adjustment),
               host.defaultOutput() == device {
                success = host.setMuted(muted, device)
            }
            if success || volumeWritten { self.confirmDirectAdjustment(confirmation) }
            else { self.finishAdjustment(adjustment, result: .fallback) }
        }
    }

    nonisolated private static func isConfirmed(_ adjustment: Adjustment, volume: Double?, muted: Bool?) -> Bool {
        if let expected = adjustment.volume,
           volume.map({ $0.isFinite && abs($0 - expected) < 0.005 }) != true { return false }
        if let expected = adjustment.muted, muted != expected { return false }
        return true
    }

    /// Keep keys behind a slider until all requested properties are observed.
    /// Unlike a mute key, even a silent slider must wait for its volume ACK.
    nonisolated private func confirmDirectAdjustment(_ adjustment: Adjustment, remainingReads: Int = 3) {
        let host = self.host
        guard isCurrent(adjustment), host.defaultOutput() == adjustment.device else {
            finishAdjustment(adjustment, result: .superseded)
            return
        }
        let volume = host.volume(adjustment.device).map(Double.init)
        let muted = host.muted(adjustment.device)
        if Self.isConfirmed(adjustment, volume: volume, muted: muted) {
            finishAdjustment(adjustment, result: .applied)
        } else if remainingReads > 0 {
            host.halAfter(0.02) { [self] in
                confirmDirectAdjustment(adjustment, remainingReads: remainingReads - 1)
            }
        } else {
            finishAdjustment(adjustment, result: .unconfirmed)
        }
    }

    /// Runs on the HAL queue, then hands the result to the main thread.
    nonisolated private func finishAdjustment(_ adjustment: Adjustment, result: KeyResult,
                                              volume: Double? = nil, muted: Bool? = nil) {
        // A listener may not have reached main yet when the default changes
        // during a read or a failed write.
        let result = host.defaultOutput() == adjustment.device ? result : .superseded
        let current = adjustment.step == nil ? isCurrent(adjustment) : isCurrentKey(adjustment)
        if current, result == .unconfirmed || (adjustment.step != nil && result == .fallback) {
            // Unconfirmed writes must not leave future keys on an ineffective
            // path. Later presses go native; never replay a key whose write
            // was accepted and may still arrive late.
            nativeKeyLifetime = adjustment.lifetime
        }
        host.main { [self] in
            completeAdjustment(adjustment, result: result, volume: volume, muted: muted)
        }
    }

    private func completeAdjustment(_ adjustment: Adjustment, result: KeyResult, volume: Double?, muted: Bool?) {
        writeInFlight = nil
        let current = adjustment.step == nil ? isCurrent(adjustment) : isCurrentKey(adjustment)
        let result = current ? result : .superseded
        if adjustment.step == nil, result == .unconfirmed, pending == nil {
            // These keys arrived while the slider was awaiting an ACK.
            // Consume them before its callback can enqueue a new press.
            // New presses use the native path, without an indefinite
            // barrier that depends on matching an old slider target.
            settleQueuedSteps(result: .unconfirmed)
        }
        if result == .applied, adjustment.step != nil, pending == nil {
            apply(volume: volume, muted: muted)
        }
        adjustment.completion(result)
        if pending != nil {
            drainAdjustment()
        } else if current, result != .superseded {
            readForQueuedKeys()
            refresh(adjustment.device)
        } else {
            // The default changed before its listener arrived. These
            // queued keys still belong to the same, superseded output.
            if current { settleQueuedSteps(result: .superseded) }
            host.outputsChanged()
        }
    }

    /// Choose the device's next representable level before writing anything.
    /// A successful HAL write may finish asynchronously, so an unchanged
    /// immediate readback must never trigger a second, louder request.
    nonisolated private func beginKeyAdjustment(_ adjustment: Adjustment) {
        let host = self.host
        let device = adjustment.device
        guard isCurrentKey(adjustment), host.defaultOutput() == device else {
            finishAdjustment(adjustment, result: .superseded)
            return
        }
        if nativeKeyLifetime == adjustment.lifetime {
            finishAdjustment(adjustment, result: .fallback)
            return
        }
        let muted = host.muted(device)
        let volume = host.volume(device).map(Double.init)
        guard let step = adjustment.step else { return }
        if let level = step.level {
            guard let volume, volume.isFinite else {
                finishAdjustment(adjustment, result: .fallback)
                return
            }
            // Down while muted must not turn the stored level into sound.
            if muted == true, level(0) == 0 {
                finishAdjustment(adjustment, result: .applied, volume: volume, muted: muted)
                return
            }
            guard let target = Self.keyVolumeTarget(host: host, device: device, from: volume, muted: muted,
                                                    level: level) else {
                finishAdjustment(adjustment, result: .fallback)
                return
            }
            guard isCurrentKey(adjustment), host.defaultOutput() == device else {
                finishAdjustment(adjustment, result: .superseded)
                return
            }
            let changesVolume = abs(target.volume - volume) >= 0.0001
            if changesVolume {
                let success = target.usesScalar ? host.setScalarVolume(target.volume, device)
                    : host.setVolumeWithoutFallback(Float32(target.volume), device)
                guard success else {
                    finishAdjustment(adjustment, result: .fallback)
                    return
                }
            }
            confirmKeyAdjustment(KeyWrite(adjustment: adjustment, expectedVolume: target.volume,
                                          volumeTolerance: target.usesScalar ? 0.0001 : 0.005,
                                          muted: target.muted, volumeWritten: changesVolume))
        } else if let muted {
            confirmKeyAdjustment(KeyWrite(adjustment: adjustment, expectedVolume: nil,
                                          muted: !muted, volumeWritten: false))
        } else {
            finishAdjustment(adjustment, result: .fallback)
        }
    }

    /// Hold this key's place in the queue while the HAL applies its write.
    /// Retries only read. A timeout after an accepted write consumes the key
    /// without replay or confirmation, since that write can still arrive late.
    nonisolated private func confirmKeyAdjustment(_ pending: KeyWrite, remainingReads: Int = 3) {
        var write = pending
        let host = self.host
        let adjustment = write.adjustment
        let device = adjustment.device
        guard isCurrentKey(adjustment), host.defaultOutput() == device else {
            finishAdjustment(adjustment, result: .superseded)
            return
        }
        let actual = host.volume(device).map(Double.init)
        // A regular output may report whole percentages. Accept that
        // rounding, but never unmute an unchanged high scalar or a level the
        // UI still considers silence. An explicit mute needs no scalar ACK.
        if let expected = write.expectedVolume, write.muted != true,
           actual.map({ $0.isFinite && abs($0 - expected) < write.volumeTolerance
               && (write.muted != false || !MixerRoutingSupport.mutesOutput(atVolume: $0)) }) != true {
            scheduleKeyConfirmation(write, remainingReads: remainingReads)
            return
        }
        var actualMuted = host.muted(device)
        if let muted = write.muted, actualMuted != muted {
            if !write.muteWritten {
                // In particular, never unmute a stale, higher stored volume
                // before the requested low volume has been read back.
                guard isCurrentKey(adjustment), host.defaultOutput() == device else {
                    finishAdjustment(adjustment, result: .superseded)
                    return
                }
                guard host.setMuted(muted, device) else {
                    finishAdjustment(adjustment, result: write.volumeWritten ? .unconfirmed : .fallback)
                    return
                }
                write.muteWritten = true
                actualMuted = host.muted(device)
            }
            guard actualMuted == muted else {
                scheduleKeyConfirmation(write, remainingReads: remainingReads)
                return
            }
        }
        guard isCurrentKey(adjustment), host.defaultOutput() == device else {
            finishAdjustment(adjustment, result: .superseded)
            return
        }
        finishAdjustment(adjustment, result: .applied, volume: actual, muted: actualMuted)
    }

    nonisolated private func scheduleKeyConfirmation(_ write: KeyWrite, remainingReads: Int) {
        guard remainingReads > 0 else {
            finishAdjustment(write.adjustment, result: .unconfirmed)
            return
        }
        host.halAfter(0.02) { [self] in
            confirmKeyAdjustment(write, remainingReads: remainingReads - 1)
        }
    }

    /// Some USB drivers expose plateaus through scalar/dB conversion. Use
    /// those only as a target hint, with mandatory readback after the write.
    /// Continuous or missing USB conversions go native before any write;
    /// regular outputs keep their ordinary scalar request and balance.
    nonisolated private static func keyVolumeTarget(host: Host, device: AudioObjectID, from volume: Double,
                                                    muted: Bool?, level: (Double) -> Double)
        -> (volume: Double, muted: Bool?, usesScalar: Bool)? {
        guard volume.isFinite, (0...1).contains(volume) else { return nil }
        let from = muted == true ? 0 : volume
        let requested = level(from)
        guard requested.isFinite else { return nil }
        let first = min(1, max(0, requested))
        if first == from {
            return (volume, muted == nil ? nil : MixerRoutingSupport.mutesOutput(atVolume: first), false)
        }
        guard host.requiresQuantizedKeys(device) else {
            return (first, muted == nil ? nil : MixerRoutingSupport.mutesOutput(atVolume: first), false)
        }
        guard host.hasSettableScalar(device, volume) else { return nil }
        let direction = first > from ? 1.0 : -1.0
        var targets = [first]
        // Production keys advance by 1/16 or 1/64. No HAL calls in this loop.
        while targets.count < 64, let last = targets.last, last > 0, last < 1 {
            let next = level(last)
            guard next.isFinite else { return nil }
            let clamped = min(1, max(0, next))
            guard (clamped - last) * direction > 0 else { return nil }
            targets.append(clamped)
        }
        let deadline = host.uptime() + 0.05
        var queries = 0
        func converted(_ target: Double) -> Double? {
            guard queries < 11, host.uptime() <= deadline else { return nil }
            queries += 1
            guard let value = host.quantizedVolume(target, device), value.isFinite,
                  (0...1).contains(value), host.uptime() <= deadline else { return nil }
            return value
        }
        guard let baseline = converted(volume), abs(baseline - volume) < 0.0001 else { return nil }
        // Equivalence alone does not promise a hardware step. Require an
        // observed plateau, not just a successful continuous round trip.
        let probe = volume >= 1.0 / 1024 ? volume - 1.0 / 1024 : volume + 1.0 / 1024
        guard let nearby = converted(probe), abs(nearby - baseline) < 0.0001,
              let initial = converted(first), (initial - from) * direction >= -0.0001 else { return nil }
        func advances(_ value: Double, at index: Int) -> Bool {
            if muted != nil, MixerRoutingSupport.mutesOutput(atVolume: targets[index]) { return true }
            return (value - from) * direction >= 0.0001
                && (direction < 0 || !MixerRoutingSupport.mutesOutput(atVolume: value))
        }
        var chosen = initial
        var index = 0
        if !advances(initial, at: 0) {
            var low = 0
            var high = targets.count - 1
            guard high > low, let end = converted(targets[high]), advances(end, at: high),
                  (end - initial) * direction >= 0 else { return nil }
            var lowValue = initial
            var highValue = end
            while high - low > 1 {
                let middle = (low + high) / 2
                guard let value = converted(targets[middle]),
                      (value - lowValue) * direction >= -0.0001,
                      (highValue - value) * direction >= -0.0001 else { return nil }
                if advances(value, at: middle) { high = middle; highValue = value }
                else { low = middle; lowValue = value }
            }
            index = high
            chosen = highValue
        }
        guard let canonical = converted(chosen), abs(canonical - chosen) < 0.0001 else { return nil }
        let mutes = MixerRoutingSupport.mutesOutput(atVolume: targets[index])
            || MixerRoutingSupport.mutesOutput(atVolume: chosen)
        return (chosen, muted == nil ? nil : mutes, true)
    }
}
