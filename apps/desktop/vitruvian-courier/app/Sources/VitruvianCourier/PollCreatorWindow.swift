// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// "New Poll" (01 §6's PollCreator): a question, options (an empty row at the end adds one, up to as many as the
/// chat takes), and "Allow multiple answers". What would stop it from going is listed under it, in the engine's
/// limits. Closing it with something written asks first.
struct PollCreatorWindow: View {
    let features: PollFeatures
    /// Sends the poll; true when it went.
    let create: (PollDraft) async -> Bool
    let close: () -> Void
    @State var draft = PollDraft()
    @State private var askDiscard = false
    @State private var sending = false
    /// Problems show once Create was pressed, not while the first words are typed.
    @State private var triedToSend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "New Poll"))
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Question"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Question"), text: $draft.question,
                          prompt: Text(String(localized: "Ask a question…")))
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Options"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(draft.options.indices, id: \.self) { index in
                    HStack(spacing: 6) {
                        TextField(String(localized: "Option"), text: option(index),
                                  prompt: Text(String(localized: "Add an option")))
                            .textFieldStyle(.roundedBorder)
                        Button { remove(index) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(draft.options.count <= 2)
                        .help(String(localized: "Remove option"))
                        .accessibilityLabel(String(localized: "Remove option"))
                    }
                }
                Text(remainingLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle(String(localized: "Allow multiple answers"), isOn: $draft.multiple)
            if triedToSend, !problems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.circle")
                    }
                }
                .font(.callout)
                .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Create Poll"), action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(sending)
            }
        }
        .padding(20)
        .frame(width: 380)
        .alert(String(localized: "Discard poll?"), isPresented: $askDiscard) {
            Button(String(localized: "Discard"), role: .destructive, action: close)
            Button(String(localized: "Keep Editing"), role: .cancel) {}
        } message: {
            Text(String(localized: "Your poll will be deleted."))
        }
    }

    private var problems: [String] { draft.problems(in: features) }

    /// "You can enter 8 more options": the rows still free under the chat's most.
    private var remainingLine: String {
        guard features.maxOptions > 0 else { return "" }
        let left = max(0, features.maxOptions - draft.sendableOptions.count)
        if left == 0 { return String(localized: "You have added the maximum number of options") }
        return left == 1 ? String(localized: "You can enter \(left) more option")
            : String(localized: "You can enter \(left) more options")
    }

    /// An option row; filling the last one adds an empty row after it, while the chat takes more.
    private func option(_ index: Int) -> Binding<String> {
        Binding(get: { index < draft.options.count ? draft.options[index] : "" }, set: { value in
            guard index < draft.options.count else { return }
            draft.options[index] = value
            let last = draft.options.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !last.isEmpty, !draft.isAtMaximum(in: features) { draft.options.append("") }
        })
    }

    private func remove(_ index: Int) {
        guard draft.options.count > 2, index < draft.options.count else { return }
        draft.options.remove(at: index)
    }

    private var hasContent: Bool {
        !draft.sendableQuestion.isEmpty || !draft.sendableOptions.isEmpty
    }

    private func cancel() {
        if hasContent { askDiscard = true } else { close() }
    }

    private func send() {
        triedToSend = true
        guard problems.isEmpty else { return }
        sending = true
        Task {
            let sent = await create(draft)
            sending = false
            if sent { close() }
        }
    }
}
