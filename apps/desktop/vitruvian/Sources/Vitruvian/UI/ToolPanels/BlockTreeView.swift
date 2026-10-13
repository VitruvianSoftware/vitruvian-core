// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol

/// A page a tool sent, as the app draws it: every word in the person's
/// language and cut to its line limit, every picture found, and nothing
/// the app does not know how to draw. Plain values, so the tests check
/// what a page shows without drawing it.
package struct BlockTreeContent: Equatable {
    /// The island draws smaller, in white on black; Settings and windows
    /// draw at the system's sizes.
    package enum Size: Equatable, Sendable {
        case island, standard
    }

    /// One row of a `row` block or of a `list`.
    package struct Row: Identifiable, Equatable, Sendable {
        package let id: String
        package let title: String
        package let subtitle: String?
        package let symbol: String?
        package let trailing: String?

        package init(id: String, title: String, subtitle: String?, symbol: String?, trailing: String?) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.symbol = symbol
            self.trailing = trailing
        }
    }

    /// One block, ready to draw.
    package enum Kind: Equatable, Sendable {
        case text(String, style: TextBlock.Style, lines: Int)
        case heading(String)
        /// A row; with an id it can be tapped.
        case row(Row, tappable: Bool)
        case button(id: String, title: String, style: ButtonBlock.Style, enabled: Bool)
        case toggle(id: String, title: String, isOn: Bool, enabled: Bool)
        case field(id: String, title: String?, value: String, placeholder: String, kind: FieldBlock.Kind)
        case list(id: String, rows: [Row])
        case progress(value: Double?, label: String?)
        /// A picture, or nil for one the app does not draw: its alt text
        /// stands in.
        case image(ToolPanelImage?, alt: String?, height: Double)
        case divider
        /// A link the app may open; with no address it is drawn as text.
        case link(title: String, url: URL?)
        case spacer(Double)
        /// A block of a kind the app does not know, drawn as its fallback.
        case fallback(String)
    }

    package struct Item: Identifiable, Equatable, Sendable {
        /// Where the block is in the page.
        package let id: Int
        package let kind: Kind
    }

    /// The most characters of a tool's words one text draws. A page may
    /// weigh 256 KB, and no line limit makes a long text cheap to lay out.
    package static let maxCharacters = 2_000
    /// The lines each kind of text takes, at most.
    package static let textLines = 4
    package static let headingLines = 2
    package static let toggleLines = 2
    package static let fallbackLines = 2
    /// The height of a picture that does not say, in points.
    package static func imageHeight(_ size: Size) -> Double { size == .island ? 40 : 64 }
    /// The height of a spacer that does not say, in points.
    package static let spacerSize = 8.0

    package let items: [Item]

    /// `tree` as the app draws it in `language`. A picture is looked for in
    /// `folder`, the app's copy of the tool's folder.
    package init(tree: UITree, language: String, folder: URL?, size: Size) {
        func words(_ text: UIText?) -> String? {
            guard let text else { return nil }
            let shown = text.text(for: language)
            return shown.count > Self.maxCharacters ? String(shown.prefix(Self.maxCharacters - 1)) + "…" : shown
        }
        func row(_ id: String, _ title: UIText, _ subtitle: UIText?, _ icon: String?, _ trailing: UIText?) -> Row {
            Row(id: id, title: words(title) ?? "", subtitle: words(subtitle), symbol: icon, trailing: words(trailing))
        }
        var items: [Item] = []
        for (index, block) in tree.blocks.enumerated() {
            let kind: Kind?
            switch block.content {
            case .text(let text):
                kind = .text(words(text.text) ?? "", style: text.style ?? .body, lines: text.lines ?? Self.textLines)
            case .heading(let heading):
                kind = .heading(words(heading.text) ?? "")
            case .row(let shown):
                kind = .row(row(block.id ?? "", shown.title, shown.subtitle, shown.icon, shown.trailing),
                            tappable: block.id != nil)
            case .button(let button):
                kind = .button(id: block.id ?? "", title: words(button.title) ?? "", style: button.style ?? .plain,
                               enabled: button.enabled ?? true)
            case .toggle(let toggle):
                kind = .toggle(id: block.id ?? "", title: words(toggle.title) ?? "", isOn: toggle.value,
                               enabled: toggle.enabled ?? true)
            case .field(let field):
                kind = .field(id: block.id ?? "", title: words(field.title), value: field.value ?? "",
                              placeholder: words(field.placeholder) ?? "", kind: field.kind ?? .text)
            case .list(let list):
                kind = .list(id: block.id ?? "", rows: list.rows.map { row($0.id, $0.title, $0.subtitle, $0.icon, $0.trailing) })
            case .progress(let progress):
                kind = .progress(value: progress.value, label: words(progress.label))
            case .image(let image):
                kind = .image(folder.flatMap { ToolPanelImage.resolve(image.source, in: $0) }, alt: words(image.alt),
                              height: image.height ?? Self.imageHeight(size))
            case .divider:
                kind = .divider
            case .link(let link):
                let url = URL(string: link.url).flatMap { url in
                    url.scheme.map { ToolPanelHost.linkSchemes.contains($0.lowercased()) } == true ? url : nil
                }
                kind = .link(title: words(link.title) ?? "", url: url)
            case .spacer(let spacer):
                kind = .spacer(spacer.size ?? Self.spacerSize)
            case .unknown:
                kind = words(block.fallback).map(Kind.fallback)
            case .choice:
                // Read, and not drawn yet: its fallback stands in, as for a
                // kind the app does not know.
                kind = words(block.fallback).map(Kind.fallback)
            }
            if let kind { items.append(Item(id: index, kind: kind)) }
        }
        self.items = items
    }
}

