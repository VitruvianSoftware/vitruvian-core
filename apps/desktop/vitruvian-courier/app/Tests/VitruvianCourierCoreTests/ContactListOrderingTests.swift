// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// `ContactListOrdering`: which names are only a phone number or handle, and how New Chat's Contacts list puts
/// named people first and leaves out numbers that a named contact already has. All data is synthetic.
final class ContactListOrderingTests: XCTestCase {
    private func candidate(
        _ name: String,
        network: String = "whatsapp",
        account: String = "wa-1",
        user: String? = nil,
        identifiers: [String] = []
    ) -> ContactCandidate {
        ContactCandidate(
            userID: user ?? "@\(UUID().uuidString):courier.local",
            name: name,
            network: network,
            accountID: account,
            identifiers: identifiers
        )
    }

    // MARK: - Is this name only a number or handle?

    func testPhoneNumbersAreNotNames() {
        for text in [
            "+12134476502",
            "+1 213-447-6502",
            "+1 (213) 447-6502",
            "(213) 447-6502",
            "213.447.6502",
            "+44 20 7946 0958",
            "+1\u{00A0}213\u{00A0}447\u{00A0}6502",
            "tel:+12134476502",
            "5550101",
        ] {
            XCTAssertTrue(ContactListOrdering.isNumberOrHandle(text), "\(text) is a phone number, not a name")
        }
    }

    func testNetworkTagAfterANumberDoesNotMakeItAName() {
        for text in ["+12134476502 (WA)", "(+1 213) 447-6502 (WA)", "+1 (213) 447-6502 (TG)", "+12134476502 (Signal)"] {
            XCTAssertTrue(ContactListOrdering.isNumberOrHandle(text), "\(text) is a number with a network tag")
        }
    }

    func testEmailsAndHandlesAreNotNames() {
        for text in ["alice@example.com", "mailto:alice@example.com", "@alice", "@alice:courier.local", "", "   "] {
            XCTAssertTrue(ContactListOrdering.isNumberOrHandle(text), "\(text) is not a name")
        }
    }

    func testRealNamesStayNamed() {
        for text in [
            "Alice Example",
            "alice",
            "Room 101",
            "Studio 54",
            "Apt 4B",
            "Route 66 Diner",
            "Alice (WA)",
            "Alice Example (work)",
            "3M Support",
            "Al@Home",
            "(WA)",
        ] {
            XCTAssertFalse(ContactListOrdering.isNumberOrHandle(text), "\(text) is a name")
        }
    }

    // MARK: - Same number, different spellings

    func testPhoneKeyIsTheSameForEverySpellingOfOneNumber() {
        let spellings = [
            "+12134476502",
            "+1 213-447-6502",
            "(213) 447-6502",
            "+1 (213) 447-6502 (WA)",
            "tel:+1 213 447 6502",
        ]
        XCTAssertEqual(Set(spellings.compactMap(ContactListOrdering.phoneKey)), ["2134476502"])
        XCTAssertNotEqual(ContactListOrdering.phoneKey("+12134476503"), "2134476502")
    }

    func testPhoneKeyIsNilForNamesAndHandles() {
        for text in ["Alice", "Room 101", "alice@example.com", "@alice", ""] {
            XCTAssertNil(ContactListOrdering.phoneKey(text), text)
        }
    }

    // MARK: - Ordering

    func testNamedPeopleComeFirstThenNumbersEachAToZ() {
        let sections = ContactListOrdering.sections([
            candidate("+12134476502"),
            candidate("Zara"),
            candidate("adam"),
            candidate("+12125550100"),
            candidate("Mia"),
        ])
        XCTAssertEqual(sections.named.map(\.name), ["adam", "Mia", "Zara"])
        XCTAssertEqual(sections.other.map(\.name), ["+12125550100", "+12134476502"])
        XCTAssertEqual(sections.ordered.map(\.name), ["adam", "Mia", "Zara", "+12125550100", "+12134476502"])
    }

    func testHandlesAndEmailsGoWithTheNumbers() {
        let sections = ContactListOrdering.sections([candidate("@bot"), candidate("Bea"), candidate("bo@example.com")])
        XCTAssertEqual(sections.named.map(\.name), ["Bea"])
        XCTAssertEqual(Set(sections.other.map(\.name)), ["@bot", "bo@example.com"])
    }

