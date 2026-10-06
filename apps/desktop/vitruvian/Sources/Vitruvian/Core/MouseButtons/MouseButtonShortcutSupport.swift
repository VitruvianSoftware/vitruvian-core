// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The pure half of the mouse button shortcuts feature: which buttons can
/// carry a shortcut, how the mappings persist and who owns a button when two
/// features could answer the same click.
package enum MouseButtonShortcutSupport {
    /// Buttons a shortcut can live on. CoreGraphics numbers left, right and
    /// middle as 0, 1 and 2; everything from 3 up is an extra button (3 and 4
    /// are the standard Back and Forward side buttons). Left and right never
    /// arrive as extra-button events, and the middle button stays with its
    /// own feature, so mappings start at 3.
    package static let buttonRange: ClosedRange<Int64> = 3...31

    package static let backButtonNumber: Int64 = 3
    package static let forwardButtonNumber: Int64 = 4
    /// Negative values cannot collide with CoreGraphics mouse button numbers.
    /// They let the existing persisted dictionary represent the two directions
    /// of a side wheel without adding another preference or storage format.
    package static let sideWheelLeftInput: Int64 = -2
    package static let sideWheelRightInput: Int64 = -1

    /// A wheel driver can emit several horizontal packets for one physical
    /// move. Keep the first packet for each direction in that burst and let a
    /// quiet gap begin a new move, without a timer or work between events.
    package struct SideWheelGestureGate {
        package static let quietNanoseconds: UInt64 = 250_000_000

        private var lastTimestamp: UInt64?
        private var firedDirections: UInt8 = 0

        package mutating func shouldFire(_ input: Int64, at timestamp: UInt64) -> Bool {
            let bit: UInt8
            switch input {
            case MouseButtonShortcutSupport.sideWheelLeftInput: bit = 1
            case MouseButtonShortcutSupport.sideWheelRightInput: bit = 2
            default: return false
            }

            if let lastTimestamp,
               timestamp >= lastTimestamp,
               timestamp - lastTimestamp <= Self.quietNanoseconds {
                self.lastTimestamp = timestamp
            } else {
                lastTimestamp = timestamp
                firedDirections = 0
            }

            guard firedDirections & bit == 0 else { return false }
            firedDirections |= bit
            return true
        }

        package mutating func reset() {
            lastTimestamp = nil
            firedDirections = 0
        }

        // Spelled out because a default initializer never leaves its module.
        package init() {}
    }

    package static func canMap(_ input: Int64) -> Bool {
        input == sideWheelLeftInput
            || input == sideWheelRightInput
            || buttonRange.contains(input)
    }

    /// Whether an extra mouse button is physically down right now. This is
    /// used only to recover state after the system disabled an event tap: an
    /// Up may have bypassed the tap while it was off, so stale consumed state
    /// must survive only for buttons that are still held.
    package static func isPressed(_ button: Int64, pressedButtons: Int) -> Bool {
        guard button >= 0, button < Int64(Int.bitWidth) else { return false }
        return pressedButtons & (1 << Int(button)) != 0
    }

    /// Resolves only horizontal mouse-wheel movement. Vertical scrolling stays
    /// ordinary scrolling, and the caller first excludes touch gestures.
    package static func sideWheelInput(isContinuous: Bool,
                               vertical: (line: Double, fixedPoint: Double, point: Double),
                               horizontal: (line: Double, fixedPoint: Double, point: Double)) -> Int64? {
        guard vertical.line.isFinite,
              vertical.fixedPoint.isFinite,
              vertical.point.isFinite,
              horizontal.line.isFinite,
              horizontal.fixedPoint.isFinite,
              horizontal.point.isFinite else { return nil }
        let verticalDelta: Double
        let horizontalDelta: Double
        if isContinuous {
            verticalDelta = vertical.point != 0
                ? vertical.point : (vertical.fixedPoint != 0 ? vertical.fixedPoint : vertical.line)
            horizontalDelta = horizontal.point != 0
                ? horizontal.point : (horizontal.fixedPoint != 0 ? horizontal.fixedPoint : horizontal.line)
        } else {
            verticalDelta = vertical.fixedPoint != 0
                ? vertical.fixedPoint : (vertical.line != 0 ? vertical.line : vertical.point)
            horizontalDelta = horizontal.fixedPoint != 0
                ? horizontal.fixedPoint : (horizontal.line != 0 ? horizontal.line : horizontal.point)
        }
        guard horizontalDelta != 0, abs(horizontalDelta) > abs(verticalDelta) else { return nil }
        // AppKit defines a positive horizontal delta as movement to the left.
        return horizontalDelta > 0 ? sideWheelLeftInput : sideWheelRightInput
    }

    /// Mappings persist as a plain dictionary of button number to the same
    /// storage form every other shortcut in the app uses. Anything that does
    /// not parse (a hand-edited plist, an imported backup from a newer
    /// version) is dropped rather than trusted.
    package static func decode(_ raw: [String: String]?) -> [Int64: GlobalShortcut] {
        guard let raw else { return [:] }
        var mappings: [Int64: GlobalShortcut] = [:]
        for (key, value) in raw {
            guard let button = Int64(key), canMap(button),
                  let shortcut = GlobalShortcut(storageValue: value) else { continue }
            mappings[button] = shortcut
        }
        return mappings
    }

    package static func encode(_ mappings: [Int64: GlobalShortcut]) -> [String: String] {
        var raw: [String: String] = [:]
        for (button, shortcut) in mappings where canMap(button) {
            raw[String(button)] = shortcut.storageValue
        }
        return raw
    }

    /// Whether a button fires its shortcut right now, given plain readers so
    /// the rule is testable without touching real defaults. The radial menu
    /// keeps its summoner: a wheel button never doubles as a shortcut.
    package static func firesShortcut(for button: Int64,
                              isAvailable: Bool,
                              isEnabled: Bool,
                              mappings: [Int64: GlobalShortcut],
                              claimedByWheel: (Int64) -> Bool) -> GlobalShortcut? {
        guard isAvailable, isEnabled, !claimedByWheel(button) else { return nil }
        return mappings[button]
    }

    /// What the shortcut tap does with an extra button's press.
    package enum PressRoute: Equatable {
        /// The press goes on to the app untouched.
        case pass
        /// The Settings capture row takes the press it asked for.
        case capture
        /// Held back while it may still become the Spaces and Mission Control
        /// drag, and given back to the app if it never does.
        case holdForSpaces
        /// Taken, with this shortcut typed in its place.
        case fire(GlobalShortcut)
    }

    /// Decides a press in the order the tap must ask. A tap draining an
    /// earlier press claims nothing new. The capture row takes every button
    /// it can map. An app on the exception list keeps its buttons. The drag's
    /// button is held back by this tap, which already receives its drags. Only
    /// then may a mapping fire, and only while the shortcut switch is on: the
    /// drag alone keeps the tap up with that switch off, and a mapping left
    /// behind is inert, its button the app's. `isExcepted` is asked only when
    /// the answer matters, as it may have to ask the window server.
    package static func route(press button: Int64,
                              isDraining: Bool,
                              isCapturing: Bool,
                              isExcepted: () -> Bool,
                              spacesButton: Int64?,
                              isAvailable: Bool,
                              isEnabled: Bool,
                              mappings: [Int64: GlobalShortcut],
                              claimedByWheel: (Int64) -> Bool) -> PressRoute {
        if isDraining { return .pass }
        if isCapturing { return canMap(button) ? .capture : .pass }
        if isExcepted() { return .pass }
        if button == spacesButton { return .holdForSpaces }
        guard let shortcut = firesShortcut(for: button, isAvailable: isAvailable, isEnabled: isEnabled,
                                           mappings: mappings, claimedByWheel: claimedByWheel)
        else { return .pass }
        return .fire(shortcut)
    }

    /// Whether the shortcut tap has to be up. A capture holds it up by itself:
    /// the press being asked for may be the drag's, and the drag's switch is
    /// not the shortcut switch. A bound drag holds it up with the shortcut
    /// switch off for the same reason.
    package static func tapWanted(shortcutsEnabled: Bool, hasMappings: Bool,
                                  isCapturing: Bool, spacesButton: Int64?) -> Bool {
        (shortcutsEnabled && hasMappings) || isCapturing || spacesButton != nil
    }

    /// Whether this feature currently owns the button, for either of the two
    /// jobs it can give one: pressing a shortcut, or driving the Spaces and
    /// Mission Control drag. Mouse navigation asks this from its own tap and
    /// lets an owned button through, the same contract it already keeps with
    /// the radial menu; pure defaults reads, so asking never wakes the
    /// service.
    package static func claimsButton(_ button: Int64) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppFeature.mouseButtonShortcuts.availabilityKey),
              !RadialMenuSupport.claimsMouseButton(button) else { return false }
        // Runs inside a HID tap callback during side-button drags: look up
        // just this button's entry instead of decoding the whole dictionary.
        guard canMap(button) else { return false }
        return hasActiveShortcut(button, defaults) || spacesGestureButton(defaults) == button
    }

    /// The button the Spaces and Mission Control drag is bound to right now,
    /// or nil when the gesture is off, unbound, or the button already belongs
    /// to a shortcut or to the radial menu. Defaults reads only, so both taps
    /// can ask on the hot path.
    package static func spacesGestureButton(_ defaults: UserDefaults = .standard) -> Int64? {
        MouseSpacesGestureSupport.boundButton(
            isAvailable: defaults.bool(forKey: AppFeature.mouseButtonShortcuts.availabilityKey),
            isEnabled: defaults[Preferences.mouseSpacesGestureEnabled],
            button: Int64(defaults[Preferences.mouseSpacesGestureButton]),
            hasShortcut: { hasActiveShortcut($0, defaults) },
            claimedByWheel: RadialMenuSupport.claimsMouseButton)
    }

    /// A stored shortcut that would really fire. A mapping left behind while
    /// the shortcut switch is off is inert, so it holds no claim on a button.
    private static func hasActiveShortcut(_ button: Int64, _ defaults: UserDefaults) -> Bool {
        guard defaults[Preferences.mouseButtonShortcutsEnabled] else { return false }
        let raw = defaults.dictionary(forKey: DefaultsKey.mouseButtonShortcuts) as? [String: String]
        guard let stored = raw?[String(button)] else { return false }
        return GlobalShortcut(storageValue: stored) != nil
    }

    /// The rows in Settings sort by button number so the list never reorders
    /// itself between visits.
    package static func sortedButtons(_ mappings: [Int64: GlobalShortcut]) -> [Int64] {
        mappings.keys.sorted()
    }

    /// What a button is called across the feature: the two standard side
    /// buttons by their job, anything above by the count printed on mouse
    /// software (button number 5 is the sixth button of the mouse).
    package static func buttonName(for button: Int64, strings: MouseButtonFeatureStrings) -> String {
        switch button {
        case sideWheelLeftInput: return strings.sideWheelLeftName
        case sideWheelRightInput: return strings.sideWheelRightName
        case backButtonNumber: return strings.backButtonName
        case forwardButtonNumber: return strings.forwardButtonName
        default: return String(format: strings.otherButtonFormat, Int(button) + 1)
        }
    }
}
