// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol

/// One tool from outside, as its row on the Extensions page shows it. Plain
/// values, so the row can be checked without drawing it.
package struct ExternalToolRow: Identifiable, Equatable {
    package enum Status: Equatable, Sendable {
        /// Nothing to say: switched off, or waiting for its first command.
        case quiet
        case running
        /// Its program ended without being asked to. `canStartAgain` once
        /// the app has given up on it, and only the person can start it.
        case stopped(canStartAgain: Bool)
        /// The app's copy is not what the person agreed to. It is not
        /// started, and its switch does nothing.
        case changed
    }

    /// What the row is badged as. A package that contributes panels, in any
    /// place, is an extension; one that only adds commands is a tool. A
    /// package that is held back has no manifest the app reads, so it reads
    /// as a tool until it is updated.
    package enum Kind: Equatable, Sendable {
        case extensionPackage
        case tool
    }

    package let id: ToolID
    /// The tool's name in the person's language, as the tool wrote it. For
    /// a tool that is held back, the name the person agreed to.
    package let name: String
    /// The publisher and the version, as the tool wrote them.
    package let byline: String
    package let symbol: String
    package let kind: Kind
    /// The pill beside the byline: "Extension" or "Tool", in the person's language.
    package let kindBadge: String
    package let isOn: Bool
    package let status: Status
    /// The words beside the row for its status; nil when there are none.
    package let statusText: String?
    /// "Update available", for a tool the catalog lists a newer version
    /// of; nil otherwise.
    package let updateText: String?
    /// The words on the row's Update button: "Update" for a tool from the
    /// catalog, "Update from the catalog" for one added from a folder, which
    /// the update moves onto the catalog; nil when the row has none.
    package let updateButton: String?
    /// What VoiceOver says for the row's Update button: the button and the
    /// tool's name, so a list of them is not read as "Update" each time; nil
    /// when the row has no Update button.
    package let updateSpoken: String?
    /// False for a tool that is held back: its switch does nothing until
    /// the person updates it from its folder.
    package var canSwitch: Bool { status != .changed }

    /// `updateAvailable` is true when the catalog lists a newer version of
    /// this tool, which `CatalogueWatch.update(for:)` says.
    package init(_ listed: ExternalToolStore.Listed, language: AppLanguage, strings: ExternalToolStrings,
                 updateAvailable: Bool = false,
                 hasSymbol: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }) {
        let agreed = listed.record.agreement
        id = listed.id
        updateText = updateAvailable ? strings.updateAvailable : nil
        let button = updateAvailable ? Self.updateWords(listed, strings: strings) : nil
        updateButton = button
        let name = listed.tool?.name.text(for: language.rawValue) ?? agreed.name
        self.name = name
        updateSpoken = button.map { ExtensionsPageContent.spoken($0, name: name) }
        byline = "\(listed.tool?.publisher ?? agreed.publisher) · \(listed.tool?.version ?? agreed.version)"
        let wanted = listed.tool?.manifest.tool.symbol ?? ExternalToolManifest.defaultSymbol
        symbol = hasSymbol(wanted) ? wanted : ExternalToolManifest.defaultSymbol
        kind = listed.tool?.panels.isEmpty == false ? .extensionPackage : .tool
        kindBadge = kind == .extensionPackage ? strings.kindExtension : strings.kindTool
        isOn = listed.record.isOn
        if listed.isHeld {
            status = .changed
            statusText = strings.statusChanged
        } else {
            switch listed.standing {
            case .starting?, .running?:
                status = .running
                statusText = strings.statusRunning
            case .waiting?:
                status = .stopped(canStartAgain: false)
                statusText = strings.statusStopped
            case .gaveUp?:
                status = .stopped(canStartAgain: true)
                statusText = strings.statusStopped
            case .off?, .resting?, .stopping?, nil:
                status = .quiet
                statusText = nil
            }
        }
    }

    /// The words on the button that installs the newer version from the
    /// catalog: "Update" for a tool from the catalog, and for one added from
    /// a folder, which the update moves onto the catalog, "Update from the
    /// catalog".
    package static func updateWords(_ listed: ExternalToolStore.Listed, strings: ExternalToolStrings) -> String {
        listed.record.catalogue == nil ? strings.updateFromCatalog : strings.updateNow
    }

    /// A row for each tool the person added, in the order they added them.
    @MainActor package static func all(store: ExternalToolStore, language: AppLanguage, strings: ExternalToolStrings,
                                       watch: CatalogueWatch? = nil) -> [ExternalToolRow] {
        store.listed.map {
            ExternalToolRow($0, language: language, strings: strings, updateAvailable: watch?.update(for: $0) != nil)
        }
    }
}

/// One of a tool's own settings, as its detail shows it: what its author
/// called it, and the control that fits its kind of value.
package struct ExternalToolSetting: Identifiable, Equatable {
    /// The control a setting is drawn with, holding its value.
    package enum Control: Equatable, Sendable {
        /// A switch, for yes or no.
        case toggle(Bool)
        /// A text field.
        case text(String)
        /// A number field that takes whole numbers.
        case whole(Int)
        /// A number field.
        case number(Double)
        /// A pop-up menu, for a text setting whose author gave options: the
        /// selected value, and the rows. The value is text, as for a field.
        case choice(String, [Choice])

        /// The value the control holds, as the store saves it.
        package var value: PreferenceDeclaration.Value {
            switch self {
            case .toggle(let isOn): return .bool(isOn)
            case .text(let text): return .string(text)
            case .whole(let number): return .int(number)
            case .number(let number): return .double(number)
            case .choice(let value, _): return .string(value)
            }
        }

        /// A menu's rows; nil for any other control.
        package var choices: [Choice]? {
            if case .choice(_, let choices) = self { return choices }
            return nil
        }

        /// The menu with `value` picked. Picking an option takes away the
        /// row that stood for a stored value that was none of them: only
        /// the person's pick replaces such a value, and once it has, the
        /// row has nothing to stand for. Any other control is as it was.
        package func picking(_ value: String) -> Control {
            guard case .choice(_, let choices) = self else { return self }
            return .choice(value, Choice.rows(selected: value, among: choices))
        }
    }

    /// One row of a menu: the value it stands for, and what it says.
    package struct Choice: Identifiable, Equatable, Sendable {
        /// What is saved, or sent, when the person picks it.
        package let value: String
        /// What the row says, as one short line of plain text.
        package let title: String
        /// True for the row that stands for a stored value that is none of
        /// the options, shown as written so that it is never lost unseen.
        package let isStored: Bool

        package var id: String { value }

        package init(value: String, title: String, isStored: Bool) {
            self.value = value
            self.title = title
            self.isStored = isStored
        }

        /// The rows of a menu: the options in order, each title cut to one
        /// line of `limit` characters. When `selected` is none of them, a
        /// first row holds it as written. The app never refuses such a
        /// value and never rewrites it.
        package static func menu(selected: String, options: [(value: String, title: String)],
                                 limit: Int) -> [Choice] {
            rows(selected: selected,
                 among: options.map { Choice(value: $0.value, title: ToolOwnWords.oneLine($0.title, limit: limit),
                                             isStored: false) },
                 limit: limit)
        }

        /// The rows a menu draws while `selected` is selected: the rows of
        /// `rows` that stand for options, and before them a row for
        /// `selected` when it is none of them. So what is selected is
        /// always one of the rows, and the row for a value that is no
        /// option's is there exactly while that value is selected.
        package static func rows(selected: String, among rows: [Choice],
                                 limit: Int = ManifestLimits.maxPreferenceTitleLength) -> [Choice] {
            let options = rows.filter { !$0.isStored }
            if !options.contains(where: { $0.value == selected }) {
                return [Choice(value: selected, title: ToolOwnWords.oneLine(selected, limit: limit), isStored: true)]
                    + options
            }
            return options
        }
    }

    /// The preference's id within the tool. It is never drawn.
    package let id: String
    /// The title its author gave it, in the person's language, as one
    /// short line of plain text.
    package let title: String
    package let control: Control
    /// True for a text setting whose author asked for a folder: a Choose…
    /// button beside its field picks one, and the folder's path is saved.
    /// A setting with options is a menu, and has no button.
    package let picksFolder: Bool

    package init(_ setting: ExternalToolStore.Setting, language: AppLanguage) {
        id = setting.id
        // The manifest's rules hold a title to this length already. It is
        // bounded again here, where it is drawn.
        title = ToolOwnWords.oneLine(setting.title.text(for: language.rawValue) ?? "",
                                     limit: ManifestLimits.maxPreferenceTitleLength)
        switch setting.value {
        case .bool(let isOn): control = .toggle(isOn)
        case .string(let text) where !setting.options.isEmpty:
            // The manifest's rules hold an option's title to a preference
            // title's length. It is bounded again here, where it is drawn.
            let options = setting.options.map { (value: $0.value, title: $0.title.text(for: language.rawValue) ?? $0.value) }
            control = .choice(text, Choice.menu(selected: text, options: options,
                                                limit: ManifestLimits.maxPreferenceTitleLength))
        case .string(let text): control = .text(text)
        case .int(let number): control = .whole(number)
        case .double(let number): control = .number(number)
        }
        if case .text = control { picksFolder = setting.picker == .folder } else { picksFolder = false }
    }
}

