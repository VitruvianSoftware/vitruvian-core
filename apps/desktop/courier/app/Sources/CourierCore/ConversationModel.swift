// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Something the conversation could not do, shown in a bar above the composer.
public enum ConversationProblem: Equatable, Sendable {
    /// The newest messages could not be read.
    case loadFailed
    /// A reaction, retry or delete was refused or not answered. The text is for people.
    case actionFailed(String)
    /// The chat was opened at a message that is no longer in it (deleted since): the newest messages show instead.
    case messageGone
}

/// The open chat: its timeline, what is new in it, and its composer.
///
/// The timeline keeps the pages it has loaded. A change in the open chat (a new event, a status, the read marker)
/// reads the newest page again and merges it by event id, so older pages stay; a `resync`, and a new engine's
/// greeting, read the newest page and drop the older ones. A read that was in flight when the chat was closed, or
/// when the engine restarted, is dropped when its answer comes.
///
/// A chat opened at a message (a search result) shows a window of its history around that message instead: the
/// page `room.events around` reads, then older pages above it and newer pages below it as the person scrolls.
/// While that window does not reach the newest message the chat is "away": changes don't read the newest page (a
/// new message is only noted, for "Jump to latest"), nothing new is marked read, and the "New" divider isn't drawn.
/// Reaching the newest message by scrolling, "Jump to latest" and sending all end it.
///
/// The open chat's features (`room.features`) are read when it opens, when the engine is greeted or resyncs, and
/// whenever its row changes (`room`): a bridge writes new ones as the network's limits change. They and the chat's
/// network go to both composers (the chat's and the thread pane's), with the other person's name in a one-to-one
/// chat, for its quick replies. A chat whose network leaves no "deleted" placeholder, or the person's setting, hides
/// deleted messages.
///
/// Disappearing messages (01 §5). The header says the chat's timer (`timerLine`) and its menu offers the timers the
/// chat has (`timerChoices`, `setTimer`); neither shows a timer the engine has not reported: a change the person
/// asks for is a call to `room.setDisappearing`, and the header moves when the engine says the chat has it (a room
/// change reads the features again). A message with a timer running says how long it has left (`disappearsIn`,
/// by the minute), and a message past its time is left out of the chat and of the thread pane with no read of the
/// engine: one wake, for whichever comes first of the next message to run out and the next minute a countdown
/// changes at, builds both again (see `scheduleWake`). The bridge's note that the timer changed reads as a note
/// (`timerChangeNote`), not as the bridge's English.
///
/// A search result that is a reply in a thread (Ruling 23) opens the chat around its root, which the engine centres
/// the page on, and the thread pane at the reply.
///
/// Protocol 5. Who is typing (`typingLine`) is the chat's row's, read again on each typing change; a read that fails
/// shows no one, so a line never sticks. A receipt change reads the newest page again, as a status change does: my
/// newest message says Delivered or Seen. Mark as Unread from a message (`markUnread`) and Reply Privately
/// (`replyPrivately`) are here; the composer sends my typing, while "Show recipients I'm typing" is on.
///
/// **Incognito** (`incognitoIsOn`: the setting, with the plan): opening and reading the chat marks nothing read and
/// sends no receipt, so its count and "New" divider stay. It is read when I send a message in it (my newest message
/// that went changes: the networks mark it read then anyway), or by hand (⌘⇧U, Mark as Read, Mark All as Read, which
/// are the inbox's). Turning Incognito off sends nothing for chats already open: what was looked at while it was on
/// waits for the next message. Turning it on (`setIncognito`) asks whether to also hide that I'm typing.
@MainActor
public final class ConversationModel: ObservableObject {
    public static let pageSize = 50
    /// The reactions offered on hover, the default first.
    public static let quickReactions = ["❤️", "👍", "😂", "😮", "😢", "🙏"]
    /// How long a message the chat was opened at stays highlighted.
    public static let highlightDuration: Duration = .seconds(3)

    /// The view is asked to scroll to a message. A new request has a higher serial, so asking for the same
    /// message twice is two requests.
    public struct MessageScrollRequest: Equatable, Sendable {
        public let messageID: String
        public let serial: Int
    }

    /// The open chat; nil when none is.
    @Published public private(set) var roomID: String?
    /// Oldest first.
    @Published public private(set) var items: [TimelineItem] = []
    /// The newest page of the open chat has been read (or, for a chat opened at a message, the page around it).
    @Published public private(set) var isLoaded = false
    /// There are older messages than the ones loaded.
    @Published public private(set) var hasOlder = false
    @Published public private(set) var isLoadingOlder = false
    /// The last read of an older page failed: the view offers a button instead of trying again by itself.
    @Published public private(set) var olderFailed = false
    @Published public private(set) var problem: ConversationProblem?
    /// Messages from others that came while the chat was scrolled up: the jump-to-bottom button's count.
    @Published public private(set) var newMessageCount = 0
    @Published public private(set) var isAtBottom = true
    /// Goes up by one each time the view is asked to scroll to the newest message.
    @Published public private(set) var jumpToBottomRequest = 0
    /// The message a keyboard action (⌘R) is about.
    @Published public var selectedMessageID: String?
    /// Showing history that doesn't reach the newest message (the chat was opened at an older one).
    @Published public private(set) var isAwayFromLatest = false
    /// A newer page is being read, while away.
    @Published public private(set) var isLoadingNewer = false
    /// The message the chat was opened at, for `highlightDuration`.
    @Published public private(set) var highlightedMessageID: String?
    /// The view scrolls to this message whenever it changes.
    @Published public private(set) var scrollToMessageRequest: MessageScrollRequest?
    /// A new event came in the chat while away: "Jump to latest" has something new below.
    @Published public private(set) var hasNewerWhileAway = false
    /// My newest message that went (not a note, not deleted): the only one whose Sent, Delivered or Seen is shown.
    public private(set) var lastOutgoingID: String?
    /// What the open chat can do (room.features); `noFeatures` until read, and for no chat.
    @Published public private(set) var features: ChatFeatures = .noFeatures
    /// The open chat's network, by the engine's id; "" until its row is known.
    @Published public private(set) var network = ""
    /// In a one-to-one chat, the other person's name (what quick replies fill in); nil in a group, or unknown.
    @Published public private(set) var otherPerson: String?
    /// The open chat is one-to-one (true) or a group (false); nil while its row is unknown.
    @Published public private(set) var isDirectChat: Bool?
    /// The time the timeline was last built at. Countdowns (`disappearsIn`) are read from the clock; a view that shows
    /// one watches this so it is drawn again whenever the model has built the timeline, at least every minute while
    /// a countdown shows.
    @Published public private(set) var countdownClock = Date(timeIntervalSince1970: 0)
    /// A change of the disappearing timer is on its way to the engine: the menu waits for its answer.
    @Published public private(set) var isChangingTimer = false
    /// Who is typing in the open chat, as its row words it ("Ana is typing…", "3 people are typing…"); nil when no one
    /// is, and for no chat.
    @Published public private(set) var typingLine: String?
    /// "After marking the open chat read or unread", for Mark as Unread from a message: the inbox's own rule
    /// (`InboxModel.planAfterToggleRead`), worked out before the mark and done after it. The app sets it; unset, the
    /// chat stays open.
    public var planAfterToggleRead: @MainActor () -> @MainActor () -> Void = { {} }
    /// Whether the person's plan includes a feature: the inbox's (`InboxModel.isEntitled`), which the app points
    /// this at. Unset, nothing is included, so Incognito does nothing until the plan is known (C42).
    public var isEntitled: @MainActor (Feature) -> Bool = { _ in false } {
        didSet { objectWillChange.send() }
    }
    /// Turning Incognito on asked whether to also hide that I'm typing, and the person hasn't answered yet: the
    /// view shows `hideTypingQuestion` with `hideTypingButton` and `keepShowingTypingButton`.
    @Published public private(set) var asksToHideTyping = false
    /// Tests: how many times the open chat has been told read (room.markRead asked for).
    private(set) var readsSent = 0
    /// Tests: how many of the newest pages have been applied, to know every change so far has been read.
    private(set) var pagesApplied = 0
    /// Tests: called each time an answer for a chat that is no longer open (or from an engine that is gone), or for a
    /// window around a message that was let go of meanwhile, is dropped, so a test can wait for that instead of for a
    /// while.
    var staleAnswerDropped: (@MainActor () -> Void)?
    /// From the moment the chat is opened at a message (its page still on the way) until it is back at the
    /// newest message: what it shows doesn't reach the newest, so nothing new in it should be marked read.
    public var isHeldAwayFromLatest: Bool { anchorID != nil }

