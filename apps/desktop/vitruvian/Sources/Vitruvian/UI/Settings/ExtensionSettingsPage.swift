// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
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
    /// How tall the region the page scrolls in is; with `fills`, the least
    /// it is while the window has room for it.
    let height: CGFloat
    /// True when the region takes the room it is given, from `height` up to
    /// the height of what it holds, as the Extensions sheet's does (in a
    /// `SheetColumn`), and down to `tight` in a short window; false for a
    /// region of `height` exactly.
    let fills: Bool
    /// The least the region gives way to in a window too short for
    /// `height`, when it fills.
    let tight: CGFloat
    let text: ExternalToolStrings
    let focus: FocusState<ExternalToolDetail.Focus?>.Binding
    /// What the page draws for what a search kept.
    let lists: (SettingsSheetIndex.Kept) -> Lists
    /// The section whose link is lit: the one in view.
    @State private var lit: SettingsSheetIndex.Anchor?
    /// The section whose link was just used, lit while its heading is in
    /// view though it cannot reach the top (a short last section).
    @State private var chosen: SettingsSheetIndex.Anchor?
    /// How tall the region is drawn; zero until it is.
    @State private var drawn: CGFloat = 0
    /// How tall what the region holds is with no search typed, so a search
    /// that keeps less does not shrink the sheet as the person types.
    @State private var whole: CGFloat = 0

    package init(index: SettingsSheetIndex, query: Binding<String>, height: CGFloat, fills: Bool = false,
                 tight: CGFloat? = nil, text: ExternalToolStrings,
                 focus: FocusState<ExternalToolDetail.Focus?>.Binding,
                 @ViewBuilder lists: @escaping (SettingsSheetIndex.Kept) -> Lists) {
        self.index = index
        _query = query
        self.height = height
        self.fills = fills
        self.tight = min(height, tight ?? height)
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
                SettingsSheetLinks(links: kept.links,
                                   current: kept.links.contains { $0.anchor == lit } ? lit : kept.links.first?.anchor,
                                   focus: focus) { anchor in
                    chosen = anchor
                    lit = anchor
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(anchor, anchor: .top) }
                }
                sized(searching: kept.searching, ScrollView(.vertical) {
                    lists(kept).frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            GeometryReader { Color.clear.preference(key: ListsHeight.self, value: $0.size.height) }
                        }
                }
                .coordinateSpace(.named(SettingsSheetMark.space)))
                .background {
                    GeometryReader { Color.clear.preference(key: RegionHeight.self, value: $0.size.height) }
                }
                .onPreferenceChange(SettingsSheetMark.Tops.self) { [index, chosen, height = drawn > 0 ? drawn : height,
                                                                    lit = $lit] tops in
                    let now = index.current(tops: tops, reach: SettingsSheetMark.reach, height: height, chosen: chosen)
                    DispatchQueue.main.async {
                        if lit.wrappedValue != now { lit.wrappedValue = now }
                    }
                }
                .onPreferenceChange(RegionHeight.self) { [drawn = $drawn] height in
                    DispatchQueue.main.async {
                        if drawn.wrappedValue != height { drawn.wrappedValue = height }
                    }
                }
                .onPreferenceChange(ListsHeight.self) { [searching = kept.searching, whole = $whole] height in
                    guard !searching else { return }
                    DispatchQueue.main.async {
                        if whole.wrappedValue != height { whole.wrappedValue = height }
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
}

extension ExtensionSettingsOnePage {
    /// The region at `height`, or, when it fills, as tall as its column
    /// lets it be: up to what it holds, and down to `tight` (the column
    /// keeps it at `height` while the window has room). What it holds is
    /// read in the same layout pass, so the sheet opens at its height and
    /// does not grow a moment later. While a search is typed it asks for
    /// the height of the whole page, so the sheet does not shrink as the
    /// person types.
    @ViewBuilder
    private func sized(searching: Bool, _ region: some View) -> some View {
        if fills {
            RegionFill(least: tight, wants: searching ? whole : 0) { region }
        } else {
            region.frame(height: height)
        }
    }
}

/// A scrolling region that is as tall as it is given, never less than
/// `least`, and, when nothing says how tall, as tall as what it holds, or
/// `wants` when that is more.
private struct RegionFill: Layout {
    let least: CGFloat
    let wants: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let region = subviews.first else { return .zero }
        let height = proposal.height
            ?? max(wants, region.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).height)
        let width = proposal.width ?? region.sizeThatFits(.unspecified).width
        return CGSize(width: width, height: max(least, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

/// How tall the scrolling region of an extension's settings is drawn.
private struct RegionHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// How tall what that region holds is.
private struct ListsHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A column, as a leading `VStack` is, whose one view marked `fills` takes
/// the height the column has to give: from the least it can be up to all it
/// wants, within `budget` with the rest of the column drawn whole. The
/// Extensions sheet is one, so its settings region is as tall as the window
/// lets it be, up to a 13-inch display's room, and never shorter than its
/// least. With no budget, or no view marked, it is a plain column.
package struct SheetColumn: Layout {
    /// Marks the view that takes the room.
    package struct Fills: LayoutValueKey {
        package static let defaultValue = false
    }

    let spacing: CGFloat
    /// The tallest the column may be, in points; nil for no limit.
    let budget: CGFloat?
    /// How much more than the least it can be drawn at the view that fills
    /// is kept while the budget has room for it: the least it gives way to
    /// in a short window is that much less than the least it keeps.
    let give: CGFloat

    package init(spacing: CGFloat, budget: CGFloat?, give: CGFloat = 0) {
        self.spacing = spacing
        self.budget = budget
        self.give = give
    }

    /// The height of the view that takes the room: all it wants (`ideal`)
    /// when that fits in `budget` with `rest` of the column, else what is
    /// left of it; never less than `least` while that fits, and never less
    /// than `floor` when it does not.
    package static func fill(ideal: CGFloat, least: CGFloat, floor: CGFloat, rest: CGFloat,
                             budget: CGFloat) -> CGFloat {
        let left = budget - rest
        return max(min(least, max(floor, left)), min(ideal, left))
    }

    package func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let heights = heights(width: proposal.width, subviews)
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return CGSize(width: width, height: heights.reduce(0, +) + gaps(subviews))
    }

    package func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var top = bounds.minY
        for (subview, height) in zip(subviews, heights(width: bounds.width, subviews)) {
            subview.place(at: CGPoint(x: bounds.minX, y: top), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: height))
            top += height + spacing
        }
    }

    private func gaps(_ subviews: Subviews) -> CGFloat {
        spacing * CGFloat(max(0, subviews.count - 1))
    }

    /// Each view's height: the height it wants, but the one that fills.
    private func heights(width: CGFloat?, _ subviews: Subviews) -> [CGFloat] {
        var heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        guard let budget, let filling = subviews.firstIndex(where: { $0[Fills.self] }) else { return heights }
        let rest = heights.enumerated().filter { $0.offset != filling }.map(\.element).reduce(0, +) + gaps(subviews)
        let floor = subviews[filling].sizeThatFits(ProposedViewSize(width: width, height: 0)).height
        heights[filling] = Self.fill(ideal: heights[filling], least: floor + give, floor: floor, rest: rest,
                                     budget: budget)
        return heights
    }
}

