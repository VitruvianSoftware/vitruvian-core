// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import AVFoundation
import AVKit
import CourierCore
import SwiftUI

/// AppKit `AVPlayerView` wrapper with native controls hidden so `InlineVideoPlayer` and `PictureInPictureView`
/// render Courier's own SwiftUI transport bar. Enables `allowsPictureInPicturePlayback` on macOS 14.
struct AVPlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context _: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.allowsPictureInPicturePlayback = true
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context _: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.controlsStyle = .none
        nsView.allowsPictureInPicturePlayback = true
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator _: ()) {
        nsView.player = nil
    }
}

/// Manages local `AVPlayer` playback state for a single video view.
@MainActor
final class InlineVideoPlayerModel: ObservableObject {
    @Published var isPlaying: Bool
    @Published var elapsedMS: Int
    @Published var durationMS: Int
    @Published var speed: InlineVideoPlayer.Speed
    @Published var isMuted: Bool
    @Published var showsControls: Bool
    @Published private(set) var player: AVPlayer?
    @Published private(set) var hasError = false

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var currentPath: String = ""
    private var isLoopingGIF = false

    init(
        isPlaying: Bool = false,
        elapsedMS: Int = 0,
        durationMS: Int = 0,
        speed: InlineVideoPlayer.Speed = .one,
        isMuted: Bool = false,
        showsControls: Bool = false
    ) {
        self.isPlaying = isPlaying
        self.elapsedMS = elapsedMS
        self.durationMS = durationMS
        self.speed = speed
        self.isMuted = isMuted
        self.showsControls = showsControls
    }

    func configure(
        mediaPath: String,
        fallbackDurationMS: Int?,
        isGIF: Bool,
        autoStartGIF: Bool
    ) {
        if let fallbackDurationMS, fallbackDurationMS > 0, durationMS == 0 {
            durationMS = fallbackDurationMS
        }
        isLoopingGIF = isGIF
        guard currentPath != mediaPath else { return }
        tearDownPlayer()
        currentPath = mediaPath

        guard let localURL = InlineVideoPlayer.localMediaURL(for: mediaPath) else {
            hasError = !mediaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return
        }
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            hasError = true
            return
        }
        hasError = false

        let avPlayer = AVPlayer(url: localURL)
        avPlayer.isMuted = isGIF ? true : isMuted
        player = avPlayer

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite, seconds >= 0 else { return }
            let ms = Int((seconds * 1000).rounded())
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedMS = ms
                if let itemDuration = self.player?.currentItem?.duration {
                    let totalSec = CMTimeGetSeconds(itemDuration)
                    if totalSec.isFinite, totalSec > 0 {
                        self.durationMS = Int((totalSec * 1000).rounded())
                    }
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: avPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isLoopingGIF {
                    self.player?.seek(to: .zero)
                    self.player?.playImmediately(atRate: self.speed.rawValue)
                } else {
                    self.isPlaying = false
                    self.elapsedMS = 0
                    self.player?.seek(to: .zero)
                }
            }
        }

        if isGIF && autoStartGIF {
            isMuted = true
            isPlaying = true
            avPlayer.isMuted = true
            avPlayer.playImmediately(atRate: speed.rawValue)
        } else if isPlaying {
            if elapsedMS > 0 {
                let target = CMTime(seconds: Double(elapsedMS) / 1000.0, preferredTimescale: 600)
                avPlayer.seek(to: target)
            }
            avPlayer.playImmediately(atRate: speed.rawValue)
        }
    }

    func togglePlayPause() {
        guard !hasError else { return }
        showsControls = true
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !hasError else { return }
        showsControls = true
        isPlaying = true
        player?.isMuted = isMuted
        player?.playImmediately(atRate: speed.rawValue)
    }

    func pause() {
        isPlaying = false
        player?.pause()
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    func selectSpeed(_ newSpeed: InlineVideoPlayer.Speed) {
        speed = newSpeed
        if isPlaying {
            player?.rate = newSpeed.rawValue
        }
    }

    func seek(toFraction fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        let total = max(durationMS, 1)
        let targetMS = Int((Double(total) * clamped).rounded())
        elapsedMS = targetMS
        let targetTime = CMTime(seconds: Double(targetMS) / 1000.0, preferredTimescale: 600)
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stopInlineOnDisappear() {
        pause()
        tearDownPlayer()
    }

    private func tearDownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        currentPath = ""
    }
}

/// Inline video player (`BrandVideo.tsx`) with a custom SwiftUI transport bar (Play/Pause, time elapsed / total
/// duration, scrub slider, playback speed menu `0.25×`–`2×`, Mute toggle, Picture in Picture button, and Expand
/// button). When `isGIF == true`, auto-plays muted in a loop with no transport bar unless hovered.
public struct InlineVideoPlayer: View {
    public enum Speed: Float, CaseIterable, Sendable {
        case quarter = 0.25
        case half = 0.5
        case one = 1.0
        case onePointTwoFive = 1.25
        case onePointFive = 1.5
        case two = 2.0

