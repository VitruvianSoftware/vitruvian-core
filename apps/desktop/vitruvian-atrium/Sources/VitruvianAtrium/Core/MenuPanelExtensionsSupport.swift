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
/// own in the tab's edit mode, on until the person turns it off
/// (`DefaultsKey.panelHiddenExtensions`), a place in the tab's custom order
/// (`DefaultsKey.panelExtensionOrder`), and a collapsible header of its own
/// (`DefaultsKey.panelCollapsedExtensions`).
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
        idSet(forKey: DefaultsKey.panelHiddenExtensions, in: defaults)
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
        setIDSet(off, forKey: DefaultsKey.panelHiddenExtensions, in: defaults)
    }

    /// `tools` in the tab's saved order: the ones the saved order names come
    /// first, in that order, followed by any others in the order given.
    package static func ordered(_ tools: [ToolID], in defaults: UserDefaults) -> [ToolID] {
        let byID = Dictionary(tools.map { ($0.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
        return QuickToolsSupport.tileOrder(live: tools.map(\.rawValue), saved: savedOrder(in: defaults))
            .compactMap { byID[$0] }
    }

    /// Saves the rearranged order of `tools`. A tool in the previous order
    /// that is not in `tools` now (switched off in Settings, or removed and
    /// not yet added back) keeps its place so it returns where it was left.
    package static func setOrder(_ tools: [ToolID], in defaults: UserDefaults) {
        let next = QuickToolsSupport.savedTileOrder(
            afterMoving: tools.map(\.rawValue),
            previous: savedOrder(in: defaults),
            isWellFormed: { ToolID($0) != nil }
        )
        if next.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.panelExtensionOrder)
        } else {
            defaults.set(next.joined(separator: ","), forKey: DefaultsKey.panelExtensionOrder)
        }
    }

    /// Of `tools`, the ones the tab shows, in the tab's saved order.
    package static func shown(_ tools: [ToolID], in defaults: UserDefaults) -> [ToolID] {
        let off = hidden(in: defaults)
        return ordered(tools, in: defaults).filter { !off.contains($0) }
    }

    /// The extensions whose card is collapsed in the tab.
    package static func collapsed(in defaults: UserDefaults) -> Set<ToolID> {
        idSet(forKey: DefaultsKey.panelCollapsedExtensions, in: defaults)
    }

    /// Whether this extension's card is collapsed in the tab: open until the
    /// person collapses it.
    package static func isCollapsed(_ tool: ToolID, in defaults: UserDefaults) -> Bool {
        collapsed(in: defaults).contains(tool)
    }

    /// Collapses or expands one extension's card in the tab. With none
    /// collapsed, nothing is saved.
    package static func setCollapsed(_ isCollapsed: Bool, for tool: ToolID, in defaults: UserDefaults) {
        var closed = collapsed(in: defaults)
        if isCollapsed { closed.insert(tool) } else { closed.remove(tool) }
        setIDSet(closed, forKey: DefaultsKey.panelCollapsedExtensions, in: defaults)
    }

    /// Returns the tab to its defaults: every extension shown, in the order
    /// they were added, with every card expanded.
    package static func reset(in defaults: UserDefaults) {
        defaults.removeObject(forKey: DefaultsKey.panelHiddenExtensions)
        defaults.removeObject(forKey: DefaultsKey.panelExtensionOrder)
        defaults.removeObject(forKey: DefaultsKey.panelCollapsedExtensions)
    }

    private static func savedOrder(in defaults: UserDefaults) -> [String] {
        (defaults.string(forKey: DefaultsKey.panelExtensionOrder) ?? "")
            .split(separator: ",")
            .map(String.init)
    }

    private static func idSet(forKey key: String, in defaults: UserDefaults) -> Set<ToolID> {
        Set((defaults.string(forKey: key) ?? "")
            .split(separator: ",")
            .compactMap { ToolID(String($0)) })
    }

    private static func setIDSet(_ ids: Set<ToolID>, forKey key: String, in defaults: UserDefaults) {
        if ids.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(ids.map(\.rawValue).sorted().joined(separator: ","), forKey: key)
        }
    }
}
