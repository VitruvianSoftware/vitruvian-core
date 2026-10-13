// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CryptoKit
import Foundation

/// Whether a list of tools is the one VitruvianSoftware published. The list
/// is `tools.json`; beside it, `tools.json.sig` holds an Ed25519 signature
/// of the list's exact bytes, made in CI with the key whose public half is
/// below. The signature file is the signature's 64 bytes in base64, on one
/// line. Nothing about the list is trusted before this says yes.
package enum CatalogueSigning {
    /// The public half of the key that signs the catalog: 32 bytes, in
    /// base64. `catalog/public-key.txt` holds the same line, and
    /// `//catalog:catalog_test` fails when the two differ. A new key is a new
    /// release of the app.
    package static let publicKey = "ysvqcMifelrOyxEx01sOS4B5VN585nBLKkdaaT0xyWY="

    /// The longest signature file the app reads: the 88 characters of the
    /// signature, a line ending, and room for stray spaces.
    package static let signatureFileBytes = 256

    /// True when `signatureFile` is a signature of exactly `list` by the key
    /// whose public half is `publicKey`, in base64.
    package static func verify(_ list: Data, signatureFile: Data, publicKey: String = publicKey) -> Bool {
        guard signatureFile.count <= signatureFileBytes,
              let text = String(data: signatureFile, encoding: .ascii),
              let signature = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              signature.count == 64,
              let raw = Data(base64Encoded: publicKey), raw.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(signature, for: list)
    }
}
