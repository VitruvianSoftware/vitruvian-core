// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// The open chat's messages scheduled to send later (the strip above the composer, 01 §5): waiting, canceled
/// because they wrote first, or missed while Courier was closed, soonest first.
///
/// The list is the engine's (`scheduled.list`), read when a chat opens, when the engine is greeted or resyncs, and
/// each time it says the open chat's scheduled messages changed. Nothing is assumed: after Send Now, Reschedule,
/// Edit or Delete the list is read again, and shows what the engine has, whether the call worked or not. A refusal is
/// a toast, in Courier's words.
@MainActor
public final class ScheduledModel: ObservableObject {
    /// The open chat's, soonest first (by due time, then as scheduled).
    @Published public private(set) var scheduled: [ScheduledMessage] = []
    /// Active scheduled message being edited in `ScheduledEditSheet`.
    @Published public var editingMessage: ScheduledMessage?
    /// Active scheduled message being rescheduled in `ScheduledRescheduleSheet`.
    @Published public var reschedulingMessage: ScheduledMessage?
    /// Where toasts go: the inbox's, the one place they show.
    public var onToast: @MainActor (String) -> Void = { _ in }

    private let appModel: AppModel
    public private(set) var roomID: String?
    private var subscription: AnyCancellable?
    private weak var observedLifecycle: SystemLifecycleModel?
    private var lockObserver: AnyCancellable?
    /// Goes up with each read: an answer older than the newest one shown, or for another chat, is dropped.
    private var serial = 0
    private var shownSerial = 0

    public init(appModel: AppModel, followsAppSelection: Bool = true) {
        self.appModel = appModel
        if followsAppSelection {
            subscription = appModel.$selectedRoomID.removeDuplicates().sink { [weak self] room in
                self?.open(room)
            }
        }
        self.lockObserver = NotificationCenter.default
            .publisher(for: SystemLifecycleModel.didLockNotification)
            .sink { [weak self] notification in
                self?.observedLifecycle = notification.object as? SystemLifecycleModel
                self?.dismissAllPresentations()
            }
        appModel.onConnect { [weak self] _ in self?.read() }
        appModel.onChange { [weak self] change in
            guard let self, case let .scheduled(room) = change else { return }
            if let currentRoom = self.roomID {
                let memberIDs = self.appModel.mergedChats[currentRoom]?.roomIDs ?? [currentRoom]
                guard memberIDs.contains(room) else { return }
            } else {
                guard self.appModel.isOpen(roomID: room) else { return }
            }
            self.read()
        }
    }

    /// Clears any presented scheduled message editor or reschedule sheets.
    public func dismissAllPresentations() {
        editingMessage = nil
        reschedulingMessage = nil
    }

    public var lifecycle: SystemLifecycleModel {
        observedLifecycle ?? appModel.lifecycle
    }

    public var isLocked: Bool {
        !AppLockGate.shared.canPerform(.send, lifecycle: lifecycle)
    }

    /// Opens a room explicitly for a detached window (`followsAppSelection == false`).
    public func openDetachedRoom(_ room: String?) {
        open(room)
    }

    private func open(_ room: String?) {
        roomID = room
        scheduled = []
        read()
    }

    private func read() {
        guard let room = roomID, let client = appModel.client else { return }
        let memberIDs = appModel.mergedChats[room]?.roomIDs ?? [room]
        serial += 1
        let mine = serial
        Task { [weak self] in
            var collected: [ScheduledMessage] = []
            for memberID in memberIDs {
                guard let result: ScheduledResult = try? await client.call(
                    "scheduled.list", RoomOptionalParams(roomID: memberID)
                ) else { return }
                collected.append(contentsOf: result.scheduled.filter { $0.roomID == memberID })
            }
            guard let self, room == self.roomID, client === self.appModel.client,
                  mine > self.shownSerial else { return }
            self.shownSerial = mine
            self.scheduled = collected.sorted { ($0.dueAt, $0.outboxID) < ($1.dueAt, $1.outboxID) }
        }
    }

    /// "Send Now": sends it at once, whatever its state.
    public func sendNow(_ id: Int64) async {
        await act { client in
            let _: Empty = try await client.call("scheduled.sendNow", OutboxIDParams(outboxID: id))
        }
    }

    /// "Reschedule": a new time, which makes a canceled or missed message wait again.
    public func reschedule(_ id: Int64, to due: Date) async {
        await act { client in
            let params = ScheduledUpdateParams(outboxID: id, dueAt: Int64((due.timeIntervalSince1970 * 1000).rounded()))
            let _: ScheduledMessage = try await client.call("scheduled.update", params)
        }
    }

    /// What "Edit" sends for `message` with its words now `text`: its formatting follows the change, so a bold
    /// message edited for a typo stays bold (`EntityEditing.following`).
    public static func edited(_ message: ScheduledMessage, to text: String) -> RichText {
        RichText(text: text, entities: EntityEditing.following(message.entities, from: message.text, to: text))
    }

    /// "Edit": new words and their formatting. Text with no ranges sends none, so none are kept.
    public func edit(_ id: Int64, text: RichText) async {
        await act { client in
            let params = ScheduledUpdateParams(outboxID: id, text: text.text,
                                               entities: text.entities.isEmpty ? nil : text.entities)
            let _: ScheduledMessage = try await client.call("scheduled.update", params)
        }
    }

    /// "Delete Without Sending".
    public func delete(_ id: Int64) async {
        await act { client in
            let _: Empty = try await client.call("scheduled.delete", OutboxIDParams(outboxID: id))
        }
    }

    private func act(_ call: (EngineClient) async throws -> Void) async {
        guard !isLocked else { return }
        guard let client = appModel.client else {
            onToast(EngineErrorText.text(for: EngineError.notConnected, fallback: ""))
            return
        }
        do {
            try await call(client)
        } catch {
            onToast(EngineErrorText.text(for: error, fallback: String(localized: "That didn’t work. Try again.")))
        }
        read()
    }
}
