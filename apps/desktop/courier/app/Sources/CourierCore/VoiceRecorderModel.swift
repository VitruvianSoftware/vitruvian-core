// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AudioToolbox
import AVFoundation
import CoreAudio
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

public struct CoreAudioDeviceEntry: Equatable, Sendable {
    public let deviceID: UInt32
    public let uid: String
    public let name: String
    public let inputChannels: Int

    public init(deviceID: UInt32, uid: String, name: String, inputChannels: Int = 1) {
        self.deviceID = deviceID
        self.uid = uid
        self.name = name
        self.inputChannels = inputChannels
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
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var lastEngineMeterLevel: Float = 0
    private var engineWriteFailed = false
    private var activeURL: URL?
    private var startedAt: Date?

    public override init() {
        super.init()
    }

    public static func resolveAudioDeviceID(
        forUID uid: String?,
        in devices: [CoreAudioDeviceEntry]
    ) -> (deviceID: UInt32?, didFallback: Bool) {
        guard let uid, !uid.isEmpty else {
            return (nil, false)
        }
        if let matched = devices.first(where: { $0.uid == uid && $0.inputChannels > 0 }) {
            return (matched.deviceID, false)
        }
        return (nil, true)
    }

    public static func systemInputDevices() -> [CoreAudioDeviceEntry] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObjectID, &propertyAddress, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else {
            return []
        }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(systemObjectID, &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        var entries: [CoreAudioDeviceEntry] = []
        for devID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidRef: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(devID, &uidAddress, 0, nil, &uidSize, &uidRef) == noErr,
                  let uid = uidRef?.takeUnretainedValue() as String?
            else {
                continue
            }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let name: String
            if AudioObjectGetPropertyData(devID, &nameAddress, 0, nil, &nameSize, &nameRef) == noErr,
               let resolvedName = nameRef?.takeUnretainedValue() as String? {
                name = resolvedName
            } else {
                name = uid
            }

            let channels = inputChannelCount(for: devID)
            entries.append(CoreAudioDeviceEntry(deviceID: devID, uid: uid, name: name, inputChannels: channels))
        }
        return entries
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &streamAddress, 0, nil, &size, rawPtr) == noErr else {
            return 0
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(rawPtr.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
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

        let resolved = Self.resolveAudioDeviceID(forUID: deviceUID, in: Self.systemInputDevices())
        if let targetDeviceID = resolved.deviceID,
           startEngineRecording(to: url, deviceID: targetDeviceID, settings: settings) {
            return url
        }

        let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder.isMeteringEnabled = true
        guard audioRecorder.prepareToRecord(), audioRecorder.record() else {
            try? FileManager.default.removeItem(at: url)
            throw VoiceRecorderError.couldNotStart
        }
        lock.withLock {
            recorder = audioRecorder
            audioEngine = nil
            audioFile = nil
            lastEngineMeterLevel = 0
            activeURL = url
            startedAt = Date()
        }
        return url
    }

    private func startEngineRecording(to url: URL, deviceID: UInt32, settings: [String: Any]) -> Bool {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            return false
        }
        var mutableDeviceID = AudioDeviceID(deviceID)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            return false
        }
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0,
              let file = try? Self.makeEngineFile(at: url, matching: format)
        else {
            return false
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let wrote = (try? file.write(from: buffer)) != nil
            let level = Self.computeBufferMeterLevel(buffer)
            self.lock.withLock {
                self.lastEngineMeterLevel = level
                if !wrote { self.engineWriteFailed = true }
            }
        }
        do {
            try engine.start()
            lock.withLock {
                recorder = nil
                audioEngine = engine
                audioFile = file
                lastEngineMeterLevel = 0
                engineWriteFailed = false
                activeURL = url
                startedAt = Date()
            }
            return true
        } catch {
            inputNode.removeTap(onBus: 0)
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    /// The file the selected-microphone path writes into: AAC in an .m4a, created for the microphone's own
    /// sample rate, channel count and sample layout, because the tap hands over buffers in that format and
    /// `AVAudioFile.write(from:)` refuses any other (which would leave a silent note).
    static func makeEngineFile(at url: URL, matching format: AVAudioFormat) throws -> AVAudioFile {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        return try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
    }

    private static func computeBufferMeterLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let channelData = buffer.floatChannelData?[0] else {
            return 0
        }
        var sumSquares: Float = 0
        for index in 0 ..< frameLength {
            let sample = channelData[index]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameLength))
        guard rms > 0 else { return 0 }
        let decibels = 20.0 * log10(rms)
        let clamped = max(-60.0, min(0.0, decibels))
        return (clamped + 60.0) / 60.0
    }

    public func currentMeterLevel() -> Float {
        lock.withLock {
            if audioEngine != nil {
                return lastEngineMeterLevel
            }
            guard let recorder else { return 0 }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let clamped = max(-60.0, min(0.0, power))
            return (clamped + 60.0) / 60.0
        }
    }

    public func stopRecording() async throws -> RecordedVoiceNote {
        let (audioRecorder, engine, url, start, writeFailed) = lock.withLock { () -> (AVAudioRecorder?, AVAudioEngine?, URL?, Date?, Bool) in
            defer {
                recorder = nil
                audioEngine = nil
                audioFile = nil
                lastEngineMeterLevel = 0
                engineWriteFailed = false
                activeURL = nil
                startedAt = nil
            }
            return (recorder, audioEngine, activeURL, startedAt, engineWriteFailed)
        }
        if let engine, let url {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            if writeFailed {
                try? FileManager.default.removeItem(at: url)
                throw VoiceRecorderError.recordingFailed
            }
            let elapsedSeconds = start.map { Date().timeIntervalSince($0) } ?? 0
            let durationMS = max(0, Int((elapsedSeconds * 1000.0).rounded()))
            return RecordedVoiceNote(url: url, durationMS: durationMS, waveform: [])
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
        let (audioRecorder, engine, url) = lock.withLock { () -> (AVAudioRecorder?, AVAudioEngine?, URL?) in
            defer {
                recorder = nil
                audioEngine = nil
                audioFile = nil
                lastEngineMeterLevel = 0
                activeURL = nil
                startedAt = nil
            }
            return (recorder, audioEngine, activeURL)
        }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
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
    /// The microphone delivered audio that could not be written, so there is no usable recording.
    case recordingFailed
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
    @Published public private(set) var deviceFallbackNotice: String?

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
        availableDevices = backend.availableDevices()
        let trimmedUID = preferredDeviceUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid: String?
        if trimmedUID.isEmpty {
            deviceFallbackNotice = nil
            uid = nil
        } else if availableDevices.contains(where: { $0.uid == trimmedUID }) {
            deviceFallbackNotice = nil
            uid = trimmedUID
        } else {
            deviceFallbackNotice = String(
                localized: "Preferred microphone isn’t connected. Recording with the system default microphone."
            )
            uid = nil
        }
        do {
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