/// Tells how tall a window is inside, below its title bar and toolbar, as
/// the view goes into it and whenever that window is resized: the window a
/// sheet hangs from (nil while the view is in no sheet), or with `own`, the
/// view's own window, which the page that opens a sheet hands it, so the
/// sheet knows its room in its first layout.
package struct SheetRoomReader: NSViewRepresentable {
    let own: Bool
    let report: (CGFloat?) -> Void

    package init(own: Bool = false, report: @escaping (CGFloat?) -> Void) {
        self.own = own
        self.report = report
    }

    package func makeNSView(context: Context) -> Reader {
        Reader(own: own, report: report)
    }

    package func updateNSView(_ view: Reader, context: Context) {
        view.report = report
    }

    package final class Reader: NSView {
        let own: Bool
        var report: (CGFloat?) -> Void
        /// Its own window becoming key: a sheet's window is given its
        /// parent as it is shown, after the view is in it.
        private var shown: NSObjectProtocol?
        /// The parent being resized.
        private var resized: NSObjectProtocol?
        private weak var parent: NSWindow?
        private var told: CGFloat??

        init(own: Bool, report: @escaping (CGFloat?) -> Void) {
            self.own = own
            self.report = report
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override package func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            shown.map(NotificationCenter.default.removeObserver)
            shown = window.map {
                NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: $0,
                                                       queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.measure() }
                }
            }
            measure()
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        private func measure() {
            let sheetParent = own ? window : window?.sheetParent
            if sheetParent !== parent {
                parent = sheetParent
                resized.map(NotificationCenter.default.removeObserver)
                resized = sheetParent.map {
                    NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: $0,
                                                           queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.measure() }
                    }
                }
            }
            let room = sheetParent?.contentLayoutRect.height
            guard told != .some(room) else { return }
            told = .some(room)
            let report = report
            DispatchQueue.main.async { report(room) }
        }
    }
}

