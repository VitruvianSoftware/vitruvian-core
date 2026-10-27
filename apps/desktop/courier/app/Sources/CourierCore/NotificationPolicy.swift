// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// When a message makes a notification, what the notification says, and what the Dock badge counts. Plain values and
// pure functions, so the rules are tested here and the system's notification centre only carries them out.

/// Which set of buttons a notification carries.
public enum NotificationCategory: String, Equatable, Sendable, CaseIterable {
    /// A new message: Mark as Read, Reply and the remind-later buttons.
    case message
    /// A new message containing a one-time verification code when auto-copy is enabled: includes Copy Code.
    case messageOTP
    /// A reminder that came due: the same without Reply, because there is nothing new to answer.
    case reminder
    /// A scheduled message that didn't go (canceled, or missed): no buttons, since there is nothing to read or
    /// answer; a click opens the chat, whose strip offers Send Now, Reschedule and Delete.
    case scheduled
    /// Someone started typing: no buttons either, since nothing has come yet to read or answer; a click opens the
    /// chat.
    case typing

    /// The buttons, in the order they are shown. The remind-later ones are part of a plan, so they are left out
    /// when it doesn't include reminders (spec §3): a button that could only say no is not offered.
    public func actions(entitlement: any EntitlementProvider) -> [NotificationAction] {
        guard self != .scheduled, self != .typing else { return [] }
        var actions: [NotificationAction] = []
        if self == .messageOTP { actions.append(.copyCode) }
        actions.append(.markRead)
        if self == .message || self == .messageOTP { actions.append(.reply) }
        if entitlement.isEntitled(.reminders) { actions += [.remindOneHour, .remindEightHours] }
        return actions
    }
}

/// A button on a notification.
public enum NotificationAction: String, Equatable, Sendable, CaseIterable {
    case copyCode, markRead, reply, remindOneHour, remindEightHours
}

/// Sound effect playback trigger mode.
public enum SoundEffectsMode: String, CaseIterable, Codable, Sendable {
    case never, sentOnly, receivedOnly, always

    public func shouldPlay(for event: SoundEffectEvent) -> Bool {
        switch self {
        case .never: false
        case .sentOnly: event == .messageSent
        case .receivedOnly: event == .messageReceived
        case .always: true
        }
    }
}

/// Event that can trigger an in-app sound effect.
public enum SoundEffectEvent: String, Equatable, Sendable {
    case messageSent
    case messageReceived
}

/// Sound choice for message and group notifications.
public enum NotificationSoundChoice: String, CaseIterable, Codable, Sendable {
    case `default`, none, beeper, sounds, double, dreams, not, marimba, rain, harp, record, spirit
}

/// Per-account notification override.
public struct AccountNotificationOverride: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var showPreviews: Bool
    public var sound: NotificationSoundChoice?

    public init(enabled: Bool = true, showPreviews: Bool = true, sound: NotificationSoundChoice? = nil) {
        self.enabled = enabled
        self.showPreviews = showPreviews
        self.sound = sound
    }
}

/// Extracts a 4-8 digit OTP/2FA verification code when accompanied by an OTP keyword.
public enum OTPDetector {
    private static let keywordRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(security\s+code|verification|passcode|code|otp|2fa|pin)\b"#
    )
    private static let codeRegex = try! NSRegularExpression(
        pattern: #"(?<![\d$+-])(?<!\d\.)\b(?:\d{3,4}-\d{3,4}|\d{4,8})\b(?![\d-]|\.\d)"#
    )

    /// Extracts a 4-8 digit OTP/2FA verification code when accompanied by an OTP keyword
    /// ("code", "verification", "OTP", "2FA", "passcode", "security code", "pin").
    public static func extractCode(from text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard keywordRegex.firstMatch(in: text, options: [], range: range) != nil else {
            return nil
        }
        let matches = codeRegex.matches(in: text, options: [], range: range)
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let raw = String(text[matchRange])
            let digits = raw.replacingOccurrences(of: "-", with: "")
            guard (4...8).contains(digits.count), digits.allSatisfy(\.isNumber) else { continue }
            if digits.count == 4, let value = Int(digits), (1900...2099).contains(value) {
                continue
            }
            return digits
        }
        return nil
    }
}

