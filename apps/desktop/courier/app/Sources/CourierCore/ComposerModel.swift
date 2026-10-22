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
    /// The text is longer than the chat's network takes (`ChatFeatures.maxTextLength`, counted in bytes of UTF-8,
    /// so an emoji counts four). Nothing was sent, and the text stays to be shortened.
    case textTooLong
}

/// Where the composer asks the text view to put the caret, in UTF-16 units. A new request has a higher serial.
public struct CaretRequest: Equatable, Sendable {
    public let location: Int
    public let serial: Int
}

/// The link dialog, asked for over `range` of the composer's text. A new request has a higher serial.
public struct LinkEditRequest: Equatable, Sendable {
    public let range: NSRange
    public let serial: Int
}

/// What the composer is doing.
public enum ComposerMode: Equatable, Sendable {
    /// Writing a new message to the chat.
    case new
    /// Changing a message of mine: Return sends message.edit, Escape puts back what was in the composer.
    case editing(eventID: String, original: RichText)
    /// Writing in a thread: what is sent goes in it.
    case thread(rootID: String)
}

/// Sends a person's words and files to a chat. The engine's client is behind it; tests give one that writes down
/// what it was asked.
public protocol MessageSending: AnyObject, Sendable {
    func sendText(roomID: String, text: String, replyTo: String?) async throws
    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?) async throws
    /// Keeps a chat's unsent text (room.setDraft). It stays on this Mac.
    func saveDraft(roomID: String, text: String) async throws
    /// message.send: text and its ranges, in a thread or not, held `holdMillis` for undo send (0 is not held).
    /// Returns the stored event's ID.
    func send(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, holdMillis: Int) async throws
        -> String
    /// message.sendFile, as `send`.
    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?, threadRoot: String?, holdMillis: Int)
        async throws -> String
    /// message.edit.
    func edit(eventID: String, rich: RichText) async throws
    /// message.schedule.
    func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date,
                  condition: SendLaterCondition) async throws
    /// message.undo: the held message's text, ranges and reply, given back.
    func undo(eventID: String) async throws -> Draft
    /// message.sendHeld: a chat's held messages now, or with nil every chat's.
    func sendHeld(roomID: String?) async throws
    /// room.members: the people whose name matches what was typed after "@".
    func members(roomID: String, query: String) async throws -> [Member]
    /// A message's status line as the engine has it now, read in `thread` for a thread reply (the chat's own
    /// timeline leaves those out); nil when it isn't there (it was undone or deleted). Throws when it can't be read.
    func status(of eventID: String, in roomID: String, thread: String?) async throws -> StatusLine?
}

extension MessageSending {
    /// A sender with nowhere to keep drafts keeps none.
    public func saveDraft(roomID: String, text: String) async throws {}
}

/// The composer's state: the text and its formatting, attachments and reply chip of the open chat, a draft for every
/// other chat the person has typed in, and what it is doing (a new message, an edit, a thread).
///
/// The open chat's text is also kept by the engine (`room.setDraft`), a second after typing stops and at once on
/// switching chats, so it is there after a restart. A chat opened with no text in memory takes the engine's draft:
/// its inbox row's (`savedDraft`), or for a chat the inbox hasn't loaded, one looked up (`lookUpDraft`). Until the
/// engine's draft is known, nothing is saved for that chat, so no keystroke can overwrite a draft nobody has seen.
/// The formatting (`entities`) stays in memory with the draft; the engine keeps the text only. While a message is
/// being edited, the draft kept is what was in the composer before, never the edit.
///
/// Sending clears the composer at once and sends in the background, a chat at a time and in order, so two messages
/// typed quickly arrive in that order. The text goes first, then the files, one `message.sendFile` each; a reply
/// is the first thing sent. If the engine refuses a send, what was not sent goes back into that chat's draft. If
/// it does not answer, the message may be sent already, so it is never sent again: the chat reads again and shows
/// what the engine has. What is sent is cut of spaces at either end and its ranges cleaned as the engine checks them
/// (`RichTextHTML.sendable`); text longer than the chat takes is refused here, with why, and nothing is sent.
///
/// Undo send: with the preference on and a plan that has it, each send is held `undoSendMillis` (`hold_ms`); the
/// held messages of the open chat are `heldIDs`. ⌘Z (`undoNewestHeld`) takes the newest back: either the engine gives
/// back what was typed, and it goes back into the composer, or it says the message already went (-32025), and the
/// composer says whether it really did. Never both, and never twice. `HeldMessages` keeps the books.
@MainActor
public final class ComposerModel: ObservableObject {
    /// The total size of the files in one send: 90 MB.
    public nonisolated static let maxAttachmentBytes: Int64 = 90 * 1024 * 1024

    /// The text of the open chat's draft (or, while editing, of the edit). The text view writes it, best through
    /// `textChanged(to:replacing:with:)`; set as a whole, the ranges follow what changed as well as can be told.
    @Published public var text = "" {
        didSet { if text != oldValue { textDidChange(from: oldValue) } }
    }
    /// The formatting of `text`. Kept with the in-memory draft; room.setDraft still keeps the text only.
    @Published public var entities: [TextEntity] = []
    /// A key with no selection: applies to what is typed next, there.
    @Published public private(set) var pendingKinds: Set<TextEntity.Kind> = []
    @Published public private(set) var mode: ComposerMode = .new
    /// "@" plus letters at the caret: who to mention. `range` covers the "@" and the letters.
    @Published public private(set) var mentionQuery: (range: NSRange, text: String)?
    /// ";" plus letters at the caret: which quick reply. `range` covers the ";" and the letters.
    @Published public private(set) var quickReplyQuery: (range: NSRange, text: String)?
    /// My held (queued) messages in the open chat, newest last.
    @Published public private(set) var heldIDs: [String] = []
    @Published public private(set) var attachments: [ComposerAttachment] = []
    @Published public private(set) var replyTarget: QuotedMessage?
    /// What the person should be told, first the most important. Cleared when another chat opens or on dismiss.
    @Published public private(set) var notices: [ComposerNotice] = []
    /// A short word about what was just done (an undo, a plan's limit), when `onToast` isn't set.
    @Published public private(set) var toast: Toast?
    /// A message is being scheduled: until the engine answers, Return and Send Later do nothing, so nothing goes twice.
    @Published public private(set) var isScheduling = false
    /// Where the text view is to put the caret after the composer changed the text itself (a mention or quick reply
    /// put in, a link's words): a new request each time.
    @Published public private(set) var caretRequest: CaretRequest?
    /// The link dialog is asked for, over this range (⌘⇧K, or the Message menu's Link…): a new request each time.
    @Published public private(set) var linkRequest: LinkEditRequest?
    /// The text view's selection, as last told: what the Message menu's formatting items act on.
    public private(set) var selection = NSRange(location: 0, length: 0)
    /// The first of `notices`.
    public var notice: ComposerNotice? { notices.first }
    public private(set) var roomID: String?

