// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// ";" in the composer (01 §6's QuickReplyItem): the quick replies whose title starts with what follows it. ↑ and ↓
/// move, Return or Tab put the text in (with the other person's name filled in, in a one-to-one chat), Esc closes it.
struct QuickReplyPicker: View {
    let replies: [QuickReply]
    let index: Int
    let choose: (QuickReply) -> Void

    var body: some View {
        PickerList(count: replies.count, index: index) { row in
            let reply = replies[row]
            Button { choose(reply) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.secondary)
                    Text(verbatim: ";" + reply.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(reply.text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(String(localized: "Quick replies"))
    }
}

/// "Create quick reply from draft": a title for the composer's text.
struct QuickReplyTitleSheet: View {
    let actions: MessageActionsModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "New Quick Reply"))
                .font(.headline)
            TextField(String(localized: "Title"), text: $title)
            Text(String(localized: "Type ; and the title in a chat to put the text in."))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) {
                    actions.dismissRequest()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save")) {
                    if actions.createQuickReply(title: title) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
