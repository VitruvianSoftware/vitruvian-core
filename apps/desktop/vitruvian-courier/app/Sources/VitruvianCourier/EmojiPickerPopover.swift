// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// The emoji button's picker, open over the button: a search box (focused), "Frequently used", one tab per category,
/// the emoji in a grid, and a skin tone for hands and people. A click adds the emoji where the caret is and closes the
/// picker; Shift-click adds it and keeps the picker open. Escape closes it. "Emoji & Symbols…" at the bottom opens the
/// macOS Character Viewer, as ⌃⌘Space does everywhere.
struct EmojiPickerPopover: View {
    @ObservedObject var composer: ComposerModel
    @State private var query = ""
    @State private var frequent: [String] = []
    @FocusState private var searchFocused: Bool

    private static let columns: [GridItem] = Array(repeating: GridItem(.flexible(minimum: 30), spacing: 2), count: 8)

    private var sections: [EmojiPickerSection] {
        EmojiPickerContent.sections(query: query, tone: composer.emojiSkinTone, frequent: frequent)
    }

    var body: some View {
        let shown = sections
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        categoryTabs(shown, proxy: proxy)
                    }
                    Divider()
                    grid(shown)
                }
            }
            Divider()
            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
        }
        .frame(width: 330, height: 380)
        .onAppear {
            frequent = composer.emojiUsage.frequent()
            DispatchQueue.main.async { searchFocused = true }
        }
        .onExitCommand { composer.isEmojiPickerPresented = false }
        .accessibilityIdentifier("composer.emojiPicker")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search emoji"), text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($searchFocused)
                .accessibilityIdentifier("composer.emojiPicker.search")
                .onSubmit {
                    // Return chooses the first match, as in any search-and-pick list.
                    if let first = sections.first?.items.first { choose(first.glyph, keepOpen: false) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }

    private func categoryTabs(_ shown: [EmojiPickerSection], proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 2) {
            ForEach(shown) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(section.id, anchor: .top) }
                } label: {
                    Image(systemName: section.category?.symbolName ?? "clock")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(section.title)
            }
        }
        .padding(.horizontal, 8)
    }

    private func grid(_ shown: [EmojiPickerSection]) -> some View {
        Group {
            if shown.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "face.dashed")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "No matching emoji"))
                        .font(.callout.weight(.medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6, pinnedViews: []) {
                        ForEach(shown) { section in
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 6)
                                .id(section.id)
                            LazyVGrid(columns: Self.columns, spacing: 2) {
                                ForEach(section.items) { item in
                                    EmojiCell(item: item) { choose(item.glyph, keepOpen: NSEvent.modifierFlags.contains(.shift)) }
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(EmojiSkinTone.allCases) { tone in
                    Button {
                        composer.emojiSkinTone = tone
                    } label: {
                        Text(verbatim: "\(tone.swatch)  \(tone.title)")
                    }
                }
            } label: {
                Text(verbatim: composer.emojiSkinTone.swatch)
                    .font(.system(size: 16))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "Skin tone for hands and people"))
            .accessibilityLabel(String(localized: "Skin tone"))
            .accessibilityValue(composer.emojiSkinTone.title)

            Spacer(minLength: 8)

            Button {
                composer.isEmojiPickerPresented = false
                NSApp.orderFrontCharacterPalette(nil)
            } label: {
                Text(String(localized: "Emoji & Symbols…"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Open the macOS Character Viewer (⌃⌘Space)"))
        }
    }

    private func choose(_ glyph: String, keepOpen: Bool) {
        composer.insertEmoji(glyph, keepOpen: keepOpen)
        frequent = composer.emojiUsage.frequent()
    }
}

private struct EmojiCell: View {
    let item: EmojiPickerItem
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: item.glyph)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.1) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.name.isEmpty ? item.glyph : item.name.replacingOccurrences(of: "_", with: " "))
        .accessibilityLabel(item.name.isEmpty ? item.glyph : item.name.replacingOccurrences(of: "_", with: " "))
    }
}
