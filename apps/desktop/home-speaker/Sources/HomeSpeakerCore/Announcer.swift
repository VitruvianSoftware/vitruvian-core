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
import os

// The one place an announcement is decided and sent, for every caller: the
// CLI (`--say`, and `--announce` for the Stop hook), the chat monitor and
// Quick Announce. It applies docs/local-speech.md's rules in order.

/// What happened to one output.
public enum OutputStatus: Equatable, Sendable {
    /// Not selected in the settings.
    case off
    case spoken
    /// Held by a condition on the target (e.g., phone headphones-only mode with no headphones connected).
    case skipped(String)
    case failed(String)

    public var didSpeak: Bool { self == .spoken }
    public var isSkipped: Bool {
        if case .skipped = self { return true }
        return false
    }
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
    case announced(home: OutputStatus, local: OutputStatus, phone: OutputStatus = .off)

    public static let noOutputsMessage = "No outputs selected (home speakers and this Mac are both off)"

    public var anySpoke: Bool {
        guard case .announced(let home, let local, let phone) = self else { return false }
        return home.didSpeak || local.didSpeak || phone.didSpeak
    }

    public var anySkipped: Bool {
        guard case .announced(let home, let local, let phone) = self else { return false }
        return home.isSkipped || local.isSkipped || phone.isSkipped
    }

    /// Where it was heard, for the history list: "Lake Office + This Mac".
    public func spokenLabel(homeName: String) -> String {
        guard case .announced(let home, let local, let phone) = self else { return "" }
        var parts: [String] = []
        if home.didSpeak { parts.append(homeName) }
        if local.didSpeak { parts.append("This Mac") }
        if phone.didSpeak { parts.append("This phone") }
        return parts.joined(separator: " + ")
    }

    /// Heard on this Mac while the home speaker failed: said in one line,
    /// so a caller that shows only what was spoken (the Vitruvian tool
    /// shows `--say`'s output) still says the speaker did not play it.
    public static func spokeLocallyHomeFailed(_ why: String) -> String {
        "Spoke on this Mac (Home speaker failed: \(why))"
    }

    /// What `HomeSpeaker --say` prints for what was heard, a line an
    /// output. Failures alone go to standard error, as `failureMessages`.
    public func spokenLines(homeName: String) -> [String] {
        guard case .announced(let home, let local, let phone) = self else { return [] }
        var lines: [String] = []
        if home.didSpeak { lines.append("sent to \(homeName)") }
        if local.didSpeak {
            if case .failed(let why) = home {
                lines.append(Self.spokeLocallyHomeFailed(why))
            } else {
                lines.append("spoke on this Mac")
            }
        }
        if phone.didSpeak {
            if case .failed(let why) = home, !local.didSpeak {
                lines.append("Spoke on this phone (Home speaker failed: \(why))")
            } else {
                lines.append("sent to this phone")
            }
        } else if case .skipped(let why) = phone {
            lines.append("skipped on this phone (\(why))")
        }
        return lines
    }

    /// One line per failed output. Named only when more than one output was
    /// selected, so a single-output failure reads without a prefix.
    public var failureMessages: [String] {
        guard case .announced(let home, let local, let phone) = self else { return [] }
        let named = [home, local, phone].filter { $0 != .off }.count > 1
        var out: [String] = []
        if case .failed(let why) = home { out.append(named ? "Home speakers: \(why)" : why) }
        if case .failed(let why) = local { out.append(named ? "This Mac: \(why)" : why) }
        if case .failed(let why) = phone { out.append(named ? "This phone: \(why)" : why) }
        return out
    }
}

// MARK: - What the announcer drives (protocols so tests make no sound)

public protocol HomeBroadcasting: Sendable {
    /// How many seconds the physical home speaker continues speaking after
    /// `broadcast` returns `true` (`0` for in-memory test stand-ins).
    func speakerHoldSeconds(for text: String) -> TimeInterval
    func broadcast(
        text: String, target: SpeakerDevice, structureId: String,
        config: SpeakerConfig?, force: Bool, at date: Date
    ) async throws -> Bool
}

extension HomeBroadcasting {
    public func speakerHoldSeconds(for text: String) -> TimeInterval { 0 }
}

