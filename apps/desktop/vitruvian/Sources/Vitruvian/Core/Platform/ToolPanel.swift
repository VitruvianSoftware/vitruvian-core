// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianToolProtocol

/// Where the app shows a tool's panel. The protocol's list, mapped onto the
/// app's own, so that a placement the app does not have is a refusal that
/// names it.
package enum ToolPanelPlacement: String, CaseIterable, Sendable {
    /// A page in the island's Tools area.
    case island
    /// A part of the tool's detail in Settings.
    case settings
    /// A window the app owns.
    case window
}

/// One panel of a tool from outside, as its manifest describes it.
package struct ToolPanelDescriptor: Equatable, Sendable {
    /// The panel's name within the tool, as the messages name it.
    package let id: String
    /// What it is called, in every language its author wrote.
    package let title: LocalizedText
    package let placement: ToolPanelPlacement
    /// An SF Symbol name: the panel's own, else the tool's.
    package let symbol: String
    /// A web panel's page, as a path inside the tool's folder. Nil for a
    /// panel the app draws from blocks.
    package let entry: String?

    package init(id: String, title: LocalizedText, placement: ToolPanelPlacement, symbol: String,
                 entry: String? = nil) {
        self.id = id
        self.title = title
        self.placement = placement
        self.symbol = symbol
        self.entry = entry
    }

    /// True for a panel that is a web page.
    package var isWeb: Bool { entry != nil }
}
