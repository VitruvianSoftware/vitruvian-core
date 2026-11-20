// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import PDFKit
import SwiftUI

final class InlinePDFDocumentCache: @unchecked Sendable {
    static let shared = InlinePDFDocumentCache()
    private let lock = NSLock()
    private var cache: [String: PDFDocument] = [:]
    private(set) var parseCount = 0

    func resetForTests() {
        lock.withLock {
            cache.removeAll()
            inFlight.removeAll()
            parseCount = 0
        }
    }

    private var inFlight = Set<String>()

    /// The document, when it has been read; never reads the file on the calling thread (a row is laid out and measured
    /// on the main one). One not read yet is read in the background, and `didLearnSizeNotification` (with the path)
    /// says when it is in.
    func document(atPath path: String) -> PDFDocument? {
        if let cached = lock.withLock({ cache[path] }) { return cached }
        guard LocalFileFacts.exists(path) == true else { return nil }
        parseInBackground(path)
        return nil
    }

    /// Reads the file now, on this thread (a background one): for `LocalFileFacts.warm` and the lookup above.
    func parse(path: String) {
        guard let url = InlinePDFView.localPDFURL(for: path) else { return }
        let alreadyThere = lock.withLock { cache[url.path] != nil }
        guard !alreadyThere, let doc = PDFDocument(url: url) else {
            lock.withLock { _ = inFlight.remove(path) }
            return
        }
        lock.withLock {
            parseCount += 1
            cache[url.path] = doc
            inFlight.remove(path)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: ImagePixelSizeReader.didLearnSizeNotification, object: nil,
                userInfo: [ImagePixelSizeReader.pathUserInfoKey: path]
            )
        }
    }

    private func parseInBackground(_ path: String) {
        let started = lock.withLock { inFlight.insert(path).inserted }
        guard started else { return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in parse(path: path) }
    }

    /// Reads PDFs ahead of their rows, as `LocalFileFacts.warm` finds them, so a PDF card is its full height from
    /// the first frame.
    static func installWarmer() {
        LocalFileFacts.setWarmer { path in
            guard path.lowercased().hasSuffix(".pdf") else { return }
            InlinePDFDocumentCache.shared.parse(path: path)
        }
    }

    func hasDocument(atPath path: String) -> Bool {
        lock.withLock { cache[path] != nil }
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

    /// Whether `message` is a local, non-view-once PDF that can be rendered inline.
    public static func canDisplay(_ message: TimelineMessage) -> Bool {
        guard !message.viewOnce,
              isPDF(fileName: message.fileName, mimeType: message.mimeType)
        else {
            return false
        }
        return InlinePDFDocumentCache.shared.document(atPath: message.mediaPath) != nil
    }

    private var document: PDFDocument? {
        guard !message.viewOnce else { return nil }
        return InlinePDFDocumentCache.shared.document(atPath: message.mediaPath)
    }

    private var displayName: String {
        message.fileName.isEmpty ? String(localized: "PDF Document") : message.fileName
    }

    public var body: some View {
        if let document, document.pageCount > 0 {
            let pageCount = document.pageCount
            let clampedIndex = min(max(0, currentPageIndex), pageCount - 1)
            let pageNumber = clampedIndex + 1

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
            .accessibilityLabel(String(localized: "\(displayName), Page \(pageNumber) of \(pageCount)"))
        } else {
            FileAttachmentChip(message: message, preferences: preferences, onDownload: onDownload)
        }
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
    private func pagePreview(document: PDFDocument, pageIndex: Int) -> some View {
        if let page = document.page(at: pageIndex) {
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
        }
    }

    @ViewBuilder
    private func footerControls(clampedIndex: Int, pageNumber: Int, pageCount: Int) -> some View {
        HStack(spacing: 8) {
            Text(String(localized: "Page \(pageNumber) of \(pageCount)"))
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
            .disabled(clampedIndex + 1 >= pageCount)
            .help(String(localized: "Next Page"))
            .accessibilityLabel(String(localized: "Next Page"))
        }
    }

    private func metadataSubtitle(pageNumber: Int, pageCount: Int) -> String {
        var parts: [String] = ["PDF"]
        if let size = message.byteSize, size > 0 {
            parts.append(FileSize.text(size))
        }
        parts.append(String(localized: "Page \(pageNumber) of \(pageCount)"))
        return parts.joined(separator: " · ")
    }
}
