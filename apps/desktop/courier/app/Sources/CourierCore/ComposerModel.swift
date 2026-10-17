// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The modifier keys held with a key, as the composer reads them. The view translates the system's flags.
public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
}

/// What Return does in the composer.
public enum ReturnKeyAction: Equatable, Sendable {
    case send
    /// Add a line to the text. The view does that: only it knows where the caret is.
    case newline
}

/// What the composer needs to know about a file it is given.
public struct ComposerFileInfo: Equatable, Sendable {
    public var size: Int64
    /// A file, not a folder.
    public var isRegularFile: Bool

    public init(size: Int64, isRegularFile: Bool) {
        self.size = size
        self.isRegularFile = isRegularFile
    }
}

/// A file waiting to be sent, shown as a chip above the text.
public struct ComposerAttachment: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let size: Int64
    public var fileName: String { url.lastPathComponent }
}

/// Something the person should be told about the composer, under it.
public enum ComposerNotice: Equatable, Sendable {
    /// Adding the file would take the attachments past 90 MB.
    case attachmentTooLarge(fileName: String)
    /// Files that were to be put back after a send went wrong no longer fit under 90 MB with what was added since.
    case attachmentsLeftOut(fileNames: [String])
    /// What was given is a folder, which cannot be sent.
    case notAFile(fileName: String)
    /// The file could not be read (it is gone, or Courier may not open it).
    case cannotRead(fileName: String)
    /// The engine did not answer a send. It may have taken the message: the chat shows what it has.
    case noAnswer
    /// The engine refused a send. Nothing was sent, and what was typed is back in the composer.
    case sendFailed(reason: String)
}

/// Sends a person's words and files to a chat. The engine's client is behind it; tests give one that writes down
/// what it was asked.
public protocol MessageSending: AnyObject, Sendable {
    func sendText(roomID: String, text: String, replyTo: String?) async throws
    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?) async throws
}

/// The composer's state: the text, attachments and reply chip of the open chat, and a draft for every other chat
/// the person has typed in.
///
/// Sending clears the composer at once and sends in the background, a chat at a time and in order, so two messages
/// typed quickly arrive in that order. The text goes first, then the files, one `message.sendFile` each; a reply
/// is the first thing sent. If the engine refuses a send, what was not sent goes back into that chat's draft. If
/// it does not answer, the message may be sent already, so it is never sent again: the chat reads again and shows
/// what the engine has.
@MainActor
public final class ComposerModel: ObservableObject {
    /// The total size of the files in one send: 90 MB.
    public nonisolated static let maxAttachmentBytes: Int64 = 90 * 1024 * 1024

    /// The text of the open chat's draft. The text view writes it.
    @Published public var text = ""
    @Published public private(set) var attachments: [ComposerAttachment] = []
    @Published public private(set) var replyTarget: QuotedMessage?
    /// What the person should be told, first the most important. Cleared when another chat opens or on dismiss.
    @Published public private(set) var notices: [ComposerNotice] = []
    /// The first of `notices`.
    public var notice: ComposerNotice? { notices.first }
    public private(set) var roomID: String?

    public var sender: MessageSending?
    /// Called when a send is done, whether it worked or not, so the chat can read what the engine has.
    public var onSettled: @MainActor () -> Void = {}
    /// Called when something is submitted, before it is sent.
    public var onSubmit: @MainActor () -> Void = {}

    private struct Draft {
        var text = ""
        var attachments: [ComposerAttachment] = []
        var reply: QuotedMessage?
        /// Notices about a send in a chat that was not open when it ended: shown when it is opened.
        var notices: [ComposerNotice] = []

        var isEmpty: Bool { text.isEmpty && attachments.isEmpty && reply == nil && notices.isEmpty }

        /// What was refused, back above what has been typed since. The files that were refused come first; any
        /// added since that would take the total past 90 MB are left out, and their names are returned.
        func restored(into current: Draft) -> (draft: Draft, leftOut: [String]) {
            var merged = current
            merged.text = text.isEmpty ? current.text : (current.text.isEmpty ? text : text + "\n\n" + current.text)
            merged.reply = current.reply ?? reply
            var total = attachments.reduce(Int64(0)) { $0 + $1.size }
            merged.attachments = attachments
            var leftOut: [String] = []
            for file in current.attachments {
                if total + file.size <= ComposerModel.maxAttachmentBytes {
                    merged.attachments.append(file)
                    total += file.size
                } else {
                    leftOut.append(file.fileName)
                }
            }
            return (merged, leftOut)
        }
    }

