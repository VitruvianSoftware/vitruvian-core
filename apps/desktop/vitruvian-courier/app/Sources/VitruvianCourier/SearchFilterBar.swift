// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import VitruvianCourierCore
import SwiftUI

/// The filters under the search field (01 §12): Accounts, Type, Sent / Received, Chats and Time. Each is a chip
/// with a menu; an active chip shows its choice and an × that turns it off. Every change searches at once.
struct SearchFilterBar: View {
    @ObservedObject var search: SearchModel
    /// The linked networks, for Accounts.
    let accounts: [AccountStatusItem]

    private var controls: SearchPanelControls {
        SearchPanelControls.resolve(
            isScopedToChat: search.isScoped,
            hasAccounts: !accounts.isEmpty,
            filters: search.filters,
            hasCommandBarAction: false
        )
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if controls.showsAccountsFilter { accountsChip }
                typeChip
                senderChip
                // Inside one chat, whether it is a group is already decided.
                if controls.showsChatTypeFilter { chatTypeChip }
                periodChip
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: The chips

    private var accountsChip: some View {
        let chosen = accounts.filter { search.filters.networks.contains($0.network) }.map(\.displayName)
        return FilterChip(title: String(localized: "Accounts"), choice: joined(chosen, count: search.filters.networks.count),
                          clear: { search.filters.networks = [] }) {
            ForEach(accounts, id: \.network) { account in
                Toggle(account.displayName, isOn: Binding(
                    get: { search.filters.networks.contains(account.network) },
                    set: { on in
                        if on { search.filters.networks.insert(account.network) }
                        else { search.filters.networks.remove(account.network) }
                    }))
            }
        }
    }

    private var typeChip: some View {
        let chosen = SearchKind.allCases.filter(search.filters.kinds.contains).map(Self.title)
        return FilterChip(title: String(localized: "Type"), choice: joined(chosen, count: chosen.count),
                          clear: { search.filters.kinds = [] }) {
            ForEach(Self.kindOrder, id: \.self) { kind in
                Toggle(Self.title(kind), isOn: Binding(
                    get: { search.filters.kinds.contains(kind) },
                    set: { on in
                        if on { search.filters.kinds.insert(kind) } else { search.filters.kinds.remove(kind) }
                    }))
            }
        }
    }

    private var senderChip: some View {
        FilterChip(title: String(localized: "Sent / Received"), choice: search.filters.sender.map(Self.senderTitle),
                   clear: { search.filters.sender = nil }) {
            Picker(String(localized: "Sent / Received"), selection: $search.filters.sender) {
                Text(String(localized: "Anyone")).tag(String?.none)
                Text(Self.senderTitle("me")).tag(String?.some("me"))
                Text(Self.senderTitle("others")).tag(String?.some("others"))
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var chatTypeChip: some View {
        FilterChip(title: String(localized: "Chats"), choice: search.filters.chatType.map(Self.chatTypeTitle),
                   clear: { search.filters.chatType = nil }) {
            Picker(String(localized: "Chats"), selection: $search.filters.chatType) {
                Text(String(localized: "All chats")).tag(String?.none)
                Text(Self.chatTypeTitle("dm")).tag(String?.some("dm"))
                Text(Self.chatTypeTitle("group")).tag(String?.some("group"))
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var periodChip: some View {
        FilterChip(title: String(localized: "Time"),
                   choice: search.filters.period == .anyTime ? nil : Self.title(search.filters.period),
                   clear: { search.filters.period = .anyTime }) {
            Picker(String(localized: "Time"), selection: $search.filters.period) {
                ForEach(SearchPeriod.allCases, id: \.self) { Text(Self.title($0)).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    /// One choice by name; two joined; more as the first and a count.
    private func joined(_ names: [String], count: Int) -> String? {
        guard count > 0 else { return nil }
        switch names.count {
        case 0: return String(localized: "\(count) accounts")
        case 1, 2: return names.joined(separator: ", ")
        default: return String(localized: "\(names[0]) and \(names.count - 1) more")
        }
    }

    // MARK: Names

    /// The Type menu's order.
    static let kindOrder: [SearchKind] = [.text, .image, .video, .audio, .file, .link, .sticker]

    static func title(_ kind: SearchKind) -> String {
        switch kind {
        case .text: String(localized: "Text")
        case .image: String(localized: "Photos")
        case .video: String(localized: "Videos")
        case .audio: String(localized: "Voice and audio")
        case .file: String(localized: "Files")
        case .link: String(localized: "Links")
        case .sticker: String(localized: "Stickers")
        }
    }

    static func senderTitle(_ sender: String) -> String {
        sender == "me" ? String(localized: "Sent by me") : String(localized: "Received")
    }

    static func chatTypeTitle(_ type: String) -> String {
        type == "dm" ? String(localized: "Direct messages") : String(localized: "Groups")
    }

    /// Inferred (inventory 01 §12): each period counts back from now (SearchPeriod).
    static func title(_ period: SearchPeriod) -> String {
        switch period {
        case .anyTime: String(localized: "Any time")
        case .lastHour: String(localized: "Last hour")
        case .lastWeek: String(localized: "Last week")
        case .last30Days: String(localized: "Last 30 days")
        case .lastYear: String(localized: "Last year")
        }
    }
}

/// A filter's chip: its menu, named by the choice when one is made, and then an × that clears it.
///
/// It has to read as a control that is on: the label in the primary text colour (a menu's own label drew dimmed, dark
/// grey on the panel), a chevron when nothing is chosen, a fill and a visible outline. A chosen chip is the accent
/// with white text.
private struct FilterChip<Choices: View>: View {
    let title: String
    let choice: String?
    let clear: () -> Void
    @ViewBuilder let choices: () -> Choices
    @Environment(\.themeAccentColor) private var themeAccent

    var body: some View {
        HStack(spacing: 4) {
            Menu(content: choices) {
                HStack(spacing: 4) {
                    Text(choice ?? title)
                        .lineLimit(1)
                    if choice == nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(labelColor)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(title)
            .accessibilityLabel(choice.map { "\(title): \($0)" } ?? title)
            if choice != nil {
                Button(action: clear) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(labelColor)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Clear this filter"))
                .accessibilityLabel(String(localized: "Clear \(title)"))
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(choice == nil ? Color.primary.opacity(0.08) : themeAccent))
        // The menu's own button draws a little past the label; the capsule is the chip's edge.
        .clipShape(Capsule())
        // The outline is for a chip with no choice made; a chosen chip is filled with the accent.
        .overlay(Capsule().strokeBorder(Color.primary.opacity(choice == nil ? 0.3 : 0), lineWidth: 1))
    }

    private var labelColor: Color { choice == nil ? .primary : .white }
}