    public let composer: ComposerModel
    /// The thread pane, in the open chat.
    public let thread: ThreadModel
    /// Whether the person is looking at the open chat (see `Attention`): it is marked read only then.
    public let attention: Attention
    /// Where toasts go: the inbox's (`InboxModel.announce`). Today: a refused disappearing timer.
    public var onToast: @MainActor (String) -> Void = { _ in }
    /// The composer's settings, one object shared with Settings: hiding deleted messages and the quick reaction are
    /// read from it, and both composers are given it.
    public var preferences: ComposerPreferences? {
        didSet { preferencesChanged() }
    }

    private let appModel: AppModel
    private let unreadCount: @MainActor (String) -> Int
    private let chat: @MainActor (String) -> InboxRow?
    private var hideDeletedPreference = false
    private var preferenceSubscription: AnyCancellable?
    private var incognitoSubscription: AnyCancellable?
    /// Goes up with each read of the features: an older answer, or one for another chat, is dropped.
    private var featuresSerial = 0
    private let calendar: Calendar
    private let sleep: @Sendable (Duration) async throws -> Void
    /// The time the timeline is built at: a message whose disappearing timer has run out by then is not shown.
    private let now: @MainActor () -> Date
    private let locale: Locale
    /// The one scheduled wake for the soonest change the clock brings (`scheduleWake`); nil when none is waited for.
    private var wakeTask: Task<Void, Never>?
    /// A wake is set this much after the time it is for: a message goes at its `expires_at`, not a moment before.
    static let wakeSlack: Duration = .milliseconds(50)
    /// A wake is never nearer than this, so a clock that disagrees with the sleeper cannot make it spin.
    static let minimumWake: Int64 = 100
    private var subscriptions: [AnyCancellable] = []

    // What is loaded.
    private var events: [String: Event] = [:]
    private var seenIDs = Set<String>()
    private var olderCursor: Cursor?
    private var olderPagesLoaded = false
    private var firstUnreadID: String?
    private var unreadAtOpen = 0
    /// The next newest page is the first since the chat was opened (or came back from a window): it places the
    /// "New" divider and marks the chat read, as opening does.
    private var firstNewest = true
    /// The newest page asked for by "Jump to latest" from a window: the view scrolls down once it is in.
    private var scrollDownOnNewest = false
    /// The chat was opened at a message that isn't there: the newest page shows `messageGone` when it lands.
    private var messageGoneOnNewest = false
    /// A window reached the newest message while changes were waiting: the newest page that brings them places
    /// the "New" divider, from `unreadAtOpen`.
    private var dividerOnNewest = false

    // A window around a message.
    /// The message the chat is held at, from the moment it is opened at it until the window reaches the newest
    /// message. While it is set the newest page is never read.
    private var anchorID: String?
    /// The page around `anchorID` is in (until then the chat is still opening at it).
    private var windowLoaded = false
    /// The newest event of the window, for the next newer page.
    private var newerCursor: Cursor?
    /// Something asked for the newest page while it couldn't be read: it is read on reaching the latest.
    private var missedChanges = false
    /// The serial of the last `AppModel.pendingMessage` taken, so each is taken once.
    private var takenPendingSerial = 0
    private var scrollSerial = 0
    private var highlightTask: Task<Void, Never>?

    // Which answers still count.
    private var generation = 0
    private var pageEpoch = 0
    private var fetchSerial = 0
    private var appliedSerial = 0
    private var refetching = false
    private var refetchAgain = false
    /// A resync (or a new engine) asked for the older pages to be dropped, and no answer has done it yet. Whichever
    /// answer lands first does it, so a refetch that overtakes the resync's own read cannot keep them.
    private var dropPending = false

    // Reading.
    private var needsRead = false
    /// My messages sent from this chat's composers (the chat's or its thread pane's) that haven't gone yet: when one
    /// has, it is a reply, wherever the chat shows when it does (after leaving an older part of the chat, say).
    private var mySends = Set<String>()
    /// Marked unread from a message and stayed on: nothing marks the chat read again until it is reopened or a new
    /// message comes (Inferred (inventory 02 §3.4.2 item 8)).
    private var holdsRead = false

    // Who is typing.
    private var readingTyping = false
    private var typingAgain = false

    /// Reply Privately's quote, for the one-to-one chat being opened: put in once that chat's features are read
    /// (whether the quote is a range or "> " lines), since opening a chat forgets the last chat's features and its
    /// draft may come in after.
    private var pendingPrivateReply: (roomID: String, message: TimelineMessage)?

    /// - Parameters:
    ///   - unreadCount: a chat's unread count as the inbox has it, read when the chat is opened (the "New" divider
    ///     goes above that many of the newest messages from others), and when a window reaches the newest message.
    ///   - attention: whether the person is looking; nil makes one that only follows `setWindowKey`.
    ///   - savedDraft: a chat's draft as the engine keeps it (its inbox row's), for a chat opened with no text in
    ///     the composer's memory; nil when the inbox hasn't loaded the chat.
    ///   - lookUpDraft: the draft of a chat `savedDraft` doesn't know, looked up; nil when that fails.
    ///   - sleep: how the highlight waits out `highlightDuration`; tests give one on a clock they move.
    ///   - now: the time now, for disappearing messages; tests give a clock they move.
    ///   - locale: how lengths of time read ("7 days"), in the header, the menu, countdowns and notes.
    ///   - chat: a chat's row as the inbox has it (its network, its name, whether it is one-to-one); nil when the
    ///     inbox hasn't loaded it (then `learnChat` brings it once looked up).
    ///   - preferences: the composer's settings (see `preferences`).
    public init(appModel: AppModel, unreadCount: @escaping @MainActor (String) -> Int = { _ in 0 },
                attention: Attention? = nil, calendar: Calendar = .autoupdatingCurrent,
                savedDraft: @escaping @MainActor (String) -> String? = { _ in "" },
                lookUpDraft: @escaping @MainActor (String) async -> String? = { _ in nil },
                chat: @escaping @MainActor (String) -> InboxRow? = { _ in nil },
                preferences: ComposerPreferences? = nil,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                now: @escaping @MainActor () -> Date = Date.init, locale: Locale = .current) {
        self.appModel = appModel
        self.unreadCount = unreadCount
        self.chat = chat
        self.preferences = preferences
        self.attention = attention ?? Attention(source: StaticPresence(), pollInterval: nil)
        self.calendar = calendar
        self.sleep = sleep
        self.now = now
        self.locale = locale
        composer = ComposerModel(sender: EngineMessageSender(appModel: appModel), now: now)
        thread = ThreadModel(appModel: appModel, now: now, calendar: calendar, sleep: sleep)
        composer.savedDraft = savedDraft
        composer.lookUpDraft = lookUpDraft
        composer.onSettled = { [weak self] in self?.requestRefetch() }
        composer.onSubmit = { [weak self] in self?.jumpToBottom() }
        for target in [composer, thread.composer] {
            target.onSent = { [weak self] room, eventID in self?.sent(eventID, in: room) }
        }
        composer.quote = { [weak self] id in self?.message(id)?.quoted }
        composer.selectedMessage = { [weak self] in self?.selectedMessageID.flatMap { self?.message($0) } }
        subscriptions.append(appModel.$selectedRoomID.removeDuplicates().sink { [weak self] room in
            self?.open(room)
        })
        // A message in the chat that is already open: selectedRoomID doesn't change, so this is how it arrives.
        // (For another chat, `open` takes it when selectedRoomID moves, just after.)
        subscriptions.append(appModel.$pendingMessage.compactMap { $0 }.sink { [weak self] pending in
            self?.pendingMessageArrived(pending)
        })
        // The thread pane's messages leave on time too: its items decide what the wake waits for. (The value comes
        // before the property is set.)
        subscriptions.append(thread.$items.dropFirst().sink { [weak self] threadItems in
            self?.scheduleWake(threadItems: threadItems)
        })
        appModel.onConnect { [weak self] client in await self?.reload(from: client) }
        appModel.onChange { [weak self] change in self?.handle(change) }
        self.attention.onReturn { [weak self] in self?.personReturned() }
        preferencesChanged()
    }

