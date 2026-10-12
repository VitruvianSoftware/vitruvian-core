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
    package enum Choice: Equatable, Sendable {
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
    /// its limit, so the sheet stays under 800: what is left of a 13-inch
    /// display 900 points high under the menu bar and above the Dock.
    package static let listsHeight: CGFloat = 200

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
    /// The folder the person picked.
    package let from: String
    /// That the name, publisher and description are the tool's own words.
    package let ownWords: String
    /// For an update: the version agreed to before, and this one.
    package let versions: String?
    /// For an update whose manifest is not the bytes agreed to before.
    package let changed: String?
    /// For an update: that what the tool saved is kept.
    package let keepsData: String?
    /// The one sentence the sheet exists to say.
    package let headline: String
    package let detail: String
    package let commandsTitle: String
    /// Each command the tool adds, by its title in the person's language.
    package let commands: [String]
    package let usesTitle: String
    /// Each of the app's services the tool says it uses, in plain words.
    package let uses: [String]
    /// That the list above is the tool's, and no limit.
    package let usesNote: String
    package let agree: String
    package let cancel: String

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
        from = strings.agreeFrom(Self.abbreviated(offer.folder.path, home: home))
        ownWords = strings.agreeOwnWords
        versions = offer.replaces.map {
            strings.updateVersions(agreed: ToolOwnWords.oneLine($0.version), offered: ToolOwnWords.oneLine(tool.version))
        }
        changed = offer.manifestChanged ? strings.updateChanged : nil
        keepsData = isUpdate ? strings.updateKeepsData : nil
        headline = strings.agreeHeadline
        detail = strings.agreeDetail
        commandsTitle = strings.commandsTitle
        commands = tool.manifest.tool.commands.map { tool.commandTitles[$0.id]?.text(for: tag) ?? $0.title }
        usesTitle = strings.usesTitle
        uses = tool.manifest.capabilities.compactMap { strings.use($0.capability) }
        usesNote = strings.usesNote
        agree = isUpdate ? strings.updateConfirm : strings.agreeAdd
        self.cancel = cancel
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
    package init(_ refusal: ExternalToolStore.Refusal, language: AppLanguage, strings: ExternalToolStrings,
                 numbers: Locale? = nil) {
        title = strings.refusalTitle
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
            } else if content.listRows > 0 {
                lists
            }
            buttons
        }
        .padding(22)
        .frame(width: 480)
        .onExitCommand(perform: onCancel)
    }

    /// What the tool adds and what it says it uses.
    private var lists: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !content.commands.isEmpty {
                list(content.commandsTitle, content.commands, symbol: "command", lines: 2)
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
    /// nothing added. The button that agrees has no key at all.
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
        if choice == ToolAgreementContent.defaultChoice {
            plain.keyboardShortcut(.defaultAction)
        } else {
            plain
        }
    }
}
