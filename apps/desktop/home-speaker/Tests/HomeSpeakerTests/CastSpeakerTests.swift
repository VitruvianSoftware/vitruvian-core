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
import Testing
@testable import HomeSpeakerCore

// Playing the Gemini voice on the Home speakers over Google Cast
// (`home_cast_voice`). Nothing here reaches a real speaker: the wire format
// is checked byte for byte, the audio server and the whole Cast
// conversation run against stand-ins on loopback.

// MARK: - Helpers

/// A real 16-bit mono 24 kHz WAV of `seconds` of silence.
private func silentWAV(seconds: Double = 0.2) -> Data {
    let pcm = Data(count: Int(24000 * seconds) * 2)
    return GeminiSpeaker.wav(from: pcm, mimeType: "audio/L16;rate=24000")
}

private let lake = SpeakerDevice(id: "device@lake", type: "GoogleDisplayDevice", name: "Lake Office", room: "Lake Office")
private let wholeHome = SpeakerDevice(id: "structure@s", type: "structure", name: "Home")

private func device(_ name: String, model: String = "Google Nest Mini", service: String? = nil) -> CastDevice {
    CastDevice(name: name, model: model, serviceName: service ?? "Google-Nest-Mini-\(name.count)",
               endpoint: .hostPort(host: "127.0.0.1", port: 8009))
}

// MARK: - The wire format

@Suite struct CastMessageTests {
    @Test func encodesTheProtobufFieldsInOrder() {
        let m = CastMessage(sourceId: "s", destinationId: "d", namespace: "n", payloadUTF8: "{}")
        // 1:varint 0, 2:"s", 3:"d", 4:"n", 5:varint 0, 6:"{}"
        let expected: [UInt8] = [0x08, 0x00, 0x12, 0x01, 0x73, 0x1A, 0x01, 0x64, 0x22, 0x01, 0x6E,
                                 0x28, 0x00, 0x32, 0x02, 0x7B, 0x7D]
        #expect([UInt8](m.encoded()) == expected)
    }

    @Test func framesWithABigEndianLength() {
        let m = CastMessage.json(["type": "PING"], namespace: CastNamespace.heartbeat)
        let framed = [UInt8](m.framed())
        let length = Int(framed[0]) << 24 | Int(framed[1]) << 16 | Int(framed[2]) << 8 | Int(framed[3])
        #expect(length == framed.count - 4)
        #expect(Data(framed.dropFirst(4)) == m.encoded())
    }

    @Test func roundTripsIncludingLongPayloadsAndUnicode() throws {
        let long = String(repeating: "é—", count: 300)  // length varint over one byte
        let m = CastMessage.json(["type": "LOAD", "title": long], namespace: CastNamespace.media,
                                 from: "sender-0", to: "transport-7")
        let back = try CastMessage.decode(m.encoded())
        #expect(back == m)
        #expect(back.type == "LOAD")
        #expect(back.payload?["title"] as? String == long)
    }

    @Test func skipsUnknownFieldsAndRefusesBrokenOnes() throws {
        var bytes = CastMessage(sourceId: "a", destinationId: "b", namespace: "c", payloadUTF8: "x").encoded()
        bytes.append(contentsOf: [0x48, 0x2A])              // field 9, varint 42
        bytes.append(contentsOf: [0x52, 0x02, 0x01, 0x02])  // field 10, two bytes
        #expect(try CastMessage.decode(bytes).payloadUTF8 == "x")
        // Truncated inside a string.
        #expect(throws: CastError.self) { try CastMessage.decode(Data([0x12, 0x05, 0x61])) }
        // Missing the required strings.
        #expect(throws: CastError.self) { try CastMessage.decode(Data([0x08, 0x00])) }
    }

