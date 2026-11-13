// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import CoreGraphics
import Foundation
import VitruvianAtriumCore
import VitruvianAtriumServices

/// The speakers built into a monitor: the pure rules in `BrightnessSupport`,
/// and the production `BrightnessService` discovering them, queueing changes
/// and routing the sound output, over a scripted desk whose monitor answers
/// the MCCS audio controls. No monitor or audio device is touched.
enum DisplaySpeakerVolumeTests {
    private typealias Rig = BrightnessRig
    private typealias Device = BrightnessService.SoundOutput.Device

    private static let id: CGDirectDisplayID = 7

    /// A started service with its speakers on, over one external monitor
    /// whose speakers sit at `level`. `muted` nil is a monitor without a
    /// mute control of its own.
    private static func desk(level: UInt16 = 40, maximum: UInt16 = 100, muted: Bool? = false,
                             keys: Bool = false)
        -> (Rig.Desk, BrightnessService, Rig.Display, Rig.Monitor) {
        let desk = Rig.Desk()
        desk.defaults.set(true, forKey: DefaultsKey.displayVolumeEnabled)
        desk.defaults.set(keys, forKey: DefaultsKey.displayVolumeKeysEnabled)
        let monitor = Rig.Monitor(current: 50)
        monitor.speakerLevel = level
        monitor.speakerMaximum = maximum
        monitor.speakerMuted = muted
        let display = Rig.Display(id: id, monitor: monitor)
        desk.displays = [display]
        desk.screenNames = [id: "Monitor A"]
        let service = BrightnessService(environment: desk.environment)
        service.start()
        desk.drain()
        return (desk, service, display, monitor)
    }

    private static func audio(_ service: BrightnessService) -> BrightnessDisplay.Audio? {
        service.displays.first { $0.id == id }?.audio
    }

    private static func near(_ value: Double?, _ expected: Double) -> Bool {
        value.map { abs($0 - expected) < 0.0001 } ?? false
    }

    /// A monitor's speakers for `applySpeakerChange`: every read and write the
    /// transaction makes, against a level, a range and an optional mute.
    final class ScriptedSpeakers {
        var raw: UInt16
        var maximum: UInt16 = 100
        var muted: Bool?
        var ignoresLevel = false
        var levelOnUnmute: UInt16?
        var writes: [String] = []
        var restore: BrightnessSupport.SpeakerLevel?

        init(raw: UInt16, maximum: UInt16 = 100, muted: Bool?) {
            self.raw = raw
            self.maximum = maximum
            self.muted = muted
        }

        @discardableResult
        func apply(_ change: BrightnessSupport.SpeakerChange,
                   settings: MonitorVolumeKeySettings = MonitorVolumeKeySettings())
            -> (level: BrightnessSupport.SpeakerLevel, muted: Bool?)? {
            BrightnessSupport.applySpeakerChange(change, hasNativeMute: muted != nil, keySettings: settings,
                restore: &restore,
                read: { code in
                    if code == BrightnessSupport.audioVolumeCode { return (self.raw, self.maximum) }
                    guard let muted = self.muted else { return nil }
                    return (muted ? BrightnessSupport.audioMutedValue : BrightnessSupport.audioUnmutedValue, 2)
                }, write: { code, value in
                    if code == BrightnessSupport.audioVolumeCode {
                        self.writes.append("volume:\(value)")
                        if !self.ignoresLevel { self.raw = value }
                    } else {
                        self.writes.append(value == BrightnessSupport.audioMutedValue ? "mute:on" : "mute:off")
                        self.muted = value == BrightnessSupport.audioMutedValue
                        if self.muted == false, let restored = self.levelOnUnmute { self.raw = restored }
                    }
                    return true
                })
        }
    }

    static func run(_ suite: TestSuite) {
        replyChecks(suite)
        keyChecks(suite)
        rememberedPathChecks(suite)
        transactionChecks(suite)
        discoveryChecks(suite)
        queueChecks(suite)
        routingChecks(suite)
        settingChecks(suite)
    }

    // MARK: - Pure rules

