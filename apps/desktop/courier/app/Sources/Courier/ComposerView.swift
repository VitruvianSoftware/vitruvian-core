// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Picks files for the composer. ⌘O and the paperclip both come here.
@MainActor
enum AttachmentPicker {
    static func run(into composer: ComposerModel) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose files to send")
        panel.prompt = String(localized: "Attach")
        guard panel.runModal() == .OK else { return }
        composer.attach(panel.urls)
    }
}

/// The bottom of a chat: what is being replied to, files waiting to go, and the box.
struct ComposerView: View {
    @ObservedObject var composer: ComposerModel
    @Binding var textHeight: CGFloat
    /// Esc's first use outside the composer (leaving selection mode); true when it was used.
    var escapeFirst: () -> Bool = { false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(composer.notices.enumerated()), id: \.offset) { _, notice in
                NoticeBar(text: noticeText(notice)) { composer.dismissNotice() }
            }
            if let reply = composer.replyTarget {
                ReplyChip(quote: reply) { composer.cancelReply() }
            }
            if !composer.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(composer.attachments) { attachment in
                            PendingAttachmentChip(attachment: attachment) {
                                composer.removeAttachment(attachment.id)
                            }
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    AttachmentPicker.run(into: composer)
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Attach files (⌘O)"))
                .accessibilityLabel(String(localized: "Attach files"))

                ComposerTextView(
                    text: $composer.text,
                    height: $textHeight,
                    placeholder: String(localized: "Type a message…"),
                    focusToken: "\(composer.roomID ?? "")|\(composer.replyTarget?.eventID ?? "")",
                    onReturn: { composer.handleReturn(modifiers: $0) },
                    onEscape: { escapeFirst() || composer.escape() },
                    onPasteFiles: { urls in
                        composer.attach(urls)
                        return true
                    })
                    .frame(height: textHeight)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))

                Button {
                    // The system's own picker, as ⌃⌘Space opens it.
                    NSApp.orderFrontCharacterPalette(nil)
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.title3)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Emoji & Symbols (⌃⌘Space)"))
                .accessibilityLabel(String(localized: "Emoji and symbols"))

                Button {
                    composer.submit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(composer.canSend ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!composer.canSend)
                .help(String(localized: "Send (Return)"))
                .accessibilityLabel(String(localized: "Send"))
            }
        }
        .padding(10)
        .background(.bar)
    }

    private func noticeText(_ notice: ComposerNotice) -> String {
        switch notice {
        case let .attachmentTooLarge(name):
            String(localized: "Could not attach \(name) — total size would exceed 90 MB.")
        case let .attachmentsLeftOut(names):
            names.count == 1
                ? String(localized: "Could not put \(names[0]) back — total size would exceed 90 MB.")
                : String(localized: "Could not put \(names.count) files back — total size would exceed 90 MB: \(names.joined(separator: ", "))")
        case let .notAFile(name):
            String(localized: "Could not attach \(name). Courier can send files, not folders.")
        case let .cannotRead(name):
            String(localized: "Could not read \(name). It may have moved, or Courier may not be allowed to open it.")
        case .noAnswer:
            StatusLine.mayHaveBeenSentText
        case let .sendFailed(reason):
            reason.isEmpty ? String(localized: "The message could not be sent.")
                : String(localized: "The message could not be sent: \(reason)")
        case .textTooLong:
            String(localized: "This message is too long for this chat. Shorten it, or send it in parts.")
        }
    }
}

private struct NoticeBar: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(String(localized: "Dismiss"))
            .accessibilityLabel(String(localized: "Dismiss"))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// The message being replied to, above the box. Esc or the button clears it.
private struct ReplyChip: View {
    let quote: QuotedMessage
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.accentColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.mine ? String(localized: "Replying to yourself")
                    : String(localized: "Replying to \(quote.senderName)"))
                    .font(.caption.weight(.semibold))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Clear quoted message (Esc)"))
            .accessibilityLabel(String(localized: "Clear quoted message"))
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var summary: String {
        if !quote.text.isEmpty { return quote.text }
        switch quote.kind {
        case .image: return String(localized: "Image")
        case .video: return String(localized: "Video")
        case .voiceNote: return String(localized: "Voice note")
        case .file: return String(localized: "File")
        case .sticker: return String(localized: "Sticker")
        default: return ""
        }
    }
}

