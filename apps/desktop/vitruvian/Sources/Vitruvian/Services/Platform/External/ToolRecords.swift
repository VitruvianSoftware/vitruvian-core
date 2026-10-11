// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// What the person agreed to when they added a tool, or last updated it.
/// The name, version and publisher are the tool's own words at that moment.
package struct ToolAgreement: Codable, Equatable, Sendable {
    /// When the person agreed.
    package let date: Date
    package let name: String
    package let version: String
    package let publisher: String
    /// The manifest the person was shown, as `ToolFingerprint` names its
    /// bytes. A copy whose manifest has another one is not what they
    /// agreed to.
    package let fingerprint: String
    /// The folder the tool was added from.
    package let source: String

    package init(date: Date, name: String, version: String, publisher: String, fingerprint: String,
                 source: String) {
        self.date = date
        self.name = name
        self.version = version
        self.publisher = publisher
        self.fingerprint = fingerprint
        self.source = source
    }
}

/// One tool the person added, as the app remembers it from one launch to
/// the next.
package struct ToolRecord: Codable, Equatable, Sendable {
    package let id: String
    /// The tool's switch in Settings.
    package var isOn: Bool
    package var agreement: ToolAgreement

    package init(id: String, isOn: Bool, agreement: ToolAgreement) {
        self.id = id
        self.isOn = isOn
        self.agreement = agreement
    }
}

/// The file the tool store keeps its records in: `InstalledTools.json`, in
/// the app's support folder, beside `Tools/` and `ToolData/`.
///
///     { "version": 1,
///       "tools": [ { "id": "com.acme.deploys", "isOn": true,
///                    "agreement": { "date": "2026-10-11T09:30:00Z", "name": "Deploys",
///                                   "version": "1.2.0", "publisher": "Acme",
///                                   "fingerprint": "<64 hex digits>",
///                                   "source": "/Users/me/tools/deploys" } } ] }
///
/// It is not a preference and is in no settings backup: a tool is a program
/// on this Mac, and agreeing to one is done on the Mac it runs on.
package enum ToolRecords {
    package static let fileName = "InstalledTools.json"
    /// Where a file that could not be read is put before a new one is
    /// written, so that writing never destroys what a person could mend.
    package static let unreadableFileName = "InstalledTools.unreadable.json"
    /// The one version of the file this app reads and writes.
    package static let version = 1

    package enum Outcome: Equatable, Sendable {
        /// There is no file: nothing was ever added.
        case none
        case records([ToolRecord])
        /// There is a file and it is not one this app can read: damaged,
        /// written by a later version, or naming something that is no tool
        /// from outside. It is left exactly as it is.
        case unreadable
    }

    private struct File: Codable {
        var version: Int
        var tools: [ToolRecord]
    }

    package static func read(at url: URL, fileManager: FileManager = .default) -> Outcome {
        guard fileManager.fileExists(atPath: url.path) else { return .none }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = fileManager.contents(atPath: url.path),
              let file = try? decoder.decode(File.self, from: data), file.version == version else {
            return .unreadable
        }
        // Every record names a tool from outside, once. Anything else is
        // not a file this app wrote.
        let ids = file.tools.compactMap { ToolID($0.id) }.filter { !$0.isBundledForm }
        guard ids.count == file.tools.count, Set(ids).count == ids.count else { return .unreadable }
        return .records(file.tools)
    }

    /// Writes the whole file, in place of the one there. For the person
    /// alone, as everything in the app's support folder is.
    @discardableResult
    package static func write(_ records: [ToolRecord], to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(File(version: version, tools: records)) else { return false }
        return PrivateFileStore.write(data, to: url)
    }
}
