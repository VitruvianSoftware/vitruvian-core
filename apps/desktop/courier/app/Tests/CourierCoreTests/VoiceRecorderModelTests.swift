// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest

@testable import CourierCore

@MainActor
final class VoiceRecorderModelTests: XCTestCase {
    private func makeTempVoiceFile(named name: String = "voice-\(UUID().uuidString).m4a") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data([0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70]).write(to: url)
        return url
    }

    func testStartSampleWaveformStopAndSendVoice() async throws {
        let tempURL = try makeTempVoiceFile()
        let meterSamples: [Float] = [
            0.1, 0.5, 0.9, 0.2, 0.4, 0.6, 0.8, 0.3, 0.7, 1.0,
            0.0, 0.15, 0.35, 0.55, 0.75, 0.95, 0.25, 0.45, 0.65, 0.85,
        ]
        let backend = FakeVoiceRecordingBackend(
            devices: [
                AudioInputDevice(uid: "built-in-mic", name: "MacBook Pro Microphone"),
                AudioInputDevice(uid: "usb-mic", name: "Studio USB Mic"),
            ],
            authStatus: .authorized,
            recordingURL: tempURL,
            meterSequence: meterSamples,
            stoppedDurationMS: 4200
        )
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        var currentTime = startTime
        let recorder = VoiceRecorderModel(backend: backend, now: { currentTime })
        let sender = VoiceSpySender()
        let composer = ComposerModel(sender: sender, voiceRecorder: recorder)
        composer.open("!roomA:courier.local")

        await recorder.start(preferredDeviceUID: "usb-mic")
        XCTAssertEqual(backend.lastStartedDeviceUID, "usb-mic")
        guard case let .recording(startedAt, elapsedMS, initialLevels) = recorder.state else {
            return XCTFail("Expected .recording state, got \(recorder.state)")
        }
        XCTAssertEqual(startedAt, startTime)
        XCTAssertEqual(elapsedMS, 0)
        XCTAssertTrue(initialLevels.isEmpty)

        for index in 0 ..< meterSamples.count {
            currentTime = startTime.addingTimeInterval(Double(index + 1) * 0.05)
            recorder.sampleMeter()
        }

        guard case let .recording(_, sampledElapsedMS, sampledLevels) = recorder.state else {
            return XCTFail("Expected .recording state after sampling, got \(recorder.state)")
        }
        XCTAssertEqual(sampledElapsedMS, 1000)
        XCTAssertEqual(sampledLevels.count, 20)
        XCTAssertEqual(Array(sampledLevels.prefix(3)), [10, 50, 90])
        XCTAssertTrue(sampledLevels.allSatisfy { (0 ... 100).contains($0) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), "temp file exists until sent")

        await recorder.stopAndSend(using: composer)
        await composer.settle()

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(sender.voiceCalls.count, 1)
        let call = try XCTUnwrap(sender.voiceCalls.first)
        XCTAssertEqual(call.roomID, "!roomA:courier.local")
        XCTAssertEqual(call.url, tempURL)
        XCTAssertEqual(call.durationMS, 4200)
        XCTAssertEqual(call.waveform, sampledLevels)
        XCTAssertNil(call.replyTo)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempURL.path),
            "temporary recording file must be deleted after sending"
        )
    }

    func testCancelRecordingDeletesTempFileAndSendsNothing() async throws {
        let tempURL = try makeTempVoiceFile()
        let backend = FakeVoiceRecordingBackend(
            authStatus: .authorized,
            recordingURL: tempURL,
            meterSequence: [0.3, 0.6],
            stoppedDurationMS: 1500
        )
        let recorder = VoiceRecorderModel(backend: backend)
        let sender = VoiceSpySender()
        let composer = ComposerModel(sender: sender, voiceRecorder: recorder)
        composer.open("!roomA:courier.local")

        await recorder.start()
        recorder.sampleMeter()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        await recorder.cancel()

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(backend.cancelCallCount, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempURL.path),
            "temporary recording file must be deleted on cancel"
        )
        XCTAssertTrue(sender.voiceCalls.isEmpty)
    }

    func testPermissionDeniedShowsNonBlockingStateWithoutCrashing() async throws {
        let deniedBackend = FakeVoiceRecordingBackend(
            authStatus: .denied,
            requestAccessResult: false
        )
        let recorder = VoiceRecorderModel(backend: deniedBackend)
        // Microphone access is never requested at launch / init.
        XCTAssertEqual(deniedBackend.authCheckCallCount, 0)
        XCTAssertEqual(deniedBackend.requestAccessCallCount, 0)

        await recorder.start()
        XCTAssertEqual(recorder.state, .permissionDenied)
        XCTAssertEqual(
            deniedBackend.requestAccessCallCount, 0,
            "never prompts again once authorization status is denied"
        )

        // When status starts as .notDetermined and the user denies the prompt once,
        // subsequent record presses must never call requestAccess() again.
        let promptOnceBackend = FakeVoiceRecordingBackend(
            authStatus: .notDetermined,
            requestAccessResult: false
        )
        let promptOnceRecorder = VoiceRecorderModel(backend: promptOnceBackend)
        XCTAssertEqual(promptOnceBackend.requestAccessCallCount, 0)

        await promptOnceRecorder.start()
        XCTAssertEqual(promptOnceRecorder.state, .permissionDenied)
        XCTAssertEqual(promptOnceBackend.requestAccessCallCount, 1)

        await promptOnceRecorder.start()
        XCTAssertEqual(promptOnceRecorder.state, .permissionDenied)
        XCTAssertEqual(
            promptOnceBackend.requestAccessCallCount, 1,
            "never asks for microphone access again after a denial"
        )
    }

    func testRecorderStopsWhenChatChanges() async throws {
        let tempURL = try makeTempVoiceFile()
        let backend = FakeVoiceRecordingBackend(
            authStatus: .authorized,
            recordingURL: tempURL,
            meterSequence: [0.4, 0.8],
            stoppedDurationMS: 2000
        )
        let recorder = VoiceRecorderModel(backend: backend)
        let sender = VoiceSpySender()
        let composer = ComposerModel(sender: sender, voiceRecorder: recorder)
        composer.open("!roomA:courier.local")

        await recorder.start()
        recorder.sampleMeter()
        guard case .recording = recorder.state else {
            return XCTFail("Expected .recording state before switching chats")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        composer.open("!roomB:courier.local")
        await recorder.waitForPendingCancel()

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(backend.cancelCallCount, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempURL.path),
            "switching chats must stop recording and delete the temporary file"
        )
        XCTAssertTrue(sender.voiceCalls.isEmpty)
    }

    func testReviewBeforeSendAndSlashVoiceCommand() async throws {
        let tempURL = try makeTempVoiceFile()
        let backend = FakeVoiceRecordingBackend(
            devices: [AudioInputDevice(uid: "ext-mic", name: "Desk Microphone")],
            authStatus: .authorized,
            recordingURL: tempURL,
            meterSequence: [0.25, 0.75],
            stoppedDurationMS: 3100
        )
        let suiteName = "courier.test.voice.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ComposerPreferences(defaults: defaults)
        preferences.preferredMicrophoneUID = "ext-mic"
        XCTAssertEqual(defaults.string(forKey: ComposerPreferences.preferredMicrophoneUIDKey), "ext-mic")

        let recorder = VoiceRecorderModel(backend: backend)
        let sender = VoiceSpySender()
        let composer = ComposerModel(sender: sender, preferences: preferences, voiceRecorder: recorder)
        composer.open("!roomA:courier.local")

        // Typing /voice and submitting starts voice recording and clears the composer text.
        composer.text = "/voice"
        await composer.submit()?.value
        XCTAssertEqual(composer.text, "")
        XCTAssertEqual(backend.lastStartedDeviceUID, "ext-mic")
        guard case .recording = recorder.state else {
            return XCTFail("Expected /voice to start recording, got \(recorder.state)")
        }

        recorder.sampleMeter()
        recorder.sampleMeter()
        await recorder.stopForReview()

        guard case let .reviewing(reviewURL, durationMS, waveform) = recorder.state else {
            return XCTFail("Expected .reviewing state after stopForReview, got \(recorder.state)")
        }
        XCTAssertEqual(reviewURL, tempURL)
        XCTAssertEqual(durationMS, 3100)
        XCTAssertEqual(waveform, [25, 75])
        XCTAssertTrue(sender.voiceCalls.isEmpty, "nothing is uploaded until the person presses send")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        await recorder.stopAndSend(using: composer)
        await composer.settle()

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(sender.voiceCalls.count, 1)
        XCTAssertEqual(sender.voiceCalls.first?.durationMS, 3100)
        XCTAssertEqual(sender.voiceCalls.first?.waveform, [25, 75])
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testResolveAudioDeviceIDAndFallbackWhenPreferredDeviceUnplugged() async throws {
        let injectedList = [
            CoreAudioDeviceEntry(deviceID: 42, uid: "built-in-mic", name: "MacBook Pro Microphone", inputChannels: 1),
            CoreAudioDeviceEntry(deviceID: 77, uid: "usb-mic", name: "Studio USB Mic", inputChannels: 2),
            CoreAudioDeviceEntry(deviceID: 99, uid: "speakers-only", name: "External Speakers", inputChannels: 0),
        ]

        // 1. Matching input device UID resolves to its AudioDeviceID without fallback.
        let matched = AVAudioVoiceRecordingBackend.resolveAudioDeviceID(forUID: "usb-mic", in: injectedList)
        XCTAssertEqual(matched.deviceID, 77)
        XCTAssertFalse(matched.didFallback)

        // 2. Output-only device or missing UID falls back to nil (system default input) with didFallback == true.
        let missing = AVAudioVoiceRecordingBackend.resolveAudioDeviceID(forUID: "unplugged-mic", in: injectedList)
        XCTAssertNil(missing.deviceID)
        XCTAssertTrue(missing.didFallback)

        let outputOnly = AVAudioVoiceRecordingBackend.resolveAudioDeviceID(forUID: "speakers-only", in: injectedList)
        XCTAssertNil(outputOnly.deviceID)
        XCTAssertTrue(outputOnly.didFallback)

        // 3. Empty/nil UID uses system default without fallback warning.
        let defaultDev = AVAudioVoiceRecordingBackend.resolveAudioDeviceID(forUID: "", in: injectedList)
        XCTAssertNil(defaultDev.deviceID)
        XCTAssertFalse(defaultDev.didFallback)

        // 4. VoiceRecorderModel falls back to default input device and surfaces a notice when preferred UID is unplugged.
        let tempURL = try makeTempVoiceFile()
        let backend = FakeVoiceRecordingBackend(
            devices: [AudioInputDevice(uid: "built-in-mic", name: "MacBook Pro Microphone")],
            authStatus: .authorized,
            recordingURL: tempURL
        )
        let recorder = VoiceRecorderModel(backend: backend)
        await recorder.start(preferredDeviceUID: "unplugged-usb-mic")
        XCTAssertNil(
            backend.lastStartedDeviceUID,
            "when preferred deviceUID is not connected, recorder must fall back to default input device (nil)"
        )
        XCTAssertNotNil(recorder.deviceFallbackNotice, "must surface a notice when preferred microphone is unavailable")
        await recorder.cancel()
    }
}

