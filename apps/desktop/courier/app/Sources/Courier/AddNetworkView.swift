// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// The sheet for adding a network: the picker, then each step of the sign-in, then how it ended. The sign-in
/// window, for a step that signs in on a web page, is a window of its own (SignInWindow.swift); this sheet says
/// it is open and can cancel it.
struct AddNetworkView: View {
    @ObservedObject var login: LoginFlowModel

    var body: some View {
        content
            .padding(24)
            .frame(width: 460)
            .background(AllowsQuitWhileShown())
    }

    @ViewBuilder
    private var content: some View {
        switch login.screen {
        case .closed:
            EmptyView()
        case .picker:
            picker
        case let .googleWarning(network, _):
            framed(title: String(localized: "Link \(login.displayName(network))")) {
                Label(String(localized: "Google Messages allows one web session at a time. Linking it here signs out any other place it’s open on the web, including other messaging apps."),
                      systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
            } buttons: {
                cancelButton
                Button(String(localized: "Continue"), action: login.continueAfterWarning)
                    .keyboardShortcut(.defaultAction)
            }
        case let .working(network):
            framed(title: String(localized: "Link \(login.displayName(network))")) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Waiting for \(login.displayName(network))…"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } buttons: {
                cancelButton
            }
        case let .display(network, step):
            framed(title: String(localized: "Link \(login.displayName(network))")) {
                LoginDisplayStepView(step: step)
            } buttons: {
                cancelButton
            }
        case let .input(network, step):
            framed(title: String(localized: "Link \(login.displayName(network))")) {
                LoginInputStepView(login: login, step: step)
            } buttons: {
                cancelButton
                Button(String(localized: "Continue"), action: login.submitInput)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!login.canSubmitInput)
            }
        case let .signIn(network, _):
            framed(title: String(localized: "Link \(login.displayName(network))")) {
                Text(String(localized: "Sign in to \(login.displayName(network)) in the window that opened. Courier picks up the sign-in when you’re done."))
                    .fixedSize(horizontal: false, vertical: true)
            } buttons: {
                cancelButton
            }
        case let .linked(network, remoteName):
            framed(title: String(localized: "Link \(login.displayName(network))")) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(remoteName.isEmpty ? String(localized: "Linked") : String(localized: "Linked as \(remoteName)"),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    // Reconnect signed in a different account than the one asked for (Ruling 11): both are kept.
                    if let note = login.linkedNote {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } buttons: {
                doneButton
            }
        case let .message(network, text):
            framed(title: network.map { login.displayName($0) } ?? String(localized: "Add a network")) {
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            } buttons: {
                doneButton
            }
        case .telegramSetup:
            TelegramSetupView(login: login)
        }
    }

    private var picker: some View {
        framed(title: String(localized: "Add a network")) {
            VStack(spacing: 0) {
                ForEach(login.choices) { choice in
                    NetworkChoiceRow(choice: choice, login: login)
                    if choice.id != login.choices.last?.id { Divider() }
                }
            }
        } buttons: {
            cancelButton
        }
    }

    private var cancelButton: some View {
        Button(String(localized: "Cancel"), action: login.close)
            .keyboardShortcut(.cancelAction)
    }

    private var doneButton: some View {
        Button(String(localized: "Done"), action: login.close)
            .keyboardShortcut(.defaultAction)
    }

    private func framed<Body: View, Buttons: View>(title: String, @ViewBuilder _ body: () -> Body,
                                                    @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
            body()
            HStack {
                Spacer()
                buttons()
            }
        }
    }
}

/// One network in the picker: starting (it can't be picked yet), linked (who as, and Add Another Account…), or its
/// ways to sign in, the app's choice first.
private struct NetworkChoiceRow: View {
    let choice: NetworkChoice
    @ObservedObject var login: LoginFlowModel

    var body: some View {
        HStack(spacing: 10) {
            NetworkBadge(network: choice.network, name: choice.displayName, size: 20)
                .opacity(choice.isStarting ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(choice.displayName)
                    .foregroundStyle(choice.isStarting ? .secondary : .primary)
                // Who it is linked as, under the name, where a phone number or two has room.
                if choice.isLinked, !choice.isStarting {
                    Text(choice.linkedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(choice.linkedAs.joined(separator: ", "))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if choice.isStarting {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text(NetworkChoice.startingLabel)
                }
                .foregroundStyle(.secondary)
                .help(String(localized: "\(choice.displayName) is still starting. Try again in a moment."))
            } else if choice.isLinked {
                Button(NetworkChoice.addAnotherTitle) {
                    login.begin(network: choice.network, another: true)
                }
                .fixedSize()
            } else if let first = choice.flows.first {
                if choice.flows.count > 1 {
                    Menu {
                        ForEach(choice.flows.dropFirst(), id: \.self) { flow in
                            Button(LoginFlowModel.flowName(flow, network: choice.network)) {
                                login.begin(network: choice.network, flow: flow)
                            }
                        }
                    } label: {
                        Text(String(localized: "Other ways"))
                    }
                    .fixedSize()
                }
                Button(String(localized: "Link")) {
                    login.begin(network: choice.network, flow: first)
                }
                .help(LoginFlowModel.flowName(first, network: choice.network))
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}

/// A sheet's window stops the app from quitting while it is up: AppKit's `preventsApplicationTerminationWhenModal`
/// is on for SwiftUI sheets, so Quit, ⌘Q and the menu-bar icon's Quit did nothing while this sheet was open. This
/// one has only a Cancel or Done to lose, and a sign-in in progress ends when the engine stops, so Quit may go
/// ahead. Set on the window itself, which works on every macOS Courier runs on (SwiftUI's own
/// `presentationPreventsAppTermination` needs 15.4).
private struct AllowsQuitWhileShown: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.preventsApplicationTerminationWhenModal = false
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {}
}