    @Test func frameReaderSplitsAStreamArrivingInPieces() throws {
        let a = CastMessage.json(["type": "PING"], namespace: CastNamespace.heartbeat)
        let b = CastMessage.json(["type": "GET_STATUS", "requestId": 1], namespace: CastNamespace.receiver)
        let stream = a.framed() + b.framed()
        var reader = CastFrameReader()
        var out: [CastMessage] = []
        var i = 0
        for size in [1, 3, 7, 2, 50, 1000] where i < stream.count {
            let end = min(i + size, stream.count)
            out += try reader.feed(stream.subdata(in: i..<end))
            i = end
        }
        #expect(out == [a, b])
        var bad = CastFrameReader()
        #expect(throws: CastError.self) { try bad.feed(Data([0x7F, 0xFF, 0xFF, 0xFF])) }
    }

    @Test func normalizesAStreamedWAVHeader() throws {
        var wav = [UInt8](silentWAV(seconds: 0.1))
        // A streamed WAV: data and RIFF sizes say 0xFFFFFFFF.
        for i in 4..<8 { wav[i] = 0xFF }
        for i in 40..<44 { wav[i] = 0xFF }
        let fixed = [UInt8](CastSpeaker.normalizedWAV(Data(wav)))
        func u32(_ i: Int) -> Int { Int(fixed[i]) | Int(fixed[i + 1]) << 8 | Int(fixed[i + 2]) << 16 | Int(fixed[i + 3]) << 24 }
        #expect(u32(40) == fixed.count - 44)
        #expect(u32(4) == fixed.count - 8)
        let duration = try #require(GeminiSpeaker.duration(ofWAV: Data(fixed)))
        #expect(abs(duration - 0.1) < 0.001)
        // A sound one is left alone.
        let sound = silentWAV()
        #expect(CastSpeaker.normalizedWAV(sound) == sound)
    }
}

// MARK: - Matching the speaker

@Suite struct CastMatchTests {
    @Test func aSpeakerMatchesByFriendlyNameAnyCase() throws {
        let found = try CastDevice.match(lake, among: [device("Kitchen"), device("lake office")])
        #expect(found?.name == "lake office")
    }

    @Test func aSpeakerMatchesByServiceNameAndPrefersASpeakerToAGroup() throws {
        let byService = try CastDevice.match(lake, among: [device("Den", service: "Lake Office")])
        #expect(byService?.name == "Den")
        let both = [device("Lake Office", model: "Google Cast Group"), device("Lake Office")]
        #expect(try CastDevice.match(lake, among: both)?.isGroup == false)
        #expect(try CastDevice.match(lake, among: [device("Kitchen")]) == nil)
    }

    @Test func wholeHomeTakesTheNamedGroupOrTheOnlyGroup() throws {
        let groups = [device("Upstairs", model: "Google Cast Group"), device("Home", model: "Google Cast Group")]
        #expect(try CastDevice.match(wholeHome, among: groups + [device("Kitchen")])?.name == "Home")
        let one = [device("Everywhere", model: "Google Cast Group"), device("Kitchen")]
        #expect(try CastDevice.match(wholeHome, among: one)?.name == "Everywhere")
        #expect(try CastDevice.match(wholeHome, among: [device("Kitchen")]) == nil)
        let two = [device("Upstairs", model: "Google Cast Group"), device("Downstairs", model: "Google Cast Group")]
        #expect(throws: CastError.ambiguousGroup("Home")) { try CastDevice.match(wholeHome, among: two) }
    }
}

// MARK: - Serving the audio

