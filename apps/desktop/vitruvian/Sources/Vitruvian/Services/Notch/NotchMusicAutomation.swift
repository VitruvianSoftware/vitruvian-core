// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices
import VitruvianCore
import VitruvianDesign

/// Apple Events stay in this process so consent belongs to this app. Addressing
/// the running PID cannot fall through to the system's currently playing video.
package enum NotchMusicAutomation {
    package struct Target: Equatable {
        package let pid: Int32
        package let bundleIdentifier: String
        package let bundleURL: URL
        /// Nil when Launch Services did not start the player, as for a process
        /// launchd spawned; the bundle checks still bind the process identity.
        package let launched: Date?

        package init?(_ playback: NotchPlayback) {
            guard let pid = playback.track.appPID, let bundle = playback.track.appBundleIdentifier,
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                  app.bundleIdentifier == bundle, let url = app.bundleURL else { return nil }
            self.pid = pid; bundleIdentifier = bundle; bundleURL = url; launched = app.launchDate
        }

        package var isCurrent: Bool {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
            return app.bundleIdentifier == bundleIdentifier && app.bundleURL == bundleURL && app.launchDate == launched
        }
    }

    package enum Access { case granted, consent, denied, unavailable }
    package struct Availability {
        package let target: Target
        package let capabilities: NotchMusicAutomationCapabilities
        package let access: Access

        // Spelled out because a memberwise initializer never leaves its module.
        package init(target: Target, capabilities: NotchMusicAutomationCapabilities, access: Access) {
            self.target = target
            self.capabilities = capabilities
            self.access = access
        }
    }

    package static func inspect(_ target: Target) -> Availability? {
        guard target.isCurrent, let capabilities = NotchMusicAutomationCapabilities.load(bundleURL: target.bundleURL) else { return nil }
        return Availability(target: target, capabilities: capabilities, access: access(to: target))
    }

    package static func access(to target: Target) -> Access {
        guard target.isCurrent else { return .unavailable }
        let address = NSAppleEventDescriptor(processIdentifier: target.pid)
        switch AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventWouldRequireUserConsent): return .consent
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unavailable
        }
    }

    package static func event(_ command: NotchPlaybackCommand, playback: NotchPlayback,
                      capabilities: NotchMusicAutomationCapabilities, pid: Int32) -> NSAppleEventDescriptor? {
        guard pid > 0 else { return nil }
        let address = NSAppleEventDescriptor(processIdentifier: pid)
        if case .seek(let seconds) = command {
            guard seconds.isFinite, (0...604_800).contains(seconds), let position = capabilities.position else { return nil }
            let specifier = NSAppleEventDescriptor.record()
            specifier.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: AEKeyword(keyAEDesiredClass))
            specifier.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
            specifier.setDescriptor(NSAppleEventDescriptor(typeCode: position.code), forKeyword: AEKeyword(keyAEKeyData))
            specifier.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
            guard let property = specifier.coerce(toDescriptorType: typeObjectSpecifier) else { return nil }
            let event = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: kAESetData, targetDescriptor: address,
                                               returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            event.setParam(property, forKeyword: keyDirectObject)
            event.setParam(position.integer ? NSAppleEventDescriptor(int32: Int32(seconds.rounded()))
                           : NSAppleEventDescriptor(double: seconds), forKeyword: keyAEData)
            return event
        }
        guard let code = capabilities.event(for: command, isPlaying: playback.isPlaying) else { return nil }
        return NSAppleEventDescriptor(eventClass: code.eventClass, eventID: code.eventID, targetDescriptor: address,
                                      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    package static func send(_ command: NotchPlaybackCommand, playback: NotchPlayback, availability: Availability,
                     cancellation: DispatchWorkItem, validatedAt: TimeInterval) -> Bool {
        guard !cancellation.isCancelled, availability.target.isCurrent,
              access(to: availability.target) == .granted,
              let event = event(command, playback: playback, capabilities: availability.capabilities, pid: availability.target.pid),
              !cancellation.isCancelled, availability.target.isCurrent,
              ProcessInfo.processInfo.systemUptime - validatedAt < 0.5 else { return false }
        // A timeout may occur after delivery. Never retry a playback action.
        guard let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1) else { return false }
        return (reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0) == 0
    }
}
