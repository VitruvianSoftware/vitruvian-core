// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A picture an AI service sent back from a photo edit.
public struct EditedImage: Equatable, Sendable {
    public let data: Data
    /// "image/png", "image/jpeg" or "image/webp".
    public let mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }

    /// The file extension for `mimeType`, for the name a saved or drafted file gets.
    public var fileExtension: String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg": "jpg"
        case "image/webp": "webp"
        default: "png"
        }
    }
}

/// Why an AI photo edit did not come back with a picture. `message(service:)` says each in plain words.
public enum ImageEditFailure: Equatable, Sendable {
    /// The service can't edit photos at all (Anthropic, Ollama, LM Studio, Unsloth, a custom server, Apple's on-device model).
    case unsupported
    /// No key is saved for the service.
    case noKey
    /// The service refused the saved key.
    case keyRejected
    /// The service's safety rules stopped the photo or the change.
    case refused
    /// The service couldn't be reached.
    case network
    /// The photo is too big to send, even after it was shrunk.
    case tooLarge
    /// Too many requests, or the key's limit is used up.
    case rateLimited
    /// The key works, but the service only edits photos on a paid key (Google) or a verified organization (OpenAI).
    case needsPaidAccess
    /// The photo's file could not be read, or is not a picture.
    case unreadablePhoto
    /// The service answered but sent no picture. `note` is what it said instead, when it said anything.
    case noImageReturned(note: String?)
    /// Any other error the service reported.
    case server(status: Int, detail: String)
    /// The person stopped the edit.
    case cancelled

    /// What to tell the person, in plain words, naming the service where that helps.
    public func message(service: AIProviderKind) -> String {
        let name = service.label
        switch self {
        case .unsupported:
            return String(localized: "\(name) can’t edit photos.")
        case .noKey:
            return String(localized: "Add a \(name) key in Settings ▸ AI to edit photos.")
        case .keyRejected:
            return String(localized: "\(name) didn’t accept your key. Check it in Settings ▸ AI.")
        case .refused:
            return String(localized: "\(name) wouldn’t edit this photo. Its safety rules blocked the photo or the change. Try asking for something different.")
        case .network:
            return String(localized: "Couldn’t reach \(name). Check your connection and try again.")
        case .tooLarge:
            return String(localized: "This photo is too big to send. Try a smaller one.")
        case .rateLimited:
            return String(localized: "\(name) is busy, or you’ve used up your limit. Wait a moment and try again.")
        case .needsPaidAccess:
            switch service {
            case .openAI:
                return String(localized: "OpenAI hasn’t turned on photo editing for this key. Your organization may need to be verified in OpenAI’s settings.")
            default:
                return String(localized: "\(name) only edits photos with a key that has billing turned on. Free keys can’t.")
            }
        case .unreadablePhoto:
            return String(localized: "Couldn’t read this photo.")
        case let .noImageReturned(note):
            if let note, !note.isEmpty {
                return String(localized: "\(name) didn’t send a picture back. It said: \(note)")
            }
            return String(localized: "\(name) didn’t send a picture back. Try again, or describe the change differently.")
        case let .server(status, detail):
            if detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return String(localized: "\(name) had a problem (error \(status)). Try again.")
            }
            return String(localized: "\(name) had a problem: \(detail)")
        case .cancelled:
            return String(localized: "Stopped.")
        }
    }

    /// Whether changing something in Settings (a key, a service) is what fixes it, rather than trying again.
    public var needsSettings: Bool {
        switch self {
        case .noKey, .keyRejected, .needsPaidAccess, .unsupported: true
        default: false
        }
    }
}

public enum ImageEditResult: Equatable, Sendable {
    case success(EditedImage)
    case failure(ImageEditFailure)
}

/// Edits a photo from a written instruction ("brighten it", "remove the person on the left") and returns the new picture.
/// Implementations shrink the photo and strip its location before it leaves this Mac (`PhotoEditPreparer`).
/// An editor never sends anything to a chat: it only talks to its AI service.
public protocol AIImageEditor: Sendable {
    /// The service that does the edit, for "Edited with …".
    var provider: AIProviderKind { get }
    func edit(image: Data, mimeType: String, instruction: String) async -> ImageEditResult
}

/// An editor for a service that can't do it right now: it answers with `failure` and never touches the network.
public struct UnavailableImageEditor: AIImageEditor {
    public let provider: AIProviderKind
    public let failure: ImageEditFailure

    public init(provider: AIProviderKind, failure: ImageEditFailure) {
        self.provider = provider
        self.failure = failure
    }

    public func edit(image _: Data, mimeType _: String, instruction _: String) async -> ImageEditResult {
        .failure(failure)
    }
}

extension AIProviderKind {
    /// Whether the service can edit a photo from an instruction. Google AI Studio (the "Nano Banana" image model) and
    /// OpenAI (its GPT Image model) can. Anthropic, Ollama, LM Studio, Unsloth Studio and custom servers have no image
    /// editing. Apple's on-device Image Playground makes new stylised pictures from a prompt or a person's picture,
    /// not edits of a photo, so Apple Intelligence is left out.
    public var canEditPhotos: Bool {
        switch self {
        case .googleAIStudio, .openAI: true
        case .appleIntelligence, .ollama, .lmStudio, .unslothStudio, .anthropic, .customOpenAICompatible: false
        }
    }

    /// The services that can edit photos, in the order Automatic falls back to them.
    public static let photoEditingServices: [AIProviderKind] = [.googleAIStudio, .openAI]
}

public enum ImageEditors {
    /// The editor for `kind` with its saved key: a real one for Google AI Studio and OpenAI, an `UnavailableImageEditor`
    /// saying `.noKey` when no key is saved, and one saying `.unsupported` for every other service.
    public static func make(
        for kind: AIProviderKind,
        keyStore: AIKeyStore,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared
    ) -> any AIImageEditor {
        guard kind.canEditPhotos else {
            return UnavailableImageEditor(provider: kind, failure: .unsupported)
        }
        guard let key = keyStore.key(for: kind) else {
            return UnavailableImageEditor(provider: kind, failure: .noKey)
        }
        switch kind {
        case .googleAIStudio:
            return GeminiImageEditor(apiKey: key, transport: transport)
        case .openAI:
            return OpenAIImageEditor(apiKey: key, transport: transport)
        default:
            return UnavailableImageEditor(provider: kind, failure: .unsupported)
        }
    }
}

/// What both services are told to do with the photo, around the person's own words.
enum PhotoEditPrompt {
    static func wrap(_ instruction: String) -> String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Edit this photo as asked. Change only what the instruction says and keep everything else the same. "
            + "Return the edited photo. Instruction: \(trimmed)"
    }
}
