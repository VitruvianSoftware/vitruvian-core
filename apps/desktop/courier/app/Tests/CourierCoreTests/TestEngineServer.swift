// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Darwin
import Foundation
import XCTest

/// A stand-in engine: a Unix stream socket under /tmp that answers newline-delimited JSON-RPC with a handler the
/// test gives, and sends notifications when the test asks. Plain BSD sockets on threads of its own, so it shares
/// nothing with the client under test.
final class TestEngineServer: @unchecked Sendable {
    enum Reply {
        case result(Any)
        case error(code: Int, message: String, data: Any? = nil)
        /// Answer later, with `reply(to:with:)`.
        case later
    }

    typealias Handler = (_ method: String, _ params: [String: Any]?) -> Reply

    /// Short enough for sun_path (104 bytes) wherever the test runs.
    let path = "/tmp/courier-test-\(UUID().uuidString.prefix(8)).sock"
    private let listener: Int32
    private let lock = NSLock()
    private var handler: Handler
    private var connections: [Int32] = []
    private var requests: [[String: Any]] = []
    private var heldIDs: [Int: Int32] = [:]
    private var stopped = false
    private var _expectMergeIDRejection = false
    private var _rejectedMergeIDs: [String] = []

    var expectMergeIDRejection: Bool {
        get { lock.withLock { _expectMergeIDRejection } }
        set { lock.withLock { _expectMergeIDRejection = newValue } }
    }

    var rejectedMergeIDs: [String] {
        get { lock.withLock { _rejectedMergeIDs } }
        set { lock.withLock { _rejectedMergeIDs = newValue } }
    }

    init(handler: @escaping Handler = TestEngineServer.standard) throws {
        self.handler = handler
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.init(rawValue: errno)!) }
        unlink(path)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (index, byte) in bytes.enumerated() { raw[index] = UInt8(bitPattern: byte) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 8) == 0 else {
            let code = errno
            close(listener)
            throw POSIXError(.init(rawValue: code)!)
        }
        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.start()
    }

    deinit { stop() }

    /// Answers hello for the protocol this app speaks, and every other method with an empty result.
    static func standard(_ method: String, _ params: [String: Any]?) -> Reply {
        if method == "hello" { return helloOK }
        return .result([String: Any]())
    }

    static let helloOK = Reply.result(["protocol": CourierProtocol.version, "engine": "test",
                                       "networks": ["whatsapp", "signal"]])

    func setHandler(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler }
    }

    /// Every request received, in order.
    var received: [[String: Any]] { lock.withLock { requests } }

    func receivedMethods() -> [String] { received.compactMap { $0["method"] as? String } }

    /// Sends a changed notification with these params to every connection.
    func notify(_ params: [String: Any]) {
        broadcast(["jsonrpc": "2.0", "method": "changed", "params": params])
    }

    /// Sends another notification (protocol 12: integrations.pairRequest, integrations.pairEnded, app.focus).
    func notify(method: String, params: [String: Any]) {
        broadcast(["jsonrpc": "2.0", "method": method, "params": params])
    }

    /// Answers a request the handler held with `.later`.
    func reply(to id: Int, with result: Any) {
        guard let connection = lock.withLock({ heldIDs.removeValue(forKey: id) }) else { return }
        write(["jsonrpc": "2.0", "id": id, "result": result], to: connection)
    }

    /// Closes every connection, as an engine that dies does; the socket stays to accept new ones.
    func dropConnections() {
        let all = lock.withLock { () -> [Int32] in
            defer { connections = [] }
            return connections
        }
        for connection in all { shutdown(connection, SHUT_RDWR) }
    }

    func stop() {
        let already = lock.withLock { () -> Bool in
            defer { stopped = true }
            return stopped
        }
        guard !already else { return }
        dropConnections()
        close(listener)
        unlink(path)
    }

    // MARK: -

    private func acceptLoop() {
        while true {
            var poller = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, 50)
            if lock.withLock({ stopped }) { return }
            guard ready > 0 else { continue }
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { continue }
            var on: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            lock.withLock { connections.append(connection) }
            Thread { [weak self] in self?.serve(connection) }.start()
        }
    }

    private func serve(_ connection: Int32) {
        defer { close(connection) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(connection, &chunk, chunk.count)
            guard count > 0 else { return }
            buffer.append(contentsOf: chunk[0 ..< count])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex ..< newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                handle(Data(line), on: connection)
            }
        }
    }

    private func handle(_ line: Data, on connection: Int32) {
        guard let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let method = request["method"] as? String else { return }
        let params = request["params"] as? [String: Any]
        let (handler, id, rejectedMergeID, expectRejection) = lock.withLock { () -> (Handler, Any?, String?, Bool) in
            requests.append(request)
            let leaked = Self.firstMergeRoomID(in: params)
            if let leaked {
                _rejectedMergeIDs.append("\(method):\(leaked)")
            }
            return (self.handler, request["id"], leaked, _expectMergeIDRejection)
        }
        guard let id else { return }
        if let rejectedMergeID {
            if !expectRejection {
                XCTFail("Engine RPC \(method) received synthetic merge ID: \(rejectedMergeID)")
            }
            let error: [String: Any] = [
                "code": -32602,
                "message": "invalid params",
                "data": ["reason": "room_id must not be a merge_id"],
            ]
            write(["jsonrpc": "2.0", "id": id, "error": error], to: connection)
            return
        }
        switch handler(method, params) {
        case let .result(result):
            write(["jsonrpc": "2.0", "id": id, "result": result], to: connection)
        case let .error(code, message, data):
            var error: [String: Any] = ["code": code, "message": message]
            if let data { error["data"] = data }
            write(["jsonrpc": "2.0", "id": id, "error": error], to: connection)
        case .later:
            if let number = id as? Int { lock.withLock { heldIDs[number] = connection } }
        }
    }

    /// Returns the first room ID string in `params` that begins with `"merge:"`, or `nil` when none does.
    private static func firstMergeRoomID(in params: [String: Any]?) -> String? {
        guard let params else { return nil }
        for key in ["room_id", "open_room_id", "last_room_id"] {
            if let value = params[key] as? String, value.hasPrefix("merge:") {
                return value
            }
        }
        if let ids = params["room_ids"] as? [String], let bad = ids.first(where: { $0.hasPrefix("merge:") }) {
            return bad
        }
        if let filters = params["filters"] as? [String: Any],
           let ids = filters["room_ids"] as? [String],
           let bad = ids.first(where: { $0.hasPrefix("merge:") }) {
            return bad
        }
        if let messages = params["messages"] as? [[String: Any]] {
            for message in messages {
                if let roomID = message["room_id"] as? String, roomID.hasPrefix("merge:") {
                    return roomID
                }
            }
        }
        return nil
    }

    private func broadcast(_ message: [String: Any]) {
        for connection in lock.withLock({ connections }) { write(message, to: connection) }
    }

    private func write(_ message: [String: Any], to connection: Int32) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        lock.withLock {
            data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let written = Darwin.write(connection, raw.baseAddress! + offset, raw.count - offset)
                    if written <= 0 { return }
                    offset += written
                }
            }
        }
    }
}
