// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Network

/// What went wrong talking to the engine.
public enum EngineError: LocalizedError, Equatable, Sendable {
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
    /// No answer within the call's time limit. The engine may still do what was asked.
    case timedOut

    /// Typed error thrown when a user-initiated mutation is refused because Courier is locked.
    public static let appLocked = EngineError.rpc(.badValue, message: "Courier is locked", reason: "locked")

    /// Only a refused handshake means the app and engine are of different versions.
    public var isUpdateNeeded: Bool {
        if case .protocolMismatch = self { return true }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .protocolMismatch:
            return String(localized: "Courier needs an update to talk to its engine.")
        case .notConnected:
            return String(localized: "Courier’s engine is not connected.")
        case .disconnected:
            return String(localized: "Lost connection to Courier’s engine.")
        case .frameTooLarge:
            return String(localized: "That request is too large.")
        case .badResponse:
            return String(localized: "Courier’s engine returned an unexpected answer.")
        case .timedOut:
            return String(localized: "Courier’s engine did not answer in time.")
        case let .rpc(code, _, reason):
            if code == .badValue, reason == "locked" {
                return String(localized: "Courier is locked.")
            }
            return Self.describe(code: code)
        }
    }

    private static func describe(code: RPCErrorCode) -> String {
        switch code {
        case .parseError, .invalidRequest, .methodNotFound, .invalidParams:
            return String(localized: "Courier’s engine couldn’t understand that request.")
        case .internalError:
            return String(localized: "Courier’s engine ran into a problem. Try again.")
        case .protocolMismatch:
            return String(localized: "Courier needs an update to talk to its engine.")
        case .helloRequired:
            return String(localized: "Courier’s engine is still starting up.")
        case .notLinked:
            return String(localized: "This network isn’t linked.")
        case .bridgeCommand:
            return String(localized: "The network would take this as a command, so it was not sent.")
        case .tooLarge:
            return String(localized: "This file is larger than the network allows.")
        case .alreadyLinked:
            return String(localized: "That account is already connected.")
        case .badValue:
            return String(localized: "That isn’t accepted. Check it and try again.")
        case .unknownLogin:
            return String(localized: "The sign-in ended before it was finished. Try again.")
        case .notRunning:
            return String(localized: "This network isn’t running.")
        case .loginInProgress:
            return String(localized: "A sign-in is already in progress for this network.")
        case .notConnected:
            return String(localized: "The network isn’t connected yet.")
        case .notFailed:
            return String(localized: "Only a message that was not sent can be sent again or deleted.")
        case .notFound:
            return String(localized: "That account or chat is no longer there.")
        case .pinned:
            return String(localized: "Unpin a chat to archive it.")
        case .notEntitled:
            return String(localized: "Available with a plan")
        case .notSupported:
            return String(localized: "This network can’t do that.")
        case .tooOld:
            return String(localized: "That message can’t be changed any more.")
        case .alreadySent:
            return String(localized: "Too late to undo. Check the message in the chat.")
        case .notYours:
            return String(localized: "You can only change your own messages.")
        case .networkRefused:
            return String(localized: "The network didn’t accept that change.")
        case .needsFFmpeg:
            return String(localized: "Sending voice notes on this network needs ffmpeg. Install it with Homebrew (brew install ffmpeg), then try again.")
        case .other:
            return String(localized: "Courier’s engine could not do that.")
        }
    }
}