    // MARK: - Opening

    private func open(_ room: String?) {
        var target: String?
        if let room, let pending = appModel.pendingMessage, pending.roomID == room,
           pending.serial > takenPendingSerial {
            takenPendingSerial = pending.serial
            target = pending.eventID
        }
        reset(room, at: target, inPlace: false)
        if pendingPrivateReply?.roomID != room { pendingPrivateReply = nil }
        composer.open(room)
        thread.close()
        features = .noFeatures
        let row = room.flatMap(chat)
        learnChat(row, of: room)
        // The row may be a moment behind the engine: when it says someone is typing, read it again.
        typingLine = row?.typingLine
        if typingLine != nil { readTyping() }
        startReading()
        readFeatures()
    }

    // MARK: - The chat's features, network and people

    /// The open chat's row, looked up after it opened (the inbox didn't list it): its network and, one-to-one, the
    /// other person's name reach the composers. Another chat's row changes nothing.
    public func learnChat(_ row: InboxRow) {
        guard row.roomID == roomID else { return }
        learnChat(row, of: row.roomID)
    }

    private func learnChat(_ row: InboxRow?, of room: String?) {
        guard room == roomID else { return }
        network = row?.network ?? ""
        let name = row?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        otherPerson = row?.isDirect == true && !name.isEmpty ? name : nil
        let wasDirect = isDirectChat
        isDirectChat = row?.isDirect
        handOnChat()
        if isDirectChat != wasDirect, !events.isEmpty { rebuild() } // "Seen" names no one one-to-one
    }

    /// Reads the open chat's features. An answer for a chat no longer open, from an engine that is gone, or older
    /// than one already shown, is dropped; a failure keeps what was known.
    private func readFeatures() {
        guard let room = roomID, let client = appModel.client else { return }
        featuresSerial += 1
        let serial = featuresSerial
        Task { [weak self] in
            let read: ChatFeatures? = try? await client.call("room.features", RoomParams(roomID: room))
            guard let self, serial == self.featuresSerial, room == self.roomID, client === self.appModel.client
            else { return }
            if let read {
                self.features = read
                self.handOnChat()
                self.rebuild()
            }
            // With the features known (or not to be had), Reply Privately's quote goes in.
            self.putInPrivateReply()
        }
    }

    /// The chat's features, network and other person, to each composer open on this chat.
    private func handOnChat() {
        guard let room = roomID else { return }
        for target in [composer, thread.composer] where target.roomID == room {
            target.features = features
            target.network = network
            target.otherPerson = otherPerson
        }
        if thread.roomID == room { thread.hideDeleted = hidesDeleted }
    }

    /// Deleted messages leave no placeholder: the person's setting, or a network that leaves none (Telegram).
    private var hidesDeleted: Bool { hideDeletedPreference || features.hideDeletedPlaceholder }

    private func preferencesChanged() {
        composer.preferences = preferences
        thread.composer.preferences = preferences
        // C21: my typing goes out from either composer while "Show recipients I'm typing" is on, read at each
        // change, so Settings counts at once. Incognito's Hide Typing turns the setting off; Incognito itself
        // never hides typing.
        let showsTyping: @MainActor () -> Bool = { [weak self] in self?.preferences?.showTyping ?? true }
        composer.sendsTyping = showsTyping
        thread.composer.sendsTyping = showsTyping
        incognitoSubscription = preferences?.$incognito.dropFirst().sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        hideDeletedPreference = preferences?.hideDeletedMessages ?? false
        // @Published says so before the value changes: the new value is the one handed over.
        preferenceSubscription = preferences?.$hideDeletedMessages.dropFirst().sink { [weak self] hide in
            guard let self else { return }
            self.hideDeletedPreference = hide
            self.rebuild()
            if self.thread.roomID == self.roomID { self.thread.hideDeleted = self.hidesDeleted }
        }
        rebuild()
    }

    // MARK: - The thread pane

    /// Opens the thread pane on `rootID` in the open chat, at `replyID` when given (a search result).
    public func openThread(_ rootID: String, at replyID: String? = nil) {
        guard let room = roomID else { return }
        thread.open(rootID, in: room, at: replyID)
        handOnChat()
    }

    /// The open chat's unread count, learned after it opened: the inbox didn't list the chat (a search opened it from
    /// the archive, say) and looked its row up. At its newest message, the "New" divider goes above that many, at
    /// once if the newest page is in, else when it lands; in a window around a message, reaching the newest one
    /// reads the count again anyway. A count that is no higher than the one it opened with changes nothing.
    public func learnUnreadCount(_ count: Int, of room: String) {
        guard room == roomID, anchorID == nil, count > unreadAtOpen else { return }
        unreadAtOpen = count
        guard !firstNewest, !dividerOnNewest else { return } // the newest page still to come places it
        firstUnreadID = Timeline.firstUnreadID(events: Array(events.values), me: Timeline.meUserID, unread: count,
                                               now: now())
        rebuild()
    }

    private func pendingMessageArrived(_ pending: PendingMessage) {
        guard pending.serial > takenPendingSerial, let room = roomID, pending.roomID == room else { return }
        takenPendingSerial = pending.serial
        // Opened again at a message, in place: what is on screen stays until the page around it is in, and the
        // composer (its text, its reply) is untouched.
        reset(room, at: pending.eventID, inPlace: true)
        if typingLine != nil { readTyping() }
        startReading()
    }

