// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianServices

/// An extension's settings as one page: a search field and a row of links
/// to its sections, which stay in place, over the page, which scrolls. A
/// link scrolls to its section; the link of the section in view is lit as
/// the page scrolls. The Extensions sheet draws Vitruvian's own rows, the
/// commands and what the extension uses around the extension's page
/// (`lists`); the Dynamic Island page draws the extension's page alone.
/// Both show the same page, so a change in either is the same change.
package struct ExtensionSettingsOnePage<Lists: View>: View {
    /// What the page holds, as its search and its links read it.
    let index: SettingsSheetIndex
    /// What is typed in the search field.
    @Binding var query: String
    /// How tall the region the page scrolls in is.
    let height: CGFloat
    let text: ExternalToolStrings
    let focus: FocusState<ExternalToolDetail.Focus?>.Binding
    /// What the page draws for what a search kept.
    let lists: (SettingsSheetIndex.Kept) -> Lists
    /// The section whose link is lit: the one in view.
    @State private var lit: SettingsSheetIndex.Anchor?
    /// The section whose link was just used, lit while its heading is in
    /// view though it cannot reach the top (a short last section).
    @State private var chosen: SettingsSheetIndex.Anchor?

    package init(index: SettingsSheetIndex, query: Binding<String>, height: CGFloat, text: ExternalToolStrings,
                 focus: FocusState<ExternalToolDetail.Focus?>.Binding,
                 @ViewBuilder lists: @escaping (SettingsSheetIndex.Kept) -> Lists) {
        self.index = index
        _query = query
        self.height = height
        self.text = text
        self.focus = focus
        self.lists = lists
    }

    package var body: some View {
        let kept = index.kept(query)
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                TextField(text.searchSettings, text: $query, prompt: Text(text.searchSettings))
                    .textFieldStyle(.roundedBorder)
                    .controlNamed(text.searchSettings)
                    .focused(focus, equals: .search)
                links(kept) { anchor in
                    chosen = anchor
                    lit = anchor
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(anchor, anchor: .top) }
                }
                ScrollView(.vertical) {
                    lists(kept).frame(maxWidth: .infinity, alignment: .leading)
                }
                .coordinateSpace(.named(SettingsSheetMark.space))
                .frame(height: height)
                .onPreferenceChange(SettingsSheetMark.Tops.self) { [index, chosen, height, lit = $lit] tops in
                    let now = index.current(tops: tops, reach: SettingsSheetMark.reach, height: height, chosen: chosen)
                    DispatchQueue.main.async {
                        if lit.wrappedValue != now { lit.wrappedValue = now }
                    }
                }
            }
            .onChange(of: query) { _, typed in
                chosen = nil
                if let first = index.kept(typed).links.first?.anchor { proxy.scrollTo(first, anchor: .top) }
            }
            .onChange(of: kept.nothingFound) { _, nothing in
                // Said to VoiceOver too, as the person types.
                if nothing { AccessibilityNotification.Announcement(SettingsSheetNoMatch.words(text, query)).post() }
            }
        }
    }

    /// The row of links to the page's sections, each the section's title,
    /// the one in view lit. It scrolls sideways when they do not fit.
    private func links(_ kept: SettingsSheetIndex.Kept,
                       jump: @escaping (SettingsSheetIndex.Anchor) -> Void) -> some View {
        let links = kept.links
        let current = links.contains { $0.anchor == lit } ? lit : links.first?.anchor
        return ScrollViewReader { row in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // Each link has an id of its own, never its section's
                    // anchor: the lists' reader scrolls to the first view
                    // with that id, and would find the link.
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        let on = link.anchor == current
                        Button { jump(link.anchor) } label: {
                            // A section's title is the tool's own words:
                            // plain text, on one short line.
                            Text(verbatim: ToolOwnWords.oneLine(link.title, limit: SettingsSheetMark.linkCharacters))
                                .font(.callout.weight(on ? .semibold : .regular))
                                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule(style: .continuous)
                                    .fill(on ? Color.accentColor.opacity(0.14) : Color.clear))
                                .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .controlNamed(link.title)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .focused(focus, equals: .section(link.anchor))
                        .id(SettingsSheetMark.Link(anchor: link.anchor))
                    }
                }
                // As tall with no link, so a search that keeps nothing does
                // not move the lists.
                .frame(minHeight: 24)
            }
            .onChange(of: current) { _, now in
                if let now { withAnimation(.easeInOut(duration: 0.2)) { row.scrollTo(SettingsSheetMark.Link(anchor: now)) } }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

/// The extension's own settings page on the one page, under the settings
/// title when the page does not start with a section of its own. A web
/// page is drawn as it is; while a search is typed the page says it cannot
/// look inside it.
package struct ExtensionSettingsPanel: View {
    let key: ToolPanelHost.Key
    /// The app's word for Settings, the page's title when it has no section.
    let title: String
    let kept: SettingsSheetIndex.Kept
    let text: ExternalToolStrings
    let focus: FocusState<ExternalToolDetail.Focus?>.Binding

    package init(key: ToolPanelHost.Key, title: String, kept: SettingsSheetIndex.Kept, text: ExternalToolStrings,
                 focus: FocusState<ExternalToolDetail.Focus?>.Binding) {
        self.key = key
        self.title = title
        self.kept = kept
        self.text = text
        self.focus = focus
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if kept.drawsSection(.panel) {
                SettingsSheetHeading(title: title, mark: .panel)
            }
            if kept.saysNotSearchable {
                Text(text.pageNotSearchable).font(.caption).foregroundStyle(.secondary)
            }
            ToolPanelView(key: key, size: .standard, focus: focus, keeping: kept.panelItems, marksSections: true)
                .padding(.top, kept.drawsSection(.panel) ? 4 : 0)
        }
    }
}

/// A heading of an extension's settings. With `mark`, a section heading of
/// the one page, as large as the page's own, which its link scrolls to.
struct SettingsSheetHeading: View {
    let title: String
    let mark: SettingsSheetIndex.Anchor?

    var body: some View {
        if let mark {
            Text(title).font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .modifier(SettingsSheetMark(anchor: mark))
        } else {
            Text(title).font(.subheadline.weight(.semibold))
        }
    }
}

/// What the page says when its search finds nothing: "No settings match".
struct SettingsSheetNoMatch: View {
    let text: ExternalToolStrings
    let query: String

    static func words(_ text: ExternalToolStrings, _ query: String) -> String {
        text.noSettingsMatch(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        Text(Self.words(text, query))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }
}
