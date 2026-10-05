// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AudioToolbox
import Combine
import CoreAudio
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The real input and mute services over an in-memory HAL, queues the test
/// runs by hand and a private settings suite. The HAL calls back the listeners
/// the services register, the way CoreAudio does. No microphone, hotkey or
/// real user preference is changed.
enum MixerInputVolumeContract {
    /// A serial queue the test runs one job at a time, on the main thread.
    nonisolated final class Queue: @unchecked Sendable {
        static let main = Queue()
        nonisolated(unsafe) static var queues: [Queue] = [main]
        var work: [() -> Void] = []
        func run() { if !work.isEmpty { work.removeFirst()() } }
        static func make() -> Queue {
            let queue = Queue()
            queues.append(queue)
            return queue
        }
        static func drain() {
            for _ in 0..<100 {
                if queues.allSatisfy({ $0.work.isEmpty }) { return }
                for q in queues { q.run() }
            }
            fatalError("queue did not settle")
        }
        /// The queue as the services see it: `sync` runs what is queued first.
        var serial: AudioWorkQueue {
            AudioWorkQueue(async: { [self] in work.append($0) },
                           sync: { [self] body in
                               while !work.isEmpty { run() }
                               body()
                           })
        }
    }
    /// What the mute shows: the island's microphone notice and the HUD.
    nonisolated enum Feedback {
        nonisolated(unsafe) static var messages: [String] = []
        nonisolated(unsafe) static var showsMicrophone = false
        nonisolated(unsafe) static var microphone: [Bool] = []
        nonisolated(unsafe) static var retractions = 0
    }
    nonisolated struct Key: Hashable {
        let d: UInt32
        let s: UInt32
        let e: UInt32
        init(_ d: UInt32, _ a: AudioObjectPropertyAddress) {
            self.d = d
            s = a.mSelector
            e = a.mElement
        }
    }
    nonisolated enum HAL {
        nonisolated(unsafe) static var levels: [Key: Float] = [:]
        nonisolated(unsafe) static var readOnly: Set<Key> = []
        nonisolated(unsafe) static var readFails: Set<Key> = []
        nonisolated(unsafe) static var writeFails: Set<Key> = []
        nonisolated(unsafe) static var mute: [UInt32: UInt32] = [:]
        nonisolated(unsafe) static var writes: [Key] = []
        nonisolated(unsafe) static var listeners: Set<Key> = []
        nonisolated(unsafe) static var listenerFails = false
        nonisolated(unsafe) static var ignoreWrites = false
        nonisolated(unsafe) static var devices: [UInt32] = [10]
        nonisolated(unsafe) static var streamChannels: [UInt32: [UInt32]] = [:]
        nonisolated(unsafe) static var streamReadFails = false
        nonisolated(unsafe) static var afterWrite: (() -> Void)?
        nonisolated(unsafe) static var afterUIDRead: (() -> Void)?
        nonisolated(unsafe) static var current: UInt32 = 10
        nonisolated(unsafe) static var uids: [UInt32: String] = [:]
        nonisolated(unsafe) static var aggregates: Set<UInt32> = []
        nonisolated(unsafe) static var running: Set<UInt32> = []
        static func key(_ d: UInt32, _ e: UInt32 = 0, _ s: UInt32 = kAudioDevicePropertyVolumeScalar)
            -> Key
        {
            Key(
                d,
                AudioObjectPropertyAddress(
                    mSelector: s, mScope: kAudioDevicePropertyScopeInput, mElement: e))
        }
        nonisolated(unsafe) static var procs: [Key: [(AudioObjectPropertyListenerProc, UnsafeMutableRawPointer?)]] = [:]
        nonisolated(unsafe) static var removals = 0
        /// Devices with no input stream: speakers, which are not microphones.
        nonisolated(unsafe) static var outputOnly: Set<UInt32> = []
        nonisolated(unsafe) static var clock: CFAbsoluteTime = 0
        nonisolated(unsafe) static var suite = ""
        nonisolated(unsafe) static var defaults = Foundation.UserDefaults()
        nonisolated(unsafe) static var inputQueue = Queue()
        nonisolated(unsafe) static var muteQueue = Queue()
        @MainActor static var muteService = makeMute()

        static var hal: AudioHAL {
            AudioHAL(hasProperty: HasProperty, isPropertySettable: IsPropertySettable,
                     getPropertyDataSize: GetPropertyDataSize, getPropertyData: GetPropertyData,
                     setPropertyData: SetPropertyData, addPropertyListener: AddPropertyListener,
                     removePropertyListener: { RemovePropertyListener($0, $1, $2, $3) })
        }
        static let main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = { work in
            Queue.main.work.append { MainActor.assumeIsolated { work() } }
        }

        @MainActor static func makeMute() -> MicMuteService {
            MicMuteService(environment: .init(
                hal: hal, halQueue: muteQueue.serial, main: main, defaults: defaults,
                showMicrophone: { muted in
                    guard Feedback.showsMicrophone else { return false }
                    Feedback.microphone.append(muted)
                    return true
                },
                retractMicrophoneNotice: { Feedback.retractions += 1 },
                hud: { _, message in Feedback.messages.append(message) }))
        }

        @MainActor static func makeManager() -> AudioInputDeviceManager {
            AudioInputDeviceManager(environment: .init(
                hal: hal, halQueue: inputQueue.serial, main: main,
                after: { _, work in Queue.main.work.append { MainActor.assumeIsolated { work() } } },
                // Every reading a second later: a notification refreshes at once.
                now: {
                    clock += 1
                    return clock
                },
                defaults: defaults, micMute: muteService))
        }

        /// The HAL reporting a change of one property of an object, the way
        /// CoreAudio calls the listeners registered on it.
        static func notify(_ d: UInt32, _ selector: UInt32, element: UInt32 = 0) {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: element)
            for (key, registered) in procs where key.d == d && key.s == selector && key.e == element {
                for (proc, client) in registered { _ = proc(d, 1, &address, client) }
            }
        }