        public var label: String {
            switch self {
            case .quarter: return "0.25×"
            case .half: return "0.5×"
            case .one: return "1×"
            case .onePointTwoFive: return "1.25×"
            case .onePointFive: return "1.5×"
            case .two: return "2×"
            }
        }
    }

    public let messageID: String
    public let roomID: String
    public let mediaPath: String
    public let thumbnailPath: String?
    public let blurhash: String?
    public let width: Int?
    public let height: Int?
    public let durationMS: Int?
    public let isGIF: Bool
    public let onPopOutPiP: () -> Void
    public let onOpenLightbox: () -> Void
    public var preloadedPoster: NSImage?

    @StateObject private var model: InlineVideoPlayerModel
    @State private var loadedPosterCGImage: CGImage?
    @State private var isHovering = false

    public static let longestSide: CGFloat = 320

    public init(
        messageID: String,
        roomID: String,
        mediaPath: String,
        thumbnailPath: String?,
        blurhash: String?,
        width: Int?,
        height: Int?,
        durationMS: Int?,
        isGIF: Bool,
        onPopOutPiP: @escaping () -> Void,
        onOpenLightbox: @escaping () -> Void,
        preloadedPoster: NSImage? = nil,
        initialIsPlaying: Bool? = nil,
        initialElapsedMS: Int = 0,
        initialSpeed: Speed = .one,
        initialIsMuted: Bool? = nil,
        initialShowsControls: Bool = false
    ) {
        self.messageID = messageID
        self.roomID = roomID
        self.mediaPath = mediaPath
        self.thumbnailPath = thumbnailPath
        self.blurhash = blurhash
        self.width = width
        self.height = height
        self.durationMS = durationMS
        self.isGIF = isGIF
        self.onPopOutPiP = onPopOutPiP
        self.onOpenLightbox = onOpenLightbox
        self.preloadedPoster = preloadedPoster

        let autoPlay = Self.shouldAutoplayMuted(isGIF: isGIF)
        let playing = initialIsPlaying ?? autoPlay
        let muted = initialIsMuted ?? autoPlay
        let totalMS = max(durationMS ?? 0, 0)
        _model = StateObject(
            wrappedValue: InlineVideoPlayerModel(
                isPlaying: playing,
                elapsedMS: initialElapsedMS,
                durationMS: totalMS,
                speed: initialSpeed,
                isMuted: muted,
                showsControls: initialShowsControls || (playing && !isGIF)
            )
        )
    }