@Suite struct CastAudioServerTests {
    @Test func answersGetHeadAndRefusesTheRest() {
        let body = Data("RIFFdata".utf8)
        let ok = CastAudioServer.response(forRequest: "GET /announce-x.wav HTTP/1.1\r\nHost: a\r\n\r\n", path: "/announce-x.wav", body: body)
        let text = String(decoding: ok.bytes, as: UTF8.self)
        #expect(ok.isAudio)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: audio/wav\r\n"))
        #expect(text.contains("Content-Length: 8\r\n"))
        #expect(text.contains("Accept-Ranges: none\r\n"))
        #expect(text.hasSuffix("\r\n\r\nRIFFdata"))

        let head = CastAudioServer.response(forRequest: "HEAD /announce-x.wav?x=1 HTTP/1.1\r\n\r\n", path: "/announce-x.wav", body: body)
        #expect(String(decoding: head.bytes, as: UTF8.self).hasSuffix("Content-Length: 8\r\nAccept-Ranges: none\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"))

        let other = CastAudioServer.response(forRequest: "GET /other.wav HTTP/1.1\r\n\r\n", path: "/announce-x.wav", body: body)
        #expect(!other.isAudio && String(decoding: other.bytes, as: UTF8.self).hasPrefix("HTTP/1.1 404"))
        let post = CastAudioServer.response(forRequest: "POST /announce-x.wav HTTP/1.1\r\n\r\n", path: "/announce-x.wav", body: body)
        #expect(!post.isAudio && String(decoding: post.bytes, as: UTF8.self).hasPrefix("HTTP/1.1 405"))
    }

    @Test func servesTheWAVOverRealHTTP() async throws {
        let wav = silentWAV()
        let server = CastAudioServer(wav: wav)
        defer { server.stop() }
        let port = try await server.start()
        #expect(server.path.hasPrefix("/announce-") && server.path.hasSuffix(".wav"))

        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)\(server.path)")!)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "audio/wav")
        #expect(http.value(forHTTPHeaderField: "Content-Length") == "\(wav.count)")
        #expect(http.value(forHTTPHeaderField: "Accept-Ranges") == "none")
        #expect(data == wav)
        #expect(server.requests == 1)

        let (_, missing) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/announce-guess.wav")!)
        #expect((missing as? HTTPURLResponse)?.statusCode == 404)
        #expect(server.requests == 1)
    }
}

// MARK: - The whole conversation, against a stand-in speaker

/// A Cast receiver on loopback (plain TCP, no TLS) that answers as a Nest
/// speaker does: status, launch, load -- and fetches the URL it is given,
/// as a real speaker would, before it reports playing and finished.
private final class FakeReceiver: @unchecked Sendable {
    enum Mode { case plays, busy, refusesLoad }

    let mode: Mode
    let volume: Double
    private let queue = DispatchQueue(label: "fake-cast-receiver")
    private let listener: NWListener
    private let lock = NSLock()
    private var _received: [CastMessage] = []
    private var _fetched: (status: Int, bytes: Int)?
    private var connection: NWConnection?
    /// The level now, as a real speaker reports it in every status.
    private var level: Double

    var received: [CastMessage] { lock.withLock { _received } }
    var fetched: (status: Int, bytes: Int)? { lock.withLock { _fetched } }
    var types: [String] { received.compactMap(\.type) }

    init(mode: Mode = .plays, volume: Double = 0.5) throws {
        self.mode = mode
        self.volume = volume
        level = volume
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [self] c in
            lock.withLock { connection = c }
            c.start(queue: queue)
            read(c, CastFrameReader())
        }
        return try await withCheckedThrowingContinuation { cont in
            let done = Locked(false)
            listener.stateUpdateHandler = { [listener] state in
                if case .ready = state, !done.value, let port = listener.port?.rawValue {
                    done.value = true
                    cont.resume(returning: port)
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        lock.withLock { connection }?.cancel()
    }

    private func read(_ c: NWConnection, _ reader: CastFrameReader) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
            var reader = reader
            if let data, let messages = try? reader.feed(data) {
                for m in messages { handle(m, on: c) }
            }
            if error == nil && !complete { read(c, reader) }
        }
    }

    private func reply(_ c: NWConnection, _ payload: [String: Any], _ ns: String, from source: String) {
        c.send(content: CastMessage.json(payload, namespace: ns, from: source, to: CastNamespace.senderId).framed(),
               completion: .contentProcessed { _ in })
    }

