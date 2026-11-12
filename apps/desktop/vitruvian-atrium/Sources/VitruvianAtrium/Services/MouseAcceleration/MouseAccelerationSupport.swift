// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

package struct MouseAccelerationDeviceIdentity: Codable, Equatable {
    package let vendorID: Int64?
    package let productID: Int64?
    package let locationID: Int64?
    package let transport: String?
    package let physicalUniqueID: String?
    package let serialNumber: String?

    package func matches(_ other: MouseAccelerationDeviceIdentity) -> Bool {
        if let physicalUniqueID, let otherID = other.physicalUniqueID {
            return physicalUniqueID == otherID
        }
        if let serialNumber, let otherSerial = other.serialNumber {
            return serialNumber == otherSerial
        }
        return vendorID == other.vendorID
            && productID == other.productID
            && locationID == other.locationID
            && transport == other.transport
    }

    package var canMatchAcrossRegistryIDs: Bool {
        physicalUniqueID != nil
            || serialNumber != nil
            || ((vendorID ?? 0) > 0 && (productID ?? 0) > 0 && (locationID ?? 0) > 0)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(vendorID: Int64?, productID: Int64?, locationID: Int64?, transport: String?, physicalUniqueID: String?, serialNumber: String?) {
        self.vendorID = vendorID
        self.productID = productID
        self.locationID = locationID
        self.transport = transport
        self.physicalUniqueID = physicalUniqueID
        self.serialNumber = serialNumber
    }
}

package struct MouseAccelerationStoredValue: Codable, Equatable {
    package let rawValue: Int64
    package let isBoolean: Bool

    // Spelled out because a memberwise initializer never leaves its module.
    package init(rawValue: Int64, isBoolean: Bool) {
        self.rawValue = rawValue
        self.isBoolean = isBoolean
    }
}

package struct MouseAccelerationRecoveryEntry: Codable, Equatable {
    package let registryID: UInt64
    package let identity: MouseAccelerationDeviceIdentity
    package let key: String
    package let original: MouseAccelerationStoredValue

    // Spelled out because a memberwise initializer never leaves its module.
    package init(registryID: UInt64, identity: MouseAccelerationDeviceIdentity, key: String, original: MouseAccelerationStoredValue) {
        self.registryID = registryID
        self.identity = identity
        self.key = key
        self.original = original
    }
}

package struct MouseAccelerationRecoveryJournal: Codable, Equatable {
    package let bootTime: Int64
    package var entries: [MouseAccelerationRecoveryEntry]

    package func entry(registryID: UInt64,
               identity: MouseAccelerationDeviceIdentity) -> MouseAccelerationRecoveryEntry? {
        entries.first { $0.registryID == registryID && $0.identity.matches(identity) }
    }

    package func entriesToRestore(preserving connectedDevices: [UInt64: MouseAccelerationDeviceIdentity])
        -> [MouseAccelerationRecoveryEntry] {
        entries.filter { entry in
            guard let identity = connectedDevices[entry.registryID] else { return true }
            return !entry.identity.matches(identity)
        }
    }

    package mutating func upsert(_ entry: MouseAccelerationRecoveryEntry) {
        entries.removeAll { $0.registryID == entry.registryID }
        entries.append(entry)
        entries.sort { $0.registryID < $1.registryID }
    }

    package mutating func remove(registryID: UInt64) {
        entries.removeAll { $0.registryID == registryID }
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(bootTime: Int64, entries: [MouseAccelerationRecoveryEntry]) {
        self.bootTime = bootTime
        self.entries = entries
    }
}

/// A short settling window after hotplug, never a repeating idle timer.
package struct MouseAccelerationReapplySchedule {
    private var generation: UUID?
    private var delays: ArraySlice<TimeInterval> = []

    package mutating func restart() -> UUID {
        let token = UUID()
        generation = token
        delays = [0, 0.25, 0.75, 1.5, 2.5]
        return token
    }

    package func isCurrent(_ token: UUID) -> Bool {
        generation == token
    }

    package mutating func nextDelay(for token: UUID) -> TimeInterval? {
        guard isCurrent(token) else { return nil }
        guard let delay = delays.popFirst() else {
            cancel()
            return nil
        }
        return delay
    }

    package mutating func cancel() {
        generation = nil
        delays = []
    }

    // Spelled out because a default initializer never leaves its module.
    package init() {}
}

package enum MouseAccelerationSupport {
    package static let linearScalingKey = "HIDUseLinearScalingMouseAcceleration"
    package static let pointerAccelerationTypeKey = "HIDPointerAccelerationType"
    package static let pointerAccelerationKey = "HIDPointerAcceleration"
    package static let mouseAccelerationKey = "HIDMouseAcceleration"
    package static let trackpadAccelerationType = "HIDTrackpadAcceleration"

    package static func validatedRegistryID(_ value: UInt64?) -> UInt64? {
        guard let value, value != 0 else { return nil }
        return value
    }

    package static func isRestorableKey(_ key: String) -> Bool {
        key == linearScalingKey || key == pointerAccelerationKey || key == mouseAccelerationKey
    }

    package static func targetValue(for key: String,
                            originalIsBoolean: Bool) -> MouseAccelerationStoredValue {
        if key == linearScalingKey {
            return MouseAccelerationStoredValue(rawValue: 1, isBoolean: originalIsBoolean)
        }
        return MouseAccelerationStoredValue(rawValue: -1, isBoolean: false)
    }
}
