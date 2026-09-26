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

// The one place an announcement is decided and sent, for every caller: the
// CLI (`--say`, and `--announce` for the Stop hook), the chat monitor and
// Quick Announce. It applies docs/local-speech.md's rules in order.

/// What happened to one output.
public enum OutputStatus: Equatable, Sendable {
    /// Not selected in the settings.
    case off
    case spoken
    case failed(String)

    public var didSpeak: Bool { self == .spoken }
}

/// The result of one announcement, reporting each output separately.
public enum AnnounceOutcome: Equatable, Sendable {
    /// Rule 1: broadcasting is switched off.
    case disabled
    /// Rule 2: quiet hours; `until` is the configured end ("07:00").
    case quietHours(until: String)
    /// Rule 3: both outputs are off.
    case noOutputs
    /// The text cleaned down to nothing.
    case nothingToSay
    case announced(home: OutputStatus, local: OutputStatus)

    public static let noOutputsMessage = "No outputs selected (home speakers and this Mac are both off)"

    public var anySpoke: Bool {
        guard case .announced(let home, let local) = self else { return false }
        return home.didSpeak || local.didSpeak
    }

    /// Where it was heard, for the history list: "Lake Office + This Mac".
    public func spokenLabel(homeName: String) -> String {
        guard case .announced(let home, let local) = self else { return "" }
        var parts: [String] = []
        if home.didSpeak { parts.append(homeName) }
        if local.didSpeak { parts.append("This Mac") }
        return parts.joined(separator: " + ")
    }

    /// One line per failed output. Named only when both were selected, so
    /// a home-only failure reads exactly as it did before local speech.
    public var failureMessages: [String] {
        guard case .announced(let home, let local) = self else { return [] }
        let both = home != .off && local != .off
        var out: [String] = []
        if case .failed(let why) = home { out.append(both ? "Home speakers: \(why)" : why) }
        if case .failed(let why) = local { out.append(both ? "This Mac: \(why)" : why) }
        return out
    }
}

// MARK: - What the announcer drives (protocols so tests make no sound)

public protocol HomeBroadcasting: Sendable {
    func broadcast(
        text: String, target: SpeakerDevice, structureId: String,
        config: SpeakerConfig?, force: Bool, at date: Date
    ) async throws -> Bool
}

extension GoogleHomeClient: HomeBroadcasting {}

public protocol LocalSpeaking: Sendable {
    func speak(_ text: String, voiceID: String) async throws
}

extension LocalSpeaker: LocalSpeaking {}

public protocol MediaPausing: Sendable {
    func pause(seconds: Double) async
    func extend(seconds: Double) async
    func resumeNow() async
}

/// The real pause: the menu bar app's coordinator, in process or over a
/// distributed notification.
public struct SharedMediaPause: MediaPausing {
    public init() {}
    public func pause(seconds: Double) async { await MediaPauseRequest.pause(seconds: seconds) }
    public func extend(seconds: Double) async { await MediaPauseRequest.extend(seconds: seconds) }
    public func resumeNow() async { await MediaPauseRequest.resumeNow() }
}

// MARK: - The announcer

public struct Announcer: Sendable {
    public static let shared = Announcer()

    let home: HomeBroadcasting
    let local: LocalSpeaking
    let media: MediaPausing

    public init(
        home: HomeBroadcasting = GoogleHomeClient.shared,
        local: LocalSpeaking = LocalSpeaker.shared,
        media: MediaPausing = SharedMediaPause()
    ) {
        self.home = home
        self.local = local
        self.media = media
    }

    /// Speaks `text` wherever `config` says. Returns once every selected
    /// output is done -- for this Mac, once it has finished speaking.
    /// `force` is a deliberate human action (Quick Announce, `--say`): it
    /// overrides quiet hours, never the master switch.
    public func announce(_ text: String, config: SpeakerConfig, force: Bool, at date: Date = Date()) async -> AnnounceOutcome {
        // 1. The master switch.
        guard config.enabled else { return .disabled }
        // 2. Quiet hours hold both outputs.
        if GoogleHomeClient.isSuppressedByQuietHours(config: config, force: force, at: date) {
            return .quietHours(until: config.quietHoursEnd ?? "")
        }
        // 3. Nowhere to speak.
        let wantHome = config.effectiveSpeakHome
        let wantLocal = config.effectiveSpeakLocal
        guard wantHome || wantLocal else { return .noOutputs }
        // 7. One cleaning for both outputs.
        let spoken = GoogleHomeClient.cleanForSpeech(text, length: config.effectiveSpeechLength)
        guard !spoken.isEmpty else { return .nothingToSay }

        // Home only: exactly the path that existed before local speech,
        // pause-media and all, so an older config behaves as it always did.
        guard wantLocal else {
            return .announced(home: await sendHome(text, config: config, force: force, at: date), local: .off)
        }

        // 4. Pause once, for the longer of the two.
        let pausing = config.effectivePauseMedia
        let extra = config.effectivePauseMediaExtraSeconds
        if pausing {
            var hold = LocalSpeaker.estimatedSeconds(for: spoken) + extra
            if wantHome { hold = max(hold, AnnouncementTiming.seconds(for: spoken, extra: extra)) }
            await media.pause(seconds: hold)
        }
        // The home broadcast must not pause a second time.
        let homeConfig: SpeakerConfig = {
            var c = config
            c.pauseMedia = false
            return c
        }()

        // 6. Both at once; neither can stop the other.
        async let homeStatus: OutputStatus = wantHome
            ? sendHome(text, config: homeConfig, force: force, at: date) : .off
        async let localStatus: OutputStatus = speakHere(spoken, voiceID: config.effectiveLocalVoice)
        let (h, l) = await (homeStatus, localStatus)

        if pausing {
            if !h.didSpeak && !l.didSpeak {
                await media.resumeNow()
            } else if l.didSpeak {
                // The Mac has just finished: stay paused `extra` beyond that,
                // or longer if the home estimate still runs.
                await media.extend(seconds: extra)
            }
        }
        return .announced(home: h, local: l)
    }

    /// 5. The home speakers, with `announce_volume` applied inside `broadcast`.
    private func sendHome(_ text: String, config: SpeakerConfig, force: Bool, at date: Date) async -> OutputStatus {
        guard let target = config.defaultDevice, !config.structureId.isEmpty else {
            return .failed(BroadcastError.noSpeaker.errorDescription ?? "No speaker selected.")
        }
        do {
            let sent = try await home.broadcast(
                text: text, target: target, structureId: config.structureId, config: config, force: force, at: date)
            return sent ? .spoken : .failed("Nothing to say after cleaning up the text.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// This Mac, at its own current volume.
    private func speakHere(_ spoken: String, voiceID: String) async -> OutputStatus {
        do {
            try await local.speak(spoken, voiceID: voiceID)
            return .spoken
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
