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

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The small window that shows a pairing QR code and counts down its five
/// minutes. One at a time: opening a new one closes the old, whose code the
/// agent has already replaced.
@MainActor
final class QRWindowController {
    static let shared = QRWindowController()
    private var window: NSWindow?

    func show(url: URL, address: String, expires: Date) {
        window?.close()
        let view = QRPairView(url: url, address: address, expires: expires) { [weak self] in
            self?.window?.close()
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Pair a Phone"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct QRPairView: View {
    let url: URL
    let address: String
    let expires: Date
    let done: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, Int(expires.timeIntervalSince(context.date)))
            VStack(spacing: 14) {
                Text("Scan with your phone's camera")
                    .font(.headline)
                Group {
                    if left > 0, let image = qrImage(url.absoluteString) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 220, height: 220)
                    } else {
                        Text("Expired. Choose Pair with QR Code again for a new one.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(width: 220, height: 220)
                    }
                }
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                Text("Open the link, tap Open in Vitruvian Remote, then confirm on the phone.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(left > 0 ? "\(address) · expires in \(left / 60):\(String(format: "%02d", left % 60))" : address)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(22)
            .frame(width: 300)
        }
    }

    private func qrImage(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
