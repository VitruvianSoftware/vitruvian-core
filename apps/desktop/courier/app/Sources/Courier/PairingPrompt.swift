// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import CourierCore

/// The prompt a client asking to connect raises: an alert on Courier's main window, "“<clientName>” wants to read
/// your chats in Courier.", with Allow, Allow and Send Messages, and Don't Allow. One shows at a time
/// (`IntegrationsModel.pairRequest`), and it goes away by itself when the engine says the request ended.
@MainActor
final class PairingPrompt {
    private let model: IntegrationsModel
    private let showMainWindow: () -> Void
    private var subscription: AnyCancellable?
    private var alert: NSAlert?
    private var shownRequestID: String?

    init(model: IntegrationsModel, showMainWindow: @escaping () -> Void) {
        self.model = model
        self.showMainWindow = showMainWindow
        subscription = model.$pairRequest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                MainActor.assumeIsolated { self?.follow(request) }
            }
    }

    private func follow(_ request: PairRequest?) {
        if let request {
            guard shownRequestID == nil else { return }
            show(request)
        } else {
            dismiss()
        }
    }

    private func show(_ request: PairRequest) {
        shownRequestID = request.requestID
        let alert = NSAlert()
        alert.messageText = IntegrationsModel.pairingQuestion(request)
        alert.informativeText = String(localized: "Allow lets it read your chats. Allow and Send Messages also lets it send messages as you. You can revoke it in Settings ▸ Integrations.")
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Allow and Send Messages"))
        alert.addButton(withTitle: String(localized: "Don’t Allow")).keyEquivalent = "\u{1b}"
        self.alert = alert
        showMainWindow()
        // The window comes forward on the next turn of the run loop.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alert === alert else { return }
                if let window = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
                    alert.beginSheetModal(for: window) { [weak self] response in
                        MainActor.assumeIsolated { self?.answered(response, for: alert) }
                    }
                } else {
                    let response = alert.runModal()
                    self.answered(response, for: alert)
                }
            }
        }
    }

    private func answered(_ response: NSApplication.ModalResponse, for alert: NSAlert) {
        guard self.alert === alert else { return }
        self.alert = nil
        shownRequestID = nil
        let answer: PairingAnswer
        switch response {
        case .alertFirstButtonReturn: answer = .allow
        case .alertSecondButtonReturn: answer = .allowAndSend
        default: answer = .deny
        }
        Task { await model.answerPairing(answer) }
    }

    /// The request ended without an answer from here: take the alert away, answering nothing.
    private func dismiss() {
        guard let alert else { return }
        self.alert = nil
        shownRequestID = nil
        if let sheetParent = alert.window.sheetParent {
            sheetParent.endSheet(alert.window, returnCode: .abort)
        } else if NSApp.modalWindow === alert.window {
            NSApp.abortModal()
        }
        alert.window.orderOut(nil)
    }
}
