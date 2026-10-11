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

/// What ties an answer to its request: a whole number or a string, chosen by
/// whoever sends the request.
public enum RPCID: Hashable, Sendable {
    case number(Int)
    case string(String)
}

extension RPCID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

/// Why a request was not done.
public struct RPCErrorObject: Codable, Equatable, Sendable, Error {
    public let code: Int
    /// A few English words for a log. Never shown to the person as it is.
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case code, message, data
    }

    /// The two refusals that say more (`notInUses`, `permissionMissing`)
    /// say it as a `RefusalData`. With either code, data that is anything
    /// else is not read.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        data = try container.decodeIfPresent(JSONValue.self, forKey: .data)
        let named = code == RefusalCode.notInUses.rawValue || code == RefusalCode.permissionMissing.rawValue
        if named, container.contains(.data) {
            guard let data, data.objectValue != nil, (try? data.decode(RefusalData.self)) != nil else {
                throw DecodingError.dataCorruptedError(forKey: .data, in: container,
                                                       debugDescription: "not what this refusal carries")
            }
        }
    }
}

/// The JSON-RPC 2.0 codes for a message that could not be handled at all.
public enum RPCErrorCode {
    /// The line was not JSON.
    public static let parseError = -32700
    /// It was JSON and not a message.
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

/// One JSON-RPC 2.0 message: what one line on the link holds.
public enum RPCMessage: Equatable, Sendable {
    /// A message that is answered.
    case request(id: RPCID, method: String, params: JSONValue?)
    /// A message that is not answered.
    case notice(method: String, params: JSONValue?)
    /// The answer to a request that was done.
    case result(id: RPCID, value: JSONValue)
    /// The answer to a request that was not done. The id is nil when the
    /// request could not be read at all.
    case failure(id: RPCID?, error: RPCErrorObject)
}

extension RPCMessage: Codable {
    private enum Key: String, CodingKey {
        case jsonrpc, id, method, params, result, error
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        func refuse(_ key: Key, _ why: String) -> DecodingError {
            DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: why)
        }
        guard try container.decode(String.self, forKey: .jsonrpc) == "2.0" else {
            throw refuse(.jsonrpc, "jsonrpc is not 2.0")
        }
        if container.contains(.method) {
            guard !container.contains(.result), !container.contains(.error) else {
                throw refuse(.method, "a message is a method or an answer, never both")
            }
            let method = try container.decode(String.self, forKey: .method)
            let params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
            if let params, params.objectValue == nil {
                throw refuse(.params, "params is not an object")
            }
            if container.contains(.id) {
                let id = try container.decode(RPCID.self, forKey: .id)
                self = .request(id: id, method: method, params: params)
            } else {
                self = .notice(method: method, params: params)
            }
        } else if container.contains(.error) {
            guard !container.contains(.result) else {
                throw refuse(.error, "an answer is a result or an error, never both")
            }
            // A null id is allowed here and nowhere else; a missing one is not.
            var id: RPCID?
            if try !container.decodeNil(forKey: .id) {
                id = try container.decode(RPCID.self, forKey: .id)
            }
            let error = try container.decode(RPCErrorObject.self, forKey: .error)
            self = .failure(id: id, error: error)
        } else {
            let id = try container.decode(RPCID.self, forKey: .id)
            let value = try container.decode(JSONValue.self, forKey: .result)
            self = .result(id: id, value: value)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode("2.0", forKey: .jsonrpc)
        switch self {
        case .request(let id, let method, let params):
            try container.encode(id, forKey: .id)
            try container.encode(method, forKey: .method)
            try container.encodeIfPresent(params, forKey: .params)
        case .notice(let method, let params):
            try container.encode(method, forKey: .method)
            try container.encodeIfPresent(params, forKey: .params)
        case .result(let id, let value):
            try container.encode(id, forKey: .id)
            try container.encode(value, forKey: .result)
        case .failure(let id, let error):
            if let id {
                try container.encode(id, forKey: .id)
            } else {
                try container.encodeNil(forKey: .id)
            }
            try container.encode(error, forKey: .error)
        }
    }
}
