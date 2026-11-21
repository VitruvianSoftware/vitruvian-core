// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The OpenAI image model that edits photos.
public enum OpenAIImageModel {
    /// GPT-Image-2.6 Sunburst, the newest GPT Image model in OpenAI's docs (checked 2026-11-21 at
    /// developers.openai.com/api/docs/guides/image-generation and /docs/models/gpt-image-2.6-sunburst), which says to
    /// use Sunburst "for detailed compositions and image editing workflows". `gpt-image-2.6-flare` is the fast one.
    public static let `default` = "gpt-image-2.6-sunburst"
}

/// Edits a photo with OpenAI's image model through `POST /v1/images/edits`: a `multipart/form-data` request with the
/// model, the instruction and the photo, answered with the edited picture as base64 (`data[0].b64_json`). The key
/// goes in the `Authorization` header only. OpenAI may ask an organization to verify itself before it allows GPT Image
/// models; that answer maps to `.needsPaidAccess`.
public struct OpenAIImageEditor: AIImageEditor, CustomStringConvertible, CustomDebugStringConvertible {
    public static let timeout: TimeInterval = 180

    public let provider: AIProviderKind = .openAI
    public let baseURL: URL
    public let model: String
    private let apiKey: String
    private let transport: any HTTPTransport
    private let maxUploadBytes: Int

    public init(
        apiKey: String,
        model: String = OpenAIImageModel.default,
        baseURL: URL = AIProviderKind.openAI.defaultBaseURL!,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared,
        maxUploadBytes: Int = PhotoEditPreparer.maxUploadBytes
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        self.transport = transport
        self.maxUploadBytes = maxUploadBytes
    }

    public var description: String { "OpenAIImageEditor(model: \(model), key: <redacted>)" }
    public var debugDescription: String { description }

    public func edit(image: Data, mimeType _: String, instruction: String) async -> ImageEditResult {
        guard !apiKey.isEmpty, !model.isEmpty else { return .failure(.noKey) }
        let prepared: PreparedPhoto
        do {
            prepared = try PhotoEditPreparer.prepare(image, maxBytes: maxUploadBytes)
        } catch PhotoEditPreparer.Failure.tooLarge {
            return .failure(.tooLarge)
        } catch {
            return .failure(.unreadablePhoto)
        }

        let request = makeRequest(photo: prepared, instruction: instruction)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch let urlError as URLError where urlError.code == .cancelled {
            return .failure(.cancelled)
        } catch {
            return .failure(.network)
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            return .failure(Self.failure(status: response.statusCode, body: data, key: apiKey))
        }
        return Self.parse(data)
    }

    /// The request that would be sent: exposed so tests can read it without a network.
    func makeRequest(photo: PreparedPhoto, instruction: String) -> URLRequest {
        let url = AIClientHTTP.endpoint(baseURL: baseURL, path: "/v1/images/edits")
        let boundary = "CourierPhotoEdit-\(UUID().uuidString)"
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var form = MultipartForm(boundary: boundary)
        form.addField(name: "model", value: model)
        form.addField(name: "prompt", value: PhotoEditPrompt.wrap(instruction))
        let ext = photo.mimeType == "image/png" ? "png" : "jpg"
        form.addFile(name: "image[]", filename: "photo.\(ext)", mimeType: photo.mimeType, data: photo.data)
        request.httpBody = form.finished()
        return request
    }

    static func parse(_ data: Data) -> ImageEditResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]]
        else { return .failure(.noImageReturned(note: nil)) }
        for item in items {
            guard let encoded = item["b64_json"] as? String,
                  let bytes = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), !bytes.isEmpty
            else { continue }
            let format = (json["output_format"] as? String)?.lowercased() ?? "png"
            let mime: String
            switch format {
            case "jpeg", "jpg": mime = "image/jpeg"
            case "webp": mime = "image/webp"
            default: mime = "image/png"
            }
            return .success(EditedImage(data: bytes, mimeType: mime))
        }
        return .failure(.noImageReturned(note: nil))
    }

    static func failure(status: Int, body: Data, key: String) -> ImageEditFailure {
        let detail = ImageEditText.errorDetail(from: body, key: key)
        let lowered = detail.lowercased()
        var code = ""
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let error = json["error"] as? [String: Any]
        {
            code = ((error["code"] as? String) ?? "").lowercased()
        }
        switch status {
        case 413:
            return .tooLarge
        case 401:
            return .keyRejected
        case 403:
            return lowered.contains("verif") ? .needsPaidAccess : .keyRejected
        case 429:
            return code == "insufficient_quota" || lowered.contains("billing") || lowered.contains("quota")
                ? .needsPaidAccess : .rateLimited
        case 400:
            if code == "moderation_blocked" || lowered.contains("safety system") || lowered.contains("moderation") {
                return .refused
            }
            if lowered.contains("verif") { return .needsPaidAccess }
            if code.contains("too_large") || lowered.contains("too large") || lowered.contains("exceeds") {
                return .tooLarge
            }
            if code.contains("invalid_image") || lowered.contains("invalid image") || lowered.contains("unsupported image") {
                return .unreadablePhoto
            }
            return .server(status: status, detail: detail)
        default:
            return .server(status: status, detail: detail)
        }
    }
}

/// A `multipart/form-data` body: text fields and one file.
struct MultipartForm {
    let boundary: String
    private(set) var body = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func addField(name: String, value: String) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data("\(value)\r\n".utf8))
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finished() -> Data {
        var out = body
        out.append(Data("--\(boundary)--\r\n".utf8))
        return out
    }
}
