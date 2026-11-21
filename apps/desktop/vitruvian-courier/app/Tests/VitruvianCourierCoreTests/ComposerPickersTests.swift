// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import AppKit
import XCTest

@testable import VitruvianCourierCore

/// A GIF service that answers from a script, and counts what it was asked.
final class FakeGIFProvider: GIFProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    var available = true
    var folder: URL
    /// A search for "slow" waits here until the test lets it go.
    private var gate: CheckedContinuation<Void, Never>?

    init(folder: URL) {
        self.folder = folder
    }

    var isAvailable: Bool { available }

    func count(_ name: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[name, default: 0]
    }

    var isWaiting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return gate != nil
    }

    func release() {
        lock.lock()
        let waiting = gate
        gate = nil
        lock.unlock()
        waiting?.resume()
    }

    private func bump(_ name: String) {
        lock.lock()
        counts[name, default: 0] += 1
        lock.unlock()
    }

    private func candidate(_ id: String) -> GIFCandidate {
        GIFCandidate(id: id, title: "GIF \(id)", mediaURL: "https://static.klipy.com/\(id).gif", mimeType: "image/gif",
                     width: 320, height: 240, previewURL: "https://static.klipy.com/\(id)-sm.gif",
                     mp4URL: "https://static.klipy.com/\(id).mp4")
    }

    func trending() async throws -> [GIFCandidate] {
        bump("trending")
        return [candidate("t1"), candidate("t2")]
    }

    func search(_ query: String) async throws -> [GIFCandidate] {
        bump("search")
        if query == "slow" {
            await withCheckedContinuation { continuation in
                lock.lock()
                gate = continuation
                lock.unlock()
            }
            return [candidate("slow1")]
        }
        if query == "boom" { throw GIFProviderError.status(500) }
        return [candidate("found-\(query)")]
    }

    func fetchFile(for candidate: GIFCandidate, asMP4: Bool) async throws -> URL {
        bump("file")
        bump(asMP4 ? "file-mp4" : "file-gif")
        if candidate.id == "broken" { throw GIFProviderError.status(404) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(candidate.id).\(asMP4 ? "mp4" : "gif")")
        try Data("bytes".utf8).write(to: url)
        return url
    }

    func fetchPreview(for candidate: GIFCandidate) async throws -> URL? {
        bump("preview")
        return folder.appendingPathComponent("\(candidate.id)-preview.gif")
    }
}

/// The message box's pickers: the emoji picker's insert, the online GIF picker's gate, and the loop previews.
@MainActor
final class ComposerPickersTests: XCTestCase {
    private struct Made {
        let composer: ComposerModel
        let sender: FakeSender
        let preferences: ComposerPreferences
        let provider: FakeGIFProvider
        let usage: EmojiUsageStore
    }