/// What a tool's detail view says, beyond its row.
package struct ExternalToolDetail: Equatable {
    package let row: ExternalToolRow
    /// The tool's own sentence about itself.
    package let summary: String?
    package let commandsTitle: String
    package let commands: [String]
    package let usesTitle: String
    package let uses: [String]
    package let usesNote: String
    /// Where the app's copy of the tool is, with a tilde for the home
    /// folder; nil when there is none.
    package let files: String?
    /// True when one of its commands may have a shortcut, which the person
    /// records on the Shortcuts page.
    package let offersShortcuts: Bool
    /// The button that installs the newer version from the catalog; nil when
    /// there is none.
    package let updateNow: String?
    /// One of the tool's windows, as the detail lists it under its commands.
    package struct Window: Identifiable, Equatable, Sendable {
        /// The panel's id.
        package let id: String
        /// Its title in the person's language, as the tool wrote it.
        package let title: String
        package let symbol: String

        package init(id: String, title: String, symbol: String) {
            self.id = id
            self.title = title
            self.symbol = symbol
        }
    }

    /// The tool's Settings panel, by its id, drawn under its own settings;
    /// nil for a tool with none, or one that is switched off or held back.
    package let settingsPanel: String?
    /// The tool's windows, each with the app's word Open. None for a tool
    /// that is switched off or held back: it has no program to ask.
    package let windows: [Window]
    /// The switch that lists the tool's page among the island's sections,
    /// as it stands; nil for a tool with no island page.
    package let showsInIsland: Bool?
    /// The words beside that switch.
    package let showInIslandTitle: String
    /// The switch that draws the tool's status on the closed island, as it
    /// stands; nil for a tool whose manifest declares no status.
    package let showsStatus: Bool?
    /// The words beside that switch.
    package let showStatusTitle: String

    /// The app's word above the tool's own settings.
    package let settingsTitle: String
    /// The tool's settings the person may change: the preferences its
    /// author gave a title. One with no title is not here, so it is never
    /// drawn by its id.
    package let settings: [ExternalToolSetting]

    /// Each control of the detail the keyboard can be on.
    package enum Focus: Hashable, Sendable {
        case startAgain
        /// One of the tool's own settings, by the preference's id.
        case setting(String)
        case shortcuts
        case reveal
        case remove
        case update
        /// The button that installs the newer version from the catalog.
        case updateNow
        case close
        /// The switch that lists the tool's page in the island.
        case showsInIsland
        /// The switch that draws the tool's status on the closed island.
        case showsStatus
        /// The Open button of one of the tool's windows, by the panel's id.
        case window(String)
        /// A control of the tool's Settings panel, by its block's id.
        case panel(String)
        /// The field that searches a sheet whose lists scroll.
        case search
        /// A link of that sheet's row of sections, by where it scrolls to.
        case section(SettingsSheetIndex.Anchor)
    }

    /// The control the keyboard is on when the detail opens. It is never
    /// one that changes anything: with "Keyboard navigation" on in System
    /// Settings, macOS puts focus on the detail's first control, which is
    /// the tool's first setting, and Space turns a switch.
    package var initialFocus: Focus { .close }

    /// How many rows the lists hold together.
    package var listRows: Int {
        settings.count + commands.count + uses.count + windows.count + (showsInIsland == nil ? 0 : 1)
            + (showsStatus == nil ? 0 : 1)
    }
    /// True when the lists are too long to draw whole, and scroll in a
    /// region of a fixed height, as on the agreement sheet. A tool's own
    /// Settings panel may be of any height, so a tool with one always
    /// scrolls there: the buttons stay in view.
    package var listsScroll: Bool { listRows > ToolAgreementContent.rowsDrawnWhole || settingsPanel != nil }
    /// The height of the region the lists scroll in. A tool with a Settings
    /// panel has all its settings on one page there, under a search field
    /// and a row of links to its sections, so its region is taller.
    package var listsHeight: CGFloat {
        settingsPanel == nil ? ToolAgreementContent.listsHeight : ToolAgreementContent.pageListsHeight
    }
    /// True when the region takes the room the window gives the sheet, with
    /// `listsHeight` as its least: a tool with a Settings panel. A tool
    /// with none keeps the agreement sheet's region.
    package var fillsHeight: Bool { settingsPanel != nil }

    /// The detail's margins, above and below.
    package static let margins: CGFloat = 22 * 2

    /// The tallest the detail's column may be, inside its margins, in a
    /// window `room` points high inside (nil when that is not known): the
    /// window less the sheet's margin, and never more than a 13-inch
    /// display has room for.
    package static func columnBudget(room: CGFloat?) -> CGFloat {
        min(ToolAgreementContent.detailHeight, (room ?? .infinity) - ToolAgreementContent.sheetMargin) - margins
    }

    /// The most of a tool's log the detail shows: its newest lines, and no
    /// more bytes than this.
    package static let logLines = 200
    package static let logBytes = 32 * 1024

    /// The end of what a tool logged, as the detail shows it: plain text,
    /// cut to the newest `logLines` lines and `logBytes` bytes.
    package static func shownLog(_ text: String) -> String {
        var bytes = text.utf8.suffix(logBytes)
        // The cut may fall inside one character: start at the next whole one.
        while let first = bytes.first, first & 0b1100_0000 == 0b1000_0000 { bytes = bytes.dropFirst() }
        let newest = String(decoding: bytes, as: UTF8.self)
        return newest.split(separator: "\n", omittingEmptySubsequences: false).suffix(logLines).joined(separator: "\n")
    }

    /// `settings` is what the store says the tool's settings are, and
    /// `settingsTitle` the app's existing word for Settings.
    package init(_ listed: ExternalToolStore.Listed, files: URL?, language: AppLanguage,
                 strings: ExternalToolStrings, settings: [ExternalToolStore.Setting] = [], settingsTitle: String = "",
                 updateAvailable: Bool = false, showsInIsland: Bool = true, showsStatus: Bool = true,
                 home: String = NSHomeDirectory(),
                 hasSymbol: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }) {
        let tag = language.rawValue
        self.settingsTitle = settingsTitle
        self.settings = settings.map { ExternalToolSetting($0, language: language) }
            .filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        row = ExternalToolRow(listed, language: language, strings: strings, updateAvailable: updateAvailable,
                              hasSymbol: hasSymbol)
        updateNow = updateAvailable ? ExternalToolRow.updateWords(listed, strings: strings) : nil
        summary = listed.tool?.summary?.text(for: tag)
        commandsTitle = strings.commandsTitle
        let declared = listed.tool?.manifest.tool.commands ?? []
        commands = declared.map { listed.tool?.commandTitles[$0.id]?.text(for: tag) ?? $0.title }
        usesTitle = strings.usesTitle
        uses = (listed.tool?.manifest.capabilities ?? []).compactMap { strings.use($0.capability) }
        usesNote = strings.usesNote
        self.files = files.map { ToolAgreementContent.abbreviated($0.path, home: home) }
        // A tool that is switched off or held back has no command anywhere.
        offersShortcuts = listed.standing != nil && declared.contains { $0.surfaces.contains(.shortcut) }
        // Nor a program to draw a panel.
        let panels = listed.standing == nil ? [] : listed.tool?.panels ?? []
        settingsPanel = panels.first { $0.placement == .settings }?.id
        windows = panels.filter { $0.placement == .window }.map {
            Window(id: $0.id, title: $0.title.text(for: tag) ?? $0.id, symbol: $0.symbol)
        }
        self.showsInIsland = listed.tool?.panel(in: .island) == nil ? nil : showsInIsland
        showInIslandTitle = strings.showInIsland
        self.showsStatus = listed.tool?.showsStatus == true ? showsStatus : nil
        showStatusTitle = strings.showStatusInIsland
    }
}

