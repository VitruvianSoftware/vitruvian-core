// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import AVFoundation
import AVKit
import CourierCore
import SwiftUI

/// Item displayed in Courier's floating Picture-in-Picture window (`PictureInPictureBrowserWindow.tsx`).
public struct PiPVideoItem: Equatable, Identifiable, Sendable {
    public let messageID: String
    public let roomID: String
    public let mediaPath: String
    public let thumbnailPath: String?
    public let blurhash: String?
    public let title: String
    public let width: Int?
    public let height: Int?
    public let durationMS: Int?
    public var elapsedMS: Int
    public var isPlaying: Bool
    public var playbackRate: Float
    public var isMuted: Bool

    public var id: String { messageID }

    public init(
        messageID: String,
        roomID: String,
        mediaPath: String,
        thumbnailPath: String? = nil,
        blurhash: String? = nil,
        title: String = "",
        width: Int? = nil,
        height: Int? = nil,
        durationMS: Int? = nil,
        elapsedMS: Int = 0,
        isPlaying: Bool = true,
        playbackRate: Float = 1.0,
        isMuted: Bool = false
    ) {
        self.messageID = messageID
        self.roomID = roomID
        self.mediaPath = mediaPath
        self.thumbnailPath = thumbnailPath
        self.blurhash = blurhash
        self.title = title
        self.width = width
        self.height = height
        self.durationMS = durationMS
        self.elapsedMS = elapsedMS
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.isMuted = isMuted
    }
}

/// Hosts an always-on-top floating `NSPanel` (`level = .floating`, `collectionBehavior = [.canJoinAllSpaces,
/// .fullScreenAuxiliary]`) with play/pause, scrub bar, Return to Chat button, and Close button so a video keeps
/// playing while switching or closing chats, and stops when Courier quits.
@MainActor
public final class PictureInPictureController: ObservableObject, PictureInPictureControlling {
    public static let shared = PictureInPictureController()

    @Published public private(set) var activeItem: PiPVideoItem?
    public private(set) var panel: NSPanel?
    public private(set) var player: AVPlayer?

    public var isPresentingPiP: Bool { activeItem != nil }

    public func pauseAndCloseForAppLock() {
        close()
    }

