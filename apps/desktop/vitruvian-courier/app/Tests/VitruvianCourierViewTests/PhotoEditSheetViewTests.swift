// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// "Edit with AI…": the sheet in each of its states, light and dark, and the viewer's button. Draws them to PNGs for a
/// person to read (see the BUILD note on VitruvianCourierViewTests) and asserts only that each drew at a sensible size.
@MainActor
final class PhotoEditSheetViewTests: XCTestCase {
    private var tempDirs: [URL] = []
    private var suites: [String] = []

    override func tearDown() async throws {
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
        for name in suites { ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name) }
        suites = []
    }

    private func png(_ width: Int, _ height: Int, red: CGFloat) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor(calibratedRed: red, green: 0.5, blue: 0.7, alpha: 1).setFill()
            rect.fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3)).fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func makeModel(
        resolution: PhotoEditingResolution, consented: Bool = true,
        result: ImageEditResult? = nil
    ) throws -> PhotoEditModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("photo-edit-view-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        let photo = dir.appendingPathComponent("beach.png")
        try png(800, 600, red: 0.2).write(to: photo)
        let name = "courier.photoEditSheet.\(UUID().uuidString)"
        suites.append(name)
        let consent = PhotoEditConsentStore(defaults: ScratchDefaults.suite(named: name)!)
        if consented { consent.recordConsent(to: .googleAIStudio) }
        let edited = EditedImage(data: png(800, 600, red: 0.8), mimeType: "image/png")
        let backend = PhotoEditBackend(
            isOffered: { true }, resolve: { resolution },
            makeEditor: { kind in StubEditor(provider: kind, result: result ?? .success(edited)) },
            consent: consent
        )
        return PhotoEditModel(
            source: PhotoEditSource(path: photo.path, fileName: "beach.png", mimeType: "image/png", roomID: "!a"),
            backend: backend, draftIntoMessage: { _, _ in true },
            scratchDirectory: dir.appendingPathComponent("drafts")
        )
    }

    private struct StubEditor: AIImageEditor {
        let provider: AIProviderKind
        let result: ImageEditResult
        func edit(image _: Data, mimeType _: String, instruction _: String) async -> ImageEditResult { result }
    }

    private func settle(_ model: PhotoEditModel) async throws {
        for _ in 0 ..< 500 {
            if case .working = model.phase {
                try await Task.sleep(nanoseconds: 10_000_000)
            } else {
                return
            }
        }
        XCTFail("the edit never finished")
    }

    private func draw(_ name: String, _ model: PhotoEditModel) throws {
        let sizes = try Snapshot.render(name, width: 640) {
            PhotoEditSheet(model: model, onClose: {})
        }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes {
            XCTAssertGreaterThan(size.width, 300)
            XCTAssertGreaterThan(size.height, 200, "\(name) drew with something in it")
            XCTAssertLessThan(size.height, 1800)
        }
    }

    func testSheetDrawsInEachState() async throws {
        // Ready: the photo and the instruction field.
        let ready = try makeModel(resolution: .service(.googleAIStudio, source: .savedKey))
        try draw("photo-edit-ready", ready)

        // No service can edit photos: the words, Open AI Settings and the key page link.
        let unavailable = try makeModel(resolution: .noService)
        XCTAssertEqual(unavailable.phase, .unavailable(.noService))
        try draw("photo-edit-unavailable", unavailable)

        // The first photo to a service: the question.
        let asking = try makeModel(resolution: .service(.googleAIStudio, source: .savedKey), consented: false)
        asking.instruction = "brighten it"
        asking.submit()
        XCTAssertEqual(asking.phase, .confirming(.googleAIStudio))
        try draw("photo-edit-consent", asking)

        // A result next to the original.
        let done = try makeModel(resolution: .service(.googleAIStudio, source: .savedKey))
        done.instruction = "brighten it"
        done.submit()
        try await settle(done)
        XCTAssertNotNil(done.outcome)
        try draw("photo-edit-result", done)

        // An error in plain words.
        let failed = try makeModel(resolution: .service(.googleAIStudio, source: .savedKey), result: .failure(.needsPaidAccess))
        failed.instruction = "brighten it"
        failed.submit()
        try await settle(failed)
        XCTAssertEqual(failed.phase, .failed(.needsPaidAccess, .googleAIStudio))
        try draw("photo-edit-error", failed)
    }

    func testViewerShowsEditWithAIOnlyWhenOffered() throws {
        let model = AttachmentCarouselModel()
        let item = CarouselItem(eventID: "$p1", roomID: "!a", mediaPath: "/tmp/p1.jpg", fileName: "p1.jpg", mimeType: "image/jpeg")
        model.open(items: [item], selectedEventID: "$p1")
        XCTAssertTrue(AttachmentCarouselOverlay.actionTitles.contains("Edit with AI…"))

        var asked: [String] = []
        for offered in [false, true] {
            let sizes = try Snapshot.render("photo-viewer-edit-\(offered ? "on" : "off")", width: 1100, height: 520) {
                AttachmentCarouselOverlay(
                    model: model,
                    canEditWithAI: { candidate in
                        asked.append(candidate.eventID)
                        return offered
                    },
                    onEditWithAI: { _ in }
                )
            }
            XCTAssertEqual(sizes.count, 2)
        }
        XCTAssertTrue(asked.contains("$p1"), "the bar asks per item whether to show the button")
    }
}
