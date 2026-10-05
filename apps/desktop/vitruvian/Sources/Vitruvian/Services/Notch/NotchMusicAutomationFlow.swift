// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

/// Playback control through Apple Events for a player whose own commands do
/// not reach it: what the player offers and allows, the consent request, and
/// one validated action at a time. `NotchMusicService` owns it and passes the
/// playback and its command pipe; tests pass doubles for those and the
/// system.
@MainActor
package final class NotchMusicAutomationFlow {
    /// What the flow reads from the music service and asks of it.
    @MainActor
    package struct Host {
        package var playback: () -> NotchPlayback?
        /// Changes whenever the playback source does.
        package var generation: () -> UUID
        package var commandPending: () -> Bool
        package var setCommandPending: (Bool) -> Void
        package var setCommandFailed: (Bool) -> Void
        /// Asks the adapter to confirm the recording an action was chosen for.
        package var validate: (_ action: UUID, _ context: NotchPlaybackContext) -> Bool
        /// Announces a change to what the flow publishes, before it lands.
        package var willChange: () -> Void

        package init(playback: @escaping () -> NotchPlayback?, generation: @escaping () -> UUID,
                     commandPending: @escaping () -> Bool, setCommandPending: @escaping (Bool) -> Void,
                     setCommandFailed: @escaping (Bool) -> Void,
                     validate: @escaping (UUID, NotchPlaybackContext) -> Bool,
                     willChange: @escaping () -> Void) {
            self.playback = playback
            self.generation = generation
            self.commandPending = commandPending
            self.setCommandPending = setCommandPending
            self.setCommandFailed = setCommandFailed
            self.validate = validate
            self.willChange = willChange
        }
    }

    /// The system and the queues the flow runs on.
    package struct Environment: Sendable {
        package var system: NotchMusicAutomation.System
        /// The music service's own serial queue, which inspects and sends.
        package var worker: @Sendable (@escaping @Sendable () -> Void) -> Void
        /// Where the consent prompt waits for the person.
        package var interactive: @Sendable (@escaping @Sendable () -> Void) -> Void
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        /// Runs `work` on the main queue after `delay` unless it is cancelled first.
        package var after: @Sendable (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void

        package init(system: NotchMusicAutomation.System,
                     worker: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     interactive: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     after: @escaping @Sendable (TimeInterval, DispatchWorkItem) -> Void) {
            self.system = system
            self.worker = worker
            self.interactive = interactive
            self.main = main
            self.after = after
        }

        /// The system's, working on `queue`.
        package static func live(queue: DispatchQueue) -> Environment {
            Environment(system: .live,
                        worker: { work in queue.async { work() } },
                        interactive: { work in DispatchQueue.global(qos: .userInitiated).async { work() } },
                        main: { work in DispatchQueue.main.async { work() } },
                        after: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) })
        }
    }

    private struct Action {
        let id = UUID()
        let command: NotchPlaybackCommand
        let playback: NotchPlayback
        let availability: NotchMusicAutomation.Availability
    }

    private let host: Host
    private let environment: Environment
    /// What the player offers and allows; the last answer stays on screen
    /// while the same player is checked again.
    package private(set) var availability: NotchMusicAutomation.Availability?
    package private(set) var requesting = false
    package private(set) var target: NotchMusicAutomation.Target?
    private var discovery = DispatchWorkItem {}
    private var cancellation = DispatchWorkItem {}
    private var consentCancellation = DispatchWorkItem {}
    private var timeout: DispatchWorkItem?
    private var action: Action?
    private var awaitingValidation = false

    package init(host: Host, environment: Environment) {
        self.host = host
        self.environment = environment
    }

    /// The action waiting for validation or delivery, if any.
    package var actionID: UUID? { action?.id }

    private func publish(_ change: () -> Void) {
        host.willChange()
        change()
    }

    package var canSeek: Bool {
        guard let playback = host.playback(), playback.hasPosition, playback.duration > 0 else { return false }
        return playback.canSendCommandsDirectly ? playback.canSeek
            : availability?.access == .granted && availability?.capabilities.position != nil
    }

    package func canPerform(_ command: NotchPlaybackCommand) -> Bool {
        guard let playback = host.playback(), playback.commandContext != nil, !host.commandPending() else { return false }
        if case .seek = command { return canSeek }
        if playback.canSendCommandsDirectly { return !lacksTrackSkipping(command) }
        guard let available = availability, available.access == .granted else { return false }
        if command == .toggle { return available.capabilities.canToggle }
        return available.capabilities.event(for: command, isPlaying: playback.isPlaying) != nil
    }

    /// The player itself says it cannot skip this way, so the button is hidden.
    package func lacksTrackSkipping(_ command: NotchPlaybackCommand) -> Bool {
        guard let playback = host.playback(), playback.canSendCommandsDirectly else { return false }
        switch command {
        case .next: return playback.canSkipNext == false
        case .previous: return playback.canSkipPrevious == false
        default: return false
        }
    }

    package func refresh() {
        target = nil
        update(for: host.playback())
    }

    package func update(for playback: NotchPlayback?) {
        if let action, action.playback.commandContext != playback?.commandContext { cancelAction() }
        guard let playback, !playback.canSendCommandsDirectly, let target = environment.system.target(playback) else {
            reset()
            return
        }
        guard target != self.target else { return }
        consentCancellation.cancel()
        discovery.cancel()
        // The queues only read its flag, which is thread-safe.
        nonisolated(unsafe) let cancellation = DispatchWorkItem {}
        discovery = cancellation
        self.target = target
        // Every page that shows the controls asks for a fresh look at the
        // same player. Its last answer stays on screen until the new one
        // lands, instead of the fallback row flashing on each open; sending
        // checks access again anyway. Another player starts from nothing.
        if availability?.target != target { publish { availability = nil } }
        let requested = host.generation()
        let system = environment.system
        let main = environment.main
        environment.worker { [weak self] in
            guard !cancellation.isCancelled else { return }
            let available = system.inspect(target)
            main {
                guard let self, self.host.generation() == requested, self.target == target,
                      !cancellation.isCancelled else { return }
                self.publish { self.availability = available }
            }
        }
    }

    /// Forgets the player, as when the reader disconnects or the playback
    /// can take commands directly.
    package func reset() {
        discovery.cancel()
        consentCancellation.cancel()
        target = nil
        if availability != nil { publish { availability = nil } }
        cancelAction()
    }

    /// Consent never queues the old gesture. The next press supplies a fresh
    /// recording context, which is re-read again before any Apple Event is sent.
    package func requestAccess() {
        guard !requesting, let available = availability,
              available.access == .consent, environment.system.isCurrent(available.target) else { return }
        publish { requesting = true }
        let requested = host.generation()
        let context = host.playback()?.commandContext
        // The queues only read its flag, which is thread-safe.
        nonisolated(unsafe) let cancellation = DispatchWorkItem {}
        consentCancellation = cancellation
        let system = environment.system
        let main = environment.main
        environment.interactive { [weak self] in
            if !cancellation.isCancelled, system.isCurrent(available.target) {
                _ = system.consent(available.target.bundleIdentifier)
            }
            main {
                guard let self else { return }
                self.publish { self.requesting = false }
                guard !cancellation.isCancelled, self.host.generation() == requested,
                      self.host.playback()?.commandContext == context,
                      self.target == available.target else { return }
                self.refresh()
            }
        }
    }

    package func begin(_ command: NotchPlaybackCommand, playback: NotchPlayback) -> Bool {
        guard canPerform(command), let context = playback.commandContext,
              let available = availability, environment.system.isCurrent(available.target) else { return false }
        let action = Action(command: command, playback: playback, availability: available)
        self.action = action
        awaitingValidation = true
        cancellation = DispatchWorkItem {}
        host.setCommandPending(true)
        host.setCommandFailed(false)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.action?.id == action.id else { return }
            self.cancelAction()
            self.host.setCommandFailed(true)
        }
        self.timeout = timeout
        environment.after(3, timeout)
        guard host.validate(action.id, context) else {
            cancelAction(); host.setCommandFailed(true); return false
        }
        return true
    }

    package func receiveValidation(_ reply: [String: Any]) {
        guard awaitingValidation, let action,
              reply["validationRequest"] as? String == action.id.uuidString else { return }
        awaitingValidation = false
        guard reply["validationOK"] as? Bool == true, host.playback()?.commandContext == action.playback.commandContext else {
            cancelAction(); host.setCommandFailed(true); return
        }
        timeout?.cancel(); timeout = nil
        // The worker only reads its flag, which is thread-safe.
        nonisolated(unsafe) let cancellation = cancellation
        let system = environment.system
        let validatedAt = system.uptime()
        let main = environment.main
        environment.worker { [weak self] in
            let succeeded = NotchMusicAutomation.send(action.command, playback: action.playback,
                availability: action.availability, cancellation: cancellation, validatedAt: validatedAt,
                system: system)
            main {
                guard let self, !cancellation.isCancelled, self.action?.id == action.id else { return }
                self.cancelAction()
                self.host.setCommandFailed(!succeeded)
                if !succeeded { self.refresh() }
            }
        }
    }

    package func cancelAction() {
        cancellation.cancel()
        timeout?.cancel(); timeout = nil
        action = nil
        awaitingValidation = false
        host.setCommandPending(false)
    }
}