    /// Invoked when the person clicks Return to Chat (`roomID, messageID`).
    public var onReturnToChat: (@MainActor (_ roomID: String, _ messageID: String) -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?

    public init() {
        AppLockGate.shared.registerPiPController(self)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopForApplicationTermination()
            }
        }
        lockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didLockNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pauseAndCloseForAppLock()
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        if let lockObserver {
            NotificationCenter.default.removeObserver(lockObserver)
        }
    }

    /// Opens or updates the floating Picture-in-Picture window for `item`.
    /// Refuses non-local URLs so Picture-in-Picture only ever plays from the local media store.
    public func show(_ item: PiPVideoItem) {
        guard AppLockGate.shared.canPerform(.other) else { return }
        guard let localURL = InlineVideoPlayer.localMediaURL(for: item.mediaPath) else {
            return
        }
        tearDownPlayer()
        activeItem = item

        if FileManager.default.fileExists(atPath: localURL.path) {
            let avPlayer = AVPlayer(url: localURL)
            avPlayer.isMuted = item.isMuted
            player = avPlayer

            if item.elapsedMS > 0 {
                let target = CMTime(seconds: Double(item.elapsedMS) / 1000.0, preferredTimescale: 600)
                avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            }

            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                let seconds = CMTimeGetSeconds(time)
                guard seconds.isFinite, seconds >= 0 else { return }
                let ms = Int((seconds * 1000).rounded())
                Task { @MainActor [weak self] in
                    guard let self, var current = self.activeItem else { return }
                    current.elapsedMS = ms
                    self.activeItem = current
                }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: avPlayer.currentItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, var current = self.activeItem else { return }
                    current.isPlaying = false
                    current.elapsedMS = 0
                    self.activeItem = current
                    self.player?.seek(to: .zero)
                }
            }

            if item.isPlaying {
                avPlayer.playImmediately(atRate: item.playbackRate)
            }
        }

        let targetPanel = ensurePanel()
        targetPanel.contentView = NSHostingView(rootView: PictureInPictureControllerRootView(controller: self))
        if NSClassFromString("XCTestCase") == nil {
            targetPanel.orderFrontRegardless()
        }
    }

    public func togglePlayPause() {
        guard AppLockGate.shared.canPerform(.other) else {
            pauseAndCloseForAppLock()
            return
        }
        guard var current = activeItem else { return }
        current.isPlaying.toggle()
        activeItem = current
        if current.isPlaying {
            player?.playImmediately(atRate: current.playbackRate)
        } else {
            player?.pause()
        }
    }

    public func seek(toFraction fraction: Double) {
        guard AppLockGate.shared.canPerform(.other) else {
            pauseAndCloseForAppLock()
            return
        }
        guard var current = activeItem else { return }
        let clamped = min(max(fraction, 0), 1)
        let total = max(current.durationMS ?? 0, 1)
        let targetMS = Int((Double(total) * clamped).rounded())
        current.elapsedMS = targetMS
        activeItem = current
        let target = CMTime(seconds: Double(targetMS) / 1000.0, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func returnToChat() {
        guard AppLockGate.shared.canPerform(.openChat), let current = activeItem else { return }
        onReturnToChat?(current.roomID, current.messageID)
    }

    /// Closing or switching away from a chat intentionally leaves Picture-in-Picture playing.
    public func handleChatClosed(roomID _: String) {
        // Intentional no-op: closing the chat must not kill a PiP video the person is watching.
    }

    /// Stops playback and closes the floating window when Courier quits.
    public func stopForApplicationTermination() {
        close()
    }

    public func close() {
        tearDownPlayer()
        activeItem = nil
        panel?.orderOut(nil)
        panel?.close()
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }
        let created = NSPanel(
            contentRect: NSRect(x: 80, y: 80, width: 340, height: 230),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.level = .floating
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.isReleasedWhenClosed = false
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.isMovableByWindowBackground = true
        created.minSize = NSSize(width: 280, height: 190)
        panel = created
        return created
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
    }
}

private struct PictureInPictureControllerRootView: View {
    @ObservedObject var controller: PictureInPictureController

    var body: some View {
        if let item = controller.activeItem {
            PictureInPictureView(
                item: item,
                player: controller.player,
                onTogglePlayPause: { controller.togglePlayPause() },
                onSeek: { controller.seek(toFraction: $0) },
                onReturnToChat: { controller.returnToChat() },
                onClose: { controller.close() }
            )
        }
    }
}

/// Content view of the floating Picture-in-Picture panel (`PictureInPictureBrowserWindow.tsx`).
public struct PictureInPictureView: View {
    public let item: PiPVideoItem
    public var player: AVPlayer?
    public var preloadedPoster: NSImage?
    public let onTogglePlayPause: () -> Void
    public let onSeek: (Double) -> Void
    public let onReturnToChat: () -> Void
    public let onClose: () -> Void

    @State private var loadedPosterCGImage: CGImage?

    public init(
        item: PiPVideoItem,
        player: AVPlayer? = nil,
        preloadedPoster: NSImage? = nil,
        onTogglePlayPause: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void,
        onReturnToChat: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.item = item
        self.player = player
        self.preloadedPoster = preloadedPoster
        self.onTogglePlayPause = onTogglePlayPause
        self.onSeek = onSeek
        self.onReturnToChat = onReturnToChat
        self.onClose = onClose
    }

    /// User-visible strings rendered by `PictureInPictureView`, checked by tests for plain words.
    public static var userVisibleStrings: [String] {
        [
            String(localized: "Return to Chat"),
            String(localized: "Close"),
            String(localized: "Play"),
            String(localized: "Pause"),
            String(localized: "Video"),
        ]
    }

    private var decodedBlurHash: CGImage? {
        guard let hash = item.blurhash, !hash.isEmpty else { return nil }
        return BlurHashDecoder.decode(hash, width: 32, height: 32)
    }

    private var localPosterPath: String? {
        if let thumb = item.thumbnailPath, isLocalMediaStorePath(thumb) {
            return thumb
        }
        if isLocalMediaStorePath(item.mediaPath) {
            return item.mediaPath
        }
        return nil
    }

    private var totalDurationMS: Int {
        max(item.durationMS ?? 0, item.elapsedMS)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            ZStack {
                if let preloadedPoster {
                    Image(nsImage: preloadedPoster)
                        .resizable()
                        .scaledToFill()
                } else if let loadedPosterCGImage {
                    Image(decorative: loadedPosterCGImage, scale: 2)
                        .resizable()
                        .scaledToFill()
                } else if let blurCG = decodedBlurHash {
                    Image(decorative: blurCG, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.88))
                }

                if preloadedPoster == nil, let player {
                    AVPlayerSurfaceView(player: player)
                }
            }
            .frame(height: 168)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTogglePlayPause)

            controlsBar
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        .task(id: localPosterPath) {
            guard preloadedPoster == nil, let path = localPosterPath else { return }
            if let thumbnail = await ThumbnailLoader.shared.thumbnail(atPath: path) {
                loadedPosterCGImage = thumbnail.image
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Picture in Picture video"))
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "pip")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(item.title.isEmpty ? String(localized: "Video") : item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            Button(action: onReturnToChat) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption2.weight(.semibold))
                    Text(String(localized: "Return to Chat"))
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Return to Chat"))
            .accessibilityLabel(String(localized: "Return to Chat"))

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Close"))
            .accessibilityLabel(String(localized: "Close"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var controlsBar: some View {
        HStack(spacing: 8) {
            Button(action: onTogglePlayPause) {
                Image(systemName: item.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(item.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
            .accessibilityLabel(item.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

            Slider(
                value: Binding(
                    get: {
                        let total = max(totalDurationMS, 1)
                        return min(max(Double(item.elapsedMS) / Double(total), 0), 1)
                    },
                    set: { fraction in
                        onSeek(fraction)
                    }
                ),
                in: 0 ... 1
            )
            .controlSize(.mini)
            .accessibilityLabel(String(localized: "Video playback position"))

            Text(InlineVideoPlayer.formatTimeRange(elapsedMS: item.elapsedMS, durationMS: totalDurationMS))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
