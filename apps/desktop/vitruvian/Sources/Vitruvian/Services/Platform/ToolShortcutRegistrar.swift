// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Combine
import VitruvianCore

/// What the registrar needs of a global hotkey. `QuickToolHotkey` is one; a
/// test passes a double that registers nothing.
///
/// `sync` asked again for the combination it already holds must do nothing:
/// the registrar relies on that to leave a working key alone.
package protocol ToolHotkey: AnyObject {
    var onPress: (() -> Void)? { get set }
    /// False when macOS would not give the combination.
    @discardableResult func sync(enabled: Bool, shortcut: GlobalShortcut, storageKey: String) -> Bool
    func unregister()
}

extension QuickToolHotkey: ToolHotkey {}

/// Turns the shortcuts people gave to tool commands into keys that work.
///
/// It is tied to no hub feature, so nothing re-syncs it for free. It syncs
/// at launch (`AppDelegate`), whenever the registry changes (it watches
/// `revision`), and when a shortcut recording ends (`ShortcutCapture.end`),
/// because recording releases every key the app holds.
///
/// Only `assign` writes what is saved. `sync` reads it and never changes it,
/// so a shortcut outlives a tool that is switched off or not registered.
@MainActor
package final class ToolShortcutRegistrar: ObservableObject {
    /// First made by `AppDelegate`, after the app's tools are registered, so
    /// it does not hear the registry fill up at launch.
    package static let shared = ToolShortcutRegistrar(environment: .live)

    /// The first id of this registrar's run, clear of every other hotkey's
    /// (`hotkey_ids_are_unique` in bazel/source_lints.py). The run is
    /// `ToolCommandShortcuts.limit` long. It sits below the wheels' run,
    /// which starts at 1700 and has no end, so nothing above 1700 is free.
    package static let firstHotkeyID: UInt32 = 1000

    @MainActor
    package struct Environment {
        package var registry: ToolRegistry
        package var shortcuts: () -> [String: GlobalShortcut]
        package var save: ([String: GlobalShortcut]) -> Void
        package var makeHotkey: (UInt32) -> ToolHotkey
        /// True while a shortcut field is listening: no key may be held then.
        package var isRecording: () -> Bool
        /// What a key does when its command cannot run.
        package var refuse: () -> Void
        package var setTakeOver: (String, Bool) -> Void

        package init(registry: ToolRegistry, shortcuts: @escaping () -> [String: GlobalShortcut],
                     save: @escaping ([String: GlobalShortcut]) -> Void,
                     makeHotkey: @escaping (UInt32) -> ToolHotkey, isRecording: @escaping () -> Bool,
                     refuse: @escaping () -> Void, setTakeOver: @escaping (String, Bool) -> Void) {
            self.registry = registry
            self.shortcuts = shortcuts
            self.save = save
            self.makeHotkey = makeHotkey
            self.isRecording = isRecording
            self.refuse = refuse
            self.setTakeOver = setTakeOver
        }

        package static var live: Environment {
            Environment(
                registry: .shared,
                shortcuts: { ToolCommandShortcuts.load(from: .standard) },
                save: { ToolCommandShortcuts.save($0, to: .standard) },
                makeHotkey: { QuickToolHotkey(id: $0) },
                isRecording: { ShortcutCapture.isCapturing },
                refuse: { NSSound.beep() },
                setTakeOver: { SystemShortcutTakeover.setTakeOver($0, $1) })
        }
    }

    /// Commands whose combination macOS would not give: another app holds it.
    @Published package private(set) var refused: Set<CommandID> = []

    /// A command's hotkey and its place in the run. Both stay with the
    /// command for as long as it holds a key.
    private struct Held {
        let hotkey: ToolHotkey
        let place: Int
    }

    private let environment: Environment
    private var held: [CommandID: Held] = [:]
    private var watching: AnyCancellable?

    package init(environment: Environment) {
        self.environment = environment
        // `revision` publishes before it changes, but the registry has
        // already changed by then: it bumps the count last.
        watching = environment.registry.$revision.dropFirst().sink { [weak self] _ in self?.sync() }
    }

    /// Every saved shortcut, whether or not its command is here to use it.
    package var shortcuts: [String: GlobalShortcut] { environment.shortcuts() }

    /// One key per shortcut whose command asks for one and is switched on,
    /// and not one more. Nothing saved is changed.
    ///
    /// A key whose command and combination did not change is left as it is:
    /// letting go of it and taking it again could lose it to another app.
    package func sync() {
        // A field is listening. `ShortcutCapture.begin` released the keys;
        // `ShortcutCapture.end` calls back here to take them again.
        guard !environment.isRecording() else {
            for entry in held.values { entry.hotkey.unregister() }
            return
        }
        let wanted = wantedShortcuts()
        for (id, entry) in held where wanted[id] == nil {
            entry.hotkey.unregister()
            held[id] = nil
        }
        var refused: Set<CommandID> = []
        for (id, shortcut) in wanted.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let entry = held[id] ?? hold(id) else { continue }
            // A combination another app already holds is refused by the
            // system. The hotkey is kept, and asked again at the next sync.
            if !entry.hotkey.sync(enabled: true, shortcut: shortcut,
                                  storageKey: ToolCommandShortcuts.takeOverKey(for: id)) {
                refused.insert(id)
            }
        }
        if refused != self.refused { self.refused = refused }
    }

    /// Gives `id` a shortcut, or clears it with nil, and re-syncs. The caller
    /// has already checked the combination is free; were another command
    /// still holding it, it moves here, as a Command Bar row's does.
    package func assign(_ shortcut: GlobalShortcut?, to id: CommandID) {
        objectWillChange.send()
        if shortcut == nil { environment.setTakeOver(ToolCommandShortcuts.takeOverKey(for: id), false) }
        environment.save(ShortcutMap.setting(shortcut, for: id.rawValue, in: environment.shortcuts(),
                                             limit: ToolCommandShortcuts.limit))
        sync()
    }

    /// The saved shortcuts that should be keys now, at most as many as the
    /// run has ids. With no command asking, what is saved is not even read.
    private func wantedShortcuts() -> [CommandID: GlobalShortcut] {
        let asking = Set(environment.registry.commands(on: .shortcut).map(\.id))
        guard !asking.isEmpty else { return [:] }
        var wanted: [CommandID: GlobalShortcut] = [:]
        for (text, shortcut) in environment.shortcuts().sorted(by: { $0.key < $1.key }) {
            guard wanted.count < ToolCommandShortcuts.limit else { break }
            guard let id = CommandID(text), asking.contains(id), ShortcutMap.isUsable(shortcut) else { continue }
            wanted[id] = shortcut
        }
        return wanted
    }

    /// A hotkey for `id` at the first free place in the run, or nil when the
    /// run is full. An id is never made outside the run.
    private func hold(_ id: CommandID) -> Held? {
        let taken = Set(held.values.map(\.place))
        guard let place = (0 ..< ToolCommandShortcuts.limit).first(where: { !taken.contains($0) }) else { return nil }
        let hotkey = environment.makeHotkey(Self.firstHotkeyID + UInt32(place))
        hotkey.onPress = { [weak self] in self?.pressed(id) }
        let entry = Held(hotkey: hotkey, place: place)
        held[id] = entry
        return entry
    }

    private func pressed(_ id: CommandID) {
        if !environment.registry.run(id) { environment.refuse() }
    }
}