extension GoogleHomeClient: HomeBroadcasting {
    public nonisolated func speakerHoldSeconds(for text: String) -> TimeInterval {
        session === URLSession.shared ? AnnouncementTiming.seconds(for: text, extra: 0) : 0
    }
}

public protocol LocalSpeaking: Sendable {
    func speak(_ text: String, voiceID: String) async throws
}

extension LocalSpeaker: LocalSpeaking {}

public protocol MediaPausing: Sendable {
    func pause(seconds: Double) async
    func pause(seconds: Double, id: String?) async
    func extend(seconds: Double) async
    func extend(seconds: Double, id: String?) async
    func resumeNow() async
    func resumeNow(id: String?) async
    /// Returns once a pause this process holds itself is over; at once
    /// when the long-lived process holds it, or nothing is held. A
    /// short-lived `--say` waits on it before it exits.
    func waitUntilReleased() async
}

extension MediaPausing {
    public func pause(seconds: Double, id: String?) async { await pause(seconds: seconds) }
    public func extend(seconds: Double, id: String?) async { await extend(seconds: seconds) }
    public func resumeNow(id: String?) async { await resumeNow() }
    public func waitUntilReleased() async {}
}

/// The real pause: the long-lived process's coordinator (the menu bar
/// app's, or the extension's), in process or over a distributed
/// notification under `profile`'s names. A nil profile is the process's
/// (`HomeSpeakerProfile.current`), read at each call.
public struct SharedMediaPause: MediaPausing {
    public let profile: HomeSpeakerProfile?
    public init(profile: HomeSpeakerProfile? = nil) { self.profile = profile }
    private var messages: HomeSpeakerProfile { profile ?? .current }
    public func pause(seconds: Double) async { await MediaPauseRequest.pause(seconds: seconds, profile: messages) }
    public func pause(seconds: Double, id: String?) async { await MediaPauseRequest.pause(seconds: seconds, id: id, profile: messages) }
    public func extend(seconds: Double) async { await MediaPauseRequest.extend(seconds: seconds, profile: messages) }
    public func extend(seconds: Double, id: String?) async { await MediaPauseRequest.extend(seconds: seconds, id: id, profile: messages) }
    public func resumeNow() async { await MediaPauseRequest.resumeNow(profile: messages) }
    public func resumeNow(id: String?) async { await MediaPauseRequest.resumeNow(id: id, profile: messages) }
    public func waitUntilReleased() async { await MediaPauseRequest.waitForOwnHold(profile: messages) }
}

// MARK: - The announcer

public struct Announcer: Sendable {
    public static let shared = Announcer(speechLockURL: SpeechLock.defaultURL)

    public static let logger = Logger(subsystem: "com.vitruviansoftware.homespeaker", category: "announcer")

    let home: HomeBroadcasting
    let local: LocalSpeaking
    let phone: PhoneSpeaking
    let media: MediaPausing
    /// Speaks on this Mac when `local_engine` is Gemini.
    let gemini: GeminiSpeaking
    /// Words a coding agent's reply in `announcement_style`.
    let stylist: AnnouncementStyling
    /// The saved Gemini API key, read at each announcement.
    let geminiKey: @Sendable () -> String?
    /// Cross-process lock file held while speaking so concurrent announcements
    /// wait in FIFO order instead of talking over each other.
    let speechLockURL: URL?
    let log: @Sendable (String) -> Void

    public init(
        home: HomeBroadcasting = GoogleHomeClient.shared,
        local: LocalSpeaking = LocalSpeaker.shared,
        phone: PhoneSpeaking = PhoneSpeaker.shared,
        media: MediaPausing = SharedMediaPause(),
        gemini: GeminiSpeaking = GeminiSpeaker(cache: .shared),
        stylist: AnnouncementStyling? = nil,
        geminiKey: @escaping @Sendable () -> String? = { SecretStore.shared.load().geminiApiKey },
        speechLockURL: URL? = nil,
        log: @escaping @Sendable (String) -> Void = { Announcer.logger.notice("\($0, privacy: .public)") }
    ) {
        self.home = home
        self.local = local
        self.phone = phone
        self.media = media
        self.gemini = gemini
        self.stylist = stylist ?? AnnouncementStylist(geminiKey: geminiKey)
        self.geminiKey = geminiKey
        self.speechLockURL = speechLockURL
        self.log = log
    }