/// Extended notification preferences backed by UserDefaults.
public final class NotificationPreferences: ObservableObject {
    public static let allowedDelaySeconds: [Int] = [0, 10, 30, 60, 120, 300]
    public static let allowedRepeatUnreadMinutes: [Int] = [0, 2, 5, 10]

    @Published public var soundEffectsMode: SoundEffectsMode {
        didSet {
            guard !isInitializing else { return }
            set(soundEffectsMode.rawValue, "soundEffectsMode")
        }
    }
    @Published public var soundEffectsVolume: Double {
        didSet {
            let clamped = min(1.0, max(0.0, soundEffectsVolume))
            if soundEffectsVolume != clamped {
                soundEffectsVolume = clamped
                return
            }
            guard !isInitializing else { return }
            set(soundEffectsVolume, "soundEffectsVolume")
        }
    }
    @Published public var messageNotificationsEnabled: Bool {
        didSet {
            guard !isInitializing else { return }
            set(messageNotificationsEnabled, "messageNotificationsEnabled")
        }
    }
    @Published public var messageSound: NotificationSoundChoice {
        didSet {
            guard !isInitializing else { return }
            set(messageSound.rawValue, "messageSound")
        }
    }
    @Published public var groupNotificationsEnabled: Bool {
        didSet {
            guard !isInitializing else { return }
            set(groupNotificationsEnabled, "groupNotificationsEnabled")
        }
    }
    @Published public var groupSound: NotificationSoundChoice {
        didSet {
            guard !isInitializing else { return }
            set(groupSound.rawValue, "groupSound")
        }
    }
    @Published public var requestNotificationsEnabled: Bool {
        didSet {
            guard !isInitializing else { return }
            set(requestNotificationsEnabled, "requestNotificationsEnabled")
            defaults.set(requestNotificationsEnabled, forKey: InboxPreferences.key("requestNotifications"))
            onRequestNotificationsChanged?(requestNotificationsEnabled)
        }
    }
    @Published public var notifyWhenInFocus: Bool {
        didSet {
            guard !isInitializing else { return }
            set(notifyWhenInFocus, "notifyWhenInFocus")
        }
    }
    @Published public var notifyOnReaction: Bool {
        didSet {
            guard !isInitializing else { return }
            set(notifyOnReaction, "notifyOnReaction")
        }
    }
    @Published public var typingNotificationsEnabled: Bool {
        didSet {
            guard !isInitializing else { return }
            set(typingNotificationsEnabled, "typingNotificationsEnabled")
            defaults.set(typingNotificationsEnabled, forKey: InboxPreferences.key("typingNotifications"))
            onTypingNotificationsChanged?(typingNotificationsEnabled)
        }
    }
    @Published public var delaySeconds: Int {
        didSet {
            guard Self.allowedDelaySeconds.contains(delaySeconds) else {
                delaySeconds = oldValue
                return
            }
            guard !isInitializing else { return }
            set(delaySeconds, "delaySeconds")
        }
    }
    @Published public var repeatUnreadMinutes: Int {
        didSet {
            guard Self.allowedRepeatUnreadMinutes.contains(repeatUnreadMinutes) else {
                repeatUnreadMinutes = oldValue
                return
            }
            guard !isInitializing else { return }
            set(repeatUnreadMinutes, "repeatUnreadMinutes")
        }
    }
    @Published public var autoCopyOTP: Bool {
        didSet {
            guard !isInitializing else { return }
            set(autoCopyOTP, "autoCopyOTP")
        }
    }
    @Published public var accountOverrides: [String: AccountNotificationOverride] {
        didSet {
            guard !isInitializing else { return }
            if let data = try? JSONEncoder().encode(accountOverrides) {
                defaults.set(data, forKey: Self.key("accountOverrides"))
            }
        }
    }

    public static func key(_ name: String) -> String { "courier.notifications." + name }

