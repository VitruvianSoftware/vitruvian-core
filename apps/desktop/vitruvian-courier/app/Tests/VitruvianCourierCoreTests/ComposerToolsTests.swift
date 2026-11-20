// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

@MainActor
final class ComposerToolsTests: XCTestCase {
    private func fullFeatures() -> ChatFeatures {
        ChatFeatures(
            reply: true,
            poll: PollFeatures(maxOptions: 12, optionMaxLength: 100),
            formatting: [.bold, .italic, .link],
            source: .stored,
            imageFeatures: FileKindFeatures(supported: true, mimeTypes: ["image/*"]),
            voiceFeatures: FileKindFeatures(supported: true, mimeTypes: ["audio/ogg"]),
            fileFeatures: FileKindFeatures(supported: true, mimeTypes: ["*/*"]),
            gifFeatures: FileKindFeatures(supported: true, mimeTypes: ["image/gif", "video/mp4"])
        )
    }

    private func makeComposer(
        features: ChatFeatures? = nil,
        entitled: Bool = true
    ) -> (ComposerModel, FakeSender) {
        let sender = FakeSender()
        let composer = ComposerModel(
            sender: sender,
            entitlement: entitled ? AlwaysEntitled() : NoPlan()
        )
        composer.open("!room")
        composer.network = "whatsapp"
        composer.features = features ?? fullFeatures()
        return (composer, sender)
    }

    private func makeEditableMessage(id: String, roomID: String, body: String, ts: Int64) -> TimelineMessage {
        TimelineMessage(
            id: id,
            roomID: roomID,
            sender: Timeline.meUserID,
            senderName: "Me",
            senderAvatarPath: "",
            mine: true,
            ts: ts,
            kind: .text,
            body: body,
            rich: RichText(text: body),
            isEdited: false,
            editCount: 0,
            editFailed: nil,
            failedEditID: nil,
            fileName: "",
            mimeType: "",
            byteSize: nil,
            width: nil,
            height: nil,
            mediaPath: "",
            statusLine: .sent,
            countsAsUnread: false,
            poll: nil,
            thread: nil,
            bookmarked: false,
            expiresAt: nil,
            timerChange: nil,
            call: nil,
            reply: nil,
            reactions: [],
            startsGroup: true
        )
    }

    func testToolRowOrderMatchesSpecWhenAllSupported() {
        let (composer, _) = makeComposer()
        composer.text = "Hello"

        let items = composer.toolRowItems()
        XCTAssertEqual(
            items.map(\.kind),
            [.attachFile, .photo, .gif, .voiceNote, .sendLater, .poll, .ai]
        )
        XCTAssertTrue(items.allSatisfy(\.isEnabled))
        XCTAssertTrue(items.allSatisfy { $0.disabledReason == nil })
    }

    func testUnsupportedNetworkToolsAreHiddenNotGreyed() {
        // Text-only network: hides attachFile, photo, gif, voiceNote, and poll; keeps sendLater and ai.
        let textOnly = ChatFeatures(reply: true, source: .stored)
        let (composer, _) = makeComposer(features: textOnly)
        XCTAssertEqual(composer.toolRowItems().map(\.kind), [.sendLater, .ai])

        // Network with file + voice only (like a restricted SMS/chat profile): hides photo, gif, poll.
        let fileAndVoice = ChatFeatures(
            reply: true,
            source: .stored,
            voiceFeatures: FileKindFeatures(supported: true, mimeTypes: ["audio/mp4"]),
            fileFeatures: FileKindFeatures(supported: true, mimeTypes: ["*/*"])
        )
        composer.features = fileAndVoice
        XCTAssertEqual(
            composer.toolRowItems().map(\.kind),
            [.attachFile, .voiceNote, .sendLater, .ai]
        )

        // Unknown features (.noFeatures, source == .none) keeps media fallbacks, omits poll and location.
        composer.features = .noFeatures
        XCTAssertEqual(
            composer.toolRowItems().map(\.kind),
            [.attachFile, .photo, .gif, .sticker, .voiceNote, .sendLater, .ai]
        )
    }

