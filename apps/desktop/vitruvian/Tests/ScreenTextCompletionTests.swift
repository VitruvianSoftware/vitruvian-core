// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianServices

/// Runs the real Screen OCR entry points and completion with controlled
/// queues. Recognition, the feature runtime, the preferences and the clipboard
/// are doubles; no user data or system pasteboard is touched. A capture is
/// told apart by its width.
@MainActor
enum ScreenTextCompletionTests {
    /// Work waiting for its queue. Only the test's own thread touches it.
    nonisolated final class Queue: @unchecked Sendable {
        var pending: [() -> Void] = []
        func drain() {
            let work = pending
            pending = []
            work.forEach { $0() }
        }
    }

    /// What recognition was asked to read. Only the test's own thread touches it.
    nonisolated final class Recognizer: @unchecked Sendable {
        var outcomes: [Int: ScreenTextService.Outcome] = [:]
        var requests: [(image: Int, qr: Bool, joinLines: Bool, languages: [String])] = []
        func outcome(_ image: CGImage, _ qr: Bool, _ joinLines: Bool, _ languages: [String]) -> ScreenTextService.Outcome {
            requests.append((image.width, qr, joinLines, languages))
            return outcomes[image.width] ?? .text("capture \(image.width)")
        }
    }

    final class Rig {
        var available = true
        var detectsQR = true
        var joinsLines = true
        var pasteboard = "original"
        var changeCount = 0
        var messages: [String] = []
        var readings: [BarcodeDetector.Reading] = []
        let main = Queue()
        let background = Queue()
        let recognizer = Recognizer()

        func write(_ value: String) { pasteboard = value; changeCount += 1 }

        lazy var service = ScreenTextService(environment: .init(
            isAvailable: { self.available },
            detectsQRCodes: { self.detectsQR },
            removesLineBreaks: { self.joinsLines },
            fallbackLanguages: { ["en-US"] },
            pasteboardChangeCount: { self.changeCount },
            recognize: { [recognizer] in recognizer.outcome($0, $1, $2, $3) },
            background: { [background] in background.pending.append($0) },
            main: { [main] work in main.pending.append { MainActor.assumeIsolated { work() } } },
            copy: { self.write($0) },
            notify: { self.messages.append($0) },
            showQR: { self.readings.append($0) }))

        func finish() {
            background.drain()
            main.drain()
        }
    }

    static func image(_ width: Int) -> CGImage {
        CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    static func capture(_ width: Int) -> ScreenshotSelectionController.Capture {
        .init(image: image(width), scale: 1, anchorRect: .zero)
    }

    static func run(_ suite: TestSuite) {
        let strings = L10n.shared.s

        let normal = Rig()
        normal.service.copyText(from: image(42))
        suite.expect(normal.pasteboard == "original" && normal.recognizer.requests.isEmpty,
                     "preview OCR does not block or copy before background recognition")
        normal.finish()
        suite.expect(normal.pasteboard == "capture 42" && normal.messages == [strings.ocrCopied],
                     "an unchanged clipboard receives the recognized text and success feedback")
        suite.expect(normal.recognizer.requests.count == 1 && normal.recognizer.requests[0].image == 42
                     && !normal.recognizer.requests[0].qr && normal.recognizer.requests[0].joinLines
                     && normal.recognizer.requests[0].languages == ["en-US"],
                     "preview OCR uses the captured image and language/line preferences, bypassing QR")

        for duringRecognition in [true, false] {
            let rig = Rig()
            rig.service.copyText(from: image(1))
            if !duringRecognition { rig.background.drain() }
            rig.write("newer user copy")
            rig.finish()
            suite.expect(rig.pasteboard == "newer user copy" && rig.messages.isEmpty,
                         "OCR preserves a newer copy made before or after recognition finishes")
        }

        let disabled = Rig()
        disabled.available = false
        disabled.service.copyText(from: image(1))
        disabled.service.receiveUnifiedCapture(capture(2))
        suite.expect(disabled.background.pending.isEmpty,
                     "disabled OCR cannot start from the preview or unified capture")

        for resync in [false, true] {
            let rig = Rig()
            rig.service.copyText(from: image(1))
            rig.background.drain()
            rig.available = false
            if resync {
                rig.service.syncWithPreferences()
                rig.available = true
            }
            rig.finish()
            suite.expect(rig.pasteboard == "original" && rig.messages.isEmpty,
                         "turning OCR off suppresses pending results, including after reinstall")
        }

        let suspended = Rig()
        suspended.service.copyText(from: image(1))
        suspended.service.suspend()
        suspended.finish()
        suite.expect(suspended.pasteboard == "original" && suspended.messages.isEmpty,
                     "suspending OCR suppresses a pending preview result")

        for newestFirst in [false, true] {
            let rig = Rig()
            rig.service.copyText(from: image(1))
            rig.service.copyText(from: image(2))
            if newestFirst { rig.background.pending.reverse() }
            rig.finish()
            suite.expect(rig.pasteboard == "capture 2" && rig.messages == [strings.ocrCopied],
                         "only the latest OCR request copies, with newestFirst=\(newestFirst)")
        }

        for detectQR in [false, true] {
            for joinLines in [false, true] {
                for preview in [false, true] {
                    let rig = Rig()
                    rig.detectsQR = detectQR
                    rig.joinsLines = joinLines
                    if preview { rig.service.copyText(from: image(7)) }
                    else { rig.service.receiveUnifiedCapture(capture(7)) }
                    rig.finish()
                    suite.expect(rig.recognizer.requests.count == 1
                                 && rig.recognizer.requests[0].qr == (preview ? false : detectQR)
                                 && rig.recognizer.requests[0].joinLines == joinLines,
                                 "OCR respects QR=\(detectQR), joinLines=\(joinLines), preview=\(preview)")
                    suite.expect(rig.pasteboard == "capture 7",
                                 "both entry points still copy text with each preference combination")
                }
            }
        }

        let empty = Rig()
        empty.recognizer.outcomes[1] = .empty
        empty.service.copyText(from: image(1))
        empty.finish()
        suite.expect(empty.pasteboard == "original" && empty.messages == [strings.ocrNoText],
                     "no text leaves the clipboard intact and reports the empty result")

        let unified = Rig()
        let reading = BarcodeDetector.Reading(payload: "https://example.com", url: URL(string: "https://example.com"))
        unified.recognizer.outcomes[1] = .qr(reading)
        unified.service.receiveUnifiedCapture(capture(1))
        unified.finish()
        suite.expect(unified.recognizer.requests.first?.qr == true && unified.readings == [reading]
                     && unified.pasteboard == "original",
                     "unified OCR still honors QR detection and presents its result without copying")

        // Past the area bound a capture is scaled down before Vision reads it.
        let small = image(40)
        suite.expect(ScreenTextService.recognitionImage(small) === small,
                     "a capture within the area bound is read whole")
    }
}