    private let defaults: UserDefaults
    private var isInitializing = true
    var onRequestNotificationsChanged: ((Bool) -> Void)?
    var onTypingNotificationsChanged: ((Bool) -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ name: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: Self.key(name)) as? Bool ?? fallback
        }
        func value<T: RawRepresentable>(_ name: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: Self.key(name)).flatMap(T.init(rawValue:)) ?? fallback
        }

        soundEffectsMode = value("soundEffectsMode", SoundEffectsMode.never)
        let rawVolume = defaults.object(forKey: Self.key("soundEffectsVolume")) as? Double ?? 0.7
        soundEffectsVolume = min(1.0, max(0.0, rawVolume))
        messageNotificationsEnabled = bool("messageNotificationsEnabled", true)
        messageSound = value("messageSound", NotificationSoundChoice.default)
        groupNotificationsEnabled = bool("groupNotificationsEnabled", true)
        groupSound = value("groupSound", NotificationSoundChoice.default)
        let reqFallback = defaults.object(forKey: InboxPreferences.key("requestNotifications")) as? Bool ?? true
        requestNotificationsEnabled = bool("requestNotificationsEnabled", reqFallback)
        notifyWhenInFocus = bool("notifyWhenInFocus", false)
        notifyOnReaction = bool("notifyOnReaction", true)
        let typingFallback = defaults.object(forKey: InboxPreferences.key("typingNotifications")) as? Bool ?? false
        typingNotificationsEnabled = bool("typingNotificationsEnabled", typingFallback)

        let rawDelay = defaults.object(forKey: Self.key("delaySeconds")) as? Int ?? 0
        delaySeconds = Self.allowedDelaySeconds.contains(rawDelay) ? rawDelay : 0

        let rawRepeat = defaults.object(forKey: Self.key("repeatUnreadMinutes")) as? Int ?? 0
        repeatUnreadMinutes = Self.allowedRepeatUnreadMinutes.contains(rawRepeat) ? rawRepeat : 0

        autoCopyOTP = bool("autoCopyOTP", false)
        if let data = defaults.data(forKey: Self.key("accountOverrides")),
           let decoded = try? JSONDecoder().decode([String: AccountNotificationOverride].self, from: data) {
            accountOverrides = decoded
        } else {
            accountOverrides = [:]
        }
        isInitializing = false
    }

    private func set(_ value: Any?, _ name: String) {
        if let value {
            defaults.set(value, forKey: Self.key(name))
        } else {
            defaults.removeObject(forKey: Self.key(name))
        }
    }
}

/// Decision returned by `NotificationPolicy.evaluate`.
public struct NotificationDecision: Equatable, Sendable {
    public let shouldNotify: Bool
    public let content: NotificationContent?
    public let sound: NotificationSoundChoice
    public let delaySeconds: Int
    public let repeatUnreadMinutes: Int
    public let otpCode: String?
    public let shouldAutoCopyOTP: Bool

    public init(
        shouldNotify: Bool,
        content: NotificationContent? = nil,
        sound: NotificationSoundChoice = .default,
        delaySeconds: Int = 0,
        repeatUnreadMinutes: Int = 0,
        otpCode: String? = nil,
        shouldAutoCopyOTP: Bool = false
    ) {
        self.shouldNotify = shouldNotify
        self.content = content
        self.sound = sound
        self.delaySeconds = delaySeconds
        self.repeatUnreadMinutes = repeatUnreadMinutes
        self.otpCode = otpCode
        self.shouldAutoCopyOTP = shouldAutoCopyOTP
    }
}

/// A notification, before the system draws it.
public struct NotificationContent: Equatable, Sendable {
    public let eventID: String
    public let roomID: String
    /// The chat's name.
    public let title: String
    /// For a group, who wrote it. Nil in a direct chat.
    public let subtitle: String?
    /// The text, or what kind of file it is.
    public let body: String
    /// Which buttons it carries.
    public let category: NotificationCategory
    /// Local path of a thumbnail or image/video/sticker attachment to show on the notification; nil for view-once media.
    public let attachmentPath: String?
    /// Which notification sound to play.
    public let sound: NotificationSoundChoice

    public init(eventID: String, roomID: String, title: String, subtitle: String?, body: String,
                category: NotificationCategory = .message, attachmentPath: String? = nil,
                sound: NotificationSoundChoice = .default) {
        self.eventID = eventID
        self.roomID = roomID
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.category = category
        self.attachmentPath = attachmentPath
        self.sound = sound
    }

    /// Notifications of one chat are stacked together.
    public var threadIdentifier: String { roomID }

    /// All a notification carries to say where a click goes: the chat. No text, no names.
    public var userInfo: [String: String] { ["room_id": roomID] }
}

