// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Vision
import VitruvianCore
import VitruvianDesign

/// Screen OCR: the user picks an area on the app's own capture surface, the
/// text in it is recognized offline with Vision and lands on the clipboard.
/// Needs Screen Recording, requested contextually on first use.
///
/// The picking and the capture both happen here rather than through the
/// system's capture command. A separate command is judged by macOS on its own
/// standing, which on recent versions can be refused even while this app is
/// allowed, and a refused command writes no file and says nothing: the tool
/// looked dead with no crosshair, no message and nothing to fix (issue #364).
@MainActor
package final class ScreenTextService: ObservableObject {
    /// What the service reads and drives. `system` is the feature runtime,
    /// the preferences, the clipboard, Vision, the HUD, the QR panel and the
    /// dispatch queues; tests pass doubles.
    @MainActor
    package struct Environment {
        package var isAvailable: () -> Bool
        package var detectsQRCodes: () -> Bool
        package var removesLineBreaks: () -> Bool
        package var fallbackLanguages: () -> [String]
        /// Counts the clipboard's changes, so a copy made after a request is kept.
        package var pasteboardChangeCount: () -> Int
        /// Reads a capture; runs on the background queue.
        package var recognize: @Sendable (_ image: CGImage, _ detectQRCodes: Bool, _ removeLineBreaks: Bool,
                                          _ fallbackLanguages: [String]) -> Outcome
        package var background: @Sendable (@escaping @Sendable () -> Void) -> Void
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        package var copy: (String) -> Void
        package var notify: (_ message: String) -> Void
        package var showQR: (BarcodeDetector.Reading) -> Void

        package init(isAvailable: @escaping () -> Bool,
                     detectsQRCodes: @escaping () -> Bool,
                     removesLineBreaks: @escaping () -> Bool,
                     fallbackLanguages: @escaping () -> [String],
                     pasteboardChangeCount: @escaping () -> Int,
                     recognize: @escaping @Sendable (CGImage, Bool, Bool, [String]) -> Outcome,
                     background: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     copy: @escaping (String) -> Void,
                     notify: @escaping (String) -> Void,
                     showQR: @escaping (BarcodeDetector.Reading) -> Void) {
            self.isAvailable = isAvailable
            self.detectsQRCodes = detectsQRCodes
            self.removesLineBreaks = removesLineBreaks
            self.fallbackLanguages = fallbackLanguages
            self.pasteboardChangeCount = pasteboardChangeCount
            self.recognize = recognize
            self.background = background
            self.main = main
            self.copy = copy
            self.notify = notify
            self.showQR = showQR
        }

        package static var system: Environment {
            Environment(
                isAvailable: { AppFeature.screenOCR.isAvailable },
                detectsQRCodes: { UserDefaults.standard[Preferences.screenOCRDetectQRCodes] },
                removesLineBreaks: { UserDefaults.standard[Preferences.screenOCRRemoveLineBreaks] },
                fallbackLanguages: { MediaSupport.recognitionLanguages(for: L10n.shared.language.rawValue) },
                pasteboardChangeCount: { NSPasteboard.general.changeCount },
                recognize: { image, detectQRCodes, removeLineBreaks, fallbackLanguages in
                    ScreenTextService.outcome(for: ScreenTextService.recognitionImage(image),
                                              detectQRCodes: detectQRCodes,
                                              removeLineBreaks: removeLineBreaks,
                                              fallbackLanguages: fallbackLanguages)
                },
                background: { work in DispatchQueue.global(qos: .userInitiated).async { work() } },
                main: { work in DispatchQueue.main.async { work() } },
                copy: { ScreenTextService.copyToPasteboard($0) },
                notify: { QuickToolHUD.show(icon: "text.viewfinder", message: $0) },
                // Show what the code holds instead of copying it blindly;
                // the panel offers copy and, for a link, open.
                showQR: { QRResultController.shared.show(reading: $0) })
        }
    }

    package static let shared = ScreenTextService()

    private var recognitionGeneration = 0
    private let environment: Environment

    package init(environment: Environment = .system) {
        self.environment = environment
    }

    package func syncWithPreferences() {
        guard environment.isAvailable() else {
            cancelSession()
            return
        }
    }

    package func suspend() {
        cancelSession()
    }

    private func cancelSession() {
        recognitionGeneration += 1
    }

    package func capture() {
        ScreenCaptureService.shared.capture(initial: .text)
    }

    package func receiveUnifiedCapture(_ capture: ScreenshotSelectionController.Capture) {
        recognize(capture.image, detectQRCodes: environment.detectsQRCodes())
    }

    /// Copies text from an image that has already been captured. Screenshot
    /// previews expose QR results separately, so this path deliberately runs
    /// text recognition even when the image also contains a code.
    package func copyText(from image: CGImage) {
        recognize(image, detectQRCodes: false)
    }

    /// What a captured region turned out to hold.
    package enum Outcome: Equatable, Sendable {
        case qr(BarcodeDetector.Reading)
        case text(String)
        case empty
    }

    private func recognize(_ image: CGImage, detectQRCodes: Bool) {
        guard environment.isAvailable() else { return }
        recognitionGeneration += 1
        let generation = recognitionGeneration
        let pasteboardChangeCount = environment.pasteboardChangeCount()
        let removeLineBreaks = environment.removesLineBreaks()
        let fallbackLanguages = environment.fallbackLanguages()
        let recognize = environment.recognize
        let main = environment.main
        environment.background { [weak self] in
            let outcome = recognize(image, detectQRCodes, removeLineBreaks, fallbackLanguages)
            main { [weak self] in
                // A later copy belongs to the user, even if this recognition
                // is still the latest OCR request. Never replace it with a
                // result from an earlier capture.
                guard let self, self.recognitionGeneration == generation,
                      self.environment.isAvailable(),
                      self.environment.pasteboardChangeCount() == pasteboardChangeCount else { return }
                let strings = L10n.shared.s
                switch outcome {
                case .qr(let reading):
                    self.environment.showQR(reading)
                case .text(let text):
                    self.environment.copy(text)
                    self.environment.notify(strings.ocrCopied)
                case .empty:
                    self.environment.notify(strings.ocrNoText)
                }
            }
        }
    }

    /// A capture can run to tens of megapixels, like a long scrolling
    /// capture in a screenshot preview or a large area on an 8K display.
    /// Past the bound the clipboard history's Copy text uses, either is
    /// scaled down here, off the main thread, before Vision reads it.
    nonisolated package static func recognitionImage(_ image: CGImage) -> CGImage {
        guard let size = ClipboardImageRecognition.scaledSize(width: image.width, height: image.height),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: size.width,
                                      height: size.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage() ?? image
    }

    /// Decides what a captured region holds. A QR code wins over the text:
    /// it is the thing the user pointed at, and the scan is a fast pass that
    /// falls through to text recognition when no code is found. Pure enough
    /// to exercise directly on a known image.
    /// Recognition runs on a background queue, so any thread may call this.
    nonisolated package static func outcome(for image: CGImage,
                        detectQRCodes: Bool,
                        removeLineBreaks: Bool,
                        fallbackLanguages: [String] = ["en-US"]) -> Outcome {
        if detectQRCodes, let reading = BarcodeDetector.read(image) {
            return .qr(reading)
        }

        var lines = recognizedLines(in: image,
                                    level: .accurate,
                                    automaticallyDetectLanguage: true,
                                    preferredLanguages: fallbackLanguages)
        if lines.isEmpty {
            // The fast path uses a different recognition model. It is a
            // separate second chance when the accurate model returns no text.
            lines = recognizedLines(in: image,
                                    level: .fast,
                                    automaticallyDetectLanguage: false,
                                    preferredLanguages: fallbackLanguages)
        }
        let text = QuickToolsSupport.joinedRecognizedText(lines,
                                                         removingLineBreaks: removeLineBreaks)
        return text.isEmpty ? .empty : .text(text)
    }

    nonisolated private static func recognizedLines(
        in image: CGImage,
        level: VNRequestTextRecognitionLevel,
        automaticallyDetectLanguage: Bool,
        preferredLanguages: [String] = []
    ) -> [QuickToolsSupport.RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = automaticallyDetectLanguage
        if !preferredLanguages.isEmpty,
           let supported = try? request.supportedRecognitionLanguages() {
            let available = preferredLanguages.filter { supported.contains($0) }
            if !available.isEmpty { request.recognitionLanguages = available }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }

        return (request.results ?? []).compactMap { observation -> QuickToolsSupport.RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return QuickToolsSupport.RecognizedLine(text: candidate.string,
                                                    x: observation.boundingBox.minX,
                                                    y: observation.boundingBox.midY)
        }
    }

    package static func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVitruvianSource()
        pasteboard.setString(value, forType: .string)
    }
}
