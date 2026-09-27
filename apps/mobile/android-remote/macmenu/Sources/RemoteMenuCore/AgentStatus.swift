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

/// What `GET /healthz` returns. Only the fields the menu shows; unknown keys
/// are ignored so a newer agent never breaks an older menu.
public struct AgentHealth: Decodable, Equatable, Sendable {
    public struct Notify: Decodable, Equatable, Sendable {
        public var configured: Bool
        public var enabled: Bool

        public init(configured: Bool, enabled: Bool) {
            self.configured = configured
            self.enabled = enabled
        }
    }

    public var ok: Bool
    public var agentVersion: String?
    public var paired: Bool
    public var sampleAgeMs: Int?
    public var notify: Notify?

    public init(ok: Bool, agentVersion: String? = nil, paired: Bool, sampleAgeMs: Int? = nil, notify: Notify? = nil) {
        self.ok = ok
        self.agentVersion = agentVersion
        self.paired = paired
        self.sampleAgeMs = sampleAgeMs
        self.notify = notify
    }

    enum CodingKeys: String, CodingKey {
        case ok, paired, notify
        case agentVersion = "agent_version"
        case sampleAgeMs = "sample_age_ms"
    }
}

/// What `GET /v1/phone` returns: whether a phone holds its link open now.
public struct PhoneLink: Decodable, Equatable, Sendable {
    public struct Device: Decodable, Equatable, Sendable {
        public var model: String?
        public var android: String?
    }

    public var connected: Bool
    public var device: Device?
    public var since: String?
}

/// The agent as the menu sees it. `stale` is the agent answering while its
/// readings are old (it replies 503 then): alive, but not healthy.
public enum AgentState: Equatable, Sendable {
    case notInstalled
    case down
    case stale(version: String?)
    case running(version: String?)

    public var isHealthy: Bool {
        if case .running = self { return true }
        return false
    }
}

/// One poll's worth of facts, and the lines the menu prints for them. Kept
/// free of AppKit so every wording and every state is unit-tested.
public struct StatusSnapshot: Equatable, Sendable {
    public var state: AgentState
    public var health: AgentHealth?
    public var phone: PhoneLink?
    /// Whether the agent answers on this Mac's Tailscale address, the one the
    /// phone uses. Nil when not checked (agent down, or no Tailscale here).
    public var tailnetReachable: Bool?

    public init(state: AgentState, health: AgentHealth? = nil, phone: PhoneLink? = nil, tailnetReachable: Bool? = nil) {
        self.state = state
        self.health = health
        self.phone = phone
        self.tailnetReachable = tailnetReachable
    }

    /// Said only when it is a problem: the agent runs, but the phone can't
    /// reach it, so pairing and every phone feature are dead.
    public var tailnetLine: String? {
        tailnetReachable == false ? "Phone can't reach it over Tailscale" : nil
    }

    /// Decide the state from what the probe saw. `status` is the HTTP code, or
    /// nil when nothing answered on the port at all.
    public static func classify(installed: Bool, status: Int?, health: AgentHealth?) -> AgentState {
        guard let status else { return installed ? .down : .notInstalled }
        if status == 200, health?.ok == true { return .running(version: health?.agentVersion) }
        return .stale(version: health?.agentVersion)
    }

    public var agentLine: String {
        switch state {
        case .notInstalled: return "Agent not installed"
        case .down: return "Agent not responding"
        case .stale(let v): return "Agent running, readings stale" + versionSuffix(v)
        case .running(let v): return "Agent running" + versionSuffix(v)
        }
    }

    /// Nil while the agent is down: the menu must not claim anything about a
    /// phone it cannot ask about.
    public func phoneLine(now: Date = Date()) -> String? {
        switch state {
        case .notInstalled, .down: return nil
        default: break
        }
        if let phone, phone.connected {
            let name = phone.device?.model.flatMap { $0.isEmpty ? nil : $0 } ?? "Phone"
            if let since = phone.since.flatMap(Self.parseDate) {
                return "\(name) connected since \(Self.clock(since))"
            }
            return "\(name) connected"
        }
        if health?.paired == true { return "Phone paired, not connected" }
        return "No phone paired"
    }

    public var notificationsLine: String? {
        guard let notify = health?.notify else { return nil }
        if !notify.configured { return "Push notifications not set up" }
        return notify.enabled ? "Push notifications on" : "Push notifications off"
    }

    private func versionSuffix(_ v: String?) -> String {
        guard let v, !v.isEmpty else { return "" }
        return " · v\(v)"
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = Calendar.current.isDateInToday(d) ? .none : .short
        return f.string(from: d)
    }
}

/// The phone shows a six-digit code; people type it with spaces or a dash.
public enum PairCode {
    public static func normalize(_ raw: String) -> String? {
        let digits = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return digits
    }
}

/// Where the agent's install script puts things. Fixed paths, mirrored from
/// macagent/install.sh; paths_match_installer_test fails if the two drift.
public struct AgentPaths: Sendable {
    public static let label = "com.vitruvian.remote-agent"
    public static let baseURL = URL(string: "http://127.0.0.1:7411")!
    public static let installCommand = "bazel run //apps/mobile/android-remote/macagent:install"

    public var home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var binary: URL { home.appendingPathComponent(".local/bin/vitruvian-remote-agent") }
    public var log: URL { home.appendingPathComponent("Library/Logs/vitruvian-remote-agent.log") }

    /// `launchctl kickstart -k` restarts the job in place, keeping its plist
    /// and flags, which is what "Restart" should mean.
    public static func restartArguments(uid: uid_t) -> [String] {
        ["kickstart", "-k", "gui/\(uid)/\(label)"]
    }
}
