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

import AppKit
import Foundation

// A speaker's volume: read it, set it, and -- for "announce at a set volume"
// -- raise or lower it for one announcement and put it back afterwards.
//
// Facts from the live Home API (2026-09-22), each one a trap:
//
// - `list_home_states` filtered to the `Volume` trait reports
//   `currentVolumePercent` and `isMuted` for speakers, displays and TVs.
// - Changing it must address the device's SPEAKER component: a Nest Hub is a
//   `GoogleDisplayDevice`, and `Volume.MoveToVolume` sent with that type fails
//   "Trait not supported"; sent with `SpeakerDevice` it works.
// - An offline speaker still reports a level -- the last one it had -- and no
//   mute flag. It is shown as offline, never as that stale number.
// - Some speakers expose no volume at all, and the whole-home target has none.
// - The reported level LAGS the change: measured on James's Nest Hub, a new
//   level showed up ~3 s after the command returned (~6 s after it was sent).
//   A read straight after a set returns the old level. Everything that reads
//   after setting waits for it (`confirmedVolume`).
// - And it is flaky: in live testing one set was refused with no message, and
//   one of seven never showed up at all. Setting an absolute level is safe to
//   repeat, so a refusal is retried once and an unconfirmed set is re-sent
//   once (`setVolumeConfirmed`).

/// A speaker's volume as Google last heard it.
public struct SpeakerVolume: Equatable, Sendable {
    public var percent: Int
    public var muted: Bool
    public var online: Bool

    public init(percent: Int, muted: Bool, online: Bool) {
        self.percent = percent
        self.muted = muted
        self.online = online
    }
}

public enum VolumeError: LocalizedError, Equatable {
    case wholeHome
    /// The speaker has no volume control through the Home API.
    case unsupported(String)
    case offline(String)

    public var errorDescription: String? {
        switch self {
        case .wholeHome: return "Pick a single speaker to see or change its volume."
        case .unsupported(let name): return "\(name) does not offer volume control through Google Home."
        case .offline(let name): return "\(name) is offline."
        }
    }
}

/// What the volume features need from Google Home -- a protocol so the
/// restore logic can be tested without a speaker in the room.
public protocol VolumeControlling: Sendable {
    func volume(of target: SpeakerDevice, structureId: String) async throws -> SpeakerVolume
    func setVolume(_ percent: Int, on target: SpeakerDevice, structureId: String) async throws
}

extension VolumeControlling {
    /// The volume once it reads `expecting`, or the last reading when that
    /// never happens within `timeout` -- Google reports a change seconds
    /// after making it, so a single read straight after a set is stale.
    public func confirmedVolume(
        of target: SpeakerDevice, structureId: String, expecting: Int,
        timeout: Double = 8, interval: Double = 0.75
    ) async throws -> SpeakerVolume {
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        var last = try await volume(of: target, structureId: structureId)
        while last.percent != expecting, Date() < deadline {
            // Never sleep past the deadline: the caller's timeout is a promise.
            let nap = min(interval, deadline.timeIntervalSinceNow)
            if nap > 0 { try? await Task.sleep(for: .milliseconds(Int(nap * 1000))) }
            last = try await volume(of: target, structureId: structureId)
        }
        return last
    }

    /// Sets `percent` and waits until Google reports it, re-sending once when
    /// it has not shown up after `timeout`. Returns what Google finally says,
    /// which the caller shows -- never the level it only asked for.
    public func setVolumeConfirmed(
        _ percent: Int, on target: SpeakerDevice, structureId: String, timeout: Double = 6
    ) async throws -> SpeakerVolume {
        try await setVolume(percent, on: target, structureId: structureId)
        let first = try await confirmedVolume(of: target, structureId: structureId, expecting: percent, timeout: timeout)
        guard first.percent != percent else { return first }
        try await setVolume(percent, on: target, structureId: structureId)
        return try await confirmedVolume(of: target, structureId: structureId, expecting: percent, timeout: timeout)
    }
}

