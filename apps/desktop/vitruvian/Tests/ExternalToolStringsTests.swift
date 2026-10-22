// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// The app's own words about tools from outside, in all fifteen languages.
/// A language that is missing does not compile. These checks hold what the
/// compiler cannot: that each text is there, is a translation, and fills its
/// format the way the English one does.
enum ExternalToolStringsTests {
    /// How many texts the screens for tools from outside add. A text added
    /// or taken away changes this number on purpose, with the plan's table.
    static let count = 89

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
            // The app's name is the same in every language.
            let names: Set = ["vitruvianSection"]
            let untranslated = zip(english, texts).filter { $0.text == $1.text && !names.contains($0.key) }.map(\.0.key)
            suite.expect(untranslated.isEmpty,
                         "no text about tools from outside is left in English in \(language.rawValue) "
                             + "(\(untranslated.joined(separator: ", ")))")
        }
        suite.expect(AppLanguage.allCases.allSatisfy { FeatureStrings.externalTools($0).vitruvianSection == "Vitruvian" },
                     "the heading of Vitruvian's own rows on an extension's settings sheet is the app's name, in every "
                         + "language")

        let strings = FeatureStrings.externalTools(.enUS)
        suite.expect(strings.agreeTitle("Deploys") == "Add “Deploys” to Vitruvian?"
                         && strings.updateVersions(agreed: "1.2.0", offered: "1.3.0")
                         == "You have version 1.2.0. This folder has version 1.3.0."
                         && strings.updateVersionsFromCatalog(agreed: "1.2.0", offered: "1.3.0")
                         == "You have version 1.2.0. The catalog has version 1.3.0."
                         && strings.refusalTooBig(size: "256 MB", items: "10,000")
                         == "The folder is too large. A tool can hold up to 256 MB and 10,000 files."
                         && strings.stopped("Deploys") == "“Deploys” stopped working"
                         && strings.removeKeptTitle("Deploys") == "What “Deploys” saved was kept"
                         && strings.removeUndeletedTitle("Deploys") == "Some files of “Deploys” could not be deleted"
                         && strings.installRefused("Deploys") == "“Deploys” was not installed",
                     "a format is filled with what it is handed, in the order the sentence names it")
        func size(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory) }
        suite.expect(strings.panelRefused("HomeSpeaker", .notWellFormed("blocks[76].id"))
                         == "HomeSpeaker sent a page Vitruvian can’t show (blocks[76].id is not well formed). "
                         + "Updating the extension may fix it."
                         && strings.panelRefused("HomeSpeaker", .tooLarge(bytes: 300_000))
                         == "HomeSpeaker sent a page Vitruvian can’t show (over the \(size(UILimits.maxTreeBytes)) "
                         + "size limit). Updating the extension may fix it."
                         && size(UILimits.maxTreeBytes) == "256 KB",
                     "a refused page is said in plain words, with the extension's name and why")
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
        suite.expect(strings.pageTitle == "Extensions" && strings.sectionTitle == "Extensions & Tools"
                         && strings.addButton == "Add from Folder…"
                         && strings.kindExtension == "Extension" && strings.kindTool == "Tool",
                     "the page is called Extensions, the old card's name is still a word for it, and its rows are "
                         + "badged Extension or Tool")
        suite.expect(strings.summaryCount(3) == "3 extensions installed"
                         && FeatureStrings.externalTools(.ru).summaryCount(12) == "Установлено расширений: 12",
                     "the Features page's count is filled with how many are added")
        // Some extensions add only a Settings part or a window, so the card's
        // words name every place a page can go, not the island alone.
        suite.expect(["Dynamic Island", "Settings", "window", "commands"].allSatisfy(strings.sectionEmpty.contains),
                     "the card's sentence says an extension adds pages in the island, Settings or a window, and a tool adds commands")
        let sameKind = AppLanguage.allCases.filter {
            let local = FeatureStrings.externalTools($0)
            return local.kindExtension == local.kindTool
        }
        suite.expect(sameKind.isEmpty,
                     "the two badges read differently in every language (\(sameKind.map(\.rawValue).joined(separator: ", ")))")
    }
}
