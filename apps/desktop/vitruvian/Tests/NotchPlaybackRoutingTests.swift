// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ObjectiveC
import VitruvianNowPlaying

/// The production adapter's reads, sends and source discovery, through the
/// real selection over a recording MediaRemote. These tests never send
/// commands to a real player.
///
/// Only this file sees the adapter's module. Its playback types are the app's
/// own sources compiled a second time, so a suite on the app's side reaches
/// the adapter the way the app does: through reply and request lines.
enum NotchPlaybackRoutingContract {
    typealias Playback = NotchNativePlayback
    typealias Target = NotchNativePlayback.Target

    static let callbacks = DispatchQueue(label: "notch-routing-test")
    static var available = true
    static var destination: AnyObject?
    static var command: Int32?
    static var options: CFDictionary?
    static var requestedArtwork = false
    static var sendError: UInt32 = 0
    static var sendResponses: [NSNumber]? = [0]
    static var metadata: [ObjectIdentifier: [String: Any]] = [:]
    static var beforeRead: (() -> Void)?
    static var reply: [String: Any] = [:]
    /// Stands in for the system uptime the selection reads.
    static var uptime: TimeInterval = 0
    static var refreshes = 0
    static var discovering = false
    static var applications: [NowPlayingApplication] = []
    static var registeredPIDs: [Int32] = []
    static var systemPID: Int32 = 10
    static var sourceMetadata: [Int32: [String: Any]] = [:]
    static var silentPIDs: Set<Int32> = []
    static var lateReads: [() -> Void] = []
    static var queueRequest: UUID?
    static var queueSelection: NotchQueueSelection?
    static var artwork: NSData?
    /// MediaRemote string constants this system lacks.
    static var missingConstants: Set<String> = []
    // What the registered clients call themselves, and the app that owns them.
    static var clientNames: [Int32: NSString] = [:]
    static var parents: [Int32: NSString] = [:]
    private static var saved: NotchNativePlayback.Platform?

    static func application(_ pid: Int32, _ bundleIdentifier: String, music: Bool = false,
                            terminated: Bool = false) -> NowPlayingApplication {
        NowPlayingApplication(pid: pid, bundleIdentifier: bundleIdentifier, localizedName: bundleIdentifier,
                              isTerminated: terminated, category: music ? "public.app-category.music" : nil)
    }

    /// A player path that takes native commands for its recording.
    static func target(pid: Int32 = 10, bundleIdentifier: String = "test.player", path: NSObject) -> Target {
        Target(pid: pid, bundleIdentifier: bundleIdentifier, path: path, itemIdentifier: "fixture",
               allowsDirectCommands: true)
    }

    /// Swaps the recording MediaRemote in, with "test.player" running at
    /// `runningPIDs` and already terminated at 11; `restore` puts the
    /// system's back.
    static func install(runningPIDs: [Int32] = [10, 20]) {
        applications = runningPIDs.map { application($0, "test.player") }
            + [application(11, "test.player", terminated: true)]
        if saved == nil { saved = NotchNativePlayback.platform }
        NotchNativePlayback.platform = NotchNativePlayback.Platform(
            symbol: { available ? symbol($0) : nil },
            constant: { missingConstants.contains($0) ? nil : $0 },
            application: { pid in applications.first { $0.pid == pid } },
            runningApplications: { applications },
            uptime: { uptime },
            emit: { reply = $0 },
            refresh: { refreshes += 1 },
            configureQueue: { queueRequest = $0 },
            playQueue: { queueSelection = $0 })
    }

    static func restore() {
        reset()
        metadata = [:]
        artwork = nil
        missingConstants = []
        clientNames = [:]
        parents = [:]
        if let saved { NotchNativePlayback.platform = saved }
        saved = nil
    }

    /// Nothing published, chosen or discovered.
    static func reset() {
        Playback.publish(nil)
        Playback.choose(nil)
        let wasAvailable = available
        available = false
        // A failed scan clears the discovered rows.
        _ = Playback.select()
        available = wasAvailable
    }

    /// Publishes a recording, and answers with what the app reads of it.
    static func publish(pid: Int32, path: NSObject, info: [String: Any]) -> [String: Any] {
        guard let context = Playback.publish(target(pid: pid, path: path), info: info) else { return [:] }
        return ["pid": context.pid, "playbackRevision": context.revision.uuidString]
    }

    /// Hands the adapter one line the way its pipe does.
    static func deliver(_ line: String?) {
        var framer = NotchPlaybackCommandFramer()
        for request in framer.append(Data(((line ?? "") + "\n").utf8)) {
            if let request { Playback.perform(request) } else { reply = ["sent": false] }
        }
    }

    // The chooser, as the app reads it.
    static var chosenPID: Int32? { Playback.sourceReply["selectedPID"] as? Int32 }
    static var isAutomatic: Bool { Playback.sourceReply["sourceIsAutomatic"] as? Bool == true }
    static var sources: [NotchPlaybackSource] {
        NotchPlaybackSource.decode(Playback.sourceReply["sources"], selectedPID: chosenPID)
    }

