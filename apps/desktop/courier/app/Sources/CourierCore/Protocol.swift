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
    public static let version = 9
    public static let schemaVersion = 10
    /// The longest line either side may send, not counting the newline.
    public static let maxFrameBytes = 4_194_304
    /// protocol.json's `conventions.typing_repeat_ms`: while the text keeps changing, room.setTyping true goes again
    /// this often (`ComposerModel.typingRepeat`). The engine counts a pulse a second early as a new start.
    public static let typingRepeatMillis = 4000
}

public let protocolVersion = CourierProtocol.version

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
    /// Whether any linked account on this network can create group chats (`GroupCreatingNetworkAPI`).
    public var canCreateGroup: Bool
    /// Each account signed in on the network (a second phone number, a second workspace), first the one a plain
    /// sign-in signs in again. `state` sums them up. [] when none is linked.
    public var logins: [Login]

    public init(network: String, displayName: String, flows: [String], state: AccountState, error: String = "",
                remoteName: String = "", notStarted: String = "", syncs: [AccountSync] = [],
                logins: [Login] = [], canCreateGroup: Bool = true) {
        self.network = network
        self.displayName = displayName
        self.flows = flows
        self.state = state
        self.error = error
        self.remoteName = remoteName
        self.notStarted = notStarted
        self.syncs = syncs
        self.canCreateGroup = canCreateGroup
        self.logins = logins
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
        case canCreateGroup = "can_create_group"
        case logins
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network = try container.decode(String.self, forKey: .network)
        displayName = try container.decode(String.self, forKey: .displayName)
        flows = try container.decode([String].self, forKey: .flows)
        state = try container.decode(AccountState.self, forKey: .state)
        error = try container.decode(String.self, forKey: .error)
        remoteName = try container.decode(String.self, forKey: .remoteName)
        notStarted = try container.decode(String.self, forKey: .notStarted)
        syncs = try container.decode([AccountSync].self, forKey: .syncs)
        canCreateGroup = try container.decodeIfPresent(Bool.self, forKey: .canCreateGroup) ?? true
        logins = try container.decode([Login].self, forKey: .logins)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(network, forKey: .network)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(flows, forKey: .flows)
        try container.encode(state, forKey: .state)
        try container.encode(error, forKey: .error)
        try container.encode(remoteName, forKey: .remoteName)
        try container.encode(notStarted, forKey: .notStarted)
        try container.encode(syncs, forKey: .syncs)
        try container.encode(canCreateGroup, forKey: .canCreateGroup)
        try container.encode(logins, forKey: .logins)
    }
}

/// One account signed in on a network. "Login" here (and `InboxRow.loginName`) means an account, named by
/// `accountID`; a sign-in session's ID is `LoginStep.loginID`, never an account.
public struct Login: ProtocolType, Equatable, Hashable {
    public static let protocolName = "Login"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// The account's ID on its network, as the bridge keeps it: what `LoginStartParams.accountID` signs in again.
    public var accountID: String
    /// What the network calls the account (a phone number, a workspace's name); "" when it hasn't said.
    public var remoteName: String
    public var state: AccountState
    /// The bridge's own words, for help only: never shown as Courier's copy. "" when nothing is wrong.
    public var error: String
    /// Whether this account's bridge client implements `GroupCreatingNetworkAPI` and can create group chats.
    public var canCreateGroup: Bool

    public init(accountID: String, remoteName: String = "", state: AccountState, error: String = "",
                canCreateGroup: Bool = true) {
        self.accountID = accountID
        self.remoteName = remoteName
        self.state = state
        self.error = error
        self.canCreateGroup = canCreateGroup
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case accountID = "account_id"
        case remoteName = "remote_name"
        case state
        case error
        case canCreateGroup = "can_create_group"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decode(String.self, forKey: .accountID)
        remoteName = try container.decode(String.self, forKey: .remoteName)
        state = try container.decode(AccountState.self, forKey: .state)
        error = try container.decode(String.self, forKey: .error)
        canCreateGroup = try container.decodeIfPresent(Bool.self, forKey: .canCreateGroup) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(remoteName, forKey: .remoteName)
        try container.encode(state, forKey: .state)
        try container.encode(error, forKey: .error)
        try container.encode(canCreateGroup, forKey: .canCreateGroup)
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
    /// A note that the chat's disappearing timer changed. The preview is empty: the label says it.
    public static let timerChange = Self(rawValue: "timer_change")
    /// A bridge's notice of a call. The preview is empty: `InboxRow.previewCall` says what happened, the label words it.
    public static let call = Self(rawValue: "call")
    public static let none = Self(rawValue: "")
    public static let known: [Self] = [.text, .image, .video, .audio, .file, .sticker, .poll, .timerChange, .call, .none]
}

/// One chat in the inbox.
public struct InboxRow: ProtocolType, Equatable, Identifiable {
    public static let protocolName = "InboxRow"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var id: String { mergeID.isEmpty ? roomID : mergeID }
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
    /// CallNote|null: for a `call` preview, what happened; null for any other. Always on the wire.
    public var previewCall: CallNote?
    /// How far the newest message has got, when it is mine and has gone; `.none` for anything else.
    public var previewStatus: PreviewStatus
    /// The account the chat is on, for a small tag, while its network has more than one; "" otherwise (and for a
    /// chat every account shares). An account's name, not a sign-in's login_id.
    public var loginName: String
    /// The chat's name on its network, before any local override.
    public var remoteName: String
    /// The name set on this Mac (Just for Me), or "".
    public var localName: String
    /// The picture set on this Mac (Just for Me), or "".
    public var localAvatarPath: String
    /// The merged chat this room belongs to, or "".
    public var mergeID: String

    public init(roomID: String, network: String, name: String, avatarPath: String, isDirect: Bool, lastTS: Int64,
                preview: String, previewKind: PreviewKind, previewMine: Bool, unread: Int, muted: Bool,
                pinned: Bool = false, archived: Bool = false, lowPriority: Bool = false, hidden: Bool = false,
                markedUnread: Bool = false, request: Bool = false, draft: String = "", labels: [Int64] = [],
                mutedBy: MutedBy = .none, mutedByName: String = "", reminder: Reminder? = nil,
                typing: [String] = [], unreadMentions: Int = 0, previewMediaPath: String = "",
                previewCall: CallNote? = nil, previewStatus: PreviewStatus = .none, loginName: String = "",
                remoteName: String = "", localName: String = "", localAvatarPath: String = "",
                mergeID: String = "") {
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
        self.previewCall = previewCall
        self.previewStatus = previewStatus
        self.loginName = loginName
        self.remoteName = remoteName
        self.localName = localName
        self.localAvatarPath = localAvatarPath
        self.mergeID = mergeID
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
        case previewCall = "preview_call"
        case previewStatus = "preview_status"
        case loginName = "login_name"
        case remoteName = "remote_name"
        case localName = "local_name"
        case localAvatarPath = "local_avatar_path"
        case mergeID = "merge_id"
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
        previewCall = try container.decode(CallNote?.self, forKey: .previewCall) // the key must be there
        previewStatus = try container.decode(PreviewStatus.self, forKey: .previewStatus)
        loginName = try container.decode(String.self, forKey: .loginName)
        remoteName = try container.decodeIfPresent(String.self, forKey: .remoteName) ?? ""
        localName = try container.decodeIfPresent(String.self, forKey: .localName) ?? ""
        localAvatarPath = try container.decodeIfPresent(String.self, forKey: .localAvatarPath) ?? ""
        mergeID = try container.decodeIfPresent(String.self, forKey: .mergeID) ?? ""
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
        try container.encode(previewCall, forKey: .previewCall) // null, not left out
        try container.encode(previewStatus, forKey: .previewStatus)
        try container.encode(loginName, forKey: .loginName)
        try container.encode(remoteName, forKey: .remoteName)
        try container.encode(localName, forKey: .localName)
        try container.encode(localAvatarPath, forKey: .localAvatarPath)
        try container.encode(mergeID, forKey: .mergeID)
    }
}

/// InboxRow.preview_status: how far the row's newest message has got, when it is mine and has gone (not a note).
public struct PreviewStatus: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Someone else's message, one of mine not sent yet, a note, or no message.
    public static let none = Self(rawValue: "")
    public static let sent = Self(rawValue: "sent")
    /// Someone's device has it (one-to-one chats only).
    public static let delivered = Self(rawValue: "delivered")
    /// Someone has read it, or anything after it.
    public static let seen = Self(rawValue: "seen")
    public static let known: [Self] = [.none, .sent, .delivered, .seen]
}

/// A bridge's notice of a call, as Courier reads it (`InboxRow.previewCall`, and an event's content's
/// `fi.courier.call`: `CallNote.of`). Whether it was mine is the event's, or the row's `previewMine`.
public struct CallNote: ProtocolType, Equatable, Hashable {
    public static let protocolName = "CallNote"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var state: CallState
    public var media: CallMedia

    public init(state: CallState, media: CallMedia = .unknown) {
        self.state = state
        self.media = media
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case state
        case media
    }
}

/// CallNote.state: what happened with the call.
public struct CallState: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A call came in; for mine, I called.
    public static let ringing = Self(rawValue: "ringing")
    /// A group's call started.
    public static let started = Self(rawValue: "started")
    /// No one answered.
    public static let missed = Self(rawValue: "missed")
    /// It is over: answered, except on Signal, which doesn't say.
    public static let ended = Self(rawValue: "ended")
    /// It was turned down.
    public static let declined = Self(rawValue: "declined")
    /// The connection was lost.
    public static let dropped = Self(rawValue: "dropped")
    public static let known: [Self] = [.ringing, .started, .missed, .ended, .declined, .dropped]
}

/// CallNote.media: voice or video; `unknown` ("") when the bridge doesn't say.
public struct CallMedia: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let voice = Self(rawValue: "voice")
    public static let video = Self(rawValue: "video")
    public static let unknown = Self(rawValue: "")
    public static let known: [Self] = [.voice, .video, .unknown]
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
/// With `thread`, one page of that thread instead, paged with `before` only.
///
/// Page by the cursors only: a page may hold fewer than `limit` events, even none, and still have more before it.
public struct RoomEventsParams: ProtocolType, Equatable {
    public static let protocolName = "RoomEventsParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String?
    /// A merged chat's merge_id: interleaves the events of its rooms.
    public var mergeID: String?
    /// A thread's root: that thread's replies (and what they carry), newest first; the oldest page ends with the
    /// root. Without it, a reply that stays in its thread is left out, though its edits and reactions may come.
    public var thread: String?
    /// A page's `before`, for the page older than it.
    public var before: Cursor?
    /// A page's `after`, for the page newer than it.
    public var after: Cursor?
    /// An event_id in this chat: the page with that event in the middle (to open the chat at a search result).
    public var around: String?
    public var limit: Int?

    public init(roomID: String? = nil, mergeID: String? = nil, thread: String? = nil, before: Cursor? = nil,
                after: Cursor? = nil, around: String? = nil, limit: Int? = nil) {
        self.roomID = roomID
        self.mergeID = mergeID
        self.thread = thread
        self.before = before
        self.after = after
        self.around = around
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case mergeID = "merge_id"
        case thread
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

    /// Held for undo send: message.undo takes it back, and it goes when its window ends.
    public static let queued = Self(rawValue: "queued")
    /// Its network is starting, down or logging in (or messages before it in the chat are waiting): it goes when the
    /// chat's account is back, however long that takes, and message.undo takes it back (Don't Send).
    public static let waiting = Self(rawValue: "waiting")
    public static let pending = Self(rawValue: "pending")
    public static let sent = Self(rawValue: "sent")
    public static let failed = Self(rawValue: "failed")
    public static let known: [Self] = [.queued, .waiting, .pending, .sent, .failed]
}

public struct LinkPreviewItem: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "LinkPreviewItem"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var matchedURL: String
    public var url: String?
    public var title: String?
    public var siteName: String?
    public var description: String?
    public var imagePath: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var blurhash: String?

    public init(matchedURL: String, url: String? = nil, title: String? = nil,
                siteName: String? = nil, description: String? = nil,
                imagePath: String? = nil, imageWidth: Int? = nil,
                imageHeight: Int? = nil, blurhash: String? = nil) {
        self.matchedURL = matchedURL
        self.url = url
        self.title = title
        self.siteName = siteName
        self.description = description
        self.imagePath = imagePath
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.blurhash = blurhash
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case matchedURL = "matched_url"
        case url
        case title
        case siteName = "site_name"
        case description
        case imagePath = "image_path"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case blurhash
    }
}

