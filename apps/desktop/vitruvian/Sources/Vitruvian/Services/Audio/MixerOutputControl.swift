// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreAudio
import Foundation

/// The default output's volume and mute as the panel, the island and the keys
/// change them, for the output `AppVolumeMixer` follows.
///
/// UI feedback is immediate; one HAL write runs at a time and a burst retains
/// only its newest requested level. Keys step from the output's own reading.
/// Each output followed is a lifetime of its own, so nothing meant for one
/// output reaches the one that replaced it.
@MainActor
package final class MixerOutputControl {
    package struct Host: Sendable {
        /// The queue every HAL read and write runs on.
        package var hal: @Sendable (@escaping @Sendable () -> Void) -> Void
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        package var after: @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void
        package var defaultOutput: @Sendable () -> AudioObjectID?
        package var volumeIsSettable: @Sendable (AudioObjectID) -> Bool
        package var volume: @Sendable (AudioObjectID) -> Float32?
        package var muted: @Sendable (AudioObjectID) -> Bool?
        package var setVolume: @Sendable (Float32, AudioObjectID) -> Bool
        package var setMuted: @Sendable (Bool, AudioObjectID) -> Bool
        /// Whether the mixer still listens to the HAL.
        package var isListening: @MainActor () -> Bool
        /// Each assignment of the reading, for the mixer to publish.
        package var volumeChanged: @MainActor (Double?) -> Void
        package var mutedChanged: @MainActor (Bool?) -> Void
        /// The default output may have changed; the mixer reads its devices again.
        package var outputsChanged: @MainActor () -> Void

        package init(hal: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     after: @escaping @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void,
                     defaultOutput: @escaping @Sendable () -> AudioObjectID?,
                     volumeIsSettable: @escaping @Sendable (AudioObjectID) -> Bool,
                     volume: @escaping @Sendable (AudioObjectID) -> Float32?,
                     muted: @escaping @Sendable (AudioObjectID) -> Bool?,
                     setVolume: @escaping @Sendable (Float32, AudioObjectID) -> Bool,
                     setMuted: @escaping @Sendable (Bool, AudioObjectID) -> Bool,
                     isListening: @escaping @MainActor () -> Bool,
                     volumeChanged: @escaping @MainActor (Double?) -> Void,
                     mutedChanged: @escaping @MainActor (Bool?) -> Void,
                     outputsChanged: @escaping @MainActor () -> Void) {
            self.hal = hal
            self.main = main
            self.after = after
            self.defaultOutput = defaultOutput
            self.volumeIsSettable = volumeIsSettable
            self.volume = volume
            self.muted = muted
            self.setVolume = setVolume
            self.setMuted = setMuted
            self.isListening = isListening
            self.volumeChanged = volumeChanged
            self.mutedChanged = mutedChanged
            self.outputsChanged = outputsChanged
        }
    }

    private struct Adjustment {
        let device: AudioObjectID
        let lifetime: UUID
        var volume: Double?
        var muted: Bool?
        var completion: (Bool) -> Void
    }

    /// One volume or mute key waiting on the output's own reading. A nil
    /// `level` toggles mute.
    private struct Step {
        let level: ((Double) -> Double)?
        let completion: (Bool) -> Void
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
        pending?.completion(true)
        stepReadInFlight = false
        settleQueuedSteps(handled: true)
    }

    /// Clears the reading, as when the mixer stops.
    package func forget() {
        if volume != nil { volume = nil }
        if muted != nil { muted = nil }
    }

    /// A level the mixer wrote to the default output itself.
    package func adopt(volume: Double) {
        if self.volume != volume { self.volume = volume }
        if volume > 0, muted == true { muted = false }
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
        guard let device,
              volume?.isFinite != false,
              volume == nil || self.volume != nil,
              muted == nil || self.muted != nil else { completion(false); return }
        // A direct control change supersedes keys pressed before it. The HAL
        // read for those keys may still finish later, so invalidate its value.
        stepReadGeneration &+= 1
        settleQueuedSteps(handled: true)
        refreshGeneration &+= 1
        let previous = pending
        var adjustment = previous ?? Adjustment(device: device,
            lifetime: lock.withLock { lifetime }, completion: completion)
        adjustment.completion = completion
        if let volume {
            let value = min(1, max(0, volume))
            adjustment.volume = value
            self.volume = value
            // Many outputs still play faintly at a scalar of zero; macOS mutes
            // there, so do the same.
            if self.muted != nil, muted == nil {
                adjustment.muted = value == 0
                self.muted = value == 0
            }
        }
        if let muted { adjustment.muted = muted; self.muted = muted }
        pending = adjustment
        previous?.completion(true)
        drainAdjustment()
    }

    /// A volume key steps from the level the output reports now, not from the
    /// last published reading: after sleep an output can come back at another
    /// level without notifying, and stepping from the stale reading left the
    /// island at 21% while the speakers played at 2%. Keys pressed while that
    /// read runs queue behind it, and keys during this app's own write carry on
    /// from the level already requested. `level` receives the audible level
    /// (0 while muted) and returns the one to set.
    package func requestStep(level: @escaping (Double) -> Double,
                             completion: @escaping (Bool) -> Void = { _ in }) {
        enqueueKey(Step(level: level, completion: completion), isAvailable: volume != nil)
    }

    /// The mute key rides the same read and queue as the volume keys, so it
    /// toggles the state the output reports now (a stale reading asked for the
    /// state already in place and the key did nothing), and a volume key right
    /// after it steps from the level that one read fetched.
    package func requestMuteToggle(completion: @escaping (Bool) -> Void = { _ in }) {
        enqueueKey(Step(level: nil, completion: completion), isAvailable: muted != nil)
    }

    private func enqueueKey(_ step: Step, isAvailable: Bool) {
        guard let device, isAvailable else {
            step.completion(false)
            return
        }
        queuedSteps.append(step)
        guard !stepReadInFlight else { return }
        guard !hasCurrentAdjustment else {
            applyQueuedSteps()
            return
        }
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
                    // The keys were meant for an output that has since been
                    // replaced, as headphones taking over. Replaying a volume
                    // key natively would step the new output a full step per
                    // press, so those settle as handled, the way a pending
                    // adjustment does when its output changes. A native mute
                    // is the same toggle, so mute keys go back to the system
                    // and still mute what now plays. The mixer resubscribes
                    // to that output.
                    let steps = self.queuedSteps
                    self.queuedSteps.removeAll()
                    for step in steps { step.completion(step.level != nil) }
                    if current { self.host.outputsChanged() }
                    return
                }
                // A direct control change since the read began already set
                // the level these keys continue from, read or not. A control
                // the default output lacks leaves its keys to the system; the
                // others still apply.
                let superseded = self.stepReadGeneration != readGeneration
                if !superseded, !self.hasCurrentAdjustment {
                    if self.volume != volume { self.volume = volume }
                    if self.muted != muted { self.muted = muted }
                }
                self.applyQueuedSteps()
            }
        }
    }

    private func settleQueuedSteps(handled: Bool) {
        let steps = queuedSteps
        queuedSteps.removeAll()
        for step in steps { step.completion(handled) }
    }

    private func applyQueuedSteps() {
        let steps = queuedSteps
        queuedSteps.removeAll()
        for step in steps {
            if let level = step.level {
                guard let volume else {
                    step.completion(false)
                    continue
                }
                requestAdjustment(volume: level(muted == true ? 0 : volume), completion: step.completion)
            } else {
                guard let muted else {
                    step.completion(false)
                    continue
                }
                requestAdjustment(muted: !muted, completion: step.completion)
            }
        }
    }

    // MARK: - Writing

    nonisolated private func isCurrent(_ adjustment: Adjustment) -> Bool {
        lock.withLock { lifetime == adjustment.lifetime }
    }

    private var hasCurrentAdjustment: Bool {
        pending != nil || writeInFlight.map(isCurrent) == true
    }

    private func drainAdjustment() {
        guard writeInFlight == nil, let adjustment = pending else { return }
        pending = nil
        guard isCurrent(adjustment), device == adjustment.device else {
            adjustment.completion(true)
            return
        }
        writeInFlight = adjustment
        // Made and finished on the main thread; the HAL queue only reads it.
        nonisolated(unsafe) let write = adjustment
        let host = self.host
        host.hal { [weak self] in
            guard let self else { return }
            let device = write.device
            var success = self.isCurrent(write) && host.defaultOutput() == device
            if success, let volume = write.volume { success = host.setVolume(Float32(volume), device) }
            if success, let muted = write.muted, self.isCurrent(write) {
                success = host.setMuted(muted, device)
            }
            let succeeded = success
            host.main {
                self.writeInFlight = nil
                let current = self.isCurrent(write)
                write.completion(!current || succeeded)
                if self.pending != nil {
                    self.drainAdjustment()
                } else if current {
                    self.refresh(device)
                } else {
                    self.host.outputsChanged()
                }
            }
        }
    }
}
