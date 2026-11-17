// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class ChatEncryptionTests: XCTestCase {
    /// Every network the app knows, with what Chat Info says about it for a room the bridge on this Mac marks as
    /// encrypted (`RoomInfoResult.encrypted`) and for one it doesn't. The flag is only that hop: a WhatsApp chat is
    /// end-to-end encrypted on WhatsApp's side whatever it says.
    func testEncryptionPerNetwork() {
        enum Answer { case e2e, notE2E, notConfirmed }
        let table: [(network: String, name: String, roomFlag: Answer, noFlag: Answer)] = [
            ("whatsapp", "WhatsApp", .e2e, .e2e),
            ("signal", "Signal", .e2e, .e2e),
            ("imessage", "iMessage", .e2e, .e2e),
            ("gmessages", "Google Messages", .e2e, .notConfirmed),
            ("facebook", "Facebook Messenger", .e2e, .notE2E),
            ("instagram", "Instagram", .e2e, .notE2E),
            ("telegram", "Telegram", .notE2E, .notE2E),
            ("slack", "Slack", .notE2E, .notE2E),
            ("gchat", "Google Chat", .notE2E, .notE2E),
            ("discord", "Discord", .notE2E, .notE2E),
            ("twitter", "X", .notE2E, .notE2E),
            ("linkedin", "LinkedIn", .notE2E, .notE2E),
            ("gvoice", "Google Voice", .notE2E, .notE2E),
            ("bluesky", "Bluesky", .notE2E, .notE2E),
        ]
        func check(_ got: ChatEncryption, _ want: Answer, _ name: String, _ message: String) {
            switch want {
            case .e2e: XCTAssertEqual(got, .endToEnd(networkName: name), message)
            case .notE2E: XCTAssertEqual(got, .notEndToEnd(networkName: name), message)
            case .notConfirmed: XCTAssertEqual(got, .notConfirmed(networkName: name), message)
            }
        }
        for row in table {
            check(ChatEncryption.of(network: row.network, roomEncrypted: true), row.roomFlag, row.name, "\(row.network), room encrypted")
            check(ChatEncryption.of(network: row.network, roomEncrypted: false), row.noFlag, row.name, "\(row.network), room not encrypted")
        }
        // Every network the app names is in the table: none is left to a guess.
        XCTAssertEqual(Set(table.map(\.network)), Set(NetworkNames.names.keys))
    }

    func testWhatsAppIsNeverSaidToBeUnencryptedAndSaysWhyItIsDecryptedHere() {
        let info = RoomInfoResult(roomID: "!r:x", name: "Alice", remoteName: "Alice", network: "whatsapp",
                                  isDirect: true, encrypted: false, features: ChatFeatures(reply: true, edit: false, unsend: false, deleteReachesPhone: true, source: .stored))
        let result = ChatEncryption.of(info)
        XCTAssertEqual(result.title, "End-to-end encrypted on WhatsApp")
        XCTAssertEqual(result.note, "Messages are decrypted on this Mac to show them here.")
        XCTAssertEqual(result.symbolName, "lock.fill")
    }

    func testNetworksWithoutEndToEndSayNotAndShowAnOpenPadlock() {
        let result = ChatEncryption.of(network: "slack", roomEncrypted: false)
        XCTAssertEqual(result.title, "Not end-to-end encrypted on Slack")
        XCTAssertNil(result.note)
        XCTAssertEqual(result.symbolName, "lock.open")
    }

    func testAnUnknownNetworkIsNeverClaimedToBeEncrypted() {
        let result = ChatEncryption.of(network: "newchat", roomEncrypted: true)
        XCTAssertEqual(result, .notEndToEnd(networkName: "this network"))
        XCTAssertEqual(result.title, "Not end-to-end encrypted on this network")
    }

    func testGoogleMessagesNeitherClaimsNorDeniesWhenItCannotTellRCSFromSMS() {
        let result = ChatEncryption.of(network: "gmessages", roomEncrypted: false)
        XCTAssertEqual(result.title, "End-to-end encryption isn’t confirmed on Google Messages")
        XCTAssertEqual(result.symbolName, "lock.open")
        XCTAssertNotNil(result.note)
    }
}
