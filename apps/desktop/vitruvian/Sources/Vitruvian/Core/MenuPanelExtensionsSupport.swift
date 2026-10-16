// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The rules of the menu bar panel's Extensions tab, over the saved
/// preferences alone, so the tests reach them without a store or a view.
///
/// The tab shows each extension's island page. Whether the tab itself is on
/// is the panel's ordinary switch (`DefaultsKey.panelShowExtensions`), with
/// one difference: until the person flips it, it follows whether any
/// extension has an island page. Each extension also has a switch of its
/// own for the tab, on until the person turns it off; the ones turned off
/// are saved as their tool ids (`DefaultsKey.panelHiddenExtensions`).
package enum MenuPanelExtensionsSupport {
    /// Whether the tab is on when the person never chose: exactly while an
    /// extension has an island page to show in it.
    package static func shownByDefault(anyIslandPanel: Bool) -> Bool {
        anyIslandPanel
    }

    /// The extensions switched off for the tab. An id that is not well
    /// formed is dropped; one that names no installed tool is kept, so a
    /// tool removed and added again keeps the person's choice.
    package static func hidden(in defaults: UserDefaults) -> Set<ToolID> {
        Set((defaults.string(forKey: DefaultsKey.panelHiddenExtensions) ?? "")
            .split(separator: ",")
            .compactMap { ToolID(String($0)) })
    }

    /// Whether the tab shows this extension: yes until the person turns it
    /// off.
    package static func isShown(_ tool: ToolID, in defaults: UserDefaults) -> Bool {
        !hidden(in: defaults).contains(tool)
    }

    /// Turns one extension on or off for the tab. With none off, nothing is
    /// saved.
    package static func setShown(_ shown: Bool, for tool: ToolID, in defaults: UserDefaults) {
        var off = hidden(in: defaults)
        if shown { off.remove(tool) } else { off.insert(tool) }
        if off.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.panelHiddenExtensions)
        } else {
            defaults.set(off.map(\.rawValue).sorted().joined(separator: ","), forKey: DefaultsKey.panelHiddenExtensions)
        }
    }

    /// Of `tools`, the ones the tab shows, in the order given.
    package static func shown(_ tools: [ToolID], in defaults: UserDefaults) -> [ToolID] {
        let off = hidden(in: defaults)
        return tools.filter { !off.contains($0) }
    }
}
