// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The labels model against a stand-in engine.
@MainActor
final class LabelsModelTests: XCTestCase {
    private var harnesses: [InboxHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
    }

    private func start(rules: [[String: Any]] = [], entitlement: any EntitlementProvider = AlwaysEntitled())
        async throws -> (InboxHarness, LabelsModel) {
        let h = try await startInbox(rooms: [room("!a", ts: 100), room("!b", ts: 90, unread: 1)], autoRelease: true)
        harnesses.append(h)
        h.script.rules = rules
        let labels = LabelsModel(appModel: h.app, entitlement: entitlement)
        try await waitUntil { h.count("autoArchive.list") >= 1 }
        return (h, labels)
    }

    private func rule(_ id: Int, scope: String, trigger: String, chatType: String = "all", days: Int = 7,
                      enabled: Bool = true) -> [String: Any] {
        ["rule_id": id, "scope": scope, "trigger": trigger, "chat_type": chatType,
         "duration_ms": days * 86_400_000, "enabled": enabled]
    }

    /// The code the model's error carries.
    private func code(of error: Error) -> RPCErrorCode? {
        if case let .rpc(code, _, _)? = error as? EngineError { return code }
        return nil
    }

    // MARK: - The lists

    func testTheColourAndIconLists() {
        XCTAssertEqual(LabelsModel.maxTitle, 40)
        XCTAssertEqual(Array(LabelsModel.colors), Array(0 ..< 12))
        XCTAssertEqual(LabelsModel.icons, [
            "tag", "star", "heart", "bolt", "flag", "bookmark", "briefcase", "house", "person.2", "cart", "airplane",
            "car", "book", "graduationcap", "gamecontroller", "music.note", "camera", "leaf", "pawprint",
            "cup.and.saucer", "fork.knife", "gift", "bell", "moon",
        ])
    }

    // MARK: - Making, changing and deleting

    func testTitleIsTrimmedAndLimitedTo40() async throws {
        let (h, labels) = try await start()
        let id = try await labels.create(title: "  Work  \n", color: 3, icon: "briefcase")
        XCTAssertEqual(id, 7, "the engine's label_id")
        XCTAssertEqual(dicts(h.server.receivedParams("labels.create")),
                       dicts([["title": "Work", "color": 3, "icon": "briefcase"]]))

        // Longer than 40 characters: the first 40 are kept, and none of the spaces at the end.
        let long = String(repeating: "a", count: 39) + " " + String(repeating: "b", count: 10)
        _ = try await labels.create(title: long, color: 0, icon: "tag")
        XCTAssertEqual(h.server.receivedParams("labels.create").last?["title"] as? String,
                       String(repeating: "a", count: 39), "cut at 40 characters, then trimmed again")
        let exactly = String(repeating: "c", count: 40)
        _ = try await labels.create(title: exactly, color: 0, icon: "tag")
        XCTAssertEqual(h.server.receivedParams("labels.create").last?["title"] as? String, exactly)

        // The engine counts characters as code points: a cut never goes over, or through a letter.
        let flags = String(repeating: "🇬🇧", count: 30)
        _ = try await labels.create(title: flags, color: 0, icon: "tag")
        let sent = try XCTUnwrap(h.server.receivedParams("labels.create").last?["title"] as? String)
        XCTAssertLessThanOrEqual(sent.unicodeScalars.count, 40)
        XCTAssertEqual(sent, String(repeating: "🇬🇧", count: 20), "whole flags only")

        // Nothing but spaces is no title.
        let before = h.count("labels.create")
        do {
            _ = try await labels.create(title: "  \t ", color: 0, icon: "tag")
            XCTFail("an empty title was accepted")
        } catch {
            XCTAssertEqual(code(of: error), .badValue)
        }
        XCTAssertEqual(h.count("labels.create"), before, "nothing is asked of the engine")
        XCTAssertEqual(LabelsModel.clean("  Home "), "Home")
    }

