// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Opening the player from the island's cover or the radial Now Playing card
/// runs as shipped against doubles that never activate, unhide or launch an
/// app. Both are non-activating panels, so Vitruvian rarely holds activation
/// of its own, and a bare request left the player where it was.
enum NowPlayingOpenContract {
    /// What opening asked for, in order. Only the test's thread touches it.
    final class Record {
        var events: [String] = []
    }

    static func run(_ suite: TestSuite) {
        let track = RadialNowPlayingSnapshot(title: "Track", artist: nil, album: nil, artworkData: nil,
                                             appBundleIdentifier: "org.example.player", appPID: 20)
        let record = Record()
        let bundle = URL(fileURLWithPath: "/Applications/Player.app")
        func player(isHidden: Bool = false, policy: NSApplication.ActivationPolicy = .regular,
                    cooperative: Bool = true) -> RadialNowPlayingApplication.OpenablePlayer {
            .init(pid: 20, activationPolicy: policy, isHidden: isHidden, bundleURL: bundle,
                  unhide: { record.events.append("unhide:20") },
                  yieldActivation: { record.events.append("yield:20") },
                  activateFromVitruvian: {
                      record.events.append("activate:20:\($0.contains(.activateAllWindows))")
                      return cooperative
                  },
                  activate: { record.events.append("fallback:20:\($0.contains(.activateAllWindows))") })
        }
        func open(_ running: RadialNowPlayingApplication.OpenablePlayer?, installedAt url: URL? = nil,
                  window: Bool = true) {
            record.events = []
            RadialNowPlayingApplication.open(track, using: .init(
                player: { _ in running },
                hasWindowOnScreen: { _ in window },
                installedURL: { $0 == "org.example.player" ? url : nil },
                openApplication: { url, configuration in
                    // A reopen shows a window without taking activation from the handoff.
                    let quiet = !configuration.activates && !configuration.addsToRecentItems
                        && !configuration.promptsUserIfNeeded
                    record.events.append("\(quiet ? "reopen" : "launch"):\(url.lastPathComponent)")
                }))
        }
        open(player())
        suite.expect(record.events == ["yield:20", "activate:20:true"],
                     "the cover hands Vitruvian's activation to the player before asking for all its windows")
        open(player(cooperative: false))
        suite.expect(record.events == ["yield:20", "activate:20:true", "fallback:20:true"],
                     "a refused cooperative request still falls back to a direct one")
        open(player(isHidden: true))
        suite.expect(record.events == ["unhide:20", "yield:20", "activate:20:true"],
                     "a hidden player is shown before it is activated")
        for policy in [NSApplication.ActivationPolicy.accessory, .prohibited] {
            open(player(policy: policy), installedAt: bundle)
            suite.expect(record.events.isEmpty,
                         "a helper that takes no activation leaves Vitruvian inactive and launches nothing")
        }
        open(player(), window: false)
        suite.expect(record.events == ["yield:20", "activate:20:true", "reopen:Player.app"],
                     "a player playing with its window closed shows one again, like a Dock click")
        open(player(isHidden: true), window: false)
        suite.expect(record.events == ["unhide:20", "yield:20", "activate:20:true"],
                     "a hidden player's own windows come back with it, so no reopen is sent")
        open(nil, installedAt: bundle)
        suite.expect(record.events == ["launch:Player.app"], "a player that has quit opens again from its bundle")
        open(nil)
        suite.expect(record.events.isEmpty, "a player that is neither running nor installed is left alone")
    }
}
