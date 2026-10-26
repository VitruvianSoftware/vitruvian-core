// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Where Copy puts text: the system's general pasteboard in the app; tests give one that keeps what it was given.
/// (Not "Pasteboard": Carbon has a type of that name, which every file importing AppKit also sees.)
public protocol TextPasteboard: AnyObject {
    func setString(_ text: String)
}

/// A step a message action needs from the person before it can go on: a question to answer, or a picker or sheet
/// to show. The views (Task 12) show it and answer with `confirm()`, a picker's own call, or `dismissRequest()`.
public enum MessageActionRequest: Equatable, Sendable {
    /// Unsend and Delete for Me ask first, with this question.
    case confirm(MessageAction, messageID: String, prompt: String)
    /// The forward picker, for this message.
    case forward(messageID: String)
    case reactionPicker(messageID: String)
    /// Edit History: the versions (`history(of:)`) below the bubble, in the timeline it was asked from (the chat's or
    /// the thread pane's).
    case history(messageID: String, source: MessageSource)
    /// The Send Later picker, for the composer's text.
    case sendLater
    /// "Create quick reply from draft": a title, then `createQuickReply(title:)`.
    case quickReplyTitle
}

/// Where a message was acted on: the chat's timeline, or the thread pane (a thread's root is in both).
public enum MessageSource: Hashable, Sendable {
    case chat, thread
}

/// Which message the keys and the Message menu act on: the chat's selected message, or, after a click in the
/// thread pane, the pane's (acted on `from: .thread`, so what goes into a composer goes into the pane's).
@MainActor
public final class MessageFocus: ObservableObject {
    /// The message selected in the thread pane.
    @Published public var paneSelection: String?
    /// The pane was clicked last (its messages or its composer), not the chat.
    @Published public var inPane = false

    public init() {}

    /// Where ⌘C is: the pane after a click there, else the chat; anywhere when the keyboard isn't in the chat.
    public func copyPlace(inConversation: Bool) -> CopyPlace {
        guard inConversation else { return .elsewhere }
        return inPane ? .pane : .chat
    }

    /// The message the keys act on, and where it was selected; nil with none selected there.
    public func target(chatSelection: String?) -> (id: String, source: MessageSource)? {
        if inPane { return paneSelection.map { ($0, .thread) } }
        return chatSelection.map { ($0, .chat) }
    }
}

/// Where the keyboard is, for ⌘C: the open chat, its thread pane, or anywhere else (search, a sheet, Settings).
public enum CopyPlace: Sendable {
    case chat, pane, elsewhere
}

/// What ⌘C copies.
public enum CopyChoice: Equatable, Sendable {
    /// The text selected in a text view: the system's Copy.
    case text
    /// The selected message, as the message menu's Copy does.
    case message(id: String, source: MessageSource)
    /// Nothing to copy: the system's Copy, which says so.
    case nothing
}