    /// Resolves `path` to a local file URL only when it lives in the local filesystem (never a remote URL).
    public static func localMediaURL(for path: String) -> URL? {
        guard isLocalMediaStorePath(path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Muted autoplay is enabled only for GIF-style videos (`fi.mau.gif`); real videos never autoplay with sound.
    public static func shouldAutoplayMuted(isGIF: Bool) -> Bool {
        isGIF
    }

    /// User-visible labels and tooltips exposed by `InlineVideoPlayer`, checked by tests for plain words.
    public static var userVisibleStrings: [String] {
        [
            String(localized: "Play"),
            String(localized: "Pause"),
            String(localized: "Mute"),
            String(localized: "Unmute"),
            String(localized: "Playback Speed"),
            String(localized: "Picture in Picture"),
            String(localized: "Expand"),
            String(localized: "Video unavailable"),
            String(localized: "Not downloaded yet"),
        ]
    }

    public var frameSize: CGSize {
        EnhancedImageView.proportionalSize(
            width: width,
            height: height,
            longestSide: Self.longestSide,
            fallback: CGSize(width: 280, height: 180)
        )
    }

    private var decodedBlurHash: CGImage? {
        guard let hash = blurhash, !hash.isEmpty else { return nil }
        return BlurHashDecoder.decode(hash, width: 32, height: 32)
    }

    private var localPosterPath: String? {
        if let thumb = thumbnailPath, isLocalMediaStorePath(thumb) {
            return thumb
        }
        if isLocalMediaStorePath(mediaPath) {
            return mediaPath
        }
        return nil
    }

    private var effectiveDurationMS: Int {
        max(model.durationMS, durationMS ?? 0)
    }

    private var shouldShowTransportBar: Bool {
        if isGIF {
            return isHovering
        }
        return model.isPlaying || model.showsControls
    }

    public var body: some View {
        ZStack {
            if model.hasError && preloadedPoster == nil {
                ImageErrorCard(
                    fileName: (mediaPath as NSString).lastPathComponent,
                    size: frameSize,
                    title: String(localized: "Video unavailable"),
                    symbol: "video.slash"
                )
            } else {
                videoCanvas
                overlays
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .task(id: mediaPath) {
            model.configure(
                mediaPath: mediaPath,
                fallbackDurationMS: durationMS,
                isGIF: isGIF,
                autoStartGIF: preloadedPoster == nil
            )
            guard preloadedPoster == nil, let posterPath = localPosterPath else { return }
            if let thumbnail = await ThumbnailLoader.shared.thumbnail(atPath: posterPath) {
                loadedPosterCGImage = thumbnail.image
            }
        }
        .onDisappear {
            model.stopInlineOnDisappear()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isGIF ? String(localized: "Animated GIF video") : String(localized: "Video"))
    }

    @ViewBuilder
    private var videoCanvas: some View {
        ZStack {
            // Poster / BlurHash backdrop beneath the video surface
            if let preloadedPoster {
                Image(nsImage: preloadedPoster)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frameSize.width, height: frameSize.height)
            } else if let loadedPosterCGImage {
                Image(decorative: loadedPosterCGImage, scale: 2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frameSize.width, height: frameSize.height)
            } else if let blurCG = decodedBlurHash {
                Image(decorative: blurCG, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: frameSize.width, height: frameSize.height)
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: frameSize.width, height: frameSize.height)
            }

            if preloadedPoster == nil, let player = model.player, model.isPlaying || model.showsControls || isGIF {
                AVPlayerSurfaceView(player: player)
                    .frame(width: frameSize.width, height: frameSize.height)
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .clipped()
    }

    @ViewBuilder
    private var overlays: some View {
        ZStack {
            // Tap surface to toggle play/pause
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if isGIF {
                        onOpenLightbox()
                    } else {
                        model.togglePlayPause()
                    }
                }

            // Top badges (GIF pill, or Not downloaded yet notice)
            VStack {
                HStack(spacing: 6) {
                    if isGIF {
                        Text("GIF")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.68)))
                    }
                    Spacer(minLength: 0)
                    if !shouldShowTransportBar && isHovering && !isGIF {
                        topHoverButtons
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(6)

            // Center Play badge when paused and transport bar is not yet shown
            if !isGIF && !shouldShowTransportBar {
                if mediaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "video")
                        Text(String(localized: "Not downloaded yet"))
                            .font(.caption)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        model.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.65))
                                .frame(width: 44, height: 44)
                            Circle()
                                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                                .frame(width: 44, height: 44)
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Play"))
                    .accessibilityLabel(String(localized: "Play"))
                }

                // Bottom-trailing duration pill on the paused poster
                if let durationText = GalleryVideoPoster.formatDuration(effectiveDurationMS) {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            Text(durationText)
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.72)))
                        }
                    }
                    .padding(8)
                }
            }

            // Custom SwiftUI transport bar when playing or hovered
            if shouldShowTransportBar {
                VStack {
                    Spacer(minLength: 0)
                    transportBar
                }
            }
        }
    }

    private var topHoverButtons: some View {
        HStack(spacing: 4) {
            Button {
                popOutToPiP()
            } label: {
                Image(systemName: "pip.enter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Circle().fill(Color.black.opacity(0.65)))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Picture in Picture"))
            .accessibilityLabel(String(localized: "Picture in Picture"))

            Button {
                onOpenLightbox()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Circle().fill(Color.black.opacity(0.65)))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Expand"))
            .accessibilityLabel(String(localized: "Expand"))
        }
    }

    private var transportBar: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: {
                        let total = max(effectiveDurationMS, 1)
                        return min(max(Double(model.elapsedMS) / Double(total), 0), 1)
                    },
                    set: { fraction in
                        model.seek(toFraction: fraction)
                    }
                ),
                in: 0 ... 1
            )
            .controlSize(.mini)
            .tint(.white)
            .accessibilityLabel(String(localized: "Video playback position"))

            HStack(spacing: 8) {
                Button {
                    model.togglePlayPause()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(model.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
                .accessibilityLabel(model.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

                Text(Self.formatTimeRange(elapsedMS: model.elapsedMS, durationMS: effectiveDurationMS))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Menu {
                    ForEach(Speed.allCases, id: \.rawValue) { choice in
                        Button {
                            model.selectSpeed(choice)
                        } label: {
                            HStack {
                                Text(choice.label)
                                if choice == model.speed {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(model.speed.label)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(String(localized: "Playback Speed"))
                .accessibilityLabel(String(localized: "Playback Speed"))

                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(model.isMuted ? String(localized: "Unmute") : String(localized: "Mute"))
                .accessibilityLabel(model.isMuted ? String(localized: "Unmute") : String(localized: "Mute"))

                Button {
                    popOutToPiP()
                } label: {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Picture in Picture"))
                .accessibilityLabel(String(localized: "Picture in Picture"))

                Button {
                    onOpenLightbox()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Expand"))
                .accessibilityLabel(String(localized: "Expand"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func popOutToPiP() {
        model.pause()
        onPopOutPiP()
    }

    public static func formatTimeRange(elapsedMS: Int, durationMS: Int) -> String {
        let elapsedText = formatTimestamp(elapsedMS)
        let totalText = formatTimestamp(max(durationMS, elapsedMS))
        return "\(elapsedText) / \(totalText)"
    }

    public static func formatTimestamp(_ milliseconds: Int) -> String {
        let clamped = max(0, milliseconds)
        let totalSeconds = clamped / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
