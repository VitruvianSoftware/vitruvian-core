// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The app's own words about tools from outside, in all fifteen languages.
/// A language that is missing does not compile. These checks hold what the
/// compiler cannot: that each text is there, is a translation, and fills its
/// format the way the English one does.
enum ExternalToolStringsTests {
    /// How many texts the screens for tools from outside add. A text added
    /// or taken away changes this number on purpose, with the plan's table.
    static let count = 61

    static func run(_ suite: TestSuite) {
        let english = FeatureStrings.externalTools(.enUS).all
        suite.expect(english.count == count && Set(english.map(\.key)).count == count,
                     "the screens for tools from outside add \(count) texts, each under its own name (\(english.count))")

        for language in AppLanguage.allCases {
            let texts = FeatureStrings.externalTools(language).all
            let blank = texts.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.key)
            let dashed = texts.filter { $0.text.contains("\u{2014}") || $0.text.contains("...") }.map(\.key)
            suite.expect(texts.map(\.key) == english.map(\.key) && blank.isEmpty && dashed.isEmpty,
                         "every text about tools from outside is written, with no em-dash and no three periods, "
                             + "in \(language.rawValue) (\((blank + dashed).joined(separator: ", ")))")

            var misfilled: [String] = []
            for (base, mine) in zip(english, texts) where base.key.hasSuffix("Format") {
                let wanted = TestFormat.parse(base.text)
                if wanted == nil || wanted?.arguments.isEmpty == true
                    || wanted?.arguments != TestFormat.parse(mine.text)?.arguments {
                    misfilled.append(mine.key)
                }
            }
            suite.expect(misfilled.isEmpty,
                         "every format about tools from outside is filled the same way in \(language.rawValue) "
                             + "(\(misfilled.joined(separator: ", ")))")
            let stray = texts.filter { !$0.key.hasSuffix("Format") && $0.text.contains("%") }.map(\.key)
            suite.expect(stray.isEmpty,
                         "a text that is no format holds no percent sign in \(language.rawValue) "
                             + "(\(stray.joined(separator: ", ")))")

            guard language != .enUS else { continue }
            let untranslated = zip(english, texts).filter { $0.text == $1.text }.map(\.0.key)
            suite.expect(untranslated.isEmpty,
                         "no text about tools from outside is left in English in \(language.rawValue) "
                             + "(\(untranslated.joined(separator: ", ")))")
        }

        let strings = FeatureStrings.externalTools(.enUS)
        suite.expect(strings.agreeTitle("Deploys") == "Add “Deploys” to Vitruvian?"
                         && strings.updateVersions(agreed: "1.2.0", offered: "1.3.0")
                         == "You have version 1.2.0. This folder has version 1.3.0."
                         && strings.refusalTooBig(size: "256 MB", items: "10,000")
                         == "The folder is too large. A tool can hold up to 256 MB and 10,000 files."
                         && strings.stopped("Deploys") == "“Deploys” stopped working"
                         && strings.removeKeptTitle("Deploys") == "What “Deploys” saved was kept"
                         && strings.removeUndeletedTitle("Deploys") == "Some files of “Deploys” could not be deleted"
                         && strings.installRefused("Deploys") == "“Deploys” was not installed",
                     "a format is filled with what it is handed, in the order the sentence names it")
        let listable: [Capability] = [.notify, .open, .clipboardRead, .clipboardWrite, .keystrokes, .processes, .storage]
        suite.expect(Capability.allCases.filter { strings.use($0) != nil } == Capability.allCases.filter(listable.contains)
                         && Set(listable.compactMap(strings.use)).count == 7
                         && strings.use(.keystrokes) == "Paste and press menu commands in other apps",
                     "each of the seven services a tool from outside may list has its own plain words, and no other has any")
        suite.expect(FeatureStrings.externalTools(.de).removeTitle("Deploys") == "„Deploys“ entfernen?"
                         && FeatureStrings.externalTools(.fr).agreeTitle("Deploys")
                         == "Ajouter «\u{00A0}Deploys\u{00A0}» à Vitruvian\u{00A0}?"
                         && FeatureStrings.externalTools(.fr).installRefused("Deploys")
                         == "«\u{00A0}Deploys\u{00A0}» n’a pas été installé"
                         && FeatureStrings.externalTools(.ja).installRefused("Deploys") == "「Deploys」はインストールされませんでした",
                     "a tool's name is quoted the way each language quotes")
    }
}
