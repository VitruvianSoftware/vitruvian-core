// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Multi-column keyboard shortcuts cheat sheet (`⌘/`, `hotkey Keyboard Shortcuts`,
/// `command Show keyboard shortcuts`, `menu:Help Keyboard Shortcuts`), reading from the shared `HotkeyRegistry`.
struct KeyboardShortcutsSheet: View {
    @ObservedObject var registry: HotkeyRegistry
    var onCustomize: () -> Void = {}
    var onClose: () -> Void = {}
    @State private var sheetSearchQuery: String = ""

    private let columns = [
        GridItem(.flexible(minimum: 320), spacing: 20, alignment: .top),
        GridItem(.flexible(minimum: 320), spacing: 20, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(HotkeyRegistry.categories, id: \.self) { category in
                        let items = activeDefinitions(in: category)
                        if !items.isEmpty {
                            categoryCard(title: category, items: items)
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 540)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Keyboard Shortcuts"))
                    .font(.title3.weight(.semibold))
                Text(String(localized: "All active shortcuts across Courier"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search shortcuts..."), text: $sheetSearchQuery)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                if !sheetSearchQuery.isEmpty {
                    Button {
                        sheetSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func categoryCard(title: String, items: [HotkeyDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    HStack(spacing: 10) {
                        Text(item.title)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        ChordBadgesView(chords: registry.chords(for: item.id))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var footer: some View {
        HStack {
            Button(String(localized: "Customize Shortcuts…")) {
                onClose()
                onCustomize()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(String(localized: "Done")) {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func activeDefinitions(in category: String) -> [HotkeyDefinition] {
        registry.filteredDefinitions(matching: sheetSearchQuery).filter { def in
            def.category == category
                && registry.isEnabled(def.id)
                && !registry.chords(for: def.id).isEmpty
        }
    }
}
