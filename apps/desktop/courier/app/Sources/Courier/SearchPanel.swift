// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// ⌘K over the main window (01 §12): a light dim, and the panel centred near the top. Clicking the dim closes it.
struct SearchOverlay: View {
    @ObservedObject var search: SearchModel
    @ObservedObject var inbox: InboxModel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .onTapGesture { search.close() }
                    .accessibilityHidden(true)
                SearchPanel(search: search, inbox: inbox, maxHeight: proxy.size.height * 0.7)
                    .padding(.top, max(16, proxy.size.height * 0.06))
            }
        }
    }
}

/// The search field, the filter bar and the sections, with what the panel says when it has no rows.
struct SearchPanel: View {
    @ObservedObject var search: SearchModel
    @ObservedObject var inbox: InboxModel
    /// 70% of the window's height: the panel grows with its rows up to this.
    let maxHeight: CGFloat
    @State private var rowsHeight: CGFloat = 0

    static let width: CGFloat = 640
    /// What the field, the filter bar and the quiet line take above the rows, about.
    private static let chromeHeight: CGFloat = 112

    var body: some View {
        VStack(spacing: 0) {
            fieldRow
            SearchFilterBar(search: search, accounts: inbox.statusItems)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            Divider()
            if !search.complete, search.phase == .results {
                Text(String(localized: "Still adding older messages to search. Some results may be missing."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            if let notice = search.notice {
                SearchNoticeView(notice: notice, clearFilters: search.clearFilters, retry: search.retry)
            } else {
                results
            }
        }
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        // A click on the panel itself isn't a click on the dim.
        .contentShape(RoundedRectangle(cornerRadius: 12))
        // Esc while a filter's menu or a button has the keyboard, as in the field.
        .onExitCommand { _ = search.escape() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Search"))
    }

    // MARK: The field

    private var fieldRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let scope = search.scope {
                ScopeChip(name: scope.name.isEmpty ? String(localized: "Unnamed chat") : scope.name,
                          remove: search.removeScope)
            }
            SearchField(text: $search.text, placeholder: placeholder, command: command)
                .frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var placeholder: String {
        search.scope == nil ? String(localized: "Search chats, people and messages")
            : String(localized: "Search this chat")
    }

    /// The panel's keys, as the field reads them: typing always goes to the field.
    private func command(_ command: SearchFieldCommand) -> Bool {
        switch command {
        case .up: search.moveSelection(-1)
        case .down: search.moveSelection(1)
        case .nextSection: search.moveSection(1)
        case .previousSection: search.moveSection(-1)
        case .open: search.activate()
        case .escape: _ = search.escape()
        case .deleteOnEmpty:
            guard search.scope != nil else { return false }
            search.removeScope()
        case .clear: search.text = ""
        }
        return true
    }

    // MARK: The sections

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(search.sections) { section in
                        SearchSectionView(search: search, section: section, inbox: inbox,
                                          linesAfter: linesAfter(section))
                    }
                }
                .padding(.vertical, 8)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: RowsHeightKey.self, value: geometry.size.height)
                    }
                }
            }
            .frame(height: min(rowsHeight, max(120, maxHeight - Self.chromeHeight)))
            .onPreferenceChange(RowsHeightKey.self) { rowsHeight = $0 }
            .onChange(of: search.selection) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    /// The lines under a section: "Type one more letter…" under the people found, and the 100-chats limit.
    private func linesAfter(_ section: SearchSection) -> [String] {
        var lines: [String] = []
        if section.kind == .chats, section.items.count >= SearchModel.moreChats {
            lines.append(String(localized: "Showing the first \(SearchModel.moreChats) chats. Type more to narrow it down."))
        }
        if search.needsMoreLettersUnderChats,
           section.kind == search.sections.last(where: { [.chats, .inGroups].contains($0.kind) })?.kind {
            lines.append(String(localized: "Type one more letter to search messages."))
        }
        return lines
    }
}

private struct RowsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// "In: <chat> ×": the chat searched in. × (or ⌫ in an empty field) searches every chat again.
private struct ScopeChip: View {
    let name: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(String(localized: "In: \(name)"))
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Search every chat"))
            .accessibilityLabel(String(localized: "Search every chat"))
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        .frame(maxWidth: 220, alignment: .leading)
        .fixedSize()
    }
}