    private enum Outgoing {
        case text(String)
        case file(ComposerAttachment)
    }

    private var drafts: [String: Draft] = [:]
    private var queues: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    private let fileInfo: (URL) -> ComposerFileInfo?

    public init(sender: MessageSending? = nil, fileInfo: @escaping (URL) -> ComposerFileInfo? = ComposerModel.readFileInfo) {
        self.sender = sender
        self.fileInfo = fileInfo
    }

    // MARK: - Keys

    /// Return sends; Shift, Option and Control with it add a line.
    public static func action(forReturn modifiers: KeyModifiers) -> ReturnKeyAction {
        modifiers.isDisjoint(with: [.shift, .option, .control]) ? .send : .newline
    }

    /// Return was pressed. Sends when it should, and says what the view is to do about the key.
    @discardableResult
    public func handleReturn(modifiers: KeyModifiers) -> ReturnKeyAction {
        let action = Self.action(forReturn: modifiers)
        if action == .send { submit() }
        return action
    }

    /// Escape clears the reply chip. False when there was none, so the key can do something else.
    public func escape() -> Bool {
        guard replyTarget != nil else { return false }
        replyTarget = nil
        return true
    }

    // MARK: - Chats and drafts

    /// Opens a chat's composer: the open chat's draft is kept, and this chat's (if it has one) comes back.
    public func open(_ room: String?) {
        guard room != roomID else { return }
        if let roomID { drafts[roomID] = currentDraft.isEmpty ? nil : currentDraft }
        roomID = room
        let draft = room.flatMap { drafts[$0] } ?? Draft()
        text = draft.text
        attachments = draft.attachments
        replyTarget = draft.reply
        notices = draft.notices
        if let room { drafts[room]?.notices = [] } // shown now, once
    }

    private var currentDraft: Draft { Draft(text: text, attachments: attachments, reply: replyTarget) }

    // MARK: - Reply

    public func startReply(to message: QuotedMessage) {
        replyTarget = message
    }

    public func cancelReply() {
        replyTarget = nil
    }

    // MARK: - Attachments

    /// Adds files to what will be sent. A folder, an unreadable file, or a file that would take the total past
    /// 90 MB is left out, and `notices` says which.
    public func attach(_ urls: [URL]) {
        notices = []
        for url in urls {
            let name = url.lastPathComponent
            if attachments.contains(where: { $0.url == url }) { continue }
            guard let info = fileInfo(url) else {
                notices = [.cannotRead(fileName: name)]
                continue
            }
            guard info.isRegularFile else {
                notices = [.notAFile(fileName: name)]
                continue
            }
            let total = attachments.reduce(Int64(0)) { $0 + $1.size }
            guard total + info.size <= Self.maxAttachmentBytes else {
                notices = [.attachmentTooLarge(fileName: name)]
                continue
            }
            attachments.append(ComposerAttachment(id: UUID(), url: url, size: info.size))
        }
    }

    public func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    public func dismissNotice() {
        notices = []
    }

    /// A file's size and kind from the disk; nil when it cannot be read.
    public nonisolated static func readFileInfo(_ url: URL) -> ComposerFileInfo? {
        let resolved = url.resolvingSymlinksInPath()
        guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              let size = values.fileSize else { return nil }
        return ComposerFileInfo(size: Int64(size), isRegularFile: values.isRegularFile ?? false)
    }

    // MARK: - Sending