private final class FakeVoiceRecordingBackend: VoiceRecordingBackend, @unchecked Sendable {
    private let lock = NSLock()
    var devices: [AudioInputDevice]
    var authStatus: MicrophoneAuthStatus
    var requestAccessResult: Bool
    var recordingURL: URL
    var meterSequence: [Float]
    var stoppedDurationMS: Int
    private var meterIndex = 0

    private(set) var authCheckCallCount = 0
    private(set) var requestAccessCallCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var lastStartedDeviceUID: String?

    init(
        devices: [AudioInputDevice] = [],
        authStatus: MicrophoneAuthStatus = .authorized,
        requestAccessResult: Bool = true,
        recordingURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("fake-voice.m4a"),
        meterSequence: [Float] = [0.5],
        stoppedDurationMS: Int = 1000
    ) {
        self.devices = devices
        self.authStatus = authStatus
        self.requestAccessResult = requestAccessResult
        self.recordingURL = recordingURL
        self.meterSequence = meterSequence
        self.stoppedDurationMS = stoppedDurationMS
    }

    func availableDevices() -> [AudioInputDevice] {
        lock.withLock { devices }
    }

    func authorizationStatus() -> MicrophoneAuthStatus {
        lock.withLock {
            authCheckCallCount += 1
            return authStatus
        }
    }