/// One event in a chat: a message, a poll, a reaction, an edit or a redaction. A message deleted for me is left out
/// of every page.
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
    /// Why it failed, for people, or "". The engine's exact words `StatusLine` knows ("may have been sent", "not sent",
    /// "not connected") the app words itself.
    public var statusReason: String
    public var mediaPath: String
    public var thumbnailPath: String?
    public var blurhash: String?
    public var durationMS: Int64?
    public var waveform: [Int]?
    public var isGIF: Bool?
    public var isAnimated: Bool?
    public var viewOnce: Bool?
    public var geoURI: String?
    public var linkPreviews: [LinkPreviewItem]?
    public var played: Bool?
    /// I bookmarked it, on this Mac.
    public var bookmarked: Bool
    /// PollTally|null: for a poll, how it stands; nil for anything else.
    public var poll: PollTally?
    /// ThreadSummary|null: for a thread's root, its replies; nil when it has none.
    public var thread: ThreadSummary?
    /// When its disappearing timer takes it, in Unix milliseconds; 0 is never. The app hides one past its time even
    /// before the engine deletes it.
    public var expiresAt: Int64
    /// Someone's device has it: only my messages that have gone, and only in one-to-one chats.
    public var delivered: Bool
    /// Who has read it or anything after it, newest receipt first, at most 50: only my messages that have gone. My
    /// own reads on other devices never count.
    public var readBy: [Reader]

    public init(eventID: String, roomID: String, sender: String, senderName: String, senderAvatarPath: String = "",
                mine: Bool, type: String, content: JSONValue, ts: Int64, seq: Int64, status: EventStatus,
                statusReason: String = "", mediaPath: String = "", thumbnailPath: String? = nil,
                blurhash: String? = nil, durationMS: Int64? = nil, waveform: [Int]? = nil,
                isGIF: Bool? = nil, isAnimated: Bool? = nil, viewOnce: Bool? = nil, geoURI: String? = nil,
                linkPreviews: [LinkPreviewItem]? = nil, played: Bool? = nil, bookmarked: Bool = false,
                poll: PollTally? = nil, thread: ThreadSummary? = nil, expiresAt: Int64 = 0,
                delivered: Bool = false, readBy: [Reader] = []) {
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
        self.thumbnailPath = thumbnailPath
        self.blurhash = blurhash
        self.durationMS = durationMS
        self.waveform = waveform
        self.isGIF = isGIF
        self.isAnimated = isAnimated
        self.viewOnce = viewOnce
        self.geoURI = geoURI
        self.linkPreviews = linkPreviews
        self.played = played
        self.bookmarked = bookmarked
        self.poll = poll
        self.thread = thread
        self.expiresAt = expiresAt
        self.delivered = delivered
        self.readBy = readBy
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
        case thumbnailPath = "thumbnail_path"
        case blurhash
        case durationMS = "duration_ms"
        case waveform
        case isGIF = "is_gif"
        case isAnimated = "is_animated"
        case viewOnce = "view_once"
        case geoURI = "geo_uri"
        case linkPreviews = "link_previews"
        case played
        case bookmarked
        case poll
        case thread
        case expiresAt = "expires_at"
        case delivered
        case readBy = "read_by"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try container.decode(String.self, forKey: .eventID)
        roomID = try container.decode(String.self, forKey: .roomID)
        sender = try container.decode(String.self, forKey: .sender)
        senderName = try container.decode(String.self, forKey: .senderName)
        senderAvatarPath = try container.decode(String.self, forKey: .senderAvatarPath)
        mine = try container.decode(Bool.self, forKey: .mine)
        type = try container.decode(String.self, forKey: .type)
        content = try container.decode(JSONValue.self, forKey: .content)
        ts = try container.decode(Int64.self, forKey: .ts)
        seq = try container.decode(Int64.self, forKey: .seq)
        status = try container.decode(EventStatus.self, forKey: .status)
        statusReason = try container.decode(String.self, forKey: .statusReason)
        mediaPath = try container.decode(String.self, forKey: .mediaPath)
        thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath)
        blurhash = try container.decodeIfPresent(String.self, forKey: .blurhash)
        durationMS = try container.decodeIfPresent(Int64.self, forKey: .durationMS)
        waveform = try container.decodeIfPresent([Int].self, forKey: .waveform)
        isGIF = try container.decodeIfPresent(Bool.self, forKey: .isGIF)
        isAnimated = try container.decodeIfPresent(Bool.self, forKey: .isAnimated)
        viewOnce = try container.decodeIfPresent(Bool.self, forKey: .viewOnce)
        geoURI = try container.decodeIfPresent(String.self, forKey: .geoURI)
        linkPreviews = try container.decodeIfPresent([LinkPreviewItem].self, forKey: .linkPreviews)
        played = try container.decodeIfPresent(Bool.self, forKey: .played)
        bookmarked = try container.decode(Bool.self, forKey: .bookmarked)
        poll = try container.decode(PollTally?.self, forKey: .poll) // the key must be there
        thread = try container.decode(ThreadSummary?.self, forKey: .thread) // the key must be there
        expiresAt = try container.decode(Int64.self, forKey: .expiresAt)
        delivered = try container.decode(Bool.self, forKey: .delivered)
        readBy = try container.decode([Reader].self, forKey: .readBy)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(roomID, forKey: .roomID)
        try container.encode(sender, forKey: .sender)
        try container.encode(senderName, forKey: .senderName)
        try container.encode(senderAvatarPath, forKey: .senderAvatarPath)
        try container.encode(mine, forKey: .mine)
        try container.encode(type, forKey: .type)
        try container.encode(content, forKey: .content)
        try container.encode(ts, forKey: .ts)
        try container.encode(seq, forKey: .seq)
        try container.encode(status, forKey: .status)
        try container.encode(statusReason, forKey: .statusReason)
        try container.encode(mediaPath, forKey: .mediaPath)
        try container.encodeIfPresent(thumbnailPath, forKey: .thumbnailPath)
        try container.encodeIfPresent(blurhash, forKey: .blurhash)
        try container.encodeIfPresent(durationMS, forKey: .durationMS)
        try container.encodeIfPresent(waveform, forKey: .waveform)
        try container.encodeIfPresent(isGIF, forKey: .isGIF)
        try container.encodeIfPresent(isAnimated, forKey: .isAnimated)
        try container.encodeIfPresent(viewOnce, forKey: .viewOnce)
        try container.encodeIfPresent(geoURI, forKey: .geoURI)
        try container.encodeIfPresent(linkPreviews, forKey: .linkPreviews)
        try container.encodeIfPresent(played, forKey: .played)
        try container.encode(bookmarked, forKey: .bookmarked)
        try container.encode(poll, forKey: .poll) // null, not left out
        try container.encode(thread, forKey: .thread) // null, not left out
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(delivered, forKey: .delivered)
        try container.encode(readBy, forKey: .readBy)
    }
}

/// Someone who has read a message of mine, or anything after it.
public struct Reader: ProtocolType, Equatable, Hashable {
    public static let protocolName = "Reader"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var userID: String
    /// As typing names people: their name in the chat, else their profile's, else their ID's localpart.
    public var name: String
    /// When their receipt says they read it, in Unix milliseconds; 0 when it had no time.
    public var ts: Int64

    public init(userID: String, name: String, ts: Int64 = 0) {
        self.userID = userID
        self.name = name
        self.ts = ts
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case userID = "user_id"
        case name
        case ts
    }
}

/// A poll as it stands. Each person's newest vote counts, for options the poll has, at most `maxSelections` of them;
/// a vote after the poll ended doesn't.
public struct PollTally: ProtocolType, Equatable, Hashable {
    public static let protocolName = "PollTally"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var question: String
    /// In the poll's order.
    public var options: [PollOption]
    /// How many options one person may choose: 1, or every option.
    public var maxSelections: Int
    /// How many people voted.
    public var voters: Int
    /// The ids of the options I chose; [] when I didn't vote.
    public var mine: [String]
    /// Its creator ended it: no more votes count.
    public var ended: Bool

    public init(question: String, options: [PollOption], maxSelections: Int, voters: Int, mine: [String],
                ended: Bool) {
        self.question = question
        self.options = options
        self.maxSelections = maxSelections
        self.voters = voters
        self.mine = mine
        self.ended = ended
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case question
        case options
        case maxSelections = "max_selections"
        case voters
        case mine
        case ended
    }
}

public struct PollOption: ProtocolType, Equatable, Hashable, Identifiable {
    public static let protocolName = "PollOption"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// What poll.vote names it by.
    public var id: String
    public var text: String
    public var votes: Int

    public init(id: String, text: String, votes: Int) {
        self.id = id
        self.text = text
        self.votes = votes
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case text
        case votes
    }
}

/// What a thread's root shows. A deleted reply, or one that failed to send, doesn't count.
public struct ThreadSummary: ProtocolType, Equatable, Hashable {
    public static let protocolName = "ThreadSummary"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var replies: Int
    /// When the newest reply was sent, in Unix milliseconds.
    public var lastTS: Int64
    /// Who wrote the newest replies, by name, newest first: at most 3 people.
    public var lastSenders: [String]

    public init(replies: Int, lastTS: Int64, lastSenders: [String]) {
        self.replies = replies
        self.lastTS = lastTS
        self.lastSenders = lastSenders
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case replies
        case lastTS = "last_ts"
        case lastSenders = "last_senders"
    }
}

public struct EventsPage: ProtocolType, Equatable {
    public static let protocolName = "EventsPage"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// Newest first. A page may hold fewer than asked for, even none (to stay under 1 MiB, or because messages
    /// deleted for me are left out): only `before` and `after` say whether there is more.
    public var events: [Event]
    /// Cursor|null: always on the wire, null when there is no older event.
    public var before: Cursor?
    /// Cursor|null: the newest event of this page, for the next newer page; null when the page has the chat's
    /// newest event, and always for a thread's page.
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
    /// Messages I bookmarked, of every kind.
    public static let bookmarks = Self(rawValue: "bookmarks")
    public static let media = Self(rawValue: "media")
    public static let messages = Self(rawValue: "messages")
    public static let known: [Self] = [.chats, .inGroups, .bookmarks, .media, .messages]
}

/// One search over every chat on this Mac. Answers don't change by themselves: a changed notification doesn't
/// re-run a search.
public struct SearchParams: ProtocolType, Equatable {
    public static let protocolName = "SearchParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// What was typed: at most `maxTextScalars` Unicode scalars (not Characters); longer is -32602.
    public var text: String
    /// Left out (or []) is all five.
    public var sections: [SearchSectionName]?
    public var filters: SearchFilters?
    /// A page of bookmarks', media's or messages' next_cursor. It needs sections of exactly that one, and the same
    /// text and filters as the query that handed it out.
    public var cursor: String?
    /// Each section's most results. Left out: chats, in_groups and bookmarks 5, media 12, messages 20.
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
    /// MessageHits|null: messages I bookmarked, newest first. For empty text with no filters, the five newest
    /// bookmarks (newest bookmark first), with no next page.
    public var bookmarks: MessageHits?
    /// MessageHits|null: images and videos.
    public var media: MessageHits?
    /// MessageHits|null: every other kind.
    public var messages: MessageHits?
    /// InboxRow|null: only for empty text with no filters, the chat archived most recently.
    public var lastArchived: InboxRow?
    /// false while older messages are still being added.
    public var complete: Bool
    public var hint: SearchHint

    public init(chats: [InboxRow]? = nil, inGroups: [PersonHit]? = nil, bookmarks: MessageHits? = nil,
                media: MessageHits? = nil, messages: MessageHits? = nil, lastArchived: InboxRow? = nil,
                complete: Bool = true, hint: SearchHint = .none) {
        self.chats = chats
        self.inGroups = inGroups
        self.bookmarks = bookmarks
        self.media = media
        self.messages = messages
        self.lastArchived = lastArchived
        self.complete = complete
        self.hint = hint
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case chats
        case inGroups = "in_groups"
        case bookmarks
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
        bookmarks = try container.decode(MessageHits?.self, forKey: .bookmarks)
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
        try container.encode(bookmarks, forKey: .bookmarks)
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
    /// True when the message is a view-once attachment.
    public var viewOnce: Bool?

    public init(eventID: String, roomID: String, roomName: String, network: String, isDirect: Bool,
                place: ChatPlace = .inbox, sender: String, senderName: String, mine: Bool, ts: Int64, seq: Int64,
                kind: MessageHitKind = .text, snippet: String, ranges: [TextRange] = [], mediaPath: String = "",
                partial: Bool = false, viewOnce: Bool? = nil) {
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
        self.viewOnce = viewOnce
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
        case viewOnce = "view_once"
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
    /// What was typed, exactly: `*`, `_`, `#` and `<b>` are text, never formatting. At most
    /// `SendParams.maxTextBytes` bytes of UTF-8.
    public var text: String
    /// The text's formatting. The chat keeps the kinds its network keeps; the rest go as readable plain text.
    public var entities: [TextEntity]?
    public var replyTo: String?
    /// The root of the thread this goes in (where the chat has threads).
    public var threadRoot: String?
    /// Undo send: hold the message this long, queued, before it goes. One of `SendParams.holdValues`.
    public var holdMS: Int?
    /// Suppress link preview generation on this send when true.
    public var disableLinkPreview: Bool?

    /// The longest text the engine takes, in bytes of UTF-8.
    public static let maxTextBytes = 65_536
    /// The undo-send windows the engine takes, in milliseconds.
    public static let holdValues = [0, 750, 1000, 2000, 3000, 5000, 10000]

    public init(roomID: String, text: String, entities: [TextEntity]? = nil, replyTo: String? = nil,
                threadRoot: String? = nil, holdMS: Int? = nil, disableLinkPreview: Bool? = nil) {
        self.roomID = roomID
        self.text = text
        self.entities = entities
        self.replyTo = replyTo
        self.threadRoot = threadRoot
        self.holdMS = holdMS
        self.disableLinkPreview = disableLinkPreview
    }

    public init(roomID: String, body: String, entities: [TextEntity]? = nil, replyTo: String? = nil,
                threadRoot: String? = nil, holdMS: Int? = nil, disableLinkPreview: Bool? = nil) {
        self.init(roomID: roomID, text: body, entities: entities, replyTo: replyTo,
                  threadRoot: threadRoot, holdMS: holdMS, disableLinkPreview: disableLinkPreview)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case text
        case entities
        case replyTo = "reply_to"
        case threadRoot = "thread_root"
        case holdMS = "hold_ms"
        case disableLinkPreview = "disable_link_preview"
    }
}

public struct SendFileParams: ProtocolType, Equatable {
    public static let protocolName = "SendFileParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var path: String
    /// Taken and ignored: a file has no text.
    public var entities: [TextEntity]?
    public var replyTo: String?
    public var threadRoot: String?
    public var holdMS: Int?

    public init(roomID: String, path: String, entities: [TextEntity]? = nil, replyTo: String? = nil,
                threadRoot: String? = nil, holdMS: Int? = nil) {
        self.roomID = roomID
        self.path = path
        self.entities = entities
        self.replyTo = replyTo
        self.threadRoot = threadRoot
        self.holdMS = holdMS
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case path
        case entities
        case replyTo = "reply_to"
        case threadRoot = "thread_root"
        case holdMS = "hold_ms"
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

    public init(eventID: String) {
        self.eventID = eventID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
    }
}

public typealias SendResult = Sent

public struct MarkPlayedParams: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "MarkPlayedParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var eventID: String

    public init(roomID: String, eventID: String) {
        self.roomID = roomID
        self.eventID = eventID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case eventID = "event_id"
    }
}

public struct SendVoiceParams: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "SendVoiceParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var path: String
    public var durationMS: Int64
    public var waveform: [Int]?
    public var replyTo: String?

    public init(roomID: String, path: String, durationMS: Int64, waveform: [Int]? = nil,
                replyTo: String? = nil) {
        self.roomID = roomID
        self.path = path
        self.durationMS = durationMS
        self.waveform = waveform
        self.replyTo = replyTo
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case path
        case durationMS = "duration_ms"
        case waveform
        case replyTo = "reply_to"
    }
}

public struct SendLocationParams: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "SendLocationParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var latitude: Double
    public var longitude: Double
    public var label: String?
    public var replyTo: String?

