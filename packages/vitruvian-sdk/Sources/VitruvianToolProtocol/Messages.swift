// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

/// The versions of the protocol this library speaks. Version 2 adds what a
/// tool draws and changes nothing of version 1, so every tool written to 1
/// is a tool of 2.
public enum ProtocolVersion {
    public static let current = "2"
    public static let supported = ["1", current]
}

/// An app service a tool may call. A tool's manifest lists the ones it
/// calls in `uses`, by these names.
public enum AppService: String, CaseIterable, Sendable {
    case notify
    case open
    case clipboardRead = "clipboard.read"
    case clipboardWrite = "clipboard.write"
    case keystrokes
    case processes
    case storage
}

/// What an app may have beyond the first release of a protocol version, by
/// the name it gives in `initialize`'s `features`. A tool asks before it
/// uses one: an app that does not name it does not have it. The list on the
/// link is plain text, so that a name of a later app is read and ignored.
public enum ProtocolFeature: String, CaseIterable, Sendable {
    /// `ui/status`: the tool's status on the closed island.
    case status = "ui.status"
    /// The `choice` block.
    case choice = "ui.choice"
    /// `options` on a text preference, drawn as a pop-up menu.
    case preferenceOptions = "preferences.options"
    /// `activity` and `since` on `ui/status`: a few words, or a count of
    /// seconds, beside the tool's mark on the closed island. From 3.50.
    case statusActivity = "ui.status.activity"
    /// `open` in the answer to `ui/event` may name the tool's own settings
    /// panel: the app opens Settings on the tool's detail. From 3.58.
    case openSettings = "ui.open.settings"
    /// The `chips` block.
    case chips = "ui.chips"
    /// `section` on a heading, and `help` on a switch, a field, a choice and
    /// chips.
    case sections = "ui.sections"
}

/// Every message of the protocol, by its name on the link. The last six
/// are version 2's.
/// `protocol/methods.json` is the same table, and a test holds the two
/// together.
public enum ToolMethod: String, CaseIterable, Sendable {
    case initialize
    case commandRun = "command/run"
    case preferencesChanged = "preferences/changed"
    case languageChanged = "language/changed"
    case shutdown
    case commandsState = "commands/state"
    case notifyHUD = "notify/hud"
    case notifyBeep = "notify/beep"
    case openURL = "open/url"
    case clipboardReadText = "clipboard/readText"
    case clipboardWriteText = "clipboard/writeText"
    case keystrokesPaste = "keystrokes/paste"
    case keystrokesPressMenuItem = "keystrokes/pressMenuItem"
    case processesTerminate = "processes/terminate"
    case storageGet = "storage/get"
    case storageSet = "storage/set"
    case log
    case uiOpen = "ui/open"
    case uiEvent = "ui/event"
    case uiClose = "ui/close"
    case uiRender = "ui/render"
    case uiBadge = "ui/badge"
    case uiStatus = "ui/status"

    public enum Sender: String, Sendable {
        case app, tool
    }

    /// Who sends it.
    public var sender: Sender {
        switch self {
        case .initialize, .commandRun, .preferencesChanged, .languageChanged, .shutdown, .uiOpen, .uiEvent, .uiClose:
            return .app
        case .commandsState, .notifyHUD, .notifyBeep, .openURL, .clipboardReadText, .clipboardWriteText,
             .keystrokesPaste, .keystrokesPressMenuItem, .processesTerminate, .storageGet, .storageSet, .log,
             .uiRender, .uiBadge, .uiStatus:
            return .tool
        }
    }

    /// True for a request, which is answered; false for a notice.
    public var isAnswered: Bool {
        switch self {
        case .preferencesChanged, .languageChanged, .shutdown, .commandsState, .log, .uiClose, .uiRender:
            return false
        case .initialize, .commandRun, .notifyHUD, .notifyBeep, .openURL, .clipboardReadText,
             .clipboardWriteText, .keystrokesPaste, .keystrokesPressMenuItem, .processesTerminate, .storageGet,
             .storageSet, .uiOpen, .uiEvent, .uiBadge, .uiStatus:
            return true
        }
    }