    public var sender: MessageSending?
    /// The open chat's features (room.features): its text limit, @room, and what Return and ↑ may edit. Opening
    /// another chat forgets them, until that chat's are set.
    public var features: ChatFeatures = .noFeatures
    /// The open chat's network, by the engine's id. Opening another chat forgets it.
    public var network = ""
    /// In a one-to-one chat, the other person's name, which quick replies fill in; nil in a group. Opening another
    /// chat forgets it.
    public var otherPerson: String?
    /// The person's plan: undo send holds and send later schedules only with it. Until it is set, neither.
    public var entitlement: any EntitlementProvider
    /// The composer's settings; nil is every default (undo send off).
    public var preferences: ComposerPreferences?
    public var quickReplies: QuickReplies?
    /// Called when a send is done, whether it worked or not, so the chat can read what the engine has.
    public var onSettled: @MainActor () -> Void = {}
    /// Called when something is submitted, before it is sent.
    public var onSubmit: @MainActor () -> Void = {}
    /// The draft the engine keeps for a chat, for a chat opened with none in memory: its inbox row's `draft`. Nil
    /// when the inbox hasn't loaded the chat (another space, a filter, further down), so it isn't known here.
    public var savedDraft: @MainActor (_ roomID: String) -> String? = { _ in "" }
    /// Looks up the draft of a chat `savedDraft` doesn't know (`inbox.list {room_ids: [id]}`). Nil when that fails:
    /// the draft stays unknown, and nothing is saved for the chat.
    public var lookUpDraft: @MainActor (_ roomID: String) async -> String? = { _ in nil }
    /// A message of the open chat as a reply chip shows it, for a reply that comes back with an undone message.
    public var quote: @MainActor (_ eventID: String) -> QuotedMessage? = { _ in nil }
    /// The message selected in the timeline, for Return in an empty composer.
    public var selectedMessage: @MainActor () -> TimelineMessage? = { nil }
    /// ⌘↩: archives the chat once its message has gone. The inbox does it, as its own Archive does (a pinned chat,
    /// its toast with Undo, what opens next).
    public var onArchive: @MainActor (_ roomID: String) async -> Void = { _ in }
    /// Where toasts go: the inbox's, the one place they show. Unset, they are `toast`.
    public var onToast: (@MainActor (String) -> Void)?

    /// One chat's composer, kept while another is open.
    private struct Contents {
        var text = ""
        var entities: [TextEntity] = []
        var attachments: [ComposerAttachment] = []
        var reply: QuotedMessage?
        /// Notices about a send in a chat that was not open when it ended: shown when it is opened.
        var notices: [ComposerNotice] = []

        var isEmpty: Bool { text.isEmpty && attachments.isEmpty && reply == nil && notices.isEmpty }

        /// What was refused, back above what has been typed since. The files that were refused come first; any
        /// added since that would take the total past 90 MB are left out, and their names are returned.
        func restored(into current: Contents) -> (draft: Contents, leftOut: [String]) {
            var merged = current
            (merged.text, merged.entities) = ComposerModel.join((text, entities), (current.text, current.entities))
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
        case text(RichText)
        case file(ComposerAttachment)
    }

    private var drafts: [String: Contents] = [:]
    private var queues: [String: (token: UUID, task: Task<Void, Never>)] = [:]
    private let fileInfo: (URL) -> ComposerFileInfo?
    private let draftDelay: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let now: @MainActor () -> Date
    /// The text the engine has for each chat, as far as this composer knows: what it saved, or the draft it took.
    private var savedTexts: [String: String] = [:]
    /// Goes up with each change of text and each switch: a wait that finds it moved on saves nothing.
    private var draftToken = 0
    /// Saves to the engine, a chat at a time and in order.
    private var draftSaves: [String: Task<Void, Never>] = [:]
    /// The text is being set by opening a chat, not by typing.
    private var openingChat = false
    /// Chats whose draft the engine has but this composer doesn't know yet: nothing is saved for them.
    private var unknownDrafts: Set<String> = []
    /// The text is being set with its ranges already known: they aren't worked out from the change.
    private var settingContents = false
    /// What was in the composer when an edit started, and what it was doing: back on Escape or once it is sent.
    private var stash = Contents()
    private var stashedMode: ComposerMode = .new
    /// Where `pendingKinds` apply: typing there takes them, and the caret moving elsewhere drops them.
    private var pendingAt = 0
    /// A line break about to be typed at the end of a block: the new line goes on in that block.
    private var continuingBlock: (kind: TextEntity.Kind, at: Int)?
    private var caretSerial = 0
    /// My held messages, by chat, and what Undo does with them.
    private let held = HeldMessages()

