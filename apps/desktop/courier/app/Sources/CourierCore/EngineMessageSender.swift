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

    /// message.send's params: the ranges and `hold_ms` only when there are some (a message not held has none).
    public static func sendParams(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?,
                                  holdMillis: Int) -> SendParams {
        SendParams(roomID: roomID, text: rich.text, entities: rich.entities.isEmpty ? nil : rich.entities,
                   replyTo: replyTo, threadRoot: threadRoot, holdMS: holdMillis > 0 ? holdMillis : nil)
    }

    private func client() async throws -> EngineClient {
        guard let client = await appModel.client else { throw EngineError.notConnected }
        return client
    }

    public func sendText(roomID: String, text: String, replyTo: String?) async throws {
        let _: Sent = try await client().call("message.send", SendParams(roomID: roomID, text: text, replyTo: replyTo))
    }

    public func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?) async throws {
        _ = try await sendFile(roomID: roomID, url: url, size: size, replyTo: replyTo, threadRoot: nil, holdMillis: 0)
    }

    public func saveDraft(roomID: String, text: String) async throws {
        let _: Empty = try await client().call("room.setDraft", DraftParams(roomID: roomID, text: text))
    }

    public func send(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, holdMillis: Int)
        async throws -> String {
        let params = Self.sendParams(roomID: roomID, rich: rich, replyTo: replyTo, threadRoot: threadRoot,
                                     holdMillis: holdMillis)
        let sent: Sent = try await client().call("message.send", params)
        return sent.eventID
    }

    public func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?, threadRoot: String?,
                         holdMillis: Int) async throws -> String {
        let params = SendFileParams(roomID: roomID, path: url.path, replyTo: replyTo, threadRoot: threadRoot,
                                    holdMS: holdMillis > 0 ? holdMillis : nil)
        let sent: Sent = try await client().call("message.sendFile", params, timeout: Self.fileTimeout(forBytes: size))
        return sent.eventID
    }

    public func edit(eventID: String, rich: RichText) async throws {
        let params = EditParams(eventID: eventID, text: rich.text, entities: rich.entities.isEmpty ? nil : rich.entities)
        let _: Sent = try await client().call("message.edit", params)
    }

    public func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date,
                         condition: SendLaterCondition) async throws {
        let params = ScheduleParams(roomID: roomID, text: rich.text, entities: rich.entities.isEmpty ? nil : rich.entities,
                                    replyTo: replyTo, threadRoot: threadRoot,
                                    dueAt: Int64((due.timeIntervalSince1970 * 1000).rounded()), condition: condition.wire)
        let _: ScheduledMessage = try await client().call("message.schedule", params)
    }

    public func undo(eventID: String) async throws -> Draft {
        try await client().call("message.undo", EventParams(eventID: eventID))
    }

    public func sendHeld(roomID: String?) async throws {
        let _: Empty = try await client().call("message.sendHeld", RoomOptionalParams(roomID: roomID))
    }

    public func members(roomID: String, query: String) async throws -> [Member] {
        let result: MembersResult = try await client().call("room.members", MembersParams(roomID: roomID, query: query))
        return result.members
    }

    public func archive(roomID: String) async throws {
        let _: RoomsChanged = try await client().call("room.setArchived", ArchiveParams(roomIDs: [roomID], archived: true))
    }

    public func status(of eventID: String, in roomID: String) async throws -> StatusLine? {
        let page: EventsPage = try await client().call("room.events",
                                                       RoomEventsParams(roomID: roomID, around: eventID, limit: 1))
        guard let event = page.events.first(where: { $0.eventID == eventID }) else { return nil }
        return StatusLine.of(status: event.status, reason: event.statusReason)
    }
}
