// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
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

    public init(id: UUID = UUID(), url: URL, size: Int64) {
        self.id = id
        self.url = url
        self.size = size
    }
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
    /// Importing a sticker or custom emoji failed.
    case importFailed(reason: String)
    /// The text is longer than the chat's network takes (`ChatFeatures.maxTextLength`, counted in bytes of UTF-8,
    /// so an emoji counts four). Nothing was sent, and the text stays to be shortened.
    case textTooLong
    /// Calm stub notice for features not available yet in Courier (`AIProvider` Talk to Type, Draft with AI, slash commands).
    case calmStub(reason: String)

    /// User-facing text shown in the notice banner under the composer.
    public var displayText: String {
        switch self {
        case let .attachmentTooLarge(name):
            String(localized: "Could not attach \(name) — total size would exceed 90 MB.")
        case let .attachmentsLeftOut(names):
            names.count == 1
                ? String(localized: "Could not put \(names[0]) back — total size would exceed 90 MB.")
                : String(localized: "Could not put \(names.count) files back — total size would exceed 90 MB: \(names.joined(separator: ", "))")
        case let .notAFile(name):
            String(localized: "Could not attach \(name). Courier can send files, not folders.")
        case let .cannotRead(name):
            String(localized: "Could not read \(name). It may have moved, or Courier may not be allowed to open it.")
        case .noAnswer:
            StatusLine.mayHaveBeenSentText
        case let .sendFailed(reason):
            reason.isEmpty ? String(localized: "The message could not be sent.")
                : String(localized: "The message could not be sent: \(reason)")
        case let .importFailed(reason):
            reason.isEmpty ? String(localized: "Could not import sticker.")
                : String(localized: "Could not import sticker: \(reason)")
        case .textTooLong:
            String(localized: "This message is too long for this chat. Shorten it, or send it in parts.")
        case let .calmStub(reason):
            reason
        }
    }
}

/// Slash command trigger surfaced in the composer when `aiPreferences.enableSlashCommands` is enabled.
public struct ComposerSlashCommand: Equatable, Sendable, Identifiable {
    public let trigger: String
    public let title: String
    public let summary: String
    public var id: String { trigger }

    public init(trigger: String, title: String, summary: String) {
        self.trigger = trigger
        self.title = title
        self.summary = summary
    }

    public static let allCommands: [ComposerSlashCommand] = [
        ComposerSlashCommand(
            trigger: "/ai",
            title: String(localized: "Ask AI"),
            summary: String(localized: "Ask contextual AI about the current conversation (Not available yet)")
        ),
        ComposerSlashCommand(
            trigger: "/draft",
            title: String(localized: "Draft with AI"),
            summary: String(localized: "Rewrite or draft a reply in this chat (Not available yet)")
        ),
        ComposerSlashCommand(
            trigger: "/summarize",
            title: String(localized: "Summarize Chat"),
            summary: String(localized: "Summarize recent messages in this chat (Not available yet)")
        ),
        ComposerSlashCommand(
            trigger: "/translate",
            title: String(localized: "Translate Draft"),
            summary: String(localized: "Translate your message draft before sending (Not available yet)")
        ),
    ]
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
    /// message.send with `disable_link_preview`.
    func send(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, holdMillis: Int,
              disableLinkPreview: Bool?) async throws -> String
    /// message.sendLocation: sends an `m.location` event.
    func sendLocation(roomID: String, latitude: Double, longitude: Double, label: String?, replyTo: String?)
        async throws -> String
    /// message.sendFile, as `send`.
    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?, threadRoot: String?, holdMillis: Int)
        async throws -> String
    /// message.sendVoice: records and sends a voice note (.m4a/OGG Opus) with duration and waveform bars.
    func sendVoice(roomID: String, url: URL, durationMS: Int64, waveform: [Int], replyTo: String?) async throws -> String
    /// message.edit.
    func edit(eventID: String, rich: RichText) async throws
    /// message.schedule.
    func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date,
                  condition: SendLaterCondition) async throws
    /// message.schedule with `disable_link_preview`.
    func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date,
                  condition: SendLaterCondition, disableLinkPreview: Bool?) async throws
    /// message.undo: the held message's text, ranges and reply, given back.
    func undo(eventID: String) async throws -> Draft
    /// message.sendHeld: a chat's held messages now, or with nil every chat's.
    func sendHeld(roomID: String?) async throws
    /// room.members: the people whose name matches what was typed after "@".
    func members(roomID: String, query: String) async throws -> [Member]
    /// A message's status line as the engine has it now, read in `thread` for a thread reply (the chat's own
    /// timeline leaves those out); nil when it isn't there (it was undone or deleted). Throws when it can't be read.
    func status(of eventID: String, in roomID: String, thread: String?) async throws -> StatusLine?
    /// room.setTyping: I am typing in the chat, or I stopped. Best effort: the engine tells a network that is down
    /// nothing, and that is no error.
    func setTyping(roomID: String, typing: Bool) async throws
    /// room.setUnreadFrom: the chat's unread count runs from this message on (the engine finds its chat), on this
    /// Mac only.
    func setUnreadFrom(eventID: String) async throws
    /// room.directChat: the one-to-one chat with `userID`, a person in the group `roomID`, found or made. Returns its
    /// room ID.
    func directChat(roomID: String, userID: String) async throws -> String
    /// stickers.list: returns installed and recent sticker packs plus recent GIFs.
    func listStickers(refreshBridgePacks: Bool) async throws -> StickersListResult
    /// stickers.import: imports a local image file into the local sticker/emoji catalog.
    func importSticker(_ params: StickersImportParams) async throws -> StickerItemWire
    /// message.sendSticker: sends an `m.sticker` event to `params.roomID`.
    func sendSticker(_ params: MessageSendStickerParams) async throws -> String
    /// message.sendGIF: sends an animated GIF/MP4 (`fi.mau.gif: true`) to `params.roomID`.
    func sendGIF(_ params: MessageSendGIFParams) async throws -> String
}

extension MessageSending {
    /// A sender with nowhere to keep drafts keeps none.
    public func saveDraft(roomID: String, text: String) async throws {}

    public func send(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, holdMillis: Int,
                     disableLinkPreview _: Bool?) async throws -> String {
        try await send(roomID: roomID, rich: rich, replyTo: replyTo, threadRoot: threadRoot, holdMillis: holdMillis)
    }

    public func sendLocation(roomID _: String, latitude _: Double, longitude _: Double, label _: String?,
                             replyTo _: String?) async throws -> String {
        ""
    }

    public func sendVoice(roomID: String, url: URL, durationMS: Int64, waveform: [Int], replyTo: String?) async throws
        -> String {
        ""
    }