    public init(roomID: String, latitude: Double, longitude: Double, label: String? = nil,
                replyTo: String? = nil) {
        self.roomID = roomID
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
        self.replyTo = replyTo
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case latitude
        case longitude
        case label
        case replyTo = "reply_to"
    }
}

public struct BridgedStickerRef: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "BridgedStickerRef"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String?
    public var packURL: String?
    public var id: String?

    public init(network: String? = nil, packURL: String? = nil, id: String? = nil) {
        self.network = network
        self.packURL = packURL
        self.id = id
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case packURL = "pack_url"
        case id
    }
}

public typealias BridgedStickerWire = BridgedStickerRef

public struct SendStickerParams: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "SendStickerParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var path: String?
    public var mediaURL: String?
    public var name: String?
    public var emoji: String?
    public var mimeType: String?
    public var bridgedSticker: BridgedStickerRef?
    public var replyTo: String?
    public var threadRoot: String?
    public var holdMS: Int?

    public init(roomID: String, path: String? = nil, mediaURL: String? = nil, name: String? = nil,
                emoji: String? = nil, mimeType: String? = nil, bridgedSticker: BridgedStickerRef? = nil,
                replyTo: String? = nil, threadRoot: String? = nil, holdMS: Int? = nil) {
        self.roomID = roomID
        self.path = path
        self.mediaURL = mediaURL
        self.name = name
        self.emoji = emoji
        self.mimeType = mimeType
        self.bridgedSticker = bridgedSticker
        self.replyTo = replyTo
        self.threadRoot = threadRoot
        self.holdMS = holdMS
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case path
        case mediaURL = "media_url"
        case name
        case emoji
        case mimeType = "mime_type"
        case bridgedSticker = "bridged_sticker"
        case replyTo = "reply_to"
        case threadRoot = "thread_root"
        case holdMS = "hold_ms"
    }
}

public struct SendGIFParams: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "SendGIFParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var path: String?
    public var mediaURL: String?
    public var caption: String?
    public var replyTo: String?
    public var threadRoot: String?
    public var holdMS: Int?

    public init(roomID: String, path: String? = nil, mediaURL: String? = nil, caption: String? = nil,
                replyTo: String? = nil, threadRoot: String? = nil, holdMS: Int? = nil) {
        self.roomID = roomID
        self.path = path
        self.mediaURL = mediaURL
        self.caption = caption
        self.replyTo = replyTo
        self.threadRoot = threadRoot
        self.holdMS = holdMS
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case path
        case mediaURL = "media_url"
        case caption
        case replyTo = "reply_to"
        case threadRoot = "thread_root"
        case holdMS = "hold_ms"
    }
}

public typealias MessageSendStickerParams = SendStickerParams
public typealias MessageSendGIFParams = SendGIFParams

public struct StickerItem: ProtocolType, Identifiable, Equatable, Hashable, Sendable {
    public static let protocolName = "StickerItem"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var id: String
    public var packID: String
    public var shortcode: String?
    public var name: String
    public var emoji: String?
    public var mediaURL: String
    public var mimeType: String
    public var width: Int?
    public var height: Int?
    public var usage: [String]
    public var bridgedSticker: BridgedStickerRef?

    public init(id: String, packID: String, shortcode: String? = nil, name: String, emoji: String? = nil,
                mediaURL: String, mimeType: String, width: Int? = nil, height: Int? = nil,
                usage: [String] = ["sticker"], bridgedSticker: BridgedStickerRef? = nil) {
        self.id = id
        self.packID = packID
        self.shortcode = shortcode
        self.name = name
        self.emoji = emoji
        self.mediaURL = mediaURL
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.usage = usage
        self.bridgedSticker = bridgedSticker
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case packID = "pack_id"
        case shortcode
        case name
        case emoji
        case mediaURL = "media_url"
        case mimeType = "mime_type"
        case width
        case height
        case usage
        case bridgedSticker = "bridged_sticker"
    }
}

public typealias StickerItemWire = StickerItem

public struct StickerPack: ProtocolType, Identifiable, Equatable, Hashable, Sendable {
    public static let protocolName = "StickerPack"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var id: String
    public var title: String
    public var source: String
    public var network: String?
    public var items: [StickerItem]

    public init(id: String, title: String, source: String, network: String? = nil, items: [StickerItem] = []) {
        self.id = id
        self.title = title
        self.source = source
        self.network = network
        self.items = items
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case title
        case source
        case network
        case items
    }
}

public typealias StickerPackWire = StickerPack

public struct ListStickersResult: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "ListStickersResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var packs: [StickerPack]
    public var recentGIFs: [StickerItem]

    public init(packs: [StickerPack] = [], recentGIFs: [StickerItem] = []) {
        self.packs = packs
        self.recentGIFs = recentGIFs
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case packs
        case recentGIFs = "recent_gifs"
    }
}

public typealias StickersListResult = ListStickersResult

public struct StickersListParams: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "StickersListParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var refreshBridgePacks: Bool?

    public init(refreshBridgePacks: Bool? = nil) {
        self.refreshBridgePacks = refreshBridgePacks
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case refreshBridgePacks = "refresh_bridge_packs"
    }
}

public struct ImportStickerParams: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "ImportStickerParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var path: String
    public var shortcode: String?
    public var name: String?
    public var emoji: String?
    public var usage: [String]?

    public init(path: String, shortcode: String? = nil, name: String? = nil, emoji: String? = nil,
                usage: [String]? = nil) {
        self.path = path
        self.shortcode = shortcode
        self.name = name
        self.emoji = emoji
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case shortcode
        case name
        case emoji
        case usage
    }
}

public typealias StickersImportParams = ImportStickerParams
public typealias StickersImportResult = StickerItem

// MARK: - Typing, Reply Privately (protocol 5)

/// room.setTyping: I am typing (true: at the first change and every `conventions.typing_repeat_ms` while the text
/// keeps changing), or I stopped (false).
public struct TypingParams: ProtocolType, Equatable {
    public static let protocolName = "TypingParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var typing: Bool

    public init(roomID: String, typing: Bool) {
        self.roomID = roomID
        self.typing = typing
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case typing
    }
}

/// room.directChat: the one-to-one chat with `userID`, a person in the group `roomID`, or on `network`.
public struct DirectChatParams: ProtocolType, Equatable {
    public static let protocolName = "DirectChatParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String?
    public var network: String?
    public var accountID: String?
    public var userID: String

    public init(roomID: String? = nil, network: String? = nil, accountID: String? = nil, userID: String) {
        self.roomID = roomID
        self.network = network
        self.accountID = accountID
        self.userID = userID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case network
        case accountID = "account_id"
        case userID = "user_id"
    }
}

/// A chat, as room.directChat answers.
public struct RoomResult: ProtocolType, Equatable {
    public static let protocolName = "RoomResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String

    public init(roomID: String) { self.roomID = roomID }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
    }
}

// MARK: - Formatting, features and message actions (protocol 4)

/// One formatting range of a message's text. Offsets and lengths count UTF-16 code units, as NSString and NSRange
/// count them, never Characters.
public struct TextEntity: ProtocolType, Equatable, Hashable {
    public static let protocolName = "TextEntity"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }

    /// TextEntity.type, and ChatFeatures.formatting.
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case bold, italic, strikethrough, code, pre, blockquote
        case bulletList = "bullet_list"
        case orderedList = "ordered_list"
        case link, mention, spoiler

        /// A block takes whole lines: a code block, a quote or a list.
        public var isBlock: Bool {
            switch self {
            case .pre, .blockquote, .bulletList, .orderedList: true
            default: false
            }
        }
    }

    public var kind: Kind
    /// Where it starts, in UTF-16 code units.
    public var offset: Int
    /// UTF-16 code units, at least 1.
    public var length: Int
    /// For a link: an http, https or mailto address. Left out of the wire when nil or empty.
    public var url: String?
    /// For a mention: a member's Matrix ID, or "@room". Left out of the wire when nil or empty.
    public var userID: String?

    public init(kind: Kind, offset: Int, length: Int, url: String? = nil, userID: String? = nil) {
        self.kind = kind
        self.offset = offset
        self.length = length
        self.url = url
        self.userID = userID
    }

    /// The range, as NSString counts.
    public var range: NSRange { NSRange(location: offset, length: length) }

    /// The order ranges are kept in: by where they start, the longer first, then by kind.
    public static func precedes(_ lhs: TextEntity, _ rhs: TextEntity) -> Bool {
        if lhs.offset != rhs.offset { return lhs.offset < rhs.offset }
        if lhs.length != rhs.length { return lhs.length > rhs.length }
        let order = Kind.allCases
        let left = order.firstIndex(of: lhs.kind) ?? 0
        let right = order.firstIndex(of: rhs.kind) ?? 0
        if left != right { return left < right }
        return (lhs.url ?? "", lhs.userID ?? "") < (rhs.url ?? "", rhs.userID ?? "")
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind = "type"
        case offset
        case length
        case url
        case userID = "user_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        offset = try container.decode(Int.self, forKey: .offset)
        length = try container.decode(Int.self, forKey: .length)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(offset, forKey: .offset)
        try container.encode(length, forKey: .length)
        // The engine leaves these out when empty, and refuses neither form; "" is never sent.
        if let url, !url.isEmpty { try container.encode(url, forKey: .url) }
        if let userID, !userID.isEmpty { try container.encode(userID, forKey: .userID) }
    }
}

/// ChatFeatures.source: where a chat's features came from.
public struct FeatureSource: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The network was asked, because the chat had none stored.
    public static let network = Self(rawValue: "network")
    /// The chat's stored features, as its bridge wrote them.
    public static let stored = Self(rawValue: "stored")
    /// Neither: only send, reply and Delete for Me are offered.
    public static let none = Self(rawValue: "none")
    public static let known: [Self] = [.network, .stored, .none]
}

public struct FileKindFeatures: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "FileKindFeatures"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var supported: Bool
    public var mimeTypes: [String]?
    public var caption: Bool
    public var maxCaptionLength: Int?
    public var maxSize: Int64?
    public var maxDurationSec: Int?

    public init(supported: Bool, mimeTypes: [String]? = nil, caption: Bool = false,
                maxCaptionLength: Int? = nil, maxSize: Int64? = nil, maxDurationSec: Int? = nil) {
        self.supported = supported
        self.mimeTypes = mimeTypes
        self.caption = caption
        self.maxCaptionLength = maxCaptionLength
        self.maxSize = maxSize
        self.maxDurationSec = maxDurationSec
    }

    public init?(from mediaCap: MediaCapFeature) {
        guard mediaCap.supported else { return nil }
        self.init(
            supported: true,
            mimeTypes: mediaCap.mimeTypes.isEmpty ? nil : mediaCap.mimeTypes,
            caption: mediaCap.captions,
            maxCaptionLength: mediaCap.maxCaptionLength,
            maxSize: mediaCap.maxSize
        )
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case supported
        case mimeTypes = "mime_types"
        case caption
        case maxCaptionLength = "max_caption_length"
        case maxSize = "max_size"
        case maxDurationSec = "max_duration_sec"
    }
}

public struct MediaCapFeature: ProtocolType, Equatable, Hashable, Sendable {
    public static let protocolName = "MediaCapFeature"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var supported: Bool
    public var mimeTypes: [String]
    public var captions: Bool
    public var maxCaptionLength: Int?
    public var maxSize: Int64?

    public static let unsupported = MediaCapFeature(supported: false, mimeTypes: [], captions: false, maxCaptionLength: nil, maxSize: nil)

    public init(supported: Bool = false, mimeTypes: [String] = [], captions: Bool = false,
                maxCaptionLength: Int? = nil, maxSize: Int64? = nil) {
        self.supported = supported
        self.mimeTypes = mimeTypes
        self.captions = captions
        self.maxCaptionLength = maxCaptionLength
        self.maxSize = maxSize
    }

    public init(from fileKind: FileKindFeatures?) {
        guard let fileKind, fileKind.supported else {
            self = .unsupported
            return
        }
        self.init(
            supported: true,
            mimeTypes: fileKind.mimeTypes ?? [],
            captions: fileKind.caption,
            maxCaptionLength: fileKind.maxCaptionLength,
            maxSize: fileKind.maxSize
        )
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case supported
        case mimeTypes = "mime_types"
        case captions
        case maxCaptionLength = "max_caption_length"
        case maxSize = "max_size"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supported = try container.decode(Bool.self, forKey: .supported)
        mimeTypes = try container.decodeIfPresent([String].self, forKey: .mimeTypes) ?? []
        captions = try container.decodeIfPresent(Bool.self, forKey: .captions) ?? false
        maxCaptionLength = try container.decodeIfPresent(Int.self, forKey: .maxCaptionLength)
        maxSize = try container.decodeIfPresent(Int64.self, forKey: .maxSize)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(supported, forKey: .supported)
        try container.encode(mimeTypes, forKey: .mimeTypes)
        try container.encode(captions, forKey: .captions)
        try container.encodeIfPresent(maxCaptionLength, forKey: .maxCaptionLength)
        try container.encodeIfPresent(maxSize, forKey: .maxSize)
    }
}