    func testAnEmptyNameCountsAsNumberOnly() {
        let sections = ContactListOrdering.sections([candidate("", user: "@x:courier.local"), candidate("Bea")])
        XCTAssertEqual(sections.named.map(\.name), ["Bea"])
        XCTAssertEqual(sections.other.map(\.userID), ["@x:courier.local"])
    }

    func testNamesWithDigitsAreSortedAmongThePeople() {
        let sections = ContactListOrdering.sections([candidate("Room 101"), candidate("+12134476502"), candidate("Zed")])
        XCTAssertEqual(sections.named.map(\.name), ["Room 101", "Zed"])
        XCTAssertEqual(sections.other.map(\.name), ["+12134476502"])
    }

    // MARK: - Duplicates

    func testNumberOnlyEntryIsDroppedWhenANamedContactHasThatNumber() {
        let alice = candidate("Alice", network: "signal", account: "sig-1", identifiers: ["+1 213-447-6502"])
        let bareE164 = candidate("+12134476502", network: "whatsapp")
        let formattedWithTag = candidate("(+1 213) 447-6502 (WA)", network: "whatsapp", account: "wa-2")
        let other = candidate("+12125550100")
        let sections = ContactListOrdering.sections([bareE164, alice, formattedWithTag, other])
        XCTAssertEqual(sections.named, [alice])
        XCTAssertEqual(sections.other, [other], "Both spellings of Alice's number go, on any network")
    }

    func testNumberOnlyEntryMatchesANamedContactThroughItsIdentifiers() {
        let alice = candidate("Alice", identifiers: ["tel:+12134476502", "mailto:alice@example.com"])
        let bare = candidate("+12134476502", identifiers: [])
        XCTAssertEqual(ContactListOrdering.sections([bare, alice]).other, [])
    }

    func testNumberOnlyEntryMatchesThroughItsOwnIdentifiers() {
        let alice = candidate("Alice", identifiers: ["+12134476502"])
        let handleWithNumber = candidate("@alice_wa", identifiers: ["+1 213 447 6502"])
        XCTAssertEqual(ContactListOrdering.sections([handleWithNumber, alice]).other, [])
    }

    func testNumberWrittenWithoutCountryCodeMatchesTheSameNumberWithIt() {
        let alice = candidate("Alice", identifiers: ["+12134476502"])
        let local = candidate("(213) 447-6502")
        XCTAssertEqual(ContactListOrdering.sections([local, alice]).other, [])
    }

    func testDifferentNumbersAreKept() {
        let alice = candidate("Alice", identifiers: ["+12134476502"])
        let stranger = candidate("+12134476503")
        XCTAssertEqual(ContactListOrdering.sections([stranger, alice]).other, [stranger])
    }

    func testNumberOnlyEntriesDoNotHideEachOtherOrNamedContactsWithoutNumbers() {
        let a = candidate("+12134476502", network: "whatsapp")
        let b = candidate("+12134476502", network: "signal", account: "sig-1")
        let bea = candidate("Bea")
        let sections = ContactListOrdering.sections([a, b, bea])
        XCTAssertEqual(sections.named, [bea])
        XCTAssertEqual(Set(sections.other.map(\.network)), ["whatsapp", "signal"], "Only a named contact removes a number")
    }

    func testTwoPeopleWithTheSameNameAreBothKept() {
        let one = candidate("Sam", network: "whatsapp")
        let two = candidate("Sam", network: "signal", account: "sig-1")
        XCTAssertEqual(ContactListOrdering.sections([two, one]).named.count, 2)
    }

    func testNothingIsLostOrInvented() {
        let all = [
            candidate("Alice", identifiers: ["+12134476502"]),
            candidate("+12134476502"),
            candidate("Room 101"),
            candidate("@bot"),
            candidate("+12125550100"),
        ]
        let sections = ContactListOrdering.sections(all)
        XCTAssertEqual(sections.ordered.count, all.count - 1, "Only the duplicate number is dropped")
        XCTAssertEqual(Set(sections.ordered.map(\.id)).count, sections.ordered.count)
    }
}
