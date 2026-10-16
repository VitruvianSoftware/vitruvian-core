// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Telegram's app credentials: api_id and api_hash from my.telegram.org, checked as the engine checks them, then
/// saved in the Keychain. Nothing is filled in from the Keychain, so a saved value is never shown again.
struct TelegramSetupView: View {
    @ObservedObject var login: LoginFlowModel
    @State private var apiID = ""
    @State private var apiHash = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Set up Telegram"))
                .font(.title3.weight(.semibold))
            Text(String(localized: "Telegram asks every app for its own credentials. Sign in at my.telegram.org, open API development tools, create an app, and copy its api_id and api_hash here. Courier keeps them in your Keychain."))
                .fixedSize(horizontal: false, vertical: true)
            Link(String(localized: "Open my.telegram.org"), destination: TelegramSetup.appsURL)
            // Telegram's own names for the two values: never translated.
            TextField(text: $apiID, prompt: Text(verbatim: "api_id")) { Text(verbatim: "api_id") }
                .textFieldStyle(.roundedBorder)
            if problems.contains(.apiID), !apiID.isEmpty {
                hint(String(localized: "api_id is a whole number."))
            }
            SecureField(text: $apiHash, prompt: Text(verbatim: "api_hash")) { Text(verbatim: "api_hash") }
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if problems.contains(.apiHash), !apiHash.isEmpty {
                hint(String(localized: "api_hash is 32 letters and digits."))
            }
            if let notice = login.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), action: login.close)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!problems.isEmpty)
            }
        }
    }

    private var problems: [TelegramSetup.Problem] {
        TelegramSetup.problems(apiID: apiID, apiHash: apiHash)
    }

    private func save() {
        if login.saveTelegram(apiID: apiID, apiHash: apiHash) {
            apiID = ""
            apiHash = ""
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
    }
}
