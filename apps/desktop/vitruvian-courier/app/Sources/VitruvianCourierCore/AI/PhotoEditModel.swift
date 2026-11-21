// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// What the photo-editing sheet needs from the AI settings, without the whole `AIProviderStore`.
public struct PhotoEditBackend {
    /// Whether "Edit with AI…" is offered at all: false while AI is turned off.
    public var isOffered: @MainActor () -> Bool
    /// Who edits photos now, read again each time so a key added in Settings counts.
    public var resolve: @MainActor () -> PhotoEditingResolution
    public var makeEditor: @MainActor (AIProviderKind) -> any AIImageEditor
    public var consent: PhotoEditConsentStore

    public init(
        isOffered: @escaping @MainActor () -> Bool,
        resolve: @escaping @MainActor () -> PhotoEditingResolution,
        makeEditor: @escaping @MainActor (AIProviderKind) -> any AIImageEditor,
        consent: PhotoEditConsentStore = PhotoEditConsentStore()
    ) {
        self.isOffered = isOffered
        self.resolve = resolve
        self.makeEditor = makeEditor
        self.consent = consent
    }
}

/// The result of one edit: the picture, and who made it.
public struct PhotoEditOutcome: Equatable, Sendable {
    public let image: EditedImage
    public let service: AIProviderKind

    /// "Edited with Google AI Studio", shown small under the result.
    public var caption: String { String(localized: "Edited with \(service.label)") }
}

/// The "Edit with AI…" sheet's state: the photo, what to change, then the result next to the original, to try again,
/// save to the Mac, or put in the chat's message box as a draft.
///
/// **It never sends.** The only way out for a result is `saveToMac` (a file) or `addToMessage` (a draft in the chat's
/// message box through `draftIntoMessage`); posting is always the person's own Send.
@MainActor
public final class PhotoEditModel: ObservableObject, Identifiable {
    public enum Phase: Equatable {
        /// Waiting for the person to say what to change.
        case ready
        /// The first photo to this service: asking before it goes.
        case confirming(AIProviderKind)
        case working(AIProviderKind)
        case done(PhotoEditOutcome)
        case failed(ImageEditFailure, AIProviderKind)
        /// No service can edit photos right now; the resolution says why.
        case unavailable(PhotoEditingResolution)
    }

    public nonisolated let id = UUID()
    public let source: PhotoEditSource
    @Published public var instruction: String = ""
    @Published public private(set) var phase: Phase = .ready
    /// A line about what the last Save or Add to Message did.
    @Published public private(set) var notice: String?

    private let backend: PhotoEditBackend
    private let readPhoto: @Sendable (String) throws -> Data
    private let draftIntoMessage: @MainActor (URL, String) -> Bool
    private let scratchDirectory: URL
    private let openAISettings: @MainActor (AIProviderKind?) -> Void
    private var task: Task<Void, Never>?
    private var generation = 0

    public init(
        source: PhotoEditSource,
        backend: PhotoEditBackend,
        draftIntoMessage: @escaping @MainActor (URL, String) -> Bool,
        openAISettings: @escaping @MainActor (AIProviderKind?) -> Void = { _ in },
        readPhoto: @escaping @Sendable (String) throws -> Data = { try Data(contentsOf: URL(fileURLWithPath: $0)) },
        scratchDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("VitruvianCourierEditedPhotos")
    ) {
        self.source = source
        self.backend = backend
        self.draftIntoMessage = draftIntoMessage
        self.openAISettings = openAISettings
        self.readPhoto = readPhoto
        self.scratchDirectory = scratchDirectory
        recheck()
    }

    deinit {
        task?.cancel()
    }

    /// Reads who edits photos again: a key added in Settings turns "can't edit" into "ready".
    public func recheck() {
        switch phase {
        case .working, .confirming, .done:
            return
        case .ready, .failed, .unavailable:
            break
        }
        let resolution = backend.resolve()
        if resolution.service == nil {
            phase = .unavailable(resolution)
        } else if case .unavailable = phase {
            phase = .ready
        }
    }

