// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Run the production intro sequence, its close rules and its completion
/// writes against isolated preferences, a hand-drained queue and an app shell
/// that only notes which windows it was asked for. No window is created.
enum UpdateIntroFlowTests {
    typealias Intro = UpdateIntroSequence.Intro

    final class IntroShell {
        let defaults: Foundation.UserDefaults
        var version: String
        var isTerminating = false
        var windows: Set<Intro> = []
        var shown: [String] = []
        var cleanups = 0
        var later: [@MainActor () -> Void] = []
        private(set) lazy var sequence = UpdateIntroSequence(host: .init(
            defaults: defaults,
            version: { [unowned self] in self.version },
            isBeta: { [unowned self] in AppInfo.isPrerelease(self.version) },
            isTerminating: { [unowned self] in self.isTerminating },
            open: { [unowned self] intro in
                guard self.windows.insert(intro).inserted else { return false }
                self.shown.append(IntroShell.name(intro))
                return true
            },
            cleanupShowcaseCache: { [unowned self] in self.cleanups += 1 },
            finish: { [unowned self] in self.shown.append("finished") },
            later: { [unowned self] work in self.later.append(work) }))

        init(_ defaults: Foundation.UserDefaults, version: String) {
            self.defaults = defaults
            self.version = version
        }

        static func name(_ intro: Intro) -> String {
            switch intro {
            case .highlights: return "tour"
            case .support: return "support"
            case .showcase: return "showcase"
            }
        }

        /// The window closing, as the app delegate reports it, and everything
        /// it queued. False when that window was not open or the queue loops.
        func close(_ intro: Intro) -> Bool {
            guard windows.remove(intro) != nil else { return false }
            sequence.closed(intro)
            for _ in 0..<20 where !later.isEmpty { later.removeFirst()() }
            return later.isEmpty
        }
    }

