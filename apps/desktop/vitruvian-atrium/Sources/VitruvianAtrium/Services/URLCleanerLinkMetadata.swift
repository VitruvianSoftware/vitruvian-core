// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import LinkPresentation
import VitruvianAtriumCore

package enum URLCleanerLinkMetadata {
    package static let pasteboardType = NSPasteboard.PasteboardType("com.apple.linkpresentation.metadata")

    package enum Rewrite: Equatable, Sendable {
        case preserved(Data)
        case discard
        case incompatible
    }

    /// Safari can put a rich preview beside a copied link. Keep its title and
    /// pictures, but clean both navigation addresses so a rich paste cannot
    /// restore tracking. The archive layout belongs to LinkPresentation.
    package static func rewrite(_ data: Data?, matching text: String, rules: URLCleaning.Rules) -> Rewrite {
        // A large or unrecognized preview falls back to the cleaned link,
        // without decoding unbounded content on the shared pasteboard lane.
        guard let data, data.count <= 2 * 1024 * 1024,
              let decoder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return .discard }
        decoder.requiresSecureCoding = true
        decoder.decodingFailurePolicy = .setErrorAndReturn
        let metadata = decoder.decodeObject(of: LPLinkMetadata.self, forKey: NSKeyedArchiveRootObjectKey)
        decoder.finishDecoding()
        guard let metadata, decoder.error == nil else { return .discard }

        let link = URLCleaning.address(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let addresses = [metadata.originalURL, metadata.url].compactMap { $0 }
        guard addresses.contains(where: { URLCleaning.address($0.absoluteString) == link }) else { return .incompatible }

        func clean(_ url: URL?) -> URL? {
            guard let url, let result = URLCleaning.clean(url.absoluteString, rules: rules) else { return nil }
            return URL(string: result.url)
        }
        let originalURL = clean(metadata.originalURL)
        let url = clean(metadata.url)
        guard (metadata.originalURL == nil || originalURL != nil),
              (metadata.url == nil || url != nil) else { return .incompatible }

        // A redirect may lead somewhere else. Clean each address with its own
        // host's rules instead of replacing the destination with the source.
        metadata.originalURL = originalURL
        metadata.url = url
        guard let rewritten = try? NSKeyedArchiver.archivedData(
            withRootObject: metadata, requiringSecureCoding: true) else { return .discard }
        return .preserved(rewritten)
    }
}