public enum NotificationPolicy {
    /// A message counts as live for this long after it was sent: a bridge that catches up later than this is
    /// bringing history, not news.
    public static let liveWindowMillis: Int64 = 120_000
    /// A longer text is cut to this many characters and an ellipsis.
    public static let maxBodyLength = 200

    /// What the decision depends on besides the event and its chat.
    public struct Context: Equatable, Sendable {
        /// Who I am in every chat (`Timeline.meUserID`).
        public var me: String
        /// When the app connected to the engine, in ms since 1970.
        public var connectedAt: Int64
        /// The time now, in ms since 1970.
        public var now: Int64
        /// The chat that is open.
        public var openRoomID: String?
        /// When the open chat is a merged chat, its member room IDs.
        public var openMemberRoomIDs: Set<String>
        /// The person is looking at the open chat (`Attention`): the window is key, the screen unlocked and awake,
        /// and they are not idle.
        public var isLooking: Bool
        /// The setting "notify for message requests" (`InboxPreferences.requestNotifications`).
        public var requestNotifications: Bool
        /// Whether to show notifications even for the open chat when the window is in focus.
        public var notifyWhenInFocus: Bool
        /// Whether reaction events (`m.reaction`) should notify.
        public var notifyOnReaction: Bool
        /// Whether the app lock screen is currently active (redacts all previews and hides reply actions).
        public var isAppLocked: Bool

        public init(me: String, connectedAt: Int64, now: Int64, openRoomID: String?,
                    openMemberRoomIDs: Set<String> = [], isLooking: Bool,
                    requestNotifications: Bool = true,
                    notifyWhenInFocus: Bool = false,
                    notifyOnReaction: Bool = false,
                    isAppLocked: Bool = false) {
            self.me = me
            self.connectedAt = connectedAt
            self.now = now
            self.openRoomID = openRoomID
            self.openMemberRoomIDs = openMemberRoomIDs
            self.isLooking = isLooking
            self.requestNotifications = requestNotifications
            self.notifyWhenInFocus = notifyWhenInFocus
            self.notifyOnReaction = notifyOnReaction
            self.isAppLocked = isAppLocked
        }

        /// True when `roomID` is the open chat or one of the open merged chat's member rooms.
        public func isOpen(roomID: String) -> Bool {
            openRoomID == roomID || openMemberRoomIDs.contains(roomID)
        }
    }

    /// Whether `event`, new in `room`, makes a notification.
    ///
    /// Yes for a message, a sticker or a poll that is not from me, in a chat that is not muted (by itself, its account or
    /// a label), is not low priority or hidden, and is not a request while requests are turned off, that is live (sent
    /// after the app connected and not more than two minutes ago: the first sync's history must not notify), and that
    /// is not in the chat the person is looking at. An archived chat is none of these: its new message brings it back
    /// to the inbox, and it notifies. Reactions, edits, deletions, timer-change notes, call records (a call that
    /// ended, was declined or dropped: `CallNote.isNews`) and anything the app cannot read do not.
    /// A notification for another chat does come while the window is in front, and one for the open chat does
    /// while nobody is looking at it (the screen locked or asleep, or the person away).
    public static func shouldNotify(event: Event, room: InboxRow, context: Context) -> Bool {
        // Ruling 17: someone starting a poll is a message (its votes and its end are not).
        let isReaction = event.type == "m.reaction" && context.notifyOnReaction && reactionEmoji(of: event) != nil
        guard event.type == "m.room.message" || event.type == "m.sticker" || event.type == Timeline.pollStartType || isReaction
        else { return false }
        guard !Timeline.isEdit(event) else { return false }
        // A note that the disappearing timer changed is a system line, not news (Ruling 40), and the engine doesn't
        // count it unread.
        guard TimerChange.of(event.content) == nil else { return false }
        // Nor is the record that a call ended, was declined or dropped: only a call that rang or was missed is news.
        guard CallNote.isNews(event) else { return false }
        guard !event.mine, event.sender != context.me else { return false }
        guard !isMuted(room) else { return false }
        // Inferred (inventory 01 §18): Low Priority hides a chat "for good" and Hide removes it from the inbox, so a
        // new message in one is not news.
        guard !room.lowPriority, !room.hidden else { return false }
        guard !room.request || context.requestNotifications else { return false }
        guard event.ts >= context.connectedAt, context.now - event.ts <= liveWindowMillis else { return false }
        if !context.notifyWhenInFocus, context.isLooking, context.isOpen(roomID: event.roomID) { return false }
        return true
    }

