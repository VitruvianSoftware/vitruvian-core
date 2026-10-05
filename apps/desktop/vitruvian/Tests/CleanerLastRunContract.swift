// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The scheduler's real run record, read back the way the Cleaner card reads
/// it, feeds the card's real last-run line. Defaults live in a test domain;
/// nothing is cleaned.
enum CleanerLastRunContract {
    static func run(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.cleaner-last-run"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let strings = Strings.localized(.enUS)
        let ran = String(format: strings.cleanerScheduleRanFormat, "today")
        let freedFive = String(format: strings.cleanerScheduleLastFormat,
                               ByteCountFormatter.string(fromByteCount: 5, countStyle: .file))
        let leftSome = " " + strings.uninstallerSomeFailed
        for (freed, failed, line) in [(Int64(0), 3, ran + leftSome), (0, 0, ran),
                                      (5, 1, freedFive + leftSome), (5, 0, freedFive)] {
            CleanerScheduler.recordRun(freed: freed, failed: failed, at: Date(timeIntervalSince1970: 100), in: defaults)
            let shown = CleanerView.lastRunLine(ranAt: "today", freed: defaults[Preferences.cleanerLastAutoFreed],
                                                failed: defaults[Preferences.cleanerLastAutoFailed], strings: strings)
            suite.expect(defaults[Preferences.cleanerLastAutoRun] == 100 && shown == line,
                         "a scheduled run freeing \(freed) bytes and leaving \(failed) items reads \"\(shown)\"")
        }
    }
}
