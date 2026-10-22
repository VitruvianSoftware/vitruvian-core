// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// "@" in the composer (01 §6's TextAreaAutocomplete): the chat's members whose name matches, and @room first where
/// the chat has it. ↑ and ↓ move, Return or Tab put the mention in, Esc closes it; a click puts it in.
struct MentionPicker: View {
    let members: [Member]
    let index: Int
    let choose: (Member) -> Void

    var body: some View {
        PickerList(count: members.count, index: index) { row in
            let member = members[row]
            Button { choose(member) } label: {
                HStack(spacing: 8) {
                    if member.userID == "@room" {
                        Image(systemName: "person.3.fill")
                            .frame(width: 22, height: 22)
                        Text(verbatim: "@room")
                            .fontWeight(.medium)
                        Text(String(localized: "Everyone in this chat"))
                            .foregroundStyle(.secondary)
                    } else {
                        AvatarView(path: member.avatarPath, initials: InboxRow.initials(of: member.name), seed: member.name)
                            .frame(width: 22, height: 22)
                        Text(member.name)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(String(localized: "People to mention"))
    }
}

/// A picker's rows above the composer, the one the arrows are on tinted.
struct PickerList<Row: View>: View {
    let count: Int
    let index: Int
    @ViewBuilder let row: (Int) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0 ..< count, id: \.self) { position in
                row(position)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(position == index ? Color.accentColor.opacity(0.18) : .clear))
            }
        }
        .padding(4)
        .frame(maxWidth: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 1)
        .accessibilityElement(children: .contain)
    }
}
