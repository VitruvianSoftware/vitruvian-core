// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// Selecting an enabled keyboard input source through the system's Text
/// Input Sources services. Shared by the paths that switch a source while
/// their own surface is up: the Super key tap cycles to the next source, and
/// the Command Bar borrows a Latin layout for the length of a presentation.
package enum InputSourceSelection {
    /// What one enabled source looks like once read out of TIS. Plain values,
    /// so decisions over them stay pure and testable.
    package struct Snapshot: Equatable {
        package let id: String
        /// A layout rather than an input method: a layout types what is
        /// printed on the keys, a method types whatever it is set to produce.
        package let isLayout: Bool
        package let isASCIICapable: Bool

        // Spelled out because a memberwise initializer never leaves its module.
        package init(id: String, isLayout: Bool, isASCIICapable: Bool) {
            self.id = id
            self.isLayout = isLayout
            self.isASCIICapable = isASCIICapable
        }
    }

    // MARK: - Decisions (pure)

    /// The source to borrow when plain Latin typing is wanted, or nil when
    /// there is nothing to switch to: either the current source is already an
    /// ASCII layout, or none is enabled (a Mac set to Cyrillic and Greek
    /// alone has no Latin layout to borrow). First enabled wins, because that
    /// is the order the Input menu shows.
    package static func asciiLayoutID(currentID: String?, snapshots: [Snapshot]) -> String? {
        if let currentID,
           let current = snapshots.first(where: { $0.id == currentID }),
           current.isASCIICapable, current.isLayout {
            return nil
        }
        return snapshots.first { $0.isASCIICapable && $0.isLayout }?.id
    }

    // MARK: - The Super key's cycle

    /// What one step of the cycle reads and does. `live()` is Text Input
    /// Sources, read through the same plumbing as the Command Bar's borrowing.
    package struct Cycle {
        /// The enabled, selectable sources' ids, in the Input menu's order.
        package var enabledIDs: [String]
        /// The current source's id: nil when no source is current at all, and
        /// empty when the current one has no id, which starts the cycle over.
        package var currentSourceID: () -> String?
        /// Selects an enabled source by its id.
        package var select: (_ sourceID: String) -> Void

        // Spelled out because a memberwise initializer never leaves its module.
        package init(enabledIDs: [String],
                     currentSourceID: @escaping () -> String?,
                     select: @escaping (_ sourceID: String) -> Void) {
            self.enabledIDs = enabledIDs
            self.currentSourceID = currentSourceID
            self.select = select
        }

        /// The Mac's sources, listed once for the step. TIS talks to the
        /// text-input server from the main thread.
        package static func live() -> Cycle {
            let sources = InputSourceSelection.selectableInputSources()
            return Cycle(
                enabledIDs: sources.compactMap {
                    InputSourceSelection.inputSourceString($0, property: kTISPropertyInputSourceID)
                },
                currentSourceID: {
                    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
                    else { return nil }
                    return InputSourceSelection.inputSourceString(current, property: kTISPropertyInputSourceID)
                        ?? ""
                },
                select: { sourceID in
                    guard let next = sources.first(where: {
                        InputSourceSelection.inputSourceString($0, property: kTISPropertyInputSourceID) == sourceID
                    }) else { return }
                    _ = TISSelectInputSource(next)
                })
        }
    }

    /// Selects the enabled source after the current one, wrapping round, the
    /// way the Super key cycles. Nothing happens when no source is current or
    /// there is nothing to cycle to.
    package static func selectNextSource(_ cycle: Cycle) {
        guard let currentID = cycle.currentSourceID(),
              let nextID = SuperKeySupport.nextInputSourceID(currentID: currentID.isEmpty ? nil : currentID,
                                                             enabledIDs: cycle.enabledIDs)
        else { return }
        cycle.select(nextID)
    }

    // MARK: - TIS access

    package static func currentSourceID() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return inputSourceString(current, property: kTISPropertyInputSourceID)
    }

    /// Selects an enabled source by its id, answering whether the system
    /// took the request. The two mistakes are not symmetric: recording
    /// against a switch that never lands restores a source the caller never
    /// left — a no-op — while failing to record one that lands strands the
    /// typist on the borrowed layout, so the caller records on acceptance.
    package static func select(sourceID: String) -> Bool {
        guard let source = selectableInputSources().first(where: {
            inputSourceString($0, property: kTISPropertyInputSourceID) == sourceID
        }) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    // MARK: - Shared TIS plumbing

    /// The enabled, selectable keyboard sources, in the order the system
    /// keeps them. TIS talks to the text-input server from the main thread.
    package static func selectableInputSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false) else { return [] }
        let values = list.takeRetainedValue() as NSArray
        return (values as! [TISInputSource]).filter {
            inputSourceString($0, property: kTISPropertyInputSourceCategory)
                == kTISCategoryKeyboardInputSource as String
                && inputSourceBool($0, property: kTISPropertyInputSourceIsSelectCapable)
        }
    }

    package static func snapshots() -> [Snapshot] {
        selectableInputSources().map {
            Snapshot(id: inputSourceString($0, property: kTISPropertyInputSourceID) ?? "",
                     isLayout: inputSourceString($0, property: kTISPropertyInputSourceType)
                         == kTISTypeKeyboardLayout as String,
                     isASCIICapable: inputSourceBool($0, property: kTISPropertyInputSourceIsASCIICapable))
        }
    }

    package static func inputSourceString(_ source: TISInputSource,
                                  property: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    package static func inputSourceBool(_ source: TISInputSource,
                                property: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}
