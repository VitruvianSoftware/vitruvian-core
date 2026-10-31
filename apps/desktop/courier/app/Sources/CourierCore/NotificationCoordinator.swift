// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The system's notification centre, as the coordinator uses it. The app's adapter is `UNUserNotificationCenter`;
/// tests give a fake. An adapter in a process with no app bundle (a bare `swift run`) does nothing, because the
/// real centre aborts there.
@MainActor
public protocol NotificationDelivering: AnyObject {
    /// Asks the person to allow notifications. The system asks once; later calls do nothing.
    func requestPermission()
    /// Shows a notification, grouped by chat. The same event shown twice is shown once.
    func deliver(_ content: NotificationContent)
    /// Takes down what is shown for a chat (it was read).
    func clear(roomID: String)
    /// Takes down one notification, by its id (`NotificationContent.eventID`), if it is shown.
    func remove(notificationID: String)
    /// Takes down all delivered and pending notifications (e.g. when Courier locks).
    func clearAll()
    /// Opens the macOS System Settings Notifications pane.
    func openSystemNotificationSettings()
    /// Removes delivered notifications, restarts the macOS NotificationCenter daemon, and re-requests settings.
    func restartNotificationCenter()
}

extension NotificationDelivering {
    public func clearAll() {}
    public func openSystemNotificationSettings() {}
    public func restartNotificationCenter() {}
}

@MainActor
public protocol ClipboardSink: AnyObject {
    func copyOTP(_ code: String)
}

@MainActor
public protocol SoundEffectPlaying: AnyObject {
    func play(_ effect: SoundEffectEvent, volume: Double)
}

@MainActor
public protocol NotificationTimerScheduling: AnyObject {
    @discardableResult
    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () async -> Void) -> UUID
    func cancel(_ id: UUID)
}

@MainActor
public final class ManualNotificationScheduler: NotificationTimerScheduling {
    private struct Entry {
        let id: UUID
        let fireAt: TimeInterval
        let action: @MainActor () async -> Void
    }

    private var now: TimeInterval = 0
    private var entries: [Entry] = []

    public init() {}

    @discardableResult
    public func schedule(after seconds: TimeInterval, action: @escaping @MainActor () async -> Void) -> UUID {
        let id = UUID()
        entries.append(Entry(id: id, fireAt: now + max(0, seconds), action: action))
        return id
    }

    public func cancel(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public func advance(by seconds: TimeInterval) async {
        let target = now + max(0, seconds)
        while let nextIndex = entries.indices.min(by: { entries[$0].fireAt < entries[$1].fireAt }),
              entries[nextIndex].fireAt <= target {
            let entry = entries.remove(at: nextIndex)
            now = entry.fireAt
            await entry.action()
        }
        now = target
    }
}

@MainActor
final class TaskNotificationTimerScheduler: NotificationTimerScheduling {
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(sleep: @escaping @Sendable (TimeInterval) async -> Void) {
        self.sleep = sleep
    }

    @discardableResult
    func schedule(after seconds: TimeInterval, action: @escaping @MainActor () async -> Void) -> UUID {
        let id = UUID()
        let sleep = self.sleep
        tasks[id] = Task { @MainActor [weak self] in
            await sleep(seconds)
            guard !Task.isCancelled, self?.tasks.removeValue(forKey: id) != nil else { return }
            await action()
        }
        return id
    }