    private func status(_ apps: [[String: Any]], level: Double) -> [String: Any] {
        ["type": "RECEIVER_STATUS", "status": ["applications": apps, "volume": ["level": level, "muted": false]] as [String: Any]]
    }

    private func handle(_ m: CastMessage, on c: NWConnection) {
        lock.withLock { _received.append(m) }
        let body = m.payload ?? [:]
        switch m.type {
        case "GET_STATUS":
            let apps: [[String: Any]] = mode == .busy
                ? [["appId": "CC32E753", "displayName": "Spotify", "isIdleScreen": false]] : []
            reply(c, status(apps, level: lock.withLock { level }), CastNamespace.receiver, from: CastNamespace.receiverId)
        case "SET_VOLUME":
            let set = (body["volume"] as? [String: Any])?["level"] as? Double ?? volume
            lock.withLock { level = set }
            reply(c, status([], level: set), CastNamespace.receiver, from: CastNamespace.receiverId)
        case "LAUNCH":
            reply(c, status([["appId": CastNamespace.defaultMediaReceiver, "sessionId": "sess-1",
                              "transportId": "transport-1", "isIdleScreen": false]], level: lock.withLock { level }),
                  CastNamespace.receiver, from: CastNamespace.receiverId)
        case "LOAD":
            if mode == .refusesLoad {
                reply(c, ["type": "LOAD_FAILED", "requestId": body["requestId"] ?? 0], CastNamespace.media, from: "transport-1")
                return
            }
            let url = ((body["media"] as? [String: Any])?["contentId"] as? String).flatMap(URL.init(string:))
            Task { [self] in
                var fetched: (Int, Int) = (0, 0)
                if let url, let (data, response) = try? await URLSession(configuration: .ephemeral).data(from: url) {
                    fetched = ((response as? HTTPURLResponse)?.statusCode ?? 0, data.count)
                }
                lock.withLock { _fetched = fetched }
                reply(c, ["type": "MEDIA_STATUS", "status": [["playerState": "PLAYING"]]], CastNamespace.media, from: "transport-1")
                try? await Task.sleep(for: .milliseconds(50))
                reply(c, ["type": "MEDIA_STATUS", "status": [["playerState": "IDLE", "idleReason": "FINISHED"]]],
                      CastNamespace.media, from: "transport-1")
            }
        default:
            break
        }
    }
}

private struct FixedDiscovery: CastDiscovering {
    let port: UInt16
    func find(_ target: SpeakerDevice, timeout: Double) async throws -> CastDevice {
        CastDevice(name: target.name, model: "Google Nest Audio", serviceName: "Fake",
                   endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))
    }
}

@Suite(.serialized) struct CastSessionTests {
    private func speaker(_ receiver: FakeReceiver) async throws -> CastSpeaker {
        let port = try await receiver.start()
        return CastSpeaker(discovery: FixedDiscovery(port: port), discoveryTimeout: 1, stepTimeout: 3, useTLS: false)
    }

    @Test func connectsLaunchesLoadsAndWaitsForTheEnd() async throws {
        let receiver = try FakeReceiver()
        defer { receiver.stop() }
        let cast = try await speaker(receiver)
        let wav = silentWAV()
        var config = SpeakerConfig()
        config.effectiveAnnounceVolumeEnabled = true
        config.effectiveAnnounceVolume = 30

        try await cast.speak(wav: wav, target: lake, config: config)
        for _ in 0..<50 where !receiver.types.contains("STOP") {
            try await Task.sleep(for: .milliseconds(20))
        }

        let types = receiver.types
        #expect(Array(types.prefix(5)) == ["CONNECT", "GET_STATUS", "SET_VOLUME", "LAUNCH", "CONNECT"])
        #expect(types.contains("LOAD"))
        let load = try #require(receiver.received.first { $0.type == "LOAD" })
        #expect(load.destinationId == "transport-1")
        #expect(load.namespace == CastNamespace.media)
        let media = try #require(load.payload?["media"] as? [String: Any])
        #expect(media["contentType"] as? String == "audio/wav")
        #expect(media["streamType"] as? String == "BUFFERED")
        #expect(load.payload?["autoplay"] as? Bool == true)
        let url = try #require(media["contentId"] as? String)
        #expect(url.hasPrefix("http://127.0.0.1:") && url.contains("/announce-") && url.hasSuffix(".wav"))
        // The speaker could fetch exactly the WAV.
        #expect(receiver.fetched?.status == 200)
        #expect(receiver.fetched?.bytes == wav.count)
        // The level was set for the announcement, then put back, and the
        // player this launched was stopped.
        let volumes = receiver.received.filter { $0.type == "SET_VOLUME" }
            .compactMap { ($0.payload?["volume"] as? [String: Any])?["level"] as? Double }
        #expect(volumes == [0.3, 0.5])
        let stop = try #require(receiver.received.first { $0.type == "STOP" })
        #expect(stop.payload?["sessionId"] as? String == "sess-1")
    }