    /// - Parameters:
    ///   - draftDelay: how long after the last keystroke the draft is saved, in seconds.
    ///   - sleep: waits `draftDelay`; tests give one they can open.
    ///   - preferences: the composer's settings (undo send, ↑); nil is every default.
    ///   - entitlement: whether the plan has undo send and send later. A send is held only with it; with none given,
    ///     there is no plan.
    ///   - now: the time now, for what ↑ and Return may edit and when a held message's window ends; tests give their
    ///     own.
    public init(sender: MessageSending? = nil, fileInfo: @escaping (URL) -> ComposerFileInfo? = ComposerModel.readFileInfo,
                draftDelay: TimeInterval = 1,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { await waitForInboxWindow($0) },
                preferences: ComposerPreferences? = nil, entitlement: any EntitlementProvider = NoPlan(),
                quickReplies: QuickReplies? = nil, now: @escaping @MainActor () -> Date = Date.init) {
        self.sender = sender
        self.fileInfo = fileInfo
        self.draftDelay = draftDelay
        self.sleep = sleep
        self.preferences = preferences
        self.entitlement = entitlement
        self.quickReplies = quickReplies
        self.now = now
        held.sender = { [weak self] in self?.sender }
        held.now = now
        held.quote = { [weak self] id in self?.quote(id) }
        held.onChange = { [weak self] room in
            guard let self, room == self.roomID else { return }
            let ids = self.held.ids(in: room)
            if self.heldIDs != ids { self.heldIDs = ids }
        }
        held.onRestore = { [weak self] room, copy in
            self?.restoreUndone(copy, in: room)
            self?.showToast(String(localized: "Message unsent from Courier"))
        }
        held.onToast = { [weak self] message in self?.showToast(message) }
    }

    private var isEditing: Bool {
        if case .editing = mode { return true }
        return false
    }

    private var threadRoot: String? {
        if case let .thread(root) = mode { return root }
        return nil
    }

    // MARK: - Keys

    /// Return sends; Shift, Option and Control with it add a line.
    public static func action(forReturn modifiers: KeyModifiers) -> ReturnKeyAction {
        modifiers.isDisjoint(with: [.shift, .option, .control]) ? .send : .newline
    }

    /// Return was pressed. Sends when it should, and says what the view is to do about the key. In an empty
    /// composer with a message selected, it edits the message if it is mine and can be edited, and otherwise
    /// replies to it (02 §2.2 "Quote or Edit Selected Message").
    @discardableResult
    public func handleReturn(modifiers: KeyModifiers) -> ReturnKeyAction {
        let action = Self.action(forReturn: modifiers)
        guard action == .send else { return action }
        if mode == .new, trimmedText.isEmpty, attachments.isEmpty, let selected = selectedMessage() {
            act(on: selected)
        } else {
            submit()
        }
        return action
    }

    /// Escape ends an edit (what was in the composer comes back), or else clears the reply chip. False when there
    /// was neither, so the key can do something else.
    public func escape() -> Bool {
        if isEditing {
            leaveEditing()
            return true
        }
        guard replyTarget != nil else { return false }
        replyTarget = nil
        return true
    }

    private func act(on message: TimelineMessage) {
        let offered = MessageActions.available(for: message, in: features, network: network, now: now()).actions
        if offered.contains(.edit) {
            startEditing(message)
        } else if offered.contains(.reply) {
            startReply(to: message.quoted)
        } else if offered.contains(.replyInThread) {
            startThread(message.id)
        }
    }

    // MARK: - Chats and drafts

    /// Opens a chat's composer: the open chat's draft is kept (and saved at once if the engine doesn't have it),
    /// and this chat's comes back: the one in memory, or with none, the engine's. An edit under way ends, and a
    /// thread is left.
    public func open(_ room: String?) {
        guard room != roomID else { return }
        if isEditing { leaveEditing() }
        mode = .new
        features = .noFeatures // the next chat's are set once it is open
        network = ""
        otherPerson = nil
        if let roomID {
            if !unknownDrafts.contains(roomID), text != (savedTexts[roomID] ?? "") { saveDraft(text, in: roomID) }
            drafts[roomID] = currentContents.isEmpty ? nil : currentContents
        }
        draftToken += 1 // a wait for the chat left behind saves nothing
        roomID = room
        let draft = room.flatMap { drafts[$0] } ?? Contents()
        openingChat = true
        defer { openingChat = false }
        if let room, draft.text.isEmpty {
            if let kept = savedTexts[room] ?? savedDraft(room) {
                savedTexts[room] = kept
                setContents(kept, [])
            } else {
                // Not in the rows loaded: look it up, and save nothing for it until the answer says what it is.
                setContents("", [])
                unknownDrafts.insert(room)
                Task { [weak self] in
                    guard let self else { return }
                    let kept = await self.lookUpDraft(room)
                    self.learnDraft(kept, of: room)
                }
            }
        } else {
            setContents(draft.text, draft.entities)
        }
        attachments = draft.attachments
        replyTarget = draft.reply
        notices = draft.notices
        heldIDs = room.map { held.ids(in: $0) } ?? []
        if let room { drafts[room]?.notices = [] } // shown now, once
    }

    private var currentContents: Contents {
        Contents(text: text, entities: entities, attachments: attachments, reply: replyTarget)
    }

    /// The open chat's own draft: what is in the composer, or while editing, what was there before the edit.
    private var openContents: Contents {
        get { isEditing ? stash : currentContents }
        set {
            if isEditing {
                stash = newValue
            } else {
                setContents(newValue.text, newValue.entities)
                attachments = newValue.attachments
                replyTarget = newValue.reply
            }
        }
    }

    /// Sets the text and its ranges together, as one change.
    private func setContents(_ newText: String, _ newEntities: [TextEntity]) {
        settingContents = true
        text = newText
        settingContents = false
        entities = newEntities
        pendingKinds = []
        mentionQuery = nil
        quickReplyQuery = nil
    }

    /// The engine's draft of a chat, looked up. Nil (the lookup failed) leaves it unknown: it is looked up again
    /// the next time the chat opens. What the person typed meanwhile is kept after the engine's draft, so neither
    /// is lost, and from now on it saves as usual.
    private func learnDraft(_ kept: String?, of room: String) {
        guard let kept, unknownDrafts.remove(room) != nil else { return }
        savedTexts[room] = kept
        if room == roomID {
            var open = openContents
            if open.text.isEmpty {
                openingChat = true
                open.text = kept
                open.entities = []
                openContents = open
                openingChat = false
            } else if !kept.isEmpty {
                (open.text, open.entities) = Self.join((kept, []), (open.text, open.entities))
                openContents = open
                if isEditing { draftTextChanged() } // setting the composer's text saves it already
            } else {
                draftTextChanged()
            }
        } else if var draft = drafts[room], !draft.text.isEmpty, !kept.isEmpty {
            (draft.text, draft.entities) = Self.join((kept, []), (draft.text, draft.entities))
            drafts[room] = draft
        }
    }

