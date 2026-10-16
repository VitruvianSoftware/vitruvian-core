// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Network

/// What went wrong talking to the engine.
public enum EngineError: Error, Equatable, Sendable {
    /// hello was refused: the engine speaks another protocol. The app says "update needed".
    case protocolMismatch(engine: Int)
    /// The engine answered with an error. `reason` is invalid_params' data.reason, which names the parameter.
    case rpc(RPCErrorCode, message: String, reason: String?)
    /// No handshake yet, or it was refused, or the connection is closed.
    case notConnected
    /// The connection ended while the call was in flight.
    case disconnected
    /// A request or an answer longer than the protocol's max_frame_bytes.
    case frameTooLarge
    /// An answer that is not what the protocol says it is.
    case badResponse

    /// Only a refused handshake means the app and engine are of different versions.
    public var isUpdateNeeded: Bool {
        if case .protocolMismatch = self { return true }
        return false
    }
}

/// The app's connection to its engine: newline-delimited JSON-RPC 2.0 over the engine's Unix socket.
///
/// `connect()` opens the socket and says hello; only then do `call` and `changes` work. Answers are matched to
/// requests by id, so slow calls (message.send, login.wait) do not hold up others. When the connection ends, every
/// call in flight throws `.disconnected` and every `changes` stream finishes; a client is not reused after that
/// (the supervisor makes a new one for the restarted engine).
public actor EngineClient {
    /// `Courier/<the app's version>`, the client name hello sends.
    public static var defaultClientName: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "Courier/\(version ?? "dev")"
    }

    private let socketPath: String
    private let clientName: String
    private let queue = DispatchQueue(label: "com.vitruviansoftware.courier.engine-client")
    private var connection: NWConnection?
    private var greeted = false
    private var closed = false
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var subscribers: [UUID: AsyncStream<Change>.Continuation] = [:]
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    public init(socketPath: String, client: String = EngineClient.defaultClientName) {
        self.socketPath = socketPath
        self.clientName = client
    }

    /// True once the connection has ended (or was never made and `close()` was called).
    public var isClosed: Bool { closed }

    /// Opens the socket and says hello. Throws `.protocolMismatch` when the engine speaks another protocol.
    @discardableResult
    public func connect() async throws -> HelloResult {
        guard connection == nil, !closed else { throw EngineError.notConnected }
        let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        self.connection = connection
        do {
            try await Self.open(connection, on: queue)
        } catch {
            close()
            throw error
        }
        Task { await self.receiveLoop(connection) }
        do {
            let hello: HelloResult = try await send("hello", HelloParams(client: clientName))
            greeted = true
            return hello
        } catch {
            // A refused handshake leaves nothing to talk about.
            close()
            throw error
        }
    }

    /// Calls a method once hello has succeeded. Params are encoded as given: leave optional keys nil, and they are
    /// left out (the engine refuses keys a method does not take).
    public func call<P: Encodable, R: Decodable>(_ method: String, _ params: P) async throws -> R {
        guard greeted, !closed else { throw EngineError.notConnected }
        return try await send(method, params)
    }

    /// The engine's changed notifications, from now on. Each access is a stream of its own; subscribe before you
    /// read, so nothing that changes in between is missed. The stream finishes when the connection ends.
    public var changes: AsyncStream<Change> {
        let (stream, continuation) = AsyncStream.makeStream(of: Change.self)
        if closed {
            continuation.finish()
            return stream
        }
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    /// Ends the connection. Calls in flight throw `.disconnected`.
    public func close() {
        guard !closed else { return }
        closed = true
        greeted = false
        connection?.cancel()
        let calls = pending
        pending = [:]
        for call in calls.values { call.resume(throwing: EngineError.disconnected) }
        for subscriber in subscribers.values { subscriber.finish() }
        subscribers = [:]
        let waiters = closeWaiters
        closeWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// Returns once the connection has ended, from either side.
    public func waitUntilClosed() async {
        if closed { return }
        await withCheckedContinuation { closeWaiters.append($0) }
    }

    // MARK: - Sending

    private struct Request<P: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: Int
        let method: String
        let params: P
    }

    private struct Response<R: Decodable>: Decodable {
        let result: R?
        let error: ErrorObject?
    }

    private struct ErrorObject: Decodable {
        let code: Int
        let message: String
        let data: JSONValue?
    }

    private func send<P: Encodable, R: Decodable>(_ method: String, _ params: P) async throws -> R {
        guard let connection, !closed else { throw EngineError.notConnected }
        let id = nextID
        nextID += 1
        var line = try JSONEncoder().encode(Request(id: id, method: method, params: params))
        guard line.count <= CourierProtocol.maxFrameBytes else { throw EngineError.frameTooLarge }
        line.append(0x0A)

        let answer = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pending[id] = continuation
            connection.send(content: line, completion: .contentProcessed { error in
                guard error != nil else { return }
                Task { await self.close() }
            })
        }
        let response: Response<R>
        do {
            response = try JSONDecoder().decode(Response<R>.self, from: answer)
        } catch {
            throw EngineError.badResponse
        }
        if let error = response.error { throw Self.engineError(error) }
        guard let result = response.result else { throw EngineError.badResponse }
        return result
    }

    private static func engineError(_ error: ErrorObject) -> EngineError {
        let code = RPCErrorCode(number: error.code)
        if code == .protocolMismatch, case let .int(engine)? = error.data?["engine"] {
            return .protocolMismatch(engine: Int(engine))
        }
        return .rpc(code, message: error.message, reason: error.data?["reason"]?.stringValue)
    }

    // MARK: - Receiving

    /// The parts of a line that say what it is. Decoding ignores the rest (result, params).
    private struct Header: Decodable {
        let id: Int?
        let method: String?
    }

    private struct Notification: Decodable {
        let params: Changed
    }

    private func receiveLoop(_ connection: NWConnection) async {
        var buffer = Data()
        while !closed {
            let (data, isComplete, failed) = await Self.receive(on: connection)
            if let data { buffer.append(data) }
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex ..< newline])
                buffer = Data(buffer[buffer.index(after: newline)...])
                handle(line)
            }
            // A line the protocol would not allow: the engine is not speaking it.
            if buffer.count > CourierProtocol.maxFrameBytes || isComplete || failed {
                close()
                return
            }
        }
    }

    private func handle(_ line: Data) {
        guard let header = try? JSONDecoder().decode(Header.self, from: line) else { return }
        if let id = header.id {
            pending.removeValue(forKey: id)?.resume(returning: line)
        } else if header.method == ProtocolMethods.changedNotification,
                  let notification = try? JSONDecoder().decode(Notification.self, from: line) {
            let change = Change(notification.params)
            for subscriber in subscribers.values { subscriber.yield(change) }
        }
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    // MARK: - Network.framework, as async

    /// Waits for the connection to be ready. A Unix socket nobody listens on is `.waiting` (connection refused, or
    /// no such file), not `.failed`: either way it is an error here, not something to wait out.
    private static func open(_ connection: NWConnection, on queue: DispatchQueue) async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                case let .waiting(error), let .failed(error):
                    once.run { continuation.resume(throwing: error) }
                case .cancelled:
                    once.run { continuation.resume(throwing: EngineError.disconnected) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
        // From here the receive loop notices the end; this handler only frees the continuation above.
        connection.stateUpdateHandler = nil
    }

    private static func receive(on connection: NWConnection) async -> (Data?, Bool, Bool) {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, isComplete, error in
                continuation.resume(returning: (data, isComplete, error != nil))
            }
        }
    }
}

/// Runs a closure once, from whichever thread gets there first.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        let first = lock.withLock { () -> Bool in
            defer { done = true }
            return !done
        }
        if first { body() }
    }
}
