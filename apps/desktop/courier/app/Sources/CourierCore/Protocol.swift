// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// The app's side of apps/desktop/courier/protocol/protocol.json. That file is the one definition: every type
// here is named exactly as an entry in its "types", with exactly its fields (CodingKeys hold the wire names), and
// ProtocolConformanceTests holds the two together and round-trips every example through these types.
//
// Field kinds, as protocol.json's type_grammar has them:
//   T       a plain property
//   T?      an optional the encoder leaves out when nil (Swift's default)
//   T|null  an optional whose key is always written, as null when nil (a custom encode(to:))
//   values  an open enum (a RawRepresentable string): the known values are constants, and a value this app does
//           not know still decodes, so a newer engine's state never breaks the inbox.

/// The protocol this app speaks, and the framing limit both sides keep.
public enum CourierProtocol {
    public static let version = 3
    /// The longest line either side may send, not counting the newline.
    public static let maxFrameBytes = 4_194_304
}

/// A type of protocol.json's "types": its name there and the wire names of its fields.
public protocol ProtocolType: Codable, Sendable {
    static var protocolName: String { get }
    static var fieldNames: [String] { get }
}

extension ProtocolType {
    /// Decodes one JSON value as this type and encodes it again. The conformance test compares the two.
    public static func roundTrip(_ json: Data) throws -> Data {
        let value = try JSONDecoder().decode(Self.self, from: json)
        return try JSONEncoder().encode(value)
    }
}

/// An open set of strings: the protocol's "values". Decodes any string; the known ones are constants.
public protocol OpenValues: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {
    init(rawValue: String)
    /// Every value protocol.json lists for this field, in its order.
    static var known: [Self] { get }
}

// MARK: - JSON

/// Any JSON value: an event's Matrix content, whose keys are not part of the protocol.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// The string, when this is one.
    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        if case let .object(value) = self { return value[key] }
        return nil
    }
}

// MARK: - Types

/// No params, or a result with nothing in it.
public struct Empty: ProtocolType, Equatable {
    public static let protocolName = "Empty"
    public static let fieldNames: [String] = []
    public init() {}
}

public struct HelloParams: ProtocolType, Equatable {
    public static let protocolName = "HelloParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var `protocol`: Int
    public var client: String

    public init(protocol: Int = CourierProtocol.version, client: String) {
        self.protocol = `protocol`
        self.client = client
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case `protocol`
        case client
    }
}

public struct HelloResult: ProtocolType, Equatable {
    public static let protocolName = "HelloResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var `protocol`: Int
    public var engine: String
    public var networks: [String]

    public init(protocol: Int, engine: String, networks: [String]) {
        self.protocol = `protocol`
        self.engine = engine
        self.networks = networks
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case `protocol`
        case engine
        case networks
    }
}

/// Account.state: the bridge's state_event, or NOT_STARTED / UNCONFIGURED.
public struct AccountState: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let notStarted = Self(rawValue: "NOT_STARTED")
    public static let unconfigured = Self(rawValue: "UNCONFIGURED")
    public static let starting = Self(rawValue: "STARTING")
    public static let running = Self(rawValue: "RUNNING")
    public static let connecting = Self(rawValue: "CONNECTING")
    public static let backfilling = Self(rawValue: "BACKFILLING")
    public static let connected = Self(rawValue: "CONNECTED")
    public static let transientDisconnect = Self(rawValue: "TRANSIENT_DISCONNECT")
    public static let badCredentials = Self(rawValue: "BAD_CREDENTIALS")
    public static let unknownError = Self(rawValue: "UNKNOWN_ERROR")
    public static let loggedOut = Self(rawValue: "LOGGED_OUT")
    public static let bridgeUnreachable = Self(rawValue: "BRIDGE_UNREACHABLE")
    public static let known: [Self] = [
        .notStarted, .unconfigured, .starting, .running, .connecting, .backfilling, .connected,
        .transientDisconnect, .badCredentials, .unknownError, .loggedOut, .bridgeUnreachable,
    ]
}

/// One network the engine knows, linked or not.
public struct Account: ProtocolType, Equatable {
    public static let protocolName = "Account"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String
    public var displayName: String
    public var flows: [String]
    public var state: AccountState
    public var error: String
    public var remoteName: String
    public var notStarted: String
    /// The chat changes Courier also sends to this network. Everything else stays on this Mac.
    public var syncs: [AccountSync]

    public init(network: String, displayName: String, flows: [String], state: AccountState, error: String = "",
                remoteName: String = "", notStarted: String = "", syncs: [AccountSync] = []) {
        self.network = network
        self.displayName = displayName
        self.flows = flows
        self.state = state
        self.error = error
        self.remoteName = remoteName
        self.notStarted = notStarted
        self.syncs = syncs
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case displayName = "display_name"
        case flows
        case state
        case error
        case remoteName = "remote_name"
        case notStarted = "not_started"
        case syncs
    }
}

/// Account.syncs: a chat change Courier also sends to the network, so it shows on the phone too.
public struct AccountSync: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let pin = Self(rawValue: "pin")
    public static let mute = Self(rawValue: "mute")
    public static let acceptRequest = Self(rawValue: "accept_request")
    public static let known: [Self] = [.pin, .mute, .acceptRequest]
}

public struct AccountsResult: ProtocolType, Equatable {
    public static let protocolName = "AccountsResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var accounts: [Account]

    public init(accounts: [Account]) { self.accounts = accounts }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case accounts
    }
}

/// InboxRow.preview_kind. "" when there is nothing readable.
public struct PreviewKind: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let text = Self(rawValue: "text")
    public static let image = Self(rawValue: "image")
    public static let video = Self(rawValue: "video")
    public static let audio = Self(rawValue: "audio")
    public static let file = Self(rawValue: "file")
    public static let sticker = Self(rawValue: "sticker")
    public static let poll = Self(rawValue: "poll")
    public static let none = Self(rawValue: "")
    public static let known: [Self] = [.text, .image, .video, .audio, .file, .sticker, .poll, .none]
}

/// One chat in the inbox.
public struct InboxRow: ProtocolType, Equatable {
    public static let protocolName = "InboxRow"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var network: String
    public var name: String
    public var avatarPath: String
    public var isDirect: Bool
    public var lastTS: Int64
    public var preview: String
    public var previewKind: PreviewKind
    public var previewMine: Bool
    public var unread: Int
    /// I muted this chat itself. `mutedBy` says what else mutes it.
    public var muted: Bool
    /// Pinned chats come first in every sort, in the order they were pinned.
    public var pinned: Bool
    public var archived: Bool
    public var lowPriority: Bool
    public var hidden: Bool
    /// Marked unread by me (or by a reminder that fired), whatever `unread` says. It stays on this Mac.
    public var markedUnread: Bool
    /// A message request: someone new writing first.
    public var request: Bool
    /// The unsent text of the chat's composer. "" when there is none.
    public var draft: String
    /// The label_id of each label on the chat, smallest first.
    public var labels: [Int64]
    public var mutedBy: MutedBy
    public var mutedByName: String
    /// Reminder|null: always on the wire, null when the chat has none.
    public var reminder: Reminder?
    public var typing: [String]
    public var unreadMentions: Int
    public var previewMediaPath: String

