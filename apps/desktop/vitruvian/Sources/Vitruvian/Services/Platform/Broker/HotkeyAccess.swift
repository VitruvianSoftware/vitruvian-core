// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The global keys tools hold. A key belongs to a `GlobalShortcutRole`: its
/// combination is the one saved for the role and it is claimed under the
/// role's own preference, so nothing a person saved moves. The host owns
/// the hotkey ids; a tool never sees one.
///
/// A binding is what a tool asked for, whether or not macOS gave the key.
/// It stays until the tool gives it back, so the host can take the key
/// again without the tool asking twice.
@MainActor
package final class HotkeyBindings {
    package struct Environment {
        /// The hotkey for a role, or nil for a role the host holds no key
        /// for. Asked once for each tool and role.
        package var makeHotkey: (GlobalShortcutRole) -> ToolHotkey?
        /// The combination saved for a role now.
        package var savedShortcut: (GlobalShortcutRole) -> GlobalShortcut

        package init(makeHotkey: @escaping (GlobalShortcutRole) -> ToolHotkey?,
                     savedShortcut: @escaping (GlobalShortcutRole) -> GlobalShortcut) {
            self.makeHotkey = makeHotkey
            self.savedShortcut = savedShortcut
        }

        /// The app's own. No role has a key here yet. A role's id moves in
        /// with the tool that holds it, in the same change, so no id is
        /// ever made in two places (`hotkey_ids_are_unique`).
        @MainActor package static let live = Environment(makeHotkey: { _ in nil },
                                                         savedShortcut: { $0.savedShortcut })

        /// Holds no key. For tests of other capabilities.
        package static var inert: Environment {
            Environment(makeHotkey: { _ in nil }, savedShortcut: { $0.defaultShortcut })
        }
    }

    /// A tool, and the role it holds a key for.
    private struct Holder: Hashable {
        let tool: ToolID
        let role: GlobalShortcutRole
    }

    private struct Binding {
        let hotkey: ToolHotkey
        let onRegistered: @MainActor (Bool) -> Void
    }

    private let environment: Environment
    /// Every hotkey made, kept for the life of the app, as the service's
    /// one hotkey was before it was a tool.
    private var hotkeys: [Holder: ToolHotkey] = [:]
    private var bindings: [Holder: Binding] = [:]

    package init(environment: Environment) {
        self.environment = environment
    }

    /// Takes the key of `role` for `tool`, with the combination saved for
    /// the role now. `onPress` hears each press. `onRegistered` hears
    /// whether macOS gave the key, now and each time the host takes it
    /// again. Asked again for a key it holds, it takes nothing twice; asked
    /// after the key was let go or its combination changed, it takes it.
    /// False when the host holds no key for the role.
    package func bind(_ role: GlobalShortcutRole, for tool: ToolID,
                      onPress: @escaping @MainActor () -> Void,
                      onRegistered: @escaping @MainActor (Bool) -> Void) -> Bool {
        let holder = Holder(tool: tool, role: role)
        guard let hotkey = hotkeys[holder] ?? environment.makeHotkey(role) else { return false }
        hotkeys[holder] = hotkey
        hotkey.onPress = { onPress() }
        bindings[holder] = Binding(hotkey: hotkey, onRegistered: onRegistered)
        take(holder)
        return true
    }

    /// Gives the key back. Safe when the tool holds none.
    package func unbind(_ role: GlobalShortcutRole, for tool: ToolID) {
        guard let binding = bindings.removeValue(forKey: Holder(tool: tool, role: role)) else { return }
        binding.hotkey.unregister()
    }

    /// Lets go of each key `tool` asked for whose saved combination
    /// `matches`, and says for which roles. What the tool asked for is
    /// kept: `retake` takes the keys again.
    package func release(of tool: ToolID, where matches: (GlobalShortcut) -> Bool) -> [GlobalShortcutRole] {
        var released: [GlobalShortcutRole] = []
        for (holder, binding) in bindings
        where holder.tool == tool && matches(environment.savedShortcut(holder.role)) {
            binding.hotkey.unregister()
            released.append(holder.role)
        }
        return released
    }

    /// Takes again the keys `release` let go of, for what the tool still
    /// asks for, and tells the tool how each went.
    package func retake(_ roles: [GlobalShortcutRole], for tool: ToolID) {
        for role in roles { take(Holder(tool: tool, role: role)) }
    }

    private func take(_ holder: Holder) {
        guard let binding = bindings[holder] else { return }
        let given = binding.hotkey.sync(enabled: true, shortcut: environment.savedShortcut(holder.role),
                                        storageKey: holder.role.storageKey)
        binding.onRegistered(given)
    }
}

/// The `hotkey` capability: hold the global shortcut of a role.
@MainActor
package struct HotkeyAccess {
    let gate: () -> BrokerRefusal?
    let bindings: HotkeyBindings
    let tool: ToolID

    /// Takes the key saved for `role`. `onPress` hears each press, on the
    /// main thread. `onRegistered` hears whether macOS gave the key, each
    /// time the host takes it; a combination another app holds is not a
    /// refusal. Refused as unavailable for a role of another feature, or
    /// one the host holds no key for. Neither closure is called when the
    /// call is refused.
    @discardableResult
    package func bind(_ role: GlobalShortcutRole, onPress: @escaping @MainActor () -> Void,
                      onRegistered: @escaping @MainActor (Bool) -> Void = { _ in }) -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        guard role.availabilityFeatures.contains(where: { $0.rawValue == tool.rawValue }),
              bindings.bind(role, for: tool, onPress: onPress, onRegistered: onRegistered)
        else { return .unavailable }
        return nil
    }

    /// Gives the key back. Never refused: a tool that was removed in the
    /// hub must still be able to let go.
    package func unbind(_ role: GlobalShortcutRole) {
        bindings.unbind(role, for: tool)
    }
}