    public func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date,
                         condition: SendLaterCondition, disableLinkPreview _: Bool?) async throws {
        try await schedule(roomID: roomID, rich: rich, replyTo: replyTo, threadRoot: threadRoot, due: due,
                           condition: condition)
    }

    public func listStickers(refreshBridgePacks _: Bool) async throws -> StickersListResult {
        StickersListResult()
    }

    public func importSticker(_ params: StickersImportParams) async throws -> StickerItemWire {
        StickerItemWire(
            id: "imported:stub",
            packID: "imported",
            shortcode: params.shortcode,
            name: params.name ?? "Sticker",
            emoji: params.emoji,
            mediaURL: "courier://media/stub",
            mimeType: "image/png",
            usage: params.usage ?? ["sticker"]
        )
    }

    public func sendSticker(_: MessageSendStickerParams) async throws -> String {
        ""
    }

    public func sendGIF(_: MessageSendGIFParams) async throws -> String {
        ""
    }
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
    /// ":" plus 2+ shortcode characters at the caret when emoji autocomplete is enabled.
    @Published public private(set) var emojiQuery: String?
    /// The UTF-16 range of the active `:shortcode` token (including the leading `:`).
    public private(set) var emojiQueryRange: NSRange?
    /// Range of a `:shortcode` token dismissed with Escape so a repeated selection report at the same caret does not reopen it.
    private var dismissedEmojiRange: NSRange?
    /// Matching emoji candidates for `emojiQuery`.
    @Published public private(set) var emojiCandidates: [EmojiCandidate] = []
    /// Highlighted row in the emoji autocomplete popover.
    @Published public var selectedEmojiIndex: Int = 0
    /// Custom emoji candidates from installed packs, merged into `EmojiCatalog.shared.search`.
    public var customEmojis: [EmojiCandidate] = []
    /// Sticker packs loaded from `stickers.list` (`Recent`, `Imported`, and bridge packs).
    @Published public private(set) var stickerPacks: [StickerPackWire] = []
    /// Recent GIF items loaded from `stickers.list`.
    @Published public private(set) var recentGIFs: [StickerItemWire] = []
    /// Selected pack tab in `StickerPickerPopover`.
    @Published public var selectedStickerPackID: String = "recent"
    /// Search query in `StickerPickerPopover`.
    @Published public var stickerSearchQuery: String = ""
    /// Optional thumbnail loader used to render custom emoji, sticker, and GIF previews.
    public var thumbnailLoader: ThumbnailLoader?
    /// Offline GIF provider (StubGIFProvider in Iteration 1; zero network calls).
    public var gifProvider: any GIFProvider = StubGIFProvider()
    /// Offline AI provider (UnavailableAIProvider in Iteration 1; zero network calls).
    public var aiProvider: any AIProvider = UnavailableAIProvider()
    /// Local AI preferences (`AIPreferences`).
    public var aiPreferences: AIPreferences = AIPreferences()
    @Published public var isEmojiPickerPresented: Bool = false
    @Published public var isStickerPickerPresented: Bool = false
    @Published public var isGIFPickerPresented: Bool = false
    @Published public var gifSearchQuery: String = ""
    /// A GIF staged in the composer when `preferences.autoSendGIFs == false`.
    @Published public var pendingGIF: StickerItemWire?
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
    /// The composer's text view has the keyboard, in the key window: only then do the Message menu's formatting
    /// items act on `selection`. The view tells it.
    @Published public var hasKeyboard = false
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
    public var preferences: ComposerPreferences? {
        didSet { observePreferences() }
    }
    public var quickReplies: QuickReplies?
    /// Shared hotkey registry for checking "Send Message", "Insert New Line", and "Message: Quote or Edit Selected Message".
    public weak var hotkeys: HotkeyRegistry?
    /// Shared live shortcut dispatcher for composer return-key shortcuts.
    public weak var hotkeyDispatcher: HotkeyDispatcher?
    /// The composer's voice-note recorder.
    public let voiceRecorder: VoiceRecorderModel
    /// Called when a send is done, whether it worked or not, so the chat can read what the engine has.
    public var onSettled: @MainActor () -> Void = {}
    /// Called when something is submitted, before it is sent.
    public var onSubmit: @MainActor () -> Void = {}
    /// Called for each message the engine took (its event ID), held or not: the chat knows a reply of mine is on
    /// its way, wherever the chat shows (`ConversationModel`, Incognito's "until I reply").
    public var onSent: @MainActor (_ roomID: String, _ eventID: String) -> Void = { _, _ in }
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
    /// Whether my typing may reach the chat: the "Show recipients I'm typing" preference, which Incognito's Hide
    /// Typing turns off (Task 9 wires it). Asked at every change; turned off while I type, the stop goes at the next
    /// keystroke or at the end of the 5 s rest, whichever comes first.
    public var sendsTyping: @MainActor () -> Bool = { true }

    /// While the text keeps changing, room.setTyping true goes again this often: protocol.json's
    /// `conventions.typing_repeat_ms`. Inferred (inventory 01 §5): the bridges hand a start on once and the networks
    /// time it out, Telegram after about 5 s; the engine counts a pulse a second early as a new start.
    public nonisolated static let typingRepeat: TimeInterval = TimeInterval(CourierProtocol.typingRepeatMillis) / 1000
    /// After this long with no change, room.setTyping false goes (Inferred (inventory 01 §5)).
    public nonisolated static let typingStopAfter: TimeInterval = 5

    /// One chat's composer, kept while another is open.
    private struct Contents {
        var text = ""
        var entities: [TextEntity] = []
        var attachments: [ComposerAttachment] = []
        var pendingGIF: StickerItemWire?
        var reply: QuotedMessage?
        /// Notices about a send in a chat that was not open when it ended: shown when it is opened.
        var notices: [ComposerNotice] = []

        var isEmpty: Bool {
            text.isEmpty && attachments.isEmpty && pendingGIF == nil && reply == nil && notices.isEmpty
        }

        /// What was refused, back above what has been typed since. The files that were refused come first; any
        /// added since that would take the total past 90 MB are left out, and their names are returned.
        func restored(into current: Contents) -> (draft: Contents, leftOut: [String]) {
            var merged = current
            (merged.text, merged.entities) = ComposerModel.join((text, entities), (current.text, current.entities))
            merged.pendingGIF = current.pendingGIF ?? pendingGIF
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
        case gif(StickerItemWire, caption: RichText?)
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
    private var preferencesCancellable: AnyCancellable?
    private var lockCancellable: AnyCancellable?
    private weak var observedLifecycle: SystemLifecycleModel?
    private var initialStickerLoadStarted = false
    private var stickerLoadGeneration = 0
    /// My held messages, by chat, and what Undo does with them.
    private let held = HeldMessages()

    public var lifecycle: SystemLifecycleModel {
        observedLifecycle
            ?? hotkeyDispatcher?.lifecycle
            ?? AppLockGate.shared.lifecycle
    }

    public var isLocked: Bool {
        if !AppLockGate.shared.canPerform(.send, lifecycle: lifecycle) {
            return true
        }
        if let hotkeys, hotkeys.isLocked {
            return true
        }
        return false
    }

    /// Dismisses the link dialog request.
    public func dismissLinkRequest() {
        linkRequest = nil
    }

    /// Dismisses every active popover, picker, dialog, and recording state owned by this composer.
    public func dismissAllPresentations() {
        isEmojiPickerPresented = false
        isStickerPickerPresented = false
        isGIFPickerPresented = false
        linkRequest = nil
        mentionQuery = nil
        quickReplyQuery = nil
        dismissEmojiAutocomplete()
        if voiceRecorder.state != .idle {
            voiceRecorder.cancelImmediately()
        }
        stopTyping()
    }

    // Typing.
    /// The chat a start was sent to and no stop yet; nil while I'm not typing anywhere.
    private var typingRoom: String?
    /// When the last start went.
    private var lastTypingPulse: Date?
    /// Goes up with each change and each stop: a rest that finds it moved on sends nothing.
    private var typingToken = 0
    /// room.setTyping calls go one after another, in order, so a stop never overtakes its start.
    private var typingSends: Task<Void, Never>?
    /// Waits out `typingStopAfter`; tests give one they release.
    private let typingSleep: @Sendable (TimeInterval) async -> Void

    /// - Parameters:
    ///   - draftDelay: how long after the last keystroke the draft is saved, in seconds.
    ///   - sleep: waits `draftDelay`; tests give one they can open.
    ///   - preferences: the composer's settings (undo send, ↑); nil is every default.
    ///   - entitlement: whether the plan has undo send and send later. A send is held only with it; with none given,
    ///     there is no plan.
    ///   - now: the time now, for what ↑ and Return may edit, when a held message's window ends and when typing goes
    ///     again; tests give their own.
    ///   - typingSleep: waits out `typingStopAfter` after the last change, before the stop goes; tests give one they
    ///     release.
    public init(sender: MessageSending? = nil, fileInfo: @escaping (URL) -> ComposerFileInfo? = ComposerModel.readFileInfo,
                draftDelay: TimeInterval = 1,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { await waitForInboxWindow($0) },
                preferences: ComposerPreferences? = nil, entitlement: any EntitlementProvider = NoPlan(),
                quickReplies: QuickReplies? = nil, now: @escaping @MainActor () -> Date = Date.init,
                typingSleep: @escaping @Sendable (TimeInterval) async -> Void = { await waitForInboxWindow($0) },
                voiceRecorder: VoiceRecorderModel? = nil) {
        self.typingSleep = typingSleep
        self.sender = sender
        self.fileInfo = fileInfo
        self.draftDelay = draftDelay
        self.sleep = sleep
        self.preferences = preferences
        self.entitlement = entitlement
        self.quickReplies = quickReplies
        self.now = now
        self.voiceRecorder = voiceRecorder ?? VoiceRecorderModel()
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
        lockCancellable = NotificationCenter.default.publisher(for: SystemLifecycleModel.didLockNotification)
            .sink { [weak self] notification in
                guard let self else { return }
                if let lifecycle = notification.object as? SystemLifecycleModel {
                    self.observedLifecycle = lifecycle
                }
                self.dismissAllPresentations()
            }
        observePreferences()
    }

    private func observePreferences() {
        preferencesCancellable = preferences?.$enableEmojiAutocomplete
            .sink { [weak self] enabled in
                guard let self, !enabled else { return }
                self.dismissEmojiAutocomplete()
            }
        if preferences?.enableEmojiAutocomplete == false {
            dismissEmojiAutocomplete()
        }
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
        guard !isLocked else { return .send }
        if let dispatcher = hotkeyDispatcher, dispatcher.lifecycle.isLocked {
            return .send
        }
        let resolvedHotkeys = hotkeyDispatcher?.hotkeys ?? hotkeys
        if let resolvedHotkeys {
            guard !resolvedHotkeys.isLocked else { return .send }
            let chord = KeyChord(
                key: "enter",
                command: modifiers.contains(.command),
                shift: modifiers.contains(.shift),
                option: modifiers.contains(.option),
                control: modifiers.contains(.control)
            )
            if resolvedHotkeys.chords(for: "Insert New Line").contains(chord) {
                return .newline
            }
            if voiceRecorder.isRecordingOrReviewing {
                guard resolvedHotkeys.chords(for: "Send Message").contains(chord) else { return .send }
                Task { [weak self] in
                    guard let self else { return }
                    await self.voiceRecorder.stopAndSend(using: self)
                }
                return .send
            }
            if actsOnSelectedMessage, trimmedText.isEmpty, attachments.isEmpty, pendingGIF == nil,
               let selected = selectedMessage() {
                if resolvedHotkeys.chords(for: "Message: Quote or Edit Selected Message").contains(chord) {
                    act(on: selected)
                } else if resolvedHotkeys.chords(for: "Send Message").contains(chord) {
                    submit()
                }
                return .send
            }
            if resolvedHotkeys.chords(for: "Send Message").contains(chord) {
                submit()
            }
            return .send
        }

        let action = Self.action(forReturn: modifiers)
        guard action == .send else { return action }
        if voiceRecorder.isRecordingOrReviewing {
            Task { [weak self] in
                guard let self else { return }
                await self.voiceRecorder.stopAndSend(using: self)
            }
            return action
        }
        if actsOnSelectedMessage, trimmedText.isEmpty, attachments.isEmpty, pendingGIF == nil,
               let selected = selectedMessage() {
            act(on: selected)
        } else {
            submit()
        }
        return action
    }

    /// Escape ends an edit (what was in the composer comes back), or else clears the reply chip. False when there
    /// was neither, so the key can do something else.
    public func escape() -> Bool {
        if emojiQuery != nil {
            dismissEmojiAutocomplete()
            return true
        }
        if isStickerPickerPresented {
            isStickerPickerPresented = false
            return true
        }
        if isGIFPickerPresented {
            isGIFPickerPresented = false
            return true
        }
        if voiceRecorder.state != .idle {
            voiceRecorder.cancelImmediately()
            return true
        }
        if isEditing {
            leaveEditing()
            return true
        }
        guard replyTarget != nil else { return false }
        replyTarget = nil
        return true
    }

    /// The thread pane's composer (`ThreadModel` sets it): always in its thread, and Return in it, empty, acts on
    /// the message selected in the pane.
    var isThreadPaneComposer = false

    /// Return in an empty composer acts on the selected message: in the chat's composer writing a new message, and
    /// in the thread pane's (`ThreadPane` gives it the pane's selection).
    private var actsOnSelectedMessage: Bool {
        switch mode {
        case .new: true
        case .thread: isThreadPaneComposer
        case .editing: false
        }
    }

    private func act(on message: TimelineMessage) {
        let offered = MessageActions.available(for: message, in: features, network: network, now: now()).actions
        if offered.contains(.edit) {
            startEditing(message)
        } else if offered.contains(.reply) {
            startReply(to: message.quoted)
        } else if offered.contains(.replyInThread), !isThreadPaneComposer {
            // Not from the thread pane: its composer stays in the thread it is open on.
            startThread(message.id)
        }
    }

    // MARK: - Chats and drafts

    /// Opens a chat's composer: the open chat's draft is kept (and saved at once if the engine doesn't have it),
    /// and this chat's comes back: the one in memory, or with none, the engine's. An edit under way ends, and a
    /// thread is left.
    public func open(_ room: String?) {
        guard room != roomID else { return }
        if voiceRecorder.state != .idle {
            voiceRecorder.cancelImmediately()
        }
        isStickerPickerPresented = false
        isGIFPickerPresented = false
        isEmojiPickerPresented = false
        dismissEmojiAutocomplete()
        stopTyping() // leaving the chat
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
        pendingGIF = draft.pendingGIF
        replyTarget = draft.reply
        notices = draft.notices
        heldIDs = room.map { held.ids(in: $0) } ?? []
        if let room {
            drafts[room]?.notices = [] // shown now, once
            if stickerPacks.isEmpty, !initialStickerLoadStarted, sender != nil {
                initialStickerLoadStarted = true
                Task { [weak self] in
                    guard let self, self.stickerLoadGeneration == 0, self.stickerPacks.isEmpty else { return }
                    await self.loadStickers(refresh: false)
                }
            }
        }
    }

    private var currentContents: Contents {
        Contents(
            text: text,
            entities: entities,
            attachments: attachments,
            pendingGIF: pendingGIF,
            reply: replyTarget
        )
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
                pendingGIF = newValue.pendingGIF
                replyTarget = newValue.reply
            }
        }
    }

    /// Sets the text and its ranges together, as one change. It is never typing (`settingContents` keeps
    /// `textDidChange` from calling `typingChanged`): a quote, an edit loaded or left, a refused edit put back and a
    /// draft coming back are the composer's own text, not the person's (testTextTheComposerPutsInIsNotTyping).
    private func setContents(_ newText: String, _ newEntities: [TextEntity]) {
        settingContents = true
        text = newText
        settingContents = false
        entities = newEntities
        pendingKinds = []
        mentionQuery = nil
        quickReplyQuery = nil
        emojiQuery = nil
        emojiQueryRange = nil
        dismissedEmojiRange = nil
        emojiCandidates = []
        selectedEmojiIndex = 0
        selection = NSRange(location: (newText as NSString).length, length: 0)
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
        guard !isLocked, !openingChat, let room = roomID, !unknownDrafts.contains(room) else { return }
        draftToken += 1
        guard draftBody != (savedTexts[room] ?? "") else { return } // back to what the engine has: nothing to save
        let token = draftToken
        Task { [weak self, sleep, draftDelay] in
            await sleep(draftDelay)
            guard let self, !self.isLocked, self.draftToken == token, self.roomID == room else { return }
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
        guard !isLocked else { return }
        settingContents = true
        self.text = text
        settingContents = false
        applyEdit(range: range, length: length)
        typingChanged()
    }

    /// The caret or selection moved. A pending formatting key holds only where it was pressed.
    public func selectionChanged(to range: NSRange) {
        selection = range
        if range.length > 0 || range.location != pendingAt { pendingKinds = [] }
        if range.length > 0 {
            mentionQuery = nil
            quickReplyQuery = nil
            emojiQuery = nil
            emojiQueryRange = nil
            emojiCandidates = []
            selectedEmojiIndex = 0
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
        guard !isLocked, roomID != nil else { return false }
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
        guard !isLocked else { return }
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

    /// Puts a kept draft back (the thread pane's, on reopening the thread): the composer's own text, so it is not
    /// typing and no emoticon in it is replaced.
    public func restoreDraft(_ rich: RichText) {
        setContents(rich.text, rich.entities)
    }

    /// "Insert as Draft" on someone else's message: its text and formatting go into the composer, below what is
    /// typed (after a blank line), so nothing typed is lost. While editing, it waits with what was there before.
    public func insertAsDraft(_ rich: RichText) {
        guard !isLocked, roomID != nil, !rich.text.isEmpty else { return }
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
        let newCaret = range.location + length
        selection = NSRange(location: newCaret, length: 0)
        updateQueries(caret: newCaret)
        caretSerial += 1
        caretRequest = CaretRequest(location: newCaret, serial: caretSerial)
    }

    // MARK: - Emoji Autocomplete

    /// Moves the highlighted emoji candidate by `delta`, wrapping around `emojiCandidates`.
    public func moveEmojiSelection(_ delta: Int) {
        guard !emojiCandidates.isEmpty else {
            selectedEmojiIndex = 0
            return
        }
        let count = emojiCandidates.count
        selectedEmojiIndex = ((selectedEmojiIndex + delta) % count + count) % count
    }

    /// Replaces the active `:shortcode` token (or inserts at `selection`) with `candidate` and clears autocomplete.
    public func pickEmoji(_ candidate: EmojiCandidate) {
        let replacement = candidate.glyph.map { "\($0) " } ?? ":\(candidate.shortcode): "
        let string = text as NSString
        let targetRange: NSRange
        if let active = emojiQueryRange,
           active.location >= 0,
           active.location + active.length <= string.length {
            targetRange = active
        } else if selection.location >= 0,
                  selection.location + selection.length <= string.length {
            targetRange = selection
        } else {
            targetRange = NSRange(location: string.length, length: 0)
        }
        replaceText(in: targetRange, with: replacement)
        dismissEmojiAutocomplete()
    }

    /// Dismisses the `:shortcode:` autocomplete popover without altering composer text.
    public func dismissEmojiAutocomplete() {
        if let active = emojiQueryRange {
            dismissedEmojiRange = active
        }
        emojiQuery = nil
        emojiQueryRange = nil
        emojiCandidates = []
        selectedEmojiIndex = 0
    }

    /// Explicitly opens `:shortcode:` autocomplete at the current selection or presents the emoji picker.
    public func openEmojiAutocomplete() {
        isStickerPickerPresented = false
        isGIFPickerPresented = false
        dismissedEmojiRange = nil
        let caret = min(max(selection.location, 0), (text as NSString).length)
        if let found = shortcodeQuery(caret: caret, minLength: 1) {
            emojiQueryRange = found.range
            emojiQuery = found.text
            emojiCandidates = EmojiCatalog.shared.search(found.text, custom: customEmojis, limit: 8)
            selectedEmojiIndex = 0
            isEmojiPickerPresented = false
        } else {
            isEmojiPickerPresented = false
        }
    }

    /// Text set as a whole (the view's binding, a paste it reports as a whole): what changed is worked out from the
    /// two texts, the shortest change that turns one into the other, and the ranges follow it.
    private func textDidChange(from old: String) {
        if !settingContents, !openingChat, isLocked {
            settingContents = true
            text = old
            settingContents = false
            return
        }
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
            typingChanged()
        }
        if text.isEmpty { stopTyping() } // an emptied box, however it was emptied
        draftTextChanged()
    }

    private func applyEdit(range: NSRange, length: Int) {
        dismissedEmojiRange = nil
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
        let preEditString = text as NSString
        let insertedEndsWithNewline = length > 0
            && caret <= preEditString.length
            && preEditString.substring(with: NSRange(location: range.location, length: length)).hasSuffix("\n")
        var currentEntities = EntityEditing.fitted(updated, to: preEditString)
        var effectiveCaret = caret

        if !openingChat,
           length > 0,
           !(preferences?.disableEmoticonReplacement ?? false),
           effectiveCaret <= preEditString.length {
            let prefix = preEditString.substring(to: effectiveCaret)
            if let match = EmojiCatalog.trailingEmoticonReplacement(in: prefix),
               !currentEntities.contains(where: { [.code, .pre, .link].contains($0.kind) && Self.touches($0, match.range) }) {
                let replaced = preEditString.replacingCharacters(in: match.range, with: match.replacement)
                let glyphLength = (match.replacement as NSString).length
                settingContents = true
                text = replaced
                settingContents = false
                currentEntities = Self.adjustingEntitiesForEmoticon(
                    currentEntities,
                    replacing: match.range,
                    with: glyphLength,
                    in: replaced as NSString
                )
                let delta = glyphLength - match.range.length
                effectiveCaret += delta
                if !pendingKinds.isEmpty {
                    pendingAt = effectiveCaret
                }
                caretSerial += 1
                caretRequest = CaretRequest(location: effectiveCaret, serial: caretSerial)
            }
        }

        entities = currentEntities
        if let continuing = continuingBlock {
            continuingBlock = nil
            let string = text as NSString
            if range.location == continuing.at, insertedEndsWithNewline, effectiveCaret <= string.length {
                pendingKinds = [continuing.kind]
                pendingAt = effectiveCaret
            }
        }
        selection = NSRange(location: effectiveCaret, length: 0)
        updateQueries(caret: effectiveCaret)
    }

    private static func adjustingEntitiesForEmoticon(
        _ entities: [TextEntity],
        replacing range: NSRange,
        with glyphLength: Int,
        in text: NSString
    ) -> [TextEntity] {
        let start = range.location
        let end = range.location + range.length
        let delta = glyphLength - range.length
        var adjusted: [TextEntity] = []
        for var entity in entities {
            let first = entity.offset
            let last = entity.offset + entity.length
            if last <= start {
                // Entirely before the emoticon token.
            } else if end <= first {
                entity.offset += delta
            } else if first <= start, end <= last, entity.kind != .mention {
                entity.length += delta
            } else {
                continue
            }
            if entity.length > 0 {
                adjusted.append(entity)
            }
        }
        return EntityEditing.fitted(adjusted.sorted(by: TextEntity.precedes), to: text)
    }

    private func updateQueries(caret: Int) {
        mentionQuery = query(marker: "@", caret: caret).flatMap { found in
            // Not inside a mention already made.
            entities.contains { $0.kind == .mention && $0.offset == found.range.location } ? nil : found
        }
        quickReplyQuery = quickReplies == nil ? nil : query(marker: ";", caret: caret)
        if preferences?.enableEmojiAutocomplete ?? true,
           let found = shortcodeQuery(caret: caret, minLength: 2),
           found.range != dismissedEmojiRange {
            let previousQuery = emojiQuery
            emojiQueryRange = found.range
            emojiQuery = found.text
            emojiCandidates = EmojiCatalog.shared.search(found.text, custom: customEmojis, limit: 8)
            if previousQuery != found.text || selectedEmojiIndex >= emojiCandidates.count {
                selectedEmojiIndex = 0
            }
        } else {
            if shortcodeQuery(caret: caret, minLength: 2)?.range != dismissedEmojiRange {
                dismissedEmojiRange = nil
            }
            emojiQuery = nil
            emojiQueryRange = nil
            emojiCandidates = []
            selectedEmojiIndex = 0
        }
    }

    /// Scans backwards from `caret` for a `:shortcode` token preceded by start-of-text or whitespace/newline,
    /// outside `.code`, `.pre`, `.link` entities and inline backtick code spans.
    private func shortcodeQuery(caret: Int, minLength: Int) -> (range: NSRange, text: String)? {
        let string = text as NSString
        guard caret > 0, caret <= string.length else { return nil }
        var index = caret
        while index > 0, caret - index <= 64 {
            let piece = string.rangeOfComposedCharacterSequence(at: index - 1)
            let character = string.substring(with: piece)
            if character == ":" {
                if piece.location > 0 {
                    let before = string.substring(with: string.rangeOfComposedCharacterSequence(at: piece.location - 1))
                    if !before.allSatisfy({ $0.isWhitespace || $0.isNewline }) { return nil }
                }
                let tokenRange = NSRange(location: piece.location, length: caret - piece.location)
                if entities.contains(where: { [.code, .pre, .link].contains($0.kind) && Self.touches($0, tokenRange) }) {
                    return nil
                }
                let prefixBeforeColon = string.substring(to: piece.location)
                let backtickCount = prefixBeforeColon.reduce(into: 0) { count, ch in
                    if ch == "`" { count += 1 }
                }
                if backtickCount % 2 != 0 { return nil }
                let start = piece.location + piece.length
                let shortcode = string.substring(with: NSRange(location: start, length: caret - start))
                guard shortcode.count >= minLength else { return nil }
                if EmojiCatalog.isEmoticon(":" + shortcode) {
                    return nil
                }
                if shortcode.hasPrefix("-"), shortcode != "-1" {
                    return nil
                }
                return (tokenRange, shortcode)
            }
            guard character.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "+" }) else {
                return nil
            }
            index = piece.location
        }
        return nil
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

    // MARK: - Typing

    /// The person changed the text: a start goes at the first change and again every `typingRepeat` while the text
    /// keeps changing, and a stop `typingStopAfter` after the last change. Nothing goes while `sendsTyping` says no
    /// (a start already sent is stopped), or for an empty box. Only changes the person makes count: a draft coming
    /// back, an undone message or a quote put in is not typing.
    private func typingChanged() {
        guard !openingChat, let room = roomID else { return }
        guard !isLocked, !text.isEmpty, sendsTyping() else {
            stopTyping()
            return
        }
        let time = now()
        if typingRoom != room || lastTypingPulse.map({ time.timeIntervalSince($0) >= Self.typingRepeat }) ?? true {
            if let other = typingRoom, other != room { stopTyping() }
            typingRoom = room
            lastTypingPulse = time
            sendTyping(true, in: room)
        }
        typingToken += 1
        let token = typingToken
        Task { [weak self, typingSleep] in
            await typingSleep(Self.typingStopAfter)
            guard let self, self.typingToken == token else { return }
            self.stopTyping()
        }
    }

    /// Quitting: tells the chat I stopped typing, if a start was sent (`stopTyping`). `waitForTyping` returns once it
    /// has been handed to the engine.
    public func endTyping() {
        stopTyping()
    }

    /// Tells the chat a start sent is over: on a rest, on send, on an emptied box and on leaving the chat. Nothing
    /// when no start was sent.
    private func stopTyping() {
        typingToken += 1 // a rest under way sends nothing more
        guard let room = typingRoom else { return }
        typingRoom = nil
        lastTypingPulse = nil
        sendTyping(false, in: room)
    }

    private func sendTyping(_ typing: Bool, in room: String) {
        guard let sender else { return }
        let previous = typingSends
        typingSends = Task {
            await previous?.value
            // Best effort: one that doesn't go is never retried; the network times a start out by itself.
            try? await sender.setTyping(roomID: room, typing: typing)
        }
    }

    /// Returns once every room.setTyping asked for so far has been handed to the sender. For tests.
    func waitForTyping() async {
        await typingSends?.value
    }

    // MARK: - Reply Privately

    /// Reply Privately, in the one-to-one chat that just opened: the message goes into the composer quoted, as a
    /// quote range where the chat keeps them (`features`), else as "> " lines, then a blank line, with the caret
    /// after it. A draft the chat already has stays, above it. Inferred (inventory 01 §7): a Matrix reply can't
    /// point across chats, so the quote is text.
    public func startPrivateReply(quoting message: TimelineMessage, in features: ChatFeatures) {
        guard roomID != nil else { return }
        if isEditing { leaveEditing() }
        let words = message.body.isEmpty ? message.fileName : message.body
        guard !words.isEmpty else { return }
        let quote: (String, [TextEntity])
        if features.keeps(.blockquote) {
            quote = (words, [TextEntity(kind: .blockquote, offset: 0, length: (words as NSString).length)])
        } else {
            let lines = words.components(separatedBy: "\n").map { "> " + $0 }
            quote = (lines.joined(separator: "\n"), [])
        }
        let (body, ranges) = Self.join((text, entities), quote)
        let joined = body + "\n\n"
        setContents(joined, ranges)
        caretSerial += 1
        caretRequest = CaretRequest(location: (joined as NSString).length, serial: caretSerial)
    }

    // MARK: - Reply, edit, thread

    public func startReply(to message: QuotedMessage) {
        guard !isLocked else { return }
        if isEditing { leaveEditing() }
        replyTarget = message
    }

    public func cancelReply() {
        replyTarget = nil
    }

    /// Loads a message of mine to edit: its text and formatting replace the composer's, which come back on Escape
    /// or once the edit is sent.
    public func startEditing(_ message: TimelineMessage) {
        guard !isLocked, message.mine, roomID != nil else { return }
        if isEditing { leaveEditing() }
        isStickerPickerPresented = false
        isGIFPickerPresented = false
        isEmojiPickerPresented = false
        dismissEmojiAutocomplete()
        stash = currentContents
        stashedMode = mode
        mode = .editing(eventID: message.id, original: message.rich)
        setContents(message.rich.text, message.rich.entities)
        attachments = []
        pendingGIF = nil
        replyTarget = nil
        notices = []
    }

    /// ↑ with "Edit your last message": edits my newest text message that can still be edited. Inferred (inventory
    /// 02 §1.2): "last message" is my newest message the chat lets me edit (text, sent, within its limits), not my
    /// newest message of any kind. False, doing nothing, when the setting is off, something is typed, or there is
    /// none; ↑ then does what it otherwise does.
    @discardableResult
    public func editLast(in items: [TimelineItem]) -> Bool {
        guard !isLocked,
              preferences?.upArrow == .editLast, !isEditing, trimmedText.isEmpty, attachments.isEmpty,
              pendingGIF == nil, roomID != nil
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
        guard !isLocked else { return }
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
        pendingGIF = kept.pendingGIF
        replyTarget = kept.reply
    }

    // MARK: - Attachments

    /// Adds files to what will be sent. A folder, an unreadable file, or a file that would take the total past
    /// 90 MB is left out, and `notices` says which. While editing, they wait with what was in the composer.
    public func attach(_ urls: [URL]) {
        guard !isLocked else { return }
        notices = []
        var list = isEditing ? stash.attachments : attachments
        for url in urls where url.isFileURL {
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

    /// There is something to send: some text that is not only spaces, a file, or a staged GIF.
    public var canSend: Bool {
        roomID != nil && sender != nil && (!trimmedText.isEmpty || !attachments.isEmpty || pendingGIF != nil)
    }

    /// There is text to send later, and nothing else: files, GIFs, and edits can't be scheduled.
    public var canSchedule: Bool {
        roomID != nil && sender != nil && !isEditing && !trimmedText.isEmpty && attachments.isEmpty && pendingGIF == nil
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

    /// Sends the composer's text, staged GIF, and files to the open chat and awaits completion.
    public func send(archive: Bool = false) async {
        await submit(archive: archive)?.value
    }

    /// Sends the composer's text and files to the open chat and empties it; in edit mode, sends the edit instead.
    /// The task is done when everything has been handed to the engine (or refused, or not answered); the view does
    /// not wait for it. `archive` (⌘↩) archives the chat once it has all gone. Text longer than the chat takes is
    /// refused at once (nil), with `notices` saying why.
    @discardableResult
    public func submit(archive: Bool = false) -> Task<Void, Never>? {
        guard !isLocked, !isScheduling else { return nil }
        if case let .editing(eventID, original) = mode { return submitEdit(of: eventID, original: original) }
        if attachments.isEmpty, roomID != nil,
           trimmedText == "/gif" || trimmedText.hasPrefix("/gif ") {
            guard canSendGIF else {
                let netName = NetworkNames.displayName(of: network)
                    ?? (network.isEmpty ? String(localized: "this chat") : network)
                notices = [
                    .sendFailed(
                        reason: String(
                            format: String(localized: "GIFs are not supported on %@."),
                            netName
                        )
                    ),
                ]
                return nil
            }
            let query = trimmedText == "/gif"
                ? ""
                : String(trimmedText.dropFirst("/gif ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            stopTyping()
            setContents("", [])
            notices = []
            _ = openGIFPicker(query: query)
            return nil
        }
        if attachments.isEmpty, pendingGIF == nil, trimmedText == "/voice", roomID != nil {
            stopTyping()
            setContents("", [])
            notices = []
            return Task { [weak self] in
                await self?.startVoiceRecording()
            }
        }
        if attachments.isEmpty, pendingGIF == nil, features.locationSupported,
           let coordinate = GeoCoordinate.parseLocationCommand(trimmedText),
           let room = roomID, let sender {
            let reply = replyTarget
            let rawText = trimmedText
            stopTyping()
            setContents("", [])
            replyTarget = nil
            notices = []
            onSubmit()
            return enqueue(in: room) { [weak self] in
                await self?.deliverLocation(
                    coordinate,
                    rawText: rawText,
                    reply: reply,
                    in: room,
                    archive: archive,
                    with: sender
                )
            }
        }
        guard canSend, let room = roomID, let sender else { return nil }
        if pendingGIF != nil, !canSendGIF {
            let netName = NetworkNames.displayName(of: network)
                ?? (network.isEmpty ? String(localized: "this chat") : network)
            notices = [
                .sendFailed(
                    reason: String(
                        format: String(localized: "GIFs are not supported on %@."),
                        netName
                    )
                ),
            ]
            return nil
        }
        let rich = outgoingText
        guard fitsChat(rich.text) else {
            notices = [.textTooLong]
            return nil
        }
        let draft = Contents(
            text: rich.text,
            entities: rich.entities,
            attachments: attachments,
            pendingGIF: pendingGIF,
            reply: replyTarget
        )
        let thread = threadRoot
        let hold = holdMillis
        let disableLinkPreview = preferences?.disableOutgoingLinkPreviews
        stopTyping() // the engine stops typing for a send too (C8); this ends the composer's own pulses
        setContents("", [])
        attachments = []
        pendingGIF = nil
        replyTarget = nil
        notices = []
        onSubmit()
        return enqueue(in: room) { [weak self] in
            await self?.deliver(
                draft,
                in: room,
                thread: thread,
                hold: hold,
                disableLinkPreview: disableLinkPreview,
                archive: archive,
                with: sender
            )
        }
    }

    /// Starts recording a voice note in the open chat (`⌘⇧A`, the microphone button, or `/voice`).
    public func startVoiceRecording() async {
        guard !isLocked, roomID != nil else { return }
        let preferredUID = preferences?.preferredMicrophoneUID ?? ""
        await voiceRecorder.start(preferredDeviceUID: preferredUID)
    }

    /// Sends a recorded voice note to the open chat via `message.sendVoice`.
    public func sendVoiceNote(url: URL, durationMS: Int, waveform: [Int]) async {
        guard !isLocked, let room = roomID, let sender else { return }
        let reply = replyTarget
        replyTarget = nil
        notices = []
        stopTyping()
        onSubmit()
        let task = enqueue(in: room) { [weak self] in
            do {
                let eventID = try await sender.sendVoice(
                    roomID: room,
                    url: url,
                    durationMS: Int64(durationMS),
                    waveform: waveform,
                    replyTo: reply?.eventID
                )
                self?.onSent(room, eventID)
            } catch {
                guard let self else { return }
                if self.roomID == room, self.replyTarget == nil {
                    self.replyTarget = reply
                }
                switch Self.classify(
                    error,
                    network: self.network,
                    maxSizeBytes: self.features.voiceFeatures?.maxSize
                        ?? self.features.audioFeatures?.maxSize
                        ?? self.features.fileFeatures?.maxSize
                ) {
                case let .refused(reason):
                    self.show([.sendFailed(reason: reason)], in: room)
                case .unanswered:
                    self.show([.noAnswer], in: room)
                }
            }
            self?.onSettled()
        }
        await task.value
    }

    // MARK: - Stickers

    private nonisolated static let allowedStickerExtensions: Set<String> = [
        "png", "webp", "gif", "apng", "jpg", "jpeg",
    ]
    private nonisolated static let allowedGIFExtensions: Set<String> = [
        "gif", "mp4", "m4v",
    ]

    /// Whether the open chat allows sending stickers according to the engine's `room.features`.
    public var canSendSticker: Bool {
        guard roomID != nil, !isEditing else { return false }
        return features.source == .none || features.sticker.supported
    }

    /// Whether the open chat allows sending GIFs according to the engine's `room.features`.
    public var canSendGIF: Bool {
        guard roomID != nil, !isEditing else { return false }
        return features.source == .none || features.gif.supported
    }

    /// Title for the Message menu's "Send Sticker…" item, including `"%1$@ (Unavailable for %2$@)"` when unsupported.
    public var sendStickerMenuTitle: String {
        guard !isLocked, roomID != nil, !isEditing else { return String(localized: "Send Sticker…") }
        guard canSendSticker else {
            return FormattingBar.unavailable(String(localized: "Send Sticker"), features: features, network: network)
        }
        return String(localized: "Send Sticker…")
    }

    /// Title for the Message menu's "Send GIF…" item, including `"%1$@ (Unavailable for %2$@)"` when unsupported.
    public var sendGIFMenuTitle: String {
        guard !isLocked, roomID != nil, !isEditing else { return String(localized: "Send GIF…") }
        guard canSendGIF else {
            return FormattingBar.unavailable(String(localized: "Send GIF"), features: features, network: network)
        }
        return String(localized: "Send GIF…")
    }

    /// Title for the composer `+` menu's "Add Sticker…" item, including `"%1$@ (Unavailable for %2$@)"` when unsupported.
    public var addStickerMenuTitle: String {
        guard roomID != nil, !isEditing else { return String(localized: "Add Sticker…") }
        guard canSendSticker else {
            return FormattingBar.unavailable(String(localized: "Add Sticker…"), features: features, network: network)
        }
        return String(localized: "Add Sticker…")
    }

    /// Title for the composer `+` menu's "Add GIF…" item, including `"%1$@ (Unavailable for %2$@)"` when unsupported.
    public var addGIFMenuTitle: String {
        guard roomID != nil, !isEditing else { return String(localized: "Add GIF…") }
        guard canSendGIF else {
            return FormattingBar.unavailable(String(localized: "Add GIF…"), features: features, network: network)
        }
        return String(localized: "Add GIF…")
    }

    /// Opens the sticker picker popover when the open chat supports stickers.
    @discardableResult
    public func openStickerPicker() -> Bool {
        guard !isLocked, canSendSticker else { return false }
        isGIFPickerPresented = false
        isEmojiPickerPresented = false
        dismissEmojiAutocomplete()
        isStickerPickerPresented = true
        return true
    }

    /// Opens the GIF picker popover when the open chat supports GIFs.
    @discardableResult
    public func openGIFPicker(query: String? = nil) -> Bool {
        guard !isLocked, canSendGIF else { return false }
        isStickerPickerPresented = false
        isEmojiPickerPresented = false
        dismissEmojiAutocomplete()
        if let query {
            gifSearchQuery = query
        }
        isGIFPickerPresented = true
        return true
    }

    /// Clears a staged pending GIF from the composer.
    public func removePendingGIF() {
        pendingGIF = nil
    }

    /// Selects a GIF from `GIFPickerPopover`: sends immediately when `preferences.autoSendGIFs == true`,
    /// or stages `pendingGIF` on the composer so the user can add a caption and press Return.
    public func selectGIF(_ item: StickerItemWire) async {
        guard !isLocked, roomID != nil, sender != nil else { return }
        isGIFPickerPresented = false
        guard canSendGIF else {
            let netName = NetworkNames.displayName(of: network)
                ?? (network.isEmpty ? String(localized: "this chat") : network)
            notices = [
                .sendFailed(
                    reason: String(
                        format: String(localized: "GIFs are not supported on %@."),
                        netName
                    )
                ),
            ]
            return
        }
        notices = []
        if preferences?.autoSendGIFs == true {
            await sendGIFImmediately(item)
        } else {
            pendingGIF = item
        }
    }

    /// Validates a local `.gif` or `.mp4` file and either sends it immediately (`autoSendGIFs == true`) or stages `pendingGIF`.
    public func sendGIFFile(url: URL) async {
        guard url.isFileURL else { return }
        let fileName = url.lastPathComponent
        guard let info = fileInfo(url) else {
            notices = [.cannotRead(fileName: fileName)]
            return
        }
        guard info.isRegularFile else {
            notices = [.notAFile(fileName: fileName)]
            return
        }
        guard info.size <= Self.maxAttachmentBytes else {
            notices = [.attachmentTooLarge(fileName: fileName)]
            return
        }
        let ext = url.pathExtension.lowercased()
        guard Self.allowedGIFExtensions.contains(ext) else {
            notices = [.sendFailed(reason: String(localized: "GIFs must be GIF or MP4 files."))]
            return
        }
        let mimeType = (ext == "gif") ? "image/gif" : "video/mp4"
        let item = StickerItemWire(
            id: "file:\(url.path)",
            packID: "local_gif",
            name: fileName,
            mediaURL: url.path,
            mimeType: mimeType,
            usage: ["gif"]
        )
        await selectGIF(item)
    }

    private func sendGIFImmediately(_ item: StickerItemWire) async {
        guard let room = roomID, let sender else { return }
        let reply = replyTarget
        let thread = threadRoot
        let hold = holdMillis
        replyTarget = nil
        notices = []
        stopTyping()
        onSubmit()

        let params = Self.makeSendGIFParams(
            roomID: room,
            item: item,
            caption: nil,
            replyTo: reply?.eventID,
            threadRoot: thread,
            holdMS: hold
        )

        let task = enqueue(in: room) { [weak self] in
            do {
                let eventID = try await sender.sendGIF(params)
                if hold > 0 {
                    let copy = HeldCopy(gif: item, reply: reply, threadRoot: thread)
                    self?.held.add(eventID, in: room, copy: copy, holdMillis: hold)
                }
                self?.onSent(room, eventID)
            } catch {
                guard let self else { return }
                if self.roomID == room, self.replyTarget == nil {
                    self.replyTarget = reply
                }
                switch Self.classify(
                    error,
                    network: self.network,
                    maxSizeBytes: self.features.gif.maxSize
                        ?? self.features.videoFeatures?.maxSize
                        ?? self.features.imageFeatures?.maxSize
                        ?? self.features.fileFeatures?.maxSize
                ) {
                case let .refused(reason):
                    self.show([.sendFailed(reason: reason)], in: room)
                case .unanswered:
                    self.show([.noAnswer], in: room)
                }
            }
            self?.onSettled()
        }
        await task.value
    }

    private static func makeSendGIFParams(
        roomID: String,
        item: StickerItemWire,
        caption: String?,
        replyTo: String?,
        threadRoot: String?,
        holdMS: Int
    ) -> MessageSendGIFParams {
        let path: String?
        let mediaURL: String?
        if item.mediaURL.hasPrefix("file://") {
            path = URL(string: item.mediaURL)?.path
            mediaURL = nil
        } else if item.mediaURL.hasPrefix("/") {
            path = item.mediaURL
            mediaURL = nil
        } else {
            path = nil
            mediaURL = item.mediaURL
        }
        let nonEmptyCaption = (caption?.isEmpty == false) ? caption : nil
        return MessageSendGIFParams(
            roomID: roomID,
            path: path,
            mediaURL: mediaURL,
            caption: nonEmptyCaption,
            replyTo: replyTo,
            threadRoot: threadRoot,
            holdMS: holdMS > 0 ? holdMS : nil
        )
    }

    /// Populates the sticker and recent GIF catalog directly for snapshot and unit tests.
    public func setStickerCatalogForTesting(packs: [StickerPackWire], recentGIFs: [StickerItemWire] = []) {
        stickerLoadGeneration += 1
        initialStickerLoadStarted = true
        applyStickerCatalog(StickersListResult(packs: packs, recentGIFs: recentGIFs))
    }

    /// Loads installed and bridge sticker packs plus recent GIFs from the engine (`stickers.list`).
    public func loadStickers(refresh: Bool = false) async {
        guard !isLocked, let sender else { return }
        stickerLoadGeneration += 1
        let generation = stickerLoadGeneration
        guard let result = try? await sender.listStickers(refreshBridgePacks: refresh) else { return }
        guard !isLocked, stickerLoadGeneration == generation else { return }
        applyStickerCatalog(result)
    }

    private func applyStickerCatalog(_ result: StickersListResult) {
        stickerPacks = result.packs
        recentGIFs = result.recentGIFs
        if !result.packs.contains(where: { $0.id == selectedStickerPackID }) {
            selectedStickerPackID = result.packs.first?.id ?? "recent"
        }
        rebuildCustomEmojisFromPacks()
    }

    private func rebuildCustomEmojisFromPacks() {
        var seen = Set<String>()
        var merged: [EmojiCandidate] = []
        for pack in stickerPacks {
            for item in pack.items {
                guard let raw = item.shortcode?.trimmingCharacters(in: CharacterSet(charactersIn: ": \t\n")),
                      !raw.isEmpty,
                      item.usage.contains("emoticon") || pack.id == "imported"
                else { continue }
                let key = raw.lowercased()
                guard seen.insert(key).inserted else { continue }
                merged.append(
                    EmojiCandidate(
                        id: item.mediaURL,
                        shortcode: raw,
                        glyph: nil,
                        mediaURL: item.mediaURL,
                        isCustom: true
                    )
                )
            }
        }
        customEmojis = merged
        if emojiQuery != nil {
            updateQueries(caret: selection.location)
        }
    }

    /// Validates a local image file and imports it into the engine's sticker/emoji catalog (`stickers.import`).
    public func importSticker(from url: URL, shortcode: String? = nil) async {
        guard !isLocked, let sender, url.isFileURL else { return }
        let fileName = url.lastPathComponent
        guard let info = fileInfo(url) else {
            notices = [.cannotRead(fileName: fileName)]
            return
        }
        guard info.isRegularFile else {
            notices = [.notAFile(fileName: fileName)]
            return
        }
        guard info.size <= Self.maxAttachmentBytes else {
            notices = [.attachmentTooLarge(fileName: fileName)]
            return
        }
        let ext = url.pathExtension.lowercased()
        guard Self.allowedStickerExtensions.contains(ext) else {
            notices = [.importFailed(reason: String(localized: "Stickers must be PNG, WebP, GIF, or JPEG images."))]
            return
        }

        let cleanShortcode = shortcode?.trimmingCharacters(in: CharacterSet(charactersIn: ": \t\n"))
        let nonEmptyShortcode = (cleanShortcode?.isEmpty == false) ? cleanShortcode : nil
        let usage = nonEmptyShortcode != nil ? ["emoticon", "sticker"] : ["sticker"]
        let stem = url.deletingPathExtension().lastPathComponent
        let itemName = nonEmptyShortcode ?? (stem.isEmpty ? "Sticker" : stem)
        let params = StickersImportParams(
            path: url.path,
            shortcode: nonEmptyShortcode,
            name: itemName,
            emoji: nil,
            usage: usage
        )

        do {
            let imported = try await sender.importSticker(params)
            notices = []
            upsertImportedSticker(imported)
        } catch {
            let reason = EngineErrorText.text(
                for: error,
                network: network.isEmpty ? nil : network,
                maxSizeBytes: Self.maxAttachmentBytes,
                fallback: ""
            )
            if let room = roomID {
                show([.importFailed(reason: reason)], in: room)
            } else {
                notices = [.importFailed(reason: reason)]
            }
        }
    }

    private func upsertImportedSticker(_ imported: StickerItemWire) {
        if stickerPacks.isEmpty {
            stickerPacks = [
                StickerPackWire(id: "recent", title: "Recent", source: "recent", items: []),
                StickerPackWire(id: "imported", title: "Imported", source: "imported", items: [imported]),
            ]
            selectedStickerPackID = "imported"
        } else if let idx = stickerPacks.firstIndex(where: { $0.id == "imported" }) {
            var pack = stickerPacks[idx]
            if let existing = pack.items.firstIndex(where: {
                $0.id == imported.id || (imported.shortcode != nil && $0.shortcode == imported.shortcode)
            }) {
                pack.items[existing] = imported
            } else {
                pack.items.append(imported)
            }
            stickerPacks[idx] = pack
        } else {
            stickerPacks.append(
                StickerPackWire(id: "imported", title: "Imported", source: "imported", items: [imported])
            )
        }
        rebuildCustomEmojisFromPacks()
    }

    /// Sends a sticker to the open chat (`message.sendSticker`), respecting the room's sticker capability and undo-send hold.
    public func sendSticker(_ item: StickerItemWire) async {
        guard !isLocked, let room = roomID, let sender else { return }
        isStickerPickerPresented = false
        guard features.source == .none || features.sticker.supported else {
            let netName = NetworkNames.displayName(of: network)
                ?? (network.isEmpty ? String(localized: "this chat") : network)
            notices = [
                .sendFailed(
                    reason: String(
                        format: String(localized: "Stickers are not supported on %@."),
                        netName
                    )
                ),
            ]
            return
        }

        let reply = replyTarget
        let thread = threadRoot
        let hold = holdMillis
        replyTarget = nil
        notices = []
        stopTyping()
        onSubmit()

        let path: String?
        let mediaURL: String?
        if item.mediaURL.hasPrefix("file://") {
            path = URL(string: item.mediaURL)?.path
            mediaURL = nil
        } else if item.mediaURL.hasPrefix("/") {
            path = item.mediaURL
            mediaURL = nil
        } else {
            path = nil
            mediaURL = item.mediaURL
        }

        let params = MessageSendStickerParams(
            roomID: room,
            path: path,
            mediaURL: mediaURL,
            name: item.name.isEmpty ? nil : item.name,
            emoji: (item.emoji?.isEmpty == false) ? item.emoji : nil,
            mimeType: item.mimeType.isEmpty ? nil : item.mimeType,
            bridgedSticker: item.bridgedSticker,
            replyTo: reply?.eventID,
            threadRoot: thread,
            holdMS: hold > 0 ? hold : nil
        )

        let task = enqueue(in: room) { [weak self] in
            do {
                let eventID = try await sender.sendSticker(params)
                if hold > 0 {
                    let copy = HeldCopy( isSticker: true, reply: reply, threadRoot: thread)
                    self?.held.add(eventID, in: room, copy: copy, holdMillis: hold)
                }
                self?.onSent(room, eventID)
            } catch {
                guard let self else { return }
                if self.roomID == room, self.replyTarget == nil {
                    self.replyTarget = reply
                }
                switch Self.classify(
                    error,
                    network: self.network,
                    maxSizeBytes: self.features.sticker.maxSize
                        ?? self.features.imageFeatures?.maxSize
                        ?? self.features.fileFeatures?.maxSize
                ) {
                case let .refused(reason):
                    self.show([.sendFailed(reason: reason)], in: room)
                case .unanswered:
                    self.show([.noAnswer], in: room)
                }
            }
            self?.onSettled()
        }
        await task.value
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
        stopTyping()
        leaveEditing()
        let unchanged = rich.text == original.text.trimmingCharacters(in: .whitespacesAndNewlines)
            && rich.entities == RichTextHTML.sendable(original.entities, in: original.text)
        guard !unchanged else { return nil }
        return enqueue(in: room) { [weak self] in
            do {
                try await sender.edit(eventID: eventID, rich: rich)
            } catch {
                guard let self else { return }
                switch Self.classify(error, network: self.network) {
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
        if room == roomID, mode == .new || threadRoot != nil, trimmedText.isEmpty, attachments.isEmpty, pendingGIF == nil {
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

    private func deliverLocation(
        _ coordinate: GeoCoordinate,
        rawText: String,
        reply: QuotedMessage?,
        in room: String,
        archive: Bool,
        with sender: MessageSending
    ) async {
        do {
            let eventID = try await sender.sendLocation(
                roomID: room,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                label: coordinate.label,
                replyTo: reply?.eventID
            )
            onSent(room, eventID)
            if archive { await onArchive(room) }
        } catch {
            switch Self.classify(error, network: self.network) {
            case let .refused(reason):
                let leftOut = putBack([.text(RichText(text: rawText))][...], reply: reply, in: room)
                show([.sendFailed(reason: reason)] + Self.leftOutNotice(leftOut), in: room)
            case .unanswered:
                show([.noAnswer], in: room)
            }
        }
        onSettled()
    }

    private func deliver(_ draft: Contents, in room: String, thread: String?, hold: Int,
                         disableLinkPreview: Bool? = nil, archive: Bool,
                         with sender: MessageSending) async {
        var items: [Outgoing] = []
        if let gifItem = draft.pendingGIF {
            let caption = draft.text.isEmpty ? nil : RichText(text: draft.text, entities: draft.entities)
            items.append(.gif(gifItem, caption: caption))
        } else if !draft.text.isEmpty {
            items.append(.text(RichText(text: draft.text, entities: draft.entities)))
        }
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
                                                    threadRoot: thread, holdMillis: hold,
                                                    disableLinkPreview: disableLinkPreview)
                    copy = HeldCopy(text: rich.text, entities: rich.entities, reply: reply, threadRoot: thread)
                case let .gif(gifItem, caption):
                    let params = Self.makeSendGIFParams(
                        roomID: room,
                        item: gifItem,
                        caption: caption?.text,
                        replyTo: reply?.eventID,
                        threadRoot: thread,
                        holdMS: hold
                    )
                    eventID = try await sender.sendGIF(params)
                    copy = HeldCopy(
                        text: caption?.text ?? "",
                        entities: caption?.entities ?? [],
                        gif: gifItem,
                        reply: reply,
                        threadRoot: thread
                    )
                case let .file(file):
                    eventID = try await sender.sendFile(roomID: room, url: file.url, size: file.size,
                                                        replyTo: reply?.eventID, threadRoot: thread, holdMillis: hold)
                    copy = HeldCopy(attachment: file, reply: reply, threadRoot: thread)
                }
                if hold > 0 { held.add(eventID, in: room, copy: copy, holdMillis: hold) }
                onSent(room, eventID)
                reply = nil
            } catch {
                let itemMaxSize: Int64?
                switch item {
                case let .file(file):
                    itemMaxSize = self.maxFileSize(for: file.url)
                case .gif:
                    itemMaxSize = self.features.gif.maxSize
                        ?? self.features.videoFeatures?.maxSize
                        ?? self.features.imageFeatures?.maxSize
                        ?? self.features.fileFeatures?.maxSize
                case .text:
                    itemMaxSize = nil
                }
                switch Self.classify(error, network: self.network, maxSizeBytes: itemMaxSize) {
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
            case let .gif(gifItem, caption):
                unsent.pendingGIF = gifItem
                if let caption {
                    unsent.text = caption.text
                    unsent.entities = caption.entities
                }
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

    /// An MCP client's focus_app: `text` and the file at `attachment` go into `room`'s composer (now if it is open,
    /// otherwise with its draft, for when it opens), ahead of anything already typed there. They are only filled in:
    /// nothing is sent until the person presses Send. A file that isn't there, is a folder, or can't be read puts in
    /// nothing at all, so a composer is never left half filled, and false is returned.
    @discardableResult
    public func placeDraft(text: String?, attachment: URL?, in room: String) -> Bool {
        guard !isLocked else { return false }
        var items: [Outgoing] = []
        if let text, !text.isEmpty { items.append(.text(RichText(text: text))) }
        if let attachment {
            guard attachment.isFileURL, let info = fileInfo(attachment), info.isRegularFile,
                  info.size <= Self.maxAttachmentBytes else { return false }
            items.append(.file(ComposerAttachment(url: attachment, size: info.size)))
        }
        guard !items.isEmpty else { return true }
        _ = putBack(items[...], reply: nil, in: room)
        return true
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
    private static func classify(_ error: Error, network: String = "", maxSizeBytes: Int64? = nil) -> Failure {
        if (error as? EngineError)?.mayHaveBeenHandled == true { return .unanswered }
        return .refused(
            EngineErrorText.text(
                for: error,
                network: network.isEmpty ? nil : network,
                maxSizeBytes: maxSizeBytes,
                fallback: String(localized: "The message could not be sent.")
            )
        )
    }

    private func maxFileSize(for url: URL) -> Int64? {
        let ext = url.pathExtension.lowercased()
        let msgType: String
        switch ext {
        case "gif":
            msgType = "fi.mau.gif"
        case "jpg", "jpeg", "png", "webp", "heic", "heif", "bmp", "tiff", "tif":
            msgType = "m.image"
        case "mp4", "mov", "m4v", "webm", "mkv", "avi":
            msgType = "m.video"
        case "mp3", "m4a", "aac", "ogg", "oga", "opus", "wav", "flac":
            msgType = "m.audio"
        default:
            msgType = "m.file"
        }
        return features.maxSizeBytes(for: msgType) ?? features.fileFeatures?.maxSize
    }

    // MARK: - Send later

    /// Schedules the composer's text (with its reply, in its thread) for `due`, and empties the composer once the
    /// engine has it. Without a plan that has send later, it says "Available with a plan" and nothing is sent; text
    /// longer than the chat takes is refused with why. The engine's refusal (a time in the past, say) is thrown, and
    /// the text stays. One at a time: while one is with the engine, another (or Return) does nothing.
    public func schedule(at due: Date, condition: SendLaterCondition) async throws {
        guard !isLocked, !isScheduling, let room = roomID, let sender else { return }
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
        let disableLinkPreview = preferences?.disableOutgoingLinkPreviews
        isScheduling = true
        defer { isScheduling = false }
        try await sender.schedule(roomID: room, rich: rich, replyTo: reply?.eventID, threadRoot: threadRoot,
                                  due: due, condition: condition, disableLinkPreview: disableLinkPreview)
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
        guard !isLocked, let room = roomID else { return false }
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
        current.pendingGIF = current.pendingGIF ?? undone.gif
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

    /// Don't Send on a message waiting for its network: takes it back as Undo does, held or not yet (the timeline may
    /// not have been read since it went back to waiting). True when it was taken up; false when it can't be (Undo
    /// already took it back, or it is being taken back).
    @discardableResult
    public func dontSend(_ eventID: String) async -> Bool {
        guard !isLocked, let room = roomID else { return false }
        held.holdWaiting(eventID, in: room)
        return await undoHeld(eventID)
    }

    /// ⌘⇧Z: sends the open chat's held messages now. It waits for the engine's answer (a call dropped on the way
    /// would leave them to fail as "not connected"); until then, and if the call fails, they stay held, and go when
    /// their windows end.
    public func sendHeldNow() async {
        guard !isLocked, let room = roomID else { return }
        await held.sendNow(in: room)
    }

    // MARK: - AI & Slash Command Stubs (Milestone 4.7)

    /// Matching `/` slash commands when `aiPreferences.enableSlashCommands` is enabled and `text` begins with `/`.
    public var slashCommandSuggestions: [ComposerSlashCommand] {
        guard aiPreferences.enableSlashCommands else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return [] }
        let token = String(trimmed.prefix(while: { !$0.isWhitespace })).lowercased()
        return ComposerSlashCommand.allCommands.filter { cmd in
            cmd.trigger.lowercased().hasPrefix(token)
        }
    }

    /// Triggers Talk to Type (`⌘⇧D` / `Message: Talk to Type`). Preserves `text` and shows a calm notice.
    public func triggerTalkToType() {
        guard !isLocked else { return }
        notices = [.calmStub(reason: String(localized: "Talk to Type isn’t available yet in Courier."))]
    }

    /// Triggers Draft with AI (`AIRewriteTone`). Preserves `text` and shows a calm notice.
    public func draftWithAI(tone _: AIRewriteTone? = nil) {
        guard !isLocked else { return }
        notices = [.calmStub(reason: String(localized: "Drafting with AI isn’t available yet in Courier."))]
    }

    /// Runs a slash command (`/ai`, `/translate`, `/summarize`, `/draft`) without clearing or sending `text`.
    public func executeSlashCommand(_ command: String) {
        guard !isLocked else { return }
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let reason: String
        switch normalized {
        case let cmd where cmd.hasPrefix("/translate"):
            reason = String(localized: "Message translation isn’t available yet in Courier.")
        case let cmd where cmd.hasPrefix("/summarize"):
            reason = String(localized: "AI chat summaries aren’t available yet in Courier.")
        case let cmd where cmd.hasPrefix("/draft"):
            reason = String(localized: "Drafting with AI isn’t available yet in Courier.")
        default:
            reason = aiProvider.unavailableReason
        }
        notices = [.calmStub(reason: reason)]
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
