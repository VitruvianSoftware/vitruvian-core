// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol

/// One tool of the catalog, as the Extensions page lists it. Every word but
/// the button's is the catalog's copy of the tool's own.
package struct CatalogueRow: Identifiable, Equatable {
    package enum Action: Equatable, Sendable {
        case install
        /// Added already, with nothing newer listed: there is nothing to
        /// press.
        case installed
        /// Added already, from the catalog or from a folder, and the catalog
        /// lists a newer version.
        case update
    }

    package let entry: CatalogueEntry
    package var id: ToolID { entry.id }
    package let name: String
    /// The publisher and the version, as the catalog copies them.
    package let byline: String
    /// The pill beside the byline ("Extension" or "Tool", in the person's
    /// language), when the entry carries `panels`; nil when it predates
    /// `panels`.
    package let kindBadge: String?
    package let summary: String
    /// What the tool says it uses, in the app's plain words.
    package let uses: [String]
    package let action: Action
    package let actionText: String
    /// What VoiceOver says for the button: its words, then the tool's name.
    package var actionSpoken: String { ExtensionsPageContent.spoken(actionText, name: name) }
}

/// Everything the catalog says, as plain values: on the Extensions page
/// since it has one (before, on the sheet "Browse Tools…" opened, hence the
/// name).
package struct CatalogueSheetContent: Equatable {
    package enum Body: Equatable {
        /// The list is on its way and there is none to show yet.
        case loading
        /// One sentence in place of the list: it is empty, could not be
        /// fetched, or is not ours.
        case message(String)
        case rows([CatalogueRow])
    }

    /// The quiet line at the foot of the catalog's card: where to start
    /// building one's own, with the SDK's name as the link. The sentence is
    /// split around the name, so the name is a link wherever a language
    /// puts it.
    package struct SDKLine: Equatable {
        /// The SDK's name, the same in every language.
        package static let name = "Vitruvian SDK"

        package let before: String
        /// The words that are the link: `name`, or the whole sentence when a
        /// language's sentence lacks the name.
        package let link: String
        package let after: String
        package let url: URL
        /// The whole sentence, as VoiceOver reads it.
        package var sentence: String { before + link + after }

        package init(_ sentence: String, url: URL) {
            self.url = url
            guard let range = sentence.range(of: Self.name) else {
                (before, link, after) = ("", sentence, "")
                return
            }
            before = String(sentence[..<range.lowerBound])
            link = Self.name
            after = String(sentence[range.upperBound...])
        }
    }

    package let title: String
    package let body: Body
    /// The heading over what a tool says it uses, and the note under it.
    package let usesTitle: String
    /// Under the list, whatever the list is doing: loading, empty, out of
    /// reach, refused or listed.
    package let sdk: SDKLine
    /// The one line in place of the rows when every tool listed is added.
    private let allInstalled: String

    /// `update` says which added tool has a newer version listed.
    package init(state: CatalogueWatch.State, entries: [CatalogueEntry], listed: [ExternalToolStore.Listed],
                 update: (ExternalToolStore.Listed) -> CatalogueEntry?, language: AppLanguage,
                 strings: ExternalToolStrings) {
        title = strings.catalogTitle
        usesTitle = strings.usesTitle
        sdk = SDKLine(strings.sdkLine, url: AppInfo.sdkURL)
        allInstalled = strings.catalogAllInstalled
        switch state {
        case .unknown, .loading:
            body = .loading
        case .unreachable:
            body = .message(strings.catalogUnreachable)
        case .notOurs:
            body = .message(strings.catalogNotOurs)
        case .ready where entries.isEmpty:
            body = .message(strings.catalogEmpty)
        case .ready:
            let tag = language.rawValue
            body = .rows(entries.map { entry in
                let added = listed.first { $0.id == entry.id }
                let action: CatalogueRow.Action = added == nil ? .install
                    : added.flatMap(update)?.id == entry.id ? .update : .installed
                return CatalogueRow(
                    entry: entry,
                    name: ToolOwnWords.oneLine(entry.name.text(for: tag) ?? entry.id.rawValue),
                    byline: "\(ToolOwnWords.oneLine(entry.publisher)) · \(entry.version)",
                    kindBadge: entry.panels.map { $0.isEmpty ? strings.kindTool : strings.kindExtension },
                    summary: entry.summary.text(for: tag) ?? "",
                    uses: entry.uses.compactMap { Capability(rawValue: $0).flatMap(strings.use) },
                    action: action,
                    actionText: action == .update ? added.map { ExternalToolRow.updateWords($0, strings: strings) } ?? ""
                        : action == .install ? strings.installButton : strings.installedLabel)
            })
        }
    }

    /// The catalog as the Extensions page lists it, under what is installed:
    /// only the tools that are not added. One that is, from the catalog or
    /// from a folder, is in the Installed list, which offers its update.
    /// When the catalog lists nothing else, one line says so; waiting, an
    /// empty catalog and a refusal are as they are.
    package var notInstalled: Body {
        guard case .rows(let rows) = body else { return body }
        let left = rows.filter { $0.action == .install }
        return left.isEmpty ? .message(allInstalled) : .rows(left)
    }
}

