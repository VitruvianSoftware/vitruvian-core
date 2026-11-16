// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// New Chat's Contacts list with bare phone numbers mixed in: named people first, the numbers after under "Other
/// numbers", and a number already listed under a name left out. Look at start-new-chat-numbers-*.
@MainActor
final class StartNewChatContactOrderTests: XCTestCase {
    private func contact(_ name: String, _ network: String, _ account: String, _ identifiers: [String] = []) -> ContactCandidate {
        ContactCandidate(
            userID: "@\(name.filter(\.isLetter))\(identifiers.first ?? ""):courier.local",
            name: name,
            network: network,
            accountID: account,
            identifiers: identifiers
        )
    }

    private var accounts: [Account] {
        [
            Account(network: "whatsapp", displayName: "WhatsApp", flows: ["qr"], state: .connected),
            Account(network: "signal", displayName: "Signal", flows: ["qr"], state: .connected),
        ]
    }

    private var candidates: [ContactCandidate] {
        [
            contact("+12134476502", "whatsapp", "wa-1"),
            contact("(+1 213) 555-0111 (WA)", "whatsapp", "wa-1"),
            contact("+12134476599", "whatsapp", "wa-1"),
            contact("Zara Example", "whatsapp", "wa-1", ["+1 213-555-0111"]),
            contact("Room 101", "signal", "sig-1"),
            contact("Adam Example", "signal", "sig-1", ["+12134476502"]),
        ]
    }

    func testNamedContactsListFirstAndDuplicateNumbersAreLeftOut() {
        let sorted = StartNewChatPresentation.sortedContacts(candidates, filter: nil)
        XCTAssertEqual(sorted.map(\.name), ["Adam Example", "Room 101", "Zara Example", "+12134476599"])
    }

    func testTheKeyboardWalksNamedThenNumbers() {
        let draft = StartNewChatDraft(accounts: accounts, candidates: candidates)
        let sorted = StartNewChatPresentation.sortedContacts(candidates, filter: nil)
        XCTAssertEqual(
            StartNewChatPresentation.navigableRowIDs(draft: draft, recentRows: []),
            sorted.map { "contact:\($0.id)" }
        )
        let last = sorted.last
        XCTAssertEqual(
            StartNewChatPresentation.candidate(forRowID: "contact:\(last?.id ?? "")", draft: draft, recentRows: []),
            last
        )
    }

    func testAnAccountFilterOnlyHidesANumberBehindAPersonWhoIsAlsoShown() {
        // Adam (Signal) has +12134476502. Filtered to WhatsApp, Adam is not shown, so his WhatsApp number stays.
        let wa = StartNewChatPresentation.sortedContacts(candidates, filter: "whatsapp")
        XCTAssertEqual(wa.map(\.name), ["Zara Example", "+12134476502", "+12134476599"])
    }

    func testListRendersWithNumbersAfterNames() throws {
        let draft = StartNewChatDraft(accounts: accounts, candidates: candidates)
        let sizes = try Snapshot.render("start-new-chat-numbers", width: 520, height: 520) {
            StartNewChatView(draft: draft)
        }
        XCTAssertEqual(sizes.count, 2)
    }
}