public typealias MediaCapFeatureWire = MediaCapFeature
public typealias RoomFeaturesResult = ChatFeatures

/// What a person can do in one chat, as its network's bridge says (room.features). A greyed action says why from
/// these, in Courier's words (MessageActions).
public struct ChatFeatures: ProtocolType, Equatable {
    public static let protocolName = "ChatFeatures"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// A plain reply.
    public var reply: Bool
    /// A reply in a thread: Reply in Thread, and the thread pane.
    public var thread: Bool
    /// The chat has threads and no plain replies (Slack, WhatsApp community announcement groups): Reply is Reply in
    /// Thread.
    public var replyIsThread: Bool
    /// My text messages can be edited.
    public var edit: Bool
    /// How old a message may be to be edited, in milliseconds; 0 is no limit.
    public var editMaxAgeMS: Int64
    /// How many times one message may be edited; 0 is no limit.
    public var editMaxCount: Int
    /// My messages can be deleted for everyone. False where the network only deletes for me (Google Messages).
    public var unsend: Bool
    /// How old a message may be to be unsent, in milliseconds; 0 is no limit.
    public var unsendMaxAgeMS: Int64
    /// Delete for Me also deletes it from the phone's own app (Google Messages).
    public var deleteReachesPhone: Bool
    /// The network leaves no "deleted" placeholder (Telegram).
    public var hideDeletedPlaceholder: Bool
    /// PollFeatures|null: nil is no polls.
    public var poll: PollFeatures?
    /// DisappearingFeatures|null: nil is no disappearing timer.
    public var disappearing: DisappearingFeatures?
    /// DisappearingTimer|null: the chat's timer now, which new messages get; nil when it is off.
    public var currentTimer: DisappearingTimer?
    /// The formatting the chat keeps. Other kinds go as plain text; [] keeps none. A kind this app doesn't know is
    /// left out.
    public var formatting: [TextEntity.Kind]
    /// @room reaches everyone (Slack). Elsewhere it is plain text.
    public var mentionRoom: Bool
    /// The longest text the engine sends, in bytes of UTF-8 (not characters). See `fits(text:)`.
    public var maxTextLength: Int
    public var source: FeatureSource
    public var canSetName: Bool
    public var canSetTopic: Bool
    public var canSetAvatar: Bool
    public var canInvite: Bool
    public var canKick: Bool
    public var canSetAdmin: Bool
    public var canLeave: Bool
    public var canDelete: Bool
    /// Deleting this group chat on its network also leaves the group (WhatsApp).
    public var deleteLeavesGroup: Bool
    public var imageFeatures: FileKindFeatures?
    public var videoFeatures: FileKindFeatures?
    public var audioFeatures: FileKindFeatures?
    public var voiceFeatures: FileKindFeatures?
    public var fileFeatures: FileKindFeatures?
    public var gifFeatures: FileKindFeatures?
    public var stickerFeatures: FileKindFeatures?
    public var sticker: MediaCapFeature {
        get { MediaCapFeature(from: stickerFeatures) }
        set {
            let mimes = newValue.mimeTypes.isEmpty ? ["image/png", "image/webp"] : newValue.mimeTypes
            stickerFeatures = newValue.supported
                ? FileKindFeatures(
                    supported: true,
                    mimeTypes: mimes,
                    caption: newValue.captions,
                    maxCaptionLength: newValue.maxCaptionLength,
                    maxSize: newValue.maxSize
                )
                : nil
        }
    }
    public var gif: MediaCapFeature {
        get { MediaCapFeature(from: gifFeatures) }
        set {
            let mimes = newValue.mimeTypes.isEmpty ? ["image/gif", "video/mp4"] : newValue.mimeTypes
            gifFeatures = newValue.supported
                ? FileKindFeatures(
                    supported: true,
                    mimeTypes: mimes,
                    caption: newValue.captions,
                    maxCaptionLength: newValue.maxCaptionLength,
                    maxSize: newValue.maxSize
                )
                : nil
        }
    }
    public var locationSupported: Bool
    public var linkPreviewsSupported: Bool

    /// A chat with nothing stored and no network to ask: only send, reply and Delete for Me.
    public static let noFeatures = ChatFeatures(reply: true, source: .none)
    public static let conservative = noFeatures

    public init(reply: Bool = false, thread: Bool = false, replyIsThread: Bool = false, edit: Bool = false,
                editMaxAgeMS: Int64 = 0, editMaxCount: Int = 0, unsend: Bool = false, unsendMaxAgeMS: Int64 = 0,
                deleteReachesPhone: Bool = false, hideDeletedPlaceholder: Bool = false, poll: PollFeatures? = nil,
                disappearing: DisappearingFeatures? = nil, currentTimer: DisappearingTimer? = nil,
                formatting: [TextEntity.Kind] = [], mentionRoom: Bool = false, maxTextLength: Int = 0,
                source: FeatureSource, canSetName: Bool = false, canSetTopic: Bool = false,
                canSetAvatar: Bool = false, canInvite: Bool = false, canKick: Bool = false,
                canSetAdmin: Bool = false, canLeave: Bool = false, canDelete: Bool = false,
                deleteLeavesGroup: Bool = false, imageFeatures: FileKindFeatures? = nil,
                videoFeatures: FileKindFeatures? = nil, audioFeatures: FileKindFeatures? = nil,
                voiceFeatures: FileKindFeatures? = nil, fileFeatures: FileKindFeatures? = nil,
                gifFeatures: FileKindFeatures? = nil, stickerFeatures: FileKindFeatures? = nil,
                locationSupported: Bool = false, linkPreviewsSupported: Bool = false) {
        self.reply = reply
        self.thread = thread
        self.replyIsThread = replyIsThread
        self.edit = edit
        self.editMaxAgeMS = editMaxAgeMS
        self.editMaxCount = editMaxCount
        self.unsend = unsend
        self.unsendMaxAgeMS = unsendMaxAgeMS
        self.deleteReachesPhone = deleteReachesPhone
        self.hideDeletedPlaceholder = hideDeletedPlaceholder
        self.poll = poll
        self.disappearing = disappearing
        self.currentTimer = currentTimer
        self.formatting = formatting
        self.mentionRoom = mentionRoom
        self.maxTextLength = maxTextLength
        self.source = source
        self.canSetName = canSetName
        self.canSetTopic = canSetTopic
        self.canSetAvatar = canSetAvatar
        self.canInvite = canInvite
        self.canKick = canKick
        self.canSetAdmin = canSetAdmin
        self.canLeave = canLeave
        self.canDelete = canDelete
        self.deleteLeavesGroup = deleteLeavesGroup
        self.imageFeatures = imageFeatures
        self.videoFeatures = videoFeatures
        self.audioFeatures = audioFeatures
        self.voiceFeatures = voiceFeatures
        self.fileFeatures = fileFeatures
        self.gifFeatures = gifFeatures
        self.stickerFeatures = stickerFeatures
        self.locationSupported = locationSupported
        self.linkPreviewsSupported = linkPreviewsSupported
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case reply
        case thread
        case replyIsThread = "reply_is_thread"
        case edit
        case editMaxAgeMS = "edit_max_age_ms"
        case editMaxCount = "edit_max_count"
        case unsend
        case unsendMaxAgeMS = "unsend_max_age_ms"
        case deleteReachesPhone = "delete_reaches_phone"
        case hideDeletedPlaceholder = "hide_deleted_placeholder"
        case poll
        case disappearing
        case currentTimer = "current_timer"
        case formatting
        case mentionRoom = "mention_room"
        case maxTextLength = "max_text_length"
        case source
        case canSetName = "can_set_name"
        case canSetTopic = "can_set_topic"
        case canSetAvatar = "can_set_avatar"
        case canInvite = "can_invite"
        case canKick = "can_kick"
        case canSetAdmin = "can_set_admin"
        case canLeave = "can_leave"
        case canDelete = "can_delete"
        case deleteLeavesGroup = "delete_leaves_group"
        case imageFeatures = "image_features"
        case videoFeatures = "video_features"
        case audioFeatures = "audio_features"
        case voiceFeatures = "voice_features"
        case fileFeatures = "file_features"
        case gifFeatures = "gif_features"
        case stickerFeatures = "sticker_features"
        case sticker
        case gif
        case locationSupported = "location_supported"
        case linkPreviewsSupported = "link_previews_supported"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(Bool.self, forKey: .reply)
        thread = try container.decode(Bool.self, forKey: .thread)
        replyIsThread = try container.decode(Bool.self, forKey: .replyIsThread)
        edit = try container.decode(Bool.self, forKey: .edit)
        editMaxAgeMS = try container.decode(Int64.self, forKey: .editMaxAgeMS)
        editMaxCount = try container.decode(Int.self, forKey: .editMaxCount)
        unsend = try container.decode(Bool.self, forKey: .unsend)
        unsendMaxAgeMS = try container.decode(Int64.self, forKey: .unsendMaxAgeMS)
        deleteReachesPhone = try container.decode(Bool.self, forKey: .deleteReachesPhone)
        hideDeletedPlaceholder = try container.decode(Bool.self, forKey: .hideDeletedPlaceholder)
        // Every T|null key must be there.
        poll = try container.decode(PollFeatures?.self, forKey: .poll)
        disappearing = try container.decode(DisappearingFeatures?.self, forKey: .disappearing)
        currentTimer = try container.decode(DisappearingTimer?.self, forKey: .currentTimer)
        // An open list: a kind a newer engine keeps that this app can't make is simply not offered.
        formatting = try container.decode([String].self, forKey: .formatting).compactMap(TextEntity.Kind.init(rawValue:))
        mentionRoom = try container.decode(Bool.self, forKey: .mentionRoom)
        maxTextLength = try container.decode(Int.self, forKey: .maxTextLength)
        source = try container.decode(FeatureSource.self, forKey: .source)
        canSetName = try container.decodeIfPresent(Bool.self, forKey: .canSetName) ?? false
        canSetTopic = try container.decodeIfPresent(Bool.self, forKey: .canSetTopic) ?? false
        canSetAvatar = try container.decodeIfPresent(Bool.self, forKey: .canSetAvatar) ?? false
        canInvite = try container.decodeIfPresent(Bool.self, forKey: .canInvite) ?? false
        canKick = try container.decodeIfPresent(Bool.self, forKey: .canKick) ?? false
        canSetAdmin = try container.decodeIfPresent(Bool.self, forKey: .canSetAdmin) ?? false
        canLeave = try container.decodeIfPresent(Bool.self, forKey: .canLeave) ?? false
        canDelete = try container.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
        deleteLeavesGroup = try container.decodeIfPresent(Bool.self, forKey: .deleteLeavesGroup) ?? false
        imageFeatures = try container.decodeIfPresent(FileKindFeatures.self, forKey: .imageFeatures)
        videoFeatures = try container.decodeIfPresent(FileKindFeatures.self, forKey: .videoFeatures)
        audioFeatures = try container.decodeIfPresent(FileKindFeatures.self, forKey: .audioFeatures)
        voiceFeatures = try container.decodeIfPresent(FileKindFeatures.self, forKey: .voiceFeatures)
        fileFeatures = try container.decodeIfPresent(FileKindFeatures.self, forKey: .fileFeatures)
        let decodedGifFeatures = try container.decodeIfPresent(FileKindFeatures.self, forKey: .gifFeatures)
        let decodedStickerFeatures = try container.decodeIfPresent(FileKindFeatures.self, forKey: .stickerFeatures)
        let decodedSticker = try container.decodeIfPresent(MediaCapFeature.self, forKey: .sticker)
        let decodedGIF = try container.decodeIfPresent(MediaCapFeature.self, forKey: .gif)
        gifFeatures = decodedGifFeatures ?? decodedGIF.flatMap(FileKindFeatures.init(from:))
        stickerFeatures = decodedStickerFeatures ?? decodedSticker.flatMap(FileKindFeatures.init(from:))
        locationSupported = try container.decodeIfPresent(Bool.self, forKey: .locationSupported) ?? false
        linkPreviewsSupported = try container.decodeIfPresent(Bool.self, forKey: .linkPreviewsSupported) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reply, forKey: .reply)
        try container.encode(thread, forKey: .thread)
        try container.encode(replyIsThread, forKey: .replyIsThread)
        try container.encode(edit, forKey: .edit)
        try container.encode(editMaxAgeMS, forKey: .editMaxAgeMS)
        try container.encode(editMaxCount, forKey: .editMaxCount)
        try container.encode(unsend, forKey: .unsend)
        try container.encode(unsendMaxAgeMS, forKey: .unsendMaxAgeMS)
        try container.encode(deleteReachesPhone, forKey: .deleteReachesPhone)
        try container.encode(hideDeletedPlaceholder, forKey: .hideDeletedPlaceholder)
        // null, not left out
        try container.encode(poll, forKey: .poll)
        try container.encode(disappearing, forKey: .disappearing)
        try container.encode(currentTimer, forKey: .currentTimer)
        try container.encode(formatting, forKey: .formatting)
        try container.encode(mentionRoom, forKey: .mentionRoom)
        try container.encode(maxTextLength, forKey: .maxTextLength)
        try container.encode(source, forKey: .source)
        try container.encode(canSetName, forKey: .canSetName)
        try container.encode(canSetTopic, forKey: .canSetTopic)
        try container.encode(canSetAvatar, forKey: .canSetAvatar)
        try container.encode(canInvite, forKey: .canInvite)
        try container.encode(canKick, forKey: .canKick)
        try container.encode(canSetAdmin, forKey: .canSetAdmin)
        try container.encode(canLeave, forKey: .canLeave)
        try container.encode(canDelete, forKey: .canDelete)
        try container.encode(deleteLeavesGroup, forKey: .deleteLeavesGroup)
        try container.encodeIfPresent(imageFeatures, forKey: .imageFeatures)
        try container.encodeIfPresent(videoFeatures, forKey: .videoFeatures)
        try container.encodeIfPresent(audioFeatures, forKey: .audioFeatures)
        try container.encodeIfPresent(voiceFeatures, forKey: .voiceFeatures)
        try container.encodeIfPresent(fileFeatures, forKey: .fileFeatures)
        try container.encodeIfPresent(gifFeatures, forKey: .gifFeatures)
        try container.encodeIfPresent(stickerFeatures, forKey: .stickerFeatures)
        try container.encode(sticker, forKey: .sticker)
        try container.encode(gif, forKey: .gif)
        try container.encode(locationSupported, forKey: .locationSupported)
        try container.encode(linkPreviewsSupported, forKey: .linkPreviewsSupported)
    }
}

