// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol

/// One open panel of a tool from outside, in any place: a small spinner
/// while the tool has not answered, its page once it has, and the app's one
/// sentence when it could not be shown, which says why when the tool's
/// first page was refused. The panel host says which.
package struct ToolPanelView: View {
    package let key: ToolPanelHost.Key
    package let size: BlockTreeContent.Size
    package let focus: FocusState<ExternalToolDetail.Focus?>.Binding?
    /// The items of a page to draw, by their place in it; nil for all. A
    /// search of an extension's settings sheet keeps only what it found.
    package let keeping: Set<Int>?
    /// True in an extension's settings sheet: see `BlockTreeView`.
    package let marksSections: Bool
    @ObservedObject private var host: ToolPanelHost
    @ObservedObject private var l10n = L10n.shared

    package init(key: ToolPanelHost.Key, size: BlockTreeContent.Size,
                 focus: FocusState<ExternalToolDetail.Focus?>.Binding? = nil, keeping: Set<Int>? = nil,
                 marksSections: Bool = false, host: ToolPanelHost = .shared) {
        self.key = key
        self.size = size
        self.focus = focus
        self.keeping = keeping
        self.marksSections = marksSections
        self.host = host
    }

    /// `tree` as this view draws it.
    private func content(_ tree: UITree) -> BlockTreeContent {
        let content = BlockTreeContent(tree: tree, language: l10n.language.rawValue,
                                       folder: ExternalToolStore.shared.installed[key.tool]?.files, size: size)
        return keeping.map(content.keeping) ?? content
    }

    /// Why the tool's page was refused, in the app's language, naming the
    /// tool as its manifest does.
    private func why(_ problem: ToolPanelProblem) -> String {
        FeatureStrings.externalTools(l10n.language)
            .panelRefused(host.name(of: key.tool, language: l10n.language.rawValue), problem)
    }

    package var body: some View {
        switch host.shown[key] {
        case .waiting?:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 44)
        case .page(let tree)?:
            BlockTreeView(
                content: content(tree),
                size: size,
                act: { block, event, value in host.act(key, block: block, event: event, value: value) },
                follow: { host.follow(key, $0) },
                focus: focus,
                marksSections: marksSections,
                revision: host.revisions[key] ?? 0)
        case .web(let page, let folder)?:
            ToolWebPanelView(key: key, page: page, folder: folder)
                .frame(minHeight: size == .island ? 160 : 240)
        case .notShown(let refused)?:
            ToolPanelNotShown(size: size, why: refused.map(why))
        case nil:
            EmptyView()
        }
    }
}

/// Where a panel would be, when it could not be shown: why, when the app
/// knows, or else the app's one sentence that the tool's log says why.
package struct ToolPanelNotShown: View {
    package let size: BlockTreeContent.Size
    /// The sentence that says why, in the app's language; nil for the
    /// one that points to the log.
    package let why: String?
    @ObservedObject private var l10n = L10n.shared

    package init(size: BlockTreeContent.Size, why: String? = nil) {
        self.size = size
        self.why = why
    }

    package var body: some View {
        VStack(spacing: 8) {
            Image(systemName: ExternalToolManifest.defaultSymbol)
                .font(.system(size: size == .island ? 16 : 22, weight: .regular))
                .foregroundStyle(size == .island ? AnyShapeStyle(Color.white.opacity(0.42)) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
            Text(why ?? FeatureStrings.externalTools(l10n.language).panelNotShown)
                .font(size == .island ? .system(size: 11) : .callout)
                .foregroundStyle(size == .island ? AnyShapeStyle(Color.white.opacity(0.62)) : AnyShapeStyle(.secondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}
