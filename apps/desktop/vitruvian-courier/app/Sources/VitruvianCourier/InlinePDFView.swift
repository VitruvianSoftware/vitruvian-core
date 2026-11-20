// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import PDFKit
import SwiftUI

final class InlinePDFDocumentCache: @unchecked Sendable {
    static let shared = InlinePDFDocumentCache()

    /// How many parsed documents are kept; the least recently used one goes first.
    static let maxDocuments = 24

    private let cond = NSCondition()
    private var cache: [String: PDFDocument] = [:]
    /// Paths by recency of use, oldest first.
    private var order: [String] = []
    private var inFlight = Set<String>()
    /// Files that are not (readable) PDFs, so they are not parsed again.
    private var failed = Set<String>()
    private(set) var parseCount = 0

    func resetForTests() {
        cond.lock()
        cache.removeAll()
        order.removeAll()
        inFlight.removeAll()
        failed.removeAll()
        parseCount = 0
        cond.unlock()
    }

    var cachedCountForTesting: Int {
        cond.lock()
        defer { cond.unlock() }
        return cache.count
    }

    func hasDocument(atPath path: String) -> Bool {
        cond.lock()
        defer { cond.unlock() }
        return cache[path] != nil
    }

    /// Whether the file is known not to be a readable PDF.
    func hasFailed(atPath path: String) -> Bool {
        cond.lock()
        defer { cond.unlock() }
        return failed.contains(path)
    }

    /// The document, when it has been read; never reads the file on the calling thread (a row is laid out and measured
    /// on the main one). One not read yet is read in the background, and `didLearnSizeNotification` (with the path)
    /// says when it is in.
    func document(atPath path: String) -> PDFDocument? {
        cond.lock()
        if let cached = cache[path] {
            touch(path)
            cond.unlock()
            return cached
        }
        let skip = failed.contains(path)
        cond.unlock()
        guard !skip, LocalFileFacts.exists(path) == true else { return nil }
        parseInBackground(path)
        return nil
    }

    /// Reads the file now, on this thread (a background one): for `LocalFileFacts.warm` and the lookup above. A path
    /// being read by another thread is waited for, not read twice.
    func parse(path: String) {
        cond.lock()
        if cache[path] != nil || failed.contains(path) {
            cond.unlock()
            return
        }
        if inFlight.contains(path) {
            while inFlight.contains(path) { cond.wait() }
            cond.unlock()
            return
        }
        inFlight.insert(path)
        cond.unlock()

        var document: PDFDocument?
        if let url = InlinePDFView.localPDFURL(for: path) { document = PDFDocument(url: url) }

        cond.lock()
        if let document, document.pageCount > 0 {
            parseCount += 1
            cache[path] = document
            touch(path)
            while order.count > Self.maxDocuments {
                cache.removeValue(forKey: order.removeFirst())
            }
        } else {
            failed.insert(path)
        }
        inFlight.remove(path)
        cond.broadcast()
        cond.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: ImagePixelSizeReader.didLearnSizeNotification, object: nil,
                userInfo: [ImagePixelSizeReader.pathUserInfoKey: path]
            )
        }
    }

    private func touch(_ path: String) {
        if let index = order.firstIndex(of: path) { order.remove(at: index) }
        order.append(path)
    }

    private func parseInBackground(_ path: String) {
        cond.lock()
        let busy = inFlight.contains(path)
        cond.unlock()
        guard !busy else { return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in parse(path: path) }
    }

    /// Reads PDFs ahead of their rows, as `LocalFileFacts.warm` finds them, so a PDF card shows its page from the
    /// first frame. A file is a PDF by its first bytes (a media-store file has no extension).
    static func installWarmer() {
        LocalFileFacts.setWarmer { path in
            guard Self.looksLikePDF(path) else { return }
            InlinePDFDocumentCache.shared.parse(path: path)
        }
    }

    /// Reads five bytes; for background threads.
    static func looksLikePDF(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 5)) ?? Data()
        return head == Data("%PDF-".utf8)
    }
}