    private func make() -> Made {
        let store = TestDefaults()
        addTeardownBlock { store.remove() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("picker-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let preferences = ComposerPreferences(defaults: store.defaults)
        let sender = FakeSender()
        let composer = ComposerModel(sender: sender, draftDelay: 0, sleep: { _ in }, preferences: preferences)
        let provider = FakeGIFProvider(folder: folder)
        composer.gifProvider = provider
        let usage = EmojiUsageStore(defaults: store.defaults)
        composer.emojiUsage = usage
        composer.open("!a")
        return Made(composer: composer, sender: sender, preferences: preferences, provider: provider, usage: usage)
    }

    private func type(_ text: String, into composer: ComposerModel) {
        let current = composer.text as NSString
        let at = current.length
        composer.textChanged(to: current.replacingCharacters(in: NSRange(location: at, length: 0), with: text),
                             replacing: NSRange(location: at, length: 0), with: (text as NSString).length)
    }

    // MARK: Emoji picker

    func testAnEmojiGoesWhereTheCaretIsAndIsCounted() {
        let made = make()
        let composer = made.composer
        type("hello", into: composer)
        composer.selectionChanged(to: NSRange(location: 2, length: 0))
        composer.insertEmoji("😀")
        XCTAssertEqual(composer.text, "he😀llo")
        XCTAssertEqual(composer.selection, NSRange(location: 4, length: 0), "the caret ends after the emoji")
        XCTAssertEqual(made.usage.frequent(), ["😀"])

        composer.selectionChanged(to: NSRange(location: 0, length: 2))
        composer.insertEmoji("🎉")
        XCTAssertEqual(composer.text, "🎉😀llo", "a selection is replaced")
    }

    func testTheEmojiPickerClosesAfterAClickAndStaysOpenForShiftClick() {
        let made = make()
        let composer = made.composer
        composer.toggleEmojiPicker()
        XCTAssertTrue(composer.isEmojiPickerPresented)
        composer.insertEmoji("👍", keepOpen: true)
        XCTAssertTrue(composer.isEmojiPickerPresented, "Shift-click keeps it open")
        composer.insertEmoji("👍")
        XCTAssertFalse(composer.isEmojiPickerPresented, "a plain click closes it")
        XCTAssertEqual(composer.text, "👍👍")
        XCTAssertEqual(made.usage.frequent(), ["👍"])
    }

    func testEscapeClosesTheEmojiPickerBeforeAnythingElse() {
        let made = make()
        let composer = made.composer
        composer.startReply(to: QuotedMessage(eventID: "$q", senderName: "Ann", mine: false, text: "hi", kind: .text))
        composer.toggleEmojiPicker()
        XCTAssertTrue(composer.escape())
        XCTAssertFalse(composer.isEmojiPickerPresented)
        XCTAssertNotNil(composer.replyTarget, "the first Escape only closed the picker")
    }

    func testOpeningOnePickerClosesTheOthers() {
        let made = make()
        let composer = made.composer
        XCTAssertTrue(composer.openGIFPicker())
        composer.toggleEmojiPicker()
        XCTAssertTrue(composer.isEmojiPickerPresented)
        XCTAssertFalse(composer.isGIFPickerPresented)
        XCTAssertTrue(composer.openGIFPicker())
        XCTAssertFalse(composer.isEmojiPickerPresented)
        composer.open(nil)
        composer.toggleEmojiPicker()
        XCTAssertFalse(composer.isEmojiPickerPresented, "no chat, no picker")
    }

    func testTheSkinToneIsKept() {
        let made = make()
        made.composer.emojiSkinTone = .dark
        XCTAssertEqual(made.usage.skinTone, .dark)
    }

    // MARK: Online GIF search and its setting

    func testWithTheSettingOffNothingIsAskedOfTheGIFService() async {
        let made = make()
        let composer = made.composer
        made.preferences.searchGIFsOnline = false
        XCTAssertFalse(composer.canSearchGIFsOnline)
        composer.gifSearchQuery = "cats"
        await composer.refreshGIFResults()
        composer.gifSearchQuery = ""
        await composer.refreshGIFResults()
        await composer.selectGIFCandidate(GIFCandidate(id: "x", title: "x", mediaURL: "https://static.klipy.com/x.mp4", mimeType: "video/mp4"))
        let preview = await composer.gifPreviewFile(for: GIFCandidate(id: "x", title: "x", mediaURL: "m", mimeType: "image/gif", previewURL: "p"))
        XCTAssertNil(preview)
        XCTAssertEqual(composer.gifResults, [])
        XCTAssertNil(composer.pendingGIF)
        for name in ["trending", "search", "file", "preview"] {
            XCTAssertEqual(made.provider.count(name), 0, "\(name) must not be asked while the setting is off")
        }
    }

    func testWithNoKeyNothingIsAskedEitherAndTheSettingStaysOn() async {
        let made = make()
        made.provider.available = false
        XCTAssertTrue(made.preferences.searchGIFsOnline)
        XCTAssertFalse(made.composer.canSearchGIFsOnline)
        await made.composer.refreshGIFResults()
        XCTAssertEqual(made.provider.count("trending"), 0)
        XCTAssertEqual(made.composer.gifResultsState, .idle)
    }

    func testTrendingWithNothingTypedAndASearchWithSomething() async {
        let made = make()
        let composer = made.composer
        XCTAssertTrue(composer.canSearchGIFsOnline, "on by default")
        await composer.refreshGIFResults()
        XCTAssertEqual(composer.gifResults.map(\.id), ["t1", "t2"])
        XCTAssertEqual(composer.gifResultsState, .loaded)
        composer.gifSearchQuery = "  cats "
        await composer.refreshGIFResults()
        XCTAssertEqual(composer.gifResults.map(\.id), ["found-cats"])
        XCTAssertEqual(made.provider.count("trending"), 1)
        XCTAssertEqual(made.provider.count("search"), 1)
    }

    func testAFailedSearchSaysSoAndKeepsNothing() async {
        let made = make()
        let composer = made.composer
        await composer.refreshGIFResults()
        composer.gifSearchQuery = "boom"
        await composer.refreshGIFResults()
        XCTAssertEqual(composer.gifResults, [])
        guard case .failed = composer.gifResultsState else { return XCTFail("expected a failure, got \(composer.gifResultsState)") }
    }

    func testASlowAnswerForAnOldQueryIsDropped() async {
        let made = make()
        let composer = made.composer
        composer.gifSearchQuery = "slow"
        let slow = Task { await composer.refreshGIFResults() }
        while !made.provider.isWaiting { await Task.yield() }
        composer.gifSearchQuery = "fast"
        await composer.refreshGIFResults()
        XCTAssertEqual(composer.gifResults.map(\.id), ["found-fast"])
        made.provider.release()
        await slow.value
        XCTAssertEqual(composer.gifResults.map(\.id), ["found-fast"], "the old query's late answer must not replace it")
        XCTAssertEqual(composer.gifResultsState, .loaded)
    }

    func testChoosingAnOnlineGIFAttachesItToTheDraftAndNeverSendsIt() async throws {
        let made = make()
        let composer = made.composer
        await composer.refreshGIFResults()
        XCTAssertTrue(composer.openGIFPicker())
        let chosen = try XCTUnwrap(composer.gifResults.first)
        await composer.selectGIFCandidate(chosen)
        let pending = try XCTUnwrap(composer.pendingGIF, "the GIF is on the draft")
        XCTAssertEqual(pending.name, "GIF t1")
        XCTAssertEqual(pending.mimeType, "image/gif", "the GIF where the chat does not list MP4")
        XCTAssertTrue(pending.mediaURL.hasSuffix("t1.gif"), "it is the downloaded file, not the address")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.mediaURL))
        XCTAssertFalse(composer.isGIFPickerPresented)
        XCTAssertNil(composer.downloadingGIFID)
        XCTAssertTrue(made.sender.gifSends.isEmpty, "choosing alone never sends")
        XCTAssertEqual(made.provider.count("file"), 1)
    }

