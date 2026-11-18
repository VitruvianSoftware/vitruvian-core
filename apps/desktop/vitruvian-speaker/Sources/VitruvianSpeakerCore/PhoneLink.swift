// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

// When "speak on phone" is on and the phone's link to Vitruvian Remote is
// down, the relay answers every phone-say with "no phone connected". Those
// announcements are dropped for the phone (see `Announcer.sendPhone` for
// why they are not queued). What this file adds is that the outage is
// written down, once, so every place that shows Vitruvian Speaker's state
// (`--status`, the menu bar, the extension's page and island, `--state`)
// can say so, and a probe can clear it when the phone comes back.

/// What was last seen of the phone's link: down since `since`, or back
/// since `since`.
public struct PhoneLinkStatus: Codable, Equatable, Sendable {
    public var connected: Bool
    public var since: Date

    public init(connected: Bool, since: Date) {
        self.connected = connected
        self.since = since
    }
}

/// `~/.gemini/speaker_phone_link.json` for the app, `phone_link.json` in the
/// extension's data folder. Written under an exclusive `FileLock` on its own
/// `.lock` file and replaced atomically, as `ChatMonitorStatusFile` is, so a
/// reader takes no lock and never sees half a file.
public struct PhoneLinkStatusFile: Sendable {
    public static let appFileName = "speaker_phone_link.json"
    public static let extensionFileName = "phone_link.json"

    /// The words every surface shows during an outage.
    public static let headline = "Your phone: not connected"
    public static let hint = "Open Vitruvian Remote → Settings → Phone Bridge → Run Phone Bridge"
    /// Logged once, when an outage starts.
    public static let droppedNotice =
        "Your phone is not connected; phone announcements are dropped until it reconnects. \(hint)"

    /// The headline with when it started, in local time: "Your phone: not
    /// connected (since 14:05)".
    public static func headline(since: Date, calendar: Calendar = .current) -> String {
        "\(headline) (since \(SpeakerConfig.localTimeHHmm(since, calendar: calendar)))"
    }

    public let url: URL
    public var lockURL: URL { url.appendingPathExtension("lock") }

    public init(url: URL) {
        self.url = url
    }

    /// The file for `door` in the folder `settingsURL` is in.
    public static func url(beside settingsURL: URL, door: VitruvianSpeakerProfile.Door) -> URL {
        settingsURL.deletingLastPathComponent()
            .appendingPathComponent(door == .app ? appFileName : extensionFileName)
    }

    /// Nil when there is no file, or none that reads.
    public func read() -> PhoneLinkStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(PhoneLinkStatus.self, from: data)
    }

    /// When the outage that a reader should show began: only while phone
    /// output is on and the file says not connected. Nil otherwise.
    public func outageSince(config: SpeakerConfig) -> Date? {
        Self.outageSince(read(), config: config)
    }

    public static func outageSince(_ status: PhoneLinkStatus?, config: SpeakerConfig) -> Date? {
        guard config.effectiveSpeakPhone, let status, !status.connected else { return nil }
        return status.since
    }

    /// The relay said no phone is connected. Returns true only when this
    /// starts an outage (no file yet, or the file said connected), so the
    /// caller says so once and not on every dropped announcement.
    @discardableResult
    public func recordNotConnected(at date: Date = Date()) -> Bool {
        if read()?.connected == false { return false }
        return (try? FileLock.withExclusiveLock(at: lockURL) { () throws -> Bool in
            if read()?.connected == false { return false }
            try write(PhoneLinkStatus(connected: false, since: date))
            return true
        }) ?? false
    }

    /// The phone answered (or the probe saw it connected). Writes only when
    /// the file says not connected, so an ordinary announcement writes
    /// nothing.
    public func recordConnected(at date: Date = Date()) {
        guard read()?.connected == false else { return }
        try? FileLock.withExclusiveLock(at: lockURL) { () throws -> Void in
            guard read()?.connected == false else { return }
            try write(PhoneLinkStatus(connected: true, since: date))
        }
    }

    /// `read()`, for a short-lived reader (`--status`, `--state`) that no
    /// watcher keeps fresh: while phone output is on and an outage is
    /// recorded, it asks the relay once (up to `wait`) and clears the
    /// outage if the phone is back. Without an outage, or with phone output
    /// off, nothing is asked. Blocks the caller for at most `wait`, and
    /// clearing takes the file lock on the caller's thread: meant for the
    /// short-lived command-line process, never a UI loop (the long-lived
    /// app and extension clear through `PhoneLinkWatcher` instead).
    public func refreshedRead(
        config: SpeakerConfig, probe: PhoneLinkProbing = PhoneLinkProbe(),
        wait: TimeInterval = 3, at date: Date = Date()
    ) -> PhoneLinkStatus? {
        let status = read()
        guard config.effectiveSpeakPhone, status?.connected == false else { return status }
        let answer = ProbeAnswer()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            answer.set(await probe.isConnected())
            done.signal()
        }
        guard done.wait(timeout: .now() + wait) == .success, answer.get() == true else { return status }
        recordConnected(at: date)
        return read()
    }

    private func write(_ status: PhoneLinkStatus) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(status)
        try data.write(to: url, options: .atomic)
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// One probe answer handed from a detached task to a waiting caller.
private final class ProbeAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?
    func set(_ v: Bool?) { lock.withLock { value = v } }
    func get() -> Bool? { lock.withLock { value } }
}

