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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Foundation

// MARK: - Arbitrary JSON & JSON-RPC Primitives

/// Arbitrary JSON value for forward-compatible ACP decoding and `_meta` extensions.
public enum ACPJSONValue: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ACPJSONValue])
    case object([String: ACPJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([ACPJSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: ACPJSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .int(let i):
            try container.encode(i)
        case .double(let d):
            try container.encode(d)
        case .string(let s):
            try container.encode(s)
        case .array(let arr):
            try container.encode(arr)
        case .object(let obj):
            try container.encode(obj)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d.rounded() == d && d >= Double(Int.min) && d <= Double(Int.max):
            return Int(d)
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    public var objectValue: [String: ACPJSONValue]? {
        if case .object(let obj) = self { return obj }
        return nil
    }

    public var arrayValue: [ACPJSONValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    /// True when an ACP capability marker is advertised (`true` or an object `{}`).
    public var isAdvertisedCapability: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        default: return true
        }
    }

    /// Converts an `ACPJSONValue` into Foundation JSON types (`[String: Any]`, `[Any]`, etc.).
    public var foundationObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let arr): return arr.map(\.foundationObject)
        case .object(let obj): return obj.mapValues(\.foundationObject)
        }
    }

    public static func fromEncodable<T: Encodable>(_ value: T) throws -> ACPJSONValue {
        if let existing = value as? ACPJSONValue {
            return existing
        }
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(ACPJSONValue.self, from: data)
    }

    public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        if type == ACPJSONValue.self, let cast = self as? T {
            return cast
        }
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func serializedJSONString() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// JSON-RPC 2.0 request identifier (integer or string).
public enum ACPRPCID: Hashable, Sendable, Codable {
    case int(Int)
    case string(String)

    public init?(jsonValue: ACPJSONValue) {
        switch jsonValue {
        case .int(let i): self = .int(i)
        case .string(let s): self = .string(s)
        default: return nil
        }
    }

    public var jsonValue: ACPJSONValue {
        switch self {
        case .int(let i): return .int(i)
        case .string(let s): return .string(s)
        }
    }

    public var stringDescription: String {
        switch self {
        case .int(let i): return String(i)
        case .string(let s): return s
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON-RPC id")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let i): try container.encode(i)
        case .string(let s): try container.encode(s)
        }
    }
}

/// Typed JSON-RPC 2.0 error keeping `code`, `message` and optional `data`.
public struct ACPRPCError: Error, Equatable, Sendable, Codable, LocalizedError {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603

    public let code: Int
    public let message: String
    public let data: ACPJSONValue?

    public init(code: Int, message: String, data: ACPJSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public var errorDescription: String? { message }
}

/// Empty JSON object `{}` that tolerates and ignores unknown fields when decoding.
public struct ACPEmptyObject: Equatable, Sendable, Codable {
    public init() {}

    public init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer()
    }

    public func encode(to encoder: Encoder) throws {
        let container = encoder.container(keyedBy: CodingKeys.self)
        _ = container
    }

    private enum CodingKeys: CodingKey {}
}

// MARK: - Initialize & Authenticate

public struct ACPImplementation: Equatable, Sendable, Codable {
    public var name: String
    public var title: String?
    public var version: String?

    public init(name: String, title: String? = nil, version: String? = nil) {
        self.name = name
        self.title = title
        self.version = version
    }
}

public struct ACPFileSystemCapabilities: Equatable, Sendable, Codable {
    public var readTextFile: Bool
    public var writeTextFile: Bool

    public init(readTextFile: Bool = false, writeTextFile: Bool = false) {
        self.readTextFile = readTextFile
        self.writeTextFile = writeTextFile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.readTextFile = try container.decodeIfPresent(Bool.self, forKey: .readTextFile) ?? false
        self.writeTextFile = try container.decodeIfPresent(Bool.self, forKey: .writeTextFile) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case readTextFile
        case writeTextFile
    }
}

public struct ACPElicitationCapabilities: Equatable, Sendable, Codable {
    public var form: ACPEmptyObject?
    public var url: ACPEmptyObject?

    public init(form: ACPEmptyObject? = ACPEmptyObject(), url: ACPEmptyObject? = ACPEmptyObject()) {
        self.form = form
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let flag = try? single.decode(Bool.self) {
            self.form = flag ? ACPEmptyObject() : nil
            self.url = flag ? ACPEmptyObject() : nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.form = try container.decodeIfPresent(ACPEmptyObject.self, forKey: .form)
        self.url = try container.decodeIfPresent(ACPEmptyObject.self, forKey: .url)
    }

    private enum CodingKeys: String, CodingKey {
        case form
        case url
    }
}

public struct ACPClientCapabilities: Equatable, Sendable, Codable {
    public var fs: ACPFileSystemCapabilities?
    public var terminal: Bool?
    public var elicitation: ACPElicitationCapabilities?