    public init(roomID: String, network: String, name: String, avatarPath: String, isDirect: Bool, lastTS: Int64,
                preview: String, previewKind: PreviewKind, previewMine: Bool, unread: Int, muted: Bool,
                pinned: Bool = false, archived: Bool = false, lowPriority: Bool = false, hidden: Bool = false,
                markedUnread: Bool = false, request: Bool = false, draft: String = "", labels: [Int64] = [],
                mutedBy: MutedBy = .none, mutedByName: String = "", reminder: Reminder? = nil,
                typing: [String] = [], unreadMentions: Int = 0, previewMediaPath: String = "") {
        self.roomID = roomID
        self.network = network
        self.name = name
        self.avatarPath = avatarPath
        self.isDirect = isDirect
        self.lastTS = lastTS
        self.preview = preview
        self.previewKind = previewKind
        self.previewMine = previewMine
        self.unread = unread
        self.muted = muted
        self.pinned = pinned
        self.archived = archived
        self.lowPriority = lowPriority
        self.hidden = hidden
        self.markedUnread = markedUnread
        self.request = request
        self.draft = draft
        self.labels = labels
        self.mutedBy = mutedBy
        self.mutedByName = mutedByName
        self.reminder = reminder
        self.typing = typing
        self.unreadMentions = unreadMentions
        self.previewMediaPath = previewMediaPath
    }

    /// Unread messages, or marked unread: what toggle read and the Unread filter go by.
    public var isUnread: Bool { unread > 0 || markedUnread }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case network
        case name
        case avatarPath = "avatar_path"
        case isDirect = "is_direct"
        case lastTS = "last_ts"
        case preview
        case previewKind = "preview_kind"
        case previewMine = "preview_mine"
        case unread
        case muted
        case pinned
        case archived
        case lowPriority = "low_priority"
        case hidden
        case markedUnread = "marked_unread"
        case request
        case draft
        case labels
        case mutedBy = "muted_by"
        case mutedByName = "muted_by_name"
        case reminder
        case typing
        case unreadMentions = "unread_mentions"
        case previewMediaPath = "preview_media_path"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomID = try container.decode(String.self, forKey: .roomID)
        network = try container.decode(String.self, forKey: .network)
        name = try container.decode(String.self, forKey: .name)
        avatarPath = try container.decode(String.self, forKey: .avatarPath)
        isDirect = try container.decode(Bool.self, forKey: .isDirect)
        lastTS = try container.decode(Int64.self, forKey: .lastTS)
        preview = try container.decode(String.self, forKey: .preview)
        previewKind = try container.decode(PreviewKind.self, forKey: .previewKind)
        previewMine = try container.decode(Bool.self, forKey: .previewMine)
        unread = try container.decode(Int.self, forKey: .unread)
        muted = try container.decode(Bool.self, forKey: .muted)
        pinned = try container.decode(Bool.self, forKey: .pinned)
        archived = try container.decode(Bool.self, forKey: .archived)
        lowPriority = try container.decode(Bool.self, forKey: .lowPriority)
        hidden = try container.decode(Bool.self, forKey: .hidden)
        markedUnread = try container.decode(Bool.self, forKey: .markedUnread)
        request = try container.decode(Bool.self, forKey: .request)
        draft = try container.decode(String.self, forKey: .draft)
        labels = try container.decode([Int64].self, forKey: .labels)
        mutedBy = try container.decode(MutedBy.self, forKey: .mutedBy)
        mutedByName = try container.decode(String.self, forKey: .mutedByName)
        reminder = try container.decode(Reminder?.self, forKey: .reminder) // the key must be there
        typing = try container.decode([String].self, forKey: .typing)
        unreadMentions = try container.decode(Int.self, forKey: .unreadMentions)
        previewMediaPath = try container.decode(String.self, forKey: .previewMediaPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roomID, forKey: .roomID)
        try container.encode(network, forKey: .network)
        try container.encode(name, forKey: .name)
        try container.encode(avatarPath, forKey: .avatarPath)
        try container.encode(isDirect, forKey: .isDirect)
        try container.encode(lastTS, forKey: .lastTS)
        try container.encode(preview, forKey: .preview)
        try container.encode(previewKind, forKey: .previewKind)
        try container.encode(previewMine, forKey: .previewMine)
        try container.encode(unread, forKey: .unread)
        try container.encode(muted, forKey: .muted)
        try container.encode(pinned, forKey: .pinned)
        try container.encode(archived, forKey: .archived)
        try container.encode(lowPriority, forKey: .lowPriority)
        try container.encode(hidden, forKey: .hidden)
        try container.encode(markedUnread, forKey: .markedUnread)
        try container.encode(request, forKey: .request)
        try container.encode(draft, forKey: .draft)
        try container.encode(labels, forKey: .labels)
        try container.encode(mutedBy, forKey: .mutedBy)
        try container.encode(mutedByName, forKey: .mutedByName)
        try container.encode(reminder, forKey: .reminder) // null, not left out
        try container.encode(typing, forKey: .typing)
        try container.encode(unreadMentions, forKey: .unreadMentions)
        try container.encode(previewMediaPath, forKey: .previewMediaPath)
    }
}

/// InboxRow.muted_by: what else mutes the chat. An account mute wins.
public struct MutedBy: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let none = Self(rawValue: "")
    public static let account = Self(rawValue: "account")
    public static let label = Self(rawValue: "label")
    public static let known: [Self] = [.none, .account, .label]
}

/// Reminder.condition and ReminderParams.condition.
public struct ReminderCondition: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Only if I haven't sent a message in the chat since setting it.
    public static let ifNoReply = Self(rawValue: "if_no_reply")
    public static let always = Self(rawValue: "always")
    public static let known: [Self] = [.ifNoReply, .always]
}

/// Brings a chat back to my attention at `dueAt`.
public struct Reminder: ProtocolType, Equatable, Hashable {
    public static let protocolName = "Reminder"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// Unix milliseconds.
    public var dueAt: Int64
    public var condition: ReminderCondition
    public var fired: Bool

    public init(dueAt: Int64, condition: ReminderCondition, fired: Bool = false) {
        self.dueAt = dueAt
        self.condition = condition
        self.fired = fired
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case dueAt = "due_at"
        case condition
        case fired
    }
}

/// One page of chats: a query (space, filters, sort) a page at a time, or the chats `roomIDs` names.
public struct InboxListParams: ProtocolType, Equatable {
    public static let protocolName = "InboxListParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var space: String?
    /// Left out (or []) is All. There is no all filter.
    public var filters: [InboxFilter]?
    public var sort: InboxSort?
    public var cursor: String?
    public var limit: Int?
    public var roomIDs: [String]?

    public init(space: String? = nil, filters: [InboxFilter]? = nil, sort: InboxSort? = nil, cursor: String? = nil,
                limit: Int? = nil, roomIDs: [String]? = nil) {
        self.space = space
        self.filters = filters
        self.sort = sort
        self.cursor = cursor
        self.limit = limit
        self.roomIDs = roomIDs
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case space
        case filters
        case sort
        case cursor
        case limit
        case roomIDs = "room_ids"
    }
}

public struct InboxResult: ProtocolType, Equatable {
    public static let protocolName = "InboxResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// In the query's order.
    public var rooms: [InboxRow]
    /// string|null: the cursor of the next page; null on the last page. Only null ends paging: a page may hold
    /// fewer chats than asked for and still have one.
    public var nextCursor: String?