    /// The process a player path was made for.
    static func clientPID(_ path: AnyObject) -> Int32 {
        let client = path.perform(NSSelectorFromString("client"))?.takeUnretainedValue() as? NSObject
        return (client?.value(forKey: "processIdentifier") as? NSNumber)?.int32Value ?? 0
    }

    typealias Read = @convention(c) (AnyObject, Bool, DispatchQueue,
        @escaping @convention(block) (NSDictionary?, UnsafeRawPointer?) -> Void) -> Void
    typealias Send = @convention(c) (Int32, CFDictionary?, AnyObject, UInt32, DispatchQueue,
        @escaping @convention(block) (UInt32, NSArray?) -> Void) -> Bool
    typealias Commands = @convention(c) (AnyObject, DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
    typealias Client = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
    typealias Clients = @convention(c) (DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
    typealias PID = @convention(c) (AnyObject) -> Int32
    typealias ClientString = @convention(c) (AnyObject) -> Unmanaged<CFString>?
    typealias CopyArtwork = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFData>?

    static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        switch name {
        case "MRMediaRemoteGetNowPlayingClient":
            let read: Client = { _, completion in
                completion(NSNumber(value: NotchPlaybackRoutingContract.systemPID))
            }
            return unsafeBitCast(read, to: UnsafeMutableRawPointer.self)
        case "MRMediaRemoteGetNowPlayingClients":
            let read: Clients = { _, completion in
                completion(NotchPlaybackRoutingContract.registeredPIDs.map { NSNumber(value: $0) } as NSArray)
            }
            return unsafeBitCast(read, to: UnsafeMutableRawPointer.self)
        case "MRNowPlayingClientGetProcessIdentifier":
            let pid: PID = { ($0 as! NSNumber).int32Value }
            return unsafeBitCast(pid, to: UnsafeMutableRawPointer.self)
        case "MRNowPlayingClientGetDisplayName":
            let name: ClientString = { client in
                NotchPlaybackRoutingContract.clientNames[(client as! NSNumber).int32Value].map { Unmanaged.passUnretained($0 as CFString) }
            }
            return unsafeBitCast(name, to: UnsafeMutableRawPointer.self)
        case "MRNowPlayingClientGetParentAppBundleIdentifier":
            let parent: ClientString = { client in
                NotchPlaybackRoutingContract.parents[(client as! NSNumber).int32Value].map { Unmanaged.passUnretained($0 as CFString) }
            }
            return unsafeBitCast(parent, to: UnsafeMutableRawPointer.self)
        case "MRNowPlayingArtworkCopyImageData":
            let copy: CopyArtwork = { _ in
                NotchPlaybackRoutingContract.artwork.map { Unmanaged.passRetained($0 as CFData) }
            }
            return unsafeBitCast(copy, to: UnsafeMutableRawPointer.self)
        case "MRMediaRemoteGetNowPlayingInfoForPlayer":
            let read: Read = { path, artwork, _, completion in
                if NotchPlaybackRoutingContract.discovering {
                    let pid = NotchPlaybackRoutingContract.clientPID(path)
                    let info = (NotchPlaybackRoutingContract.sourceMetadata[pid] ?? [:]) as NSDictionary
                    if NotchPlaybackRoutingContract.silentPIDs.contains(pid) {
                        NotchPlaybackRoutingContract.lateReads.append { completion(info, nil) }
                    } else { completion(info, nil) }
                    return
                }
                NotchPlaybackRoutingContract.destination = path
                NotchPlaybackRoutingContract.requestedArtwork = artwork
                NotchPlaybackRoutingContract.beforeRead?()
                // The cover arrives as an opaque handle the artwork call copies.
                let cover = artwork && NotchPlaybackRoutingContract.artwork != nil ? UnsafeRawPointer(bitPattern: 1) : nil
                completion((NotchPlaybackRoutingContract.metadata[ObjectIdentifier(path)]
                            ?? ["kMRMediaRemoteNowPlayingInfoTitle": "Selected track"]) as NSDictionary, cover)
            }
            return unsafeBitCast(read, to: UnsafeMutableRawPointer.self)
        case "MRMediaRemoteSendCommandToPlayer":
            let send: Send = { value, settings, path, _, _, completion in
                NotchPlaybackRoutingContract.destination = path
                NotchPlaybackRoutingContract.command = value
                NotchPlaybackRoutingContract.options = settings
                completion(NotchPlaybackRoutingContract.sendError, NotchPlaybackRoutingContract.sendResponses as NSArray?)
                return true
            }
            return unsafeBitCast(send, to: UnsafeMutableRawPointer.self)
        case "MRMediaRemoteGetSupportedCommandsForPlayer":
            let commands: Commands = { path, _, completion in
                NotchPlaybackRoutingContract.destination = path
                completion([])
            }
            return unsafeBitCast(commands, to: UnsafeMutableRawPointer.self)
        default: return nil
        }
    }
}

enum NotchPlaybackRoutingTests {
    private typealias Adapter = NotchPlaybackRoutingContract
    private typealias Playback = NotchNativePlayback

