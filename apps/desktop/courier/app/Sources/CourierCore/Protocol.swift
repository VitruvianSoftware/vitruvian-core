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
    public static let version = 1
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

    public init(network: String, displayName: String, flows: [String], state: AccountState, error: String = "",
                remoteName: String = "", notStarted: String = "") {
        self.network = network
        self.displayName = displayName
        self.flows = flows
        self.state = state
        self.error = error
        self.remoteName = remoteName
        self.notStarted = notStarted
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case displayName = "display_name"
        case flows
        case state
        case error
        case remoteName = "remote_name"
        case notStarted = "not_started"
    }
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
    public static let none = Self(rawValue: "")
    public static let known: [Self] = [.text, .image, .video, .audio, .file, .sticker, .none]
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
    public var muted: Bool

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
    }
}

public struct InboxResult: ProtocolType, Equatable {
    public static let protocolName = "InboxResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var rooms: [InboxRow]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case rooms
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

public struct RoomEventsParams: ProtocolType, Equatable {
    public static let protocolName = "RoomEventsParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var before: Cursor?
    public var limit: Int?

    public init(roomID: String, before: Cursor? = nil, limit: Int? = nil) {
        self.roomID = roomID
        self.before = before
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case before
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

    public init(events: [Event], before: Cursor?) {
        self.events = events
        self.before = before
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case events
        case before
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decode([Event].self, forKey: .events)
        before = try container.decode(Cursor?.self, forKey: .before) // the key must be there
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        try container.encode(before, forKey: .before) // null, not left out
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
    public static let resync = Self(rawValue: "resync")
    public static let known: [Self] = [.room, .event, .status, .read, .bridge, .resync]
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
        "inbox.list": (Empty.self, InboxResult.self),
        "room.events": (RoomEventsParams.self, EventsPage.self),
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
        InboxResult.self, Cursor.self, RoomParams.self, RoomEventsParams.self, Event.self, EventsPage.self,
        SetMutedParams.self, SendParams.self, SendFileParams.self, ReactParams.self, EventParams.self, Sent.self,
        LoginStartParams.self, LoginSubmitParams.self, LoginParams.self, LoginStep.self, LoginDisplay.self,
        LoginField.self, LoginCookies.self, LoginCookieField.self, LoginCookieSource.self, Changed.self,
        ProtocolMismatchData.self, InvalidParamsData.self,
    ]

    /// The open-valued fields, by "Type.field", with the values this app knows.
    public static let values: [String: [String]] = [
        "Account.state": AccountState.known.map(\.rawValue),
        "InboxRow.preview_kind": PreviewKind.known.map(\.rawValue),
        "Event.status": EventStatus.known.map(\.rawValue),
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
    ]

    public init(number: Int) {
        self = Self.known.first(where: { $0.number == number })?.code ?? .other(number)
    }

    public var number: Int {
        if case let .other(number) = self { return number }
        return Self.known.first(where: { $0.code == self })!.number
    }
}
