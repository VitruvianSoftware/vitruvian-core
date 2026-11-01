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
@MainActor
public final class FocusRouter {
    private let appModel: AppModel
    private let composer: ComposerModel
    private let lookUpChat: (String) async -> Bool
    private let activate: () -> Void

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
