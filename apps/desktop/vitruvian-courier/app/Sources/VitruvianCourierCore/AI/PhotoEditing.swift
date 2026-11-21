// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Settings ▸ AI ▸ Photo editing: which service edits photos. It never changes the main AI service.
public enum PhotoEditingChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    /// The main AI service if it can edit photos, otherwise a saved Google AI Studio key, otherwise a saved OpenAI key.
    case automatic
    case googleAIStudio
    case openAI

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .googleAIStudio: AIProviderKind.googleAIStudio.label
        case .openAI: AIProviderKind.openAI.label
        }
    }

    /// The service a fixed choice names; nil for Automatic.
    public var service: AIProviderKind? {
        switch self {
        case .automatic: nil
        case .googleAIStudio: .googleAIStudio
        case .openAI: .openAI
        }
    }
}

/// Who will edit a photo, or why nobody can.
public enum PhotoEditingResolution: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// The main AI service can edit photos.
        case mainService
        /// The person picked this service for photo editing.
        case chosen
        /// Automatic fell back to a key saved for photo edits.
        case savedKey
    }

    case service(AIProviderKind, source: Source)
    /// Photo editing is on a fixed service whose key is not saved.
    case missingKey(AIProviderKind)
    /// Automatic found no service that can edit photos.
    case noService
    /// AI is turned off in Settings: photo editing is not offered.
    case aiOff

    /// The service that will do the edit, if there is one.
    public var service: AIProviderKind? {
        if case let .service(kind, _) = self { return kind }
        return nil
    }

    /// The service Settings should ask for a key for, when nothing can edit now.
    public var keyToAdd: AIProviderKind? {
        switch self {
        case let .missingKey(kind): kind
        case .noService: .googleAIStudio
        case .service, .aiOff: nil
        }
    }

    /// What the sheet says when nothing can edit photos.
    public var unavailableMessage: String? {
        switch self {
        case .noService:
            String(localized: "Your AI service can’t edit photos. Add a Google AI Studio key to use Nano Banana for photo edits.")
        case let .missingKey(kind):
            String(localized: "Add a \(kind.label) key to edit photos with \(kind.label).")
        case .aiOff:
            String(localized: "AI is turned off. Turn it on in Settings ▸ AI to edit photos.")
        case .service:
            nil
        }
    }

    /// A line under `unavailableMessage` about what Google needs, when Google is what to add.
    public var unavailableFootnote: String? {
        switch self {
        case .noService, .missingKey(.googleAIStudio):
            String(localized: "Google only allows photo edits with a key that has billing turned on.")
        case .missingKey(.openAI):
            String(localized: "OpenAI may ask your organization to verify itself before it allows photo edits.")
        default:
            nil
        }
    }

    /// One line for Settings ▸ AI under the Photo editing row.
    public var settingsStatusLine: String {
        switch self {
        case let .service(kind, .mainService):
            String(localized: "Uses \(kind.label), your AI service.")
        case let .service(kind, .savedKey):
            String(localized: "Uses \(kind.label), with the key saved here. Your AI service stays as it is.")
        case let .service(kind, .chosen):
            String(localized: "Uses \(kind.label). Your AI service stays as it is.")
        case let .missingKey(kind):
            String(localized: "Add a \(kind.label) key below to edit photos.")
        case .noService:
            String(localized: "Your AI service can’t edit photos. Add a Google AI Studio key below to use Nano Banana.")
        case .aiOff:
            String(localized: "AI is off, so photo editing is off too.")
        }
    }
}

extension PhotoEditingChoice {
    /// The Settings ▸ AI anchor of the Photo editing row.
    public static let settingID = "ai.photoEditing"

    /// The anchor of `kind`'s key field in Photo editing, so "Open AI Settings" can scroll to it and put the cursor in
    /// it. Only Google AI Studio and OpenAI have one; any other service (or none) is the Photo editing row itself.
    public static func settingID(forKeyOf kind: AIProviderKind?) -> String {
        guard let kind, kind.canEditPhotos else { return settingID }
        return settingID + "." + kind.rawValue
    }