/// What a chat allows in a new poll.
public struct PollFeatures: ProtocolType, Equatable, Hashable {
    public static let protocolName = "PollFeatures"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var maxOptions: Int
    /// Characters.
    public var optionMaxLength: Int

    public init(maxOptions: Int, optionMaxLength: Int) {
        self.maxOptions = maxOptions
        self.optionMaxLength = optionMaxLength
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case maxOptions = "max_options"
        case optionMaxLength = "option_max_length"
    }
}

/// When a disappearing message's timer starts. DisappearingParams also takes `off`.
public struct DisappearingType: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let afterSend = Self(rawValue: "after_send")
    public static let afterRead = Self(rawValue: "after_read")
    /// No timer: DisappearingParams only, with timer_ms 0.
    public static let off = Self(rawValue: "")
    public static let known: [Self] = [.afterSend, .afterRead]
    /// The values room.setDisappearing takes.
    public static let settable: [Self] = [.off, .afterSend, .afterRead]
}

/// The disappearing-message timer a chat takes.
public struct DisappearingFeatures: ProtocolType, Equatable, Hashable {
    public static let protocolName = "DisappearingFeatures"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var type: DisappearingType
    /// The lengths offered, besides off, in milliseconds.
    public var timersMS: [Int64]

    public init(type: DisappearingType, timersMS: [Int64]) {
        self.type = type
        self.timersMS = timersMS
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case timersMS = "timers_ms"
    }
}

public struct DisappearingTimer: ProtocolType, Equatable, Hashable {
    public static let protocolName = "DisappearingTimer"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var type: DisappearingType
    public var timerMS: Int64

    public init(type: DisappearingType, timerMS: Int64) {
        self.type = type
        self.timerMS = timerMS
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case timerMS = "timer_ms"
    }
}

/// The people in a chat whose name matches what was typed after @.
public struct MembersParams: ProtocolType, Equatable {
    public static let protocolName = "MembersParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    /// Each word must begin a word of the name, folded as search folds it. "" matches everyone.
    public var query: String
    /// 1 to 50; 20 when left out.
    public var limit: Int?

    public init(roomID: String, query: String, limit: Int? = nil) {
        self.roomID = roomID
        self.query = query
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case query
        case limit
    }
}

public struct MembersResult: ProtocolType, Equatable {
    public static let protocolName = "MembersResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// By name.
    public var members: [Member]

    public init(members: [Member]) { self.members = members }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case members
    }
}

/// Someone in the chat on its network: not me, nor the bridge's bot, nor anyone who left.
public struct Member: ProtocolType, Equatable, Hashable, Identifiable {
    public static let protocolName = "Member"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// What a mention's user_id names.
    public var userID: String
    public var name: String
    public var avatarPath: String
    public var powerLevel: Int
    public var isAdmin: Bool
    public var identifiers: [String]
    public var tz: String
    public var isBot: Bool

    public var id: String { userID }

    public init(userID: String, name: String, avatarPath: String = "", powerLevel: Int = 0, isAdmin: Bool = false,
                identifiers: [String] = [], tz: String = "", isBot: Bool = false) {
        self.userID = userID
        self.name = name
        self.avatarPath = avatarPath
        self.powerLevel = powerLevel
        self.isAdmin = isAdmin
        self.identifiers = identifiers
        self.tz = tz
        self.isBot = isBot
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case userID = "user_id"
        case name
        case avatarPath = "avatar_path"
        case powerLevel = "power_level"
        case isAdmin = "is_admin"
        case identifiers
        case tz
        case isBot = "is_bot"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        avatarPath = try container.decode(String.self, forKey: .avatarPath)
        powerLevel = try container.decodeIfPresent(Int.self, forKey: .powerLevel) ?? 0
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        identifiers = try container.decodeIfPresent([String].self, forKey: .identifiers) ?? []
        tz = try container.decodeIfPresent(String.self, forKey: .tz) ?? ""
        isBot = try container.decodeIfPresent(Bool.self, forKey: .isBot) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(name, forKey: .name)
        try container.encode(avatarPath, forKey: .avatarPath)
        try container.encode(powerLevel, forKey: .powerLevel)
        try container.encode(isAdmin, forKey: .isAdmin)
        try container.encode(identifiers, forKey: .identifiers)
        try container.encode(tz, forKey: .tz)
        try container.encode(isBot, forKey: .isBot)
    }
}

public struct DisappearingParams: ProtocolType, Equatable {
    public static let protocolName = "DisappearingParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    /// The chat's DisappearingFeatures.type, or `off` (with timer_ms 0).
    public var type: DisappearingType
    /// One of the chat's timers_ms, or 0.
    public var timerMS: Int64

    public init(roomID: String, type: DisappearingType, timerMS: Int64) {
        self.roomID = roomID
        self.type = type
        self.timerMS = timerMS
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case type
        case timerMS = "timer_ms"
    }
}

public struct EditParams: ProtocolType, Equatable {
    public static let protocolName = "EditParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// A text message of mine.
    public var eventID: String
    /// The new text, as SendParams.text.
    public var text: String
    public var entities: [TextEntity]?

    public init(eventID: String, text: String, entities: [TextEntity]? = nil) {
        self.eventID = eventID
        self.text = text
        self.entities = entities
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
        case text
        case entities
    }
}

public struct ForwardParams: ProtocolType, Equatable {
    public static let protocolName = "ForwardParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var eventID: String
    /// 1 to `maxRooms` chats; a chat named twice gets one copy.
    public var roomIDs: [String]

    public static let maxRooms = 20

    public init(eventID: String, roomIDs: [String]) {
        self.eventID = eventID
        self.roomIDs = roomIDs
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
        case roomIDs = "room_ids"
    }
}

/// Each chat named, once: sent a copy, or not.
public struct ForwardResult: ProtocolType, Equatable {
    public static let protocolName = "ForwardResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var sent: [Forwarded]
    public var failed: [ForwardFailure]

    public init(sent: [Forwarded], failed: [ForwardFailure]) {
        self.sent = sent
        self.failed = failed
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case sent
        case failed
    }
}

public struct Forwarded: ProtocolType, Equatable, Hashable {
    public static let protocolName = "Forwarded"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    /// The copy, in that chat.
    public var eventID: String

    public init(roomID: String, eventID: String) {
        self.roomID = roomID
        self.eventID = eventID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case eventID = "event_id"
    }
}

public struct ForwardFailure: ProtocolType, Equatable, Hashable {
    public static let protocolName = "ForwardFailure"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    /// The error that chat would have given alone (`RPCErrorCode(number:)` reads it).
    public var code: Int

    public init(roomID: String, code: Int) {
        self.roomID = roomID
        self.code = code
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case code
    }
}

/// What was typed, given back for the composer (message.undo).
public struct Draft: ProtocolType, Equatable {
    public static let protocolName = "Draft"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var text: String
    public var entities: [TextEntity]
    /// string|null.
    public var replyTo: String?
    /// string|null.
    public var threadRoot: String?

    public init(text: String, entities: [TextEntity], replyTo: String?, threadRoot: String?) {
        self.text = text
        self.entities = entities
        self.replyTo = replyTo
        self.threadRoot = threadRoot
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case entities
        case replyTo = "reply_to"
        case threadRoot = "thread_root"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        entities = try container.decode([TextEntity].self, forKey: .entities)
        replyTo = try container.decode(String?.self, forKey: .replyTo) // the key must be there
        threadRoot = try container.decode(String?.self, forKey: .threadRoot) // the key must be there
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(entities, forKey: .entities)
        try container.encode(replyTo, forKey: .replyTo) // null, not left out
        try container.encode(threadRoot, forKey: .threadRoot) // null, not left out
    }
}

/// A chat, or (left out) every chat.
public struct RoomOptionalParams: ProtocolType, Equatable {
    public static let protocolName = "RoomOptionalParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String?

    public init(roomID: String? = nil) { self.roomID = roomID }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
    }
}

public struct BookmarkParams: ProtocolType, Equatable {
    public static let protocolName = "BookmarkParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var eventID: String
    /// Bookmark it, or take its bookmark away.
    public var on: Bool

    public init(eventID: String, on: Bool) {
        self.eventID = eventID
        self.on = on
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
        case on
    }
}

public struct HistoryResult: ProtocolType, Equatable {
    public static let protocolName = "HistoryResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// The message as first sent, then each edit of it that wasn't refused or deleted, oldest first.
    public var versions: [Version]

    public init(versions: [Version]) { self.versions = versions }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case versions
    }
}

/// One version of an edited message.
public struct Version: ProtocolType, Equatable, Hashable {
    public static let protocolName = "Version"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var body: String
    /// Its HTML; "" when it is plain.
    public var formattedBody: String
    public var ts: Int64

    public init(body: String, formattedBody: String = "", ts: Int64) {
        self.body = body
        self.formattedBody = formattedBody
        self.ts = ts
    }

    /// The version as text and ranges.
    public var rich: RichText { RichTextHTML.parse(html: formattedBody, fallback: body) }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case body
        case formattedBody = "formatted_body"
        case ts
    }
}

/// ScheduleParams.condition and ScheduledMessage.condition.
public struct ScheduleCondition: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A message from someone else in the chat after it was set (or last changed) cancels it.
    public static let ifNoReply = Self(rawValue: "if_no_reply")
    public static let always = Self(rawValue: "always")
    public static let known: [Self] = [.ifNoReply, .always]
}

/// ScheduledMessage.state.
public struct ScheduledState: OpenValues {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let waiting = Self(rawValue: "waiting")
    /// Someone replied first (if_no_reply).
    public static let canceled = Self(rawValue: "canceled")
    /// Due over an hour before the engine could send it: it waits for Send Now, a new time or Delete.
    public static let missed = Self(rawValue: "missed")
    public static let known: [Self] = [.waiting, .canceled, .missed]
}

public struct ScheduleParams: ProtocolType, Equatable {
    public static let protocolName = "ScheduleParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var text: String
    public var entities: [TextEntity]?
    public var replyTo: String?
    public var threadRoot: String?
    /// Unix milliseconds: after now and at most 5 years ahead.
    public var dueAt: Int64
    public var condition: ScheduleCondition
    public var disableLinkPreview: Bool?

    public init(roomID: String, text: String, entities: [TextEntity]? = nil, replyTo: String? = nil,
                threadRoot: String? = nil, dueAt: Int64, condition: ScheduleCondition,
                disableLinkPreview: Bool? = nil) {
        self.roomID = roomID
        self.text = text
        self.entities = entities
        self.replyTo = replyTo
        self.threadRoot = threadRoot
        self.dueAt = dueAt
        self.condition = condition
        self.disableLinkPreview = disableLinkPreview
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case text
        case entities
        case replyTo = "reply_to"
        case threadRoot = "thread_root"
        case dueAt = "due_at"
        case condition
        case disableLinkPreview = "disable_link_preview"
    }
}

/// A message scheduled to be sent later. It is in no chat's timeline, nor in search, until it is sent.
public struct ScheduledMessage: ProtocolType, Equatable, Identifiable {
    public static let protocolName = "ScheduledMessage"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var outboxID: Int64
    public var roomID: String
    /// As typed.
    public var text: String
    public var entities: [TextEntity]
    /// string|null.
    public var replyTo: String?
    /// string|null.
    public var threadRoot: String?
    public var dueAt: Int64
    public var condition: ScheduleCondition
    public var state: ScheduledState
    /// When it was scheduled or last changed, in Unix milliseconds.
    public var setAt: Int64

    public var id: Int64 { outboxID }