/// What the question before a tool is removed says.
package struct ToolRemovalContent: Equatable {
    package enum Choice: Equatable, Sendable {
        case keepData
        case deleteData
        case cancel

        /// What the store is told when this button is pressed: whether
        /// what the tool saved is deleted too. Nil for Cancel, which
        /// removes nothing.
        package var deletesData: Bool? {
            switch self {
            case .keepData: return false
            case .deleteData: return true
            case .cancel: return nil
            }
        }
    }

    /// The button Return presses. Removing takes a deliberate click.
    package static let defaultChoice: Choice = .cancel

    package let title: String
    package let message: String
    package let keepData: String
    package let deleteData: String
    package let cancel: String

    package init(name: String, strings: ExternalToolStrings, cancel: String) {
        // An alert's title has no line limit of its own.
        title = strings.removeTitle(ToolOwnWords.oneLine(name))
        message = strings.removeMessage
        keepData = strings.removeKeepData
        deleteData = strings.removeDeleteData
        self.cancel = cancel
    }

    /// The words on the button for a choice.
    package func label(_ choice: Choice) -> String {
        switch choice {
        case .keepData: return keepData
        case .deleteData: return deleteData
        case .cancel: return cancel
        }
    }
}

/// What the person is told after a tool is removed, when there is something
/// to tell: they asked for what the tool saved to be deleted, and it was
/// kept, because the tool's program would not stop; or the program was gone
/// and a folder that was to go could not be deleted. Nil when removing did
/// what was asked.
package struct ToolRemovalNotice: Equatable {
    package let title: String
    package let message: String
    /// The folder that holds what the tool saved, or each folder that could
    /// not be deleted on a line of its own, with a tilde for the home
    /// folder; nil when the store could not name it.
    package let folder: String?
    /// The same folders, for the button that shows them in the Finder.
    package let reveals: [URL]
    /// The first of them, or nil when there is none.
    package var reveal: URL? { reveals.first }

    /// What the alert says under its title: the sentence, and the folder
    /// on a line of its own.
    package var text: String { folder.map { message + "\n\n" + $0 } ?? message }

    package init?(_ removal: ExternalToolStore.Removal, name: String, strings: ExternalToolStrings,
                  home: String = NSHomeDirectory()) {
        // An alert's title has no line limit of its own.
        switch removal {
        case .keptStillRunning(let data):
            title = strings.removeKeptTitle(ToolOwnWords.oneLine(name))
            message = strings.removeKeptMessage
            reveals = data.map { [$0] } ?? []
        case .notDeleted(let folders) where !folders.isEmpty:
            title = strings.removeUndeletedTitle(ToolOwnWords.oneLine(name))
            message = strings.removeUndeletedMessage
            reveals = folders
        default:
            // What was asked was done, or there is no folder to name.
            return nil
        }
        folder = reveals.isEmpty ? nil
            : reveals.map { ToolAgreementContent.abbreviated($0.path, home: home) }.joined(separator: "\n")
    }

    /// Removes a tool, and gives back what the person must be told about
    /// it, if anything. `name` is the tool's own name for itself.
    @MainActor package static func removing(_ id: ToolID, deletingData: Bool, name: String, store: ExternalToolStore,
                                            strings: ExternalToolStrings,
                                            home: String = NSHomeDirectory()) -> ToolRemovalNotice? {
        ToolRemovalNotice(store.remove(id, deletingData: deletingData), name: name, strings: strings, home: home)
    }
}

/// What follows the folder picker: nothing when the person chose no folder,
/// the agreement sheet for a tool the store offers, or one sentence that
/// says why the folder cannot be added. Whichever it is, nothing has been
/// copied, run or saved.
package enum ToolPicked: Equatable {
    case nothing
    case ask(ToolOffer)
    case refuse(ExternalToolStore.Refusal)

    @MainActor package static func after(_ folder: URL?, store: ExternalToolStore) -> ToolPicked {
        guard let folder else { return .nothing }
        switch store.offer(from: folder) {
        case .success(let offer): return .ask(offer)
        case .failure(let refused): return .refuse(refused)
        }
    }
}

