// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// D4: an E.164 number reads grouped, wherever a number stands in for a name. Anything else is left exactly as it was.
final class PhoneNumberFormatTests: XCTestCase {
    func testNorthAmericanNumbers() {
        XCTAssertEqual(PhoneNumberFormat.display("+19496254263"), "+1 949-625-4263")
        XCTAssertEqual(PhoneNumberFormat.display("+14165550123"), "+1 416-555-0123", "Canada shares the plan")
    }

    func testUnitedKingdomNumbers() {
        XCTAssertEqual(PhoneNumberFormat.display("+447974905044"), "+44 7974 905044")
        XCTAssertEqual(PhoneNumberFormat.display("+442079460958"), "+44 20 7946 0958", "London")
    }

    func testOtherCommonCountries() {
        XCTAssertEqual(PhoneNumberFormat.display("+61412345678"), "+61 412 345 678", "Australia, mobile")
        XCTAssertEqual(PhoneNumberFormat.display("+61212345678"), "+61 2 1234 5678", "Australia, landline")
        XCTAssertEqual(PhoneNumberFormat.display("+33612345678"), "+33 6 12 34 56 78")
        XCTAssertEqual(PhoneNumberFormat.display("+34612345678"), "+34 612 345 678")
        XCTAssertEqual(PhoneNumberFormat.display("+919876543210"), "+91 98765 43210")
        XCTAssertEqual(PhoneNumberFormat.display("+819012345678"), "+81 90 1234 5678")
        XCTAssertEqual(PhoneNumberFormat.display("+8613800138000"), "+86 138 0013 8000")
        XCTAssertEqual(PhoneNumberFormat.display("+5215512345678"), "+5215512345678",
                       "Mexico's older 11-digit form isn't the 10-digit one this knows: left alone")
        XCTAssertEqual(PhoneNumberFormat.display("+525512345678"), "+52 55 1234 5678")
        XCTAssertEqual(PhoneNumberFormat.display("+5511912345678"), "+55 11 91234 5678")
    }

    func testAnythingElseIsLeftAsItWas() {
        for text in [
            "", "Alex", "Alex Kim", "alex@example.com", "+1 949-625-4263", "19496254263", "+1949625426", "+194962542630",
            "+0949625426", "+1 (949) 625-4263", "+999123456789", "+4479749050", "+44 7974 905044 (WA)", "+1949abc4263",
            "#+19496254263",
        ] {
            XCTAssertEqual(PhoneNumberFormat.display(text), text, "\(text) must not change")
        }
    }

    func testNANPAreaCodeNeverStartsWithZeroOrOne() {
        XCTAssertEqual(PhoneNumberFormat.display("+10496254263"), "+10496254263")
        XCTAssertEqual(PhoneNumberFormat.display("+11496254263"), "+11496254263")
    }

    func testSurroundingSpaceIsKeptWhenNothingChanges() {
        XCTAssertEqual(PhoneNumberFormat.display(" Alex "), " Alex ")
        XCTAssertEqual(PhoneNumberFormat.display(" +19496254263 "), "+1 949-625-4263")
    }

    /// A search result names its sender and its group by a number the same way.
    func testSearchRowsFormatNumbersTheyShowAsNames() {
        var hit = MessageHit(eventID: "$1", roomID: "!a", roomName: "+19496254263", network: "whatsapp", isDirect: true,
                             sender: "@wa_1:courier.local", senderName: "+447974905044", mine: false, ts: 1, seq: 1,
                             snippet: "hi")
        XCTAssertEqual(hit.senderLine, "+44 7974 905044")
        hit.senderName = "Sam"
        XCTAssertEqual(hit.senderLine, "Sam")
        XCTAssertEqual(
            SearchResultLocation.subtitle(sender: "Sam", chatTitle: "+19496254263", networkName: "WhatsApp",
                                          isDirect: false),
            "Sam in +1 949-625-4263 · WhatsApp"
        )
    }
}