    public init(rooms: [InboxRow], nextCursor: String? = nil) {
        self.rooms = rooms
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case rooms
        case nextCursor = "next_cursor"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rooms = try container.decode([InboxRow].self, forKey: .rooms)
        nextCursor = try container.decode(String?.self, forKey: .nextCursor) // the key must be there
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rooms, forKey: .rooms)
        try container.encode(nextCursor, forKey: .nextCursor) // null, not left out
    }
}

/// Space.kind.
public struct SpaceKind: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let builtin = Self(rawValue: "builtin")
    public static let account = Self(rawValue: "account")
    public static let label = Self(rawValue: "label")
    public static let known: [Self] = [.builtin, .account, .label]
}

/// Space.show_in_inbox and SpaceUpdateParams.show_in_inbox: which of an account's or a label's chats also show
/// in the inbox space. "" for a built-in space (never sent).
public struct ShowInInbox: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let all = Self(rawValue: "all")
    public static let dms = Self(rawValue: "dms")
    public static let none = Self(rawValue: "none")
    public static let notApplicable = Self(rawValue: "")
    public static let known: [Self] = [.all, .dms, .none, .notApplicable]
    /// The values spaces.update takes.
    public static let settable: [Self] = [.all, .dms, .none]
}

/// One entry of the spaces bar.
public struct Space: ProtocolType, Equatable, Identifiable {
    public static let protocolName = "Space"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var spaceID: String
    public var kind: SpaceKind
    public var title: String
    public var network: String
    public var labelID: Int64
    public var color: Int
    public var icon: String
    public var hidden: Bool
    public var muted: Bool
    public var showInInbox: ShowInInbox
    public var chats: Int
    public var unreadChats: Int
    /// For the inbox: its unread chats that nothing mutes, the Dock badge. 0 for every other space.
    public var attentionChats: Int

    public var id: String { spaceID }

    public init(spaceID: String, kind: SpaceKind, title: String = "", network: String = "", labelID: Int64 = 0,
                color: Int = 0, icon: String = "", hidden: Bool = false, muted: Bool = false,
                showInInbox: ShowInInbox = .notApplicable, chats: Int = 0, unreadChats: Int = 0,
                attentionChats: Int = 0) {
        self.spaceID = spaceID
        self.kind = kind
        self.title = title
        self.network = network
        self.labelID = labelID
        self.color = color
        self.icon = icon
        self.hidden = hidden
        self.muted = muted
        self.showInInbox = showInInbox
        self.chats = chats
        self.unreadChats = unreadChats
        self.attentionChats = attentionChats
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case spaceID = "space_id"
        case kind
        case title
        case network
        case labelID = "label_id"
        case color
        case icon
        case hidden
        case muted
        case showInInbox = "show_in_inbox"
        case chats
        case unreadChats = "unread_chats"
        case attentionChats = "attention_chats"
    }
}

public struct SpacesResult: ProtocolType, Equatable {
    public static let protocolName = "SpacesResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var spaces: [Space]

    public init(spaces: [Space]) { self.spaces = spaces }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case spaces
    }
}

public struct SpaceLayoutParams: ProtocolType, Equatable {
    public static let protocolName = "SpaceLayoutParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var order: [String]
    public var hidden: [String]

    public init(order: [String], hidden: [String]) {
        self.order = order
        self.hidden = hidden
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case order
        case hidden
    }
}

public struct SpaceUpdateParams: ProtocolType, Equatable {
    public static let protocolName = "SpaceUpdateParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var spaceID: String
    public var muted: Bool?
    public var showInInbox: ShowInInbox?

    public init(spaceID: String, muted: Bool? = nil, showInInbox: ShowInInbox? = nil) {
        self.spaceID = spaceID
        self.muted = muted
        self.showInInbox = showInInbox
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case spaceID = "space_id"
        case muted
        case showInInbox = "show_in_inbox"
    }
}

public struct LabelParams: ProtocolType, Equatable {
    public static let protocolName = "LabelParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var title: String
    public var color: Int
    public var icon: String

    public init(title: String, color: Int, icon: String) {
        self.title = title
        self.color = color
        self.icon = icon
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case title
        case color
        case icon
    }
}

public struct LabelResult: ProtocolType, Equatable {
    public static let protocolName = "LabelResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var labelID: Int64

    public init(labelID: Int64) { self.labelID = labelID }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case labelID = "label_id"
    }
}

/// A field left out stays as it is.
public struct LabelUpdateParams: ProtocolType, Equatable {
    public static let protocolName = "LabelUpdateParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var labelID: Int64
    public var title: String?
    public var color: Int?
    public var icon: String?

    public init(labelID: Int64, title: String? = nil, color: Int? = nil, icon: String? = nil) {
        self.labelID = labelID
        self.title = title
        self.color = color
        self.icon = icon
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case labelID = "label_id"
        case title
        case color
        case icon
    }
}

public struct LabelIDParams: ProtocolType, Equatable {
    public static let protocolName = "LabelIDParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var labelID: Int64

    public init(labelID: Int64) { self.labelID = labelID }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case labelID = "label_id"
    }
}

public struct SetPinnedParams: ProtocolType, Equatable {
    public static let protocolName = "SetPinnedParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var pinned: Bool

    public init(roomID: String, pinned: Bool) {
        self.roomID = roomID
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case pinned
    }
}

public struct ArchiveParams: ProtocolType, Equatable {
    public static let protocolName = "ArchiveParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// 1 to 500 chats.
    public var roomIDs: [String]
    public var archived: Bool
    public var markRead: Bool?

    public init(roomIDs: [String], archived: Bool, markRead: Bool? = nil) {
        self.roomIDs = roomIDs
        self.archived = archived
        self.markRead = markRead
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomIDs = "room_ids"
        case archived
        case markRead = "mark_read"
    }
}

/// The chats a call changed, in the order asked for; [] when none did. Undo reverses exactly these.
public struct RoomsChanged: ProtocolType, Equatable {
    public static let protocolName = "RoomsChanged"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomIDs: [String]

    public init(roomIDs: [String]) { self.roomIDs = roomIDs }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomIDs = "room_ids"
    }
}

public struct RoomsFlagParams: ProtocolType, Equatable {
    public static let protocolName = "RoomsFlagParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// 1 to 500 chats.
    public var roomIDs: [String]
    public var on: Bool

    public init(roomIDs: [String], on: Bool) {
        self.roomIDs = roomIDs
        self.on = on
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomIDs = "room_ids"
        case on
    }
}

public struct SetLabelParams: ProtocolType, Equatable {
    public static let protocolName = "SetLabelParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomIDs: [String]
    public var labelID: Int64
    public var on: Bool

    public init(roomIDs: [String], labelID: Int64, on: Bool) {
        self.roomIDs = roomIDs
        self.labelID = labelID
        self.on = on
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomIDs = "room_ids"
        case labelID = "label_id"
        case on
    }
}

public struct DraftParams: ProtocolType, Equatable {
    public static let protocolName = "DraftParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    /// "" clears the draft.
    public var text: String

    public init(roomID: String, text: String) {
        self.roomID = roomID
        self.text = text
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case text
    }
}

public struct ReminderParams: ProtocolType, Equatable {
    public static let protocolName = "ReminderParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomIDs: [String]
    /// Unix milliseconds: after now, at most 5 years ahead.
    public var dueAt: Int64
    public var condition: ReminderCondition
    /// Also archive the chats (all but pinned ones) until the reminder brings them back.
    public var archive: Bool?

