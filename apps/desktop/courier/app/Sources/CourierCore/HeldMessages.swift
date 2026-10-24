// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What a held message was, as it left the composer: kept on this Mac so it can come back on Undo even when the
/// engine's answer is lost.
public struct HeldCopy: Equatable, Sendable {
    public var text: String
    public var entities: [TextEntity]
    /// For a file: the file, and no text.
    public var attachment: ComposerAttachment?
    public var reply: QuotedMessage?
    public var threadRoot: String?

    public init(text: String = "", entities: [TextEntity] = [], attachment: ComposerAttachment? = nil,
                reply: QuotedMessage? = nil, threadRoot: String? = nil) {
        self.text = text
        self.entities = entities
        self.attachment = attachment
        self.reply = reply
        self.threadRoot = threadRoot
    }
}

/// What ⌘Z on a held message came to.
enum HeldUndo: Equatable {
    /// Nothing is held in the chat: ⌘Z is the text view's.
    case nothingHeld
    /// Taken back: this goes back into the composer, and "Message unsent from Courier" says so.
    case undone(HeldCopy)
    /// Not taken back (it went, it failed, or no one can tell yet): only this is said.
    case notUndone(String)
}

/// My held (undo send) messages, by chat, and what Undo does with them.
///
/// Each message is undone at most once: it leaves the list before message.undo is called, and one being undone or
/// done with is never brought back by a timeline read. When the engine's answer to Undo is lost (no answer, or the
/// message is not found), its status is read, in its thread for a thread reply: gone means the engine did undo it,
/// so the copy kept here comes back (restoring text never sends anything, so it can't be sent twice); still queued
/// puts it back to undo again; sent or failed is said as Ruling 32 says it. If even that read fails, the message waits
/// unresolved until a timeline read, or a later lookup, settles it.
///
/// A message whose window has ended (plus `margin`) is no longer held, timeline or not: the chat's timeline leaves
/// thread replies out, so it would never say a held thread reply went.
///
/// A message waiting for its network ("Waiting to send", or no account to go through) is held too, with no window: it
/// waits however long its network takes, and Don't Send is Undo. A held message whose window ended while its network
/// was down becomes one. A message the timeline shows waiting is held whenever it does, though it left hold before (a
/// hand-off that found the network down again goes waiting, Sending…, waiting): only one Undo took back stays gone,
/// whatever a stale page shows.
@MainActor
final class HeldMessages {
    /// How long after its window a message is still offered to undo: the engine's timer may hand it off a little late.
    static let margin: TimeInterval = 2

    private struct Entry: Equatable {
        let id: String
        /// What was sent; nil for one learned from the timeline (held before a restart, say).
        var copy: HeldCopy?
        var threadRoot: String?
        /// When its window ends; nil when not known.
        var holdEnd: Date?

        init(id: String, copy: HeldCopy? = nil, threadRoot: String? = nil, holdEnd: Date? = nil) {
            self.id = id
            self.copy = copy
            self.threadRoot = threadRoot
            self.holdEnd = holdEnd
        }
    }

    /// The most messages remembered as having left hold (`settled`); past it, the oldest half is forgotten.
    static let maxSettled = 200
    /// How many messages are remembered as having left hold. For tests.
    var settledCount: Int { settled.count }

    private var held: [String: [Entry]] = [:]
    private var undoing: Set<String> = []
    /// Messages that left hold (sent, undone, past their window): a stale read that still shows one queued never
    /// holds it again. Only the newest `maxSettled` are kept, oldest first in `settledOrder`.
    private var settled: Set<String> = []
    private var settledOrder: [String] = []
    /// Messages Undo took back (the engine said so): never held again, even by a page that shows one waiting. Only the
    /// newest `maxSettled`, oldest first in `undoneOrder`.
    private var undone: Set<String> = []
    private var undoneOrder: [String] = []
    /// Undone with no answer, and no way to tell yet what happened: by event, with its chat.
    private var unresolved: [String: (room: String, entry: Entry)] = [:]
    private var checks: [String: Task<Void, Never>] = [:]

    var sender: @MainActor () -> MessageSending? = { nil }
    var now: @MainActor () -> Date = Date.init
    /// A message of the open chat as a reply chip shows it, for a reply the engine gives back by ID only.
    var quote: @MainActor (String) -> QuotedMessage? = { _ in nil }
    /// A chat's list changed.
    var onChange: @MainActor (_ room: String) -> Void = { _ in }
    /// An Undo whose answer was lost turned out, later, to have taken the message back: into its chat's composer.
    var onRestore: @MainActor (_ room: String, HeldCopy) -> Void = { _, _ in }
    /// Something to tell the person, found out after ⌘Z returned.
    var onToast: @MainActor (String) -> Void = { _ in }

    /// The chat's held messages, newest last. Ones past their window are dropped first.
    func ids(in room: String) -> [String] {
        prune(room)
        return (held[room] ?? []).map(\.id)
    }

