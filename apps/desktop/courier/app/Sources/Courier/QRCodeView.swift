// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code for the phone to scan, drawn by CoreImage's CIQRCodeGenerator: black on white in either
/// appearance, with the quiet zone around it that scanners need.
struct QRCodeView: View {
    let data: String
    var side: CGFloat = 220

    var body: some View {
        if let image = Self.image(for: data) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: side, height: side)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(String(localized: "QR code"))
        } else {
            Text(String(localized: "Courier couldn’t draw this QR code."))
                .foregroundStyle(.secondary)
        }
    }

    /// The code at one point per module, scaled up without smoothing by the view.
    static func image(for data: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(data.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
