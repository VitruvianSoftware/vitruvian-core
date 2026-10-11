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
}
