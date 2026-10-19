// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// What an extension's settings sheet holds, as the sheet's search and its
/// row of section links read it: every setting with the section it is in,
/// the words it can be found by, and where it is on the page. Plain values,
/// so the tests check what a search finds without drawing the sheet.
///
/// The sheet is one page: Vitruvian's own rows (the island switches and the
/// settings the manifest declares), then the extension's page, then its
/// commands, then what it uses. Vitruvian builds the sections and does the
/// search from what the extension sends, so every extension has them.
package struct SettingsSheetIndex: Equatable {
    /// A place on the sheet a link scrolls to, or a setting is drawn at.
    package enum Anchor: Hashable, Sendable {
        /// One of Vitruvian's own rows, by its key (`showsInIsland`,
        /// `showsStatus`, `setting(_:)`); the empty key is their heading.
        case vitruvian(String)
        /// The top of the extension's page: the sheet's settings title,
        /// drawn above it when the page does not start with a section.
        case panel
        /// An item of the extension's page, by `BlockTreeContent.Item.id`,
        /// its place in the page.
        case panelItem(Int)
        /// The heading of the commands.
        case commands
        /// The heading of what the extension uses.
        case uses

        /// The heading of Vitruvian's own rows.
        package static let vitruvianHeading = Anchor.vitruvian("")
        /// The switch that lists the extension's page in the island.
        package static let showsInIsland = Anchor.vitruvian("island")
        /// The switch that draws its status on the closed island.
        package static let showsStatus = Anchor.vitruvian("status")

        /// A setting the manifest declares, by the preference's id.
        package static func setting(_ id: String) -> Anchor { .vitruvian("setting/" + id) }
    }

    /// One setting, or one line of the commands or of what the extension
    /// uses.
    package struct Entry: Equatable, Sendable {
        /// The title of the section it is in, as its link says it.
        package let section: String
        /// Where that section starts.
        package let sectionAnchor: Anchor
        /// Its title.
        package let title: String
        /// The other words it is found by: its help (or the caption
        /// directly after it, when it has none), its sub-heading, its
        /// section's title, and the titles of its chips or of its menu's
        /// options. A section or a sub-heading that matches so keeps every
        /// setting under it.
        package let text: [String]
        /// Where it is drawn.
        package let anchor: Anchor
        /// The items of the extension's page drawn with it when a search
        /// keeps it: its own, its section's heading, its sub-heading and
        /// the caption read as its help. Empty for a row Vitruvian draws.
        package let items: [Int]

        package init(section: String, sectionAnchor: Anchor, title: String, text: [String], anchor: Anchor,
                     items: [Int] = []) {
            self.section = section
            self.sectionAnchor = sectionAnchor
            self.title = title
            self.text = text
            self.anchor = anchor
            self.items = items
        }

        /// True when every word of `words` is in its title or its other
        /// words (`text`), whatever the letters' case and
        /// accents.
        func holds(_ words: [Substring]) -> Bool {
            let said = [title] + text
            return words.allSatisfy { word in
                said.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
        }
    }

    /// The sections' titles, in the order the sheet draws them: the link
    /// row's words.
    package let sections: [String]
    /// Where each section starts, in the order of `sections`.
    package let anchors: [Anchor]
    /// Every setting, in the order the sheet draws them.
    package let entries: [Entry]
    /// False when part of the sheet cannot be searched: a settings page
    /// that is a web page. Its section is still linked.
    package let searchable: Bool

    /// The index of `detail`'s sheet. `panel` is the extension's settings
    /// page as the app draws it, nil while there is none to read (it is
    /// loading, or a web page: `panelIsWeb`).
    package init(detail: ExternalToolDetail, panel: BlockTreeContent?, panelIsWeb: Bool, strings: ExternalToolStrings) {
        var sections: [String] = []
        var anchors: [Anchor] = []
        var entries: [Entry] = []
        func start(_ title: String, _ anchor: Anchor) {
            sections.append(title)
            anchors.append(anchor)
        }

        // Vitruvian's own rows.
        let own = strings.vitruvianSection
        var vitruvian: [Entry] = []
        if detail.showsInIsland != nil {
            vitruvian.append(Entry(section: own, sectionAnchor: .vitruvianHeading, title: detail.showInIslandTitle,
                                   text: [own], anchor: .showsInIsland))
        }
        if detail.showsStatus != nil {
            vitruvian.append(Entry(section: own, sectionAnchor: .vitruvianHeading, title: detail.showStatusTitle,
                                   text: [own], anchor: .showsStatus))
        }
        vitruvian += detail.settings.map {
            Entry(section: own, sectionAnchor: .vitruvianHeading, title: $0.title, text: [own],
                  anchor: .setting($0.id))
        }
        if !vitruvian.isEmpty {
            start(own, .vitruvianHeading)
            entries += vitruvian
        }

        // The extension's page.
        if detail.settingsPanel != nil {
            entries += Self.page(panel, isWeb: panelIsWeb, title: detail.settingsTitle, start: start)
        }

        // The commands, and what the extension uses.
        if !detail.commands.isEmpty || !detail.windows.isEmpty {
            start(detail.commandsTitle, .commands)
            entries += (detail.commands + detail.windows.map(\.title)).map {
                Entry(section: detail.commandsTitle, sectionAnchor: .commands, title: $0,
                      text: [detail.commandsTitle], anchor: .commands)
            }
        }
        if !detail.uses.isEmpty {
            start(detail.usesTitle, .uses)
            entries += detail.uses.map {
                Entry(section: detail.usesTitle, sectionAnchor: .uses, title: $0, text: [detail.usesTitle],
                      anchor: .uses)
            }
        }
        self.sections = sections
        self.anchors = anchors
        self.entries = entries
        searchable = !(detail.settingsPanel != nil && panelIsWeb)
    }

    /// The index of an extension's settings page alone, as the Dynamic
    /// Island page draws it, without Vitruvian's own rows, the commands or
    /// what the extension uses: its sections, or one titled `title` when it
    /// sends none. `page` is nil while there is none to read (it is
    /// loading, or a web page: `isWeb`).
    package init(page: BlockTreeContent?, isWeb: Bool, title: String) {
        var sections: [String] = []
        var anchors: [Anchor] = []
        entries = Self.page(page, isWeb: isWeb, title: title) { title, anchor in
            sections.append(title)
            anchors.append(anchor)
        }
        self.sections = sections
        self.anchors = anchors
        searchable = !isWeb
    }

    /// The settings of the extension's page, under `title` when it does not
    /// start with a section of its own; `start` is told of each section.
    private static func page(_ panel: BlockTreeContent?, isWeb: Bool, title: String,
                             start: (String, Anchor) -> Void) -> [Entry] {
        let items = isWeb ? [] : panel?.items ?? []
        if items.first?.isSection != true {
            start(title, .panel)
        }
        return entries(of: items, title: title, start: start)
    }

    /// The settings of a page's `items`. The ones before the page's first
    /// section are under `title`, the sheet's settings title; `start` is
    /// told of each section the page starts.
    private static func entries(of items: [BlockTreeContent.Item], title: String,
                                start: (String, Anchor) -> Void) -> [Entry] {
        var entries: [Entry] = []
        var section = (title: title, anchor: Anchor.panel, item: Int?.none)
        var subheading: (title: String, item: Int)?
        for (position, item) in items.enumerated() {
            let next = items.indices.contains(position + 1) ? items[position + 1] : nil
            /// The caption directly after a control is its help, when it
            /// has none of its own: a best guess, for a page that does not
            /// give its controls help.
            func help(_ own: String?) -> (text: String, item: Int?)? {
                if let own { return (own, nil) }
                guard let next, case .text(let caption, style: .caption, _) = next.kind else { return nil }
                return (caption, next.id)
            }
            func add(_ title: String, help: (text: String, item: Int?)?, more: [String] = []) {
                let text = [help?.text, subheading?.title, section.title].compactMap { $0 } + more
                let drawn = [section.item, subheading?.item, item.id, help?.item].compactMap { $0 }
                entries.append(Entry(section: section.title, sectionAnchor: section.anchor, title: title, text: text,
                                     anchor: .panelItem(item.id), items: drawn))
            }
            switch item.kind {
            case .heading(let words, section: true):
                section = (words, .panelItem(item.id), item.id)
                subheading = nil
                start(words, .panelItem(item.id))
            case .heading(let words, section: false):
                subheading = (words, item.id)
            case .toggle(_, let title, _, _, let own):
                add(title, help: help(own))
            case .choice(_, let title, _, let options, _, let own):
                add(title ?? "", help: help(own), more: options.map(\.title))
            case .chips(_, let title, let options, _, let own):
                add(title ?? "", help: help(own), more: options.map(\.title))
            case .field(_, let title, _, _, _, let own):
                add(title ?? "", help: help(own))
            case .button(_, let title, _, _), .link(let title, _):
                add(title, help: help(nil))
            case .row(let row, _):
                add(row.title, help: help(nil), more: [row.subtitle].compactMap { $0 })
            case .list(_, let rows):
                for row in rows { add(row.title, help: nil, more: [row.subtitle].compactMap { $0 }) }
            case .text, .progress, .image, .divider, .spacer, .fallback:
                break
            }
        }
        return entries
    }

    /// The settings a search for `query` keeps, in the sheet's order: each
    /// that holds every word of it in its title or its other words (its
    /// help, its sub-heading, its section's title, its chips' or options'
    /// titles), whatever the letters' case and accents. A query
    /// of no words keeps every setting.
    package func matches(_ query: String) -> [Entry] {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return entries }
        return entries.filter { $0.holds(words) }
    }

    /// What the sheet draws while `query` is typed: every setting it keeps,
    /// each under its section's heading. All of the sheet while nothing is
    /// typed.
    package func kept(_ query: String) -> Kept {
        let searching = !query.split(whereSeparator: \.isWhitespace).isEmpty
        return Kept(index: self, found: searching ? matches(query) : nil)
    }

    /// What the sheet draws, for a search or for none.
    package struct Kept: Equatable {
        package let index: SettingsSheetIndex
        /// The settings a search kept; nil while nothing is typed.
        package let found: [Entry]?

        /// True while a search is typed.
        package var searching: Bool { found != nil }
        /// True when a search kept nothing, and the sheet says so: "No
        /// settings match". Never for a sheet with a web page, of which a
        /// search cannot say it holds nothing.
        package var nothingFound: Bool { found?.isEmpty == true && index.searchable }
        /// True when a search is typed and the sheet has a web page: the
        /// sheet says it cannot search it, and draws it as it is.
        package var saysNotSearchable: Bool { searching && !index.searchable }

        /// Whether the row or line at `anchor` is drawn; for the commands
        /// and what the extension uses, the line with `title`.
        package func draws(_ anchor: Anchor, title: String? = nil) -> Bool {
            guard let found else { return true }
            return found.contains { $0.anchor == anchor && (title == nil || $0.title == title) }
        }

        /// Whether the section starting at `anchor` is drawn, and linked.
        package func drawsSection(_ anchor: Anchor) -> Bool {
            guard index.anchors.contains(anchor) else { return false }
            guard let found else { return true }
            return found.contains { $0.sectionAnchor == anchor } || (anchor == .panel && !index.searchable)
        }

        /// The items of the extension's page to draw, by their place in
        /// it; nil for all of them.
        package var panelItems: Set<Int>? { found.map { Set($0.flatMap(\.items)) } }

        /// The links the sheet's row shows: each section drawn, in order.
        package var links: [(title: String, anchor: Anchor)] {
            zip(index.sections, index.anchors).filter { drawsSection($0.1) }.map { ($0.0, $0.1) }
        }
    }

    /// The anchor of the section in view: the one a link was just used for
    /// while its heading is still in view, or else the last whose heading
    /// is at or above `reach` from the top of the scrolling region. `tops`
    /// is where each drawn heading is, from that top; `height` is the
    /// region's. Nil for a sheet with no sections.
    package func current(tops: [Anchor: CGFloat], reach: CGFloat, height: CGFloat, chosen: Anchor?) -> Anchor? {
        if let chosen, let top = tops[chosen], top >= -1, top < height { return chosen }
        let drawn = anchors.filter { tops[$0] != nil }
        return drawn.last { (tops[$0] ?? .infinity) <= reach } ?? drawn.first ?? anchors.first
    }
}
