// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
@preconcurrency import IOBluetooth
import VitruvianCore
import VitruvianDesign

/// Who was connected when the first Bluetooth read returned. It is built off
/// the main thread and handed to it once.
package struct NotchAccessoryBaseline: @unchecked Sendable {
    package let addresses: Set<String>
    /// The connected devices themselves, whose disconnects are then watched.
    /// The main thread alone uses them once the read has returned.
    fileprivate let devices: [IOBluetoothDevice]

    package init(addresses: Set<String>) {
        self.addresses = addresses
        devices = []
    }

    fileprivate init(devices: [IOBluetoothDevice]) {
        addresses = Set(devices.compactMap { $0.addressString })
        self.devices = devices
    }
}

/// What the service reaches outside itself, so a test can stand in for
/// Bluetooth, the preferences and the system monitor.
package struct NotchAccessoryEnvironment {
    package var isEnabled: @MainActor () -> Bool
    /// The first Bluetooth read. It runs off the main thread, because macOS
    /// holds it until the person answers "Allow Vitruvian to use Bluetooth?",
    /// and asks again after an update to an ad hoc signed app. Without
    /// permission it returns nobody.
    package var readBaseline: @Sendable () -> NotchAccessoryBaseline
    /// Called on the main thread, and only after the first read has returned.
    package var registerForConnections: @MainActor (_ observer: Any, _ selector: Selector) -> IOBluetoothUserNotification?
    package var batterySamples: @MainActor () -> AnyPublisher<PeripheralBatterySample, Never>
    package var setBatteryMonitoring: @MainActor (Bool) -> Void

    package init(isEnabled: @escaping @MainActor () -> Bool,
                 readBaseline: @escaping @Sendable () -> NotchAccessoryBaseline,
                 registerForConnections: @escaping @MainActor (_ observer: Any, _ selector: Selector) -> IOBluetoothUserNotification?,
                 batterySamples: @escaping @MainActor () -> AnyPublisher<PeripheralBatterySample, Never>,
                 setBatteryMonitoring: @escaping @MainActor (Bool) -> Void) {
        self.isEnabled = isEnabled
        self.readBaseline = readBaseline
        self.registerForConnections = registerForConnections
        self.batterySamples = batterySamples
        self.setBatteryMonitoring = setBatteryMonitoring
    }

    package static let system = NotchAccessoryEnvironment(
        isEnabled: { NotchAccessorySupport.isEnabled() },
        readBaseline: {
            NotchAccessoryBaseline(devices: (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
                .filter { $0.isConnected() })
        },
        registerForConnections: { IOBluetoothDevice.register(forConnectNotifications: $0, selector: $1) },
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
    /// One read at a time: each waits for the person's answer to the
    /// Bluetooth prompt, so a second one queues behind the first.
    private let bluetoothQueue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.notch-accessory.bluetooth",
                                               qos: .utility)
    private var subscription: AnyCancellable?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var batteryState = NotchAccessoryBatteryState()
    package private(set) var connectionState = NotchAccessoryConnectionState()
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
        // Launch never waits for it: the read runs off the main thread, and
        // connections are watched from the moment it returns. A stop or a
        // restart in between changes the generation, which drops a late answer.
        let readBaseline = environment.readBaseline
        bluetoothQueue.async { [weak self] in
            let baseline = readBaseline()
            DispatchQueue.main.async { [weak self] in
                self?.establish(baseline, for: currentGeneration)
            }
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

    private func establish(_ baseline: NotchAccessoryBaseline, for readGeneration: UUID) {
        guard active, generation == readGeneration else { return }
        connectionState.establishBaseline(baseline.addresses)
        baseline.devices.forEach(observeDisconnect)
        connectNotification = environment.registerForConnections(
            self, #selector(deviceConnected(_:device:)))
    }

    package func stop() {
        batteryState = NotchAccessoryBatteryState()
        connectionState = NotchAccessoryConnectionState()
        suspend()
    }

    package func suspend() {
        guard active else { return }
        active = false
        generation = UUID()
        subscription = nil
        connectNotification?.unregister(); connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        noticeWork?.cancel(); noticeWork = nil
        pending.removeAll()
        environment.setBatteryMonitoring(false)
    }

    private func observeDisconnect(_ device: IOBluetoothDevice) {
        guard let id = device.addressString, disconnectNotifications[id] == nil else { return }
        disconnectNotifications[id] = device.register(forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:)))
    }

    // IOBluetooth may call these on any thread; each hops to the main queue.
    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active, self.environment.isEnabled(), device.isConnected(),
                  NotchAccessorySupport.announcesConnection(majorClass: UInt32(device.deviceClassMajor)),
                  let id = device.addressString, self.connectionState.connected(id) else { return }
            self.observeDisconnect(device)
            guard let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            let text = FeatureStrings.notchActivities(L10n.shared.language)
            // The status stays short beside its icon, so the name gets a
            // whole wing to itself before it has to be shortened.
            self.enqueue(NotchNotice(event: .accessory, title: text.connected, detail: name,
                symbol: NotchAccessorySupport.symbol(name: name, majorClass: UInt32(device.deviceClassMajor),
                                                     minorClass: UInt32(device.deviceClassMinor))),
                         device: name)
        }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active, !device.isConnected(), let id = device.addressString else { return }
            self.connectionState.disconnected(id)
            if let name = device.name { self.pending.removeAll { $0.device == name } }
            self.disconnectNotifications.removeValue(forKey: id)?.unregister()
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
