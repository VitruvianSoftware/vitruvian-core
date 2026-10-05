// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Only the permission system, scheduling and final Apple Event delivery are
/// doubles. The production command/validation/cancellation bodies are generated.
/// The automation flow over a system of doubles and queues the test runs by
/// hand: no Apple Event reaches a player and no consent prompt opens.
enum NotchMusicAutomationFlowContract {
    /// Work waiting for its queue. Only the test's own thread touches it.
    nonisolated final class Jobs: @unchecked Sendable {
        var jobs: [() -> Void] = []
        func add(_ job: @escaping () -> Void) { jobs.append(job) }
    }

    /// The player, its permission and what was delivered, as the flow's
    /// system reports them. Read from the queues the test drains itself.
    nonisolated final class Player: @unchecked Sendable {
        var alive = true
        var permission = NotchMusicAutomation.Access.granted
        var capabilities: NotchMusicAutomationCapabilities?
        var inspections = 0
        var prompts: [String] = []
        /// The address of each event delivered.
        var deliveries: [Data] = []
        let worker = Jobs()
        let interactive = Jobs()
        let main = Jobs()

        static let bundleURL = URL(fileURLWithPath: "/Applications/Player.app")

        var system: NotchMusicAutomation.System {
            NotchMusicAutomation.System(
                target: { playback in
                    playback.track.appPID.map {
                        NotchMusicAutomation.Target(pid: $0, bundleIdentifier: "local.test.player",
                                                    bundleURL: Player.bundleURL, launched: nil)
                    }
                },
                isCurrent: { [unowned self] _ in self.alive },
                inspect: { [unowned self] target in
                    self.inspections += 1
                    return self.capabilities.map {
                        NotchMusicAutomation.Availability(target: target, capabilities: $0, access: self.permission)
                    }
                },
                access: { [unowned self] _ in self.alive ? self.permission : .unavailable },
                consent: { [unowned self] in
                    self.prompts.append($0)
                    return true
                },
                deliver: { [unowned self] event in
                    self.deliveries.append(event.attributeDescriptor(forKeyword: keyAddressAttr)?.data ?? Data())
                    return NSAppleEventDescriptor.record()
                },
                uptime: { 100 })
        }
    }

    /// The music service's side of the flow.
    final class Service {
        let player = Player()
        var playback: NotchPlayback?
        var generation = UUID()
        var commandPending = false
        var commandFailed = false
        var validationRequests: [UUID] = []
        var timeouts: [DispatchWorkItem] = []
        lazy var flow: NotchMusicAutomationFlow = NotchMusicAutomationFlow(
            host: .init(playback: { [unowned self] in self.playback },
                        generation: { [unowned self] in self.generation },
                        commandPending: { [unowned self] in self.commandPending },
                        setCommandPending: { [unowned self] in self.commandPending = $0 },
                        setCommandFailed: { [unowned self] in self.commandFailed = $0 },
                        validate: { [unowned self] id, _ in
                            self.validationRequests.append(id)
                            return true
                        },
                        willChange: {}),
            environment: .init(system: player.system,
                               worker: { [player] in player.worker.add($0) },
                               interactive: { [player] in player.interactive.add($0) },
                               main: { [player] work in player.main.add { MainActor.assumeIsolated { work() } } },
                               after: { [unowned self] _, work in
                                   MainActor.assumeIsolated { self.timeouts.append(work) }
                               }))

        /// Runs every queue until nothing is left, as the system would.
        func drain() {
            while let jobs = [player.worker, player.interactive, player.main].first(where: { !$0.jobs.isEmpty }) {
                jobs.jobs.removeFirst()()
            }
        }

        /// The player answers with `capabilities` and `access` on a fresh check.
        func land(_ capabilities: NotchMusicAutomationCapabilities, _ access: NotchMusicAutomation.Access) {
            player.capabilities = capabilities
            player.permission = access
            flow.refresh()
            drain()
        }
    }
}

