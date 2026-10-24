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
//
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).

import AppKit
import NexusAgentCore
import SwiftUI
import UniformTypeIdentifiers

/// What the list over the composer offers while a `/` command or an `@`
/// mention is being typed.
enum ComposerSuggestions: Equatable {
    case none
    case commands([NexusAgentSlashCommand])
    case files([String])

    var count: Int {
        switch self {
        case .none: return 0
        case .commands(let commands): return commands.count
        case .files(let files): return files.count
        }
    }

    var isEmpty: Bool { count == 0 }

    /// The `/` list comes first: a draft that is a lone `/word` has no `@`.
    @MainActor
    static func of(_ session: NexusAgentQuickPromptSession) -> ComposerSuggestions {
        let commands = session.matchingSlashCommands
        if !commands.isEmpty { return .commands(commands) }
        let files = session.matchingWorkspaceFiles
        if !files.isEmpty { return .files(files) }
        return .none
    }

    /// The selection after an arrow key, wrapping at either end.
    static func move(_ selection: Int, by step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((selection + step) % count + count) % count
    }
}

/// The compact list over the composer: the `/` commands that match, or the
/// working folder's files that match an `@`. The arrow keys move the
/// highlight; a click, Tab or Return takes the highlighted row.
struct ComposerSuggestionList: View {
    let suggestions: ComposerSuggestions
    let selection: Int
    let strings: NexusAgentChatStrings
    let choose: (Int) -> Void

    static let rowHeight: CGFloat = 25
    static let maxRowsHeight: CGFloat = 188

    /// Height for `count` suggestion rows: grows with the list up to
    /// `maxRowsHeight` so a `ScrollView` never collapses to a single row.
    static func rowsHeight(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return min(CGFloat(count) * rowHeight + 6, maxRowsHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(heading)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(strings.completeKey)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.15),
                                                                                 lineWidth: 0.5))
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        rows
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
                .frame(height: Self.rowsHeight(for: suggestions.count))
                .onChange(of: selection) { _, row in proxy.scrollTo(row) }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private var heading: String {
        if case .files = suggestions { return strings.filesHeading }
        return strings.slashCommandsHeading
    }

    @ViewBuilder
    private var rows: some View {
        switch suggestions {
        case .none:
            EmptyView()
        case .commands(let commands):
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                row(index) {
                    Image(systemName: command.isBuiltIn ? "sparkles" : "terminal")
                        .font(.system(size: 9))
                        .foregroundStyle(NexusAgentTheme.warmCoral.opacity(0.85))
                        .frame(width: 14)
                    Text("/" + command.name)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    if let hint = command.argumentHint {
                        Text(hint)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if !command.description.isEmpty {
                        Text(command.description)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        case .files(let files):
            ForEach(Array(files.enumerated()), id: \.element) { index, file in
                row(index) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text((file as NSString).lastPathComponent)
                        .font(.system(size: 11.5, weight: .medium))
                    Text((file as NSString).deletingLastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
    }

    private func row<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        Button {
            choose(index)
        } label: {
            HStack(spacing: 6) {
                content()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(index == selection ? NexusAgentTheme.warmCoral.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
    }
}

/// The files attached to the next turn, as chips that can be taken off.
struct AttachmentChipsRow: View {
    let attachments: [NexusAgentAttachment]
    let strings: NexusAgentChatStrings
    let remove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 4) {
                        Group {
                            if attachment.isImage {
                                Image(systemName: "photo")
                            } else {
                                Image(systemName: "doc.text")
                            }
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(NexusAgentTheme.warmCoral)
                        Text(attachment.displayName)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 160)
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { remove(attachment.id) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(strings.removeAttachment)
                        .accessibilityLabel(strings.removeAttachment + " " + attachment.displayName)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .help(attachment.url.path)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

/// A prompt waiting for the running turn, over the follow-up bar: the
/// pencil puts it back in the composer, the cross drops it.
struct QueuedPromptBanner: View {
    let text: String
    let strings: NexusAgentChatStrings
    let edit: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NexusAgentTheme.warmCoral)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(strings.queuedLabel)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(NexusAgentTheme.warmCoral)
                    Text(strings.queuedHint)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Button(action: edit) {
                Image(systemName: "pencil").font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(strings.editQueued)
            .accessibilityLabel(strings.editQueued)
            Button(action: cancel) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(strings.cancelQueued)
            .accessibilityLabel(strings.cancelQueued)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NexusAgentTheme.warmCoral.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NexusAgentTheme.warmCoral.opacity(0.25), lineWidth: 0.5))
        )
        .padding(.horizontal, 12)
    }
}

/// The attach button beside the composer: a menu with the file picker and
/// the clipboard. A small count says how many are attached.
struct AttachMenuButton: View {
    @ObservedObject var session: NexusAgentQuickPromptSession
    let strings: NexusAgentChatStrings
    /// Brings the chat back once the file panel closes.
    let showWindow: () -> Void
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button {
                chooseFiles()
            } label: {
                Label(strings.chooseFile, systemImage: "doc.badge.plus")
            }
            Button {
                session.pasteFromClipboard()
            } label: {
                Label(strings.pasteFromClipboard, systemImage: "doc.on.clipboard")
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(session.attachments.isEmpty
                    ? Color.primary.opacity(isHovered ? 0.7 : 0.45)
                    : NexusAgentTheme.warmCoral)
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .overlay(alignment: .topTrailing) {
            if !session.attachments.isEmpty {
                Text("\(session.attachments.count)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 12, minHeight: 12)
                    .background(Circle().fill(NexusAgentTheme.warmCoral))
                    .offset(x: 4, y: -4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .help(session.attachments.isEmpty
            ? strings.attach
            : strings.attach + ": " + session.attachments.map(\.displayName).joined(separator: ", "))
        .accessibilityLabel(strings.attach)
        .onHover { isHovered = $0 }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            for url in panel.urls { session.addAttachment(url: url) }
        }
        showWindow()
    }
}

/// ⌘V in the composer with an image on the clipboard and no text attaches
/// the image; with text it is the field's paste, untouched. It watches the
/// keys of its own window only, and only while `isActive` (a prompt field
/// has the caret).
struct ComposerPasteMonitor: NSViewRepresentable {
    let isActive: () -> Bool
    let pasteImage: () -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.isActive = isActive
        view.pasteImage = pasteImage
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.isActive = isActive
        nsView.pasteImage = pasteImage
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
        nsView.stop()
    }

    final class MonitorView: NSView {
        var isActive: (() -> Bool)?
        var pasteImage: (() -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "v",
                      self.isActive?() == true,
                      NexusAgentQuickPromptSession.pasteboardHasImageOnly(.general),
                      self.pasteImage?() == true else { return event }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        // No deinit: leaving the window (viewDidMoveToWindow) and
        // dismantleNSView already remove the monitor, and a deinit may not
        // call this main-actor method on the mirror's toolchain.
    }
}

/// What is dropped on the chat: files are attached as they are; an image
/// with no file behind it (dragged out of a browser, say) is written out
/// first. True when anything was taken.
@MainActor
func attachDroppedItems(_ providers: [NSItemProvider], to session: NexusAgentQuickPromptSession) -> Bool {
    var taken = false
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            taken = true
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in session.addAttachment(url: url) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            taken = true
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in session.attachImage(data: data) }
            }
        }
    }
    return taken
}
