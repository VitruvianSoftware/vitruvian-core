// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import Foundation

public struct AudioInputDevice: Equatable, Identifiable, Sendable {
    public let uid: String
    public let name: String

    public var id: String { uid }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

public enum MicrophoneAuthStatus: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public struct RecordedVoiceNote: Equatable, Sendable {
    public let url: URL
    public let durationMS: Int
    public let waveform: [Int]

    public init(url: URL, durationMS: Int, waveform: [Int] = []) {
        self.url = url
        self.durationMS = durationMS
        self.waveform = waveform
    }
}

public protocol VoiceRecordingBackend: Sendable {
    func availableDevices() -> [AudioInputDevice]
    func authorizationStatus() -> MicrophoneAuthStatus
    func requestAccess() async -> Bool
    func startRecording(deviceUID: String?) async throws -> URL
    func currentMeterLevel() -> Float // 0.0 ... 1.0
    func stopRecording() async throws -> RecordedVoiceNote
    func cancelRecording() async
}

public final class AVAudioVoiceRecordingBackend: NSObject, VoiceRecordingBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var recorder: AVAudioRecorder?
    private var activeURL: URL?
    private var startedAt: Date?

    public override init() {
        super.init()
    }

    public func availableDevices() -> [AudioInputDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { AudioInputDevice(uid: $0.uniqueID, name: $0.localizedName) }
    }

    public func authorizationStatus() -> MicrophoneAuthStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func startRecording(deviceUID: String?) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("courier-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder.isMeteringEnabled = true
        guard audioRecorder.prepareToRecord(), audioRecorder.record() else {
            try? FileManager.default.removeItem(at: url)
            throw VoiceRecorderError.couldNotStart
        }
        lock.withLock {
            recorder = audioRecorder
            activeURL = url
            startedAt = Date()
        }
        return url
    }

    public func currentMeterLevel() -> Float {
        lock.withLock {
            guard let recorder else { return 0 }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let clamped = max(-60.0, min(0.0, power))
            return (clamped + 60.0) / 60.0
        }
    }

    public func stopRecording() async throws -> RecordedVoiceNote {
        let (audioRecorder, url, start) = lock.withLock { () -> (AVAudioRecorder?, URL?, Date?) in
            defer {
                recorder = nil
                activeURL = nil
                startedAt = nil
            }
            return (recorder, activeURL, startedAt)
        }
        guard let audioRecorder, let url else {
            throw VoiceRecorderError.notRecording
        }
        let currentTime = audioRecorder.currentTime
        audioRecorder.stop()
        let elapsedSeconds = currentTime > 0 ? currentTime : (start.map { Date().timeIntervalSince($0) } ?? 0)
        let durationMS = max(0, Int((elapsedSeconds * 1000.0).rounded()))
        return RecordedVoiceNote(url: url, durationMS: durationMS, waveform: [])
    }