    /// Speaks `text` wherever `config` says. Returns once every selected
    /// output is done -- for this Mac, once it has finished speaking.
    /// `force` is a deliberate human action (Quick Announce, `--say`): it
    /// overrides quiet hours, never the master switch.
    ///
    /// `restyle` words it in `announcement_style` first: a coding agent's
    /// reply (`--announce`). Chat messages, Quick Announce and `--say` are
    /// someone's own words and are read as written.
    public func announce(
        _ text: String, config: SpeakerConfig, force: Bool, restyle: Bool = false, at date: Date = Date()
    ) async -> AnnounceOutcome {
        await announceReporting(text, config: config, force: force, restyle: restyle, at: date).outcome
    }

    /// `announce`, also saying the words spoken (nil when nothing was
    /// meant to be), for a history that lists what was heard rather than
    /// the reply it was made from.
    public func announceReporting(
        _ text: String, config: SpeakerConfig, force: Bool, restyle: Bool = false, at date: Date = Date()
    ) async -> (outcome: AnnounceOutcome, spoken: String?) {
        // 1. The master switch.
        guard config.enabled else { return (.disabled, nil) }
        // 2. Quiet hours hold both outputs.
        if GoogleHomeClient.isSuppressedByQuietHours(config: config, force: force, at: date) {
            return (.quietHours(until: config.quietHoursEnd ?? ""), nil)
        }
        // 3. Nowhere to speak.
        let wantHome = config.effectiveSpeakHome
        let wantLocal = config.effectiveSpeakLocal
        let wantPhone = config.effectiveSpeakPhone
        guard wantHome || wantLocal || wantPhone else { return (.noOutputs, nil) }
        // 7. One cleaning (and, for an agent's reply, one rewording) for
        // both outputs.
        let styled = restyle && AnnouncementStylist.rewrites(config)
        let spoken = styled
            ? await stylist.style(text, config: config)
            : GoogleHomeClient.cleanForSpeech(text, length: config.effectiveSpeechLength)
        guard !spoken.isEmpty else { return (.nothingToSay, nil) }
        // The speaker cleans again; reworded text goes as it was reworded.
        let homeText = styled ? spoken : text

        let homeSpeakerHold = home.speakerHoldSeconds(for: spoken)

        return await SpeechLock.withLockReportingCooldown(at: speechLockURL) {
            // Home only: exactly the path that existed before local speech,
            // pause-media and all, so an older config behaves as it always did.
            guard wantLocal || wantPhone else {
                let h = await sendHome(homeText, config: config, force: force, at: date)
                let cooldown = h.didSpeak && homeSpeakerHold > 0 ? Date().addingTimeInterval(homeSpeakerHold) : nil
                return ((.announced(home: h, local: .off, phone: .off), spoken), cooldown)
            }

            // 4. Pause once on this Mac when a Mac/Home output speaks.
            let pausing = config.effectivePauseMedia && (wantHome || wantLocal)
            let extra = config.effectivePauseMediaExtraSeconds
            let holdID = UUID().uuidString
            if pausing {
                var hold = LocalSpeaker.estimatedSeconds(for: spoken) + extra
                if wantHome { hold = max(hold, AnnouncementTiming.seconds(for: spoken, extra: extra)) }
                await media.pause(seconds: hold, id: holdID)
            }
            // The home broadcast must not pause a second time.
            let homeConfig: SpeakerConfig = {
                var c = config
                c.pauseMedia = false
                return c
            }()

            // Start a shared Gemini synthesis task when the phone needs it, so
            // Home speakers start immediately without waiting for Gemini, and
            // both This phone (via WAV payload) and This Mac (via GeminiAudioCache)
            // share a single synthesis request.
            let geminiKeyTrimmed = geminiKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sharedPhoneWavTask: Task<Data?, Error>? = (wantPhone && config.effectiveLocalEngine == .gemini && !geminiKeyTrimmed.isEmpty)
                ? Task { [gemini, spoken, voice = config.effectiveGeminiVoice] in
                    try await gemini.synthesizeWAV(spoken, voice: voice, apiKey: geminiKeyTrimmed)
                }
                : nil

            // 6. All selected outputs at once; none can stop the others. Once
            // Google has accepted the broadcast the speaker starts: hold its
            // full time from then, not from before the network calls.
            let homeHold = AnnouncementTiming.seconds(for: spoken, extra: extra)
            let media = self.media
            async let homeResult: (status: OutputStatus, cooldownUntil: Date?) = {
                guard wantHome else { return (.off, nil) }
                let status = await sendHome(homeText, config: homeConfig, force: force, at: date)
                if pausing, status.didSpeak { await media.extend(seconds: homeHold, id: holdID) }
                let cooldown = status.didSpeak && homeSpeakerHold > 0 ? Date().addingTimeInterval(homeSpeakerHold) : nil
                return (status, cooldown)
            }()
            async let localStatus: OutputStatus = {
                guard wantLocal else { return .off }
                if let sharedPhoneWavTask {
                    do {
                        _ = try await sharedPhoneWavTask.value
                    } catch {
                        log("Gemini voice failed (\(error.localizedDescription)); speaking in the Mac voice.")
                        return await speakMacVoice(spoken, config: config)
                    }
                }
                return await speakHere(spoken, config: config, hold: pausing ? (id: holdID, extra: extra) : nil)
            }()
            async let phoneStatus: OutputStatus = {
                guard wantPhone else { return .off }
                var wavForPhone: Data?
                if let sharedPhoneWavTask {
                    do {
                        wavForPhone = try await sharedPhoneWavTask.value
                    } catch {
                        if !wantLocal {
                            log("Gemini voice failed (\(error.localizedDescription)); using phone voice.")
                        }
                    }
                }
                return await sendPhone(spoken, wav: wavForPhone, config: config)
            }()
            let (homeOut, l, p) = await (homeResult, localStatus, phoneStatus)
            let h = homeOut.status

            if pausing {
                if !h.didSpeak && !l.didSpeak && !p.didSpeak {
                    await media.resumeNow(id: holdID)
                } else if l.didSpeak || p.didSpeak {
                    // The Mac or phone has just finished: stay paused `extra` beyond that,
                    // or longer if the home estimate still runs.
                    await media.extend(seconds: extra, id: holdID)
                }
            }
            return ((.announced(home: h, local: l, phone: p), spoken), homeOut.cooldownUntil)
        }
    }