    @Test func leavesTheVolumeAloneUnlessAsked() async throws {
        let receiver = try FakeReceiver()
        defer { receiver.stop() }
        let cast = try await speaker(receiver)
        try await cast.speak(wav: silentWAV(), target: lake, config: SpeakerConfig())
        #expect(!receiver.types.contains("SET_VOLUME"))
        #expect(receiver.types.contains("LOAD"))
    }

    @Test func doesNotInterruptASpeakerPlayingSomethingElse() async throws {
        let receiver = try FakeReceiver(mode: .busy)
        defer { receiver.stop() }
        let cast = try await speaker(receiver)
        await #expect(throws: CastError.busy("Spotify")) {
            try await cast.speak(wav: silentWAV(), target: lake, config: SpeakerConfig())
        }
        #expect(!receiver.types.contains("LAUNCH"))
    }

    @Test func aRefusedLoadThrows() async throws {
        let receiver = try FakeReceiver(mode: .refusesLoad)
        defer { receiver.stop() }
        let cast = try await speaker(receiver)
        await #expect(throws: CastError.self) {
            try await cast.speak(wav: silentWAV(), target: lake, config: SpeakerConfig())
        }
    }

    @Test func refusesAudioThatIsNotAWAV() async throws {
        let cast = CastSpeaker(discovery: FixedDiscovery(port: 1), discoveryTimeout: 1, stepTimeout: 1, useTLS: false)
        await #expect(throws: CastError.unplayable) {
            try await cast.speak(wav: Data("not audio".utf8), target: lake, config: SpeakerConfig())
        }
    }
}

// MARK: - The setting

