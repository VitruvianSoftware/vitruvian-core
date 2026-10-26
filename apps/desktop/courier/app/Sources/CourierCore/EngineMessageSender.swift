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
                                  holdMillis: Int, disableLinkPreview: Bool? = nil) -> SendParams {
        SendParams(roomID: roomID, text: rich.text, entities: rich.entities.isEmpty ? nil : rich.entities,
                   replyTo: replyTo, threadRoot: threadRoot, holdMS: holdMillis > 0 ? holdMillis : nil,
                   disableLinkPreview: disableLinkPreview)
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

    public func send(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, holdMillis: Int,
                     disableLinkPreview: Bool?)
        async throws -> String {
        let params = Self.sendParams(roomID: roomID, rich: rich, replyTo: replyTo, threadRoot: threadRoot,
                                     holdMillis: holdMillis, disableLinkPreview: disableLinkPreview)
        let sent: Sent = try await client().call("message.send", params)
        return sent.eventID
    }

    public func sendLocation(roomID: String, latitude: Double, longitude: Double, label: String?, replyTo: String?)
        async throws -> String {
        let params = SendLocationParams(
            roomID: roomID,
            latitude: latitude,
            longitude: longitude,
            label: (label?.isEmpty == false) ? label : nil,
            replyTo: replyTo
        )
        let sent: Sent = try await client().call("message.sendLocation", params)
        return sent.eventID
    }

    public func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?, threadRoot: String?,
                         holdMillis: Int) async throws -> String {
        let params = SendFileParams(roomID: roomID, path: url.path, replyTo: replyTo, threadRoot: threadRoot,
                                    holdMS: holdMillis > 0 ? holdMillis : nil)
        let sent: Sent = try await client().call("message.sendFile", params, timeout: Self.fileTimeout(forBytes: size))
        return sent.eventID
    }

    public func sendVoice(roomID: String, url: URL, durationMS: Int64, waveform: [Int], replyTo: String?) async throws
        -> String {
        let size = ComposerModel.readFileInfo(url)?.size ?? 0
        let params = SendVoiceParams(
            roomID: roomID,
            path: url.path,
            durationMS: durationMS,
            waveform: waveform.isEmpty ? nil : waveform,
            replyTo: replyTo
        )
        let sent: Sent = try await client().call("message.sendVoice", params, timeout: Self.fileTimeout(forBytes: size))
        return sent.eventID
    }

    public func listStickers(refreshBridgePacks: Bool = false) async throws -> StickersListResult {
        try await client().call(
            "stickers.list",
            StickersListParams(refreshBridgePacks: refreshBridgePacks ? true : nil)
        )
    }

    public func importSticker(_ params: StickersImportParams) async throws -> StickerItemWire {
        let size = ComposerModel.readFileInfo(URL(fileURLWithPath: params.path))?.size ?? 0
        return try await client().call("stickers.import", params, timeout: Self.fileTimeout(forBytes: size))
    }

    public func sendSticker(_ params: MessageSendStickerParams) async throws -> String {
        let size = params.path.flatMap { ComposerModel.readFileInfo(URL(fileURLWithPath: $0))?.size } ?? 0
        let sent: Sent = try await client().call("message.sendSticker", params, timeout: Self.fileTimeout(forBytes: size))
        return sent.eventID
    }

    public func edit(eventID: String, rich: RichText) async throws {
        let params = EditParams(eventID: eventID, text: rich.text, entities: rich.entities.isEmpty ? nil : rich.entities)
        let _: Sent = try await client().call("message.edit", params)
    }

    public func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date,
                         condition: SendLaterCondition) async throws {
        try await schedule(roomID: roomID, rich: rich, replyTo: replyTo, threadRoot: threadRoot, due: due,
                           condition: condition, disableLinkPreview: nil)
    }

    public func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date,
                         condition: SendLaterCondition, disableLinkPreview: Bool?) async throws {
        let params = ScheduleParams(roomID: roomID, text: rich.text, entities: rich.entities.isEmpty ? nil : rich.entities,
                                    replyTo: replyTo, threadRoot: threadRoot,
                                    dueAt: Int64((due.timeIntervalSince1970 * 1000).rounded()),
                                    condition: condition.wire,
                                    disableLinkPreview: disableLinkPreview)
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

    /// How long a room.setTyping waits for the engine's answer, in seconds. Typing is best effort and stale soon, and
    /// quitting waits for the stops (`ConversationModel.stopTyping`): a stuck engine can't hold either up for long.
    /// The engine answers at once (it queues the event for the bridge).
    public static let typingTimeout: TimeInterval = 5

    public func setTyping(roomID: String, typing: Bool) async throws {
        let _: Empty = try await client().call("room.setTyping", TypingParams(roomID: roomID, typing: typing),
                                               timeout: Self.typingTimeout)
    }

    /// Only the message: the engine finds its chat (EventParams, strict).
    public func setUnreadFrom(eventID: String) async throws {
        let _: Empty = try await client().call("room.setUnreadFrom", EventParams(eventID: eventID))
    }

    public func directChat(roomID: String, userID: String) async throws -> String {
        let result: RoomResult = try await client().call("room.directChat",
                                                         DirectChatParams(roomID: roomID, userID: userID))
        return result.roomID
    }

    /// A thread reply is read from its thread's newest page (the chat's own pages leave thread replies out); any
    /// other message from the page around it. A message the engine no longer has (not found) is nil.
    public func status(of eventID: String, in roomID: String, thread: String?) async throws -> StatusLine? {
        let params = thread.map { RoomEventsParams(roomID: roomID, thread: $0, limit: 50) }
            ?? RoomEventsParams(roomID: roomID, around: eventID, limit: 1)
        let page: EventsPage
        do {
            page = try await client().call("room.events", params)
        } catch EngineError.rpc(.notFound, _, _) where thread == nil {
            return nil // around a message that isn't in the chat: it is gone
        }
        guard let event = page.events.first(where: { $0.eventID == eventID }) else { return nil }
        return StatusLine.of(status: event.status, reason: event.statusReason)
    }
}