/// What the Extensions page counts, as plain values.
package enum ExtensionsPageContent {
    /// How many added tools the catalog lists a newer version of: the count
    /// on the page's row in the sidebar. A tool installed from the catalog
    /// and one added from a folder with a catalog entry's id both count
    /// (`CatalogueWatch.update(for:)`), so the count is 0 until the list
    /// has been fetched, and for a Mac with no tool the catalog lists.
    @MainActor package static func updates(store: ExternalToolStore, watch: CatalogueWatch) -> Int {
        store.listed.filter { watch.update(for: $0) != nil }.count
    }

    /// How a row's Install or Update button is drawn, while one tool at a
    /// time is fetched from the catalog or added.
    package enum InstallButton: Equatable, Sendable {
        /// This row's tool is being fetched or added: a spinner in place of
        /// the button, as the catalog's sheet drew it.
        case progress
        case enabled
        /// Another tool is being fetched or added, or its result waits:
        /// the button is there and does nothing until that is done.
        case disabled
    }

    /// The button of the row for `id`. `fetching` is the tool being fetched
    /// from the catalog, `waiting` is true while what a fetch came to waits
    /// for the page, and `adding` holds the tools agreed to that are not
    /// added yet.
    package static func installButton(for id: ToolID, fetching: ToolID?, waiting: Bool,
                                      adding: Set<ToolID>) -> InstallButton {
        if fetching == id || adding.contains(id) { return .progress }
        return fetching == nil && !waiting && adding.isEmpty ? .enabled : .disabled
    }

    /// What VoiceOver says for a row's button: its words, then whose it is.
    package static func spoken(_ button: String, name: String) -> String {
        button + ", " + name
    }

    /// The line the Features page shows for what the person added.
    @MainActor package static func summary(store: ExternalToolStore, language: AppLanguage) -> ExtensionsPageSupport.Summary {
        ExtensionsPageSupport.summary(installed: store.listed.count, strings: FeatureStrings.externalTools(language))
    }
}