/// The links to the sections of an extension's settings, each the
/// section's title, the one in view lit. They wrap onto rows as chips do
/// (`ChipFlow`), so every section's name is in view without scrolling.
package struct SettingsSheetLinks: View {
    let links: [(title: String, anchor: SettingsSheetIndex.Anchor)]
    /// The section in view.
    let current: SettingsSheetIndex.Anchor?
    let focus: FocusState<ExternalToolDetail.Focus?>.Binding?
    let jump: (SettingsSheetIndex.Anchor) -> Void
    /// Told where each link was placed, from the row's top left, in their
    /// order; nil for no one. A test reads it.
    let placed: (([CGRect]) -> Void)?

    package init(links: [(title: String, anchor: SettingsSheetIndex.Anchor)], current: SettingsSheetIndex.Anchor?,
                 focus: FocusState<ExternalToolDetail.Focus?>.Binding?,
                 jump: @escaping (SettingsSheetIndex.Anchor) -> Void, placed: (([CGRect]) -> Void)? = nil) {
        self.links = links
        self.current = current
        self.focus = focus
        self.jump = jump
        self.placed = placed
    }

    private static let space = "extension.settings.links"

    private struct Placed: PreferenceKey {
        static let defaultValue: [Int: CGRect] = [:]

        static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
            value.merge(nextValue()) { $1 }
        }
    }

    package var body: some View {
        ChipFlow(spacing: 4) {
            // Each link has an id of its own, never its section's anchor:
            // the lists' reader scrolls to the first view with that id, and
            // would find the link.
            ForEach(Array(links.enumerated()), id: \.offset) { position, link in
                reported(focused(button(link), link.anchor), position)
                    .id(SettingsSheetMark.Link(anchor: link.anchor))
            }
        }
        // As tall with no link, so a search that keeps nothing does not
        // move the lists.
        .frame(minHeight: 24, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
        .onPreferenceChange(Placed.self) { [placed] frames in
            placed?(frames.sorted { $0.key < $1.key }.map(\.value))
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func reported(_ view: some View, _ position: Int) -> some View {
        if placed != nil {
            view.background {
                GeometryReader { proxy in
                    Color.clear.preference(key: Placed.self, value: [position: proxy.frame(in: .named(Self.space))])
                }
            }
        } else {
            view
        }
    }

    /// A link: the same type, padding and capsule whether it is lit or not,
    /// so lighting another never changes a link's width, and the row wraps
    /// the same way whichever is lit. Only the colours and the lit link's
    /// outline change. Every link has a faint capsule, so each row's first
    /// starts at the same visible edge.
    private func button(_ link: (title: String, anchor: SettingsSheetIndex.Anchor)) -> some View {
        let on = link.anchor == current
        return Button { jump(link.anchor) } label: {
            // A section's title is the tool's own words: plain text, on one
            // short line.
            Text(verbatim: ToolOwnWords.oneLine(link.title, limit: SettingsSheetMark.linkCharacters))
                .font(.callout.weight(.medium))
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous)
                    .fill(on ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05)))
                // The lit link is outlined too, so it stands out by more
                // than its colour: in greyscale and to red-green colour
                // blindness its red is close to the others' grey. Drawn
                // inside the capsule, so no link changes width.
                .overlay(Capsule(style: .continuous)
                    .strokeBorder(on ? Color.accentColor : Color.clear, lineWidth: 1.5))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .controlNamed(link.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private func focused(_ view: some View, _ anchor: SettingsSheetIndex.Anchor) -> some View {
        if let focus {
            view.focused(focus, equals: .section(anchor))
        } else {
            view
        }
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
    let host: ToolPanelHost

    package init(key: ToolPanelHost.Key, title: String, kept: SettingsSheetIndex.Kept, text: ExternalToolStrings,
                 focus: FocusState<ExternalToolDetail.Focus?>.Binding, host: ToolPanelHost = .shared) {
        self.key = key
        self.host = host
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
            ToolPanelView(key: key, size: .standard, focus: focus, keeping: kept.panelItems, marksSections: true,
                          host: host)
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
