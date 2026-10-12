// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// What the screens for tools from outside say, checked as the plain values
/// the views show. No view is drawn: how a screen looks in the app is a
/// check a person makes by hand.
enum ExternalToolScreensTests {
    static func run(_ suite: TestSuite) {
        agreement(suite)
        anUpdate(suite)
        refusalWords(suite)
        asWritten(suite)
        rows(suite)
        detailAndRemoval(suite)
        beforeAgreeing(suite)
        removalChoices(suite)
        switchAndOwnWords(suite)
        ownWordsInAlerts(suite)
    }

    static let id = ExternalToolTests.id
    static let english = FeatureStrings.externalTools(.enUS)

    static func content(_ offer: ToolOffer, _ language: AppLanguage = .enUS, home: String = "/Users/me",
                        hasSymbol: @escaping (String) -> Bool = { _ in true }) -> ToolAgreementContent {
        ToolAgreementContent(offer: offer, language: language, strings: FeatureStrings.externalTools(language),
                             cancel: "Cancel", home: home, hasSymbol: hasSymbol)
    }

    /// The sheet for a tool nobody has added yet.
    static func agreement(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        guard case .success(let offer) = bench.store.offer(from: bench.folder()) else {
            suite.expect(false, "the design's example is offered")
            return
        }
        let sheet = content(offer, home: bench.root.resolvingSymlinksInPath().path)
        suite.expect(sheet.title == "Add “Deploys” to Vitruvian?" && sheet.byline == "Acme · 1.2.0"
                         && sheet.summary == "Copies the address of your latest deploy."
                         && sheet.from == "From ~/picked" && sheet.symbol == "shippingbox" && !sheet.isUpdate,
                     "the sheet names the tool, its publisher and version as the tool wrote them, "
                         + "and the folder it would be added from")
        suite.expect(sheet.headline == "This tool can do anything Vitruvian can on this Mac."
                         && sheet.detail.contains("Vitruvian does not limit or check what it does.")
                         && sheet.detail.contains("Add it only if you trust who made it.")
                         && sheet.ownWords == english.agreeOwnWords,
                     "it says, in the app's own words, that the tool can do anything the app can, "
                         + "and that the tool's words are the tool's")
        suite.expect(sheet.commands == ["Copy latest deploy"] && sheet.commandsTitle == "Commands"
                         && sheet.uses == ["Write to the clipboard", "Show messages and play the alert sound",
                                           "Save its own settings"]
                         && sheet.usesTitle == "What it says it uses"
                         && sheet.usesNote == "This list comes from the tool. It is not a limit on what the tool can do.",
                     "it lists the commands the tool adds, and what the tool says it uses, in the manifest's order, "
                         + "as what the tool says and not as a limit")
        suite.expect(ToolAgreementContent.defaultChoice == .cancel && sheet.agree == "Add Tool" && sheet.cancel == "Cancel"
                         && sheet.versions == nil && sheet.changed == nil && sheet.keepsData == nil,
                     "Return presses Cancel, never the button that adds the tool")

        let french = content(offer, .fr, home: "/nowhere")
        suite.expect(french.title == "Ajouter «\u{00A0}Déploiements\u{00A0}» à Vitruvian\u{00A0}?"
                         && french.from == "Depuis " + offer.folder.path
                         && french.headline == FeatureStrings.externalTools(.fr).agreeHeadline
                         && french.commands == ["Copy latest deploy"],
                     "the app's words are in the person's language; the tool's are as the tool wrote them, "
                         + "in that language where it wrote one and in English where it did not")
        suite.expect(content(offer, hasSymbol: { _ in false }).symbol == "puzzlepiece.extension",
                     "an icon this Mac does not have draws as the plain puzzle piece")
        suite.expect(ToolAgreementContent.abbreviated("/Users/me", home: "/Users/me") == "~"
                         && ToolAgreementContent.abbreviated("/Users/me/tools/x", home: "/Users/me") == "~/tools/x"
                         && ToolAgreementContent.abbreviated("/Users/meme/x", home: "/Users/me") == "/Users/meme/x"
                         && ToolAgreementContent.abbreviated("/opt/x", home: "") == "/opt/x",
                     "the folder is shown with the home folder as a tilde, and no other folder shortened")

        let silent = ExternalToolStoreTests.Bench()
        defer { silent.close() }
        let bare = ExternalToolManifestTests.file(#"{"uses": null, "contributes": null, "description": null}"#)
        guard case .success(let little) = silent.store.offer(from: silent.folder(manifest: bare)) else {
            suite.expect(false, "a tool that lists no service and no command is offered")
            return
        }
        let plain = content(little)
        suite.expect(plain.uses.isEmpty && plain.commands.isEmpty && plain.summary == nil
                         && plain.headline == sheet.headline && plain.detail == sheet.detail,
                     "a tool that says it uses nothing gets the same statement: the list is not what makes it true")
        suite.expect(!silent.exists(silent.support) && silent.store.listed.isEmpty,
                     "and building what the sheet says adds nothing")
        suite.expect(sheet.listRows == 4 && !sheet.listsScroll && plain.listRows == 0 && !plain.listsScroll,
                     "the design's example has four rows in its two lists, drawn whole")

        // The most a tool may have: 32 commands, and every service.
        let full = ExternalToolStoreTests.Bench()
        defer { full.close() }
        let commands = ExternalToolManifestTests.list(32) {
            #"{"id": "c\#($0)", "title": {"en": "Command \#($0)"}, "surfaces": ["commandBar"]}"#
        }
        let most = ExternalToolManifestTests.file(#"""
            {"uses": ["notify", "open", "clipboard.read", "clipboard.write", "keystrokes", "processes", "storage"],
             "contributes": {"commands": \#(commands)}}
            """#)
        guard case .success(let large) = full.store.offer(from: full.folder(manifest: most)) else {
            suite.expect(false, "a tool with 32 commands and every service is offered")
            return
        }
        let long = content(large)
        suite.expect(long.commands.count == 32 && long.commands.first == "Command 0" && long.commands.last == "Command 31"
                         && long.uses.count == 7 && Set(long.uses).count == 7 && long.listRows == 39 && long.listsScroll
                         && ToolAgreementContent.rowsDrawnWhole == 6 && ToolAgreementContent.listsHeight == 200
                         && long.headline == sheet.headline && long.agree == sheet.agree,
                     "a tool with the most a tool may have, 32 commands and 7 services, has 39 rows: "
                         + "they scroll in a region of a fixed height, and the statement and the buttons are not in it")
    }

    /// The sheet for a tool that is added already.
    static func anUpdate(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        let picked = bench.folder()
        bench.add(picked)
        guard case .success(let same) = bench.store.offer(from: picked) else { return }
        let unchanged = content(same)
        suite.expect(unchanged.isUpdate && unchanged.title == "Update “Deploys”?" && unchanged.agree == "Update Tool"
                         && unchanged.versions == "You have version 1.2.0. This folder has version 1.2.0."
                         && unchanged.changed == nil && unchanged.keepsData == "What the tool saved is kept."
                         && unchanged.headline == english.agreeHeadline && unchanged.detail == english.agreeDetail,
                     "choosing an added tool's folder again asks again, with both versions and the same statement")

        try? ExternalToolManifestTests.file(#"{"version": "1.3.0", "uses": ["notify", "keystrokes"]}"#)
            .write(to: picked.appendingPathComponent("vitruvian-tool.json"))
        guard case .success(let newer) = bench.store.offer(from: picked) else { return }
        let changed = content(newer)
        suite.expect(changed.versions == "You have version 1.2.0. This folder has version 1.3.0."
                         && changed.changed == "What the tool says about itself has changed since you agreed. Read it again."
                         && changed.uses == ["Show messages and play the alert sound",
                                             "Paste and press menu commands in other apps"]
                         && ToolAgreementContent.defaultChoice == .cancel,
                     "when the manifest is not the one agreed to, the sheet says so and shows what it says now")
    }

    /// Each reason a folder is not added, as the sentence a person reads.
    static func refusalWords(_ suite: TestSuite) {
        func message(_ refusal: ExternalToolStore.Refusal, _ language: AppLanguage = .enUS,
                     numbers: String = "en_US") -> ToolRefusalMessage {
            ToolRefusalMessage(refusal, language: language, strings: FeatureStrings.externalTools(language),
                               numbers: Locale(identifier: numbers))
        }
        suite.expect(message(.manifest(.noManifest)).title == "This folder can’t be added"
                         && message(.manifest(.noManifest)).message == "It has no vitruvian-tool.json file, so it is not a tool."
                         && message(.manifest(.noManifest)).command == nil,
                     "a folder that is no tool is refused in one plain sentence")
        suite.expect(message(.manifest(.invalid(.unknownService("camera")))).message
                         == #"Its vitruvian-tool.json file has a mistake. Tell whoever made the tool: unknownService("camera")"#
                         && message(.manifest(.notOfferedHere("island"))).message
                         == "It needs something this version of Vitruvian does not have: island",
                     "a manifest that breaks a rule names the rule, for whoever made the tool")
        let program = "Its program, bin/deploys, is missing or macOS will not run it."
        suite.expect(message(.manifest(.programMissing("bin/deploys"))).message == program
                         && message(.manifest(.programOutsideFolder("bin/deploys"))).message == program
                         && message(.manifest(.programNotExecutable("bin/deploys"))).message == program,
                     "a program that cannot be started is named by its path")
        let quarantined = message(.quarantined(URL(fileURLWithPath: "/Users/me/Down loads/it's")))
        suite.expect(quarantined.message.hasPrefix("macOS has quarantined this folder because it was downloaded. "
                                                       + "Vitruvian will not clear that for you.")
                         && quarantined.command == #"xattr -dr com.apple.quarantine '/Users/me/Down loads/it'\''s'"#,
                     "a quarantined folder says the app will not clear it, and gives the command for the person to run")
        suite.expect(message(.tooBig(bytes: 256 * 1_048_576, items: 10_000)).message
                         == "The folder is too large. A tool can hold up to 256 MB and 10,000 files."
                         && message(.tooBig(bytes: 256 * 1_048_576, items: 10_000), .de, numbers: "de_DE").message
                         == "Der Ordner ist zu groß. Ein Werkzeug darf höchstens 256 MB und 10.000 Dateien enthalten.",
                     "a folder that is too large says the most a tool may hold, the count written the region's way")
        let rest: [ExternalToolStore.Refusal] = [.noSupportFolder, .files(.notCopied), .files(.insideTheApp),
                                                 .files(.linkedElsewhere), .alreadyInstalled(id),
                                                 .changedSinceOffered, .notRemembered]
        suite.expect(rest.allSatisfy { message($0).message == english.refusalNotAdded && message($0).command == nil },
                     "everything else says that nothing was added")
    }

    /// A tool's words are shown as written, an update is judged by the
    /// manifest's bytes alone, and the command for a quarantined folder is
    /// safe whatever the folder is called.
    static func asWritten(_ suite: TestSuite) {
        let loud = ExternalToolStoreTests.Bench()
        defer { loud.close() }
        let marked = ExternalToolManifestTests.file(
            #"{"name": {"en": "**Bold** [free](https://example.invalid)"}, "publisher": "_Acme_ `x`"}"#)
        if case .success(let offer) = loud.store.offer(from: loud.folder(manifest: marked)) {
            suite.expect(content(offer).title == "Add “**Bold** [free](https://example.invalid)” to Vitruvian?"
                             && content(offer).byline == "_Acme_ `x` · 1.2.0",
                         "a name with markdown and a link in it is carried as the plain text the tool wrote")
        } else {
            suite.expect(false, "a name with markdown and a link in it is carried as the plain text the tool wrote")
        }

        // The old tool runs on while the person reads the sheet.
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        let picked = bench.folder()
        bench.add(picked)
        bench.registry.run(ExternalToolStoreTests.copy)
        bench.current.greets()
        let sent = bench.current.sent.count
        let copied = bench.files.appendingPathComponent("vitruvian-tool.json")
        let agreed = try? Data(contentsOf: copied)
        try? ExternalToolManifestTests.file(#"{"version": "1.3.0"}"#)
            .write(to: picked.appendingPathComponent("vitruvian-tool.json"))
        if case .success(let newer) = bench.store.offer(from: picked) {
            let sheet = content(newer)
            suite.expect(sheet.isUpdate && sheet.changed != nil && bench.store.listed.first?.standing == .running
                             && bench.runs.count == 1 && bench.current.sent.count == sent && !bench.current.inputClosed
                             && bench.store.installed[id]?.tool.version == "1.2.0"
                             && agreed != nil && (try? Data(contentsOf: copied)) == agreed,
                         "the tool that is added runs on, untouched, until the person agrees to the update")
        } else {
            suite.expect(false, "the tool that is added runs on, untouched, until the person agrees to the update")
        }

        // One byte of the manifest, and nothing else, makes it changed.
        let exact = ExternalToolStoreTests.Bench()
        defer { exact.close() }
        let folder = exact.folder()
        exact.add(folder)
        try? Data("another program".utf8).write(to: folder.appendingPathComponent("bin/deploys"))
        let unchanged = (try? exact.store.offer(from: folder).get()).map { content($0).changed }
        let file = folder.appendingPathComponent("vitruvian-tool.json")
        var spaced = (try? Data(contentsOf: file)) ?? Data()
        spaced.append(0x20)
        try? spaced.write(to: file)
        let oneByte = (try? exact.store.offer(from: folder).get()).map { content($0) }
        suite.expect(unchanged == .some(nil) && oneByte?.changed == english.updateChanged
                         && oneByte?.versions == "You have version 1.2.0. This folder has version 1.2.0.",
                     "the sheet says the tool changed exactly when its manifest's bytes are not the ones agreed to: "
                         + "one added space is enough, and another program is not")

        // The quoted folder is one word to a shell, whatever it holds.
        let paths = ["/Users/me/Down loads/it's", "/tmp/a\nb", "/tmp/$(touch x) `id` \\ \" ; rm -rf ~", "/tmp/''", "/tmp/-n"]
        var echoed: [String] = []
        for path in paths {
            let shell = Process()
            let output = Pipe()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", "printf '%s' " + ToolRefusalMessage.quoted(path)]
            shell.standardOutput = output
            guard (try? shell.run()) != nil else { continue }
            let bytes = output.fileHandleForReading.readDataToEndOfFile()
            shell.waitUntilExit()
            echoed.append(String(decoding: bytes, as: UTF8.self))
        }
        let newline = ToolRefusalMessage(.quarantined(URL(fileURLWithPath: "/tmp/a\nb c")), language: .enUS,
                                         strings: english)
        suite.expect(echoed == paths && newline.command == "xattr -dr com.apple.quarantine '/tmp/a\nb c'",
                     "a quote, a space, a newline and a command in a folder's name reach a shell as one plain word")
    }

    /// The rows of the Features hub's section, one for each added tool.
    static func rows(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        func rows(_ language: AppLanguage = .enUS) -> [ExternalToolRow] {
            ExternalToolRow.all(store: bench.store, language: language, strings: FeatureStrings.externalTools(language))
        }
        suite.expect(rows().isEmpty, "with no tool added the section has no row: it shows its one quiet line")

        let picked = bench.folder()
        bench.add(picked)
        let other = bench.folder("other", manifest: ExternalToolManifestTests.file(
            #"{"id": "com.acme.other", "name": {"en": "Other"}, "icon": "no.such.symbol"}"#))
        bench.add(other)
        suite.expect(rows().map(\.name) == ["Deploys", "Other"] && rows(.fr).map(\.name) == ["Déploiements", "Other"]
                         && rows()[0].byline == "Acme · 1.2.0" && rows()[0].symbol == "shippingbox"
                         && rows()[1].symbol == "puzzlepiece.extension"
                         && rows().allSatisfy { $0.isOn && $0.status == .quiet && $0.statusText == nil },
                     "each added tool has a row, in the order added, by the name it gives itself in the person's "
                         + "language; a tool waiting for its first command says nothing about how it stands")

        bench.registry.run(ExternalToolTests.copy)
        suite.expect(rows()[0].status == .running && rows()[0].statusText == "Running" && rows()[1].status == .quiet,
                     "a tool whose program is up says Running")
        bench.current.ends(1)
        suite.expect(rows()[0].status == .stopped(canStartAgain: false) && rows()[0].statusText == "Stopped working",
                     "a tool that crashed says so, with no button while the app will start it again by itself")
        for wait in [1.0, 2.0] {
            bench.clock.advance(by: wait)
            bench.registry.run(ExternalToolTests.copy)
            bench.current.ends(1)
        }
        suite.expect(rows()[0].status == .stopped(canStartAgain: true) && rows()[0].statusText == "Stopped working",
                     "once the app has given up on it, the row offers Start Again")
        bench.store.startAgain(id)
        suite.expect(rows()[0].status == .quiet, "and after Start Again it waits for its next command")

        bench.store.setOn(id, false)
        suite.expect(rows()[0].isOn == false && rows()[0].status == .quiet && rows()[0].name == "Deploys"
                         && rows().count == 2,
                     "a tool that is switched off keeps its row, with its switch off")

        try? Data("{}".utf8).write(to: bench.files.appendingPathComponent("vitruvian-tool.json"))
        let next = bench.relaunched()
        next.store.restore()
        let held = ExternalToolRow.all(store: next.store, language: .enUS, strings: english)
        suite.expect(held[0].status == .changed && held[0].name == "Deploys" && held[0].byline == "Acme · 1.2.0"
                         && held[0].statusText == "Changed since you added it. Update it to use it again."
                         && held[1].status == .quiet,
                     "a tool whose copy is not what was agreed to says so, under the name and version agreed to")
    }

    /// A tool's detail view, and the question before it is removed.
    static func detailAndRemoval(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        bench.add(bench.folder())
        guard let listed = bench.store.listed.first else { return }
        let home = bench.root.resolvingSymlinksInPath().path
        let detail = ExternalToolDetail(listed, files: bench.store.folder(of: id), language: .enUS, strings: english,
                                        home: home)
        suite.expect(detail.row.name == "Deploys" && detail.summary == "Copies the address of your latest deploy."
                         && detail.commands == ["Copy latest deploy"] && detail.offersShortcuts
                         && detail.uses == ["Write to the clipboard", "Show messages and play the alert sound",
                                            "Save its own settings"]
                         && detail.usesNote == english.usesNote,
                     "a tool's detail lists its commands and what it says it uses, with the same note as the sheet, "
                         + "and offers the Shortcuts page when a command may have a shortcut")
        suite.expect(detail.files == "~/support/Tools/com.acme.deploys"
                         && bench.store.folder(of: ToolID("com.acme.other")!) == nil,
                     "it says where the app's copy of the tool is, and has no folder for a tool nobody added")

        bench.store.setOn(id, false)
        if let off = bench.store.listed.first {
            let quiet = ExternalToolDetail(off, files: bench.store.folder(of: id), language: .enUS, strings: english,
                                           home: home)
            suite.expect(quiet.commands == ["Copy latest deploy"] && !quiet.offersShortcuts,
                         "a tool that is switched off still says what it would add, and offers no shortcut: "
                             + "it has no command to give one")
        }

        let removal = ToolRemovalContent(name: detail.row.name, strings: english, cancel: "Cancel")
        suite.expect(removal.title == "Remove “Deploys”?"
                         && removal.message == "Vitruvian deletes its copy of the tool. The folder you added it from is not touched."
                         && removal.keepData == "Remove, Keep What It Saved"
                         && removal.deleteData == "Remove and Delete What It Saved" && removal.cancel == "Cancel",
                     "removing a tool asks first, says what is deleted and what is not, and offers to keep what it saved")
        suite.expect(ToolRemovalContent.defaultChoice == .cancel, "Return presses Cancel there too")
    }

    /// From the folder picker to the sheet: nothing is copied, recorded or
    /// started until the person agrees.
    static func beforeAgreeing(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        func untouched() -> Bool {
            !bench.exists(bench.support) && bench.store.listed.isEmpty && bench.store.installed.isEmpty
                && bench.runs.isEmpty && bench.started.isEmpty && bench.registry.tool(id) == nil
                && bench.host.manifest(for: id) == nil
        }
        suite.expect(ToolPicked.after(nil, store: bench.store) == .nothing && untouched(),
                     "closing the folder picker without choosing asks nothing and changes nothing")

        let empty = bench.root.appendingPathComponent("empty", isDirectory: true)
        try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        suite.expect(ToolPicked.after(empty, store: bench.store) == .refuse(.manifest(.noManifest)) && untouched(),
                     "a folder that is no tool is refused, and closing the refusal leaves nothing copied, recorded or started")

        guard case .ask(let offer) = ToolPicked.after(bench.folder(), store: bench.store) else {
            suite.expect(false, "a tool's folder is taken to the agreement sheet")
            return
        }
        // The sheet is made, read and cancelled: the offer is dropped.
        let sheet = content(offer)
        suite.expect(sheet.title == "Add “Deploys” to Vitruvian?" && untouched(),
                     "cancelling the agreement sheet leaves nothing copied, recorded or started")
        suite.expect(bench.store.add(ToolConsent(to: offer)).map(\.tool.manifest.id) == .success(id)
                         && bench.store.listed.map(\.id) == [id] && bench.exists(bench.files),
                     "only the consent the sheet's button makes adds the tool")
    }

    /// The two buttons that remove a tool, and which of them deletes what
    /// the tool saved.
    static func removalChoices(_ suite: TestSuite) {
        let removal = ToolRemovalContent(name: "Deploys", strings: english, cancel: "Cancel")
        suite.expect(removal.label(.keepData) == "Remove, Keep What It Saved"
                         && removal.label(.deleteData) == "Remove and Delete What It Saved"
                         && removal.label(.cancel) == "Cancel"
                         && ToolRemovalContent.Choice.cancel.deletesData == nil,
                     "each button of the question carries its own words, and Cancel removes nothing")

        func saved(after choice: ToolRemovalContent.Choice) -> (removed: Bool, data: Bool, preference: Bool)? {
            let bench = ExternalToolStoreTests.Bench()
            defer { bench.close() }
            bench.add(bench.folder())
            try? Data("kept".utf8).write(to: bench.data.appendingPathComponent("saved"))
            bench.box.values["com.acme.deploys/project"] = "api"
            guard let deletingData = choice.deletesData else { return nil }
            bench.store.remove(id, deletingData: deletingData)
            return (bench.store.listed.isEmpty && !bench.exists(bench.files),
                    bench.exists(bench.data.appendingPathComponent("saved")),
                    bench.box.values["com.acme.deploys/project"] != nil)
        }
        let kept = saved(after: .keepData)
        suite.expect(kept?.removed == true && kept?.data == true && kept?.preference == true,
                     "the button that says Keep What It Saved removes the tool and keeps its data folder and its settings")
        let deleted = saved(after: .deleteData)
        suite.expect(deleted?.removed == true && deleted?.data == false && deleted?.preference == false,
                     "the button that says Delete What It Saved removes the tool with its data folder and its settings")
    }

    /// A row's switch, across launches; and a tool's own words and log,
    /// which are carried as plain text and cannot grow a screen without end.
    static func switchAndOwnWords(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        bench.add(bench.folder())
        func row(_ bench: ExternalToolStoreTests.Bench) -> ExternalToolRow? {
            ExternalToolRow.all(store: bench.store, language: .enUS, strings: english).first
        }
        bench.registry.run(ExternalToolTests.copy)
        bench.current.greets()
        let running = row(bench)
        bench.store.setOn(id, false)
        suite.expect(running?.status == .running && running?.canSwitch == true
                         && row(bench)?.isOn == false && row(bench)?.status == .quiet && row(bench)?.canSwitch == true
                         && bench.current.inputClosed && !bench.registry.canRun(ExternalToolTests.copy),
                     "switching a running tool off stops its program and takes its command away; the switch still works")
        let next = bench.relaunched()
        next.store.restore()
        suite.expect(row(next)?.isOn == false && next.runs.isEmpty && !next.registry.canRun(ExternalToolTests.copy),
                     "a tool that was switched off is still off, and not started, at the next launch")
        next.store.setOn(id, true)
        suite.expect(row(next)?.isOn == true && row(next)?.status == .quiet && next.registry.canRun(ExternalToolTests.copy),
                     "switching it on brings its command back, and it waits for its first command")
        try? Data("{}".utf8).write(to: next.files.appendingPathComponent("vitruvian-tool.json"))
        let later = next.relaunched()
        later.store.restore()
        suite.expect(row(later)?.status == .changed && row(later)?.canSwitch == false && later.runs.isEmpty
                         && !later.registry.canRun(ExternalToolTests.copy),
                     "a tool that is held back has a switch that does nothing, and is never started")

        let loud = ExternalToolStoreTests.Bench()
        defer { loud.close() }
        let commands = ExternalToolManifestTests.list(32) {
            #"{"id": "c\#($0)", "title": {"en": "**Command** [\#($0)](https://example.invalid)"}, "surfaces": ["commandBar"]}"#
        }
        loud.add(loud.folder(manifest: ExternalToolManifestTests.file(#"""
            {"name": {"en": "**Bold** [free](https://example.invalid)"}, "publisher": "_Acme_ `x`",
             "description": {"en": "~~struck~~ <b>tag</b>"},
             "uses": ["notify", "open", "clipboard.read", "clipboard.write", "keystrokes", "processes", "storage"],
             "contributes": {"commands": \#(commands)}}
            """#)))
        if let listed = loud.store.listed.first {
            let detail = ExternalToolDetail(listed, files: loud.store.folder(of: listed.id), language: .enUS,
                                            strings: english, home: "/nowhere")
            suite.expect(detail.row.name == "**Bold** [free](https://example.invalid)"
                             && detail.row.byline == "_Acme_ `x` · 1.2.0" && detail.summary == "~~struck~~ <b>tag</b>"
                             && detail.commands.first == "**Command** [0](https://example.invalid)",
                         "markdown, a link and a tag in a tool's name, publisher, description and command titles "
                             + "reach the row and the detail as the plain text the tool wrote")
            suite.expect(detail.commands.count == 32 && detail.uses.count == 7 && detail.listRows == 39 && detail.listsScroll,
                         "a tool with the most a tool may have scrolls its two lists in the detail, as on the sheet")
        } else {
            suite.expect(false, "a tool with marked-up words and 32 commands is added")
        }
        let few = ExternalToolStoreTests.Bench()
        defer { few.close() }
        few.add(few.folder())
        if let listed = few.store.listed.first {
            let detail = ExternalToolDetail(listed, files: nil, language: .enUS, strings: english)
            suite.expect(detail.listRows == 4 && !detail.listsScroll && detail.files == nil,
                         "the design's example has four rows in the detail's two lists, drawn whole")
        }

        let lines = (1...1_000).map { "line \($0)" }.joined(separator: "\n")
        let shown = ExternalToolDetail.shownLog(lines).split(separator: "\n", omittingEmptySubsequences: false)
        let wide = ExternalToolDetail.shownLog(String(repeating: "é", count: 200_000) + "\nlast **line**")
        suite.expect(shown.count == ExternalToolDetail.logLines && shown.last == "line 1000" && shown.first == "line 801"
                         && wide.utf8.count <= ExternalToolDetail.logBytes && wide.hasSuffix("\nlast **line**")
                         && !wide.unicodeScalars.contains("\u{FFFD}")
                         && ExternalToolDetail.shownLog("one\n[two](x)") == "one\n[two](x)"
                         && ExternalToolDetail.shownLog("").isEmpty,
                     "the log a detail shows is the newest of what the tool wrote, at most so many lines and bytes, "
                         + "as plain text")
    }

    /// A tool's own words inside one of the app's sentences, in an alert or
    /// in the app's short on-screen message: one line, cut short, and with
    /// no character that turns the sentence round.
    static func ownWordsInAlerts(_ suite: TestSuite) {
        let limit = ToolOwnWords.limit
        let exact = String(repeating: "a", count: limit)
        suite.expect(limit == 120 && ToolOwnWords.oneLine("Deploys") == "Deploys" && ToolOwnWords.oneLine("") == ""
                         && ToolOwnWords.oneLine(exact) == exact
                         && ToolOwnWords.oneLine(exact + "b") == String(repeating: "a", count: limit - 1) + "…",
                     "a tool's words in an alert are shown whole up to 120 characters, and cut there with an ellipsis")
        let huge = ToolOwnWords.oneLine(String(repeating: "é", count: 50_000))
        let stacked = ToolOwnWords.oneLine("a" + String(repeating: "\u{301}", count: 50_000) + "b")
        suite.expect(huge.count == limit && huge.hasSuffix("…")
                         && stacked.unicodeScalars.count <= limit * ToolOwnWords.scalarsPerCharacter + 1
                         && stacked.hasSuffix("…"),
                     "tens of kilobytes of a tool's words become one short text, however the characters are built")
        suite.expect(ToolOwnWords.oneLine("a\nb\r\nc\u{2028}d\u{2029}e\tf\u{0}g\u{85}h\u{7F}i") == "a b  c d e f g h i",
                     "a line break, a tab and every other control character in a tool's words is shown as a space")
        let turners = ["\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", "\u{2066}", "\u{2067}",
                       "\u{2068}", "\u{2069}", "\u{200E}", "\u{200F}", "\u{061C}"]
        suite.expect(turners.allSatisfy { ToolOwnWords.oneLine("safe" + $0 + "gnp.exe") == "safegnp.exe" }
                         && ToolOwnWords.oneLine("שלום 👨‍👩‍👧‍👦 e\u{301}") == "שלום 👨‍👩‍👧‍👦 e\u{301}",
                     "the characters that turn a line of text round are taken out, so a tool's name cannot reorder "
                         + "the sentence it is put in; letters of any script, and an emoji made of several, stay")

        func message(_ refusal: ExternalToolStore.Refusal) -> String {
            ToolRefusalMessage(refusal, language: .enUS, strings: english, numbers: Locale(identifier: "en_US")).message
        }
        let long = String(repeating: "camera", count: 8_500)
        let hostile = "is\nland\u{202E}" + long
        let mistake = message(.manifest(.invalid(.unknownService(long))))
        let newer = message(.manifest(.notOfferedHere(hostile)))
        let program = message(.manifest(.programMissing("bin/\n\u{202E}" + long)))
        // The longest of the three sentences, and the most of a tool's words it may carry.
        let room = english.refusalMistakeFormat.count + limit
        suite.expect(long.utf8.count > 50_000 && [mistake, newer, program].allSatisfy { text in
                         text.count <= room && !text.contains("\n") && !text.unicodeScalars.contains("\u{202E}")
                     }
                         && mistake.hasPrefix(#"Its vitruvian-tool.json file has a mistake. Tell whoever made the tool: unknownService("cameracamera"#)
                         && mistake.hasSuffix("…")
                         && newer.hasPrefix("It needs something this version of Vitruvian does not have: is landcamera")
                         && program.hasPrefix("Its program, bin/ camera") && program.hasSuffix("…, is missing or macOS will not run it."),
                     "a manifest with a 50 KB service name, surface or program path is refused in one short line")

        let name = "De\nploys\u{202E}" + long
        let removal = ToolRemovalContent(name: name, strings: english, cancel: "Cancel")
        suite.expect(removal.title.hasPrefix("Remove “De ployscamera") && removal.title.hasSuffix("…”?")
                         && removal.title.count == english.removeTitle("").count + limit && !removal.title.contains("\n")
                         && !removal.title.unicodeScalars.contains("\u{202E}"),
                     "the question before a tool is removed names it in one short line, whatever the tool calls itself")

        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        let named = ExternalToolManifestTests.file(
            #"{"uses": [], "name": {"en": "Deploys", "fr": "Dé\nploie\u202Ements \#(String(repeating: "x", count: 4_000))"}}"#)
        let picked = bench.folder(manifest: named)
        bench.add(picked)
        bench.registry.run(ExternalToolTests.copy)
        bench.current.greets()
        bench.current.ends(1)
        let said = bench.said.first ?? ""
        let french = FeatureStrings.externalTools(.fr)
        suite.expect(bench.said.count == 1 && said.hasPrefix("exclamationmark.triangle: «\u{00A0}Dé ploiements xxx")
                         && said.hasSuffix("…\u{00A0}» a cessé de fonctionner") && !said.contains("\n")
                         && !said.unicodeScalars.contains("\u{202E}")
                         && said.count == "exclamationmark.triangle: ".count + french.stopped("").count + limit,
                     "the short message that says a tool stopped working names it in one short line too")

        if case .success(let offer) = bench.store.offer(from: picked) {
            let sheet = content(offer, .fr)
            suite.expect(sheet.isUpdate && sheet.title.hasPrefix("Mettre à jour «\u{00A0}Dé ploiements xxx")
                             && sheet.title.count == french.updateTitle("").count + limit
                             && !sheet.title.contains("\n") && !sheet.title.unicodeScalars.contains("\u{202E}"),
                         "the sheet's own sentence that names the tool is held to the same bound")
        } else {
            suite.expect(false, "the sheet's own sentence that names the tool is held to the same bound")
        }
    }
}