/// The Features page's one line for the tools from outside, where their card
/// was: how many are added, and a link to the Extensions page.
package struct ExtensionsSummaryLine: View {
    @ObservedObject private var l10n = L10n.shared
    /// Bumped whenever a tool is added or removed, so the count is read again.
    @ObservedObject private var registry = ToolRegistry.shared

    package init() {}

    package var body: some View {
        let summary = ExtensionsPageContent.summary(store: .shared, language: l10n.language)
        HStack(spacing: 8) {
            Image(systemName: ExternalToolManifest.defaultSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            // VoiceOver reads the line once, as the link's label.
            Text(summary.text).accessibilityHidden(true)
            Text(verbatim: "·").foregroundStyle(.tertiary).accessibilityHidden(true)
            Button(summary.link) { SettingsRouter.shared.request(summary.destination) }
                .buttonStyle(.link)
                .accessibilityLabel(summary.spoken)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// The Extensions page: what the person added, each with its switch and its
/// detail, then what the catalog lists that is not added, each with
/// Install. Adding from a folder opens a folder picker and then the
/// agreement sheet; installing from the catalog fetches the tool and opens
/// the same sheet. Nothing is copied or run before the person agrees there.
package struct ExtensionsSettings: View {
    private struct Asked: Identifiable {
        let id = UUID()
        let offer: ToolOffer
    }

    private struct Shown: Identifiable {
        let tool: ToolID
        var id: String { tool.rawValue }
    }

    @ObservedObject private var l10n = L10n.shared
    /// Bumped whenever a tool is added, removed, switched, or stands
    /// differently, so the rows are read again.
    @ObservedObject private var registry = ToolRegistry.shared
    /// The catalog, and which added tool has a newer version listed.
    @ObservedObject private var watch = CatalogueWatch.shared
    /// The tool from the catalog being fetched, and what it came to. Kept
    /// outside the page, so leaving it loses neither.
    @ObservedObject private var installs = CatalogueInstalls.shared
    /// A tool's request, from one of its panels, to show its own detail.
    @ObservedObject private var router = SettingsRouter.shared
    @State private var asked: Asked?
    /// The tools the person agreed to that are not added yet: an add waits
    /// for whatever the app hands the tool to be ready, never on the main
    /// thread (`ExternalToolStore.add(_:then:)`).
    @State private var adding: Set<ToolID> = []
    @State private var refusal: ToolRefusalMessage?
    @State private var shown: Shown?
    /// What to tell the person about the tool they just removed. It waits
    /// in `removed` until the tool's detail has closed, and is then shown
    /// as `kept`: one thing is presented at a time.
    @State private var removed: ToolRemovalNotice?
    @State private var kept: ToolRemovalNotice?
    /// How tall the Settings window is inside, handed to a tool's detail so
    /// its sheet is drawn at its height from its first layout.
    @State private var room: CGFloat?

    package init() {}

    private var text: ExternalToolStrings { FeatureStrings.externalTools(l10n.language) }
    private var store: ExternalToolStore { .shared }
    private var installer: CatalogueInstaller { .shared }

    package var body: some View {
        let rows = ExternalToolRow.all(store: store, language: l10n.language, strings: text, watch: watch)
        let catalogue = CatalogueSheetContent(state: watch.state, entries: watch.entries, listed: store.listed,
                                              update: watch.update(for:), language: l10n.language, strings: text)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(text.pageTitle).font(.title2.bold())
                    Spacer(minLength: 12)
                    if !adding.isEmpty { ProgressView().controlSize(.small) }
                    Button(text.addButton) { chooseFolder() }
                }
                SettingsCard(title: text.installedTitle) {
                    if rows.isEmpty {
                        Text(text.sectionEmpty)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(rows) { row in
                                ExternalToolRowView(row: row, text: text,
                                                    setOn: { store.setOn(row.id, $0) },
                                                    startAgain: { store.startAgain(row.id) },
                                                    update: updateAction(for: row.id),
                                                    updateButton: button(for: row.id),
                                                    open: { shown = Shown(tool: row.id) })
                                if row.id != rows.last?.id {
                                    Divider().padding(.leading, 8)
                                }
                            }
                        }
                    }
                }
                SettingsCard(title: catalogue.title) {
                    switch catalogue.notInstalled {
                    case .loading:
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60)
                    case .message(let message):
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .rows(let entries):
                        VStack(spacing: 0) {
                            ForEach(entries) { row in
                                CatalogueRowView(row: row, usesTitle: catalogue.usesTitle,
                                                 button: button(for: row.id),
                                                 install: { install($0) })
                                if row.id != entries.last?.id { Divider().padding(.leading, 8) }
                            }
                        }
                    }
                    // Outside the switch, so it shows whatever the list is
                    // doing: loading, empty, out of reach, refused or listed.
                    Divider()
                    CatalogueSDKLineView(line: catalogue.sdk)
                }
            }
            .modifier(FeatureHubColumn())
        }
        // The list is asked for each time the page opens, as the catalog's
        // sheet did when it opened, with the ETag of the one kept.
        .onAppear { watch.refresh() }
        // What a fetch came to is shown when it arrives, or when the page
        // is next opened if the person had left it, once no other sheet is up.
        .onChange(of: installs.waiting, initial: true) { _, _ in showWaiting() }
        .onChange(of: asked == nil && shown == nil) { _, _ in showWaiting() }
        // A tool asked for its own settings: its detail opens now, or once
        // the page is free.
        .onChange(of: router.extensionTool, initial: true) { _, _ in showAsked() }
        .onChange(of: asked == nil && shown == nil && refusal == nil && removed == nil && kept == nil) { _, _ in
            showAsked()
        }
        .sheet(item: $asked) { asked in
            ToolAgreementSheet(
                offer: asked.offer,
                content: ToolAgreementContent(offer: asked.offer, language: l10n.language, strings: text,
                                              cancel: l10n.s.uninstallerCancel),
                onAgree: { consent in
                    self.asked = nil
                    let offer = consent.offer
                    let id = offer.tool.manifest.id
                    // Usually done before this returns. Never a wait on the
                    // main thread: the page shows the tool is being added.
                    adding.insert(id)
                    store.add(consent) { result in
                        adding.remove(id)
                        if case .failure(let refused) = result { show(refused, of: offer) }
                        // The download's folder, for a tool from the catalog:
                        // the store has its own copy now, or nothing.
                        installer.finished(with: offer)
                    }
                },
                onCancel: {
                    self.asked = nil
                    installer.finished(with: asked.offer)
                })
        }
        .background(SheetRoomReader(own: true) { room = $0 })
        .background {
            // A second sheet and the alert hang on a view of their own, so
            // neither competes with the agreement sheet for the page.
            Color.clear
                .sheet(item: $shown, onDismiss: {
                    kept = removed
                    removed = nil
                }) { shown in detail(of: shown.tool) }
                .alert(refusal?.title ?? "", isPresented: Binding(get: { refusal != nil },
                                                                 set: { if !$0 { refusal = nil } }),
                       presenting: refusal) { refusal in
                    if let command = refusal.command {
                        Button(l10n.s.menuCopy) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                    }
                    Button(l10n.s.menuClose, role: .cancel) {}
                } message: { refusal in
                    Text(refusal.command.map { refusal.message + "\n\n" + $0 } ?? refusal.message)
                }
        }
        .background {
            // Said once, after the row has gone: what the tool saved was to
            // be deleted and was kept, because its program would not stop,
            // or a folder that was to go could not be deleted.
            Color.clear
                .alert(kept?.title ?? "", isPresented: Binding(get: { kept != nil }, set: { if !$0 { kept = nil } }),
                       presenting: kept) { kept in
                    if !kept.reveals.isEmpty {
                        Button(l10n.s.cleanerRevealInFinder) {
                            NSWorkspace.shared.activateFileViewerSelecting(kept.reveals)
                        }
                    }
                    Button(l10n.s.menuClose, role: .cancel) {}
                } message: { kept in
                    Text(kept.text)
                }
        }
    }

    private func button(for id: ToolID) -> ExtensionsPageContent.InstallButton {
        ExtensionsPageContent.installButton(for: id, fetching: installs.fetching, waiting: installs.waiting != nil,
                                            adding: adding)
    }

    /// Shows the detail a tool asked for from one of its panels, or keeps
    /// the request until no other sheet or alert is up
    /// (`ExtensionsPageSupport.askedDetail`).
    private func showAsked() {
        let busy = asked != nil || refusal != nil || removed != nil || kept != nil
        switch ExtensionsPageSupport.askedDetail(router.extensionTool, listed: store.listed.map(\.id),
                                                 showing: shown?.tool, busy: busy) {
        case .show(let id)?:
            router.extensionTool = nil
            shown = Shown(tool: id)
        case .drop?:
            router.extensionTool = nil
        case .wait?, nil:
            break
        }
    }

    /// Shows what a fetch from the catalog came to: the agreement sheet, or
    /// why there is none. It waits while another sheet is up.
    private func showWaiting() {
        guard asked == nil, shown == nil, installs.waiting != nil else { return }
        switch installs.take() {
        case .ready(let offer)?:
            asked = Asked(offer: offer)
        case .refused(let refused, let entry)?:
            refusal = ToolRefusalMessage(catalogue: refused,
                                         name: entry.name.text(for: l10n.language.rawValue) ?? entry.id.rawValue,
                                         language: l10n.language, strings: text)
        case nil:
            break
        }
    }

    /// The row's Update button: installs the newer version the catalog
    /// lists, through the agreement sheet. Nil when it lists none.
    private func updateAction(for id: ToolID) -> (() -> Void)? {
        guard let listed = store.listed.first(where: { $0.id == id }), let newer = watch.update(for: listed) else {
            return nil
        }
        return { install(newer) }
    }

    @ViewBuilder
    private func detail(of id: ToolID) -> some View {
        if let listed = store.listed.first(where: { $0.id == id }) {
            let name = ExternalToolRow(listed, language: l10n.language, strings: text).name
            let newer = watch.update(for: listed)
            ExternalToolDetailView(
                detail: ExternalToolDetail(listed, files: store.folder(of: id), language: l10n.language, strings: text,
                                           settings: store.settings(of: id), settingsTitle: l10n.s.panelSettings,
                                           updateAvailable: newer != nil,
                                           showsInIsland: store.showsInIsland(id),
                                           showsStatus: store.showsStatus(id)),
                log: ExternalToolDetail.shownLog(store.tool(id)?.log.text ?? ""),
                removal: ToolRemovalContent(name: name, strings: text, cancel: l10n.s.uninstallerCancel),
                text: text,
                startAgain: { store.startAgain(id) },
                saveSetting: { name, value in store.setSetting(value, for: name, of: id) == nil },
                setShowsInIsland: { store.setShowsInIsland(id, $0) },
                setShowsStatus: { store.setShowsStatus(id, $0) },
                panel: { panel, open in
                    let key = ToolPanelHost.Key(tool: id, panel: panel)
                    if open { ToolPanelHost.shared.open(key, in: .settings) } else { ToolPanelHost.shared.close(key) }
                },
                openWindow: { ToolPanelHost.shared.open(ToolPanelHost.Key(tool: id, panel: $0), in: .window) },
                reveal: { if let folder = store.folder(of: id) { NSWorkspace.shared.activateFileViewerSelecting([folder]) } },
                openShortcuts: {
                    shown = nil
                    SettingsRouter.shared.page = .shortcuts
                },
                update: {
                    // The detail closes first: the agreement sheet is the
                    // page's, and one sheet shows at a time.
                    shown = nil
                    DispatchQueue.main.async { chooseFolder() }
                },
                updateNow: {
                    shown = nil
                    if let newer { install(newer) }
                },
                remove: { deletingData in
                    shown = nil
                    removed = ToolRemovalNotice.removing(id, deletingData: deletingData, name: name, store: store,
                                                         strings: text)
                },
                close: { shown = nil },
                room: room)
        }
    }

    /// The first step of adding or updating a tool: the person picks its
    /// folder, and the store reads it. Nothing is copied or run here.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        switch ToolPicked.after(panel.runModal() == .OK ? panel.url : nil, store: store) {
        case .nothing: return
        case .ask(let offer): asked = Asked(offer: offer)
        case .refuse(let refused): show(refused)
        }
    }

    private func show(_ refused: ExternalToolStore.Refusal, of offer: ToolOffer? = nil) {
        let name = offer?.catalogue == nil ? nil
            : offer.map { $0.tool.name.text(for: l10n.language.rawValue) ?? $0.tool.manifest.tool.name }
        refusal = ToolRefusalMessage(refused, language: l10n.language, strings: text, installing: name)
    }

    /// Fetches a tool from the catalog. What it comes to waits in
    /// `CatalogueInstalls` until the page shows it (`showWaiting`): the
    /// agreement sheet, as for a folder. Nothing is installed here.
    private func install(_ entry: CatalogueEntry) {
        guard adding.isEmpty else { return }
        installs.start(entry)
    }
}

