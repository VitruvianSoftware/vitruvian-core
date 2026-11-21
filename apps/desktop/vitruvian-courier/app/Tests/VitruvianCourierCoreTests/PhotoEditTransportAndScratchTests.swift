// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Foundation
import XCTest

@testable import VitruvianCourierCore

/// A stand-in network for `URLSession`: a host's handler answers each request itself. Nothing leaves the process.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (StubURLProtocol) -> Void
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    private let stoppedFlag = NSLock()
    nonisolated(unsafe) private var _stopped = false

    static func register(host: String, _ handler: @escaping Handler) {
        lock.withLock { handlers[host] = handler }
    }

    static func unregister(host: String) {
        lock.withLock { _ = handlers.removeValue(forKey: host) }
    }

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    var isStopped: Bool { stoppedFlag.withLock { _stopped } }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return lock.withLock { handlers[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host, let handler = Self.lock.withLock({ Self.handlers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        handler(self)
    }

    override func stopLoading() {
        stoppedFlag.withLock { _stopped = true }
    }

    func respond(status: Int = 200, headers: [String: String] = [:]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func send(_ data: Data) { client?.urlProtocol(self, didLoad: data) }
    func finish() { client?.urlProtocolDidFinishLoading(self) }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func add(_ n: Int = 1) { lock.withLock { _value += n } }
}

/// What photo edits do on the wire (no redirects, a capped answer) and how their scratch files are let go once a draft
/// is sent or the photo is taken out of it. All data is made up.
@MainActor
final class PhotoEditTransportAndScratchTests: XCTestCase {
    private var hosts: [String] = []
    private var scratch: [URL] = []

    override func tearDown() async throws {
        for host in hosts { StubURLProtocol.unregister(host: host) }
        hosts = []
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
        AppLockGate.shared.resetForTesting()
    }

    private func host(_ handler: @escaping StubURLProtocol.Handler) -> String {
        let name = "t\(UUID().uuidString.prefix(8).lowercased()).example.test"
        StubURLProtocol.register(host: name, handler)
        hosts.append(name)
        return name
    }

    private func request(to host: String, key: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://\(host)/edit")!)
        request.httpMethod = "POST"
        if let key { request.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
        return request
    }

    private func thrownCode(_ transport: ImageEditHTTPTransport, _ request: URLRequest) async -> URLError.Code? {
        do {
            _ = try await transport.send(request)
            return nil
        } catch {
            return (error as? URLError)?.code
        }
    }

    // MARK: - Redirects

    func testARedirectIsNotFollowedAndNothingIsSentToItsTarget() async {
        let targetHits = Counter()
        let targetKeys = Counter()
        let target = host { proto in
            targetHits.add()
            if proto.request.value(forHTTPHeaderField: "x-goog-api-key") != nil { targetKeys.add() }
            proto.respond(); proto.send(Data("ok".utf8)); proto.finish()
        }
        let origin = host { proto in
            let moved = HTTPURLResponse(url: proto.request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                                        headerFields: ["Location": "https://\(target)/elsewhere"])!
            proto.client?.urlProtocol(proto, wasRedirectedTo: URLRequest(url: URL(string: "https://\(target)/elsewhere")!),
                                      redirectResponse: moved)
        }
        let transport = ImageEditHTTPTransport(configuration: StubURLProtocol.configuration)
        let code = await thrownCode(transport, request(to: origin, key: "fixture-key"))
        XCTAssertEqual(code, .httpTooManyRedirects)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(targetHits.value, 0, "the address the redirect named was never asked")
        XCTAssertEqual(targetKeys.value, 0, "and so never saw the key")
    }

    func testAnEditThatIsRedirectedEndsAsANetworkError() async {
        let target = host { proto in proto.respond(); proto.send(Data("{}".utf8)); proto.finish() }
        let origin = host { proto in
            let moved = HTTPURLResponse(url: proto.request.url!, statusCode: 307, httpVersion: "HTTP/1.1",
                                        headerFields: ["Location": "https://\(target)/x"])!
            proto.client?.urlProtocol(proto, wasRedirectedTo: URLRequest(url: URL(string: "https://\(target)/x")!),
                                      redirectResponse: moved)
        }
        let transport = ImageEditHTTPTransport(configuration: StubURLProtocol.configuration)
        let gemini = GeminiImageEditor(apiKey: "fixture-key", baseURL: URL(string: "https://\(origin)")!, transport: transport)
        let openAI = OpenAIImageEditor(apiKey: "fixture-key", baseURL: URL(string: "https://\(origin)/v1")!, transport: transport)
        let photo = TestImages.jpeg(width: 40, height: 30)
        let a = await gemini.edit(image: photo, mimeType: "image/jpeg", instruction: "x")
        let b = await openAI.edit(image: photo, mimeType: "image/jpeg", instruction: "x")
        XCTAssertEqual(a, .failure(.network))
        XCTAssertEqual(b, .failure(.network))
    }

    // MARK: - Size of the answer

    func testAnAnswerPastTheLimitIsAbortedWhileItStreams() async throws {
        let sent = Counter()
        let stopped = Counter()
        let streaming = host { proto in
            proto.respond()
            DispatchQueue.global().async {
                let chunk = Data(repeating: 0x61, count: 100_000)
                // Up to 100 MB if nobody stops it.
                while !proto.isStopped, sent.value < 100_000_000 {
                    proto.send(chunk)
                    sent.add(chunk.count)
                    usleep(200)
                }
                stopped.add()
            }
        }
        let transport = ImageEditHTTPTransport(configuration: StubURLProtocol.configuration, maxResponseBytes: 1_000_000)
        let code = await thrownCode(transport, request(to: streaming))
        XCTAssertEqual(code, .dataLengthExceedsMaximum)
        try await waitUntil { stopped.value == 1 }
        XCTAssertLessThan(sent.value, 20_000_000, "it stopped reading soon after the limit, not at the end of the stream")
    }

    func testADeclaredLengthPastTheLimitIsRefusedBeforeAnyBody() async {
        let sent = Counter()
        let origin = host { proto in
            proto.respond(headers: ["Content-Length": "5000000", "Content-Type": "application/json"])
            proto.send(Data(repeating: 0x61, count: 2048)); sent.add(2048)
        }
        let transport = ImageEditHTTPTransport(configuration: StubURLProtocol.configuration, maxResponseBytes: 1_000_000)
        let code = await thrownCode(transport, request(to: origin))
        XCTAssertEqual(code, .dataLengthExceedsMaximum)
    }

    func testAnEditWhoseAnswerIsTooBigSaysSo() async {
        let origin = host { proto in
            proto.respond()
            DispatchQueue.global().async {
                let chunk = Data(repeating: 0x61, count: 100_000)
                var total = 0
                while !proto.isStopped, total < 50_000_000 { proto.send(chunk); total += chunk.count; usleep(200) }
            }
        }
        let transport = ImageEditHTTPTransport(configuration: StubURLProtocol.configuration, maxResponseBytes: 500_000)
        let editor = GeminiImageEditor(apiKey: "fixture-key", baseURL: URL(string: "https://\(origin)")!, transport: transport)
        let result = await editor.edit(image: TestImages.jpeg(width: 40, height: 30), mimeType: "image/jpeg", instruction: "x")
        XCTAssertEqual(result, .failure(.responseTooLarge))
        XCTAssertFalse(ImageEditFailure.responseTooLarge.message(service: .googleAIStudio).isEmpty)
    }

    func testANormalAnswerStillComesBackWholeWhateverItsStatus() async throws {
        let ok = host { proto in
            proto.respond(headers: ["Content-Type": "application/json"])
            proto.send(Data("{\"a\":".utf8)); proto.send(Data("1}".utf8)); proto.finish()
        }
        let bad = host { proto in proto.respond(status: 400); proto.send(Data("nope".utf8)); proto.finish() }
        let transport = ImageEditHTTPTransport(configuration: StubURLProtocol.configuration)
        let (data, response) = try await transport.send(request(to: ok))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"a\":1}")
        XCTAssertEqual(response.statusCode, 200)
        let (body, failure) = try await transport.send(request(to: bad))
        XCTAssertEqual(failure.statusCode, 400)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "nope")
        XCTAssertEqual(ImageEditHTTPTransport.maxResponseBytes, 64 * 1024 * 1024)
    }

    func testStoppingTheCallerStopsTheRequest() async throws {
        let started = Counter()
        let stopped = Counter()
        let origin = host { proto in
            proto.respond()
            started.add()
            DispatchQueue.global().async {
                while !proto.isStopped { proto.send(Data(repeating: 0x61, count: 1000)); usleep(1000) }
                stopped.add()
            }
        }
        let transport = ImageEditHTTPTransport(configuration: StubURLProtocol.configuration)
        let call = request(to: origin)
        let task = Task { await thrownCode(transport, call) }
        try await waitUntil { started.value == 1 }
        task.cancel()
        let code = await task.value
        XCTAssertEqual(code, .cancelled)
        try await waitUntil { stopped.value == 1 }
    }

    // MARK: - Scratch files after a send or a removal

    private func makeScratchRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("photo-scratch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        scratch.append(root)
        return root
    }

    private func scratchPhoto(in root: URL, name: String = "beach edited.png") throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        try TestImages.jpeg(width: 16, height: 16).write(to: file)
        return file
    }

    private func start() async throws -> ConversationHarness {
        let h = try await startConversation(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1)]], features: ["!a": featuresJSON()],
            rows: ["!a": chatRow("!a", name: "Example Person", network: "signal")])
        try await h.open("!a")
        h.script.overrides["message.sendFile"] = .result(["event_id": "$file"])
        h.preferences.undoSendMillis = 0
        return h
    }

    func testTakingTheEditedPhotoOutOfTheDraftDeletesItsScratchFile() async throws {
        let h = try await start()
        defer { Task { await h.stop() } }
        let root = try makeScratchRoot()
        let composer = h.conversation.composer
        composer.scratchRoot = root
        let mine = try scratchPhoto(in: root)
        composer.attach([mine])
        let attachment = try XCTUnwrap(composer.attachments.first)
        composer.removeAttachment(attachment.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mine.path), "the scratch file went")
        XCTAssertFalse(FileManager.default.fileExists(atPath: mine.deletingLastPathComponent().path), "and its emptied folder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path), "never the root")

        // A file that is not in the scratch folder is never touched.
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("not-scratch-\(UUID().uuidString).png")
        try TestImages.jpeg(width: 8, height: 8).write(to: elsewhere)
        scratch.append(elsewhere)
        composer.attach([elsewhere])
        composer.removeAttachment(try XCTUnwrap(composer.attachments.first).id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.path))
    }

    func testSendingTheDraftDeletesTheScratchFileAndNothingElse() async throws {
        let h = try await start()
        defer { Task { await h.stop() } }
        let root = try makeScratchRoot()
        let composer = h.conversation.composer
        composer.scratchRoot = root
        let mine = try scratchPhoto(in: root)
        let other = try scratchPhoto(in: root, name: "second edited.png")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).png")
        try TestImages.jpeg(width: 8, height: 8).write(to: outside)
        scratch.append(outside)
        composer.attach([mine, outside])
        XCTAssertTrue(FileManager.default.fileExists(atPath: mine.path), "kept while it waits in the draft")
        await composer.submit()?.value
        XCTAssertEqual(h.server.receivedMethods().filter { $0 == "message.sendFile" }.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mine.path), "sent: the scratch file went")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "a file from elsewhere stays")
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "so does a scratch file not in this send")
    }

    func testAFileWhoseSendFailedStaysForAnotherTry() async throws {
        let h = try await start()
        defer { Task { await h.stop() } }
        h.script.overrides["message.sendFile"] = .error(code: -32603, message: "internal error")
        let root = try makeScratchRoot()
        let composer = h.conversation.composer
        composer.scratchRoot = root
        let mine = try scratchPhoto(in: root)
        composer.attach([mine])
        await composer.submit()?.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: mine.path), "not sent, so not deleted")
        XCTAssertEqual(composer.attachments.map(\.url), [mine], "and back in the draft")
    }

    func testAHeldSendKeepsTheScratchFileThroughTheUndoWindowThenDeletesIt() async throws {
        let h = try await start()
        defer { Task { await h.stop() } }
        h.preferences.undoSendMillis = 750
        let root = try makeScratchRoot()
        let composer = h.conversation.composer
        composer.scratchRoot = root
        composer.scratchReleaseGrace = .milliseconds(300)
        composer.entitlement = AlwaysEntitled() // undo send is a plan feature: without it nothing is held
        let mine = try scratchPhoto(in: root)
        composer.attach([mine])
        await composer.submit()?.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: mine.path), "Undo may still give it back")
        try await waitUntil { !FileManager.default.fileExists(atPath: mine.path) }
    }

    func testScratchHelpersOnlyTouchWhatIsInsideTheRoot() throws {
        let root = try makeScratchRoot()
        let inside = try scratchPhoto(in: root)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).png")
        try Data("x".utf8).write(to: outside)
        scratch.append(outside)
        XCTAssertTrue(PhotoEditScratch.isInside(inside, root: root))
        XCTAssertFalse(PhotoEditScratch.isInside(root, root: root))
        XCTAssertFalse(PhotoEditScratch.isInside(outside, root: root))
        XCTAssertFalse(PhotoEditScratch.isInside(root.appendingPathComponent("../\(outside.lastPathComponent)"), root: root))
        XCTAssertFalse(PhotoEditScratch.remove(outside, root: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(PhotoEditScratch.remove(inside, root: root))
    }
}

/// A small real picture for the requests that need one.
enum TestImages {
    static func jpeg(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .jpeg, properties: [:])!
    }
}