    public init(outboxID: Int64, roomID: String, text: String, entities: [TextEntity] = [], replyTo: String? = nil,
                threadRoot: String? = nil, dueAt: Int64, condition: ScheduleCondition, state: ScheduledState,
                setAt: Int64) {
        self.outboxID = outboxID
        self.roomID = roomID
        self.text = text
        self.entities = entities
        self.replyTo = replyTo
        self.threadRoot = threadRoot
        self.dueAt = dueAt
        self.condition = condition
        self.state = state
        self.setAt = setAt
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case outboxID = "outbox_id"
        case roomID = "room_id"
        case text
        case entities
        case replyTo = "reply_to"
        case threadRoot = "thread_root"
        case dueAt = "due_at"
        case condition
        case state
        case setAt = "set_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outboxID = try container.decode(Int64.self, forKey: .outboxID)
        roomID = try container.decode(String.self, forKey: .roomID)
        text = try container.decode(String.self, forKey: .text)
        entities = try container.decode([TextEntity].self, forKey: .entities)
        replyTo = try container.decode(String?.self, forKey: .replyTo) // the key must be there
        threadRoot = try container.decode(String?.self, forKey: .threadRoot) // the key must be there
        dueAt = try container.decode(Int64.self, forKey: .dueAt)
        condition = try container.decode(ScheduleCondition.self, forKey: .condition)
        state = try container.decode(ScheduledState.self, forKey: .state)
        setAt = try container.decode(Int64.self, forKey: .setAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outboxID, forKey: .outboxID)
        try container.encode(roomID, forKey: .roomID)
        try container.encode(text, forKey: .text)
        try container.encode(entities, forKey: .entities)
        try container.encode(replyTo, forKey: .replyTo) // null, not left out
        try container.encode(threadRoot, forKey: .threadRoot) // null, not left out
        try container.encode(dueAt, forKey: .dueAt)
        try container.encode(condition, forKey: .condition)
        try container.encode(state, forKey: .state)
        try container.encode(setAt, forKey: .setAt)
    }
}

public struct ScheduledResult: ProtocolType, Equatable {
    public static let protocolName = "ScheduledResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// Soonest first, in any state: at most what fits in 1 MiB, the soonest.
    public var scheduled: [ScheduledMessage]

    public init(scheduled: [ScheduledMessage]) { self.scheduled = scheduled }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case scheduled
    }
}

/// Changes what is given. Any change makes it waiting again; a canceled or missed message needs a new due_at.
public struct ScheduledUpdateParams: ProtocolType, Equatable {
    public static let protocolName = "ScheduledUpdateParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var outboxID: Int64
    public var dueAt: Int64?
    /// A new text, with `entities` its ranges.
    public var text: String?
    /// Without text: new ranges for the text it has.
    public var entities: [TextEntity]?
    public var condition: ScheduleCondition?

    public init(outboxID: Int64, dueAt: Int64? = nil, text: String? = nil, entities: [TextEntity]? = nil,
                condition: ScheduleCondition? = nil) {
        self.outboxID = outboxID
        self.dueAt = dueAt
        self.text = text
        self.entities = entities
        self.condition = condition
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case outboxID = "outbox_id"
        case dueAt = "due_at"
        case text
        case entities
        case condition
    }
}

public struct OutboxIDParams: ProtocolType, Equatable {
    public static let protocolName = "OutboxIDParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var outboxID: Int64

    public init(outboxID: Int64) { self.outboxID = outboxID }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case outboxID = "outbox_id"
    }
}

public struct PollParams: ProtocolType, Equatable {
    public static let protocolName = "PollParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    /// 1 to 300 characters.
    public var question: String
    /// 2 to the chat's max_options, each 1 to its option_max_length characters, no two the same.
    public var options: [String]
    /// A person may choose every option, or one.
    public var multiple: Bool

    public init(roomID: String, question: String, options: [String], multiple: Bool) {
        self.roomID = roomID
        self.question = question
        self.options = options
        self.multiple = multiple
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case question
        case options
        case multiple
    }
}

public struct VoteParams: ProtocolType, Equatable {
    public static let protocolName = "VoteParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    /// The poll.
    public var eventID: String
    /// 0 to the poll's max_selections of its option ids, each once. [] takes my vote back.
    public var optionIDs: [String]

    public init(eventID: String, optionIDs: [String]) {
        self.eventID = eventID
        self.optionIDs = optionIDs
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
        case optionIDs = "option_ids"
    }
}

public struct LoginStartParams: ProtocolType, Equatable {
    public static let protocolName = "LoginStartParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String
    public var flow: String?
    /// true: sign in beside the accounts linked (a second account).
    public var another: Bool?
    /// Sign this account (a `Login.accountID`) in again. Never with `another`. Not a sign-in's login_id.
    public var accountID: String?

    public init(network: String, flow: String? = nil, another: Bool? = nil, accountID: String? = nil) {
        self.network = network
        self.flow = flow
        self.another = another
        self.accountID = accountID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case flow
        case another
        case accountID = "account_id"
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
    /// On complete: the account the sign-in became (a `Login.accountID`).
    public var accountID: String?
    /// On complete: true when the sign-in became another account than the one asked to sign in again (scanned with
    /// another phone, say). That one is kept as it was; this one is added beside it.
    public var otherAccount: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case loginID = "login_id"
        case stepID = "step_id"
        case type
        case instructions
        case display
        case fields
        case cookies
        case remoteName = "remote_name"
        case accountID = "account_id"
        case otherAccount = "other_account"
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
    public static let scheduled = Self(rawValue: "scheduled")
    public static let receipt = Self(rawValue: "receipt")
    public static let resync = Self(rawValue: "resync")
    public static let known: [Self] = [
        .room, .event, .status, .read, .bridge, .spaces, .typing, .reminder, .scheduled, .receipt, .resync,
    ]
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

// MARK: - Protocol 6: people, groups, chat info, blast and merged chats

public struct RoomInfoParams: ProtocolType, Equatable {
    public static let protocolName = "RoomInfoParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var refresh: Bool?

    public init(roomID: String, refresh: Bool? = nil) {
        self.roomID = roomID
        self.refresh = refresh
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case refresh
    }
}

public struct RoomLink: ProtocolType, Equatable, Hashable, Identifiable {
    public static let protocolName = "RoomLink"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var eventID: String
    public var sender: String
    public var ts: Int64
    public var url: String
    public var host: String

    public var id: String { "\(eventID):\(url)" }

    public init(eventID: String, sender: String, ts: Int64, url: String, host: String) {
        self.eventID = eventID
        self.sender = sender
        self.ts = ts
        self.url = url
        self.host = host
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
        case sender
        case ts
        case url
        case host
    }
}

public struct RoomInfoResult: ProtocolType, Equatable {
    public static let protocolName = "RoomInfoResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var name: String
    public var remoteName: String
    public var localName: String
    public var topic: String
    public var avatarPath: String
    public var localAvatarURI: String
    public var network: String
    public var accountID: String
    public var isDirect: Bool
    public var encrypted: Bool
    public var disappearingMS: Int64
    public var pinnedEventIDs: [String]
    public var members: [Member]
    public var sharedMedia: [Event]
    public var sharedFiles: [Event]
    public var sharedLinks: [RoomLink]
    public var features: ChatFeatures

    public init(roomID: String, name: String, remoteName: String, localName: String = "", topic: String = "",
                avatarPath: String = "", localAvatarURI: String = "", network: String, accountID: String = "",
                isDirect: Bool, encrypted: Bool = false, disappearingMS: Int64 = 0, pinnedEventIDs: [String] = [],
                members: [Member] = [], sharedMedia: [Event] = [], sharedFiles: [Event] = [],
                sharedLinks: [RoomLink] = [], features: ChatFeatures) {
        self.roomID = roomID
        self.name = name
        self.remoteName = remoteName
        self.localName = localName
        self.topic = topic
        self.avatarPath = avatarPath
        self.localAvatarURI = localAvatarURI
        self.network = network
        self.accountID = accountID
        self.isDirect = isDirect
        self.encrypted = encrypted
        self.disappearingMS = disappearingMS
        self.pinnedEventIDs = pinnedEventIDs
        self.members = members
        self.sharedMedia = sharedMedia
        self.sharedFiles = sharedFiles
        self.sharedLinks = sharedLinks
        self.features = features
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case name
        case remoteName = "remote_name"
        case localName = "local_name"
        case topic
        case avatarPath = "avatar_path"
        case localAvatarURI = "local_avatar_uri"
        case network
        case accountID = "account_id"
        case isDirect = "is_direct"
        case encrypted
        case disappearingMS = "disappearing_ms"
        case pinnedEventIDs = "pinned_event_ids"
        case members
        case sharedMedia = "shared_media"
        case sharedFiles = "shared_files"
        case sharedLinks = "shared_links"
        case features
    }
}

public struct RoomLocalOverrideParams: ProtocolType, Equatable {
    public static let protocolName = "RoomLocalOverrideParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var localName: String
    public var localAvatarPath: String

    public init(roomID: String, localName: String = "", localAvatarPath: String = "") {
        self.roomID = roomID
        self.localName = localName
        self.localAvatarPath = localAvatarPath
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case localName = "local_name"
        case localAvatarPath = "local_avatar_path"
    }
}

public struct RoomExportParams: ProtocolType, Equatable {
    public static let protocolName = "RoomExportParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var path: String

    public init(roomID: String, path: String) {
        self.roomID = roomID
        self.path = path
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case path
    }
}

public struct RoomExportResult: ProtocolType, Equatable {
    public static let protocolName = "RoomExportResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var messagesWritten: Int

    public init(messagesWritten: Int) { self.messagesWritten = messagesWritten }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case messagesWritten = "messages_written"
    }
}

public struct ReportSpamParams: ProtocolType, Equatable {
    public static let protocolName = "ReportSpamParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var leaveOrDelete: Bool?

    public init(roomID: String, leaveOrDelete: Bool? = nil) {
        self.roomID = roomID
        self.leaveOrDelete = leaveOrDelete
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case leaveOrDelete = "leave_or_delete"
    }
}

public struct RoomTextParams: ProtocolType, Equatable {
    public static let protocolName = "RoomTextParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
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

public struct RoomAvatarParams: ProtocolType, Equatable {
    public static let protocolName = "RoomAvatarParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var path: String

    public init(roomID: String, path: String) {
        self.roomID = roomID
        self.path = path
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case path
    }
}

public struct RoomInviteParams: ProtocolType, Equatable {
    public static let protocolName = "RoomInviteParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var userIDs: [String]

    public init(roomID: String, userIDs: [String]) {
        self.roomID = roomID
        self.userIDs = userIDs
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case userIDs = "user_ids"
    }
}

public struct RoomKickParams: ProtocolType, Equatable {
    public static let protocolName = "RoomKickParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var userID: String
    public var reason: String?

    public init(roomID: String, userID: String, reason: String? = nil) {
        self.roomID = roomID
        self.userID = userID
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case userID = "user_id"
        case reason
    }
}

public struct RoomAdminParams: ProtocolType, Equatable {
    public static let protocolName = "RoomAdminParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var userID: String
    public var isAdmin: Bool

    public init(roomID: String, userID: String, isAdmin: Bool) {
        self.roomID = roomID
        self.userID = userID
        self.isAdmin = isAdmin
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case userID = "user_id"
        case isAdmin = "is_admin"
    }
}

public struct PeopleContactsParams: ProtocolType, Equatable {
    public static let protocolName = "PeopleContactsParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String?
    public var accountID: String?
    public var query: String?

    public init(network: String? = nil, accountID: String? = nil, query: String? = nil) {
        self.network = network
        self.accountID = accountID
        self.query = query
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case accountID = "account_id"
        case query
    }
}

public struct ContactCandidate: ProtocolType, Equatable, Hashable, Identifiable {
    public static let protocolName = "ContactCandidate"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var userID: String
    public var name: String
    public var avatarPath: String
    public var network: String
    public var accountID: String
    public var identifiers: [String]
    public var roomID: String?

    public var id: String { "\(network):\(accountID):\(userID)" }

    public init(userID: String, name: String, avatarPath: String = "", network: String, accountID: String,
                identifiers: [String] = [], roomID: String? = nil) {
        self.userID = userID
        self.name = name
        self.avatarPath = avatarPath
        self.network = network
        self.accountID = accountID
        self.identifiers = identifiers
        self.roomID = roomID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case userID = "user_id"
        case name
        case avatarPath = "avatar_path"
        case network
        case accountID = "account_id"
        case identifiers
        case roomID = "room_id"
    }
}

public struct PeopleContactsResult: ProtocolType, Equatable {
    public static let protocolName = "PeopleContactsResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var contacts: [ContactCandidate]

    public init(contacts: [ContactCandidate]) { self.contacts = contacts }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case contacts
    }
}

public struct PeopleResolveParams: ProtocolType, Equatable {
    public static let protocolName = "PeopleResolveParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String
    public var accountID: String?
    public var identifier: String
    public var startChat: Bool?

    public init(network: String, accountID: String? = nil, identifier: String, startChat: Bool? = nil) {
        self.network = network
        self.accountID = accountID
        self.identifier = identifier
        self.startChat = startChat
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case accountID = "account_id"
        case identifier
        case startChat = "start_chat"
    }
}

public struct CreateGroupParams: ProtocolType, Equatable {
    public static let protocolName = "CreateGroupParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String
    public var accountID: String?
    public var name: String
    public var userIDs: [String]

    public init(network: String, accountID: String? = nil, name: String, userIDs: [String]) {
        self.network = network
        self.accountID = accountID
        self.name = name
        self.userIDs = userIDs
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case accountID = "account_id"
        case name
        case userIDs = "user_ids"
    }
}

public struct BlastMessage: ProtocolType, Equatable {
    public static let protocolName = "BlastMessage"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
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

public struct BlastSendParams: ProtocolType, Equatable {
    public static let protocolName = "BlastSendParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var messages: [BlastMessage]

    public init(messages: [BlastMessage]) {
        self.messages = messages
    }

    public init(roomIDs: [String], text: String) {
        self.messages = roomIDs.map { BlastMessage(roomID: $0, text: text) }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case messages
    }
}

public struct BlastSendResult: ProtocolType, Equatable {
    public static let protocolName = "BlastSendResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var events: [Event]

    public init(events: [Event]) { self.events = events }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case events
    }
}

public struct MergedChat: ProtocolType, Equatable, Hashable, Identifiable {
    public static let protocolName = "MergedChat"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var mergeID: String
    public var name: String
    public var avatarPath: String
    public var lastRoomID: String
    public var roomIDs: [String]
    public var networks: [String]
    public var createdTS: Int64

    public var id: String { mergeID }

