// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol

/// One tool from outside, as its row in the Features hub shows it. Plain
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

    package let id: ToolID
    /// The tool's name in the person's language, as the tool wrote it. For
    /// a tool that is held back, the name the person agreed to.
    package let name: String
    /// The publisher and the version, as the tool wrote them.
    package let byline: String
    package let symbol: String
    package let isOn: Bool
    package let status: Status
    /// The words beside the row for its status; nil when there are none.
    package let statusText: String?
    /// False for a tool that is held back: its switch does nothing until
    /// the person updates it from its folder.
    package var canSwitch: Bool { status != .changed }

    package init(_ listed: ExternalToolStore.Listed, language: AppLanguage, strings: ExternalToolStrings,
                 hasSymbol: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }) {
        let agreed = listed.record.agreement
        id = listed.id
        name = listed.tool?.name.text(for: language.rawValue) ?? agreed.name
        byline = "\(listed.tool?.publisher ?? agreed.publisher) · \(listed.tool?.version ?? agreed.version)"
        let wanted = listed.tool?.manifest.tool.symbol ?? ExternalToolManifest.defaultSymbol
        symbol = hasSymbol(wanted) ? wanted : ExternalToolManifest.defaultSymbol
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

    /// A row for each tool the person added, in the order they added them.
    @MainActor package static func all(store: ExternalToolStore, language: AppLanguage,
                                       strings: ExternalToolStrings) -> [ExternalToolRow] {
        store.listed.map { ExternalToolRow($0, language: language, strings: strings) }
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

        /// The value the control holds, as the store saves it.
        package var value: PreferenceDeclaration.Value {
            switch self {
            case .toggle(let isOn): return .bool(isOn)
            case .text(let text): return .string(text)
            case .whole(let number): return .int(number)
            case .number(let number): return .double(number)
            }
        }
    }

    /// The preference's id within the tool. It is never drawn.
    package let id: String
    /// The title its author gave it, in the person's language, as one
    /// short line of plain text.
    package let title: String
    package let control: Control

    package init(_ setting: ExternalToolStore.Setting, language: AppLanguage) {
        id = setting.id
        // The manifest's rules hold a title to this length already. It is
        // bounded again here, where it is drawn.
        title = ToolOwnWords.oneLine(setting.title.text(for: language.rawValue) ?? "",
                                     limit: ManifestLimits.maxPreferenceTitleLength)
        switch setting.value {
        case .bool(let isOn): control = .toggle(isOn)
        case .string(let text): control = .text(text)
        case .int(let number): control = .whole(number)
        case .double(let number): control = .number(number)
        }
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

    /// The app's word above the tool's own settings.
    package let settingsTitle: String
    /// The tool's settings the person may change: the preferences its
    /// author gave a title. One with no title is not here, so it is never
    /// drawn by its id.
    package let settings: [ExternalToolSetting]

    /// How many rows the lists hold together.
    package var listRows: Int { settings.count + commands.count + uses.count }
    /// True when the lists are too long to draw whole, and scroll in a
    /// region of a fixed height, as on the agreement sheet.
    package var listsScroll: Bool { listRows > ToolAgreementContent.rowsDrawnWhole }

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
                 home: String = NSHomeDirectory(),
                 hasSymbol: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }) {
        let tag = language.rawValue
        self.settingsTitle = settingsTitle
        self.settings = settings.map { ExternalToolSetting($0, language: language) }
            .filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        row = ExternalToolRow(listed, language: language, strings: strings, hasSymbol: hasSymbol)
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
/// kept, because the tool's program would not stop. Nil when removing did
/// what was asked.
package struct ToolRemovalNotice: Equatable {
    package let title: String
    package let message: String
    /// The folder that holds what the tool saved, with a tilde for the home
    /// folder; nil when the store could not name it.
    package let folder: String?
    /// The same folder, for the button that shows it in the Finder.
    package let reveal: URL?

    /// What the alert says under its title: the sentence, and the folder
    /// on a line of its own.
    package var text: String { folder.map { message + "\n\n" + $0 } ?? message }

    package init?(_ removal: ExternalToolStore.Removal, name: String, strings: ExternalToolStrings,
                  home: String = NSHomeDirectory()) {
        guard case .keptStillRunning(let data) = removal else { return nil }
        // An alert's title has no line limit of its own.
        title = strings.removeKeptTitle(ToolOwnWords.oneLine(name))
        message = strings.removeKeptMessage
        folder = data.map { ToolAgreementContent.abbreviated($0.path, home: home) }
        reveal = data
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

/// The tools from outside, in the Features hub: one quiet line and a button
/// when there are none, a row for each when there are. Adding one opens a
/// folder picker and then the agreement sheet; nothing is copied or run
/// before the person agrees there.
package struct ExternalToolsSection: View {
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
    @State private var asked: Asked?
    @State private var refusal: ToolRefusalMessage?
    @State private var shown: Shown?
    /// What to tell the person about the tool they just removed. It waits
    /// in `removed` until the tool's detail has closed, and is then shown
    /// as `kept`: one thing is presented at a time.
    @State private var removed: ToolRemovalNotice?
    @State private var kept: ToolRemovalNotice?

    package init() {}

    private var text: ExternalToolStrings { FeatureStrings.externalTools(l10n.language) }
    private var store: ExternalToolStore { .shared }

    package var body: some View {
        let rows = ExternalToolRow.all(store: store, language: l10n.language, strings: text)
        SettingsCard {
            HStack(spacing: 10) {
                Image(systemName: ExternalToolManifest.defaultSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(text.sectionTitle).font(.headline)
                Spacer(minLength: 12)
                Button(text.addButton) { chooseFolder() }
                    .controlSize(.small)
            }
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
                                            open: { shown = Shown(tool: row.id) })
                        if row.id != rows.last?.id {
                            Divider().padding(.leading, 8)
                        }
                    }
                }
            }
        }
        .sheet(item: $asked) { asked in
            ToolAgreementSheet(
                offer: asked.offer,
                content: ToolAgreementContent(offer: asked.offer, language: l10n.language, strings: text,
                                              cancel: l10n.s.uninstallerCancel),
                onAgree: { consent in
                    self.asked = nil
                    if case .failure(let refused) = store.add(consent) { show(refused) }
                },
                onCancel: { self.asked = nil })
        }
        .background {
            // A second sheet and the alert hang on a view of their own, so
            // neither competes with the agreement sheet for the card.
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
            // be deleted and was kept, because its program would not stop.
            Color.clear
                .alert(kept?.title ?? "", isPresented: Binding(get: { kept != nil }, set: { if !$0 { kept = nil } }),
                       presenting: kept) { kept in
                    if let folder = kept.reveal {
                        Button(l10n.s.cleanerRevealInFinder) {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                    }
                    Button(l10n.s.menuClose, role: .cancel) {}
                } message: { kept in
                    Text(kept.text)
                }
        }
    }

    @ViewBuilder
    private func detail(of id: ToolID) -> some View {
        if let listed = store.listed.first(where: { $0.id == id }) {
            let name = ExternalToolRow(listed, language: l10n.language, strings: text).name
            ExternalToolDetailView(
                detail: ExternalToolDetail(listed, files: store.folder(of: id), language: l10n.language, strings: text,
                                           settings: store.settings(of: id), settingsTitle: l10n.s.panelSettings),
                log: ExternalToolDetail.shownLog(store.tool(id)?.log.text ?? ""),
                removal: ToolRemovalContent(name: name, strings: text, cancel: l10n.s.uninstallerCancel),
                text: text,
                startAgain: { store.startAgain(id) },
                saveSetting: { name, value in store.setSetting(value, for: name, of: id) == nil },
                reveal: { if let folder = store.folder(of: id) { NSWorkspace.shared.activateFileViewerSelecting([folder]) } },
                openShortcuts: {
                    shown = nil
                    SettingsRouter.shared.page = .shortcuts
                },
                update: {
                    // The detail closes first: the agreement sheet is the
                    // card's, and one sheet shows at a time.
                    shown = nil
                    DispatchQueue.main.async { chooseFolder() }
                },
                remove: { deletingData in
                    shown = nil
                    removed = ToolRemovalNotice.removing(id, deletingData: deletingData, name: name, store: store,
                                                         strings: text)
                },
                close: { shown = nil })
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

    private func show(_ refused: ExternalToolStore.Refusal) {
        refusal = ToolRefusalMessage(refused, language: l10n.language, strings: text)
    }
}

/// One tool's row: its icon, name, publisher and version, how it stands, a
/// button when only the person can start it again, its switch, and the way
/// into its detail.
private struct ExternalToolRowView: View {
    let row: ExternalToolRow
    let text: ExternalToolStrings
    let setOn: (Bool) -> Void
    let startAgain: () -> Void
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
                        Text(row.byline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let status = row.statusText {
                            ExternalToolStatusLabel(status: row.status, text: status)
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
            .accessibilityLabel([row.name, row.byline, row.statusText].compactMap { $0 }.joined(separator: ". "))
            if row.status == .stopped(canStartAgain: true) {
                Button(text.startAgain, action: startAgain).controlSize(.small)
            }
            Toggle(row.name, isOn: Binding(get: { row.isOn }, set: setOn))
                .labelsHidden()
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

/// One of a tool's own settings in its detail: its title, and a switch, a
/// text field or a number field. A switch saves as it is turned. A field
/// saves when Return is pressed, when the person moves on from it, and when
/// the detail closes. A value the store will not take is put back as it was.
private struct ExternalToolSettingRow: View {
    let setting: ExternalToolSetting
    /// Saves a value. False when it was refused, and nothing was saved.
    let save: (PreferenceDeclaration.Value) -> Bool
    /// What the control holds now, and the last value that was saved.
    @State private var draft: ExternalToolSetting.Control
    @State private var saved: ExternalToolSetting.Control
    @FocusState private var editing: Bool

    init(setting: ExternalToolSetting, save: @escaping (PreferenceDeclaration.Value) -> Bool) {
        self.setting = setting
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
        .onChange(of: editing) { _, isEditing in
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
                .toggleStyle(.switch)
                .controlSize(.small)
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
        }
    }

    private func field(_ field: some View, width: CGFloat) -> some View {
        field
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(width: width)
            .focused($editing)
            .onSubmit { commit(draft) }
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
private struct ExternalToolDetailView: View {
    @ObservedObject private var l10n = L10n.shared
    let detail: ExternalToolDetail
    let log: String
    let removal: ToolRemovalContent
    let text: ExternalToolStrings
    let startAgain: () -> Void
    /// Saves one of the tool's settings, by the preference's id. False when
    /// the value was refused.
    let saveSetting: (String, PreferenceDeclaration.Value) -> Bool
    let reveal: () -> Void
    let openShortcuts: () -> Void
    let update: () -> Void
    let remove: (_ deletingData: Bool) -> Void
    let close: () -> Void
    @State private var confirmingRemoval = false
    @State private var logExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    if let status = detail.row.statusText {
                        HStack(spacing: 10) {
                            ExternalToolStatusLabel(status: detail.row.status, text: status)
                            if detail.row.status == .stopped(canStartAgain: true) {
                                Button(text.startAgain, action: startAgain).controlSize(.small)
                            }
                        }
                    }
                }
            }
            // Only the lists scroll, and only when they are long: the
            // buttons below are always in view.
            if detail.listsScroll {
                ScrollView(.vertical) {
                    lists.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: ToolAgreementContent.listsHeight)
            } else if detail.listRows > 0 {
                lists
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
                Button(text.updateButton, action: update)
                Spacer()
                Button(l10n.s.menuClose, action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onExitCommand(perform: close)
        .alert(removal.title, isPresented: $confirmingRemoval) {
            removalButton(.keepData)
            removalButton(.deleteData)
            removalButton(.cancel)
        } message: {
            Text(removal.message)
        }
    }

    /// The tool's own settings, what it adds, and what it says it uses.
    @ViewBuilder
    private var lists: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !detail.settings.isEmpty {
                section(detail.settingsTitle) {
                    ForEach(detail.settings) { setting in
                        ExternalToolSettingRow(setting: setting, save: { saveSetting(setting.id, $0) })
                    }
                }
            }
            if !detail.commands.isEmpty {
                section(detail.commandsTitle) {
                    ForEach(Array(detail.commands.enumerated()), id: \.offset) {
                        Text($0.element).font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    if detail.offersShortcuts {
                        Button(l10n.s.shortcutsPageTitle, action: openShortcuts).controlSize(.small)
                    }
                }
            }
            if !detail.uses.isEmpty {
                section(detail.usesTitle) {
                    ForEach(Array(detail.uses.enumerated()), id: \.offset) { Text($0.element).font(.callout) }
                    Text(detail.usesNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
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