    public init(
        fs: ACPFileSystemCapabilities? = nil,
        terminal: Bool? = nil,
        elicitation: ACPElicitationCapabilities? = nil
    ) {
        self.fs = fs
        self.terminal = terminal
        self.elicitation = elicitation
    }
}

public struct ACPInitializeParams: Equatable, Sendable, Codable {
    public static let v1ProtocolVersion = 1

    public var protocolVersion: Int
    public var clientInfo: ACPImplementation?
    public var clientCapabilities: ACPClientCapabilities

    public init(
        protocolVersion: Int = ACPInitializeParams.v1ProtocolVersion,
        clientInfo: ACPImplementation? = nil,
        clientCapabilities: ACPClientCapabilities = ACPClientCapabilities()
    ) {
        self.protocolVersion = protocolVersion
        self.clientInfo = clientInfo
        self.clientCapabilities = clientCapabilities
    }
}

public struct ACPPromptCapabilities: Equatable, Sendable, Codable {
    public var image: Bool?
    public var audio: Bool?
    public var embeddedContext: Bool?

    public init(image: Bool? = nil, audio: Bool? = nil, embeddedContext: Bool? = nil) {
        self.image = image
        self.audio = audio
        self.embeddedContext = embeddedContext
    }
}

public struct ACPMCPCapabilities: Equatable, Sendable, Codable {
    public var http: Bool?
    public var sse: Bool?

    public init(http: Bool? = nil, sse: Bool? = nil) {
        self.http = http
        self.sse = sse
    }
}

public struct ACPSessionCapabilities: Equatable, Sendable, Codable {
    public var resume: ACPJSONValue?
    public var list: ACPJSONValue?
    public var close: ACPJSONValue?
    public var fork: ACPJSONValue?
    public var delete: ACPJSONValue?

    public init(
        resume: ACPJSONValue? = nil,
        list: ACPJSONValue? = nil,
        close: ACPJSONValue? = nil,
        fork: ACPJSONValue? = nil,
        delete: ACPJSONValue? = nil
    ) {
        self.resume = resume
        self.list = list
        self.close = close
        self.fork = fork
        self.delete = delete
    }

    public var supportsResume: Bool { resume?.isAdvertisedCapability == true }
    public var supportsList: Bool { list?.isAdvertisedCapability == true }
    public var supportsClose: Bool { close?.isAdvertisedCapability == true }
}

public struct ACPAgentCapabilities: Equatable, Sendable, Codable {
    public var loadSession: Bool?
    public var promptCapabilities: ACPPromptCapabilities?
    public var mcpCapabilities: ACPMCPCapabilities?
    public var sessionCapabilities: ACPSessionCapabilities?

    public init(
        loadSession: Bool? = nil,
        promptCapabilities: ACPPromptCapabilities? = nil,
        mcpCapabilities: ACPMCPCapabilities? = nil,
        sessionCapabilities: ACPSessionCapabilities? = nil
    ) {
        self.loadSession = loadSession
        self.promptCapabilities = promptCapabilities
        self.mcpCapabilities = mcpCapabilities
        self.sessionCapabilities = sessionCapabilities
    }
}

public struct ACPAuthMethod: Equatable, Sendable, Codable {
    public var id: String
    public var name: String
    public var description: String?

    public init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public struct ACPInitializeResult: Equatable, Sendable, Codable {
    public var protocolVersion: Int
    public var agentCapabilities: ACPAgentCapabilities?
    public var authMethods: [ACPAuthMethod]?
    public var agentInfo: ACPImplementation?

    public init(
        protocolVersion: Int = ACPInitializeParams.v1ProtocolVersion,
        agentCapabilities: ACPAgentCapabilities? = nil,
        authMethods: [ACPAuthMethod]? = nil,
        agentInfo: ACPImplementation? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.agentCapabilities = agentCapabilities
        self.authMethods = authMethods
        self.agentInfo = agentInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion)
            ?? ACPInitializeParams.v1ProtocolVersion
        self.agentCapabilities = try container.decodeIfPresent(ACPAgentCapabilities.self, forKey: .agentCapabilities)
        self.authMethods = try container.decodeIfPresent([ACPAuthMethod].self, forKey: .authMethods)
        self.agentInfo = try container.decodeIfPresent(ACPImplementation.self, forKey: .agentInfo)
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case agentCapabilities
        case authMethods
        case agentInfo
    }
}

public struct ACPAuthenticateParams: Equatable, Sendable, Codable {
    public var methodId: String

    public init(methodId: String) {
        self.methodId = methodId
    }
}

// MARK: - Session Setup & Lifecycle

public struct ACPEnvVariable: Equatable, Sendable, Codable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct ACPHTTPHeader: Equatable, Sendable, Codable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public enum ACPMCPServer: Equatable, Sendable, Codable {
    case stdio(name: String, command: String, args: [String], env: [ACPEnvVariable])
    case http(name: String, url: String, headers: [ACPHTTPHeader])

