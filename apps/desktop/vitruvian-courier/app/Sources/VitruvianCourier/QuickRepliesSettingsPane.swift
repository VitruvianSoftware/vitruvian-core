// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Settings ▸ Quick Replies pane (`QuickRepliesSettingsPane.swift`, `QuickRepliesPrefsSubView.tsx`):
/// Create, edit, and delete saved replies (`QuickReplies`), with template variable guide
/// (`{first_name}`, `{last_name}`, `{full_name}`, `{username}`, `{phone_number}`, `{email}`).
struct QuickRepliesSettingsPane: View {
    @ObservedObject var quickReplies: QuickReplies
    @ObservedObject var lifecycle: SystemLifecycleModel
    var highlightedSettingID: String? = nil

    @State private var selectedReplyID: QuickReply.ID?

    public static let supportedTemplateVariables: [(token: String, description: String)] = [
        ("{first_name}", String(localized: "Other person’s first name in a direct chat")),
        ("{last_name}", String(localized: "Other person’s last name in a direct chat")),
        ("{full_name}", String(localized: "Other person’s full name in a direct chat")),
        ("{username}", String(localized: "Other person’s username when available")),
        ("{phone_number}", String(localized: "Other person’s phone number when available")),
        ("{email}", String(localized: "Other person’s email address when available")),
    ]

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                savedRepliesSection
                templateVariablesSection
            }
            .formStyle(.grouped)
            .disabled(lifecycle.isLocked)
            .sheet(item: $quickReplies.editing) { edit in
                QuickReplySheetEditor(edit: edit, quickReplies: quickReplies)
            }
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                if let targetID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }

    private var savedRepliesSection: some View {
        Section(SettingsNavigationModel.title(for: "quickReplies.savedReplies")) {
            VStack(alignment: .leading, spacing: 10) {
                if quickReplies.all.isEmpty {
                    Text(String(localized: "No quick replies saved yet. Type ; followed by a shortcut in any chat to insert one."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    List(quickReplies.all, selection: $selectedReplyID) { reply in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: ";" + reply.title)
                                .font(.subheadline.weight(.semibold))
                            Text(reply.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                        .tag(reply.id)
                    }
                    .frame(minHeight: 160)
                }

                HStack(spacing: 8) {
                    Button(String(localized: "Add Quick Reply…")) {
                        quickReplies.editing = QuickReplyEdit(reply: nil)
                    }
                    .disabled(quickReplies.all.count >= QuickReplies.maxCount)

                    Button(String(localized: "Edit…")) {
                        if let reply = quickReplies.all.first(where: { $0.id == selectedReplyID }) {
                            quickReplies.editing = QuickReplyEdit(reply: reply)
                        }
                    }
                    .disabled(selectedReplyID == nil)

                    Button(String(localized: "Delete"), role: .destructive) {
                        if let id = selectedReplyID {
                            quickReplies.remove(id)
                            selectedReplyID = nil
                        }
                    }
                    .disabled(selectedReplyID == nil)

                    Spacer()

                    Text("\(quickReplies.all.count)/\(QuickReplies.maxCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .settingAnchor("quickReplies.savedReplies", highlighted: highlightedSettingID)
        }
    }

    private var templateVariablesSection: some View {
        Section(SettingsNavigationModel.title(for: "quickReplies.variables")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Use these placeholders inside a quick reply to fill in details from a direct chat:"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Self.supportedTemplateVariables, id: \.token) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: item.token)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.07))
                            )
                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .settingAnchor("quickReplies.variables", highlighted: highlightedSettingID)
        }
    }
}

struct QuickReplySheetEditor: View {
    let edit: QuickReplyEdit
    let quickReplies: QuickReplies
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var text: String = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(edit.reply == nil ? String(localized: "New Quick Reply") : String(localized: "Edit Quick Reply"))
                .font(.headline)

            TextField(String(localized: "Title (typed after ;)"), text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))

            Text(String(localized: "Variables: {first_name}, {last_name}, {full_name}, {username}, {phone_number}, {email}"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Save"), action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            title = edit.reply?.title ?? ""
            text = edit.reply?.text ?? ""
        }
    }

    private func save() {
        do {
            if var reply = edit.reply {
                reply.title = title
                reply.text = text
                try quickReplies.update(reply)
            } else {
                try quickReplies.add(title: title, text: text)
            }
            dismiss()
        } catch let error as QuickReplyError {
            problem = MessageActionsModel.text(for: error)
        } catch {
            problem = String(localized: "That didn’t work. Try again.")
        }
    }
}