    public func cancelRecording() async {
        let (audioRecorder, url) = lock.withLock { () -> (AVAudioRecorder?, URL?) in
            defer {
                recorder = nil
                activeURL = nil
                startedAt = nil
            }
            return (recorder, activeURL)
        }
        audioRecorder?.stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

public enum VoiceRecorderError: Error, Equatable {
    case couldNotStart
    case notRecording
}

@MainActor
public final class VoiceRecorderModel: ObservableObject {
    public nonisolated static let maxWaveformBars = 64
    public nonisolated static let meterIntervalSeconds: TimeInterval = 0.05

    public enum State: Equatable {
        case idle
        case recording(startedAt: Date, elapsedMS: Int, levels: [Int])
        case reviewing(url: URL, durationMS: Int, waveform: [Int])
        case permissionDenied
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var availableDevices: [AudioInputDevice] = []

    private let backend: VoiceRecordingBackend
    private let now: () -> Date
    private let automaticallyPollsMeter: Bool
    private var meterTimer: Timer?
    private var activeRecordingURL: URL?
    private var hasBeenDenied = false
    private var pendingCancelTask: Task<Void, Never>?

    public init(
        backend: VoiceRecordingBackend = AVAudioVoiceRecordingBackend(),
        now: @escaping () -> Date = Date.init,
        automaticallyPollsMeter: Bool? = nil
    ) {
        self.backend = backend
        self.now = now
        self.automaticallyPollsMeter = automaticallyPollsMeter ?? (backend is AVAudioVoiceRecordingBackend)
        // Device discovery does not prompt for microphone access; permission is never checked or requested at launch.
        self.availableDevices = backend.availableDevices()
    }

    public var isRecordingOrReviewing: Bool {
        switch state {
        case .recording, .reviewing:
            return true
        case .idle, .permissionDenied, .failed:
            return false
        }
    }

    public func refreshDevices() {
        availableDevices = backend.availableDevices()
    }

    public func start(preferredDeviceUID: String = "") async {
        if hasBeenDenied {
            state = .permissionDenied
            return
        }
        let status = backend.authorizationStatus()
        switch status {
        case .denied, .restricted:
            hasBeenDenied = true
            state = .permissionDenied
            return
        case .notDetermined:
            let granted = await backend.requestAccess()
            guard granted else {
                hasBeenDenied = true
                state = .permissionDenied
                return
            }
        case .authorized:
            break
        }

        stopMeterTimer()
        do {
            let uid = preferredDeviceUID.isEmpty ? nil : preferredDeviceUID
            let url = try await backend.startRecording(deviceUID: uid)
            activeRecordingURL = url
            let startTime = now()
            state = .recording(startedAt: startTime, elapsedMS: 0, levels: [])
            if automaticallyPollsMeter {
                startMeterTimer()
            }
        } catch {
            activeRecordingURL = nil
            state = .failed(String(localized: "Could not start recording."))
        }
    }

    public func sampleMeter(elapsedMS: Int? = nil) {
        guard case let .recording(startedAt, _, currentLevels) = state else { return }
        let raw = backend.currentMeterLevel()
        let clamped = max(Float(0.0), min(Float(1.0), raw))
        let bar = Int((clamped * 100.0).rounded())
        var updatedLevels = currentLevels
        updatedLevels.append(bar)
        let computedElapsed = elapsedMS ?? max(0, Int((now().timeIntervalSince(startedAt) * 1000.0).rounded()))
        state = .recording(startedAt: startedAt, elapsedMS: computedElapsed, levels: updatedLevels)
    }

    public func stopForReview() async {
        guard case let .recording(_, elapsedMS, levels) = state else { return }
        stopMeterTimer()
        do {
            let note = try await backend.stopRecording()
            let waveform = Self.normalizeWaveform(note.waveform.isEmpty ? levels : note.waveform)
            let durationMS = note.durationMS > 0 ? note.durationMS : elapsedMS
            activeRecordingURL = note.url
            state = .reviewing(url: note.url, durationMS: durationMS, waveform: waveform)
        } catch {
            if let url = activeRecordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            activeRecordingURL = nil
            state = .failed(String(localized: "Could not save voice note."))
        }
    }

    public func stopAndSend(using composer: ComposerModel) async {
        stopMeterTimer()
        let url: URL
        let durationMS: Int
        let waveform: [Int]

        switch state {
        case let .recording(_, elapsedMS, levels):
            do {
                let note = try await backend.stopRecording()
                url = note.url
                durationMS = note.durationMS > 0 ? note.durationMS : elapsedMS
                waveform = Self.normalizeWaveform(note.waveform.isEmpty ? levels : note.waveform)
            } catch {
                if let activeURL = activeRecordingURL {
                    try? FileManager.default.removeItem(at: activeURL)
                }
                activeRecordingURL = nil
                state = .failed(String(localized: "Could not save voice note."))
                return
            }
        case let .reviewing(reviewURL, reviewDurationMS, reviewWaveform):
            url = reviewURL
            durationMS = reviewDurationMS
            waveform = Self.normalizeWaveform(reviewWaveform)
        case .idle, .permissionDenied, .failed:
            return
        }

        activeRecordingURL = nil
        state = .idle
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        await composer.sendVoiceNote(url: url, durationMS: durationMS, waveform: waveform)
    }

    public func cancel() async {
        let task = beginCancel()
        await task?.value
    }

    /// Cancels any active or reviewed recording immediately on the main actor (used on chat change, Escape, window
    /// close, and app termination) and cleans up the temporary file on disk.
    public func cancelImmediately() {
        _ = beginCancel()
    }

    public func waitForPendingCancel() async {
        await pendingCancelTask?.value
    }

    public func dismissBanner() {
        if case .permissionDenied = state {
            state = .idle
        } else if case .failed = state {
            state = .idle
        }
    }

    @discardableResult
    private func beginCancel() -> Task<Void, Never>? {
        stopMeterTimer()
        let wasRecording: Bool
        var urlToDelete = activeRecordingURL
        switch state {
        case .recording:
            wasRecording = true
        case let .reviewing(url, _, _):
            wasRecording = false
            urlToDelete = url
        case .idle, .permissionDenied, .failed:
            wasRecording = false
        }
        activeRecordingURL = nil
        state = .idle

        if let urlToDelete {
            try? FileManager.default.removeItem(at: urlToDelete)
        }
        guard wasRecording else { return nil }
        let backend = self.backend
        let url = urlToDelete
        let task = Task {
            await backend.cancelRecording()
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
        }
        pendingCancelTask = task
        return task
    }

    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: Self.meterIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleMeter()
            }
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    public nonisolated static func normalizeWaveform(_ raw: [Int], maxBars: Int = maxWaveformBars) -> [Int] {
        guard !raw.isEmpty else { return [] }
        let clamped = raw.map { max(0, min(100, $0)) }
        guard clamped.count > maxBars, maxBars > 0 else { return clamped }
        var bars: [Int] = []
        bars.reserveCapacity(maxBars)
        let step = Double(clamped.count) / Double(maxBars)
        for index in 0 ..< maxBars {
            let start = Int((Double(index) * step).rounded(.down))
            let end = max(start + 1, min(clamped.count, Int((Double(index + 1) * step).rounded(.down))))
            let slice = clamped[start ..< end]
            let peak = slice.max() ?? 0
            bars.append(peak)
        }
        return bars
    }
}
