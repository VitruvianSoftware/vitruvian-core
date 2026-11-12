// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import VitruvianSpeakerCore
import SwiftUI

/// Settings › Chats for one chat app read over its local API: Beeper or
/// Courier. The same rows for both, each with its own switch, Announce
/// choice, network switches, token and address. Everything it shows and
/// does comes in from outside, so it draws the same in the Settings window
/// and in a snapshot.
///
/// Courier stays off until a token is saved: its switch is greyed and the
/// token field shows until then. Beeper keeps the rows it had: the token
/// field shows once it is switched on.
struct ChatAppSection: View {
    let app: ChatApp
    let isOn: Binding<Bool>
    let announce: Binding<ChatMonitorConfig.BeeperAnnounce>
    let networks: BeeperNetworkList
    /// A network's switch: on reads it, off mutes it.
    let networkSwitch: (String) -> Binding<Bool>
    let hasToken: Bool
    let tokenDraft: Binding<String>
    let showReplaceToken: Binding<Bool>
    let saveToken: () -> Void
    let addressDraft: Binding<String>
    let saveAddress: () -> Void
    /// "Reading Courier: WhatsApp", while the monitor reads it.
    let readingLine: String?
    /// Courier only: a network's "read it here as well" switch, for one
    /// Vitruvian Speaker's own Slack or Google Chat reader covers; and the
    /// networks it is on for. Nil for Beeper, whose skipped rows stay greyed.
    var readAnyway: ((String) -> Binding<Bool>)? = nil
    var readAnywayKeys: [String] = []

    /// Courier asks for its token before it can be switched on.
    private var needsTokenFirst: Bool { app == .courier && !hasToken }

    private var toggleKey: SettingsCatalog.Key { app == .beeper ? .beeperEnabled : .courierEnabled }
    private var announceKey: SettingsCatalog.Key { app == .beeper ? .beeperAnnounce : .courierAnnounce }
    private var addressKey: SettingsCatalog.Key { app == .beeper ? .beeperAddress : .courierAddress }

    var body: some View {
        Section {
            Toggle(toggleKey.label(), isOn: isOn)
                .disabled(needsTokenFirst && !isOn.wrappedValue)
                .accessibilityHint(needsTokenFirst
                    ? "Save a \(app.name) token below first"
                    : "Announces new messages from \(app.programName) aloud")
            if isOn.wrappedValue {
                Picker(announceKey.label(), selection: Binding(
                    get: { announce.wrappedValue.rawValue },
                    set: { if let v = ChatMonitorConfig.BeeperAnnounce(rawValue: $0) { announce.wrappedValue = v } }
                )) {
                    ForEach(SettingsCatalog.chatAnnounceChoices, id: \.value) { mode in
                        Text(mode.label).tag(mode.value)
                    }
                }
                networkSwitches
            }
            if isOn.wrappedValue || needsTokenFirst {
                tokenRows
            }
            if isOn.wrappedValue {
                addressRows
            }
        } header: {
            Text(app.name)
        } footer: {
            if isOn.wrappedValue || needsTokenFirst {
                Text(help)
            }
        }
    }

    /// Where the token comes from, and what is skipped.
    private var help: String {
        switch app {
        case .beeper:
            return "In Beeper Desktop: Settings › Integrations, turn on the Desktop API, then + next to Approved connections. Beeper Desktop must be running; Vitruvian Speaker only talks to it on this Mac. Slack and Google Chat chats in Beeper are skipped while their own switches above are on."
        case .courier:
            return "In Courier: Settings › Integrations › New connection…, then paste the token here. Courier must be running; Vitruvian Speaker only talks to it on this Mac. With Beeper on as well, a message that comes through both is read out once. Courier can't say which Slack workspace is which, so while the Slack switch above is on, Courier's Slack is left to it. To hear another workspace through Courier, switch its Slack on here; messages from the workspace above may then be read twice."
        }
    }

    @ViewBuilder
    private var tokenRows: some View {
        if hasToken && !showReplaceToken.wrappedValue {
            HStack {
                Label("\(app.name) token saved", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                Button("Replace Token…") { showReplaceToken.wrappedValue = true }
                    .controlSize(.small)
                if let readingLine {
                    Text(readingLine).font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            SecureField("Access token", text: tokenDraft)
                .onSubmit {
                    saveToken()
                    showReplaceToken.wrappedValue = false
                }
            HStack {
                Button("Save Token") {
                    saveToken()
                    showReplaceToken.wrappedValue = false
                }
                .controlSize(.small)
                if hasToken {
                    Button("Cancel") { showReplaceToken.wrappedValue = false }
                        .controlSize(.small)
                }
                if needsTokenFirst {
                    Text("Save a token to turn \(app.name) on.").font(.caption).foregroundStyle(.secondary)
                } else if let readingLine {
                    Text(readingLine).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Where the app's API is: empty for its usual address. Saved on
    /// Return; one not on this Mac is refused and says why.
    @ViewBuilder
    private var addressRows: some View {
        TextField(addressKey.label(), text: addressDraft, prompt: Text(app.defaultBaseURL.absoluteString))
            .onSubmit(saveAddress)
            .accessibilityHint("Where \(app.programName) answers on this Mac. Leave empty for the usual address.")
        if let problem = ChatAppClient.addressProblem(addressDraft.wrappedValue, app: app) {
            Label(problem.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    /// A switch for each network, under a "Networks" caption: on reads it,
    /// off mutes it. A network Vitruvian Speaker reads itself is shown off and
    /// greyed. Before the monitor has read the app, the saved mutes and
    /// where the others will show.
    @ViewBuilder
    private var networkSwitches: some View {
        if networks.shows(beeperEnabled: isOn.wrappedValue) {
            Text("Networks").font(.caption).foregroundStyle(.secondary)
            ForEach(networks.rows, id: \.key) { row in
                if let readAnyway, row.state == .skipped || readAnywayKeys.contains(row.key) {
                    Toggle(readAnywayKeys.contains(row.key) ? "\(row.name) · Also read here" : "\(row.name) · Read directly",
                           isOn: readAnyway(row.key))
                        .accessibilityHint("On reads this network through \(app.name) too, although Vitruvian Speaker reads it itself")
                } else if row.state == .skipped {
                    Toggle("\(row.name) · Read directly", isOn: .constant(false))
                        .disabled(true)
                        .accessibilityHint("Read by Vitruvian Speaker's own reader while its switch is on")
                } else {
                    Toggle(row.name, isOn: networkSwitch(row.key))
                        .accessibilityHint("Off mutes this \(app.name) network")
                }
            }
            if !networks.isListed {
                Text(BeeperNetworkList.othersLater(app)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
