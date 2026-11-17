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
            ("facebook", "Facebook Messenger", .e2e, .notConfirmed),
            ("instagram", "Instagram", .e2e, .notConfirmed),
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

    /// A network the app doesn't know is not called unencrypted, and is called encrypted only when its room says so.
    func testAnUnknownNetworkIsEncryptedOnlyWhenItsRoomSaysSoElseNotConfirmed() {
        let flagged = ChatEncryption.of(network: "newchat", roomEncrypted: true)
        XCTAssertEqual(flagged, .endToEnd(networkName: "this network"))
        XCTAssertEqual(flagged.title, "End-to-end encrypted on this network")
        let unflagged = ChatEncryption.of(network: "newchat", roomEncrypted: false)
        XCTAssertEqual(unflagged, .notConfirmed(networkName: "this network"))
        XCTAssertEqual(unflagged.title, "End-to-end encryption isn’t confirmed on this network")
        XCTAssertEqual(unflagged.symbolName, "lock.open")
    }

    /// Messenger and Instagram encrypt some chats only: with no flag on the room the answer is "isn't confirmed",
    /// not a claim that the chat is unencrypted.
    func testMessengerAndInstagramRoomsThatAreNotFlaggedAreNotConfirmed() {
        for (network, name) in [("facebook", "Facebook Messenger"), ("instagram", "Instagram")] {
            XCTAssertEqual(ChatEncryption.of(network: network, roomEncrypted: false), .notConfirmed(networkName: name))
            XCTAssertEqual(ChatEncryption.of(network: network, roomEncrypted: true), .endToEnd(networkName: name))
        }
    }

    func testGoogleMessagesNeitherClaimsNorDeniesWhenItCannotTellRCSFromSMS() {
        let result = ChatEncryption.of(network: "gmessages", roomEncrypted: false)
        XCTAssertEqual(result.title, "End-to-end encryption isn’t confirmed on Google Messages")
        XCTAssertEqual(result.symbolName, "lock.open")
        XCTAssertNotNil(result.note)
    }

    func testTheNoteSaysWhichChatsAreEncryptedOnlyForGoogleMessages() {
        XCTAssertEqual(ChatEncryption.of(network: "gmessages", roomEncrypted: false).note,
                       "RCS chats are end-to-end encrypted and SMS texts aren’t, and this chat doesn’t say which it is.")
        XCTAssertEqual(ChatEncryption.of(network: "facebook", roomEncrypted: false).note,
                       "This chat doesn’t say whether it is end-to-end encrypted.")
    }
}
