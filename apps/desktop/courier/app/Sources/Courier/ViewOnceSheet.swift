// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Applies `NSWindow.sharingType = .none` to the hosting window while `ViewOnceSheet` is visible,
/// restoring the previous sharing type when the view is dismantled.
private struct ScreenshotProtectionWindowAccessor: NSViewRepresentable {
    final class ProtectionView: NSView {
        private var previousSharingType: NSWindow.SharingType?
        private weak var trackedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let oldWindow = trackedWindow, oldWindow !== window, let prev = previousSharingType {
                oldWindow.sharingType = prev
                trackedWindow = nil
                previousSharingType = nil
            }
            if let newWindow = window {
                if trackedWindow !== newWindow {
                    previousSharingType = newWindow.sharingType
                    trackedWindow = newWindow
                }
                _ = ViewOnceSheet.applyScreenshotProtection(to: newWindow)
            }
        }

        func restore() {
            if let trackedWindow, let prev = previousSharingType {
                trackedWindow.sharingType = prev
            }
            trackedWindow = nil
            previousSharingType = nil
        }
    }

    func makeNSView(context _: Context) -> ProtectionView {
        ProtectionView(frame: .zero)
    }

    func updateNSView(_ nsView: ProtectionView, context _: Context) {
        if let window = nsView.window {
            _ = ViewOnceSheet.applyScreenshotProtection(to: window)
        }
    }

    static func dismantleNSView(_ nsView: ProtectionView, coordinator _: ()) {
        nsView.restore()
    }
}

/// Modal viewer for view-once media (`ViewLimitedMediaViewer.tsx`).
///
/// - Loads directly from `message.mediaPath` into memory (`options: .uncached`), never writing to
///   `OpenFileCache` or any secondary cache directory.
/// - Blocks window screenshots where macOS allows (`NSWindow.sharingType = .none`) and states honestly
///   when system-level or external capture cannot be prevented.
/// - Exposes no Save, Copy, Share, Export, or Quick Look controls.
/// - Marks the message played (`message.markPlayed`) as soon as the viewer is dismissed so it can
///   only be opened once on this Mac.
public struct ViewOnceSheet: View {
    public let message: TimelineMessage
    public var preloadedImage: NSImage?
    public let onMarkPlayed: () -> Void
    public let onDismiss: () -> Void

    @State private var inMemoryImage: NSImage?
    @State private var loadError = false
    @State private var didMarkPlayed = false

    public init(
        message: TimelineMessage,
        preloadedImage: NSImage? = nil,
        onMarkPlayed: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.preloadedImage = preloadedImage
        self.onMarkPlayed = onMarkPlayed
        self.onDismiss = onDismiss
    }

    /// Sets `window.sharingType = .none` to block macOS window capture where supported.
    @discardableResult
    public static func applyScreenshotProtection(to window: NSWindow) -> Bool {
        window.sharingType = .none
        return window.sharingType == .none
    }

    public static var screenshotNoticeText: String {
        String(
            localized: "Screenshots and screen recordings of this window are blocked where macOS allows it. A camera pointed at the screen can\u{2019}t be stopped."
        )
    }

    public var body: some View {
        VStack(spacing: 12) {
            headerBar

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.86))

                if message.played {
                    expiredStateView
                } else if let image = preloadedImage ?? inMemoryImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else if loadError || message.mediaPath.isEmpty {
                    ImageErrorCard(
                        fileName: message.fileName,
                        size: CGSize(width: 280, height: 180)
                    )
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                }
            }
            .frame(minWidth: 320, minHeight: 200, maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if !message.body.isEmpty && !message.played {
                Text(message.body)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            honestProtectionBanner
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .background(ScreenshotProtectionWindowAccessor())
        .task(id: message.id) {
            guard !message.played, preloadedImage == nil else { return }
            loadInMemoryOnly()
        }
        .onDisappear {
            markPlayedIfNeeded()
        }
        .accessibilityElement(children: .contain)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: message.played ? "1.circle" : "1.circle.fill")
                .foregroundStyle(message.played ? Color.secondary : Color.accentColor)
            Text(
                message.played
                    ? String(localized: "View-once media (Opened)")
                    : String(localized: "View-once from \(message.senderName.isEmpty ? message.sender : message.senderName)")
            )
            .font(.headline)
            .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                markPlayedIfNeeded()
                onDismiss()
            } label: {
                Text(String(localized: "Close"))
                    .font(.callout.weight(.medium))
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private var expiredStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Text(String(localized: "Opened"))
                .font(.headline)
                .foregroundStyle(.white)
            Text(String(localized: "This view-once media was already opened and is gone on this Mac."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(16)
    }

    private var honestProtectionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(Self.screenshotNoticeText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.45)))
    }

    private func loadInMemoryOnly() {
        guard isLocalMediaStorePath(message.mediaPath) else {
            loadError = true
            return
        }
        let fileURL = URL(fileURLWithPath: message.mediaPath)
        guard let data = try? Data(contentsOf: fileURL, options: [.uncached]),
              let decoded = NSImage(data: data)
        else {
            loadError = true
            return
        }
        inMemoryImage = decoded
    }

    private func markPlayedIfNeeded() {
        guard !didMarkPlayed, !message.played else { return }
        didMarkPlayed = true
        onMarkPlayed()
    }
}