    static func run(_ suite: TestSuite) {
        Adapter.install()
        defer { Adapter.restore() }
        let musicPath = NSObject()
        let otherPath = NSObject()
        let music = Adapter.target(path: musicPath)
        let other = Adapter.target(path: otherPath)
        _ = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        let first = Playback.makeTarget(Adapter.application(101, "test.music"))
        let second = Playback.makeTarget(Adapter.application(202, "test.video"))
        suite.expect(first != nil && second != nil && first?.path !== second?.path,
               "constructing a second destination never mutates the native path of the first player")
        suite.expect(first.map { Adapter.clientPID($0.path) } == 101,
               "the first destination retains its process after another candidate is created")
        suite.expect(Playback.makeTarget(Adapter.application(303, "test.closed", terminated: true)) == nil
                     && Playback.makeTarget(NowPlayingApplication(pid: 304, bundleIdentifier: nil)) == nil,
                     "an application that already quit, or has no bundle identifier, gets no player path")
        var title: String?
        var cover: Data?
        Adapter.artwork = Data([1, 2, 3]) as NSData
        Playback.readInfo(music, artwork: true, queue: Adapter.callbacks) { info in
            title = info?["kMRMediaRemoteNowPlayingInfoTitle"] as? String
            cover = info?["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        }
        Adapter.artwork = nil
        suite.expect(Adapter.destination === musicPath && title == "Selected track" && Adapter.requestedArtwork
                     && cover == Data([1, 2, 3]),
               "metadata and artwork are requested from the selected music path")
        Playback.supportedCommands(music, queue: Adapter.callbacks) { _ in }
        suite.expect(Adapter.destination === musicPath, "seek availability belongs to the selected player")
        for command: Int32 in [2, 4, 5, 24, 131] {
            let options = ["position": 37] as CFDictionary
            suite.expect(Playback.send(command, options: options, to: music), "the selected player accepts the transport request")
            suite.expect(Adapter.destination === musicPath && Adapter.command == command
                   && (Adapter.options as? [String: Any])?["position"] as? Int == 37
                   && (Adapter.options as? [String: Any])?["kMRMediaRemoteOptionNowPlayingContentItemID"] as? String == "fixture",
                   "playback, seeking and queue commands retain their selected destination and options")
        }
        _ = Playback.send(2, to: other)
        suite.expect(Adapter.destination === otherPath, "an explicit new selection changes the command destination")
        // Another app at the same process, one that quit, and none at all.
        for gone in [Adapter.target(bundleIdentifier: "test.replaced", path: musicPath),
                     Adapter.target(pid: 11, path: musicPath), Adapter.target(pid: 12, path: musicPath)] {
            Adapter.destination = nil
            suite.expect(!Playback.send(2, to: gone) && Adapter.destination == nil,
                   "a closed or replaced process never receives a command or falls back to the system player")
            var unread = false
            Playback.readInfo(gone, artwork: false, queue: Adapter.callbacks) { unread = $0 == nil }
            suite.expect(unread && Adapter.destination == nil, "a closed or replaced process is never read")
        }
        Adapter.available = false
        suite.expect(!Playback.send(2, to: music) && Adapter.destination == nil,
               "a missing targeted transport never sends a global media command")
        var cleared = false
        Playback.readInfo(music, artwork: false, queue: Adapter.callbacks) { cleared = $0 == nil }
        suite.expect(cleared && Adapter.destination == nil, "an unavailable targeted reader clears the result without reading another player")
        var noCommands = false
        Playback.supportedCommands(music, queue: Adapter.callbacks) { noCommands = $0 == nil }
        suite.expect(noCommands && Adapter.destination == nil, "an unavailable command reader answers nothing")
        Adapter.available = true
        Adapter.sendError = 7
        suite.expect(!Playback.send(2, to: music), "a rejected native command is not reported as delivered")
        Adapter.sendError = 0
        Adapter.sendResponses = nil
        suite.expect(!Playback.send(2, to: music), "a native send without a handler result cannot claim delivery")
        Adapter.sendResponses = [1]
        suite.expect(!Playback.send(2, to: music), "a handler that answers with a failure cannot claim delivery")
        Adapter.sendResponses = [0]
        var unavailable = music
        unavailable.allowsDirectCommands = false
        Adapter.command = nil
        suite.expect(!Playback.send(2, to: unavailable) && Adapter.command == nil,
               "an unsupported native target never falls back to the global player's transport")
        var unidentified = music
        unidentified.itemIdentifier = nil
        suite.expect(!Playback.send(2, to: unidentified) && Adapter.command == nil,
               "native commands require the receiver's content identity")
        unidentified.requiresCurrentPlayer = true
        suite.expect(Playback.send(2, to: unidentified) && Adapter.destination === musicPath
                     && Adapter.options == nil,
                     "the current video can receive play/pause without a content identifier")
        Adapter.systemPID = 20
        Adapter.command = nil
        suite.expect(!Playback.send(2, to: unidentified) && Adapter.command == nil,
                     "a video that lost the system session cannot send to the new global player")
        Adapter.systemPID = 10
        replyEncoding(suite)
        radioPlayback(suite)
        recordingContext(suite)
        sourceDiscovery(suite)
    }

    private static func radioPlayback(_ suite: TestSuite) {
        let path = NSObject()
        var radio = Adapter.target(path: path)
        radio.requiresCurrentPlayer = true
        var info: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": "Live radio",
                                   "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1,
                                   "canPlay": true, "canPause": true]
        defer { Adapter.beforeRead = nil; Adapter.metadata[ObjectIdentifier(path)] = nil; Playback.publish(nil) }
        Adapter.metadata[ObjectIdentifier(path)] = info
        let playing = Playback.publish(radio, info: info)!
        Playback.perform(NotchPlaybackRequest(command: .toggle, context: playing))
        suite.expect(Adapter.reply["sent"] as? Bool == true && Adapter.command == 1,
                     "a radio player with separate playback commands receives Pause instead of Toggle")

        info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 0
        Adapter.metadata[ObjectIdentifier(path)] = info
        let paused = Playback.publish(radio, info: info)!
        Playback.perform(NotchPlaybackRequest(command: .toggle, context: paused))
        suite.expect(Adapter.reply["sent"] as? Bool == true && Adapter.command == 0,
                     "the same radio player receives Play when the stream is paused")

        info["canPlay"] = false
        Adapter.metadata[ObjectIdentifier(path)] = info
        let fallback = Playback.publish(radio, info: info)!
        Playback.perform(NotchPlaybackRequest(command: .toggle, context: fallback))
        suite.expect(Adapter.reply["sent"] as? Bool == true && Adapter.command == 2,
                     "players without a separate command retain Toggle")

        Adapter.systemPID = 20
        Adapter.command = nil
        Playback.perform(NotchPlaybackRequest(command: .toggle, context: fallback))
        suite.expect(Adapter.reply["sent"] as? Bool == false && Adapter.command == nil,
                     "a radio player that lost the system session cannot control another player")
        Adapter.systemPID = 10

        var delayed = info
        delayed["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 1
        delayed["canPause"] = nil
        Adapter.metadata[ObjectIdentifier(path)] = delayed
        let delayedContext = Playback.publish(radio, info: delayed)!
        Playback.perform(NotchPlaybackRequest(command: .toggle, context: delayedContext))
        suite.expect(Adapter.reply["sent"] as? Bool == true && Adapter.command == 2,
                     "an unanswered capability query initially keeps Toggle")
        var late = delayed
        late["canPause"] = true
        Playback.updatePlayPauseCommand(for: radio, info: late)
        Playback.perform(NotchPlaybackRequest(command: .toggle, context: delayedContext))
        suite.expect(Adapter.reply["sent"] as? Bool == true && Adapter.command == 1,
                     "a late capability reply updates the same recording without another metadata notification")

        let inFlight = Playback.publish(radio, info: delayed)!
        Adapter.beforeRead = { Playback.updatePlayPauseCommand(for: radio, info: late) }
        Playback.perform(NotchPlaybackRequest(command: .toggle, context: inFlight))
        Adapter.beforeRead = nil
        suite.expect(Adapter.reply["sent"] as? Bool == true && Adapter.command == 1,
                     "a capability arriving during validation is used by the pending command")

        var changed = delayed
        changed["kMRMediaRemoteNowPlayingInfoTitle"] = "Another station"
        Adapter.metadata[ObjectIdentifier(path)] = changed
        let changedContext = Playback.publish(radio, info: changed)!
        Playback.updatePlayPauseCommand(for: radio, info: late)
        Playback.perform(NotchPlaybackRequest(command: .toggle, context: changedContext))
        suite.expect(Adapter.reply["sent"] as? Bool == true && Adapter.command == 2,
                     "an old capability reply cannot change another recording on the same path")

        var replacement = Adapter.target(path: NSObject())
        replacement.requiresCurrentPlayer = true
        Adapter.metadata[ObjectIdentifier(replacement.path)] = delayed
        let replacedContext = Playback.publish(replacement, info: delayed)!
        Playback.updatePlayPauseCommand(for: radio, info: late)
        Playback.perform(NotchPlaybackRequest(command: .toggle, context: replacedContext))
        suite.expect(Adapter.reply["sent"] as? Bool == true && Adapter.command == 2,
                     "an old capability reply cannot change a newly selected path")
        Adapter.metadata[ObjectIdentifier(replacement.path)] = nil
    }

    /// JSONSerialization raises an exception `try?` cannot catch on NaN or
    /// infinity, which would end the adapter mid-reply.
    private static func replyEncoding(_ suite: TestSuite) {
        let reply: [String: Any] = ["kMRMediaRemoteNowPlayingInfoDuration": Double.infinity,
                                    "kMRMediaRemoteNowPlayingInfoElapsedTime": Double.nan,
                                    "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1.0,
                                    "pid": Int32(20)]
        let decoded = (try? JSONSerialization.jsonObject(with: encodedReply(reply))) as? [String: Any]
        suite.expect(decoded?.count == 2 && decoded?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double == 1,
                     "a live stream's non-finite duration or position is left out of an otherwise intact reply")
        let nested: [String: Any] = ["sources": [["pid": -Double.infinity]]]
        let fallback = String(data: encodedReply(nested), encoding: .utf8)
        suite.expect(fallback == "{\"error\":\"json\"}", "any other invalid value reads as an error instead of ending the adapter")
    }

    private static func recordingContext(_ suite: TestSuite) {
        let musicPath = NSObject(), otherPath = NSObject()
        let music = Adapter.target(pid: 10, path: musicPath)
        let other = Adapter.target(pid: 20, path: otherPath)
        func info(_ item: String?, title: String = "Same visible title") -> [String: Any] {
            var value: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": title,
                                       "kMRMediaRemoteNowPlayingInfoDuration": 180]
            value["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] = item
            return value
        }
        func prepare(_ target: Adapter.Target, _ value: [String: Any]) -> NotchPlaybackContext {
            Adapter.metadata[ObjectIdentifier(target.path)] = value
            return Playback.publish(target, info: value)!
        }
        func send(_ command: NotchPlaybackCommand, _ context: NotchPlaybackContext) -> Bool {
            Adapter.command = nil
            Playback.perform(NotchPlaybackRequest(command: command, context: context))
            return Adapter.command != nil
        }
        defer {
            Adapter.beforeRead = nil
            Adapter.metadata = [:]
            Adapter.reset()
        }
        let first = prepare(music, info("A"))
        let validation = UUID()
        Adapter.command = nil
        Playback.perform(NotchPlaybackRequest(command: .validate(validation, first)))
        suite.expect(Adapter.reply["validationRequest"] as? String == validation.uuidString
               && Adapter.reply["validationOK"] as? Bool == true && Adapter.command == nil,
               "automation validation checks context without sending a playback command")
        suite.expect(Playback.publish(music, info: info("A")) == first,
               "ordinary updates of an identified recording keep its control revision stable")
        for (command, identifier) in [(NotchPlaybackCommand.toggle, Int32(2)), (.next, 4), (.previous, 5), (.seek(75), 24)] {
            suite.expect(send(command, first) && Adapter.command == identifier && Adapter.destination === musicPath,
                   "stable commands validate and reach the displayed recording without selecting another source")
        }
        suite.expect((Adapter.options as? [String: Any])?["kMRMediaRemoteOptionPlaybackPosition"] as? Double == 75
                     && (Adapter.options as? [String: Any])?["kMRMediaRemoteOptionNowPlayingContentItemID"] as? String == "A",
                     "a seek carries its position and the recording it was made on")
        Adapter.missingConstants = ["kMRMediaRemoteOptionPlaybackPosition"]
        Adapter.reply = [:]
        suite.expect(!send(.seek(75), first) && Adapter.reply["sent"] as? Bool == false,
                     "a system without a seek position option refuses the seek instead of sending it bare")
        Adapter.missingConstants = []
        let otherContext = prepare(other, info("B"))
        for command in [NotchPlaybackCommand.toggle, .next, .previous, .seek(75)] {
            Adapter.reply = [:]
            Adapter.destination = nil
            suite.expect(!send(command, first) && Adapter.reply["sent"] as? Bool == false && Adapter.destination == nil,
                         "pending controls cannot be redirected after the chosen process changes, nor read the new one")
        }
        suite.expect(send(.toggle, otherContext), "a deliberate new snapshot can control its own process")
        Playback.perform(NotchPlaybackRequest(command: .validate(validation, first)))
        suite.expect(Adapter.reply["validationRequest"] as? String == validation.uuidString
                     && Adapter.reply["validationOK"] as? Bool == false,
                     "automation validation of a superseded recording answers no")
        let current = prepare(music, info("A"))
        let next = prepare(music, info("C"))
        suite.expect(current != next && !send(.seek(90), current),
               "a new item with identical title and process cannot inherit an old scrub")
        let sameRecording = prepare(music, info("A"))
        suite.expect(prepare(Adapter.target(pid: 20, path: musicPath), info("A")) != sameRecording,
                     "the same recording in another process is a new control revision")

        let beforeNativeChange = prepare(music, info("A"))
        Adapter.metadata[ObjectIdentifier(musicPath)] = info("C")
        suite.expect(!send(.seek(90), beforeNativeChange),
               "a player change preceding its notification is detected by fresh metadata before sending")
        Adapter.metadata[ObjectIdentifier(musicPath)] = info("A")
        Adapter.beforeRead = { _ = prepare(other, info("B")) }
        suite.expect(!send(.next, beforeNativeChange), "a selection changed during validation cannot authorize the old action")
        Adapter.beforeRead = { _ = Playback.publish(Adapter.target(path: NSObject()), info: info("A")) }
        suite.expect(!send(.next, prepare(music, info("A"))),
                     "a player path replaced during validation cannot take the gesture, even for the same recording")
        Adapter.beforeRead = { _ = Playback.publish(music, info: info("C")) }
        suite.expect(!send(.next, prepare(music, info("A"))),
                     "a recording that changes during validation cannot take the old gesture")
        Adapter.beforeRead = nil

        let noID = prepare(music, info(nil))
        suite.expect(Playback.validatedTarget(for: noID) != nil && !send(.seek(30), noID),
               "a player without content identifiers can be validated for automation but is not sent an unsafe native command")
        var progress = info(nil)
        progress["kMRMediaRemoteNowPlayingInfoElapsedTime"] = 45
        progress["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 0
        let refreshed = prepare(music, progress)
        suite.expect(noID == refreshed && Playback.validatedTarget(for: noID) != nil,
               "position and play/pause updates without an item ID preserve an ongoing scrub")
        Adapter.metadata[ObjectIdentifier(musicPath)] = info(nil, title: "Changed recording")
        suite.expect(!send(.seek(30), refreshed), "unidentified playback also compares fresh recording metadata")
        let changedNoID = prepare(music, info(nil, title: "Changed recording"))
        suite.expect(changedNoID != refreshed && Playback.validatedTarget(for: refreshed) == nil
               && Playback.validatedTarget(for: changedNoID) != nil,
               "an observable recording change without an item ID advances the revision and rejects an old gesture")
        let stopped = prepare(Adapter.target(pid: 11, path: musicPath), info("A"))
        suite.expect(!send(.toggle, stopped), "terminated players cannot receive a validated action")
        suite.expect(Playback.publish(music, info: ["kMRMediaRemoteNowPlayingInfoTitle": " \n"]) == nil
                     && Playback.target?.path === musicPath,
                     "a player without a title is followed but publishes no controls")
        let invalidID = prepare(music, info(""))
        suite.expect(!send(.seek(30), invalidID), "an empty content identifier does not count as one")
        let adapterKey = prepare(music, ["kMRMediaRemoteNowPlayingInfoTitle": "Keyed", "itemIdentifier": "Z"])
        suite.expect(send(.seek(30), adapterKey)
                     && (Adapter.options as? [String: Any])?["kMRMediaRemoteOptionNowPlayingContentItemID"] as? String == "Z",
                     "the adapter's own item key identifies the recording too")

        let request = UUID()
        let selection = NotchQueueSelection(requestID: request, pid: 10, currentIdentifier: "A", itemIdentifier: "B", offset: 1)
        Playback.perform(NotchPlaybackRequest(command: .queue(request)))
        Playback.perform(NotchPlaybackRequest(command: .queuePlay(selection)))
        suite.expect(Adapter.queueRequest == request && Adapter.queueSelection == selection,
               "queue queries and their immutable selections retain their existing native route")
        Playback.perform(NotchPlaybackRequest(command: .queueStop))
        suite.expect(Adapter.queueRequest == nil, "queue-stop still cancels without requiring a playing track")

        // The chooser's rows come from discovery: a browser playing a video.
        Adapter.discovering = true
        Adapter.applications.append(Adapter.application(202, "test.browser"))
        Adapter.registeredPIDs = [202]
        Adapter.sourceMetadata = [202: ["kMRMediaRemoteNowPlayingInfoTitle": "Video",
                                        "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1]]
        // A web content helper, named and owned by its app.
        Adapter.clientNames[202] = "Video site"
        Adapter.parents[202] = "com.spotify.client"
        defer {
            Adapter.discovering = false
            Adapter.clientNames = [:]
            Adapter.parents = [:]
        }
        _ = Playback.select()
        suite.expect(Adapter.sources.first?.displayName == "Video site" && Adapter.sources.first?.isMusicApp == true,
                     "a helper process is listed under its own name, as the app that owns it")
        Adapter.parents[202] = ""
        _ = Playback.select()
        suite.expect(Adapter.sources.first?.isMusicApp == false, "an empty owner is no owner")
        let browser = NotchPlaybackSource.Selection(pid: 202, bundleIdentifier: "test.browser")
        let refreshesBefore = Adapter.refreshes
        Adapter.queueRequest = UUID()
        Adapter.command = nil
        Playback.perform(NotchPlaybackRequest(command: .source(browser)))
        suite.expect(Adapter.chosenPID == 202 && Adapter.refreshes == refreshesBefore + 1
                     && Adapter.queueRequest == nil && Adapter.command == nil,
                     "choosing a source refreshes metadata and retires its old queue without changing playback")
        Adapter.parents[202] = "com.spotify.client"
        let helper = Playback.select()
        suite.expect(helper?.pid == 202 && helper?.bundleIdentifier == "test.browser"
                     && helper?.applicationBundleIdentifier == "com.spotify.client",
                     "commands route to the helper's own process while the owning app presents it")
        Adapter.parents[202] = ""
        suite.expect(Playback.select()?.applicationBundleIdentifier == nil, "an empty owner presents nothing")
        Playback.choose(.init(pid: 202, bundleIdentifier: "unrelated.app"))
        _ = Playback.select()
        suite.expect(Adapter.chosenPID == 202 && !Adapter.isAutomatic, "a reused PID cannot select an undiscovered application")
        Playback.perform(NotchPlaybackRequest(command: .source(nil)))
        suite.expect(Adapter.isAutomatic && Adapter.chosenPID == nil && Adapter.refreshes == refreshesBefore + 2,
                     "automatic source selection can be restored without sending a transport command")
    }

    private static func sourceDiscovery(_ suite: TestSuite) {
        Adapter.reset()
        Adapter.discovering = true
        Playback.includeOtherPlayers = false
        Adapter.available = true
        Adapter.applications = [Adapter.application(10, "test.player.10", music: true)]
            + [20, 30].map { Adapter.application($0, "test.player.\($0)") }
        Adapter.registeredPIDs = [10, 20, 30]
        Adapter.systemPID = 10
        Adapter.sourceMetadata = Dictionary(uniqueKeysWithValues: [Int32(10), 20, 30].map {
            ($0, ["kMRMediaRemoteNowPlayingInfoTitle": "Track \($0)", "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1] as [String: Any])
        })
        defer {
            Adapter.lateReads.forEach { $0() }
            Adapter.lateReads = []
            Adapter.silentPIDs = []
            Adapter.discovering = false
            Playback.includeOtherPlayers = false
            Adapter.uptime = 0
            Adapter.reset()
        }
        _ = Playback.select()
        let browser = NotchPlaybackSource.Selection(pid: 20, bundleIdentifier: "test.player.20")
        Adapter.sourceMetadata[10]?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 0
        Adapter.systemPID = 20
        suite.expect(Playback.select()?.pid == 10,
                     "automatic playback keeps paused music instead of showing the active video by default")
        suite.expect((Playback.sourceReply["sources"] as? [[String: Any]])?.compactMap { $0["pid"] as? Int32 } == [10, 20, 30],
                     "the chooser's rows arrive in a stable order")
        Playback.includeOtherPlayers = true
        suite.expect(Playback.select()?.requiresCurrentPlayer == true && Playback.select()?.allowsDirectCommands == true,
                     "opted-in video playback exposes native controls without Automation")
        Playback.includeOtherPlayers = false
        Adapter.systemPID = 10
        Playback.choose(browser)
        suite.expect(Playback.select()?.requiresCurrentPlayer == false && Playback.select()?.allowsDirectCommands == false,
                     "a chosen video outside the system session does not expose redirected native controls")
        Adapter.sourceMetadata[10]?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 1
        Playback.publish(Playback.select())
        Adapter.silentPIDs = [30]
        suite.expect(Playback.select()?.pid == 20 && Adapter.chosenPID == 20 && Adapter.sources.count == 2,
                     "an unrelated client timeout preserves the chosen source and other completed reads")
        Adapter.silentPIDs = [20]
        suite.expect(Playback.select() == nil && Adapter.chosenPID == 20 && !Adapter.isAutomatic,
                     "a chosen source timeout exposes no stale controls and keeps the manual choice")
        Playback.publish(nil)
        Adapter.silentPIDs = []
        Adapter.registeredPIDs = [10, 30]
        suite.expect(Playback.select()?.pid == 20,
                     "a manual source is queried again after a timeout even if enumeration omits it")
        Adapter.lateReads.forEach { $0() }
        Adapter.lateReads = []
        suite.expect(Adapter.chosenPID == 20 && Adapter.sources.contains(where: { $0.selection == browser }),
                     "late callbacks cannot replace a completed discovery or its choice")
        Adapter.available = false
        suite.expect(Playback.select() == nil && Adapter.chosenPID == 20 && Adapter.sources.isEmpty,
                     "a failed discovery clears unavailable rows without resetting the manual choice")
        Adapter.available = true
        suite.expect(Playback.select()?.pid == 20, "discovery recovery restores the chosen source")
        // A browser clears its track between videos, or leaves a blank title.
        Adapter.sourceMetadata[20] = ["kMRMediaRemoteNowPlayingInfoTitle": " "]
        suite.expect(Playback.select()?.pid == 10 && Adapter.chosenPID == 20,
                     "a chosen source without a track keeps the choice while the automatic player shows")
        suite.expect(Adapter.sources.contains(where: { $0.pid == 20 && !$0.hasTrack })
                     && Playback.sourceReply["selectedPID"] as? Int32 == 20,
                     "the chooser keeps the chosen row and its mark while it waits for a track")
        Adapter.uptime = 4
        Adapter.sourceMetadata[20] = ["kMRMediaRemoteNowPlayingInfoTitle": "Next video"]
        suite.expect(Playback.select()?.pid == 20 && Adapter.chosenPID == 20,
                     "the chosen source shows again with its next track")
        Adapter.sourceMetadata[20] = [:]
        _ = Playback.select()
        Adapter.uptime = 8
        suite.expect(Playback.select()?.pid == 10 && Adapter.chosenPID == 20,
                     "a track seen again restarts the five-second wait")
        // Choosing the waiting row again is no choice: it has no track.
        Playback.choose(browser)
        Adapter.uptime = 9
        suite.expect(Playback.select()?.pid == 10 && Adapter.isAutomatic
                     && !Adapter.sources.contains(where: { $0.pid == 20 }),
                     "a chosen source still without a track after five seconds releases the choice")
        Adapter.registeredPIDs = [10, 20, 30]
        Adapter.sourceMetadata[20] = ["kMRMediaRemoteNowPlayingInfoTitle": "Browser track"]
        _ = Playback.select()
        Playback.choose(browser)
        Adapter.sourceMetadata[20] = [:]
        suite.expect(Playback.select()?.pid == 10 && Adapter.chosenPID == 20,
                     "choosing a released source again starts a fresh wait")
        Adapter.uptime = 13
        Playback.choose(.init(pid: 30, bundleIdentifier: "test.player.30"))
        Adapter.sourceMetadata[30] = [:]
        Adapter.uptime = 15
        suite.expect(Playback.select()?.pid == 10 && Adapter.chosenPID == 30,
                     "a new choice starts its own wait instead of inheriting the previous one")
        Adapter.sourceMetadata[30] = ["kMRMediaRemoteNowPlayingInfoTitle": "Track 30", "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1]
        Adapter.sourceMetadata[20] = ["kMRMediaRemoteNowPlayingInfoTitle": "Browser track"]
        Adapter.registeredPIDs = [10, 20, 30]
        _ = Playback.select()
        Playback.choose(browser)
        Adapter.applications[1] = Adapter.application(20, "test.reused.pid")
        suite.expect(Playback.select()?.pid == 10 && Adapter.isAutomatic,
                     "a reused process identifier cannot retain another application's manual selection")
        Adapter.applications[1] = Adapter.application(browser.pid, browser.bundleIdentifier)
        _ = Playback.select()
        Playback.choose(browser)
        Adapter.applications[1] = Adapter.application(browser.pid, browser.bundleIdentifier, terminated: true)
        suite.expect(Playback.select()?.pid == 10 && Adapter.isAutomatic,
                     "the selected application quitting restores automatic selection")
        Adapter.applications[1] = Adapter.application(browser.pid, browser.bundleIdentifier)
        _ = Playback.select()
        Playback.choose(browser)
        Adapter.applications.removeAll { $0.pid == 20 }
        suite.expect(Playback.select()?.pid == 10 && Adapter.isAutomatic,
                     "closing the selected application restores automatic selection")
        Adapter.applications.removeAll { $0.pid == 10 }
        Adapter.systemPID = 99
        Adapter.applications.append(Adapter.application(99, "test.private.browser"))
        suite.expect(Playback.select() == nil && Adapter.sources.map(\.pid) == [30],
                     "discovered sources remain available when the global player has no metadata")
        Playback.choose(.init(pid: 30, bundleIdentifier: "test.player.30"))
        suite.expect(Playback.select()?.pid == 30, "an empty automatic result can be recovered by choosing a discovered source")

        // Two music apps playing: the one on screen stays while the other
        // takes the system's session.
        Playback.choose(nil)
        Adapter.applications = [10, 40].map { Adapter.application($0, "test.player.\($0)", music: true) }
        Adapter.registeredPIDs = [10, 40]
        Adapter.sourceMetadata = Dictionary(uniqueKeysWithValues: [Int32(10), 40].map {
            ($0, ["kMRMediaRemoteNowPlayingInfoTitle": "Track \($0)", "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1] as [String: Any])
        })
        Adapter.systemPID = 10
        Playback.publish(Playback.select())
        Adapter.systemPID = 40
        suite.expect(Playback.select()?.pid == 10, "the music app on screen stays when another one takes the system's session")
        Playback.publish(nil)

        // Sixteen registered clients plus one music app exceed the bound.
        let crowd = (Int32(100)...115).map { $0 }
        Playback.choose(nil)
        Adapter.applications = [Adapter.application(10, "test.player.10", music: true)]
            + crowd.map { Adapter.application($0, "test.player.\($0)") }
        Adapter.registeredPIDs = crowd
        Adapter.systemPID = 10
        Adapter.sourceMetadata = Dictionary(uniqueKeysWithValues: ([10] + crowd).map {
            ($0, ["kMRMediaRemoteNowPlayingInfoTitle": "Track \($0)"] as [String: Any])
        })
        Adapter.sourceMetadata[10]?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 1
        suite.expect(Playback.select()?.pid == 10 && Adapter.sources.count == 16,
                     "more candidates than the bound still yield the playing music app")
        // The system's player is enumerated first, so the last client has a row to choose.
        Adapter.systemPID = 115
        _ = Playback.select()
        Playback.choose(.init(pid: 115, bundleIdentifier: "test.player.115"))
        Adapter.systemPID = 10
        suite.expect(Playback.select()?.pid == 115, "a chosen source enumerated last keeps its place in the bound")
        Playback.choose(nil)
        Adapter.systemPID = 115
        Adapter.sourceMetadata[10]?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 0
        Adapter.sourceMetadata[115]?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 1
        suite.expect(Playback.select()?.pid == 10,
                     "a video discovered at the end of a crowded list stays out of music-only playback")
        Playback.includeOtherPlayers = true
        suite.expect(Playback.select()?.pid == 115,
                     "opted-in playback still finds the system's current player at the end of the bound")
    }
}
