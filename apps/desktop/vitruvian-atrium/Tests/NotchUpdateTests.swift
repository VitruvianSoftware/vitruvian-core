// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The island's update action and the module's own update control. No
/// network, download, visible window, screenshot or input event is used.
enum NotchUpdateTests {
    static func run(_ suite: TestSuite) {
        let states: [UpdateService.State] = [.idle, .checking, .upToDate, .failed("offline"),
            .available(version: "3.4.0"), .available(version: "3.4.0-beta.3"),
            .downloading(progress: nil), .downloading(progress: 0.5), .installing]
        for state in states {
            let offered: Bool
            if case .available = state { offered = true } else { offered = false }
            suite.expect(state.isOffer == offered, "only an available version is an offer (\(state))")
            for running in [false, true] {
                for suspended in [false, true] {
                    for expanded in [false, true] {
                        let opens = NotchService.opensUpdatePreview(offered: state.isOffer, running: running,
                                                                    suspended: suspended, expanded: expanded)
                        suite.expect(opens == (running && !suspended && expanded && offered),
                                     "only a current offer in the open, running island can open release notes")
                    }
                }
            }
        }
        let offer = UpdateService.State.available(version: "3.4.0-beta.3").isOffer
        suite.expect(!NotchService.opensUpdatePreview(offered: offer, running: true, suspended: false, expanded: false),
                     "an update cannot open or activate the resting island")
        suite.expect(NotchService.opensUpdatePreview(offered: offer, running: true, suspended: false, expanded: true),
                     "opening the island makes the existing offer actionable")
        layout(suite)
    }

    private static func layout(_ suite: TestSuite) {
        // The compact control shares the narrowest wing beside the camera
        // with the header menu. The menu, its indicator and the spacing
        // between them take 44 points.
        let wing = narrowestCameraWing()
        suite.expect(wing.isFinite && wing > 44, "some island layout places the header beside the camera")
        let samples: [UpdateService.State] = [.available(version: "3.4.0-beta.3"),
                                             .available(version: "3.4.0"), .downloading(progress: nil),
                                             .downloading(progress: 0.63), .installing]
        let originalLanguage = L10n.shared.language
        defer { L10n.shared.language = originalLanguage }
        for language in AppLanguage.allCases {
            L10n.shared.language = language
            for state in samples {
                for compact in [false, true] {
                    let host = NSHostingView(rootView: NotchUpdateBadge(state: state, action: {}, compact: compact)
                        .environment(\.colorScheme, .dark))
                    host.layoutSubtreeIfNeeded()
                    let size = host.fittingSize
                    let maximumWidth: CGFloat = compact ? wing - 44 : 150
                    suite.expect(size.width.isFinite && size.width > 0 && size.width <= maximumWidth
                           && size.height > 0 && size.height <= NotchLayout.headerHeight,
                           "\(language.rawValue) update action and progress fit the \(compact ? "camera wing" : "full header") budget (\(size))")
                }
            }
        }
    }

    /// The narrowest trailing wing any preset or custom width leaves beside a
    /// camera, read from the geometry instead of assumed.
    private static func narrowestCameraWing() -> CGFloat {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let widths = stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 1)
        var narrowest = CGFloat.infinity
        for camera: CGFloat in [180, 185, 210, 240] {
            for layout in NotchSize.allCases {
                for width in widths {
                    let geometry = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: camera,
                                                 layout: layout, customWidth: width)
                    guard geometry.headerCameraGap > 0 else { continue }
                    narrowest = min(narrowest, (geometry.contentWidth - geometry.headerCameraGap) / 2)
                }
            }
        }
        return narrowest
    }
}
