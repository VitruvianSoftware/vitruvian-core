// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Tests for `ContactsBridge`, E.164 phone/email normalization, on-demand Contacts authorization,
/// privacy isolation from the engine, and the 0.5s sender hover card controller. All data is synthetic.
@MainActor
final class ContactsBridgeTests: XCTestCase {
    private var harnesses: [ConversationHarness] = []

    override func tearDown() async throws {
        for harness in harnesses { await harness.stop() }
        harnesses = []
    }

    func testMatchesNormalizedPhoneAndEmail() async {
        let alice = MatchedContact(
            contactIdentifier: "cn-alice-1",
            fullName: "Alice Example",
            organization: "Example Corp",
            phones: ["+1 (555) 010-0101"],
            emails: ["alice@example.com"]
        )
        let store = FakeContactsStore(status: .authorized, contacts: [alice])
        let bridge = ContactsBridge(store: store)

        // Matches E.164 normalized phone across formatting differences.
        let matchedByPhone = store.match(identifiers: ["tel:+15550100101"], fallbackName: "Alice")
        XCTAssertEqual(matchedByPhone?.fullName, "Alice Example")

        await bridge.loadMatch(identifiers: ["tel:+15550100101"], fallbackName: "Alice")
        XCTAssertEqual(bridge.matchedContact?.fullName, "Alice Example")

        // Whole-number E.164 comparison: +1 555-010-0101 never matches +44 555-010-0101.
        let mismatchedCountry = store.match(identifiers: ["tel:+445550100101", "+44 555-010-0101"], fallbackName: "Alice")
        XCTAssertNil(mismatchedCountry)

        // Matches case-insensitive email with mailto: prefix.
        let matchedByEmail = store.match(identifiers: ["mailto:ALICE@example.com"], fallbackName: "Alice")
        XCTAssertEqual(matchedByEmail?.fullName, "Alice Example")
    }

    func testDeniedAuthorizationDoesNotPromptAndReportsDenied() async throws {
        let alice = MatchedContact(
            contactIdentifier: "cn-alice-1",
            fullName: "Alice Example",
            organization: "Example Corp",
            phones: ["+1 (555) 010-0101"],
            emails: ["alice@example.com"]
        )
        let deniedStore = FakeContactsStore(status: .denied, contacts: [alice])
        let deniedBridge = ContactsBridge(store: deniedStore)

        // Never prompts at launch/init.
        XCTAssertEqual(deniedStore.requestAccessCalls, 0)
        XCTAssertEqual(deniedBridge.status, .denied)
        XCTAssertTrue(deniedBridge.isAccessDenied)
        XCTAssertNil(deniedBridge.matchedContact)

        // Opening hover card's Contacts section when denied never prompts again.
        await deniedBridge.loadMatch(identifiers: ["tel:+15550100101"], fallbackName: "Alice")
        XCTAssertEqual(deniedBridge.status, .denied)
        XCTAssertEqual(deniedStore.requestAccessCalls, 0)
        XCTAssertTrue(deniedBridge.isAccessDenied)
        XCTAssertNil(deniedBridge.matchedContact)

        // Restricted also never prompts and reports access denied.
        let restrictedStore = FakeContactsStore(status: .restricted, contacts: [alice])
        let restrictedBridge = ContactsBridge(store: restrictedStore)
        await restrictedBridge.loadMatch(identifiers: ["tel:+15550100101"], fallbackName: "Alice")
        XCTAssertEqual(restrictedStore.requestAccessCalls, 0)
        XCTAssertTrue(restrictedBridge.isAccessDenied)
        XCTAssertNil(restrictedBridge.matchedContact)

        // When notDetermined, does not prompt at init, and prompts once on first on-demand use.
        let promptStore = FakeContactsStore(status: .notDetermined, requestGrantResult: true, contacts: [alice])
        let promptBridge = ContactsBridge(store: promptStore)
        XCTAssertEqual(promptStore.requestAccessCalls, 0)
        await promptBridge.loadMatch(identifiers: ["tel:+15550100101"], fallbackName: "Alice")
        XCTAssertEqual(promptStore.requestAccessCalls, 1)
        XCTAssertEqual(promptBridge.status, .authorized)
        XCTAssertEqual(promptBridge.matchedContact?.fullName, "Alice Example")
    }

    func testSaveNewContactPersistsAndReturnsMatchedContact() async throws {
        let store = FakeContactsStore(status: .authorized, contacts: [])
        let bridge = ContactsBridge(store: store)

        let saved = try store.saveNewContact(
            givenName: "Bob",
            familyName: "Carter",
            phone: "+15550100202",
            email: nil
        )
        XCTAssertEqual(saved.fullName, "Bob Carter")
        XCTAssertEqual(saved.phones, ["+15550100202"])

        let savedViaBridge = try await bridge.saveContact(
            givenName: "Clara",
            familyName: "Oswald",
            phone: "+15550100303",
            email: "clara@example.com"
        )
        XCTAssertEqual(savedViaBridge.fullName, "Clara Oswald")
        XCTAssertEqual(bridge.matchedContact?.fullName, "Clara Oswald")
    }

