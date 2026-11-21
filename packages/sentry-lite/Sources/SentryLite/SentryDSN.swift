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

public struct SentryDSN: Sendable, Equatable {
    public let rawValue: String
    public let publicKey: String
    public let projectId: String
    public let storeEndpointURL: URL

    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host,
              let user = url.user, !user.isEmpty else {
            return nil
        }

        let pathSegments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let lastSegment = pathSegments.last, !lastSegment.isEmpty else {
            return nil
        }

        self.rawValue = trimmed
        self.publicKey = user
        self.projectId = lastSegment

        let scheme = url.scheme ?? "https"
        let portPart = url.port.map { ":\($0)" } ?? ""
        let prefix: String
        if pathSegments.count > 1 {
            let baseSegments = pathSegments.dropLast().joined(separator: "/")
            prefix = "/\(baseSegments)"
        } else {
            prefix = ""
        }

        let endpointString = "\(scheme)://\(host)\(portPart)\(prefix)/api/\(self.projectId)/store/"
        guard let endpointURL = URL(string: endpointString) else {
            return nil
        }
        self.storeEndpointURL = endpointURL
    }

    public var authHeader: String {
        "Sentry sentry_version=7, sentry_client=sentry-lite-swift/1.0.0, sentry_key=\(publicKey)"
    }
}