extension GoogleHomeClient: VolumeControlling {
    public func volume(of target: SpeakerDevice, structureId: String) async throws -> SpeakerVolume {
        guard !target.isWholeHome else { throw VolumeError.wholeHome }
        let payload = try await callTool("list_home_states", arguments: [
            "structureId": structureId,
            "freshness": "MOST_FRESH",
            "filter": ["resourceIds": [target.id], "shortenedResourceTraits": ["Volume"]],
        ])
        guard let volume = Self.parseVolume(payload, deviceId: target.id) else {
            throw VolumeError.unsupported(target.name)
        }
        return volume
    }

    public func setVolume(_ percent: Int, on target: SpeakerDevice, structureId: String) async throws {
        try await runVolumeCommand("Volume.MoveToVolume", ["volumePercent": min(max(percent, 0), 100)], on: target, structureId: structureId)
    }

    public func setMuted(_ muted: Bool, on target: SpeakerDevice, structureId: String) async throws {
        try await runVolumeCommand(muted ? "Volume.Mute" : "Volume.Unmute", [:], on: target, structureId: structureId)
    }

    private func runVolumeCommand(_ command: String, _ parameters: [String: Any], on target: SpeakerDevice, structureId: String) async throws {
        guard !target.isWholeHome else { throw VolumeError.wholeHome }
        var request: [String: Any] = [
            "id": target.id,
            // The speaker component, whatever the device is -- see the top of this file.
            "type": "SpeakerDevice",
            "command": command,
        ]
        if !parameters.isEmpty { request["parameters"] = parameters }
        let arguments: [String: Any] = ["structureId": structureId, "homeActionRequests": [request]]
        if Self.actionError(try await callTool("run_home_actions", arguments: arguments)) == nil { return }
        // Refused -- seen once live, with no reason given. One retry.
        try? await Task.sleep(for: .seconds(1))
        if let failure = Self.actionError(try await callTool("run_home_actions", arguments: arguments)) {
            throw BroadcastError.mcp(failure)
        }
    }

    /// The Volume state of `deviceId` in a `list_home_states` answer, or nil
    /// when that speaker reports no Volume trait.
    static func parseVolume(_ payload: [String: Any], deviceId: String) -> SpeakerVolume? {
        let states = (payload["states"] as? [[String: Any]]) ?? []
        guard let entry = states.first(where: { ($0["id"] as? String) == deviceId }),
              let traits = entry["traits"] as? [String: Any],
              let volume = traits["Volume"] as? [String: Any],
              let state = volume["state"] as? [String: Any],
              let percent = (state["currentVolumePercent"] as? NSNumber)?.doubleValue
        else { return nil }
        return SpeakerVolume(
            percent: Int(percent.rounded()),
            muted: (state["isMuted"] as? Bool) ?? false,
            online: (entry["resourceConnectivityState"] as? String) != "OFFLINE")
    }