    /// Forgets what is loaded, and every read in flight, for `room` opened at its newest message or at `target`.
    private func reset(_ room: String?, at target: String?, inPlace: Bool) {
        generation += 1
        pageEpoch += 1
        cancelWake()
        events = [:]
        seenIDs = []
        olderCursor = nil
        olderPagesLoaded = false
        firstUnreadID = nil
        unreadAtOpen = room.map { unreadCount($0) } ?? 0
        firstNewest = true
        scrollDownOnNewest = false
        messageGoneOnNewest = false
        dividerOnNewest = false
        refetching = false
        refetchAgain = false
        dropPending = false
        readingTyping = false
        typingAgain = false
        holdsRead = false
        if room != roomID { mySends = [] }
        // Opened at a message, nothing is read until the person reaches the newest one; in Incognito, nothing is
        // read at all, and nothing waits to be read once it is off.
        needsRead = room != nil && target == nil && !incognitoIsOn
        anchorID = room == nil ? nil : target
        windowLoaded = false
        newerCursor = nil
        missedChanges = false
        clearHighlight()

        roomID = room
        hasOlder = false
        isLoadingOlder = false
        olderFailed = false
        isLoadingNewer = false
        problem = nil
        isAwayFromLatest = false
        hasNewerWhileAway = false
        if !inPlace {
            items = []
            typingLine = nil
            lastOutgoingID = nil
            isLoaded = false
            newMessageCount = 0
            isAtBottom = true
            selectedMessageID = nil
            scrollToMessageRequest = nil
        }
    }

    private func startReading() {
        guard roomID != nil, appModel.client != nil else { return }
        if let anchor = anchorID {
            Task { [weak self] in await self?.fetchAround(anchor, reveal: true) }
        } else {
            requestRefetch()
        }
    }

    // MARK: - Reading the engine

    /// The engine was greeted, or said `resync`: read the newest page, and forget the older ones. A chat held at
    /// a message reads the page around it again instead (highlighting it only if it was still opening).
    private func reload(from client: EngineClient) async {
        guard let room = roomID, client === appModel.client else { return }
        learnChat(chat(room), of: room)
        readFeatures()
        if typingLine != nil { readTyping() } // a new engine, or lost changes: whoever was typing may have stopped
        if let anchor = anchorID {
            await fetchAround(anchor, reveal: !windowLoaded)
            return
        }
        dropPending = true
        await fetchNewest()
    }

    /// "Try again" on the bar: read again what failed.
    public func reload() {
        if problem == .messageGone { problem = nil }
        if let anchor = anchorID {
            // Held at a message: read the page around it again (highlighting it only if it never showed).
            let reveal = !windowLoaded
            Task { [weak self] in await self?.fetchAround(anchor, reveal: reveal) }
            return
        }
        requestRefetch()
    }

    private func handle(_ change: Change) {
        guard let open = roomID else { return }
        switch change {
        case let .event(room, _):
            guard room == open else { return }
            if anchorID != nil { hasNewerWhileAway = true }
            requestRefetch()
        case let .status(room, _), let .read(room, _), let .receipt(room):
            // A receipt: my newest message's Delivered or Seen, read with the page as a status is.
            if room == open { requestRefetch() }
        case let .typing(room):
            if room == open { readTyping() }
        case let .room(room):
            // With no room, names or pictures changed in chats unknown: this one may be among them. Its features
            // may have changed too (its bridge writes them as the network's limits change).
            if room == nil || room == open {
                requestRefetch()
                learnChat(chat(open), of: open)
                readFeatures()
            }
        case .bridge, .resync, .spaces, .reminder, .scheduled:
            // resync reads through the app model's connect hooks. Spaces and a reminder change rows, not the chat's
            // events (a reminder that fires brings a room change of its own). Scheduled messages are in no timeline
            // until they are sent, which brings an event.
            break
        }
    }

    /// Reads the newest page. Changes that come while a read is in flight cost one more read, however many. While
    /// the chat is held at a message the newest page isn't read: the request waits until the window reaches it.
    private func requestRefetch() {
        guard roomID != nil else { return }
        if anchorID != nil {
            missedChanges = true
            return
        }
        if refetching {
            refetchAgain = true
            return
        }
        refetching = true
        let owner = generation
        Task { [weak self] in await self?.refetchUntilQuiet(owner: owner) }
    }

    private func refetchUntilQuiet(owner: Int) async {
        var again = true
        while again {
            refetchAgain = false
            await fetchNewest()
            guard owner == generation else { return } // another chat is open: it owns the flags now
            again = refetchAgain
        }
        refetching = false
    }

    /// Reads who is typing in the open chat: its row, by id. Changes that come while a read is in flight cost one more
    /// read, however many.
    private func readTyping() {
        guard roomID != nil else { return }
        if readingTyping {
            typingAgain = true
            return
        }
        readingTyping = true
        let owner = generation
        Task { [weak self] in await self?.readTypingUntilQuiet(owner: owner) }
    }

    private func readTypingUntilQuiet(owner: Int) async {
        var again = true
        while again {
            typingAgain = false
            guard let room = roomID, let client = appModel.client else { break }
            let result: InboxResult? = try? await client.call("inbox.list", InboxListParams(roomIDs: [room]))
            guard owner == generation else { return } // another chat is open: it owns the flags now
            guard client === appModel.client else { break }
            // A read that failed shows no one: a typing line never sticks.
            typingLine = result?.rooms.first { $0.roomID == room }?.typingLine
            again = typingAgain
        }
        readingTyping = false
    }

    private func fetchNewest() async {
        guard let room = roomID, let client = appModel.client else { return }
        let owner = generation
        fetchSerial += 1
        let serial = fetchSerial
        let page: EventsPage
        do {
            page = try await client.call("room.events", RoomEventsParams(roomID: room, limit: Self.pageSize))
        } catch {
            guard owner == generation, client === appModel.client, anchorID == nil else {
                staleAnswerDropped?()
                return
            }
            messageGoneOnNewest = false // the failure is what the bar says now
            problem = .loadFailed
            return
        }
        // Only the answer for the chat that is open now, from the engine that is up now, not older than one
        // already shown, and not while the chat is held at a message.
        guard owner == generation, client === appModel.client, serial > appliedSerial, anchorID == nil else {
            staleAnswerDropped?()
            return
        }
        appliedSerial = serial
        let drop = dropPending
        dropPending = false
        apply(page, dropOlder: drop)
        pagesApplied += 1
    }

    private func apply(_ page: EventsPage, dropOlder: Bool) {
        let first = firstNewest
        let previousOutgoing = lastOutgoingID.flatMap { events[$0] }.map(Self.position)
        let pageIDs = Set(page.events.map(\.eventID))
        let fresh = page.events.filter { !seenIDs.contains($0.eventID) }

        // A page that does not reach back to what is loaded leaves a hole: more came than one page holds. Where the
        // page reaches is its before cursor (its events may be fewer than it covers).
        var hasHole = false
        if let before = page.before, let newestLoaded = events.values.map(Self.position).max() {
            hasHole = Position(ts: before.ts, seq: before.seq) > newestLoaded
        }
        if dropOlder || hasHole {
            events = [:]
            olderCursor = nil
            olderPagesLoaded = false
            pageEpoch += 1
        } else if let before = page.before {
            // What the page covers, down to its before cursor, is what the engine has now: a message it no longer
            // lists (discarded, deleted for me) goes. The page may list fewer events than asked for, even none: the
            // cursor, not the count, says where it ends.
            let from = Position(ts: before.ts, seq: before.seq)
            events = events.filter { Self.position($0.value) < from || pageIDs.contains($0.key) }
        } else {
            // Nothing older: the page is the whole chat (an empty one has no events).
            events = events.filter { pageIDs.contains($0.key) }
        }
        for event in page.events { events[event.eventID] = event }
        seenIDs.formUnion(pageIDs)
        if !olderPagesLoaded { olderCursor = page.before }
        hasOlder = olderCursor != nil
        if messageGoneOnNewest {
            messageGoneOnNewest = false
            problem = .messageGone
        } else if problem != .messageGone {
            problem = nil // the notice that a message is gone stays until the person moves on
        }

        if first || dividerOnNewest {
            dividerOnNewest = false
            firstUnreadID = Timeline.firstUnreadID(events: Array(events.values), me: Timeline.meUserID,
                                                   unread: unreadAtOpen, now: now())
        }
        rebuild()
        isLoaded = true

        if first {
            firstNewest = false
            if attention.isLooking { markRead() }
            readIfReplied()
        } else {
            let incoming = fresh.filter(Timeline.isIncomingMessage)
            if !incoming.isEmpty {
                holdsRead = false // a new message: the chat is read as usual again
                if !isAtBottom { newMessageCount += incoming.count }
                if attention.isLooking { markRead() } else if !incognitoIsOn { needsRead = true }
            }
            // My reply went: a newer message of mine than before is the one that shows Sent. It reads a chat that
            // Incognito or Mark as Unread kept unread (the networks mark it read on a reply anyway, surprise 7).
            // (A reply from another device, or from a notification, while the chat is open.)
            if let mine = lastOutgoingID, let event = events[mine],
               previousOutgoing.map({ Self.position(event) > $0 }) ?? true {
                readAfterReply()
            } else {
                readIfReplied()
            }
        }
        if scrollDownOnNewest {
            scrollDownOnNewest = false
            jumpToBottomRequest += 1
        }
    }