    /// The text the chat's draft is: while editing, what was in the composer before, never the edit.
    private var draftBody: String { isEditing ? stash.text : text }

    /// Typing (or a send that emptied the box): the draft is saved once the text has rested for `draftDelay`.
    private func draftTextChanged() {
        guard !openingChat, let room = roomID, !unknownDrafts.contains(room) else { return }
        draftToken += 1
        guard draftBody != (savedTexts[room] ?? "") else { return } // back to what the engine has: nothing to save
        let token = draftToken
        Task { [weak self, sleep, draftDelay] in
            await sleep(draftDelay)
            guard let self, self.draftToken == token, self.roomID == room else { return }
            self.saveDraft(self.draftBody, in: room)
        }
    }

    /// Hands the draft to the engine, after the saves before it for that chat. A failure is not shown: the text is
    /// still in the composer, and the next change saves it again.
    private func saveDraft(_ body: String, in room: String) {
        savedTexts[room] = body
        guard let sender else { return }
        let previous = draftSaves[room]
        let save = Task {
            await previous?.value
            try? await sender.saveDraft(roomID: room, text: body)
        }
        draftSaves[room] = save
    }

    // MARK: - Text and formatting

    /// The text view's edit: `range` of the old text was replaced by `length` UTF-16 units, giving `text`. The ranges
    /// follow it (EntityEditing.replacing); typed where a formatting key was pressed with no selection, it takes that
    /// formatting; and "@" or ";" with letters at the caret is looked up.
    public func textChanged(to text: String, replacing range: NSRange, with length: Int) {
        settingContents = true
        self.text = text
        settingContents = false
        applyEdit(range: range, length: length)
    }

    /// The caret or selection moved. A pending formatting key holds only where it was pressed.
    public func selectionChanged(to range: NSRange) {
        selection = range
        if range.length > 0 || range.location != pendingAt { pendingKinds = [] }
        if range.length > 0 {
            mentionQuery = nil
            quickReplyQuery = nil
        } else {
            updateQueries(caret: range.location)
        }
    }

    /// A formatting key (⌘B, ⌘I, ⌘⇧X, ⌘E, the quote and list keys) on `range`. With no selection, an inline kind is
    /// kept for what is typed next (or, pressed again, dropped); a block takes the caret's line, or on an empty line
    /// the line typed next.
    public func toggle(_ kind: TextEntity.Kind, in range: NSRange) {
        guard kind != .link, kind != .mention else { return }
        let string = text as NSString
        let emptyLine = kind.isBlock && EntityEditing.lineSpan(of: range, in: string).length == 0
        if (range.length == 0 && !kind.isBlock) || emptyLine {
            if pendingKinds.contains(kind), pendingAt == range.location {
                pendingKinds.remove(kind)
            } else {
                if pendingAt != range.location { pendingKinds = [] }
                pendingKinds.insert(kind)
                pendingAt = range.location
            }
            return
        }
        entities = EntityEditing.toggle(kind, in: range, of: string, entities: entities)
    }

    /// A formatting key, or the Message menu's item, on `range`: the link key asks for the link dialog, the others
    /// toggle their kind. A kind the chat doesn't keep changes nothing and says why, in the formatting bar's words
    /// ("Spoiler (Unavailable for WhatsApp)"). False when nothing was done.
    @discardableResult
    public func formattingKey(_ kind: TextEntity.Kind, in range: NSRange) -> Bool {
        guard roomID != nil else { return false }
        guard features.keeps(kind) else {
            if let item = FormattingBar.items(features: features, network: network).first(where: { $0.kind == kind }) {
                showToast(item.help)
            }
            return false
        }
        if kind == .link {
            caretSerial += 1
            linkRequest = LinkEditRequest(range: range, serial: caretSerial)
        } else {
            toggle(kind, in: range)
        }
        return true
    }

    /// Makes `range` a link to `url`, its words `text` (the address when empty), in place of what was selected. A nil
    /// url takes the links off `range` and keeps their words. An address the engine wouldn't take (not http, https
    /// or mailto) changes nothing.
    public func setLink(_ url: URL?, text words: String, in range: NSRange) {
        guard let url else {
            entities.removeAll { $0.kind == .link && Self.touches($0, range) }
            return
        }
        let address = url.absoluteString
        guard RichTextHTML.isSafeURL(address) else { return }
        let shown = words.isEmpty ? address : words
        let string = text as NSString
        guard range.location >= 0, range.location + range.length <= string.length else { return }
        if string.substring(with: range) != shown { replaceText(in: range, with: shown) }
        let linked = NSRange(location: range.location, length: (shown as NSString).length)
        entities.removeAll { [.link, .mention, .code].contains($0.kind) && Self.touches($0, linked) }
        entities.append(TextEntity(kind: .link, offset: linked.location, length: linked.length, url: address))
        entities.sort(by: TextEntity.precedes)
    }

    /// "@Name" in place of `range` (the "@" and what was typed), as one mention, and a space after it.
    public func insertMention(_ member: Member, replacing range: NSRange) {
        let name = "@" + member.name
        let string = text as NSString
        guard range.location >= 0, range.location + range.length <= string.length else { return }
        let end = range.location + range.length
        let spaced = end < string.length
            && CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(string.character(at: end)) ?? " ")
        replaceText(in: range, with: spaced ? name : name + " ")
        let mention = TextEntity(kind: .mention, offset: range.location, length: (name as NSString).length,
                                 userID: member.userID)
        entities.removeAll { [.link, .mention, .code].contains($0.kind) && Self.touches($0, mention.range) }
        entities.append(mention)
        entities.sort(by: TextEntity.precedes)
        mentionQuery = nil
    }