    public init(mergeID: String, name: String, avatarPath: String = "", lastRoomID: String, roomIDs: [String],
                networks: [String], createdTS: Int64) {
        self.mergeID = mergeID
        self.name = name
        self.avatarPath = avatarPath
        self.lastRoomID = lastRoomID
        self.roomIDs = roomIDs
        self.networks = networks
        self.createdTS = createdTS
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case mergeID = "merge_id"
        case name
        case avatarPath = "avatar_path"
        case lastRoomID = "last_room_id"
        case roomIDs = "room_ids"
        case networks
        case createdTS = "created_ts"
    }
}

public struct MergeSuggestion: ProtocolType, Equatable, Hashable {
    public static let protocolName = "MergeSuggestion"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var displayName: String
    public var reason: String
    public var roomIDs: [String]
    public var networks: [String]

    public init(displayName: String, reason: String, roomIDs: [String], networks: [String]) {
        self.displayName = displayName
        self.reason = reason
        self.roomIDs = roomIDs
        self.networks = networks
    }

    public init(name: String, reason: String, roomIDs: [String], networks: [String]) {
        self.init(displayName: name, reason: reason, roomIDs: roomIDs, networks: networks)
    }

    public var name: String {
        get { displayName }
        set { displayName = newValue }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case displayName = "display_name"
        case reason
        case roomIDs = "room_ids"
        case networks
    }
}

public struct MergeCreateParams: ProtocolType, Equatable {
    public static let protocolName = "MergeCreateParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var name: String
    public var roomIDs: [String]

    public init(name: String, roomIDs: [String]) {
        self.name = name
        self.roomIDs = roomIDs
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case roomIDs = "room_ids"
    }
}

public struct MergeUpdateParams: ProtocolType, Equatable {
    public static let protocolName = "MergeUpdateParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var mergeID: String
    public var name: String
    public var roomIDs: [String]
    public var lastRoomID: String?

    public init(mergeID: String, name: String, roomIDs: [String], lastRoomID: String? = nil) {
        self.mergeID = mergeID
        self.name = name
        self.roomIDs = roomIDs
        self.lastRoomID = lastRoomID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case mergeID = "merge_id"
        case name
        case roomIDs = "room_ids"
        case lastRoomID = "last_room_id"
    }
}

public struct MergeDeleteParams: ProtocolType, Equatable {
    public static let protocolName = "MergeDeleteParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var mergeID: String

    public init(mergeID: String) { self.mergeID = mergeID }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case mergeID = "merge_id"
    }
}

public struct MergeListResult: ProtocolType, Equatable {
    public static let protocolName = "MergeListResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var mergedChats: [MergedChat]

    public init(mergedChats: [MergedChat]) { self.mergedChats = mergedChats }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case mergedChats = "merged_chats"
    }
}

public struct MergeSuggestResult: ProtocolType, Equatable {
    public static let protocolName = "MergeSuggestResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var suggestions: [MergeSuggestion]

    public init(suggestions: [MergeSuggestion]) { self.suggestions = suggestions }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case suggestions
    }
}

public struct BridgeInfo: ProtocolType, Equatable, Identifiable {
    public static let protocolName = "BridgeInfo"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String
    public var displayName: String
    public var bridgeID: String
    public var modulePath: String
    public var version: String
    public var mautrixVersion: String
    public var state: String
    public var error: String?
    public var message: String?
    public var startedAt: Int64
    public var accounts: [Account]
    public var id: String { network }

    public init(network: String, displayName: String, bridgeID: String, modulePath: String, version: String,
                mautrixVersion: String, state: String, error: String? = nil, message: String? = nil,
                startedAt: Int64, accounts: [Account]) {
        self.network = network
        self.displayName = displayName
        self.bridgeID = bridgeID
        self.modulePath = modulePath
        self.version = version
        self.mautrixVersion = mautrixVersion
        self.state = state
        self.error = error
        self.message = message
        self.startedAt = startedAt
        self.accounts = accounts
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case displayName = "display_name"
        case bridgeID = "bridge_id"
        case modulePath = "module_path"
        case version
        case mautrixVersion = "mautrix_version"
        case state
        case error
        case message
        case startedAt = "started_at"
        case accounts
    }
}

public struct BridgesResult: ProtocolType, Equatable {
    public static let protocolName = "BridgesResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var bridges: [BridgeInfo]

    public init(bridges: [BridgeInfo]) { self.bridges = bridges }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case bridges
    }
}

public struct BridgeRestartParams: ProtocolType, Equatable {
    public static let protocolName = "BridgeRestartParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String

    public init(network: String) { self.network = network }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
    }
}

public struct AccountRemoveParams: ProtocolType, Equatable {
    public static let protocolName = "AccountRemoveParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String
    public var accountID: String
    public var logoutRemote: Bool
    public var deleteChats: Bool

    public init(network: String, accountID: String, logoutRemote: Bool, deleteChats: Bool) {
        self.network = network
        self.accountID = accountID
        self.logoutRemote = logoutRemote
        self.deleteChats = deleteChats
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case accountID = "account_id"
        case logoutRemote = "logout_remote"
        case deleteChats = "delete_chats"
    }
}

public struct SubAccountItem: ProtocolType, Equatable, Hashable, Identifiable {
    public static let protocolName = "SubAccountItem"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String
    public var accountID: String
    public var subID: String
    public var title: String
    public var avatarURI: String
    public var kind: String
    public var enabled: Bool
    public var showInInbox: ShowInInbox
    public var id: String { "\(network):\(accountID):\(subID)" }

    public init(network: String, accountID: String, subID: String, title: String, avatarURI: String = "",
                kind: String, enabled: Bool, showInInbox: ShowInInbox) {
        self.network = network
        self.accountID = accountID
        self.subID = subID
        self.title = title
        self.avatarURI = avatarURI
        self.kind = kind
        self.enabled = enabled
        self.showInInbox = showInInbox
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case accountID = "account_id"
        case subID = "sub_id"
        case title
        case avatarURI = "avatar_uri"
        case kind
        case enabled
        case showInInbox = "show_in_inbox"
    }
}

public struct SubAccountsParams: ProtocolType, Equatable {
    public static let protocolName = "SubAccountsParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String
    public var accountID: String
    public var refresh: Bool?

    public init(network: String, accountID: String, refresh: Bool? = nil) {
        self.network = network
        self.accountID = accountID
        self.refresh = refresh
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case accountID = "account_id"
        case refresh
    }
}

public struct SubAccountsResult: ProtocolType, Equatable {
    public static let protocolName = "SubAccountsResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var subAccounts: [SubAccountItem]

    public init(subAccounts: [SubAccountItem]) { self.subAccounts = subAccounts }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case subAccounts = "sub_accounts"
    }
}

public struct SetSubAccountParams: ProtocolType, Equatable {
    public static let protocolName = "SetSubAccountParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var network: String
    public var accountID: String
    public var subID: String
    public var enabled: Bool?
    public var showInInbox: ShowInInbox?

    public init(network: String, accountID: String, subID: String, enabled: Bool? = nil,
                showInInbox: ShowInInbox? = nil) {
        self.network = network
        self.accountID = accountID
        self.subID = subID
        self.enabled = enabled
        self.showInInbox = showInInbox
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case accountID = "account_id"
        case subID = "sub_id"
        case enabled
        case showInInbox = "show_in_inbox"
    }
}

public struct DiagnosticsExportParams: ProtocolType, Equatable {
    public static let protocolName = "DiagnosticsExportParams"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String?
    public var eventID: String?

    public init(roomID: String? = nil, eventID: String? = nil) {
        self.roomID = roomID
        self.eventID = eventID
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case eventID = "event_id"
    }
}

public struct RoomDiagnostic: ProtocolType, Equatable, Hashable {
    public static let protocolName = "RoomDiagnostic"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var roomID: String
    public var network: String
    public var isDirect: Bool

    public init(roomID: String, network: String, isDirect: Bool) {
        self.roomID = roomID
        self.network = network
        self.isDirect = isDirect
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case roomID = "room_id"
        case network
        case isDirect = "is_direct"
    }
}

public struct MessageDiagnostic: ProtocolType, Equatable, Hashable {
    public static let protocolName = "MessageDiagnostic"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var eventID: String
    public var roomID: String
    public var network: String
    public var type: String
    public var ts: Int64
    public var status: String
    public var statusReason: String
    public var hasMedia: Bool
    public var isRedacted: Bool

    public init(eventID: String, roomID: String, network: String, type: String, ts: Int64, status: String,
                statusReason: String = "", hasMedia: Bool = false, isRedacted: Bool = false) {
        self.eventID = eventID
        self.roomID = roomID
        self.network = network
        self.type = type
        self.ts = ts
        self.status = status
        self.statusReason = statusReason
        self.hasMedia = hasMedia
        self.isRedacted = isRedacted
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID = "event_id"
        case roomID = "room_id"
        case network
        case type
        case ts
        case status
        case statusReason = "status_reason"
        case hasMedia = "has_media"
        case isRedacted = "is_redacted"
    }
}

public struct DiagnosticsExportResult: ProtocolType, Equatable {
    public static let protocolName = "DiagnosticsExportResult"
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }
    public var protocolVersion: Int
    public var schemaVersion: Int
    public var goVersion: String
    public var bridges: [BridgeInfo]
    public var scrubbedStderr: [String]
    public var roomDetails: RoomDiagnostic?
    public var messageDetails: MessageDiagnostic?

    public init(protocolVersion: Int, schemaVersion: Int, goVersion: String, bridges: [BridgeInfo],
                scrubbedStderr: [String], roomDetails: RoomDiagnostic? = nil,
                messageDetails: MessageDiagnostic? = nil) {
        self.protocolVersion = protocolVersion
        self.schemaVersion = schemaVersion
        self.goVersion = goVersion
        self.bridges = bridges
        self.scrubbedStderr = scrubbedStderr
        self.roomDetails = roomDetails
        self.messageDetails = messageDetails
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion = "protocol_version"
        case schemaVersion = "schema_version"
        case goVersion = "go_version"
        case bridges
        case scrubbedStderr = "scrubbed_stderr"
        case roomDetails = "room_details"
        case messageDetails = "message_details"
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
    /// The room's scheduled messages changed (scheduled, changed, sent, canceled, missed or deleted): re-read
    /// scheduled.list.
    case scheduled(roomID: String)
    /// Someone's read receipt or a delivery arrived for a message in the room: re-read the open chat's page (who
    /// read what) and the chat's row (its preview's status).
    case receipt(roomID: String)
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
        case .scheduled:
            guard let room = changed.roomID else { self = .resync; return }
            self = .scheduled(roomID: room)
        case .receipt:
            guard let room = changed.roomID else { self = .resync; return }
            self = .receipt(roomID: room)
        default:
            self = .resync
        }
    }
}

// MARK: - Methods and errors

/// The methods, with the types of their params and results, as protocol.json's "methods".
public enum ProtocolMethods {
    public static let changedNotification = "changed"

    /// Whether a protocol method is read-only/background or a user-initiated mutation refused while locked.
    public enum AccessClassification: String, Equatable, Sendable {
        case readOnlyOrBackground
        case userInitiatedMutation
    }

    /// Classification of every method in `protocol.json` for `EngineClient`'s app-lock chokepoint.
    public static let classifications: [String: AccessClassification] = [
        "hello": .readOnlyOrBackground,
        "accounts.list": .readOnlyOrBackground,
        "inbox.list": .readOnlyOrBackground,
        "spaces.list": .readOnlyOrBackground,
        "spaces.setLayout": .userInitiatedMutation,
        "spaces.update": .userInitiatedMutation,
        "labels.create": .userInitiatedMutation,
        "labels.update": .userInitiatedMutation,
        "labels.delete": .userInitiatedMutation,
        "room.setPinned": .userInitiatedMutation,
        "room.setArchived": .userInitiatedMutation,
        "room.setLowPriority": .userInitiatedMutation,
        "room.setHidden": .userInitiatedMutation,
        "room.setMarkedUnread": .userInitiatedMutation,
        "room.setLabel": .userInitiatedMutation,
        "room.setDraft": .userInitiatedMutation,
        "room.acceptRequest": .userInitiatedMutation,
        "reminder.set": .userInitiatedMutation,
        "reminder.clear": .userInitiatedMutation,
        "reminder.clearAll": .userInitiatedMutation,
        "inbox.archiveMatching": .userInitiatedMutation,
        "inbox.markAllRead": .userInitiatedMutation,
        "autoArchive.list": .readOnlyOrBackground,
        "autoArchive.set": .userInitiatedMutation,
        "autoArchive.delete": .userInitiatedMutation,
        "search.query": .readOnlyOrBackground,
        "room.events": .readOnlyOrBackground,
        "room.features": .readOnlyOrBackground,
        "room.markRead": .userInitiatedMutation,
        "room.setTyping": .userInitiatedMutation,
        "room.setUnreadFrom": .userInitiatedMutation,
        "room.members": .readOnlyOrBackground,
        "room.directChat": .userInitiatedMutation,
        "room.setMuted": .userInitiatedMutation,
        "message.send": .userInitiatedMutation,
        "message.sendFile": .userInitiatedMutation,
        "message.sendVoice": .userInitiatedMutation,
        "message.sendLocation": .userInitiatedMutation,
        "message.sendSticker": .userInitiatedMutation,
        "message.sendGIF": .userInitiatedMutation,
        "message.markPlayed": .userInitiatedMutation,
        "message.react": .userInitiatedMutation,
        "message.retry": .userInitiatedMutation,
        "message.discard": .userInitiatedMutation,
        "room.setDisappearing": .userInitiatedMutation,
        "message.edit": .userInitiatedMutation,
        "message.unsend": .userInitiatedMutation,
        "message.deleteForMe": .userInitiatedMutation,
        "message.forward": .userInitiatedMutation,
        "message.history": .userInitiatedMutation,
        "message.undo": .userInitiatedMutation,
        "message.sendHeld": .userInitiatedMutation,
        "message.setBookmarked": .userInitiatedMutation,
        "message.schedule": .userInitiatedMutation,
        "scheduled.list": .readOnlyOrBackground,
        "scheduled.update": .userInitiatedMutation,
        "scheduled.sendNow": .userInitiatedMutation,
        "scheduled.delete": .userInitiatedMutation,
        "poll.create": .userInitiatedMutation,
        "poll.vote": .userInitiatedMutation,
        "login.start": .userInitiatedMutation,
        "login.submit": .userInitiatedMutation,
        "login.wait": .userInitiatedMutation,
        "login.cancel": .userInitiatedMutation,
        "room.info": .userInitiatedMutation,
        "room.setLocalOverride": .userInitiatedMutation,
        "room.export": .userInitiatedMutation,
        "room.reportSpam": .userInitiatedMutation,
        "room.setName": .userInitiatedMutation,
        "room.setTopic": .userInitiatedMutation,
        "room.setAvatar": .userInitiatedMutation,
        "room.invite": .userInitiatedMutation,
        "room.kick": .userInitiatedMutation,
        "room.setAdmin": .userInitiatedMutation,
        "room.leave": .userInitiatedMutation,
        "room.delete": .userInitiatedMutation,
        "people.contacts": .userInitiatedMutation,
        "people.resolve": .userInitiatedMutation,
        "room.createGroup": .userInitiatedMutation,
        "blast.send": .userInitiatedMutation,
        "merge.list": .readOnlyOrBackground,
        "merge.suggest": .userInitiatedMutation,
        "merge.create": .userInitiatedMutation,
        "merge.update": .userInitiatedMutation,
        "merge.delete": .userInitiatedMutation,
        "stickers.list": .userInitiatedMutation,
        "stickers.import": .userInitiatedMutation,
        "bridges.list": .userInitiatedMutation,
        "bridges.restart": .userInitiatedMutation,
        "accounts.remove": .userInitiatedMutation,
        "accounts.subAccounts": .userInitiatedMutation,
        "accounts.setSubAccount": .userInitiatedMutation,
        "diagnostics.export": .userInitiatedMutation,
    ]

