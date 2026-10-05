// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import ObjectiveC

/// One running application, as the selection reads it.
package struct NowPlayingApplication {
    package let pid: Int32
    package let bundleIdentifier: String?
    package let localizedName: String?
    package let isTerminated: Bool
    /// The bundle's `LSApplicationCategoryType`.
    package let category: String?

    package init(pid: Int32, bundleIdentifier: String?, localizedName: String? = nil,
                 isTerminated: Bool = false, category: String? = nil) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.isTerminated = isTerminated
        self.category = category
    }

    init(_ app: NSRunningApplication) {
        self.init(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier,
                  localizedName: app.localizedName, isTerminated: app.isTerminated,
                  category: app.bundleURL.flatMap {
                      Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
                  })
    }
}

/// The watched surface owns its destination independently of the system's
/// latest player. Reads and commands use this same path, without changing the
/// system-wide player or requesting automation permission.
package enum NotchNativePlayback {
    package struct Target {
        package let pid: Int32
        package let bundleIdentifier: String
        package let path: NSObject
        package var itemIdentifier: String?
        package var allowsDirectCommands = false
        package var requiresCurrentPlayer = false
        package var playPauseCommand: Int32 = 2
        package var applicationBundleIdentifier: String?

        package init(pid: Int32, bundleIdentifier: String, path: NSObject, itemIdentifier: String? = nil,
                     allowsDirectCommands: Bool = false, requiresCurrentPlayer: Bool = false) {
            self.pid = pid
            self.bundleIdentifier = bundleIdentifier
            self.path = path
            self.itemIdentifier = itemIdentifier
            self.allowsDirectCommands = allowsDirectCommands
            self.requiresCurrentPlayer = requiresCurrentPlayer
        }

        package var isRunning: Bool {
            guard let app = NotchNativePlayback.platform.application(pid), !app.isTerminated else { return false }
            return app.bundleIdentifier == bundleIdentifier
        }
    }

    /// What the selection asks of the system and the app on the other end of
    /// the pipe. `live` is their own; a test replaces it before anything reads
    /// it, and puts it back after.
    package struct Platform {
        /// A MediaRemote function, by name.
        package var symbol: (String) -> UnsafeMutableRawPointer?
        /// A MediaRemote string constant, by name.
        package var constant: (String) -> String?
        package var application: (Int32) -> NowPlayingApplication?
        package var runningApplications: () -> [NowPlayingApplication]
        package var uptime: () -> TimeInterval
        /// Writes one reply line for the app.
        package var emit: ([String: Any]) -> Void
        /// Reads the session again and replies with it.
        package var refresh: () -> Void
        package var configureQueue: (UUID?) -> Void
        package var playQueue: (NotchQueueSelection) -> Void

        package init(symbol: @escaping (String) -> UnsafeMutableRawPointer?,
                     constant: @escaping (String) -> String?,
                     application: @escaping (Int32) -> NowPlayingApplication?,
                     runningApplications: @escaping () -> [NowPlayingApplication],
                     uptime: @escaping () -> TimeInterval,
                     emit: @escaping ([String: Any]) -> Void,
                     refresh: @escaping () -> Void,
                     configureQueue: @escaping (UUID?) -> Void,
                     playQueue: @escaping (NotchQueueSelection) -> Void) {
            self.symbol = symbol
            self.constant = constant
            self.application = application
            self.runningApplications = runningApplications
            self.uptime = uptime
            self.emit = emit
            self.refresh = refresh
            self.configureQueue = configureQueue
            self.playQueue = playQueue
        }

        package static var live: Platform {
            Platform(
                symbol: { name in handle.flatMap { dlsym($0, name) } },
                constant: { name in
                    guard let handle, let symbol = dlsym(handle, name) else { return nil }
                    return symbol.assumingMemoryBound(to: NSString?.self).pointee as String?
                },
                application: { NSRunningApplication(processIdentifier: $0).map(NowPlayingApplication.init) },
                runningApplications: { NSWorkspace.shared.runningApplications.map(NowPlayingApplication.init) },
                uptime: { ProcessInfo.processInfo.systemUptime },
                emit: { VitruvianNowPlaying.emit($0) },
                refresh: { vitruvianNowPlayingGet() },
                configureQueue: { NotchNativeQueue.configure($0) },
                playQueue: { NotchNativeQueue.play($0) })
        }
    }

    // `nonisolated(unsafe)`: replaced only by a test, before and after it runs.
    nonisolated(unsafe) package static var platform = Platform.live

    // `nonisolated(unsafe)`: set once, then only read.
    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    private static let callbacks = DispatchQueue(label: "com.vitruviansoftware.vitruvian.now-playing-selection-callbacks")
    private static let lock = NSLock()
    // `nonisolated(unsafe)`: `lock` guards these six.
    nonisolated(unsafe) private static var selected: Target?
    nonisolated(unsafe) private static var identity: Identity?
    nonisolated(unsafe) private static var context: NotchPlaybackContext?
    nonisolated(unsafe) private static var sources: [NotchPlaybackSource] = []
    nonisolated(unsafe) private static var selection: NotchPlaybackSource.Selection?
    /// System uptime at which the chosen source, still without a track, is
    /// released. A monotonic clock, so changing the time cannot stretch it.
    nonisolated(unsafe) private static var releaseAt: TimeInterval?
    /// Set before the watch starts; the one-shot reader does not use selection.
    nonisolated(unsafe) package static var includeOtherPlayers = false

    package static var sourceReply: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        var reply: [String: Any] = ["sources": sources.map(\.reply), "sourceIsAutomatic": selection == nil]
        // The chosen source stays marked while the automatic player fills a gap.
        reply["selectedPID"] = selection?.pid
        return reply
    }

    /// When the chosen source, waiting for its next track, is due for release.
    /// Nil once that time has passed, so a failed read never repeats at once.
    static var pendingRelease: TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        guard selection != nil, let releaseAt, releaseAt > platform.uptime() else { return nil }
        return releaseAt
    }

    package static func choose(_ requested: NotchPlaybackSource.Selection?) {
        lock.lock(); defer { lock.unlock() }
        guard requested == nil || sources.contains(where: { $0.selection == requested && $0.hasTrack }) else { return }
        selection = requested
        releaseAt = nil
    }

    private struct Identity: Equatable {
        let item: String?
        let metadata: [String]

        init?(_ info: [String: Any]) {
            let title = (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let identifier = info["itemIdentifier"] as? String
                ?? info["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String
            item = identifier.flatMap { NotchPlaybackCommand.validIdentifier($0) ? $0 : nil }
            if item != nil { metadata = []; return }
            let duration = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue
            metadata = [title, info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                        info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
                        duration.flatMap { $0.isFinite ? String($0.rounded()) : nil } ?? ""]
        }
    }

    package static var target: Target? {
        lock.lock()
        defer { lock.unlock() }
        return selected
    }

    private static func playPauseCommand(for info: [String: Any]) -> Int32 {
        guard let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue,
              rate.isFinite else { return 2 }
        if rate > 0, info["canPause"] as? Bool == true { return 1 }
        if rate == 0, info["canPlay"] as? Bool == true { return 0 }
        return 2
    }

    package static func select() -> Target? {
        var discovered = false
        defer {
            if !discovered {
                // A failed scan is not evidence that the chosen player ended.
                lock.lock(); sources = []; lock.unlock()
            }
        }
        typealias ReadClient = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
        typealias ReadClients = @convention(c) (DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
        typealias PID = @convention(c) (AnyObject) -> Int32
        typealias ClientString = @convention(c) (AnyObject) -> Unmanaged<CFString>?
        guard let getClient = function("MRMediaRemoteGetNowPlayingClient", as: ReadClient.self),
              let getPID = function("MRNowPlayingClientGetProcessIdentifier", as: PID.self) else { return nil }
        let group = DispatchGroup()
        let clientsGroup = DispatchGroup()
        let resultsLock = NSLock()
        var systemPID: Int32?
        var clientPIDs: [Int32] = []
        var clientPresentation: [Int32: (name: String?, application: String?)] = [:]
        let getName = function("MRNowPlayingClientGetDisplayName", as: ClientString.self)
        let getParent = function("MRNowPlayingClientGetParentAppBundleIdentifier", as: ClientString.self)
        group.enter()
        getClient(callbacks) { client in
            resultsLock.lock()
            systemPID = client.map(getPID)
            resultsLock.unlock()
            group.leave()
        }
        // Browsers need to remain discoverable when a music app owns the
        // system's current player. Enumerate registered clients, not all apps.
        if let getClients = function("MRMediaRemoteGetNowPlayingClients", as: ReadClients.self) {
            clientsGroup.enter()
            getClients(callbacks) { clients in
                resultsLock.lock()
                clientPIDs = (clients as? [AnyObject] ?? []).prefix(16).map(getPID)
                for client in (clients as? [AnyObject] ?? []).prefix(16) {
                    clientPresentation[getPID(client)] = (getName?(client)?.takeUnretainedValue() as String?,
                                                         getParent?(client)?.takeUnretainedValue() as String?)
                }
                resultsLock.unlock()
                clientsGroup.leave()
            }
        }
        guard group.wait(timeout: .now() + 0.5) == .success else { return nil }
        // Failure to enumerate extra sources must not hide the known player.
        _ = clientsGroup.wait(timeout: .now() + 0.2)
        resultsLock.lock()
        let currentPID = systemPID
        let registeredPIDs = clientPIDs
        let presentation = clientPresentation
        resultsLock.unlock()
        let chosenPID = lock.withLock { selection?.pid }
        let musicPIDs = platform.runningApplications().filter { isMusicApp($0) }.map(\.pid)
        var applications: [NowPlayingApplication] = []
        // A bounded fan-out; no timers or queries survive the adapter process.
        // Past the bound, only the least likely clients are skipped: chosen,
        // current and followed players first, then music apps, then the rest.
        for pid in [chosenPID, currentPID, target?.pid].compactMap({ $0 }) + musicPIDs + registeredPIDs {
            guard applications.count < 16 else { break }
            if pid > 0, !applications.contains(where: { $0.pid == pid }),
               let current = platform.application(pid) {
                applications.append(current)
            }
        }
        var candidates: [(Target, NotchPlaybackSource)] = []
        for app in applications {
            guard var candidate = makeTarget(app) else { continue }
            // A browser can publish through a web content helper. Keep its exact
            // process for routing, and use the parent app only for presentation/opening.
            candidate.applicationBundleIdentifier = presentation[candidate.pid]?.application
                .flatMap { NotchPlaybackCommand.validIdentifier($0) ? $0 : nil }
            group.enter()
            readInfo(candidate, artwork: false, queue: callbacks) { info in
                let source = NotchPlaybackSource(pid: candidate.pid, bundleIdentifier: candidate.bundleIdentifier,
                    isMusicApp: isMusicApp(app, parentBundleIdentifier: candidate.applicationBundleIdentifier),
                    isPlaying: (info?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0 > 0,
                    hasTrack: (info?["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                    displayName: presentation[candidate.pid]?.name ?? app.localizedName)
                resultsLock.lock()
                candidates.append((candidate, source))
                resultsLock.unlock()
                group.leave()
            }
        }
        // Keep completed reads when an unrelated client misses the deadline.
        _ = group.wait(timeout: .now() + 1)
        resultsLock.lock()
        let ready = candidates
        resultsLock.unlock()
        let now = platform.uptime()
        lock.lock()
        if let selection {
            let app = platform.application(selection.pid)
            let ended = app == nil || app?.isTerminated == true || app?.bundleIdentifier != selection.bundleIdentifier
            let lostTrack = ready.contains { $0.1.selection == selection && !$0.1.hasTrack }
            if ready.contains(where: { $0.1.selection == selection && $0.1.hasTrack }) { releaseAt = nil }
            // A browser clears its track between videos. The choice outlasts
            // five seconds without one, while the automatic player fills in.
            if lostTrack, releaseAt == nil { releaseAt = now + 5 }
            let expired = releaseAt.map { now >= $0 } == true
            if ended || expired {
                self.selection = nil
                releaseAt = nil
            }
        }
        let requested = selection
        let bridging = requested != nil && releaseAt != nil
        // The chooser keeps the chosen row, and its checkmark, during a gap.
        sources = ready.map(\.1).filter { $0.hasTrack || bridging && $0.selection == requested }
            .sorted { $0.pid < $1.pid }
        lock.unlock()
        discovered = true
        // An unanswered selected player stays selected, but exposes no stale
        // controls. The empty surface still lets the user choose another one.
        if let requested, !bridging,
           !ready.contains(where: { $0.1.selection == requested && $0.1.hasTrack }) { return nil }
        let source = NotchPlaybackSource.preferred(in: ready.map(\.1), previousPID: target?.pid,
                                                   systemPID: currentPID, selection: requested,
                                                   includeOtherPlayers: includeOtherPlayers)
        guard var chosen = ready.first(where: { $0.1 == source })?.0 else { return nil }
        typealias IsSystemPlayer = @convention(c) (AnyObject, Selector) -> Bool
        let systemPlayer = ["isSystemMediaApplication", "isSystemPodcastsApplication", "isSystemBooksApplication"].contains { name in
            let selector = NSSelectorFromString(name)
            guard chosen.path.responds(to: selector) else { return false }
            return unsafeBitCast(chosen.path.method(for: selector), to: IsSystemPlayer.self)(chosen.path, selector)
        }
        // A third-party player without Automation can receive native commands
        // while it owns the system session. Recheck that ownership at delivery.
        chosen.requiresCurrentPlayer = !systemPlayer && chosen.pid == currentPID
        chosen.allowsDirectCommands = (systemPlayer
            && stringConstant("kMRMediaRemoteOptionNowPlayingContentItemID") != nil)
            || chosen.requiresCurrentPlayer
        return chosen
    }

    @discardableResult
    package static func publish(_ target: Target?, info: [String: Any] = [:]) -> NotchPlaybackContext? {
        lock.lock()
        defer { lock.unlock() }
        guard var target, let next = Identity(info) else {
            selected = target; identity = nil; context = nil
            return nil
        }
        // Position and play/pause updates do not end a recording. Without an
        // item ID, use only observable recording metadata for its revision.
        if selected?.pid != target.pid || selected?.bundleIdentifier != target.bundleIdentifier
            || identity != next {
            context = NotchPlaybackContext(pid: target.pid, revision: UUID())
        }
        target.itemIdentifier = next.item
        // Some players expose Play and Pause separately. Use the command for
        // the displayed state, keeping Toggle for players without either one.
        target.playPauseCommand = playPauseCommand(for: info)
        selected = target
        identity = next
        return context
    }

    /// A supported-command callback may finish after the metadata snapshot.
    /// Update only the same selected path and recording, without polling again.
    package static func updatePlayPauseCommand(for target: Target, info: [String: Any]) {
        guard let next = Identity(info) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard var current = selected, current.path === target.path,
              current.pid == target.pid, current.bundleIdentifier == target.bundleIdentifier,
              identity == next else { return }
        current.playPauseCommand = playPauseCommand(for: info)
        selected = current
    }

    package static func validatedTarget(for requested: NotchPlaybackContext) -> Target? {
        lock.lock()
        let target = context == requested ? selected : nil
        let expected = identity
        lock.unlock()
        guard let target, let expected, target.isRunning else { return nil }
        // The actual player can advance before its change notification reaches
        // our reader. Re-read this path without changing music source selection.
        let group = DispatchGroup()
        let resultLock = NSLock()
        var fresh: Identity?
        group.enter()
        readInfo(target, artwork: false, queue: callbacks) { info in
            resultLock.lock()
            fresh = (info as? [String: Any]).flatMap(Identity.init)
            resultLock.unlock()
            group.leave()
        }
        guard group.wait(timeout: .now() + 1) == .success else { return nil }
        resultLock.lock()
        let matches = fresh == expected
        resultLock.unlock()
        lock.lock()
        defer { lock.unlock() }
        guard matches, context == requested, identity == expected,
              let current = selected, current.path === target.path, current.isRunning else { return nil }
        return current
    }

    package static func readInfo(_ target: Target, artwork: Bool, queue: DispatchQueue,
                         completion: @escaping (NSDictionary?) -> Void) {
        typealias Read = @convention(c) (AnyObject, Bool, DispatchQueue,
            @escaping @convention(block) (NSDictionary?, UnsafeRawPointer?) -> Void) -> Void
        typealias CopyArtwork = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFData>?
        guard target.isRunning,
              let read = function("MRMediaRemoteGetNowPlayingInfoForPlayer", as: Read.self) else {
            completion(nil); return
        }
        read(target.path, artwork, queue) { info, cover in
            guard let info else { completion(nil); return }
            let result = info.mutableCopy() as! NSMutableDictionary
            if let cover, let copy = function("MRNowPlayingArtworkCopyImageData", as: CopyArtwork.self),
               let data = copy(cover)?.takeRetainedValue() {
                result["kMRMediaRemoteNowPlayingInfoArtworkData"] = data as Data
            }
            completion(result)
        }
    }

    package static func supportedCommands(_ target: Target, queue: DispatchQueue, completion: @escaping (NSArray?) -> Void) {
        typealias Read = @convention(c) (AnyObject, DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
        guard let read = function("MRMediaRemoteGetSupportedCommandsForPlayer", as: Read.self) else {
            completion(nil); return
        }
        read(target.path, queue, completion)
    }

    private static func currentPlayerPID() -> Int32? {
        typealias Read = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
        typealias PID = @convention(c) (AnyObject) -> Int32
        guard let read = function("MRMediaRemoteGetNowPlayingClient", as: Read.self),
              let getPID = function("MRNowPlayingClientGetProcessIdentifier", as: PID.self) else { return nil }
        let group = DispatchGroup()
        let resultLock = NSLock()
        var pid: Int32?
        group.enter()
        read(callbacks) { client in
            resultLock.lock()
            pid = client.map(getPID)
            resultLock.unlock()
            group.leave()
        }
        guard group.wait(timeout: .now() + 0.5) == .success else { return nil }
        return resultLock.withLock { pid }
    }

    @discardableResult
    package static func send(_ command: Int32, options: CFDictionary? = nil, to target: Target) -> Bool {
        typealias Send = @convention(c) (Int32, CFDictionary?, AnyObject, UInt32, DispatchQueue,
            @escaping @convention(block) (UInt32, NSArray?) -> Void) -> Bool
        guard target.isRunning, target.allowsDirectCommands,
              !target.requiresCurrentPlayer || currentPlayerPID() == target.pid,
              let send = function("MRMediaRemoteSendCommandToPlayer", as: Send.self) else { return false }
        // The service may redirect unprivileged requests to the global player.
        // Scope to the recording when possible; an unidentified recording is
        // allowed only while this process remains the current system player.
        var scoped = (options as? [String: Any]) ?? [:]
        if let item = target.itemIdentifier,
           let itemKey = stringConstant("kMRMediaRemoteOptionNowPlayingContentItemID") {
            scoped[itemKey] = item
        } else if !target.requiresCurrentPlayer { return false }
        let settings = scoped.isEmpty ? nil : scoped as CFDictionary
        let group = DispatchGroup()
        let resultLock = NSLock()
        var delivered = false
        group.enter()
        guard send(command, settings, target.path, 0, callbacks, { error, responses in
            resultLock.lock()
            delivered = error == 0 && (responses as? [NSNumber])?.contains(where: { $0.intValue == 0 }) == true
            resultLock.unlock()
            group.leave()
        }) else { return false }
        guard group.wait(timeout: .now() + 2) == .success else { return false }
        return resultLock.withLock { delivered }
    }

    package static func stringConstant(_ name: String) -> String? {
        platform.constant(name)
    }

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        platform.symbol(name).map { unsafeBitCast($0, to: type) }
    }

    private static func isMusicApp(_ app: NowPlayingApplication, parentBundleIdentifier: String? = nil) -> Bool {
        NotchPlaybackSource.isMusicApplication(bundleIdentifier: app.bundleIdentifier,
                                               parentBundleIdentifier: parentBundleIdentifier, category: app.category)
    }

    /// A player path of this application's own, for reads and commands.
    package static func makeTarget(_ app: NowPlayingApplication) -> Target? {
        guard !app.isTerminated, let identifier = app.bundleIdentifier,
              let pathClass = NSClassFromString("MRPlayerPath"),
              let clientClass = NSClassFromString("MRClient"),
              class_getClassMethod(pathClass, NSSelectorFromString("localPlayerPath")) != nil,
              class_getInstanceMethod(clientClass, NSSelectorFromString("initWithBundleIdentifier:")) != nil,
              let localPath = (pathClass as AnyObject).perform(NSSelectorFromString("localPlayerPath"))?.takeUnretainedValue() as? NSObject,
              let path = localPath.copy() as? NSObject,
              let allocation = (clientClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeRetainedValue(),
              let client = allocation.perform(NSSelectorFromString("initWithBundleIdentifier:"), with: identifier)?.takeUnretainedValue() as? NSObject else { return nil }
        // The native local path is shared. Only mutate our own copy, otherwise
        // constructing the next candidate redirects previously selected paths.
        typealias SetPID = @convention(c) (AnyObject, Selector, Int32) -> Void
        let setPID = NSSelectorFromString("setProcessIdentifier:")
        guard client.responds(to: setPID), path.responds(to: NSSelectorFromString("setClient:")),
              path.responds(to: NSSelectorFromString("setPlayer:")) else { return nil }
        unsafeBitCast(client.method(for: setPID), to: SetPID.self)(client, setPID, app.pid)
        path.perform(NSSelectorFromString("setClient:"), with: client)
        // Nil resolves this app's active player; "default" is a different player
        // for apps which publish multiple sessions.
        path.perform(NSSelectorFromString("setPlayer:"), with: nil)
        return Target(pid: app.pid, bundleIdentifier: identifier, path: path)
    }

    /// Runs one request from the app: a source choice, a validation, a queue
    /// command or a transport command for the recording on screen.
    package static func perform(_ request: NotchPlaybackRequest) {
        let command = request.command
        switch command {
        case .source(let selection):
            platform.configureQueue(nil)
            choose(selection)
            platform.refresh()
            return
        case .validate(let id, let context):
            platform.emit(["validationRequest": id.uuidString,
                           "validationOK": validatedTarget(for: context) != nil])
            return
        case .queue(let request): platform.configureQueue(request); return
        case .queueStop: platform.configureQueue(nil); return
        case .queuePlay(let selected): platform.playQueue(selected); return
        default: break
        }
        guard let context = request.context,
              let target = validatedTarget(for: context) else { platform.emit(["sent": false]); return }
        let identifier: Int32
        var options: CFDictionary?
        switch command {
        case .toggle: identifier = target.playPauseCommand
        case .next: identifier = 4
        case .previous: identifier = 5
        case .seek(let position):
            guard let key = stringConstant("kMRMediaRemoteOptionPlaybackPosition") else {
                platform.emit(["sent": false]); return
            }
            identifier = 24
            options = [key: position] as CFDictionary
        case .queue, .queueStop, .queuePlay, .validate, .source: return
        }
        platform.emit(["sent": send(identifier, options: options, to: target)])
    }
}
