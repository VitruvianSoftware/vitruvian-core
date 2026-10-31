// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
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
        nsView.isLocked = isLocked
        if isLocked {
            nsView.enforceLockOnWindow()
        }
    }
}

@MainActor
private final class LockEnforcerNSView: NSView {
    var isLocked = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isLocked {
            enforceLockOnWindow()
        }
    }

    func enforceLockOnWindow() {
        guard let window else { return }
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