/// One tool's row: its icon, name, publisher and version, how it stands, a
/// button when only the person can start it again, one that installs a
/// newer version from the catalog when there is one, its switch, and the way
/// into its detail.
private struct ExternalToolRowView: View {
    let row: ExternalToolRow
    let text: ExternalToolStrings
    let setOn: (Bool) -> Void
    let startAgain: () -> Void
    /// Installs the newer version the catalog lists; nil when it lists none.
    let update: (() -> Void)?
    /// How the Update button is drawn while a tool is fetched or added.
    let updateButton: ExtensionsPageContent.InstallButton
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        // The tool's own words can be any length: each
                        // keeps to one line of the row.
                        Text(row.name)
                            .foregroundStyle(row.isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(row.byline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            ExternalToolKindBadge(text: row.kindBadge)
                        }
                        if let status = row.statusText {
                            ExternalToolStatusLabel(status: row.status, text: status)
                        }
                        if let update = row.updateText {
                            ExternalToolUpdateLabel(text: update)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel([row.name, row.kindBadge, row.byline, row.statusText, row.updateText].compactMap { $0 }
                .joined(separator: ". "))
            if row.status == .stopped(canStartAgain: true) {
                Button(text.startAgain, action: startAgain).controlSize(.small)
            }
            if let update, let words = row.updateButton {
                if updateButton == .progress {
                    ProgressView().controlSize(.small)
                } else {
                    Button(words, action: update)
                        .controlSize(.small)
                        .disabled(updateButton == .disabled)
                        .accessibilityLabel(row.updateSpoken ?? words)
                }
            }
            Toggle(row.name, isOn: Binding(get: { row.isOn }, set: setOn))
                .labelsHidden()
                .controlNamed(row.name)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!row.canSwitch)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(hovering ? Color.primary.opacity(0.04) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
    }
}

/// A status in words, with a dot whose colour says the same: green for
/// running, red for stopped, orange for changed.
private struct ExternalToolStatusLabel: View {
    let status: ExternalToolRow.Status
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var color: Color {
        switch status {
        case .running: return .green
        case .stopped: return .red
        case .changed: return .orange
        case .quiet: return .secondary
        }
    }
}

/// "Extension" or "Tool", in a quiet pill beside the byline.
struct ExternalToolKindBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// "Update available", with a dot in the accent colour.
private struct ExternalToolUpdateLabel: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// One of a tool's own settings in its detail: its title, and a switch, a
/// text field, a number field or a pop-up menu. A switch saves as it is
/// turned, and a menu as an option is picked. A field
/// saves when Return is pressed, when the person moves on from it, and when
/// the detail closes. A value the store will not take is put back as it was.
private struct ExternalToolSettingRow: View {
    let setting: ExternalToolSetting
    /// The words on the button beside a field that picks a folder.
    let chooseFolder: String
    /// Saves a value. False when it was refused, and nothing was saved.
    let save: (PreferenceDeclaration.Value) -> Bool
    /// What the control holds now, and the last value that was saved.
    @State private var draft: ExternalToolSetting.Control
    @State private var saved: ExternalToolSetting.Control
    /// The detail's focus: the keyboard is on this row's control while it
    /// says this setting.
    @FocusState.Binding private var focus: ExternalToolDetail.Focus?

    init(setting: ExternalToolSetting, chooseFolder: String, focus: FocusState<ExternalToolDetail.Focus?>.Binding,
         save: @escaping (PreferenceDeclaration.Value) -> Bool) {
        self.setting = setting
        self.chooseFolder = chooseFolder
        _focus = focus
        self.save = save
        _draft = State(initialValue: setting.control)
        _saved = State(initialValue: setting.control)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // The tool's own words: plain text, on two lines at most.
            Text(setting.title).font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            control
        }
        .onChange(of: focus == .setting(setting.id)) { _, isEditing in
            if !isEditing { commit(draft) }
        }
        .onDisappear { commit(draft) }
    }

