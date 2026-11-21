// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import VitruvianCourierCore

/// Edit a photo with AI: who edits (the resolver and its setting), what is sent to each service (built and read
/// against fixtures, never the network), how failures read, that location and size are dealt with before upload, that
/// the first photo to a service asks once, and that a result is only ever drafted, never sent. All data is made up.
@MainActor
final class PhotoEditingTests: XCTestCase {
    private var scratch: [URL] = []

    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
        for url in scratch { try? FileManager.default.removeItem(at: url) }
        scratch = []
    }

    // MARK: - Fixtures

    /// A picture of the given size, encoded as `type`, with GPS and camera details in it when asked.
    private func makeImage(
        width: Int, height: Int, type: UTType = .jpeg, withMetadata: Bool = false, alpha: Bool = false,
        orientation: Int = 1
    ) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: info)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: alpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 3, height: height / 2))
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if withMetadata {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 51.5,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 0.12,
                kCGImagePropertyGPSLongitudeRef: "W",
            ]
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05"]
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFMake: "Example Camera Co", kCGImagePropertyTIFFModel: "Model 1",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    private func size(of data: Data) -> (Int, Int)? {
        guard let props = properties(of: data),
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        return (w, h)
    }

    private func assertNoLocationOrCamera(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        let props = properties(of: data)
        XCTAssertNil(props?[kCGImagePropertyGPSDictionary], "no GPS", file: file, line: line)
        // ImageIO always writes the picture's own colour space and pixel size under {Exif}; nothing else may be there
        // (no date taken, no camera settings).
        let structural: Set<String> = [
            kCGImagePropertyExifColorSpace as String, kCGImagePropertyExifPixelXDimension as String,
            kCGImagePropertyExifPixelYDimension as String,
        ]
        let exifKeys = Set(((props?[kCGImagePropertyExifDictionary] as? [String: Any]) ?? [:]).keys)
        XCTAssertTrue(exifKeys.isSubset(of: structural), "no EXIF beyond the pixel size: \(exifKeys)", file: file, line: line)
        XCTAssertNil((props?[kCGImagePropertyExifDictionary] as? [String: Any])?[kCGImagePropertyExifDateTimeOriginal as String],
                     "no date taken", file: file, line: line)
        XCTAssertNil(props?[kCGImagePropertyTIFFDictionary], "no camera make or model", file: file, line: line)
        XCTAssertNil(props?[kCGImagePropertyIPTCDictionary], "no IPTC", file: file, line: line)
    }

    private func keyStore(_ keys: [AIProviderKind] = []) -> AIKeyStore {
        AIKeyStore(store: InMemoryCredentialStore(Dictionary(uniqueKeysWithValues: keys.map { ($0.rawValue, "fixture-\($0.rawValue)-key") })))
    }

    private func defaults() -> (UserDefaults, () -> Void) {
        let name = "courier.test.photoEditing.\(UUID().uuidString)"
        let suite = ScratchDefaults.suite(named: name)!
        return (suite, { suite.removePersistentDomain(forName: name) })
    }

    private func geminiSuccessJSON(image: Data, mime: String = "image/png") -> String {
        #"{"candidates":[{"content":{"role":"model","parts":[{"text":"Here you go."},{"inlineData":{"mimeType":"\#(mime)","data":"\#(image.base64EncodedString())"}}]},"finishReason":"STOP"}]}"#
    }

    private func openAISuccessJSON(image: Data) -> String {
        #"{"created":1,"output_format":"png","data":[{"b64_json":"\#(image.base64EncodedString())"}]}"#
    }

    private func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(StubHTTPTransport.bodyData(of: request))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    /// The bytes of the one file part in a multipart body, and the text fields.
    private func multipartParts(_ request: URLRequest) throws -> (fields: [String: String], file: Data, fileHeaders: String) {
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try XCTUnwrap(contentType.components(separatedBy: "boundary=").last)
        let body = try XCTUnwrap(StubHTTPTransport.bodyData(of: request))
        let delimiter = Data("--\(boundary)".utf8)
        var fields: [String: String] = [:]
        var file = Data()
        var fileHeaders = ""
        var cursor = body.startIndex
        var chunks: [Data] = []
        while let range = body.range(of: delimiter, in: cursor ..< body.endIndex) {
            chunks.append(body[cursor ..< range.lowerBound])
            cursor = range.upperBound
        }
        for chunk in chunks.dropFirst() {
            let separator = Data("\r\n\r\n".utf8)
            guard let split = chunk.range(of: separator) else { continue }
            let headers = String(decoding: chunk[chunk.startIndex ..< split.lowerBound], as: UTF8.self)
            var content = Data(chunk[split.upperBound...])
            if content.suffix(2) == Data("\r\n".utf8) { content = content.dropLast(2) }
            if headers.contains("filename=") {
                file = content
                fileHeaders = headers
            } else if let nameRange = headers.range(of: #"name="([^"]+)""#, options: .regularExpression) {
                let name = headers[nameRange].dropFirst(6).dropLast(1)
                fields[String(name)] = String(decoding: content, as: UTF8.self)
            }
        }
        return (fields, file, fileHeaders)
    }

    // MARK: - Which services can edit

    func testOnlyGoogleAndOpenAICanEditPhotos() {
        for kind in AIProviderKind.allCases {
            let expected = kind == .googleAIStudio || kind == .openAI
            XCTAssertEqual(kind.canEditPhotos, expected, "\(kind)")
        }
        XCTAssertEqual(AIProviderKind.photoEditingServices, [.googleAIStudio, .openAI])
    }

    func testUnsupportedServicesAnswerUnsupportedAndNeverTouchTheNetwork() async {
        for kind in AIProviderKind.allCases where !kind.canEditPhotos {
            let transport = StubHTTPTransport()
            // Even with a key saved (Anthropic, Unsloth, custom keep one), they have no image editing.
            let editor = ImageEditors.make(for: kind, keyStore: keyStore([kind]), transport: transport)
            let result = await editor.edit(image: makeImage(width: 40, height: 30), mimeType: "image/jpeg", instruction: "brighten it")
            XCTAssertEqual(result, .failure(.unsupported), "\(kind)")
            XCTAssertEqual(editor.provider, kind)
            XCTAssertTrue(transport.requests.isEmpty, "\(kind) sent nothing")
        }
    }

    func testCapableServicesWithNoKeySayNoKeyAndNeverTouchTheNetwork() async {
        for kind in AIProviderKind.photoEditingServices {
            let transport = StubHTTPTransport()
            let editor = ImageEditors.make(for: kind, keyStore: keyStore(), transport: transport)
            let result = await editor.edit(image: makeImage(width: 40, height: 30), mimeType: "image/jpeg", instruction: "brighten it")
            XCTAssertEqual(result, .failure(.noKey), "\(kind)")
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testFactoryBuildsTheRightEditorPerService() {
        XCTAssertTrue(ImageEditors.make(for: .googleAIStudio, keyStore: keyStore([.googleAIStudio])) is GeminiImageEditor)
        XCTAssertTrue(ImageEditors.make(for: .openAI, keyStore: keyStore([.openAI])) is OpenAIImageEditor)
    }

    func testModelIDsAreOneConstantEach() {
        XCTAssertEqual(GeminiImageModel.default, "gemini-nano-banana-2.1")
        XCTAssertEqual(OpenAIImageModel.default, "gpt-image-2.6-sunburst")
    }

    // MARK: - The resolver

    private func resolve(_ choice: PhotoEditingChoice, ai: Bool = true, main: AIProviderKind,
                         keys: Set<AIProviderKind>) -> PhotoEditingResolution {
        PhotoEditingResolver.resolve(choice: choice, aiEnabled: ai, mainService: main, hasKey: { keys.contains($0) })
    }

    func testAutomaticUsesTheMainServiceWhenItCanEditPhotos() {
        XCTAssertEqual(resolve(.automatic, main: .openAI, keys: [.openAI, .googleAIStudio]),
                       .service(.openAI, source: .mainService), "main wins over a saved Google key")
        XCTAssertEqual(resolve(.automatic, main: .googleAIStudio, keys: [.googleAIStudio, .openAI]),
                       .service(.googleAIStudio, source: .mainService))
    }

    func testAutomaticFallsBackToGoogleThenOpenAIThenNone() {
        // The main service can't edit: Google's saved key, then OpenAI's.
        XCTAssertEqual(resolve(.automatic, main: .anthropic, keys: [.anthropic, .googleAIStudio, .openAI]),
                       .service(.googleAIStudio, source: .savedKey))
        XCTAssertEqual(resolve(.automatic, main: .ollama, keys: [.openAI]), .service(.openAI, source: .savedKey))
        XCTAssertEqual(resolve(.automatic, main: .appleIntelligence, keys: []), .noService)
        XCTAssertEqual(resolve(.automatic, main: .anthropic, keys: [.anthropic]), .noService)
        // The main service is OpenAI but its key is gone: it can't edit now, so Google's key is used.
        XCTAssertEqual(resolve(.automatic, main: .openAI, keys: [.googleAIStudio]),
                       .service(.googleAIStudio, source: .savedKey))
        XCTAssertEqual(resolve(.automatic, main: .openAI, keys: []), .noService)
    }

    func testAFixedChoiceUsesThatServiceWhateverTheMainServiceIs() {
        XCTAssertEqual(resolve(.googleAIStudio, main: .openAI, keys: [.googleAIStudio, .openAI]),
                       .service(.googleAIStudio, source: .chosen))
        XCTAssertEqual(resolve(.openAI, main: .anthropic, keys: [.openAI]), .service(.openAI, source: .chosen))
        XCTAssertEqual(resolve(.googleAIStudio, main: .googleAIStudio, keys: [.openAI]), .missingKey(.googleAIStudio))
        XCTAssertEqual(resolve(.openAI, main: .openAI, keys: [.googleAIStudio]), .missingKey(.openAI))
    }

    func testAIOffMeansPhotoEditingIsOffWhateverElseIsSet() {
        for choice in PhotoEditingChoice.allCases {
            XCTAssertEqual(resolve(choice, ai: false, main: .openAI, keys: [.openAI, .googleAIStudio]), .aiOff)
        }
    }

    /// Every combination of choice, AI on or off, main service and saved keys (3 x 2 x 8 x 256).
    func testResolverIsRightForEveryCombination() {
        let kinds = AIProviderKind.allCases
        for choice in PhotoEditingChoice.allCases {
            for ai in [true, false] {
                for main in kinds {
                    for mask in 0 ..< (1 << kinds.count) {
                        let keys = Set(kinds.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
                        let got = resolve(choice, ai: ai, main: main, keys: keys)
                        let context = "\(choice) ai:\(ai) main:\(main) keys:\(keys.map(\.rawValue).sorted())"
                        guard ai else { XCTAssertEqual(got, .aiOff, context); continue }
                        if let fixed = choice.service {
                            XCTAssertEqual(got, keys.contains(fixed) ? .service(fixed, source: .chosen) : .missingKey(fixed), context)
                            continue
                        }
                        if main.canEditPhotos, keys.contains(main) {
                            XCTAssertEqual(got, .service(main, source: .mainService), context)
                        } else if keys.contains(.googleAIStudio) {
                            XCTAssertEqual(got, .service(.googleAIStudio, source: .savedKey), context)
                        } else if keys.contains(.openAI) {
                            XCTAssertEqual(got, .service(.openAI, source: .savedKey), context)
                        } else {
                            XCTAssertEqual(got, .noService, context)
                        }
                        // Whatever it picked can edit photos and has its key.
                        if let service = got.service {
                            XCTAssertTrue(service.canEditPhotos && keys.contains(service), context)
                        }
                    }
                }
            }
        }
    }

    func testUnavailableWordsAndTheKeyToAdd() {
        XCTAssertEqual(
            PhotoEditingResolution.noService.unavailableMessage,
            "Your AI service can’t edit photos. Add a Google AI Studio key to use Nano Banana for photo edits."
        )
        XCTAssertEqual(PhotoEditingResolution.noService.keyToAdd, .googleAIStudio)
        XCTAssertEqual(PhotoEditingResolution.missingKey(.openAI).keyToAdd, .openAI)
        XCTAssertNil(PhotoEditingResolution.service(.openAI, source: .chosen).unavailableMessage)
        XCTAssertNotNil(PhotoEditingResolution.noService.unavailableFootnote, "says Google needs billing")
        // Google's key page is the one AIProviderKind already has.
        XCTAssertEqual(AIProviderKind.googleAIStudio.keyPortalURL?.absoluteString, "https://aistudio.google.com/apikey")
    }

    // MARK: - The setting, and the main service staying put

    func testPhotoEditingChoiceDefaultsToAutomaticAndIsRemembered() {
        let (suite, cleanup) = defaults()
        defer { cleanup() }
        let prefs = AIPreferences(defaults: suite)
        XCTAssertEqual(prefs.photoEditingChoice, .automatic)
        prefs.photoEditingChoice = .googleAIStudio
        XCTAssertEqual(AIPreferences(defaults: suite).photoEditingChoice, .googleAIStudio)
    }

    func testPhotoEditingNeverChangesTheMainAIService() {
        let (suite, cleanup) = defaults()
        defer { cleanup() }
        let prefs = AIPreferences(defaults: suite)
        prefs.enableContextualAI = true
        prefs.selectedEngine = .anthropic
        prefs.selectedModel = "claude-example"
        let store = AIProviderStore(preferences: prefs, keyStore: keyStore([.anthropic]),
                                    transport: StubHTTPTransport(), isAppInstalled: { _ in false })
        XCTAssertEqual(store.photoEditingResolution, .noService)

        // Saving a Google key for photo edits, and choosing the service: the main service stays Anthropic.
        XCTAssertNoThrow(try store.saveKey("fixture-google-key", for: .googleAIStudio).get())
        prefs.photoEditingChoice = .googleAIStudio
        XCTAssertEqual(store.photoEditingResolution, .service(.googleAIStudio, source: .chosen))
        XCTAssertEqual(prefs.selectedEngine, .anthropic)
        XCTAssertEqual(prefs.selectedModel, "claude-example")
        XCTAssertTrue(prefs.enableContextualAI)
        prefs.photoEditingChoice = .automatic
        XCTAssertEqual(store.photoEditingResolution, .service(.googleAIStudio, source: .savedKey))
        XCTAssertEqual(prefs.selectedEngine, .anthropic)

        prefs.enableContextualAI = false
        XCTAssertEqual(store.photoEditingResolution, .aiOff)
        XCTAssertFalse(store.photoEditBackend().isOffered())
    }

    func testSettingsAnchorsAndSearch() {
        XCTAssertEqual(PhotoEditingChoice.settingID(forKeyOf: .googleAIStudio), "ai.photoEditing.googleAIStudio")
        XCTAssertEqual(PhotoEditingChoice.settingID(forKeyOf: .openAI), "ai.photoEditing.openAI")
        XCTAssertEqual(PhotoEditingChoice.settingID(forKeyOf: .anthropic), "ai.photoEditing")
        XCTAssertEqual(PhotoEditingChoice.settingID(forKeyOf: nil), "ai.photoEditing")
        XCTAssertEqual(PhotoEditingChoice.keyService(forSettingID: "ai.photoEditing.googleAIStudio"), .googleAIStudio)
        XCTAssertNil(PhotoEditingChoice.keyService(forSettingID: "ai.photoEditing"))
        XCTAssertNil(PhotoEditingChoice.keyService(forSettingID: "ai.contextual"))
        let ids = Set(SettingsNavigationModel.allSettings.map(\.id))
        XCTAssertTrue(ids.contains("ai.photoEditing"))
        XCTAssertTrue(SettingsNavigationModel.anchoredSettingIDs.contains("ai.photoEditing"))
    }

    // MARK: - Request building

    func testGeminiRequestIsBuiltFromTheFixture() async throws {
        let transport = StubHTTPTransport()
        let png = makeImage(width: 64, height: 48, type: .png)
        transport.enqueue(status: 200, json: geminiSuccessJSON(image: png))
        let editor = GeminiImageEditor(apiKey: " fixture-google-key \n", transport: transport)
        let original = makeImage(width: 4000, height: 2000, withMetadata: true)

        let result = await editor.edit(image: original, mimeType: "image/jpeg", instruction: "remove the person on the left")
        XCTAssertEqual(result, .success(EditedImage(data: png, mimeType: "image/png")))

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-nano-banana-2.1:generateContent"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-google-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertFalse(request.url?.absoluteString.contains("fixture-google-key") ?? true, "the key is never in the URL")

        let body = try bodyJSON(request)
        let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(config["responseModalities"] as? [String], ["TEXT", "IMAGE"])
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue((parts[0]["text"] as? String)?.hasSuffix("remove the person on the left") ?? false)
        let inline = try XCTUnwrap(parts[1]["inlineData"] as? [String: Any])
        XCTAssertEqual(inline["mimeType"] as? String, "image/jpeg")
        let sent = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(inline["data"] as? String)))
        // What went out is the shrunk, metadata-free copy, not the original.
        let sentSize = try XCTUnwrap(size(of: sent))
        XCTAssertEqual(max(sentSize.0, sentSize.1), 2048)
        XCTAssertLessThan(sent.count, original.count)
        assertNoLocationOrCamera(sent)
        XCTAssertFalse(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("fixture-google-key"))
    }

    func testOpenAIRequestIsBuiltFromTheFixture() async throws {
        let transport = StubHTTPTransport()
        let png = makeImage(width: 64, height: 48, type: .png)
        transport.enqueue(status: 200, json: openAISuccessJSON(image: png))
        let editor = OpenAIImageEditor(apiKey: "fixture-openai-key", transport: transport)
        let original = makeImage(width: 3000, height: 3000, withMetadata: true)

        let result = await editor.edit(image: original, mimeType: "image/jpeg", instruction: "brighten it")
        XCTAssertEqual(result, .success(EditedImage(data: png, mimeType: "image/png")))

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/images/edits")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-openai-key")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let parts = try multipartParts(request)
        XCTAssertEqual(parts.fields["model"], "gpt-image-2.6-sunburst")
        XCTAssertTrue(parts.fields["prompt"]?.hasSuffix("brighten it") ?? false)
        XCTAssertTrue(parts.fileHeaders.contains(#"name="image[]""#))
        XCTAssertTrue(parts.fileHeaders.contains("Content-Type: image/jpeg"))
        let sentSize = try XCTUnwrap(size(of: parts.file))
        XCTAssertEqual(max(sentSize.0, sentSize.1), 2048)
        assertNoLocationOrCamera(parts.file)
        XCTAssertFalse(String(decoding: StubHTTPTransport.bodyData(of: request) ?? Data(), as: UTF8.self).contains("fixture-openai-key"))
    }

    func testAPNGWithSeeThroughPartsIsSentAsPNG() async throws {
        let transport = StubHTTPTransport()
        transport.enqueue(status: 200, json: openAISuccessJSON(image: makeImage(width: 8, height: 8, type: .png)))
        let editor = OpenAIImageEditor(apiKey: "fixture-openai-key", transport: transport)
        _ = await editor.edit(image: makeImage(width: 200, height: 100, type: .png, alpha: true), mimeType: "image/png", instruction: "x")
        let parts = try multipartParts(try XCTUnwrap(transport.requests.first))
        XCTAssertTrue(parts.fileHeaders.contains("Content-Type: image/png"))
    }

    // MARK: - Reading answers and mapping failures

    private func geminiResult(status: Int = 200, json: String) async -> ImageEditResult {
        let transport = StubHTTPTransport()
        transport.enqueue(status: status, json: json)
        let editor = GeminiImageEditor(apiKey: "fixture-google-key", transport: transport)
        return await editor.edit(image: makeImage(width: 40, height: 30), mimeType: "image/jpeg", instruction: "brighten it")
    }

    private func openAIResult(status: Int = 200, json: String) async -> ImageEditResult {
        let transport = StubHTTPTransport()
        transport.enqueue(status: status, json: json)
        let editor = OpenAIImageEditor(apiKey: "fixture-openai-key", transport: transport)
        return await editor.edit(image: makeImage(width: 40, height: 30), mimeType: "image/jpeg", instruction: "brighten it")
    }

    func testGeminiFailuresAreMappedToPlainTypedFailures() async {
        // Safety: the prompt was blocked, or the picture was.
        let blockedPrompt = await geminiResult(json: #"{"promptFeedback":{"blockReason":"PROHIBITED_CONTENT"}}"#)
        XCTAssertEqual(blockedPrompt, .failure(.refused))
        let blockedImage = await geminiResult(json: #"{"candidates":[{"finishReason":"IMAGE_SAFETY"}]}"#)
        XCTAssertEqual(blockedImage, .failure(.refused))
        // It answered in words only.
        let wordsOnly = await geminiResult(json: #"{"candidates":[{"content":{"parts":[{"text":"I can only edit one photo at a time."}]},"finishReason":"STOP"}]}"#)
        XCTAssertEqual(wordsOnly, .failure(.noImageReturned(note: "I can only edit one photo at a time.")))
        let empty = await geminiResult(json: #"{"candidates":[]}"#)
        XCTAssertEqual(empty, .failure(.noImageReturned(note: nil)))
        let notJSON = await geminiResult(json: "nope")
        XCTAssertEqual(notJSON, .failure(.noImageReturned(note: nil)))
        // HTTP errors.
        let badKey = await geminiResult(status: 401, json: #"{"error":{"message":"bad"}}"#)
        XCTAssertEqual(badKey, .failure(.keyRejected))
        let invalidKey = await geminiResult(status: 400, json: #"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}"#)
        XCTAssertEqual(invalidKey, .failure(.keyRejected))
        let freeKey = await geminiResult(status: 429, json: #"{"error":{"code":429,"message":"Quota exceeded for metric: generate_content_free_tier_requests, limit: 0","status":"RESOURCE_EXHAUSTED"}}"#)
        XCTAssertEqual(freeKey, .failure(.needsPaidAccess))
        let busy = await geminiResult(status: 429, json: #"{"error":{"code":429,"message":"Too many requests","status":"RESOURCE_EXHAUSTED"}}"#)
        XCTAssertEqual(busy, .failure(.rateLimited))
        let big = await geminiResult(status: 413, json: "")
        XCTAssertEqual(big, .failure(.tooLarge))
        let down = await geminiResult(status: 503, json: #"{"error":{"message":"overloaded"}}"#)
        XCTAssertEqual(down, .failure(.server(status: 503, detail: "overloaded")))
    }

    func testOpenAIFailuresAreMappedToPlainTypedFailures() async {
        let moderated = await openAIResult(status: 400, json: #"{"error":{"code":"moderation_blocked","message":"Your request was rejected by the safety system."}}"#)
        XCTAssertEqual(moderated, .failure(.refused))
        let badKey = await openAIResult(status: 401, json: #"{"error":{"message":"Incorrect API key provided"}}"#)
        XCTAssertEqual(badKey, .failure(.keyRejected))
        let verify = await openAIResult(status: 403, json: #"{"error":{"message":"Your organization must be verified to use the model `gpt-image-2.6-sunburst`."}}"#)
        XCTAssertEqual(verify, .failure(.needsPaidAccess))
        let noCredit = await openAIResult(status: 429, json: #"{"error":{"code":"insufficient_quota","message":"You exceeded your current quota"}}"#)
        XCTAssertEqual(noCredit, .failure(.needsPaidAccess))
        let busy = await openAIResult(status: 429, json: #"{"error":{"code":"rate_limit_exceeded","message":"Slow down"}}"#)
        XCTAssertEqual(busy, .failure(.rateLimited))
        let big = await openAIResult(status: 413, json: "")
        XCTAssertEqual(big, .failure(.tooLarge))
        let noImage = await openAIResult(json: #"{"data":[]}"#)
        XCTAssertEqual(noImage, .failure(.noImageReturned(note: nil)))
        let broken = await openAIResult(status: 500, json: "")
        XCTAssertEqual(broken, .failure(.server(status: 500, detail: "")))
    }

    func testNetworkAndCancellationFailures() async {
        for kind in AIProviderKind.photoEditingServices {
            let offline = StubHTTPTransport()
            offline.enqueue(error: URLError(.notConnectedToInternet))
            let editor = ImageEditors.make(for: kind, keyStore: keyStore([kind]), transport: offline)
            let result = await editor.edit(image: makeImage(width: 40, height: 30), mimeType: "image/jpeg", instruction: "x")
            XCTAssertEqual(result, .failure(.network), "\(kind)")

            let stopped = StubHTTPTransport()
            stopped.enqueue(error: URLError(.cancelled))
            let stoppable = ImageEditors.make(for: kind, keyStore: keyStore([kind]), transport: stopped)
            let cancelled = await stoppable.edit(image: makeImage(width: 40, height: 30), mimeType: "image/jpeg", instruction: "x")
            XCTAssertEqual(cancelled, .failure(.cancelled), "\(kind)")
        }
    }

    func testTooLargeAndUnreadablePhotosNeverReachTheNetwork() async {
        let transport = StubHTTPTransport()
        let gemini = GeminiImageEditor(apiKey: "fixture-google-key", transport: transport, maxUploadBytes: 200)
        let openAI = OpenAIImageEditor(apiKey: "fixture-openai-key", transport: transport, maxUploadBytes: 200)
        let big = makeImage(width: 600, height: 600)
        for editor in [gemini as any AIImageEditor, openAI] {
            let large = await editor.edit(image: big, mimeType: "image/jpeg", instruction: "x")
            XCTAssertEqual(large, .failure(.tooLarge))
            let unreadable = await editor.edit(image: Data("not a picture".utf8), mimeType: "image/jpeg", instruction: "x")
            XCTAssertEqual(unreadable, .failure(.unreadablePhoto))
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testEveryFailureReadsInPlainWords() {
        let failures: [ImageEditFailure] = [
            .unsupported, .noKey, .keyRejected, .refused, .network, .tooLarge, .rateLimited, .needsPaidAccess,
            .unreadablePhoto, .noImageReturned(note: nil), .noImageReturned(note: "No."), .server(status: 500, detail: ""),
            .server(status: 400, detail: "Bad"), .cancelled,
        ]
        for failure in failures {
            for service in AIProviderKind.photoEditingServices {
                let text = failure.message(service: service)
                XCTAssertFalse(text.isEmpty)
                for jargon in ["HTTP", "JSON", "401", "429", "generateContent", "b64"] {
                    XCTAssertFalse(text.contains(jargon), "\(failure): \(text)")
                }
            }
        }
        XCTAssertTrue(ImageEditFailure.needsPaidAccess.message(service: .googleAIStudio).contains("billing"))
        XCTAssertTrue(ImageEditFailure.needsPaidAccess.message(service: .openAI).contains("verified"))
        XCTAssertTrue(ImageEditFailure.noKey.needsSettings)
        XCTAssertFalse(ImageEditFailure.network.needsSettings)
    }

    // MARK: - Shrinking and stripping

    func testBigPhotoIsShrunkToTheLongEdgeAndItsLocationIsDropped() throws {
        let original = makeImage(width: 4000, height: 3000, withMetadata: true)
        XCTAssertNotNil(properties(of: original)?[kCGImagePropertyGPSDictionary], "the fixture has a location")
        let prepared = try PhotoEditPreparer.prepare(original)
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertEqual(prepared.pixelWidth, 2048)
        XCTAssertEqual(prepared.pixelHeight, 1536)
        XCTAssertEqual(size(of: prepared.data).map { [$0.0, $0.1] }, [2048, 1536])
        assertNoLocationOrCamera(prepared.data)
    }

    func testSmallPhotoKeepsItsSizeButStillLosesItsLocation() throws {
        let original = makeImage(width: 400, height: 300, withMetadata: true)
        let prepared = try PhotoEditPreparer.prepare(original)
        XCTAssertEqual([prepared.pixelWidth, prepared.pixelHeight], [400, 300], "never made bigger")
        assertNoLocationOrCamera(prepared.data)
    }

    func testPhotoTurnedByItsOrientationTagComesOutUpright() throws {
        // Orientation 6: stored sideways (400 x 300), shown 300 x 400.
        let sideways = makeImage(width: 400, height: 300, withMetadata: true, orientation: 6)
        let prepared = try PhotoEditPreparer.prepare(sideways)
        XCTAssertEqual([prepared.pixelWidth, prepared.pixelHeight], [300, 400])
        let orientation = (properties(of: prepared.data)?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        XCTAssertEqual(orientation, 1)
    }

    func testPhotoWithSeeThroughPartsStaysPNG() throws {
        let prepared = try PhotoEditPreparer.prepare(makeImage(width: 300, height: 200, type: .png, alpha: true))
        XCTAssertEqual(prepared.mimeType, "image/png")
        XCTAssertEqual(prepared.data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testPrepareRefusesWhatIsNotAPictureAndWhatIsTooBig() {
        XCTAssertThrowsError(try PhotoEditPreparer.prepare(Data("hello".utf8))) {
            XCTAssertEqual($0 as? PhotoEditPreparer.Failure, .unreadable)
        }
        XCTAssertThrowsError(try PhotoEditPreparer.prepare(makeImage(width: 500, height: 500), maxBytes: 100)) {
            XCTAssertEqual($0 as? PhotoEditPreparer.Failure, .tooLarge)
        }
    }

    // MARK: - Asking once per service

    func testConsentIsRememberedPerService() {
        let (suite, cleanup) = defaults()
        defer { cleanup() }
        let store = PhotoEditConsentStore(defaults: suite)
        XCTAssertFalse(store.hasConsented(to: .googleAIStudio))
        XCTAssertFalse(store.hasConsented(to: .openAI))
        store.recordConsent(to: .googleAIStudio)
        XCTAssertTrue(store.hasConsented(to: .googleAIStudio))
        XCTAssertFalse(store.hasConsented(to: .openAI), "a yes to Google is not a yes to OpenAI")
        XCTAssertTrue(PhotoEditConsentStore(defaults: suite).hasConsented(to: .googleAIStudio), "remembered next launch")
        XCTAssertEqual(
            PhotoEditConsentStore.question(for: .googleAIStudio),
            "This sends the photo to Google AI Studio. It may be someone else’s photo."
        )
    }

    // MARK: - The sheet's model

    private final class FakeEditor: AIImageEditor, @unchecked Sendable {
        let provider: AIProviderKind
        private let lock = NSLock()
        private var _result: ImageEditResult
        private var _instructions: [String] = []
        private var _sent: [Data] = []

        init(_ provider: AIProviderKind, result: ImageEditResult) {
            self.provider = provider
            _result = result
        }

        var result: ImageEditResult {
            get { lock.withLock { _result } }
            set { lock.withLock { _result = newValue } }
        }
        var instructions: [String] { lock.withLock { _instructions } }
        var sent: [Data] { lock.withLock { _sent } }

        func edit(image: Data, mimeType _: String, instruction: String) async -> ImageEditResult {
            lock.withLock {
                _instructions.append(instruction)
                _sent.append(image)
            }
            return result
        }
    }

    private struct Rig {
        let model: PhotoEditModel
        let editor: FakeEditor
        let consent: PhotoEditConsentStore
        let resolution: Box<PhotoEditingResolution>
        let drafted: Box<[(URL, String)]>
        let settingsAsked: Box<[AIProviderKind?]>
        let cleanup: () -> Void
    }

    @MainActor final class Box<T> { var value: T; init(_ value: T) { self.value = value } }

    private func makeRig(
        resolution: PhotoEditingResolution = .service(.googleAIStudio, source: .savedKey),
        result: ImageEditResult? = nil,
        consented: [AIProviderKind] = []
    ) throws -> Rig {
        let (suite, cleanup) = defaults()
        let consent = PhotoEditConsentStore(defaults: suite)
        for service in consented { consent.recordConsent(to: service) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("photo-edit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scratch.append(dir)
        let photo = dir.appendingPathComponent("beach.jpg")
        try makeImage(width: 64, height: 48).write(to: photo)
        let edited = EditedImage(data: makeImage(width: 32, height: 24, type: .png), mimeType: "image/png")
        let editor = FakeEditor(resolution.service ?? .googleAIStudio, result: result ?? .success(edited))
        let box = Box(resolution)
        let drafted = Box<[(URL, String)]>([])
        let asked = Box<[AIProviderKind?]>([])
        let backend = PhotoEditBackend(
            isOffered: { true }, resolve: { box.value },
            makeEditor: { kind in
                // The editor for whichever service is asked for, answering as that service.
                kind == editor.provider ? editor : FakeEditor(kind, result: editor.result)
            },
            consent: consent
        )
        let model = PhotoEditModel(
            source: PhotoEditSource(path: photo.path, fileName: "beach.jpg", mimeType: "image/jpeg", roomID: "!room"),
            backend: backend,
            draftIntoMessage: { url, room in drafted.value.append((url, room)); return true },
            openAISettings: { asked.value.append($0) },
            scratchDirectory: dir.appendingPathComponent("drafts")
        )
        return Rig(model: model, editor: editor, consent: consent, resolution: box, drafted: drafted,
                   settingsAsked: asked, cleanup: cleanup)
    }

    private func waitForEdit(_ model: PhotoEditModel) async throws {
        try await waitUntil {
            await MainActor.run {
                if case .working = model.phase { return false }
                return true
            }
        }
    }

    func testFirstPhotoToAServiceAsksAndSendsNothingUntilContinue() async throws {
        let rig = try makeRig()
        defer { rig.cleanup() }
        rig.model.instruction = "brighten it"
        rig.model.submit()
        XCTAssertEqual(rig.model.phase, .confirming(.googleAIStudio))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(rig.editor.instructions.isEmpty, "nothing leaves before Continue")

        // Cancel: back to ready, nothing remembered, nothing sent.
        rig.model.declineConsent()
        XCTAssertEqual(rig.model.phase, .ready)
        XCTAssertFalse(rig.consent.hasConsented(to: .googleAIStudio))
        XCTAssertTrue(rig.editor.instructions.isEmpty)

        // Continue: remembered, and the edit runs.
        rig.model.submit()
        rig.model.confirmConsent()
        try await waitForEdit(rig.model)
        XCTAssertTrue(rig.consent.hasConsented(to: .googleAIStudio))
        XCTAssertEqual(rig.editor.instructions.count, 1)
        XCTAssertNotNil(rig.model.outcome)

        // Try Again does not ask again.
        rig.model.submit()
        XCTAssertNotEqual(rig.model.phase, .confirming(.googleAIStudio))
        try await waitForEdit(rig.model)
        XCTAssertEqual(rig.editor.instructions.count, 2)
    }

    func testAnotherServiceAsksAgain() async throws {
        let rig = try makeRig(consented: [.googleAIStudio])
        defer { rig.cleanup() }
        rig.model.instruction = "brighten it"
        rig.model.submit()
        try await waitForEdit(rig.model)
        XCTAssertNotNil(rig.model.outcome)
        // The person switches to OpenAI in Settings: the first photo to OpenAI asks.
        rig.resolution.value = .service(.openAI, source: .chosen)
        rig.model.submit()
        XCTAssertEqual(rig.model.phase, .confirming(.openAI))
    }

    func testTheResultKeepsTheInstructionSentAndNamesTheService() async throws {
        let rig = try makeRig(consented: [.googleAIStudio])
        defer { rig.cleanup() }
        rig.model.instruction = "  remove the person on the left \n"
        rig.model.submit()
        try await waitForEdit(rig.model)
        XCTAssertEqual(rig.editor.instructions, ["  remove the person on the left \n"])
        XCTAssertEqual(rig.model.outcome?.caption, "Edited with Google AI Studio")
        XCTAssertEqual(rig.model.suggestedFileName, "beach edited.png")
        // The photo read from disk is what the editor got.
        XCTAssertEqual(rig.editor.sent.first, try Data(contentsOf: URL(fileURLWithPath: rig.model.source.path)))
    }

    func testEmptyInstructionDoesNotRun() throws {
        let rig = try makeRig(consented: [.googleAIStudio])
        defer { rig.cleanup() }
        rig.model.instruction = "   \n"
        XCTAssertFalse(rig.model.canSubmit)
        rig.model.submit()
        XCTAssertEqual(rig.model.phase, .ready)
        XCTAssertTrue(rig.editor.instructions.isEmpty)
    }

    func testFailureShowsPlainWordsAndTryAgainWorks() async throws {
        let rig = try makeRig(result: .failure(.refused), consented: [.googleAIStudio])
        defer { rig.cleanup() }
        rig.model.instruction = "make it dramatic"
        rig.model.submit()
        try await waitForEdit(rig.model)
        guard case let .failed(failure, service) = rig.model.phase else { return XCTFail("expected a failure, got \(rig.model.phase)") }
        XCTAssertEqual(failure, .refused)
        XCTAssertEqual(service, .googleAIStudio)
        XCTAssertTrue(rig.model.canSubmit, "Try Again is there")
        rig.editor.result = .success(EditedImage(data: makeImage(width: 8, height: 8, type: .png), mimeType: "image/png"))
        rig.model.instruction = "make it a bit dramatic"
        rig.model.submit()
        try await waitForEdit(rig.model)
        XCTAssertNotNil(rig.model.outcome)
        XCTAssertEqual(rig.editor.instructions.last, "make it a bit dramatic", "Try Again takes the tweaked instruction")
    }

    func testUnreadablePhotoFileIsAFailureNotACrash() async throws {
        let rig = try makeRig(consented: [.googleAIStudio])
        defer { rig.cleanup() }
        try FileManager.default.removeItem(atPath: rig.model.source.path)
        rig.model.instruction = "brighten it"
        rig.model.submit()
        try await waitForEdit(rig.model)
        XCTAssertEqual(rig.model.phase, .failed(.unreadablePhoto, .googleAIStudio))
        XCTAssertTrue(rig.editor.instructions.isEmpty)
    }

    func testNoCapableServiceSaysSoAndASavedKeyTurnsItIntoReady() throws {
        let rig = try makeRig(resolution: .noService)
        defer { rig.cleanup() }
        XCTAssertEqual(rig.model.phase, .unavailable(.noService))
        rig.model.instruction = "brighten it"
        XCTAssertFalse(rig.model.canSubmit)
        rig.model.submit()
        XCTAssertEqual(rig.model.phase, .unavailable(.noService))
        XCTAssertTrue(rig.editor.instructions.isEmpty)

        // "Open AI Settings" asks for Google AI Studio's key field.
        rig.model.openSettings()
        XCTAssertEqual(rig.settingsAsked.value, [.googleAIStudio])

        // Back from Settings with a key saved.
        rig.resolution.value = .service(.googleAIStudio, source: .savedKey)
        rig.model.recheck()
        XCTAssertEqual(rig.model.phase, .ready)
        XCTAssertTrue(rig.model.canSubmit)
    }

    func testStopCancelsAnEditInProgress() async throws {
        let rig = try makeRig(consented: [.googleAIStudio])
        defer { rig.cleanup() }
        rig.model.instruction = "brighten it"
        rig.model.submit()
        XCTAssertEqual(rig.model.phase, .working(.googleAIStudio))
        rig.model.cancel()
        XCTAssertEqual(rig.model.phase, .ready)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(rig.model.phase, .ready, "a late answer after Stop is dropped")
        XCTAssertNil(rig.model.outcome)
    }

    func testAddToMessageOnlyDraftsTheEditedPhoto() async throws {
        let rig = try makeRig(consented: [.googleAIStudio])
        defer { rig.cleanup() }
        XCTAssertFalse(rig.model.addToMessage(), "nothing to add before there is a result")
        rig.model.instruction = "brighten it"
        rig.model.submit()
        try await waitForEdit(rig.model)
        let expected = try XCTUnwrap(rig.model.outcome?.image.data)

        XCTAssertTrue(rig.model.addToMessage())
        XCTAssertEqual(rig.drafted.value.count, 1)
        let (file, room) = try XCTUnwrap(rig.drafted.value.first)
        XCTAssertEqual(room, "!room", "into the chat the photo is in")
        XCTAssertEqual(file.lastPathComponent, "beach edited.png")
        XCTAssertEqual(try Data(contentsOf: file), expected)
        XCTAssertEqual(rig.model.notice, "Added to your message. Nothing is sent until you press Send.")
    }

    func testSaveToMacWritesTheResult() async throws {
        let rig = try makeRig(consented: [.googleAIStudio])
        defer { rig.cleanup() }
        rig.model.instruction = "brighten it"
        rig.model.submit()
        try await waitForEdit(rig.model)
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("saved-\(UUID().uuidString).png")
        scratch.append(target)
        XCTAssertTrue(rig.model.saveToMac(at: target))
        XCTAssertEqual(try Data(contentsOf: target), rig.model.outcome?.image.data)
    }

    // MARK: - Never sends: through the real composer

    private func sends(_ h: ConversationHarness) -> [String] {
        h.server.receivedMethods().filter { $0.hasPrefix("message.send") || $0 == "message.schedule" }
    }

    func testAddToMessagePutsADraftInTheChatsComposerAndSendsNothing() async throws {
        let h = try await startConversation(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1)]],
            features: ["!a": featuresJSON()], rows: ["!a": chatRow("!a", name: "Example Person", network: "signal")])
        defer { Task { await h.stop() } }
        try await h.open("!a")

        let (suite, cleanup) = defaults()
        defer { cleanup() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("photo-edit-composer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scratch.append(dir)
        let photo = dir.appendingPathComponent("holiday.jpg")
        try makeImage(width: 64, height: 48).write(to: photo)
        let editor = FakeEditor(.googleAIStudio, result: .success(EditedImage(data: makeImage(width: 16, height: 16, type: .png), mimeType: "image/png")))
        let consent = PhotoEditConsentStore(defaults: suite)
        consent.recordConsent(to: .googleAIStudio)
        h.conversation.photoEditBackend = PhotoEditBackend(
            isOffered: { true }, resolve: { .service(.googleAIStudio, source: .savedKey) },
            makeEditor: { _ in editor }, consent: consent)

        XCTAssertTrue(h.conversation.editPhotoWithAI(
            PhotoEditSource(path: photo.path, fileName: "holiday.jpg", mimeType: "image/jpeg", roomID: "!a")))
        let model = try XCTUnwrap(h.conversation.photoEdit)
        model.instruction = "brighten it"
        model.submit()
        try await waitForEdit(model)
        XCTAssertNotNil(model.outcome)
        XCTAssertTrue(h.conversation.composer.attachments.isEmpty, "a result alone is not a draft")

        XCTAssertTrue(model.addToMessage())
        let attachments = h.conversation.composer.attachments
        XCTAssertEqual(attachments.map(\.fileName), ["holiday edited.png"])
        // Time passes, and still nothing goes: posting is the person's own Send.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(sends(h), [])
        XCTAssertEqual(h.conversation.composer.attachments.count, 1)
        XCTAssertTrue(h.conversation.composer.text.isEmpty, "no words added to the draft either")
    }

    func testEditWithAIIsHiddenWhenAIIsOffOrNotBound() async throws {
        let h = try await startConversation(["!a": [textEvent(id: "$1", room: "!a", at: 1)]],
                                            features: ["!a": featuresJSON()],
                                            rows: ["!a": chatRow("!a", name: "Example Person", network: "signal")])
        defer { Task { await h.stop() } }
        let source = PhotoEditSource(path: "/tmp/x.jpg", fileName: "x.jpg", mimeType: "image/jpeg", roomID: "!a")
        // No AI store bound (a detached window): not offered, and the call does nothing.
        XCTAssertFalse(h.conversation.isPhotoEditingOffered)
        XCTAssertFalse(h.conversation.editPhotoWithAI(source))
        XCTAssertNil(h.conversation.photoEdit)

        let on = Box(false)
        h.conversation.photoEditBackend = PhotoEditBackend(
            isOffered: { on.value }, resolve: { .noService },
            makeEditor: { UnavailableImageEditor(provider: $0, failure: .unsupported) },
            consent: PhotoEditConsentStore(defaults: defaults().0))
        XCTAssertFalse(h.conversation.isPhotoEditingOffered, "AI is off")
        XCTAssertFalse(h.conversation.editPhotoWithAI(source))
        on.value = true
        XCTAssertTrue(h.conversation.isPhotoEditingOffered)
        XCTAssertTrue(h.conversation.editPhotoWithAI(source))
        XCTAssertEqual(h.conversation.photoEdit?.phase, .unavailable(.noService))
        h.conversation.closePhotoEdit()
        XCTAssertNil(h.conversation.photoEdit)
    }

    // MARK: - Where "Edit with AI…" shows

    private func timelineMessage(
        kind: MessageKind = .image, mediaPath: String = "/store/photo.jpg", mimeType: String = "image/jpeg",
        isGIF: Bool = false, viewOnce: Bool = false, mediaRemoved: Bool = false
    ) -> TimelineMessage {
        TimelineMessage(
            id: "$p", roomID: "!room:courier.local", sender: "@alice:courier.local", senderName: "Alice",
            senderAvatarPath: "", mine: false, ts: 1_760_600_000_000, kind: kind, body: "photo.jpg",
            rich: RichText(text: "photo.jpg"), isEdited: false, editCount: 0, editFailed: nil, failedEditID: nil,
            fileName: "photo.jpg", mimeType: mimeType, byteSize: nil, width: nil, height: nil, mediaPath: mediaPath,
            isGIF: isGIF, viewOnce: viewOnce, statusLine: .sent, countsAsUnread: true, poll: nil, thread: nil,
            bookmarked: false, expiresAt: nil, timerChange: nil, call: nil, reply: nil, reactions: [],
            startsGroup: true, mediaRemoved: mediaRemoved)
    }

    func testOnlyStillPhotosOnThisMacCanBeEdited() {
        XCTAssertNotNil(PhotoEditSource(message: timelineMessage()))
        XCTAssertEqual(PhotoEditSource(message: timelineMessage())?.roomID, "!room:courier.local")
        XCTAssertNotNil(PhotoEditSource(message: timelineMessage(mimeType: "")))
        XCTAssertNotNil(PhotoEditSource(message: timelineMessage(mimeType: "image/heic")))
        XCTAssertNil(PhotoEditSource(message: timelineMessage(kind: .video)))
        XCTAssertNil(PhotoEditSource(message: timelineMessage(kind: .sticker)))
        XCTAssertNil(PhotoEditSource(message: timelineMessage(kind: .file)))
        XCTAssertNil(PhotoEditSource(message: timelineMessage(kind: .text)))
        XCTAssertNil(PhotoEditSource(message: timelineMessage(isGIF: true)))
        XCTAssertNil(PhotoEditSource(message: timelineMessage(mimeType: "image/gif")))
        XCTAssertNil(PhotoEditSource(message: timelineMessage(viewOnce: true)), "a view-once photo is never copied")
        XCTAssertNil(PhotoEditSource(message: timelineMessage(mediaPath: "")), "not downloaded yet")
        XCTAssertNil(PhotoEditSource(message: timelineMessage(mediaPath: "mxc://example.test/abc")))
        XCTAssertNil(PhotoEditSource(message: timelineMessage(mediaPath: "", mediaRemoved: true)))
        XCTAssertNil(PhotoEditSource(message: timelineMessage(mimeType: "application/pdf")))

        let item = CarouselItem(eventID: "$c", roomID: "!room", kind: .image, mediaPath: "/store/c.jpg", fileName: "c.jpg",
                                mimeType: "image/jpeg")
        XCTAssertEqual(PhotoEditSource(item: item)?.path, "/store/c.jpg")
        XCTAssertNil(PhotoEditSource(item: CarouselItem(eventID: "$v", roomID: "!room", kind: .video, mediaPath: "/store/v.mp4")))
        XCTAssertNil(PhotoEditSource(item: CarouselItem(eventID: "$g", roomID: "!room", mediaPath: "/store/g.gif", isGIF: true)))
        XCTAssertNil(PhotoEditSource(item: CarouselItem(eventID: "$o", roomID: "!room", mediaPath: "/store/o.jpg", viewOnce: true)))
    }

    func testMessageMenuOffersEditWithAIUnderMoreOnlyWhenAsked() {
        let message = timelineMessage()
        func more(_ canEdit: Bool) -> [MessageMenuItem] {
            MessageMenu.sections(
                for: message, available: (actions: [.reply, .copy], unavailable: []),
                features: ChatFeatures(source: .stored), disappearsIn: nil, time: { _ in "12:00" },
                canEditPhoto: canEdit
            ).flatMap { $0 }.first { $0.command == .more }?.children ?? []
        }
        let offered = more(true).first { $0.command == .editPhoto }
        XCTAssertEqual(offered?.title, "Edit with AI…")
        XCTAssertEqual(offered?.isEnabled, true)
        XCTAssertNil(more(false).first { $0.command == .editPhoto }, "hidden when AI is off or it isn't a photo")
        // Not at all by default.
        let byDefault = MessageMenu.sections(
            for: message, available: (actions: [.reply], unavailable: []), features: ChatFeatures(source: .stored),
            disappearsIn: nil, time: { _ in "12:00" }
        ).flatMap { $0 }.flatMap { [$0] + $0.children }
        XCTAssertFalse(byDefault.contains { $0.command == .editPhoto })
    }
}