    public init(roomIDs: [String], dueAt: Int64, condition: ReminderCondition, archive: Bool? = nil) {
        self.roomIDs = roomIDs
        self.dueAt = dueAt
        self.condition = condition
        self.archive = archive
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomIDs = "room_ids"
        case dueAt = "due_at"
        case condition
        case archive
    }
}

public struct RoomsParams: ProtocolType, Equatable {
    public static let protocolName = "RoomsParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomIDs: [String]

    public init(roomIDs: [String]) { self.roomIDs = roomIDs }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomIDs = "room_ids"
    }
}

public struct ArchiveMatchingParams: ProtocolType, Equatable {
    public static let protocolName = "ArchiveMatchingParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// inbox (when left out), an account:<network> or a label:<label_id>.
    public var space: String?
    public var readOnly: Bool
    public var olderThanMS: Int64
    public var dryRun: Bool

    public init(space: String? = nil, readOnly: Bool, olderThanMS: Int64 = 0, dryRun: Bool = false) {
        self.space = space
        self.readOnly = readOnly
        self.olderThanMS = olderThanMS
        self.dryRun = dryRun
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case space
        case readOnly = "read_only"
        case olderThanMS = "older_than_ms"
        case dryRun = "dry_run"
    }
}

public struct SpaceParams: ProtocolType, Equatable {
    public static let protocolName = "SpaceParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// Left out means inbox.
    public var space: String?

    public init(space: String? = nil) { self.space = space }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case space
    }
}

/// AutoArchiveRule.trigger.
public struct AutoArchiveTrigger: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let afterReply = Self(rawValue: "after_reply")
    public static let afterRead = Self(rawValue: "after_read")
    public static let olderThan = Self(rawValue: "older_than")
    public static let known: [Self] = [.afterReply, .afterRead, .olderThan]
}

/// AutoArchiveRule.chat_type.
public struct AutoArchiveChatType: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let all = Self(rawValue: "all")
    public static let read = Self(rawValue: "read")
    public static let known: [Self] = [.all, .read]
}

/// A rule that archives chats by itself.
public struct AutoArchiveRule: ProtocolType, Equatable, Identifiable {
    public static let protocolName = "AutoArchiveRule"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// 0 in autoArchive.set makes a new rule.
    public var ruleID: Int64
    public var scope: String
    public var trigger: AutoArchiveTrigger
    public var chatType: AutoArchiveChatType
    public var durationMS: Int64
    public var enabled: Bool

    public var id: Int64 { ruleID }

    public init(ruleID: Int64 = 0, scope: String, trigger: AutoArchiveTrigger, chatType: AutoArchiveChatType,
                durationMS: Int64, enabled: Bool) {
        self.ruleID = ruleID
        self.scope = scope
        self.trigger = trigger
        self.chatType = chatType
        self.durationMS = durationMS
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case ruleID = "rule_id"
        case scope
        case trigger
        case chatType = "chat_type"
        case durationMS = "duration_ms"
        case enabled
    }
}

public struct RulesResult: ProtocolType, Equatable {
    public static let protocolName = "RulesResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var rules: [AutoArchiveRule]

    public init(rules: [AutoArchiveRule]) { self.rules = rules }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case rules
    }
}

public struct RuleIDParams: ProtocolType, Equatable {
    public static let protocolName = "RuleIDParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var ruleID: Int64

    public init(ruleID: Int64) { self.ruleID = ruleID }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case ruleID = "rule_id"
    }
}

/// A place in a chat's history: the oldest event of the page you have.
public struct Cursor: ProtocolType, Equatable, Hashable {
    public static let protocolName = "Cursor"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var ts: Int64
    public var seq: Int64

    public init(ts: Int64, seq: Int64) {
        self.ts = ts
        self.seq = seq
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case ts
        case seq
    }
}

public struct RoomParams: ProtocolType, Equatable {
    public static let protocolName = "RoomParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String

    public init(roomID: String) { self.roomID = roomID }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
    }
}

/// One page of a chat's history. Give at most one of `before`, `after` and `around`; none is the newest page.
public struct RoomEventsParams: ProtocolType, Equatable {
    public static let protocolName = "RoomEventsParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    /// A page's `before`, for the page older than it.
    public var before: Cursor?
    /// A page's `after`, for the page newer than it.
    public var after: Cursor?
    /// An event_id in this chat: the page with that event in the middle (to open the chat at a search result).
    public var around: String?
    public var limit: Int?

    public init(roomID: String, before: Cursor? = nil, after: Cursor? = nil, around: String? = nil,
                limit: Int? = nil) {
        self.roomID = roomID
        self.before = before
        self.after = after
        self.around = around
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case before
        case after
        case around
        case limit
    }
}

/// Event.status.
public struct EventStatus: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let pending = Self(rawValue: "pending")
    public static let sent = Self(rawValue: "sent")
    public static let failed = Self(rawValue: "failed")
    public static let known: [Self] = [.pending, .sent, .failed]
}

/// One event in a chat: a message, a reaction, an edit or a redaction.
public struct Event: ProtocolType, Equatable {
    public static let protocolName = "Event"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var eventID: String
    public var roomID: String
    public var sender: String
    public var senderName: String
    public var senderAvatarPath: String
    public var mine: Bool
    public var type: String
    public var content: JSONValue
    public var ts: Int64
    public var seq: Int64
    public var status: EventStatus
    public var statusReason: String
    public var mediaPath: String

    public init(eventID: String, roomID: String, sender: String, senderName: String, senderAvatarPath: String = "",
                mine: Bool, type: String, content: JSONValue, ts: Int64, seq: Int64, status: EventStatus,
                statusReason: String = "", mediaPath: String = "") {
        self.eventID = eventID
        self.roomID = roomID
        self.sender = sender
        self.senderName = senderName
        self.senderAvatarPath = senderAvatarPath
        self.mine = mine
        self.type = type
        self.content = content
        self.ts = ts
        self.seq = seq
        self.status = status
        self.statusReason = statusReason
        self.mediaPath = mediaPath
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
        case roomID = "room_id"
        case sender
        case senderName = "sender_name"
        case senderAvatarPath = "sender_avatar_path"
        case mine
        case type
        case content
        case ts
        case seq
        case status
        case statusReason = "status_reason"
        case mediaPath = "media_path"
    }
}

public struct EventsPage: ProtocolType, Equatable {
    public static let protocolName = "EventsPage"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var events: [Event]
    /// Cursor|null: always on the wire, null when there is no older event.
    public var before: Cursor?
    /// Cursor|null: the newest event of this page, for the next newer page; null when the page has the chat's
    /// newest event.
    public var after: Cursor?

    public init(events: [Event], before: Cursor?, after: Cursor? = nil) {
        self.events = events
        self.before = before
        self.after = after
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case events
        case before
        case after
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decode([Event].self, forKey: .events)
        before = try container.decode(Cursor?.self, forKey: .before) // the key must be there
        after = try container.decode(Cursor?.self, forKey: .after) // the key must be there
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        try container.encode(before, forKey: .before) // null, not left out
        try container.encode(after, forKey: .after) // null, not left out
    }
}

// MARK: - Search

/// SearchParams.sections: what one search.query searches.
public struct SearchSectionName: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let chats = Self(rawValue: "chats")
    public static let inGroups = Self(rawValue: "in_groups")
    public static let media = Self(rawValue: "media")
    public static let messages = Self(rawValue: "messages")
    public static let known: [Self] = [.chats, .inGroups, .media, .messages]
}

