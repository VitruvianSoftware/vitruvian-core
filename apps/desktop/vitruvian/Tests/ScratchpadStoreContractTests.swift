// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VMStatisticsCompat
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

enum ScratchpadStoreContractTests {
    static func run(_ suite: TestSuite) {
        ScratchpadExportContract.run(suite)
        ScratchpadSaveContract.run(suite)
        let manager = FileManager.default
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let original = ScratchpadDocument.initial(defaultName: "Scratchpad", text: "Keep these notes",
                                                   modifiedAt: now.addingTimeInterval(-90_000))
        let originalData = original.encoded()!
        let empty = ScratchpadDocument.initial(defaultName: "Scratchpad")

        func fixture(_ check: (URL, UserDefaults, inout ScratchpadStore) throws -> Void) {
            let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let suiteName = "com.vitruviansoftware.vitruvian.tests.scratchpad.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer {
                try? manager.removeItem(at: directory)
                defaults.removePersistentDomain(forName: suiteName)
            }
            do {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                var store = ScratchpadStore(directoryURL: directory, defaults: defaults)
                try check(directory, defaults, &store)
            } catch {
                suite.expect(false, "scratchpad fixture completes: \(error)")
            }
        }

        fixture { directory, _, store in
            suite.expect(!store.save(empty), "scratchpad cannot save before its first successful read")
            let loaded = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            suite.expect(loaded.pads.count == 1 && loaded.pads[0].text.isEmpty,
                   "a scratchpad with no files or preferences starts empty")
            suite.expect(store.save(original), "a new scratchpad saves edits after a successful read")
            let reopened = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            suite.expect(reopened == original, "scratchpad edits survive reopening")
            let url = directory.appendingPathComponent("Scratchpad.json")
            let permissions = try manager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            suite.expect(permissions?.intValue == 0o600, "scratchpad content remains owner-only")
        }

        for damaged in [Data(), Data("{broken".utf8), Data("{}".utf8)] {
            fixture { directory, defaults, store in
                let url = directory.appendingPathComponent("Scratchpad.json")
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                try damaged.write(to: url)
                try Data("Older notes".utf8).write(to: legacyURL)
                defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
                suite.expect((try? store.load(defaultName: "Scratchpad", retention: .day, now: now)) == nil,
                       "damaged scratchpad data fails without applying retention or falling back")
                suite.expect(!store.save(empty) && !store.save(original),
                       "a damaged scratchpad blocks subsequent saves of empty and nonempty documents")
                suite.expect(try Data(contentsOf: url) == damaged,
                       "damaged scratchpad bytes are preserved exactly")
                suite.expect(defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData
                        && (try? String(contentsOf: legacyURL, encoding: .utf8)) == "Older notes",
                       "a damaged current file keeps both older copies")
                try originalData.write(to: url)
                let retried = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
                suite.expect(retried == original && store.save(original),
                       "retrying after the file becomes readable re-enables normal saving")
            }
        }

