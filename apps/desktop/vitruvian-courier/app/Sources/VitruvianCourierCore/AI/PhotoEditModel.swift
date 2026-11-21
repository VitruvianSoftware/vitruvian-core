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

/// Where edited photos wait while they are attached to a draft. The composer holds an attachment by its file's address
/// (it doesn't copy it), so a file stays until the draft is sent or dropped; anything left behind is swept at launch.
public enum PhotoEditScratch {
    public static let folderName = "VitruvianCourierEditedPhotos"
    public static let maxAge: TimeInterval = 24 * 60 * 60

    public static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Whether `url` is a file inside `root` (not `root` itself). Symlinks are resolved on both sides.
    public static func isInside(_ url: URL, root: URL = defaultDirectory) -> Bool {
        let file = url.resolvingSymlinksInPath().standardizedFileURL.path
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        return file.hasPrefix(base + "/") && file.count > base.count + 1
    }

    /// Deletes `file` if it is inside `root`, and its folder when that is left empty (and is not `root`). Anything outside
    /// `root` is left alone. Returns whether it deleted the file.
    @discardableResult
    public static func remove(_ file: URL, root: URL = defaultDirectory, fileManager: FileManager = .default) -> Bool {
        guard isInside(file, root: root) else { return false }
        guard (try? fileManager.removeItem(at: file)) != nil else { return false }
        let folder = file.deletingLastPathComponent()
        if isInside(folder, root: root), (try? fileManager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? fileManager.removeItem(at: folder)
        }
        return true
    }

    /// Removes what is older than `maxAge` under `directory` (a session's folder at a time). Run at launch, when no
    /// draft can still hold one of these files: drafts' attachments are not kept across launches. Returns how many
    /// entries it removed.
    @discardableResult
    public static func sweep(
        directory: URL = defaultDirectory, olderThan age: TimeInterval = maxAge, now: Date = Date(),
        fileManager: FileManager = .default
    ) -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: []
        ) else { return 0 }
        var removed = 0
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            // An entry with no readable date is as old as can be.
            guard modified.map({ now.timeIntervalSince($0) > age }) ?? true else { continue }
            if (try? fileManager.removeItem(at: entry)) != nil { removed += 1 }
        }
        return removed
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
    /// The service the photo goes to, as things stand: Settings' choice, or the fallback Automatic picked. Nil when none can edit.
    @Published public private(set) var service: AIProviderKind?

    private let backend: PhotoEditBackend
    private let readPhoto: @Sendable (String) throws -> Data
    private let draftIntoMessage: @MainActor (URL, String) -> Bool
    private let scratchDirectory: URL
    private let openAISettings: @MainActor (AIProviderKind?) -> Void
    private var task: Task<Void, Never>?
    private var generation = 0
    /// This sheet's own folder under `scratchDirectory`, made when a result is first added to a message.
    private let sessionID = UUID().uuidString
    private var addedToMessage = false

    var sessionFolder: URL { scratchDirectory.appendingPathComponent(sessionID, isDirectory: true) }

    public init(
        source: PhotoEditSource,
        backend: PhotoEditBackend,
        draftIntoMessage: @escaping @MainActor (URL, String) -> Bool,
        openAISettings: @escaping @MainActor (AIProviderKind?) -> Void = { _ in },
        readPhoto: @escaping @Sendable (String) throws -> Data = { try Data(contentsOf: URL(fileURLWithPath: $0)) },
        scratchDirectory: URL = PhotoEditScratch.defaultDirectory
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
        let resolution = backend.resolve()
        service = resolution.service
        switch phase {
        case .working, .confirming, .done:
            return
        case .ready, .failed, .unavailable:
            break
        }
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
        self.service = resolution.service
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

    /// "The photo goes to Google AI Studio.": names the service that will get it, which with Automatic may be a fallback.
    public var destinationLine: String? {
        service.map { String(localized: "The photo goes to \($0.label).") }
    }

    /// The sheet is closing: stops any edit, and clears this sheet's files unless a result was added to a message (the
    /// draft holds that file by its address, so it stays until launch's sweep).
    public func close() {
        cancel()
        if !addedToMessage { removeSessionFolder() }
    }

    private func removeSessionFolder() {
        try? FileManager.default.removeItem(at: sessionFolder)
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

    /// The name a saved or drafted copy gets: the original's name with "edited" before the extension. The original's name
    /// comes from whoever sent the photo, so only its last path component is used, with leading dots and separators
    /// dropped ("../../x.jpg" is "x edited.png"); with nothing left it is "Edited Photo.png".
    public var suggestedFileName: String {
        Self.safeFileName(from: source.fileName, fileExtension: outcome?.image.fileExtension ?? "png")
    }

    static func safeFileName(from original: String, fileExtension ext: String) -> String {
        let slashed = original.replacingOccurrences(of: "\\", with: "/")
        var last = (slashed as NSString).lastPathComponent
        let drop = CharacterSet(charactersIn: "./:").union(.whitespacesAndNewlines).union(.controlCharacters)
        last = String(last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" && $0 != "/" })
        while let first = last.unicodeScalars.first, drop.contains(first) { last.unicodeScalars.removeFirst() }
        let base = (last as NSString).deletingPathExtension.trimmingCharacters(in: drop)
        guard !base.isEmpty else { return "Edited Photo." + ext }
        return String(base.prefix(120)) + " edited." + ext
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
        // A folder of its own for each add, so adding twice never changes a file a draft already holds.
        let folder = sessionFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent(suggestedFileName)
        guard file.standardizedFileURL.path.hasPrefix(sessionFolder.standardizedFileURL.path + "/") else {
            notice = String(localized: "Couldn’t prepare the photo.")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try outcome.image.data.write(to: file, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            notice = String(localized: "Couldn’t prepare the photo.")
            return false
        }
        guard draftIntoMessage(file, source.roomID) else {
            try? FileManager.default.removeItem(at: folder)
            notice = String(localized: "Couldn’t add the photo to the message box.")
            return false
        }
        addedToMessage = true
        notice = String(localized: "Added to your message. Nothing is sent until you press Send.")
        return true
    }
}
