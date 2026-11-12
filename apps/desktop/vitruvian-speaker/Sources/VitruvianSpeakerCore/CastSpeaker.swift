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
import Network
import os

// Playing an announcement's audio on a Google Home / Nest speaker over the
// local network (Google Cast, "CastV2"), so the speaker says it in the
// chosen Gemini voice rather than the Assistant's own.
//
// How it goes, in order:
//   1. find the speaker on the LAN (Bonjour, `_googlecast._tcp`), by the
//      friendly name in its TXT record (`fn`);
//   2. open TLS to it (port 8009 for a speaker; a group's leader says its
//      own port), accepting the self-signed certificate every Cast device has;
//   3. serve the WAV from memory on a one-off HTTP URL on this Mac, at the
//      address the speaker reaches us on;
//   4. launch the Default Media Receiver, LOAD the URL, wait until it has
//      played, then put the speaker back the way it was.
//
// The announcer falls back to Google Assistant Broadcast whenever this
// throws, so a speaker that cannot be found, is busy playing something
// else, or refuses the audio still hears the announcement.

/// Plays a WAV on the home speaker and returns once it has finished.
public protocol CastSpeaking: Sendable {
    func speak(wav: Data, target: SpeakerDevice, config: SpeakerConfig) async throws
}

public enum CastError: LocalizedError, Equatable, Sendable {
    case notFound(String)
    case ambiguousGroup(String)
    case discoveryFailed(String)
    case connectionFailed(String)
    case noLocalAddress
    case unplayable
    case busy(String)
    case launchFailed(String)
    case loadFailed(String)
    case timedOut(String)
    case malformedMessage

    public var errorDescription: String? {
        switch self {
        case .notFound(let name): return "No Cast speaker named \"\(name)\" answered on this network."
        case .ambiguousGroup(let name):
            return "More than one Cast speaker group is on this network and none is named \"\(name)\"."
        case .discoveryFailed(let why): return "Looking for Cast speakers failed (\(why))."
        case .connectionFailed(let why): return "Could not connect to the speaker (\(why))."
        case .noLocalAddress: return "Could not tell which address the speaker reaches this Mac on."
        case .unplayable: return "The audio is not a WAV the speaker can play."
        case .busy(let app): return "The speaker is busy playing \(app); not interrupting it."
        case .launchFailed(let why): return "The speaker would not start its media player (\(why))."
        case .loadFailed(let why): return "The speaker would not play the audio (\(why))."
        case .timedOut(let step): return "The speaker did not answer in time (\(step))."
        case .malformedMessage: return "The speaker sent a message that could not be read."
        }
    }
}

// MARK: - CastMessage (extensions.api.cast_channel.CastMessage)

/// The one message type on a Cast channel, protobuf-encoded by hand:
///
///     required ProtocolVersion protocol_version = 1;  // CASTV2_1_0 = 0
///     required string source_id = 2;
///     required string destination_id = 3;
///     required string namespace = 4;
///     required PayloadType payload_type = 5;          // STRING = 0, BINARY = 1
///     optional string payload_utf8 = 6;
///     optional bytes payload_binary = 7;
///
/// On the wire each message is preceded by its length, 4 bytes big-endian.
public struct CastMessage: Equatable, Sendable {
    public var protocolVersion: Int
    public var sourceId: String
    public var destinationId: String
    public var namespace: String
    public var payloadType: Int
    public var payloadUTF8: String?
    public var payloadBinary: Data?

    public init(
        sourceId: String, destinationId: String, namespace: String,
        payloadUTF8: String? = nil, payloadBinary: Data? = nil, protocolVersion: Int = 0
    ) {
        self.protocolVersion = protocolVersion
        self.sourceId = sourceId
        self.destinationId = destinationId
        self.namespace = namespace
        self.payloadType = payloadBinary == nil ? 0 : 1
        self.payloadUTF8 = payloadUTF8
        self.payloadBinary = payloadBinary
    }