        fixture { directory, defaults, store in
            let url = directory.appendingPathComponent("Scratchpad.json")
            try originalData.write(to: url)
            _ = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
            try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
            defer { try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
            suite.expect((try? store.load(defaultName: "Scratchpad", retention: .day, now: now)) == nil,
                   "a read permission failure after a successful opening is not treated as a missing file")
            suite.expect(!store.save(empty) && !store.save(original),
                   "a failed reload revokes saving even for the previously saved document")
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            suite.expect(try Data(contentsOf: url) == originalData,
                   "a read permission failure preserves the original file")
            suite.expect(defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData,
                   "a read permission failure preserves a valid preference copy")
        }

        for preference: Any in [Data("{broken".utf8), "unexpected preference type"] {
            fixture { directory, defaults, store in
                defaults.set(preference, forKey: DefaultsKey.scratchpadDocument)
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                try Data("Older notes".utf8).write(to: legacyURL)
                suite.expect((try? store.load(defaultName: "Scratchpad", retention: .never, now: now)) == nil
                        && !store.save(empty), "an invalid preference blocks replacement and legacy migration")
                suite.expect(defaults.object(forKey: DefaultsKey.scratchpadDocument) != nil
                        && !manager.fileExists(atPath: directory.appendingPathComponent("Scratchpad.json").path)
                        && (try? String(contentsOf: legacyURL, encoding: .utf8)) == "Older notes",
                       "invalid preferences and older notes survive a failed load")
            }
        }

        fixture { directory, defaults, store in
            defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
            let migrated = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            let saved = try Data(contentsOf: directory.appendingPathComponent("Scratchpad.json"))
            suite.expect(migrated == original && ScratchpadDocument.decoded(saved, defaultName: "Scratchpad") == original,
                   "valid preferences migrate with all note content intact")
            suite.expect(defaults.object(forKey: DefaultsKey.scratchpadDocument) == nil,
                   "a migrated preference is removed after the replacement is verified")
        }

        for legacy in [false, true] {
            fixture { directory, defaults, store in
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                if legacy {
                    try Data("Older notes".utf8).write(to: legacyURL)
                } else {
                    defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
                }
                try manager.setAttributes([.immutable: true], ofItemAtPath: directory.path)
                defer { try? manager.setAttributes([.immutable: false], ofItemAtPath: directory.path) }
                let loaded = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
                suite.expect(store.lastSavedDocument == nil
                        && !manager.fileExists(atPath: directory.appendingPathComponent("Scratchpad.json").path),
                       "a blocked migration never counts as a saved document")
                suite.expect(legacy
                        ? (try? String(contentsOf: legacyURL, encoding: .utf8)) == "Older notes"
                        : defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData,
                       "a failed migration write keeps the source copy")
                try manager.setAttributes([.immutable: false], ofItemAtPath: directory.path)
                suite.expect(store.save(loaded), "migration can retry saving once storage becomes writable")
            }
        }

        for unreadable in [false, true] {
            fixture { directory, _, store in
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                let legacyData = unreadable ? Data("Keep these notes".utf8) : Data([0xff, 0xfe, 0xff])
                try legacyData.write(to: legacyURL)
                if unreadable { try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: legacyURL.path) }
                defer { try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyURL.path) }
                suite.expect((try? store.load(defaultName: "Scratchpad", retention: .day, now: now)) == nil
                        && !store.save(empty), "unreadable or invalid legacy text blocks saving")
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyURL.path)
                suite.expect(try Data(contentsOf: legacyURL) == legacyData,
                       "failed legacy reads preserve the exact original bytes")
                suite.expect(!manager.fileExists(atPath: directory.appendingPathComponent("Scratchpad.json").path),
                       "failed legacy reads never create an empty replacement")
            }
        }

        fixture { directory, _, store in
            let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
            try Data("Older notes".utf8).write(to: legacyURL)
            let migrated = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            let saved = try Data(contentsOf: directory.appendingPathComponent("Scratchpad.json"))
            suite.expect(migrated.pads[0].text == "Older notes"
                    && ScratchpadDocument.decoded(saved, defaultName: "Scratchpad") == migrated
                    && !manager.fileExists(atPath: legacyURL.path),
                   "valid legacy text is removed only after its replacement is verified")
        }

        fixture { directory, _, store in
            let url = directory.appendingPathComponent("Scratchpad.json")
            try originalData.write(to: url)
            let loaded = try store.load(defaultName: "Scratchpad", retention: .day, now: now)
            let saved = try Data(contentsOf: url)
            suite.expect(loaded.pads[0].text.isEmpty
                    && ScratchpadDocument.decoded(saved, defaultName: "Scratchpad") == loaded,
                   "retention still clears expired notes after a successful read")
        }

        fixture { _, defaults, _ in
            defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
            var unavailable = ScratchpadStore(directoryURL: nil, defaults: defaults)
            suite.expect((try? unavailable.load(defaultName: "Scratchpad", retention: .never, now: now)) == nil
                    && !unavailable.save(empty)
                    && defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData,
                   "an unavailable private container never discards stored notes")
        }
    }
}

/// A real pad over a directory of its own. Every call it makes outside
/// itself is recorded instead: warnings, autosaves, save dialogs, activation
/// and main-queue work. No dialog opens and nothing is written outside the
/// directory.
final class ScratchpadHarness {
    final class Window: IslandWindowing {
        var isVisible = true
        var level = NSWindow.Level(rawValue: 26)
        var focusCount = 0
        func makeKey() { focusCount += 1 }
    }

    final class Dialog {
        /// Where it was begun on its own, if it was.
        var level: NSWindow.Level?
        var focused = false
        var modalCalls = 0
        var response: NSApplication.ModalResponse = .cancel
        var url: URL?
        var completion: ((NSApplication.ModalResponse, URL?) -> Void)?

        func finish(_ response: NSApplication.ModalResponse) {
            let callback = completion
            completion = nil
            callback?(response, url)
        }
    }

    let directory: URL
    private let suiteName = "com.vitruviansoftware.vitruvian.tests.scratchpad-service.\(UUID().uuidString)"
    var island: Window?
    var warnings: [String] = []
    var autosaves: [(delay: TimeInterval, work: DispatchWorkItem)] = []
    var dialogs: [Dialog] = []
    var activations = 0
    var jobs: [@MainActor () -> Void] = []
    private(set) var service: ScratchpadService!