    public init(from server: AgentSessionRequest.MCPServer) {
        switch server {
        case .stdio(let name, let command, let arguments, let environment):
            let envList = environment.keys.sorted().map { ACPEnvVariable(name: $0, value: environment[$0] ?? "") }
            self = .stdio(name: name, command: command, args: arguments, env: envList)
        case .http(let name, let url, let headers):
            let headerList = headers.keys.sorted().map { ACPHTTPHeader(name: $0, value: headers[$0] ?? "") }
            self = .http(name: name, url: url, headers: headerList)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        let name = try container.decode(String.self, forKey: .name)
        if type == "http" || container.contains(.url) {
            let url = try container.decode(String.self, forKey: .url)
            let headers = try container.decodeIfPresent([ACPHTTPHeader].self, forKey: .headers) ?? []
            self = .http(name: name, url: url, headers: headers)
        } else {
            let command = try container.decode(String.self, forKey: .command)
            let args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
            let env = try container.decodeIfPresent([ACPEnvVariable].self, forKey: .env) ?? []
            self = .stdio(name: name, command: command, args: args, env: env)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stdio(let name, let command, let args, let env):
            try container.encode(name, forKey: .name)
            try container.encode(command, forKey: .command)
            try container.encode(args, forKey: .args)
            try container.encode(env, forKey: .env)
        case .http(let name, let url, let headers):
            try container.encode("http", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(url, forKey: .url)
            try container.encode(headers, forKey: .headers)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case command
        case args
        case env
        case url
        case headers
    }
}

public struct ACPSessionNewParams: Equatable, Sendable, Codable {
    public var cwd: String
    public var mcpServers: [ACPMCPServer]
    public var additionalDirectories: [String]?
    public var _meta: [String: ACPJSONValue]?

    public init(
        cwd: String,
        mcpServers: [ACPMCPServer] = [],
        additionalDirectories: [String]? = nil,
        _meta: [String: ACPJSONValue]? = nil
    ) {
        self.cwd = cwd
        self.mcpServers = mcpServers
        self.additionalDirectories = additionalDirectories
        self._meta = _meta
    }
}

public struct ACPSessionLoadParams: Equatable, Sendable, Codable {
    public var sessionId: String
    public var cwd: String
    public var mcpServers: [ACPMCPServer]
    public var additionalDirectories: [String]?
    public var _meta: [String: ACPJSONValue]?

    public init(
        sessionId: String,
        cwd: String,
        mcpServers: [ACPMCPServer] = [],
        additionalDirectories: [String]? = nil,
        _meta: [String: ACPJSONValue]? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.mcpServers = mcpServers
        self.additionalDirectories = additionalDirectories
        self._meta = _meta
    }
}

public struct ACPSessionResumeParams: Equatable, Sendable, Codable {
    public var sessionId: String
    public var cwd: String
    public var mcpServers: [ACPMCPServer]?
    public var additionalDirectories: [String]?
    public var _meta: [String: ACPJSONValue]?

    public init(
        sessionId: String,
        cwd: String,
        mcpServers: [ACPMCPServer]? = nil,
        additionalDirectories: [String]? = nil,
        _meta: [String: ACPJSONValue]? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.mcpServers = mcpServers
        self.additionalDirectories = additionalDirectories
        self._meta = _meta
    }
}

public struct ACPSessionCloseParams: Equatable, Sendable, Codable {
    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct ACPSessionMode: Equatable, Sendable, Codable {
    public var id: String
    public var name: String
    public var description: String?

    public init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public struct ACPSessionModeState: Equatable, Sendable, Codable {
    public var currentModeId: String
    public var availableModes: [ACPSessionMode]

    public init(currentModeId: String, availableModes: [ACPSessionMode]) {
        self.currentModeId = currentModeId
        self.availableModes = availableModes
    }
}

public enum ACPConfigOptionValue: Equatable, Sendable, Codable {
    case string(String)
    case bool(Bool)

    public init(_ configValue: AgentConfigValue) {
        switch configValue {
        case .string(let s): self = .string(s)
        case .bool(let b): self = .bool(b)
        }
    }

    public var agentConfigValue: AgentConfigValue {
        switch self {
        case .string(let s): return .string(s)
        case .bool(let b): return .bool(b)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Config option value must be string or bool")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .bool(let b): try container.encode(b)
        }
    }
}

public struct ACPSessionConfigSelectOption: Equatable, Sendable, Codable {
    public var value: String
    public var name: String
    public var description: String?

    public init(value: String, name: String, description: String? = nil) {
        self.value = value
        self.name = name
        self.description = description
    }
}

public enum ACPSessionConfigSelectItem: Equatable, Sendable, Codable {
    case option(ACPSessionConfigSelectOption)
    case group(group: String, name: String, options: [ACPSessionConfigSelectOption])

    public var flattenedOptions: [ACPSessionConfigSelectOption] {
        switch self {
        case .option(let opt): return [opt]
        case .group(_, _, let opts): return opts
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.value) {
            self = .option(try ACPSessionConfigSelectOption(from: decoder))
        } else {
            let group = try container.decode(String.self, forKey: .group)
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? group
            let options = try container.decodeIfPresent([ACPSessionConfigSelectOption].self, forKey: .options) ?? []
            self = .group(group: group, name: name, options: options)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .option(let opt):
            try opt.encode(to: encoder)
        case .group(let group, let name, let options):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(group, forKey: .group)
            try container.encode(name, forKey: .name)
            try container.encode(options, forKey: .options)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case group
        case name
        case options
    }
}

public struct ACPSessionConfigOption: Equatable, Sendable, Codable {
    public var id: String
    public var name: String
    public var description: String?
    public var category: String?
    public var type: String
    public var currentValue: ACPConfigOptionValue
    public var options: [ACPSessionConfigSelectItem]?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        category: String? = nil,
        type: String,
        currentValue: ACPConfigOptionValue,
        options: [ACPSessionConfigSelectItem]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.type = type
        self.currentValue = currentValue
        self.options = options
    }

    public var flattenedSelectOptions: [ACPSessionConfigSelectOption] {
        (options ?? []).flatMap(\.flattenedOptions)
    }
}

public struct ACPSessionSetupResult: Equatable, Sendable, Codable {
    public var sessionId: String?
    public var modes: ACPSessionModeState?
    public var models: ACPJSONValue?
    public var configOptions: [ACPSessionConfigOption]?
    public var _meta: [String: ACPJSONValue]?

    public init(
        sessionId: String? = nil,
        modes: ACPSessionModeState? = nil,
        models: ACPJSONValue? = nil,
        configOptions: [ACPSessionConfigOption]? = nil,
        _meta: [String: ACPJSONValue]? = nil
    ) {
        self.sessionId = sessionId
        self.modes = modes
        self.models = models
        self.configOptions = configOptions
        self._meta = _meta
    }
}

// MARK: - Prompt, Cancel & Config Updates

public enum ACPContentBlock: Equatable, Sendable, Codable {
    case text(String)
    case image(data: String, mimeType: String, uri: String? = nil)
    case resourceLink(
        uri: String,
        name: String,
        mimeType: String? = nil,
        title: String? = nil,
        description: String? = nil,
        size: Int? = nil
    )
    case unknown(type: String, rawJSON: ACPJSONValue)

    public init(from decoder: Decoder) throws {
        let raw = try ACPJSONValue(from: decoder)
        guard case .object(let obj) = raw,
              let blockType = obj["type"]?.stringValue else {
            self = .unknown(type: "unknown", rawJSON: raw)
            return
        }
        switch blockType {
        case "text":
            self = .text(obj["text"]?.stringValue ?? "")
        case "image":
            self = .image(
                data: obj["data"]?.stringValue ?? "",
                mimeType: obj["mimeType"]?.stringValue ?? "application/octet-stream",
                uri: obj["uri"]?.stringValue
            )
        case "resource_link":
            self = .resourceLink(
                uri: obj["uri"]?.stringValue ?? "",
                name: obj["name"]?.stringValue ?? "",
                mimeType: obj["mimeType"]?.stringValue,
                title: obj["title"]?.stringValue,
                description: obj["description"]?.stringValue,
                size: obj["size"]?.intValue
            )
        default:
            self = .unknown(type: blockType, rawJSON: raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType, let uri):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(uri, forKey: .uri)
        case .resourceLink(let uri, let name, let mimeType, let title, let description, let size):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("resource_link", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(size, forKey: .size)
        case .unknown(_, let rawJSON):
            try rawJSON.encode(to: encoder)
        }
    }

    public var textContent: String? {
        if case .text(let text) = self { return text }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case data
        case mimeType
        case uri
        case name
        case title
        case description
        case size
    }
}

public struct ACPPromptParams: Equatable, Sendable, Codable {
    public var sessionId: String
    public var prompt: [ACPContentBlock]

    public init(sessionId: String, prompt: [ACPContentBlock]) {
        self.sessionId = sessionId
        self.prompt = prompt
    }
}

public struct ACPUsage: Equatable, Sendable, Codable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedReadTokens: Int?
    public var cachedWriteTokens: Int?
    public var thoughtTokens: Int?
    public var totalTokens: Int?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cachedReadTokens: Int? = nil,
        cachedWriteTokens: Int? = nil,
        thoughtTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedReadTokens = cachedReadTokens
        self.cachedWriteTokens = cachedWriteTokens
        self.thoughtTokens = thoughtTokens
        self.totalTokens = totalTokens
    }
}

public struct ACPPromptResult: Equatable, Sendable, Codable {
    public var stopReason: String
    public var usage: ACPUsage?
    public var _meta: [String: ACPJSONValue]?

    public init(stopReason: String, usage: ACPUsage? = nil, _meta: [String: ACPJSONValue]? = nil) {
        self.stopReason = stopReason
        self.usage = usage
        self._meta = _meta
    }
}

public struct ACPSessionCancelParams: Equatable, Sendable, Codable {
    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

public struct ACPSetSessionModeParams: Equatable, Sendable, Codable {
    public var sessionId: String
    public var modeId: String

    public init(sessionId: String, modeId: String) {
        self.sessionId = sessionId
        self.modeId = modeId
    }
}

public struct ACPSetSessionConfigOptionParams: Equatable, Sendable, Codable {
    public var sessionId: String
    public var configId: String
    public var value: ACPConfigOptionValue

    public init(sessionId: String, configId: String, value: ACPConfigOptionValue) {
        self.sessionId = sessionId
        self.configId = configId
        self.value = value
    }
}

public struct ACPSetSessionConfigOptionResult: Equatable, Sendable, Codable {
    public var configOptions: [ACPSessionConfigOption]?

    public init(configOptions: [ACPSessionConfigOption]? = nil) {
        self.configOptions = configOptions
    }
}

// MARK: - Session Updates

public struct ACPToolCallLocation: Equatable, Sendable, Codable {
    public var path: String
    public var line: Int?

    public init(path: String, line: Int? = nil) {
        self.path = path
        self.line = line
    }
}

public enum ACPToolCallContent: Equatable, Sendable, Codable {
    case content(ACPContentBlock)
    case diff(path: String, oldText: String?, newText: String)
    case terminal(terminalId: String)
    case unknown(type: String, rawJSON: ACPJSONValue)

    public init(from decoder: Decoder) throws {
        let raw = try ACPJSONValue(from: decoder)
        guard case .object(let obj) = raw,
              let kind = obj["type"]?.stringValue else {
            self = .unknown(type: "unknown", rawJSON: raw)
            return
        }
        switch kind {
        case "content":
            if let inner = obj["content"], let block = try? inner.decode(ACPContentBlock.self) {
                self = .content(block)
            } else {
                self = .unknown(type: kind, rawJSON: raw)
            }
        case "text":
            self = .content(.text(obj["text"]?.stringValue ?? ""))
        case "diff":
            self = .diff(
                path: obj["path"]?.stringValue ?? "",
                oldText: obj["oldText"]?.stringValue,
                newText: obj["newText"]?.stringValue ?? ""
            )
        case "terminal":
            self = .terminal(terminalId: obj["terminalId"]?.stringValue ?? "")
        default:
            self = .unknown(type: kind, rawJSON: raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .content(let block):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("content", forKey: .type)
            try container.encode(block, forKey: .content)
        case .diff(let path, let oldText, let newText):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("diff", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(oldText, forKey: .oldText)
            try container.encode(newText, forKey: .newText)
        case .terminal(let terminalId):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("terminal", forKey: .type)
            try container.encode(terminalId, forKey: .terminalId)
        case .unknown(_, let rawJSON):
            try rawJSON.encode(to: encoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case path
        case oldText
        case newText
        case terminalId
    }
}

public struct ACPToolCall: Equatable, Sendable, Codable {
    public var toolCallId: String
    public var title: String?
    public var kind: String?
    public var status: String?
    public var content: [ACPToolCallContent]?
    public var locations: [ACPToolCallLocation]?
    public var rawInput: ACPJSONValue?
    public var rawOutput: ACPJSONValue?
    public var _meta: [String: ACPJSONValue]?

    public init(
        toolCallId: String,
        title: String? = nil,
        kind: String? = nil,
        status: String? = nil,
        content: [ACPToolCallContent]? = nil,
        locations: [ACPToolCallLocation]? = nil,
        rawInput: ACPJSONValue? = nil,
        rawOutput: ACPJSONValue? = nil,
        _meta: [String: ACPJSONValue]? = nil
    ) {
        self.toolCallId = toolCallId
        self.title = title
        self.kind = kind
        self.status = status
        self.content = content
        self.locations = locations
        self.rawInput = rawInput
        self.rawOutput = rawOutput
        self._meta = _meta
    }
}

public typealias ACPToolCallUpdate = ACPToolCall

public struct ACPPlanEntry: Equatable, Sendable, Codable {
    public var content: String
    public var priority: String?
    public var status: String

    public init(content: String, priority: String? = nil, status: String = "pending") {
        self.content = content
        self.priority = priority
        self.status = status
    }
}

public struct ACPCommandInput: Equatable, Sendable, Codable {
    public var hint: String?

    public init(hint: String? = nil) {
        self.hint = hint
    }
}

public struct ACPAvailableCommand: Equatable, Sendable, Codable {
    public var name: String
    public var description: String?
    public var input: ACPCommandInput?

    public init(name: String, description: String? = nil, input: ACPCommandInput? = nil) {
        self.name = name
        self.description = description
        self.input = input
    }
}

public struct ACPSessionInfoUpdate: Equatable, Sendable, Codable {
    public var title: String?
    public var updatedAt: String?
    public var _meta: [String: ACPJSONValue]?

    public init(title: String? = nil, updatedAt: String? = nil, _meta: [String: ACPJSONValue]? = nil) {
        self.title = title
        self.updatedAt = updatedAt
        self._meta = _meta
    }
}

public struct ACPCost: Equatable, Sendable, Codable {
    public var amount: Double
    public var currency: String

    public init(amount: Double, currency: String = "USD") {
        self.amount = amount
        self.currency = currency
    }
}

public struct ACPUsageUpdate: Equatable, Sendable, Codable {
    public var used: Int?
    public var size: Int?
    public var cost: ACPCost?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedTokens: Int?
    public var _meta: [String: ACPJSONValue]?

    public init(
        used: Int? = nil,
        size: Int? = nil,
        cost: ACPCost? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cachedTokens: Int? = nil,
        _meta: [String: ACPJSONValue]? = nil
    ) {
        self.used = used
        self.size = size
        self.cost = cost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self._meta = _meta
    }
}

public enum ACPSessionUpdate: Equatable, Sendable, Codable {
    case agentMessageChunk(ACPContentBlock)
    case agentThoughtChunk(ACPContentBlock)
    case userMessageChunk(ACPContentBlock)
    case toolCall(ACPToolCall)
    case toolCallUpdate(ACPToolCallUpdate)
    case plan([ACPPlanEntry])
    case availableCommandsUpdate([ACPAvailableCommand])
    case currentModeUpdate(String)
    case configOptionUpdate([ACPSessionConfigOption])
    case sessionInfoUpdate(ACPSessionInfoUpdate)
    case usageUpdate(ACPUsageUpdate)
    case unknown(kind: String, rawJSON: ACPJSONValue)

    public init(from decoder: Decoder) throws {
        let raw = try ACPJSONValue(from: decoder)
        guard case .object(let obj) = raw,
              let kind = obj["sessionUpdate"]?.stringValue else {
            self = .unknown(kind: "unknown", rawJSON: raw)
            return
        }
        switch kind {
        case "agent_message_chunk":
            if let content = obj["content"], let block = try? content.decode(ACPContentBlock.self) {
                self = .agentMessageChunk(block)
            } else {
                self = .unknown(kind: kind, rawJSON: raw)
            }
        case "agent_thought_chunk":
            if let content = obj["content"], let block = try? content.decode(ACPContentBlock.self) {
                self = .agentThoughtChunk(block)
            } else {
                self = .unknown(kind: kind, rawJSON: raw)
            }
        case "user_message_chunk":
            if let content = obj["content"], let block = try? content.decode(ACPContentBlock.self) {
                self = .userMessageChunk(block)
            } else {
                self = .unknown(kind: kind, rawJSON: raw)
            }
        case "tool_call":
            if let call = try? raw.decode(ACPToolCall.self) {
                self = .toolCall(call)
            } else {
                self = .unknown(kind: kind, rawJSON: raw)
            }
        case "tool_call_update":
            if let call = try? raw.decode(ACPToolCallUpdate.self) {
                self = .toolCallUpdate(call)
            } else {
                self = .unknown(kind: kind, rawJSON: raw)
            }
        case "plan":
            let entries = (try? obj["entries"]?.decode([ACPPlanEntry].self)) ?? []
            self = .plan(entries)
        case "available_commands_update":
            let commands = (try? obj["availableCommands"]?.decode([ACPAvailableCommand].self)) ?? []
            self = .availableCommandsUpdate(commands)
        case "current_mode_update":
            if let modeId = obj["currentModeId"]?.stringValue {
                self = .currentModeUpdate(modeId)
            } else {
                self = .unknown(kind: kind, rawJSON: raw)
            }
        case "config_option_update":
            let options = (try? obj["configOptions"]?.decode([ACPSessionConfigOption].self)) ?? []
            self = .configOptionUpdate(options)
        case "session_info_update":
            let info = (try? raw.decode(ACPSessionInfoUpdate.self)) ?? ACPSessionInfoUpdate()
            self = .sessionInfoUpdate(info)
        case "usage_update":
            let usage = (try? raw.decode(ACPUsageUpdate.self)) ?? ACPUsageUpdate()
            self = .usageUpdate(usage)
        default:
            self = .unknown(kind: kind, rawJSON: raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .agentMessageChunk(let block):
            let payload: ACPJSONValue = .object([
                "sessionUpdate": .string("agent_message_chunk"),
                "content": (try? ACPJSONValue.fromEncodable(block)) ?? .null,
            ])
            try payload.encode(to: encoder)
        case .agentThoughtChunk(let block):
            let payload: ACPJSONValue = .object([
                "sessionUpdate": .string("agent_thought_chunk"),
                "content": (try? ACPJSONValue.fromEncodable(block)) ?? .null,
            ])
            try payload.encode(to: encoder)
        case .userMessageChunk(let block):
            let payload: ACPJSONValue = .object([
                "sessionUpdate": .string("user_message_chunk"),
                "content": (try? ACPJSONValue.fromEncodable(block)) ?? .null,
            ])
            try payload.encode(to: encoder)
        case .toolCall(let call):
            var obj = (try? ACPJSONValue.fromEncodable(call))?.objectValue ?? [:]
            obj["sessionUpdate"] = .string("tool_call")
            try ACPJSONValue.object(obj).encode(to: encoder)
        case .toolCallUpdate(let update):
            var obj = (try? ACPJSONValue.fromEncodable(update))?.objectValue ?? [:]
            obj["sessionUpdate"] = .string("tool_call_update")
            try ACPJSONValue.object(obj).encode(to: encoder)
        case .plan(let entries):
            let payload: ACPJSONValue = .object([
                "sessionUpdate": .string("plan"),
                "entries": (try? ACPJSONValue.fromEncodable(entries)) ?? .array([]),
            ])
            try payload.encode(to: encoder)
        case .availableCommandsUpdate(let commands):
            let payload: ACPJSONValue = .object([
                "sessionUpdate": .string("available_commands_update"),
                "availableCommands": (try? ACPJSONValue.fromEncodable(commands)) ?? .array([]),
            ])
            try payload.encode(to: encoder)
        case .currentModeUpdate(let currentModeId):
            let payload: ACPJSONValue = .object([
                "sessionUpdate": .string("current_mode_update"),
                "currentModeId": .string(currentModeId),
            ])
            try payload.encode(to: encoder)
        case .configOptionUpdate(let options):
            let payload: ACPJSONValue = .object([
                "sessionUpdate": .string("config_option_update"),
                "configOptions": (try? ACPJSONValue.fromEncodable(options)) ?? .array([]),
            ])
            try payload.encode(to: encoder)
        case .sessionInfoUpdate(let info):
            var obj = (try? ACPJSONValue.fromEncodable(info))?.objectValue ?? [:]
            obj["sessionUpdate"] = .string("session_info_update")
            try ACPJSONValue.object(obj).encode(to: encoder)
        case .usageUpdate(let usage):
            var obj = (try? ACPJSONValue.fromEncodable(usage))?.objectValue ?? [:]
            obj["sessionUpdate"] = .string("usage_update")
            try ACPJSONValue.object(obj).encode(to: encoder)
        case .unknown(_, let rawJSON):
            try rawJSON.encode(to: encoder)
        }
    }
}

public struct ACPSessionNotification: Equatable, Sendable, Codable {
    public var sessionId: String
    public var update: ACPSessionUpdate
    public var _meta: [String: ACPJSONValue]?

    public init(sessionId: String, update: ACPSessionUpdate, _meta: [String: ACPJSONValue]? = nil) {
        self.sessionId = sessionId
        self.update = update
        self._meta = _meta
    }
}

// MARK: - Permission Requests

public enum ACPPermissionOptionKind: String, Equatable, Sendable, Codable, CaseIterable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case rejectOnce = "reject_once"
    case rejectAlways = "reject_always"
}

public struct ACPPermissionOption: Equatable, Sendable, Codable {
    public var optionId: String
    public var name: String
    public var kind: ACPPermissionOptionKind

    public init(optionId: String, name: String, kind: ACPPermissionOptionKind) {
        self.optionId = optionId
        self.name = name
        self.kind = kind
    }
}

public struct ACPRequestPermissionParams: Equatable, Sendable, Codable {
    public var sessionId: String
    public var toolCall: ACPToolCallUpdate
    public var options: [ACPPermissionOption]
    public var _meta: [String: ACPJSONValue]?

    public init(
        sessionId: String,
        toolCall: ACPToolCallUpdate,
        options: [ACPPermissionOption],
        _meta: [String: ACPJSONValue]? = nil
    ) {
        self.sessionId = sessionId
        self.toolCall = toolCall
        self.options = options
        self._meta = _meta
    }
}

public enum ACPPermissionOutcome: Equatable, Sendable, Codable {
    case selected(optionId: String)
    case cancelled

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .outcome)
        switch kind {
        case "selected":
            let optionId = try container.decode(String.self, forKey: .optionId)
            self = .selected(optionId: optionId)
        case "cancelled":
            self = .cancelled
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .outcome,
                in: container,
                debugDescription: "Unknown permission outcome \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .selected(let optionId):
            try container.encode("selected", forKey: .outcome)
            try container.encode(optionId, forKey: .optionId)
        case .cancelled:
            try container.encode("cancelled", forKey: .outcome)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case outcome
        case optionId
    }
}

public struct ACPRequestPermissionResult: Equatable, Sendable, Codable {
    public var outcome: ACPPermissionOutcome

    public init(outcome: ACPPermissionOutcome) {
        self.outcome = outcome
    }
}

// MARK: - Client Files & Terminals

public struct ACPReadTextFileParams: Equatable, Sendable, Codable {
    public var sessionId: String?
    public var path: String
    public var line: Int?
    public var limit: Int?

    public init(sessionId: String? = nil, path: String, line: Int? = nil, limit: Int? = nil) {
        self.sessionId = sessionId
        self.path = path
        self.line = line
        self.limit = limit
    }
}

public struct ACPReadTextFileResult: Equatable, Sendable, Codable {
    public var content: String

    public init(content: String) {
        self.content = content
    }
}

public struct ACPWriteTextFileParams: Equatable, Sendable, Codable {
    public var sessionId: String?
    public var path: String
    public var content: String

    public init(sessionId: String? = nil, path: String, content: String) {
        self.sessionId = sessionId
        self.path = path
        self.content = content
    }
}

public struct ACPTerminalCreateParams: Equatable, Sendable, Codable {
    public var sessionId: String?
    public var command: String
    public var args: [String]?
    public var env: [ACPEnvVariable]?
    public var cwd: String?
    public var outputByteLimit: Int?

    public init(
        sessionId: String? = nil,
        command: String,
        args: [String]? = nil,
        env: [ACPEnvVariable]? = nil,
        cwd: String? = nil,
        outputByteLimit: Int? = nil
    ) {
        self.sessionId = sessionId
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.outputByteLimit = outputByteLimit
    }
}

public struct ACPTerminalCreateResult: Equatable, Sendable, Codable {
    public var terminalId: String

    public init(terminalId: String) {
        self.terminalId = terminalId
    }
}

public struct ACPTerminalOutputParams: Equatable, Sendable, Codable {
    public var sessionId: String?
    public var terminalId: String

    public init(sessionId: String? = nil, terminalId: String) {
        self.sessionId = sessionId
        self.terminalId = terminalId
    }
}

public struct ACPTerminalExitStatus: Equatable, Sendable, Codable {
    public var exitCode: Int?
    public var signal: String?

    public init(exitCode: Int? = nil, signal: String? = nil) {
        self.exitCode = exitCode
        self.signal = signal
    }
}

public struct ACPTerminalOutputResult: Equatable, Sendable, Codable {
    public var output: String
    public var truncated: Bool
    public var exitStatus: ACPTerminalExitStatus?

    public init(output: String, truncated: Bool, exitStatus: ACPTerminalExitStatus? = nil) {
        self.output = output
        self.truncated = truncated
        self.exitStatus = exitStatus
    }
}

public struct ACPTerminalWaitForExitParams: Equatable, Sendable, Codable {
    public var sessionId: String?
    public var terminalId: String

    public init(sessionId: String? = nil, terminalId: String) {
        self.sessionId = sessionId
        self.terminalId = terminalId
    }
}

public struct ACPTerminalKillParams: Equatable, Sendable, Codable {
    public var sessionId: String?
    public var terminalId: String

    public init(sessionId: String? = nil, terminalId: String) {
        self.sessionId = sessionId
        self.terminalId = terminalId
    }
}

public struct ACPTerminalReleaseParams: Equatable, Sendable, Codable {
    public var sessionId: String?
    public var terminalId: String

    public init(sessionId: String? = nil, terminalId: String) {
        self.sessionId = sessionId
        self.terminalId = terminalId
    }
}

// MARK: - Elicitation

public struct ACPElicitationCreateParams: Equatable, Sendable, Codable {
    public var sessionId: String?
    public var mode: String?
    public var title: String?
    public var message: String
    public var url: String?
    public var elicitationId: String?
    public var requestedSchema: ACPJSONValue?
    public var _meta: [String: ACPJSONValue]?

    public init(
        sessionId: String? = nil,
        mode: String? = nil,
        title: String? = nil,
        message: String,
        url: String? = nil,
        elicitationId: String? = nil,
        requestedSchema: ACPJSONValue? = nil,
        _meta: [String: ACPJSONValue]? = nil
    ) {
        self.sessionId = sessionId
        self.mode = mode
        self.title = title
        self.message = message
        self.url = url
        self.elicitationId = elicitationId
        self.requestedSchema = requestedSchema
        self._meta = _meta
    }
}

public enum ACPElicitationAction: String, Equatable, Sendable, Codable {
    case accept
    case decline
    case cancel
}

public struct ACPElicitationCreateResult: Equatable, Sendable, Codable {
    public var action: ACPElicitationAction
    public var content: [String: ACPJSONValue]?

    public init(action: ACPElicitationAction, content: [String: ACPJSONValue]? = nil) {
        self.action = action
        self.content = content
    }
}