        /// True when no audio can come out of the device: its mute switch is
        /// on, or its first level reads silent.
        static func silenced(_ d: UInt32) -> Bool {
            if mute[d] == 1 { return true }
            guard let level = [UInt32(0), 1, 2].lazy.compactMap({ levels[key(d, $0)] }).first else { return false }
            return level <= 0.01
        }

        @MainActor static func reset() {
            levels = [:]
            readOnly = []
            readFails = []
            writeFails = []
            mute = [:]
            writes = []
            listeners = []
            procs = [:]
            removals = 0
            outputOnly = []
            listenerFails = false
            ignoreWrites = false
            devices = [10]
            current = 10
            uids = [:]
            aggregates = []
            running = []
            streamChannels = [:]
            streamReadFails = false
            afterWrite = nil
            afterUIDRead = nil
            if !suite.isEmpty { defaults.removePersistentDomain(forName: suite) }
            let name = "vitru.tests.mixer-input.\(UUID().uuidString)"
            suite = name
            defaults = Foundation.UserDefaults(suiteName: name)!
            for feature in [AppFeature.mixer, .audioPriority, .micMute] {
                defaults.set(true, forKey: feature.availabilityKey)
            }
            Queue.queues = [Queue.main]
            Queue.main.work = []
            inputQueue = Queue.make()
            muteQueue = Queue.make()
            muteService = makeMute()
        }

        static func finish() {
            if !suite.isEmpty { defaults.removePersistentDomain(forName: suite) }
            suite = ""
        }

