// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Extracts attachable file URLs or clipboard image data from an `NSPasteboard`.
///
/// When a user copies a file in Finder, the pasteboard contains a `file://` URL (alongside a Finder icon `.tiff`
/// and filename `.string`), so file URLs always take precedence. When no file URLs are present—for example after
/// taking a macOS screenshot to the clipboard (`⌘⌃⇧4`), choosing **Copy Image** in a browser, Preview, Photos, or
/// Vitruvian Courier's media lightbox—raw image data on the pasteboard is materialized to a temporary file so the composer
/// can attach and send it as an inline image.
public enum PasteboardAttachmentExtractor {
    private static let gifPasteboardType = NSPasteboard.PasteboardType(UTType.gif.identifier)
    private static let jpegPasteboardType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
    private static let webpPasteboardType = NSPasteboard.PasteboardType(UTType.webP.identifier)
    private static let heicPasteboardType = NSPasteboard.PasteboardType("public.heic")

    /// Returns `true` when `pasteboard` carries either local file URLs or standalone image data suitable for
    /// attaching to the message composer.
    public static func hasFilesOrImage(on pasteboard: NSPasteboard) -> Bool {
        if !fileURLs(on: pasteboard).isEmpty {
            return true
        }
        if isRichOrTabularTextCopy(pasteboard) {
            return false
        }
        let directImageTypes: [NSPasteboard.PasteboardType] = [
            gifPasteboardType,
            .png,
            jpegPasteboardType,
            webpPasteboardType,
            heicPasteboardType,
            .tiff,
        ]
        if pasteboard.availableType(from: directImageTypes) != nil {
            return true
        }
        return NSImage.canInit(with: pasteboard)
    }

    /// Reads local file URLs from `pasteboard`, or if none are present, writes any standalone clipboard image to a
    /// temporary file inside `tempDirectory` and returns its file URL.
    public static func extractFiles(
        from pasteboard: NSPasteboard,
        tempDirectory: URL = FileManager.default.temporaryDirectory,
        now: Date = Date()
    ) -> [URL] {
        let urls = fileURLs(on: pasteboard)
        if !urls.isEmpty {
            return urls
        }
        guard !isRichOrTabularTextCopy(pasteboard),
              let payload = extractImagePayload(from: pasteboard),
              let savedURL = writeTemporaryImage(
                  data: payload.data,
                  fileExtension: payload.fileExtension,
                  tempDirectory: tempDirectory,
                  now: now
              )
        else {
            return []
        }
        return [savedURL]
    }

    /// Materializes raw image bytes (converting TIFF/HEIC/unrecognized bitmaps to PNG when needed) into a
    /// uniquely-located temporary file with a clean `"Pasted Image <timestamp>.<ext>"` filename.
    public static func writeImageData(
        _ data: Data,
        preferredExtension: String = "png",
        tempDirectory: URL = FileManager.default.temporaryDirectory,
        now: Date = Date()
    ) -> URL? {
        guard !data.isEmpty else { return nil }
        if let sniffedExt = sniffDirectImageExtension(data) {
            return writeTemporaryImage(
                data: data,
                fileExtension: sniffedExt,
                tempDirectory: tempDirectory,
                now: now
            )
        }
        if let rep = NSBitmapImageRep(data: data),
           let pngData = rep.representation(using: .png, properties: [:]),
           !pngData.isEmpty {
            return writeTemporaryImage(
                data: pngData,
                fileExtension: "png",
                tempDirectory: tempDirectory,
                now: now
            )
        }
        let ext = preferredExtension.lowercased()
        return writeTemporaryImage(
            data: data,
            fileExtension: ext.isEmpty ? "png" : ext,
            tempDirectory: tempDirectory,
            now: now
        )
    }

    /// Detects PNG, JPEG, GIF, or WebP from magic bytes so raw bytes keep their exact format and any other
    /// container (TIFF, HEIC, BMP) is transcoded to PNG.
    private static func sniffDirectImageExtension(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 8,
           bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
           bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A {
            return "png"
        }
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "jpg"
        }
        if bytes.count >= 6,
           bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38,
           (bytes[4] == 0x37 || bytes[4] == 0x39), bytes[5] == 0x61 {
            return "gif"
        }
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return "webp"
        }
        return nil
    }

    private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
    }

    /// Rich text editors and spreadsheets (Pages, Word, Notes, Numbers, Excel) place `.rtf`, `.rtfd`, or
    /// `.tabularText` alongside plain text (and sometimes a `.tiff` preview of the copied cells). Those copies
    /// should paste as plain text rather than attaching a picture of the text.
    private static func isRichOrTabularTextCopy(_ pasteboard: NSPasteboard) -> Bool {
        let richTextTypes: [NSPasteboard.PasteboardType] = [
            .rtf,
            .rtfd,
            .tabularText,
        ]
        guard pasteboard.availableType(from: richTextTypes) != nil else {
            return false
        }
        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return false
        }
        return !text.isEmpty
    }

    private static func extractImagePayload(
        from pasteboard: NSPasteboard
    ) -> (data: Data, fileExtension: String)? {
        if let gifData = pasteboard.data(forType: gifPasteboardType), !gifData.isEmpty {
            return (gifData, "gif")
        }
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return (pngData, "png")
        }
        if let jpegData = pasteboard.data(forType: jpegPasteboardType), !jpegData.isEmpty {
            return (jpegData, "jpg")
        }
        if let webpData = pasteboard.data(forType: webpPasteboardType), !webpData.isEmpty {
            return (webpData, "webp")
        }
        if let heicData = pasteboard.data(forType: heicPasteboardType), !heicData.isEmpty {
            if let rep = NSBitmapImageRep(data: heicData),
               let pngData = rep.representation(using: .png, properties: [:]),
               !pngData.isEmpty {
                return (pngData, "png")
            }
            return (heicData, "heic")
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]),
           !pngData.isEmpty {
            return (pngData, "png")
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let pngData = encodePNG(from: image),
           !pngData.isEmpty {
            return (pngData, "png")
        }
        return nil
    }

    private static func encodePNG(from image: NSImage) -> Data? {
        if let tiffData = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
            return pngData
        }
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    private static func writeTemporaryImage(
        data: Data,
        fileExtension: String,
        tempDirectory: URL,
        now: Date
    ) -> URL? {
        let rootDir = tempDirectory.appendingPathComponent("VitruvianCourier-Pasted-Images", isDirectory: true)
        pruneStaleDirectories(in: rootDir, now: now)
        let baseDir = rootDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            let fileURL = baseDir.appendingPathComponent(fileName(for: now, fileExtension: fileExtension))
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func pruneStaleDirectories(in rootDir: URL, now: Date) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: rootDir,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let cutoff = now.addingTimeInterval(-24 * 3600)
        for child in children {
            guard let values = try? child.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
                  let date = values.contentModificationDate ?? values.creationDate,
                  date < cutoff
            else { continue }
            try? fm.removeItem(at: child)
        }
    }

    private static func fileName(for date: Date, fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Pasted Image \(formatter.string(from: date)).\(fileExtension)"
    }
}