/// Inline PDF card (`PDFAttachment.tsx`, `PDF.tsx`): renders local `PDFDocument` pages with `PDFKit`
/// (`PDFPage.thumbnail(of:for:)`), a header showing filename, byte size, `Page X of N`,
/// **Previous Page** / **Next Page** buttons, **Open**, and **Download** (`⌘D`).
/// Never loads remote URLs.
public struct InlinePDFView: View {
    public let message: TimelineMessage
    public var preferences: ComposerPreferences
    public var onDownload: ((TimelineMessage) -> Void)?

    @State private var currentPageIndex: Int

    public static let previewWidth: CGFloat = 340
    public static let previewHeight: CGFloat = 220

    public static let userVisibleStrings: [String] = [
        String(localized: "PDF Document"),
        String(localized: "Previous Page"),
        String(localized: "Next Page"),
        String(localized: "Open"),
        String(localized: "Download"),
        String(localized: "Download (⌘D)"),
        String(localized: "PDF unavailable"),
    ]

    public init(
        message: TimelineMessage,
        initialPageIndex: Int = 0,
        preferences: ComposerPreferences = ComposerPreferences(),
        onDownload: ((TimelineMessage) -> Void)? = nil
    ) {
        self.message = message
        self.preferences = preferences
        self.onDownload = onDownload
        _currentPageIndex = State(initialValue: max(0, initialPageIndex))
    }

