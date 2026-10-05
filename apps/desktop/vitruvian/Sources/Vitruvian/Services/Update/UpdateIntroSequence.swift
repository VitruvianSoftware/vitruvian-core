// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Which introduction an update shows next, what closing one means, and the
/// markers that keep each from coming back. The app shell owns the windows;
/// this decides when to ask for them.
@MainActor
package final class UpdateIntroSequence {
    package enum Intro: Hashable {
        /// The tour of this release's headline feature.
        case highlights
        /// The invitation to support the project.
        case support
        /// The release's showcase.
        case showcase
    }

    package struct Host {
        package var defaults: UserDefaults
        package var version: () -> String
        package var isBeta: () -> Bool
        package var isTerminating: () -> Bool
        /// Opens an intro's window, or brings an open one forward. True when
        /// it opened a new one. Its close comes back through `closed(_:)`.
        package var open: (Intro) -> Bool
        package var cleanupShowcaseCache: () -> Void
        /// The last stop: the brightness prompt, when it is still owed.
        package var finish: () -> Void
        /// Runs work on a later turn of the main queue.
        package var later: (@escaping @MainActor () -> Void) -> Void

        package init(defaults: UserDefaults, version: @escaping () -> String, isBeta: @escaping () -> Bool,
                     isTerminating: @escaping () -> Bool, open: @escaping (Intro) -> Bool,
                     cleanupShowcaseCache: @escaping () -> Void, finish: @escaping () -> Void,
                     later: @escaping (@escaping @MainActor () -> Void) -> Void) {
            self.defaults = defaults
            self.version = version
            self.isBeta = isBeta
            self.isTerminating = isTerminating
            self.open = open
            self.cleanupShowcaseCache = cleanupShowcaseCache
            self.finish = finish
            self.later = later
        }
    }

    private let host: Host
    /// The support page closes only from its Done action, or when quitting.
    package private(set) var supportCanClose = false
    package private(set) var supportIsReview = false
    package private(set) var highlightsIsReview = false

    package init(host: Host) {
        self.host = host
    }

    /// Beta updates only introduce their new feature; other update surfaces
    /// retain their own release gates.
    package func present() {
        if showHighlightsIfNeeded() { return }
        if !host.isBeta() {
            if showSupportIfNeeded() { return }
            if showShowcaseIfNeeded() { return }
        }
        host.finish()
    }

    package func showHighlights(isReview: Bool = false) {
        if host.open(.highlights) { highlightsIsReview = isReview }
    }

    package func showSupport(isReview: Bool = false) {
        guard SupportUpdateIntroInfo.isOffered else { return }
        guard !host.isTerminating(), isReview || !host.isBeta() else { return }
        if host.open(.support) {
            supportCanClose = false
            supportIsReview = isReview
        }
    }

    /// The support page's Done action.
    package func allowSupportToClose() {
        supportCanClose = true
    }

    package func shouldCloseSupport() -> Bool {
        supportCanClose || host.isTerminating()
    }

    /// An intro's window closed: record it as seen, unless it was a review or
    /// the app is quitting, and move on to the next.
    package func closed(_ intro: Intro) {
        switch intro {
        case .support:
            supportCanClose = false
            let isReview = supportIsReview
            supportIsReview = false
            guard !host.isTerminating(), !isReview else { return }
            markSupportSeen()
        case .showcase:
            guard !host.isTerminating() else { return }
            markShowcaseSeen()
        case .highlights:
            let isReview = highlightsIsReview
            highlightsIsReview = false
            guard !host.isTerminating() else { return }
            if isReview {
                host.later { [weak self] in self?.showSupport(isReview: true) }
                return
            }
            markHighlightsSeen()
        }
        host.later { [weak self] in self?.present() }
    }

    /// Marks both the first run and this version's feature tour as seen, so
    /// neither reappears on the next launch.
    package func markOnboardingComplete() {
        let defaults = host.defaults
        defaults.set(true, forKey: DefaultsKey.hasOnboarded)
        defaults.set(OnboardingInfo.currentFeatureSet, forKey: DefaultsKey.featuresOnboardingVersion)
        defaults.set(host.version(), forKey: DefaultsKey.lastUpdateIntroVersion)
        defaults.set(BrightnessUpdatePromptInfo.handled, forKey: DefaultsKey.brightnessUpdatePromptState)
        if SupportUpdateIntroInfo.matchesRelease(host.version()) { markSupportSeen() }
        if host.version() == UpdateShowcaseInfo.releaseVersion { markShowcaseSeen() }
        // A clean install that just saw everything in onboarding should not
        // then get the update tour; only people who updated get it.
        markHighlightsSeen()
    }

    package func markShowcaseSeen() {
        host.defaults.set(UpdateShowcaseInfo.releaseVersion, forKey: DefaultsKey.updateShowcaseIntroVersion)
    }

    private func showHighlightsIfNeeded() -> Bool {
        guard UpdateHighlightsInfo.shouldShow(
            appVersion: host.version(),
            lastSeenVersion: host.defaults.string(forKey: DefaultsKey.updateHighlightsSeenVersion)
        ) else { return false }
        showHighlights()
        return true
    }

    private func showSupportIfNeeded() -> Bool {
        // Stable patches share one invitation, even if the first installed
        // version in this release series is a hotfix.
        guard SupportUpdateIntroInfo.shouldShow(
            appVersion: host.version(),
            lastSeenVersion: host.defaults.string(forKey: DefaultsKey.supportUpdateIntroVersion)
        ) else { return false }
        showSupport()
        return true
    }

    private func showShowcaseIfNeeded() -> Bool {
        guard host.version() == UpdateShowcaseInfo.releaseVersion,
              host.defaults.string(forKey: DefaultsKey.updateShowcaseIntroVersion)
                != UpdateShowcaseInfo.releaseVersion else {
            host.cleanupShowcaseCache()
            return false
        }
        _ = host.open(.showcase)
        return true
    }

    private func markHighlightsSeen() {
        guard let marker = UpdateHighlightsInfo.seenVersion(for: host.version()) else { return }
        host.defaults.set(marker, forKey: DefaultsKey.updateHighlightsSeenVersion)
    }

    private func markSupportSeen() {
        host.defaults.set(SupportUpdateIntroInfo.seenVersion, forKey: DefaultsKey.supportUpdateIntroVersion)
    }
}