    /// A quick reply's text in place of `range` (the ";" and what was typed), its variables filled from the other
    /// person's name in a one-to-one chat (nil in a group).
    public func insertQuickReply(_ reply: QuickReply, replacing range: NSRange, otherPerson: String?) {
        let string = text as NSString
        guard range.location >= 0, range.location + range.length <= string.length else { return }
        replaceText(in: range, with: QuickReplies.fill(reply.text, otherPerson: otherPerson))
        quickReplyQuery = nil
    }

    /// A quick reply in place of `range`, filled from the open chat's other person (`otherPerson`).
    public func insertQuickReply(_ reply: QuickReply, replacing range: NSRange) {
        insertQuickReply(reply, replacing: range, otherPerson: otherPerson)
    }

    /// "Insert as Draft" on someone else's message: its text and formatting go into the composer, below what is
    /// typed (after a blank line), so nothing typed is lost. While editing, it waits with what was there before.
    public func insertAsDraft(_ rich: RichText) {
        guard roomID != nil, !rich.text.isEmpty else { return }
        var open = openContents
        (open.text, open.entities) = Self.join((open.text, open.entities), (rich.text, rich.entities))
        openContents = open
        if isEditing { draftTextChanged() } // setting the composer's text saves it already
    }

    /// The quick replies whose title starts with what follows the ";", at most 8.
    public var quickReplyMatches: [QuickReply] {
        guard let query = quickReplyQuery, let quickReplies else { return [] }
        return quickReplies.matching(query.text)
    }

    /// The people to offer for `mentionQuery`: the chat's members whose name matches, and first, @room where the chat
    /// has it (Slack) and what was typed could be it.
    public func mentionCandidates() async -> [Member] {
        guard let room = roomID, let sender, let query = mentionQuery?.text else { return [] }
        let roomMention = features.mentionRoom && "room".hasPrefix(QuickReplies.fold(query))
        var found = (try? await sender.members(roomID: room, query: query)) ?? []
        found.removeAll { $0.userID == "@room" }
        if roomMention { found.insert(Member(userID: "@room", name: "room"), at: 0) }
        return found
    }

    /// A new line (Shift-Return) at `range`, before the view types it. In a quote, a list or a code block the new
    /// line goes on in the block, as in other editors; and on an empty line that was going on in one, it leaves the
    /// block instead, adding no line: two Returns on an empty item end a list. True when the view is to type the
    /// line break; false when it left the block, and types nothing.
    public func beginNewline(at range: NSRange) -> Bool {
        continuingBlock = nil
        let string = text as NSString
        guard range.location >= 0, range.location + range.length <= string.length else { return true }
        let blocks = pendingKinds.filter(\.isBlock)
        if range.length == 0, !blocks.isEmpty, pendingAt == range.location,
           EntityEditing.lineSpan(of: range, in: string).length == 0 {
            pendingKinds.subtract(blocks)
            return false
        }
        // At the end of a block's last line the break would fall outside it: the line typed next is kept in it.
        let end = range.location + range.length
        if let block = entities.first(where: { $0.kind.isBlock && $0.offset + $0.length == end && $0.offset <= range.location }) {
            continuingBlock = (block.kind, range.location)
        }
        return true
    }

    /// Replaces `range` with `string` as one edit, with no pending formatting: the caret ends after it.
    private func replaceText(in range: NSRange, with string: String) {
        let replaced = (text as NSString).replacingCharacters(in: range, with: string)
        let length = (string as NSString).length
        settingContents = true
        text = replaced
        settingContents = false
        entities = EntityEditing.fitted(EntityEditing.replacing(entities, range: range, with: length),
                                        to: replaced as NSString)
        pendingKinds = []
        updateQueries(caret: range.location + length)
        caretSerial += 1
        caretRequest = CaretRequest(location: range.location + length, serial: caretSerial)
    }

    /// Text set as a whole (the view's binding, a paste it reports as a whole): what changed is worked out from the
    /// two texts, the shortest change that turns one into the other, and the ranges follow it.
    private func textDidChange(from old: String) {
        if !settingContents {
            let before = Array(old.utf16)
            let after = Array(text.utf16)
            var prefix = 0
            while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < before.count - prefix, suffix < after.count - prefix,
                  before[before.count - 1 - suffix] == after[after.count - 1 - suffix] { suffix += 1 }
            applyEdit(range: NSRange(location: prefix, length: before.count - prefix - suffix),
                      length: after.count - prefix - suffix)
        }
        draftTextChanged()
    }

    private func applyEdit(range: NSRange, length: Int) {
        var updated = EntityEditing.replacing(entities, range: range, with: length)
        let caret = range.location + length
        if !pendingKinds.isEmpty {
            if range.location == pendingAt, range.length == 0, length > 0 {
                let inserted = NSRange(location: range.location, length: length)
                let string = text as NSString
                for kind in pendingKinds.sorted(by: { $0.rawValue < $1.rawValue }) {
                    updated = EntityEditing.adding(kind, in: inserted, of: string, entities: updated)
                }
                pendingAt = caret
            } else {
                pendingKinds = []
            }
        }
        // As the engine will check them: a block joined to the line before gives that line up, and so on.
        entities = EntityEditing.fitted(updated, to: text as NSString)
        if let continuing = continuingBlock {
            continuingBlock = nil
            let string = text as NSString
            if range.location == continuing.at, length > 0, caret <= string.length,
               string.substring(with: NSRange(location: range.location, length: length)).hasSuffix("\n") {
                pendingKinds = [continuing.kind]
                pendingAt = caret
            }
        }
        updateQueries(caret: caret)
    }

    private func updateQueries(caret: Int) {
        mentionQuery = query(marker: "@", caret: caret).flatMap { found in
            // Not inside a mention already made.
            entities.contains { $0.kind == .mention && $0.offset == found.range.location } ? nil : found
        }
        quickReplyQuery = quickReplies == nil ? nil : query(marker: ";", caret: caret)
    }

