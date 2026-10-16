// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Sends through the engine that is up when the call is made.
public final class EngineMessageSender: MessageSending {
    private let appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    /// The time limit of a file's `message.sendFile`: 30 seconds and one more for each megabyte (a part of one
    /// counts), so a big file on a slow line is not given up on while it is still going out.
    public static func fileTimeout(forBytes bytes: Int64) -> TimeInterval {
        EngineClient.defaultCallTimeout + (Double(max(0, bytes)) / 1_048_576).rounded(.up)
    }

    public func sendText(roomID: String, text: String, replyTo: String?) async throws {
        guard let client = await appModel.client else { throw EngineError.notConnected }
        let _: Sent = try await client.call("message.send", SendParams(roomID: roomID, text: text, replyTo: replyTo))
    }

    public func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?) async throws {
        guard let client = await appModel.client else { throw EngineError.notConnected }
        let _: Sent = try await client.call(
            "message.sendFile", SendFileParams(roomID: roomID, path: url.path, replyTo: replyTo),
            timeout: Self.fileTimeout(forBytes: size))
    }
}