enum NotchMusicAutomationTests {
    private static let dictionary = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
    <dictionary><suite name="Playback" code="TEST">
      <command name="playpause" code="ABCDtogl"/>
      <command name="next track" code="EFGHnext"/>
      <command name="previous track" code="IJKLprev"/>
      <class name="application" code="capp"><property name="player position" code="time" type="real"/></class>
    </suite></dictionary>
    """

    private static func playback() -> NotchPlayback {
        let track = RadialNowPlayingSnapshot(title: "Recording", artist: "Artist", album: "Album", artworkData: nil,
                                            appBundleIdentifier: "local.test.player", appPID: 42)
        return NotchPlayback(track: track, isPlaying: true, elapsed: 3, duration: 180, rate: 1, sampledAt: Date(),
                             canSeek: false, itemIdentifier: "one", commandContext: .init(pid: 42, revision: UUID()))
    }

    static func run(_ suite: TestSuite) {
        parsing(suite)
        descriptors(suite)
        lifecycle(suite)
        refresh(suite)
    }

    private static func parsing(_ suite: TestSuite) {
        func parse(_ source: String) -> NotchMusicAutomationCapabilities? { .parse(Data(source.utf8)) }
        let result = parse(dictionary)
        suite.expect(result?.commands["playpause"] == .init(eventClass: 0x41424344, eventID: 0x746F676C),
               "event codes come from the installed dictionary instead of a product-specific table")
        suite.expect(result?.canToggle == true && result?.position?.code == 0x74696D65,
               "declared playback controls and a writable application position are discoverable")
        let required = dictionary.replacingOccurrences(of: "<command name=\"next track\" code=\"EFGHnext\"/>",
            with: "<command name=\"next track\" code=\"EFGHnext\"><direct-parameter type=\"file\"/></command>")
        suite.expect(parse(required)?.commands["next track"] == nil, "commands requiring an argument cannot receive an incomplete playback action")
        let unrelated = dictionary.replacingOccurrences(of: "name=\"playpause\"", with: "name=\"delete\"")
        suite.expect(parse(unrelated)?.canToggle == false, "unrelated commands never become playback controls")
        for changed in [dictionary.replacingOccurrences(of: "type=\"real\"", with: "type=\"file\""),
                        dictionary.replacingOccurrences(of: "type=\"real\"", with: "type=\"real\" access=\"r\""),
                        dictionary.replacingOccurrences(of: "class name=\"application\"", with: "class name=\"track\"")] {
            suite.expect(parse(changed)?.position == nil, "only a numeric writable property of the application can seek")
        }
        let duplicate = dictionary.replacingOccurrences(of: "</suite>", with: "<command name=\"playpause\" code=\"abcdabcd\"/></suite>")
        suite.expect(parse(duplicate)?.commands["playpause"] == nil, "ambiguous command names fail closed")
        let playPause = dictionary.replacingOccurrences(of: "<command name=\"playpause\" code=\"ABCDtogl\"/>",
            with: "<command name=\"play\" code=\"abcdplay\"><direct-parameter optional=\"yes\"/></command><command name=\"pause\" code=\"abcdpaus\"/>")
        suite.expect(parse(playPause)?.canToggle == true
               && parse(playPause)?.event(for: .toggle, isPlaying: true)?.eventID == 0x70617573,
               "optional play arguments are omitted and a playing snapshot chooses its declared pause operation")
        suite.expect(parse(playPause)?.playCommand?.eventID == 0x706C6179
               && result?.playCommand?.eventID == 0x746F676C
               && parse(unrelated)?.playCommand == nil,
               "starting playback prefers the declared play command and falls back to the toggle alone")
        suite.expect(MusicLaunchSupport.playbackNeverArrived(-600)
               && MusicLaunchSupport.playbackNeverArrived(-609)
               && !MusicLaunchSupport.playbackNeverArrived(-1712)
               && !MusicLaunchSupport.playbackNeverArrived(-1743)
               && !MusicLaunchSupport.playbackNeverArrived(0),
               "a play command is asked again only when the player was not listening yet")
        let entity = "<!DOCTYPE dictionary [<!ENTITY payload 'private'>]><dictionary>&payload;</dictionary>"
        suite.expect(parse(entity) == nil && parse(String(repeating: "x", count: NotchMusicAutomationCapabilities.maximumBytes + 1)) == nil,
               "entity expansion and oversized dictionaries are rejected without external reads")
        suite.expect(parse("<dictionary><suite><command name='playpause' code='bad'/></suite></dictionary>") == nil,
               "invalid native event identifiers never reach the sender")
    }

    private static func descriptors(_ suite: TestSuite) {
        let capabilities = NotchMusicAutomationCapabilities.parse(Data(dictionary.utf8))!
        let pid = ProcessInfo.processInfo.processIdentifier
        let value = playback()
        let event = NotchMusicAutomation.event(.seek(72.5), playback: value, capabilities: capabilities, pid: pid)
        suite.expect(event?.eventClass == kAECoreSuite && event?.eventID == kAESetData,
               "seeking uses the native property setter rather than evaluated script text")
        suite.expect(event?.paramDescriptor(forKeyword: keyDirectObject)?.descriptorType == typeObjectSpecifier
               && event?.paramDescriptor(forKeyword: keyAEData)?.doubleValue == 72.5,
               "the declared property and numeric position are encoded as descriptors")
        let address = NSAppleEventDescriptor(processIdentifier: pid)
        suite.expect(event?.attributeDescriptor(forKeyword: keyAddressAttr)?.data == address.data
               && event?.attributeDescriptor(forKeyword: keyAddressAttr)?.descriptorType == address.descriptorType,
               "the Apple Event is addressed to the requested process, independently of global playback")
        let toggle = NotchMusicAutomation.event(.toggle, playback: value, capabilities: capabilities, pid: pid)
        suite.expect(toggle?.eventClass == 0x41424344 && toggle?.eventID == 0x746F676C,
               "the transport encodes the dictionary's actual command identifiers")
        suite.expect(NotchMusicAutomation.event(.seek(.nan), playback: value, capabilities: capabilities, pid: pid) == nil
               && NotchMusicAutomation.event(.queueStop, playback: value, capabilities: capabilities, pid: pid) == nil,
               "non-finite positions and queue operations cannot become unrelated Apple Events")
    }

    private static func lifecycle(_ suite: TestSuite) {
        let capabilities = NotchMusicAutomationCapabilities.parse(Data(dictionary.utf8))!
        let service = NotchMusicAutomationFlowContract.Service()
        let flow = service.flow
        let player = service.player
        let current = playback()
        let native = NotchPlayback(track: current.track, isPlaying: true, elapsed: 3, duration: 180, rate: 1,
            sampledAt: Date(), canSeek: true, commandContext: current.commandContext, canSendCommandsDirectly: true)
        service.playback = native
        suite.expect(flow.canSeek && flow.canPerform(.seek(20)), "direct native playback keeps its existing seeking capability")
        suite.expect(flow.canPerform(.next) && !flow.lacksTrackSkipping(.next),
               "a player whose commands are unknown keeps its skip buttons")
        var video = native; video.canSkipNext = false; video.canSkipPrevious = false
        service.playback = video
        suite.expect(flow.lacksTrackSkipping(.next) && flow.lacksTrackSkipping(.previous)
               && !flow.canPerform(.next) && flow.canPerform(.toggle),
               "a player without next or previous commands keeps only play and pause")
        service.playback = current
        service.land(capabilities, .granted)
        suite.expect(flow.canSeek && current.seekPosition(20, allowed: flow.canSeek) == 20,
               "authorized scripting position enables effective seek without a native seeking capability")
        var readonly = capabilities; readonly.position = nil
        service.land(readonly, .granted)
        suite.expect(!flow.canSeek, "authorization cannot make an undeclared or read-only position writable")
        service.land(capabilities, .granted)
        var noPosition = current; noPosition.hasPosition = false; service.playback = noPosition
        suite.expect(!flow.canSeek, "a missing observed position never exposes an editable timeline")
        service.playback = current
        service.land(capabilities, .consent)
        suite.expect(!flow.canSeek && !flow.begin(.next, playback: current) && player.prompts.isEmpty,
               "an ordinary gesture cannot request permission or send before authorization")
        let inspections = player.inspections
        flow.requestAccess()
        suite.expect(flow.requesting, "a consent request is pending until the person answers")
        service.drain()
        suite.expect(player.prompts == ["local.test.player"] && player.deliveries.isEmpty
               && player.inspections == inspections + 1 && !flow.requesting,
               "consent refreshes capabilities but never replays the gesture that preceded it")
        service.land(capabilities, .granted)
        suite.expect(flow.begin(.seek(20), playback: current) && !flow.begin(.next, playback: current),
               "only one fallback action waits for validation or execution")
        let id = flow.actionID!
        suite.expect(service.validationRequests == [id] && player.deliveries.isEmpty && service.commandPending,
               "the first operation only asks the adapter to validate the selected recording")
        flow.receiveValidation(["validationRequest": id.uuidString, "validationOK": true])
        flow.receiveValidation(["validationRequest": id.uuidString, "validationOK": true])
        service.drain()
        suite.expect(player.deliveries == [NSAppleEventDescriptor(processIdentifier: 42).data] && !service.commandPending
               && !service.commandFailed && service.timeouts.first?.isCancelled == true,
               "a fresh validation permits exactly one event to the captured process")

        for interruption in 0..<4 {
            player.deliveries = []
            player.alive = true; player.permission = .granted
            service.playback = current
            _ = flow.begin(.next, playback: current)
            let action = flow.actionID!
            if interruption == 0 { service.playback?.commandContext = .init(pid: 42, revision: UUID()) }
            flow.receiveValidation(["validationRequest": action.uuidString, "validationOK": interruption != 1])
            if interruption == 2 { flow.cancelAction() }
            if interruption == 3 { player.permission = .denied }
            service.drain()
            suite.expect(player.deliveries.isEmpty && !service.commandPending,
                         "track replacement, failed validation, cancellation and revoked consent block event delivery")
        }
        service.playback = current
        service.land(capabilities, .granted)
        _ = flow.begin(.toggle, playback: current)
        service.timeouts.last?.perform()
        suite.expect(flow.actionID == nil && service.commandFailed && !service.commandPending,
                     "a validation that never answers gives up after its deadline")
        service.land(capabilities, .consent)
        player.prompts = []
        flow.requestAccess()
        flow.reset()
        service.drain()
        suite.expect(player.prompts.isEmpty && !flow.requesting,
               "stopping before a queued consent request suppresses the prompt and releases pending state")
    }

    /// Each page that shows the controls checks the player again when it
    /// appears. Until that check lands, the controls keep the player's last
    /// answer instead of flashing the fallback row on every open.
    private static func refresh(_ suite: TestSuite) {
        let service = NotchMusicAutomationFlowContract.Service()
        let flow = service.flow
        let player = service.player
        player.capabilities = NotchMusicAutomationCapabilities.parse(Data(dictionary.utf8))
        service.playback = playback()
        flow.refresh()
        suite.expect(flow.availability == nil,
               "a player seen for the first time shows no access until its check lands")
        service.drain()
        suite.expect(flow.availability?.access == .granted && player.inspections == 1,
               "the first check fills in the player's access")
        player.permission = .denied
        flow.refresh()
        suite.expect(flow.availability?.access == .granted,
               "opening the page again keeps the last answer on screen while the player is checked again")
        service.drain()
        suite.expect(flow.availability?.access == .denied && player.inspections == 2,
               "the fresh check still replaces the kept answer, so a revoked permission shows")
        let track = RadialNowPlayingSnapshot(title: "Other", artist: "Artist", album: "Album", artworkData: nil,
                                            appBundleIdentifier: "local.test.player", appPID: 43)
        let other = NotchPlayback(track: track, isPlaying: true, elapsed: 3, duration: 180, rate: 1, sampledAt: Date(),
                                  canSeek: false, itemIdentifier: "two", commandContext: .init(pid: 43, revision: UUID()))
        service.playback = other
        flow.update(for: other)
        suite.expect(flow.availability == nil && flow.target?.pid == 43,
               "another player never shows the previous player's access")
        service.drain()
        suite.expect(flow.availability?.target.pid == 43, "the new player gets its own answer")
        player.permission = .granted
        flow.refresh()
        service.generation = UUID()
        service.drain()
        suite.expect(flow.availability?.access == .denied,
                     "a check that lands after the playback source changed is dropped")
    }

}
