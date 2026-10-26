// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import XCTest

@testable import CourierCore

/// Inline voice-note & audio playback (`AudioPlayerModel`), speed cycling & persistence, continuous voice-note
/// auto-advance within the same chat (stopping at non-voice messages), local-only `message.markPlayed`, and the
/// persistent floating audio bar (`shouldShowGlobalBar`) across room switches. All data here is synthetic.
@MainActor
final class AudioPlayerModelTests: XCTestCase {
    private var harnesses: [ConversationHarness] = []
    private var tempFiles: [URL] = []

    override func tearDown() async throws {
        for harness in harnesses { await harness.stop() }
        harnesses = []
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        tempFiles = []
    }

    private func makeLocalAudioFile(name: String = "voice-\(UUID().uuidString).ogg") throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data("OggS-synthetic-audio".utf8).write(to: url, options: .atomic)
        tempFiles.append(url)
        return url.path
    }

    private func voiceEvent(
        id: String,
        room: String,
        at seq: Int64,
        mediaPath: String,
        durationMS: Int = 12_000,
        waveform: [Int] = [12, 36, 72, 95, 48, 20, 64, 82],
        played: Bool = false,
        senderName: String = "Alice Example"
    ) -> [String: Any] {
        [
            "event_id": id,
            "room_id": room,
            "sender": "@alice:courier.local",
            "sender_name": senderName,
            "sender_avatar_path": "",
            "mine": false,
            "type": "m.room.message",
            "content": [
                "msgtype": "m.audio",
                "body": "Voice message.ogg",
                "filename": "Voice message.ogg",
                "org.matrix.msc3245.voice": [String: Any](),
                "org.matrix.msc1767.audio": [
                    "duration": durationMS,
                    "waveform": waveform,
                ] as [String: Any],
                "info": [
                    "mimetype": "audio/ogg",
                    "duration": durationMS,
                    "size": 18_432,
                ] as [String: Any],
            ] as [String: Any],
            "ts": ConversationScript.timestamp(seq),
            "seq": seq,
            "status": "sent",
            "status_reason": "",
            "media_path": mediaPath,
            "duration_ms": durationMS,
            "waveform": waveform,
            "played": played,
            "bookmarked": false,
            "poll": NSNull(),
            "thread": NSNull(),
            "expires_at": 0,
            "delivered": false,
            "read_by": [[String: Any]](),
        ]
    }

    func testPlaySeekSpeedCycleAndMarkPlayed() async throws {
        let audioPath1 = try makeLocalAudioFile(name: "voice-1.ogg")
        let audioPath2 = try makeLocalAudioFile(name: "voice-2.ogg")
        let room1 = "!r1:courier.local"
        let h = try await startConversation(
            [
                room1: [
                    voiceEvent(id: "$v1", room: room1, at: 1, mediaPath: audioPath1),
                    voiceEvent(id: "$v2", room: room1, at: 2, mediaPath: audioPath2),
                ],
            ],
            features: [room1: featuresJSON()],
            rows: [room1: chatRow(room1, name: "Alice Example", network: "whatsapp")]
        )
        harnesses.append(h)
        try await h.open(room1)

        // Default preference matches the inventory ("Automatically play the next voice note" = true).
        XCTAssertTrue(h.preferences.autoPlayNextVoiceNote)

        let backend = FakeAudioPlaybackBackend()
        let player = AudioPlayerModel(
            appModel: h.app,
            conversation: h.conversation,
            preferences: h.preferences,
            defaults: h.store.defaults,
            backend: backend
        )

        // Remote URLs are never played; only local file paths are accepted.
        XCTAssertNotNil(AudioPlayerModel.localMediaURL(for: audioPath1))
        XCTAssertNil(AudioPlayerModel.localMediaURL(for: "https://example.test/remote.ogg"))
        XCTAssertNil(AudioPlayerModel.localMediaURL(for: "http://example.test/remote.ogg"))
        XCTAssertNil(AudioPlayerModel.localMediaURL(for: "mxc://courier.local/sha256"))
        XCTAssertNil(AudioPlayerModel.localMediaURL(for: ""))

        let remoteTrack = AudioPlayerModel.Track(
            eventID: "$remote",
            roomID: room1,
            mediaPath: "https://example.test/remote.ogg",
            senderName: "Alice Example",
            chatTitle: "Alice Example",
            durationMS: 8_000,
            waveform: [10, 50, 90]
        )
        player.playOrPause(remoteTrack)
        XCTAssertNil(player.currentTrack, "AudioPlayerModel must refuse remote URLs")
        XCTAssertFalse(player.isPlaying)

        // Play local voice note track 1.
        let track1 = AudioPlayerModel.Track(
            eventID: "$v1",
            roomID: room1,
            mediaPath: audioPath1,
            senderName: "Alice Example",
            chatTitle: "Alice Example",
            durationMS: 12_000,
            waveform: [12, 36, 72, 95, 48, 20, 64, 82]
        )
        player.playOrPause(track1)
        XCTAssertEqual(player.currentTrack?.eventID, "$v1")
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(backend.loadedURL?.path, audioPath1)

        // Cycle speed: 1× -> 1.5× -> 2× -> 0.5× -> 1×.
        XCTAssertEqual(player.speed, .one)
        XCTAssertEqual(player.speed.label, "1×")

        player.cycleSpeed()
        XCTAssertEqual(player.speed, .onePointFive)
        XCTAssertEqual(player.speed.label, "1.5×")
        XCTAssertEqual(backend.rate, 1.5, accuracy: 0.001)

        // App-wide speed persistence in UserDefaults.
        let secondPlayer = AudioPlayerModel(
            appModel: h.app,
            conversation: h.conversation,
            preferences: h.preferences,
            defaults: h.store.defaults,
            backend: FakeAudioPlaybackBackend()
        )
        XCTAssertEqual(secondPlayer.speed, .onePointFive, "speed choice is remembered app-wide")

        player.cycleSpeed()
        XCTAssertEqual(player.speed, .two)
        XCTAssertEqual(player.speed.label, "2×")
        XCTAssertEqual(backend.rate, 2.0, accuracy: 0.001)

        player.cycleSpeed()
        XCTAssertEqual(player.speed, .half)
        XCTAssertEqual(player.speed.label, "0.5×")
        XCTAssertEqual(backend.rate, 0.5, accuracy: 0.001)

        player.cycleSpeed()
        XCTAssertEqual(player.speed, .one)
        XCTAssertEqual(player.speed.label, "1×")
        XCTAssertEqual(backend.rate, 1.0, accuracy: 0.001)

        // Seek to 0.5 (50% of 12,000 ms = 6,000 ms).
        player.seek(to: 0.5)
        XCTAssertEqual(player.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(player.elapsedMS, 6_000)
        XCTAssertEqual(backend.lastSeekFraction ?? -1, 0.5, accuracy: 0.001)

        // Marking played sends message.markPlayed to the local engine and updates TimelineMessage.played.
        try await waitUntil { h.count("message.markPlayed") == 1 }
        XCTAssertEqual(
            dicts(h.server.receivedParams("message.markPlayed")),
            dicts([["room_id": room1, "event_id": "$v1"]])
        )
        XCTAssertEqual(h.message("$v1")?.played, true)

        // Context menu offers .markAsPlayed ("Mark as played") on unplayed voice note $v2, and hides it once played.
        let unplayedV2 = try XCTUnwrap(h.message("$v2"))
        XCTAssertFalse(unplayedV2.played)
        let v2AvailableBefore = h.conversation.availableActions(for: unplayedV2)
        XCTAssertTrue(v2AvailableBefore.actions.contains(.markAsPlayed))
        XCTAssertEqual(MessageMenu.title(of: .markAsPlayed, features: h.conversation.features), "Mark as played")

        let actionsModel = MessageActionsModel(
            conversation: h.conversation,
            appModel: h.app,
            preferences: h.preferences,
            pasteboard: FakePasteboard()
        )
        await actionsModel.perform(.markAsPlayed, on: "$v2")
        try await waitUntil { h.count("message.markPlayed") == 2 }
        let playedV2 = try XCTUnwrap(h.message("$v2"))
        XCTAssertTrue(playedV2.played)
        let v2AvailableAfter = h.conversation.availableActions(for: playedV2)
        XCTAssertFalse(v2AvailableAfter.actions.contains(.markAsPlayed))
    }

    func testContinuousPlaybackAdvancesToNextVoiceNoteWhenEnabled() async throws {
        let audioPath1 = try makeLocalAudioFile(name: "cont-1.ogg")
        let audioPath2 = try makeLocalAudioFile(name: "cont-2.ogg")
        let audioPath4 = try makeLocalAudioFile(name: "cont-4.ogg")
        let room1 = "!r1:courier.local"
        let room2 = "!r2:courier.local"
        let h = try await startConversation(
            [
                room1: [
                    voiceEvent(id: "$v1", room: room1, at: 1, mediaPath: audioPath1),
                    voiceEvent(id: "$v2", room: room1, at: 2, mediaPath: audioPath2),
                    textEvent(id: "$t3", room: room1, at: 3, body: "Trailhead is open"),
                    voiceEvent(id: "$v4", room: room1, at: 4, mediaPath: audioPath4),
                ],
                room2: [
                    voiceEvent(id: "$v-other", room: room2, at: 1, mediaPath: audioPath4),
                ],
            ],
            features: [room1: featuresJSON(), room2: featuresJSON()],
            rows: [
                room1: chatRow(room1, name: "Alice Example", network: "whatsapp"),
                room2: chatRow(room2, name: "Bob Example", network: "signal"),
            ]
        )
        harnesses.append(h)
        try await h.open(room1)

        // Consecutive voice-note queue in ConversationModel stops at the first non-voice message ($t3).
        let queueFromV1 = h.conversation.voiceNoteQueue(startingAt: "$v1")
        XCTAssertEqual(queueFromV1.map(\.eventID), ["$v1", "$v2"], "queue must stop at the first non-voice message")

        let backend = FakeAudioPlaybackBackend()
        let player = AudioPlayerModel(
            appModel: h.app,
            conversation: h.conversation,
            preferences: h.preferences,
            defaults: h.store.defaults,
            backend: backend
        )

        // 1. With autoPlayNextVoiceNote = true, finishing track 1 automatically starts track 2 in the same chat.
        h.preferences.autoPlayNextVoiceNote = true
        player.playOrPause(queueFromV1[0], queueInRoom: queueFromV1)
        XCTAssertEqual(player.currentTrack?.eventID, "$v1")
        XCTAssertTrue(player.isPlaying)

        await player.handleTrackFinished()
        XCTAssertEqual(player.currentTrack?.eventID, "$v2", "continuous playback advances to the next voice note")
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(backend.loadedURL?.path, audioPath2)

        // Finishing the newest consecutive voice note ($v2) stops playback.
        await player.handleTrackFinished()
        XCTAssertNil(player.currentTrack)
        XCTAssertFalse(player.isPlaying)

        // Continuous playback never crosses into another chat even if passed in queueInRoom.
        let otherRoomTrack = AudioPlayerModel.Track(
            eventID: "$v-other",
            roomID: room2,
            mediaPath: audioPath4,
            senderName: "Bob Example",
            chatTitle: "Bob Example",
            durationMS: 9_000,
            waveform: [20, 60, 40]
        )
        player.playOrPause(queueFromV1[0], queueInRoom: [queueFromV1[0], otherRoomTrack])
        await player.handleTrackFinished()
        XCTAssertNil(player.currentTrack, "continuous playback must stay in the same chat only")
        XCTAssertFalse(player.isPlaying)

        // 2. With autoPlayNextVoiceNote = false, playback stops after track 1.
        h.preferences.autoPlayNextVoiceNote = false
        XCTAssertEqual(
            h.store.defaults.object(forKey: ComposerPreferences.autoPlayNextVoiceNoteKey) as? Bool,
            false
        )
        player.playOrPause(queueFromV1[0], queueInRoom: queueFromV1)
        XCTAssertEqual(player.currentTrack?.eventID, "$v1")
        XCTAssertTrue(player.isPlaying)

        await player.handleTrackFinished()
        XCTAssertNil(player.currentTrack, "playback stops after track 1 when autoPlayNextVoiceNote is false")
        XCTAssertFalse(player.isPlaying)
    }

    func testGlobalAudioBarShowsWhenSwitchingAwayFromPlayingRoom() async throws {
        let audioPath1 = try makeLocalAudioFile(name: "bar-1.ogg")
        let room1 = "!r1:courier.local"
        let room2 = "!r2:courier.local"
        let h = try await startConversation(
            [
                room1: [voiceEvent(id: "$v1", room: room1, at: 1, mediaPath: audioPath1)],
                room2: [textEvent(id: "$t1", room: room2, at: 1, body: "Hello from room 2")],
            ],
            features: [room1: featuresJSON(), room2: featuresJSON()],
            rows: [
                room1: chatRow(room1, name: "Alice Example", network: "whatsapp"),
                room2: chatRow(room2, name: "Bob Example", network: "signal"),
            ]
        )
        harnesses.append(h)
        try await h.open(room1)

        let backend = FakeAudioPlaybackBackend()
        let player = h.conversation.audioPlayer
        player.setBackendForTesting(backend)

        let queue = h.conversation.voiceNoteQueue(startingAt: "$v1")
        let track1 = try XCTUnwrap(queue.first)
        player.playOrPause(track1, queueInRoom: queue)

        XCTAssertEqual(player.currentTrack?.eventID, "$v1")
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.shouldShowGlobalBar, "bar is hidden while the playing room is open")

        // Switch to !r2:courier.local: playback continues and the persistent floating audio bar shows.
        try await h.open(room2)
        XCTAssertTrue(player.isPlaying, "switching chats must not stop voice note playback")
        XCTAssertEqual(player.currentTrack?.roomID, room1)
        XCTAssertTrue(player.shouldShowGlobalBar, "GlobalAudioPlayerBar shows when viewing a different chat")

        // Jumping back to the playing room hides the floating bar again while playback continues.
        try await h.open(room1)
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.shouldShowGlobalBar)

        // Switch back to !r2:courier.local and verify quitting stops playback and dismisses the bar.
        try await h.open(room2)
        XCTAssertTrue(player.shouldShowGlobalBar)
        player.stopForApplicationTermination()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentTrack)
        XCTAssertFalse(player.shouldShowGlobalBar)
    }
}

@MainActor
private final class FakeAudioPlaybackBackend: AudioPlaybackBackend {
    var loadedURL: URL?
    var isPlaying = false
    var rate: Float = 1.0
    var currentTimeSec: TimeInterval = 0
    var durationSec: TimeInterval = 12.0
    var lastSeekFraction: Double?
    var onFinish: (@MainActor () -> Void)?

    func load(url: URL, rate: Float, onFinish: @escaping @MainActor () -> Void) throws {
        loadedURL = url
        self.rate = rate
        self.onFinish = onFinish
        currentTimeSec = 0
        isPlaying = true
    }

    func play() {
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        isPlaying = false
        loadedURL = nil
    }

    func seek(toFraction fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        lastSeekFraction = clamped
        currentTimeSec = durationSec * clamped
    }

    func setRate(_ rate: Float) {
        self.rate = rate
    }
}
