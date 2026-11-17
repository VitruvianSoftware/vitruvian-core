// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class SendLaterNudgeTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: hour, minute: minute))!
    }

    func testLateRunsFrom2200Through0659() {
        XCTAssertFalse(SendLaterNudge.isLate(now: at(21, 59), calendar: calendar))
        XCTAssertTrue(SendLaterNudge.isLate(now: at(22, 0), calendar: calendar))
        XCTAssertTrue(SendLaterNudge.isLate(now: at(23, 30), calendar: calendar))
        XCTAssertTrue(SendLaterNudge.isLate(now: at(0, 0), calendar: calendar))
        XCTAssertTrue(SendLaterNudge.isLate(now: at(6, 59), calendar: calendar))
        XCTAssertFalse(SendLaterNudge.isLate(now: at(7, 0), calendar: calendar))
        XCTAssertFalse(SendLaterNudge.isLate(now: at(14, 0), calendar: calendar))
    }

    func testShowsOnlyWhenLateWithTextAndNotDismissed() {
        let late = at(23)
        XCTAssertTrue(SendLaterNudge.shows(hasText: true, now: late, calendar: calendar, dismissed: false))
        XCTAssertFalse(SendLaterNudge.shows(hasText: false, now: late, calendar: calendar, dismissed: false))
        XCTAssertFalse(SendLaterNudge.shows(hasText: true, now: late, calendar: calendar, dismissed: true))
        XCTAssertFalse(SendLaterNudge.shows(hasText: true, now: at(12), calendar: calendar, dismissed: false))
    }

    func testMidnightWrapSecondBoundariesAndTimeZones() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        // Exact second boundaries around 22:00 and 07:00.
        let justBefore22 = london.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 21, minute: 59, second: 59))!
        let exact22 = london.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 22, minute: 0, second: 0))!
        let endOf0659 = london.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 6, minute: 59, second: 59))!
        let exact07 = london.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 7, minute: 0, second: 0))!
        XCTAssertFalse(SendLaterNudge.isLate(now: justBefore22, calendar: london))
        XCTAssertTrue(SendLaterNudge.isLate(now: exact22, calendar: london))
        XCTAssertTrue(SendLaterNudge.isLate(now: endOf0659, calendar: london))
        XCTAssertFalse(SendLaterNudge.isLate(now: exact07, calendar: london))

        // Same UTC instant: 02:30 in London (late) is 21:30 the night before in New York (not late), and 11:30 in Tokyo (not late).
        let london0230 = london.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 2, minute: 30))!
        XCTAssertTrue(SendLaterNudge.isLate(now: london0230, calendar: london))
        XCTAssertFalse(SendLaterNudge.isLate(now: london0230, calendar: newYork))
        XCTAssertFalse(SendLaterNudge.isLate(now: london0230, calendar: tokyo))
    }

    @MainActor
    func testComposerCanScheduleRejectsWhitespaceAttachmentsAndEditing() {
        let late = at(23, 15)
        let sender = FakeSender()
        let composer = ComposerModel(
            sender: sender,
            fileInfo: { _ in ComposerFileInfo(size: 128, isRegularFile: true) },
            entitlement: AlwaysEntitled()
        )
        composer.open("!room:courier.local")

        for blank in ["", "   ", "\n\t  \n"] {
            composer.text = blank
            XCTAssertFalse(composer.canSchedule, "blank text \(blank.debugDescription) must not be schedulable")
            XCTAssertFalse(SendLaterNudge.shows(hasText: composer.canSchedule, now: late, calendar: calendar, dismissed: false))
        }

        composer.text = "  Sleep well!  "
        XCTAssertTrue(composer.canSchedule)
        XCTAssertTrue(SendLaterNudge.shows(hasText: composer.canSchedule, now: late, calendar: calendar, dismissed: false))
        XCTAssertFalse(SendLaterNudge.shows(hasText: composer.canSchedule, now: late, calendar: calendar, dismissed: true))

        // Attachment-only and text+attachment drafts cannot be scheduled, so the nudge stays off.
        composer.attach([URL(fileURLWithPath: "/tmp/vitruvian-courier-nudge/photo.png")])
        XCTAssertFalse(composer.canSchedule)
        XCTAssertFalse(SendLaterNudge.shows(hasText: composer.canSchedule, now: late, calendar: calendar, dismissed: false))
        composer.text = ""
        XCTAssertFalse(composer.canSchedule)
        XCTAssertFalse(SendLaterNudge.shows(hasText: composer.canSchedule, now: late, calendar: calendar, dismissed: false))

        if let attachmentID = composer.attachments.first?.id {
            composer.removeAttachment(attachmentID)
        }
        composer.text = "Real text again"
        XCTAssertTrue(composer.canSchedule)

        // With no room open, canSchedule is false.
        let closed = ComposerModel(sender: sender, entitlement: AlwaysEntitled())
        closed.text = "No open room"
        XCTAssertFalse(closed.canSchedule)
        XCTAssertFalse(SendLaterNudge.shows(hasText: closed.canSchedule, now: late, calendar: calendar, dismissed: false))
    }
}