    /// Returns a local file `URL` only when `path` is inside the local filesystem (never a remote URL) and exists on disk.
    /// Asks the disk: not for a view's body (the main thread); the document cache asks memory instead.
    public static func localPDFURL(for path: String) -> URL? {
        guard isLocalMediaStorePath(path) else { return nil }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return nil
        }
        return url
    }

    /// Whether the filename or MIME type identifies a PDF document.
    public static func isPDF(fileName: String, mimeType: String) -> Bool {
        if mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "application/pdf" {
            return true
        }
        return (fileName as NSString).pathExtension.lowercased() == "pdf"
    }

    /// Whether `message` is a local, non-view-once PDF that can be rendered inline: its file is there (or not known
    /// yet; it is looked up in the background) and is not known to be unreadable. Its pages may still be coming.
    public static func canDisplay(_ message: TimelineMessage) -> Bool {
        guard !message.viewOnce,
              isPDF(fileName: message.fileName, mimeType: message.mimeType)
        else {
            return false
        }
        return mayBecomeCard(message)
    }

    static func mayBecomeCard(_ message: TimelineMessage) -> Bool {
        guard !message.viewOnce, isLocalMediaStorePath(message.mediaPath) else { return false }
        if InlinePDFDocumentCache.shared.hasDocument(atPath: message.mediaPath) { return true }
        if InlinePDFDocumentCache.shared.hasFailed(atPath: message.mediaPath) { return false }
        return LocalFileFacts.exists(message.mediaPath) != false
    }

    private var document: PDFDocument? {
        guard !message.viewOnce else { return nil }
        return InlinePDFDocumentCache.shared.document(atPath: message.mediaPath)
    }

    private var displayName: String {
        message.fileName.isEmpty ? String(localized: "PDF Document") : message.fileName
    }

    @State private var factTick = 0
    @Environment(\.timelineContentRevision) private var contentRevision

    /// Draws again when the file turns up or its pages are read (`didLearnSizeNotification`, with the path).
    public var body: some View {
        card
            .onReceive(NotificationCenter.default.publisher(for: ImagePixelSizeReader.didLearnSizeNotification)) { note in
                if let path = note.userInfo?[ImagePixelSizeReader.pathUserInfoKey] as? String, path == message.mediaPath {
                    factTick += 1
                }
            }
            .id(factTick)
    }

    /// The card with its page; the same card without the page while the file is being read (one height both ways, so
    /// no row moves when the pages arrive); the file chip when there is nothing to show.
    @ViewBuilder
    private var card: some View {
        let _ = contentRevision
        if let document, document.pageCount > 0 {
            let pageCount = document.pageCount
            let clampedIndex = min(max(0, currentPageIndex), pageCount - 1)
            cardBody(document: document, pageNumber: clampedIndex + 1, pageCount: pageCount, clampedIndex: clampedIndex)
        } else if Self.mayBecomeCard(message) {
            cardBody(document: nil, pageNumber: 1, pageCount: 0, clampedIndex: 0)
        } else {
            FileAttachmentChip(message: message, preferences: preferences, onDownload: onDownload)
        }
    }

    private func cardBody(document: PDFDocument?, pageNumber: Int, pageCount: Int, clampedIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headerBar(pageNumber: pageNumber, pageCount: pageCount)
            pagePreview(document: document, pageIndex: clampedIndex)
            footerControls(clampedIndex: clampedIndex, pageNumber: pageNumber, pageCount: pageCount)
        }
        .padding(10)
        .frame(width: Self.previewWidth)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pageCount > 0
            ? String(localized: "\(displayName), Page \(pageNumber) of \(pageCount)")
            : displayName)
    }

    @ViewBuilder
    private func headerBar(pageNumber: Int, pageCount: Int) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadataSubtitle(pageNumber: pageNumber, pageCount: pageCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                ReceivedFile.open(message)
            } label: {
                Text(String(localized: "Open"))
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(String(localized: "Open"))
            .accessibilityLabel(String(localized: "Open \(displayName)"))

            Button {
                if let onDownload {
                    onDownload(message)
                } else {
                    ReceivedFile.download(message, preferences: preferences)
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(String(localized: "Download (⌘D)"))
            .accessibilityLabel(String(localized: "Download \(displayName)"))
        }
    }

    @ViewBuilder
    private func pagePreview(document: PDFDocument?, pageIndex: Int) -> some View {
        if let page = document?.page(at: pageIndex) {
            let thumb = page.thumbnail(
                of: NSSize(width: Self.previewWidth * 2, height: Self.previewHeight * 2),
                for: .mediaBox
            )
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: Self.previewWidth - 20, maxHeight: Self.previewHeight)
                    .padding(4)
            }
            .frame(width: Self.previewWidth - 20, height: Self.previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            .onTapGesture {
                ReceivedFile.open(message)
            }
        } else {
            // Not read yet: the page's place, as tall as the page.
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: Self.previewWidth - 20, height: Self.previewHeight)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        }
    }

    @ViewBuilder
    private func footerControls(clampedIndex: Int, pageNumber: Int, pageCount: Int) -> some View {
        HStack(spacing: 8) {
            Text(pageCount > 0 ? String(localized: "Page \(pageNumber) of \(pageCount)") : String(localized: "Page \(pageNumber)"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                currentPageIndex = max(0, clampedIndex - 1)
            } label: {
                Label(String(localized: "Previous Page"), systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(clampedIndex <= 0)
            .help(String(localized: "Previous Page"))
            .accessibilityLabel(String(localized: "Previous Page"))

            Button {
                currentPageIndex = min(pageCount - 1, clampedIndex + 1)
            } label: {
                Label(String(localized: "Next Page"), systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(pageCount == 0 || clampedIndex + 1 >= pageCount)
            .help(String(localized: "Next Page"))
            .accessibilityLabel(String(localized: "Next Page"))
        }
    }

    private func metadataSubtitle(pageNumber: Int, pageCount: Int) -> String {
        var parts: [String] = ["PDF"]
        if let size = message.byteSize, size > 0 {
            parts.append(FileSize.text(size))
        }
        if pageCount > 0 { parts.append(String(localized: "Page \(pageNumber) of \(pageCount)")) }
        return parts.joined(separator: " · ")
    }
}

/// A file message's content: the PDF card when it is one, else the file chip. Draws again when the file is learned
/// (the SwiftUI timeline and thread pane have no table to re-measure them), as `InlinePDFView` itself does.
struct FileMessageContent: View {
    let message: TimelineMessage
    let preferences: ComposerPreferences?
    @State private var factTick = 0
    @Environment(\.timelineContentRevision) private var contentRevision

    var body: some View {
        let _ = contentRevision
        Group {
            if InlinePDFView.canDisplay(message) {
                InlinePDFView(message: message)
                    .id(message.id)
            } else {
                FileAttachmentChip(message: message, preferences: preferences)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ImagePixelSizeReader.didLearnSizeNotification)) { note in
            if let path = note.userInfo?[ImagePixelSizeReader.pathUserInfoKey] as? String, path == message.mediaPath {
                factTick += 1
            }
        }
        .id(factTick)
    }
}