    private static func replyChecks(_ suite: TestSuite) {
        suite.expect(BrightnessSupport.audioReply(current: 50, maximum: 100) == 0.5
                     && BrightnessSupport.audioReply(current: 100, maximum: 100) == 1,
                     "a volume reply is read against its own maximum")
        suite.expect(BrightnessSupport.audioReply(current: 5, maximum: 0) == nil
                     && BrightnessSupport.audioReply(current: 255, maximum: 100) == nil,
                     "an empty or impossible range never becomes a usable volume")
        var rejected: [UInt8] = [0x6e, 0x88, 0x02, 0x01, 0x62, 0, 0, 100, 0, 80]
        rejected.append(rejected.reduce(UInt8(0x50)) { $0 ^ $1 })
        suite.expect(BrightnessSupport.parseReply(rejected, code: 0x62) == nil,
                     "an unsupported VCP reply cannot confirm a level even with a correct checksum")

        suite.expect(BrightnessSupport.muteReply(current: 1, maximum: 2) == true
                     && BrightnessSupport.muteReply(current: 2, maximum: 2) == false,
                     "only the two MCCS mute values read as muted or unmuted")
        suite.expect(BrightnessSupport.muteReply(current: 0, maximum: 2) == nil
                     && BrightnessSupport.muteReply(current: 3, maximum: 100) == nil
                     && BrightnessSupport.muteReply(current: 1, maximum: 1) == nil,
                     "any other mute value is not a mute control")
        suite.expect(BrightnessSupport.muteDeviceValue(true) == BrightnessSupport.audioMutedValue
                     && BrightnessSupport.muteDeviceValue(false) == BrightnessSupport.audioUnmutedValue,
                     "mute writes use the MCCS values")

        suite.expect(BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeHDMI)
                     && BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeDisplayPort)
                     && !BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeBuiltIn)
                     && !BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeBluetooth),
                     "only HDMI and DisplayPort outputs can belong to a monitor")
        suite.expect(BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeHDMI, outputHasSettableVolume: false)
                     && !BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeHDMI, outputHasSettableVolume: true)
                     && !BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeBuiltIn, outputHasSettableVolume: false),
                     "keys reach a monitor only when its output cannot take macOS volume")
        typealias Mute = BrightnessSupport
        suite.expect(Mute.monitorMuteChange(from: 0.0625, muted: false, to: 0, raises: false) == true
                     && Mute.monitorMuteChange(from: 0, muted: true, to: 0, raises: false) == nil,
                     "reaching zero mutes a monitor once, as macOS does for its own outputs")
        suite.expect(Mute.monitorMuteChange(from: 0, muted: false, to: 0.0625, raises: true) == false,
                     "leaving zero unmutes even when the last reading said unmuted, for monitors that mute themselves")
        suite.expect(Mute.monitorMuteChange(from: 0.4, muted: true, to: 0.5, raises: true) == false
                     && Mute.monitorMuteChange(from: 0.4, muted: true, to: 0.3, raises: false) == nil
                     && Mute.monitorMuteChange(from: 0.4, muted: false, to: 0.5, raises: true) == nil,
                     "a raise lifts a chosen mute, a lower leaves it, and an audible step writes no mute")
        suite.expect(Mute.monitorMuteChange(from: 0.0625, muted: nil, to: 0, raises: false) == nil
                     && Mute.monitorMuteChange(from: 0, muted: nil, to: 0.0625, raises: true) == nil,
                     "a monitor without an MCCS mute control never gets a mute write")
        let monitors: [(id: UInt32, name: String)] = [(2, "LG HDR 4K"), (3, "DELL U2720Q")]
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "DELL U2720Q",
                        candidates: monitors) == 3
                     && BrightnessSupport.displayForAudioOutput(deviceName: "dell u2720q",
                        candidates: monitors) == 3,
                     "the sound device is matched to its display by name, ignoring case")
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "LG HDR 4K Audio",
                        candidates: monitors) == 2,
                     "a device name that extends the display name still matches it")
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "MacBook Pro Speakers",
                        candidates: monitors) == nil
                     && BrightnessSupport.displayForAudioOutput(deviceName: "",
                        candidates: monitors) == nil,
                     "sound from another device or with no name never routes keys to a display")
        let identical: [(id: UInt32, name: String)] = [(2, "LG HDR"), (3, "LG HDR")]
        suite.expect(BrightnessSupport.displayForAudioOutput(deviceName: "LG HDR", candidates: identical) == nil
                     && BrightnessSupport.displayForAudioOutput(deviceName: "LG HDR Audio", candidates: identical) == nil
                     && BrightnessSupport.displayForAudioOutput(deviceName: "Receiver", candidates: [(2, "LG HDR")]) == nil,
                     "neither duplicate names nor an unrelated single monitor identify the selected output")
        suite.expect(BrightnessSupport.speakerService(for: 1, scores: [(1, 7, 2), (2, 7, 2)]) == nil
                     && BrightnessSupport.speakerService(for: 1, scores: [(1, 7, 2), (1, 8, 2)]) == nil
                     && BrightnessSupport.speakerService(for: 1, scores: [(1, 7, 10), (2, 7, 2)]) == 7,
                     "a speaker service needs a unique display and endpoint, while a matched connection is usable")
        var screen = BrightnessSupport.DisplayIdentity()
        screen.ioDisplayLocation = "port-a"
        screen.serialNumber = 5
        var endpointIdentity = BrightnessSupport.ServiceIdentity()
        endpointIdentity.ioDisplayLocation = "port-a"
        endpointIdentity.serialNumber = 6
        suite.expect(BrightnessSupport.matchScore(service: endpointIdentity, display: screen, requireIdentity: true) == 0
                     && BrightnessSupport.matchScore(service: endpointIdentity, display: screen) > 0,
                     "a conflicting serial on a reused port rules out audio without changing brightness assignment")
    }

    private static func keyChecks(_ suite: TestSuite) {
        func keyData(_ code: Int, state: Int, repeatBit: Int = 0) -> Int {
            (code << 16) | (state << 8) | repeatBit
        }
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(0, state: 10))
                        == BrightnessSupport.VolumeKeyEvent(action: .step(direction: 1),
                                                            isKeyDown: true, isRepeat: false),
                     "the volume-up key press parses as one step up")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(1, state: 11))
                        == BrightnessSupport.VolumeKeyEvent(action: .step(direction: -1),
                                                            isKeyDown: false, isRepeat: false),
                     "the volume-down key release parses as one step down")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(7, state: 10))
                        == BrightnessSupport.VolumeKeyEvent(action: .toggleMute,
                                                            isKeyDown: true, isRepeat: false),
                     "the mute key press parses as a mute toggle")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8,
                        data1: keyData(0, state: 10, repeatBit: 1))?.isRepeat == true,
                     "a held volume key is marked as a repeat")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(2, state: 10)) == nil
                     && BrightnessSupport.volumeKeyEvent(subtype: 7, data1: keyData(0, state: 10)) == nil
                     && BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(0, state: 7)) == nil,
                     "brightness keys, other subtypes and other states are never volume keys")

        let settings = MonitorVolumeKeySettings()
        suite.expect(settings.requestedLevel(from: 0, direction: 1, fine: false) == 1.0 / 16.0
                     && settings.requestedLevel(from: 0, direction: -1, fine: true) == -1.0 / 100.0,
                     "default monitor keys move one sixteenth, or one percent with Option and Shift")
        suite.expect(BrightnessSupport.volumeKeyFineness(option: true, shift: true,
                        commandOrControl: false) == true
                     && BrightnessSupport.volumeKeyFineness(option: false, shift: false,
                        commandOrControl: false) == false
                     && BrightnessSupport.volumeKeyFineness(option: true, shift: false,
                        commandOrControl: false) == nil
                     && BrightnessSupport.volumeKeyFineness(option: true, shift: true,
                        commandOrControl: true) == nil,
                     "Option+Shift is the fine step, Option alone and Command or Control stay with macOS")
        suite.expect(BrightnessSupport.steppedLevel(0.95, delta: 0.1) == 1
                     && BrightnessSupport.steppedLevel(0.05, delta: -0.1) == 0
                     && BrightnessSupport.steppedLevel(0.5, delta: 0.25) == 0.75,
                     "a volume step stays between silent and full")
    }

    private static func rememberedPathChecks(_ suite: TestSuite) {
        suite.expect(BrightnessSupport.updatedRememberedPaths(["a", "b"], path: "c",
                        remembered: true, limit: 2) == ["b", "c"]
                     && BrightnessSupport.updatedRememberedPaths(["a", "b"], path: "a",
                        remembered: false) == ["b"],
                     "a silent-speaker path is remembered newest and forgotten when it changes")
        suite.expect(!BrightnessSupport.shouldProbe(pathKey: "a", rememberedPaths: ["a"])
                     && BrightnessSupport.shouldProbe(pathKey: "b", rememberedPaths: ["a"])
                     && BrightnessSupport.shouldProbe(pathKey: nil, rememberedPaths: ["a"]),
                     "a remembered silent path is not probed again, and an unknown path always is")
        suite.expect(BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: true, recheckedPaths: [])
                     && !BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: true, recheckedPaths: ["a"])
                     && !BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: [])
                     && BrightnessSupport.shouldProbeLuminance(pathKey: "b", writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: [])
                     && BrightnessSupport.shouldProbeLuminance(pathKey: nil, writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: []),
                     "a remembered write-only path is read again once while speakers are wanted, then trusted")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: true, repliedThisSession: true) == 2
                     && BrightnessSupport.ddcRetryDelay(attempt: 2, probesAudio: true, repliedThisSession: true) == 5
                     && BrightnessSupport.ddcRetryDelay(attempt: 3, probesAudio: true, repliedThisSession: true) == 15,
                     "a monitor that answered before is read again after about 2, 5 and 15 seconds")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 4, probesAudio: true, repliedThisSession: true) == nil,
                     "the write-only answer stands once the third retry fails")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: false, repliedThisSession: true) == nil
                     && BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: true, repliedThisSession: false) == nil,
                     "a failed read is retried only while speakers are wanted and the monitor answered this session")
        suite.expect(BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 100, lastRescan: nil)
                     && !BrightnessSupport.rescansForVolumeKey(hasTarget: true, displayOwnsOutput: true,
                        now: 100, lastRescan: nil)
                     && !BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: false,
                        now: 100, lastRescan: nil),
                     "an unclaimed volume key rescans only while a monitor output has no target")
        suite.expect(!BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 109, lastRescan: 100)
                     && BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 110, lastRescan: 100),
                     "volume keys rescan at most once every 10 seconds")
        suite.expect(BrightnessSupport.needsAudioScan(wanted: true, scanned: false, queued: nil)
                     && !BrightnessSupport.needsAudioScan(wanted: true, scanned: false, queued: true)
                     && !BrightnessSupport.needsAudioScan(wanted: true, scanned: true, queued: nil)
                     && BrightnessSupport.needsAudioScan(wanted: false, scanned: true, queued: true)
                     && BrightnessSupport.needsAudioScan(wanted: false, scanned: false, queued: true)
                     && !BrightnessSupport.needsAudioScan(wanted: false, scanned: true, queued: false),
                     "a speaker scan is forced once per setting change, not again while one is queued")
    }

    /// `applySpeakerChange` against a scripted monitor: what a slider, a key
    /// or the mute button does to the speakers, read for read and write for
    /// write. Upstream checks these through its mixer stand-in; here they run
    /// on the production transaction directly.
    private static func transactionChecks(_ suite: TestSuite) {
        var speakers = ScriptedSpeakers(raw: 80, muted: true)
        var result = speakers.apply(.set(volume: 0.05, muted: nil))
        suite.expect(speakers.writes == ["volume:5", "mute:off"] && result?.level.raw == 5 && result?.muted == false,
                     "a verified low volume can safely lift a native mute")

        speakers = ScriptedSpeakers(raw: 80, muted: true)
        speakers.ignoresLevel = true
        result = speakers.apply(.step(levels: [{ _ in 0.05 }], raises: true))
        suite.expect(result == nil && speakers.writes == ["volume:5"] && speakers.raw == 80 && speakers.muted == true,
                     "an acknowledged-but-ignored level never unmutes the old high volume")

        speakers = ScriptedSpeakers(raw: 80, muted: true)
        speakers.levelOnUnmute = 80
        result = speakers.apply(.set(volume: 0.05, muted: nil))
        suite.expect(result == nil && speakers.writes == ["volume:5", "mute:off", "mute:on"] && speakers.muted == true,
                     "firmware that restores the old high level on unmute is muted again")

        speakers = ScriptedSpeakers(raw: 2, muted: nil)
        result = speakers.apply(.toggleMute)
        suite.expect(speakers.raw == 0 && result?.muted == true && result?.level.volume == 0,
                     "a volume-only monitor silences through its confirmed volume")
        result = speakers.apply(.toggleMute)
        suite.expect(speakers.writes == ["volume:0", "volume:2"] && result?.muted == false
                     && near(result?.level.volume, 0.02),
                     "software unmute restores exactly the last physical level read at mute time")

        speakers = ScriptedSpeakers(raw: 0, muted: nil)
        suite.expect(speakers.apply(.toggleMute) == nil && speakers.writes.isEmpty,
                     "zero without a known restore level cannot unmute to a guessed volume")
        result = speakers.apply(.step(levels: [{ $0 + 0.01 }], raises: true))
        suite.expect(speakers.raw == 1 && result?.level.raw == 1,
                     "a fine raise at zero remains available without a restore level")

        speakers = ScriptedSpeakers(raw: 2, muted: nil)
        _ = speakers.apply(.toggleMute)
        speakers.maximum = 20
        suite.expect(speakers.apply(.toggleMute) == nil && speakers.raw == 0 && speakers.writes.count == 1,
                     "a new device range cannot inherit the old raw restore value")

        speakers = ScriptedSpeakers(raw: 1, muted: false)
        speakers.maximum = 20
        _ = speakers.apply(.step(levels: [{ $0 + 0.01 }], raises: true))
        result = speakers.apply(.step(levels: [{ $0 + 0.01 }, { $0 + 0.01 }], raises: true))
        suite.expect(speakers.writes == ["volume:2", "volume:4"] && near(result?.level.volume, 0.2),
                     "each fine press advances one representable step and repeats share a confirmed write")

        let replaced = BrightnessSupport.SpeakerChange.set(volume: 0.7, muted: nil)
            .replacing(.set(volume: 0.5, muted: nil))
        var replacedVolume: Double?
        if case let .set(volume, _)? = replaced { replacedVolume = volume }
        suite.expect(replacedVolume == 0.7, "a newer slider level replaces one still waiting")
        suite.expect(BrightnessSupport.SpeakerChange.toggleMute.replacing(.toggleMute) == nil
                     && BrightnessSupport.SpeakerChange.step(levels: [{ $0 }], raises: false)
                        .replacing(.step(levels: [{ $0 }], raises: true)) == nil,
                     "a toggle or a change of direction keeps its place in the queue")
    }

    // MARK: - The production service

    private static func discoveryChecks(_ suite: TestSuite) {
        do {
            let (desk, service, display, _) = desk(level: 40, muted: false)
            defer { desk.tearDown() }
            let found = audio(service)
            suite.expect(near(found?.volume, 0.4) && found?.muted == false
                         && found?.target.displayID == id && found?.target.path == display.pathKey,
                         "a monitor that answers the audio controls gets its speakers' level and mute")
        }
        do {
            let (desk, service, _, _) = desk(level: 30, muted: nil)
            defer { desk.tearDown() }
            suite.expect(near(audio(service)?.volume, 0.3) && audio(service)?.muted == false,
                         "a monitor with volume but no mute control is still offered, unmuted while audible")
        }
        do {
            let (desk, service, display, _) = desk(level: 0, maximum: 0)
            defer { desk.tearDown() }
            suite.expect(audio(service) == nil
                         && desk.defaults.stringArray(forKey: DefaultsKey.displayAudioSilentPaths) == [display.pathKey],
                         "a monitor answering with an empty range has no speakers, and its connection is remembered")
        }
        do {
            let (desk, service, _, monitor) = desk(level: 255, maximum: 100)
            defer { desk.tearDown() }
            suite.expect(audio(service) == nil
                         && desk.defaults.stringArray(forKey: DefaultsKey.displayAudioSilentPaths) == nil
                         && monitor.speakerWrites.isEmpty,
                         "an impossible reading does not permanently classify a connection as silent")
        }
        do {
            let desk = Rig.Desk()
            defer { desk.tearDown() }
            let monitor = Rig.Monitor(current: 50)
            monitor.speakerLevel = 40
            monitor.speakerMuted = false
            desk.displays = [Rig.Display(id: id, monitor: monitor)]
            let service = BrightnessService(environment: desk.environment)
            service.start()
            desk.drain()
            suite.expect(audio(service) == nil && service.displays.count == 1,
                         "with the speaker setting off, no monitor is asked about its speakers")
            desk.defaults.set(true, forKey: DefaultsKey.displayVolumeEnabled)
            service.syncSpeakers()
            desk.drain()
            suite.expect(near(audio(service)?.volume, 0.4),
                         "switching the speakers on scans the monitors without a display change")
        }
    }

    private static func queueChecks(_ suite: TestSuite) {
        do {
            let (desk, service, _, monitor) = desk(level: 40, muted: false)
            defer { desk.tearDown() }
            guard let target = audio(service)?.target else {
                suite.expect(false, "the monitor's speakers are found")
                return
            }
            var done: Bool?
            service.requestSpeakers(.set(volume: 0.7, muted: nil), target: target) { done = $0 }
            suite.expect(done == nil && monitor.speakerWrites.isEmpty && near(audio(service)?.volume, 0.4),
                         "queueing a monitor change does not report a write or predict a level")
            desk.drain()
            suite.expect(done == true && monitor.speakerWrites == ["volume:70"] && near(audio(service)?.volume, 0.7),
                         "a panel slider writes the monitor and shows the level it read back")
        }
        do {
            let (desk, service, _, monitor) = desk(level: 80, muted: true)
            defer { desk.tearDown() }
            let target = audio(service)!.target
            var first: Bool?
            var last: Bool?
            monitor.onSpeakerWrite = {
                monitor.onSpeakerWrite = nil
                MainActor.assumeIsolated {
                    service.requestSpeakers(.set(volume: 0.05, muted: nil), target: target) { last = $0 }
                }
            }
            service.requestSpeakers(.set(volume: 0.7, muted: nil), target: target) { first = $0 }
            desk.drain()
            suite.expect(first == false && last == true
                         && monitor.speakerWrites == ["volume:70", "volume:5", "mute:off"]
                         && monitor.speakerMuted == false && near(audio(service)?.volume, 0.05),
                         "a superseded level cannot unmute while a lower slider setting waits for the bus")
        }
        do {
            let (desk, service, _, monitor) = desk(level: 1, maximum: 20, muted: false)
            defer { desk.tearDown() }
            let target = audio(service)!.target
            var results: [Bool] = []
            for _ in 0..<3 {
                service.requestSpeakers(.step(levels: [{ $0 + 0.01 }], raises: true), target: target) {
                    results.append($0)
                }
            }
            desk.drain()
            suite.expect(monitor.speakerWrites == ["volume:2", "volume:4"] && near(audio(service)?.volume, 0.2)
                         && results.count == 3 && results.filter { $0 }.count == 2,
                         "presses waiting behind one transaction share the next confirmed write")
        }
        do {
            let (desk, service, _, monitor) = desk()
            defer { desk.tearDown() }
            let target = audio(service)!.target
            service.requestSpeakers(.set(volume: 0.6, muted: nil), target: target)
            desk.defaults.set(false, forKey: DefaultsKey.displayVolumeEnabled)
            desk.drain()
            suite.expect(monitor.speakerWrites.isEmpty, "turning speakers off invalidates an already queued panel change")
        }
        do {
            let (desk, service, _, monitor) = desk()
            defer { desk.tearDown() }
            let target = audio(service)!.target
            var refused: Bool?
            service.requestSpeakers(.set(volume: 0.6, muted: nil), target: target, requiresKeys: true) { refused = $0 }
            desk.drain()
            suite.expect(refused == false && monitor.speakerWrites.isEmpty,
                         "a key change is refused while the volume keys are not given to the monitor")
        }
    }

    private static func routingChecks(_ suite: TestSuite) {
        let (desk, service, _, monitor) = desk(level: 40, muted: false, keys: true)
        defer { desk.tearDown() }
        let speakers = Device(id: 31, name: "Monitor A", transport: kAudioDeviceTransportTypeHDMI)
        desk.soundOutput = speakers
        service.syncSpeakers()
        desk.drain()
        let output = service.monitorSpeakerOutput()
        suite.expect(desk.isWatchingSoundOutput && output?.target.displayID == id && output?.target.deviceID == 31
                     && near(output?.volume, 0.4) && service.wantsMonitorVolumeKeys,
                     "sound leaving through the monitor's own cable points the volume keys at its speakers")

        desk.soundOutputSettable = true
        desk.playThrough(speakers)
        desk.drain()
        suite.expect(service.monitorSpeakerOutput() == nil,
                     "an output macOS can set keeps its own volume, even through a display cable")
        desk.soundOutputSettable = false
        desk.playThrough(Device(id: 40, name: "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn))
        desk.drain()
        suite.expect(service.monitorSpeakerOutput() == nil, "built-in speakers never route keys to a display")

        desk.playThrough(speakers)
        desk.drain()
        guard let keyTarget = service.monitorSpeakerOutput()?.target else {
            suite.expect(false, "the monitor carries the sound again")
            return
        }
        var keyResult: Bool?
        service.requestSpeakers(.step(levels: [{ $0 + 0.01 }], raises: true), target: keyTarget,
                                requiresKeys: true) { keyResult = $0 }
        desk.soundOutput = Device(id: 32, name: "Monitor A", transport: kAudioDeviceTransportTypeHDMI)
        desk.drain()
        suite.expect(keyResult == false && monitor.speakerWrites.isEmpty,
                     "a selected output change before queued work cannot transfer a key")

        desk.playThrough(speakers)
        desk.drain()
        service.requestSpeakers(.set(volume: 0.07, muted: nil), target: audio(service)!.target)
        desk.playThrough(Device(id: 32, name: "Other", transport: kAudioDeviceTransportTypeHDMI))
        desk.drain()
        suite.expect(monitor.speakerWrites == ["volume:7"],
                     "a display's own slider still addresses it when another output is selected")

        desk.playThrough(speakers)
        let namesake = Rig.Display(id: 8, monitor: Rig.Monitor(current: 50))
        desk.displays.append(namesake)
        desk.screenNames[8] = "Monitor A"
        service.refresh(force: true)
        desk.drain()
        suite.expect(service.monitorSpeakerOutput() == nil,
                     "a namesake without speakers of its own still makes key routing ambiguous")

        desk.defaults.set(false, forKey: DefaultsKey.displayVolumeEnabled)
        service.syncSpeakers()
        desk.drain()
        var refused: Bool?
        service.requestSpeakers(.set(volume: 1, muted: nil), target: keyTarget) { refused = $0 }
        suite.expect(audio(service) == nil && !desk.isWatchingSoundOutput && refused == false
                     && !service.wantsMonitorVolumeKeys,
                     "switching the speakers off drops what was found, stops watching the output and refuses changes")
    }

    private static func settingChecks(_ suite: TestSuite) {
        let monitor = BrightnessSupport.MonitorSpeakerOutput(
            target: BrightnessSupport.SpeakerTarget(displayID: id, path: "port-a"), volume: 0.4, muted: nil)
        let shown = AppVolumeMixer.presentedOutput(monitor: monitor, coreAudioVolume: 0.2, coreAudioMuted: false)
        let back = AppVolumeMixer.presentedOutput(monitor: nil, coreAudioVolume: 0.2, coreAudioMuted: false)
        suite.expect(shown.volume == 0.4 && shown.muted == nil && back.volume == 0.2 && back.muted == false,
                     "the mixer shows the monitor's level while it carries the sound, and CoreAudio's after")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.displayVolumeEnabled] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.displayVolumeKeysEnabled] as? Bool == false,
                     "speaker volume and its volume keys are off until enabled")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayVolumeEnabled)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayVolumeKeysEnabled),
                     "the speaker volume switches travel in a settings backup")
        suite.expect(SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.displayAudioSilentPaths)
                     && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayAudioSilentPaths),
                     "a monitor's silent-speaker memory stays on this Mac")
    }
}