    init(root: URL) {
        directory = root.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: suiteName)!
        service = ScratchpadService(environment: .init(
            makeStore: { [unowned self] in ScratchpadStore(directoryURL: self.directory, defaults: defaults) },
            showWarning: { [unowned self] in self.warnings.append($0) },
            schedule: { [unowned self] delay, work in self.autosaves.append((delay, work)) },
            makeExportDialog: { [unowned self] _ in
                let dialog = Dialog()
                self.dialogs.append(dialog)
                return .init(beginAbove: { level, completion in
                    dialog.level = level
                    dialog.completion = completion
                }, makeKeyAndOrderFront: { dialog.focused = true },
                runModal: {
                    dialog.modalCalls += 1
                    return (dialog.response, dialog.url)
                })
            },
            islandWindow: { [unowned self] in self.island },
            activate: { [unowned self] in self.activations += 1 },
            main: { [unowned self] in self.jobs.append($0) }))
    }

    /// Loads the document the way a settings backup asks for it.
    func load() {
        service.prepareForSettingsBackup()
    }

    /// The autosaves that were not cancelled run, as the main queue would.
    func runAutosaves() {
        while !autosaves.isEmpty {
            let work = autosaves.removeFirst().work
            if !work.isCancelled { work.perform() }
        }
    }

    func drain() {
        while !jobs.isEmpty { jobs.removeFirst()() }
    }

    /// A file where the store's directory goes, so every write fails.
    func breakStore() {
        try? FileManager.default.removeItem(at: directory)
        _ = FileManager.default.createFile(atPath: directory.path, contents: nil)
    }

    func repairStore() {
        try? FileManager.default.removeItem(at: directory)
    }

    func savedDocument() -> ScratchpadDocument? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("Scratchpad.json")) else { return nil }
        return try? JSONDecoder().decode(ScratchpadDocument.self, from: data)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

/// The production export runs on a real pad whose dialogs, island and
/// application are doubles.
enum ScratchpadExportContract {
    typealias Harness = ScratchpadHarness

    static func run(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for fromIsland in [true, false] {
                for response in [NSApplication.ModalResponse.cancel, .OK] {
                    let pad = Harness(root: root)
                    defer { pad.cleanUp() }
                    let island = Harness.Window()
                    let floating = Harness.Window()
                    pad.island = island
                    pad.load()
                    pad.service.text = "Notes to export"
                    let host = fromIsland ? island : floating
                    let destination = root.appendingPathComponent("notes.txt")
                    try "Previous file".write(to: destination, atomically: true, encoding: .utf8)
                    pad.service.exportText(suggestedName: "Notes.txt", from: host)
                    guard let dialog = pad.dialogs.last else {
                        suite.expect(false, "export prepares its save dialog")
                        continue
                    }
                    suite.expect(pad.service.modalInteractionActive
                                 && pad.savedDocument()?.pads.first?.text == "Notes to export",
                                 "export protects its document while a dialog is pending")
                    pad.service.exportText(suggestedName: "Duplicate.txt", from: host)
                    suite.expect(pad.dialogs.count == 1, "a pending export cannot open a second dialog")
                    dialog.url = destination
                    dialog.response = response
                    pad.service.text = "A later edit"
                    suite.expect(pad.activations == 1, "export activates the app for the dialog's input")
                    if !fromIsland {
                        suite.expect(dialog.level == nil && dialog.modalCalls == 0,
                                     "the floating pad's dialog waits for the next turn and stays its own")
                        pad.drain()
                        suite.expect(dialog.modalCalls == 1 && floating.focusCount == 1 && island.focusCount == 0,
                                     "floating-pad export returns focus only to its own host")
                    } else {
                        suite.expect(dialog.focused && dialog.modalCalls == 0
                                     && (dialog.level?.rawValue ?? .min) > island.level.rawValue,
                                     "island export opens its own dialog above its host instead of attaching or opening behind it")
                        dialog.finish(response)
                        suite.expect(island.focusCount == 0, "completion defers focus until dismissal finishes")
                        pad.drain()
                        suite.expect(island.focusCount == 1 && floating.focusCount == 0,
                                     "island export returns focus to the island")
                    }
                    suite.expect(!pad.service.modalInteractionActive, "completion releases the export guard")
                    let saved = try String(contentsOf: destination, encoding: .utf8)
                    suite.expect(saved == (response == .OK ? "A later edit" : "Previous file"),
                                 "export writes the pad as it is when the save is confirmed and cancellation never writes")
                }
            }
            try editsWhileOpen(suite, root: root)
            let pad = Harness(root: root)
            defer { pad.cleanUp() }
            let island = Harness.Window()
            pad.island = island
            pad.load()
            pad.service.text = "Notes to export"
            pad.service.exportText(suggestedName: "Notes.txt", from: island)
            island.isVisible = false
            pad.dialogs.last?.finish(.cancel)
            pad.drain()
            suite.expect(island.focusCount == 0 && !pad.service.modalInteractionActive,
                         "closing the island during export does not resurrect its window")
            pad.service.exportText(suggestedName: "Hidden.txt", from: island)
            suite.expect(pad.dialogs.count == 1 && !pad.service.modalInteractionActive,
                         "an action delivered after its host disappeared cannot open a dialog")
            pad.service.exportText(suggestedName: "Nowhere.txt")
            suite.expect(pad.dialogs.count == 1, "with no host window and no floating pad, export opens nothing")
            island.isVisible = true
            pad.service.text = ""
            pad.service.exportText(suggestedName: "Empty.txt", from: island)
            suite.expect(pad.dialogs.count == 1, "an empty pad has nothing to export")
        } catch {
            suite.expect(false, "export fixture completes: \(error)")
        }
    }

    /// The island's dialog does not block its pad. Choosing another tab
    /// meanwhile still saves the pad that asked; closing that pad reports the
    /// failed export and writes nothing.
    private static func editsWhileOpen(_ suite: TestSuite, root: URL) throws {
        let island = Harness.Window()
        let switching = Harness(root: root)
        defer { switching.cleanUp() }
        switching.island = island
        switching.load()
        switching.service.text = "Notes to export"
        let chosen = root.appendingPathComponent("chosen.txt")
        switching.service.exportText(suggestedName: "Notes.txt", from: island)
        switching.service.createPad(defaultName: "Notes")
        switching.service.text = "Another pad"
        switching.dialogs.last?.url = chosen
        switching.dialogs.last?.finish(.OK)
        switching.drain()
        let exported = try String(contentsOf: chosen, encoding: .utf8)
        suite.expect(switching.service.pads.count == 2 && exported == "Notes to export",
                     "choosing another tab during export still saves the pad that asked")

        let closing = Harness(root: root)
        defer { closing.cleanUp() }
        closing.island = island
        closing.load()
        closing.service.text = "Notes to export"
        let asked = closing.service.selectedPadID
        let kept = root.appendingPathComponent("kept.txt")
        try "Previous file".write(to: kept, atomically: true, encoding: .utf8)
        closing.service.exportText(suggestedName: "Notes.txt", from: island)
        closing.service.createPad(defaultName: "Notes")
        let closed = asked.map { closing.service.closePad($0) } ?? false
        closing.dialogs.last?.url = kept
        closing.dialogs.last?.finish(.OK)
        closing.drain()
        let untouched = try String(contentsOf: kept, encoding: .utf8)
        suite.expect(closed && untouched == "Previous file"
                     && closing.warnings == [FeatureStrings.scratchpad(L10n.shared.language).exportFailed],
                     "a pad closed while its dialog is open reports the failed export and writes nothing")
    }
}

