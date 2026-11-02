// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Holds Protocol.swift to apps/desktop/courier/protocol: protocol.json is the definition, and the engine's Go
/// tests check the same examples against it, so neither side can drift from the other.
///
/// Under Bazel the files are the test's `data` (runfiles); under SwiftPM scripts/test.sh sets COURIER_PROTOCOL_DIR.
final class ProtocolConformanceTests: XCTestCase {
    private var spec: [String: Any] = [:]
    private var examples: [(name: String, json: [String: Any])] = []

    override func setUpWithError() throws {
        let dir = try XCTUnwrap(Self.protocolDirectory(), "protocol.json not found: run under Bazel, or set COURIER_PROTOCOL_DIR (scripts/test.sh does)")
        let specData = try Data(contentsOf: dir.appendingPathComponent("protocol.json"))
        spec = try XCTUnwrap(JSONSerialization.jsonObject(with: specData) as? [String: Any])
        let exampleDir = dir.appendingPathComponent("examples")
        let names = try FileManager.default.contentsOfDirectory(atPath: exampleDir.path)
            .filter { $0.hasSuffix(".json") }.sorted()
        for name in names {
            let data = try Data(contentsOf: exampleDir.appendingPathComponent(name))
            examples.append((name, try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], name)))
        }
        // A loop over nothing would pass without checking anything.
        XCTAssertGreaterThan(examples.count, 30, "the examples are missing")
    }

    static func protocolDirectory() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let dir = environment["COURIER_PROTOCOL_DIR"] { candidates.append(dir) }
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/apps/desktop/courier/protocol")
            }
        }
        return candidates.map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("protocol.json").path) }
    }

    private var specTypes: [String: [String: Any]] { spec["types"] as? [String: [String: Any]] ?? [:] }
    private var specMethods: [String: [String: Any]] { spec["methods"] as? [String: [String: Any]] ?? [:] }
    private var specErrors: [[String: Any]] {
        (spec["errors"] as? [String: Any])?["codes"] as? [[String: Any]] ?? []
    }

    private func swiftType(named name: String) -> (any ProtocolType.Type)? {
        ProtocolMethods.types.first { $0.protocolName == name }
    }

    // MARK: - The definition

    func testProtocolNumberAndFrameLimitMatch() {
        XCTAssertEqual(spec["protocol"] as? Int, CourierProtocol.version)
        XCTAssertEqual((spec["transport"] as? [String: Any])?["max_frame_bytes"] as? Int, CourierProtocol.maxFrameBytes)
    }

    func testEveryTypeIsNamedAndHasExactlyItsFields() {
        XCTAssertEqual(Set(ProtocolMethods.types.map { $0.protocolName }), Set(specTypes.keys),
                       "Swift's types must be named exactly as protocol.json's")
        for (name, definition) in specTypes {
            guard let type = swiftType(named: name) else { continue }
            let fields = (definition["fields"] as? [String: Any] ?? [:]).keys
            XCTAssertEqual(Set(type.fieldNames), Set(fields), "\(name)'s fields")
            XCTAssertEqual(type.fieldNames.count, Set(type.fieldNames).count, "\(name) names a field twice")
        }
    }

    func testEveryValuesListMatches() {
        var listed: [String: [String]] = [:]
        for (name, definition) in specTypes {
            for (field, spec) in definition["fields"] as? [String: [String: Any]] ?? [:] {
                if let values = spec["values"] as? [String] { listed["\(name).\(field)"] = values }
            }
        }
        XCTAssertEqual(ProtocolMethods.values, listed)
    }

    func testEveryMethodHasItsParamsAndResult() {
        XCTAssertEqual(Set(ProtocolMethods.all.keys), Set(specMethods.keys))
        for (method, definition) in specMethods {
            guard let types = ProtocolMethods.all[method] else { continue }
            XCTAssertEqual(types.params.protocolName, definition["params"] as? String, "\(method)'s params")
            XCTAssertEqual(types.result.protocolName, definition["result"] as? String, "\(method)'s result")
        }
        let notifications = spec["notifications"] as? [String: [String: Any]] ?? [:]
        XCTAssertEqual(Set(notifications.keys), Set(ProtocolMethods.notifications.keys))
        for (name, definition) in notifications {
            XCTAssertEqual(ProtocolMethods.notifications[name]?.protocolName, definition["params"] as? String,
                           "\(name)'s params")
        }
    }

    func testEveryErrorCodeIsKnown() {
        let listed = specErrors.map { "\($0["code"] as? Int ?? 0) \($0["name"] as? String ?? "")" }
        let known = RPCErrorCode.known.map { "\($0.number) \($0.name)" }
        XCTAssertEqual(known, listed)
        for entry in RPCErrorCode.known {
            XCTAssertEqual(RPCErrorCode(number: entry.number), entry.code)
            XCTAssertEqual(entry.code.number, entry.number)
        }
        XCTAssertEqual(RPCErrorCode(number: -32099), .other(-32099))
    }

    /// The typing pulse is one number on both sides, read from protocol.json (the engine's Go test reads the same).
    func testTypingRepeatMatchesTheProtocol() throws {
        let conventions = try XCTUnwrap(spec["conventions"] as? [String: Any], "protocol.json has conventions")
        let millis = try XCTUnwrap(conventions["typing_repeat_ms"] as? Int)
        XCTAssertEqual(millis, 4000)
        XCTAssertEqual(CourierProtocol.typingRepeatMillis, millis)
        XCTAssertEqual(Int((ComposerModel.typingRepeat * 1000).rounded()), millis)
    }

    // MARK: - The examples

    /// Every value of a message's status and of a row's preview status, as protocol.json names them, has an example
    /// that shows it (the engine's conformance test asks the same), so each is checked on the wire here.
    func testEveryStatusValueHasAnExample() throws {
        var statuses = Set<String>(), previews = Set<String>()
        func collect(_ value: Any) {
            if let object = value as? [String: Any] {
                if object["event_id"] != nil, let status = object["status"] as? String { statuses.insert(status) }
                if object["room_id"] != nil, let preview = object["preview_status"] as? String {
                    previews.insert(preview)
                }
                object.values.forEach(collect)
            } else if let array = value as? [Any] {
                array.forEach(collect)
            }
        }
        for (_, example) in examples { collect(example) }
        XCTAssertEqual(statuses, Set(EventStatus.known.map(\.rawValue)))
        XCTAssertEqual(previews, Set(PreviewStatus.known.map(\.rawValue)))
    }

    /// The protocol 5 examples read as the app shows them: who read my message, a waiting one and one with no
    /// account, and the receipt change.
    func testProtocolFiveExamplesReadAsTheAppShowsThem() throws {
        func result<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            let example = try XCTUnwrap(examples.first { $0.name == name }?.json, name)
            let response = try XCTUnwrap(example["response"] as? [String: Any], name)
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: response["result"]!))
        }
        let now = Date(timeIntervalSince1970: 1_760_700_000)
        func lines(_ page: EventsPage, direct: Bool) -> [StatusLine?] {
            Timeline.build(events: page.events, me: Timeline.meUserID, now: now, isDirect: direct)
                .compactMap { if case let .message(m) = $0 { m.statusLine } else { nil } }
        }

        let receipts = try result("room.events-receipts.json", as: EventsPage.self)
        XCTAssertEqual(lines(receipts, direct: true), [nil, .seen(by: [], at: 1_760_600_020_000)],
                       "oldest first: theirs has no line, mine says Seen with the receipt's time")
        XCTAssertEqual(lines(receipts, direct: false).last, .seen(by: ["Contact One"], at: nil))

        let noAccount = try result("room.events-waiting-no-account.json", as: EventsPage.self)
        XCTAssertEqual(lines(noAccount, direct: true), [.noAccount])
        let waiting = try result("room.events-waiting.json", as: EventsPage.self)
        XCTAssertTrue(lines(waiting, direct: true).contains(.waiting))

        let notification = try XCTUnwrap(examples.first { $0.name == "changed-receipt.json" }?.json["notification"]
            as? [String: Any])
        let params = try JSONSerialization.data(withJSONObject: try XCTUnwrap(notification["params"]))
        let changed = try JSONDecoder().decode(Changed.self, from: params)
        XCTAssertEqual(Change(changed), .receipt(roomID: "!4f1c2b7a9d0e3f56a8b1c2d3e4f5a6b7:courier.local"))
        XCTAssertEqual(Change(Changed(kind: .receipt)), .resync, "a receipt change without its chat reads everything")

        let accounts = try result("accounts.list-two-accounts.json", as: AccountsResult.self)
        XCTAssertTrue(accounts.accounts.contains { $0.logins.count == 2 }, "a network with two accounts")
        let direct = try result("room.directChat.json", as: RoomResult.self)
        XCTAssertEqual(direct.roomID, "!4f1c2b7a9d0e3f56a8b1c2d3e4f5a6b7:courier.local")
    }

    func testEveryExampleDecodesAndReencodes() throws {
        var checked = 0
        for (name, example) in examples {
            if let request = example["request"] as? [String: Any] {
                let method = try XCTUnwrap(request["method"] as? String, name)
                guard let types = ProtocolMethods.all[method] else {
                    // Only an example of an unknown method may name one, and its answer is method_not_found.
                    let error = (example["response"] as? [String: Any])?["error"] as? [String: Any]
                    XCTAssertEqual(error?["code"] as? Int, -32601, "\(name): unknown method \(method)")
                    checked += 2
                    continue
                }
                if let params = request["params"] {
                    try assertRoundTrip(params, as: types.params, in: "\(name) params")
                    checked += 1
                }
                let response = try XCTUnwrap(example["response"] as? [String: Any], name)
                if let result = response["result"] {
                    try assertRoundTrip(result, as: types.result, in: "\(name) result")
                    checked += 1
                }
                if let error = response["error"] as? [String: Any] {
                    try assertError(error, method: method, in: name)
                    checked += 1
                }
            } else if let notification = example["notification"] as? [String: Any] {
                let method = try XCTUnwrap(notification["method"] as? String, name)
                let type = try XCTUnwrap(ProtocolMethods.notifications[method], "\(name): unknown notification \(method)")
                let params = try XCTUnwrap(notification["params"], name)
                try assertRoundTrip(params, as: type, in: "\(name) params")
                guard method == ProtocolMethods.changedNotification else {
                    checked += 1
                    continue
                }
                let changed = try JSONDecoder().decode(Changed.self, from: JSONSerialization.data(withJSONObject: params))
                if changed.kind == .resync {
                    XCTAssertEqual(Change(changed), .resync, name)
                } else {
                    XCTAssertNotEqual(Change(changed), .resync, "\(name) reads as a resync")
                }
                checked += 1
            } else {
                XCTFail("\(name) is neither a request nor a notification")
            }
        }
        XCTAssertGreaterThan(checked, examples.count)
    }

    private func assertRoundTrip(_ value: Any, as type: any ProtocolType.Type, in context: String) throws {
        let original = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        let reencoded: Data
        do {
            reencoded = try type.roundTrip(original)
        } catch {
            XCTFail("\(context) does not decode as \(type.protocolName): \(error)")
            return
        }
        let again = try JSONSerialization.jsonObject(with: reencoded, options: [.fragmentsAllowed])
        // Every key the example has must come back, with its value, and nothing else: a key Swift does not know
        // would be dropped here, and a T|null written as absent would be missing.
        XCTAssertEqual(again as? NSObject, value as? NSObject,
                       "\(context): \(type.protocolName) re-encodes as \(String(decoding: reencoded, as: UTF8.self))")
    }

    private func assertError(_ error: [String: Any], method: String, in context: String) throws {
        let number = try XCTUnwrap(error["code"] as? Int, context)
        let entry = try XCTUnwrap(specErrors.first { $0["code"] as? Int == number }, "\(context): code \(number)")
        XCTAssertEqual(error["message"] as? String, entry["message"] as? String, context)
        if case .other = RPCErrorCode(number: number) { XCTFail("\(context): \(number) is not known to Swift") }
        // A method may give its own codes, and every method the general ones.
        let general = [-32700, -32600, -32601, -32602, -32603, -32002] + (method == "hello" ? [-32001] : [])
        let own = specMethods[method]?["errors"] as? [Int] ?? []
        XCTAssertTrue((general + own).contains(number), "\(context): \(method) may not give \(number)")
        if let dataType = entry["data"] as? String {
            let data = try XCTUnwrap(error["data"], "\(context): \(number) carries \(dataType)")
            try assertRoundTrip(data, as: try XCTUnwrap(swiftType(named: dataType)), in: "\(context) data")
        }
    }

    func testProtocol6TypesDecodeAndRoundTrip() throws {
        XCTAssertEqual(protocolVersion, 12)
        XCTAssertEqual(CourierProtocol.version, 12)
        XCTAssertEqual(RPCErrorCode(number: -32027), .networkRefused)

        let infoJSON = """
        {
          "room_id": "!grp:courier.local",
          "name": "Weekend Crew",
          "remote_name": "Saturday Hike",
          "local_name": "Weekend Crew",
          "topic": "Trail plans",
          "avatar_path": "/tmp/avatar.png",
          "local_avatar_uri": "mxc://courier.local/local1",
          "network": "whatsapp",
          "account_id": "whatsapp-1",
          "is_direct": false,
          "encrypted": true,
          "disappearing_ms": 86400000,
          "pinned_event_ids": ["$pin1"],
          "members": [
            {
              "user_id": "@wa_alice:courier.local",
              "name": "Alice Example",
              "avatar_path": "",
              "power_level": 100,
              "is_admin": true,
              "identifiers": ["+15550100101"],
              "tz": "America/New_York",
              "is_bot": false
            }
          ],
          "shared_media": [],
          "shared_files": [],
          "shared_links": [
            {
              "event_id": "$e1",
              "sender": "@wa_alice:courier.local",
              "ts": 1700000000000,
              "url": "https://example.com/map",
              "host": "example.com"
            }
          ],
          "features": {
            "reply": true,
            "thread": false,
            "reply_is_thread": false,
            "edit": true,
            "edit_max_age_ms": 900000,
            "edit_max_count": 0,
            "unsend": true,
            "unsend_max_age_ms": 0,
            "delete_reaches_phone": false,
            "hide_deleted_placeholder": false,
            "poll": null,
            "disappearing": null,
            "current_timer": null,
            "formatting": [],
            "mention_room": false,
            "max_text_length": 65536,
            "source": "network",
            "can_set_name": true,
            "can_set_topic": true,
            "can_set_avatar": true,
            "can_invite": true,
            "can_kick": true,
            "can_set_admin": false,
            "can_leave": true,
            "can_delete": false,
            "delete_leaves_group": false
          }
        }
        """.data(using: .utf8)!

        let info = try JSONDecoder().decode(RoomInfoResult.self, from: infoJSON)
        XCTAssertEqual(info.name, "Weekend Crew")
        XCTAssertEqual(info.remoteName, "Saturday Hike")
        XCTAssertEqual(info.localName, "Weekend Crew")
        XCTAssertTrue(info.encrypted)
        XCTAssertEqual(info.members.first?.isAdmin, true)
        XCTAssertEqual(info.members.first?.identifiers, ["+15550100101"])
        XCTAssertEqual(info.members.first?.tz, "America/New_York")
        XCTAssertEqual(info.sharedLinks.first?.host, "example.com")
        XCTAssertTrue(info.features.canSetName)
        XCTAssertFalse(info.features.canSetAdmin)

        let merge = MergedChat(
            mergeID: "merge:1",
            name: "Alice Example",
            avatarPath: "",
            lastRoomID: "!wa:courier.local",
            roomIDs: ["!wa:courier.local", "!sig:courier.local"],
            networks: ["whatsapp", "signal"],
            createdTS: 1_700_000_000_000
        )
        let data = try JSONEncoder().encode(merge)
        let decodedMerge = try JSONDecoder().decode(MergedChat.self, from: data)
        XCTAssertEqual(decodedMerge, merge)
    }

    func testProtocol8StickerAndGIFTypesDecodeAndRoundTrip() throws {
        var features = ChatFeatures.noFeatures
        features.sticker = MediaCapFeature(
            supported: true,
            mimeTypes: ["image/png", "image/webp"],
            captions: false,
            maxCaptionLength: nil,
            maxSize: 1_048_576
        )
        features.gif = MediaCapFeature(
            supported: true,
            mimeTypes: ["image/gif", "video/mp4"],
            captions: true,
            maxCaptionLength: 1024,
            maxSize: 16_777_216
        )
        XCTAssertTrue(features.sticker.supported)
        XCTAssertEqual(features.sticker.mimeTypes, ["image/png", "image/webp"])
        XCTAssertEqual(features.sticker.maxSize, 1_048_576)
        XCTAssertTrue(features.gif.supported)
        XCTAssertTrue(features.gif.captions)
        XCTAssertEqual(features.gif.maxCaptionLength, 1024)

        let item = StickerItemWire(
            id: "bridge:telegram:pack1:smile",
            packID: "bridge:telegram:pack1",
            shortcode: "smile_cat",
            name: "Smiling Cat",
            emoji: "😺",
            mediaURL: "courier://media/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            mimeType: "image/webp",
            width: 512,
            height: 512,
            usage: ["sticker", "emoticon"],
            bridgedSticker: BridgedStickerWire(network: "telegram", packURL: "tg://addstickers?set=cats", id: "doc1")
        )
        let listResult = StickersListResult(
            packs: [
                StickerPackWire(id: "bridge:telegram:pack1", title: "Cats", source: "bridge", network: "telegram", items: [item]),
            ],
            recentGIFs: []
        )
        let listData = try JSONEncoder().encode(listResult)
        XCTAssertEqual(try JSONDecoder().decode(StickersListResult.self, from: listData), listResult)

        let sendSticker = MessageSendStickerParams(
            roomID: "!a:courier.local",
            mediaURL: item.mediaURL,
            name: item.name,
            emoji: item.emoji,
            mimeType: item.mimeType,
            bridgedSticker: item.bridgedSticker,
            replyTo: "$r1",
            threadRoot: "$t1",
            holdMS: 2000
        )
        let sendData = try JSONEncoder().encode(sendSticker)
        XCTAssertEqual(try JSONDecoder().decode(MessageSendStickerParams.self, from: sendData), sendSticker)
    }

    func testProtocol9BridgesSubAccountsAndDiagnosticsDecodeAndRoundTrip() throws {
        XCTAssertEqual(CourierProtocol.version, 12)
        XCTAssertNotNil(ProtocolMethods.all["bridges.list"])
        XCTAssertNotNil(ProtocolMethods.all["bridges.restart"])
        XCTAssertNotNil(ProtocolMethods.all["accounts.remove"])
        XCTAssertNotNil(ProtocolMethods.all["accounts.subAccounts"])
        XCTAssertNotNil(ProtocolMethods.all["accounts.setSubAccount"])
        XCTAssertNotNil(ProtocolMethods.all["diagnostics.export"])

        let account = Account(
            network: "whatsapp",
            displayName: "WhatsApp",
            flows: ["qr"],
            state: .connected,
            remoteName: "+15550100101",
            syncs: [.pin, .mute],
            logins: [Login(accountID: "wa-1", remoteName: "+15550100101", state: .connected)]
        )
        let bridge = BridgeInfo(
            network: "whatsapp",
            displayName: "WhatsApp",
            bridgeID: "whatsapp",
            modulePath: "go.mau.fi/mautrix-whatsapp",
            version: "v0.2609.0",
            mautrixVersion: "v0.31.0",
            state: "CONNECTED",
            startedAt: 1_760_600_000_000,
            accounts: [account]
        )
        let bridgesRes = BridgesResult(bridges: [bridge])
        let bridgesData = try JSONEncoder().encode(bridgesRes)
        XCTAssertEqual(try JSONDecoder().decode(BridgesResult.self, from: bridgesData), bridgesRes)

        let sub = SubAccountItem(
            network: "slack",
            accountID: "slack-1",
            subID: "!space1:courier.local",
            title: "Acme Workspace",
            avatarURI: "mxc://courier.local/acme",
            kind: "space",
            enabled: true,
            showInInbox: .all
        )
        let subRes = SubAccountsResult(subAccounts: [sub])
        let subData = try JSONEncoder().encode(subRes)
        XCTAssertEqual(try JSONDecoder().decode(SubAccountsResult.self, from: subData), subRes)

        let diag = DiagnosticsExportResult(
            protocolVersion: 10,
            schemaVersion: 10,
            goVersion: "go1.26.2",
            bridges: [bridge],
            scrubbedStderr: ["panic: [redacted]"],
            roomDetails: RoomDiagnostic(roomID: "!r:courier.local", network: "whatsapp", isDirect: true),
            messageDetails: MessageDiagnostic(
                eventID: "$e1",
                roomID: "!r:courier.local",
                network: "whatsapp",
                type: "m.room.message",
                ts: 1_760_600_000_000,
                status: "failed",
                statusReason: "token [id] rejected",
                hasMedia: false,
                isRedacted: false
            )
        )
        let diagData = try JSONEncoder().encode(diag)
        XCTAssertEqual(try JSONDecoder().decode(DiagnosticsExportResult.self, from: diagData), diag)
    }

    func testProtocol11StorageUsageAndCleanupDecodeAndRoundTrip() throws {
        XCTAssertEqual(CourierProtocol.version, 12)
        XCTAssertNotNil(ProtocolMethods.all["storage.usage"])
        XCTAssertNotNil(ProtocolMethods.all["storage.cleanup"])
        XCTAssertEqual(ProtocolMethods.classification(for: "storage.usage"), .userInitiatedMutation)
        XCTAssertEqual(ProtocolMethods.classification(for: "storage.cleanup"), .userInitiatedMutation)

        let roomUsage = RoomStorageUsage(
            roomID: "!wa1:courier.local",
            name: "Design Team",
            network: "whatsapp",
            mediaBytes: 5_376,
            itemCount: 2
        )
        let usage = StorageUsageResult(
            totalBytes: 24_900,
            databaseBytes: 16_384,
            photosAndVideosBytes: 5_376,
            audioBytes: 512,
            filesBytes: 2_048,
            stickersBytes: 280,
            otherMediaBytes: 300,
            rooms: [roomUsage]
        )
        let usageData = try JSONEncoder().encode(usage)
        XCTAssertEqual(try JSONDecoder().decode(StorageUsageResult.self, from: usageData), usage)

        let cleanupParams = StorageCleanupParams(
            roomIDs: ["!wa1:courier.local"],
            olderThanMS: 86_400_000,
            includeStickers: false
        )
        let paramsData = try JSONEncoder().encode(cleanupParams)
        XCTAssertEqual(try JSONDecoder().decode(StorageCleanupParams.self, from: paramsData), cleanupParams)

        let cleanupResult = StorageCleanupResult(freedBytes: 5_376, removedBlobs: 2)
        let resultData = try JSONEncoder().encode(cleanupResult)
        XCTAssertEqual(try JSONDecoder().decode(StorageCleanupResult.self, from: resultData), cleanupResult)
    }

    func testProtocol12IntegrationsAndFocusDecodeAndRoundTrip() throws {
        XCTAssertEqual(CourierProtocol.version, 12)
        // Settings, all of it: refused while Courier is locked.
        for method in ["integrations.status", "integrations.tokens", "integrations.update", "integrations.createToken", "integrations.revokeToken",
                       "integrations.setCanSend", "integrations.answerPairing"] {
            XCTAssertEqual(ProtocolMethods.classification(for: method), .userInitiatedMutation, method)
        }
        XCTAssertEqual(ProtocolMethods.all["integrations.tokens"]?.result.protocolName, "APIToken[]")

        // A token that was never used says so with null, not by leaving the key out.
        let unused = APIToken(id: "tok_1", name: "Example client", createdMs: 1_793_500_000_000)
        let unusedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(unused)) as? [String: Any])
        XCTAssertTrue(unusedJSON.keys.contains("lastUsedMs"))
        XCTAssertTrue(unusedJSON["lastUsedMs"] is NSNull)

        let created = CreateTokenResult(
            token: APIToken(id: "tok_2", name: "Example client", canSend: true, createdMs: 1, lastUsedMs: 2),
            secret: "courier_exampleexampleexampleexampleexampleexa" // gitleaks:allow
        )
        XCTAssertEqual(try JSONDecoder().decode(CreateTokenResult.self, from: JSONEncoder().encode(created)), created)

        // Left-out fields stay out: integrations.update changes only what it names.
        let update = try JSONSerialization.jsonObject(with: JSONEncoder().encode(IntegrationsUpdateParams(port: 24000)))
        XCTAssertEqual(update as? NSDictionary, ["port": 24000] as NSDictionary)

        let focus = FocusParams(chatID: "!a:courier.local", draftText: "Example draft")
        let focusJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(focus))
        XCTAssertEqual(focusJSON as? NSDictionary,
                       ["chatID": "!a:courier.local", "draftText": "Example draft"] as NSDictionary)
    }
}