final class SpaceShortcutLabelTests: XCTestCase {
    func testLabelIsTheModifierThenThePosition() {
        let control = KeyChord(key: "", control: true)
        XCTAssertEqual(SpaceShortcutLabel.label(position: 2, modifier: control), "⌃2")
        XCTAssertEqual(SpaceShortcutLabel.label(position: 9, modifier: KeyChord(key: "", command: true)), "⌘9")
    }

    func testNoLabelPastNineOrWhenOff() {
        let control = KeyChord(key: "", control: true)
        XCTAssertNil(SpaceShortcutLabel.label(position: 10, modifier: control))
        XCTAssertNil(SpaceShortcutLabel.label(position: 0, modifier: control))
        XCTAssertNil(SpaceShortcutLabel.label(position: 1, modifier: nil))
        XCTAssertNil(SpaceShortcutLabel.label(position: 1, modifier: KeyChord(key: "a")))
    }

    @MainActor
    func testLabelsFollowVisibleOrderAfterHidingReorderingAndModifierChanges() throws {
        let suite = "courier.space-shortcuts.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-space-shortcuts"),
            environment: [:],
            launcher: FakeLauncher { _, _ in }
        ))
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: defaults))
        let spaces = SpacesModel(appModel: app, inbox: inbox)
        let registry = HotkeyRegistry(defaults: defaults)

        func labels() -> [(String, String?)] {
            let mod = registry.primaryChord(for: "Switch First 9 Spaces Modifier")
            return spaces.visible.enumerated().map { index, space in
                (space.spaceID, SpaceShortcutLabel.label(position: index + 1, modifier: mod))
            }
        }

        // Hidden space in the middle is skipped by both SpaceBar's visible enumeration and selectNumber.
        spaces.setSpacesForTesting([
            Space(spaceID: "inbox", kind: .builtin, title: "Inbox"),
            Space(spaceID: "reminders", kind: .builtin, title: "Reminders", hidden: true),
            Space(spaceID: "account:whatsapp", kind: .account, title: "WhatsApp", network: "whatsapp"),
            Space(spaceID: "label:1", kind: .label, title: "Work", labelID: 1),
        ])
        XCTAssertEqual(labels().map(\.0), ["inbox", "account:whatsapp", "label:1"])
        XCTAssertEqual(labels().map(\.1), ["⌘1", "⌘2", "⌘3"])
        spaces.selectNumber(2)
        XCTAssertEqual(inbox.query.space, "account:whatsapp")
        spaces.selectNumber(3)
        XCTAssertEqual(inbox.query.space, "label:1")

        // Reordering visible spaces moves the shortcut labels to match selectNumber.
        spaces.setSpacesForTesting([
            Space(spaceID: "inbox", kind: .builtin, title: "Inbox"),
            Space(spaceID: "label:1", kind: .label, title: "Work", labelID: 1),
            Space(spaceID: "account:whatsapp", kind: .account, title: "WhatsApp", network: "whatsapp"),
        ])
        XCTAssertEqual(labels().map(\.0), ["inbox", "label:1", "account:whatsapp"])
        XCTAssertEqual(labels().map(\.1), ["⌘1", "⌘2", "⌘3"])
        spaces.selectNumber(2)
        XCTAssertEqual(inbox.query.space, "label:1")

        // Texts.app preset changes the modifier to ⌃; custom record changes it to ⌥; disabling clears all labels.
        registry.applyTextsAppPreset()
        XCTAssertEqual(labels().map(\.1), ["⌃1", "⌃2", "⌃3"])

        if case let .failure(error) = registry.record(KeyChord(key: "", option: true), for: "Switch First 9 Spaces Modifier") {
            XCTFail("recording option modifier failed: \(error)")
        }
        XCTAssertEqual(labels().map(\.1), ["⌥1", "⌥2", "⌥3"])

        registry.setEnabled(false, for: "Switch First 9 Spaces Modifier")
        XCTAssertEqual(labels().map(\.1), [nil, nil, nil])
    }
}