    /// `marker` and the letters after it up to `caret`, when the marker starts the text or follows something that
    /// isn't a letter or digit (so "ann@example" is an address, not a mention).
    private func query(marker: String, caret: Int) -> (range: NSRange, text: String)? {
        let string = text as NSString
        guard caret > 0, caret <= string.length else { return nil }
        var index = caret
        while index > 0, caret - index <= 64 {
            let piece = string.rangeOfComposedCharacterSequence(at: index - 1)
            let character = string.substring(with: piece)
            if character == marker {
                if piece.location > 0 {
                    let before = string.substring(with: string.rangeOfComposedCharacterSequence(at: piece.location - 1))
                    if before.contains(where: { $0.isLetter || $0.isNumber }) { return nil }
                }
                let start = piece.location + piece.length
                return (NSRange(location: piece.location, length: caret - piece.location),
                        string.substring(with: NSRange(location: start, length: caret - start)))
            }
            guard character.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
            index = piece.location
        }
        return nil
    }

    private static func touches(_ entity: TextEntity, _ range: NSRange) -> Bool {
        let end = range.location + range.length
        if range.length == 0 { return entity.offset <= range.location && range.location <= entity.offset + entity.length }
        return entity.offset < end && range.location < entity.offset + entity.length
    }

    /// Two texts and their ranges as one, a blank line between: the second's ranges move along.
    nonisolated static func join(_ first: (String, [TextEntity]), _ second: (String, [TextEntity])) -> (String, [TextEntity]) {
        if first.0.isEmpty { return second }
        if second.0.isEmpty { return first }
        let shift = (first.0 as NSString).length + 2
        let moved = second.1.map { entity -> TextEntity in
            var entity = entity
            entity.offset += shift
            return entity
        }
        return (first.0 + "\n\n" + second.0, (first.1 + moved).sorted(by: TextEntity.precedes))
    }

    // MARK: - Reply, edit, thread

    public func startReply(to message: QuotedMessage) {
        if isEditing { leaveEditing() }
        replyTarget = message
    }

    public func cancelReply() {
        replyTarget = nil
    }

    /// Loads a message of mine to edit: its text and formatting replace the composer's, which come back on Escape
    /// or once the edit is sent.
    public func startEditing(_ message: TimelineMessage) {
        guard message.mine, roomID != nil else { return }
        if isEditing { leaveEditing() }
        stash = currentContents
        stashedMode = mode
        mode = .editing(eventID: message.id, original: message.rich)
        setContents(message.rich.text, message.rich.entities)
        attachments = []
        replyTarget = nil
        notices = []
    }

    /// ↑ with "Edit your last message": edits my newest text message that can still be edited. Inferred (inventory
    /// 02 §1.2): "last message" is my newest message the chat lets me edit (text, sent, within its limits), not my
    /// newest message of any kind. False, doing nothing, when the setting is off, something is typed, or there is
    /// none; ↑ then does what it otherwise does.
    @discardableResult
    public func editLast(in items: [TimelineItem]) -> Bool {
        guard preferences?.upArrow == .editLast, !isEditing, trimmedText.isEmpty, attachments.isEmpty, roomID != nil
        else { return false }
        let time = now()
        for case let .message(message) in items.reversed() where message.mine {
            if MessageActions.available(for: message, in: features, network: network, now: time).actions.contains(.edit) {
                startEditing(message)
                return true
            }
        }
        return false
    }

    /// Writes in a thread: what is sent goes in it, until `endThread`.
    public func startThread(_ rootID: String) {
        if isEditing { leaveEditing() }
        mode = .thread(rootID: rootID)
    }

    public func endThread() {
        if case .thread = mode { mode = .new }
    }

    /// Back to what the composer was before the edit.
    private func leaveEditing() {
        guard isEditing else { return }
        mode = stashedMode
        let kept = stash
        stash = Contents()
        setContents(kept.text, kept.entities)
        attachments = kept.attachments
        replyTarget = kept.reply
    }

    // MARK: - Attachments

    /// Adds files to what will be sent. A folder, an unreadable file, or a file that would take the total past
    /// 90 MB is left out, and `notices` says which. While editing, they wait with what was in the composer.
    public func attach(_ urls: [URL]) {
        notices = []
        var list = isEditing ? stash.attachments : attachments
        for url in urls {
            let name = url.lastPathComponent
            if list.contains(where: { $0.url == url }) { continue }
            guard let info = fileInfo(url) else {
                notices = [.cannotRead(fileName: name)]
                continue
            }
            guard info.isRegularFile else {
                notices = [.notAFile(fileName: name)]
                continue
            }
            let total = list.reduce(Int64(0)) { $0 + $1.size }
            guard total + info.size <= Self.maxAttachmentBytes else {
                notices = [.attachmentTooLarge(fileName: name)]
                continue
            }
            list.append(ComposerAttachment(id: UUID(), url: url, size: info.size))
        }
        if isEditing { stash.attachments = list } else { attachments = list }
    }

    public func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    public func dismissNotice() {
        notices = []
    }

