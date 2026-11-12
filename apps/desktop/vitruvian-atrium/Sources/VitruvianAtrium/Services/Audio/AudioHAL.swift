// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreAudio
import Foundation

/// The CoreAudio object property calls the input and mute services make,
/// spelled the way CoreAudio spells them. `live` is CoreAudio itself.
package struct AudioHAL: @unchecked Sendable {
    package typealias Address = UnsafePointer<AudioObjectPropertyAddress>

    package var hasProperty: (AudioObjectID, Address) -> Bool
    package var isPropertySettable: (AudioObjectID, Address, UnsafeMutablePointer<DarwinBoolean>) -> OSStatus
    package var getPropertyDataSize: (AudioObjectID, Address, UInt32, UnsafeRawPointer?,
                                      UnsafeMutablePointer<UInt32>) -> OSStatus
    package var getPropertyData: (AudioObjectID, Address, UInt32, UnsafeRawPointer?,
                                  UnsafeMutablePointer<UInt32>, UnsafeMutableRawPointer) -> OSStatus
    package var setPropertyData: (AudioObjectID, Address, UInt32, UnsafeRawPointer?,
                                  UInt32, UnsafeRawPointer) -> OSStatus
    package var addPropertyListener: (AudioObjectID, Address, AudioObjectPropertyListenerProc,
                                      UnsafeMutableRawPointer?) -> OSStatus
    package var removePropertyListener: (AudioObjectID, Address, AudioObjectPropertyListenerProc,
                                         UnsafeMutableRawPointer?) -> OSStatus

    package init(hasProperty: @escaping (AudioObjectID, Address) -> Bool,
                 isPropertySettable: @escaping (AudioObjectID, Address, UnsafeMutablePointer<DarwinBoolean>) -> OSStatus,
                 getPropertyDataSize: @escaping (AudioObjectID, Address, UInt32, UnsafeRawPointer?,
                                                 UnsafeMutablePointer<UInt32>) -> OSStatus,
                 getPropertyData: @escaping (AudioObjectID, Address, UInt32, UnsafeRawPointer?,
                                             UnsafeMutablePointer<UInt32>, UnsafeMutableRawPointer) -> OSStatus,
                 setPropertyData: @escaping (AudioObjectID, Address, UInt32, UnsafeRawPointer?,
                                             UInt32, UnsafeRawPointer) -> OSStatus,
                 addPropertyListener: @escaping (AudioObjectID, Address, AudioObjectPropertyListenerProc,
                                                 UnsafeMutableRawPointer?) -> OSStatus,
                 removePropertyListener: @escaping (AudioObjectID, Address, AudioObjectPropertyListenerProc,
                                                    UnsafeMutableRawPointer?) -> OSStatus) {
        self.hasProperty = hasProperty
        self.isPropertySettable = isPropertySettable
        self.getPropertyDataSize = getPropertyDataSize
        self.getPropertyData = getPropertyData
        self.setPropertyData = setPropertyData
        self.addPropertyListener = addPropertyListener
        self.removePropertyListener = removePropertyListener
    }

    package static let live = AudioHAL(
        hasProperty: { AudioObjectHasProperty($0, $1) },
        isPropertySettable: { AudioObjectIsPropertySettable($0, $1, $2) },
        getPropertyDataSize: { AudioObjectGetPropertyDataSize($0, $1, $2, $3, $4) },
        getPropertyData: { AudioObjectGetPropertyData($0, $1, $2, $3, $4, $5) },
        setPropertyData: { AudioObjectSetPropertyData($0, $1, $2, $3, $4, $5) },
        addPropertyListener: { AudioObjectAddPropertyListener($0, $1, $2, $3) },
        removePropertyListener: { AudioObjectRemovePropertyListener($0, $1, $2, $3) })
}

/// A serial queue the audio services run their CoreAudio calls on. `live`
/// is a dispatch queue of its own.
package struct AudioWorkQueue: Sendable {
    package var async: @Sendable (@escaping @Sendable () -> Void) -> Void
    /// Runs work after everything already queued, and waits for it.
    package var sync: @Sendable (() -> Void) -> Void

    package init(async: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                 sync: @escaping @Sendable (() -> Void) -> Void) {
        self.async = async
        self.sync = sync
    }

    package static func live(label: String) -> AudioWorkQueue {
        let queue = DispatchQueue(label: label, qos: .userInitiated)
        return AudioWorkQueue(async: { queue.async(execute: $0) }, sync: { queue.sync(execute: $0) })
    }
}