    /// The first per-device error in a `run_home_actions` answer. The call
    /// itself returns 200 when a device refuses; the refusal is only in here.
    static func actionError(_ payload: [String: Any]) -> String? {
        let responses = (payload["homeActionResponses"] as? [[String: Any]]) ?? []
        for r in responses {
            guard let err = r["error"] as? [String: Any] else { continue }
            // The message is sometimes absent; the reason code is the only
            // clue then ("EXECUTION_FAILURE", "DEVICE_BUSY", ...).
            let reasons = ((err["details"] as? [[String: Any]]) ?? []).compactMap { $0["reason"] as? String }
            let code = (err["code"] as? NSNumber).map { "code \($0)" }
            let message = (err["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let parts = [message, reasons.isEmpty ? nil : reasons.joined(separator: ", "), code].compactMap { $0 }
            return parts.isEmpty ? "the speaker refused the command" : parts.joined(separator: " -- ")
        }
        return nil
    }
}

// MARK: - Announce at a set volume

/// The level to put back after an announcement, and the level it was set to
/// -- restoring only happens if the speaker is still at that level, so a
/// volume someone changed by hand during the announcement is left alone.
public struct VolumeBoost: Equatable, Sendable {
    public var target: SpeakerDevice
    public var structureId: String
    public var restoreTo: Int
    public var announceLevel: Int
}

public enum AnnounceVolume {
    /// Sets `target` to `level` for an announcement. Returns what is needed to
    /// put it back, or nil when there is nothing to do (whole home, no volume
    /// control, offline, or no way to restore it later).
    public static func prepare(
        level: Int, target: SpeakerDevice, structureId: String,
        client: VolumeControlling, canRestore: Bool
    ) async -> VolumeBoost? {
        // Never raise a speaker nothing will lower again.
        guard canRestore, !target.isWholeHome else { return nil }
        guard let current = try? await client.volume(of: target, structureId: structureId), current.online else { return nil }
        let boost = VolumeBoost(target: target, structureId: structureId, restoreTo: current.percent, announceLevel: level)
        // Already there -- possibly because an earlier announcement in a burst
        // set it. The restore request still goes out, so a pending restore
        // is extended rather than firing mid-announcement.
        if current.percent != level {
            do { try await client.setVolume(level, on: target, structureId: structureId) } catch { return nil }
        }
        return boost
    }
}

/// Puts speakers back after announcements. Lives in the menu bar app -- the
/// one process that outlives an announcement -- like the media pause.
@MainActor
public final class VolumeRestoreCoordinator: ObservableObject {
    public static let shared = VolumeRestoreCoordinator()

    @Published public private(set) var lastReport: String?

    private struct Pending {
        var boost: VolumeBoost
        var at: Date
        var task: Task<Void, Never>?
    }

    private let client: VolumeControlling
    private let confirmTimeout: Double
    private var pending: [String: Pending] = [:]
    /// What each speaker was last put back to, and when. An announcement just
    /// after a restore can read the raised level (the report lags), and
    /// would otherwise take that as the speaker's own volume.
    private var recentlyRestored: [String: (level: Int, at: Date)] = [:]

    /// Never put a speaker back sooner than this after raising it: Google
    /// takes up to ~6 s to report the raised level, and checking before then
    /// looks exactly like someone having changed it by hand.
    public nonisolated static let minimumHold: Double = 8

    private let minimumHold: Double

    public init(
        client: VolumeControlling = GoogleHomeClient.shared,
        confirmTimeout: Double = 4, minimumHold: Double = VolumeRestoreCoordinator.minimumHold
    ) {
        self.client = client
        self.confirmTimeout = confirmTimeout
        self.minimumHold = minimumHold
    }

    public var isHolding: Bool { !pending.isEmpty }

    /// Restore `boost` after `seconds`. A second announcement to the same
    /// speaker while one is pending keeps the FIRST level to restore -- the
    /// second one read the raised level -- and pushes the time out.
    public func schedule(_ boost: VolumeBoost, after seconds: Double) {
        let id = boost.target.id
        // A zero delay means "the announcement failed, put it back now".
        let delay = seconds <= 0 ? 0 : max(seconds, minimumHold)
        let at = Date().addingTimeInterval(delay)
        if var p = pending[id] {
            p.at = max(p.at, at)
            p.task?.cancel()
            p.task = timer(id, at: p.at)
            pending[id] = p
            return
        }
        var boost = boost
        if boost.restoreTo == boost.announceLevel,
           let recent = recentlyRestored[id], Date().timeIntervalSince(recent.at) < 15 {
            // Read the stale raised level; the speaker's own level is the one
            // just restored.
            boost.restoreTo = recent.level
        }
        guard boost.restoreTo != boost.announceLevel else { return }
        pending[id] = Pending(boost: boost, at: at, task: timer(id, at: at))
    }

    /// Restore now: the announcement failed, or the app is quitting.
    public func restoreNow(_ deviceId: String) async {
        pending[deviceId]?.task?.cancel()
        await fire(deviceId)
    }

    private func timer(_ id: String, at: Date) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(max(at.timeIntervalSinceNow, 0) * 1000)))
            guard !Task.isCancelled else { return }
            await self?.fire(id)
        }
    }

    private func fire(_ id: String) async {
        guard let p = pending.removeValue(forKey: id) else { return }
        let b = p.boost
        // Wait out the reporting lag before deciding anyone changed it.
        guard let now = try? await client.confirmedVolume(
            of: b.target, structureId: b.structureId, expecting: b.announceLevel, timeout: confirmTimeout) else {
            lastReport = "Could not read \(b.target.name)'s volume to put it back to \(b.restoreTo)%."
            return
        }
        guard now.percent == b.announceLevel else {
            // Already back where it was: the raise never took (Google drops
            // the odd command). Nothing to put back, and nobody to blame.
            lastReport = now.percent == b.restoreTo
                ? "\(b.target.name) is at \(now.percent)%, its own volume -- the announcement level did not take."
                : "Left \(b.target.name) at \(now.percent)% -- it was changed during the announcement."
            return
        }
        do {
            _ = try await client.setVolumeConfirmed(b.restoreTo, on: b.target, structureId: b.structureId)
            recentlyRestored[id] = (b.restoreTo, Date())
            lastReport = "Put \(b.target.name) back to \(b.restoreTo)% after announcing at \(b.announceLevel)%."
        } catch {
            lastReport = "Could not put \(b.target.name) back to \(b.restoreTo)%: \(error.localizedDescription)"
        }
    }
}

