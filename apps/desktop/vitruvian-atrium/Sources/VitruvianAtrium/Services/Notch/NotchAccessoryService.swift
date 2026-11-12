// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import VitruvianCore
import VitruvianDesign

/// What the service reaches outside itself, so a test can stand in for
/// Bluetooth, the preferences and the system monitor.
package struct NotchAccessoryEnvironment {
    package var isEnabled: @MainActor () -> Bool
    /// Who connects and disconnects. Every Bluetooth query runs on the
    /// monitor's own thread, never the main one: macOS holds the first read
    /// until the person answers "Allow Vitruvian to use Bluetooth?", asks
    /// again after an update to an ad hoc signed app, and a device can stall
    /// a later one.
    package var makeConnectionMonitor: @MainActor () -> NotchAccessoryConnectionMonitor
    package var batterySamples: @MainActor () -> AnyPublisher<PeripheralBatterySample, Never>
    package var setBatteryMonitoring: @MainActor (Bool) -> Void

    package init(isEnabled: @escaping @MainActor () -> Bool,
                 makeConnectionMonitor: @escaping @MainActor () -> NotchAccessoryConnectionMonitor,
                 batterySamples: @escaping @MainActor () -> AnyPublisher<PeripheralBatterySample, Never>,
                 setBatteryMonitoring: @escaping @MainActor (Bool) -> Void) {
        self.isEnabled = isEnabled
        self.makeConnectionMonitor = makeConnectionMonitor
        self.batterySamples = batterySamples
        self.setBatteryMonitoring = setBatteryMonitoring
    }

    package static let system = NotchAccessoryEnvironment(
        isEnabled: { NotchAccessorySupport.isEnabled() },
        makeConnectionMonitor: { NotchAccessoryConnectionMonitor() },
        batterySamples: {
            SystemMonitor.shared.$snapshot.map(\.peripheralBatterySample).eraseToAnyPublisher()
        },
        setBatteryMonitoring: { SystemMonitor.shared.setNotchAccessoryMonitoring($0) })
}

/// The system monitor remains the only battery sampler. Native connection
/// notifications report an actual connection, independently of missing readings.
@MainActor
package final class NotchAccessoryService: NSObject {
    package static let shared = NotchAccessoryService()
    private let environment: NotchAccessoryEnvironment
    private lazy var connectionMonitor = environment.makeConnectionMonitor()
    private var subscription: AnyCancellable?
    private var batteryState = NotchAccessoryBatteryState()
    private var active = false
    private var activationTime: TimeInterval = 0
    private var generation = UUID()
    private var pending: [(notice: NotchNotice, device: String, expiresAt: Date)] = []
    private var noticeWork: DispatchWorkItem?
    package init(environment: NotchAccessoryEnvironment = .system) {
        self.environment = environment
        super.init()
    }

    package func syncWithPreferences() {
        guard environment.isEnabled() else { stop(); return }
        guard !active else { return }
        active = true
        activationTime = ProcessInfo.processInfo.systemUptime
        generation = UUID()
        let currentGeneration = generation
        // The baseline is silent, including devices that were already low
        // before the user enabled this feature. Connection baselines are
        // rebuilt silently after lock/sleep; battery episodes survive both.
        //
        // Launch never waits for it: the monitor reads and watches on its own
        // thread, and only an immutable event reaches the main one. A stop or
        // a restart in between changes the generation, which drops a late one.
        connectionMonitor.start { [weak self] event in
            guard let self, self.active, self.generation == currentGeneration,
                  self.environment.isEnabled() else { return }
            self.handleConnection(event)
        }
        subscription = environment.batterySamples()
            .removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] sample in
                guard let self, self.active, self.generation == currentGeneration,
                      self.environment.isEnabled() else { return }
                self.pending.removeAll { queued in
                    queued.notice.level != nil && sample.devices.contains { device in
                        self.batteryState.isFresh(device, in: sample, observedAfter: self.activationTime)
                            && device.name == queued.device
                            && device.percent >= NotchAccessorySupport.recoveryThreshold
                    }
                }
                let text = FeatureStrings.notchActivities(L10n.shared.language)
                for device in self.batteryState.consume(sample, observedAfter: self.activationTime) {
                    self.enqueue(NotchNotice(event: .accessory, title: device.name,
                        detail: text.lowBattery + " · \(device.percent)%",
                        symbol: NotchAccessorySupport.symbol(for: device.kind, name: device.name),
                        level: Double(device.percent) / 100), device: device.name)
                }
            }
        environment.setBatteryMonitoring(true)
    }

    package func stop() {
        batteryState = NotchAccessoryBatteryState()
        suspend()
    }

    package func suspend() {
        guard active else { return }
        active = false
        generation = UUID()
        subscription = nil
        connectionMonitor.stop()
        noticeWork?.cancel(); noticeWork = nil
        pending.removeAll()
        environment.setBatteryMonitoring(false)
    }

    private func handleConnection(_ event: NotchAccessoryConnectionEvent) {
        switch event {
        case let .connected(name, majorClass, minorClass):
            let text = FeatureStrings.notchActivities(L10n.shared.language)
            // The status stays short beside its icon, so the name gets a
            // whole wing to itself before it has to be shortened.
            enqueue(NotchNotice(event: .accessory, title: text.connected, detail: name,
                symbol: NotchAccessorySupport.symbol(name: name, majorClass: majorClass, minorClass: minorClass)),
                    device: name)
        case let .disconnected(name):
            if let name { pending.removeAll { $0.device == name } }
        }
    }

    private func enqueue(_ notice: NotchNotice, device: String) {
        if pending.count >= 8 { pending.removeFirst() }
        pending.append((notice, device, Date().addingTimeInterval(30)))
        if noticeWork == nil { presentNext() }
    }

    private func presentNext() {
        noticeWork = nil
        pending.removeAll { $0.expiresAt <= Date() }
        guard active, environment.isEnabled(), let first = pending.first else { return }
        let notch = NotchService.shared
        if !notch.expanded, notch.captureControls == nil, notch.show(first.notice) { pending.removeFirst() }
        let work = DispatchWorkItem { [weak self] in self?.presentNext() }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchEvent.accessory.duration + 0.1, execute: work)
    }
}