// MARK: - The text box

/// A plain-text box: no styles, no pictures. Return sends; Shift, Option or Control with it adds a line. It grows
/// with its text up to a limit, and scrolls past that.
struct ComposerTextView: NSViewRepresentable {
    static let minimumHeight: CGFloat = 34
    private static let maximumHeight: CGFloat = 180

    @Binding var text: String
    @Binding var height: CGFloat
    let placeholder: String
    /// Changes whenever the box should take the keyboard: another chat, or a reply started.
    let focusToken: String
    let onReturn: (KeyModifiers) -> ReturnKeyAction
    let onEscape: () -> Bool
    let onPasteFiles: ([URL]) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = PlainTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        // ⌘F belongs to search (InboxCommands, MainWindow), so the box has no Find bar or panel of its own.
        textView.usesFindBar = false
        textView.usesFindPanel = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 6, height: 7)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.placeholder = placeholder
        textView.onPasteFiles = { context.coordinator.parent.onPasteFiles($0) }
        textView.setAccessibilityLabel(placeholder)
        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        // Only when it differs: setting the string moves the caret.
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
            textView.undoManager?.removeAllActions()
        }
        textView.placeholder = placeholder
        context.coordinator.updateHeight()
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: PlainTextView?
        var lastFocusToken: String?

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            if parent.text != textView.string { parent.text = textView.string }
            updateHeight()
        }

        func updateHeight() {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            let content = layout.usedRect(for: container).height + textView.textContainerInset.height * 2
            let wanted = min(ComposerTextView.maximumHeight, max(ComposerTextView.minimumHeight, content.rounded(.up)))
            if abs(parent.height - wanted) > 0.5 {
                let binding = parent.$height
                DispatchQueue.main.async { binding.wrappedValue = wanted }
            }
        }

        // Part 4.3's formatting keys go here. A link must not take ⌘K, and nothing may take ⌘F: those keys open
        // search, from the Courier and Chat menus (InboxCommands) and MainWindow's ⌘F.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertLineBreak(_:)):
                // While a character is still being composed, Return belongs to the input method.
                guard !textView.hasMarkedText() else { return false }
                // The key's modifiers decide: Return sends, with Shift, Option or Control it adds a line. The
                // system maps some of those to the other two commands itself, which are always a line.
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                var modifiers: KeyModifiers = []
                if flags.contains(.shift) { modifiers.insert(.shift) }
                if flags.contains(.option) { modifiers.insert(.option) }
                if flags.contains(.control) { modifiers.insert(.control) }
                if flags.contains(.command) { modifiers.insert(.command) }
                if selector != #selector(NSResponder.insertNewline(_:)) { modifiers.insert(.option) }
                if parent.onReturn(modifiers) == .newline {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                // Esc clears a reply if there is one. Either way it is handled here: left to the text view, it
                // would open the word-completion list.
                _ = parent.onEscape()
                return true
            default:
                return false
            }
        }
    }
}

/// An NSTextView that shows a placeholder when empty, and takes files that are pasted.
final class PlainTextView: NSTextView {
    var placeholder = "" {
        didSet { needsDisplay = true }
    }
    var onPasteFiles: ([URL]) -> Bool = { _ in false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty, !hasMarkedText() else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                             y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: [
            .font: font ?? NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor,
        ])
    }

    private static func files(on pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// Files dropped on the box are attached; left to the text view, their paths would be typed into the text.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.files(on: sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.files(on: sender.draggingPasteboard).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = Self.files(on: sender.draggingPasteboard)
        if !files.isEmpty, onPasteFiles(files) { return true }
        return super.performDragOperation(sender)
    }

    override func paste(_ sender: Any?) {
        let files = Self.files(on: NSPasteboard.general)
        if !files.isEmpty, onPasteFiles(files) { return }
        // Plain text only: formatting from the other app is left behind.
        pasteAsPlainText(sender)
    }
}