    /// The service whose key field `settingID` names, when it names one.
    public static func keyService(forSettingID id: String?) -> AIProviderKind? {
        guard let id, id.hasPrefix(settingID + ".") else { return nil }
        return AIProviderKind(rawValue: String(id.dropFirst(settingID.count + 1)))
    }
}

public enum PhotoEditingResolver {
    /// Picks the service that edits photos. Pure: it reads nothing but its arguments.
    /// - Automatic: the main AI service if it can edit photos and has its key, else Google AI Studio if its key is
    ///   saved, else OpenAI if its key is saved, else `.noService`.
    /// - A fixed choice: that service if its key is saved, else `.missingKey`. The main service doesn't matter.
    /// - AI turned off: `.aiOff`, whatever else is set.
    public static func resolve(
        choice: PhotoEditingChoice,
        aiEnabled: Bool,
        mainService: AIProviderKind,
        hasKey: (AIProviderKind) -> Bool
    ) -> PhotoEditingResolution {
        guard aiEnabled else { return .aiOff }
        if let fixed = choice.service {
            return hasKey(fixed) ? .service(fixed, source: .chosen) : .missingKey(fixed)
        }
        if mainService.canEditPhotos, hasKey(mainService) {
            return .service(mainService, source: .mainService)
        }
        for kind in AIProviderKind.photoEditingServices where hasKey(kind) {
            return .service(kind, source: .savedKey)
        }
        return .noService
    }
}

/// Which services the person has already said yes to sending a photo to. Asked once per service.
public final class PhotoEditConsentStore: @unchecked Sendable {
    public static func key(for service: AIProviderKind) -> String {
        AIPreferencesKeys.prefix + "photoEditConsent." + service.rawValue
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func hasConsented(to service: AIProviderKind) -> Bool {
        defaults.bool(forKey: Self.key(for: service))
    }

    public func recordConsent(to service: AIProviderKind) {
        defaults.set(true, forKey: Self.key(for: service))
    }

    /// The question, asked before the first photo goes to `service`.
    public static func question(for service: AIProviderKind) -> String {
        String(localized: "This sends the photo to \(service.label). It may be someone else’s photo.")
    }
}

/// The `courier.ai.` prefix of `AIPreferences`'s keys, for the stores that sit beside it.
enum AIPreferencesKeys {
    static let prefix = "courier.ai."
}

/// A photo that can be edited: where its file is, and the chat it is in.
public struct PhotoEditSource: Equatable, Sendable {
    public let path: String
    public let fileName: String
    public let mimeType: String
    public let roomID: String

    public init(path: String, fileName: String, mimeType: String, roomID: String) {
        self.path = path
        self.fileName = fileName
        self.mimeType = mimeType
        self.roomID = roomID
    }

    /// Whether a media item is a photo this Mac holds and may edit: a still image (not a GIF, sticker or video), not
    /// view-once, with its file on disk.
    public static func isEditable(kind: MessageKind, mediaPath: String, mimeType: String, isGIF: Bool, viewOnce: Bool) -> Bool {
        guard kind == .image, !isGIF, !viewOnce, isLocalMediaStorePath(mediaPath) else { return false }
        let mime = mimeType.lowercased()
        return mime.isEmpty || (mime.hasPrefix("image/") && mime != "image/gif")
    }

    public init?(message: TimelineMessage) {
        guard !message.showsMediaRemovedPlaceholder,
              Self.isEditable(kind: message.kind, mediaPath: message.mediaPath, mimeType: message.mimeType,
                              isGIF: message.isGIF, viewOnce: message.viewOnce)
        else { return nil }
        self.init(path: message.mediaPath, fileName: message.fileName, mimeType: message.mimeType, roomID: message.roomID)
    }

    public init?(item: CarouselItem) {
        guard Self.isEditable(kind: item.kind, mediaPath: item.mediaPath, mimeType: item.mimeType,
                              isGIF: item.isGIF, viewOnce: item.viewOnce)
        else { return nil }
        self.init(path: item.mediaPath, fileName: item.fileName, mimeType: item.mimeType, roomID: item.roomID)
    }
}