    func testStickerAndLocationToolsFollowNetworkSupport() {
        // Sticker sits right after GIF; Location right after Poll (before AI).
        var features = fullFeatures()
        features.stickerFeatures = FileKindFeatures(supported: true, mimeTypes: ["image/webp"])
        features.locationSupported = true
        let (composer, _) = makeComposer(features: features)
        composer.text = "Hello"
        XCTAssertEqual(
            composer.toolRowItems().map(\.kind),
            [.attachFile, .photo, .gif, .sticker, .voiceNote, .sendLater, .poll, .location, .ai]
        )
        XCTAssertTrue(composer.toolRowItems().allSatisfy(\.isEnabled))

        // Only Sticker supported: Location is hidden, not greyed.
        features.locationSupported = false
        composer.features = features
        let stickerOnly = composer.toolRowItems().map(\.kind)
        XCTAssertTrue(stickerOnly.contains(.sticker))
        XCTAssertFalse(stickerOnly.contains(.location))

        // Only Location supported: Sticker is hidden.
        features.stickerFeatures = nil
        features.locationSupported = true
        composer.features = features
        let locationOnly = composer.toolRowItems().map(\.kind)
        XCTAssertFalse(locationOnly.contains(.sticker))
        XCTAssertTrue(locationOnly.contains(.location))

        // Both unsupported: neither appears.
        features.locationSupported = false
        composer.features = features
        let neither = composer.toolRowItems().map(\.kind)
        XCTAssertFalse(neither.contains(.sticker))
        XCTAssertFalse(neither.contains(.location))

        // Editing a message hides both.
        features.stickerFeatures = FileKindFeatures(supported: true, mimeTypes: ["image/webp"])
        features.locationSupported = true
        composer.features = features
        let msg = makeEditableMessage(id: "$mine", roomID: "!room", body: "Original", ts: 1000)
        composer.startEditing(msg)
        XCTAssertEqual(composer.toolRowItems().map(\.kind), [.ai])
    }

    func testSendLaterVisibilityAndDisabledReasons() {
        let store = TestDefaults()
        defer { store.remove() }
        let prefs = ComposerPreferences(defaults: store.defaults)

        let (composer, _) = makeComposer(entitled: true)
        composer.preferences = prefs

        // Empty draft: Send Later stays visible, disabled, with exact tooltip reason.
        XCTAssertEqual(
            composer.toolRowItems().first { $0.kind == .sendLater },
            ComposerToolItem(kind: .sendLater, isEnabled: false, disabledReason: "Write a message first")
        )

        // Whitespace-only draft still counts as empty.
        composer.text = "  \n\t "
        XCTAssertEqual(
            composer.toolRowItems().first { $0.kind == .sendLater },
            ComposerToolItem(kind: .sendLater, isEnabled: false, disabledReason: "Write a message first")
        )

        // Non-empty draft enables Send Later with no disabled reason.
        composer.text = "Meeting at 3pm"
        XCTAssertEqual(
            composer.toolRowItems().first { $0.kind == .sendLater },
            ComposerToolItem(kind: .sendLater, isEnabled: true, disabledReason: nil)
        )

        // Staged GIF makes Send Later unavailable with explanation.
        composer.pendingGIF = StickerItemWire(
            id: "gif:1",
            packID: "recent",
            name: "Wave",
            mediaURL: "courier://media/1",
            mimeType: "image/gif",
            usage: ["gif"]
        )
        XCTAssertEqual(
            composer.toolRowItems().first { $0.kind == .sendLater },
            ComposerToolItem(kind: .sendLater, isEnabled: false, disabledReason: "Send Later works with text messages only")
        )
        composer.pendingGIF = nil

        // Unentitled user sees "Available with a plan".
        let (unentitled, _) = makeComposer(entitled: false)
        unentitled.text = "Draft"
        XCTAssertEqual(
            unentitled.toolRowItems().first { $0.kind == .sendLater },
            ComposerToolItem(kind: .sendLater, isEnabled: false, disabledReason: "Available with a plan")
        )

        // If Send Later is already placed on the composer bar via preferences, omit duplicate in tool row.
        prefs.primaryComposerButton = .sendLater
        XCTAssertFalse(composer.toolRowItems().contains { $0.kind == .sendLater })

        // Thread mode hides Send Later and Poll; editing mode hides media, Send Later, and Poll.
        prefs.primaryComposerButton = .emojiPicker
        composer.startThread("$root")
        XCTAssertEqual(
            composer.toolRowItems().map(\.kind),
            [.attachFile, .photo, .gif, .voiceNote, .ai]
        )

        composer.endThread()
        let msg = makeEditableMessage(id: "$mine", roomID: "!room", body: "Original", ts: 1000)
        composer.startEditing(msg)
        XCTAssertEqual(composer.toolRowItems().map(\.kind), [.ai])
    }