    /// There is something to send: some text that is not only spaces, or a file.
    public var canSend: Bool {
        roomID != nil && sender != nil && (!trimmedText.isEmpty || !attachments.isEmpty)
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Sends the composer's text and files to the open chat and empties it. The task is done when everything has
    /// been handed to the engine (or refused, or not answered); the view does not wait for it.
    @discardableResult
    public func submit() -> Task<Void, Never>? {
        guard canSend, let room = roomID, let sender else { return nil }
        let draft = Draft(text: trimmedText, attachments: attachments, reply: replyTarget)
        text = ""
        attachments = []
        replyTarget = nil
        notices = []
        onSubmit()

        let previous = queues[room]?.task
        let token = UUID()
        let task = Task { [weak self] in
            await previous?.value
            await self?.deliver(draft, in: room, with: sender)
            self?.finish(token, in: room)
        }
        queues[room] = (token, task)
        return task
    }

    private func finish(_ token: UUID, in room: String) {
        if queues[room]?.token == token { queues[room] = nil }
    }

    /// Returns when every send started so far is done. For tests, and for quitting.
    public func settle() async {
        while let (room, entry) = queues.first {
            await entry.task.value
            if queues[room]?.token == entry.token { queues[room] = nil }
        }
    }

    private func deliver(_ draft: Draft, in room: String, with sender: MessageSending) async {
        var items: [Outgoing] = []
        if !draft.text.isEmpty { items.append(.text(draft.text)) }
        items += draft.attachments.map(Outgoing.file)
        var reply = draft.reply

        for (index, item) in items.enumerated() {
            do {
                switch item {
                case let .text(body):
                    try await sender.sendText(roomID: room, text: body, replyTo: reply?.eventID)
                case let .file(file):
                    try await sender.sendFile(roomID: room, url: file.url, size: file.size, replyTo: reply?.eventID)
                }
                reply = nil
            } catch {
                switch Self.classify(error) {
                case .refused(let reason):
                    // Nothing of this was sent: it, and what came after, goes back.
                    let leftOut = putBack(items[index...], reply: reply, in: room)
                    show([.sendFailed(reason: reason)] + Self.leftOutNotice(leftOut), in: room)
                case .unanswered:
                    // This one may have gone: it is not put back, and not sent again. The rest was never tried.
                    // Files that no longer fit are told after that warning, never instead of it.
                    let leftOut = putBack(items[(index + 1)...], reply: nil, in: room)
                    show([.noAnswer] + Self.leftOutNotice(leftOut), in: room)
                }
                onSettled()
                return
            }
        }
        onSettled()
    }

    private static func leftOutNotice(_ names: [String]) -> [ComposerNotice] {
        names.isEmpty ? [] : [.attachmentsLeftOut(fileNames: names)]
    }

    /// Puts what was not sent back into the chat's draft. Returns the names of the files left out because the
    /// total would pass 90 MB with what was added since.
    private func putBack(_ items: ArraySlice<Outgoing>, reply: QuotedMessage?, in room: String) -> [String] {
        var unsent = Draft(text: "", attachments: [], reply: reply)
        for item in items {
            switch item {
            case let .text(body): unsent.text = body
            case let .file(file): unsent.attachments.append(file)
            }
        }
        guard !unsent.isEmpty else { return [] }
        if room == roomID {
            let merged = unsent.restored(into: currentDraft)
            text = merged.draft.text
            attachments = merged.draft.attachments
            replyTarget = merged.draft.reply
            return merged.leftOut
        }
        let merged = unsent.restored(into: drafts[room] ?? Draft())
        drafts[room] = merged.draft
        return merged.leftOut
    }

    /// Text that was typed somewhere else (a notification's Reply) and could not be sent: it goes into that chat's
    /// draft, so it is there when the chat opens, or straight into the composer if the chat is open.
    /// `mayHaveBeenSent`: the engine did not answer, so it may have gone; the chat says so with its usual notice.
    public func restoreUnsent(text body: String, in room: String, mayHaveBeenSent: Bool = false) {
        _ = putBack([Outgoing.text(body)][...], reply: nil, in: room)
        if mayHaveBeenSent { show([.noAnswer], in: room) }
    }

    /// Tells the person: now if the chat is open, otherwise with that chat's draft, for when it is.
    private func show(_ notices: [ComposerNotice], in room: String) {
        if room == roomID {
            self.notices = notices
        } else {
            var draft = drafts[room] ?? Draft()
            draft.notices = notices
            drafts[room] = draft
        }
    }

    private enum Failure {
        case refused(String)
        case unanswered
    }

    /// Whether the engine said no, or may have said yes without being heard.
    private static func classify(_ error: Error) -> Failure {
        if (error as? EngineError)?.mayHaveBeenHandled == true { return .unanswered }
        return .refused(EngineErrorText.text(for: error, fallback: String(localized: "The message could not be sent.")))
    }
}

extension EngineError {
    /// The engine may have done what was asked though no answer came: the call timed out, the connection ended, or
    /// the answer was unreadable. The thing asked is then never sent again unasked.
    var mayHaveBeenHandled: Bool {
        switch self {
        case .timedOut, .disconnected, .badResponse: true
        default: false
        }
    }
}