/// Hands a restore to the menu bar app from any process.
public enum VolumeRestoreRequest {
    public static let notificationName = Notification.Name("com.vitruviansoftware.homespeaker.volume-restore")
    public static let bundleID = "com.vitruviansoftware.homespeaker"

    @MainActor public static var inProcess: VolumeRestoreCoordinator?

    /// Whether anything will be alive to put the volume back. The Stop hook
    /// and --say exit seconds after announcing; without the app running,
    /// raising the volume would leave it raised.
    public static func canRestore() async -> Bool {
        if await MainActor.run(body: { inProcess != nil }) { return true }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public static func schedule(_ boost: VolumeBoost, after seconds: Double) async {
        if let c = await MainActor.run(body: { inProcess }) {
            await c.schedule(boost, after: seconds)
            return
        }
        DistributedNotificationCenter.default().postNotificationName(
            notificationName, object: nil, userInfo: encode(boost, after: seconds), deliverImmediately: true)
    }

    static func encode(_ b: VolumeBoost, after seconds: Double) -> [String: Any] {
        [
            "id": b.target.id, "type": b.target.type, "name": b.target.name,
            "structureId": b.structureId, "restoreTo": b.restoreTo,
            "announceLevel": b.announceLevel, "seconds": seconds,
        ]
    }

    static func decode(_ info: [AnyHashable: Any]?) -> (VolumeBoost, Double)? {
        guard let i = info, let id = i["id"] as? String, let type = i["type"] as? String,
              let structureId = i["structureId"] as? String,
              let restoreTo = (i["restoreTo"] as? NSNumber)?.intValue,
              let level = (i["announceLevel"] as? NSNumber)?.intValue else { return nil }
        let target = SpeakerDevice(id: id, type: type, name: (i["name"] as? String) ?? id)
        let seconds = min(max((i["seconds"] as? NSNumber)?.doubleValue ?? 0, 0), 180)
        return (VolumeBoost(target: target, structureId: structureId, restoreTo: restoreTo, announceLevel: level), seconds)
    }

    @MainActor public static func listen(with coordinator: VolumeRestoreCoordinator) -> NSObjectProtocol {
        inProcess = coordinator
        return DistributedNotificationCenter.default().addObserver(
            forName: notificationName, object: nil, queue: .main
        ) { note in
            guard let (boost, seconds) = decode(note.userInfo) else { return }
            Task { @MainActor in coordinator.schedule(boost, after: seconds) }
        }
    }
}