    public static func evaluate(
        event: Event,
        room: InboxRow,
        context: Context,
        preferences: NotificationPreferences? = nil,
        accountKey: String? = nil
    ) -> NotificationDecision {
        let noNotify = NotificationDecision(shouldNotify: false)
        guard !event.mine, event.sender != context.me else { return noNotify }
        guard event.ts >= context.connectedAt, context.now - event.ts <= liveWindowMillis else { return noNotify }
        guard !Timeline.isEdit(event) else { return noNotify }
        guard TimerChange.of(event.content) == nil else { return noNotify }
        guard CallNote.isNews(event) else { return noNotify }

        let allowReaction = preferences?.notifyOnReaction ?? context.notifyOnReaction
        let reactionKey = event.type == "m.reaction" ? reactionEmoji(of: event) : nil
        let isReaction = event.type == "m.reaction" && allowReaction && reactionKey != nil
        let isMessage = event.type == "m.room.message" || event.type == "m.sticker" || event.type == Timeline.pollStartType
        guard isMessage || isReaction else { return noNotify }

        let rawText = event.type == "m.room.message" ? (event.content["body"]?.stringValue ?? "") : ""
        let otpCode = rawText.isEmpty ? nil : OTPDetector.extractCode(from: rawText)
        let autoCopyOTP = preferences?.autoCopyOTP ?? false
        let isUrgentOTP = otpCode != nil && autoCopyOTP

        guard !room.lowPriority, !room.hidden else { return noNotify }
        let allowRequests = preferences?.requestNotificationsEnabled ?? context.requestNotifications
        guard !room.request || allowRequests else { return noNotify }

        let override = resolveAccountOverride(for: room, preferences: preferences, explicitKey: accountKey)

        if !isUrgentOTP {
            guard !isMuted(room) else { return noNotify }
            if room.isDirect {
                guard preferences?.messageNotificationsEnabled ?? true else { return noNotify }
            } else {
                guard preferences?.groupNotificationsEnabled ?? true else { return noNotify }
            }
            if let override, !override.enabled {
                return noNotify
            }
        }

        let notifyInFocus = preferences?.notifyWhenInFocus ?? context.notifyWhenInFocus
        if !notifyInFocus, context.isLooking, context.isOpen(roomID: event.roomID) {
            return noNotify
        }

        let baseSound = room.isDirect
            ? (preferences?.messageSound ?? .default)
            : (preferences?.groupSound ?? .default)
        let sound = override?.sound ?? baseSound

        var title = room.name.isEmpty ? event.senderName : room.name
        if title.isEmpty { title = String(localized: "Courier") }
        let sender = event.senderName.trimmingCharacters(in: .whitespaces)
        var subtitle: String? = room.isDirect || sender.isEmpty ? nil : sender
        var textBody: String
        var attachment: String?
        if let reactionKey {
            textBody = String(localized: "Reacted \(reactionKey)")
            attachment = nil
        } else {
            textBody = body(of: event)
            attachment = attachmentPath(of: event)
        }
        var category: NotificationCategory = isUrgentOTP ? .messageOTP : .message

        if context.isAppLocked {
            title = String(localized: "Courier")
            subtitle = nil
            textBody = String(localized: "New message")
            attachment = nil
            category = .scheduled
        } else if override?.showPreviews == false {
            subtitle = nil
            textBody = String(localized: "New message")
            attachment = nil
        }

        let content = NotificationContent(
            eventID: event.eventID,
            roomID: event.roomID,
            title: title,
            subtitle: subtitle,
            body: textBody,
            category: category,
            attachmentPath: attachment,
            sound: sound
        )
        let effectiveDelay = otpCode != nil ? 0 : (preferences?.delaySeconds ?? 0)
        let effectiveRepeat = preferences?.repeatUnreadMinutes ?? 0

        return NotificationDecision(
            shouldNotify: true,
            content: content,
            sound: sound,
            delaySeconds: effectiveDelay,
            repeatUnreadMinutes: effectiveRepeat,
            otpCode: otpCode,
            shouldAutoCopyOTP: isUrgentOTP
        )
    }