    func testColorAndIconMustComeFromTheLists() async throws {
        let (h, labels) = try await start()
        for bad in [(-1, "tag"), (12, "tag"), (0, "tag.fill"), (0, ""), (0, "Tag")] {
            do {
                _ = try await labels.create(title: "Work", color: bad.0, icon: bad.1)
                XCTFail("accepted colour \(bad.0), icon \(bad.1)")
            } catch {
                XCTAssertEqual(code(of: error), .badValue)
            }
        }
        do {
            try await labels.update(3, title: nil, color: 12, icon: nil)
            XCTFail("accepted colour 12")
        } catch {
            XCTAssertEqual(code(of: error), .badValue)
        }
        do {
            try await labels.update(3, title: nil, color: nil, icon: "not.a.courier.symbol")
            XCTFail("accepted a symbol that is not in the list")
        } catch {
            XCTAssertEqual(code(of: error), .badValue)
        }
        XCTAssertEqual(h.count("labels.create") + h.count("labels.update"), 0, "none of them reached the engine")

        // The first and last of each list are fine.
        _ = try await labels.create(title: "Work", color: 0, icon: "tag")
        _ = try await labels.create(title: "Work", color: 11, icon: "moon")
        XCTAssertEqual(h.count("labels.create"), 2)
    }

    func testLabelsModelAcceptsAllCatalogIconsWhilePreservingDefault30Order() async throws {
        let (h, labels) = try await start()
        XCTAssertEqual(LabelsModel.icons.first, "tag")
        XCTAssertEqual(LabelsModel.icons, [
            "tag", "star", "heart", "bolt", "flag", "bookmark", "briefcase", "house", "person.2", "cart", "airplane",
            "car", "book", "graduationcap", "gamecontroller", "music.note", "camera", "leaf", "pawprint",
            "cup.and.saucer", "fork.knife", "gift", "bell", "moon",
        ])

        // Any icon in CourierIconCatalog.allowedLabelSFSymbols succeeds in create and update
        _ = try await labels.create(title: "Winter", color: 6, icon: "snowflake")
        try await labels.update(7, title: nil, color: nil, icon: "wineglass")
        try await labels.update(7, title: nil, color: nil, icon: "moon.stars")
        XCTAssertEqual(h.server.receivedParams("labels.create").last?["icon"] as? String, "snowflake")
        XCTAssertEqual(h.server.receivedParams("labels.update").last?["icon"] as? String, "moon.stars")

        // Empty or unknown icon strings are still rejected with .badValue
        do {
            _ = try await labels.create(title: "Invalid", color: 1, icon: "")
            XCTFail("Expected empty icon to be rejected")
        } catch {
            XCTAssertEqual(code(of: error), .badValue)
        }
        do {
            try await labels.update(7, title: nil, color: nil, icon: "nonexistent.sf.symbol.xyz")
            XCTFail("Expected unknown icon to be rejected")
        } catch {
            XCTAssertEqual(code(of: error), .badValue)
        }
    }

    func testUpdateSendsOnlyWhatChanged() async throws {
        let (h, labels) = try await start()
        try await labels.update(3, title: " Family ", color: nil, icon: nil)
        try await labels.update(3, title: nil, color: 5, icon: "gift")
        try await labels.update(3, title: nil, color: nil, icon: nil)
        XCTAssertEqual(dicts(h.server.receivedParams("labels.update")), dicts([
            ["label_id": 3, "title": "Family"], ["label_id": 3, "color": 5, "icon": "gift"],
        ]), "a call with nothing to change asks nothing")
        do {
            try await labels.update(3, title: "   ", color: nil, icon: nil)
            XCTFail("a label needs a title")
        } catch {
            XCTAssertEqual(code(of: error), .badValue)
        }
    }

    func testDeleteAndTheEnginesRefusals() async throws {
        let (h, labels) = try await start()
        try await labels.delete(3)
        XCTAssertEqual(dicts(h.server.receivedParams("labels.delete")), dicts([["label_id": 3]]))

        h.script.fail("labels.delete", code: -32020)
        do {
            try await labels.delete(99)
            XCTFail("the engine said not found")
        } catch {
            XCTAssertEqual(code(of: error), .notFound)
        }
    }

    // MARK: - Auto-archive rules

    func testRulesAreReadAndFoundBySpace() async throws {
        let (h, labels) = try await start(rules: [
            rule(1, scope: "all", trigger: "after_reply", days: 1),
            rule(2, scope: "all", trigger: "older_than", days: 28),
            rule(3, scope: "label:1", trigger: "older_than", days: 7),
        ])
        try await waitUntil { labels.autoArchiveRules.count == 3 }
        // The inbox's sweep is the older_than rule for "all"; the General after_reply rule is not a space's.
        XCTAssertEqual(labels.rules(for: "inbox")?.ruleID, 2)
        XCTAssertEqual(labels.rules(for: "label:1")?.ruleID, 3)
        XCTAssertNil(labels.rules(for: "label:2"))
        XCTAssertNil(labels.rules(for: "account:whatsapp"))

        // A label that goes takes its rule with it: a spaces change reads the rules again.
        h.script.rules = [rule(1, scope: "all", trigger: "after_reply", days: 1)]
        h.server.notify(["kind": "spaces"])
        try await waitUntil { labels.autoArchiveRules.count == 1 }
        XCTAssertNil(labels.rules(for: "label:1"))
    }

