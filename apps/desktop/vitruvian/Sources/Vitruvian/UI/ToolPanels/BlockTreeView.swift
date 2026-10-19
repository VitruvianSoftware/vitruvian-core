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

    /// One option of chips: what its event carries, what it says, whether
    /// it is on, and whether it can be turned. Only a chip that cannot be
    /// turned has a reason: why not.
    package struct Chip: Identifiable, Equatable, Sendable {
        package let value: String
        package let title: String
        package let on: Bool
        package let enabled: Bool
        package let reason: String?

        package var id: String { value }

        package init(value: String, title: String, on: Bool, enabled: Bool, reason: String?) {
            self.value = value
            self.title = title
            self.on = on
            self.enabled = enabled
            self.reason = reason
        }
    }

    /// One block, ready to draw. A control's `help` is a line or two drawn
    /// under it.
    package enum Kind: Equatable, Sendable {
        case text(String, style: TextBlock.Style, lines: Int)
        /// A heading; one that starts a section is drawn a little larger,
        /// with more room above it, and is listed in `sections`.
        case heading(String, section: Bool)
        /// A row; with an id it can be tapped.
        case row(Row, tappable: Bool)
        case button(id: String, title: String, style: ButtonBlock.Style, enabled: Bool)
        case toggle(id: String, title: String, isOn: Bool, enabled: Bool, help: String?)
        case field(id: String, title: String?, value: String, placeholder: String, kind: FieldBlock.Kind, help: String?)
        case list(id: String, rows: [Row])
        case progress(value: Double?, label: String?)
        /// A picture, or nil for one the app does not draw: its alt text
        /// stands in.
        case image(ToolPanelImage?, alt: String?, height: Double)
        case divider
        /// A link the app may open; with no address it is drawn as text.
        case link(title: String, url: URL?)
        case spacer(Double)
        /// A pop-up menu: its title, the selected value and its rows. A
        /// value that is no option's is an extra first row, as written.
        case choice(id: String, title: String?, selected: String, options: [ExternalToolSetting.Choice], enabled: Bool,
                    help: String?)
        /// Chips: options each on or off, any number at once, drawn as a
        /// row of small buttons that wraps.
        case chips(id: String, title: String?, options: [Chip], enabled: Bool, help: String?)
        /// A block of a kind the app does not know, drawn as its fallback.
        case fallback(String)
    }

    package struct Item: Identifiable, Equatable, Sendable {
        /// Where the block is in the page.
        package let id: Int
        package let kind: Kind

        /// Whether it is a heading that starts a section.
        package var isSection: Bool {
            if case .heading(_, section: true) = kind { return true }
            return false
        }
    }

    /// The most characters of a tool's words one text draws. A page may
    /// weigh 256 KB, and no line limit makes a long text cheap to lay out.
    package static let maxCharacters = 2_000
    /// The lines each kind of text takes, at most.
    package static let textLines = 4
    package static let headingLines = 2
    package static let toggleLines = 2
    package static let fallbackLines = 2
    package static let helpLines = 2
    /// The height of a picture that does not say, in points.
    package static func imageHeight(_ size: Size) -> Double { size == .island ? 40 : 64 }
    /// The height of a spacer that does not say, in points.
    package static let spacerSize = 8.0

    package let items: [Item]

    /// The page's sections, in order: each section heading's words and the
    /// `id` of its item, its place in the page.
    package var sections: [(title: String, index: Int)] {
        items.compactMap { item in
            guard case .heading(let title, section: true) = item.kind else { return nil }
            return (title, item.id)
        }
    }

    /// Turns the chip of `value`, of the chips `id`: `act` is told `change`
    /// with the values of every chip then on, in the options' order. Chips
    /// that are not enabled, a chip that is not, or a value that is no
    /// chip's tell it nothing.
    package static func turnChip(_ value: String, of id: String, options: [Chip], enabled: Bool,
                                 act: (String, UIEventKind, JSONValue?) -> Void) {
        guard enabled, let turned = options.first(where: { $0.value == value }), turned.enabled else { return }
        let on = options.filter { $0.value == value ? !$0.on : $0.on }.map { JSONValue.string($0.value) }
        act(id, .change, .array(on))
    }

    /// Where chips of `sizes` go in `width`: in rows, each chip after the
    /// last with `spacing` between, a chip that does not fit starting the
    /// next row, and a chip wider than `width` cut to it.
    package static func chipFrames(_ sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for size in sizes {
            let chipWidth = min(size.width, max(width, 0))
            if x > 0, x + chipWidth > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: chipWidth, height: size.height))
            x += chipWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }

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
                kind = .heading(words(heading.text) ?? "", section: heading.section ?? false)
            case .row(let shown):
                kind = .row(row(block.id ?? "", shown.title, shown.subtitle, shown.icon, shown.trailing),
                            tappable: block.id != nil)
            case .button(let button):
                kind = .button(id: block.id ?? "", title: words(button.title) ?? "", style: button.style ?? .plain,
                               enabled: button.enabled ?? true)
            case .toggle(let toggle):
                kind = .toggle(id: block.id ?? "", title: words(toggle.title) ?? "", isOn: toggle.value,
                               enabled: toggle.enabled ?? true, help: words(toggle.help))
            case .field(let field):
                kind = .field(id: block.id ?? "", title: words(field.title), value: field.value ?? "",
                              placeholder: words(field.placeholder) ?? "", kind: field.kind ?? .text,
                              help: words(field.help))
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
            // Chips are drawn as their fallback until the app draws them
            // and names `ProtocolFeature.chips`.
            case .unknown, .chips:
                kind = words(block.fallback).map(Kind.fallback)
            case .choice(let choice):
                let options = choice.options.map { (value: $0.value, title: $0.title.text(for: language)) }
                kind = .choice(id: block.id ?? "", title: words(choice.title), selected: choice.value,
                               options: ExternalToolSetting.Choice.menu(selected: choice.value, options: options,
                                                                        limit: ToolOwnWords.limit),
                               enabled: choice.enabled ?? true, help: words(choice.help))
            case .chips(let chips):
                kind = .chips(id: block.id ?? "", title: words(chips.title),
                              options: chips.options.map { option in
                                  let enabled = option.enabled ?? true
                                  return Chip(value: option.value,
                                              title: ToolOwnWords.oneLine(option.title.text(for: language)),
                                              on: option.on, enabled: enabled,
                                              reason: enabled ? nil : words(option.reason))
                              },
                              enabled: chips.enabled ?? true, help: words(chips.help))
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
    /// A heading that starts a section: a step larger than a heading.
    var section: Font { size == .island ? .system(size: 14, weight: .bold) : .title3.weight(.semibold) }
    /// The room above a section heading, beyond the page's spacing.
    var sectionRoom: CGFloat { size == .island ? 4 : 8 }
    var chip: Font { size == .island ? .system(size: 11, weight: .medium) : .callout }
    var chipPadding: EdgeInsets {
        size == .island ? EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9)
            : EdgeInsets(top: 4, leading: 11, bottom: 4, trailing: 11)
    }
    var chipSpacing: CGFloat { size == .island ? 5 : 6 }
    /// An off chip's outline.
    var chipOutline: Color { size == .island ? Color.white.opacity(0.3) : Color.primary.opacity(0.22) }
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
    /// What is typed in the page's fields and not yet sent. Clicking a
    /// button on macOS leaves the field focused, so it is sent here, before
    /// the click, or the tool acts on what it had before.
    @State private var pending: PendingFields

    package init(content: BlockTreeContent, size: BlockTreeContent.Size,
                 act: @escaping (String, UIEventKind, JSONValue?) -> Void, follow: @escaping (URL) -> Void,
                 focus: FocusState<ExternalToolDetail.Focus?>.Binding? = nil) {
        self.content = content
        self.size = size
        self.act = act
        self.follow = follow
        self.focus = focus
        _pending = State(initialValue: PendingFields())
    }

    /// `act` for every control but a field: the fields' unsent text first.
    private var send: (String, UIEventKind, JSONValue?) -> Void { pending.flushing(into: act) }

    private var metrics: BlockMetrics { BlockMetrics(size: size) }

    package var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            ForEach(content.items) { item in
                block(item.kind)
                    .padding(.top, item.isSection && item.id != content.items.first?.id ? metrics.sectionRoom : 0)
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
        case .heading(let text, let section):
            Text(verbatim: text).font(section ? metrics.section : metrics.heading)
                .lineLimit(BlockTreeContent.headingLines)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .row(let row, let tappable):
            if tappable {
                Button { send(row.id, .tap, nil) } label: { rowLabel(row, chevron: true) }
                    .buttonStyle(.plain)
                    .modifier(Focused(focus: focus, id: row.id))
            } else {
                rowLabel(row, chevron: false)
            }
        case .button(let id, let title, let style, let enabled):
            button(id: id, title: title, style: style)
                .disabled(!enabled)
                .modifier(Focused(focus: focus, id: id))
        case .toggle(let id, let title, let isOn, let enabled, let help):
            // Laid out as a choice is: the title leading, the switch at the
            // trailing edge, so a page's switches and menus line up. A long
            // title wraps before it reaches the switch. The switch carries
            // the title as its name; the drawn title is not read twice.
            helped(help) {
                HStack(spacing: 10) {
                    Text(verbatim: title).font(metrics.body).lineLimit(BlockTreeContent.toggleLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    Toggle(title, isOn: Binding(get: { isOn }, set: { send(id, .toggle, .bool($0)) }))
                        .labelsHidden()
                        .controlNamed(title)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .fixedSize()
                        .disabled(!enabled)
                        .modifier(Focused(focus: focus, id: id))
                }
            }
        case .field(let id, let title, let value, let placeholder, let kind, let help):
            helped(help) {
                BlockField(id: id, title: title, value: value, placeholder: placeholder, kind: kind,
                           metrics: metrics, focus: focus, pending: pending, act: act)
            }
        case .list(let id, let rows):
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Button { send(id, .tap, .string(row.id)) } label: { rowLabel(row, chevron: false) }
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
        case .choice(let id, let title, let selected, let options, let enabled, let help):
            helped(help) {
                HStack(spacing: 10) {
                    if let title {
                        Text(verbatim: title).font(metrics.body).lineLimit(BlockTreeContent.toggleLines)
                    }
                    Spacer(minLength: 8)
                    // A pick is the event a field's change is, with the
                    // option's value. The page is the tool's to send again.
                    Picker(title ?? "",
                           selection: Binding(get: { selected }, set: { send(id, .change, .string($0)) })) {
                        // The tool's own words: plain text, one line each.
                        ForEach(options) { Text(verbatim: $0.title).tag($0.value) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(!enabled)
                    .modifier(Focused(focus: focus, id: id))
                }
            }
        case .chips(let id, let title, let options, let enabled, let help):
            helped(help) {
                VStack(alignment: .leading, spacing: 6) {
                    if let title {
                        Text(verbatim: title).font(metrics.body).lineLimit(BlockTreeContent.toggleLines)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ChipFlow(spacing: metrics.chipSpacing) {
                        ForEach(options) { chip in
                            self.chip(chip, of: id, options: options, enabled: enabled)
                        }
                    }
                }
            }
        case .fallback(let text):
            Text(verbatim: text).font(metrics.caption).italic().foregroundStyle(metrics.secondary)
                .lineLimit(BlockTreeContent.fallbackLines)
        }
    }

    /// A control with its help, if it has any: a caption line or two
    /// directly under it.
    @ViewBuilder
    private func helped(_ help: String?, @ViewBuilder _ control: () -> some View) -> some View {
        if let help {
            VStack(alignment: .leading, spacing: 3) {
                control()
                Text(verbatim: help).font(metrics.caption).foregroundStyle(metrics.secondary)
                    .lineLimit(BlockTreeContent.helpLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            control()
        }
    }

    /// One chip: a small capsule that is filled while it is on and outlined
    /// while it is off. To VoiceOver it is a switch named by its title. One
    /// that cannot be turned is dimmed, says why when pointed at and to
    /// VoiceOver, and does nothing when tapped.
    private func chip(_ chip: BlockTreeContent.Chip, of id: String, options: [BlockTreeContent.Chip],
                      enabled: Bool) -> some View {
        let turns = enabled && chip.enabled
        return Toggle(isOn: Binding(get: { chip.on }, set: { _ in
            BlockTreeContent.turnChip(chip.value, of: id, options: options, enabled: enabled, act: send)
        })) {
            Text(verbatim: chip.title).lineLimit(1).truncationMode(.tail)
        }
        .toggleStyle(ChipStyle(metrics: metrics, turns: turns))
        .controlNamed(chip.title)
        .disabled(!turns)
        .modifier(Why(reason: chip.reason))
        .modifier(Focused(focus: focus, id: id + "/" + chip.value))
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
            Button { send(id, .tap, nil) } label: { label }.controlSize(.small)
        case .prominent:
            Button { send(id, .tap, nil) } label: { label }.buttonStyle(.borderedProminent).controlSize(.small)
        case .destructive:
            Button(role: .destructive) { send(id, .tap, nil) } label: { label }.controlSize(.small)
        }
    }
}

/// A chip's look: a capsule of the accent colour while it is on, an
/// outline while it is off, and dimmed when it cannot be turned.
private struct ChipStyle: ToggleStyle {
    let metrics: BlockMetrics
    let turns: Bool

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .font(metrics.chip)
                .foregroundStyle(configuration.isOn || metrics.size == .island ? Color.white : Color.primary)
                .padding(metrics.chipPadding)
                .background {
                    if configuration.isOn {
                        Capsule(style: .continuous).fill(Color.accentColor)
                    } else {
                        Capsule(style: .continuous).strokeBorder(metrics.chipOutline, lineWidth: 1)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(turns ? 1 : 0.4)
        // Read as a switch, on or off, as the app's other on-off buttons are.
        .accessibilityAddTraits(.isToggle)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
        .accessibilityValue(configuration.isOn ? "1" : "0")
    }
}

/// Why a chip cannot be turned, when it cannot: shown when the pointer
/// rests on it, and said to VoiceOver after its name. Outside the chip's
/// `disabled`, so a dimmed chip still says it.
private struct Why: ViewModifier {
    let reason: String?

    func body(content: Content) -> some View {
        if let reason {
            content
                .help(Text(verbatim: reason))
                .accessibilityHint(Text(verbatim: reason))
        } else {
            content
        }
    }
}

/// Chips in rows: each after the last, the next row when one does not fit,
/// and none wider than the room (`BlockTreeContent.chipFrames`).
private struct ChipFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = BlockTreeContent.chipFrames(sizes(subviews, width: width), width: width, spacing: spacing)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = BlockTreeContent.chipFrames(sizes(subviews, width: bounds.width), width: bounds.width,
                                                 spacing: spacing)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    /// Each chip's size, its title cut to fit when it is wider than `width`.
    private func sizes(_ subviews: Subviews, width: CGFloat) -> [CGSize] {
        subviews.map { subview in
            let ideal = subview.sizeThatFits(.unspecified)
            guard ideal.width > width else { return ideal }
            return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
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

/// Text typed in a page's fields that has not reached its tool. On macOS a
/// click on a button, switch or menu does not take the focus from a field,
/// so the field never learns it was left; the page sends each field's text
/// as `change` before the click's own event, so the tool acts on what is
/// on screen.
@MainActor
package final class PendingFields {
    private var sends: [(id: String, send: () -> Void)] = []

    package init() {}

    /// Whether no field holds text the tool has not had.
    package var isEmpty: Bool { sends.isEmpty }

    /// The field `id` holds text its tool has not had; `send` sends it.
    /// A second hold for the field takes the place of the first.
    package func hold(_ id: String, send: @escaping () -> Void) {
        if let index = sends.firstIndex(where: { $0.id == id }) {
            sends[index].send = send
        } else {
            sends.append((id, send))
        }
    }

    /// The field `id` has sent its text, or has none to send.
    package func drop(_ id: String) {
        sends.removeAll { $0.id == id }
    }

    /// Sends every field's text, in the order they were first typed in,
    /// once.
    package func flush() {
        let due = sends
        sends = []
        for entry in due { entry.send() }
    }

    /// `act`, sending the fields' text first.
    package func flushing(into act: @escaping (String, UIEventKind, JSONValue?) -> Void)
        -> (String, UIEventKind, JSONValue?) -> Void {
        { [self] id, kind, value in
            flush()
            act(id, kind, value)
        }
    }
}

/// A field: Return sends `submit`, and leaving it with other text sends
/// `change`, each with the text. What is typed stays here until then, or
/// until another control of the page is used (`PendingFields`). A secret
/// field sends `change` as it is typed in: the tool never draws its value
/// back, and keeps it only as a draft until its own button saves it.
private struct BlockField: View {
    let id: String
    let title: String?
    let value: String
    let placeholder: String
    let kind: FieldBlock.Kind
    let metrics: BlockMetrics
    let focus: FocusState<ExternalToolDetail.Focus?>.Binding?
    let pending: PendingFields
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
                .controlNamed(title)
                .controlSize(.small)
                .onSubmit {
                    sent = text
                    pending.drop(id)
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
        .onChange(of: text) { _, typed in
            guard typed != sent else {
                pending.drop(id)
                return
            }
            if kind == .secret {
                sendChange()
            } else {
                pending.hold(id) { sendChange() }
            }
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            sendChange()
        }
        .onDisappear { pending.drop(id) }
    }

    /// Sends what is typed as `change`, unless the tool has it already.
    private func sendChange() {
        pending.drop(id)
        guard text != sent else { return }
        sent = text
        act(id, .change, .string(text))
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

extension View {
    /// The control's name for assistive technology: its row's title, said
    /// outright. A switch beside its title is otherwise a text and then a
    /// switch with no name of its own, and a text field's label never
    /// reaches assistive technology; with this each says what it switches
    /// or takes. Not for a pop-up menu: its own label, even hidden, already
    /// names it, and this would say the name twice. A control with no title
    /// keeps what it had.
    @ViewBuilder
    func controlNamed(_ title: String?) -> some View {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            accessibilityLabel(Text(verbatim: title))
        } else {
            self
        }
    }
}