    /// Where an event is in the chat's order: by time, then by arrival.
    private struct Position: Comparable {
        let ts: Int64
        let seq: Int64

        static func < (lhs: Position, rhs: Position) -> Bool { (lhs.ts, lhs.seq) < (rhs.ts, rhs.seq) }
    }

    private static func position(_ event: Event) -> Position { Position(ts: event.ts, seq: event.seq) }

    private func rebuild() {
        items = Timeline.build(events: Array(events.values), me: Timeline.meUserID, firstUnreadID: firstUnreadID,
                               now: now(), hideDeleted: hidesDeleted, isDirect: isDirectChat ?? false,
                               calendar: calendar)
        lastOutgoingID = items.reversed().lazy.compactMap { item -> String? in
            // The one Timeline put Sent, Delivered or Seen under: my newest that went, not a note, not deleted.
            if case let .message(message) = item, message.mine, !message.isNote, message.kind != .deleted,
               message.statusLine?.hasGone == true { message.id } else { nil }
        }.first
        if let selected = selectedMessageID, !items.contains(where: { $0.id == selected }) {
            selectedMessageID = nil
        }
        // My held messages, as the chat has them now: the composer's ⌘Z takes back the newest.
        if roomID != nil, roomID == composer.roomID { composer.updateHeld(from: items) }
        countdownClock = now()
        scheduleWake()
    }

    // MARK: - Disappearing messages

    /// "Messages disappear after 7 days", for the header; nil when the chat has no timer running.
    public var timerLine: String? { Disappearing.headerLine(for: features.currentTimer, locale: locale) }

    /// The header menu: Off, then the timers the chat offers. Empty for a chat with no timer to set (the menu is
    /// not offered).
    public var timerChoices: [DisappearingChoice] { Disappearing.choices(in: features, locale: locale) }

    /// "Change Setting", on a timer-change note: opens the same menu.
    public static var changeSettingTitle: String { String(localized: "Change Setting") }

    /// Asks the engine to set the chat's timer to `choice` (one of `timerChoices`; anything else does nothing).
    /// The header keeps showing the engine's timer: it moves when the engine reports the change, which the call
    /// brings (a room change) and this reads for. A refusal is a toast, and changes nothing.
    public func setTimer(_ choice: DisappearingChoice) async {
        guard let room = roomID, !isChangingTimer,
              let offered = timerChoices.first(where: { $0.type == choice.type && $0.timerMS == choice.timerMS })
        else { return }
        let network = self.network
        guard let client = appModel.client else {
            onToast(EngineErrorText.text(for: EngineError.notConnected, fallback: Self.couldntChangeTimer))
            return
        }
        isChangingTimer = true
        defer { isChangingTimer = false }
        let owner = generation
        do {
            let _: Empty = try await client.call(
                "room.setDisappearing", DisappearingParams(roomID: room, type: offered.type, timerMS: offered.timerMS))
        } catch {
            onToast(Self.describeTimerRefusal(error, network: network))
            return
        }
        // Read what the chat has now, whether or not the room change has come.
        if owner == generation, client === appModel.client { readFeatures() }
    }

    private static var couldntChangeTimer: String { String(localized: "Couldn’t change the timer.") }

    /// A refusal in Courier's words: the network said no (-32023), or the engine's own words for anything else.
    static func describeTimerRefusal(_ error: Error, network: String) -> String {
        if case .rpc(.notSupported, _, _)? = error as? EngineError {
            guard let name = NetworkNames.displayName(of: network) else {
                return String(localized: "Couldn’t change the timer: the network said no.")
            }
            return String(localized: "Couldn’t change the timer: \(name) said no.")
        }
        return EngineErrorText.text(for: error, fallback: couldntChangeTimer)
    }

    /// "Disappears in 1 hour, 30 minutes", under a message with a timer running: whole minutes, rounded up, read
    /// from the model's clock. Nil with none running. For a message of the chat or of the thread pane.
    public func disappearsIn(_ message: TimelineMessage) -> String? {
        Disappearing.countdown(expiresAt: message.expiresAt, now: now(), locale: locale)
    }

    /// The note for a message that is the bridge's note of a timer change ("Ann set messages to disappear after 1
    /// day.", "You set …"); nil for any other message.
    public func timerChangeNote(for message: TimelineMessage) -> String? {
        message.timerChange.map {
            Disappearing.note(for: $0, by: message.senderName, mine: message.mine, locale: locale)
        }
    }

    /// Who to name beside a call note: in a group chat, the caller; nil in a one-to-one chat, while the chat's row is
    /// unknown (so a one-to-one chat never shows a name it doesn't need), for my own call, and for any other message.
    public func callCaller(for message: TimelineMessage) -> String? {
        guard let direct = isDirectChat else { return nil }
        return CallNote.caller(of: message, direct: direct)
    }

    /// Sets the one wake for the soonest change the clock brings to what the chat and the thread pane show: a
    /// message running out (it leaves), or a countdown stepping down a minute. It is set again on every build, so
    /// there is only ever one, and `reset` takes it back with the chat. It is set a hair after the time, and never
    /// nearer than `minimumWake`. When it comes the thread pane and the chat are built again at the model's clock.
    /// If the clock has not moved forward since it was set (it stood still, or was set back), nothing is built and
    /// the wake is set again, from the clock as it is now and never nearer than `minimumWake`.
    private func scheduleWake(threadItems: [TimelineItem]? = nil) {
        wakeTask?.cancel()
        wakeTask = nil
        guard roomID != nil else { return }
        let since = now()
        let pane = thread.roomID == roomID ? (threadItems ?? thread.items) : []
        guard let until = Disappearing.millisUntilNextChange(in: items + pane, now: since) else { return }
        let wait = Duration.milliseconds(max(until, 0)) + Self.wakeSlack
        let sleep = self.sleep
        wakeTask = Task { [weak self] in
            do {
                try await sleep(max(wait, .milliseconds(Self.minimumWake)))
            } catch {
                return // set again by a build, or taken back with the chat
            }
            guard let self, !Task.isCancelled else { return }
            self.wake(since: since)
        }
    }

