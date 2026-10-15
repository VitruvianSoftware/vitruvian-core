// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import XCTest

@testable import GitHubToolCore

final class WordsTests: XCTestCase {
    func testEveryTextIsInEveryLanguageWithEnglishFirst() {
        XCTAssertEqual(Words.languages.first, "en")
        XCTAssertEqual(Words.languages.count, 15)
        XCTAssertEqual(Words.table.count, 72)
        for key in ["statusOK", "statusBusy", "statusAttention", "statusFailure"] {
            XCTAssertNotNil(Words.table[key], "the status on the closed island says \(key)")
        }
        for (key, entry) in Words.table {
            XCTAssertEqual(Set(entry.keys), Set(Words.languages), key)
            for (language, text) in entry {
                XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, "\(key) in \(language)")
                XCTAssertFalse(text.contains(" - ") || text.contains("—"), "\(key) in \(language): no dash as punctuation")
                XCTAssertFalse(text.contains("..."), "\(key) in \(language): the ellipsis character")
                XCTAssertEqual(text.components(separatedBy: "%@").count, entry["en"]!.components(separatedBy: "%@").count,
                               "\(key) in \(language) has the English's places")
            }
        }
    }

    func testFormatFillsEachLanguage() {
        let text = Words.format("connectedAsFormat", "james")
        XCTAssertEqual(text.text(for: "en-US"), "Connected as @james")
        XCTAssertEqual(text.text(for: "fr"), "Connecté en tant que @james")
        XCTAssertEqual(Words.plain("checksFormat", language: "de", "3", "1", "2"), "3 bestanden, 1 fehlgeschlagen, 2 laufen")
        XCTAssertEqual(Words.text("nothing-of-the-kind").text(for: "en"), "nothing-of-the-kind", "a missing key is seen")
    }

    func testFrenchPutsANoBreakSpaceBeforeItsColons() {
        for (key, entry) in Words.table {
            let french = entry["fr"]!
            for (index, character) in french.enumerated() where ":;?!".contains(character) {
                let before = french[french.index(french.startIndex, offsetBy: index - 1)]
                XCTAssertTrue(before == "\u{00A0}" || index == 0 || "/:".contains(before)
                                  || french.hasPrefix("ghp_") || key == "mouseMissingHomebrew",
                              "\(key): a French \(character) wants a no-break space before it")
            }
        }
    }
}