    /// Whether the Edit / Try Again button works: something is typed and nothing is running.
    public var canSubmit: Bool {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch phase {
        case .working, .confirming, .unavailable: return false
        case .ready, .done, .failed: return true
        }
    }

    /// Edit, or Try Again with the instruction as it now reads.
    public func submit() {
        guard canSubmit else { return }
        let resolution = backend.resolve()
        guard let service = resolution.service else {
            phase = .unavailable(resolution)
            return
        }
        guard backend.consent.hasConsented(to: service) else {
            phase = .confirming(service)
            return
        }
        run(with: service)
    }

    /// Continue, on the question before the first photo goes to a service: remembers the yes for that service.
    public func confirmConsent() {
        guard case let .confirming(service) = phase else { return }
        backend.consent.recordConsent(to: service)
        run(with: service)
    }

    /// Cancel, on that question: nothing is sent and nothing is remembered.
    public func declineConsent() {
        guard case .confirming = phase else { return }
        phase = .ready
    }

    /// Stops an edit in progress, or leaves the sheet: no result is kept.
    public func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        if case .working = phase { phase = .ready }
    }

    public func openSettings() {
        switch phase {
        case let .unavailable(resolution): openAISettings(resolution.keyToAdd)
        case let .failed(_, service): openAISettings(service)
        default: openAISettings(.googleAIStudio)
        }
    }

    private func run(with service: AIProviderKind) {
        generation += 1
        let mine = generation
        task?.cancel()
        notice = nil
        phase = .working(service)
        let editor = backend.makeEditor(service)
        let mime = source.mimeType
        let text = instruction
        let path = source.path
        let reader = readPhoto
        task = Task { [weak self] in
            let result: ImageEditResult
            do {
                let data = try await Task.detached(priority: .userInitiated) { try reader(path) }.value
                result = await editor.edit(image: data, mimeType: mime, instruction: text)
            } catch {
                result = .failure(.unreadablePhoto)
            }
            guard let self, !Task.isCancelled, self.generation == mine else { return }
            switch result {
            case let .success(image):
                self.phase = .done(PhotoEditOutcome(image: image, service: service))
            case .failure(.cancelled):
                self.phase = .ready
            case let .failure(failure):
                self.phase = .failed(failure, service)
            }
        }
    }

    // MARK: - What can be done with a result

    public var outcome: PhotoEditOutcome? {
        if case let .done(outcome) = phase { return outcome }
        return nil
    }

    /// The name a saved or drafted copy gets: the original's name with "edited" before the extension.
    public var suggestedFileName: String {
        let ext = outcome?.image.fileExtension ?? "png"
        let base = (source.fileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (base.isEmpty ? "Photo" : base) + " edited." + ext
    }

    /// Save to Mac…: writes the result to `url` (picked in a save panel).
    @discardableResult
    public func saveToMac(at url: URL) -> Bool {
        guard let outcome else { return false }
        do {
            try outcome.image.data.write(to: url, options: .atomic)
            notice = String(localized: "Saved \(url.lastPathComponent)")
            return true
        } catch {
            notice = String(localized: "Couldn’t save the photo.")
            return false
        }
    }

    /// Add to Message: puts the result in this chat's message box as an attachment, ready to send. **It does not send.**
    @discardableResult
    public func addToMessage() -> Bool {
        guard let outcome else { return false }
        let folder = scratchDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent(suggestedFileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try outcome.image.data.write(to: file, options: .atomic)
        } catch {
            notice = String(localized: "Couldn’t prepare the photo.")
            return false
        }
        guard draftIntoMessage(file, source.roomID) else {
            notice = String(localized: "Couldn’t add the photo to the message box.")
            return false
        }
        notice = String(localized: "Added to your message. Nothing is sent until you press Send.")
        return true
    }
}