    /// A JSON message, as every namespace this app uses speaks.
    public static func json(
        _ payload: [String: Any], namespace: String,
        from sourceId: String = CastNamespace.senderId, to destinationId: String = CastNamespace.receiverId
    ) -> CastMessage {
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        return CastMessage(sourceId: sourceId, destinationId: destinationId, namespace: namespace,
                           payloadUTF8: String(decoding: data, as: UTF8.self))
    }

    /// The payload read as a JSON object, or nil.
    public var payload: [String: Any]? {
        guard let payloadUTF8, let data = payloadUTF8.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The payload's `type` ("PING", "RECEIVER_STATUS", ...).
    public var type: String? { payload?["type"] as? String }

    // MARK: Encoding

    public func encoded() -> Data {
        var out = Data()
        Self.appendVarintField(1, UInt64(protocolVersion), to: &out)
        Self.appendBytesField(2, Data(sourceId.utf8), to: &out)
        Self.appendBytesField(3, Data(destinationId.utf8), to: &out)
        Self.appendBytesField(4, Data(namespace.utf8), to: &out)
        Self.appendVarintField(5, UInt64(payloadType), to: &out)
        if let payloadUTF8 { Self.appendBytesField(6, Data(payloadUTF8.utf8), to: &out) }
        if let payloadBinary { Self.appendBytesField(7, payloadBinary, to: &out) }
        return out
    }

    /// `encoded()` behind its 4-byte big-endian length, ready to write.
    public func framed() -> Data {
        let body = encoded()
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }

    static func appendVarint(_ value: UInt64, to out: inout Data) {
        var v = value
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
    }

    private static func appendVarintField(_ field: Int, _ value: UInt64, to out: inout Data) {
        appendVarint(UInt64(field << 3 | 0), to: &out)
        appendVarint(value, to: &out)
    }

    private static func appendBytesField(_ field: Int, _ bytes: Data, to out: inout Data) {
        appendVarint(UInt64(field << 3 | 2), to: &out)
        appendVarint(UInt64(bytes.count), to: &out)
        out.append(bytes)
    }

    // MARK: Decoding

    /// One message's protobuf bytes (without the length prefix). Unknown
    /// fields are skipped, as protobuf requires.
    public static func decode(_ data: Data) throws -> CastMessage {
        let b = [UInt8](data)
        var i = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard i < b.count, shift < 64 else { throw CastError.malformedMessage }
                let byte = b[i]
                i += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
        }
        var message = CastMessage(sourceId: "", destinationId: "", namespace: "")
        var seen = Set<Int>()
        while i < b.count {
            let key = try varint()
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                let value = try varint()
                if field == 1 { message.protocolVersion = Int(value) }
                if field == 5 { message.payloadType = Int(value) }
                seen.insert(field)
            case 2:
                let length = try varint()
                guard length <= UInt64(b.count - i) else { throw CastError.malformedMessage }
                let bytes = Data(b[i..<i + Int(length)])
                i += Int(length)
                switch field {
                case 2: message.sourceId = String(decoding: bytes, as: UTF8.self)
                case 3: message.destinationId = String(decoding: bytes, as: UTF8.self)
                case 4: message.namespace = String(decoding: bytes, as: UTF8.self)
                case 6: message.payloadUTF8 = String(decoding: bytes, as: UTF8.self)
                case 7: message.payloadBinary = bytes
                default: break
                }
                seen.insert(field)
            case 1:
                guard i + 8 <= b.count else { throw CastError.malformedMessage }
                i += 8
            case 5:
                guard i + 4 <= b.count else { throw CastError.malformedMessage }
                i += 4
            default:
                throw CastError.malformedMessage
            }
        }
        // The four strings are `required`; a message without them is not one.
        guard seen.isSuperset(of: [2, 3, 4]) else { throw CastError.malformedMessage }
        return message
    }
}

/// Splits a byte stream into messages: bytes go in as they arrive, whole
/// messages come out.
public struct CastFrameReader: Sendable {
    /// No Cast control message comes near this; a bigger length means the
    /// stream is not what it should be.
    public static let maxFrame = 64 * 1024

