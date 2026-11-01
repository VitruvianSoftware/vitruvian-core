// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// `Settings ▸ Integrations`: the local API that lets Claude and other MCP apps use Courier (Allow connections,
/// Remote Access, the port, the endpoint), the connections approved for it, and the companions Courier doesn't
/// have yet. Covers `setting:integrations *`, `BrowserExtPrefsSubView.tsx`, `MobileAppsPrefsSubView.tsx` and
/// `DebugPreferencesIndex.tsx`.
public struct IntegrationsSettingsPane: View {
    @ObservedObject public var model: IntegrationsModel
    public var highlightedSettingID: String?

    public init(model: IntegrationsModel, highlightedSettingID: String? = nil) {
        self.model = model
        self.highlightedSettingID = highlightedSettingID
    }

    public var body: some View {
        ScrollViewReader { proxy in
            Form {
                localAPISection
                connectionsSection
                companionSections
            }
            .formStyle(.grouped)
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                if let targetID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
        .task { await model.refresh() }
        .alert(String(localized: "Turn on Remote Access?"), isPresented: $model.isConfirmingRemoteAccess) {
            Button(String(localized: "Turn On")) { Task { await model.confirmRemoteAccess() } }
            Button(String(localized: "Cancel"), role: .cancel) { model.cancelRemoteAccess() }
        } message: {
            Text(IntegrationsModel.remoteAccessWarning)
        }
        .alert(
            revokeTitle,
            isPresented: Binding(
                get: { model.tokenPendingRevoke != nil },
                set: { if !$0 { model.tokenPendingRevoke = nil } }
            )
        ) {
            Button(String(localized: "Revoke"), role: .destructive) { Task { await model.confirmRevoke() } }
            Button(String(localized: "Cancel"), role: .cancel) { model.tokenPendingRevoke = nil }
        } message: {
            Text(String(localized: "It stops working at once. An app that uses it will need a new connection."))
        }
        .sheet(isPresented: Binding(
            get: { model.isPresentingNewConnection },
            set: { if !$0 { model.dismissNewConnection() } }
        )) {
            NewConnectionSheet(model: model)
        }
    }

    private var revokeTitle: String {
        guard let token = model.tokenPendingRevoke else { return String(localized: "Revoke this connection?") }
        return String(localized: "Revoke “\(token.name)”?")
    }

    // MARK: - The local API

    private var localAPISection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.isEnabled },
                set: { on in Task { await model.setEnabled(on) } }
            )) {
                Text(String(localized: "Allow connections"))
                Text(String(localized: "Claude and other apps that support MCP can read your chats, with a connection you approve."))
            }
            .settingAnchor("integrations.localAPI", highlighted: highlightedSettingID)

            Toggle(isOn: Binding(
                get: { model.isRemote },
                set: { on in Task { await model.requestRemoteAccess(on) } }
            )) {
                Text(String(localized: "Remote Access"))
                Text(String(localized: "Other devices on your network can connect too. Off, only apps on this Mac can."))
            }
            .settingAnchor("integrations.remoteAccess", highlighted: highlightedSettingID)

            VStack(alignment: .leading, spacing: 4) {
                TextField(String(localized: "Port"), text: $model.portText)
                    .onSubmit { Task { await model.savePort() } }
                if let error = model.portError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            LabeledContent(String(localized: "Status")) {
                Text(model.statusLine)
                    .foregroundStyle(model.statusIsProblem ? Color.red : Color.secondary)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent(String(localized: "MCP endpoint")) {
                HStack(spacing: 8) {
                    Text(model.endpoint)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(String(localized: "Copy")) { Pasteboard.copy(model.endpoint) }
                        .controlSize(.small)
                }
            }

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(String(localized: "Connect other apps"))
        }
    }

    // MARK: - Approved connections

    private var connectionsSection: some View {
        Section {
            if model.tokens.isEmpty {
                Text(String(localized: "No approved connections yet."))
                    .foregroundStyle(.secondary)
            }
            ForEach(model.tokens) { token in
                ConnectionRow(
                    token: token,
                    setCanSend: { on in Task { await model.setCanSend(on, for: token) } },
                    revoke: { model.tokenPendingRevoke = token }
                )
            }
            HStack {
                Spacer()
                Button(String(localized: "New connection…")) { model.beginNewConnection() }
            }
            .settingAnchor("integrations.connections", highlighted: highlightedSettingID)
        } header: {
            Text(String(localized: "Approved connections"))
        }
    }

    // MARK: - Companions Courier doesn't have

    @ViewBuilder
    private var companionSections: some View {
        Section(String(localized: "Browser extension")) {
            CompanionRow(
                title: String(localized: "Browser companion extension"),
                detail: String(localized: "Browser extension pairing isn’t available yet in Courier. Links and attachments open directly on this Mac."),
                badge: String(localized: "Not available yet")
            )
            .settingAnchor("integrations.browserExtension", highlighted: highlightedSettingID)
        }

        Section(String(localized: "Mobile companion apps")) {
            CompanionRow(
                title: String(localized: "Mobile companion sync"),
                detail: String(localized: "Courier connects directly to your chat networks on this Mac without a cloud relay or mobile companion app."),
                badge: String(localized: "Not available yet")
            )
            .settingAnchor("integrations.mobileApps", highlighted: highlightedSettingID)
        }

        Section(String(localized: "Advanced and local diagnostics")) {
            CompanionRow(
                title: String(localized: "Local-first diagnostics"),
                detail: String(localized: "Use View ▸ Toggle Bridge Logs or Help ▸ Report a Problem… (⌘⇧P) to inspect local bridge activity and save scrubbed diagnostic bundles on this Mac."),
                badge: nil
            )
            .settingAnchor("integrations.developer", highlighted: highlightedSettingID)
        }
    }
}