    static func run(_ suite: TestSuite) {
        // Vitruvian keeps upstream's support invitation off; exercise its flow
        // with it switched on, then check the default below.
        let offered = SupportUpdateIntroInfo.isOffered
        SupportUpdateIntroInfo.isOffered = true
        defer { SupportUpdateIntroInfo.isOffered = offered }
        let name = "vitru.tests.update-intros.\(UUID().uuidString)"
        let defaults = Foundation.UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        /// A fresh launch of `version`, with nothing seen yet.
        func reset(_ version: String) -> IntroShell {
            defaults.removePersistentDomain(forName: name)
            return IntroShell(defaults, version: version)
        }
        func close(_ intro: Intro, in shell: IntroShell) {
            suite.expect(shell.close(intro), "the \(IntroShell.name(intro)) is open, and closing it settles without a loop")
        }
        for version in ["3.4.0", "3.4.1", "3.4.2"] {
            for previous in [nil, "3.3.2", "3.4.0-beta.1"] as [String?] {
                let shell = reset(version)
                defaults.set(previous, forKey: DefaultsKey.updateHighlightsSeenVersion)
                // Older beta onboarding prematurely saved this value.
                defaults.set("3.4.0", forKey: DefaultsKey.supportUpdateIntroVersion)
                shell.sequence.present()
                suite.expect(shell.shown == ["tour"], "stable upgraders see the tour first")
                close(.highlights, in: shell)
                suite.expect(shell.shown == ["tour", "support"], "finishing the tour opens only support next")
                suite.expect(!shell.sequence.shouldCloseSupport(), "support waits for its Done action")
                shell.sequence.allowSupportToClose()
                suite.expect(shell.sequence.shouldCloseSupport(), "Done allows support to close")
                close(.support, in: shell)
                suite.expect(!shell.sequence.shouldCloseSupport(), "the next support page waits for Done again")
                for nextVersion in [version, "3.4.10", "3.4.11"] {
                    let relaunch = IntroShell(defaults, version: nextVersion)
                    relaunch.sequence.present()
                    suite.expect(relaunch.shown == ["finished"], "completed intros never repeat on relaunch or later hotfixes")
                }
            }
        }
        let beta = reset("3.4.0-beta.7")
        beta.sequence.markOnboardingComplete()
        suite.expect(defaults.string(forKey: DefaultsKey.supportUpdateIntroVersion) == nil
                     && defaults.bool(forKey: DefaultsKey.hasOnboarded)
                     && defaults.integer(forKey: DefaultsKey.featuresOnboardingVersion) == OnboardingInfo.currentFeatureSet
                     && defaults.string(forKey: DefaultsKey.lastUpdateIntroVersion) == "3.4.0-beta.7"
                     && defaults.string(forKey: DefaultsKey.brightnessUpdatePromptState) == BrightnessUpdatePromptInfo.handled,
                     "beta onboarding marks the first run done but cannot consume the future stable support screen")
        let upgraded = IntroShell(defaults, version: "3.4.2")
        upgraded.sequence.present()
        close(.highlights, in: upgraded)
        suite.expect(upgraded.shown == ["tour", "support"], "a fresh beta install gets both intros on stable upgrade")
        let betaUpgrade = reset("3.4.0-beta.7")
        defaults.set("3.4.0-beta.1", forKey: DefaultsKey.updateHighlightsSeenVersion)
        betaUpgrade.sequence.present()
        betaUpgrade.sequence.showSupport()
        suite.expect(betaUpgrade.shown == ["finished"],
                     "a beta that has seen its tour asks for neither the support page nor the showcase")

        for version in ["3.4.0-beta.7", "3.4.0", "3.4.1"] {
            let shell = reset(version)
            for _ in 0..<3 {
                let before = defaults.persistentDomain(forName: name) ?? [:]
                shell.sequence.showHighlights(isReview: true)
                close(.highlights, in: shell)
                suite.expect(shell.sequence.supportIsReview, "manual review includes support even on beta or later releases")
                close(.support, in: shell)
                suite.expect(shell.shown.suffix(2) == ["tour", "support"] && !shell.sequence.supportIsReview,
                             "review ends after the support page")
                suite.expect(NSDictionary(dictionary: before).isEqual(to: defaults.persistentDomain(forName: name) ?? [:]),
                             "manual review never consumes automatic launch markers")
            }
        }
        let twice = reset("3.4.0")
        twice.sequence.showHighlights(isReview: true)
        twice.sequence.showHighlights()
        suite.expect(twice.shown == ["tour"] && twice.sequence.highlightsIsReview,
                     "asking for the tour while it is open keeps the one already showing")
        let reopened = reset("3.4.0")
        defaults.set(UpdateHighlightsInfo.seenVersion(for: "3.4.0"), forKey: DefaultsKey.updateHighlightsSeenVersion)
        reopened.sequence.present()
        reopened.sequence.showSupport(isReview: true)
        suite.expect(reopened.shown == ["support"] && !reopened.sequence.supportIsReview,
                     "asking for the support page while it is open keeps the one already showing")
        let deferred = reset("3.4.0")
        deferred.sequence.present()
        deferred.windows.remove(.highlights)
        deferred.sequence.closed(.highlights)
        suite.expect(deferred.shown == ["tour"] && deferred.later.count == 1,
                     "the next intro waits for the closing window to finish closing")
        for version in ["3.4.0", "3.4.1", "3.4.2"] {
            let clean = reset(version)
            clean.sequence.markOnboardingComplete()
            let hotfix = IntroShell(defaults, version: "3.4.10")
            hotfix.sequence.present()
            suite.expect(hotfix.shown == ["finished"], "fresh stable onboarding does not repeat introductions after a hotfix")
        }
        let partial = reset("3.4.0")
        partial.sequence.present()
        close(.highlights, in: partial)
        partial.isTerminating = true
        suite.expect(partial.sequence.shouldCloseSupport(), "quitting may close the support page without Done")
        close(.support, in: partial)
        let resumed = IntroShell(defaults, version: "3.4.1")
        resumed.sequence.present()
        suite.expect(resumed.shown == ["support"], "a hotfix resumes only the unfinished support page")
        close(.support, in: resumed)
        let completed = IntroShell(defaults, version: "3.4.2")
        completed.sequence.present()
        suite.expect(completed.shown == ["finished"], "finishing the remaining page prevents later repeats")
        let interrupted = reset("3.4.0")
        interrupted.sequence.present()
        interrupted.isTerminating = true
        close(.highlights, in: interrupted)
        suite.expect(defaults.string(forKey: DefaultsKey.updateHighlightsSeenVersion) == nil
                     && interrupted.shown == ["tour"],
                     "quitting during the tour does not consume it or open the next")
        let quittingReview = reset("3.4.0-beta.7")
        quittingReview.sequence.showHighlights(isReview: true)
        quittingReview.isTerminating = true
        close(.highlights, in: quittingReview)
        suite.expect(quittingReview.shown == ["tour"], "quitting during review never opens another window")
        quittingReview.sequence.showSupport(isReview: true)
        suite.expect(quittingReview.shown == ["tour"], "nothing opens while the app quits")

        // The showcase belongs to its own release, and shows once.
        let showcase = reset(UpdateShowcaseInfo.releaseVersion)
        showcase.sequence.present()
        suite.expect(showcase.shown == ["showcase"] && showcase.cleanups == 0, "the release's own version gets its showcase")
        close(.showcase, in: showcase)
        suite.expect(showcase.shown == ["showcase", "finished"]
                     && defaults.string(forKey: DefaultsKey.updateShowcaseIntroVersion) == UpdateShowcaseInfo.releaseVersion,
                     "closing the showcase marks it seen and moves on")
        let again = IntroShell(defaults, version: UpdateShowcaseInfo.releaseVersion)
        again.sequence.present()
        let later = IntroShell(defaults, version: "3.1.5")
        later.sequence.present()
        suite.expect(again.shown == ["finished"] && again.cleanups == 1
                     && later.shown == ["finished"] && later.cleanups == 1,
                     "a seen showcase, or another version, only clears its cached media")
        let quitShowcase = reset(UpdateShowcaseInfo.releaseVersion)
        quitShowcase.sequence.present()
        quitShowcase.isTerminating = true
        close(.showcase, in: quitShowcase)
        suite.expect(defaults.string(forKey: DefaultsKey.updateShowcaseIntroVersion) == nil,
                     "quitting during the showcase does not consume it")
        let onboarded = reset(UpdateShowcaseInfo.releaseVersion)
        onboarded.sequence.markOnboardingComplete()
        suite.expect(defaults.string(forKey: DefaultsKey.updateShowcaseIntroVersion) == UpdateShowcaseInfo.releaseVersion
                     && defaults.string(forKey: DefaultsKey.supportUpdateIntroVersion) == nil,
                     "onboarding on the showcase's release counts as seeing it, and not another release's support page")
        let supportRelease = reset(SupportUpdateIntroInfo.releaseVersion)
        supportRelease.sequence.markOnboardingComplete()
        suite.expect(defaults.string(forKey: DefaultsKey.supportUpdateIntroVersion) == SupportUpdateIntroInfo.seenVersion
                     && defaults.string(forKey: DefaultsKey.updateShowcaseIntroVersion) == nil,
                     "onboarding on the support page's release counts as seeing it")

        SupportUpdateIntroInfo.isOffered = offered
        suite.expect(!SupportUpdateIntroInfo.isOffered, "Vitruvian ships without upstream's support invitation")
        let unoffered = reset("3.4.0")
        unoffered.sequence.present()
        close(.highlights, in: unoffered)
        unoffered.sequence.showSupport(isReview: true)
        suite.expect(!unoffered.windows.contains(.support) && !unoffered.shown.contains("support"),
                     "without community channels a stable upgrade never opens the support page")
    }
}