    private var buffer = Data()

    public init() {}

    public mutating func feed(_ bytes: Data) throws -> [CastMessage] {
        buffer.append(bytes)
        var out: [CastMessage] = []
        while buffer.count >= 4 {
            let head = [UInt8](buffer.prefix(4))
            let length = Int(head[0]) << 24 | Int(head[1]) << 16 | Int(head[2]) << 8 | Int(head[3])
            guard length <= Self.maxFrame else { throw CastError.malformedMessage }
            guard buffer.count >= 4 + length else { break }
            let body = buffer.subdata(in: buffer.startIndex + 4..<buffer.startIndex + 4 + length)
            buffer = Data(buffer.dropFirst(4 + length))
            out.append(try CastMessage.decode(body))
        }
        return out
    }
}

public enum CastNamespace {
    public static let connection = "urn:x-cast:com.google.cast.tp.connection"
    public static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    public static let receiver = "urn:x-cast:com.google.cast.receiver"
    public static let media = "urn:x-cast:com.google.cast.media"

    public static let senderId = "sender-0"
    public static let receiverId = "receiver-0"
    /// Google's Default Media Receiver: plays a URL, nothing else.
    public static let defaultMediaReceiver = "CC1AD845"
}

// MARK: - Finding the speaker

/// One Cast device seen on the LAN.
public struct CastDevice: Sendable {
    /// The friendly name (`fn`), as the Google Home app shows it.
    public var name: String
    /// `md`: "Google Nest Mini", "Google Cast Group", ...
    public var model: String
    /// The Bonjour service instance name.
    public var serviceName: String
    public var endpoint: NWEndpoint

    public init(name: String, model: String, serviceName: String, endpoint: NWEndpoint) {
        self.name = name
        self.model = model
        self.serviceName = serviceName
        self.endpoint = endpoint
    }

    public var isGroup: Bool { model.caseInsensitiveCompare("Google Cast Group") == .orderedSame }

    /// The device `target` names, among those seen, or nil.
    ///
    /// A single speaker: the device whose friendly name, or else Bonjour
    /// name, is the target's name (case and accents aside), a speaker
    /// before a group of the same name. Whole Home: the Cast group named
    /// as the target is, or else the only Cast group there is. With
    /// several groups and none named so, there is no telling which one is
    /// "the whole home", so nothing matches and Broadcast is used.
    public static func match(_ target: SpeakerDevice, among devices: [CastDevice]) throws -> CastDevice? {
        func fold(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        }
        let want = fold(target.name)
        let named = devices.filter { fold($0.name) == want || fold($0.serviceName) == want }
        if target.isWholeHome {
            let groups = devices.filter(\.isGroup)
            if let group = named.first(where: \.isGroup) { return group }
            if groups.count == 1 { return groups[0] }
            if groups.count > 1 { throw CastError.ambiguousGroup(target.name) }
            return nil
        }
        return named.first(where: { !$0.isGroup }) ?? named.first
    }
}

public protocol CastDiscovering: Sendable {
    /// The Cast device for `target`; throws `CastError.notFound` when none
    /// answers within `timeout` seconds.
    func find(_ target: SpeakerDevice, timeout: Double) async throws -> CastDevice
}

/// Bonjour browsing for `_googlecast._tcp` with each service's TXT record.
public struct BonjourCastDiscovery: CastDiscovering {
    public static let serviceType = "_googlecast._tcp"

    public init() {}