extension ToolRefusalMessage {
    /// Why a tool from the catalog was not offered, under the title that
    /// names it. A refusal of the store's is said as for a folder.
    package init(catalogue refusal: CatalogueRefusal, name: String, language: AppLanguage,
                 strings: ExternalToolStrings) {
        switch refusal {
        case .store(let refused):
            self.init(refused, language: language, strings: strings, installing: name)
        case .unreachable:
            self.init(title: strings.installRefused(ToolOwnWords.oneLine(name)), message: strings.catalogUnreachable)
        case .mismatch:
            self.init(title: strings.installRefused(ToolOwnWords.oneLine(name)), message: strings.downloadMismatch)
        case .notTheTool:
            self.init(title: strings.installRefused(ToolOwnWords.oneLine(name)), message: strings.downloadNotTheTool)
        }
    }
}

/// One tool of the catalog: its name, publisher and version, kind pill,
/// summary and what it says it uses, and its button. Installing closes
/// nothing by itself: the page takes the offer to the agreement sheet, which
/// is the one place a tool is agreed to.
struct CatalogueRowView: View {
    let row: CatalogueRow
    let usesTitle: String
    /// How the button is drawn while a tool is fetched or added.
    let button: ExtensionsPageContent.InstallButton
    let install: (CatalogueEntry) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ExternalToolManifest.defaultSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).lineLimit(1)
                HStack(spacing: 6) {
                    Text(row.byline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let badge = row.kindBadge {
                        ExternalToolKindBadge(text: badge)
                    }
                }
                Text(row.summary).font(.callout).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if !row.uses.isEmpty {
                    // The app's own words for each service, one to a line,
                    // as on the agreement sheet.
                    Text(usesTitle).font(.caption.weight(.semibold)).padding(.top, 3)
                    ForEach(Array(row.uses.enumerated()), id: \.offset) { use in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(use.element).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            if button == .progress {
                ProgressView().controlSize(.small)
            } else if row.action == .installed {
                Text(row.actionText).font(.caption).foregroundStyle(.secondary)
            } else {
                Button(row.actionText) { install(row.entry) }
                    .controlSize(.small)
                    .disabled(button == .disabled)
                    .accessibilityLabel(row.actionSpoken)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }
}

/// The catalog card's last line. The sentence is in the page's quiet grey
/// and the SDK's name in the link colour; the whole line is one `Link`, the
/// control the About page uses for GitHub, so it opens the SDK in the
/// default browser.
struct CatalogueSDKLineView: View {
    let line: CatalogueSheetContent.SDKLine

    var body: some View {
        Link(destination: line.url) {
            Text(line.before).foregroundStyle(.secondary)
                + Text(line.link).foregroundStyle(Color.accentColor)
                + Text(line.after).foregroundStyle(.secondary)
        }
        .font(.callout)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(line.sentence)
    }
}