    private func aliceEvent(id: String, room: String, at n: Int64, body: String = "Hello") -> [String: Any] {
        var event = textEvent(id: id, room: room, at: n, body: body, mine: false)
        event["sender"] = "@alice:courier.local"
        event["sender_name"] = "Alice"
        return event
    }

    func testContactsDataNeverSentToEngine() async throws {
        let secretContact = MatchedContact(
            contactIdentifier: "cn-secret-99",
            fullName: "Alice SecretContactName",
            organization: "TopSecretOrg",
            phones: ["+1 (555) 010-0101"],
            emails: ["alice.secret@example.com"]
        )
        let store = FakeContactsStore(status: .authorized, contacts: [secretContact])
        let time = FakeTime()
        let event = aliceEvent(id: "$m1", room: "!g", at: 1)
        let h = try await startConversation(
            ["!g": [event]],
            features: ["!g": featuresJSON()],
            rows: ["!g": chatRow("!g", name: "Team", network: "signal", direct: false)],
            sleep: { try await time.sleep(for: $0) }
        )
        harnesses.append(h)
        h.script.roomInfos["!g"] = [
            "room_id": "!g",
            "name": "Team",
            "remote_name": "Team",
            "local_name": "",
            "topic": "",
            "avatar_path": "",
            "local_avatar_uri": "",
            "network": "signal",
            "account_id": "signal_1",
            "is_direct": false,
            "encrypted": true,
            "disappearing_ms": 0,
            "pinned_event_ids": [String](),
            "members": [
                [
                    "user_id": "@alice:courier.local",
                    "name": "Alice",
                    "avatar_path": "",
                    "power_level": 0,
                    "is_admin": false,
                    "identifiers": ["tel:+15550100101"],
                    "tz": "America/Los_Angeles",
                    "is_bot": false,
                ] as [String: Any],
            ],
            "shared_media": [[String: Any]](),
            "shared_files": [[String: Any]](),
            "shared_links": [[String: Any]](),
            "features": featuresJSON(),
        ]
        h.conversation.contactsBridge = ContactsBridge(store: store)
        try await h.open("!g")

        h.conversation.selectedMessageID = "$m1"
        await h.conversation.showSenderCardForSelectedMessage()
        XCTAssertEqual(h.conversation.contactsBridge.matchedContact?.fullName, "Alice SecretContactName")

        _ = try await h.conversation.contactsBridge.saveContact(
            givenName: "Bob",
            familyName: "PrivateSurname",
            phone: "+15550100999",
            email: "bob.private@example.com"
        )

        // Verify no engine RPC request ever contains anything from Contacts.
        let serializedRequests = try JSONSerialization.data(withJSONObject: h.server.received)
        let payload = String(decoding: serializedRequests, as: UTF8.self)
        for forbidden in [
            "Alice SecretContactName",
            "TopSecretOrg",
            "alice.secret@example.com",
            "cn-secret-99",
            "PrivateSurname",
            "+15550100999",
            "bob.private@example.com",
        ] {
            XCTAssertFalse(payload.contains(forbidden), "Engine RPC payload leaked contact field: \(forbidden)")
        }
    }

    func testHoverCardWaitsHalfSecondAndClosesWhenPointerLeavesTriggerAndCard() async throws {
        let time = FakeTime()
        let event = aliceEvent(id: "$m1", room: "!g", at: 1)
        let h = try await startConversation(
            ["!g": [event]],
            features: ["!g": featuresJSON()],
            rows: ["!g": chatRow("!g", name: "Team", network: "signal", direct: false)],
            sleep: { try await time.sleep(for: $0) }
        )
        harnesses.append(h)
        h.conversation.contactsBridge = ContactsBridge(store: FakeContactsStore(status: .authorized, contacts: []))
        try await h.open("!g")
        let message = try XCTUnwrap(h.message("$m1"))

        // Early leave before 0.5s does not open the card.
        h.conversation.setTriggerHovered(true, for: message)
        try await waitUntil { time.pendingSleeps.count == 1 }
        XCTAssertEqual(time.pendingSleeps.first ?? 0, 0.5, accuracy: 0.001)
        time.advance(0.2)
        h.conversation.setTriggerHovered(false, for: message)
        time.advance(0.5)
        await Task.yield()
        XCTAssertNil(h.conversation.activeSenderCard)

        // Steady hover for 0.5s opens the card.
        h.conversation.setTriggerHovered(true, for: message)
        try await waitUntil { time.pendingSleeps.count == 1 }
        time.advance(0.3)
        await Task.yield()
        XCTAssertNil(h.conversation.activeSenderCard, "Must not open at 0.3s before 0.5s steady hover completes")

        time.advance(0.2)
        try await waitUntil { h.conversation.activeSenderCard?.userID == "@alice:courier.local" }

        // Moving pointer from trigger onto card keeps the card open.
        h.conversation.setCardHovered(true)
        h.conversation.setTriggerHovered(false, for: message)
        XCTAssertEqual(h.conversation.activeSenderCard?.userID, "@alice:courier.local")

        // Leaving the card as well closes it immediately.
        h.conversation.setCardHovered(false)
        XCTAssertNil(h.conversation.activeSenderCard)
    }
}
