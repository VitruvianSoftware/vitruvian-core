// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// An MCP client's focus_app (`app.focus`), in the app: Courier comes to the front with its main window, at the
/// chat and message given, with the draft text and file in that chat's composer.
///
/// The draft is only filled in. Nothing here sends: the person reads it, with the file's chip showing its name, and
/// presses Send or doesn't. A chat the app can't find leaves it on the inbox with nothing filled in, and so does a
/// file that can't be attached. While Courier is locked it only comes to the front: the lock screen shows, and no
/// chat opens behind it.
///
/// It also tells the engine whether Courier is locked (app.setLocked), after each connect and each time it locks
/// or unlocks, so that focus_app answers its client "Courier is locked" rather than claim a chat opened.
@MainActor
public final class FocusRouter {
    private let appModel: AppModel
    private let composer: ComposerModel
    private let lookUpChat: (String) async -> Bool
    private let activate: () -> Void
    private var lockObservers: [NSObjectProtocol] = []
    /// The last app.setLocked sent, so each waits for the one before it and the engine hears them in order.
    private var lastReport: Task<Void, Never>?

    /// - Parameters:
    ///   - composer: the main window's chat composer.
    ///   - lookUpChat: whether the app can open the chat (the inbox's row for it, loaded or looked up).
    ///   - activate: bring Courier and its main window to the front.
    public init(appModel: AppModel, composer: ComposerModel, lookUpChat: @escaping (String) async -> Bool,
                activate: @escaping () -> Void) {
        self.appModel = appModel
        self.composer = composer
        self.lookUpChat = lookUpChat
        self.activate = activate
        appModel.onNotice { [weak self] notice in
            guard case let .focus(params) = notice else { return }
            Task { await self?.route(params) }
        }
        appModel.onConnect { [weak self] client in
            self?.reportLock(to: client)
        }
        if let client = appModel.client {
            reportLock(to: client) // already connected: the next connect would be too late
        }
        for name in [SystemLifecycleModel.didLockNotification, SystemLifecycleModel.didUnlockNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let client = self.appModel.client else { return }
                    self.reportLock(to: client)
                }
            }
            lockObservers.append(observer)
        }
    }

    deinit {
        for observer in lockObservers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Tells the engine whether Courier is locked now, after whatever was told it before.
    private func reportLock(to client: EngineClient) {
        let locked = appModel.isLocked
        let previous = lastReport
        lastReport = Task {
            await previous?.value
            let _: Empty? = try? await client.call("app.setLocked", AppLockParams(locked: locked))
        }
    }

    public func route(_ params: FocusParams) async {
        activate()
        guard !appModel.isLocked, let chat = params.chatID, !chat.isEmpty else { return }
        guard await lookUpChat(chat) else { return }
        if params.draftText != nil || params.draftAttachmentPath != nil {
            let file = params.draftAttachmentPath.map { URL(fileURLWithPath: $0) }
            guard composer.placeDraft(text: params.draftText, attachment: file, in: chat) else { return }
        }
        if let message = params.messageID, !message.isEmpty {
            appModel.open(.message(roomID: chat, eventID: message))
        } else {
            appModel.open(.chat(roomID: chat))
        }
    }
}