/// Asks the relay whether the phone is connected.
public protocol PhoneLinkProbing: Sendable {
    /// True or false as the relay says; nil when the relay could not be
    /// asked or gave no answer.
    func isConnected() async -> Bool?
}

/// `GET <relay>/v1/phone` on the local Vitruvian Remote relay (no auth),
/// which answers `{"connected": bool, …}`.
public struct PhoneLinkProbe: PhoneLinkProbing {
    /// The relay's address, from `PhoneSpeaker.defaultEndpoint` with its
    /// path replaced.
    public static var defaultEndpoint: URL { endpoint(relativeTo: PhoneSpeaker.defaultEndpoint) }

    public static func endpoint(relativeTo phoneSay: URL) -> URL {
        guard var parts = URLComponents(url: phoneSay, resolvingAgainstBaseURL: false) else { return phoneSay }
        parts.path = "/v1/phone"
        parts.query = nil
        parts.fragment = nil
        return parts.url ?? phoneSay
    }

    public let endpoint: URL
    let send: PhoneSpeaker.Send

    public init(
        endpoint: URL = PhoneLinkProbe.defaultEndpoint,
        send: @escaping PhoneSpeaker.Send = { try await URLSession.shared.data(for: $0) }
    ) {
        self.endpoint = endpoint
        self.send = send
    }

    public func isConnected() async -> Bool? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        guard let (data, response) = try? await send(request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return json["connected"] as? Bool
    }
}

/// While phone output is on and an outage is recorded, asks the relay every
/// `interval` whether the phone is back, and clears the outage when it is,
/// so the warning goes away without waiting for the next announcement. An
/// unreachable relay leaves it as it is. Run by the long-lived process
/// (`VitruvianSpeakerEngine.listen`), never by the command line.
@MainActor
public final class PhoneLinkWatcher {
    private let statusFile: PhoneLinkStatusFile
    private let probe: PhoneLinkProbing
    private let config: @MainActor () -> SpeakerConfig
    private let interval: Duration
    private let now: @Sendable () -> Date
    private var task: Task<Void, Never>?

    public init(
        statusFile: PhoneLinkStatusFile,
        probe: PhoneLinkProbing = PhoneLinkProbe(),
        config: @escaping @MainActor () -> SpeakerConfig,
        interval: Duration = .seconds(60),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.statusFile = statusFile
        self.probe = probe
        self.config = config
        self.interval = interval
        self.now = now
    }

    public var isRunning: Bool { task != nil }

    public func start() {
        guard task == nil else { return }
        let interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.check()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// One look. True when it cleared an outage.
    @discardableResult
    public func check() async -> Bool {
        guard config().effectiveSpeakPhone, statusFile.read()?.connected == false else { return false }
        guard await probe.isConnected() == true else { return false }
        // The write takes a file lock another process may hold: not on the
        // main actor.
        let file = statusFile
        let at = now()
        await Task.detached { file.recordConnected(at: at) }.value
        return true
    }
}