    public func find(_ target: SpeakerDevice, timeout: Double) async throws -> CastDevice {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: "local."), using: .tcp)
        defer { browser.cancel() }
        let queue = DispatchQueue(label: "com.vitruviansoftware.homespeaker.cast-browse")
        let once = Once<CastDevice>()
        let seen = Locked<[CastDevice]>([])
        // Whole Home waits to see every group before choosing (unless one is
        // named as the target); a single speaker is taken the moment it shows.
        @Sendable func settle(final: Bool) {
            do {
                if let found = try CastDevice.match(target, among: seen.value),
                   final || !target.isWholeHome || (found.isGroup && CastDevice.namesMatch(found, target)) {
                    once.resume(.success(found))
                } else if final {
                    once.resume(.failure(CastError.notFound(target.name)))
                }
            } catch {
                if final { once.resume(.failure(error)) }
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CastDevice, Error>) in
                once.set(cont)
                browser.browseResultsChangedHandler = { results, _ in
                    seen.value = results.compactMap(Self.device(from:))
                    settle(final: false)
                }
                browser.stateUpdateHandler = { state in
                    switch state {
                    case .failed(let error), .waiting(let error):
                        // `waiting`: no local network permission, or no network.
                        once.resume(.failure(CastError.discoveryFailed(Self.describe(error))))
                    default:
                        break
                    }
                }
                queue.asyncAfter(deadline: .now() + timeout) { settle(final: true) }
                browser.start(queue: queue)
            }
        } onCancel: {
            once.resume(.failure(CancellationError()))
        }
    }

    static func device(from result: NWBrowser.Result) -> CastDevice? {
        guard case .service(let serviceName, _, _, _) = result.endpoint else { return nil }
        var txt: [String: String] = [:]
        if case .bonjour(let record) = result.metadata {
            txt = record.dictionary
        }
        let name = txt["fn"].flatMap { $0.isEmpty ? nil : $0 } ?? serviceName
        return CastDevice(name: name, model: txt["md"] ?? "", serviceName: serviceName, endpoint: result.endpoint)
    }

    static func describe(_ error: NWError) -> String {
        if case .dns(let code) = error, code == -65555 {
            return "this app is not allowed to use the local network; allow it in System Settings › Privacy & Security › Local Network"
        }
        return error.localizedDescription
    }
}

