// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPTransport: HTTPTransport {
    public static let shared = URLSessionHTTPTransport()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// In-memory HTTP transport stub for unit tests. Never touches the network.
public final class StubHTTPTransport: HTTPTransport, @unchecked Sendable {
    public typealias Handler = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private struct Route {
        let predicate: @Sendable (URLRequest) -> Bool
        let handler: Handler
    }

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var queued: [Result<(Data, HTTPURLResponse), Error>] = []
    private var routes: [Route] = []
    private var fallbackHandler: Handler?

    public init(handler: Handler? = nil) {
        self.fallbackHandler = handler
    }

    public var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    public func reset() {
        lock.withLock {
            _requests.removeAll()
            queued.removeAll()
            routes.removeAll()
        }
    }

    public func setHandler(_ handler: @escaping Handler) {
        lock.withLock {
            fallbackHandler = handler
        }
    }

    public func enqueue(
        status: Int = 200,
        url: URL = URL(string: "http://127.0.0.1")!,
        headers: [String: String] = ["Content-Type": "application/json"],
        body: Data = Data()
    ) {
        let response = Self.makeResponse(url: url, status: status, headers: headers)
        lock.withLock {
            queued.append(.success((body, response)))
        }
    }

    public func enqueue(
        status: Int = 200,
        url: URL = URL(string: "http://127.0.0.1")!,
        headers: [String: String] = ["Content-Type": "application/json"],
        json: String
    ) {
        enqueue(status: status, url: url, headers: headers, body: Data(json.utf8))
    }

    public func enqueue(error: Error) {
        lock.withLock {
            queued.append(.failure(error))
        }
    }

    public func route(
        where predicate: @escaping @Sendable (URLRequest) -> Bool,
        handler: @escaping Handler
    ) {
        lock.withLock {
            routes.append(Route(predicate: predicate, handler: handler))
        }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let nextAction = lock.withLock { () -> (Result<(Data, HTTPURLResponse), Error>?, Handler?) in
            _requests.append(request)
            if !queued.isEmpty {
                return (queued.removeFirst(), nil)
            }
            if let matched = routes.first(where: { $0.predicate(request) }) {
                return (nil, matched.handler)
            }
            return (nil, fallbackHandler)
        }
        if let queuedResult = nextAction.0 {
            let (data, response) = try queuedResult.get()
            if let url = request.url, response.url != url {
                let rebased = Self.makeResponse(
                    url: url,
                    status: response.statusCode,
                    headers: (response.allHeaderFields as? [String: String]) ?? [:]
                )
                return (data, rebased)
            }
            return (data, response)
        }
        if let handler = nextAction.1 {
            return try await handler(request)
        }
        throw URLError(.cannotConnectToHost)
    }

    public static func makeResponse(
        url: URL,
        status: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    /// Reads the request body from `httpBody` or `httpBodyStream`.
    public static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
