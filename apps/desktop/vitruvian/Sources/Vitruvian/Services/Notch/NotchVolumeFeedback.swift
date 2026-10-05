// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Combine
import Foundation
import VitruvianCore

/// The island's volume notice. It follows the system output's level and
/// mute, stays silent for a new output's first reading and, while the island
/// is open, for the island's own controls, and shows a level set elsewhere
/// when asked. `NotchService` owns it; tests pass an output and an island of
/// their own.
@MainActor
package final class NotchVolumeFeedback {
    /// The system output as the notice reads it. `system` is the app's mixer.
    @MainActor
    package struct Output {
        package var volume: () -> Double?
        package var muted: () -> Bool?
        package var deviceUID: () -> String?
        /// The device at each published change of level, mute or device. The
        /// level and mute are read again once the change has settled.
        package var changes: () -> AnyPublisher<String?, Never>

        package init(volume: @escaping () -> Double?, muted: @escaping () -> Bool?,
                     deviceUID: @escaping () -> String?, changes: @escaping () -> AnyPublisher<String?, Never>) {
            self.volume = volume
            self.muted = muted
            self.deviceUID = deviceUID
            self.changes = changes
        }

        package static var system: Output {
            Output(volume: { AppVolumeMixer.shared.systemOutputVolume },
                   muted: { AppVolumeMixer.shared.systemOutputMuted },
                   deviceUID: { AppVolumeMixer.shared.currentOutputDeviceUID },
                   changes: {
                       let mixer = AppVolumeMixer.shared
                       return mixer.$systemOutputVolume
                           .combineLatest(mixer.$systemOutputMuted, mixer.$currentOutputDeviceUID)
                           .map { $0.2 }
                           .eraseToAnyPublisher()
                   })
        }
    }

    /// What the notice asks of the island.
    @MainActor
    package struct Island {
        package var isExpanded: () -> Bool
        /// Shows a notice, or answers false when the island cannot.
        package var show: (NotchNotice) -> Bool
        package var uptime: () -> TimeInterval

        package init(isExpanded: @escaping () -> Bool, show: @escaping (NotchNotice) -> Bool,
                     uptime: @escaping () -> TimeInterval) {
            self.isExpanded = isExpanded
            self.show = show
            self.uptime = uptime
        }
    }

    private let output: Output
    private let island: Island
    private var deviceUID: String?
    private var volumeBaseline: Double?
    private var muteBaseline: Bool?
    /// System uptime until which an output change counts as the island's own.
    private var ownAdjustmentUntil: TimeInterval = 0

    package init(output: Output, island: Island) {
        self.output = output
        self.island = island
    }

    /// Follows the output from its current reading, which shows nothing, for
    /// as long as the returned subscription is kept.
    package func follow() -> AnyCancellable {
        deviceUID = output.deviceUID()
        volumeBaseline = output.volume()
        muteBaseline = output.muted()
        let output = output
        return output.changes()
            .handleEvents(receiveOutput: { [weak self] deviceUID in
                guard let self, deviceUID != self.deviceUID else { return }
                self.deviceUID = deviceUID
                self.volumeBaseline = nil
                self.muteBaseline = nil
            })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Published fields arrive separately and before assignment. Read
                // the settled device and controls together on the main queue.
                self?.volumeChanged(output.volume(), muted: output.muted())
            }
    }

    /// A volume key shows the level even when it did not change.
    package func showCurrentVolume() {
        guard let volume = output.volume() else { return }
        showVolume(volume, muted: output.muted())
    }

    /// The island's own output controls already show the level they set.
    /// Their changes, and the device's reading that follows, leave the open
    /// header's title in place instead of covering it with the same level.
    package func noteOwnAdjustment() {
        ownAdjustmentUntil = island.uptime() + 1
    }

    /// Levels set outside the island, like Command Bar's, report here
    /// too. The observer skips a level that matches the current one and a new
    /// output's first reading. False leaves the confirmation to the caller.
    @discardableResult
    package func showVolume(_ volume: Double, muted: Bool? = nil) -> Bool {
        guard volume.isFinite else { return false }
        let value = muted == true ? 0 : min(1, max(0, volume))
        return island.show(NotchNotice(event: .volume, title: FeatureStrings.notch(L10n.shared.language).volume,
                                       detail: "\(Int((value * 100).rounded()))%",
                                       symbol: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                       level: value))
    }

    private func volumeChanged(_ volume: Double?, muted: Bool?) {
        defer { volumeBaseline = volume; muteBaseline = muted }
        guard deviceUID != nil, let volume, volumeBaseline != nil,
              volume != volumeBaseline || (muteBaseline != nil && muted != muteBaseline) else { return }
        // Volume keys still announce themselves through showCurrentVolume.
        guard !island.isExpanded() || island.uptime() >= ownAdjustmentUntil else { return }
        showVolume(volume, muted: muted)
    }
}
