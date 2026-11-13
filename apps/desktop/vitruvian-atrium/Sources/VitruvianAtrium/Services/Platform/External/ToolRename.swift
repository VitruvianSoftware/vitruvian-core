// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianAtriumCore

/// What the app keeps for a tool under its id, moved to a new id when the
/// tool is renamed (`ExternalToolStore.Parts.renamed`). The tool's files,
/// what it saved and its record are the store's to move; this is the rest,
/// all in the app's preferences:
///
/// - the tool's own preferences, `<id>/<name>` (`ExternalToolManifest.storageKey`);
/// - the shortcuts given its commands, keyed `<id>/<command>` inside
///   `toolCommandShortcuts`, and their take-over keys
///   `toolCommandShortcuts.<id>/<command>`;
/// - its command bar rows, `tool.<id>/<command>`, in the pinned and hidden lists;
/// - its place in the island's Extensions tab: the hidden, order and
///   collapsed lists of ids.
///
/// A key already there under the new id is kept, not written over. A
/// command belongs to a tool by its whole id, so another tool whose id only
/// starts the same keeps what it has.
package enum ToolRename {
    package static func carryOverDefaults(from old: ToolID, to new: ToolID, in defaults: UserDefaults) {
        guard old != new else { return }
        let all = defaults.dictionaryRepresentation()
        let oldPrefix = old.rawValue + "/"
        let takeOver = DefaultsKey.toolCommandShortcuts + "."
        for (key, value) in all {
            if key.hasPrefix(oldPrefix) {
                move(key, to: new.rawValue + "/" + key.dropFirst(oldPrefix.count), value, in: defaults, all)
            } else if key.hasPrefix(takeOver + oldPrefix) {
                move(key, to: takeOver + new.rawValue + "/" + key.dropFirst((takeOver + oldPrefix).count),
                     value, in: defaults, all)
            }
        }
        carryOverShortcuts(from: old, to: new, in: defaults)
        for key in [DefaultsKey.commandBarPins, DefaultsKey.commandBarHidden] {
            rewriteList(key, in: defaults) { token in
                token.hasPrefix("tool." + oldPrefix)
                    ? "tool." + new.rawValue + "/" + token.dropFirst(("tool." + oldPrefix).count) : token
            }
        }
        for key in [DefaultsKey.panelHiddenExtensions, DefaultsKey.panelExtensionOrder,
                    DefaultsKey.panelCollapsedExtensions] {
            rewriteList(key, in: defaults) { $0 == old.rawValue ? new.rawValue : $0 }
        }
    }

    private static func move(_ key: String, to newKey: String, _ value: Any, in defaults: UserDefaults,
                             _ all: [String: Any]) {
        if all[newKey] == nil { defaults.set(value, forKey: newKey) }
        defaults.removeObject(forKey: key)
    }

    /// The `toolCommandShortcuts` entries of the old id's commands, under
    /// the new id. The stored text is rewritten as it is, so an entry that
    /// cannot be read as a combination moves with the others.
    private static func carryOverShortcuts(from old: ToolID, to new: ToolID, in defaults: UserDefaults) {
        guard let text = defaults.string(forKey: DefaultsKey.toolCommandShortcuts),
              let data = text.data(using: .utf8),
              var stored = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        var changed = false
        for (key, value) in stored where CommandID(key)?.tool == old {
            let renamed = new.rawValue + "/" + key.dropFirst(old.rawValue.count + 1)
            if stored[renamed] == nil { stored[renamed] = value }
            stored.removeValue(forKey: key)
            changed = true
        }
        guard changed, let out = try? JSONSerialization.data(withJSONObject: stored, options: [.sortedKeys]),
              let outText = String(data: out, encoding: .utf8) else { return }
        defaults.set(outText, forKey: DefaultsKey.toolCommandShortcuts)
    }

    /// Rewrites each item of a list kept as one string, one item a line or
    /// separated by commas, and keeps the separator it had.
    private static func rewriteList(_ key: String, in defaults: UserDefaults, _ rewrite: (String) -> String) {
        guard let raw = defaults.string(forKey: key), !raw.isEmpty else { return }
        let separator: Character = raw.contains("\n") ? "\n" : ","
        let next = raw.split(separator: separator, omittingEmptySubsequences: false)
            .map { item -> String in
                let trimmed = item.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? String(item) : rewrite(trimmed)
            }
            .joined(separator: String(separator))
        if next != raw { defaults.set(next, forKey: key) }
    }
}
