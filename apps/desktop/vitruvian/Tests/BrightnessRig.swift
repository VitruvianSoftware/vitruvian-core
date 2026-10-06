// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianServices

/// A desk of scripted displays for the production `BrightnessService`: what
/// the system reports about each display, a DDC monitor behind each external
/// one, their gamma curves, the reconfiguration call and the lid. The work
/// queue and the main queue wait until drained, and every clock is the
/// rig's, so nothing reaches a real screen or waits on time.
///
/// Everything here runs on the test's own thread; the `@unchecked Sendable`
/// classes only let the service's work-queue closures reach the fakes.
enum BrightnessRig {
    /// Work waits here until drained, in the order it was queued.
    nonisolated final class Queue: @unchecked Sendable {
        var pending: [() -> Void] = []
        func drain() {
            var count = 0
            while !pending.isEmpty {
                count += 1
                precondition(count < 500, "the display work must settle")
                pending.removeFirst()()
            }
        }
    }

    /// An external monitor that speaks DDC/CI: it answers a luminance read
    /// with the real reply format and takes Set VCP writes.
    nonisolated final class Monitor: @unchecked Sendable {
        var current: UInt16
        var maximum: UInt16
        var answersReads = true
        var acceptsWrites = true
        /// Every luminance value written, once per command: the service
        /// sends each packet more than once inside one command.
        private(set) var written: [UInt16] = []
        /// How many times the level was asked for.
        private(set) var reads = 0
        private var requested = false
        private var lastPacket: [UInt8]?

        init(current: UInt16, maximum: UInt16 = 100) {
            self.current = current
            self.maximum = maximum
        }

        func forgetWrites() {
            written = []
            lastPacket = nil
        }

        /// One DDC command ended or began: the next packet is a new write.
        func commandBoundary() {
            lastPacket = nil
        }

        func write(_ bytes: UnsafeMutableRawPointer, count: UInt32) -> Int32 {
            guard acceptsWrites else { return 1 }
            let packet = Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self),
                                                   count: Int(count)))
            if packet == BrightnessSupport.readRequestPacket(code: BrightnessSupport.luminanceCode) {
                if !requested { reads += 1 }
                requested = true
                lastPacket = nil
                return 0
            }
            if packet.count == 6, packet[2] == BrightnessSupport.luminanceCode {
                let value = UInt16(packet[3]) << 8 | UInt16(packet[4])
                if packet != lastPacket { written.append(value) }
                lastPacket = packet
                current = value
            }
            return 0
        }

        func read(_ bytes: UnsafeMutableRawPointer, count: UInt32) -> Int32 {
            guard answersReads, requested else { return 1 }
            requested = false
            var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, BrightnessSupport.luminanceCode, 0x00,
                                  UInt8(maximum >> 8), UInt8(maximum & 0xFF),
                                  UInt8(current >> 8), UInt8(current & 0xFF)]
            reply.append(reply.reduce(UInt8(0x50)) { $0 ^ $1 })
            let target = bytes.assumingMemoryBound(to: UInt8.self)
            for (index, byte) in reply.prefix(Int(count)).enumerated() { target[index] = byte }
            return 0
        }
    }

    /// One display as the system describes it.
    nonisolated final class Display: @unchecked Sendable {
        let id: CGDirectDisplayID
        var online = true
        var active = true
        var builtIn = false
        var asleep = false
        var virtual = false
        var fingerprint: String
        /// Where it hangs off the IORegistry, which keys its DDC path.
        var location: String
        /// The level the system pipeline reports; nil when it does not answer.
        var systemLevel: Float?
        var monitor: Monitor?
        /// The display's own curve; nil when it cannot be read.
        var curve: BrightnessService.GammaCurve? = Display.identityCurve
        /// What is on screen now, and every curve written.
        var shown: BrightnessService.GammaCurve?
        var gammaWrites: [BrightnessService.GammaCurve] = []

        static let identityCurve = BrightnessService.GammaCurve(red: [0, 0.5, 1], green: [0, 0.5, 1],
                                                              blue: [0, 0.5, 1])

        init(id: CGDirectDisplayID, monitor: Monitor? = nil, systemLevel: Float? = nil) {
            self.id = id
            self.monitor = monitor
            self.systemLevel = systemLevel
            fingerprint = "monitor-\(id)"
            location = "port-\(id)"
        }

        /// The DDC path the service keys this display's choices by.
        var pathKey: String { "\(fingerprint)|\(location)" }
        /// The picture's scale: 1 for its own curve, lower while dimmed.
        var pictureScale: Float? {
            guard let shown, let curve, let peak = curve.red.last, peak > 0 else { return nil }
            return (shown.red.last ?? 0) / peak
        }
    }

    /// The system brightness pipeline, and what its easing call does.
    enum Easing { case lands, refused, ignored }

    nonisolated final class Desk: @unchecked Sendable {
        let work = Queue()
        let main = Queue()
        var displays: [Display] = []
        let defaults: UserDefaults
        private let suiteName: String
        var clock = Date(timeIntervalSince1970: 1_000_000)
        private var uptime: UInt64 = 0

        // System pipeline
        var easing = Easing.lands
        var easingAvailable = true
        var systemCalls: [String] = []

        // Display power
        var configureAvailable = true
        var configureSucceeds = true
        var configurations: [String] = []
        /// What the lid reads. Scripted reads are taken first.
        var lidClosed: Bool? = false
        var lidReads: [Bool?] = []
        var lidSubscriptions = 0
        var lidStops = 0
        /// Runs while subscribing, before the service rechecks the lid.
        var onLidSubscribe: (() -> Void)?
        private var lidChanged: (@MainActor () -> Void)?
        var isWatchingLid: Bool { lidChanged != nil }

        /// DDC writes and picture changes in the order they reached a screen.
        var events: [String] = []
        var gammaSucceeds = true

        // Island and overlay
        var islandShowsBrightness = false
        var overlays: [String] = []

        /// The names the main thread reads from the screens.
        var screenNames: [CGDirectDisplayID: String] = [:]
        /// How many times the display list or a display's description was
        /// asked for: each one is a question for the display server.
        private(set) var displayQueries = 0
        /// What the service's main-thread check answers.
        var onMainThread = true

        let screens = NotificationCenter()
        let workspace = NotificationCenter()
        /// Delayed main-thread work, run with `runDelayed()`.
        var delayed: [DispatchWorkItem] = []

        /// `custom` stands in for the rig's own scratch suite; its owner
        /// clears it.
        init(defaults custom: UserDefaults? = nil) {
            let suiteName = "vitru.tests.brightness-rig-\(UUID().uuidString)"
            self.suiteName = suiteName
            defaults = custom ?? UserDefaults(suiteName: suiteName)!
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }

        func display(_ id: CGDirectDisplayID) -> Display {
            displays.first { $0.id == id }!
        }

        func drain() {
            while !work.pending.isEmpty || !main.pending.isEmpty {
                work.drain()
                main.drain()
            }
        }

        func runDelayed() {
            let items = delayed
            delayed = []
            for item in items where !item.isCancelled { item.perform() }
            drain()
        }

        func advance(seconds: TimeInterval) {
            clock = clock.addingTimeInterval(seconds)
        }

        /// The lid moves: the service hears about it on the main queue.
        func lidMoved(closed: Bool?) {
            lidClosed = closed
            if let lidChanged { main.pending.append { MainActor.assumeIsolated { lidChanged() } } }
        }

        private func readLid() -> Bool? {
            lidReads.isEmpty ? lidClosed : lidReads.removeFirst()
        }

        var environment: BrightnessService.Environment {
            BrightnessService.Environment(
                work: { [work] job in work.pending.append(job) },
                workSync: { job in job() },
                main: { [main] job in main.pending.append { MainActor.assumeIsolated { job() } } },
                defaults: defaults,
                now: { [unowned self] in self.clock },
                hardware: hardware,
                power: power,
                screenNotifications: screens,
                wakeNotifications: workspace,
                schedule: { [unowned self] _, item in self.delayed.append(item) },
                showInIsland: { [unowned self] _ in self.islandShowsBrightness },
                showOverlay: { [unowned self] id, level in
                    self.overlays.append("\(id):\(String(format: "%.3f", level))")
                },
                tearDownOverlay: {},
                followsKeys: false,
                isMainThread: { [unowned self] in self.onMainThread })
        }

        private var hardware: BrightnessService.Hardware {
            var ease: ((CGDirectDisplayID, Float) -> Int32)?
            if easingAvailable {
                ease = { [unowned self] id, change in
                    self.systemCalls.append("ease \(change)")
                    switch self.easing {
                    case .lands:
                        let display = self.displays.first { $0.id == id }
                        display?.systemLevel = (display?.systemLevel ?? 0) + change
                        return 0
                    case .refused: return 1000
                    case .ignored: return 0
                    }
                }
            }
            return BrightnessService.Hardware(
                onlineDisplays: { [unowned self] in
                    self.displayQueries += 1
                    return self.displays.filter(\.online).map(\.id)
                },
                activeDisplays: { [unowned self] in
                    self.displayQueries += 1
                    return Set(self.displays.filter { $0.online && $0.active }.map(\.id))
                },
                info: { [unowned self] id in
                    self.displayQueries += 1
                    guard let display = self.displays.first(where: { $0.id == id }) else { return nil }
                    // The IOKit key that names a display's registry location.
                    return ["IODisplayLocation": display.location,
                            "kCGDisplayIsVirtualDevice": display.virtual] as NSDictionary
                },
                mirrors: { _ in false },
                isBuiltIn: { [unowned self] id in self.displays.first { $0.id == id }?.builtIn ?? false },
                isAsleep: { [unowned self] id in self.displays.first { $0.id == id }?.asleep ?? false },
                fingerprint: { [unowned self] id in self.displays.first { $0.id == id }?.fingerprint ?? "" },
                screenNames: { [unowned self] in self.screenNames },
                getBrightness: { [unowned self] id, level in
                    guard let reported = self.displays.first(where: { $0.id == id })?.systemLevel else { return 1 }
                    level.pointee = reported
                    return 0
                },
                setBrightness: { [unowned self] id, value in
                    self.systemCalls.append("set \(value)")
                    self.displays.first { $0.id == id }?.systemLevel = value
                    return 0
                },
                setBrightnessSmooth: ease,
                externalServices: { [unowned self] in
                    self.displays.enumerated().compactMap { index, display in
                        guard display.online, let monitor = display.monitor else { return nil }
                        return BrightnessService.ExternalService(
                            identity: BrightnessSupport.ServiceIdentity(ioDisplayLocation: display.location,
                                                                        ordinal: index + 1),
                            service: monitor)
                    }
                },
                writeI2C: { [unowned self] service, _, _, bytes, count in
                    let monitor = service as! Monitor
                    let before = monitor.written.count
                    let result = monitor.write(bytes, count: count)
                    if monitor.written.count > before, let value = monitor.written.last {
                        self.events.append("ddc:\(value)")
                    }
                    return result
                },
                readI2C: { service, _, _, bytes, count in (service as! Monitor).read(bytes, count: count) },
                pause: { _ in },
                uptimeMicroseconds: { [unowned self] in
                    // Read at the start and end of every DDC command.
                    for display in self.displays { display.monitor?.commandBoundary() }
                    self.uptime += 100_000
                    return self.uptime
                },
                readGamma: { [unowned self] id, _ in self.displays.first { $0.id == id }?.curve },
                writeGamma: { [unowned self] id, curve in
                    guard let display = self.displays.first(where: { $0.id == id }) else { return false }
                    let peak = display.curve?.red.last ?? 1
                    self.events.append("picture:\((curve.red.last ?? 0) / (peak > 0 ? peak : 1))")
                    guard self.gammaSucceeds else { return false }
                    display.gammaWrites.append(curve)
                    display.shown = curve
                    return true
                })
        }

        private var power: BrightnessService.Power {
            var configure: (@MainActor (CGDirectDisplayID, Bool) -> Bool)?
            if configureAvailable {
                configure = { [unowned self] id, enabled in
                    self.configurations.append("\(enabled ? "on" : "off"):\(id)")
                    self.events.append("\(enabled ? "on" : "off"):\(id)")
                    guard self.configureSucceeds else { return false }
                    // A disabled display leaves even the online list.
                    if let display = self.displays.first(where: { $0.id == id }) {
                        display.online = enabled
                        display.active = enabled
                    }
                    return true
                }
            }
            return BrightnessService.Power(
                configure: configure,
                lidClosed: { [unowned self] in self.readLid() },
                observeLid: { [unowned self] changed in
                    self.lidSubscriptions += 1
                    self.lidChanged = changed
                    self.onLidSubscribe?()
                    return { [unowned self] in
                        self.lidStops += 1
                        self.lidChanged = nil
                    }
                })
        }
    }
}