    func cancel(_ id: UUID) {
        tasks.removeValue(forKey: id)?.cancel()
    }
}

/// Turns the engine's new events into notifications, and what is done on a notification into engine calls.
///
/// A `changed` event says only that a chat has a new event, so the coordinator reads that chat's newest page and
/// looks at each event it has not looked at before. Every event it reads is noted, notified or not: a message
/// that was silent because the chat was open stays silent when the person looks away.
///
/// A burst of changes in one chat is read once: the first change opens a short window, changes inside it add
/// nothing, and the read follows; a change that comes while that read is in flight asks for one more after it. So
/// the first sync's hundreds of events in a chat cost two reads, not hundreds. A chat the inbox has not listed
/// (a new chat, an archived one, or one further down than the pages read) is looked up by its id:
/// `inbox.list {room_ids: [id]}`, never a read of the whole inbox, which comes a page at a time.
///
/// An answer is used only if it came from the client that is up now, as the other models do.
///
/// **Send later** (Review Focus 3): a scheduled message that won't go by itself is told once. One canceled because
/// they wrote first says "A scheduled message to Ann wasn’t sent: they wrote first."; one that missed its time while
/// Courier was closed says it missed its time. Every chat's list is read when the engine is greeted (a message missed
/// while Courier was closed is found then), and a chat's whenever the engine says its scheduled messages changed.
/// What was told is kept in UserDefaults, by chat, message, state and when it was last set, so reading the list
/// again, or Courier starting again, tells nothing twice; a message rescheduled and then canceled again is news. While
/// the person is looking at that chat there is no banner (its strip says so), and it counts as told.
///
/// **Someone starts typing** ("Notify when someone starts typing", off by default): a `typing` change reads the
/// chat's row by id, as the engine has it now, and the first one in a burst that `NotificationPolicy.shouldNotifyTyping`
/// allows is told, once ("Ana is typing…"); more typing changes in that burst tell nothing. The burst ends when the
/// chat's typing is empty again (its notification is taken down) or when their message comes (taken down, and the
/// message's own notification shows in the same stack). Inferred (inventory 02 §1.5). While the setting is off, a
/// typing change reads nothing, unless it ends a burst already told.
@MainActor
public final class NotificationCoordinator {
    /// How many of a chat's newest events are read for one change. A burst larger than this loses its oldest
    /// messages, which is fine for a notification.
    public static let pageSize = 10
    /// "Remind in 1 Hour" and "Remind in 8 Hours", in seconds.
    public static let remindOneHour: TimeInterval = 3600, remindEightHours: TimeInterval = 28800

    private let appModel: AppModel
    private let delivery: any NotificationDelivering
    private let preferences: InboxPreferences
    private let entitlement: any EntitlementProvider
    private let row: @MainActor (String) -> InboxRow?
    private let isLooking: @MainActor () -> Bool
    private let isAwayFromLatest: @MainActor () -> Bool
    private let isIncognito: @MainActor () -> Bool
    private let isAppLocked: @MainActor () -> Bool
    private let restoreDraft: @MainActor (_ roomID: String, _ text: String, _ mayHaveBeenSent: Bool) -> Void
    private let replyTimeout: TimeInterval?
    private let showWindow: @MainActor () -> Void
    private let window: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let clock: @Sendable () -> Date
    private let scheduler: any NotificationTimerScheduling
    private let clipboard: (any ClipboardSink)?
    private let soundEffects: (any SoundEffectPlaying)?
    private var seen = SeenEvents()
    /// Chats with a read waiting for its window, or in flight.
    private var scheduled: Set<String> = []
    /// Chats with a read in flight, and those that changed again during it.
    private var inFlight: Set<String> = []
    private var readAgain: Set<String> = []
    /// Where what was told about scheduled messages is kept.
    private let defaults: UserDefaults
    /// Tests: how many scheduled lists have been read and looked at, to wait for that instead of for a while.
    private(set) var scheduledReads = 0

    /// Chats whose typing burst has been told: their notification is up, until the burst ends.
    private var typingTold: Set<String> = []
    /// Typing changes not yet covered by a read, by chat; a chat in `typingReading` has a read under way.
    private var typingWaiting: [String: Int] = [:]
    private var typingReading: Set<String> = []
    /// Goes up for a chat each time their message ends its burst: a typing read that started before is dropped, so
    /// "is typing…" never shows after the message it was about.
    private var typingEpoch: [String: Int] = [:]
    /// Tests: how many typing changes have been dealt with (read and acted on, or not read at all).
    private(set) var typingChangesHandled = 0

    /// Pending delayed-delivery and repeat-unread timer IDs per chat, canceled when the chat is read.
    private var pendingTimerIDsByRoom: [String: Set<UUID>] = [:]
    /// Most recent extracted OTP code per chat (in-memory only), for the "Copy Code" notification button.
    private var latestOTPByRoom: [String: String] = [:]
    private var lockObserver: NSObjectProtocol?