/// The production save path runs on a real store whose directory can be
/// made unwritable.
enum ScratchpadSaveContract {
    static func run(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pad = ScratchpadHarness(root: root)
        defer {
            pad.cleanUp()
            try? FileManager.default.removeItem(at: root)
        }
        let message = FeatureStrings.scratchpad(L10n.shared.language).saveFailed
        pad.load()
        pad.service.text = "Unsaved"
        pad.service.text = "Unsaved notes"
        suite.expect(pad.autosaves.count == 2 && pad.autosaves[0].work.isCancelled
                     && !pad.autosaves[1].work.isCancelled && pad.autosaves[1].delay == 0.8,
                     "each edit replaces the autosave waiting before it with one shortly after")
        pad.breakStore()
        pad.runAutosaves()
        suite.expect(pad.service.saveFailed, "a failed autosave marks the pad as unsaved")
        pad.service.createPad(defaultName: "Notes")
        suite.expect(pad.service.saveFailed && pad.warnings.isEmpty,
                     "a failed tab write keeps the warning in place without the HUD")
        suite.expect(pad.service.pads.count == 1 && pad.service.text == "Unsaved notes",
                     "a tab action whose write failed leaves the notes as they were")
        pad.service.commitEdits()
        suite.expect(pad.warnings == [message], "a failed write as the pad or the island closes shows the HUD")
        pad.repairStore()
        pad.service.createPad(defaultName: "Notes")
        suite.expect(!pad.service.saveFailed && pad.service.pads.count == 2,
                     "a failed write does not stop the next one, and its success clears the warning")
        suite.expect(pad.savedDocument()?.pads.first?.text == "Unsaved notes",
                     "edits kept in memory through failed writes reach the disk once one succeeds")
        pad.service.text = "Saved on close"
        pad.service.commitEdits()
        suite.expect(pad.autosaves.last?.work.isCancelled == true
                     && pad.savedDocument()?.pads.last?.text == "Saved on close",
                     "closing writes the latest edit at once and drops the autosave waiting for it")
        suite.expect(pad.warnings.count == 1, "a successful write on close shows no HUD")
    }
}