    @ViewBuilder
    private var control: some View {
        switch draft {
        case .toggle(let isOn):
            Toggle(setting.title, isOn: Binding(get: { isOn }, set: { commit(.toggle($0)) }))
                .labelsHidden()
                .controlNamed(setting.title)
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .focused($focus, equals: .setting(setting.id))
        case .text(let text) where setting.picksFolder:
            HStack(spacing: 6) {
                field(TextField(setting.title, text: Binding(get: { text }, set: { draft = .text($0) }),
                                prompt: Text(verbatim: "")),
                      width: 200)
                Button(chooseFolder) { pickFolder(from: text) }
                    .controlSize(.small)
                    .help(setting.title)
            }
        case .text(let text):
            field(TextField(setting.title, text: Binding(get: { text }, set: { draft = .text($0) }), prompt: Text(verbatim: "")),
                  width: 200)
        case .whole(let number):
            field(TextField(setting.title, value: Binding(get: { number }, set: { draft = .whole($0) }), format: .number,
                            prompt: Text(verbatim: "")),
                  width: 100)
        case .number(let number):
            field(TextField(setting.title, value: Binding(get: { number }, set: { draft = .number($0) }), format: .number,
                            prompt: Text(verbatim: "")),
                  width: 100)
        case .choice(let value, _):
            // In the row a text field has, and as wide. A pick is saved at
            // once, as a switch is. The rows are the setting's as the detail
            // was last drawn, so they follow the language while it is open;
            // what is selected is what this row holds.
            let rows = ExternalToolSetting.Choice.rows(selected: value, among: setting.control.choices ?? [])
            Picker(setting.title, selection: Binding(get: { value }, set: { commit(draft.picking($0)) })) {
                // The tool's own words: plain text, one line each.
                ForEach(rows) { Text(verbatim: $0.title).tag($0.value) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 200)
            .focused($focus, equals: .setting(setting.id))
        }
    }

    private func field(_ field: some View, width: CGFloat) -> some View {
        field
            .labelsHidden()
            .controlNamed(setting.title)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(width: width)
            .focused($focus, equals: .setting(setting.id))
            .onSubmit { commit(draft) }
    }

    /// Opens a panel that picks one folder, starting at the one the field
    /// names, and saves the folder's path as the field's value at once.
    private func pickFolder(from current: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = chooseFolder.trimmingCharacters(in: CharacterSet(charactersIn: "…."))
        let start = (current as NSString).expandingTildeInPath
        if !start.isEmpty { panel.directoryURL = URL(fileURLWithPath: start, isDirectory: true) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        commit(.text(url.path))
    }

    private func commit(_ wanted: ExternalToolSetting.Control) {
        guard wanted != saved else { return }
        if save(wanted.value) {
            saved = wanted
            draft = wanted
        } else {
            draft = saved
        }
    }
}

/// One tool's detail: its own settings, what it adds, what it says it uses,
/// where its files are, what it logged, and the buttons that update or
/// remove it.
package struct ExternalToolDetailView: View {
    @ObservedObject private var l10n = L10n.shared
    /// Read for the tool's Settings panel: the sheet's search and its links
    /// read the page the panel shows.
    @ObservedObject private var host: ToolPanelHost
    let detail: ExternalToolDetail
    let log: String
    let removal: ToolRemovalContent
    let text: ExternalToolStrings
    let startAgain: () -> Void
    /// Saves one of the tool's settings, by the preference's id. False when
    /// the value was refused.
    let saveSetting: (String, PreferenceDeclaration.Value) -> Bool
    /// Turns the switch that lists the tool's page in the island.
    let setShowsInIsland: (Bool) -> Void
    /// Turns the switch that draws the tool's status on the closed island.
    let setShowsStatus: (Bool) -> Void
    /// Opens the tool's Settings panel, by its id, or closes it.
    let panel: (String, _ open: Bool) -> Void
    /// Opens one of the tool's windows, by the panel's id.
    let openWindow: (String) -> Void
    let reveal: () -> Void
    let openShortcuts: () -> Void
    let update: () -> Void
    /// Installs the newer version from the catalog.
    let updateNow: () -> Void
    let remove: (_ deletingData: Bool) -> Void
    let close: () -> Void
    @State private var confirmingRemoval = false
    @State private var logExpanded: Bool
    /// The control the keyboard is on. Nil while it is on none of them.
    @FocusState private var focus: ExternalToolDetail.Focus?
    /// True once the focus macOS gave the detail as it opened has been seen.
    @State private var focusPlaced = false
    /// What is typed in the search field of a sheet whose lists scroll.
    @State private var query = ""
    /// How tall the window the sheet hangs from is inside; nil until known.
    /// The page that opens the sheet hands it in, so the first layout has
    /// it; the sheet's own reader keeps it as the window is resized.
    @State private var room: CGFloat?

    package init(detail: ExternalToolDetail, log: String, removal: ToolRemovalContent, text: ExternalToolStrings,
                 startAgain: @escaping () -> Void, saveSetting: @escaping (String, PreferenceDeclaration.Value) -> Bool,
                 setShowsInIsland: @escaping (Bool) -> Void, setShowsStatus: @escaping (Bool) -> Void,
                 panel: @escaping (String, _ open: Bool) -> Void, openWindow: @escaping (String) -> Void,
                 reveal: @escaping () -> Void, openShortcuts: @escaping () -> Void, update: @escaping () -> Void,
                 updateNow: @escaping () -> Void, remove: @escaping (_ deletingData: Bool) -> Void,
                 close: @escaping () -> Void, logExpanded: Bool = false, room: CGFloat? = nil,
                 host: ToolPanelHost = .shared) {
        self.host = host
        _room = State(initialValue: room)
        self.detail = detail
        self.log = log
        self.removal = removal
        self.text = text
        self.startAgain = startAgain
        self.saveSetting = saveSetting
        self.setShowsInIsland = setShowsInIsland
        self.setShowsStatus = setShowsStatus
        self.panel = panel
        self.openWindow = openWindow
        self.reveal = reveal
        self.openShortcuts = openShortcuts
        self.update = update
        self.updateNow = updateNow
        self.remove = remove
        self.close = close
        _logExpanded = State(initialValue: logExpanded)
    }

    /// The tallest the detail's column may be, inside its margins: a sheet
    /// whose settings region takes the room. Nil for one whose region has a
    /// height of its own.
    private var budget: CGFloat? {
        guard detail.fillsHeight else { return nil }
        return ExternalToolDetail.columnBudget(room: room)
    }

    package var body: some View {
        SheetColumn(spacing: 16, budget: budget,
                    give: ToolAgreementContent.pageListsHeight - ToolAgreementContent.pageListsTightHeight) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: detail.row.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    // The tool's own words are cut short as on the sheet,
                    // so that none can push the buttons off the view.
                    Text(detail.row.name).font(.title3.bold()).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(detail.row.byline).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    if let summary = detail.summary {
                        Text(summary).font(.callout).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    if let update = detail.row.updateText {
                        ExternalToolUpdateLabel(text: update)
                    }
                    if let status = detail.row.statusText {
                        HStack(spacing: 10) {
                            ExternalToolStatusLabel(status: detail.row.status, text: status)
                            if detail.row.status == .stopped(canStartAgain: true) {
                                Button(text.startAgain, action: startAgain).controlSize(.small)
                                    .focused($focus, equals: .startAgain)
                            }
                        }
                    }
                }
            }
            // Only the lists scroll, and only when they are long: the
            // buttons below are always in view. Lists that scroll have a
            // search field and a row of links to their sections above them.
            if let index = onePage {
                ExtensionSettingsOnePage(index: index, query: $query, height: detail.listsHeight,
                                         fills: detail.fillsHeight, tight: ToolAgreementContent.pageListsTightHeight,
                                         text: text, focus: $focus) { lists($0) }
                    .layoutValue(key: SheetColumn.Fills.self, value: true)
            } else if detail.listRows > 0 {
                lists(nil)
            }
            if let files = detail.files {
                HStack(spacing: 10) {
                    Text(files)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button(l10n.s.cleanerRevealInFinder, action: reveal).controlSize(.small)
                        .focused($focus, equals: .reveal)
                }
            }
            if !log.isEmpty {
                DisclosureGroup(l10n.s.homebrewLogTitle, isExpanded: $logExpanded) {
                    ScrollView {
                        Text(log)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                }
            }
            HStack(spacing: 10) {
                Button(l10n.s.actionRemove, role: .destructive) { confirmingRemoval = true }
                    .focused($focus, equals: .remove)
                if let updateNow = detail.updateNow {
                    Button(updateNow, action: self.updateNow)
                        .focused($focus, equals: .updateNow)
                }
                Button(text.updateButton, action: update)
                    .focused($focus, equals: .update)
                Spacer()
                Button(l10n.s.menuClose, action: close).keyboardShortcut(.defaultAction)
                    .focused($focus, equals: .close)
            }
        }
        .padding(22)
        .frame(width: 480)
        // A sheet's window has no parent yet as it goes in: what the page
        // handed in stands until there is one.
        .background(SheetRoomReader { if let known = $0 { room = known } })
        // Escape clears a search first, then closes.
        .onExitCommand { if query.isEmpty { close() } else { query = "" } }
        // The tool's Settings panel is open for as long as the detail is.
        .onAppear { if let id = detail.settingsPanel { panel(id, true) } }
        .onDisappear { if let id = detail.settingsPanel { panel(id, false) } }
        // As the agreement sheet does: macOS puts the keyboard on the
        // detail's first control as it becomes the key window, which is the
        // tool's first setting, and `onAppear` or `defaultFocus` do not
        // hold in a sheet. So the detail answers that first placing, once,
        // and moves it to Close. Tab still reaches every field and switch.
        .onChange(of: focus) { _, placed in
            guard !focusPlaced, let placed else { return }
            focusPlaced = true
            if placed != detail.initialFocus { focus = detail.initialFocus }
        }
        .alert(removal.title, isPresented: $confirmingRemoval) {
            removalButton(.keepData)
            removalButton(.deleteData)
            removalButton(.cancel)
        } message: {
            Text(removal.message)
        }
    }

    /// The sheet whose lists scroll (a tool with a Settings panel, or one
    /// with too many rows to draw whole) as one page: what the sheet
    /// holds, as its search and its links read it. Nil for a sheet short
    /// enough to show everything, which needs no search and no links.
    private var onePage: SettingsSheetIndex? {
        guard detail.listsScroll else { return nil }
        let shown = detail.settingsPanel.flatMap { host.shown[ToolPanelHost.Key(tool: detail.row.id, panel: $0)] }
        var page: BlockTreeContent?
        var isWeb = false
        switch shown {
        case .page(let tree)?:
            page = BlockTreeContent(tree: tree, language: l10n.language.rawValue, folder: nil, size: .standard)
        case .web?:
            isWeb = true
        case .waiting?, .notShown?, nil:
            break
        }
        return SettingsSheetIndex(detail: detail, panel: page, panelIsWeb: isWeb, strings: text)
    }

    /// The tool's own settings, what it adds, and what it says it uses.
    /// With `kept`, a sheet whose lists scroll: each part under a heading
    /// its row of links scrolls to, and only what its search kept.
    private func lists(_ kept: SettingsSheetIndex.Kept?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let kept {
                if kept.nothingFound {
                    SettingsSheetNoMatch(text: text, query: query)
                }
                if kept.drawsSection(.vitruvianHeading) {
                    section(text.vitruvianSection, mark: .vitruvianHeading) { ownRows(kept) }
                }
                if let id = detail.settingsPanel {
                    ExtensionSettingsPanel(key: ToolPanelHost.Key(tool: detail.row.id, panel: id),
                                           title: detail.settingsTitle, kept: kept, text: text, focus: $focus,
                                           host: host)
                }
            } else if !detail.settings.isEmpty || detail.showsInIsland != nil || detail.showsStatus != nil {
                section(detail.settingsTitle) { ownRows(nil) }
            }
            if !detail.commands.isEmpty || !detail.windows.isEmpty, kept?.drawsSection(.commands) ?? true {
                section(detail.commandsTitle, mark: kept == nil ? nil : .commands) {
                    ForEach(Array(detail.commands.enumerated()).filter { kept?.draws(.commands, title: $0.element) ?? true },
                            id: \.offset) {
                        Text($0.element).font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(detail.windows.filter { kept?.draws(.commands, title: $0.title) ?? true }) { window in
                        HStack(spacing: 8) {
                            Image(systemName: window.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                            // The tool's own words: plain text, on one line.
                            Text(verbatim: window.title).font(.callout).lineLimit(1)
                            Spacer(minLength: 8)
                            Button(l10n.s.shelfActionOpen) { openWindow(window.id) }
                                .controlSize(.small)
                                .focused($focus, equals: .window(window.id))
                        }
                    }
                    if detail.offersShortcuts, kept?.searching != true {
                        Button(l10n.s.shortcutsPageTitle, action: openShortcuts).controlSize(.small)
                            .focused($focus, equals: .shortcuts)
                    }
                }
            }
            if !detail.uses.isEmpty, kept?.drawsSection(.uses) ?? true {
                section(detail.usesTitle, mark: kept == nil ? nil : .uses) {
                    ForEach(Array(detail.uses.enumerated()).filter { kept?.draws(.uses, title: $0.element) ?? true },
                            id: \.offset) { Text($0.element).font(.callout) }
                    if kept?.searching != true {
                        Text(detail.usesNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The app's own rows of a tool's settings: its island switches and
    /// the settings its manifest declares, those a search kept. Each is laid
    /// out as the extension's own are (`BlockTreeView`): the title leading,
    /// the switch at the trailing edge, so every switch on the sheet ends at
    /// one edge.
    @ViewBuilder
    private func ownRows(_ kept: SettingsSheetIndex.Kept?) -> some View {
        if let shows = detail.showsInIsland, kept?.draws(.showsInIsland) ?? true {
            ownSwitch(detail.showInIslandTitle, isOn: shows, focus: .showsInIsland) { setShowsInIsland($0) }
        }
        if let shows = detail.showsStatus, kept?.draws(.showsStatus) ?? true {
            ownSwitch(detail.showStatusTitle, isOn: shows, focus: .showsStatus) { setShowsStatus($0) }
        }
        ForEach(detail.settings.filter { kept?.draws(.setting($0.id)) ?? true }) { setting in
            ExternalToolSettingRow(setting: setting, chooseFolder: text.chooseFolder, focus: $focus,
                                   save: { saveSetting(setting.id, $0) })
        }
    }

    /// One of the app's own switches: its title, then the switch at the
    /// trailing edge. The switch carries the title as its name; the drawn
    /// title is not read twice.
    private func ownSwitch(_ title: String, isOn: Bool, focus place: ExternalToolDetail.Focus,
                           set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(title, isOn: Binding(get: { isOn }, set: { set($0) }))
                .labelsHidden()
                .controlNamed(title)
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .focused($focus, equals: place)
        }
    }

    /// A part of the lists under its title. With `mark`, a part of a sheet
    /// whose lists scroll: its title is a section heading of that page, as
    /// large as the page's own, and its links scroll to it.
    private func section<Content: View>(_ title: String, mark: SettingsSheetIndex.Anchor? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SettingsSheetHeading(title: title, mark: mark)
            content()
        }
    }

    /// Cancel is the default button: Return removes nothing.
    @ViewBuilder
    private func removalButton(_ choice: ToolRemovalContent.Choice) -> some View {
        let role: ButtonRole? = choice == .cancel ? .cancel : choice == .deleteData ? .destructive : nil
        let plain = Button(removal.label(choice), role: role) {
            if let deletingData = choice.deletesData { remove(deletingData) }
        }
        if choice == ToolRemovalContent.defaultChoice {
            plain.keyboardShortcut(.defaultAction)
        } else {
            plain
        }
    }
}

/// Marks a section heading of an extension's settings sheet: the place its
/// link scrolls to, and where it is in the scrolling region, so the link of
/// the section in view is lit (`SettingsSheetIndex.current`). Nil marks
/// nothing.
struct SettingsSheetMark: ViewModifier {
    /// The scrolling region's coordinate space.
    static let space = "extension.settings.lists"
    /// How far below the region's top a heading may be and still be the
    /// section in view, in points.
    static let reach: CGFloat = 24
    /// The most characters of a section's title its link shows.
    static let linkCharacters = 30

    /// A link of the row, by its section's anchor: an id apart from the
    /// anchor's own.
    struct Link: Hashable {
        let anchor: SettingsSheetIndex.Anchor
    }

    /// Where each marked heading is, from the region's top.
    struct Tops: PreferenceKey {
        static let defaultValue: [SettingsSheetIndex.Anchor: CGFloat] = [:]

        static func reduce(value: inout [SettingsSheetIndex.Anchor: CGFloat],
                           nextValue: () -> [SettingsSheetIndex.Anchor: CGFloat]) {
            value.merge(nextValue()) { $1 }
        }
    }

    let anchor: SettingsSheetIndex.Anchor?

    func body(content: Content) -> some View {
        if let anchor {
            content
                .id(anchor)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: Tops.self, value: [anchor: proxy.frame(in: .named(Self.space)).minY])
                    }
                }
        } else {
            content
        }
    }
}