    private static func reactionEmoji(of event: Event) -> String? {
        guard event.type == "m.reaction", event.status != .failed else { return nil }
        guard let rel = event.content["m.relates_to"],
              rel["rel_type"]?.stringValue == "m.annotation",
              let key = rel["key"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        return key
    }

    private static func resolveAccountOverride(
        for room: InboxRow,
        preferences: NotificationPreferences?,
        explicitKey: String?
    ) -> AccountNotificationOverride? {
        guard let map = preferences?.accountOverrides, !map.isEmpty else { return nil }
        if let explicitKey, let found = map[explicitKey] { return found }
        if !room.network.isEmpty {
            if let found = map[room.network] { return found }
            if let (_, found) = map.first(where: { $0.key.hasPrefix(room.network + ":") }) {
                return found
            }
        }
        return nil
    }

    /// Whether the chat is muted: by itself, or by its account or one of its labels.
    public static func isMuted(_ room: InboxRow) -> Bool {
        room.muted || room.mutedBy != .none
    }

    // MARK: - Someone starts typing

    /// Whether someone typing in `room` makes a notification: "Notify when someone starts typing" is `on`, someone
    /// is typing, and the chat would notify for a message from them: not muted (by itself, its account or a label),
    /// not Low Priority or Hidden, not a request while requests don't notify, and not the chat the person is looking
    /// at. Inferred (inventory 02 §1.5, which names the setting but not its rules): the rules a message follows. The
    /// coordinator tells one per burst (`NotificationCoordinator`).
    public static func shouldNotifyTyping(room: InboxRow, context: Context, on: Bool) -> Bool {
        guard on, !room.typing.isEmpty else { return false }
        guard !isMuted(room), !room.lowPriority, !room.hidden else { return false }
        guard !room.request || context.requestNotifications else { return false }
        if context.isLooking, context.isOpen(roomID: room.roomID) { return false }
        return true
    }

    /// The id of a chat's typing notification: one per chat, so the next burst replaces it and the message that
    /// follows can take it down (C42: a typing notification has no event of its own).
    public static func typingID(roomID: String) -> String { "typing:" + roomID }

    /// What a typing notification says: the chat's name as its title, and who is typing as the chat's row words it
    /// ("Ana is typing…", "3 people are typing…").
    public static func typingContent(room: InboxRow) -> NotificationContent {
        NotificationContent(
            eventID: typingID(roomID: room.roomID), roomID: room.roomID,
            title: room.name.isEmpty ? String(localized: "Courier") : room.name, subtitle: nil,
            body: room.typingLine ?? "", category: .typing)
    }

    /// What the notification for a reminder that came due says. The title is the chat's name; there is no message
    /// text, and nothing else about the chat. Each reminder has an id of its own, so one never replaces another.
    ///
    /// Inferred (inventory 01 §18): a reminder notifies even when the chat is muted, low priority or hidden. The
    /// inventory describes the remind-later buttons (§18, §19) but not how a muted chat treats a reminder; the person
    /// asked for this one, and a mute is about messages, so it is not held back.
    public static func reminderContent(room: InboxRow) -> NotificationContent {
        NotificationContent(
            eventID: "reminder-" + room.roomID + "-" + UUID().uuidString, roomID: room.roomID,
            title: room.name.isEmpty ? String(localized: "Courier") : room.name, subtitle: nil,
            body: String(localized: "You asked to be reminded about this chat."), category: .reminder)
    }

    /// A scheduled message that won't go by itself: canceled because they wrote first, or missed while Courier was
    /// closed. The chat's name comes from its row; without one, "the chat".
    public static func scheduledContent(_ message: ScheduledMessage, room: InboxRow?) -> NotificationContent {
        let name = room?.name.isEmpty == false ? room!.name : String(localized: "the chat")
        let body = message.state == .canceled
            ? String(localized: "A scheduled message to \(name) wasn’t sent: they wrote first.")
            : String(localized: "A scheduled message to \(name) missed its time while Courier was closed.")
        return NotificationContent(
            eventID: "scheduled-\(message.outboxID)-\(message.state.rawValue)-\(message.setAt)",
            roomID: message.roomID, title: String(localized: "Courier"), subtitle: nil, body: body,
            category: .scheduled)
    }

    /// What the notification for `event` says.
    public static func content(for event: Event, room: InboxRow) -> NotificationContent {
        var name = room.name.isEmpty ? event.senderName : room.name
        if name.isEmpty { name = String(localized: "Courier") }
        let sender = event.senderName.trimmingCharacters(in: .whitespaces)
        return NotificationContent(
            eventID: event.eventID, roomID: event.roomID, title: name,
            subtitle: room.isDirect || sender.isEmpty ? nil : sender, body: body(of: event),
            attachmentPath: attachmentPath(of: event))
    }

    /// What a chat says when a reply typed in a notification could not be sent: the text is waiting in the chat.
    /// `mayHaveGone`: the engine did not answer, so the reply may have been sent after all.
    public static func replyNotSent(roomID: String, title: String, mayHaveGone: Bool = false) -> NotificationContent {
        NotificationContent(
            eventID: "reply-not-sent-" + UUID().uuidString, roomID: roomID,
            title: title.isEmpty ? String(localized: "Courier") : title, subtitle: nil,
            body: mayHaveGone
                ? String(localized: "Your reply may not have been sent — check the chat before sending again.")
                : String(localized: "Your reply wasn’t sent — it’s waiting in the chat."))
    }

    /// A reply typed in a notification that is waiting for its network: it goes once the network is back.
    public static func replyWaiting(roomID: String, title: String) -> NotificationContent {
        NotificationContent(
            eventID: "reply-waiting-" + UUID().uuidString, roomID: roomID,
            title: title.isEmpty ? String(localized: "Courier") : title, subtitle: nil,
            body: String(localized: "Your reply will be sent when the network is back."))
    }

    /// The events a page says were deleted (by a redaction in the page that was not itself refused).
    public static func redactedEventIDs(in events: [Event]) -> Set<String> {
        Set(events.compactMap { event in
            guard event.type == "m.room.redaction", event.status != .failed else { return nil }
            return event.content["redacts"]?.stringValue
        })
    }

    private static func body(of event: Event) -> String {
        let shown = Timeline.summary(of: event)
        let text = shown.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let label = label(of: shown.kind) else { return truncated(text) }
        return text.isEmpty ? label.title : label.title + " " + truncated(text)
    }

    private static func attachmentPath(of event: Event) -> String? {
        guard event.viewOnce != true else { return nil }
        let shown = Timeline.summary(of: event)
        guard shown.kind == .image || shown.kind == .video || shown.kind == .sticker else { return nil }
        if let thumb = event.thumbnailPath, !thumb.isEmpty { return thumb }
        if !event.mediaPath.isEmpty { return event.mediaPath }
        return nil
    }

    private static func label(of kind: MessageKind) -> PreviewLabel? {
        switch kind {
        case .image: .image
        case .video: .video
        case .voiceNote: .voiceNote
        case .file: .file
        case .sticker: .sticker
        case .poll: .poll
        default: nil
        }
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > maxBodyLength else { return text }
        let cut = String(text.prefix(maxBodyLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut + "…"
    }

    // MARK: - The Dock badge

    /// The Dock tile's text for a count of chats (SpacesModel.badgeCount, which the engine counts: the inbox's
    /// unread chats that nothing mutes; chats, not messages); nil at zero, which clears it.
    public static func badgeLabel(count: Int) -> String? {
        count > 0 ? String(count) : nil
    }
}

/// The events already looked at, so a message is announced once however many times its chat is read. Bounded: when
/// full, the oldest is forgotten.
public struct SeenEvents: Sendable {
    private var order: [String] = []
    private var members = Set<String>()
    private let capacity: Int

    public init(capacity: Int = 1000) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { members.count }

    /// Notes the event; false if it was noted already.
    @discardableResult
    public mutating func insert(_ eventID: String) -> Bool {
        guard members.insert(eventID).inserted else { return false }
        order.append(eventID)
        if order.count > capacity {
            let overflow = order.count - capacity
            for forgotten in order.prefix(overflow) { members.remove(forgotten) }
            order.removeFirst(overflow)
        }
        return true
    }
}
