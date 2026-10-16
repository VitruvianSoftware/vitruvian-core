// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// A display_and_wait step: the QR code, emoji or code to use on the phone, while login.wait waits for it.
struct LoginDisplayStepView: View {
    let step: LoginStep

    var body: some View {
        VStack(spacing: 14) {
            if let instructions = step.instructions, !instructions.isEmpty {
                Text(instructions)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let display = step.display {
                shown(display)
            }
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "Waiting for your phone…"))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func shown(_ display: LoginDisplay) -> some View {
        let data = display.data ?? ""
        switch display.kind {
        case .qr:
            QRCodeView(data: data)
            caption(String(localized: "Scan this with your phone."))
        case .emoji:
            Text(data)
                .font(.system(size: 72))
                .accessibilityLabel(data)
            caption(String(localized: "Tap this on your phone."))
        default:
            // A code, and any kind newer than this app: show what it is.
            Text(data)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
            caption(String(localized: "Enter this on your phone."))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// A user_input step: one entry per field, checked as it is typed. Passwords and tokens are hidden, and a field
/// with options is a picker.
struct LoginInputStepView: View {
    @ObservedObject var login: LoginFlowModel
    let step: LoginStep

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let instructions = step.instructions, !instructions.isEmpty {
                Text(instructions)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(step.fields ?? [], id: \.id) { field in
                fieldView(field)
            }
            if let notice = login.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func fieldView(_ field: LoginField) -> some View {
        let value = binding(field.id)
        VStack(alignment: .leading, spacing: 4) {
            switch LoginFlowModel.entry(for: field) {
            case .plain:
                TextField(field.name, text: value)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(login.submitInput)
            case .secure:
                SecureField(field.name, text: value)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(login.submitInput)
            case let .picker(options):
                Picker(field.name, selection: value) {
                    if !options.contains(value.wrappedValue) {
                        Text(String(localized: "Choose…")).tag(value.wrappedValue)
                    }
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
            }
            if !field.description.isEmpty {
                Text(field.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !value.wrappedValue.isEmpty, !LoginFlowModel.isValid(value.wrappedValue, for: field) {
                Text(String(localized: "This doesn’t look right yet."))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { login.inputValues[id] ?? "" }, set: { login.inputValues[id] = $0 })
    }
}