/// One search over every chat on this Mac. Answers don't change by themselves: a changed notification doesn't
/// re-run a search.
public struct SearchParams: ProtocolType, Equatable {
    public static let protocolName = "SearchParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// What was typed: at most `maxTextScalars` Unicode scalars (not Characters); longer is -32602.
    public var text: String
    /// Left out (or []) is all four.
    public var sections: [SearchSectionName]?
    public var filters: SearchFilters?
    /// A page of media or messages' next_cursor. It needs sections of exactly that one, and the same text and
    /// filters as the query that handed it out.
    public var cursor: String?
    /// Each section's most results. Left out: chats and in_groups 5, media 12, messages 20.
    public var limit: Int?
    /// The chat open now, which last_archived leaves out.
    public var openRoomID: String?

    /// The longest text the engine takes, counted in Unicode scalars as it counts them.
    public static let maxTextScalars = 500

    public init(text: String, sections: [SearchSectionName]? = nil, filters: SearchFilters? = nil,
                cursor: String? = nil, limit: Int? = nil, openRoomID: String? = nil) {
        self.text = text
        self.sections = sections
        self.filters = filters
        self.cursor = cursor
        self.limit = limit
        self.openRoomID = openRoomID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case sections
        case filters
        case cursor
        case limit
        case openRoomID = "open_room_id"
    }
}

/// Every filter narrows, and filters together are and'ed. room_ids leaves out chats and in_groups; sender, kinds,
/// since, until and partial narrow media and messages only; networks and chat_type narrow every section.
public struct SearchFilters: ProtocolType, Equatable {
    public static let protocolName = "SearchFilters"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// 1 to 100 chats to search in.
    public var roomIDs: [String]?
    /// Network names, as hello lists them.
    public var networks: [String]?
    /// One of `senderValues`: sent by me, or received.
    public var sender: String?
    /// One of `chatTypeValues`.
    public var chatType: String?
    /// Any of `SearchKind`'s raw values. A link is a text message holding an http(s) URL.
    public var kinds: [String]?
    /// Unix milliseconds: sent at or after.
    public var since: Int64?
    /// Unix milliseconds: sent before.
    public var until: Int64?
    /// After the messages with every word, add those with some of them.
    public var partial: Bool?

    public static let senderValues = ["me", "others"]
    public static let chatTypeValues = ["dm", "group"]

    public init(roomIDs: [String]? = nil, networks: [String]? = nil, sender: String? = nil, chatType: String? = nil,
                kinds: [String]? = nil, since: Int64? = nil, until: Int64? = nil, partial: Bool? = nil) {
        self.roomIDs = roomIDs
        self.networks = networks
        self.sender = sender
        self.chatType = chatType
        self.kinds = kinds
        self.since = since
        self.until = until
        self.partial = partial
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomIDs = "room_ids"
        case networks
        case sender
        case chatType = "chat_type"
        case kinds
        case since
        case until
        case partial
    }
}

/// SearchResult.hint.
public struct SearchHint: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let none = Self(rawValue: "")
    /// The text has only emoji or punctuation, and nothing was searched.
    public static let emojiOnly = Self(rawValue: "emoji_only")
    /// Under 2 letters: media and messages didn't run, chats and in_groups did.
    public static let needMoreLetters = Self(rawValue: "need_more_letters")
    public static let known: [Self] = [.none, .emojiOnly, .needMoreLetters]
}

/// A section that wasn't asked for or didn't run is nil; one that ran and found nothing is empty.
public struct SearchResult: ProtocolType, Equatable {
    public static let protocolName = "SearchResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// InboxRow[]|null.
    public var chats: [InboxRow]?
    /// PersonHit[]|null: people in a group with me who have no direct chat with me.
    public var inGroups: [PersonHit]?
    /// MessageHits|null: images and videos.
    public var media: MessageHits?
    /// MessageHits|null: every other kind.
    public var messages: MessageHits?
    /// InboxRow|null: only for empty text with no filters, the chat archived most recently.
    public var lastArchived: InboxRow?
    /// false while older messages are still being added.
    public var complete: Bool
    public var hint: SearchHint

    public init(chats: [InboxRow]? = nil, inGroups: [PersonHit]? = nil, media: MessageHits? = nil,
                messages: MessageHits? = nil, lastArchived: InboxRow? = nil, complete: Bool = true,
                hint: SearchHint = .none) {
        self.chats = chats
        self.inGroups = inGroups
        self.media = media
        self.messages = messages
        self.lastArchived = lastArchived
        self.complete = complete
        self.hint = hint
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case chats
        case inGroups = "in_groups"
        case media
        case messages
        case lastArchived = "last_archived"
        case complete
        case hint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Every T|null key must be there.
        chats = try container.decode([InboxRow]?.self, forKey: .chats)
        inGroups = try container.decode([PersonHit]?.self, forKey: .inGroups)
        media = try container.decode(MessageHits?.self, forKey: .media)
        messages = try container.decode(MessageHits?.self, forKey: .messages)
        lastArchived = try container.decode(InboxRow?.self, forKey: .lastArchived)
        complete = try container.decode(Bool.self, forKey: .complete)
        hint = try container.decode(SearchHint.self, forKey: .hint)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // null, not left out
        try container.encode(chats, forKey: .chats)
        try container.encode(inGroups, forKey: .inGroups)
        try container.encode(media, forKey: .media)
        try container.encode(messages, forKey: .messages)
        try container.encode(lastArchived, forKey: .lastArchived)
        try container.encode(complete, forKey: .complete)
        try container.encode(hint, forKey: .hint)
    }
}

/// Someone found by name in a group I share with them.
public struct PersonHit: ProtocolType, Equatable, Hashable {
    public static let protocolName = "PersonHit"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var userID: String
    public var name: String
    public var network: String
    public var avatarPath: String
    /// Their most recent shared group: the one with the newest message.
    public var roomID: String
    public var roomName: String
    /// How many groups I share with them.
    public var groups: Int

    public init(userID: String, name: String, network: String, avatarPath: String = "", roomID: String,
                roomName: String, groups: Int) {
        self.userID = userID
        self.name = name
        self.network = network
        self.avatarPath = avatarPath
        self.roomID = roomID
        self.roomName = roomName
        self.groups = groups
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case userID = "user_id"
        case name
        case network
        case avatarPath = "avatar_path"
        case roomID = "room_id"
        case roomName = "room_name"
        case groups
    }
}

/// One page of messages found.
public struct MessageHits: ProtocolType, Equatable {
    public static let protocolName = "MessageHits"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// Newest first; with partial, every full match first.
    public var hits: [MessageHit]
    /// string|null: the cursor of the next page. Only nil says there is no more: a page may hold fewer hits than
    /// asked for.
    public var nextCursor: String?

    public init(hits: [MessageHit], nextCursor: String? = nil) {
        self.hits = hits
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case hits
        case nextCursor = "next_cursor"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hits = try container.decode([MessageHit].self, forKey: .hits)
        nextCursor = try container.decode(String?.self, forKey: .nextCursor) // the key must be there
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hits, forKey: .hits)
        try container.encode(nextCursor, forKey: .nextCursor) // null, not left out
    }
}

