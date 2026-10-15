// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol

/// One tool of the catalog, as the sheet lists it. Every word but the
/// button's is the catalog's copy of the tool's own.
package struct CatalogueRow: Identifiable, Equatable {
    package enum Action: Equatable, Sendable {
        case install
        /// Added already, from the catalog with nothing newer, or from a
        /// folder: there is nothing to press.
        case installed
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
}

/// Everything the catalog's sheet says, as plain values.
package struct CatalogueSheetContent: Equatable {
    package enum Body: Equatable {
        /// The list is on its way and there is none to show yet.
        case loading
        /// One sentence in place of the list: it is empty, could not be
        /// fetched, or is not ours.
        case message(String)
        case rows([CatalogueRow])
    }

    package let title: String
    package let body: Body
    package let close: String
    /// The heading over what a tool says it uses, and the note under it.
    package let usesTitle: String

    /// `update` says which added tool has a newer version listed; `close`
    /// is the app's existing word for Close.
    package init(state: CatalogueWatch.State, entries: [CatalogueEntry], listed: [ExternalToolStore.Listed],
                 update: (ExternalToolStore.Listed) -> CatalogueEntry?, language: AppLanguage,
                 strings: ExternalToolStrings, close: String) {
        title = strings.catalogTitle
        self.close = close
        usesTitle = strings.usesTitle
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
                    actionText: [.install: strings.installButton, .installed: strings.installedLabel,
                                 .update: strings.updateNow][action] ?? "")
            })
        }
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

/// The catalog: each tool it lists, with Install, Installed or Update.
/// Installing closes nothing by itself: the section takes the offer to the
/// agreement sheet, which is the one place a tool is agreed to.
package struct ExternalToolCatalogueSheet: View {
    @ObservedObject private var watch: CatalogueWatch
    private let content: (CatalogueWatch.State) -> CatalogueSheetContent
    /// The tool being fetched, if any. Every button waits while one is.
    private let installing: ToolID?
    @Binding private var refusal: ToolRefusalMessage?
    private let install: (CatalogueEntry) -> Void
    private let close: () -> Void

    package init(watch: CatalogueWatch, content: @escaping (CatalogueWatch.State) -> CatalogueSheetContent,
                 installing: ToolID?, refusal: Binding<ToolRefusalMessage?>,
                 install: @escaping (CatalogueEntry) -> Void, close: @escaping () -> Void) {
        self.watch = watch
        self.content = content
        self.installing = installing
        _refusal = refusal
        self.install = install
        self.close = close
    }

    package var body: some View {
        let content = content(watch.state)
        VStack(alignment: .leading, spacing: 16) {
            Text(content.title).font(.title3.bold())
            switch content.body {
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
            case .message(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .rows(let rows):
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            rowView(row, usesTitle: content.usesTitle)
                            if row.id != rows.last?.id { Divider().padding(.leading, 8) }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            HStack {
                Spacer()
                Button(content.close, action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onExitCommand(perform: close)
        .alert(refusal?.title ?? "", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } }),
               presenting: refusal) { _ in
            Button(content.close, role: .cancel) {}
        } message: { refusal in
            Text(refusal.command.map { refusal.message + "\n\n" + $0 } ?? refusal.message)
        }
    }

    private func rowView(_ row: CatalogueRow, usesTitle: String) -> some View {
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
            if installing == row.id {
                ProgressView().controlSize(.small)
            } else if row.action == .installed {
                Text(row.actionText).font(.caption).foregroundStyle(.secondary)
            } else {
                Button(row.actionText) { install(row.entry) }
                    .controlSize(.small)
                    .disabled(installing != nil)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }
}
