// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// A new poll's problems, as the engine would refuse it (actions.CreatePoll): each in Courier's words, so nothing is
/// sent that would come back as an error.
final class PollDraftTests: XCTestCase {
    private let whatsApp = PollFeatures(maxOptions: 12, optionMaxLength: 100)
    private let signal = PollFeatures(maxOptions: 10, optionMaxLength: 100)

    private func draft(_ question: String = "Lunch?", _ options: [String] = ["Pizza", "Soup"]) -> PollDraft {
        var draft = PollDraft()
        draft.question = question
        draft.options = options
        return draft
    }

    func testAGoodDraftHasNoProblems() {
        XCTAssertEqual(PollDraft().options, ["", ""], "two empty options to fill")
        XCTAssertFalse(PollDraft().multiple)
        XCTAssertEqual(draft().problems(in: whatsApp), [])
        // Empty rows (the "Add an option" row) are left out, and what is sent is trimmed.
        let spaced = draft("  Lunch?  ", [" Pizza ", "", "Soup", "   "])
        XCTAssertEqual(spaced.problems(in: whatsApp), [])
        XCTAssertEqual(spaced.sendableQuestion, "Lunch?")
        XCTAssertEqual(spaced.sendableOptions, ["Pizza", "Soup"])
    }

    func testAskAQuestion() {
        XCTAssertEqual(draft("", ["Pizza", "Soup"]).problems(in: whatsApp), ["Ask a question"])
        XCTAssertEqual(draft("  \n", ["Pizza", "Soup"]).problems(in: whatsApp), ["Ask a question"])
    }

    func testQuestionLength() {
        let long = String(repeating: "q", count: 301)
        XCTAssertEqual(draft(long).problems(in: whatsApp), ["Questions can be up to 300 characters"])
        XCTAssertEqual(draft(String(repeating: "q", count: 300)).problems(in: whatsApp), [])
    }

    func testAddAtLeastTwoOptions() {
        XCTAssertEqual(draft("Lunch?", ["Pizza", ""]).problems(in: whatsApp), ["Add at least two options"])
        XCTAssertEqual(draft("Lunch?", ["", "  "]).problems(in: whatsApp), ["Add at least two options"])
    }

    func testThisOptionAlreadyExists() {
        // The engine compares ignoring case.
        XCTAssertEqual(draft("Lunch?", ["Pizza", "pizza "]).problems(in: whatsApp), ["This option already exists"])
        XCTAssertTrue(draft("Lunch?", ["Pizza", "Soup"]).duplicates.isEmpty)
        XCTAssertEqual(draft("Lunch?", ["Pizza", "Soup", "PIZZA"]).duplicates, [2], "the later copy is the one marked")
    }

    func testOptionLength() {
        let long = String(repeating: "o", count: 101)
        XCTAssertEqual(draft("Lunch?", ["Pizza", long]).problems(in: whatsApp), ["Options can be up to 100 characters"])
        // Characters as the engine counts them (Unicode scalars): 100 emoji fit.
        XCTAssertEqual(draft("Lunch?", ["Pizza", String(repeating: "🍕", count: 100)]).problems(in: whatsApp), [])
    }

    func testWhatsAppTakesTwelveOptionsAndSignalTen() {
        let twelve = (1 ... 12).map { "Option \($0)" }
        XCTAssertEqual(draft("Lunch?", twelve).problems(in: whatsApp), [])
        XCTAssertTrue(draft("Lunch?", twelve).isAtMaximum(in: whatsApp), "no more can be added")
        XCTAssertEqual(draft("Lunch?", twelve + ["Option 13"]).problems(in: whatsApp),
                       ["You have added the maximum number of options"])
        XCTAssertFalse(draft("Lunch?", Array(twelve.prefix(11))).isAtMaximum(in: whatsApp))

        let ten = Array(twelve.prefix(10))
        XCTAssertEqual(draft("Lunch?", ten).problems(in: signal), [])
        XCTAssertTrue(draft("Lunch?", ten).isAtMaximum(in: signal))
        XCTAssertEqual(draft("Lunch?", Array(twelve.prefix(11))).problems(in: signal),
                       ["You have added the maximum number of options"])
    }

    func testEveryProblemAtOnce() {
        XCTAssertEqual(draft("", ["Pizza"]).problems(in: whatsApp), ["Ask a question", "Add at least two options"])
    }
}