extension CastDevice {
    static func namesMatch(_ device: CastDevice, _ target: SpeakerDevice) -> Bool {
        device.name.compare(target.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

/// A value behind a lock.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Resumes one continuation exactly once, whoever gets there first.
final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?
    private var done = false

    func set(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let pending {
            self.pending = nil
            done = true
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        if done {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        guard let continuation else {
            // Arrived before the continuation was handed over.
            if pending == nil { pending = result }
            lock.unlock()
            return
        }
        self.continuation = nil
        done = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

// MARK: - Serving the audio

/// A one-off HTTP server for one WAV, at one unguessable path, on every
/// interface (the speaker must reach it), for as long as one announcement.
public final class CastAudioServer: @unchecked Sendable {
    public let path: String
    let wav: Data
    private let queue = DispatchQueue(label: "com.vitruviansoftware.homespeaker.cast-http")
    private let lock = NSLock()
    private var listener: NWListener?
    private var _requests = 0

    /// How many times the audio was asked for: zero after a play means the
    /// speaker never reached this Mac.
    public var requests: Int { lock.withLock { _requests } }

    public init(wav: Data, path: String = "/announce-\(UUID().uuidString.lowercased()).wav") {
        self.wav = wav
        self.path = path
    }

    /// Starts listening on a free port and returns it.
    public func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        lock.withLock { self.listener = listener }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        let once = Once<UInt16>()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            once.set(cont)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue { once.resume(.success(port)) }
                case .failed(let error), .waiting(let error):
                    once.resume(.failure(CastError.connectionFailed("audio server: \(error.localizedDescription)")))
                case .cancelled:
                    once.resume(.failure(CancellationError()))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        let listener = lock.withLock { () -> NWListener? in
            defer { self.listener = nil }
            return self.listener
        }
        listener?.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(connection, so: Data())
    }

    private func receiveHead(_ connection: NWConnection, so far: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var head = far
            if let data { head.append(data) }
            let end = head.range(of: Data("\r\n\r\n".utf8))
            if end == nil && error == nil && !isComplete && head.count < 16 * 1024 {
                self.receiveHead(connection, so: head)
                return
            }
            guard end != nil else { connection.cancel(); return }
            let response = Self.response(forRequest: String(decoding: head, as: UTF8.self), path: self.path, body: self.wav)
            if response.isAudio { self.lock.withLock { self._requests += 1 } }
            connection.send(content: response.bytes, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    /// The whole answer to one request: the WAV for GET (headers alone for
    /// HEAD) at `path`, 404 elsewhere, 405 for any other method. No ranges:
    /// the speaker is told so, and asks for the whole file.
    public static func response(forRequest head: String, path: String, body: Data) -> (bytes: Data, isAudio: Bool) {
        let requestLine = head.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? ""
        let target = parts.count > 1 ? String(parts[1]) : ""
        let requestedPath = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""

        func reply(_ status: String, _ headers: [(String, String)], _ content: Data) -> Data {
            var text = "HTTP/1.1 \(status)\r\n"
            for (name, value) in headers { text += "\(name): \(value)\r\n" }
            text += "\r\n"
            return Data(text.utf8) + content
        }
        guard method == "GET" || method == "HEAD" else {
            return (reply("405 Method Not Allowed", [("Allow", "GET, HEAD"), ("Content-Length", "0"), ("Connection", "close")], Data()), false)
        }
        guard requestedPath == path else {
            return (reply("404 Not Found", [("Content-Length", "0"), ("Connection", "close")], Data()), false)
        }
        let headers = [
            ("Content-Type", "audio/wav"),
            ("Content-Length", "\(body.count)"),
            ("Accept-Ranges", "none"),
            ("Cache-Control", "no-store"),
            ("Connection", "close"),
        ]
        return (reply("200 OK", headers, method == "HEAD" ? Data() : body), true)
    }
}

// MARK: - The Cast channel (TLS to the speaker)

/// A TLS connection to a Cast device, sending and receiving `CastMessage`s.
/// Heartbeat PINGs are answered here and never reach the reader.
final class CastChannel: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.vitruviansoftware.homespeaker.cast-channel")
    let messages: AsyncThrowingStream<CastMessage, Error>
    private let sink: AsyncThrowingStream<CastMessage, Error>.Continuation

    /// `tls` is off only in tests, against a plain-TCP stand-in speaker.
    init(endpoint: NWEndpoint, tls useTLS: Bool = true) {
        var tls: NWProtocolTLS.Options?
        if useTLS {
            let options = NWProtocolTLS.Options()
            // Every Cast device presents a self-signed certificate, so there
            // is no chain to check; the connection stays on the local network.
            sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, complete in
                complete(true)
            }, DispatchQueue(label: "com.vitruviansoftware.homespeaker.cast-tls"))
            tls = options
        }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 5
        tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        // IPv4, so the address the speaker sees for this Mac is one a plain
        // http:// URL can name.
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        connection = NWConnection(to: endpoint, using: parameters)
        (messages, sink) = AsyncThrowingStream.makeStream(of: CastMessage.self)
    }

    func open(timeout: Double) async throws {
        let once = Once<Void>()
        let connection = self.connection
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            once.set(cont)
            connection.stateUpdateHandler = { [sink] state in
                switch state {
                case .ready:
                    once.resume(.success(()))
                case .waiting(let error), .failed(let error):
                    once.resume(.failure(CastError.connectionFailed(error.localizedDescription)))
                    sink.finish(throwing: CastError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    once.resume(.failure(CastError.connectionFailed("cancelled")))
                    sink.finish()
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                once.resume(.failure(CastError.timedOut("connecting")))
            }
            connection.start(queue: queue)
        }
        receive(CastFrameReader())
    }

    /// This Mac's IPv4 address on the connection to the speaker: the one
    /// the speaker can reach back to (getsockname, in Network's terms).
    var localIPv4: String? {
        guard case .hostPort(let host, _) = connection.currentPath?.localEndpoint,
              case .ipv4(let address) = host else { return nil }
        return address.rawValue.map(String.init).joined(separator: ".")
    }

    func send(_ message: CastMessage) async throws {
        let connection = self.connection
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: message.framed(), completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: CastError.connectionFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    func close() {
        sink.finish()
        let connection = self.connection
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func receive(_ reader: CastFrameReader) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var reader = reader
            if let data, !data.isEmpty {
                do {
                    for message in try reader.feed(data) {
                        if message.namespace == CastNamespace.heartbeat, message.type == "PING" {
                            let pong = CastMessage.json(["type": "PONG"], namespace: CastNamespace.heartbeat,
                                                        from: message.destinationId, to: message.sourceId)
                            self.connection.send(content: pong.framed(), completion: .contentProcessed { _ in })
                            continue
                        }
                        self.sink.yield(message)
                    }
                } catch {
                    self.sink.finish(throwing: error)
                    return
                }
            }
            if let error {
                self.sink.finish(throwing: CastError.connectionFailed(error.localizedDescription))
            } else if isComplete {
                self.sink.finish()
            } else {
                self.receive(reader)
            }
        }
    }
}

// MARK: - The speaker

public struct CastSpeaker: CastSpeaking {
    public static let shared = CastSpeaker()
    public static let logger = Logger(subsystem: "com.vitruviansoftware.homespeaker", category: "cast")

    /// Roughly what connecting, launching the player and loading the audio
    /// add before the speaker makes a sound, for a media pause's length.
    public static let setupAllowance: Double = 5

    let discovery: CastDiscovering
    let discoveryTimeout: Double
    let stepTimeout: Double
    /// Off only in tests, against a plain-TCP stand-in speaker.
    let useTLS: Bool

    public init(discovery: CastDiscovering = BonjourCastDiscovery(), discoveryTimeout: Double = 3, stepTimeout: Double = 10) {
        self.init(discovery: discovery, discoveryTimeout: discoveryTimeout, stepTimeout: stepTimeout, useTLS: true)
    }

    init(discovery: CastDiscovering, discoveryTimeout: Double, stepTimeout: Double, useTLS: Bool) {
        self.discovery = discovery
        self.discoveryTimeout = discoveryTimeout
        self.stepTimeout = stepTimeout
        self.useTLS = useTLS
    }

    public func speak(wav: Data, target: SpeakerDevice, config: SpeakerConfig) async throws {
        let wav = Self.normalizedWAV(wav)
        guard let seconds = GeminiSpeaker.duration(ofWAV: wav), seconds > 0 else { throw CastError.unplayable }
        let device = try await discovery.find(target, timeout: discoveryTimeout)
        Self.logger.notice("Casting \(String(format: "%.1f", seconds), privacy: .public)s to \(device.name, privacy: .public) (\(device.model, privacy: .public))")

        let channel = CastChannel(endpoint: device.endpoint, tls: useTLS)
        defer { channel.close() }
        try await channel.open(timeout: stepTimeout)
        guard let ip = channel.localIPv4 else { throw CastError.noLocalAddress }

        let server = CastAudioServer(wav: wav)
        defer { server.stop() }
        let port = try await server.start()
        let url = "http://\(ip):\(port)\(server.path)"

        // "Announce at a set volume" for one speaker. A group's volume is
        // its members' together, which Whole Home never sets.
        let volume: Double? = config.effectiveAnnounceVolumeEnabled && !device.isGroup
            ? Double(config.effectiveAnnounceVolume) / 100 : nil
        let session = CastSession(channel: channel, stepTimeout: stepTimeout)
        do {
            try await session.play(url: url, seconds: seconds, volume: volume)
        } catch {
            await session.tidyUp()
            if server.requests == 0, case CastError.timedOut = error {
                throw CastError.loadFailed("the speaker never fetched the audio from \(ip):\(port); a firewall may be blocking it")
            }
            throw error
        }
        await session.tidyUp()
    }

    /// `wav` with its RIFF and `data` sizes made true. A streamed WAV can
    /// say 0xFFFFFFFF; a speaker asked to play that may wait for bytes
    /// that never come.
    public static func normalizedWAV(_ wav: Data) -> Data {
        var b = [UInt8](wav)
        guard b.count >= 12, b.starts(with: Array("RIFF".utf8)) else { return wav }
        func u32(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 }
        func put(_ v: Int, at i: Int) {
            b[i] = UInt8(v & 0xFF); b[i + 1] = UInt8(v >> 8 & 0xFF); b[i + 2] = UInt8(v >> 16 & 0xFF); b[i + 3] = UInt8(v >> 24 & 0xFF)
        }
        var i = 12
        while i + 8 <= b.count {
            let id = String(bytes: b[i..<i + 4], encoding: .ascii)
            let size = u32(i + 4)
            if id == "data" {
                let available = b.count - (i + 8)
                if size != available {
                    put(available, at: i + 4)
                    b = Array(b[0..<(i + 8 + available)])
                }
                put(b.count - 8, at: 4)
                return Data(b)
            }
            i += 8 + size + (size & 1)
        }
        return wav
    }
}

/// One play on an open channel: the receiver's conversation from CONNECT
/// to the end of the audio.
final class CastSession: @unchecked Sendable {
    let channel: CastChannel
    let stepTimeout: Double
    private let lock = NSLock()
    private var requestId = 0
    // What tidying up needs.
    private var launchedSession: String?
    private var transportId: String?
    private var originalVolume: Double?
    private var setVolume: Double?
    private var lastVolume: Double?
    private var started = false

    init(channel: CastChannel, stepTimeout: Double) {
        self.channel = channel
        self.stepTimeout = stepTimeout
    }

    private func nextRequestId() -> Int {
        lock.withLock { requestId += 1; return requestId }
    }

    private func send(_ payload: [String: Any], _ namespace: String, to destination: String = CastNamespace.receiverId) async throws {
        var payload = payload
        if namespace == CastNamespace.receiver || namespace == CastNamespace.media, payload["requestId"] == nil {
            payload["requestId"] = nextRequestId()
        }
        try await channel.send(.json(payload, namespace: namespace, to: destination))
    }

    private enum Phase { case status, launching, loading, playing }

    /// Plays `url` and returns once the speaker reports it finished, or
    /// once its length (plus a margin) has passed since it started.
    func play(url: String, seconds: Double, volume: Double?) async throws {
        try await send(["type": "CONNECT", "origin": [String: Any](), "userAgent": "HomeSpeaker"], CastNamespace.connection)
        try await send(["type": "GET_STATUS"], CastNamespace.receiver)

        let messages = channel.messages
        let stepTimeout = self.stepTimeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                var phase = Phase.status
                var sawPlaying = false
                var transport = ""
                for try await message in messages {
                    guard let body = message.payload, let type = body["type"] as? String else { continue }
                    switch type {
                    case "RECEIVER_STATUS":
                        let status = body["status"] as? [String: Any] ?? [:]
                        if let level = (status["volume"] as? [String: Any])?["level"] as? Double {
                            lock.withLock { lastVolume = level }
                        }
                        let apps = status["applications"] as? [[String: Any]] ?? []
                        let player = apps.first { $0["appId"] as? String == CastNamespace.defaultMediaReceiver }
                        switch phase {
                        case .status:
                            if let busy = apps.first(where: {
                                $0["appId"] as? String != CastNamespace.defaultMediaReceiver && $0["isIdleScreen"] as? Bool != true
                            }) {
                                throw CastError.busy((busy["displayName"] as? String) ?? "something else")
                            }
                            lock.withLock { originalVolume = lastVolume }
                            if let volume {
                                lock.withLock { setVolume = volume }
                                try await send(["type": "SET_VOLUME", "volume": ["level": volume]], CastNamespace.receiver)
                            }
                            if let player, let id = player["transportId"] as? String {
                                // Already up (an announcement just before): reuse it.
                                transport = id
                                try await load(url, transport: id)
                                phase = .loading
                            } else {
                                try await send(["type": "LAUNCH", "appId": CastNamespace.defaultMediaReceiver], CastNamespace.receiver)
                                phase = .launching
                            }
                        case .launching:
                            guard let player, let id = player["transportId"] as? String else { continue }
                            lock.withLock { launchedSession = player["sessionId"] as? String }
                            transport = id
                            try await load(url, transport: id)
                            phase = .loading
                        case .loading, .playing:
                            break
                        }
                    case "LAUNCH_ERROR":
                        throw CastError.launchFailed((body["reason"] as? String) ?? "launch error")
                    case "LOAD_FAILED", "LOAD_CANCELLED", "INVALID_REQUEST", "INVALID_PLAYER_STATE":
                        throw CastError.loadFailed((body["reason"] as? String).map { "\(type): \($0)" } ?? type)
                    case "MEDIA_STATUS":
                        guard phase == .loading || phase == .playing, message.sourceId == transport else { continue }
                        for entry in body["status"] as? [[String: Any]] ?? [] {
                            switch entry["playerState"] as? String {
                            case "PLAYING", "BUFFERING", "PAUSED":
                                if !sawPlaying {
                                    sawPlaying = true
                                    phase = .playing
                                    lock.withLock { started = true }
                                }
                            case "IDLE":
                                switch entry["idleReason"] as? String {
                                case "FINISHED", "INTERRUPTED", "CANCELLED":
                                    // Played to the end, or someone took the speaker over.
                                    return
                                case "ERROR":
                                    throw CastError.loadFailed("the speaker could not play the audio")
                                default:
                                    break
                                }
                            default:
                                break
                            }
                        }
                    case "CLOSE":
                        if message.sourceId == transport, sawPlaying { return }
                        if message.sourceId == transport || message.sourceId == CastNamespace.receiverId {
                            throw CastError.loadFailed("the speaker closed the player")
                        }
                    default:
                        break
                    }
                }
                // The speaker hung up.
                if sawPlaying { return }
                throw CastError.connectionFailed("the speaker closed the connection")
            }
            // The deadlines: so long to get going, then the audio's length.
            group.addTask { [self] in
                let start = Date()
                while !isStarted {
                    try await Task.sleep(for: .milliseconds(200))
                    if Date().timeIntervalSince(start) > stepTimeout * 2 {
                        throw CastError.timedOut("waiting for playback to start")
                    }
                }
                try await Task.sleep(for: .seconds(seconds + 5))
                // It started and has had its length: done, whatever it reports.
            }
            // Keeps the channel alive through a long announcement.
            group.addTask { [self] in
                while true {
                    try await Task.sleep(for: .seconds(5))
                    try await channel.send(.json(["type": "PING"], namespace: CastNamespace.heartbeat))
                }
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private var isStarted: Bool { lock.withLock { started } }

    private func load(_ url: String, transport: String) async throws {
        lock.withLock { transportId = transport }
        try await send(["type": "CONNECT", "origin": [String: Any](), "userAgent": "HomeSpeaker"],
                       CastNamespace.connection, to: transport)
        try await send([
            "type": "LOAD",
            "autoplay": true,
            "currentTime": 0,
            "media": [
                "contentId": url,
                "contentType": "audio/wav",
                "streamType": "BUFFERED",
                "metadata": ["metadataType": 0, "title": "HomeSpeaker"],
            ] as [String: Any],
        ], CastNamespace.media, to: transport)
    }

    /// Puts the speaker back: its volume, if nobody changed it meanwhile,
    /// and closes the player this session launched. Best effort, briefly.
    func tidyUp() async {
        let (original, set, last, session, transport) = lock.withLock {
            (originalVolume, setVolume, lastVolume, launchedSession, transportId)
        }
        if let original, let set, let last, abs(last - set) < 0.015 {
            try? await send(["type": "SET_VOLUME", "volume": ["level": original]], CastNamespace.receiver)
        }
        if let transport {
            try? await channel.send(.json(["type": "CLOSE"], namespace: CastNamespace.connection, to: transport))
        }
        if let session {
            try? await send(["type": "STOP", "sessionId": session], CastNamespace.receiver)
        }
        try? await channel.send(.json(["type": "CLOSE"], namespace: CastNamespace.connection))
    }
}