    func testSettingARuleStoresItAndShowsIt() async throws {
        let (h, labels) = try await start()
        let new = AutoArchiveRule(scope: "account:whatsapp", trigger: .olderThan, chatType: .read,
                                  durationMS: 14 * 86_400_000, enabled: true)
        try await labels.setRule(new)
        XCTAssertEqual(dicts(h.server.receivedParams("autoArchive.set")), dicts([[
            "rule_id": 0, "scope": "account:whatsapp", "trigger": "older_than", "chat_type": "read",
            "duration_ms": 1_209_600_000, "enabled": true,
        ]]))
        let stored = try XCTUnwrap(labels.rules(for: "account:whatsapp"))
        XCTAssertEqual(stored.ruleID, 1, "the rule as the engine stored it")

        // The same rule, changed: it replaces itself.
        var changed = stored
        changed.enabled = false
        try await labels.setRule(changed)
        XCTAssertEqual(labels.autoArchiveRules.count, 1)
        XCTAssertEqual(labels.rules(for: "account:whatsapp")?.enabled, false)

        try await labels.deleteRule(stored.ruleID)
        XCTAssertEqual(dicts(h.server.receivedParams("autoArchive.delete")), dicts([["rule_id": 1]]))
        XCTAssertNil(labels.rules(for: "account:whatsapp"))
    }

    func testARulePastThePlanCallsNothing() async throws {
        struct NoAutoArchive: EntitlementProvider {
            func isEntitled(_ feature: Feature) -> Bool { feature != .autoArchive }
        }
        let (h, labels) = try await start(entitlement: NoAutoArchive())
        XCTAssertFalse(labels.canAutoArchive)
        do {
            try await labels.setRule(AutoArchiveRule(scope: "all", trigger: .afterRead, chatType: .all,
                                                     durationMS: 0, enabled: true))
            XCTFail("a rule is part of a plan")
        } catch {
            XCTAssertEqual(code(of: error), .notEntitled)
        }
        XCTAssertEqual(h.count("autoArchive.set"), 0)
    }

    // MARK: - How many chats a rule would archive

    func testMatchCountUsesDryRun() async throws {
        let (h, labels) = try await start()
        let sweep = AutoArchiveRule(scope: "all", trigger: .olderThan, chatType: .read, durationMS: 7 * 86_400_000,
                                    enabled: true)
        // !a is read, !b is unread: one chat would be archived, and none is.
        let count = await labels.matchCount(for: sweep)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(dicts(h.server.receivedParams("inbox.archiveMatching")), dicts([[
            "read_only": true, "older_than_ms": 604_800_000, "dry_run": true,
        ]]), "the inbox is left out, as everywhere")
        XCTAssertEqual(h.inbox.rows.map(\.roomID), ["!a", "!b"], "a dry run changes nothing")
        XCTAssertEqual(h.count("room.setArchived"), 0)

        let labelSweep = AutoArchiveRule(scope: "label:4", trigger: .olderThan, chatType: .all,
                                         durationMS: 90 * 86_400_000, enabled: true)
        _ = await labels.matchCount(for: labelSweep)
        XCTAssertEqual(h.server.receivedParams("inbox.archiveMatching").last as NSDictionary?, [
            "space": "label:4", "read_only": false, "older_than_ms": 7_776_000_000, "dry_run": true,
        ] as NSDictionary)

        // After a reply or a read, nothing is swept now: those rules act on what happens next.
        let later = AutoArchiveRule(scope: "all", trigger: .afterReply, chatType: .all, durationMS: 0, enabled: true)
        let none = await labels.matchCount(for: later)
        XCTAssertEqual(none, 0)
        XCTAssertEqual(h.count("inbox.archiveMatching"), 2)

        // A refusal is not "0 chats": the count could not be had.
        h.script.fail("inbox.archiveMatching", code: -32014)
        let refused = await labels.matchCount(for: sweep)
        XCTAssertNil(refused)
    }
}