    public func dismissToast() {
        toast = nil
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

    /// There is text to send later, and nothing else: files and edits can't be scheduled.
    public var canSchedule: Bool {
        roomID != nil && sender != nil && !isEditing && !trimmedText.isEmpty && attachments.isEmpty
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The text as it is sent: without spaces and blank lines at either end, its ranges moved to match and cleaned
    /// as the engine checks them (richtext.Check), so nothing is sent that the engine would refuse.
    private var outgoingText: RichText {
        let string = text as NSString
        let scalars = Array(text.unicodeScalars)
        let blank = CharacterSet.whitespacesAndNewlines
        var start = 0
        for scalar in scalars {
            guard blank.contains(scalar) else { break }
            start += scalar.utf16.count
        }
        guard start < string.length else { return RichText(text: "") }
        var end = string.length
        for scalar in scalars.reversed() {
            guard blank.contains(scalar) else { break }
            end -= scalar.utf16.count
        }
        var ranges = EntityEditing.replacing(entities, range: NSRange(location: end, length: string.length - end), with: 0)
        ranges = EntityEditing.replacing(ranges, range: NSRange(location: 0, length: start), with: 0)
        let body = string.substring(with: NSRange(location: start, length: end - start))
        return RichText(text: body, entities: RichTextHTML.sendable(ranges, in: body))
    }

    /// Within what the chat's network takes, and the engine: bytes of UTF-8, not characters.
    private func fitsChat(_ body: String) -> Bool {
        body.utf8.count <= SendParams.maxTextBytes && features.fits(text: body)
    }

    /// How long a send is held for undo: the preference, with a plan that has undo send; otherwise 0.
    private var holdMillis: Int {
        guard entitlement.isEntitled(.undoSend), let millis = preferences?.undoSendMillis,
              ComposerPreferences.undoSendValues.contains(millis) else { return 0 }
        return millis
    }

    /// Sends the composer's text and files to the open chat and empties it; in edit mode, sends the edit instead.
    /// The task is done when everything has been handed to the engine (or refused, or not answered); the view does
    /// not wait for it. `archive` (⌘↩) archives the chat once it has all gone. Text longer than the chat takes is
    /// refused at once (nil), with `notices` saying why.
    @discardableResult
    public func submit(archive: Bool = false) -> Task<Void, Never>? {
        guard !isScheduling else { return nil }
        if case let .editing(eventID, original) = mode { return submitEdit(of: eventID, original: original) }
        guard canSend, let room = roomID, let sender else { return nil }
        let rich = outgoingText
        guard fitsChat(rich.text) else {
            notices = [.textTooLong]
            return nil
        }
        let draft = Contents(text: rich.text, entities: rich.entities, attachments: attachments, reply: replyTarget)
        let thread = threadRoot
        let hold = holdMillis
        setContents("", [])
        attachments = []
        replyTarget = nil
        notices = []
        onSubmit()
        return enqueue(in: room) { [weak self] in
            await self?.deliver(draft, in: room, thread: thread, hold: hold, archive: archive, with: sender)
        }
    }

    /// Runs `work` after the chat's sends before it, so a chat's messages and edits go in the order given.
    private func enqueue(in room: String, _ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = queues[room]?.task
        let token = UUID()
        let task = Task { [weak self] in
            await previous?.value
            await work()
            self?.finish(token, in: room)
        }
        queues[room] = (token, task)
        return task
    }

    /// Sends an edit, after the chat's sends before it. Unchanged, nothing is sent. The composer is back as it was
    /// before the edit at once; an edit the engine refuses comes back to be fixed, still an edit, when the composer
    /// is free for it, and otherwise into the chat's draft. An edit leaves held messages alone.
    private func submitEdit(of eventID: String, original: RichText) -> Task<Void, Never>? {
        guard let room = roomID, let sender else { return nil }
        let rich = outgoingText
        guard !rich.text.isEmpty else { return nil }
        guard fitsChat(rich.text) else {
            notices = [.textTooLong]
            return nil
        }
        notices = []
        leaveEditing()
        let unchanged = rich.text == original.text.trimmingCharacters(in: .whitespacesAndNewlines)
            && rich.entities == RichTextHTML.sendable(original.entities, in: original.text)
        guard !unchanged else { return nil }
        return enqueue(in: room) { [weak self] in
            do {
                try await sender.edit(eventID: eventID, rich: rich)
            } catch {
                guard let self else { return }
                switch Self.classify(error) {
                case let .refused(reason):
                    self.refusedEdit(eventID, original: original, rich: rich, in: room, reason: reason)
                case .unanswered:
                    self.show([.noAnswer], in: room)
                }
            }
            self?.onSettled()
        }
    }

    private func refusedEdit(_ eventID: String, original: RichText, rich: RichText, in room: String, reason: String) {
        if room == roomID, mode == .new || threadRoot != nil, trimmedText.isEmpty, attachments.isEmpty {
            stash = currentContents
            stashedMode = mode
            mode = .editing(eventID: eventID, original: original)
            setContents(rich.text, rich.entities)
            replyTarget = nil
        } else {
            _ = putBack([.text(rich)][...], reply: nil, in: room)
        }
        show([.sendFailed(reason: reason)], in: room)
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

    private func deliver(_ draft: Contents, in room: String, thread: String?, hold: Int, archive: Bool,
                         with sender: MessageSending) async {
        var items: [Outgoing] = []
        if !draft.text.isEmpty { items.append(.text(RichText(text: draft.text, entities: draft.entities))) }
        items += draft.attachments.map(Outgoing.file)
        var reply = draft.reply

        for (index, item) in items.enumerated() {
            do {
                let eventID: String
                // What was sent, kept to give back on Undo even if the engine's answer is lost.
                let copy: HeldCopy
                switch item {
                case let .text(rich):
                    eventID = try await sender.send(roomID: room, rich: rich, replyTo: reply?.eventID,
                                                    threadRoot: thread, holdMillis: hold)
                    copy = HeldCopy(text: rich.text, entities: rich.entities, reply: reply, threadRoot: thread)
                case let .file(file):
                    eventID = try await sender.sendFile(roomID: room, url: file.url, size: file.size,
                                                        replyTo: reply?.eventID, threadRoot: thread, holdMillis: hold)
                    copy = HeldCopy(attachment: file, reply: reply, threadRoot: thread)
                }
                if hold > 0 { held.add(eventID, in: room, copy: copy, holdMillis: hold) }
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
        if archive { await onArchive(room) }
        onSettled()
    }

    private static func leftOutNotice(_ names: [String]) -> [ComposerNotice] {
        names.isEmpty ? [] : [.attachmentsLeftOut(fileNames: names)]
    }

    /// Puts what was not sent back into the chat's draft. Returns the names of the files left out because the
    /// total would pass 90 MB with what was added since.
    private func putBack(_ items: ArraySlice<Outgoing>, reply: QuotedMessage?, in room: String) -> [String] {
        var unsent = Contents(reply: reply)
        for item in items {
            switch item {
            case let .text(rich):
                unsent.text = rich.text
                unsent.entities = rich.entities
            case let .file(file): unsent.attachments.append(file)
            }
        }
        guard !unsent.isEmpty else { return [] }
        if room == roomID {
            let merged = unsent.restored(into: openContents)
            openContents = merged.draft
            if isEditing { draftTextChanged() }
            return merged.leftOut
        }
        let merged = unsent.restored(into: drafts[room] ?? Contents())
        drafts[room] = merged.draft
        return merged.leftOut
    }

    /// Text that was typed somewhere else (a notification's Reply) and could not be sent: it goes into that chat's
    /// draft, so it is there when the chat opens, or straight into the composer if the chat is open.
    /// `mayHaveBeenSent`: the engine did not answer, so it may have gone; the chat says so with its usual notice.
    public func restoreUnsent(text body: String, in room: String, mayHaveBeenSent: Bool = false) {
        _ = putBack([Outgoing.text(RichText(text: body))][...], reply: nil, in: room)
        if mayHaveBeenSent { show([.noAnswer], in: room) }
    }

    /// Tells the person: now if the chat is open, otherwise with that chat's draft, for when it is.
    private func show(_ notices: [ComposerNotice], in room: String) {
        if room == roomID {
            self.notices = notices
        } else {
            var draft = drafts[room] ?? Contents()
            draft.notices = notices
            drafts[room] = draft
        }
    }

    private func showToast(_ message: String) {
        if let onToast {
            onToast(message)
        } else {
            toast = Toast(message: message, canUndo: false)
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

    // MARK: - Send later

    /// Schedules the composer's text (with its reply, in its thread) for `due`, and empties the composer once the
    /// engine has it. Without a plan that has send later, it says "Available with a plan" and nothing is sent; text
    /// longer than the chat takes is refused with why. The engine's refusal (a time in the past, say) is thrown, and
    /// the text stays. One at a time: while one is with the engine, another (or Return) does nothing.
    public func schedule(at due: Date, condition: SendLaterCondition) async throws {
        guard !isScheduling, let room = roomID, let sender else { return }
        guard entitlement.isEntitled(.sendLater) else {
            showToast(String(localized: "Available with a plan"))
            return
        }
        guard canSchedule else { return }
        let rich = outgoingText
        guard fitsChat(rich.text) else {
            notices = [.textTooLong]
            return
        }
        let typed = text
        let reply = replyTarget
        isScheduling = true
        defer { isScheduling = false }
        try await sender.schedule(roomID: room, rich: rich, replyTo: reply?.eventID, threadRoot: threadRoot,
                                  due: due, condition: condition)
        // What was scheduled leaves the composer; anything typed meanwhile stays.
        if room == roomID, !isEditing, text == typed {
            setContents("", [])
            if replyTarget == reply { replyTarget = nil }
            notices = []
        } else if room != roomID, drafts[room]?.text == typed {
            drafts[room]?.text = ""
            drafts[room]?.entities = []
            drafts[room]?.reply = nil
        }
    }

    // MARK: - Undo send

    /// The open chat's timeline, as read: my messages it shows queued are held (after a restart, say), and ones it
    /// shows otherwise are no longer; one being undone, or done with, is never brought back. An Undo whose answer was
    /// lost is settled by it (HeldMessages).
    public func updateHeld(from items: [TimelineItem]) {
        guard let room = roomID else { return }
        held.update(from: items, in: room)
    }

    /// ⌘Z: takes back my newest held message in the open chat. True when there was one. What was typed comes back
    /// into the composer (below anything typed since, after a blank line), and "Message unsent from Courier" says so.
    /// If the engine says it already went (-32025), the message's status says whether it really did (Ruling 32):
    /// "Already sent" only then; a message that didn't send says so, and the chat's Retry stands. Nothing comes back
    /// then. If the engine's answer is lost, its status decides, and the copy kept here comes back if it is gone.
    public func undoNewestHeld() async -> Bool {
        await undoHeld(nil)
    }

    /// A click on a held ("Queued") message, with "Click pending messages to undo send" on: takes that one back, as
    /// ⌘Z takes the newest. True when it was held.
    @discardableResult
    public func undoHeld(_ eventID: String?) async -> Bool {
        guard let room = roomID else { return false }
        switch await held.undoNewest(in: room, id: eventID) {
        case .nothingHeld:
            return false
        case let .undone(copy):
            restoreUndone(copy, in: room)
            showToast(String(localized: "Message unsent from Courier"))
        case let .notUndone(message):
            showToast(message)
        }
        return true
    }

    /// Returns once the lookups a timeline read started for lost Undo answers are done. For tests.
    func waitForHeldChecks() async {
        await held.waitForChecks()
    }

    /// An undone message, back in its chat's composer: a file as the attachment it was, text below what was typed
    /// since, its reply chip if none is there, and its thread if the composer is in none.
    private func restoreUndone(_ undone: HeldCopy, in room: String) {
        var current = room == roomID ? openContents : (drafts[room] ?? Contents())
        (current.text, current.entities) = Self.join((current.text, current.entities), (undone.text, undone.entities))
        current.reply = current.reply ?? undone.reply
        var leftOut: [String] = []
        if let file = undone.attachment {
            let total = current.attachments.reduce(Int64(0)) { $0 + $1.size }
            if current.attachments.contains(where: { $0.url == file.url }) {
                // Already back in the composer.
            } else if total + file.size <= Self.maxAttachmentBytes {
                current.attachments.append(file)
            } else {
                leftOut.append(file.fileName)
            }
        }
        if room == roomID {
            openContents = current
            if let root = undone.threadRoot, mode == .new { mode = .thread(rootID: root) }
            if isEditing { draftTextChanged() }
        } else {
            drafts[room] = current
        }
        if !leftOut.isEmpty { show(Self.leftOutNotice(leftOut), in: room) }
    }

    /// ⌘⇧Z: sends the open chat's held messages now. It waits for the engine's answer (a call dropped on the way
    /// would leave them to fail as "not connected"); until then, and if the call fails, they stay held, and go when
    /// their windows end.
    public func sendHeldNow() async {
        guard let room = roomID else { return }
        await held.sendNow(in: room)
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