/// One approved connection: its name, when it was made and last used, whether it may send, and Revoke.
private struct ConnectionRow: View {
    let token: APIToken
    let setCanSend: (Bool) -> Void
    let revoke: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // The name came from the client: plain text, never markup.
                Text(verbatim: token.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle(String(localized: "Can send messages"), isOn: Binding(get: { token.canSend }, set: setCanSend))
                .toggleStyle(.checkbox)
                .fixedSize()
            Button(String(localized: "Revoke…"), action: revoke)
        }
    }

    private var details: String {
        let created = String(localized: "Created \(Self.format(token.createdMs))")
        guard let used = token.lastUsedMs else { return created + " · " + String(localized: "Never used") }
        return created + " · " + String(localized: "Last used \(Self.format(used))")
    }

    static func format(_ ms: Int64) -> String {
        // "Nov 1, 7:06 PM": short enough that a row's two dates fit on one line.
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

private struct CompanionRow: View {
    let title: String
    let detail: String
    let badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// New connection…: a name and whether it may send; once made, its secret, once, with the setup for Claude Code,
/// Cursor and VS Code.
public struct NewConnectionSheet: View {
    @ObservedObject public var model: IntegrationsModel

    public init(model: IntegrationsModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let created = model.createdConnection {
                made(created)
            } else {
                form
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "New connection"))
                .font(.headline)
            Text(String(localized: "Name it after the app that will use it, so you can tell connections apart."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField(String(localized: "Name"), text: $model.newConnectionName,
                          prompt: Text(String(localized: "Claude Code")))
                    .onSubmit { Task { await model.createConnection() } }
                Toggle(String(localized: "Can send messages"), isOn: $model.newConnectionCanSend)
            }
            .formStyle(.columns)
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { model.dismissNewConnection() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Create")) { Task { await model.createConnection() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreateConnection)
            }
        }
    }

    private func made(_ created: CreateTokenResult) -> some View {
        let secret = created.secret
        return VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "“\(created.token.name)” is ready"))
                .font(.headline)
            Text(String(localized: "Copy the secret now. Courier won’t show it again: if you lose it, revoke this connection and make a new one."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CopyBlock(title: String(localized: "Secret"), text: secret)
            CopyBlock(title: String(localized: "Claude Code over HTTP"), text: model.claudeHTTPCommand(secret: secret))
            CopyBlock(title: String(localized: "Claude Code over stdio"), text: model.claudeStdioCommand(secret: secret))

            HStack(spacing: 12) {
                LinkButtons(title: String(localized: "Cursor"), url: model.cursorLink(secret: secret))
                LinkButtons(title: String(localized: "VS Code"), url: model.vsCodeLink(secret: secret))
            }

            HStack {
                Spacer()
                Button(String(localized: "Done")) { model.dismissNewConnection() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// A labelled block of monospaced text with a Copy button.
private struct CopyBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(String(localized: "Copy")) { Pasteboard.copy(text) }
                    .controlSize(.small)
            }
            Text(verbatim: text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }
}

/// An app's install link: open it there, or copy it.
private struct LinkButtons: View {
    let title: String
    let url: URL?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Button(String(localized: "Add")) {
                if let url { NSWorkspace.shared.open(url) }
            }
            .controlSize(.small)
            Button(String(localized: "Copy link")) {
                if let url { Pasteboard.copy(url.absoluteString) }
            }
            .controlSize(.small)
        }
        .disabled(url == nil)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