    func testTheMP4LoopIsSentOnlyWhereTheChatListsMP4() async throws {
        for (types, expectMP4) in [(["video/mp4", "image/gif"], true), (["image/gif"], false), (nil, false), ([], false)] as [([String]?, Bool)] {
            let made = make()
            var features = ChatFeatures.noFeatures
            features.gifFeatures = FileKindFeatures(supported: true, mimeTypes: types)
            made.composer.features = features
            await made.composer.refreshGIFResults()
            await made.composer.selectGIFCandidate(try XCTUnwrap(made.composer.gifResults.first))
            let pending = try XCTUnwrap(made.composer.pendingGIF)
            XCTAssertEqual(pending.mediaURL.hasSuffix(".mp4"), expectMP4, "\(String(describing: types))")
            XCTAssertEqual(pending.mimeType, expectMP4 ? "video/mp4" : "image/gif")
            XCTAssertEqual(made.provider.count(expectMP4 ? "file-mp4" : "file-gif"), 1)
        }
    }

    func testAFailedDownloadSaysSoAndAttachesNothing() async {
        let made = make()
        let composer = made.composer
        await composer.selectGIFCandidate(GIFCandidate(id: "broken", title: "b", mediaURL: "https://static.klipy.com/b.mp4", mimeType: "video/mp4"))
        XCTAssertNil(composer.pendingGIF)
        XCTAssertFalse(composer.notices.isEmpty)
        XCTAssertNil(composer.downloadingGIFID)
    }

    func testRecentGIFsStillWorkWithTheSettingOff() async {
        let made = make()
        let composer = made.composer
        made.preferences.searchGIFsOnline = false
        let recent = StickerItemWire(id: "gif:$e", packID: "recent_gifs", name: "Mine", mediaURL: "/tmp/mine.gif", mimeType: "image/gif", usage: ["gif"])
        await composer.selectGIF(recent)
        XCTAssertEqual(composer.pendingGIF, recent)
    }

    // MARK: Previews of recent GIFs

    private func tempFile(_ name: String = UUID().uuidString) -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("loop-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent(name)
    }

    private func gifBytes() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 6, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .gif, properties: [:])!
    }

    private func writeTinyMP4(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<3 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), 0x80, CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
    }

    func testLoopFilesAreToldApartByTheirFirstBytes() throws {
        XCTAssertEqual(LoopFileKind.detect(Data("GIF89a".utf8) + Data(count: 6)), .gif)
        XCTAssertEqual(LoopFileKind.detect(Data([0, 0, 0, 0x20]) + Data("ftypisom".utf8)), .mp4)
        XCTAssertEqual(LoopFileKind.detect(Data("PNGDATA...".utf8)), .other)
        XCTAssertEqual(LoopFileKind.detect(Data()), .other)
        let gif = tempFile()
        try gifBytes().write(to: gif)
        XCTAssertEqual(LoopFileKind.detect(atPath: gif.path), .gif)
        XCTAssertEqual(LoopFileKind.detect(atPath: "/nonexistent/file"), .other)
    }

    func testAnMP4LoopWithNoExtensionShowsItsFirstFrameNotAPlaceholder() async throws {
        // Courier keeps media under a hash with no extension; a GIF from a chat network is often an MP4.
        let file = tempFile("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
        try await writeTinyMP4(to: file)
        XCTAssertEqual(LoopFileKind.detect(atPath: file.path), .mp4)
        let loader = ThumbnailLoader()
        let plain = await loader.thumbnail(atPath: file.path)
        XCTAssertNil(plain, "ImageIO cannot read a video; this is why recent MP4 tiles showed a play icon and a file name")
        let frame = await loader.loopThumbnail(atPath: file.path)
        XCTAssertEqual(frame?.image.width, 64)
        XCTAssertEqual(frame?.image.height, 48)
        let after = await loader.thumbnail(atPath: file.path)
        XCTAssertNil(after, "the conversation's thumbnail cache is not given a video's frame")
    }

    func testAGIFShowsItsFirstFrameAndAFileThatIsNeitherShowsNothing() async throws {
        let gif = tempFile()
        try gifBytes().write(to: gif)
        let other = tempFile()
        try Data("plain text".utf8).write(to: other)
        let loader = ThumbnailLoader()
        let frame = await loader.loopThumbnail(atPath: gif.path)
        XCTAssertEqual(frame?.image.width, 8)
        let none = await loader.loopThumbnail(atPath: other.path)
        XCTAssertNil(none)
        let missing = await loader.loopThumbnail(atPath: "/nonexistent/file")
        XCTAssertNil(missing)
    }
}