/// MessageHit.place: where the chat is. A result outside the inbox says so.
public struct ChatPlace: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let inbox = Self(rawValue: "inbox")
    public static let archive = Self(rawValue: "archive")
    public static let lowPriority = Self(rawValue: "low_priority")
    public static let hidden = Self(rawValue: "hidden")
    public static let requests = Self(rawValue: "requests")
    public static let known: [Self] = [.inbox, .archive, .lowPriority, .hidden, .requests]
}

/// MessageHit.kind.
public struct MessageHitKind: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let text = Self(rawValue: "text")
    public static let image = Self(rawValue: "image")
    public static let video = Self(rawValue: "video")
    public static let audio = Self(rawValue: "audio")
    public static let file = Self(rawValue: "file")
    public static let sticker = Self(rawValue: "sticker")
    public static let known: [Self] = [.text, .image, .video, .audio, .file, .sticker]
}

/// One message found.
public struct MessageHit: ProtocolType, Equatable, Hashable {
    public static let protocolName = "MessageHit"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// Open the chat at it with room.events `around`.
    public var eventID: String
    public var roomID: String
    public var roomName: String
    public var network: String
    public var isDirect: Bool
    public var place: ChatPlace
    public var sender: String
    /// The sender's display name, or the localpart of their ID.
    public var senderName: String
    public var mine: Bool
    public var ts: Int64
    public var seq: Int64
    public var kind: MessageHitKind
    /// At most 160 characters of the message's text around the first match, with … where it was cut.
    public var snippet: String
    /// The matched words in `snippet`, in order, in UTF-16 code units.
    public var ranges: [TextRange]
    /// An image's or a video's thumbnail (or the file itself), or "".
    public var mediaPath: String
    /// It matches some of the words, not all.
    public var partial: Bool

    public init(eventID: String, roomID: String, roomName: String, network: String, isDirect: Bool,
                place: ChatPlace = .inbox, sender: String, senderName: String, mine: Bool, ts: Int64, seq: Int64,
                kind: MessageHitKind = .text, snippet: String, ranges: [TextRange] = [], mediaPath: String = "",
                partial: Bool = false) {
        self.eventID = eventID
        self.roomID = roomID
        self.roomName = roomName
        self.network = network
        self.isDirect = isDirect
        self.place = place
        self.sender = sender
        self.senderName = senderName
        self.mine = mine
        self.ts = ts
        self.seq = seq
        self.kind = kind
        self.snippet = snippet
        self.ranges = ranges
        self.mediaPath = mediaPath
        self.partial = partial
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
        case roomID = "room_id"
        case roomName = "room_name"
        case network
        case isDirect = "is_direct"
        case place
        case sender
        case senderName = "sender_name"
        case mine
        case ts
        case seq
        case kind
        case snippet
        case ranges
        case mediaPath = "media_path"
        case partial
    }

    /// The matched words as ranges of `snippet`, taken as the engine counts them: UTF-16 code units, never
    /// re-counted in Characters (an emoji before a match would move it). A range past the snippet's end is left out.
    public var matchRanges: [NSRange] {
        let length = (snippet as NSString).length
        return ranges.compactMap { range in
            guard range.start >= 0, range.length > 0, range.start + range.length <= length else { return nil }
            return NSRange(location: range.start, length: range.length)
        }
    }

    /// `snippet` with each matched word marked strongly emphasized, for a view to draw in bold.
    public var highlightedSnippet: AttributedString {
        var text = AttributedString(snippet)
        for range in matchRanges {
            guard let bounds = Range<AttributedString.Index>(range, in: text) else { continue }
            text[bounds].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }
}

/// A run of a snippet, in UTF-16 code units.
public struct TextRange: ProtocolType, Equatable, Hashable {
    public static let protocolName = "TextRange"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var start: Int
    public var length: Int

    public init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case start
        case length
    }
}

public struct SetMutedParams: ProtocolType, Equatable {
    public static let protocolName = "SetMutedParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var muted: Bool

    public init(roomID: String, muted: Bool) {
        self.roomID = roomID
        self.muted = muted
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case muted
    }
}

public struct SendParams: ProtocolType, Equatable {
    public static let protocolName = "SendParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var text: String
    public var replyTo: String?

    public init(roomID: String, text: String, replyTo: String? = nil) {
        self.roomID = roomID
        self.text = text
        self.replyTo = replyTo
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case text
        case replyTo = "reply_to"
    }
}

public struct SendFileParams: ProtocolType, Equatable {
    public static let protocolName = "SendFileParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var path: String
    public var replyTo: String?

    public init(roomID: String, path: String, replyTo: String? = nil) {
        self.roomID = roomID
        self.path = path
        self.replyTo = replyTo
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case path
        case replyTo = "reply_to"
    }
}

public struct ReactParams: ProtocolType, Equatable {
    public static let protocolName = "ReactParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var eventID: String
    public var key: String

    public init(roomID: String, eventID: String, key: String) {
        self.roomID = roomID
        self.eventID = eventID
        self.key = key
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case eventID = "event_id"
        case key
    }
}

public struct EventParams: ProtocolType, Equatable {
    public static let protocolName = "EventParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var eventID: String

    public init(eventID: String) { self.eventID = eventID }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
    }
}

/// The event that was stored for what was sent.
public struct Sent: ProtocolType, Equatable {
    public static let protocolName = "Sent"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var eventID: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
    }
}

public struct LoginStartParams: ProtocolType, Equatable {
    public static let protocolName = "LoginStartParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String
    public var flow: String?

    public init(network: String, flow: String? = nil) {
        self.network = network
        self.flow = flow
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case flow
    }
}

public struct LoginSubmitParams: ProtocolType, Equatable {
    public static let protocolName = "LoginSubmitParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var loginID: String
    public var values: [String: String]

    public init(loginID: String, values: [String: String]) {
        self.loginID = loginID
        self.values = values
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case loginID = "login_id"
        case values
    }
}

public struct LoginParams: ProtocolType, Equatable {
    public static let protocolName = "LoginParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var loginID: String

    public init(loginID: String) { self.loginID = loginID }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case loginID = "login_id"
    }
}

/// LoginStep.type.
public struct LoginStepType: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let displayAndWait = Self(rawValue: "display_and_wait")
    public static let userInput = Self(rawValue: "user_input")
    public static let cookies = Self(rawValue: "cookies")
    public static let complete = Self(rawValue: "complete")
    public static let unsupported = Self(rawValue: "unsupported")
    public static let known: [Self] = [.displayAndWait, .userInput, .cookies, .complete, .unsupported]
}

/// What the sign-in shows next.
public struct LoginStep: ProtocolType, Equatable {
    public static let protocolName = "LoginStep"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var loginID: String
    public var stepID: String
    public var type: LoginStepType
    public var instructions: String?
    public var display: LoginDisplay?
    public var fields: [LoginField]?
    public var cookies: LoginCookies?
    public var remoteName: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case loginID = "login_id"
        case stepID = "step_id"
        case type
        case instructions
        case display
        case fields
        case cookies
        case remoteName = "remote_name"
    }
}

/// LoginDisplay.kind.
public struct LoginDisplayKind: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let qr = Self(rawValue: "qr")
    public static let emoji = Self(rawValue: "emoji")
    public static let code = Self(rawValue: "code")
    public static let known: [Self] = [.qr, .emoji, .code]
}

