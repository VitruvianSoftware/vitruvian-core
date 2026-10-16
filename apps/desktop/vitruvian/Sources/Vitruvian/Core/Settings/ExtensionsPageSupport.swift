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

    /// What the Settings search finds the page by besides its name: the old
    /// card's name, the catalog's heading and the Add button, so "tools" and
    /// "catalog" lead here as "extensions" does.
    package static func searchWords(_ strings: ExternalToolStrings) -> [String] {
        [strings.sectionTitle, strings.catalogTitle, strings.addButton]
    }
}