@Suite struct HomeCastVoiceConfigTests {
    @Test func absentMeansOffAndRoundTrips() throws {
        let old = #"{"enabled":true,"default_target":"lake","structure_id":"s","targets":{}}"#
        let c = try JSONDecoder().decode(SpeakerConfig.self, from: Data(old.utf8))
        #expect(c.homeCastVoice == nil)
        #expect(c.effectiveHomeCastVoice == false)

        var on = c
        on.effectiveHomeCastVoice = true
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(on)) as? [String: Any])
        #expect(json["home_cast_voice"] as? Bool == true)
        let back = try JSONDecoder().decode(SpeakerConfig.self, from: JSONEncoder().encode(on))
        #expect(back.effectiveHomeCastVoice == true)
    }

    @Test func theConfigFileWritesItAndKeepsOtherKeys() throws {
        final class MemoryFS: ConfigFileSystem, @unchecked Sendable {
            var data: Data?
            func read(_ url: URL) throws -> Data? { data }
            func write(_ data: Data, to url: URL) throws { self.data = data }
        }
        let fs = MemoryFS()
        fs.data = Data(#"{"enabled":true,"default_target":"lake","structure_id":"s","targets":{},"someone_elses":7}"#.utf8)
        let file = SpeakerConfigFile(url: URL(fileURLWithPath: "/tmp/speaker_broadcast.json"), fileSystem: fs)
        guard case .loaded(var config) = file.read() else { Issue.record("did not load"); return }
        config.effectiveHomeCastVoice = true
        try file.write(config)
        let written = try #require(try JSONSerialization.jsonObject(with: fs.data!) as? [String: Any])
        #expect(written["home_cast_voice"] as? Bool == true)
        #expect(written["someone_elses"] as? Int == 7)
        guard case .loaded(let reread) = file.read() else { Issue.record("did not reload"); return }
        #expect(reread.effectiveHomeCastVoice == true)
    }

    @Test func privacyLineAndVoiceEngineVisibility() {
        var c = SpeakerConfig()
        c.localEngine = .gemini
        c.effectiveHomeCastVoice = true
        #expect(c.usesVoiceEngine && c.geminiSpeaks)
        #expect(c.chatMessagesSentTo == "Messages are sent to Google Home, and to Gemini to be spoken on your Home speakers (Gemini TTS); nowhere else.")
        c.speakLocal = true
        c.speakPhone = true
        #expect(c.chatMessagesSentTo == "Messages are sent to Google Home, and to Gemini to be spoken on your Home speakers, this Mac and your phone (Gemini TTS); nowhere else.")
        c.speakHome = false
        #expect(c.chatMessagesSentTo == "Messages are sent to Google Home, and to Gemini to be spoken on this Mac and your phone (Gemini TTS); nowhere else.")
        var off = SpeakerConfig()
        off.localEngine = .gemini
        #expect(!off.usesVoiceEngine && !off.geminiSpeaks)
        #expect(off.chatMessagesSentTo == "Nothing is sent anywhere except to Google Home.")
        #expect(SpeakerConfig.homeCastFooter(off) == nil)
    }
}

// MARK: - The announcer

final class FakeCast: CastSpeaking, @unchecked Sendable {
    let log: EventLog
    var error: Error?
    private let lock = NSLock()
    private var _calls: [(wav: Data, target: SpeakerDevice)] = []
    var calls: [(wav: Data, target: SpeakerDevice)] { lock.withLock { _calls } }

    init(log: EventLog) { self.log = log }

    func speak(wav: Data, target: SpeakerDevice, config: SpeakerConfig) async throws {
        lock.withLock { _calls.append((wav, target)) }
        log.add("cast:start")
        if let error { log.add("cast:failed"); throw error }
        log.add("cast:done")
    }
}

private final class CountingGemini: GeminiSpeaking, @unchecked Sendable {
    let wav = silentWAV()
    var error: Error?
    private let lock = NSLock()
    private var _synth = 0
    private var _speak = 0
    var synthCalls: Int { lock.withLock { _synth } }
    var speakCalls: Int { lock.withLock { _speak } }

    func speak(_ text: String, voice: String, apiKey: String, started: @escaping @Sendable (Double) async -> Void) async throws {
        lock.withLock { _speak += 1 }
        await started(0.2)
    }

    func synthesizeWAV(_ text: String, voice: String, apiKey: String) async throws -> Data? {
        lock.withLock { _synth += 1 }
        if let error { throw error }
        return wav
    }
}

private struct CastRig {
    let log = EventLog()
    let home: FakeHome
    let local: FakeLocal
    let phone: FakePhone
    let cast: FakeCast
    let gemini = CountingGemini()
    let messages = Locked<[String]>([])
    let announcer: Announcer

    init(key: String? = "gem-key") {
        home = FakeHome(log: log)
        local = FakeLocal(log: log)
        phone = FakePhone(log: log)
        cast = FakeCast(log: log)
        let messages = self.messages
        announcer = Announcer(home: home, local: local, phone: phone, cast: cast, media: FakeMedia(log: log),
                              gemini: gemini, geminiKey: { key }, log: { line in messages.value.append(line) })
    }