public struct LoginDisplay: ProtocolType, Equatable {
    public static let protocolName = "LoginDisplay"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var kind: LoginDisplayKind
    public var data: String?
    public var imageURL: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case data
        case imageURL = "image_url"
    }
}

/// LoginField.type. password and token are secret.
public struct LoginFieldType: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let username = Self(rawValue: "username")
    public static let password = Self(rawValue: "password")
    public static let phoneNumber = Self(rawValue: "phone_number")
    public static let email = Self(rawValue: "email")
    public static let twoFactorCode = Self(rawValue: "2fa_code")
    public static let token = Self(rawValue: "token")
    public static let url = Self(rawValue: "url")
    public static let domain = Self(rawValue: "domain")
    public static let select = Self(rawValue: "select")
    public static let known: [Self] = [
        .username, .password, .phoneNumber, .email, .twoFactorCode, .token, .url, .domain, .select,
    ]

    /// Hidden as typed.
    public var isSecret: Bool { self == .password || self == .token }
}

public struct LoginField: ProtocolType, Equatable {
    public static let protocolName = "LoginField"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var id: String
    public var name: String
    public var description: String
    public var type: LoginFieldType
    public var pattern: String?
    public var options: [String]?
    public var defaultValue: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case description
        case type
        case pattern
        case options
        case defaultValue = "default_value"
    }
}

public struct LoginCookies: ProtocolType, Equatable {
    public static let protocolName = "LoginCookies"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var url: String
    public var userAgent: String?
    public var waitForURL: String?
    public var extractJS: String?
    public var fields: [LoginCookieField]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case url
        case userAgent = "user_agent"
        case waitForURL = "wait_for_url"
        case extractJS = "extract_js"
        case fields
    }
}

public struct LoginCookieField: ProtocolType, Equatable {
    public static let protocolName = "LoginCookieField"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var id: String
    public var required: Bool
    public var sources: [LoginCookieSource]
    public var pattern: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case required
        case sources
        case pattern
    }
}

/// LoginCookieSource.type.
public struct LoginCookieSourceType: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let cookie = Self(rawValue: "cookie")
    public static let localStorage = Self(rawValue: "local_storage")
    public static let requestHeader = Self(rawValue: "request_header")
    public static let requestBody = Self(rawValue: "request_body")
    public static let special = Self(rawValue: "special")
    public static let known: [Self] = [.cookie, .localStorage, .requestHeader, .requestBody, .special]
}

public struct LoginCookieSource: ProtocolType, Equatable {
    public static let protocolName = "LoginCookieSource"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var type: LoginCookieSourceType
    public var name: String
    public var cookieDomain: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case name
        case cookieDomain = "cookie_domain"
    }
}

/// Changed.kind.
public struct ChangedKind: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let room = Self(rawValue: "room")
    public static let event = Self(rawValue: "event")
    public static let status = Self(rawValue: "status")
    public static let read = Self(rawValue: "read")
    public static let bridge = Self(rawValue: "bridge")
    public static let spaces = Self(rawValue: "spaces")
    public static let typing = Self(rawValue: "typing")
    public static let reminder = Self(rawValue: "reminder")
    public static let resync = Self(rawValue: "resync")
    public static let known: [Self] = [.room, .event, .status, .read, .bridge, .spaces, .typing, .reminder, .resync]
}

/// The changed notification's params, as on the wire. The app reads them as a `Change`.
public struct Changed: ProtocolType, Equatable {
    public static let protocolName = "Changed"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var kind: ChangedKind
    public var roomID: String?
    public var eventID: String?
    public var network: String?

    public init(kind: ChangedKind, roomID: String? = nil, eventID: String? = nil, network: String? = nil) {
        self.kind = kind
        self.roomID = roomID
        self.eventID = eventID
        self.network = network
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case roomID = "room_id"
        case eventID = "event_id"
        case network
    }
}

public struct ProtocolMismatchData: ProtocolType, Equatable {
    public static let protocolName = "ProtocolMismatchData"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var engine: Int

    enum CodingKeys: String, CodingKey, CaseIterable {
        case engine
    }
}

public struct InvalidParamsData: ProtocolType, Equatable {
    public static let protocolName = "InvalidParamsData"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var reason: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case reason
    }
}

// MARK: - Changes

/// Something the app shows has changed: re-query it. A `Changed` notification, read.
public enum Change: Equatable, Hashable, Sendable {
    /// A chat's row. With no room, names or pictures changed in chats unknown: re-read the inbox and the open chat.
    case room(roomID: String?)
    /// A new event in the room.
    case event(roomID: String, eventID: String)
    /// The event changed status, or was discarded.
    case status(roomID: String, eventID: String)
    /// The room's read marker moved.
    case read(roomID: String, eventID: String?)
    /// The network's account changed state.
    case bridge(network: String)
    /// Labels, the spaces layout, or an account's or label's space settings changed: re-read the spaces, and the
    /// inbox, whose rows show labels and what mutes them.
    case spaces
    /// Who is typing in the room changed.
    case typing(roomID: String)
    /// The room's reminder fired: tell the person. A `room` change for its row comes too.
    case reminder(roomID: String)
    /// Changes were lost: re-read everything.
    case resync

    /// A notification this app cannot place (a kind it does not know, or one without the keys its kind needs)
    /// becomes a resync: re-reading everything is never wrong, only slower.
    public init(_ changed: Changed) {
        switch changed.kind {
        case .room:
            self = .room(roomID: changed.roomID)
        case .event:
            guard let room = changed.roomID, let event = changed.eventID else { self = .resync; return }
            self = .event(roomID: room, eventID: event)
        case .status:
            guard let room = changed.roomID, let event = changed.eventID else { self = .resync; return }
            self = .status(roomID: room, eventID: event)
        case .read:
            guard let room = changed.roomID else { self = .resync; return }
            self = .read(roomID: room, eventID: changed.eventID)
        case .bridge:
            guard let network = changed.network else { self = .resync; return }
            self = .bridge(network: network)
        case .spaces:
            self = .spaces
        case .typing:
            guard let room = changed.roomID else { self = .resync; return }
            self = .typing(roomID: room)
        case .reminder:
            guard let room = changed.roomID else { self = .resync; return }
            self = .reminder(roomID: room)
        default:
            self = .resync
        }
    }
}

// MARK: - Methods and errors

/// The methods, with the types of their params and results, as protocol.json's "methods".
public enum ProtocolMethods {
    public static let changedNotification = "changed"

