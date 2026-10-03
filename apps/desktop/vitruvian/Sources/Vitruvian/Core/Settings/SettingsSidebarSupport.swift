// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A page or a directly selectable tool in the flat Settings sidebar.
package struct SettingsSidebarItem: Identifiable {
    package enum ID: Hashable {
        case page(SettingsPage)
        case feature(AppFeature)
        case setting(SettingsSectionAnchor)
    }

    package let id: ID
    package let destination: FeatureSettingsDestination
    package let title: String
    package let icon: String

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: ID, destination: FeatureSettingsDestination, title: String, icon: String) {
        self.id = id
        self.destination = destination
        self.title = title
        self.icon = icon
    }
}

/// A stable category in the sidebar; its title follows the selected language.
package struct SettingsSidebarSection: Identifiable {
    package let id: Int
    package let title: String
    package let items: [SettingsSidebarItem]

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: Int, title: String, items: [SettingsSidebarItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// Builds one row per tool, even when several tools share one Settings card.
package enum SettingsSidebarSupport {
    package static func items(page: SettingsPage, title: String, icon: String,
                      preferredFeatures: [AppFeature], includePage: Bool,
                      isAvailable: (AppFeature) -> Bool,
                      featureTitle: (AppFeature) -> String) -> [SettingsSidebarItem] {
        guard FeatureVisibilitySupport.isPageVisible(page, isAvailable: isAvailable) else { return [] }
        let pageItem = SettingsSidebarItem(id: .page(page),
                                           destination: FeatureSettingsDestination(page),
                                           title: title, icon: icon)
        var rows = includePage ? [pageItem] : []
        var seenFeatures: Set<AppFeature> = []
        for feature in preferredFeatures + AppFeature.allCases {
            guard seenFeatures.insert(feature).inserted else { continue }
            let destination = feature.settingsDestination
            guard destination.page == page, destination.sectionAnchor != nil,
                  isAvailable(feature) else { continue }
            rows.append(SettingsSidebarItem(id: .feature(feature),
                                            destination: destination,
                                            title: featureTitle(feature),
                                            icon: feature.symbolName))
        }
        if rows.isEmpty { rows.append(pageItem) }
        return rows
    }

    package static func selection(for destination: FeatureSettingsDestination,
                          in items: [SettingsSidebarItem],
                          preferredID: SettingsSidebarItem.ID? = nil)
        -> SettingsSidebarItem.ID? {
        if let preferredID,
           items.contains(where: { $0.id == preferredID && $0.destination == destination }) {
            return preferredID
        }
        if destination.sectionAnchor != nil,
           let tool = items.first(where: { $0.destination == destination }) {
            return tool.id
        }
        if items.contains(where: { $0.id == .page(destination.page) }) {
            return .page(destination.page)
        }
        return items.first(where: { $0.destination.page == destination.page })?.id
    }
}