    func testToolRowClosesOnEscapeSendRoomSwitchEditAndLock() async throws {
        let (composer, _) = makeComposer()
        composer.startReply(to: QuotedMessage(eventID: "$1", senderName: "Ann", mine: false, text: "Hi", kind: .text))
        composer.isToolRowOpen = true

        // First Escape closes the tool row before clearing reply target.
        XCTAssertTrue(composer.escape())
        XCTAssertFalse(composer.isToolRowOpen)
        XCTAssertNotNil(composer.replyTarget)

        // Second Escape clears reply target.
        XCTAssertTrue(composer.escape())
        XCTAssertNil(composer.replyTarget)

        // Sending a message closes the tool row.
        composer.isToolRowOpen = true
        composer.text = "On my way"
        await composer.send()
        XCTAssertFalse(composer.isToolRowOpen)

        // Scheduling closes the tool row.
        composer.isToolRowOpen = true
        composer.text = "Tomorrow morning"
        try await composer.schedule(at: Date().addingTimeInterval(3600), condition: .always)
        XCTAssertFalse(composer.isToolRowOpen)

        // Switching rooms closes the tool row.
        composer.isToolRowOpen = true
        composer.open("!other")
        XCTAssertFalse(composer.isToolRowOpen)

        // Opening GIF or sticker picker closes the tool row.
        composer.features = fullFeatures()
        composer.isToolRowOpen = true
        XCTAssertTrue(composer.openGIFPicker())
        XCTAssertFalse(composer.isToolRowOpen)

        // Starting an edit closes the tool row.
        composer.isToolRowOpen = true
        let msg = makeEditableMessage(id: "$m2", roomID: "!other", body: "Edit me", ts: 2000)
        composer.startEditing(msg)
        XCTAssertFalse(composer.isToolRowOpen)

        // Locking / dismissing presentations closes the tool row.
        composer.isToolRowOpen = true
        composer.dismissAllPresentations()
        XCTAssertFalse(composer.isToolRowOpen)
    }

    func testTabKeyDecision() {
        XCTAssertEqual(ComposerModel.action(forTab: []), .focusNext)
        XCTAssertEqual(ComposerModel.action(forTab: [], hasOpenAutocomplete: true), .acceptAutocomplete)

        XCTAssertEqual(ComposerModel.action(forTab: [.shift]), .focusPrevious)
        XCTAssertEqual(ComposerModel.action(forTab: [], isBacktab: true), .focusPrevious)
        XCTAssertEqual(ComposerModel.action(forTab: [.shift], hasOpenAutocomplete: true), .focusPrevious)
        XCTAssertEqual(ComposerModel.action(forTab: [], isBacktab: true, hasOpenAutocomplete: true), .focusPrevious)

        XCTAssertEqual(ComposerModel.action(forTab: [.option]), .insertLiteralTab)
        XCTAssertEqual(ComposerModel.action(forTab: [], ignoresFieldEditor: true), .insertLiteralTab)
        XCTAssertEqual(ComposerModel.action(forTab: [.option], hasOpenAutocomplete: true), .insertLiteralTab)
    }

    func testToolRowMotionAndSendButtonAppearance() {
        XCTAssertTrue((0.16 ... 0.20).contains(ComposerToolRowMotion.duration))
        XCTAssertTrue(ComposerToolRowMotion.usesSlideAndRotation(reduceMotion: false))
        XCTAssertFalse(ComposerToolRowMotion.usesSlideAndRotation(reduceMotion: true))
        XCTAssertEqual(ComposerToolRowMotion.plusRotationDegrees(isOpen: false, reduceMotion: false), 0)
        XCTAssertEqual(ComposerToolRowMotion.plusRotationDegrees(isOpen: true, reduceMotion: false), 45)
        XCTAssertEqual(ComposerToolRowMotion.plusRotationDegrees(isOpen: true, reduceMotion: true), 0)

        let (composer, _) = makeComposer()
        XCTAssertEqual(composer.sendButtonAppearance, .disabledNeutral)

        composer.text = "   "
        XCTAssertEqual(composer.sendButtonAppearance, .disabledNeutral)

        composer.text = "Hello"
        XCTAssertEqual(composer.sendButtonAppearance, .activeAccent)

        composer.text = ""
        composer.pendingGIF = StickerItemWire(
            id: "gif:1",
            packID: "recent",
            name: "Wave",
            mediaURL: "courier://media/1",
            mimeType: "image/gif",
            usage: ["gif"]
        )
        XCTAssertEqual(composer.sendButtonAppearance, .activeAccent)
    }
}