    private func wake(since: Date) {
        wakeTask = nil
        guard now() > since else {
            scheduleWake()
            return
        }
        thread.clockMoved()
        rebuild() // sets the next wake
    }

    private func cancelWake() {
        wakeTask?.cancel()
        wakeTask = nil
    }

    /// A message of the open chat, as loaded.
    func message(_ eventID: String) -> TimelineMessage? {
        for case let .message(message) in items where message.id == eventID { return message }
        return nil
    }

    // MARK: - A window around a message

    /// Reads the page around `eventID` and shows it in place of everything loaded. `reveal` highlights the
    /// message; the view is asked to scroll to it either way.
    private func fetchAround(_ eventID: String, reveal: Bool) async {
        guard let room = roomID, let client = appModel.client else { return }
        let owner = generation
        fetchSerial += 1
        let serial = fetchSerial
        let page: EventsPage
        do {
            page = try await client.call(
                "room.events", RoomEventsParams(roomID: room, around: eventID, limit: Self.pageSize))
        } catch EngineError.rpc(.notFound, _, _) {
            guard owner == generation, client === appModel.client, anchorID == eventID else { return }
            // Not in this chat any more (deleted since): the newest messages, with a calm notice.
            messageGoneOnNewest = true
            leaveWindow(scrollDown: isLoaded)
            return
        } catch {
            guard owner == generation, client === appModel.client, anchorID == eventID else { return }
            problem = .loadFailed
            return
        }
        // As for the newest page; and only while the chat is still held at this message ("Jump to latest" may
        // have let go of it meanwhile).
        guard owner == generation, client === appModel.client, serial > appliedSerial, anchorID == eventID else {
            staleAnswerDropped?()
            return
        }
        appliedSerial = serial
        applyWindow(page, at: eventID, reveal: reveal)
    }

    private func applyWindow(_ page: EventsPage, at eventID: String, reveal: Bool) {
        // A reply that stays in its thread isn't in the chat's timeline: the engine centred the page on its root
        // (Ruling 23). The chat shows the root, and the thread pane the reply.
        var shown = eventID
        if !page.events.contains(where: { $0.eventID == eventID }) {
            let roots = Self.threadRoots(in: page)
            if roots.count == 1 {
                shown = roots[0]
                openThread(roots[0], at: eventID)
            } else if let nearest = roots.first {
                shown = nearest
                findThread(of: eventID, among: roots, guessed: nearest, reveal: reveal)
            }
        }
        pageEpoch += 1 // an older or newer page asked for before this one joins nothing
        events = [:]
        for event in page.events { events[event.eventID] = event }
        seenIDs = Set(events.keys)
        olderCursor = page.before
        olderPagesLoaded = true // the window's own cursor is the one to go on from, whatever a newest page says
        hasOlder = olderCursor != nil
        newerCursor = page.after
        windowLoaded = true
        if problem != .messageGone { problem = nil }
        firstUnreadID = nil // no "New" divider while away
        if page.after == nil {
            reachedLatest()
        } else {
            isAwayFromLatest = true
        }
        rebuild()
        isLoaded = true
        if reveal { highlight(shown) }
        scrollSerial += 1
        scrollToMessageRequest = MessageScrollRequest(messageID: shown, serial: scrollSerial)
        if shown != eventID, thread.rootID != nil { handOnChat() }
    }

    /// The thread roots of a page centred on one of them, nearest the middle first: the page is centred on the root
    /// of the reply that isn't in it (Ruling 23).
    private static func threadRoots(in page: EventsPage) -> [String] {
        let middle = Double(page.events.count - 1) / 2
        return page.events.enumerated().filter { $0.element.thread != nil }
            .sorted { abs(Double($0.offset) - middle) < abs(Double($1.offset) - middle) }
            .map(\.element.eventID)
    }

    /// With more than one thread on the page: which of them `replyID` is in, read from each thread's pages (at most
    /// `ThreadModel.pagesToFindTarget` in all). The pane opens on the one that has it; if none does (deleted since),
    /// it stays shut.
    private func findThread(of replyID: String, among roots: [String], guessed: String, reveal: Bool) {
        guard let room = roomID, let client = appModel.client else { return }
        let owner = generation
        Task { [weak self] in
            var pages = 0
            for root in roots {
                var cursor: Cursor?
                repeat {
                    guard pages < ThreadModel.pagesToFindTarget else { return }
                    pages += 1
                    let page: EventsPage? = try? await client.call(
                        "room.events", RoomEventsParams(roomID: room, thread: root, before: cursor,
                                                        limit: ThreadModel.pageSize))
                    guard let self, owner == self.generation, client === self.appModel.client else { return }
                    guard let page else { break }
                    if page.events.contains(where: { $0.eventID == replyID }) {
                        self.openThread(root, at: replyID)
                        if root != guessed {
                            // The chat showed the root nearest the page's middle: show the one that has the reply.
                            if reveal { self.highlight(root) }
                            self.scrollSerial += 1
                            self.scrollToMessageRequest = MessageScrollRequest(messageID: root, serial: self.scrollSerial)
                        }
                        return
                    }
                    cursor = page.before
                } while cursor != nil
            }
        }
    }

    /// The view reached the bottom while away: reads the next newer page and adds it below.
    public func loadNewer() {
        guard isAwayFromLatest, let room = roomID, let cursor = newerCursor, !isLoadingNewer,
              let client = appModel.client else { return }
        isLoadingNewer = true
        let owner = generation
        let epoch = pageEpoch
        Task { [weak self] in
            let page: EventsPage?
            do {
                page = try await client.call(
                    "room.events", RoomEventsParams(roomID: room, after: cursor, limit: Self.pageSize))
            } catch {
                page = nil // reaching the bottom again tries again
            }
            guard let self, owner == self.generation else { return }
            self.isLoadingNewer = false
            // The window may have been dropped ("Jump to latest", a resync) while this was out: then it joins nothing.
            guard client === self.appModel.client, epoch == self.pageEpoch, self.isAwayFromLatest, let page else {
                if page != nil { self.staleAnswerDropped?() }
                return
            }
            for event in page.events {
                self.events[event.eventID] = event
                self.seenIDs.insert(event.eventID)
            }
            self.newerCursor = page.after
            if page.after == nil { self.reachedLatest() }
            self.rebuild()
        }
    }

    /// The window reaches the newest message: the chat is live again, from here on as one opened at its newest.
    private func reachedLatest() {
        anchorID = nil
        newerCursor = nil
        isAwayFromLatest = false
        hasNewerWhileAway = false
        firstNewest = false
        // What was unread is still unread (nothing was marked while away): the divider goes above it. Counted now,
        // before this chat is marked read. When something came while away, the count includes messages the
        // window doesn't have yet, so the divider waits for the newest page that brings them.
        unreadAtOpen = roomID.map { unreadCount($0) } ?? 0
        if missedChanges {
            missedChanges = false
            firstUnreadID = nil
            dividerOnNewest = true
            requestRefetch()
        } else {
            firstUnreadID = Timeline.firstUnreadID(events: Array(events.values), me: Timeline.meUserID,
                                                   unread: unreadAtOpen, now: now())
        }
        if attention.isLooking { markRead() } else if !incognitoIsOn { needsRead = true }
    }

    /// Lets go of the window and reads the newest page instead, as when the chat was opened.
    private func leaveWindow(scrollDown: Bool) {
        anchorID = nil
        windowLoaded = false
        newerCursor = nil
        missedChanges = false
        isAwayFromLatest = false
        hasNewerWhileAway = false
        newMessageCount = 0
        clearHighlight()
        pageEpoch += 1 // older and newer pages of the window join nothing now
        dropPending = true
        firstNewest = true
        unreadAtOpen = roomID.map { unreadCount($0) } ?? 0
        needsRead = !incognitoIsOn
        scrollDownOnNewest = scrollDown
        requestRefetch()
    }