    func requestAccess() async -> Bool {
        lock.withLock {
            requestAccessCallCount += 1
            if requestAccessResult {
                authStatus = .authorized
            } else {
                authStatus = .denied
            }
            return requestAccessResult
        }
    }

    func startRecording(deviceUID: String?) async throws -> URL {
        lock.withLock {
            startCallCount += 1
            lastStartedDeviceUID = deviceUID
            meterIndex = 0
            return recordingURL
        }
    }

    func currentMeterLevel() -> Float {
        lock.withLock {
            guard !meterSequence.isEmpty else { return 0 }
            let value = meterSequence[min(meterIndex, meterSequence.count - 1)]
            meterIndex += 1
            return value
        }
    }

    func stopRecording() async throws -> RecordedVoiceNote {
        lock.withLock {
            stopCallCount += 1
            return RecordedVoiceNote(url: recordingURL, durationMS: stoppedDurationMS, waveform: [])
        }
    }

    func cancelRecording() async {
        let url = lock.withLock { () -> URL in
            cancelCallCount += 1
            return recordingURL
        }
        try? FileManager.default.removeItem(at: url)
    }
}

private final class VoiceSpySender: MessageSending, @unchecked Sendable {
    struct VoiceCall: Equatable {
        let roomID: String
        let url: URL
        let durationMS: Int64
        let waveform: [Int]
        let replyTo: String?
    }