        static func HasProperty(_ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>) -> Bool {
            let k = Key(d, a.pointee)
            return levels[k] != nil || (a.pointee.mSelector == kAudioDevicePropertyMute && mute[d] != nil)
        }
        static func IsPropertySettable(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>,
            _ v: UnsafeMutablePointer<DarwinBoolean>
        ) -> OSStatus {
            v.pointee = DarwinBoolean(!readOnly.contains(Key(d, a.pointee)))
            return noErr
        }
        static func GetPropertyDataSize(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>, _ q: UInt32,
            _ qp: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>
        ) -> OSStatus {
            if a.pointee.mSelector == kAudioDevicePropertyStreamConfiguration {
                size.pointee = UInt32(
                    MemoryLayout<AudioBufferList>.size + max(0, (streamChannels[d] ?? [2]).count - 1)
                        * MemoryLayout<AudioBuffer>.stride)
                return streamReadFails ? -1 : noErr
            }
            if a.pointee.mSelector == kAudioDevicePropertyStreams, outputOnly.contains(d) {
                size.pointee = 0
                return noErr
            }
            size.pointee =
                a.pointee.mSelector == kAudioHardwarePropertyDevices ? UInt32(devices.count * 4) : 4
            return noErr
        }
        static func GetPropertyData(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>, _ q: UInt32,
            _ qp: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>, _ p: UnsafeMutableRawPointer
        ) -> OSStatus {
            let k = Key(d, a.pointee)
            if readFails.contains(k) { return -1 }
            if let v = levels[k] {
                p.storeBytes(of: v, as: Float.self)
                return noErr
            }
            switch a.pointee.mSelector {
            case kAudioDevicePropertyStreamConfiguration:
                if streamReadFails { return -1 }
                let channels = streamChannels[d] ?? [2]
                let list = p.assumingMemoryBound(to: AudioBufferList.self)
                list.pointee.mNumberBuffers = UInt32(channels.count)
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                for (i, n) in channels.enumerated() {
                    buffers[i] = AudioBuffer(mNumberChannels: n, mDataByteSize: 0, mData: nil)
                }
            case kAudioHardwarePropertyDevices:
                for (i, v) in devices.enumerated() {
                    p.storeBytes(of: v, toByteOffset: i * 4, as: UInt32.self)
                }
            case kAudioHardwarePropertyDefaultInputDevice: p.storeBytes(of: current, as: UInt32.self)
            case kAudioDevicePropertyDeviceUID, kAudioObjectPropertyName:
                p.assumingMemoryBound(to: CFString.self).pointee = (uids[d] ?? "device-\(d)") as CFString
                let callback = afterUIDRead
                afterUIDRead = nil
                callback?()
            case kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyDeviceCanBeDefaultDevice:
                p.storeBytes(of: UInt32(1), as: UInt32.self)
            case kAudioDevicePropertyIsHidden: p.storeBytes(of: UInt32(0), as: UInt32.self)
            case kAudioDevicePropertyTransportType:
                guard aggregates.contains(d) else { return -1 }
                p.storeBytes(of: kAudioDeviceTransportTypeAggregate, as: UInt32.self)
            case kAudioDevicePropertyDeviceIsRunningSomewhere:
                p.storeBytes(of: UInt32(running.contains(d) ? 1 : 0), as: UInt32.self)
            case kAudioDevicePropertyMute:
                guard let v = mute[d] else { return -1 }
                p.storeBytes(of: v, as: UInt32.self)
            default: return -1
            }
            return noErr
        }
        static func SetPropertyData(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>, _ q: UInt32,
            _ qp: UnsafeRawPointer?, _ size: UInt32, _ p: UnsafeRawPointer
        ) -> OSStatus {
            let k = Key(d, a.pointee)
            writes.append(k)
            if writeFails.contains(k) { return -1 }
            if ignoreWrites { return noErr }
            if a.pointee.mSelector == kAudioHardwarePropertyDefaultInputDevice {
                current = p.load(as: UInt32.self)
                return noErr
            }
            if a.pointee.mSelector == kAudioDevicePropertyMute {
                mute[d] = p.load(as: UInt32.self)
                return noErr
            }
            guard levels[k] != nil else { return -1 }
            levels[k] = p.load(as: Float.self)
            let callback = afterWrite
            afterWrite = nil
            callback?()
            return noErr
        }
        static func AddPropertyListener(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>,
            _ cb: AudioObjectPropertyListenerProc, _ client: UnsafeMutableRawPointer?
        ) -> OSStatus {
            if listenerFails { return -1 }
            listeners.insert(Key(d, a.pointee))
            procs[Key(d, a.pointee), default: []].append((cb, client))
            return noErr
        }
        @discardableResult
        static func RemovePropertyListener(
            _ d: UInt32, _ a: UnsafePointer<AudioObjectPropertyAddress>,
            _ cb: AudioObjectPropertyListenerProc, _ client: UnsafeMutableRawPointer?
        ) -> OSStatus {
            listeners.remove(Key(d, a.pointee))
            procs[Key(d, a.pointee)] = nil
            removals += 1
            return noErr
        }
    }
    static func run(_ suite: TestSuite) {
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            suite.expect(condition(), name)
        }
        func near(_ x: Double?, _ y: Double) -> Bool { x.map { abs($0 - y) < 0.0001 } ?? false }
        // What the floating confirmation says, in the app's language.
        let text = L10n.shared.s
        func manager() -> AudioInputDeviceManager {
            let m = HAL.makeManager()
            m.start()
            Queue.drain()
            return m
        }
        defer { HAL.finish() }
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.4
        var m = manager()
        check(near(m.inputVolume, 0.4), "initial discovery publishes gain")
        m.setInputVolume(0.7)
        Queue.drain()
        check(near(m.inputVolume, 0.7), "normal write and readback")
        HAL.ignoreWrites = true
        m.setInputVolume(0.8)
        Queue.drain()
        check(near(m.inputVolume, 0.7), "successful ignored write reads back")
        HAL.ignoreWrites = false
        HAL.writeFails.insert(HAL.key(10))
        m.setInputVolume(0.9)
        Queue.drain()
        check(near(m.inputVolume, 0.7), "failed write reads back")
        m.stop()
        Queue.drain()
        check(m.inputVolume == nil && HAL.listeners.isEmpty, "stop clears volume and observers")
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.4
        m = manager()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(20)] = 0.6
        m.start()
        Queue.drain()
        check(m.inputDevices.count == 2, "starting a running manager reads its devices again")
        m.stop()
        m.start()
        Queue.drain()
        HAL.removals = 0
        m.stop()
        check(HAL.removals == 3 && HAL.listeners.isEmpty, "a restarted manager removes each listener once")
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.6
        HAL.readOnly.insert(HAL.key(10))
        m = manager()
        check(m.inputVolume == nil && !HAL.listeners.contains(HAL.key(10)),
              "read-only gain hidden and not listened to")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10, 1)] = 0.2
        HAL.levels[HAL.key(10, 2)] = 0.8
        m = manager()
        check(near(m.inputVolume, 0.5), "channel mean")
        m.setInputVolume(0.6)
        Queue.drain()
        check(HAL.levels.values.allSatisfy { abs($0 - 0.6) < 0.0001 }, "writes both channels")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)] = 0.5
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(10, 1)] = 0.2
        HAL.levels[HAL.key(10, 2)] = 0.8
        m = manager()
        m.setInputVolume(0.6)
        Queue.drain()
        check(
            HAL.writes.count == 1
                && HAL.writes[0].s == kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            "virtual master preferred and channel balance intact")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.3
        m = manager()
        HAL.devices = [10, 20]
        HAL.current = 20
        HAL.notify(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        Queue.main.run()
        m.setInputVolume(0.8)
        Queue.drain()
        check(
            m.effectiveInputDeviceUID == "device-20" && m.inputVolume == nil
                && !HAL.listeners.contains(HAL.key(10)),
            "device changes during drag clear unsupported volume and the old device's listener")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.4
        m = manager()
        HAL.notify(10, kAudioDevicePropertyVolumeScalar)
        Queue.main.run()
        Queue.main.run()
        HAL.inputQueue.run()
        m.setInputVolume(0.9)
        Queue.main.run()
        check(near(m.inputVolume, 0.9), "older volume result cannot undo latest drag")
        Queue.drain()
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.4
        HAL.listenerFails = true
        HAL.ignoreWrites = true
        m = manager()
        m.setInputVolume(0.9)
        Queue.drain()
        check(near(m.inputVolume, 0.4), "listener failure still reads back ignored writes")
        m.stop()
        HAL.reset()
        HAL.streamChannels[10] = [1, 3]
        for channel: UInt32 in 1...4 { HAL.levels[HAL.key(10, channel)] = 0.5 }
        m = manager()
        m.setInputVolume(0)
        Queue.drain()
        check(
            near(m.inputVolume, 0) && HAL.levels[HAL.key(10, 3)] == 0 && HAL.levels[HAL.key(10, 4)] == 0,
            "all input channels across multiple streams follow the slider")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(
            HAL.muteService.isMuted && HAL.silenced(10),
            "production mute falls back to zero gain")
        m.setInputVolume(0.8)
        Queue.drain()
        check(
            HAL.silenced(10) && HAL.muteService.isMuted,
            "slider preserves the active gain mute")
        HAL.muteService.setMuted(false)
        Queue.drain()
        check(
            !HAL.muteService.isMuted && HAL.levels[HAL.key(10)] == 0.5,
            "explicit unmute restores the saved gain")
        m.setInputVolume(0.8)
        Queue.drain()
        check(near(m.inputVolume, 0.8), "gain remains adjustable after unmute")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.mute[10] = 0
        m = manager()
        HAL.muteService.setMuted(true)
        Queue.drain()
        m.setInputVolume(0.8)
        Queue.drain()
        check(HAL.silenced(10), "hardware mute switch remains silent after gain gesture")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        m.stop()
        Queue.drain()
        check(
            HAL.levels[HAL.key(10)] == 0.5 && m.inputVolume == nil, "stop cancels queued volume writes")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.2
        m = manager()
        HAL.devices = [20]
        HAL.current = 20
        HAL.uids[20] = "device-10"
        HAL.levels[HAL.key(20)] = 0.7
        HAL.notify(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        Queue.main.run()
        HAL.notify(10, kAudioDevicePropertyVolumeScalar)
        Queue.main.run()
        HAL.inputQueue.run()
        Queue.drain()
        check(
            HAL.listeners.contains(HAL.key(20)) && near(m.inputVolume, 0.7),
            "same UID reconnect publishes new gain despite old notification")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.2
        m = manager()
        HAL.devices = [20]
        HAL.current = 20
        HAL.levels[HAL.key(20)] = 0.7
        HAL.notify(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        Queue.main.run()
        HAL.notify(10, kAudioDevicePropertyVolumeScalar)
        Queue.main.run()
        HAL.inputQueue.run()
        Queue.drain()
        check(
            near(m.inputVolume, 0.7),
            "different UID reconnect publishes new gain despite old notification")
        m.stop()
        HAL.reset()
        HAL.streamChannels[10] = [4]
        HAL.levels[HAL.key(10, 3)] = 0.7
        m = manager()
        check(near(m.inputVolume, 0.7), "gain on channel 3 is discovered")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10, 1)] = 0.5
        HAL.levels[HAL.key(10, 2)] = 0.7
        HAL.readOnly.insert(HAL.key(10, 2))
        m = manager()
        m.setInputVolume(0.4)
        Queue.drain()
        check(
            HAL.levels[HAL.key(10, 2)] == 0.7 && near(m.inputVolume, 0.4), "read-only channel left intact"
        )
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(-1)
        Queue.drain()
        check(near(m.inputVolume, 0), "negative volume clamped")
        m.setInputVolume(2)
        Queue.drain()
        check(near(m.inputVolume, 1), "volume above one clamped")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        HAL.notify(10, kAudioDevicePropertyVolumeScalar)
        Queue.main.run()
        m.stop()
        Queue.drain()
        check(m.inputVolume == nil && HAL.listeners.isEmpty, "pending read canceled by stop")
        m.start()
        Queue.drain()
        check(near(m.inputVolume, 0.5), "restart rediscovers volume")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setPreferredInputDeviceUID("missing")
        Queue.drain()
        check(
            m.preferredUnavailable && m.effectiveInputDeviceUID == "device-10"
                && near(m.inputVolume, 0.5), "missing preference uses active input")
        m.setPreferredInputDeviceUID(nil)
        Queue.drain()
        check(
            !m.preferredUnavailable && near(m.inputVolume, 0.5), "clear missing preference preserves gain"
        )
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(20)] = 0.8
        m.setPreferredInputDeviceUID("device-20")
        Queue.drain()
        check(
            HAL.current == 20 && near(m.inputVolume, 0.8), "preferred input selected with its own gain")
        m.stop()
        check(HAL.current == 10, "stop restores original input selection")

        // Audio device priority: a microphone it puts in use becomes the
        // system's own choice, so quitting leaves it there. Only a change made
        // by the saved preferred microphone is undone.
        func priorityManager() -> AudioInputDeviceManager {
            HAL.reset()
            HAL.devices = [10, 20, 30]
            HAL.levels[HAL.key(10)] = 0.5
            HAL.levels[HAL.key(20)] = 0.5
            HAL.levels[HAL.key(30)] = 0.5
            let m = manager()
            m.setInputPriorityActive(true)
            Queue.drain()
            m.setCurrentInputDeviceUID("device-20")
            Queue.drain()
            return m
        }
        m = priorityManager()
        check(HAL.current == 20, "a priority pick becomes the system input")
        m.stop()
        check(HAL.current == 20, "quitting keeps the microphone the priority list picked")
        m = priorityManager()
        m.setInputPriorityActive(false)
        Queue.drain()
        m.stop()
        check(HAL.current == 20, "turning priority off does not make quitting undo its pick")
        m = priorityManager()
        m.setInputPriorityActive(false)
        Queue.drain()
        m.setPreferredInputDeviceUID("device-30")
        Queue.drain()
        check(HAL.current == 30, "the saved preferred microphone takes over once priority is off")
        m.stop()
        check(HAL.current == 20, "quitting then goes back to the microphone the priority list picked")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.6
        m = manager()
        for _ in 0..<20 { HAL.notify(10, kAudioDevicePropertyVolumeScalar) }
        for _ in 0..<21 { Queue.main.run() }
        check(HAL.inputQueue.work.isEmpty, "superseded callback burst does not issue stale read")
        Queue.drain()
        check(
            near(m.inputVolume, 0.6) && HAL.inputQueue.work.isEmpty,
            "callback burst settles without recurring work")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.6
        HAL.readFails.insert(HAL.key(10))
        m = manager()
        check(m.inputVolume == nil, "unreadable gain hidden")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)] = 0.6
        HAL.levels[HAL.key(10)] = 0.6
        HAL.writeFails.insert(HAL.key(10, 0, kAudioHardwareServiceDeviceProperty_VirtualMainVolume))
        m = manager()
        m.setInputVolume(0.2)
        Queue.drain()
        check(
            HAL.writes.count == 2 && HAL.levels[HAL.key(10)] == 0.2,
            "failed virtual master falls back to scalar")
        m.stop()

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(
            HAL.muteService.isMuted && HAL.levels[HAL.key(10)] == 0,
            "mute requested after a queued adjustment wins")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        HAL.muteService.setMuted(true)
        HAL.muteQueue.run()
        Queue.main.run()
        HAL.muteService.setMuted(false)
        HAL.muteQueue.run()
        Queue.main.run()
        Queue.drain()
        check(
            !HAL.muteService.isMuted && HAL.levels[HAL.key(10)] == 0.5,
            "mute and unmute invalidate a drag from before the mute")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        HAL.afterWrite = { HAL.muteService.setMuted(true) }
        m.setInputVolume(0.8)
        Queue.drain()
        check(
            HAL.muteService.isMuted && HAL.levels[HAL.key(10)] == 0,
            "mute serializes after an adjustment already writing")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        HAL.muteService.setMuted(true)
        HAL.muteService.syncWithPreferences()
        m.setInputVolume(0.8)
        Queue.drain()
        check(
            HAL.levels[HAL.key(10)] == 0 && HAL.muteService.isMuted,
            "preference sync cannot reopen a pending mute")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        HAL.writeFails.insert(HAL.key(10))
        HAL.muteService.setMuted(true)
        Queue.drain()
        HAL.writeFails = []
        m.setInputVolume(0.8)
        Queue.drain()
        check(
            !HAL.muteService.isMuted && near(m.inputVolume, 0.8),
            "a failed mute does not permanently disable gain control")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        m.stop()
        m.start()
        Queue.drain()
        check(
            HAL.levels[HAL.key(10)] == 0.5 && near(m.inputVolume, 0.5),
            "stop and restart do not revive an old gain adjustment")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        HAL.current = 20
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(20)] = 0.2
        Queue.drain()
        check(HAL.writes.isEmpty, "current hardware input overrides an outdated cached selection")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        HAL.uids[10] = "replacement"
        Queue.drain()
        check(HAL.writes.isEmpty, "recycled audio object cannot receive an old gain adjustment")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        m.setPreferredInputDeviceUID("missing")
        Queue.drain()
        check(
            HAL.writes.isEmpty && near(m.inputVolume, 0.5),
            "a new preference cancels earlier adjustments even if effective input stays the same")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(.nan)
        m.setInputVolume(.infinity)
        Queue.drain()
        check(
            HAL.writes.isEmpty && near(m.inputVolume, 0.5),
            "nonfinite gain requests do not write or publish")
        m.stop()
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        HAL.afterUIDRead = { m.stop() }
        Queue.drain()
        check(
            HAL.writes.isEmpty && m.inputVolume == nil,
            "stop during hardware identity validation cancels the pending gain write")
        m.stop()

        HAL.reset()
        HAL.streamChannels[10] = []
        m = manager()
        check(m.inputVolume == nil, "zero input channels expose no gain control")
        m.stop()
        HAL.reset()
        HAL.streamReadFails = true
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        Queue.drain()
        check(near(m.inputVolume, 0.8), "master gain works even if channel discovery fails")
        m.stop()
        HAL.reset()
        HAL.streamReadFails = true
        HAL.levels[HAL.key(10, 1)] = 0.5
        m = manager()
        check(m.inputVolume == nil, "channel discovery failure does not guess channel addresses")
        m.stop()
        HAL.reset()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(20)] = 0.5
        HAL.readOnly.insert(HAL.key(20))
        HAL.running = [20]
        Feedback.messages = []
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(
            Feedback.messages == [text.micMutePartialHUD] && HAL.levels[HAL.key(20)] == 0.5,
            "a microphone left open is announced instead of a plain mute")
        HAL.reset()
        HAL.devices = [10, 20]
        HAL.mute[10] = 0
        HAL.mute[20] = 0
        Feedback.messages = []
        HAL.muteService.setMuted(true)
        Queue.drain()
        HAL.writeFails.insert(HAL.key(20, 0, kAudioDevicePropertyMute))
        HAL.muteService.setMuted(false)
        Queue.drain()
        check(
            Feedback.messages == [text.micMutedHUD, text.micUnmutePartialHUD] && HAL.mute[10] == 0 && HAL.mute[20] == 1,
            "a claimed microphone that stays muted is announced instead of a plain unmute")
        HAL.reset()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.mute[20] = 1
        Feedback.messages = []
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(
            Feedback.messages == [text.micMutedHUD] && HAL.silenced(10),
            "every microphone silent, one by the user, still announces a plain mute")
        HAL.muteService.setMuted(false)
        Queue.drain()
        check(HAL.mute[20] == 1 && HAL.levels[HAL.key(10)] == 0.5,
              "unmuting leaves the microphone the user muted themselves")
        HAL.reset()
        HAL.devices = [10, 30]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.aggregates = [30]
        HAL.running = [30]
        Feedback.messages = []
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(
            Feedback.messages == [text.micMutedHUD] && HAL.silenced(10),
            "an aggregate with no mute or level of its own does not make the mute partial")
        HAL.reset()
        HAL.devices = [10, 40]
        HAL.levels[HAL.key(10)] = 0.5
        Feedback.messages = []
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(
            Feedback.messages == [text.micMutedHUD] && HAL.silenced(10),
            "an idle microphone with no mute or level of its own does not make the mute partial")
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        Feedback.showsMicrophone = true
        Feedback.messages = []
        HAL.muteService.setMuted(true)
        Queue.drain()
        HAL.muteService.setMuted(false)
        Queue.drain()
        check(
            Feedback.messages.isEmpty && Feedback.microphone == [true, false],
            "with Dynamic Island showing it, the switch reports there instead of a floating confirmation")
        HAL.reset()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(20)] = 0.5
        HAL.readOnly.insert(HAL.key(20))
        HAL.running = [20]
        Feedback.microphone = []
        Feedback.retractions = 0
        Feedback.messages = []
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(
            Feedback.messages == [text.micMutePartialHUD] && Feedback.microphone.isEmpty,
            "a microphone left open keeps its whole warning in the floating confirmation")
        check(Feedback.retractions == 1,
              "a partial result takes back the island notice of the press before it")
        Feedback.showsMicrophone = false
        Feedback.microphone = []
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(10, 1)] = 1
        HAL.levels[HAL.key(10, 2)] = 0.6
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(
            HAL.muteService.isMuted && HAL.levels[HAL.key(10)] == 0
                && HAL.levels[HAL.key(10, 1)] == 0 && HAL.levels[HAL.key(10, 2)] == 0,
            "a gain mute lowers the main level and every channel")
        HAL.muteService.setMuted(false)
        Queue.drain()
        check(
            HAL.levels[HAL.key(10)] == 0.5 && HAL.levels[HAL.key(10, 1)] == 1
                && HAL.levels[HAL.key(10, 2)] == 0.6,
            "a gain unmute puts back the main level and the balance between channels")
        HAL.reset()
        HAL.levels[HAL.key(10, 1)] = 0.8
        HAL.levels[HAL.key(10, 2)] = 0.4
        HAL.muteService.setMuted(true)
        Queue.drain()
        HAL.muteService.setMuted(false)
        Queue.drain()
        check(
            HAL.levels[HAL.key(10, 1)] == 0.8 && HAL.levels[HAL.key(10, 2)] == 0.4,
            "a device with channel levels only keeps their balance through a gain mute")
        // What a version without saved channel levels leaves behind: the main
        // level and both channels at zero, with only the main level saved.
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0
        HAL.levels[HAL.key(10, 1)] = 0
        HAL.levels[HAL.key(10, 2)] = 0
        HAL.defaults.set(true, forKey: DefaultsKey.micMuteActive)
        HAL.defaults.set(["device-10": 0.5], forKey: DefaultsKey.micMuteSavedVolumes)
        HAL.defaults.set(["device-10"], forKey: DefaultsKey.micMuteMutedDevices)
        HAL.muteService = HAL.makeMute()
        HAL.muteService.syncWithPreferences()
        Queue.drain()
        HAL.muteService.setMuted(false)
        Queue.drain()
        check(
            !HAL.muteService.isMuted && HAL.levels[HAL.key(10)] == 0.5
                && HAL.levels[HAL.key(10, 1)] == 0.5 && HAL.levels[HAL.key(10, 2)] == 0.5,
            "an unmute after updating brings back the channels an earlier version lowered")

        // What the copy of these services never reached.
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(-1)
        check(near(m.inputVolume, 0), "the slider shows the clamped level at once")
        Queue.drain()
        HAL.levels[HAL.key(10)] = 0.3
        HAL.notify(10, kAudioDevicePropertyVolumeScalar)
        Queue.drain()
        check(near(m.inputVolume, 0.3), "a change made elsewhere reaches the slider through the device's notification")
        HAL.notify(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        Queue.main.run()
        m.setInputVolume(0.9)
        HAL.inputQueue.run()
        Queue.main.run()
        check(near(m.inputVolume, 0.9), "a sweep that began before a drag cannot pull the slider back")
        Queue.drain()
        m.stop()

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        m = manager()
        m.setInputVolume(0.8)
        HAL.devices = [10, 20]
        HAL.current = 20
        HAL.uids[20] = "device-10"
        HAL.uids[10] = "replacement"
        Queue.drain()
        check(!HAL.writes.contains(HAL.key(10)), "a gain change never reaches an object whose identity changed")
        m.stop()

        HAL.reset()
        HAL.devices = [10, 20]
        HAL.outputOnly = [20]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(20)] = 0.5
        m = manager()
        check(m.inputDevices.map(\.uid) == ["device-10"], "a device without input streams is not offered as a microphone")
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(HAL.levels[HAL.key(20)] == 0.5, "the mute leaves a device without input streams alone")
        HAL.muteService.setMuted(false)
        Queue.drain()
        m.stop()

        // A notification already on its way when the manager stops.
        HAL.reset()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.levels[HAL.key(20)] = 0.5
        m = manager()
        m.setPreferredInputDeviceUID("device-20")
        Queue.drain()
        HAL.notify(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        m.stop()
        Queue.drain()
        check(HAL.current == 10, "a notification arriving after stop changes no input")

        // Priority over a preferred microphone that was already applied.
        HAL.reset()
        HAL.devices = [10, 20, 30]
        for device: UInt32 in [10, 20, 30] { HAL.levels[HAL.key(device)] = 0.5 }
        m = manager()
        m.setPreferredInputDeviceUID("device-20")
        Queue.drain()
        m.setInputPriorityActive(true)
        Queue.drain()
        m.stop()
        check(HAL.current == 20, "with priority on, quitting keeps the input even after a preferred microphone")
        HAL.reset()
        HAL.devices = [10, 20, 30]
        for device: UInt32 in [10, 20, 30] { HAL.levels[HAL.key(device)] = 0.5 }
        m = manager()
        m.setPreferredInputDeviceUID("device-20")
        Queue.drain()
        m.setInputPriorityActive(true)
        Queue.drain()
        m.setPreferredInputDeviceUID("device-30")
        Queue.drain()
        check(HAL.current == 30 && HAL.defaults.string(forKey: DefaultsKey.preferredInputDevice) == "device-20",
              "with priority on, the picker picks the input and keeps the saved preferred microphone")
        m.setInputPriorityActive(false)
        Queue.drain()
        m.stop()
        check(HAL.current == 30, "a priority pick replaces where an earlier preferred microphone goes back to")

        // The mute's own bookkeeping.
        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(HAL.defaults.bool(forKey: DefaultsKey.micMuteActive), "a mute is saved for the next launch")
        HAL.muteService.setMuted(false)
        HAL.muteService.syncWithPreferences()
        Queue.drain()
        check(!HAL.muteService.isMuted && HAL.levels[HAL.key(10)] == 0.5,
              "a preference sync during an unmute does not mute again")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        Feedback.messages = []
        HAL.muteService.setMuted(true)
        HAL.muteService.setMuted(false)
        Queue.drain()
        check(Feedback.messages == [text.micUnmutedHUD] && HAL.levels[HAL.key(10)] == 0.5,
              "a quick double press announces only the state it ends in")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.muteService.setMuted(true)
        HAL.muteService.unmuteForTeardown()
        Queue.drain()
        check(!HAL.muteService.isMuted && !HAL.defaults.bool(forKey: DefaultsKey.micMuteActive)
                && HAL.levels[HAL.key(10)] == 0.5,
              "a teardown outlasts a mute still in flight")

        HAL.reset()
        HAL.devices = []
        HAL.muteService.setMuted(true)
        Queue.drain()
        HAL.devices = [10]
        HAL.levels[HAL.key(10)] = 0.5
        HAL.muteService.syncWithPreferences()
        Queue.drain()
        check(!HAL.muteService.isMuted && HAL.levels[HAL.key(10)] == 0.5,
              "a mute that reached no microphone is dropped")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.defaults.set(true, forKey: DefaultsKey.micMuteActive)
        HAL.muteService = HAL.makeMute()
        m = manager()
        m.setInputVolume(0.8)
        Queue.drain()
        check(!HAL.writes.contains(HAL.key(10)), "a mute saved by the last run blocks gain changes before it is applied")
        m.stop()

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.ignoreWrites = true
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(!(HAL.defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? []).contains("device-10"),
              "a driver that ignores the level is not recorded as muted")
        HAL.reset()
        HAL.mute[10] = 0
        HAL.ignoreWrites = true
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(!(HAL.defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? []).contains("device-10"),
              "a mute switch that does not move is not recorded as muted")
        HAL.reset()
        HAL.mute[10] = 0
        HAL.levels[HAL.key(10)] = 0.5
        HAL.readOnly.insert(HAL.key(10, 0, kAudioDevicePropertyMute))
        HAL.muteService.setMuted(true)
        Queue.drain()
        check(HAL.mute[10] == 0 && HAL.levels[HAL.key(10)] == 0,
              "a mute switch that cannot be written falls back to the level")

        HAL.reset()
        HAL.levels[HAL.key(10)] = 0.5
        HAL.muteService.setMuted(true)
        Queue.drain()
        HAL.devices = [10, 20]
        HAL.levels[HAL.key(20)] = 0.5
        HAL.notify(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        Queue.drain()
        check(HAL.levels[HAL.key(20)] == 0, "a microphone that arrives while muted is muted as it appears")
        HAL.defaults.set(false, forKey: AppFeature.micMute.availabilityKey)
        HAL.muteService.syncWithPreferences()
        Queue.drain()
        check(!HAL.muteService.isMuted && HAL.levels[HAL.key(10)] == 0.5 && HAL.levels[HAL.key(20)] == 0.5,
              "switching the feature off gives every microphone its level back")
    }
}
