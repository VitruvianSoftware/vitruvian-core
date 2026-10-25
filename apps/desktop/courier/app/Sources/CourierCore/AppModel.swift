// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// A chat to open at one of its messages (a search result chosen).
public struct PendingMessage: Equatable, Sendable {
    public let roomID: String
    public let eventID: String
    /// Goes up with each request, so the same message asked for twice is two requests.
    public let serial: Int
}

/// The app's state, for its views: the engine's state, the client of the engine that is up, and its accounts.
///
/// Every time an engine is greeted (the first time and after every restart) and every time the engine says
/// `resync`, the model reads again what the app shows: the accounts here, and whatever the hooks given to
/// `onConnect` read (the inbox, the open chat). It never keeps what an earlier engine said, so a message that was
/// pending when the engine died shows as the new engine's store has it.
@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var engineState: EngineSupervisor.State = .starting
    @Published public private(set) var accounts: [Account] = []
    /// The client of the engine that is up; nil while it is not.
    @Published public private(set) var client: EngineClient?
    /// The chat the person has open. The inbox moves it, and the conversation and a clicked notification read it.
    /// A reload never clears it: a chat that is not in the list for a moment is still the chat that is open.
    @Published public var selectedRoomID: String?
    /// Merged chat definitions known to the app, keyed by `mergeID`.
    @Published public var mergedChats: [String: MergedChat] = [:]

    /// Whether `roomID` is currently open in the conversation pane: true when `roomID == selectedRoomID`, or when
    /// the selection is a merged chat and `roomID` is one of its member rooms.
    public func isOpen(roomID: String) -> Bool {
        guard let selected = selectedRoomID else { return false }
        if selected == roomID { return true }
        if let merge = mergedChats[selected], merge.roomIDs.contains(roomID) {
            return true
        }
        return false
    }

    /// The room IDs currently open in the conversation pane: the member room IDs when a merged chat is selected,
    /// `[selectedRoomID]` for a single room, or `[]` when nothing is selected.
    public var openRoomIDs: [String] {
        guard let selected = selectedRoomID else { return [] }
        if let merge = mergedChats[selected], !merge.roomIDs.isEmpty {
            return merge.roomIDs
        }
        return [selected]
    }
    /// When the engine that is up was greeted (the app connected to it); nil while none is. A message that is
    /// older than this came from the engine's history, not from the world just now.
    public private(set) var connectedAt: Date?
    /// When `accounts` was last read from the engine that is up; nil from the moment an engine is connected until
    /// its first answer, and while none is. Until then `accounts` is the previous engine's list, if any, and what
    /// it says about the accounts is not the new engine's word.
    @Published public private(set) var accountsReadAt: Date?
    /// The message the last `open(.message)` asked for. It is never cleared: the conversation remembers the
    /// serial of the last one it took, so each request is taken once.
    @Published public private(set) var pendingMessage: PendingMessage?
    private var pendingSerial = 0

    public let supervisor: EngineSupervisor
    private var hooks: [@MainActor (EngineClient) async -> Void] = []
    private var changeHooks: [@MainActor (Change) -> Void] = []
    private let clock: @Sendable () -> Date
    private var watcher: Task<Void, Never>?
    /// Reads and follows the connected engine: subscribes to its changes, reads everything, then re-reads as they
    /// say. A task of its own, so a slow read never holds up a state change.
    private var connection: Task<Void, Never>?

    /// - Parameter clock: the time `connectedAt` takes; tests give one they move.
    public init(supervisor: EngineSupervisor, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.supervisor = supervisor
        self.clock = clock
    }

    /// Runs `hook` with the new client every time the app must read everything again: after each connect, and
    /// on resync.
    public func onConnect(_ hook: @escaping @MainActor (EngineClient) async -> Void) {
        hooks.append(hook)
    }

    /// Runs `hook` for each change the engine reports, except `resync`, which runs the `onConnect` hooks instead.
    /// The hook runs on the main actor and must be quick: it should note what to read, not read it.
    public func onChange(_ hook: @escaping @MainActor (Change) -> Void) {
        changeHooks.append(hook)
    }

    public func start() {
        guard watcher == nil else { return }
        let states = supervisor.state
        watcher = Task { [weak self] in
            for await state in states {
                self?.apply(state)
            }
        }
        supervisor.start()
    }

    /// How long quitting waits, at most, for the engine to take every held message (`sendHeldMessages`), in seconds.
    public nonisolated static let sendHeldAtQuitTimeout: TimeInterval = 5

    /// Quitting: hands every chat's held (undo send) messages to the engine now, and waits for its answer, at most
    /// `timeout` seconds, so a stuck engine can't keep Courier from quitting. Never fire-and-forget: a call dropped as
    /// the engine stops would leave them to fail as "not connected".
    ///
    /// message.sendHeld claims every held message at once, then hands each to its network, which may wait (up to
    /// 30 s a message) for the account to log in. One still not sent when the bound ends and the engine stops is
    /// not lost and not sent twice: it becomes failed, with Retry and Delete in the chat. Only a message the engine
    /// never claimed (it was down) is sent at the next start, if under an hour late.
    public func sendHeldMessages(timeout: TimeInterval = AppModel.sendHeldAtQuitTimeout) async {
        guard let client else { return }
        let _: Empty? = try? await client.call("message.sendHeld", RoomOptionalParams(), timeout: timeout)
    }

    /// Quitting, in order: a typing stop for each chat I'm typing in, from the chat's composer and the thread pane's
    /// (`ConversationModel.stopTyping`); every held message handed to the engine (bounded: `sendHeldMessages`); then
    /// the engine stopped. The engine's own shutdown stops any typing it still has (Actions.StopTyping), so a stop
    /// that doesn't arrive in time still goes.
    public func quit(_ conversation: ConversationModel) async {
        await conversation.stopTyping()
        await sendHeldMessages()
        await stop()
    }

    /// Stops the engine and returns once it is gone.
    public func stop() async {
        supervisor.stop()
        await supervisor.waitUntilStopped()
    }

    /// Takes a new state at once; whatever has to be read for it is read on `connection`.
    private func apply(_ state: EngineSupervisor.State) {
        engineState = state
        connection?.cancel()
        connection = nil
        guard state == .connected, let client = supervisor.client else {
            self.client = nil
            connectedAt = nil
            accountsReadAt = nil
            return
        }
        if self.client !== client {
            connectedAt = clock()
            accountsReadAt = nil
        }
        self.client = client
        connection = Task { [weak self] in
            // Subscribe before reading, so nothing that changes in between is missed.
            let changes = await client.changes
            guard !Task.isCancelled else { return }
            await self?.reload(client)
            for await change in changes {
                await self?.handle(change, from: client)
            }
        }
    }

    private func handle(_ change: Change, from client: EngineClient) async {
        guard client === self.client else { return }
        switch change {
        case .resync:
            await reload(client)
        case let .bridge(network):
            await reloadAccounts(client)
            guard client === self.client else { return }
            for hook in changeHooks { hook(.bridge(network: network)) }
        default:
            for hook in changeHooks { hook(change) }
        }
    }

    private func reload(_ client: EngineClient) async {
        await reloadAccounts(client)
        for hook in hooks {
            await hook(client)
        }
    }

    /// Opens a search result: a chat as the inbox does, or a chat at a message. For a message, `pendingMessage`
    /// is set first, then `selectedRoomID`, so the conversation opening the chat finds it (or, when the chat is
    /// already open, sees it arrive and moves to it in place).
    public func open(_ target: SearchTarget) {
        switch target {
        case let .chat(roomID):
            selectedRoomID = roomID
        case let .message(roomID, eventID):
            pendingSerial += 1
            pendingMessage = PendingMessage(roomID: roomID, eventID: eventID, serial: pendingSerial)
            selectedRoomID = roomID
        }
    }

    /// Reads the accounts again from the engine that is up (after a sign-in completes, say).
    public func refreshAccounts() async {
        guard let client else { return }
        await reloadAccounts(client)
    }

    private func reloadAccounts(_ client: EngineClient) async {
        guard let result: AccountsResult = try? await client.call("accounts.list", Empty()),
              client === self.client else { return }
        accounts = result.accounts
        accountsReadAt = clock()
    }
}
