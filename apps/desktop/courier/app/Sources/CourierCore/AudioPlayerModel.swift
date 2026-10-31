// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import AVFoundation
import Combine
import Foundation

/// Injectable playback backend for `AudioPlayerModel`. Production uses `AVAudioPlayerBackend` on local media store
/// files; tests inject a deterministic fake without touching audio hardware.
@MainActor
public protocol AudioPlaybackBackend: AnyObject {
    var currentTimeSec: TimeInterval { get }
    var durationSec: TimeInterval { get }
    func load(url: URL, rate: Float, onFinish: @escaping @MainActor () -> Void) throws
    func play()
    func pause()
    func stop()
    func seek(toFraction fraction: Double)
    func setRate(_ rate: Float)
}

/// Default `AVAudioPlayer`-backed implementation of `AudioPlaybackBackend` for local audio files.
@MainActor
public final class AVAudioPlayerBackend: NSObject, AudioPlaybackBackend, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var finishHandler: (@MainActor () -> Void)?

    public override init() {
        super.init()
    }

    public var currentTimeSec: TimeInterval {
        player?.currentTime ?? 0
    }

    public var durationSec: TimeInterval {
        player?.duration ?? 0
    }

    public func load(url: URL, rate: Float, onFinish: @escaping @MainActor () -> Void) throws {
        player?.stop()
        finishHandler = onFinish
        let audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer.delegate = self
        audioPlayer.enableRate = true
        audioPlayer.rate = rate
        audioPlayer.prepareToPlay()
        audioPlayer.play()
        player = audioPlayer
    }

    public func play() {
        player?.play()
    }

    public func pause() {
        player?.pause()
    }

    public func stop() {
        player?.stop()
        player = nil
        finishHandler = nil
    }

    public func seek(toFraction fraction: Double) {
        guard let player, player.duration > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        player.currentTime = player.duration * clamped
    }

    public func setRate(_ rate: Float) {
        guard let player else { return }
        player.enableRate = true
        player.rate = rate
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.finishHandler?()
        }
    }
}

/// App-wide voice-note & audio player (`Audio.tsx`, `MSC1767Audio`, and `GlobalAudioPlayer.tsx`).
///
/// Plays local files from the media store only, persists the chosen playback speed (`0.5×`, `1×`, `1.5×`, `2×`)
/// app-wide, marks voice notes played locally via `message.markPlayed` (never sending any network receipt),
/// advances to the next consecutive voice note in the same chat when `autoPlayNextVoiceNote` is enabled, and
/// surfaces `shouldShowGlobalBar` when the user switches away from the playing chat.
@MainActor
public final class AudioPlayerModel: ObservableObject {
    public struct Track: Equatable, Sendable {
        public let eventID: String
        public let roomID: String
        public let mediaPath: String
        public let senderName: String
        public let chatTitle: String
        public let durationMS: Int
        public let waveform: [Int]
        public let isVoiceNote: Bool

        public init(
            eventID: String,
            roomID: String,
            mediaPath: String,
            senderName: String,
            chatTitle: String,
            durationMS: Int,
            waveform: [Int] = [],
            isVoiceNote: Bool = true
        ) {
            self.eventID = eventID
            self.roomID = roomID
            self.mediaPath = mediaPath
            self.senderName = senderName
            self.chatTitle = chatTitle
            self.durationMS = max(durationMS, 0)
            self.waveform = waveform
            self.isVoiceNote = isVoiceNote
        }
    }

    public enum Speed: Double, CaseIterable, Sendable {
        case half = 0.5
        case one = 1.0
        case onePointFive = 1.5
        case two = 2.0

        public var label: String {
            switch self {
            case .half: "0.5×"
            case .one: "1×"
            case .onePointFive: "1.5×"
            case .two: "2×"
            }
        }

        public var next: Speed {
            switch self {
            case .one: .onePointFive
            case .onePointFive: .two
            case .two: .half
            case .half: .one
            }
        }
    }

    public static let speedDefaultsKey = "courier.audio.playbackSpeed"

