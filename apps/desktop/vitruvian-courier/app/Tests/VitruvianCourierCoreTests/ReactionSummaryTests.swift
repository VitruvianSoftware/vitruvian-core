// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// What a reaction chip's hover card and accessibility label say about who reacted. All names here are made up.
final class ReactionSummaryTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    private func person(_ name: String) -> Reactor {
        Reactor(userID: "@\(name.lowercased()):example.test", name: name, isMe: false)
    }

    private let me = Reactor(userID: Timeline.meUserID, name: "me", isMe: true)

    private func chip(_ key: String, _ reactors: [Reactor]) -> ReactionChip {
        ReactionChip(key: key, count: reactors.count, mine: reactors.contains(where: \.isMe), reactors: reactors,
                     myEventID: reactors.contains(where: \.isMe) ? "$mine" : nil)
    }

    func testJustMe() {
        XCTAssertEqual(chip("👍", [me]).summary(locale: english), "You reacted with 👍")
    }

    func testOnePerson() {
        XCTAssertEqual(chip("❤️", [person("Ann")]).summary(locale: english), "Ann reacted with ❤️")
    }

    func testMeAndOneOtherWithMeFirst() {
        XCTAssertEqual(chip("👍", [person("Ann"), me]).summary(locale: english), "You and Ann reacted with 👍",
                       "I come first, however late I reacted")
    }

    func testThreePeople() {
        XCTAssertEqual(chip("😂", [person("Ann"), person("Bo"), person("Cy")]).summary(locale: english),
                       "Ann, Bo, and Cy reacted with 😂")
        XCTAssertEqual(chip("😂", [person("Ann"), me, person("Bo")]).summary(locale: english),
                       "You, Ann, and Bo reacted with 😂")
    }

    func testPastTheLimitTheRestAreCounted() {
        let names = ["Ann", "Bo", "Cy", "Di", "Ed", "Flo", "Gus", "Hal", "Ivy", "Jo", "Kit"]
        let twelve = chip("🎉", names.prefix(5).map(person) + [me] + names.dropFirst(5).map(person))
        XCTAssertEqual(twelve.count, 12)
        XCTAssertEqual(twelve.summary(maxNames: 10, locale: english),
                       "You, Ann, Bo, Cy, Di, Ed, Flo, Gus, Hal, Ivy, and 2 others reacted with 🎉")
        XCTAssertEqual(chip("🎉", names.prefix(3).map(person)).summary(maxNames: 2, locale: english),
                       "Ann, Bo, and 1 other reacted with 🎉")
    }

    func testAChipWithNoNamesStillCountsPeople() {
        // As a preview builds one: a count, and whether it is mine.
        XCTAssertEqual(ReactionChip(key: "👍", count: 3, mine: true).summary(locale: english),
                       "You and 2 others reacted with 👍")
    }
}
