// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class ContactPersonGroupingTests: XCTestCase {
    private func candidate(
        _ name: String,
        network: String,
        account: String = "acc-1",
        userID: String? = nil,
        avatarPath: String = "",
        identifiers: [String] = [],
        roomID: String? = nil
    ) -> ContactCandidate {
        ContactCandidate(
            userID: userID ?? "@\(network)_\(name.filter { $0.isLetter || $0.isNumber }):courier.local",
            name: name,
            avatarPath: avatarPath,
            network: network,
            accountID: account,
            identifiers: identifiers,
            roomID: roomID
        )
    }

    // MARK: - Email normalization

    func testEmailKeyNormalizesCaseMailtoAndNetworkTag() {
        let spellings = [
            "Alice@Example.COM",
            "mailto:alice@example.com",
            "alice@example.com (GChat)",
            "  MAILTO:Alice@example.com  ",
        ]
        XCTAssertEqual(Set(spellings.compactMap(ContactListOrdering.emailKey)), ["alice@example.com"])
        XCTAssertNil(ContactListOrdering.emailKey("@alice:courier.local"))
        XCTAssertNil(ContactListOrdering.emailKey("Al@Home"))
        XCTAssertNil(ContactListOrdering.emailKey("a@b..c"))
    }

    // MARK: - Merging rules (C4)

    func testSameNormalizedPhoneMergesDifferentNetworksIntoOnePersonRow() {
        let wa = candidate("Alice Example", network: "whatsapp", identifiers: ["+1 (213) 447-6502 (WA)"])
        let sig = candidate("Alice Example", network: "signal", identifiers: ["(213) 447-6502"])
        let imsg = candidate("Alice", network: "imessage", identifiers: ["tel:+12134476502 x12"])

        let sections = ContactPersonGrouping.sections(
            [imsg, sig, wa],
            accountOrder: ["whatsapp", "signal", "imessage"]
        )
        XCTAssertEqual(sections.named.count, 1)
        XCTAssertEqual(sections.other, [])
        let group = sections.named[0]
        XCTAssertTrue(group.isMultiNetwork)
        XCTAssertEqual(group.networks, ["whatsapp", "signal", "imessage"])
        XCTAssertEqual(group.endpoints.count, 3)
    }

    func testSameVanityOrUKTrunkPhoneMerges() {
        let vanity = candidate("Flower Shop", network: "whatsapp", identifiers: ["1-800-FLOWERS"])
        let digits = candidate("Flower Shop", network: "signal", identifiers: ["+1 (800) 356-9377"])
        let ukA = candidate("London Friend", network: "whatsapp", identifiers: ["+44 (0) 20 7946 0958"])
        let ukB = candidate("London Friend", network: "telegram", identifiers: ["+44 20 7946 0958"])

        let sections = ContactPersonGrouping.sections([vanity, digits, ukA, ukB])
        XCTAssertEqual(sections.named.count, 2)
        XCTAssertTrue(sections.named.allSatisfy { $0.isMultiNetwork && $0.endpoints.count == 2 })
    }

    func testSameNormalizedEmailMergesDifferentNetworks() {
        let gchat = candidate("Bob", network: "gchat", identifiers: ["mailto:Bob.Smith@Example.COM"])
        let slack = candidate("Bob Smith", network: "slack", identifiers: ["bob.smith@example.com"])

        let sections = ContactPersonGrouping.sections([gchat, slack])
        XCTAssertEqual(sections.named.count, 1)
        XCTAssertEqual(sections.named[0].endpoints.count, 2)
        XCTAssertEqual(Set(sections.named[0].networks), ["gchat", "slack"])
    }

    func testMergedChatMergesAcrossNetworksWithNothingElseInCommon() {
        let e = candidate("Finn", network: "whatsapp", userID: "@finn_wa", roomID: "!finn-wa")
        let f = candidate("Finn", network: "signal", userID: "@finn_sig", roomID: "!finn-sig")
        let other = candidate("Finn", network: "telegram", userID: "@finn_tg", roomID: "!finn-tg")
        let merge = MergedChat(
            mergeID: "merge:finn",
            name: "Finn",
            avatarPath: "",
            lastRoomID: "!finn-wa",
            roomIDs: ["!finn-wa", "!finn-sig"],
            networks: ["whatsapp", "signal"],
            createdTS: 1
        )

        let sections = ContactPersonGrouping.sections([e, f, other], mergedChats: [merge.mergeID: merge])
        XCTAssertEqual(sections.named.count, 2, "the merged pair is one person; the unmerged Finn stays apart")
        XCTAssertEqual(sections.named.map { $0.endpoints.count }.sorted(), [1, 2])
    }

    func testTransitiveMergeCombinesThreeNetworks() {
        let one = candidate("Grace", network: "whatsapp", identifiers: ["+12134476502"])
        let two = candidate("Grace", network: "signal", identifiers: ["+12134476502", "grace@example.com"])
        let three = candidate("Grace", network: "gchat", identifiers: ["grace@example.com"])

        let sections = ContactPersonGrouping.sections([one, two, three])
        XCTAssertEqual(sections.named.count, 1)
        XCTAssertEqual(sections.named[0].endpoints.count, 3)
    }

    func testNeverMergesOnDisplayNameAlone() {
        let sam1 = candidate("Sam", network: "whatsapp", userID: "@sam1", identifiers: ["+15550100001"])
        let sam2 = candidate("Sam", network: "signal", userID: "@sam2", identifiers: ["+15550100002"])
        let sam3 = candidate("Sam", network: "telegram", userID: "@sam3", identifiers: [])
        let sam4 = candidate("Sam", network: "discord", userID: "@sam4", identifiers: [])

        let sections = ContactPersonGrouping.sections([sam1, sam2, sam3, sam4])
        XCTAssertEqual(sections.named.count, 4, "same name without shared link/phone/email must stay separate")
        XCTAssertTrue(sections.named.allSatisfy { !$0.isMultiNetwork })
    }

    func testSameEndpointSeenTwiceIsOneButDifferentUserIDsOnOneAccountStayApart() {
        let namedWA = candidate("Alice", network: "whatsapp", account: "wa-personal", userID: "@alice", identifiers: ["+12134476502"])
        let again = candidate("Alice", network: "whatsapp", account: "wa-personal", userID: "@alice", identifiers: ["+12134476502"])
        let bareWA = candidate("+12134476502", network: "whatsapp", account: "wa-personal", userID: "@12134476502")
        let workWA = candidate("Alice", network: "whatsapp", account: "wa-work", userID: "@alice_work", identifiers: ["+12134476502"])

        let sections = ContactPersonGrouping.sections([bareWA, namedWA, again, workWA])
        XCTAssertEqual(sections.named.count, 1)
        XCTAssertEqual(sections.other, [])
        let endpoints = sections.named[0].endpoints
        XCTAssertEqual(
            Set(endpoints.map(\.id)),
            [namedWA.id, bareWA.id, workWA.id],
            "the repeated endpoint is one; the other user ID and the other account are kept"
        )
        XCTAssertEqual(endpoints.count, 3)
    }

    func testNamedAndPhoneOnlyEntryOnDifferentNetworksMergeAsOneNamedPerson() {
        let aliceSig = candidate("Alice", network: "signal", account: "sig-1", identifiers: ["+12134476502"])
        let aliceWA = candidate("+12134476502", network: "whatsapp", account: "wa-1")

        let sections = ContactPersonGrouping.sections([aliceWA, aliceSig])
        XCTAssertEqual(sections.named.count, 1)
        XCTAssertEqual(sections.other, [])
        XCTAssertEqual(sections.named[0].displayName, "Alice")
        XCTAssertEqual(sections.named[0].endpoints.count, 2)
    }

    // MARK: - QA edge cases (C4)

    func testPersonOnFiveNetworksIsOneRowWithFiveEndpointsInAccountOrder() {
        let nets = ["whatsapp", "signal", "telegram", "gchat", "imessage"]
        let people = nets.map { candidate("Alice", network: $0, identifiers: ["+1 213 447 6502"]) }
        let sections = ContactPersonGrouping.sections(people.reversed(), accountOrder: nets)
        XCTAssertEqual(sections.named.count, 1)
        XCTAssertEqual(sections.named[0].networks, nets)
        XCTAssertEqual(sections.named[0].endpoints.map(\.network), nets)
    }

    func testEmailCaseAndMissingIdentifiersNeverMergeByAccident() {
        let upper = candidate("Pat", network: "gchat", userID: "@p1", identifiers: ["PAT@Example.com"])
        let lower = candidate("Pat Lee", network: "slack", userID: "@p2", identifiers: ["pat@example.com"])
        let bare1 = candidate("Chris", network: "whatsapp", userID: "@c1")
        let bare2 = candidate("Chris", network: "signal", userID: "@c2")
        let sections = ContactPersonGrouping.sections([upper, lower, bare1, bare2])
        XCTAssertEqual(sections.named.count, 3, "Pat merges on email; the two identifier-less Chris entries stay apart")
    }

    func testSameDigitsWithDifferentCountryCodesStayApart() {
        let us = candidate("Sam", network: "whatsapp", userID: "@us", identifiers: ["(791) 112-3456"])
        let uk = candidate("Sam", network: "signal", userID: "@uk", identifiers: ["+44 791 123 456"])
        let sections = ContactPersonGrouping.sections([us, uk])
        XCTAssertEqual(sections.named.count, 2)
    }

    // MARK: - Shared numbers and addresses (family landline, shared inbox)

    func testFamilyLandlineSharedByMomAndDadDoesNotMergeThemButMobilesStayTheirOwn() {
        let landline = "+1 213 555 0100"
        let momWA = candidate("Mom", network: "whatsapp", userID: "@mom_wa", identifiers: ["+1 213 555 0111", landline])
        let dadSig = candidate("Dad", network: "signal", userID: "@dad_sig", identifiers: ["+1 213 555 0122", landline])

        let sections = ContactPersonGrouping.sections([momWA, dadSig])
        XCTAssertEqual(sections.named.count, 2, "the landline belongs to both, so it links neither")
        XCTAssertEqual(Set(sections.named.map(\.displayName)), ["Mom", "Dad"])
        XCTAssertTrue(sections.named.allSatisfy { $0.endpoints.count == 1 })
    }

    func testMomsMobileStillMergesHerAcrossNetworksWhileTheSharedLandlineIsIgnored() {
        let landline = "+1 213 555 0100"
        let momWA = candidate("Mom", network: "whatsapp", userID: "@mom_wa", identifiers: ["+1 213 555 0111", landline])
        let momSig = candidate("Mom", network: "signal", userID: "@mom_sig", identifiers: ["+1 213 555 0111"])
        let dadSig = candidate("Dad", network: "signal", userID: "@dad_sig", identifiers: ["+1 213 555 0122", landline])

        let sections = ContactPersonGrouping.sections([momWA, momSig, dadSig])
        XCTAssertEqual(sections.named.count, 2)
        let mom = sections.named.first { $0.displayName == "Mom" }
        XCTAssertEqual(mom?.endpoints.count, 2)
        XCTAssertEqual(sections.named.first { $0.displayName == "Dad" }?.endpoints.count, 1)
    }

    func testMomAndDadOnTheSameAccountAreBothReachable() {
        let landline = "+1 213 555 0100"
        let mom = candidate("Mom", network: "whatsapp", account: "acc-1", userID: "@mom", identifiers: [landline])
        let dad = candidate("Dad", network: "whatsapp", account: "acc-1", userID: "@dad", identifiers: [landline])

        let sections = ContactPersonGrouping.sections([mom, dad])
        XCTAssertEqual(sections.named.count, 2)
        let reachable = sections.named.flatMap(\.endpoints).map(\.userID)
        XCTAssertEqual(Set(reachable), ["@mom", "@dad"], "neither is swallowed by the other")
    }

    func testSharedInboxHeldByDifferentlyNamedPeopleLinksNobody() {
        let sales = candidate("Ann", network: "gchat", userID: "@ann", identifiers: ["team@example.com"])
        let support = candidate("Raj", network: "slack", userID: "@raj", identifiers: ["TEAM@example.com"])
        let sections = ContactPersonGrouping.sections([sales, support])
        XCTAssertEqual(sections.named.count, 2)
    }

    func testBareNumberEntryStillJoinsTheOnePersonWhoHasThatNumber() {
        let alice = candidate("Alice", network: "signal", userID: "@a", identifiers: ["+12134476502"])
        let bare = candidate("+12134476502", network: "whatsapp", userID: "@bare")
        let sections = ContactPersonGrouping.sections([alice, bare])
        XCTAssertEqual(sections.named.count, 1)
        XCTAssertEqual(sections.named[0].endpoints.count, 2)
    }

    // MARK: - QA: empty display names and shared numbers

    func testEntryWithNoDisplayNameNeverGluesTwoDifferentlyNamedPeopleTogether() {
        let mom = candidate("Mom", network: "whatsapp", userID: "@mom", identifiers: ["+12135559999"])
        let dad = candidate("Dad", network: "signal", userID: "@dad", identifiers: ["+12135559999"])
        let blank = candidate("", network: "telegram", userID: "@blank", identifiers: ["+12135559999"])

        let both = ContactPersonGrouping.sections([mom, dad, blank])
        XCTAssertEqual(both.named.map(\.displayName).sorted(), ["Dad", "Mom"])
        XCTAssertEqual(both.other.count, 1, "the nameless entry stays its own row")
        XCTAssertEqual(both.other[0].displayName, "@blank", "and shows its user id rather than an empty title")

        let momOnly = ContactPersonGrouping.sections([mom, blank])
        XCTAssertEqual(momOnly.named.count, 1, "with only one named holder, the nameless entry joins her")
        XCTAssertEqual(momOnly.named[0].endpoints.count, 2)
    }

    // MARK: - C5 UI helper logic (overflow edges & row affordances)

    func testHorizontalOverflowEdgesCompute() {
        XCTAssertEqual(
            HorizontalOverflowEdges.compute(viewportWidth: 0, contentMinX: 0, contentMaxX: 500),
            HorizontalOverflowEdges(leading: false, trailing: false)
        )
        XCTAssertEqual(
            HorizontalOverflowEdges.compute(viewportWidth: 400, contentMinX: 0, contentMaxX: 350),
            HorizontalOverflowEdges(leading: false, trailing: false)
        )
        XCTAssertEqual(
            HorizontalOverflowEdges.compute(viewportWidth: 400, contentMinX: 0, contentMaxX: 520),
            HorizontalOverflowEdges(leading: false, trailing: true)
        )
        XCTAssertEqual(
            HorizontalOverflowEdges.compute(viewportWidth: 400, contentMinX: -40, contentMaxX: 480),
            HorizontalOverflowEdges(leading: true, trailing: true)
        )
        XCTAssertEqual(
            HorizontalOverflowEdges.compute(viewportWidth: 400, contentMinX: -120, contentMaxX: 400),
            HorizontalOverflowEdges(leading: true, trailing: false)
        )
    }

    func testStartNewChatRowAffordanceIsUniformOnHoverForEverySingleChatRow() {
        // Recent room row (allowsMultiSelect: false) and normal contact row (allowsMultiSelect: true) both show .startChat on hover.
        XCTAssertEqual(
            StartNewChatRowAffordance.forPersonRow(
                isMultiNetwork: false,
                isExpanded: false,
                isMultiSelectActive: false,
                allowsMultiSelect: false,
                isRecipientSelected: false,
                isHovered: true,
                isKeyboardSelected: false
            ),
            .startChat
        )
        XCTAssertEqual(
            StartNewChatRowAffordance.forPersonRow(
                isMultiNetwork: false,
                isExpanded: false,
                isMultiSelectActive: false,
                allowsMultiSelect: true,
                isRecipientSelected: false,
                isHovered: true,
                isKeyboardSelected: false
            ),
            .startChat
        )
        XCTAssertEqual(
            StartNewChatRowAffordance.forPersonRow(
                isMultiNetwork: false,
                isExpanded: false,
                isMultiSelectActive: false,
                allowsMultiSelect: true,
                isRecipientSelected: false,
                isHovered: false,
                isKeyboardSelected: false
            ),
            .none
        )
        XCTAssertEqual(
            StartNewChatRowAffordance.forPersonRow(
                isMultiNetwork: true,
                isExpanded: false,
                isMultiSelectActive: false,
                allowsMultiSelect: true,
                isRecipientSelected: false,
                isHovered: true,
                isKeyboardSelected: false
            ),
            .expand(isExpanded: false)
        )
        XCTAssertEqual(
            StartNewChatRowAffordance.forEndpointSubRow(
                isMultiSelectActive: false,
                allowsMultiSelect: true,
                isRecipientSelected: false,
                isHovered: true,
                isKeyboardSelected: false
            ),
            .startChat
        )
        XCTAssertEqual(
            StartNewChatRowAffordance.forLookupRow(isHovered: true, isKeyboardSelected: false),
            .startChat
        )
        XCTAssertEqual(
            StartNewChatRowAffordance.forLookupRow(isHovered: false, isKeyboardSelected: false),
            .none
        )
    }
}
