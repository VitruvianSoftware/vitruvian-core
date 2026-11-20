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

public enum SentryLevel: String, Codable, Sendable {
    case fatal
    case error
    case warning
    case info
    case debug
}

public struct SentryMessage: Codable, Sendable {
    public let formatted: String

    public init(formatted: String) {
        self.formatted = formatted
    }
}

public struct SentryExceptionValue: Codable, Sendable {
    public let type: String
    public let value: String

    public init(type: String, value: String) {
        self.type = type
        self.value = value
    }
}

public struct SentryExceptionList: Codable, Sendable {
    public let values: [SentryExceptionValue]

    public init(values: [SentryExceptionValue]) {
        self.values = values
    }
}

public struct SentryEvent: Codable, Sendable {
    public let event_id: String
    public let timestamp: Double
    public let platform: String
    public let level: SentryLevel
    public let release: String?
    public let environment: String?
    public let message: SentryMessage?
    public let exception: SentryExceptionList?
    public let tags: [String: String]?
    public let extra: [String: String]?

    public init(
        level: SentryLevel = .info,
        message: String? = nil,
        error: Error? = nil,
        release: String? = nil,
        environment: String? = nil,
        tags: [String: String]? = nil,
        extra: [String: String]? = nil
    ) {
        self.event_id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        self.timestamp = Date().timeIntervalSince1970
        self.platform = "cocoa"
        self.level = level
        self.release = release
        self.environment = environment
        self.message = message.map { SentryMessage(formatted: $0) }
        if let err = error {
            let nsErr = err as NSError
            self.exception = SentryExceptionList(values: [
                SentryExceptionValue(
                    type: "\(type(of: err)) (\(nsErr.domain):\(nsErr.code))",
                    value: nsErr.localizedDescription
                )
            ])
        } else {
            self.exception = nil
        }
        self.tags = tags
        self.extra = extra
    }
}