    private func highlight(_ eventID: String) {
        highlightTask?.cancel()
        highlightedMessageID = eventID
        let sleep = self.sleep
        highlightTask = Task { [weak self] in
            do {
                try await sleep(Self.highlightDuration)
            } catch {
                return // a newer highlight, or another chat, took over
            }
            guard let self, !Task.isCancelled else { return }
            self.highlightedMessageID = nil
            self.highlightTask = nil
        }
    }

    private func clearHighlight() {
        highlightTask?.cancel()
        highlightTask = nil
        highlightedMessageID = nil
    }

    // MARK: - Older messages

    /// Reads the next older page, when the view scrolls to the top.
    public func loadOlder() {
        guard let room = roomID, let cursor = olderCursor, !isLoadingOlder, let client = appModel.client else { return }
        isLoadingOlder = true
        olderFailed = false
        let owner = generation
        let epoch = pageEpoch
        Task { [weak self] in
            let page: EventsPage?
            do {
                page = try await client.call(
                    "room.events", RoomEventsParams(roomID: room, before: cursor, limit: Self.pageSize))
            } catch {
                page = nil
            }
            guard let self, owner == self.generation else { return }
            self.isLoadingOlder = false
            // The pages may have been dropped (a resync) while this was out: then it joins nothing.
            guard client === self.appModel.client, epoch == self.pageEpoch else { return }
            guard let page else {
                self.olderFailed = true
                return
            }
            for event in page.events {
                self.events[event.eventID] = event
                self.seenIDs.insert(event.eventID)
            }
            self.olderPagesLoaded = true
            self.olderCursor = page.before
            self.hasOlder = page.before != nil
            self.rebuild()
            // Pages are read by cursor, not by count: one with no events (cut to stay under 1 MiB, or every
            // message in it deleted for me) and a cursor further back reads on.
            if page.events.isEmpty, let next = page.before, next != cursor { self.loadOlder() }
        }
    }

    /// A message of mine was sent from one of this chat's composers.
    private func sent(_ eventID: String, in room: String) {
        guard room == roomID else { return }
        mySends.insert(eventID)
        readIfReplied() // the page that shows it gone may have come first
    }

    /// One of my sends from here has gone: that is a reply.
    private func readIfReplied() {
        guard !mySends.isEmpty else { return }
        // The event's own status, not the status line: only my newest message shows one.
        let gone = mySends.filter { id in
            events[id].map { StatusLine.of(status: $0.status, reason: $0.statusReason).hasGone } ?? false
        }
        guard !gone.isEmpty else { return }
        mySends.subtract(gone)
        readAfterReply()
    }

    /// A reply reads a chat that Incognito or Mark as Unread kept unread (the networks mark it read on a reply
    /// anyway, surprise 7). Otherwise the chat is read as usual and there is nothing to do.
    private func readAfterReply() {
        guard holdsRead || incognitoIsOn else { return }
        holdsRead = false
        markRead(reply: true)
    }

    // MARK: - Incognito

    /// Incognito is on: the setting, and the plan has it. The composer's mark shows while this is (and "Show the
    /// incognito mark in the message box" is on).
    public var incognitoIsOn: Bool { preferences?.incognito == true && isEntitled(.incognito) }

    /// "Turn on incognito mode" and "Turn off incognito mode", from Settings and the command bar. On needs the plan.
    /// Turning it on while my typing shows asks whether to hide that too (`asksToHideTyping`). Inferred (inventory
    /// 01 §7 "asks whether to also hide typing"): the question's wording is Courier's.
    public func setIncognito(_ on: Bool) {
        guard let preferences, preferences.incognito != on else { return }
        if on, !isEntitled(.incognito) { return }
        preferences.incognito = on
        asksToHideTyping = on && preferences.showTyping
    }

    /// The answer to `hideTypingQuestion`: Hide Typing turns "Show recipients I'm typing" off; Keep Showing leaves it.
    public func answerHideTyping(_ hide: Bool) {
        guard asksToHideTyping else { return }
        asksToHideTyping = false
        if hide { preferences?.showTyping = false }
    }

    public static var hideTypingQuestion: String { String(localized: "Also hide that you’re typing?") }
    public static var hideTypingButton: String { String(localized: "Hide Typing") }
    public static var keepShowingTypingButton: String { String(localized: "Keep Showing") }

    // MARK: - Reading and scrolling

    /// The window of the open chat became key, or stopped being key (or the conversation view went away).
    public func setWindowKey(_ isKey: Bool) {
        attention.setWindowKey(isKey)
    }

    /// The person is looking again: what waited for them is read now.
    private func personReturned() {
        if needsRead, isLoaded { markRead() }
    }

    /// Tells the engine the open chat is read. The engine does nothing for a chat that already is. Not after Mark as
    /// Unread from a message that stayed on the chat, until it is reopened, a new message comes or I reply; and not
    /// while Incognito is on, unless I replied (`reply`).
    private func markRead(reply: Bool = false) {
        needsRead = false
        guard !holdsRead, reply || !incognitoIsOn, let room = roomID, let client = appModel.client else { return }
        readsSent += 1
        Task {
            // A failure is ignored: the unread count shows the truth the next time the inbox reads.
            let _: Empty? = try? await client.call("room.markRead", RoomParams(roomID: room))
        }
    }

    /// The view says whether the newest message is on screen.
    public func scrolled(toBottom: Bool) {
        guard isAtBottom != toBottom else { return }
        isAtBottom = toBottom
        if toBottom { newMessageCount = 0 }
    }

    /// ⌘↓, the jump button ("Jump to latest" while away), and sending: scroll to the newest message. While the
    /// chat is held at a message, its window is dropped and the newest page read first; the view scrolls when it
    /// is in.
    public func jumpToBottom() {
        if anchorID != nil {
            leaveWindow(scrollDown: true)
        } else {
            jumpToBottomRequest += 1
        }
    }

    // MARK: - Actions

    /// Starts a reply to the message in the composer.
    public func reply(to eventID: String) {
        for case let .message(message) in items where message.id == eventID && message.kind != .deleted {
            composer.startReply(to: message.quoted)
            return
        }
    }

    /// ⌘R: replies to the selected message.
    public func replyToSelected() {
        guard let id = selectedMessageID else { return }
        reply(to: id)
    }

    /// The selected message, as loaded.
    public var selectedMessage: TimelineMessage? { selectedMessageID.flatMap(message) }

    /// A message by its ID, looked for where it was acted on first (the chat, or the thread pane open on this
    /// chat), then in the other: a reply is only in the pane, and a thread's root is in both.
    public func message(_ eventID: String, from source: MessageSource) -> TimelineMessage? {
        let pane = thread.roomID != nil && thread.roomID == roomID ? thread.message(eventID) : nil
        switch source {
        case .chat: return message(eventID) ?? pane
        case .thread: return pane ?? message(eventID)
        }
    }

    /// What Reply is for `message` in this chat: Reply, or where replies are thread replies (Slack), Reply in
    /// Thread; nil where it has neither (an SMS chat).
    public func replyAction(for message: TimelineMessage) -> MessageAction? {
        let offered = availableActions(for: message).actions
        if offered.contains(.reply) { return .reply }
        if offered.contains(.replyInThread) { return .replyInThread }
        return nil
    }

