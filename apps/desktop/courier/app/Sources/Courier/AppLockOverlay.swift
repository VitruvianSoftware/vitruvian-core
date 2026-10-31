// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import CourierCore
import SwiftUI

/// Wraps any window's root content so locking `SystemLifecycleModel` reactively:
/// 1. Disables all underlying controls and shortcuts in that window (`.disabled(lifecycle.isLocked)`).
/// 2. Ends any AppKit-level sheets attached to the hosting `NSWindow` and resigns `firstResponder`.
/// 3. Covers the window with `AppLockOverlay` so nothing behind it is visible or interactive.
public struct LockableWindowContent<Content: View>: View {
    @ObservedObject var lifecycle: SystemLifecycleModel
    private let content: Content

    public init(lifecycle: SystemLifecycleModel, @ViewBuilder content: () -> Content) {
        self.lifecycle = lifecycle
        self.content = content()
    }

    public var body: some View {
        content
            .disabled(lifecycle.isLocked)
            .background(WindowLockEnforcer(isLocked: lifecycle.isLocked))
            .overlay {
                if lifecycle.isLocked {
                    AppLockOverlay(model: lifecycle)
                        .disabled(false)
                }
            }
    }
}

private struct WindowLockEnforcer: NSViewRepresentable {
    let isLocked: Bool

    func makeNSView(context _: Context) -> LockEnforcerNSView {
        let view = LockEnforcerNSView()
        view.isLocked = isLocked
        return view
    }

    func updateNSView(_ nsView: LockEnforcerNSView, context _: Context) {
        let wasLocked = nsView.isLocked
        nsView.isLocked = isLocked
        if isLocked {
            nsView.enforceLockOnWindow()
        } else if wasLocked {
            nsView.restoreUnlockedWindowTitle()
        }
    }
}

@MainActor
private final class LockEnforcerNSView: NSView {
    var isLocked = false
    private var savedTitle: String?
    private var savedSubtitle: String?
    private var isUpdatingWindowTitle = false
    private var lockObserver: Any?
    private var unlockObserver: Any?
    private var titleCancellable: AnyCancellable?
    private var subtitleCancellable: AnyCancellable?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installLockObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installLockObservers()
    }

    deinit {
        if let lockObserver {
            NotificationCenter.default.removeObserver(lockObserver)
        }
        if let unlockObserver {
            NotificationCenter.default.removeObserver(unlockObserver)
        }
    }

    private func installLockObservers() {
        lockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didLockNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isLocked = true
                self.enforceLockOnWindow()
            }
        }
        unlockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didUnlockNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isLocked = false
                self.restoreUnlockedWindowTitle()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        titleCancellable = nil
        subtitleCancellable = nil
        guard let window else { return }
        let lockedTitle = String(localized: "Courier")
        if window.title != lockedTitle, !window.title.isEmpty {
            savedTitle = window.title
        }
        if !window.subtitle.isEmpty {
            savedSubtitle = window.subtitle
        }
        titleCancellable = window.publisher(for: \.title).sink { [weak self, weak window] newTitle in
            guard let self, let window, !self.isUpdatingWindowTitle else { return }
            if newTitle != lockedTitle, !newTitle.isEmpty {
                self.savedTitle = newTitle
            }
            if self.isLocked, window.title != lockedTitle {
                self.isUpdatingWindowTitle = true
                window.title = lockedTitle
                self.isUpdatingWindowTitle = false
            }
        }
        subtitleCancellable = window.publisher(for: \.subtitle).sink { [weak self, weak window] newSubtitle in
            guard let self, let window, !self.isUpdatingWindowTitle else { return }
            if !newSubtitle.isEmpty {
                self.savedSubtitle = newSubtitle
            }
            if self.isLocked, !window.subtitle.isEmpty {
                self.isUpdatingWindowTitle = true
                window.subtitle = ""
                self.isUpdatingWindowTitle = false
            }
        }
        if isLocked {
            enforceLockOnWindow()
        }
    }

    func enforceLockOnWindow() {
        guard let window else { return }
        let lockedTitle = String(localized: "Courier")
        if window.title != lockedTitle, !window.title.isEmpty {
            savedTitle = window.title
        }
        if !window.subtitle.isEmpty {
            savedSubtitle = window.subtitle
        }
        isUpdatingWindowTitle = true
        window.title = lockedTitle
        window.subtitle = ""
        isUpdatingWindowTitle = false
        for sheet in window.sheets {
            window.endSheet(sheet, returnCode: .cancel)
        }
        if let attached = window.attachedSheet {
            window.endSheet(attached, returnCode: .cancel)
        }
        if let responder = window.firstResponder, responder !== window {
            window.makeFirstResponder(nil)
        }
    }

    func restoreUnlockedWindowTitle() {
        guard let window else { return }
        isUpdatingWindowTitle = true
        if let savedTitle, !savedTitle.isEmpty {
            window.title = savedTitle
        }
        if let savedSubtitle {
            window.subtitle = savedSubtitle
        }
        isUpdatingWindowTitle = false
    }
}

/// Full-window opaque lock screen shown whenever `SystemLifecycleModel.isLocked == true`.
/// Blocks all message content, chat list, and composer controls until Touch ID or device passcode succeeds.
public struct AppLockOverlay: View {
    @ObservedObject var model: SystemLifecycleModel

    public init(model: SystemLifecycleModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 6) {
                    Text("Courier is Locked")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Unlock with Touch ID or your password to view your messages.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                Button {
                    Task { await model.unlockWithTouchID() }
                } label: {
                    Label("Unlock with Touch ID…", systemImage: "touchid")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                if let errorMessage = model.lastErrorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                        .padding(.top, 4)
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Courier is Locked"))
    }
}