    /// The service the tool's manifest must list in `uses` before the app
    /// will do this; nil when it needs none.
    public var service: AppService? {
        switch self {
        case .initialize, .commandRun, .preferencesChanged, .languageChanged, .shutdown, .commandsState, .log,
             .uiOpen, .uiEvent, .uiClose, .uiRender, .uiStatus:
            return nil
        case .notifyHUD, .notifyBeep, .uiBadge: return .notify
        case .openURL: return .open
        case .clipboardReadText: return .clipboardRead
        case .clipboardWriteText: return .clipboardWrite
        case .keystrokesPaste, .keystrokesPressMenuItem: return .keystrokes
        case .processesTerminate: return .processes
        case .storageGet, .storageSet: return .storage
        }
    }
}

/// Why a request was refused, as the code of its failure.
public enum RefusalCode: Int, CaseIterable, Sendable {
    /// The app: the service is not listed in the tool's `uses`.
    case notInUses = -32001
    /// The app: the tool is not installed.
    case notInstalled = -32002
    /// The app: Vitruvian lacks a macOS permission the service needs.
    case permissionMissing = -32003
    /// The app: not available right now.
    case unavailable = -32004
    /// The tool: it would not run the command.
    case commandRefused = -32010

    /// A few English words for a log.
    public var message: String {
        switch self {
        case .notInUses: return "not listed in uses"
        case .notInstalled: return "tool not installed"
        case .permissionMissing: return "Vitruvian lacks a macOS permission"
        case .unavailable: return "not available right now"
        case .commandRefused: return "command refused"
        }
    }

    /// The failure that says so. `service` goes with `notInUses`, and
    /// `permission` with `permissionMissing`.
    public func error(service: AppService? = nil, permission: String? = nil) -> RPCErrorObject {
        var fields: [String: JSONValue] = [:]
        if let service { fields["service"] = .string(service.rawValue) }
        if let permission { fields["permission"] = .string(permission) }
        return RPCErrorObject(code: rawValue, message: message, data: fields.isEmpty ? nil : .object(fields))
    }

    /// The refusal a failure carries; nil for any other failure.
    public init?(_ error: RPCErrorObject) {
        self.init(rawValue: error.code)
    }
}

/// What a refusal names, in a failure's `data`.
public struct RefusalData: Codable, Equatable, Sendable {
    /// With `notInUses`: the entry missing from the tool's `uses`.
    public let service: String?
    /// With `permissionMissing`: the macOS permission Vitruvian lacks.
    public let permission: String?

    public init(service: String? = nil, permission: String? = nil) {
        self.service = service
        self.permission = permission
    }
}

/// Nothing to say: `{}`. The params of a message that carries none, and the
/// result of a request that was simply done.
public struct EmptyObject: Codable, Equatable, Sendable {
    private struct NoKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init() {}

    public init(from decoder: any Decoder) throws {
        _ = try decoder.container(keyedBy: NoKey.self)
    }

    public func encode(to encoder: any Encoder) throws {
        _ = encoder.container(keyedBy: NoKey.self)
    }
}

// MARK: - What the app sends

public struct InitializeParams: Codable, Equatable, Sendable {
    /// The protocol versions the app speaks.
    public let protocolVersions: [String]
    /// The language the app is in, as a tag such as `en-US`.
    public let language: String
    /// The folder the tool may keep its own files in.
    public let dataFolder: String
    /// What this app has beyond the first release of the protocol version,
    /// by the names `ProtocolFeature` lists. Nil from an app that says
    /// nothing, which has none of them. A name nobody knows is kept and
    /// ignored.
    public let features: [String]?

    public init(protocolVersions: [String], language: String, dataFolder: String, features: [String]? = nil) {
        self.protocolVersions = protocolVersions
        self.language = language
        self.dataFolder = dataFolder
        self.features = features
    }
}

public struct InitializeResult: Codable, Equatable, Sendable {
    /// The one version, of those offered, the tool will speak.
    public let protocolVersion: String
    public let toolVersion: String

    public init(protocolVersion: String, toolVersion: String) {
        self.protocolVersion = protocolVersion
        self.toolVersion = toolVersion
    }
}

public struct CommandRunParams: Codable, Equatable, Sendable {
    /// The command's id as the manifest writes it, without the tool's id.
    public let command: String

    public init(command: String) {
        self.command = command
    }
}

public struct PreferencesChangedParams: Codable, Equatable, Sendable {
    /// Each changed preference's id and its new value.
    public let values: [String: JSONValue]

    public init(values: [String: JSONValue]) {
        self.values = values
    }
}

public struct LanguageChangedParams: Codable, Equatable, Sendable {
    public let language: String