    public static func classification(for method: String) -> AccessClassification? {
        classifications[method]
    }

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
        "room.setTyping": (TypingParams.self, Empty.self),
        "room.setUnreadFrom": (EventParams.self, Empty.self),
        "room.directChat": (DirectChatParams.self, RoomResult.self),
        "message.send": (SendParams.self, Sent.self),
        "message.sendFile": (SendFileParams.self, Sent.self),
        "message.sendVoice": (SendVoiceParams.self, Sent.self),
        "message.sendLocation": (SendLocationParams.self, Sent.self),
        "message.sendSticker": (SendStickerParams.self, Sent.self),
        "message.sendGIF": (SendGIFParams.self, Sent.self),
        "message.markPlayed": (MarkPlayedParams.self, Empty.self),
        "message.react": (ReactParams.self, Sent.self),
        "message.retry": (EventParams.self, Empty.self),
        "message.discard": (EventParams.self, Empty.self),
        "room.features": (RoomParams.self, ChatFeatures.self),
        "room.members": (MembersParams.self, MembersResult.self),
        "room.setDisappearing": (DisappearingParams.self, Empty.self),
        "message.edit": (EditParams.self, Sent.self),
        "message.unsend": (EventParams.self, Sent.self),
        "message.deleteForMe": (EventParams.self, Empty.self),
        "message.forward": (ForwardParams.self, ForwardResult.self),
        "message.undo": (EventParams.self, Draft.self),
        "message.sendHeld": (RoomOptionalParams.self, Empty.self),
        "message.setBookmarked": (BookmarkParams.self, Empty.self),
        "message.history": (EventParams.self, HistoryResult.self),
        "message.schedule": (ScheduleParams.self, ScheduledMessage.self),
        "scheduled.list": (RoomOptionalParams.self, ScheduledResult.self),
        "scheduled.update": (ScheduledUpdateParams.self, ScheduledMessage.self),
        "scheduled.sendNow": (OutboxIDParams.self, Empty.self),
        "scheduled.delete": (OutboxIDParams.self, Empty.self),
        "poll.create": (PollParams.self, Sent.self),
        "poll.vote": (VoteParams.self, Sent.self),
        "login.start": (LoginStartParams.self, LoginStep.self),
        "login.submit": (LoginSubmitParams.self, LoginStep.self),
        "login.wait": (LoginParams.self, LoginStep.self),
        "login.cancel": (LoginParams.self, Empty.self),
        "room.info": (RoomInfoParams.self, RoomInfoResult.self),
        "room.setLocalOverride": (RoomLocalOverrideParams.self, Empty.self),
        "room.export": (RoomExportParams.self, RoomExportResult.self),
        "room.reportSpam": (ReportSpamParams.self, Empty.self),
        "room.setName": (RoomTextParams.self, Empty.self),
        "room.setTopic": (RoomTextParams.self, Empty.self),
        "room.setAvatar": (RoomAvatarParams.self, Empty.self),
        "room.invite": (RoomInviteParams.self, Empty.self),
        "room.kick": (RoomKickParams.self, Empty.self),
        "room.setAdmin": (RoomAdminParams.self, Empty.self),
        "room.leave": (RoomParams.self, Empty.self),
        "room.delete": (RoomParams.self, Empty.self),
        "people.contacts": (PeopleContactsParams.self, PeopleContactsResult.self),
        "people.resolve": (PeopleResolveParams.self, ContactCandidate.self),
        "room.createGroup": (CreateGroupParams.self, RoomResult.self),
        "blast.send": (BlastSendParams.self, BlastSendResult.self),
        "merge.create": (MergeCreateParams.self, MergedChat.self),
        "merge.update": (MergeUpdateParams.self, MergedChat.self),
        "merge.delete": (MergeDeleteParams.self, Empty.self),
        "merge.list": (Empty.self, MergeListResult.self),
        "merge.suggest": (Empty.self, MergeSuggestResult.self),
        "stickers.list": (StickersListParams.self, ListStickersResult.self),
        "stickers.import": (ImportStickerParams.self, StickerItem.self),
        "bridges.list": (Empty.self, BridgesResult.self),
        "bridges.restart": (BridgeRestartParams.self, Empty.self),
        "accounts.remove": (AccountRemoveParams.self, Empty.self),
        "accounts.subAccounts": (SubAccountsParams.self, SubAccountsResult.self),
        "accounts.setSubAccount": (SetSubAccountParams.self, Empty.self),
        "diagnostics.export": (DiagnosticsExportParams.self, DiagnosticsExportResult.self),
    ]

    /// Every type of protocol.json's "types".
    public static let types: [any ProtocolType.Type] = [
        Empty.self, HelloParams.self, HelloResult.self, Account.self, Login.self, AccountsResult.self, InboxRow.self,
        CallNote.self,
        Reminder.self, InboxListParams.self, InboxResult.self, Space.self, SpacesResult.self, SpaceLayoutParams.self,
        SpaceUpdateParams.self, LabelParams.self, LabelResult.self, LabelUpdateParams.self, LabelIDParams.self,
        SetPinnedParams.self, ArchiveParams.self, RoomsChanged.self, RoomsFlagParams.self, SetLabelParams.self,
        DraftParams.self, ReminderParams.self, RoomsParams.self, ArchiveMatchingParams.self, SpaceParams.self,
        AutoArchiveRule.self, RulesResult.self, RuleIDParams.self, Cursor.self, RoomParams.self, RoomEventsParams.self,
        Event.self, Reader.self, PollTally.self, PollOption.self, ThreadSummary.self, EventsPage.self,
        SearchParams.self, SearchFilters.self, SearchResult.self, PersonHit.self, MessageHits.self, MessageHit.self,
        TextRange.self, SetMutedParams.self, SendParams.self, SendFileParams.self, TextEntity.self, ChatFeatures.self,
        PollFeatures.self, DisappearingFeatures.self, DisappearingTimer.self, MembersParams.self, MembersResult.self,
        Member.self, DisappearingParams.self, EditParams.self, ForwardParams.self, ForwardResult.self, Forwarded.self,
        ForwardFailure.self, Draft.self, RoomOptionalParams.self, BookmarkParams.self, HistoryResult.self, Version.self,
        ScheduleParams.self, ScheduledMessage.self, ScheduledResult.self, ScheduledUpdateParams.self,
        OutboxIDParams.self, PollParams.self, VoteParams.self, ReactParams.self, EventParams.self, Sent.self,
        TypingParams.self, DirectChatParams.self, RoomResult.self,
        LoginStartParams.self, LoginSubmitParams.self, LoginParams.self, LoginStep.self, LoginDisplay.self,
        LoginField.self, LoginCookies.self, LoginCookieField.self, LoginCookieSource.self, Changed.self,
        ProtocolMismatchData.self, InvalidParamsData.self,
        RoomInfoParams.self, RoomLink.self, RoomInfoResult.self, RoomLocalOverrideParams.self, RoomExportParams.self,
        RoomExportResult.self, ReportSpamParams.self, RoomTextParams.self, RoomAvatarParams.self,
        RoomInviteParams.self, RoomKickParams.self, RoomAdminParams.self, PeopleContactsParams.self,
        ContactCandidate.self, PeopleContactsResult.self, PeopleResolveParams.self, CreateGroupParams.self,
        BlastMessage.self, BlastSendParams.self, BlastSendResult.self, MergedChat.self, MergeSuggestion.self,
        MergeCreateParams.self, MergeUpdateParams.self, MergeDeleteParams.self, MergeListResult.self,
        MergeSuggestResult.self,
        FileKindFeatures.self, MediaCapFeature.self, LinkPreviewItem.self, MarkPlayedParams.self, SendVoiceParams.self, SendLocationParams.self,
        BridgedStickerRef.self, SendStickerParams.self, SendGIFParams.self,
        StickerItem.self, StickerPack.self, ListStickersResult.self, StickersListParams.self, ImportStickerParams.self,
        BridgeInfo.self, BridgesResult.self, BridgeRestartParams.self, AccountRemoveParams.self, SubAccountItem.self,
        SubAccountsParams.self, SubAccountsResult.self, SetSubAccountParams.self, DiagnosticsExportParams.self,
        RoomDiagnostic.self, MessageDiagnostic.self, DiagnosticsExportResult.self,
    ]

    /// The open-valued fields, by "Type.field", with the values this app knows.
    public static let values: [String: [String]] = [
        "Account.state": AccountState.known.map(\.rawValue),
        "Account.syncs": AccountSync.known.map(\.rawValue),
        "Login.state": AccountState.known.map(\.rawValue),
        "InboxRow.preview_kind": PreviewKind.known.map(\.rawValue),
        "InboxRow.muted_by": MutedBy.known.map(\.rawValue),
        "InboxRow.preview_status": PreviewStatus.known.map(\.rawValue),
        "CallNote.state": CallState.known.map(\.rawValue),
        "CallNote.media": CallMedia.known.map(\.rawValue),
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
        "TextEntity.type": TextEntity.Kind.allCases.map(\.rawValue),
        "ChatFeatures.formatting": TextEntity.Kind.allCases.map(\.rawValue),
        "ChatFeatures.source": FeatureSource.known.map(\.rawValue),
        "DisappearingFeatures.type": DisappearingType.known.map(\.rawValue),
        "DisappearingTimer.type": DisappearingType.known.map(\.rawValue),
        "DisappearingParams.type": DisappearingType.settable.map(\.rawValue),
        "ScheduleParams.condition": ScheduleCondition.known.map(\.rawValue),
        "ScheduledMessage.condition": ScheduleCondition.known.map(\.rawValue),
        "ScheduledMessage.state": ScheduledState.known.map(\.rawValue),
        "ScheduledUpdateParams.condition": ScheduleCondition.known.map(\.rawValue),
        "MessageHit.place": ChatPlace.known.map(\.rawValue),
        "MessageHit.kind": MessageHitKind.known.map(\.rawValue),
        "LoginStep.type": LoginStepType.known.map(\.rawValue),
        "LoginDisplay.kind": LoginDisplayKind.known.map(\.rawValue),
        "LoginField.type": LoginFieldType.known.map(\.rawValue),
        "LoginCookieSource.type": LoginCookieSourceType.known.map(\.rawValue),
        "Changed.kind": ChangedKind.known.map(\.rawValue),
        "SubAccountItem.kind": ["space", "bot"],
        "SubAccountItem.show_in_inbox": ShowInInbox.settable.map(\.rawValue),
        "SetSubAccountParams.show_in_inbox": ShowInInbox.settable.map(\.rawValue),
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
    /// message.edit or message.unsend past the chat's limits. Nothing was sent.
    case tooOld
    /// message.undo on a message that is no longer held. Wording: when the hold had failed to hand off, the message
    /// did not go, so the app must not say it went (Ruling 20): read its status first.
    case alreadySent
    /// message.edit or message.unsend on someone else's message.
    case notYours
    /// The network turned the change down.
    case networkRefused
    /// Sending a voice note on this network needs ffmpeg to transcode to OGG Opus.
    case needsFFmpeg
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
        (.tooOld, -32024, "too_old"),
        (.alreadySent, -32025, "already_sent"),
        (.notYours, -32026, "not_yours"),
        (.networkRefused, -32027, "network_refused"),
        (.needsFFmpeg, -32028, "needs_ffmpeg"),
    ]

    public init(number: Int) {
        self = Self.known.first(where: { $0.number == number })?.code ?? .other(number)
    }

    public var number: Int {
        if case let .other(number) = self { return number }
        return Self.known.first(where: { $0.code == self })!.number
    }
}