    /// ↑ with "Move focus to the message list": selects the message before the selected one, or with none selected
    /// the newest, so ↑↑↑ walks up the chat. False with no message to select.
    @discardableResult
    public func selectOlderMessage() -> Bool {
        let ids = items.compactMap { item -> String? in if case let .message(message) = item { message.id } else { nil } }
        guard let newest = ids.last else { return false }
        guard let selected = selectedMessageID, let index = ids.firstIndex(of: selected) else {
            selectedMessageID = newest
            return true
        }
        if index > 0 { selectedMessageID = ids[index - 1] }
        return true
    }

    /// What `message` offers in the open chat now, and what it shows greyed with why. Reply Privately only in a chat
    /// known to be a group, on a network that runs this session.
    public func availableActions(for message: TimelineMessage) -> (actions: [MessageAction], unavailable: [Unavailable]) {
        MessageActions.available(for: message, in: features, network: network, now: now(), locale: locale,
                                 isDirect: isDirectChat ?? true, networkRunning: networkRuns)
    }

    /// The open chat's network runs this session: the engine has started it (it may still be signing in).
    private var networkRuns: Bool {
        guard let account = appModel.accounts.first(where: { $0.network == network }) else { return false }
        return account.state != .notStarted && account.state != .starting
    }

    /// ⌘T (02 §2.2 "Message: Edit"): edits the selected message if it is mine and can be edited, else my newest
    /// message the chat still lets me edit. False when there is none.
    @discardableResult
    public func editSelectedOrLast() -> Bool {
        if let selected = selectedMessage, availableActions(for: selected).actions.contains(.edit) {
            composer.startEditing(selected)
            return true
        }
        for case let .message(message) in items.reversed() where message.mine {
            if availableActions(for: message).actions.contains(.edit) {
                composer.startEditing(message)
                return true
            }
        }
        return false
    }

    /// ⌘⇧H: the selected message's first link, for the view to open; nil when it has none.
    public func firstLinkOfSelected() -> URL? {
        guard let selected = selectedMessage, availableActions(for: selected).actions.contains(.openFirstLink) else {
            return nil
        }
        return MessageActions.firstLink(in: selected.rich)
    }

    /// ⌘⇧R: reacts to the selected message with the quick reaction (Settings ▸ Messages).
    public func quickReactToSelected() async {
        guard let selected = selectedMessage, availableActions(for: selected).actions.contains(.react) else { return }
        await react(to: selected.id, key: preferences?.quickReaction ?? "❤️")
    }

    /// ⌘↓ ("Show Replies"): on a selected thread root, opens its thread; otherwise scrolls to the newest message.
    public func showRepliesOrJumpToBottom() {
        if let selected = selectedMessage, selected.thread != nil {
            openThread(selected.id)
        } else {
            jumpToBottom()
        }
    }

    /// Reads the open chat again, and the thread pane open on it: after an action whose result the engine stores
    /// without telling (a bookmark, Delete for Me) or tells only for the event it changed (a vote, an unsend).
    public func refresh() {
        requestRefetch()
        if let room = roomID, thread.roomID == room { thread.refresh() }
    }

    public func react(to eventID: String, key: String) async {
        await act { client, room in
            let _: Sent = try await client.call("message.react", ReactParams(roomID: room, eventID: eventID, key: key))
        }
    }

    /// Sends a message that failed again, as the same message.
    public func retry(_ eventID: String) async {
        await act { client, _ in
            let _: Empty = try await client.call("message.retry", EventParams(eventID: eventID))
        }
    }

    /// Deletes a message that failed, from this device only.
    public func discard(_ eventID: String) async {
        await act { client, _ in
            let _: Empty = try await client.call("message.discard", EventParams(eventID: eventID))
        }
    }

    // MARK: - Mark as Unread, Reply Privately

    /// Mark as Unread on a message: the chat's unread count runs from it on (room.setUnreadFrom, on this Mac only),
    /// then "After marking the open chat read or unread" says where to go (`planAfterToggleRead`, the inbox's rule).
    /// Staying on the chat, it isn't marked read again until it is reopened or a new message comes (Inferred
    /// (inventory 02 §3.4.2 item 8)). A refusal is a toast, and nothing moves.
    public func markUnread(from messageID: String) async {
        guard let room = roomID, let sender = composer.sender, let message = message(messageID, from: .chat),
              availableActions(for: message).actions.contains(.markUnread) else { return }
        let owner = generation
        let after = planAfterToggleRead()
        do {
            try await sender.setUnreadFrom(eventID: messageID)
        } catch {
            guard owner == generation else { return }
            onToast(EngineErrorText.text(for: error, fallback: String(localized: "Couldn’t mark the chat unread.")))
            return
        }
        guard owner == generation, room == roomID else { return }
        holdsRead = true
        needsRead = false
        after()
    }

    /// Reply Privately on someone's message in a group: the one-to-one chat with them (room.directChat: Courier's own,
    /// or one the network makes) opens, with the message quoted in its composer (`ComposerModel.startPrivateReply`)
    /// once that chat's features are read. A refusal is a toast in Courier's words, and the group stays open.
    public func replyPrivately(to messageID: String) async {
        guard let room = roomID, let sender = composer.sender, let message = message(messageID, from: .chat),
              availableActions(for: message).actions.contains(.replyPrivately) else { return }
        let owner = generation
        let network = self.network
        let target: String
        do {
            target = try await sender.directChat(roomID: room, userID: message.sender)
        } catch {
            guard owner == generation else { return }
            onToast(Self.describeDirectChatRefusal(error, network: network))
            return
        }
        guard owner == generation else { return } // the person has moved on: they aren't taken away
        pendingPrivateReply = (target, message)
        if target == roomID {
            putInPrivateReply()
        } else {
            appModel.open(.chat(roomID: target))
        }
    }

    /// Reply Privately's quote, into the composer of the chat it was for, once.
    private func putInPrivateReply() {
        guard let pending = pendingPrivateReply, pending.roomID == roomID, composer.roomID == pending.roomID
        else { return }
        pendingPrivateReply = nil
        composer.startPrivateReply(quoting: pending.message, in: features)
    }

    /// Why a private chat couldn't be had, in Courier's words: the network can't reach the person or start chats
    /// (-32023), or the person isn't in the group as far as Courier knows (-32020); the engine's words otherwise.
    static func describeDirectChatRefusal(_ error: Error, network: String) -> String {
        switch error as? EngineError {
        case .rpc(.notSupported, _, _)?:
            guard let name = NetworkNames.displayName(of: network) else {
                return String(localized: "The network can’t start a chat with this person.")
            }
            return String(localized: "\(name) can’t start a chat with this person.")
        case .rpc(.notFound, _, _)?:
            return String(localized: "That person isn’t in this chat any more.")
        default:
            return EngineErrorText.text(for: error, fallback: String(localized: "Couldn’t open a private chat."))
        }
    }

    private func act(_ call: (EngineClient, String) async throws -> Void) async {
        guard let room = roomID, let client = appModel.client else { return }
        let owner = generation
        do {
            try await call(client, room)
        } catch {
            guard owner == generation, client === appModel.client else { return }
            problem = .actionFailed(Self.describe(error))
        }
        // Whatever the answer was, the store knows best: read it. (A call that was not answered may still have
        // happened, and is never repeated.)
        if owner == generation { requestRefetch() }
    }

    static func describe(_ error: Error) -> String {
        EngineErrorText.text(for: error, fallback: String(localized: "Courier’s engine could not do that."))
    }
}