    private let lock = NSLock()
    private var _voiceCalls: [VoiceCall] = []

    var voiceCalls: [VoiceCall] {
        lock.withLock { _voiceCalls }
    }

    func sendText(roomID: String, text: String, replyTo: String?) async throws {}
    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?) async throws {}
    func send(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, holdMillis: Int) async throws -> String { "$1" }
    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?, threadRoot: String?, holdMillis: Int) async throws -> String { "$1" }
    func edit(eventID: String, rich: RichText) async throws {}
    func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date, condition: SendLaterCondition) async throws {}
    func undo(eventID: String) async throws -> Draft { Draft(text: "", entities: [], replyTo: nil, threadRoot: nil) }
    func sendHeld(roomID: String?) async throws {}
    func members(roomID: String, query: String) async throws -> [Member] { [] }
    func status(of eventID: String, in roomID: String, thread: String?) async throws -> StatusLine? { nil }
    func setTyping(roomID: String, typing: Bool) async throws {}
    func setUnreadFrom(eventID: String) async throws {}
    func directChat(roomID: String, userID: String) async throws -> String { "!dm" }
    func sendVoice(roomID: String, url: URL, durationMS: Int64, waveform: [Int], replyTo: String?) async throws -> String {
        lock.withLock {
            _voiceCalls.append(VoiceCall(roomID: roomID, url: url, durationMS: durationMS, waveform: waveform, replyTo: replyTo))
        }
        return "$voice-1"
    }
}