    static func config(home: Bool = true, local: Bool = false, phone: Bool = false, cast: Bool = true) -> SpeakerConfig {
        var c = SpeakerConfig(enabled: true, defaultTarget: "lake", structureId: "structure@s", targets: ["lake": lake])
        c.speakHome = home
        c.speakLocal = local
        c.speakPhone = phone
        c.homeCastVoice = cast
        c.localEngine = .gemini
        c.geminiVoice = "voice_custom_clone_01"
        return c
    }
}

@Suite struct AnnouncerCastTests {
    @Test func homeOnlySynthesizesAndCasts() async {
        let rig = CastRig()
        let outcome = await rig.announcer.announce("Build finished.", config: CastRig.config(), force: false)
        #expect(outcome == .announced(home: .spoken, local: .off, phone: .off))
        #expect(rig.gemini.synthCalls == 1)
        #expect(rig.cast.calls.count == 1)
        #expect(rig.cast.calls.first?.wav == rig.gemini.wav)
        #expect(rig.cast.calls.first?.target == lake)
        #expect(rig.home.configs.isEmpty)  // no Assistant broadcast
    }

    @Test func homeMacAndPhoneShareOneSynthesis() async {
        let rig = CastRig()
        let outcome = await rig.announcer.announce(
            "All three.", config: CastRig.config(home: true, local: true, phone: true), force: false)
        #expect(outcome == .announced(home: .spoken, local: .spoken, phone: .spoken))
        #expect(rig.gemini.synthCalls == 1)
        #expect(rig.cast.calls.count == 1)
        #expect(rig.phone.calls.first?.wav == rig.gemini.wav)
        #expect(rig.home.configs.isEmpty)
    }

    @Test func aFailedCastFallsBackToBroadcast() async {
        let rig = CastRig()
        rig.cast.error = CastError.notFound("Lake Office")
        let outcome = await rig.announcer.announce("Build finished.", config: CastRig.config(), force: false)
        #expect(outcome == .announced(home: .spoken, local: .off, phone: .off))
        #expect(rig.cast.calls.count == 1)
        #expect(rig.home.configs.count == 1)
        #expect(rig.log.events.firstIndex(of: "cast:failed")! < rig.log.events.firstIndex(of: "home:start")!)
        #expect(rig.messages.value.contains { $0.contains("Casting to Lake Office failed") && $0.contains("Google Assistant broadcast") })
    }

    @Test func aFailedSynthesisFallsBackToBroadcastWithoutCasting() async {
        let rig = CastRig()
        rig.gemini.error = GeminiSpeechError.timedOut
        let outcome = await rig.announcer.announce("Build finished.", config: CastRig.config(), force: false)
        #expect(outcome == .announced(home: .spoken, local: .off, phone: .off))
        #expect(rig.cast.calls.isEmpty)
        #expect(rig.home.configs.count == 1)
        #expect(rig.messages.value.contains { $0.contains("Gemini voice failed for the Home speakers") })
    }

    @Test func noKeyOrNoGeminiOrSwitchedOffBroadcastsAsBefore() async {
        let noKey = CastRig(key: nil)
        _ = await noKey.announcer.announce("Hi.", config: CastRig.config(), force: false)
        #expect(noKey.cast.calls.isEmpty && noKey.gemini.synthCalls == 0 && noKey.home.configs.count == 1)
        #expect(noKey.messages.value.contains { $0.contains("no Gemini API key") })

        let apple = CastRig()
        var c = CastRig.config()
        c.localEngine = .apple
        _ = await apple.announcer.announce("Hi.", config: c, force: false)
        #expect(apple.cast.calls.isEmpty && apple.gemini.synthCalls == 0 && apple.home.configs.count == 1)

        let off = CastRig()
        _ = await off.announcer.announce("Hi.", config: CastRig.config(cast: false), force: false)
        #expect(off.cast.calls.isEmpty && off.gemini.synthCalls == 0 && off.home.configs.count == 1)
        #expect(off.messages.value.isEmpty)
    }
}
