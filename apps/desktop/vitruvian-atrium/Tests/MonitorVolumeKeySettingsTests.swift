// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import CoreGraphics
import Foundation
import VitruvianAtriumCore
import VitruvianAtriumServices

/// The step, floor and ceiling of the monitor volume keys: each press the
/// key handler builds from `MonitorVolumeKeySettings`, run through the
/// production speaker transaction against a scripted monitor, and the
/// production service reading the settings when a key's turn comes.
enum MonitorVolumeKeySettingsTests {
    private typealias Speakers = DisplaySpeakerVolumeTests.ScriptedSpeakers
    private typealias Rig = BrightnessRig

    /// One press as the key handler queues it.
    private static func press(_ direction: Int, fine: Bool = false,
                              _ settings: MonitorVolumeKeySettings) -> BrightnessSupport.SpeakerChange {
        .step(levels: [{ settings.requestedLevel(from: $0, direction: direction, fine: fine) }],
              raises: direction > 0)
    }

    static func run(_ suite: TestSuite) {
        transactionChecks(suite)
        serviceChecks(suite)
        preferenceChecks(suite)
    }

    private static func transactionChecks(_ suite: TestSuite) {
        let onePercent = MonitorVolumeKeySettings(stepPercent: 1, maximumPercent: 5)
        let limits = MonitorVolumeKeySettings(stepPercent: 10, minimumPercent: 20, maximumPercent: 70)

        var speakers = Speakers(raw: 2, muted: false)
        speakers.apply(press(-1, onePercent), settings: onePercent)
        suite.expect(speakers.writes == ["volume:1"], "a quiet monitor goes from two to one percent")
        speakers = Speakers(raw: 0, muted: false)
        speakers.apply(press(-1, onePercent), settings: onePercent)
        suite.expect(speakers.writes == ["mute:on"], "down at zero can still silence native speakers")
        speakers = Speakers(raw: 2, maximum: 0, muted: false)
        suite.expect(speakers.apply(press(-1, onePercent), settings: onePercent) == nil && speakers.writes.isEmpty,
                     "a missing range cannot seed a key or report a write")

        speakers = Speakers(raw: 2, muted: false)
        speakers.apply(press(1, onePercent), settings: onePercent)
        speakers.apply(press(1, onePercent), settings: onePercent)
        speakers.apply(.toggleMute, settings: onePercent)
        suite.expect(speakers.writes == ["volume:3", "volume:4", "mute:on"] && speakers.muted == true,
                     "one-percent presses step one unit each, and a later mute still mutes")

        speakers = Speakers(raw: 2, muted: false)
        let below = speakers.apply(press(-1, limits), settings: limits)
        suite.expect(speakers.writes.isEmpty && speakers.raw == 2 && below?.level.raw == 2,
                     "down below the floor cannot turn the volume up")
        speakers.apply(press(1, fine: true, limits), settings: limits)
        suite.expect(speakers.writes == ["volume:3"], "a fine raise below the floor still moves just one percent")
        speakers = Speakers(raw: 40, muted: false)
        speakers.apply(press(1, limits), settings: limits)
        suite.expect(speakers.writes == ["volume:50"], "a plain key uses the configured ten-percent grid")
        let twoPercent = MonitorVolumeKeySettings(stepPercent: 2)
        speakers = Speakers(raw: 29, muted: false)
        speakers.apply(press(-1, twoPercent), settings: twoPercent)
        suite.expect(speakers.writes == ["volume:28"], "an exact half-step on the monitor rejoins the nearest grid point")

        speakers = Speakers(raw: 1, maximum: 3, muted: false)
        speakers.apply(press(1, fine: true, limits), settings: limits)
        speakers.apply(press(1, limits), settings: limits)
        suite.expect(speakers.writes == ["volume:2"], "a coarse monitor moves one unit but cannot round past its ceiling")
        let narrow = MonitorVolumeKeySettings(stepPercent: 1, minimumPercent: 34, maximumPercent: 60)
        speakers = Speakers(raw: 1, maximum: 3, muted: false)
        speakers.apply(press(1, narrow), settings: narrow)
        speakers.apply(press(-1, narrow), settings: narrow)
        suite.expect(speakers.writes.isEmpty, "keys leave an unrepresentable range alone")

        speakers = Speakers(raw: 4, muted: false)
        speakers.apply(press(1, onePercent), settings: MonitorVolumeKeySettings(stepPercent: 1, maximumPercent: 3))
        suite.expect(speakers.writes.isEmpty, "a key at or above the ceiling leaves the monitor alone")
        speakers.apply(.set(volume: 0.8, muted: nil))
        suite.expect(speakers.raw == 80, "the explicit monitor slider still reaches its full range")

        speakers = Speakers(raw: 40, muted: true)
        speakers.apply(.toggleMute, settings: onePercent)
        suite.expect(speakers.writes == ["volume:5", "mute:off"] && speakers.muted == false,
                     "native unmute confirms the new ceiling before releasing mute")
        speakers = Speakers(raw: 40, muted: true)
        speakers.ignoresLevel = true
        suite.expect(speakers.apply(.toggleMute, settings: onePercent) == nil
                     && speakers.writes == ["volume:5"] && speakers.muted == true,
                     "an ignored level write cannot release mute at the old loud level")
        speakers = Speakers(raw: 40, muted: true)
        speakers.levelOnUnmute = 40
        suite.expect(speakers.apply(.toggleMute, settings: onePercent) == nil
                     && speakers.writes == ["volume:5", "mute:off", "mute:on"] && speakers.muted == true,
                     "a monitor that restores a loud level on native unmute is muted again after readback")
        let quiet = MonitorVolumeKeySettings(stepPercent: 1, minimumPercent: 3, maximumPercent: 5)
        speakers = Speakers(raw: 40, muted: nil)
        speakers.apply(.toggleMute, settings: quiet)
        speakers.apply(.toggleMute, settings: quiet)
        suite.expect(speakers.writes == ["volume:0", "volume:5"],
                     "volume-only mute can silence below the floor and restores at most the ceiling")
    }

