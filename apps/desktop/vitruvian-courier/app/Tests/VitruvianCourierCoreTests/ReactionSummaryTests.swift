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

    func testPillDisplayFallsBackToPlainCountWhenReactorsUnknown() {
        let unknown = ReactionChip(key: "👍", count: 2, mine: false)
        XCTAssertEqual(unknown.pillDisplay(), .count("2"))
        XCTAssertEqual(unknown.tooltipText(), unknown.summary())
    }

    func testPillDisplayShowsUpToThreeAvatarsWithInitialsAndNoOverflow() {
        let one = chip("👍", [Reactor(userID: "@kent:example.test", name: "Kent Hua", isMe: false, avatarPath: "/tmp/kent.png")])
        XCTAssertEqual(
            one.pillDisplay(),
            .avatars(
                items: [
                    ReactionAvatarItem(
                        userID: "@kent:example.test",
                        avatarPath: "/tmp/kent.png",
                        initials: "KH",
                        seed: "Kent Hua",
                        isMe: false
                    ),
                ],
                overflowText: nil
            )
        )
        XCTAssertEqual(one.tooltipText(), "Kent Hua")

        let two = chip("👍", [
            Reactor(userID: "@kent:example.test", name: "Kent Hua", isMe: false),
            Reactor(userID: "@eddie:example.test", name: "Eddie Stecker", isMe: false),
        ])
        XCTAssertEqual(
            two.pillDisplay(),
            .avatars(
                items: [
                    ReactionAvatarItem(userID: "@kent:example.test", avatarPath: "", initials: "KH", seed: "Kent Hua", isMe: false),
                    ReactionAvatarItem(userID: "@eddie:example.test", avatarPath: "", initials: "ES", seed: "Eddie Stecker", isMe: false),
                ],
                overflowText: nil
            )
        )
        XCTAssertEqual(two.tooltipText(), "Kent Hua, Eddie Stecker")

        let three = chip("❤️", [person("Ann Example"), person("Bo"), Reactor(userID: "@cy:example.test", name: "@cy:example.test", isMe: false)])
        XCTAssertEqual(
            three.pillDisplay(),
            .avatars(
                items: [
                    ReactionAvatarItem(userID: "@ann example:example.test", avatarPath: "", initials: "AE", seed: "Ann Example", isMe: false),
                    ReactionAvatarItem(userID: "@bo:example.test", avatarPath: "", initials: "B", seed: "Bo", isMe: false),
                    ReactionAvatarItem(userID: "@cy:example.test", avatarPath: "", initials: "C", seed: "@cy:example.test", isMe: false),
                ],
                overflowText: nil
            )
        )
    }

    func testPillDisplayCapsAtThreeAvatarsAndFormatsPlusNOwnAndPartialCounts() {
        let four = chip("👍", [person("Ann"), person("Bo"), person("Cy"), person("Di")])
        guard case let .avatars(fourItems, fourOverflow) = four.pillDisplay() else {
            return XCTFail("Expected avatars display")
        }
        XCTAssertEqual(fourItems.count, 3)
        XCTAssertEqual(fourItems.map(\.initials), ["A", "B", "C"])
        XCTAssertEqual(fourOverflow, "+1")
        XCTAssertEqual(four.tooltipText(), "Ann, Bo, Cy, Di")

        let twelveNames = ["Ann", "Bo", "Cy", "Di", "Ed", "Flo", "Gus", "Hal", "Ivy", "Jo", "Kit", "Lou"]
        let twelve = chip("🎉", twelveNames.map(person))
        guard case let .avatars(twelveItems, twelveOverflow) = twelve.pillDisplay() else {
            return XCTFail("Expected avatars display")
        }
        XCTAssertEqual(twelveItems.count, 3)
        XCTAssertEqual(twelveOverflow, "+9")
        XCTAssertEqual(twelve.tooltipText(), twelveNames.joined(separator: ", "))

        let partial = ReactionChip(
            key: "🔥",
            count: 5,
            mine: true,
            reactors: [me, person("Kent Hua")],
            myEventID: "$mine"
        )
        guard case let .avatars(partialItems, partialOverflow) = partial.pillDisplay() else {
            return XCTFail("Expected avatars display")
        }
        XCTAssertEqual(partialItems.count, 2)
        XCTAssertEqual(partialItems[0].isMe, true)
        XCTAssertEqual(partialOverflow, "+3")
        XCTAssertEqual(partial.tooltipText(), "You, Kent Hua, +3 others")
    }

    func testTimelinePropagatesSenderAvatarPathToReactors() {
        let base = Event(
            eventID: "$m1",
            roomID: "!r:example.test",
            sender: "@kent:example.test",
            senderName: "Kent Hua",
            senderAvatarPath: "/tmp/kent-msg.jpg",
            mine: false,
            type: "m.room.message",
            content: .object(["msgtype": .string("m.text"), "body": .string("hello")]),
            ts: 1000,
            seq: 1,
            status: .sent
        )
        let reactionWithOwnAvatar = Event(
            eventID: "$r1",
            roomID: "!r:example.test",
            sender: "@eddie:example.test",
            senderName: "Eddie Stecker",
            senderAvatarPath: "/tmp/eddie-rx.jpg",
            mine: false,
            type: "m.reaction",
            content: .object([
                "m.relates_to": .object([
                    "rel_type": .string("m.annotation"),
                    "event_id": .string("$m1"),
                    "key": .string("👍"),
                ]),
            ]),
            ts: 2000,
            seq: 2,
            status: .sent
        )
        let reactionUsingSenderFallbackAvatar = Event(
            eventID: "$r2",
            roomID: "!r:example.test",
            sender: "@kent:example.test",
            senderName: "Kent Hua",
            senderAvatarPath: "",
            mine: false,
            type: "m.reaction",
            content: .object([
                "m.relates_to": .object([
                    "rel_type": .string("m.annotation"),
                    "event_id": .string("$m1"),
                    "key": .string("👍"),
                ]),
            ]),
            ts: 3000,
            seq: 3,
            status: .sent
        )

        let items = Timeline.build(
            events: [base, reactionWithOwnAvatar, reactionUsingSenderFallbackAvatar],
            me: Timeline.meUserID
        )
        let message = items.compactMap { item -> TimelineMessage? in
            if case let .message(msg) = item { return msg }
            return nil
        }.first
        XCTAssertEqual(message?.reactions.count, 1)
        XCTAssertEqual(
            message?.reactions.first?.reactors,
            [
                Reactor(userID: "@eddie:example.test", name: "Eddie Stecker", isMe: false, avatarPath: "/tmp/eddie-rx.jpg"),
                Reactor(userID: "@kent:example.test", name: "Kent Hua", isMe: false, avatarPath: "/tmp/kent-msg.jpg"),
            ]
        )
    }
}
