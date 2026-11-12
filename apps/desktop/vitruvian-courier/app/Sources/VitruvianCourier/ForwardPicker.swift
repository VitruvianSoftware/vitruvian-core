// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// "Forward message" (02 §2.6): find chats by name and choose up to 20; Courier sends each a copy. The person
/// forwarded to sees it as from me, not from who wrote it, and the picker says so.
struct ForwardPicker: View {
    /// Made once, when the picker opens, and kept while it is open.
    @StateObject private var model: ForwardPickerModel
    let networkName: (String) -> String
    let forward: ([String]) -> Void
    let cancel: () -> Void

    init(model: @autoclosure @escaping () -> ForwardPickerModel, networkName: @escaping (String) -> String,
         forward: @escaping ([String]) -> Void, cancel: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model())
        self.networkName = networkName
        self.forward = forward
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Forward message"))
                .font(.headline)
            TextField(String(localized: "Search chats"), text: $model.query)
                .textFieldStyle(.roundedBorder)
            List(model.results, id: \.roomID) { row in
                Button { model.toggle(row) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.isSelected(row) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.isSelected(row) ? Color.accentColor : .secondary)
                        ChatAvatar(row: row)
                            .frame(width: 26, height: 26)
                        Text(row.name.isEmpty ? String(localized: "Unnamed chat") : row.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        NetworkBadge(network: row.network, name: networkName(row.network), size: 13)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.isSelected(row) && model.isFull)
            }
            .listStyle(.plain)
            .frame(minHeight: 220)
            if model.failed {
                Text(String(localized: "Courier couldn’t search your chats. Try again."))
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Text(String(localized: "The people you forward to won’t see who it came from."))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(model.isFull ? String(localized: "You can forward to \(ForwardPickerModel.maxChats) chats at most")
                    : String(localized: "\(model.selected.count) selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Forward")) { forward(model.selected.map(\.roomID)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 460)
        .onAppear { model.find() }
    }
}

/// React… : any emoji. The quick ones first, then more, and a field for any other.
struct ReactionPicker: View {
    let react: (String) -> Void
    let cancel: () -> Void
    @State private var typed = ""

    static let more = ["❤️", "👍", "😂", "😮", "😢", "🙏", "🔥", "🎉", "👏", "😍", "🤔", "👀", "💯", "✅", "😅", "🙌",
                       "😊", "😎", "🥲", "😡", "👎", "🤝", "💪", "✨"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "React"))
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8), spacing: 4) {
                ForEach(Self.more, id: \.self) { emoji in
                    Button { react(emoji) } label: {
                        Text(emoji).font(.title2).frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "React with \(emoji)"))
                }
            }
            HStack {
                TextField(String(localized: "Other emoji"), text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Button(String(localized: "Emoji & Symbols")) { NSApp.orderFrontCharacterPalette(nil) }
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "React")) {
                    if let first = typed.trimmingCharacters(in: .whitespaces).first { react(String(first)) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
