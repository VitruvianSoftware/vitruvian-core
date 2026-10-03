// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import VMStatisticsCompat
import VitruvianCore
import VitruvianDesign

package struct VMStatisticsSnapshot: Equatable {
    package let wiredPages: UInt64
    package let purgeablePages: UInt64
    package let compressorPages: UInt64
    package let externalPages: UInt64
    package let internalPages: UInt64
    package let tagStoragePages: UInt64

    // Spelled out because a memberwise initializer never leaves its module.
    package init(wiredPages: UInt64, purgeablePages: UInt64, compressorPages: UInt64, externalPages: UInt64, internalPages: UInt64, tagStoragePages: UInt64) {
        self.wiredPages = wiredPages
        self.purgeablePages = purgeablePages
        self.compressorPages = compressorPages
        self.externalPages = externalPages
        self.internalPages = internalPages
        self.tagStoragePages = tagStoragePages
    }
}

package enum VMStatisticsDecoder {
    package static let rev1Count = mach_msg_type_number_t(VITRUVIAN_HOST_VM_INFO64_REV1_COUNT)
    package static let rev2Count = mach_msg_type_number_t(VITRUVIAN_HOST_VM_INFO64_REV2_COUNT)
    package static let rev3Count = mach_msg_type_number_t(VITRUVIAN_HOST_VM_INFO64_REV3_COUNT)

    package static func read() -> VMStatisticsSnapshot? {
        var raw = vitruvian_vm_statistics64_rev3_t()
        var returnedCount = mach_msg_type_number_t()
        guard vitruvian_read_vm_statistics64(&raw, &returnedCount) == KERN_SUCCESS else { return nil }
        return decode(raw, returnedCount: returnedCount)
    }

    package static func decode(_ raw: vitruvian_vm_statistics64_rev3_t,
                       returnedCount: mach_msg_type_number_t) -> VMStatisticsSnapshot? {
        guard returnedCount >= rev1Count else { return nil }
        let returnedTaggedStorageFields = returnedCount >= rev3Count
        return VMStatisticsSnapshot(
            wiredPages: UInt64(raw.wire_count),
            purgeablePages: UInt64(raw.purgeable_count),
            compressorPages: UInt64(raw.compressor_page_count),
            externalPages: UInt64(raw.external_page_count),
            internalPages: UInt64(raw.internal_page_count),
            tagStoragePages: returnedTaggedStorageFields ? raw.total_tag_storage_pages : 0)
    }

    package static func validatedTagStoragePages(_ pages: UInt64,
                                         totalBytes: UInt64,
                                         pageSize: UInt64) -> UInt64 {
        guard pageSize > 0, pages <= totalBytes / pageSize else { return 0 }
        return pages
    }
}