    private func sendPhone(_ text: String, wav: Data?, config: SpeakerConfig) async -> OutputStatus {
        do {
            switch try await phone.speak(
                text,
                wav: wav,
                pauseMedia: config.effectivePhonePauseMedia,
                headphonesOnly: config.effectivePhoneHeadphonesOnly
            ) {
            case .spoken:
                return .spoken
            case .skipped(let why):
                return .skipped(why)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
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

    /// This Mac, at its own current volume: in the Gemini voice when that
    /// is chosen and works, otherwise in the Mac voice, so this Mac is never
    /// silent for want of a key or a network.
    ///
    /// `hold` is the media pause this announcement holds. Gemini takes a few
    /// seconds to answer before anything plays, which the hold, estimated
    /// for the speech alone, does not cover: while it waits the hold is kept
    /// alive a second at a time, and once the audio's length is known it
    /// is held for exactly that.
    private func speakHere(_ spoken: String, config: SpeakerConfig, hold: (id: String, extra: Double)?) async -> OutputStatus {
        if config.effectiveLocalEngine == .gemini {
            let key = geminiKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if key.isEmpty {
                log("Gemini voice: no Gemini API key saved; speaking in the Mac voice.")
            } else {
                let media = self.media
                let keepAlive: Task<Void, Never>? = hold.map { hold in
                    Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(1))
                            if Task.isCancelled { break }
                            await media.extend(seconds: hold.extra + 2, id: hold.id)
                        }
                    }
                }
                defer { keepAlive?.cancel() }
                do {
                    try await gemini.speak(spoken, voice: config.effectiveGeminiVoice, apiKey: key) { seconds in
                        keepAlive?.cancel()
                        if let hold { await media.extend(seconds: seconds + hold.extra, id: hold.id) }
                    }
                    return .spoken
                } catch {
                    log("Gemini voice failed (\(error.localizedDescription)); speaking in the Mac voice.")
                }
            }
        }
        return await speakMacVoice(spoken, config: config)
    }

    private func speakMacVoice(_ spoken: String, config: SpeakerConfig) async -> OutputStatus {
        do {
            try await local.speak(spoken, voiceID: config.effectiveLocalVoice)
            return .spoken
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
