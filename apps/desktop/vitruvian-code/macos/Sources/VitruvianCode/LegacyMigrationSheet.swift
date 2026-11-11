// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import SwiftUI
import VitruvianCodeCore

/// What the first launch of Vitruvian Code tells someone who used Nexus Agent:
/// macOS asks for its privacy permissions again, and why; and, if a step of
/// moving their things over did not work, which one, and that it will be tried
/// again at the next launch. Shown once, in the style of the Settings window.
struct LegacyMigrationSheet: View {
    let outcome: VitruvianCodeLegacyMigration.Outcome
    let onDone: () -> Void

    private var showsPermissions: Bool { !outcome.permissions.isEmpty && !outcome.permissionsExplained }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nexus Agent is now Vitruvian Code")
                .font(.title3.weight(.semibold))

            if outcome.failures.isEmpty {
                Text(outcome.deferrals.isEmpty
                     ? "Your settings, history, Telegram bot and scheduled automations came with you."
                     : "Your settings, history and Telegram bot came with you.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !outcome.failures.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Some things did not move yet", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text("Vitruvian Code will try again the next time it starts. Nothing was deleted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(Array(outcome.failures.enumerated()), id: \.offset) { _, failure in
                        Text(failure.line)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !outcome.deferrals.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("One step is waiting for you", systemImage: "folder.badge.gearshape")
                        .font(.headline)
                    ForEach(Array(outcome.deferrals.enumerated()), id: \.offset) { _, text in
                        Text(text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if showsPermissions {
                Divider()
                Text("macOS asks for permissions again")
                    .font(.headline)
                Text("macOS ties each permission to one app, so it does not carry them over to a renamed one. Give Vitruvian Code the ones you used before; each button opens the right page in System Settings.")
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(outcome.permissions, id: \.rawValue) { permission in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.title).fontWeight(.medium)
                            Text(permission.reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button("Open \(permission.title)…") {
                            if let url = URL(string: permission.settingsURL) { NSWorkspace.shared.open(url) }
                        }
                        .controlSize(.small)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// The notice's window, a frosted panel like Settings'. Held here so it is
/// not freed while it is on screen.
private var _legacyMigrationWindow: NSWindow?

@MainActor
func openLegacyMigrationWindow(outcome: VitruvianCodeLegacyMigration.Outcome, onDone: @escaping () -> Void) {
    if let existing = _legacyMigrationWindow, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        return
    }
    let hostingView = NSHostingView(rootView: LegacyMigrationSheet(outcome: outcome, onDone: {
        _legacyMigrationWindow?.close()
    }))
    hostingView.autoresizingMask = [.width, .height]
    let size = hostingView.fittingSize

    let window = KeyablePanel(
        contentRect: NSRect(x: 0, y: 0, width: max(size.width, 440), height: max(size.height, 200)),
        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    window.title = "Welcome to Vitruvian Code"
    window.titlebarAppearsTransparent = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.isFloatingPanel = true
    window.becomesKeyOnlyIfNeeded = false

    let visualEffect = NSVisualEffectView()
    visualEffect.material = .hudWindow
    visualEffect.blendingMode = .behindWindow
    visualEffect.state = .active
    visualEffect.autoresizingMask = [.width, .height]
    hostingView.frame = visualEffect.bounds
    visualEffect.addSubview(hostingView)
    window.contentView = visualEffect

    // Done and the close button end the same way: the person has seen it.
    var observer: NSObjectProtocol?
    observer = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { _ in
        if let observer { NotificationCenter.default.removeObserver(observer) }
        MainActor.assumeIsolated {
            _legacyMigrationWindow = nil
            onDone()
        }
    }

    window.center()
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    _legacyMigrationWindow = window
}
