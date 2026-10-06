// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AudioToolbox
import Combine
import CoreAudio
import Foundation
import VitruvianCore
import VitruvianDesign

package struct MixerInputDevice: Identifiable, Equatable {
    package let id: String
    package let uid: String
    package let name: String
    package let isDefault: Bool
    package let priorityTier: MixerRoutingSupport.PriorityTier
    fileprivate let audioObjectID: AudioObjectID
}

/// Keeps Vitruvian's preferred microphone in sync with macOS' global input.
/// This is intentionally separate from the per-app output mixer: selecting a
/// microphone changes the system default input, without taps or audio capture.
@MainActor
package final class AudioInputDeviceManager: ObservableObject {
    /// What the manager asks of the system. `live` is the system's own; a
    /// test passes doubles, so it never changes a real microphone.
    package struct Environment: @unchecked Sendable {
        package var hal: AudioHAL
        /// The serial queue every CoreAudio call of a sweep, a write and a
        /// read runs on.
        package var halQueue: AudioWorkQueue
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        package var after: @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void
        package var now: @MainActor () -> CFAbsoluteTime
        package var defaults: UserDefaults
        /// The mute a volume adjustment has to wait behind.
        package var micMute: MicMuteService

        package init(hal: AudioHAL, halQueue: AudioWorkQueue,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     after: @escaping @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void,
                     now: @escaping @MainActor () -> CFAbsoluteTime,
                     defaults: UserDefaults, micMute: MicMuteService) {
            self.hal = hal
            self.halQueue = halQueue
            self.main = main
            self.after = after
            self.now = now
            self.defaults = defaults
            self.micMute = micMute
        }

        /// Main-actor: it waits behind the shared mute.
        @MainActor package static var live: Environment {
            Environment(hal: .live,
                        halQueue: .live(label: "com.vitruviansoftware.vitruvian.audioinput.hal"),
                        main: { work in DispatchQueue.main.async { work() } },
                        after: { delay, work in
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                MainActor.assumeIsolated { work() }
                            }
                        },
                        now: { CFAbsoluteTimeGetCurrent() },
                        defaults: .standard,
                        micMute: .shared)
        }
    }

    package static let shared = AudioInputDeviceManager(environment: .live)

    @Published package private(set) var inputDevices: [MixerInputDevice] = []
    @Published package private(set) var preferredInputDeviceUID: String?
    @Published package private(set) var currentInputDeviceUID: String?
    @Published package private(set) var effectiveInputDeviceUID: String?
    @Published package private(set) var inputVolume: Double?
    @Published package private(set) var preferredUnavailable = false
    @Published package private(set) var lastError: String?

    private var listenerInstalled = false
    /// Stored so stop() can remove the HAL listeners when the mixer leaves
    /// the hub.
    private var globalListeners: [AudioObjectPropertySelector] = []
    private var volumeDeviceID: AudioObjectID?
    private var volumeListenerAddresses: [AudioObjectPropertyAddress] = []
    private var volumeRefreshGeneration = 0
    private let volumeWriteLock = NSLock()
    // Guarded by volumeWriteLock.
    nonisolated(unsafe) private var volumeWriteLifetime = UUID()
    private var applyingPreferred = false
    private var refreshPending = false
    private var lastListenerRefreshAt: CFAbsoluteTime = 0
    /// Same arbitration as the mixer: the device sweep reads the audio HAL off
    /// the main thread, one reader at a time, and a sweep the manager no longer
    /// wants is dropped instead of publishing what it saw.
    private var refresh = MixerRefreshCoordinator()
    /// Every CoreAudio call of a refresh runs on the environment's HAL queue.
    /// A device being reconfigured can hold a property read for as long as
    /// the audio daemon holds the device, and that is exactly the moment the
    /// listeners fire.
    nonisolated private let environment: Environment
    /// The system input before the singular preferred-microphone behavior
    /// changed it, and the device that behavior applied. Priority selections
    /// clear this pair and become the new system choice instead of a temporary
    /// override that stop() would undo.
    private var inputDeviceBeforeOverride: String?
    private var appliedInputDeviceUID: String?
    /// True while Audio device priority is steering the input: the singular
    /// preferred-input enforcement steps aside so the two do not fight.
    package private(set) var inputPriorityIsActive = false

    package init(environment: Environment) {
        self.environment = environment
    }

    /// The microphone selector lives in the mixer panel section, so it
    /// follows the mixer's hub availability.
    package func syncWithPreferences() {
        inputPriorityIsActive = AppFeature.audioPriority.isAvailable(in: environment.defaults)
            && environment.defaults[Preferences.audioPriorityInputEnabled]
        if AppFeature.mixer.isAvailable(in: environment.defaults)
            || AppFeature.audioPriority.isAvailable(in: environment.defaults) {
            start()
        } else {
            stop()
        }
    }

    package func start() {
        guard !listenerInstalled else {
            refreshAndApply()
            return
        }
        listenerInstalled = true
        installListener(selector: kAudioHardwarePropertyDevices)
        installListener(selector: kAudioHardwarePropertyDefaultInputDevice)
        refreshAndApply()
    }

    package func stop() {
        removeVolumeListeners()
        // Priority selections are meant to survive a quit and the next
        // launch. Only the singular preferred-microphone override is restored.
        if !inputPriorityIsActive {
            restoreOriginalInputDevice()
        } else {
            inputDeviceBeforeOverride = nil
            appliedInputDeviceUID = nil
        }
        guard listenerInstalled else { return }
        listenerInstalled = false
        // A sweep already reading the HAL must not publish into a manager that
        // has stopped watching.
        refresh.discardInFlight()
        for selector in globalListeners {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            _ = environment.hal.removePropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                                       &address,
                                                       Self.listenerCallback,
                                                       listenerClient)
        }
        globalListeners.removeAll()
        if !inputDevices.isEmpty { inputDevices = [] }
        if preferredUnavailable { preferredUnavailable = false }
        if lastError != nil { lastError = nil }
        if inputVolume != nil { inputVolume = nil }
        inputPriorityIsActive = false
    }

    package func setInputPriorityActive(_ active: Bool) {
        guard inputPriorityIsActive != active else { return }
        inputPriorityIsActive = active
        refresh.discardInFlight()
        if listenerInstalled { refreshAndApply() }
    }

    package func setPreferredInputDeviceUID(_ uid: String?) {
        volumeWriteLock.withLock { volumeWriteLifetime = UUID() }
        let sanitized = Defaults.sanitizedPreferredInputDeviceUID(uid)
        // While priority owns input selection, the picker follows the actual
        // current device. Keep the dormant single preferred choice untouched
        // so it can resume when priority is disabled.
        if inputPriorityIsActive {
            if let sanitized { setCurrentInputDeviceUID(sanitized) }
            return
        }
        if let sanitized {
            environment.defaults.set(sanitized, forKey: DefaultsKey.preferredInputDevice)
        } else {
            environment.defaults.removeObject(forKey: DefaultsKey.preferredInputDevice)
        }
        preferredInputDeviceUID = sanitized
        lastError = nil
        // The choice supersedes a sweep still reading the HAL: that one saw the
        // previous preference and would publish it back for an instant.
        refresh.discardInFlight()
        refreshAndApply()
    }

    /// Points the system input at a concrete device without changing the
    /// dormant preferred-microphone setting. A successful selection becomes
    /// the new persistent system choice, so it also supersedes any restoration
    /// record left by the singular preferred-microphone behavior. The HAL write
    /// runs off-main: a device connecting or disappearing is exactly when
    /// CoreAudio may block.
    package func setCurrentInputDeviceUID(_ uid: String) {
        volumeWriteLock.withLock { volumeWriteLifetime = UUID() }
        guard listenerInstalled,
              uid != currentInputDeviceUID,
              let device = inputDevices.first(where: { $0.uid == uid }) else { return }
        refresh.discardInFlight()
        environment.halQueue.async { [weak self] in
            guard let self else { return }
            let status = self.setDefaultInputDevice(device.audioObjectID)
            self.environment.main {
                guard self.listenerInstalled else { return }
                if status == noErr {
                    self.inputDeviceBeforeOverride = nil
                    self.appliedInputDeviceUID = nil
                    if self.lastError != nil { self.lastError = nil }
                } else {
                    let message = "OSStatus \(status)"
                    if self.lastError != message { self.lastError = message }
                }
                // Do not claim the device synchronously. The HAL may publish
                // the new default a moment later; this refresh is the source
                // of truth for the picker and priority-list highlight.
                self.refreshAndApply()
            }
        }
    }

    package func setInputVolume(_ volume: Double) {
        guard listenerInstalled, volume.isFinite,
              let muteLifetime = environment.micMute.inputVolumeAdjustmentLifetime,
              let uid = effectiveInputDeviceUID,
              let device = inputDevices.first(where: { $0.uid == uid }),
              volumeDeviceID == device.audioObjectID, inputVolume != nil else { return }
        let clamped = min(max(volume, 0), 1)
        let lifetime = volumeWriteLock.withLock { volumeWriteLifetime }
        volumeRefreshGeneration &+= 1
        if inputVolume != clamped { inputVolume = clamped }
        let micMute = environment.micMute
        environment.halQueue.async { [weak self] in
            guard let self else { return }
            // Serialize with mute itself, including a mute requested while
            // this adjustment was waiting for the audio device.
            micMute.withUnmutedInput(lifetime: muteLifetime) {
                guard self.volumeWriteLock.withLock({ self.volumeWriteLifetime == lifetime }),
                      self.defaultInputDeviceUID() == uid else { return }
                var deviceUID: CFString = "" as CFString
                guard self.read(device.audioObjectID, kAudioDevicePropertyDeviceUID, &deviceUID),
                      deviceUID as String == uid,
                      self.volumeWriteLock.withLock({ self.volumeWriteLifetime == lifetime }) else { return }
                _ = self.setInputVolume(Float32(clamped), for: device.audioObjectID)
            }
            self.environment.main {
                guard self.volumeWriteLock.withLock({ self.volumeWriteLifetime == lifetime }) else { return }
                // Success may still mean a rounded or ignored adjustment.
                self.scheduleVolumeRefresh(for: device.audioObjectID)
            }
        }
    }

    /// The smallest possible answer to a change: the system decides which
    /// thread this arrives on, so it only asks the main thread for a refresh
    /// and returns. The reading that follows happens away from the main
    /// thread. Handing a closure back to be removed never matches the one that
    /// was registered, so the plain callback is what makes stopping work.
    private static let listenerCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let manager = Unmanaged<AudioInputDeviceManager>.fromOpaque(client).takeUnretainedValue()
        manager.environment.main { manager.scheduleListenerRefresh() }
        return noErr
    }

    private static let volumeListenerCallback: AudioObjectPropertyListenerProc = {
        device, _, _, client in
        guard let client else { return noErr }
        let manager = Unmanaged<AudioInputDeviceManager>.fromOpaque(client).takeUnretainedValue()
        manager.environment.main { manager.scheduleVolumeRefresh(for: device) }
        return noErr
    }

    /// Unretained is safe here and only here: this is a single instance that
    /// lives as long as the app.
    private var listenerClient: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    private func installListener(selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard environment.hal.addPropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                                  &address,
                                                  Self.listenerCallback,
                                                  listenerClient) == noErr else { return }
        globalListeners.append(selector)
    }

    /// Same coalescing as AppVolumeMixer.scheduleListenerRefresh: one hardware
    /// event fires both listeners back-to-back, and a busy audio HAL keeps the
    /// stream going. Isolated notifications refresh immediately; bursts fold
    /// into a single trailing refresh.
    private func scheduleListenerRefresh() {
        guard !refreshPending else { return }
        let now = environment.now()
        let elapsed = now - lastListenerRefreshAt
        if elapsed >= Self.listenerRefreshInterval {
            lastListenerRefreshAt = now
            refreshAndApply()
            return
        }
        refreshPending = true
        let delay = Self.listenerRefreshInterval - elapsed
        environment.after(delay) { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.lastListenerRefreshAt = self.environment.now()
            self.refreshAndApply()
        }
    }

    private static let listenerRefreshInterval: CFAbsoluteTime = 0.2

    /// The main-thread state one sweep needs, copied in.
    private struct RefreshRequest {
        let savedUID: String?
        let inputDeviceBeforeOverride: String?
        let mayApplyPreferred: Bool
        let priorityIsActive: Bool
        let preferredInputIsActive: Bool
        let volumeGeneration: Int
    }

    /// Everything one sweep read from the HAL, handed back to the main thread.
    private struct RefreshSnapshot {
        let savedUID: String?
        let currentUID: String?
        let devices: [MixerInputDevice]
        let resolution: MixerInputRouteResolution
        let inputVolume: Double?
        let volumeGeneration: Int
        /// Non-nil when this sweep actually pointed the system input at the
        /// preferred device; the write has already happened on the HAL.
        let applied: AppliedInput?
    }

    private struct AppliedInput {
        let device: MixerInputDevice
        let status: OSStatus
        let deviceBeforeOverride: String?
    }

    /// Kicks off one sweep. Reading the devices and pointing the system input
    /// at the preferred one are HAL calls and run on `halQueue`; every
    /// published property is written back on the main thread.
    private func refreshAndApply() {
        // A throttled refresh can land after stop(); watching is over.
        guard listenerInstalled else { return }
        // One reader at a time; a request that arrives meanwhile is remembered
        // and runs with the values the current sweep is about to publish.
        guard let generation = refresh.begin() else { return }
        let request = RefreshRequest(
            savedUID: Defaults.sanitizedPreferredInputDeviceUID(
                environment.defaults.string(forKey: DefaultsKey.preferredInputDevice)),
            inputDeviceBeforeOverride: inputDeviceBeforeOverride,
            mayApplyPreferred: !applyingPreferred && !inputPriorityIsActive,
            priorityIsActive: inputPriorityIsActive,
            preferredInputIsActive: AppFeature.mixer.isAvailable(in: environment.defaults),
            volumeGeneration: volumeRefreshGeneration)

        environment.halQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.readSnapshot(request)
            self.environment.main {
                self.apply(snapshot, generation: generation)
            }
        }
    }

    /// Runs on `halQueue`. Every CoreAudio call of a sweep happens here.
    nonisolated private func readSnapshot(_ request: RefreshRequest) -> RefreshSnapshot {
        let savedUID = request.savedUID
        let currentUID = defaultInputDeviceUID()
        let devices = inputDevices(defaultUID: currentUID)
        let availableUIDs = Set(devices.map(\.uid))
        let resolution = MixerRoutingSupport.resolveInputDevice(
            preferredUID: savedUID,
            availableUIDs: availableUIDs,
            currentUID: currentUID,
            priorityIsActive: request.priorityIsActive,
            preferredInputIsActive: request.preferredInputIsActive)

        guard resolution.shouldApplyPreferred,
              request.mayApplyPreferred,
              let savedUID,
              let device = devices.first(where: { $0.uid == savedUID }) else {
            let volume = resolution.effectiveUID
                .flatMap { uid in devices.first(where: { $0.uid == uid }) }
                .flatMap { inputVolume(for: $0.audioObjectID) }
            return RefreshSnapshot(savedUID: savedUID,
                                   currentUID: currentUID,
                                   devices: devices,
                                   resolution: resolution,
                                   inputVolume: volume.map(Double.init),
                                   volumeGeneration: request.volumeGeneration,
                                   applied: nil)
        }

        // Remembered once, at the first override: what the system had before
        // the app started steering it.
        let before = request.inputDeviceBeforeOverride ?? currentUID
        let status = setDefaultInputDevice(device.audioObjectID)
        return RefreshSnapshot(savedUID: savedUID,
                               currentUID: currentUID,
                               devices: devices,
                               resolution: resolution,
                               inputVolume: inputVolume(for: device.audioObjectID).map(Double.init),
                               volumeGeneration: request.volumeGeneration,
                               applied: AppliedInput(device: device,
                                                     status: status,
                                                     deviceBeforeOverride: before))
    }

    /// Main thread. Publishes one sweep in the same order the synchronous
    /// version used.
    private func apply(_ snapshot: RefreshSnapshot, generation: Int) {
        guard refresh.finish(generation) else {
            // The sweep is stale (the manager stopped, or the preference
            // changed, while it was reading), but a system input change it
            // already made on the HAL still has to be restorable on quit.
            if let applied = snapshot.applied, applied.status == noErr {
                if inputDeviceBeforeOverride == nil {
                    inputDeviceBeforeOverride = applied.deviceBeforeOverride
                }
                appliedInputDeviceUID = applied.device.uid
            }
            return
        }
        let refreshAgain = refresh.takeRepeatRequest()
        guard listenerInstalled else { return }
        defer { if refreshAgain { refreshAndApply() } }

        // Publish only real changes: refreshes run on every CoreAudio
        // notification, and assigning a @Published property signals SwiftUI
        // even when the value is identical — a chatty HAL would otherwise
        // re-render the mixer panel continuously.
        if preferredInputDeviceUID != snapshot.savedUID {
            preferredInputDeviceUID = snapshot.savedUID
        }
        if currentInputDeviceUID != snapshot.currentUID {
            currentInputDeviceUID = snapshot.currentUID
        }
        let effectiveDeviceChanged = effectiveInputDeviceUID != snapshot.resolution.effectiveUID
        if effectiveDeviceChanged {
            effectiveInputDeviceUID = snapshot.resolution.effectiveUID
        }
        if preferredUnavailable != snapshot.resolution.selectedUnavailable {
            preferredUnavailable = snapshot.resolution.selectedUnavailable
        }
        if inputDevices != snapshot.devices {
            inputDevices = snapshot.devices
        }
        let effectiveDeviceID = snapshot.resolution.effectiveUID
            .flatMap { uid in snapshot.devices.first(where: { $0.uid == uid })?.audioObjectID }
        // Rewiring listeners invalidates pending control reads. Capture the
        // sweep's validity first so that initial wiring cannot invalidate the
        // volume value discovered by this same sweep. A stale read is still
        // useful when it belongs to a newly selected device: it must replace
        // the old device's level while a slider drag is in flight.
        let sweepVolumeIsCurrent = volumeRefreshGeneration == snapshot.volumeGeneration
        let volumeDeviceChanged = volumeDeviceID != effectiveDeviceID
        updateVolumeListeners(for: effectiveDeviceID)
        if (sweepVolumeIsCurrent || effectiveDeviceChanged || volumeDeviceChanged), inputVolume != snapshot.inputVolume {
            inputVolume = snapshot.inputVolume
        }

        guard let applied = snapshot.applied else { return }
        applyPreferredInputDevice(applied)
    }

    /// Main thread. Records the outcome of a system input change the sweep
    /// already made on the HAL.
    private func applyPreferredInputDevice(_ applied: AppliedInput) {
        applyingPreferred = true
        defer { applyingPreferred = false }

        if inputDeviceBeforeOverride == nil {
            inputDeviceBeforeOverride = applied.deviceBeforeOverride
        }
        let device = applied.device
        guard applied.status == noErr else {
            let message = "OSStatus \(applied.status)"
            if lastError != message {
                lastError = message
            }
            return
        }

        if lastError != nil {
            lastError = nil
        }
        appliedInputDeviceUID = device.uid
        if currentInputDeviceUID != device.uid {
            currentInputDeviceUID = device.uid
        }
        if effectiveInputDeviceUID != device.uid {
            effectiveInputDeviceUID = device.uid
        }
        let updated = inputDevices.map {
            MixerInputDevice(id: $0.id,
                             uid: $0.uid,
                             name: $0.name,
                             isDefault: $0.uid == device.uid,
                             priorityTier: $0.priorityTier,
                             audioObjectID: $0.audioObjectID)
        }
        if inputDevices != updated {
            inputDevices = updated
        }
    }

    /// Hands the system input back the way it was found. Only when the app is
    /// still the last one to have set it: if something else picked a
    /// microphone since, that choice stays.
    ///
    /// Deliberately synchronous on the main thread even though it reads and
    /// writes the HAL: `stop()` runs while the app is quitting, so the system
    /// setting has to go back before the process does.
    private func restoreOriginalInputDevice() {
        guard let originalUID = inputDeviceBeforeOverride,
              let appliedUID = appliedInputDeviceUID else { return }
        inputDeviceBeforeOverride = nil
        appliedInputDeviceUID = nil
        let devices = inputDevices(defaultUID: nil)
        guard let restoredUID = MixerRoutingSupport.restorableInputDeviceUID(
            originalUID: originalUID,
            appliedUID: appliedUID,
            currentUID: defaultInputDeviceUID(),
            availableUIDs: Set(devices.map(\.uid))),
            let device = devices.first(where: { $0.uid == restoredUID }) else { return }
        _ = setDefaultInputDevice(device.audioObjectID)
    }

    nonisolated private func setDefaultInputDevice(_ deviceID: AudioObjectID) -> OSStatus {
        var nextDeviceID = deviceID
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        return environment.hal.setPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                               &address,
                                               0,
                                               nil,
                                               UInt32(MemoryLayout<AudioObjectID>.size),
                                               &nextDeviceID)
    }

    nonisolated private static let inputVolumeSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioDevicePropertyVolumeScalar,
    ]

    nonisolated private static func mainInputVolumeAddresses() -> [AudioObjectPropertyAddress] {
        inputVolumeSelectors.map { selector in
            AudioObjectPropertyAddress(mSelector: selector,
                                       mScope: kAudioDevicePropertyScopeInput,
                                       mElement: kAudioObjectPropertyElementMain)
        }
    }

    nonisolated private func channelInputVolumeAddresses(for deviceID: AudioObjectID) -> [AudioObjectPropertyAddress] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                mScope: kAudioDevicePropertyScopeInput,
                                                mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard environment.hal.getPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return [] }
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard environment.hal.getPropertyData(deviceID, &address, 0, nil, &size, storage) == noErr else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        let channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard channelCount > 0 else { return [] }
        return (1...channelCount).map { channel in
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                       mScope: kAudioDevicePropertyScopeInput,
                                       mElement: AudioObjectPropertyElement(channel))
        }
    }

    private func updateVolumeListeners(for deviceID: AudioObjectID?) {
        guard volumeDeviceID != deviceID else { return }
        removeVolumeListeners()
        guard let deviceID else { return }

        // The active device is also needed for explicit read-back when a
        // driver cannot install notifications.
        volumeDeviceID = deviceID
        let addresses = Self.mainInputVolumeAddresses() + channelInputVolumeAddresses(for: deviceID)
        for var address in addresses where isSettable(deviceID, &address) {
            guard environment.hal.addPropertyListener(deviceID,
                                                      &address,
                                                      Self.volumeListenerCallback,
                                                      listenerClient) == noErr else { continue }
            volumeListenerAddresses.append(address)
        }
    }

    private func removeVolumeListeners() {
        volumeWriteLock.withLock { volumeWriteLifetime = UUID() }
        volumeRefreshGeneration &+= 1
        guard let deviceID = volumeDeviceID else {
            volumeListenerAddresses.removeAll()
            return
        }
        for var address in volumeListenerAddresses {
            _ = environment.hal.removePropertyListener(deviceID,
                                                       &address,
                                                       Self.volumeListenerCallback,
                                                       listenerClient)
        }
        volumeListenerAddresses.removeAll()
        volumeDeviceID = nil
    }

    private func scheduleVolumeRefresh(for deviceID: AudioObjectID) {
        guard listenerInstalled, volumeDeviceID == deviceID else { return }
        volumeRefreshGeneration &+= 1
        let generation = volumeRefreshGeneration
        // A drag can emit several property notifications for each step. Read
        // once after the burst, and never let an older read replace newer UI.
        environment.after(0.03) { [weak self] in
            guard let self,
                  self.listenerInstalled,
                  self.volumeDeviceID == deviceID,
                  self.volumeRefreshGeneration == generation else { return }
            self.environment.halQueue.async { [weak self] in
                guard let self else { return }
                let volume = self.inputVolume(for: deviceID).map(Double.init)
                self.environment.main {
                    guard self.listenerInstalled,
                          self.volumeDeviceID == deviceID,
                          self.volumeRefreshGeneration == generation else { return }
                    if self.inputVolume != volume { self.inputVolume = volume }
                }
            }
        }
    }

    nonisolated private func isSettable(_ deviceID: AudioObjectID,
                                   _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard environment.hal.hasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        return environment.hal.isPropertySettable(deviceID, &address, &settable) == noErr
            && settable.boolValue
    }

    nonisolated private func inputVolume(for deviceID: AudioObjectID) -> Float32? {
        for var address in Self.mainInputVolumeAddresses() where isSettable(deviceID, &address) {
            var volume = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if environment.hal.getPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
                return volume
            }
        }

        // Some input devices expose writable gain only on their individual
        // channels. Represent those controls with their mean so they remain
        // visible and editable through the single slider.
        let channelVolumes = channelInputVolumeAddresses(for: deviceID).compactMap { address -> Float32? in
            var address = address
            guard isSettable(deviceID, &address) else { return nil }
            var volume = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard environment.hal.getPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else {
                return nil
            }
            return volume
        }
        guard !channelVolumes.isEmpty else { return nil }
        return channelVolumes.reduce(0, +) / Float32(channelVolumes.count)
    }

    nonisolated private func setInputVolume(_ volume: Float32, for deviceID: AudioObjectID) -> Bool {
        let clamped = min(max(volume, 0), 1)
        // Prefer a master control and stop at the first successful selector so
        // devices exposing both master and channels keep their channel balance.
        for var address in Self.mainInputVolumeAddresses() where isSettable(deviceID, &address) {
            var nextVolume = clamped
            if environment.hal.setPropertyData(deviceID, &address, 0, nil,
                                               UInt32(MemoryLayout<Float32>.size),
                                               &nextVolume) == noErr {
                return true
            }
        }

        // With no usable master, every writable channel must be updated or a
        // channel-only microphone would remain partially unchanged.
        var applied = false
        for var address in channelInputVolumeAddresses(for: deviceID) where isSettable(deviceID, &address) {
            var nextVolume = clamped
            if environment.hal.setPropertyData(deviceID, &address, 0, nil,
                                               UInt32(MemoryLayout<Float32>.size),
                                               &nextVolume) == noErr {
                applied = true
            }
        }
        return applied
    }

    nonisolated private func inputDevices(defaultUID: String?) -> [MixerInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard environment.hal.getPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                                  &address, 0, nil, &size) == noErr else { return [] }
        var deviceIDs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard environment.hal.getPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                              &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }

        var devices: [MixerInputDevice] = []
        for deviceID in deviceIDs {
            guard hasInputStreams(deviceID) else { continue }

            var isAlive: UInt32 = 1
            if read(deviceID, kAudioDevicePropertyDeviceIsAlive, &isAlive), isAlive == 0 {
                continue
            }
            var isHidden: UInt32 = 0
            if read(deviceID, kAudioDevicePropertyIsHidden, &isHidden), isHidden != 0 {
                continue
            }
            var canBeDefault: UInt32 = 1
            if read(deviceID,
                    kAudioDevicePropertyDeviceCanBeDefaultDevice,
                    &canBeDefault,
                    scope: kAudioObjectPropertyScopeInput),
               canBeDefault == 0 {
                continue
            }

            var uidRef: CFString = "" as CFString
            guard read(deviceID, kAudioDevicePropertyDeviceUID, &uidRef) else { continue }
            let uid = uidRef as String
            guard !uid.isEmpty else { continue }

            var nameRef: CFString = "" as CFString
            let name = read(deviceID, kAudioObjectPropertyName, &nameRef)
                ? nameRef as String
                : uid
            guard !MicMuteSupport.isOwnDevice(name: name) else { continue }
            var transportType: UInt32 = 0
            _ = read(deviceID, kAudioDevicePropertyTransportType, &transportType)

            devices.append(MixerInputDevice(id: uid,
                                            uid: uid,
                                            name: name,
                                            isDefault: uid == defaultUID,
                                            priorityTier: MixerRoutingSupport.PriorityTier(
                                                transportType: transportType),
                                            audioObjectID: deviceID))
        }

        return devices.sorted { lhs, rhs in
            MixerRoutingSupport.deviceDisplayOrderedBefore(
                isDefault: lhs.isDefault, name: lhs.name, uid: lhs.uid,
                otherIsDefault: rhs.isDefault, otherName: rhs.name, otherUID: rhs.uid)
        }
    }

    nonisolated private func hasInputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return environment.hal.getPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size >= MemoryLayout<AudioObjectID>.size
    }

    nonisolated private func defaultInputDeviceUID() -> String? {
        var defaultDevice = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   kAudioHardwarePropertyDefaultInputDevice, &defaultDevice),
              defaultDevice != 0 else { return nil }
        var uidRef: CFString = "" as CFString
        guard read(defaultDevice, kAudioDevicePropertyDeviceUID, &uidRef) else { return nil }
        return uidRef as String
    }

    @discardableResult
    nonisolated private func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            environment.hal.getPropertyData(object, &address, 0, nil, &size,
                                            UnsafeMutableRawPointer(pointer)) == noErr
        }
    }
}
