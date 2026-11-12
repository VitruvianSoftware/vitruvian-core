// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Foundation
import SwiftUI
import VitruvianCore
import VitruvianServices
import VitruvianUI

/// What assistive technology hears of a tool's status mark. The closed
/// island hides what it draws at rest and offers one button over it, so
/// the mark is said by that button's name: here the island names it, on
/// the module's island (`NotchIslandFixture`), and the shipped window gives
/// that name to the one element VoiceOver reaches.
extension NotchPresentationRefreshContract {
    static func restingStatusChecks(_ suite: TestSuite) {
        let open = FeatureStrings.notch(L10n.shared.language).open
        let collapse = FeatureStrings.notch(L10n.shared.language).collapse
        let before = defaults.string(forKey: DefaultsKey.notchIdleContent)
        let agentsBefore = defaults.object(forKey: DefaultsKey.notchAgentsEnabled)
        defer {
            defaults.set(before, forKey: DefaultsKey.notchIdleContent)
            defaults.set(agentsBefore, forKey: DefaultsKey.notchAgentsEnabled)
        }
        // The Agents page is opt-in, and the wings show it only when it is on.
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        defaults.set(NotchIdleContent.agents.rawValue, forKey: DefaultsKey.notchIdleContent)

        let fixture = island()
        let service = fixture.island
        suite.expect(service.idleContent == .agents && fixture.host?.activationTitle == open,
                     "with no status mark the closed island's button has its own name and no more")

        fixture.restingStatus = "Deploys: Failed"
        service.restingStatusChanged()
        suite.expect(fixture.host?.activationTitle == RestingStatus.buttonTitle(open, saying: "Deploys: Failed",
                                                                                 language: L10n.shared.language)
                         && fixture.host?.activationTitle.contains("Deploys: Failed") == true,
                     "a tool's status mark on the closed island is said by the island's button, the one element VoiceOver reaches")

        let presents = fixture.host?.presents
        service.restingStatusChanged()
        suite.expect(fixture.host?.presents == presents, "a status that says the same does not present the island again")

        fixture.restingStatus = "Deploys: main is red"
        fixture.restingStatusChanges.send()
        // The island reads the change a turn of the main queue later; a
        // busy runner can take longer than any fixed pause, so wait for it.
        let heard = Date(timeIntervalSinceNow: 2)
        while fixture.host?.activationTitle.hasSuffix("Deploys: main is red") != true, Date() < heard {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        suite.expect(fixture.host?.activationTitle.hasSuffix("Deploys: main is red") == true,
                     "the island hears a status change by itself and names its button again")

        service.open()
        suite.expect(fixture.host?.activationTitle == collapse, "the open island's button says how to close it, as before")
        service.collapse()
        suite.expect(fixture.host?.activationTitle.hasSuffix("Deploys: main is red") == true,
                     "closed again, the button says the mark again")

        runTimer(fixture)
        service.refreshPresentation(animated: false)
        suite.expect(service.compactActivity != nil && fixture.host?.activationTitle == open,
                     "an activity's strip takes the wings' place, the mark is not drawn, and the button does not say it")
        fixture.services.timerSession = NotchTimerSession()
        service.refreshPresentation(animated: false)

        defaults.set(NotchIdleContent.battery.rawValue, forKey: DefaultsKey.notchIdleContent)
        service.refreshPresentation(animated: false)
        suite.expect(service.idleContent == .battery && fixture.host?.activationTitle == open,
                     "an island that rests with the charge draws no mark, and its button does not say one")
        defaults.set(NotchIdleContent.agents.rawValue, forKey: DefaultsKey.notchIdleContent)

        fixture.restingStatus = nil
        service.refreshPresentation(animated: false)
        suite.expect(fixture.host?.activationTitle == open, "a status that is cleared is no longer said")

        shippedButtonChecks(suite)
    }

    /// The shipped window, never ordered in: the name the island gives is
    /// the accessibility label of the one button in it, and that button
    /// gives assistive technology an element to reach.
    private static func shippedButtonChecks(_ suite: TestSuite) {
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 32,
                                     cameraWidth: 210, menuBarHeight: 32, silhouette: .notch)
        let size = geometry.collapsed
        let host = NotchWindowHost(content: AnyView(Color.clear), geometry: geometry, size: size)
        defer { host.close() }
        host.setActivationArea(CGRect(origin: .zero, size: size), title: "Open Dynamic Island, Deploys: Failed",
                               willPress: {}, activate: {})
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? [] + view.subviews.flatMap(buttons(in:))
        }
        let all = host.panel.contentView.map(buttons(in:)) ?? []
        let button = all.first { $0.accessibilityIdentifier() == "notch.activation" }
        suite.expect(all.count == 1 && button != nil, "the closed island's window holds one button")
        // AppKit serves a button through its cell, the element assistive
        // technology reaches, and names it with the label set on the button:
        // on screen that element reads "Open Dynamic Island" today.
        let element = button.flatMap { NSAccessibility.unignoredDescendant(of: $0) as? NSObject & NSAccessibilityProtocol }
        suite.expect(button?.accessibilityLabel() == "Open Dynamic Island, Deploys: Failed" && button?.isHidden == false
                         && element?.isAccessibilityElement() == true && element?.accessibilityRole() == .button,
                     "the name the island gives, the mark's words in it, is the accessibility label of that button")
    }
}