/// The look of a page in each place: the island's own small white type, or
/// the system's.
private struct BlockMetrics {
    let size: BlockTreeContent.Size

    var spacing: CGFloat { size == .island ? 8 : 10 }
    var body: Font { size == .island ? .system(size: 12) : .callout }
    var caption: Font { size == .island ? .system(size: 10.5) : .caption }
    var heading: Font { size == .island ? .system(size: 13, weight: .semibold) : .headline }
    var rowTitle: Font { size == .island ? .system(size: 12, weight: .semibold) : .body }
    var fill: Color { size == .island ? Color.white.opacity(0.08) : Color.primary.opacity(0.045) }
    var secondary: Color { size == .island ? Color.white.opacity(0.62) : Color.secondary }
    var tertiary: Color { size == .island ? Color.white.opacity(0.42) : Color(nsColor: .tertiaryLabelColor) }
    var monospaced: Font { size == .island ? .system(size: 10.5, design: .monospaced) : .caption.monospaced() }
}

/// A page a tool sent, drawn with the app's own controls. A tool's words
/// are drawn as plain text with a line limit, never as markdown and never
/// as a link of their own.
package struct BlockTreeView: View {
    package let content: BlockTreeContent
    package let size: BlockTreeContent.Size
    /// What the person did: the block's id, the event, and its value.
    package let act: (String, UIEventKind, JSONValue?) -> Void
    /// The person clicked a link block.
    package let follow: (URL) -> Void
    /// The focus of the view the page is drawn in, when that view keeps one
    /// for every control: a tool's detail in Settings.
    package let focus: FocusState<ExternalToolDetail.Focus?>.Binding?

    package init(content: BlockTreeContent, size: BlockTreeContent.Size,
                 act: @escaping (String, UIEventKind, JSONValue?) -> Void, follow: @escaping (URL) -> Void,
                 focus: FocusState<ExternalToolDetail.Focus?>.Binding? = nil) {
        self.content = content
        self.size = size
        self.act = act
        self.follow = follow
        self.focus = focus
    }

    private var metrics: BlockMetrics { BlockMetrics(size: size) }

    package var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            ForEach(content.items) { item in
                block(item.kind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(size == .island ? Color.white : Color.primary)
    }

    @ViewBuilder
    private func block(_ kind: BlockTreeContent.Kind) -> some View {
        switch kind {
        case .text(let text, let style, let lines):
            Text(verbatim: text)
                .font(style == .monospaced ? metrics.monospaced : style == .caption ? metrics.caption : metrics.body)
                .foregroundStyle(style == .body || style == .monospaced ? AnyShapeStyle(.primary) : AnyShapeStyle(metrics.secondary))
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .heading(let text):
            Text(verbatim: text).font(metrics.heading).lineLimit(BlockTreeContent.headingLines)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .row(let row, let tappable):
            if tappable {
                Button { act(row.id, .tap, nil) } label: { rowLabel(row, chevron: true) }
                    .buttonStyle(.plain)
                    .modifier(Focused(focus: focus, id: row.id))
            } else {
                rowLabel(row, chevron: false)
            }
        case .button(let id, let title, let style, let enabled):
            button(id: id, title: title, style: style)
                .disabled(!enabled)
                .modifier(Focused(focus: focus, id: id))
        case .toggle(let id, let title, let isOn, let enabled):
            Toggle(isOn: Binding(get: { isOn }, set: { act(id, .toggle, .bool($0)) })) {
                Text(verbatim: title).font(metrics.body).lineLimit(BlockTreeContent.toggleLines)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!enabled)
            .modifier(Focused(focus: focus, id: id))
        case .field(let id, let title, let value, let placeholder, let kind):
            BlockField(id: id, title: title, value: value, placeholder: placeholder, kind: kind,
                       metrics: metrics, focus: focus, act: act)
        case .list(let id, let rows):
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Button { act(id, .tap, .string(row.id)) } label: { rowLabel(row, chevron: false) }
                        .buttonStyle(.plain)
                        .modifier(Focused(focus: focus, id: id + "/" + row.id))
                    if index < rows.count - 1 { Divider().padding(.leading, 8) }
                }
            }
            .background(metrics.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .progress(let value, let label):
            VStack(alignment: .leading, spacing: 4) {
                if let label {
                    Text(verbatim: label).font(metrics.caption).foregroundStyle(metrics.secondary).lineLimit(1)
                }
                if let value {
                    ProgressView(value: value).progressViewStyle(.linear)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .controlSize(.small)
        case .image(let image, let alt, let height):
            BlockImage(image: image, alt: alt, height: height, metrics: metrics)
        case .divider:
            Divider()
        case .link(let title, let url):
            if let url {
                Button { follow(url) } label: { Text(verbatim: title).lineLimit(1) }
                    .buttonStyle(.link)
                    .font(metrics.body)
                    .modifier(Focused(focus: focus, id: url.absoluteString))
            } else {
                Text(verbatim: title).font(metrics.body).lineLimit(1)
            }
        case .spacer(let height):
            Color.clear.frame(height: height)
        case .fallback(let text):
            Text(verbatim: text).font(metrics.caption).italic().foregroundStyle(metrics.secondary)
                .lineLimit(BlockTreeContent.fallbackLines)
        }
    }

    private func rowLabel(_ row: BlockTreeContent.Row, chevron: Bool) -> some View {
        HStack(spacing: 10) {
            if let symbol = row.symbol {
                Image(systemName: symbol)
                    .font(.system(size: size == .island ? 11 : 13, weight: .medium))
                    .foregroundStyle(size == .island ? metrics.secondary : Color.accentColor)
                    .frame(width: size == .island ? 16 : 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.title).font(metrics.rowTitle).lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(verbatim: subtitle).font(metrics.caption).foregroundStyle(metrics.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailing = row.trailing {
                Text(verbatim: trailing).font(metrics.caption).foregroundStyle(metrics.tertiary).lineLimit(1)
                    .monospacedDigit()
            }
            if chevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(metrics.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, size == .island ? 6 : 7)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func button(id: String, title: String, style: ButtonBlock.Style) -> some View {
        let label = Text(verbatim: title).lineLimit(1)
        switch style {
        case .plain:
            Button { act(id, .tap, nil) } label: { label }.controlSize(.small)
        case .prominent:
            Button { act(id, .tap, nil) } label: { label }.buttonStyle(.borderedProminent).controlSize(.small)
        case .destructive:
            Button(role: .destructive) { act(id, .tap, nil) } label: { label }.controlSize(.small)
        }
    }
}

/// Binds a control to the focus of the view the page is in, when it keeps
/// one: every control of a tool's detail is bound to one focus, so the first
/// focus macOS places can be moved.
private struct Focused: ViewModifier {
    let focus: FocusState<ExternalToolDetail.Focus?>.Binding?
    let id: String

    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus, equals: .panel(id))
        } else {
            content
        }
    }
}

/// A field: Return sends `submit`, and leaving it with other text sends
/// `change`, each with the text. What is typed stays here until then.
private struct BlockField: View {
    let id: String
    let title: String?
    let value: String
    let placeholder: String
    let kind: FieldBlock.Kind
    let metrics: BlockMetrics
    let focus: FocusState<ExternalToolDetail.Focus?>.Binding?
    let act: (String, UIEventKind, JSONValue?) -> Void
    @State private var text: String = ""
    @State private var sent: String = ""
    @FocusState private var own: Bool

    private var isFocused: Bool { focus.map { $0.wrappedValue == .panel(id) } ?? own }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title {
                Text(verbatim: title).font(metrics.caption).foregroundStyle(metrics.secondary).lineLimit(1)
            }
            field
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .onSubmit {
                    sent = text
                    act(id, .submit, .string(text))
                }
        }
        .onAppear {
            text = value
            sent = value
        }
        .onChange(of: value) { _, new in
            text = new
            sent = new
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused, text != sent else { return }
            sent = text
            act(id, .change, .string(text))
        }
    }

    @ViewBuilder
    private var field: some View {
        let prompt = Text(verbatim: placeholder)
        let label = Text(verbatim: title ?? "")
        if kind == .secret {
            bound(SecureField(text: $text, prompt: prompt) { label })
        } else {
            bound(TextField(text: $text, prompt: prompt) { label }
                .onChange(of: text) { _, typed in
                    // A number field keeps digits, one point and a leading minus.
                    guard kind == .number else { return }
                    let kept = BlockField.number(typed)
                    if kept != typed { text = kept }
                })
        }
    }

    @ViewBuilder
    private func bound(_ control: some View) -> some View {
        if let focus {
            control.focused(focus, equals: .panel(id))
        } else {
            control.focused($own)
        }
    }

    /// What a number field keeps of what was typed.
    static func number(_ typed: String) -> String {
        var kept = ""
        var point = false
        for (index, character) in typed.enumerated() {
            if character.isASCII, character.isNumber {
                kept.append(character)
            } else if character == ".", !point {
                point = true
                kept.append(character)
            } else if character == "-", index == 0 {
                kept.append(character)
            }
        }
        return kept
    }
}

/// A picture of the tool's, read from its folder or from its own bytes. One
/// that cannot be drawn shows its alt text, or nothing.
private struct BlockImage: View {
    let image: ToolPanelImage?
    let alt: String?
    let height: Double
    let metrics: BlockMetrics

    var body: some View {
        if let picture = loaded {
            Image(nsImage: picture)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .accessibilityLabel(Text(verbatim: alt ?? ""))
                .accessibilityHidden(alt == nil)
        } else if let alt {
            Text(verbatim: alt).font(metrics.caption).foregroundStyle(metrics.secondary).lineLimit(1)
        }
    }

    private var loaded: NSImage? {
        switch image {
        case .file(let url)?: return NSImage(contentsOf: url)
        case .bytes(let data)?: return NSImage(data: data)
        case nil: return nil
        }
    }
}