    /// The production service reads the settings at each key's transaction:
    /// a ceiling lowered while the key waits, or while its write waits for
    /// the bus, stops the write.
    private static func serviceChecks(_ suite: TestSuite) {
        func makeDesk() -> (Rig.Desk, BrightnessService, Rig.Monitor, BrightnessSupport.SpeakerTarget?) {
            let desk = Rig.Desk()
            desk.defaults.set(true, forKey: DefaultsKey.displayVolumeEnabled)
            desk.defaults.set(true, forKey: DefaultsKey.displayVolumeKeysEnabled)
            desk.defaults.set(1.0, forKey: DefaultsKey.ddcVolumeStep)
            desk.defaults.set(5, forKey: DefaultsKey.ddcVolumeMaximum)
            let monitor = Rig.Monitor(current: 50)
            monitor.speakerLevel = 4
            monitor.speakerMuted = false
            desk.displays = [Rig.Display(id: 7, monitor: monitor)]
            desk.screenNames = [7: "Monitor A"]
            desk.soundOutput = BrightnessService.SoundOutput.Device(id: 31, name: "Monitor A",
                                                                     transport: kAudioDeviceTransportTypeHDMI)
            let service = BrightnessService(environment: desk.environment)
            service.start()
            service.syncSpeakers()
            desk.drain()
            return (desk, service, monitor, service.monitorSpeakerOutput()?.target)
        }
        func key(_ service: BrightnessService, _ target: BrightnessSupport.SpeakerTarget) {
            let settings = service.monitorVolumeKeySettings
            service.requestSpeakers(.step(levels: [{ settings.requestedLevel(from: $0, direction: 1, fine: false) }],
                                          raises: true), target: target, requiresKeys: true)
        }
        do {
            let (desk, service, monitor, target) = makeDesk()
            defer { desk.tearDown() }
            suite.expect(target != nil && service.monitorVolumeKeySettings
                            == MonitorVolumeKeySettings(stepPercent: 1, maximumPercent: 5),
                         "the service reads the key step and limits from the preferences")
            if let target {
                key(service, target)
                desk.drain()
                suite.expect(monitor.speakerWrites == ["volume:5"], "a key moves the monitor within its ceiling")
                key(service, target)
                desk.defaults.set(3, forKey: DefaultsKey.ddcVolumeMaximum)
                desk.drain()
                suite.expect(monitor.speakerWrites == ["volume:5"],
                             "the ceiling in effect at write time also protects an already queued key")
            }
        }
        do {
            let (desk, service, monitor, target) = makeDesk()
            defer { desk.tearDown() }
            if let target {
                desk.beforePause = {
                    desk.beforePause = nil
                    desk.defaults.set(3, forKey: DefaultsKey.ddcVolumeMaximum)
                }
                key(service, target)
                desk.drain()
                suite.expect(monitor.speakerWrites.isEmpty && monitor.speakerLevel == 4,
                             "a ceiling lowered after the key's settings were read cancels the paced write")
            } else {
                suite.expect(false, "the monitor carries the sound")
            }
        }
    }

    private static func preferenceChecks(_ suite: TestSuite) {
        let fallback = MonitorVolumeKeySettings(stepPercent: .nan, minimumPercent: -1, maximumPercent: 0)
        suite.expect(fallback.stepPercent == 6.25 && fallback.minimumPercent == 0 && fallback.maximumPercent == 100,
                     "invalid or missing preferences use the standard grid and full range")
        let domain = "vitru.tests.monitor-volume-keys.\(UUID().uuidString)"
        let preferences = ScratchDefaults.suite(named: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        suite.expect(MonitorVolumeKeySettings(in: preferences) == MonitorVolumeKeySettings(),
                     "unset preferences are the standard step and the full range")
        preferences.set(10.0, forKey: DefaultsKey.ddcVolumeStep)
        preferences.set(20, forKey: DefaultsKey.ddcVolumeMinimum)
        preferences.set(70, forKey: DefaultsKey.ddcVolumeMaximum)
        suite.expect(MonitorVolumeKeySettings(in: preferences)
                        == MonitorVolumeKeySettings(stepPercent: 10, minimumPercent: 20, maximumPercent: 70),
                     "the keys read the step and limits stored by the settings controls")
        for key in [DefaultsKey.ddcVolumeStep, DefaultsKey.ddcVolumeMinimum, DefaultsKey.ddcVolumeMaximum] {
            suite.expect(SettingsBackupSupport.exportKeys().contains(key), "monitor key setting travels in backup: \(key)")
        }
    }
}