    /// The UserDefaults key of the scheduled messages already told about.
    public static let toldScheduledKey = "courier.notifications.toldScheduled"
    /// The most kept: the oldest go first. A message long gone needs no memory.
    static let maxToldScheduled = 1000

    /// - Parameters:
    ///   - isIncognito: Incognito is on (`ConversationModel.incognitoIsOn`): a reminder for the chat being read
    ///     then only ends the reminder, as one for a chat shown away from its newest does.
    ///   - row: the inbox's row for a chat, if it has one (its name and whether it is muted).
    ///   - isLooking: whether the person is looking at the open chat (`Attention.isLooking`).
    ///   - isAwayFromLatest: whether the open chat shows older history that doesn't reach its newest message (it was
    ///     opened at a search result: `ConversationModel.isHeldAwayFromLatest`).
    ///   - restoreDraft: puts text that could not be sent into a chat's composer draft; the last argument says the
    ///     engine did not answer, so it may have been sent.
    ///   - replyTimeout: how long a reply waits for the engine; nil is the client's own limit (30 s).
    ///   - showWindow: brings the main window forward, opening it again if it was closed.
    ///   - preferences: the inbox's settings: whether requests notify, and when a reminder brings a chat back. It
    ///     must be the object the Settings screen changes (`InboxModel.preferences`), not a copy: it reads the
    ///     defaults once, so a copy would not see a change until the next launch. Required for that reason.
    ///   - entitlement: whether the plan includes reminders (the remind-later buttons set one). It must be the same
    ///     provider the `Notifier` was given, so the buttons shown and the buttons that work agree (part 4.7).
    ///   - window: how long a chat's changes are gathered before it is read, in seconds.
    ///   - sleep: waits `window`.
    ///   - clock: the time now; tests give one they move.
    ///   - defaults: where what was told about scheduled messages is kept; tests give a suite of their own.
    public init(appModel: AppModel, delivery: any NotificationDelivering,
                row: @escaping @MainActor (String) -> InboxRow?, isLooking: @escaping @MainActor () -> Bool,
                isAwayFromLatest: @escaping @MainActor () -> Bool = { false },
                isIncognito: @escaping @MainActor () -> Bool = { false },
                isAppLocked: @escaping @MainActor () -> Bool = { false },
                restoreDraft: @escaping @MainActor (_ roomID: String, _ text: String, _ mayHaveBeenSent: Bool) -> Void,
                showWindow: @escaping @MainActor () -> Void, preferences: InboxPreferences,
                entitlement: any EntitlementProvider = AlwaysEntitled(), window: TimeInterval = 0.1,
                replyTimeout: TimeInterval? = nil,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { await waitForInboxWindow($0) },
                clock: @escaping @Sendable () -> Date = { Date() }, defaults: UserDefaults = .standard,
                scheduler: (any NotificationTimerScheduling)? = nil,
                clipboard: (any ClipboardSink)? = nil,
                soundEffects: (any SoundEffectPlaying)? = nil) {
        self.appModel = appModel
        self.delivery = delivery
        self.preferences = preferences
        self.entitlement = entitlement
        self.row = row
        self.isLooking = isLooking
        self.isAwayFromLatest = isAwayFromLatest
        self.isIncognito = isIncognito
        self.isAppLocked = isAppLocked
        self.restoreDraft = restoreDraft
        self.replyTimeout = replyTimeout
        self.showWindow = showWindow
        self.window = window
        self.sleep = sleep
        self.clock = clock
        self.defaults = defaults
        self.scheduler = scheduler ?? TaskNotificationTimerScheduler(sleep: sleep)
        self.clipboard = clipboard
        self.soundEffects = soundEffects
        appModel.onChange { [weak self] change in self?.handle(change) }
        appModel.onConnect { [weak self] client in await self?.readScheduled(roomID: nil, with: client) }
        lockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didLockNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.latestOTPByRoom.removeAll()
                self?.delivery.clearAll()
            }
        }
        if isCurrentlyLocked {
            delivery.clearAll()
        }
    }

    deinit {
        if let lockObserver {
            NotificationCenter.default.removeObserver(lockObserver)
        }
    }

    private var isCurrentlyLocked: Bool {
        isAppLocked() || !AppLockGate.shared.canPerform(.other)
    }

    /// Asks for permission to notify; the app calls it once at launch.
    public func start() {
        delivery.requestPermission()
    }

    public func handle(_ change: Change) {
        switch change {
        case let .event(roomID, _):
            examine(roomID: roomID)
        case let .read(roomID, _):
            cancelTimers(forRoomID: roomID)
            latestOTPByRoom.removeValue(forKey: roomID)
            delivery.clear(roomID: roomID)
        case let .reminder(roomID):
            Task { [weak self] in await self?.announceReminder(roomID: roomID) }
        case let .scheduled(roomID):
            guard let client = appModel.client else { return }
            Task { [weak self] in await self?.readScheduled(roomID: roomID, with: client) }
        case let .typing(roomID):
            typingChanged(roomID)
        default:
            break
        }
    }

    // MARK: - New events

    private func examine(roomID: String) {
        guard appModel.client != nil, appModel.connectedAt != nil else { return }
        if inFlight.contains(roomID) {
            readAgain.insert(roomID)
            return
        }
        guard scheduled.insert(roomID).inserted else { return } // inside the window already: covered
        Task { [weak self, sleep, window] in
            await sleep(window)
            await self?.readUntilQuiet(roomID)
        }
    }

    /// Reads the chat, and again for as long as changes came in during a read.
    private func readUntilQuiet(_ roomID: String) async {
        inFlight.insert(roomID)
        repeat {
            readAgain.remove(roomID)
            await readOnce(roomID)
        } while readAgain.contains(roomID)
        inFlight.remove(roomID)
        scheduled.remove(roomID)
    }

    private func readOnce(_ roomID: String) async {
        guard let client = appModel.client else { return }
        let page: EventsPage? = try? await client.call(
            "room.events", RoomEventsParams(roomID: roomID, limit: Self.pageSize))
        guard let page, client === appModel.client else { return }
        // The row is the inbox's when it has the chat, and read only for a chat it has not listed yet.
        var chat = row(roomID)
        if chat == nil {
            chat = await lookUp(roomID, with: client)
            guard client === appModel.client else { return }
        }
        guard let chat else { return }
        announce(page.events, in: chat)
    }

    /// The chat's row, wherever it is (archived, hidden, in another space). Nil when the engine doesn't have it.
    private func lookUp(_ roomID: String, with client: EngineClient) async -> InboxRow? {
        let result: InboxResult? = try? await client.call("inbox.list", InboxListParams(roomIDs: [roomID]))
        return result?.rooms.first { $0.roomID == roomID }
    }

    // MARK: - Someone starts typing

    /// A chat's typing changed. Read once for however many changes come while a read is under way.
    private func typingChanged(_ roomID: String) {
        guard preferences.typingNotifications || typingTold.contains(roomID), appModel.client != nil else {
            typingChangesHandled += 1
            return
        }
        typingWaiting[roomID, default: 0] += 1
        guard typingReading.insert(roomID).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            while let covered = self.typingWaiting.removeValue(forKey: roomID) {
                await self.readTyping(roomID)
                self.typingChangesHandled += covered
            }
            self.typingReading.remove(roomID)
        }
    }

    private func readTyping(_ roomID: String) async {
        guard let client = appModel.client else { return }
        let epoch = typingEpoch[roomID, default: 0]
        let row = await lookUp(roomID, with: client)
        guard client === appModel.client, typingEpoch[roomID, default: 0] == epoch else { return }
        // A read that fails shows no one: a notification that is up never sticks.
        guard let row, !row.typing.isEmpty else {
            endTypingBurst(roomID)
            return
        }
        guard !typingTold.contains(roomID), let context = context(),
              NotificationPolicy.shouldNotifyTyping(room: row, context: context, on: preferences.typingNotifications)
        else { return }
        typingTold.insert(roomID)
        deliverRespectingLock(NotificationPolicy.typingContent(room: row))
    }

    /// The burst is over: its notification, if one was told, comes down.
    private func endTypingBurst(_ roomID: String) {
        guard typingTold.remove(roomID) != nil else { return }
        delivery.remove(notificationID: NotificationPolicy.typingID(roomID: roomID))
    }

    private func deliverRespectingLock(_ content: NotificationContent) {
        delivery.deliver(NotificationPolicy.redactIfLocked(content, isLocked: isCurrentlyLocked))
    }

    private func resolveAccountKey(for room: InboxRow) -> String? {
        let loginName = room.loginName.trimmingCharacters(in: .whitespacesAndNewlines)
        let logins = appModel.accounts
            .filter { $0.network == room.network }
            .flatMap(\.logins)
        if !loginName.isEmpty {
            if let match = logins.first(where: { $0.accountID == loginName || $0.remoteName == loginName }) {
                return "\(room.network):\(match.accountID)"
            }
            return room.network.isEmpty ? loginName : "\(room.network):\(loginName)"
        }
        if logins.count == 1, let only = logins.first, !only.accountID.isEmpty {
            return "\(room.network):\(only.accountID)"
        }
        return nil
    }

    /// What the decision depends on now; nil before the app is connected.
    private var effectiveIsLooking: Bool {
        !isCurrentlyLocked && isLooking()
    }

    private func context() -> NotificationPolicy.Context? {
        guard let connectedAt = appModel.connectedAt else { return nil }
        return NotificationPolicy.Context(
            me: Timeline.meUserID, connectedAt: Self.millis(connectedAt), now: Self.millis(clock()),
            openRoomID: appModel.selectedRoomID, openMemberRoomIDs: Set(appModel.openRoomIDs),
            isLooking: effectiveIsLooking, requestNotifications: preferences.requestNotifications,
            notifyWhenInFocus: preferences.notifications.notifyWhenInFocus,
            notifyOnReaction: preferences.notifications.notifyOnReaction,
            isAppLocked: isCurrentlyLocked)
    }

    // MARK: - Send later

    /// Reads a chat's scheduled messages (or, with nil, every chat's) and tells each newly canceled or missed one.
    private func readScheduled(roomID: String?, with client: EngineClient) async {
        guard client === appModel.client else { return }
        let result: ScheduledResult? = try? await client.call("scheduled.list", RoomOptionalParams(roomID: roomID))
        guard let result, client === appModel.client else { return }
        var told = defaults.stringArray(forKey: Self.toldScheduledKey) ?? []
        var known = Set(told)
        var news: [ScheduledMessage] = []
        for message in result.scheduled where message.state == .canceled || message.state == .missed {
            let key = Self.toldKey(message)
            guard known.insert(key).inserted else { continue }
            told.append(key)
            news.append(message)
        }
        if let roomID {
            // A chat's own list is the whole of it: what it no longer has needs no memory.
            let current = Set(result.scheduled.map(Self.toldKey))
            told.removeAll { $0.hasPrefix(Self.toldPrefix(roomID)) && !current.contains($0) }
        }
        if told.count > Self.maxToldScheduled { told.removeFirst(told.count - Self.maxToldScheduled) }
        // Kept before it is told: a Courier that stops in between tells it never rather than twice.
        defaults.set(told, forKey: Self.toldScheduledKey)
        for message in news {
            // The chat in front shows it in the strip above its composer: told (kept above), with no banner, as a
            // reminder for the chat in front isn't one.
            if effectiveIsLooking, appModel.isOpen(roomID: message.roomID) { continue }
            var chat = row(message.roomID)
            if chat == nil {
                chat = await lookUp(message.roomID, with: client)
                guard client === appModel.client else { break }
            }
            deliverRespectingLock(NotificationPolicy.scheduledContent(message, room: chat))
        }
        scheduledReads += 1
    }

    /// What a told scheduled message is remembered by: its chat, its outbox ID, the state told and when it was last
    /// set (a new time makes it a new message to tell about).
    private static func toldKey(_ message: ScheduledMessage) -> String {
        toldPrefix(message.roomID) + "\(message.outboxID)\t\(message.state.rawValue)\t\(message.setAt)"
    }

    private static func toldPrefix(_ roomID: String) -> String { roomID + "\t" }

    // MARK: - Reminders

    /// One notification for a reminder that came due, whatever the chat's state: muted, low priority and hidden
    /// chats too, but not the chat the person is looking at. The engine says it once per reminder, and so does this.
    private func announceReminder(roomID: String) async {
        // Ruling 37: the person is reading that chat, so the reminder has done its job. No notification; the chat is
        // marked read, as reading it would, which ends the fired reminder and its unread mark. But when the chat
        // shows an older part of its history (opened at a search result), its newest messages haven't been read:
        // only the reminder is ended, and they stay unread until the person reaches them.
        if effectiveIsLooking, appModel.isOpen(roomID: roomID) {
            // Incognito reads nothing either: its promise holds until I reply or mark the chat read by hand.
            if isAwayFromLatest() || isIncognito() {
                await clearReminder(roomID: roomID)
            } else {
                await markRead(roomID: roomID)
            }
            return
        }
        var chat = row(roomID)
        if chat == nil, let client = appModel.client {
            chat = await lookUp(roomID, with: client)
            guard client === appModel.client else { return }
        }
        // A chat the engine doesn't have has no name to show.
        guard let chat else { return }
        deliverRespectingLock(NotificationPolicy.reminderContent(room: chat))
    }

    /// Ends a chat's fired reminder without reading it. A failure is ignored, as Mark as Read's is.
    private func clearReminder(roomID: String) async {
        guard !isCurrentlyLocked, let client = appModel.client else { return }
        let _: Empty? = try? await client.call("reminder.clear", RoomsParams(roomIDs: [roomID]))
    }

    /// `events` are newest first, as room.events has them; the oldest is announced first.
    private func announce(_ events: [Event], in room: InboxRow) {
        // Read at the moment of deciding: the person may have moved on while the page was on its way.
        guard let context = context() else { return }
        // A message deleted before it was announced is not announced.
        let deleted = NotificationPolicy.redactedEventIDs(in: events)
        let notifPrefs = preferences.notifications
        let accountKey = resolveAccountKey(for: room)
        for event in events.reversed() where seen.insert(event.eventID) {
            // Their message ends the typing burst: its notification makes way for the message's own.
            if Timeline.isIncomingMessage(event) {
                typingEpoch[room.roomID, default: 0] += 1
                endTypingBurst(room.roomID)
            }
            guard !deleted.contains(event.eventID) else { continue }
            playSoundEffectIfEligible(
                for: event,
                in: room,
                context: context,
                preferences: notifPrefs,
                accountKey: accountKey
            )

            let decision = NotificationPolicy.evaluate(
                event: event,
                room: room,
                context: context,
                preferences: notifPrefs,
                accountKey: accountKey
            )
            guard decision.shouldNotify, let content = decision.content else { continue }
            if let otpCode = decision.otpCode, !context.isAppLocked, !isCurrentlyLocked {
                latestOTPByRoom[room.roomID] = otpCode
                if decision.shouldAutoCopyOTP {
                    clipboard?.copyOTP(otpCode)
                }
            }
            if decision.delaySeconds > 0 {
                scheduleDelayedDelivery(
                    content,
                    roomID: room.roomID,
                    delaySeconds: decision.delaySeconds,
                    repeatUnreadMinutes: decision.repeatUnreadMinutes
                )
            } else {
                deliverAndScheduleRepeatIfNeeded(
                    content,
                    roomID: room.roomID,
                    repeatUnreadMinutes: decision.repeatUnreadMinutes
                )
            }
        }
    }

    private func playSoundEffectIfEligible(
        for event: Event,
        in room: InboxRow,
        context: NotificationPolicy.Context,
        preferences: NotificationPreferences,
        accountKey: String?
    ) {
        guard let soundEffects, event.status != .failed else { return }
        let isMessage = event.type == "m.room.message" || event.type == "m.sticker" || event.type == Timeline.pollStartType
        guard isMessage, !Timeline.isEdit(event), TimerChange.of(event.content) == nil, CallNote.isNews(event) else {
            return
        }
        guard event.ts >= context.connectedAt, context.now - event.ts <= NotificationPolicy.liveWindowMillis else {
            return
        }
        let isMine = event.mine || event.sender == context.me
        if isMine {
            if preferences.soundEffectsMode.shouldPlay(for: .messageSent) {
                soundEffects.play(.messageSent, volume: preferences.soundEffectsVolume)
            }
        } else {
            guard !NotificationPolicy.isMuted(room), !room.lowPriority, !room.hidden else { return }
            let allowRequests = preferences.requestNotificationsEnabled && context.requestNotifications
            guard !room.request || allowRequests else { return }
            if room.isDirect {
                guard preferences.messageNotificationsEnabled else { return }
            } else {
                guard preferences.groupNotificationsEnabled else { return }
            }
            if let override = NotificationPolicy.resolveAccountOverride(
                for: room,
                preferences: preferences,
                explicitKey: accountKey
            ), !override.enabled {
                return
            }
            if preferences.soundEffectsMode.shouldPlay(for: .messageReceived) {
                soundEffects.play(.messageReceived, volume: preferences.soundEffectsVolume)
            }
        }
    }

    private func scheduleDelayedDelivery(
        _ content: NotificationContent,
        roomID: String,
        delaySeconds: Int,
        repeatUnreadMinutes: Int
    ) {
        let initialRow = row(roomID)
        let hadUnreadMarkWhenScheduled = (initialRow?.unread ?? 0) > 0 || (initialRow?.markedUnread ?? false)
        var timerID: UUID?
        let id = scheduler.schedule(after: TimeInterval(delaySeconds)) { [weak self] in
            guard let self else { return }
            if let timerID {
                self.pendingTimerIDsByRoom[roomID]?.remove(timerID)
            }
            if self.effectiveIsLooking, self.appModel.isOpen(roomID: roomID), !self.preferences.notifications.notifyWhenInFocus {
                return
            }
            if hadUnreadMarkWhenScheduled,
               let currentRow = self.row(roomID),
               currentRow.unread == 0 && !currentRow.markedUnread {
                return
            }
            self.deliverAndScheduleRepeatIfNeeded(
                content,
                roomID: roomID,
                repeatUnreadMinutes: repeatUnreadMinutes
            )
        }
        timerID = id
        pendingTimerIDsByRoom[roomID, default: []].insert(id)
    }

    private func deliverAndScheduleRepeatIfNeeded(
        _ content: NotificationContent,
        roomID: String,
        repeatUnreadMinutes: Int
    ) {
        deliverRespectingLock(content)
        guard repeatUnreadMinutes > 0 else { return }
        var timerID: UUID?
        let id = scheduler.schedule(after: TimeInterval(repeatUnreadMinutes * 60)) { [weak self] in
            guard let self else { return }
            if let timerID {
                self.pendingTimerIDsByRoom[roomID]?.remove(timerID)
            }
            if self.effectiveIsLooking, self.appModel.isOpen(roomID: roomID), !self.preferences.notifications.notifyWhenInFocus {
                return
            }
            if let currentRow = self.row(roomID), currentRow.unread == 0 && !currentRow.markedUnread {
                return
            }
            self.deliverRespectingLock(content)
        }
        timerID = id
        pendingTimerIDsByRoom[roomID, default: []].insert(id)
    }

    private func cancelTimers(forRoomID roomID: String) {
        guard let ids = pendingTimerIDsByRoom.removeValue(forKey: roomID) else { return }
        for id in ids {
            scheduler.cancel(id)
        }
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: - What is done on a notification

    /// Copies the most recently extracted OTP code for `roomID` to the clipboard.
    /// While locked, drops the action and brings Courier forward to the lock screen.
    public func copyOTPCode(forRoomID roomID: String) {
        guard !isCurrentlyLocked else {
            showWindow()
            return
        }
        guard let code = latestOTPByRoom[roomID] else { return }
        clipboard?.copyOTP(code)
    }

    public func openSystemNotificationSettings() {
        guard !isCurrentlyLocked else {
            showWindow()
            return
        }
        delivery.openSystemNotificationSettings()
    }

    public func restartNotificationCenter() {
        guard !isCurrentlyLocked else {
            showWindow()
            return
        }
        delivery.restartNotificationCenter()
    }

    /// A click: the chat opens in the main window, which comes forward.
    /// While locked, drops the room selection and brings Courier forward to the lock screen.
    public func open(roomID: String) {
        guard !isCurrentlyLocked else {
            showWindow()
            return
        }
        appModel.selectedRoomID = roomID
        showWindow()
    }

    /// "Mark as Read". While locked, drops the action and brings Courier forward to the lock screen.
    public func markRead(roomID: String) async {
        guard !isCurrentlyLocked else {
            showWindow()
            return
        }
        await performMarkRead(roomID: roomID)
    }

    private func performMarkRead(roomID: String) async {
        cancelTimers(forRoomID: roomID)
        latestOTPByRoom.removeValue(forKey: roomID)
        if let client = appModel.client {
            // A failure is ignored: the inbox shows the truth the next time it reads.
            let _: Empty? = try? await client.call("room.markRead", RoomParams(roomID: roomID))
        }
        delivery.clear(roomID: roomID)
    }

    /// The status of the message stored for a send, as the chat has it now; nil when it can't be read.
    private func status(of eventID: String, in roomID: String, with client: EngineClient) async -> StatusLine? {
        let page: EventsPage? = try? await client.call(
            "room.events", RoomEventsParams(roomID: roomID, around: eventID, limit: 3))
        guard let event = page?.events.first(where: { $0.eventID == eventID }) else { return nil }
        return StatusLine.of(status: event.status, reason: event.statusReason)
    }

    /// "Remind in 1 Hour" and "Remind in 8 Hours": a reminder `seconds` from now, brought back as the person's
    /// default says. Like Mark as Read, a failure is ignored; the buttons are only offered with the plan, and a
    /// denial or a dead engine changes nothing. While locked, drops the action and brings Courier forward.
    public func remind(roomID: String, after seconds: TimeInterval) async {
        guard !isCurrentlyLocked else {
            showWindow()
            return
        }
        guard entitlement.isEntitled(.reminders), let client = appModel.client else { return }
        let dueAt = Self.millis(clock()) + Int64((seconds * 1000).rounded())
        let _: Empty? = try? await client.call(
            "reminder.set", ReminderParams(roomIDs: [roomID], dueAt: dueAt, condition: preferences.remindDefault.wire))
    }

    /// The inline "Reply": sends the typed text to the chat. If it cannot be sent (the engine is not up, or refuses),
    /// the text goes into that chat's draft and a notification says so, so the words are never lost. A send the
    /// engine took but stored failed, or waiting for its network, is in the chat already: a notification says that
    /// it wasn't sent, or that it goes when the network is back. While locked, drops the action and brings Courier forward.
    public func reply(roomID: String, text: String) async {
        guard !isCurrentlyLocked else {
            showWindow()
            return
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var mayHaveGone = false
        if let client = appModel.client {
            do {
                let sent: Sent = try await client.call("message.send", SendParams(roomID: roomID, text: text),
                                                       timeout: replyTimeout)
                // A reply that went reads the chat, as one typed in it does (in Incognito too: "until I reply"), and
                // its notifications come down. message.send also answers for a send the network refused (failed),
                // and at once for one that waits: neither reads anything, and each says so. A failed one is in the
                // chat with Retry, so nothing goes back into the draft.
                let line = await status(of: sent.eventID, in: roomID, with: client)
                switch line {
                case let line? where line.hasGone:
                    await performMarkRead(roomID: roomID)
                case .waiting?:
                    deliverRespectingLock(NotificationPolicy.replyWaiting(roomID: roomID, title: row(roomID)?.name ?? ""))
                case .failed?, .notSent?, .noAccount?, .mayHaveBeenSent?:
                    deliverRespectingLock(NotificationPolicy.replyNotSent(roomID: roomID, title: row(roomID)?.name ?? "",
                                                                          mayHaveGone: line == .mayHaveBeenSent))
                default:
                    break // still on its way (sending, held), or its status couldn't be read
                }
                return
            } catch {
                // Falls through, whatever the reason: the text is kept below. When the engine did not answer, the
                // send may have gone, and the person is told to look before sending it again.
                mayHaveGone = (error as? EngineError)?.mayHaveBeenHandled ?? false
            }
        }
        restoreDraft(roomID, text, mayHaveGone)
        deliverRespectingLock(NotificationPolicy.replyNotSent(roomID: roomID, title: row(roomID)?.name ?? "",
                                                              mayHaveGone: mayHaveGone))
    }
}
