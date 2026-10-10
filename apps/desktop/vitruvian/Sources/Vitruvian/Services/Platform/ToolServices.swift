// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Everything a tool may touch. A tool is built with one and reaches for
/// nothing else. It carries the tool's manifest, so each operation is
/// checked against what this tool declared.
@MainActor
package struct ToolServices {
    package let manifest: ToolManifest
    let broker: CapabilityBroker

    package var notify: NotifyAccess {
        NotifyAccess(gate: gate(.notify), backing: broker.backings.notify)
    }

    package var open: OpenAccess {
        OpenAccess(gate: gate(.open), backing: broker.backings.open)
    }

    package var clipboard: ClipboardAccess {
        ClipboardAccess(gate: { [broker, manifest] capability in broker.refusal(of: capability, for: manifest) },
                        backing: broker.backings.clipboard, watcher: broker.clipboardWatcher, tool: manifest.id)
    }

    package var processes: ProcessesAccess {
        ProcessesAccess(gate: gate(.processes), backing: broker.backings.processes)
    }

    package var storage: StorageAccess {
        StorageAccess(gate: gate(.storage), keys: Set(manifest.preferences.map(\.key)),
                      backing: broker.backings.storage)
    }

    func gate(_ capability: Capability) -> () -> BrokerRefusal? {
        { [broker, manifest] in broker.refusal(of: capability, for: manifest) }
    }
}