    public init(language: String) {
        self.language = language
    }
}

// MARK: - What a tool sends

public struct CommandsStateParams: Codable, Equatable, Sendable {
    /// The ids of the commands that can run now. One not listed cannot.
    public let runnable: [String]

    public init(runnable: [String]) {
        self.runnable = runnable
    }
}

public struct NotifyHUDParams: Codable, Equatable, Sendable {
    /// An SF Symbol name.
    public let icon: String
    public let message: String

    public init(icon: String, message: String) {
        self.icon = icon
        self.message = message
    }
}

public struct OpenURLParams: Codable, Equatable, Sendable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}

public struct OpenURLResult: Codable, Equatable, Sendable {
    public let opened: Bool

    public init(opened: Bool) {
        self.opened = opened
    }
}

public struct ClipboardReadTextResult: Codable, Equatable, Sendable {
    /// Nil when the clipboard holds no text.
    public let text: String?

    public init(text: String?) {
        self.text = text
    }
}

public struct ClipboardWriteTextParams: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ClipboardWriteTextResult: Codable, Equatable, Sendable {
    public let written: Bool

    public init(written: Bool) {
        self.written = written
    }
}

public struct KeystrokesPasteParams: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

/// A menu item's key equivalent. Command is always part of it.
public struct KeyEquivalent: Codable, Equatable, Sendable {
    /// The names `modifiers` may hold.
    public enum Modifier: String, CaseIterable, Codable, Sendable {
        case shift, option, control
    }

    /// The key, as the menu shows it.
    public let character: String
    /// The keys held with Command. A name that is not a `Modifier` is not
    /// read.
    public let modifiers: [Modifier]

    public init(character: String, modifiers: [Modifier]) {
        self.character = character
        self.modifiers = modifiers
    }
}

public struct KeystrokesPressMenuItemParams: Codable, Equatable, Sendable {
    /// The key equivalents that count.
    public let equivalents: [KeyEquivalent]

    public init(equivalents: [KeyEquivalent]) {
        self.equivalents = equivalents
    }
}

public struct KeystrokesPressMenuItemResult: Codable, Equatable, Sendable {
    public let pressed: Bool

    public init(pressed: Bool) {
        self.pressed = pressed
    }
}

public struct ProcessesTerminateParams: Codable, Equatable, Sendable {
    public let pid: Int
    public let name: String
    /// True to end it at once; false to ask it to quit.
    public let force: Bool

    public init(pid: Int, name: String, force: Bool) {
        self.pid = pid
        self.name = name
        self.force = force
    }
}

public struct StorageGetParams: Codable, Equatable, Sendable {
    /// The preference's id, as the manifest writes it.
    public let key: String

    public init(key: String) {
        self.key = key
    }
}

/// The limits on what `storage/set` saves. They are the app's: a value
/// over one is a message the app reads and then refuses, with -32602.
public enum StorageLimits {
    /// The longest text a preference may be set to, in characters as JSON
    /// Schema counts them: Unicode code points.
    public static let maxTextLength = 4_096

    /// Whether `value` is one a preference may be set to, as far as its
    /// size goes. Only text has a size.
    public static func allows(_ value: JSONValue) -> Bool {
        if case .string(let text) = value { return text.unicodeScalars.count <= maxTextLength }
        return true
    }
}

/// What a preference may hold on the wire: text, yes or no, or a number.
/// A list, an object or null is not read.
enum StoredValue {
    static func read<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) throws -> JSONValue {
        let value = try container.decode(JSONValue.self, forKey: key)
        switch value {
        case .string, .bool, .number: return value
        case .null, .array, .object:
            throw DecodingError.dataCorruptedError(forKey: key, in: container,
                                                   debugDescription: "not text, yes or no, or a number")
        }
    }
}

public struct StorageGetResult: Codable, Equatable, Sendable {
    /// Text, yes or no, or a number.
    public let value: JSONValue

    public init(value: JSONValue) {
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: any Decoder) throws {
        value = try StoredValue.read(decoder.container(keyedBy: CodingKeys.self), .value)
    }
}

public struct StorageSetParams: Codable, Equatable, Sendable {
    public let key: String
    /// Text, yes or no, or a number.
    public let value: JSONValue

    public init(key: String, value: JSONValue) {
        self.key = key
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case key, value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try StoredValue.read(container, .value)
    }
}

public struct LogParams: Codable, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}