    /// A message sent held, as `copy`, for `holdMillis`.
    func add(_ id: String, in room: String, copy: HeldCopy, holdMillis: Int) {
        guard !settled.contains(id), !undoing.contains(id), !(held[room] ?? []).contains(where: { $0.id == id })
        else { return }
        let entry = Entry(id: id, copy: copy, threadRoot: copy.threadRoot,
                          holdEnd: now().addingTimeInterval(Double(holdMillis) / 1000))
        held[room, default: []].append(entry)
        onChange(room)
    }

    /// The chat's timeline, as read: my messages it shows queued or waiting are held (a waiting one with no window),
    /// and ones it shows otherwise are not.
    /// Held messages it doesn't show (thread replies, not yet loaded) stay until their window ends. An unresolved
    /// undo is settled by what it shows, or, when it isn't there, by a lookup.
    func update(from items: [TimelineItem], in room: String) {
        var shown: [String: StatusLine] = [:] // my messages it shows, by their status: only mine are ever held
        var queued: [String] = []
        var waiting = Set<String>()
        for case let .message(message) in items {
            // Only my newest message says Sent: one of mine shown with no line has gone too.
            guard message.mine else { continue }
            let status = message.statusLine ?? .sent
            shown[message.id] = status
            if status == .queued || status.isWaiting { queued.append(message.id) }
            if status.isWaiting { waiting.insert(message.id) }
        }
        for (id, pending) in unresolved where pending.room == room {
            if let status = shown[id] {
                settle(id, status: status)
            } else {
                check(id)
            }
        }
        let known = held[room] ?? []
        var list: [Entry] = []
        for id in queued where (!settled.contains(id) || waiting.contains(id)) && !undone.contains(id)
            && !undoing.contains(id) && unresolved[id] == nil {
            var entry = known.first { $0.id == id } ?? Entry(id: id)
            if waiting.contains(id) { entry.holdEnd = nil } // it waits for its network, not for a window
            list.append(entry)
        }
        for entry in known where !list.contains(where: { $0.id == entry.id }) {
            if shown[entry.id] != nil {
                markSettled(entry.id) // shown, and not queued: it went, or failed
            } else {
                list.append(entry)
            }
        }
        held[room] = list.isEmpty ? nil : list
        prune(room)
        onChange(room)
    }

    /// ⌘Z: takes back the chat's newest held message; with `id`, that one (a click on it).
    func undoNewest(in room: String, id: String? = nil) async -> HeldUndo {
        prune(room)
        guard let sender = sender(), let list = held[room],
              let index = id.map({ id in list.lastIndex { $0.id == id } }) ?? list.indices.last
        else { return .nothingHeld }
        let entry = list[index]
        held[room]?.remove(at: index)
        undoing.insert(entry.id)
        onChange(room)
        defer { undoing.remove(entry.id) }
        do {
            let draft = try await sender.undo(eventID: entry.id)
            markUndone(entry.id)
            // The engine's words are what was typed; a file, and the reply chip, are the ones kept here.
            if let copy = entry.copy, copy.attachment != nil { return .undone(copy) }
            var given = copy(of: draft)
            if let reply = entry.copy?.reply, reply.eventID == draft.replyTo { given.reply = reply }
            return .undone(given)
        } catch let EngineError.rpc(code, _, _) where code == .alreadySent {
            markSettled(entry.id)
            let status = try? await sender.status(of: entry.id, in: room, thread: entry.threadRoot)
            return .notUndone(Self.alreadySentText(status ?? nil))
        } catch {
            guard Self.answerLost(error) else {
                // Refused for another reason: nothing happened to it, and it is still held.
                restore(entry, in: room)
                return .notUndone(EngineErrorText.text(for: error,
                                                       fallback: String(localized: "The message couldn’t be unsent.")))
            }
            let status: StatusLine?
            do {
                status = try await sender.status(of: entry.id, in: room, thread: entry.threadRoot)
            } catch {
                unresolved[entry.id] = (room, entry)
                return .notUndone(EngineErrorText.text(for: error,
                                                       fallback: String(localized: "The message couldn’t be unsent.")))
            }
            return outcome(of: entry, in: room, status: status)
        }
    }

    /// ⌘⇧Z: the chat's held messages, now. It waits for the engine's answer; until then, and if the call fails, they
    /// stay held, and go when their windows end.
    func sendNow(in room: String) async {
        prune(room)
        guard let sender = sender(), let sent = held[room]?.map(\.id), !sent.isEmpty else { return }
        do {
            try await sender.sendHeld(roomID: room)
        } catch {
            return
        }
        for id in sent { markSettled(id) }
        held[room]?.removeAll { sent.contains($0.id) }
        if held[room]?.isEmpty == true { held[room] = nil }
        onChange(room)
    }

    /// Returns once every lookup started by a timeline read is done. For tests.
    func waitForChecks() async {
        while let (id, task) = checks.first {
            await task.value
            if checks[id] == task { checks[id] = nil }
        }
    }

    // MARK: -

