// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CryptoKit
import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// A tool the person may add: what its folder holds, read and checked. To
/// make one, nothing was copied, nothing was run and nothing was saved.
///
/// Only the tool store makes one (`ExternalToolStore.offer(from:)`), which
/// is why it has no initializer another module can call: a screen cannot
/// invent an offer for a folder nobody read.
package struct ToolOffer: Equatable, Sendable {
    /// The folder the person picked, with every link followed.
    package let folder: URL
    package let tool: ExternalToolManifest
    /// The manifest file's bytes, as `ToolFingerprint` names them. Agreeing
    /// is agreeing to these bytes.
    package let fingerprint: String
}

/// That the person agreed to one offer, and when. Adding a tool takes one
/// (`ExternalToolStore.add`), and only the sheet that asks the person makes
/// one: the source rule `only_the_agreement_sheet_consents` fails for any
/// other file of the app that does.
package struct ToolConsent: Equatable, Sendable {
    package let offer: ToolOffer
    package let date: Date

    package init(to offer: ToolOffer, on date: Date = Date()) {
        self.offer = offer
        self.date = date
    }
}

/// A short name for a manifest file's exact bytes: their SHA-256, in hex.
/// Two manifests have the same one only when they are the same file, byte
/// for byte. A changed space changes it. It says nothing of the tool's
/// program or its other files.
package enum ToolFingerprint {
    package static func of(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
    }

    /// Of the manifest in `folder`; nil when there is none to read.
    package static func ofManifest(in folder: URL, fileManager: FileManager = .default) -> String? {
        fileManager.contents(atPath: folder.appendingPathComponent(ToolManifestFile.fileName).path).map(of)
    }
}
