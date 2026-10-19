// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol

/// Everything the agreement sheet says about one offer, as plain values, so
/// that what a person is asked to agree to can be checked without drawing
/// anything. The view below shows these and adds no word of its own.
///
/// The sheet is the one safety moment for a tool from outside: the tool
/// will have everything the app has. So it names the tool and the folder it
/// came from, says that one thing in the app's words, and lists what the
/// tool says it uses as what the tool says, never as a limit.
package struct ToolAgreementContent: Equatable {
    package enum Choice: Hashable, Sendable {
        case agree
        case cancel
    }

    /// The button Return presses. It is never the one that adds the tool:
    /// agreeing takes a deliberate click.
    package static let defaultChoice: Choice = .cancel

    /// The most rows the two lists may hold, together, and be drawn whole.
    /// With more they are in a region that scrolls, so that the sheet has
    /// the same height for a tool with seven rows as for one with the most
    /// a tool may have, 32 commands and 7 services.
    package static let rowsDrawnWhole = 6
    /// The height of that region, in points. The rest of the sheet is at
    /// most about 575 points with every line of the tool's own words at
    /// its limit, and about 630 for an update that moves a tool from its
    /// folder onto the catalog (three more lines at most), so the sheet
    /// stays under 800: what is left of a 13-inch display 900 points high
    /// under the menu bar and above the Dock.
    package static let listsHeight: CGFloat = 200
    /// The height of that region in the detail of a tool with a Settings
    /// panel, which holds every setting on one page. In a detail, a search
    /// field and a row of links to its sections sit above the region and
    /// do not scroll. The rest of that detail, those two included, is 518
    /// points at most, with every line of the tool's own words at its
    /// limit, Start Again, an update and its log open, so it too stays
    /// under 800: 788 at its tallest, and 718 for a tool with no Settings
    /// panel, whose region keeps `listsHeight` (`ExternalToolDetailHeightTests`
    /// measures both).
    package static let pageListsHeight: CGFloat = 270

    /// True when a tool with this id is added already, so that agreeing
    /// replaces it.
    package let isUpdate: Bool
    package let title: String
    /// The tool's icon, when this Mac has it, else the plain puzzle piece.
    package let symbol: String
    /// The publisher and the version, as the tool wrote them.
    package let byline: String
    /// The tool's own sentence about itself, in the person's language.
    package let summary: String?
    /// The folder the person picked, or for a tool from the catalog the
    /// address of its source.
    package let from: String
    /// For a tool from the catalog: that VitruvianSoftware listed it and the
    /// download is the one listed. Nil for a folder the person picked.
    package let catalogue: String?
    /// That the name, publisher and description are the tool's own words.
    package let ownWords: String
    /// For an update: the version agreed to before, and this one, which is
    /// the catalog's for an offer from the catalog.
    package let versions: String?
    /// For an update whose manifest is not the bytes agreed to before.
    package let changed: String?
    /// For an update from the catalog of a tool added from a folder: that
    /// it came from that folder and comes from the catalog from now on.
    package let movesToCatalogue: String?
    /// For an update: that what the tool saved is kept.
    package let keepsData: String?
    /// The one sentence the sheet exists to say.
    package let headline: String
    package let detail: String
    package let commandsTitle: String
    /// Each command the tool adds, by its title in the person's language.
    package let commands: [String]
    /// For a tool whose manifest declares a status: that it shows a small
    /// mark on the closed island, and a few words too when its status says
    /// `"activity": true`. One line under the commands, and no row of the
    /// lists. Nil for a tool that declares none.
    package let showsStatus: String?
    package let usesTitle: String
    /// Each of the app's services the tool says it uses, in plain words.
    package let uses: [String]
    /// That the list above is the tool's, and no limit.
    package let usesNote: String
    package let agree: String
    package let cancel: String

    /// The button the keyboard is on when the sheet opens, for an offer to
    /// add and for one to update alike. It is never the one that agrees:
    /// with "Keyboard navigation" on in System Settings, Space presses the
    /// focused button, and macOS puts focus on the first button of the row,
    /// which is the one that agrees.
    package var initialFocus: Choice { .cancel }

    /// How many rows the two lists hold together.
    package var listRows: Int { commands.count + uses.count }
    /// True when the lists are too long to draw whole, and scroll.
    package var listsScroll: Bool { listRows > Self.rowsDrawnWhole }

    /// `cancel` is the app's existing word for Cancel. `hasSymbol` says
    /// whether this Mac has a symbol of that name.
    package init(offer: ToolOffer, language: AppLanguage, strings: ExternalToolStrings, cancel: String,
                 home: String = NSHomeDirectory(),
                 hasSymbol: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }) {
        let tool = offer.tool
        let tag = language.rawValue
        let name = tool.name.text(for: tag) ?? tool.manifest.tool.name
        isUpdate = offer.replaces != nil
        // The name stands inside the app's own sentence, so it is one short
        // line there and cannot turn the sentence round.
        let named = ToolOwnWords.oneLine(name)
        title = isUpdate ? strings.updateTitle(named) : strings.agreeTitle(named)
        symbol = hasSymbol(tool.manifest.tool.symbol) ? tool.manifest.tool.symbol : ExternalToolManifest.defaultSymbol
        byline = "\(tool.publisher) · \(tool.version)"
        summary = tool.summary?.text(for: tag)
        // A tool from the catalog was unpacked into a folder of the app's
        // own; where it comes from is its source.
        from = strings.agreeFrom(offer.catalogue.map { Self.withoutScheme($0.source) }
            ?? Self.abbreviated(offer.folder.path, home: home))
        catalogue = offer.catalogue == nil ? nil : strings.agreeCatalog
        ownWords = strings.agreeOwnWords
        // An offer from the catalog was unpacked into the app's own folder,
        // which the person never sees: its version is the catalog's.
        versions = offer.replaces.map {
            let agreed = ToolOwnWords.oneLine($0.version), offered = ToolOwnWords.oneLine(tool.version)
            return offer.catalogue == nil ? strings.updateVersions(agreed: agreed, offered: offered)
                : strings.updateVersionsFromCatalog(agreed: agreed, offered: offered)
        }
        changed = offer.manifestChanged ? strings.updateChanged : nil
        movesToCatalogue = offer.movesFromFolder.map { strings.updateMovesToCatalog(Self.abbreviated($0, home: home)) }
        keepsData = isUpdate ? strings.updateKeepsData : nil
        headline = strings.agreeHeadline
        detail = strings.agreeDetail
        commandsTitle = strings.commandsTitle
        commands = tool.manifest.tool.commands.map { tool.commandTitles[$0.id]?.text(for: tag) ?? $0.title }
        showsStatus = tool.showsActivity ? strings.agreeShowsStatusAndWords
            : tool.showsStatus ? strings.agreeShowsStatus : nil
        usesTitle = strings.usesTitle
        uses = tool.manifest.capabilities.compactMap { strings.use($0.capability) }
        usesNote = strings.usesNote
        agree = isUpdate ? strings.updateConfirm : strings.agreeAdd
        self.cancel = cancel
    }

    /// An address as a person reads it: `github.com/acme/deploys`.
    package static func withoutScheme(_ address: String) -> String {
        address.hasPrefix("https://") ? String(address.dropFirst("https://".count)) : address
    }

    /// A path with the person's home folder written as a tilde.
    package static func abbreviated(_ path: String, home: String) -> String {
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// Why a folder was not added, in the app's words. It is shown in an alert,
/// which has no line limit of its own: whatever the manifest wrote that a
/// sentence carries is one short line there (`ToolOwnWords`).
package struct ToolRefusalMessage: Equatable {
    package let title: String
    package let message: String
    /// For a folder macOS has quarantined: the command that clears it, for
    /// the person to run themselves. The app never runs it.
    package let command: String?

    /// `numbers` is how a count is written; left out, it is the person's
    /// own region's way, as everywhere in the app.
    package init(title: String, message: String, command: String? = nil) {
        self.title = title
        self.message = message
        self.command = command
    }

    /// `installing` is the name of a tool from the catalog the refusal is
    /// about; nil for a folder the person picked.
    package init(_ refusal: ExternalToolStore.Refusal, language: AppLanguage, strings: ExternalToolStrings,
                 numbers: Locale? = nil, installing: String? = nil) {
        title = installing.map { strings.installRefused(ToolOwnWords.oneLine($0)) } ?? strings.refusalTitle
        var command: String?
        switch refusal {
        case .manifest(.noManifest):
            message = strings.refusalNoManifest
        case .manifest(.invalid(let problem)):
            message = strings.refusalMistake(ToolOwnWords.oneLine(String(describing: problem)))
        case .manifest(.notOfferedHere(let name)):
            message = strings.refusalNeedsNewer(ToolOwnWords.oneLine(name))
        case .manifest(.programMissing(let program)), .manifest(.programOutsideFolder(let program)),
             .manifest(.programNotExecutable(let program)):
            message = strings.refusalProgram(ToolOwnWords.oneLine(program))
        case .quarantined(let folder):
            message = strings.refusalQuarantined
            command = "xattr -dr com.apple.quarantine " + Self.quoted(folder.path)
        case .tooBig(let bytes, let items):
            let number = NumberFormatter()
            number.numberStyle = .decimal
            number.locale = numbers ?? language.formattingLocale()
            message = strings.refusalTooBig(size: "\(bytes / 1_048_576) MB",
                                            items: number.string(from: NSNumber(value: items)) ?? "\(items)")
        case .noSupportFolder, .files, .alreadyInstalled, .changedSinceOffered, .notRemembered:
            message = strings.refusalNotAdded
        }
        self.command = command
    }

    /// A path as one word of a shell command, whatever it holds.
    package static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// The sheet that asks before a tool from outside is added or updated. It
/// is the only place in the app that says the person agreed: the Add button
/// makes the `ToolConsent`, and nothing else may
/// (`only_the_agreement_sheet_consents`).
package struct ToolAgreementSheet: View {
    private let offer: ToolOffer
    private let content: ToolAgreementContent
    private let onAgree: (ToolConsent) -> Void
    private let onCancel: () -> Void
    /// The button the keyboard is on. Nil while it is on neither, which is
    /// always the case with "Keyboard navigation" off: macOS then gives no
    /// button the keyboard, and Space presses nothing.
    @FocusState private var focus: ToolAgreementContent.Choice?
    /// True once the focus macOS gave the sheet as it opened has been seen.
    @State private var focusPlaced = false

    package init(offer: ToolOffer, content: ToolAgreementContent, onAgree: @escaping (ToolConsent) -> Void,
                 onCancel: @escaping () -> Void) {
        self.offer = offer
        self.content = content
        self.onAgree = onAgree
        self.onCancel = onCancel
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if content.isUpdate { update }
            statement
            // Only the two lists scroll. The header, the statement and the
            // buttons are outside the region, so they are always in view.
            if content.listsScroll {
                ScrollView(.vertical) {
                    lists.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: ToolAgreementContent.listsHeight)
            } else if content.listRows > 0 || content.showsStatus != nil {
                lists
            }
            buttons
        }
        .padding(22)
        .frame(width: 480)
        .onExitCommand(perform: onCancel)
        // As the sheet becomes the key window, macOS puts the keyboard on
        // the first button of the row, after `onAppear` and whatever
        // `defaultFocus` or `prefersDefaultFocus` say. So the sheet answers
        // that first placing, once, and moves it. A person who then presses
        // Tab to reach the other button is left alone.
        .onChange(of: focus) { _, placed in
            guard !focusPlaced, let placed else { return }
            focusPlaced = true
            if placed != content.initialFocus { focus = content.initialFocus }
        }
    }

    /// What the tool adds and what it says it uses.
    private var lists: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !content.commands.isEmpty {
                list(content.commandsTitle, content.commands, symbol: "command", lines: 2)
            }
            if let showsStatus = content.showsStatus {
                // The app's own sentence: what the tool adds that is no command.
                Text(showsStatus).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if !content.uses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    list(content.usesTitle, content.uses, symbol: "circle.fill")
                    Text(content.usesNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: content.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                // The tool's own words, and the folder's name, can be any length.
                // Each is cut short, so that none can push the statement or the
                // buttons off the sheet.
                Text(content.title).font(.title3.bold()).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(content.byline).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                if let summary = content.summary {
                    Text(summary).font(.callout).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                Text(content.from)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                if let catalogue = content.catalogue {
                    Text(catalogue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(content.ownWords)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var update: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The two versions are the tool's own words too.
            if let versions = content.versions { Text(versions).lineLimit(3) }
            if let movesToCatalogue = content.movesToCatalogue {
                // The folder's path can be any length: the sentence keeps
                // to three lines, cut in the middle of the path.
                Text(movesToCatalogue).lineLimit(3).truncationMode(.middle)
            }
            if let changed = content.changed {
                Text(changed).fontWeight(.semibold)
            }
            if let keepsData = content.keepsData {
                Text(keepsData).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The one thing the sheet must say, set apart so it cannot be read
    /// past: a plain tinted panel, no effect.
    private var statement: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(content.headline).font(.headline)
                Text(content.detail).font(.callout)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// `lines` is the most lines one item may take; nil for the app's own words.
    private func list(_ title: String, _ items: [String], symbol: String, lines: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(Array(items.enumerated()), id: \.offset) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: symbol == "circle.fill" ? 4 : 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Text(item.element).font(.callout).lineLimit(lines).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Cancel is the default button, so Return and Escape both leave with
    /// nothing added. The button that agrees has no key at all: with
    /// "Keyboard navigation" on, a person reaches it with Tab and presses
    /// it with Space, and it is not where the keyboard starts
    /// (`ToolAgreementContent.initialFocus`).
    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            button(.agree)
            button(.cancel)
        }
    }

    @ViewBuilder
    private func button(_ choice: ToolAgreementContent.Choice) -> some View {
        let plain = Button(choice == .agree ? content.agree : content.cancel) {
            switch choice {
            case .agree: onAgree(ToolConsent(to: offer))
            case .cancel: onCancel()
            }
        }
        .focused($focus, equals: choice)
        if choice == ToolAgreementContent.defaultChoice {
            plain.keyboardShortcut(.defaultAction)
        } else {
            plain
        }
    }
}
