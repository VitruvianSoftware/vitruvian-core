// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// A link being written over a range of the composer's text (⌘⇧K, or the formatting bar's Link).
struct LinkRequest: Identifiable {
    let id = UUID()
    let composer: ComposerModel
    let range: NSRange
}

/// The link dialog (01 §6's LinkDialog): the words and the address, Save and Cancel. Return saves, Esc cancels. An
/// address with no scheme is taken as https; one the engine wouldn't send (not http, https or mailto) is refused
/// here, with why. Saving with no address takes the link off.
struct LinkDialog: View {
    let request: LinkRequest
    @Environment(\.dismiss) private var dismiss
    @State private var words = ""
    @State private var address = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Link"))
                .font(.headline)
            Form {
                TextField(String(localized: "Text"), text: $words)
                TextField(String(localized: "URL"), text: $address, prompt: Text(verbatim: "https://"))
            }
            .formStyle(.columns)
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear(perform: fill)
    }

    /// The selected words, and the address of a link already there.
    private func fill() {
        let text = request.composer.text as NSString
        guard request.range.location != NSNotFound, request.range.location + request.range.length <= text.length else {
            return
        }
        words = text.substring(with: request.range)
        address = request.composer.entities.first {
            $0.kind == .link && $0.offset <= request.range.location
                && request.range.location + request.range.length <= $0.offset + $0.length
        }?.url ?? ""
    }

    private func save() {
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            request.composer.setLink(nil, text: words, in: request.range)
            dismiss()
            return
        }
        guard let url = LinkAddress.url(from: typed) else {
            problem = String(localized: "Enter a web address (https://…) or an email address (mailto:…).")
            return
        }
        request.composer.setLink(url, text: words, in: request.range)
        dismiss()
    }
}