    @Published public private(set) var currentTrack: Track?
    @Published public private(set) var isPlaying = false
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var elapsedMS: Int = 0
    @Published public var speed: Speed

    public weak var appModel: AppModel?
    public weak var conversation: ConversationModel?
    public var preferences: ComposerPreferences?

    private let defaults: UserDefaults
    private var backend: any AudioPlaybackBackend
    private var queueInRoom: [Track] = []
    private var progressTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var terminationObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private weak var observedLifecycle: SystemLifecycleModel?

    public var lifecycle: SystemLifecycleModel {
        observedLifecycle ?? conversation?.lifecycle ?? appModel?.lifecycle ?? AppLockGate.shared.lifecycle
    }

    public var isLocked: Bool {
        !AppLockGate.shared.canPerform(.other, lifecycle: lifecycle)
    }

    public init(
        appModel: AppModel? = nil,
        conversation: ConversationModel? = nil,
        preferences: ComposerPreferences? = nil,
        defaults: UserDefaults = .standard,
        backend: (any AudioPlaybackBackend)? = nil,
        lifecycle: SystemLifecycleModel? = nil
    ) {
        self.appModel = appModel
        self.conversation = conversation
        self.preferences = preferences
        self.defaults = defaults
        self.backend = backend ?? AVAudioPlayerBackend()
        self.observedLifecycle = lifecycle

        if let stored = defaults.object(forKey: Self.speedDefaultsKey) as? Double,
           let resolved = Speed(rawValue: stored) {
            self.speed = resolved
        } else {
            self.speed = .one
        }

        bindAppModel(appModel)

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopForApplicationTermination()
            }
        }
        lockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didLockNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.observedLifecycle = notification.object as? SystemLifecycleModel
                self?.stop()
            }
        }
    }

    deinit {
        progressTimer?.invalidate()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        if let lockObserver {
            NotificationCenter.default.removeObserver(lockObserver)
        }
    }

    public func bindAppModel(_ appModel: AppModel?) {
        self.appModel = appModel
        cancellables.removeAll()
        guard let appModel else { return }
        appModel.$selectedRoomID
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        appModel.$mergedChats
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public func setBackendForTesting(_ backend: any AudioPlaybackBackend) {
        stop()
        self.backend = backend
    }

    /// Sets deterministic state for view snapshot tests without starting real audio playback.
    public func setPreviewState(
        track: Track?,
        isPlaying: Bool,
        progress: Double,
        elapsedMS: Int,
        speed: Speed = .one
    ) {
        stopProgressTimer()
        currentTrack = track
        self.isPlaying = isPlaying
        self.progress = min(max(progress, 0), 1)
        self.elapsedMS = max(elapsedMS, 0)
        self.speed = speed
    }

    /// True when a track is loaded and the user has switched away from the track's room.
    public var shouldShowGlobalBar: Bool {
        guard let track = currentTrack else { return false }
        guard let appModel else { return true }
        return !appModel.isOpen(roomID: track.roomID)
    }

    /// Resolves a local media store file path to a file URL, refusing empty strings or any remote URL scheme.
    public static func localMediaURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://")
            || lowered.hasPrefix("https://")
            || lowered.hasPrefix("mxc://")
            || lowered.hasPrefix("ws://")
            || lowered.hasPrefix("wss://") {
            return nil
        }
        let filePath: String
        if lowered.hasPrefix("file://"), let url = URL(string: trimmed), url.isFileURL {
            filePath = url.path
        } else if trimmed.hasPrefix("/") {
            filePath = trimmed
        } else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: filePath) else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    public func playOrPause(_ track: Track, queueInRoom: [Track] = []) {
        guard !isLocked else { return }
        guard let url = Self.localMediaURL(for: track.mediaPath) else { return }

        if currentTrack?.eventID == track.eventID {
            if !queueInRoom.isEmpty {
                self.queueInRoom = Self.filteredQueue(queueInRoom, startingAt: track)
            }
            if isPlaying {
                backend.pause()
                isPlaying = false
                stopProgressTimer()
            } else {
                backend.play()
                isPlaying = true
                startProgressTimer()
            }
            return
        }

        let resolvedQueue = queueInRoom.isEmpty
            ? (conversation?.voiceNoteQueue(startingAt: track.eventID) ?? [track])
            : Self.filteredQueue(queueInRoom, startingAt: track)
        startTrack(track, url: url, queue: resolvedQueue)
    }

    public func seek(to fraction: Double) {
        guard !isLocked, let track = currentTrack else { return }
        let clamped = min(max(fraction, 0), 1)
        backend.seek(toFraction: clamped)
        progress = clamped
        elapsedMS = Int((Double(track.durationMS) * clamped).rounded())
    }

    public func cycleSpeed() {
        guard !isLocked else { return }
        let next = speed.next
        speed = next
        defaults.set(next.rawValue, forKey: Self.speedDefaultsKey)
        backend.setRate(Float(next.rawValue))
    }

    public func stop() {
        stopProgressTimer()
        backend.stop()
        isPlaying = false
        currentTrack = nil
        progress = 0
        elapsedMS = 0
        queueInRoom = []
    }

    public func stopForApplicationTermination() {
        stop()
    }

    public func handleTrackFinished() async {
        guard !isLocked else {
            stop()
            return
        }
        guard let finished = currentTrack else { return }
        stopProgressTimer()

        if finished.isVoiceNote {
            await conversation?.markMediaPlayed(eventID: finished.eventID, roomID: finished.roomID)
        }

        let autoPlay = preferences?.autoPlayNextVoiceNote
            ?? (defaults.object(forKey: ComposerPreferences.autoPlayNextVoiceNoteKey) as? Bool ?? true)

        if autoPlay,
           let idx = queueInRoom.firstIndex(where: { $0.eventID == finished.eventID }),
           idx + 1 < queueInRoom.count {
            let nextTrack = queueInRoom[idx + 1]
            if nextTrack.roomID == finished.roomID,
               nextTrack.isVoiceNote,
               let nextURL = Self.localMediaURL(for: nextTrack.mediaPath) {
                startTrack(nextTrack, url: nextURL, queue: queueInRoom)
                return
            }
        }

        stop()
    }

    // MARK: - Private

    private func startTrack(_ track: Track, url: URL, queue: [Track]) {
        stopProgressTimer()
        do {
            try backend.load(url: url, rate: Float(speed.rawValue)) { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.handleTrackFinished()
                }
            }
        } catch {
            stop()
            return
        }
        queueInRoom = queue
        currentTrack = track
        isPlaying = true
        progress = 0
        elapsedMS = 0
        startProgressTimer()

        if track.isVoiceNote {
            let eventID = track.eventID
            let roomID = track.roomID
            Task { @MainActor [weak self] in
                await self?.conversation?.markMediaPlayed(eventID: eventID, roomID: roomID)
            }
        }
    }

    /// Filters a candidate queue so it starts at `first` and contains only consecutive voice notes in the same chat.
    private static func filteredQueue(_ candidates: [Track], startingAt first: Track) -> [Track] {
        guard let startIndex = candidates.firstIndex(where: { $0.eventID == first.eventID }) else {
            return [first]
        }
        var result: [Track] = []
        for candidate in candidates[startIndex...] {
            guard candidate.roomID == first.roomID, candidate.isVoiceNote else { break }
            result.append(candidate)
        }
        return result.isEmpty ? [first] : result
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncProgressFromBackend()
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func syncProgressFromBackend() {
        guard let track = currentTrack, isPlaying else { return }
        let totalSec = backend.durationSec > 0 ? backend.durationSec : Double(track.durationMS) / 1000.0
        guard totalSec > 0 else { return }
        let currentSec = min(max(backend.currentTimeSec, 0), totalSec)
        progress = min(max(currentSec / totalSec, 0), 1)
        elapsedMS = Int((currentSec * 1000).rounded())
    }
}
