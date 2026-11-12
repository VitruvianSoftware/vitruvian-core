// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct AIChatTurn: Equatable, Sendable {
    public enum Role: String, Codable, Equatable, Sendable {
        case system
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct AIChatContext: Equatable, Sendable {
    public typealias Entry = (senderName: String, mine: Bool, text: String)

    public var title: String
    public var messages: [Entry]

    public init(title: String = "", messages: [Entry] = []) {
        self.title = title
        self.messages = messages
    }

    public init(title: String = "", timelineMessages: [TimelineMessage]) {
        self.title = title
        self.messages = timelineMessages.compactMap { Self.entry(from: $0) }
    }

    public init(title: String = "", items: [TimelineItem]) {
        self.title = title
        self.messages = items.compactMap { item -> Entry? in
            guard case let .message(message) = item else { return nil }
            return Self.entry(from: message)
        }
    }

    private static func entry(from message: TimelineMessage) -> Entry? {
        guard message.kind == .text,
              !message.kind.isMedia,
              message.mediaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              message.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              message.sticker == nil,
              message.gif == nil,
              message.galleryItems.isEmpty
        else {
            return nil
        }
        let trimmed = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let name = message.senderName.isEmpty ? message.sender : message.senderName
        return (senderName: name, mine: message.mine, text: trimmed)
    }

    public static func == (lhs: AIChatContext, rhs: AIChatContext) -> Bool {
        guard lhs.title == rhs.title, lhs.messages.count == rhs.messages.count else { return false }
        for (left, right) in zip(lhs.messages, rhs.messages) {
            if left.senderName != right.senderName
                || left.mine != right.mine
                || left.text != right.text {
                return false
            }
        }
        return true
    }
}
