// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import VitruvianCore
import VitruvianDesign

/// Window-server queries and requests around Spaces, resolved at runtime so a
/// macOS that drops a symbol degrades to the previous behavior (windows on
/// other Spaces stay invisible and unreachable) instead of failing to launch.
///
/// Accessibility cannot describe a window parked on a Space that is not
/// visible: the app's window list omits it and direct element access is
/// refused (measured on macOS 26 and 27). The window server is the only
/// witness that such a window exists, and the only reliable tell between a
/// real parked window and a stale leftover surface: real windows normally
/// belong to at least one Space, leftovers belong to none. Some auxiliary
/// surfaces share a Space with a real window but explicitly opt out of window
/// cycling, so their window-server tag is checked separately.
package enum SpaceWindowBridge {
    private typealias ConnectionID = UInt32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
    }

    private static let connection: ConnectionID = {
        typealias Function = @convention(c) () -> ConnectionID
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: Function.self)()
    }()

    private typealias GetWindowTagsFunction =
        @convention(c) (ConnectionID, CGWindowID, UnsafeMutablePointer<UInt32>, Int) -> CGError
    private static let getWindowTags: GetWindowTagsFunction? = {
        guard let symbol = symbol("CGSGetWindowTags") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowTagsFunction.self)
    }()

    private typealias WindowIsOrderedInFunction =
        @convention(c) (ConnectionID, CGWindowID, UnsafeMutablePointer<UInt8>) -> CGError
    private static let windowIsOrderedIn: WindowIsOrderedInFunction? = {
        guard let symbol = symbol("CGSWindowIsOrderedIn") else { return nil }
        return unsafeBitCast(symbol, to: WindowIsOrderedInFunction.self)
    }()

    /// Unlike on-screen visibility, ordering survives a move to another desktop.
    /// A dismissed surface can retain its desktop assignment without being ordered.
    /// Keep an unavailable query distinct from an explicit ordered-out answer.
    package static func isWindowOrderedIn(_ windowID: CGWindowID) -> Bool? {
        guard connection != 0, let windowIsOrderedIn else { return nil }
        var ordered: UInt8 = 0
        guard windowIsOrderedIn(connection, windowID, &ordered) == .success else { return nil }
        return ordered != 0
    }

    // MARK: - Space membership

    private typealias CopySpacesFunction =
        @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let copySpacesForWindows: CopySpacesFunction? = {
        guard let symbol = symbol("CGSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(symbol, to: CopySpacesFunction.self)
    }()

    /// Whether `spaces(of:)` can actually answer in this session. Callers use
    /// it to tell "this surface belongs to no Space" (the leftover signature)
    /// apart from "the Space queries are unavailable here", so a macOS that
    /// drops the private symbol keeps the pre-existing behavior instead of
    /// misreading every window as a leftover (issue #807).
    package static var canResolveSpaces: Bool {
        connection != 0 && copySpacesForWindows != nil
    }

    /// Every Space (user desktops and fullscreen Spaces alike) containing the
    /// window. Empty for leftover surfaces, and when the query is unavailable.
    package static func spaces(of windowID: CGWindowID) -> [UInt64] {
        guard connection != 0, let copySpacesForWindows else { return [] }
        let mask: Int32 = 0x7
        guard let array = copySpacesForWindows(connection, mask,
                                               [NSNumber(value: windowID)] as CFArray)?
            .takeRetainedValue() as? [NSNumber]
        else { return [] }
        return array.map(\.uint64Value)
    }

    // MARK: - Display topology

    private typealias CopyDisplaySpacesFunction = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private static let copyManagedDisplaySpaces: CopyDisplaySpacesFunction? = {
        guard let symbol = symbol("CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyDisplaySpacesFunction.self)
    }()

    package struct Topology {
        package struct DisplayInfo {
            package let displayID: CGDirectDisplayID?
            package let spaces: [UInt64]
            package let fullscreenSpaces: Set<UInt64>
            package let currentSpace: UInt64?

            // Spelled out because a memberwise initializer never leaves its module.
            package init(displayID: CGDirectDisplayID?, spaces: [UInt64], fullscreenSpaces: Set<UInt64>, currentSpace: UInt64?) {
                self.displayID = displayID
                self.spaces = spaces
                self.fullscreenSpaces = fullscreenSpaces
                self.currentSpace = currentSpace
            }
        }

        /// With separate Spaces, only the island's display controls visibility.
        /// A shared Space applies to every display even if its UUID is absent.
        package func isFullscreen(on displayID: CGDirectDisplayID, separateSpaces: Bool) -> Bool {
            let candidates = separateSpaces ? displays.filter { $0.displayID == displayID } : displays
            return candidates.contains { display in
                display.currentSpace.map { display.fullscreenSpaces.contains($0) } == true
            }
        }

        /// Displays in order.
        package let displays: [DisplayInfo]
        /// Space ids in left-to-right order, one row per display.
        package var orderedSpacesPerDisplay: [[UInt64]] { displays.map(\.spaces) }
        /// The Space currently showing on each display.
        package var visibleSpaces: Set<UInt64> { Set(displays.compactMap(\.currentSpace)) }
        /// Native fullscreen Spaces. Managed-display dictionaries use type 4
        /// for these and type 0 for ordinary desktops on current macOS.
        package var fullscreenSpaces: Set<UInt64> {
            displays.reduce(into: []) { $0.formUnion($1.fullscreenSpaces) }
        }

        // Spelled out because a memberwise initializer never leaves its module.
        package init(displays: [DisplayInfo]) {
            self.displays = displays
        }
    }

    /// Captures AppKit's display identity while the caller is on main. The
    /// resulting values are safe to carry to window-enumeration workers.
    package static func displayIDsByUUID() -> [String: CGDirectDisplayID] {
        var map: [String: CGDirectDisplayID] = [:]
        for screen in NSScreen.screens {
            guard let screenNum = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(screenNum)?.takeRetainedValue(),
                  let uuidStr = CFUUIDCreateString(nil, uuid) as String?
            else { continue }
            map[uuidStr] = screenNum
        }
        return map
    }

    /// Main-thread callers can keep using the AppKit-backed display mapping.
    package static func topology() -> Topology? {
        topology(displayIDsByUUID: displayIDsByUUID())
    }

    /// Resolves Space topology using display values captured by the caller.
    /// This overload does not access AppKit and is safe for worker queues.
    package static func topology(displayIDsByUUID: [String: CGDirectDisplayID]) -> Topology? {
        guard connection != 0, let copyManagedDisplaySpaces,
              let displayDicts = copyManagedDisplaySpaces(connection)?
                .takeRetainedValue() as? [[String: Any]],
              !displayDicts.isEmpty
        else { return nil }

        var displays: [Topology.DisplayInfo] = []
        for display in displayDicts {
            let spaceDictionaries = display["Spaces"] as? [[String: Any]] ?? []
            let row = spaceDictionaries
                .compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            guard !row.isEmpty else { continue }
            let fullscreenSpaces = Set(spaceDictionaries.compactMap { space -> UInt64? in
                guard (space["type"] as? NSNumber)?.intValue == 4 else { return nil }
                return (space["id64"] as? NSNumber)?.uint64Value
            })
            let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
            let uuidStr = display["Display Identifier"] as? String
            let displayID = uuidStr.flatMap { displayIDsByUUID[$0] }
            displays.append(Topology.DisplayInfo(displayID: displayID,
                                                 spaces: row,
                                                 fullscreenSpaces: fullscreenSpaces,
                                                 currentSpace: current?.uint64Value))
        }
        guard !displays.isEmpty else { return nil }
        return Topology(displays: displays)
    }

    private typealias MoveWindowsToSpaceFunction =
        @convention(c) (ConnectionID, CFArray, UInt64) -> Void
    private static let moveWindowsToManagedSpace: MoveWindowsToSpaceFunction? = {
        guard let symbol = symbol("CGSMoveWindowsToManagedSpace") else { return nil }
        return unsafeBitCast(symbol, to: MoveWindowsToSpaceFunction.self)
    }()

    /// The Space showing on the display under `pointer`, an AppKit screen
    /// point. Nil when the Space queries are unavailable, so callers can carry
    /// on without moving anything rather than guessing at a destination.
    package static func visibleSpace(near pointer: CGPoint) -> UInt64? {
        guard let topology = topology() else { return nil }
        return visibleSpace(near: pointer, in: topology, screens: NSScreen.geometries,
                            main: NSScreen.main?.geometry)
    }

    /// The same, for a topology and the displays it was read with. A display
    /// the topology does not list falls back to its first.
    package static func visibleSpace(near pointer: CGPoint, in topology: Topology,
                                     screens: [ScreenGeometry], main: ScreenGeometry?) -> UInt64? {
        if let number = ScreenGeometry.under(pointer, among: screens, fallback: main)?.displayID,
           let display = topology.displays.first(where: { $0.displayID == number }) {
            return display.currentSpace
        }
        return topology.displays.first?.currentSpace
    }

    /// Brings one window onto the Space the pointer's display is showing. A
    /// window dropped from another desktop otherwise takes the position it was
    /// given and stays where nobody can see it.
    @discardableResult
    package static func moveToVisibleSpace(_ windowID: CGWindowID, near pointer: CGPoint) -> Bool {
        guard connection != 0,
              let moveWindowsToManagedSpace,
              let destination = visibleSpace(near: pointer)
        else { return false }
        guard !spaces(of: windowID).contains(destination) else { return true }
        moveWindowsToManagedSpace(connection, [NSNumber(value: windowID)] as CFArray, destination)
        return true
    }

    /// Whether the window sits on at least one Space and none of them is
    /// visible. False when the Space queries are unavailable, so every caller
    /// falls back to the pre-existing behavior.
    package static func isParkedOnHiddenSpace(_ windowID: CGWindowID, visibleSpaces: Set<UInt64>? = nil) -> Bool {
        guard let visible = visibleSpaces ?? topology()?.visibleSpaces else { return false }
        return SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: spaces(of: windowID),
                                                     visibleSpaces: visible)
    }

    /// False when the private query is unavailable, preserving the existing
    /// cross-Space behavior instead of hiding a legitimate window on a guess.
    package static func isExcludedFromWindowCycle(_ windowID: CGWindowID) -> Bool {
        guard connection != 0, let getWindowTags else { return false }
        var tags = [UInt32](repeating: 0, count: 2)
        return tags.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress,
                  getWindowTags(connection, windowID, base,
                                MemoryLayout<UnsafeRawPointer>.size * 8) == .success
            else { return false }
            return SpaceHopSupport.isExcludedFromWindowCycle(windowTagsLow: buffer[0])
        }
    }

    // MARK: - Fronting a specific window

    private typealias SetFrontFunction =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private static let setFrontProcess: SetFrontFunction? = {
        guard let symbol = symbol("_SLPSSetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(symbol, to: SetFrontFunction.self)
    }()

    private typealias PostEventRecordFunction =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private static let postEventRecord: PostEventRecordFunction? = {
        guard let symbol = symbol("SLPSPostEventRecordTo") else { return nil }
        return unsafeBitCast(symbol, to: PostEventRecordFunction.self)
    }()

    private typealias ProcessForPIDFunction =
        @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private static let processForPID: ProcessForPIDFunction? = {
        guard let symbol = symbol("GetProcessForPID") else { return nil }
        return unsafeBitCast(symbol, to: ProcessForPIDFunction.self)
    }()

    /// The window server's calls for fronting a window, each nil when this
    /// macOS lacks it. `live` resolves the private symbols; tests pass doubles
    /// that post nothing.
    package struct FrontingCalls {
        package var processForPID: ((pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus)?
        package var setFrontProcess: ((UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError)?
        package var postEventRecord: ((UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError)?

        package init(processForPID: ((pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus)?,
                     setFrontProcess: ((UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError)?,
                     postEventRecord: ((UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError)?) {
            self.processForPID = processForPID
            self.setFrontProcess = setFrontProcess
            self.postEventRecord = postEventRecord
        }

        package static var live: FrontingCalls {
            FrontingCalls(processForPID: SpaceWindowBridge.processForPID.map { call in { call($0, $1) } },
                          setFrontProcess: SpaceWindowBridge.setFrontProcess.map { call in { call($0, $1, $2) } },
                          postEventRecord: SpaceWindowBridge.postEventRecord.map { call in { call($0, $1) } })
        }
    }

    /// Asks the window server to bring the process forward with this exact
    /// window as the one that comes up front, marked as user-initiated. Older
    /// macOS also travels to the window's Space; current macOS ignores the
    /// Space part, which is why SpaceHop verifies the outcome and escalates.
    /// The follow-up record is a lone press that makes the window key without
    /// clicking any of its content. It has no release, so no control can ever
    /// be activated, and it aims far past the bottom-right of any window. A
    /// point just outside the frame lands on the invisible resize border, and
    /// the repeated focus pass then finished a resize that dragged the
    /// window's top-left corner to the screen's own. An all-ones (NaN) point
    /// is turned back into (0, 0) by some apps, which then click whatever sits
    /// at their top-left corner; a far positive point keeps any such fallback
    /// on the opposite corner.
    /// Returns false when the window server did not take the request, so the
    /// caller can fall back to app-level activation.
    @discardableResult
    package static func frontWindow(_ windowID: CGWindowID, ownerPID: pid_t,
                                    calls: FrontingCalls = .live) -> Bool {
        guard let setFrontProcess = calls.setFrontProcess, let processForPID = calls.processForPID,
              let postEventRecord = calls.postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard processForPID(ownerPID, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        guard setFrontProcess(&psn, windowID, userGenerated) == .success else { return false }
        var targetID = windowID
        var record = [UInt8](repeating: 0, count: 0x100)
        record[0x04] = 0xf8 // declared record length
        record[0x3a] = 0x10
        withUnsafeBytes(of: &targetID) { record.replaceSubrange(0x3c..<0x3c + $0.count, with: $0) }
        // Window-relative location, far past the bottom-right of any window.
        var farPoint = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &farPoint) { record.replaceSubrange(0x20..<0x20 + $0.count, with: $0) }
        record[0x08] = 0x01 // left mouse down alone makes the window key
        return postEventRecord(&psn, &record) == .success
    }

    /// Hands the keyboard to a window and leaves the stacking order alone,
    /// after yabai's window_manager_focus_window_without_raise. Within the app
    /// already in front, the window server moves focus only once the old
    /// window hears it lost focus and the new one that it gained it. Some apps
    /// miss the pair when it arrives at once, so the second half waits 40 ms
    /// without blocking the main thread. If the hover is no longer current
    /// when it ends, the old window gets its focus back only if it still
    /// verifiably holds it.
    package static func focusWithoutRaise(_ windowID: CGWindowID, ownerPID: pid_t,
                                          replacing focusedWindowID: CGWindowID?,
                                          while isCurrent: @escaping @MainActor @Sendable () -> Bool) {
        guard let focusedWindowID else {
            frontWindow(windowID, ownerPID: ownerPID)
            return
        }
        postFocusRecord(focusedWindowID, ownerPID: ownerPID, gained: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            // Scheduled on the main queue, where the hover state lives.
            guard MainActor.assumeIsolated({ isCurrent() }) else {
                if FocusFollowsMouseSupport.shouldRestoreFocus(
                    to: focusedWindowID,
                    reportedFocusedWindowID: WindowActivator.focusedWindowID(for: ownerPID),
                    appIsFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == ownerPID) {
                    postFocusRecord(focusedWindowID, ownerPID: ownerPID, gained: true)
                }
                return
            }
            postFocusRecord(windowID, ownerPID: ownerPID, gained: true)
            frontWindow(windowID, ownerPID: ownerPID)
        }
    }

    private static func postFocusRecord(_ windowID: CGWindowID, ownerPID: pid_t, gained: Bool) {
        guard let processForPID, let postEventRecord else { return }
        var psn = ProcessSerialNumber()
        guard processForPID(ownerPID, &psn) == noErr else { return }
        var targetID = windowID
        var record = [UInt8](repeating: 0, count: 0x100)
        record[0x04] = 0xf8 // declared record length
        record[0x08] = 0x0d
        record[0x8a] = gained ? 0x01 : 0x02
        withUnsafeBytes(of: &targetID) { record.replaceSubrange(0x3c..<0x3c + $0.count, with: $0) }
        _ = postEventRecord(&psn, &record)
    }

    // MARK: - The user's "move a space" shortcut

    private typealias HotKeyValueFunction =
        @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError
    private static let symbolicHotKeyValue: HotKeyValueFunction? = {
        guard let symbol = symbol("CGSGetSymbolicHotKeyValue") else { return nil }
        return unsafeBitCast(symbol, to: HotKeyValueFunction.self)
    }()

    private typealias HotKeyEnabledFunction = @convention(c) (Int32) -> Bool
    private static let symbolicHotKeyEnabled: HotKeyEnabledFunction? = {
        guard let symbol = symbol("CGSIsSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(symbol, to: HotKeyEnabledFunction.self)
    }()

    package enum SpaceDirection {
        case left
        case right

        /// System symbolic hotkey ids for "Move left/right a space".
        package var hotKeyID: Int32 { self == .left ? 79 : 81 }
    }

    /// The two Mission Control overviews, by their system symbolic hotkey ids
    /// (32 is "Mission Control", 33 is "Application windows"). The window
    /// server refuses software-simulated touch gestures, so an overview is
    /// opened the same way the keyboard opens it (issue #1012).
    package enum SpaceOverview {
        case missionControl
        case appExpose

        package var hotKeyID: Int32 { self == .missionControl ? 32 : 33 }
    }

    package struct SpaceShortcut {
        package let keyCode: CGKeyCode
        package let flags: CGEventFlags

        // Spelled out because a memberwise initializer never leaves its module.
        package init(keyCode: CGKeyCode, flags: CGEventFlags) {
            self.keyCode = keyCode
            self.flags = flags
        }
    }

    /// The key combination the system itself has registered for moving one
    /// Space over, honoring user remaps. Nil when the shortcut is disabled or
    /// unreadable, in which case no synthetic travel is attempted.
    package static func spaceShortcut(_ direction: SpaceDirection) -> SpaceShortcut? {
        registeredShortcut(direction.hotKeyID)
    }

    /// The same lookup for the overviews. Nil when the user switched that
    /// shortcut off in System Settings, which is the one honest answer: with
    /// no registered combination there is nothing to press.
    package static func overviewShortcut(_ overview: SpaceOverview) -> SpaceShortcut? {
        registeredShortcut(overview.hotKeyID)
    }

    private static func registeredShortcut(_ hotKeyID: Int32) -> SpaceShortcut? {
        guard let symbolicHotKeyValue, let symbolicHotKeyEnabled else { return nil }
        return registeredShortcut(
            hotKeyID,
            isEnabled: { symbolicHotKeyEnabled($0) },
            value: { id in
                var options: UInt32 = 0
                var keyCode: UInt32 = 0
                var modifiers: UInt32 = 0
                guard symbolicHotKeyValue(id, &options, &keyCode, &modifiers) == .success else { return nil }
                return (keyCode: keyCode, modifiers: modifiers)
            })
    }

    /// The combination registered for `hotKeyID`, from the window server's two
    /// answers about it. A shortcut the user switched off in System Settings
    /// reads as nil even though its old keys are still stored, and is never
    /// asked for them; so does one with no key at all.
    package static func registeredShortcut(
        _ hotKeyID: Int32,
        isEnabled: (Int32) -> Bool,
        value: (Int32) -> (keyCode: UInt32, modifiers: UInt32)?
    ) -> SpaceShortcut? {
        guard isEnabled(hotKeyID), let registered = value(hotKeyID), registered.keyCode != 0
        else { return nil }
        return SpaceShortcut(keyCode: CGKeyCode(registered.keyCode),
                             flags: SpaceHopSupport.eventFlags(fromCarbonModifiers: registered.modifiers))
    }

    /// Replays one press of a Spaces shortcut. The modifiers must match the
    /// registered combination exactly or the system ignores the press.
    package static func pressSpaceShortcut(_ shortcut: SpaceShortcut) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: false)
        else { return }
        down.flags = shortcut.flags
        up.flags = shortcut.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