    public static let all: [String: (params: any ProtocolType.Type, result: any ProtocolType.Type)] = [
        "hello": (HelloParams.self, HelloResult.self),
        "accounts.list": (Empty.self, AccountsResult.self),
        "inbox.list": (InboxListParams.self, InboxResult.self),
        "spaces.list": (Empty.self, SpacesResult.self),
        "spaces.setLayout": (SpaceLayoutParams.self, Empty.self),
        "spaces.update": (SpaceUpdateParams.self, Empty.self),
        "labels.create": (LabelParams.self, LabelResult.self),
        "labels.update": (LabelUpdateParams.self, Empty.self),
        "labels.delete": (LabelIDParams.self, Empty.self),
        "room.setPinned": (SetPinnedParams.self, Empty.self),
        "room.setArchived": (ArchiveParams.self, RoomsChanged.self),
        "room.setLowPriority": (RoomsFlagParams.self, RoomsChanged.self),
        "room.setHidden": (RoomsFlagParams.self, RoomsChanged.self),
        "room.setMarkedUnread": (RoomsFlagParams.self, RoomsChanged.self),
        "room.setLabel": (SetLabelParams.self, RoomsChanged.self),
        "room.setDraft": (DraftParams.self, Empty.self),
        "room.acceptRequest": (RoomParams.self, Empty.self),
        "reminder.set": (ReminderParams.self, Empty.self),
        "reminder.clear": (RoomsParams.self, Empty.self),
        "reminder.clearAll": (Empty.self, Empty.self),
        "inbox.archiveMatching": (ArchiveMatchingParams.self, RoomsChanged.self),
        "inbox.markAllRead": (SpaceParams.self, RoomsChanged.self),
        "autoArchive.list": (Empty.self, RulesResult.self),
        "autoArchive.set": (AutoArchiveRule.self, AutoArchiveRule.self),
        "autoArchive.delete": (RuleIDParams.self, Empty.self),
        "room.events": (RoomEventsParams.self, EventsPage.self),
        "search.query": (SearchParams.self, SearchResult.self),
        "room.markRead": (RoomParams.self, Empty.self),
        "room.setMuted": (SetMutedParams.self, Empty.self),
        "message.send": (SendParams.self, Sent.self),
        "message.sendFile": (SendFileParams.self, Sent.self),
        "message.react": (ReactParams.self, Sent.self),
        "message.retry": (EventParams.self, Empty.self),
        "message.discard": (EventParams.self, Empty.self),
        "login.start": (LoginStartParams.self, LoginStep.self),
        "login.submit": (LoginSubmitParams.self, LoginStep.self),
        "login.wait": (LoginParams.self, LoginStep.self),
        "login.cancel": (LoginParams.self, Empty.self),
    ]

    /// Every type of protocol.json's "types".
    public static let types: [any ProtocolType.Type] = [
        Empty.self, HelloParams.self, HelloResult.self, Account.self, AccountsResult.self, InboxRow.self,
        Reminder.self, InboxListParams.self, InboxResult.self, Space.self, SpacesResult.self, SpaceLayoutParams.self,
        SpaceUpdateParams.self, LabelParams.self, LabelResult.self, LabelUpdateParams.self, LabelIDParams.self,
        SetPinnedParams.self, ArchiveParams.self, RoomsChanged.self, RoomsFlagParams.self, SetLabelParams.self,
        DraftParams.self, ReminderParams.self, RoomsParams.self, ArchiveMatchingParams.self, SpaceParams.self,
        AutoArchiveRule.self, RulesResult.self, RuleIDParams.self, Cursor.self, RoomParams.self, RoomEventsParams.self, Event.self, EventsPage.self,
        SearchParams.self, SearchFilters.self, SearchResult.self, PersonHit.self, MessageHits.self, MessageHit.self,
        TextRange.self, SetMutedParams.self, SendParams.self, SendFileParams.self, ReactParams.self, EventParams.self, Sent.self,
        LoginStartParams.self, LoginSubmitParams.self, LoginParams.self, LoginStep.self, LoginDisplay.self,
        LoginField.self, LoginCookies.self, LoginCookieField.self, LoginCookieSource.self, Changed.self,
        ProtocolMismatchData.self, InvalidParamsData.self,
    ]

    /// The open-valued fields, by "Type.field", with the values this app knows.
    public static let values: [String: [String]] = [
        "Account.state": AccountState.known.map(\.rawValue),
        "Account.syncs": AccountSync.known.map(\.rawValue),
        "InboxRow.preview_kind": PreviewKind.known.map(\.rawValue),
        "InboxRow.muted_by": MutedBy.known.map(\.rawValue),
        "Reminder.condition": ReminderCondition.known.map(\.rawValue),
        "InboxListParams.filters": InboxFilter.wireOrder.map(\.rawValue),
        "InboxListParams.sort": InboxSort.allCases.map(\.rawValue),
        "Space.kind": SpaceKind.known.map(\.rawValue),
        "Space.show_in_inbox": ShowInInbox.known.map(\.rawValue),
        "SpaceUpdateParams.show_in_inbox": ShowInInbox.settable.map(\.rawValue),
        "ReminderParams.condition": ReminderCondition.known.map(\.rawValue),
        "AutoArchiveRule.trigger": AutoArchiveTrigger.known.map(\.rawValue),
        "AutoArchiveRule.chat_type": AutoArchiveChatType.known.map(\.rawValue),
        "Event.status": EventStatus.known.map(\.rawValue),
        "SearchParams.sections": SearchSectionName.known.map(\.rawValue),
        "SearchFilters.sender": SearchFilters.senderValues,
        "SearchFilters.chat_type": SearchFilters.chatTypeValues,
        "SearchFilters.kinds": SearchKind.allCases.map(\.rawValue),
        "SearchResult.hint": SearchHint.known.map(\.rawValue),
        "MessageHit.place": ChatPlace.known.map(\.rawValue),
        "MessageHit.kind": MessageHitKind.known.map(\.rawValue),
        "LoginStep.type": LoginStepType.known.map(\.rawValue),
        "LoginDisplay.kind": LoginDisplayKind.known.map(\.rawValue),
        "LoginField.type": LoginFieldType.known.map(\.rawValue),
        "LoginCookieSource.type": LoginCookieSourceType.known.map(\.rawValue),
        "Changed.kind": ChangedKind.known.map(\.rawValue),
    ]
}

/// An error code the engine answers with, as protocol.json's "errors".
public enum RPCErrorCode: Equatable, Hashable, Sendable {
    case parseError
    case invalidRequest
    case methodNotFound
    case invalidParams
    case internalError
    case protocolMismatch
    case helloRequired
    case notLinked
    case bridgeCommand
    case tooLarge
    case alreadyLinked
    case badValue
    case unknownLogin
    case notRunning
    case loginInProgress
    case notConnected
    case notFailed
    case notFound
    case pinned
    case notEntitled
    case notSupported
    /// A code this app does not know.
    case other(Int)

    /// Every code protocol.json defines, with its name there.
    public static let known: [(code: RPCErrorCode, number: Int, name: String)] = [
        (.parseError, -32700, "parse_error"),
        (.invalidRequest, -32600, "invalid_request"),
        (.methodNotFound, -32601, "method_not_found"),
        (.invalidParams, -32602, "invalid_params"),
        (.internalError, -32603, "internal_error"),
        (.protocolMismatch, -32001, "protocol_mismatch"),
        (.helloRequired, -32002, "hello_required"),
        (.notLinked, -32010, "not_linked"),
        (.bridgeCommand, -32011, "bridge_command"),
        (.tooLarge, -32012, "too_large"),
        (.alreadyLinked, -32013, "already_linked"),
        (.badValue, -32014, "bad_value"),
        (.unknownLogin, -32015, "unknown_login"),
        (.notRunning, -32016, "not_running"),
        (.loginInProgress, -32017, "login_in_progress"),
        (.notConnected, -32018, "not_connected"),
        (.notFailed, -32019, "not_failed"),
        (.notFound, -32020, "not_found"),
        (.pinned, -32021, "pinned"),
        (.notEntitled, -32022, "not_entitled"),
        (.notSupported, -32023, "not_supported"),
    ]

    public init(number: Int) {
        self = Self.known.first(where: { $0.number == number })?.code ?? .other(number)
    }

    public var number: Int {
        if case let .other(number) = self { return number }
        return Self.known.first(where: { $0.code == self })!.number
    }
}