    /// What a lost Undo came to, by the message's status now: nil is gone (the engine did undo it).
    private func outcome(of entry: Entry, in room: String, status: StatusLine?) -> HeldUndo {
        switch status {
        case nil:
            markUndone(entry.id)
            guard let copy = entry.copy else {
                // Unsent, but held before this composer knew it: there is nothing here to give back.
                return .notUndone(String(localized: "Message unsent from Courier"))
            }
            return .undone(copy)
        case .queued:
            restore(entry, in: room)
            return .notUndone(String(localized: "Courier’s engine didn’t answer. The message is still queued: undo it again."))
        case .waiting?, .noAccount?:
            restore(entry, in: room)
            let text = String(localized: "Courier’s engine didn’t answer. The message is still waiting: try Don’t Send again.")
            return .notUndone(text)
        default:
            markSettled(entry.id)
            return .notUndone(Self.alreadySentText(status))
        }
    }

    /// An unresolved undo, settled by the status found for it.
    private func settle(_ id: String, status: StatusLine?) {
        guard let pending = unresolved.removeValue(forKey: id) else { return }
        checks[id]?.cancel()
        switch outcome(of: pending.entry, in: pending.room, status: status) {
        case let .undone(copy):
            onRestore(pending.room, copy)
        case let .notUndone(message):
            if status != .queued, !(status?.isWaiting ?? false) { onToast(message) }
        case .nothingHeld:
            break
        }
    }

    /// Looks up an unresolved undo that the timeline doesn't show; once at a time.
    private func check(_ id: String) {
        guard checks[id] == nil, let pending = unresolved[id], let sender = sender() else { return }
        checks[id] = Task { [weak self] in
            let status: StatusLine?
            do {
                status = try await sender.status(of: id, in: pending.room, thread: pending.entry.threadRoot)
            } catch {
                self?.checks[id] = nil
                return // still unresolved: the next read tries again
            }
            self?.checks[id] = nil
            self?.settle(id, status: status)
        }
    }

    /// Back in the list, newest, to undo again.
    private func restore(_ entry: Entry, in room: String) {
        held[room, default: []].removeAll { $0.id == entry.id }
        held[room, default: []].append(entry)
        onChange(room)
    }

    /// Remembers that `id` left hold, forgetting the oldest half once there are more than `maxSettled`.
    private func markSettled(_ id: String) {
        Self.remember(id, in: &settled, order: &settledOrder)
    }

    /// Remembers that Undo took `id` back: it left hold for good.
    private func markUndone(_ id: String) {
        markSettled(id)
        Self.remember(id, in: &undone, order: &undoneOrder)
    }

    private static func remember(_ id: String, in set: inout Set<String>, order: inout [String]) {
        guard set.insert(id).inserted else { return }
        order.append(id)
        guard order.count > maxSettled else { return }
        let forgotten = order.prefix(order.count - maxSettled / 2)
        set.subtract(forgotten)
        order.removeFirst(forgotten.count)
    }

    /// Don't Send on a message the timeline shows waiting that isn't held yet (no read since it went back to
    /// waiting): held now, with no window, so Undo can take it back. Not one Undo took back, or one being undone.
    func holdWaiting(_ id: String, in room: String) {
        guard !undone.contains(id), !undoing.contains(id), unresolved[id] == nil,
              !(held[room] ?? []).contains(where: { $0.id == id }) else { return }
        held[room, default: []].append(Entry(id: id))
        onChange(room)
    }

    /// Drops held messages past their window and its margin.
    private func prune(_ room: String) {
        guard let list = held[room] else { return }
        let time = now()
        let live = list.filter { entry in
            guard let end = entry.holdEnd else { return true }
            return time <= end.addingTimeInterval(Self.margin)
        }
        guard live.count != list.count else { return }
        for entry in list where !live.contains(entry) { markSettled(entry.id) }
        held[room] = live.isEmpty ? nil : live
        onChange(room)
    }

    /// Undo's answer doesn't say what happened: none came, or the message is no longer found.
    private static func answerLost(_ error: Error) -> Bool {
        guard let error = error as? EngineError else { return false }
        if error.mayHaveBeenHandled { return true }
        if case .rpc(.notFound, _, _) = error { return true }
        return false
    }

    private func copy(of draft: Draft) -> HeldCopy {
        HeldCopy(text: draft.text, entities: RichTextHTML.sendable(draft.entities, in: draft.text),
                 reply: draft.replyTo.map {
                     quote($0) ?? QuotedMessage(eventID: $0, senderName: "", mine: false, text: "", kind: .text)
                 },
                 threadRoot: draft.threadRoot)
    }

    /// What Undo says when the engine says the message already went, by its status now (Ruling 32): "Already sent"
    /// only when it did.
    static func alreadySentText(_ status: StatusLine?) -> String {
        switch status {
        case .sent, .delivered, .seen:
            String(localized: "Already sent")
        case .failed, .notSent:
            String(localized: "Too late to undo, and it wasn’t sent. Retry it in the chat.")
        case .sending:
            // On its way: it may still come back as waiting (its network went down again), and then it can be
            // taken back.
            String(localized: "It’s on its way. If it comes back as waiting, try again.")
        default:
            // Not known: neither "sent" nor "not sent".
            EngineErrorText.text(for: EngineError.rpc(.alreadySent, message: "", reason: nil), fallback: "")
        }
    }
}