/// What a message's menu, its keys and its commands do (02 §3.4.2, the 4.3 subset), for the open chat.
///
/// Every action is checked against `MessageActions.available` first: one the chat shows greyed says why (its toast is
/// the greyed line, naming the network) and sends nothing; one it doesn't offer does nothing.
///
/// **Nothing is shown as done before the engine says so** (Review Focus 1). Unsend, Delete for Me, bookmarks and
/// votes go to the engine, and the chat is read again for what it stores. A refusal the engine gives at once is a
/// toast in Courier's words (-32024 is "That message can’t be changed any more.", Ruling 35). An unsend or an edit
/// the engine took can still be refused by the network later: the engine marks the redaction, or the edit, failed,
/// the chat shows the message as it was, and the toast says "Couldn’t unsend: WhatsApp said no." (or "Couldn’t edit:
/// …"), once. An unsend is followed by its redaction's ID; an edit (sent by the composer) by the status changes the
/// engine reports in the open chat, which bring the timeline's "Edit not sent".
///
/// Toasts go through `onToast`, which the app points at the inbox's one toast surface. Message text, names and
/// search text are never logged.
@MainActor
public final class MessageActionsModel: ObservableObject {
    /// What the views are to ask or show; nil when nothing is waiting.
    @Published public private(set) var request: MessageActionRequest?
    /// Where toasts go: the inbox's (`InboxModel.announce`).
    public var onToast: @MainActor (String) -> Void = { _ in }
    /// Opens a link in the browser (NSWorkspace in the app).
    public var openURL: @MainActor (URL) -> Void = { _ in }
    /// How Copy with Timestamp writes a message's time.
    public var formatTime: @MainActor (Date) -> String = { date in
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
    /// Where "Create quick reply from draft" saves; nil offers none.
    public var quickReplies: QuickReplies?
    /// How long a forward waits for the engine's answer; nil is the client's own limit. Tests shorten it.
    var forwardTimeout: TimeInterval?

    private let conversation: ConversationModel
    private let appModel: AppModel
    private let preferences: ComposerPreferences
    private let pasteboard: TextPasteboard
    private var subscriptions: [AnyCancellable] = []
    /// Unsends the engine took, by their redaction's event ID, with the chat's network for the toast: the network
    /// may still refuse them.
    private var pendingUnsends: [String: String] = [:]
    /// Events of the open chat whose status changed since the timeline last showed them: a refused edit among them
    /// is news.
    private var changedStatuses: Set<String> = []
    /// Refused edits already told, so a later read doesn't tell them again.
    private var toldEdits: Set<String> = []

    public init(conversation: ConversationModel, appModel: AppModel, preferences: ComposerPreferences,
                pasteboard: TextPasteboard) {
        self.conversation = conversation
        self.appModel = appModel
        self.preferences = preferences
        self.pasteboard = pasteboard
        appModel.onChange { [weak self] change in self?.handle(change) }
        // @Published hands over the new value before it is stored: it is the one looked at.
        subscriptions.append(conversation.$items.sink { [weak self] items in self?.timelineChanged(items) })
        subscriptions.append(conversation.thread.$items.sink { [weak self] items in self?.timelineChanged(items) })
        subscriptions.append(conversation.$roomID.removeDuplicates().sink { [weak self] _ in
            self?.changedStatuses = []
            self?.request = nil
        })
    }

    // MARK: - The menu

    /// Does `action` to the open chat's message `messageID`, acted on `from` the chat or the thread pane, or asks
    /// first (Unsend, Delete for Me), or asks the views for a picker (Forward, React, Edit History). The message is
    /// looked for where it was acted on first, then in the other (a reply is only in the pane; the root is in both).
    /// What goes into a composer (Edit, Reply, Insert as Draft) goes into the one of the place it is found in.
    public func perform(_ action: MessageAction, on messageID: String, from source: MessageSource = .chat) async {
        let thread = conversation.thread
        let paneOpen = thread.roomID != nil && thread.roomID == conversation.roomID
        let inChat = conversation.message(messageID)
        let inThread = paneOpen ? thread.message(messageID) : nil
        let inPane: Bool
        let message: TimelineMessage
        switch (source, inChat, inThread) {
        case let (.thread, _, found?), let (.chat, nil, found?):
            message = found
            inPane = true
        case let (_, found?, _):
            message = found
            inPane = false
        default:
            return
        }
        let composer = inPane ? thread.composer : conversation.composer
        let available = conversation.availableActions(for: message)
        if let greyed = available.unavailable.first(where: { $0.action == action }) {
            onToast(greyed.reason)
            return
        }
        guard available.actions.contains(action) else { return }
        switch action {
        case .reply:
            composer.startReply(to: message.quoted)
        case .replyInThread:
            // A reply in the pane is in its thread already: the pane's composer writes there.
            if !inPane { conversation.openThread(messageID) }
        case .edit:
            composer.startEditing(message)
        case .forward:
            request = .forward(messageID: messageID)
        case .copy:
            copy(message, withTime: preferences.copyWithTimestamps)
        case .copyWithTimestamp:
            copy(message, withTime: true)
        case .insertAsDraft:
            composer.insertAsDraft(message.rich)
        case .bookmark, .removeBookmark:
            await setBookmark(messageID, on: action == .bookmark)
        case .react:
            request = .reactionPicker(messageID: messageID)
        case .unsend:
            request = .confirm(.unsend, messageID: messageID,
                               prompt: String(localized: "Unsend this message? It’s removed for everyone in the chat."))
        case .deleteForMe:
            let prompt = conversation.features.deleteReachesPhone
                ? String(localized: "Delete this message from this Mac and your phone?")
                : String(localized: "Delete this message from this Mac?")
            request = .confirm(.deleteForMe, messageID: messageID, prompt: prompt)
        case .openFirstLink:
            if let url = MessageActions.firstLink(in: message.rich) { openURL(url) }
        case .showHistory:
            request = .history(messageID: messageID, source: inPane ? .thread : .chat)
        case .markUnread:
            await conversation.markUnread(from: messageID)
        case .markAsPlayed:
            await conversation.markMediaPlayed(eventID: messageID, roomID: message.roomID)
        case .replyPrivately:
            await conversation.replyPrivately(to: messageID)
        }
    }

    /// "Don't Send" on a message waiting for its network: takes it back as Undo does (message.undo), and what was
    /// typed goes back into the composer of the place it was acted on. Only a message of mine that waits.
    public func dontSend(_ messageID: String, from source: MessageSource = .chat) async {
        guard let message = conversation.message(messageID, from: source), message.mine,
              message.statusLine?.isWaiting == true else { return }
        let inPane = conversation.thread.roomID == conversation.roomID && conversation.thread.message(messageID) != nil
            && (source == .thread || conversation.message(messageID) == nil)
        let composer = inPane ? conversation.thread.composer : conversation.composer
        guard await composer.dontSend(messageID) else {
            onToast(String(localized: "Couldn’t take the message back. Try again."))
            return
        }
    }

    /// The person said yes to the question asked (`request` is `.confirm`): it is done now.
    public func confirm() async {
        guard case let .confirm(action, messageID, _)? = request else { return }
        request = nil
        switch action {
        case .unsend: await unsend(messageID)
        case .deleteForMe: await deleteForMe(messageID)
        default: break
        }
    }

    /// The person said no, or closed the picker.
    public func dismissRequest() {
        request = nil
    }

    // MARK: - Keys and commands

    /// ⌘⇧F: the forward picker for the selected message, or a toast saying to select one.
    public func forwardSelected() {
        guard let selected = conversation.selectedMessage,
              conversation.availableActions(for: selected).actions.contains(.forward) else {
            onToast(String(localized: "Select a message to forward"))
            return
        }
        request = .forward(messageID: selected.id)
    }

    /// What ⌘C copies. Anything in the responder chain that can copy now (selected text in the composer, in a
    /// message's code block, in a sheet or Settings) copies with the system's Copy. Only when nothing can, and the
    /// keyboard is in the open chat or its thread pane, is the selected message there copied; anywhere else (the
    /// search panel, a sheet, another window) ⌘C copies no message.
    public static func copyChoice(responderCanCopy: Bool, place: CopyPlace, chatSelection: String?,
                                  paneSelection: String?) -> CopyChoice {
        if responderCanCopy { return .text }
        switch place {
        case .chat: return chatSelection.map { .message(id: $0, source: .chat) } ?? .nothing
        case .pane: return paneSelection.map { .message(id: $0, source: .thread) } ?? .nothing
        case .elsewhere: return .nothing
        }
    }

    /// ⌘C (`copyChoice`): copies the selected message as the menu's Copy copies it (with its time when Settings says
    /// so), when that is the choice and the message offers Copy. Returns what was done: for `.text` and `.nothing`
    /// the view sends the system's Copy.
    @discardableResult
    public func copySelected(responderCanCopy: Bool, inConversation: Bool, focus: MessageFocus) async -> CopyChoice {
        let choice = Self.copyChoice(responderCanCopy: responderCanCopy, place: focus.copyPlace(inConversation: inConversation),
                                     chatSelection: conversation.selectedMessageID, paneSelection: focus.paneSelection)
        guard case let .message(id, source) = choice, let message = conversation.message(id, from: source),
              conversation.availableActions(for: message).actions.contains(.copy) else {
            return choice == .text ? .text : .nothing
        }
        await perform(.copy, on: id, from: source)
        return choice
    }

    /// ⌘⇧L and "Send later": the Send Later picker, when the composer has text that can be scheduled.
    public func requestSendLater() {
        guard conversation.composer.canSchedule else { return }
        request = .sendLater
    }

    /// "Create quick reply from draft": asks for a title for the composer's text.
    public func requestQuickReplyFromDraft() {
        guard canCreateQuickReply else { return }
        request = .quickReplyTitle
    }

    /// There is a draft to make a quick reply of, and somewhere to keep it.
    public var canCreateQuickReply: Bool {
        quickReplies != nil && !conversation.composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Saves the composer's text as a quick reply called `title`. False, with a toast saying why, when it can't be.
    @discardableResult
    public func createQuickReply(title: String) -> Bool {
        guard let quickReplies else { return false }
        do {
            try quickReplies.add(title: title, text: conversation.composer.text)
        } catch let error as QuickReplyError {
            onToast(Self.text(for: error))
            return false
        } catch {
            return false
        }
        if request == .quickReplyTitle { request = nil }
        return true
    }

    // MARK: - Forward, polls, history

    /// Sends a copy of the message to each chat (at most `ForwardParams.maxRooms` a call). Returns how many got one,
    /// the names of those that didn't, and the names of those the engine didn't answer for (the call timed out or the
    /// connection ended: the copies may have gone, so they are never called failed), and says so in a toast.
    @discardableResult
    public func forward(_ messageID: String, to roomIDs: [String]) async
        -> (sent: Int, failed: [String], unanswered: [String]) {
        var unique: [String] = []
        for id in roomIDs where !unique.contains(id) { unique.append(id) }
        guard !unique.isEmpty else { return (0, [], []) }
        if request == .forward(messageID: messageID) { request = nil }
        var sent = 0
        var failedIDs: [String] = []
        var unansweredIDs: [String] = []
        if let client = appModel.client {
            for chunk in unique.chunked(ForwardParams.maxRooms) {
                do {
                    let result: ForwardResult = try await client.call(
                        "message.forward", ForwardParams(eventID: messageID, roomIDs: chunk), timeout: forwardTimeout)
                    sent += result.sent.count
                    failedIDs += result.failed.map(\.roomID)
                } catch let error as EngineError where error.mayHaveBeenHandled {
                    unansweredIDs += chunk
                } catch {
                    failedIDs += chunk
                }
            }
        } else {
            failedIDs = unique
        }
        let failed = await chatNames(failedIDs)
        let unanswered = await chatNames(unansweredIDs)
        let mayHaveGone = ListFormatter.localizedString(byJoining: unanswered)
        if !failed.isEmpty, !unanswered.isEmpty {
            let couldNot = ListFormatter.localizedString(byJoining: failed)
            onToast(String(localized: "Couldn’t forward to \(couldNot). The message may have been forwarded to \(mayHaveGone): check before forwarding it again."))
        } else if !unanswered.isEmpty {
            onToast(String(localized: "Courier’s engine did not answer. The message may have been forwarded to \(mayHaveGone): check before forwarding it again."))
        } else if !failed.isEmpty {
            onToast(String(localized: "Couldn’t forward to \(ListFormatter.localizedString(byJoining: failed))"))
        } else if sent == 1 {
            onToast(String(localized: "Forwarded to 1 chat"))
        } else {
            onToast(String(localized: "Forwarded to \(sent) chats"))
        }
        return (sent, failed, unanswered)
    }

    /// Votes in a poll with these options ([] takes my vote back). The chat is read again for the tally.
    public func vote(_ pollID: String, options: [String]) async {
        await call(fallback: String(localized: "Your vote wasn’t counted. Try again.")) { client in
            let _: Sent = try await client.call("poll.vote", VoteParams(eventID: pollID, optionIDs: options))
        }
        conversation.refresh()
    }

    /// A message's versions, first as sent and then each edit, oldest first; [] (and a toast) when they can't be read.
    public func history(of messageID: String) async -> [Version] {
        guard let client = appModel.client else { return [] }
        do {
            let result: HistoryResult = try await client.call("message.history", EventParams(eventID: messageID))
            return result.versions
        } catch {
            onToast(EngineErrorText.text(for: error, fallback: String(localized: "That didn’t work. Try again.")))
            return []
        }
    }

    /// Sends a new poll to the open chat. False when it wasn't: the chat has no polls (the toast says why), the
    /// draft has problems (the window shows them), or the engine refused it (a toast).
    @discardableResult
    public func createPoll(_ draft: PollDraft) async -> Bool {
        guard let room = conversation.roomID else { return false }
        guard let polls = conversation.features.poll else {
            if let reason = conversation.features.pollsUnavailableReason(network: conversation.network) {
                onToast(reason)
            }
            return false
        }
        guard draft.problems(in: polls).isEmpty else { return false }
        var sent = false
        await call(fallback: String(localized: "The poll couldn’t be sent.")) { client in
            let params = PollParams(roomID: room, question: draft.sendableQuestion, options: draft.sendableOptions,
                                    multiple: draft.multiple)
            let _: Sent = try await client.call("poll.create", params)
            sent = true
        }
        conversation.refresh()
        return sent
    }

    // MARK: - Doing it

    private func copy(_ message: TimelineMessage, withTime: Bool) {
        let text = message.rich.text
        guard withTime else {
            pasteboard.setString(text)
            return
        }
        let time = formatTime(Date(timeIntervalSince1970: Double(message.ts) / 1000))
        // Named as the timeline names them: me as "You", anyone else by name (or, with none, their ID).
        let name = message.mine ? String(localized: "You") : message.senderName.isEmpty ? message.sender : message.senderName
        pasteboard.setString("[\(time)] \(name): \(text)")
    }

    private func setBookmark(_ messageID: String, on: Bool) async {
        await call(fallback: String(localized: "That didn’t work. Try again.")) { client in
            let _: Empty = try await client.call("message.setBookmarked", BookmarkParams(eventID: messageID, on: on))
        }
        conversation.refresh()
    }

    private func unsend(_ messageID: String) async {
        guard let room = conversation.roomID else { return }
        let network = conversation.network
        await call(fallback: Self.couldntUnsend(network)) { client in
            let sent: Sent = try await client.call("message.unsend", EventParams(eventID: messageID))
            // The engine took it; the network may still say no.
            if self.pendingUnsends.count > 100 { self.pendingUnsends = [:] }
            self.pendingUnsends[sent.eventID] = network
            self.checkUnsend(sent.eventID, in: room)
        }
        conversation.refresh()
    }

    private func deleteForMe(_ messageID: String) async {
        await call(fallback: String(localized: "That didn’t work. Try again.")) { client in
            let _: Empty = try await client.call("message.deleteForMe", EventParams(eventID: messageID))
        }
        conversation.refresh()
    }

    /// Calls the engine; a refusal is a toast in Courier's words (`fallback` for a code it has none for).
    private func call(fallback: String, _ body: (EngineClient) async throws -> Void) async {
        guard let client = appModel.client else {
            onToast(EngineErrorText.text(for: EngineError.notConnected, fallback: fallback))
            return
        }
        do {
            try await body(client)
        } catch {
            onToast(EngineErrorText.text(for: error, fallback: fallback))
        }
    }

    /// The chats' names, by their rows; "a chat" for one the engine doesn't have.
    private func chatNames(_ ids: [String]) async -> [String] {
        guard !ids.isEmpty else { return [] }
        var names: [String: String] = [:]
        if let client = appModel.client,
           let result: InboxResult = try? await client.call("inbox.list", InboxListParams(roomIDs: ids)) {
            for row in result.rooms where !row.name.isEmpty { names[row.roomID] = row.name }
        }
        return ids.map { names[$0] ?? String(localized: "a chat") }
    }

    // MARK: - Refusals that come later

    private func handle(_ change: Change) {
        guard case let .status(room, eventID) = change else { return }
        if pendingUnsends[eventID] != nil { checkUnsend(eventID, in: room) }
        if room == conversation.roomID {
            if changedStatuses.count > 500 { changedStatuses = [] }
            changedStatuses.insert(eventID)
        }
    }

    /// Reads an unsend's redaction: refused by the network, it is told (once); sent, it is done; still pending, it
    /// waits for its next status change.
    private func checkUnsend(_ redactionID: String, in room: String) {
        guard let client = appModel.client else { return }
        Task { [weak self] in
            let page: EventsPage? = try? await client.call(
                "room.events", RoomEventsParams(roomID: room, around: redactionID, limit: 1))
            guard let self, let event = page?.events.first(where: { $0.eventID == redactionID }) else { return }
            switch event.status {
            case .failed:
                guard let network = self.pendingUnsends.removeValue(forKey: redactionID) else { return }
                self.onToast(Self.couldntUnsend(network))
            case .sent:
                self.pendingUnsends[redactionID] = nil
            default:
                break
            }
        }
    }

    /// The open chat's timeline, or its thread pane's, as just read: an edit of mine that is now refused, after a
    /// status change the engine reported, is told once.
    private func timelineChanged(_ items: [TimelineItem]) {
        guard !changedStatuses.isEmpty else { return }
        for case let .message(message) in items {
            guard let edit = message.failedEditID, changedStatuses.contains(edit) else { continue }
            changedStatuses.remove(edit)
            guard toldEdits.insert(edit).inserted else { continue }
            onToast(Self.couldntEdit(conversation.network))
        }
    }

    // MARK: - Words

    static func couldntUnsend(_ network: String) -> String {
        guard let name = NetworkNames.displayName(of: network) else {
            return String(localized: "Couldn’t unsend: the network said no.")
        }
        return String(localized: "Couldn’t unsend: \(name) said no.")
    }

    static func couldntEdit(_ network: String) -> String {
        guard let name = NetworkNames.displayName(of: network) else {
            return String(localized: "Couldn’t edit: the network said no.")
        }
        return String(localized: "Couldn’t edit: \(name) said no.")
    }

    public static func text(for error: QuickReplyError) -> String {
        switch error {
        case .full: String(localized: "You have as many quick replies as Courier keeps. Delete one to add another.")
        case .emptyTitle: String(localized: "Give the quick reply a title.")
        case .titleTooLong: String(localized: "Titles can be up to \(QuickReplies.maxTitle) characters.")
        case .emptyText: String(localized: "Type the quick reply’s text first.")
        case .textTooLong: String(localized: "That’s too long for a quick reply.")
        case .duplicateTitle: String(localized: "A quick reply already has that title.")
        case .notFound: String(localized: "That didn’t work. Try again.")
        }
    }
}
