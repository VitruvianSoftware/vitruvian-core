// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

package struct DiskSMARTReading: Equatable {
    package var status: String?
    package var totalReadBytes: UInt64?
    package var totalWrittenBytes: UInt64?
    package var temperatureCelsius: Double?
    package var healthPercent: Int?
    package var powerCycles: UInt64?
    package var powerOnHours: UInt64?
    package var unsafeShutdowns: UInt64?
    package var mediaErrors: UInt64?

    package var hasDetails: Bool {
        status != nil || totalReadBytes != nil || totalWrittenBytes != nil
            || temperatureCelsius != nil || healthPercent != nil
            || powerCycles != nil || powerOnHours != nil
            || unsafeShutdowns != nil || mediaErrors != nil
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(status: String? = nil, totalReadBytes: UInt64? = nil, totalWrittenBytes: UInt64? = nil, temperatureCelsius: Double? = nil, healthPercent: Int? = nil, powerCycles: UInt64? = nil, powerOnHours: UInt64? = nil, unsafeShutdowns: UInt64? = nil, mediaErrors: UInt64? = nil) {
        self.status = status
        self.totalReadBytes = totalReadBytes
        self.totalWrittenBytes = totalWrittenBytes
        self.temperatureCelsius = temperatureCelsius
        self.healthPercent = healthPercent
        self.powerCycles = powerCycles
        self.powerOnHours = powerOnHours
        self.unsafeShutdowns = unsafeShutdowns
        self.mediaErrors = mediaErrors
    }
}

package struct DiskDeviceReading: Identifiable, Equatable {
    package var id: String
    package var name: String
    package var mountPath: String
    /// Stable across renames and remounts, so the eject exclusion list matches
    /// on it as well as on the name and the mount path.
    package var volumeUUID: String?
    package var bsdName: String?
    package var wholeDisk: String?
    package var ioCounterID: String?
    package var fileSystem: String?
    package var totalBytes: UInt64
    package var freeBytes: UInt64
    package var purgeableBytes: UInt64?
    package var usedBytes: UInt64
    package var isInternal: Bool
    package var isRemovable: Bool
    package var isEjectable: Bool
    package var smart: DiskSMARTReading?
    package var readBytesPerSec: Double?
    package var writeBytesPerSec: Double?
    package var totalReadBytes: UInt64?
    package var totalWrittenBytes: UInt64?

    package var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    package var canEject: Bool {
        !isInternal && (isEjectable || isRemovable) && ejectBSDName != nil
    }

    package var ejectBSDName: String? {
        wholeDisk ?? bsdName
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, name: String, mountPath: String, volumeUUID: String? = nil, bsdName: String? = nil, wholeDisk: String? = nil, ioCounterID: String? = nil, fileSystem: String? = nil, totalBytes: UInt64, freeBytes: UInt64, purgeableBytes: UInt64? = nil, usedBytes: UInt64, isInternal: Bool, isRemovable: Bool, isEjectable: Bool, smart: DiskSMARTReading? = nil, readBytesPerSec: Double? = nil, writeBytesPerSec: Double? = nil, totalReadBytes: UInt64? = nil, totalWrittenBytes: UInt64? = nil) {
        self.id = id
        self.name = name
        self.mountPath = mountPath
        self.volumeUUID = volumeUUID
        self.bsdName = bsdName
        self.wholeDisk = wholeDisk
        self.ioCounterID = ioCounterID
        self.fileSystem = fileSystem
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.purgeableBytes = purgeableBytes
        self.usedBytes = usedBytes
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.smart = smart
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
        self.totalReadBytes = totalReadBytes
        self.totalWrittenBytes = totalWrittenBytes
    }
}

package enum DiskMenuBarStyle: String, CaseIterable {
    case percent, free, used

    package static let defaultsKey = DefaultsKey.menuBarDiskStyle

    package static var current: DiskMenuBarStyle {
        DiskMenuBarStyle(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .percent
    }

    package var showsPercentage: Bool { self == .percent }

    package var minimumValue: String { showsPercentage ? "100%" : "1000 GB" }

    package func value(for disk: DiskDeviceReading) -> String {
        switch self {
        case .percent: return MetricFormat.percent(disk.usedFraction)
        case .free: return MetricFormat.diskBytes(disk.freeBytes)
        case .used: return MetricFormat.diskBytes(disk.usedBytes)
        }
    }
}

package struct DiskReading: Equatable {
    package var devices: [DiskDeviceReading] = []

    package var isEmpty: Bool { devices.isEmpty }

    package var uniqueIODevices: [DiskDeviceReading] {
        var seen = Set<String>()
        return devices.filter { device in
            let key = device.ioCounterID ?? device.wholeDisk ?? device.bsdName ?? device.id
            return seen.insert(key).inserted
        }
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(devices: [DiskDeviceReading] = []) {
        self.devices = devices
    }
}

package enum DiskSupport {
    package static let nvmeDataUnitBytes: UInt64 = 512_000

    /// Short user-facing label for a volume format. `type` is the mount table
    /// token (statfs f_fstypename / diskutil FilesystemType); `name` is the
    /// verbose diskutil FilesystemName, used only to tell FAT widths apart.
    package static func fileSystemLabel(type: String?, name: String? = nil) -> String? {
        guard let type = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !type.isEmpty else { return nil }
        switch type {
        case "apfs": return "APFS"
        case "hfs": return "HFS+"
        case "exfat": return "exFAT"
        case "ntfs": return "NTFS"
        case "msdos":
            if let name {
                if name.contains("32") { return "FAT32" }
                if name.contains("16") { return "FAT16" }
                if name.contains("12") { return "FAT12" }
            }
            return "FAT"
        case "cd9660": return "ISO 9660"
        default:
            // Unknown formats only earn a tag when the token already reads
            // like an acronym; anything longer is driver noise, not a format.
            guard (2...6).contains(type.count),
                  type.allSatisfy({ $0.isLetter || $0.isNumber }),
                  type.contains(where: \.isLetter) else { return nil }
            return type.uppercased()
        }
    }

    package static func nvmeBytes(low: UInt64?, high: UInt64?) -> UInt64? {
        guard let low else { return nil }
        let high = high ?? 0
        guard high <= UInt64(UInt32.max) else { return nil }
        let units = low.addingReportingOverflow(high << 32)
        guard !units.overflow else { return nil }
        let bytes = units.partialValue.multipliedReportingOverflow(by: nvmeDataUnitBytes)
        return bytes.overflow ? nil : bytes.partialValue
    }

    package static func celsius(fromSMARTTemperature raw: UInt64?) -> Double? {
        guard let raw else { return nil }
        let value = Double(raw)
        if value > 150 {
            let celsius = value - 273.15
            return (-40...125).contains(celsius) ? celsius : nil
        }
        return (1...125).contains(value) ? value : nil
    }

    package static func healthPercent(fromPercentageUsed used: UInt64?) -> Int? {
        guard let used else { return nil }
        return max(0, min(100, 100 - Int(used)))
    }

    package static func smartReading(status: String?, vendorKeys: [String: Any]?) -> DiskSMARTReading? {
        let keys = vendorKeys ?? [:]
        var reading = DiskSMARTReading()
        reading.status = status?.isEmpty == false ? status : nil
        reading.totalReadBytes = nvmeBytes(low: uint(keys["DATA_UNITS_READ_0"]),
                                           high: uint(keys["DATA_UNITS_READ_1"]))
        reading.totalWrittenBytes = nvmeBytes(low: uint(keys["DATA_UNITS_WRITTEN_0"]),
                                              high: uint(keys["DATA_UNITS_WRITTEN_1"]))
        reading.temperatureCelsius = celsius(fromSMARTTemperature: uint(keys["TEMPERATURE"]))
        reading.healthPercent = healthPercent(fromPercentageUsed: uint(keys["PERCENTAGE_USED"]))
        reading.powerCycles = uint(keys["POWER_CYCLES_0"])
        reading.powerOnHours = uint(keys["POWER_ON_HOURS_0"])
        reading.unsafeShutdowns = uint(keys["UNSAFE_SHUTDOWNS_0"])
        reading.mediaErrors = uint(keys["MEDIA_ERRORS_0"])
        return reading.hasDetails ? reading : nil
    }

    package static func uint(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            let int = number.int64Value
            return int < 0 ? nil : UInt64(int)
        }
        if let string = value as? String {
            return UInt64(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