/// The app's connection to its engine: newline-delimited JSON-RPC 2.0 over the engine's Unix socket.
///
/// `connect()` opens the socket and says hello; only then do `call` and `changes` work. Answers are matched to
/// requests by id, so slow calls (message.send, login.wait) do not hold up others. When the connection ends, every
/// call in flight throws `.disconnected` and every `changes` stream finishes; a client is not reused after that
/// (the supervisor makes a new one for the restarted engine).
///
/// Every call has a time limit, 30 seconds unless the caller gives another, so a view never waits forever on an
/// engine that stopped answering. `login.wait` has none: it waits for a person to scan a code on their phone.
public actor EngineClient {
    /// The time limit of a call that names none.
    public static let defaultCallTimeout: TimeInterval = 30
    /// Methods that wait on a person, and so have no time limit unless the caller gives one.
    public static let untimedMethods: Set<String> = ["login.wait"]

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
    private var noticeSubscribers: [UUID: AsyncStream<EngineNotice>.Continuation] = [:]
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private var timers: [Int: Task<Void, Never>] = [:]
    private let callTimeout: TimeInterval

    public init(socketPath: String, client: String = EngineClient.defaultClientName,
                callTimeout: TimeInterval = EngineClient.defaultCallTimeout) {
        self.socketPath = socketPath
        self.clientName = client
        self.callTimeout = callTimeout
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
            let hello: HelloResult = try await send("hello", HelloParams(client: clientName), timeout: callTimeout)
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
    ///
    /// `timeout` is the call's time limit in seconds; nil means the client's (30 s by default), or none for the
    /// methods in `untimedMethods`. Past it the call throws `.timedOut`, and a late answer is dropped.
    public func call<P: Encodable, R: Decodable>(_ method: String, _ params: P,
                                                 timeout: TimeInterval? = nil) async throws -> R {
        guard greeted, !closed else { throw EngineError.notConnected }
        let isRoomlessQuitFlush = method == "message.sendHeld"
            && (params as? RoomOptionalParams).map { $0.roomID == nil } == true
        if !isRoomlessQuitFlush && ProtocolMethods.classification(for: method) != .readOnlyOrBackground {
            let locked = await MainActor.run { AppLockGate.shared.isLocked }
            if locked {
                throw EngineError.appLocked
            }
        }
        let limit = timeout ?? (Self.untimedMethods.contains(method) ? nil : callTimeout)
        return try await send(method, params, timeout: limit)
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

    /// The engine's other notifications (protocol 12: a pairing request, focus_app), from now on. Like `changes`,
    /// each access is a stream of its own, and it finishes when the connection ends. One the app can't read is
    /// dropped: unlike a change, there is nothing to re-read in its place.
    public var notices: AsyncStream<EngineNotice> {
        let (stream, continuation) = AsyncStream.makeStream(of: EngineNotice.self)
        if closed {
            continuation.finish()
            return stream
        }
        let id = UUID()
        noticeSubscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribeNotice(id) }
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
        for timer in timers.values { timer.cancel() }
        timers = [:]
        for call in calls.values { call.resume(throwing: EngineError.disconnected) }
        for subscriber in subscribers.values { subscriber.finish() }
        subscribers = [:]
        for subscriber in noticeSubscribers.values { subscriber.finish() }
        noticeSubscribers = [:]
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

    private func send<P: Encodable, R: Decodable>(_ method: String, _ params: P,
                                                  timeout: TimeInterval? = nil) async throws -> R {
        guard let connection, !closed else { throw EngineError.notConnected }
        let id = nextID
        nextID += 1
        var line = try JSONEncoder().encode(Request(id: id, method: method, params: params))
        guard line.count <= CourierProtocol.maxFrameBytes else { throw EngineError.frameTooLarge }
        line.append(0x0A)

        let answer = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pending[id] = continuation
            if let timeout {
                timers[id] = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    await self?.expire(id)
                }
            }
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

    /// The call's time is up: it throws `.timedOut`, and its answer, if one comes, is dropped.
    private func expire(_ id: Int) {
        timers[id] = nil
        pending.removeValue(forKey: id)?.resume(throwing: EngineError.timedOut)
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

    private struct Params<P: Decodable>: Decodable {
        let params: P
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
            timers.removeValue(forKey: id)?.cancel()
            pending.removeValue(forKey: id)?.resume(returning: line)
        } else if header.method == ProtocolMethods.changedNotification {
            // A change the app cannot read is still a change: re-reading everything is never wrong.
            let notification = try? JSONDecoder().decode(Notification.self, from: line)
            let change = notification.map { Change($0.params) } ?? .resync
            for subscriber in subscribers.values { subscriber.yield(change) }
        } else if let notice = Self.notice(header.method, line) {
            for subscriber in noticeSubscribers.values { subscriber.yield(notice) }
        }
    }

    private static func notice(_ method: String?, _ line: Data) -> EngineNotice? {
        let decoder = JSONDecoder()
        switch method {
        case ProtocolMethods.pairRequestNotification:
            return (try? decoder.decode(Params<PairRequest>.self, from: line)).map { .pairRequest($0.params) }
        case ProtocolMethods.pairEndedNotification:
            return (try? decoder.decode(Params<PairEnded>.self, from: line)).map { .pairEnded($0.params) }
        case ProtocolMethods.focusNotification:
            return (try? decoder.decode(Params<FocusParams>.self, from: line)).map { .focus($0.params) }
        default:
            return nil
        }
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    private func unsubscribeNotice(_ id: UUID) {
        noticeSubscribers[id] = nil
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
