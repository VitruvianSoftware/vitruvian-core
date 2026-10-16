// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The Extensions page in Settings: the tools that run as their own
/// programs, which the person added, and the catalog's. Every way in lands
/// here: the sidebar, the Settings search and the command bar, the line on
/// the Features page, and the island's settings for an extension's page.
package enum ExtensionsPageSupport {
    /// Where every link to the extensions goes. The page has no sections of
    /// its own to aim at, so no anchor.
    package static var destination: FeatureSettingsDestination { FeatureSettingsDestination(.extensions) }

    /// The one line the Features page shows for the extensions, where their
    /// card was: how many are added, and the link to the page.
    package struct Summary: Equatable {
        /// "3 extensions installed", or "No extensions yet".
        package let text: String
        /// "Manage", or "Browse" when nothing is added.
        package let link: String
        /// Where the link goes.
        package let destination: FeatureSettingsDestination

        /// The whole line as one sentence, for VoiceOver.
        package var spoken: String { text + ". " + link }

        package init(text: String, link: String, destination: FeatureSettingsDestination) {
            self.text = text
            self.link = link
            self.destination = destination
        }
    }

    /// The line for `installed` extensions and tools, counting every one the
    /// person added, switched off or held back included.
    package static func summary(installed: Int, strings: ExternalToolStrings) -> Summary {
        switch installed {
        case ..<1:
            return Summary(text: strings.summaryNone, link: strings.summaryBrowse, destination: destination)
        case 1:
            return Summary(text: strings.summaryOne, link: strings.summaryManage, destination: destination)
        default:
            return Summary(text: strings.summaryCount(installed), link: strings.summaryManage,
                           destination: destination)
        }
    }

    /// What the page does with a tool's request to show its own detail
    /// (`SettingsRouter.extensionTool`).
    package enum AskedDetail: Equatable, Sendable {
        /// Show this tool's detail now.
        case show(ToolID)
        /// Something else is up on the page: the agreement sheet, another
        /// tool's detail, or an alert. The request waits, and the detail
        /// opens once the page is free, as a catalog fetch's result does.
        /// The person's sheet is never taken away from under them.
        case wait
        /// Nothing to show: the tool is no longer added, or its detail is
        /// already up. The request is dropped, and the page shows as it is.
        case drop
    }

    /// What to do with `asked`, a tool's request for its own detail. `listed`
    /// is the tools the page lists, `showing` the tool whose detail is up,
    /// and `busy` whether any other sheet or alert is up. Nil when nothing
    /// was asked.
    package static func askedDetail(_ asked: ToolID?, listed: [ToolID], showing: ToolID?,
                                    busy: Bool) -> AskedDetail? {
        guard let asked else { return nil }
        guard listed.contains(asked) else { return .drop }
        guard showing != asked else { return .drop }
        return showing == nil && !busy ? .show(asked) : .wait
    }

    /// What the Settings search finds the page by besides its name: the old
    /// card's name, the catalog's heading and the Add button, so "tools" and
    /// "catalog" lead here as "extensions" does.
    package static func searchWords(_ strings: ExternalToolStrings) -> [String] {
        [strings.sectionTitle, strings.catalogTitle, strings.addButton]
    }
}