/// One section: its title row, its rows (media in a grid of four), Show more, and the lines under it.
private struct SearchSectionView: View {
    @ObservedObject var search: SearchModel
    let section: SearchSection
    let inbox: InboxModel
    let linesAfter: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleRow
            if section.kind == .media {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(section.items) { item in
                        if case let .message(hit) = item {
                            MediaCell(hit: hit, isSelected: search.selection == item.id)
                                .id(item.id)
                                .onTapGesture { open(item) }
                        }
                    }
                }
                .padding(.horizontal, 10)
            } else {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    if index == section.partialMatchesStart {
                        PartialMatchesDivider()
                    }
                    SearchRowView(item: item, isSelected: search.selection == item.id,
                                  networkName: inbox.networkName)
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture { open(item) }
                }
            }
            if section.canShowMore {
                Button(String(localized: "Show more")) { Task { await search.showMore(section.kind) } }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            ForEach(linesAfter, id: \.self) { line in
                quietLine(line)
            }
            if section.kind == .messages {
                // The counterpart of 01 §12's limit line, in Courier's words.
                quietLine(String(localized: "Courier searches the messages on this Mac. Older history appears as each network sends it."))
            }
        }
        .padding(.bottom, 6)
    }

    private var titleRow: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            switch section.kind {
            case .recentSearches:
                Button(String(localized: "Clear Recent Searches"), action: search.clearRecentSearches)
                    .buttonStyle(.borderless)
                    .font(.caption)
            case .messages:
                Button(search.filters.partial ? String(localized: "Hide partial matches")
                    : String(localized: "Show partial matches")) {
                    search.filters.partial.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help(String(localized: "Also list messages that have some of the words, after those with all of them."))
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var title: String {
        switch section.kind {
        case .recent: String(localized: "Recent")
        case .lastArchived: String(localized: "Last archived")
        case .recentSearches: String(localized: "Recent searches")
        case .chats: String(localized: "Chats")
        case .inGroups: String(localized: "In groups")
        case .bookmarks: String(localized: "Bookmarks")
        case .media: String(localized: "Media")
        case .messages: String(localized: "Messages")
        }
    }

    private func quietLine(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    /// A click opens the row, as Return does.
    private func open(_ item: SearchItem) {
        search.select(item.id)
        search.activate()
    }
}

/// Where the messages with only some of the words begin.
private struct PartialMatchesDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.quaternary).frame(height: 1)
            Text(String(localized: "Partial matches"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// What the panel says in place of its rows, in Courier's words.
struct SearchNoticeView: View {
    let notice: SearchNotice
    let clearFilters: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            switch notice {
            case .welcome:
                line(String(localized: "Find any chat, person or message on this Mac."))
            case .welcomeInChat:
                line(String(localized: "Search this chat’s messages.",
                            comment: "Search panel inside one chat (⌘F), before typing, with no recent searches."))
            case .searching:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    line(String(localized: "Searching…"))
                }
            case let .noMatches(text):
                Text(String(localized: "No matches for “\(text)”"))
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                line(String(localized: "Check the spelling, or try fewer words."))
            case .nothingMatchesFilters:
                Text(String(localized: "Nothing matches these filters."))
                    .font(.headline)
                Button(String(localized: "Clear Filters"), action: clearFilters)
            case .emojiOnly:
                line(String(localized: "Search for a word or a name. Emoji and punctuation aren’t searched."))
            case .needMoreLetters:
                line(String(localized: "Type one more letter to search messages."))
            case .failed:
                Text(String(localized: "Search isn’t working right now."))
                    .font(.headline)
                Button(String(localized: "Try Again"), action: retry)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .accessibilityElement(children: .contain)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - The field

/// What a key in the search field asks the panel for.
enum SearchFieldCommand {
    /// ↑ and ⌃P; ↓ and ⌃N.
    case up, down
    /// Tab, ⇧Tab.
    case nextSection, previousSection
    /// Return.
    case open
    /// Esc.
    case escape
    /// ⌫ with nothing typed.
    case deleteOnEmpty
    /// ⌘⌫.
    case clear
}

/// A one-line field that keeps the keyboard while the panel is up, and hands the panel's keys to it. The field
/// editor turns the keys into commands (⌃P and ⌃N are moveUp: and moveDown: there, ⌘⌫ deleteToBeginningOfLine:),
/// so each key is read once, as the system's key bindings name it.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// True when the panel took the key.
    let command: (SearchFieldCommand) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusedTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        field.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        // Only when it differs: setting it moves the caret, and would end a character being composed.
        if field.stringValue != text, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
            field.setAccessibilityLabel(placeholder)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField

        init(_ parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // While a character is still being composed, the keys belong to the input method.
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)): return parent.command(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.command(.down)
            case #selector(NSResponder.insertTab(_:)): return parent.command(.nextSection)
            case #selector(NSResponder.insertBacktab(_:)): return parent.command(.previousSection)
            case #selector(NSResponder.insertNewline(_:)): return parent.command(.open)
            // Esc; left to the field editor it would open the word-completion list.
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
                return parent.command(.escape)
            case #selector(NSResponder.deleteBackward(_:)):
                return textView.string.isEmpty ? parent.command(.deleteOnEmpty) : false
            case #selector(NSResponder.deleteToBeginningOfLine(_:)):
                return parent.command(.clear)
            default:
                return false
            }
        }
    }
}

/// Takes the keyboard as soon as it is in a window, so the panel opens ready to type, and gives it back when the
/// panel closes: to what had it before (the composer, the chat list), else the composer when a chat is open, else
/// the chat list. Without that, the window itself keeps the keyboard: typing beeps and the list's keys do nothing.
private final class FocusedTextField: NSTextField {
    private weak var previousResponder: NSResponder?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        previousResponder = window.firstResponder
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let window { giveKeyboardBack(in: window) }
        super.viewWillMove(toWindow: newWindow)
    }

    private func giveKeyboardBack(in window: NSWindow) {
        // Only while the keyboard is still the panel's: something else may have taken it (a chat opened, say).
        let current = window.firstResponder
        let isOurs = current === self || current === window
            || (current as? NSTextView).map { $0.isFieldEditor && $0.delegate === self } == true
        guard isOurs else { return }
        if let previous = previousResponder, previous !== window, previous !== self,
           (previous as? NSView)?.window === window, window.makeFirstResponder(previous) {
            return
        }
        guard let content = window.contentView else { return }
        if let composer = Self.first(PlainTextView.self, in: content), window.makeFirstResponder(composer) { return }
        if let list = Self.first(NSTableView.self, in: content) { window.makeFirstResponder(list) }
    }

    /// The first view of a type under `view`, depth first.
    private static func first<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        for subview in view.subviews {
            if let match = subview as? T { return match }
            if let match = first(type, in: subview) { return match }
        }
        return nil
    }
}
