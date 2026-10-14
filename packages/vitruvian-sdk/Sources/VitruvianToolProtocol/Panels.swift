// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

// MARK: - Protocol 2: what a tool draws
//
// A tool describes a page as a list of blocks, and the app draws it with its
// own controls. `protocol/messages.schema.json` describes the same values,
// and the tests hold the two together. The kinds of block are a closed list:
// a kind the app does not know is drawn as its `fallback` text, or left out,
// so a later protocol's block degrades instead of breaking the page.

/// The limits on what a tool draws. They keep a tool from holding the
/// app's main thread or the island; they are not a safety measure.
public enum UILimits {
    /// The most a tree may weigh, as JSON, in bytes: 256 KB. An image
    /// written into it as `data:` counts.
    public static let maxTreeBytes = 262_144
    /// The most blocks a tree may hold.
    public static let maxBlocks = 200
    /// The most rows a `list` block may hold.
    public static let maxListRows = 200
    /// The most lines a `text` block may ask for.
    public static let maxTextLines = 10
    /// The tallest `spacer` and the tallest `image`, in points.
    public static let maxSpacer = 40.0
    public static let maxImageHeight = 300.0
    /// The most `ui/render` notices drawn for one panel in one second. The
    /// ones between are not drawn: the last one is, when the second allows.
    public static let rendersPerSecond = 4
    /// More `ui/render` notices than this for one panel in one second is a
    /// flood, and the app stops the tool as it does for any other flood.
    public static let floodRendersPerSecond = 40
    /// The most options a `choice` block may hold, and the longest value
    /// one may have, in characters as JSON Schema counts them.
    public static let maxChoiceOptions = 64
    public static let maxChoiceValueLength = 128
}

/// Where a panel is shown.
public enum PanelPlacement: String, CaseIterable, Sendable {
    /// A page in the island's Tools area. At most one per tool.
    case island
    /// A part of the tool's detail in Settings. At most one per tool.
    case settings
    /// A window the app owns, opened when the person asks.
    case window
}

/// What draws a panel.
public enum PanelKind: String, CaseIterable, Sendable {
    /// The app, from blocks the tool sends. The default.
    case blocks
    /// A web page from the tool's own folder.
    case web
}

/// Text a tool shows: plain, or one entry per language as a manifest's text
/// is. Either way it is drawn as written, never as markdown.
public enum UIText: Equatable, Sendable {
    case plain(String)
    case languages(LocalizedText)

    /// The text for a language, as `LocalizedText.text(for:)` finds it; the
    /// plain text whatever the language.
    public func text(for languageTag: String) -> String {
        switch self {
        case .plain(let text): return text
        case .languages(let text): return text.text(for: languageTag) ?? ""
        }
    }
}

extension UIText: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let plain = try? container.decode(String.self) {
            self = .plain(plain)
            return
        }
        let text = try container.decode(LocalizedText.self)
        guard text.english != nil else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "text with no English")
        }
        self = .languages(text)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .plain(let text): try container.encode(text)
        case .languages(let text): try container.encode(text)
        }
    }
}

extension UIText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self = .plain(value)
    }
}

/// A page: blocks, drawn one under the other.
public struct UITree: Codable, Equatable, Sendable {
    public let blocks: [UIBlock]

    public init(blocks: [UIBlock]) {
        self.blocks = blocks
    }

    private enum CodingKeys: String, CodingKey {
        case blocks
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try container.decode([UIBlock].self, forKey: .blocks)
        guard blocks.count <= UILimits.maxBlocks else {
            throw DecodingError.dataCorruptedError(forKey: .blocks, in: container,
                                                   debugDescription: "more than \(UILimits.maxBlocks) blocks")
        }
    }
}

/// One block of a page. `id` names it in the events it causes; `fallback`
/// is what an app that does not know its kind draws instead.
public struct UIBlock: Codable, Equatable, Sendable {
    /// What the block is, with the fields of its kind.
    public enum Content: Equatable, Sendable {
        case text(TextBlock)
        case heading(HeadingBlock)
        case row(RowBlock)
        case button(ButtonBlock)
        case toggle(ToggleBlock)
        case field(FieldBlock)
        case list(ListBlock)
        case progress(ProgressBlock)
        case image(ImageBlock)
        case divider(DividerBlock)
        case link(LinkBlock)
        case spacer(SpacerBlock)
        case choice(ChoiceBlock)
        /// A kind this version does not have, by its name.
        case unknown(String)
    }

    public let id: String?
    public let fallback: UIText?
    public let content: Content

    public init(id: String? = nil, fallback: UIText? = nil, _ content: Content) {
        self.id = id
        self.fallback = fallback
        self.content = content
    }

    /// The kind's name, as `type` writes it.
    public var type: String {
        switch content {
        case .text: return "text"
        case .heading: return "heading"
        case .row: return "row"
        case .button: return "button"
        case .toggle: return "toggle"
        case .field: return "field"
        case .list: return "list"
        case .progress: return "progress"
        case .image: return "image"
        case .divider: return "divider"
        case .link: return "link"
        case .spacer: return "spacer"
        case .choice: return "choice"
        case .unknown(let name): return name
        }
    }

    /// The thirteen kinds, by name, in the order the protocol lists them.
    public static let kinds = ["text", "heading", "row", "button", "toggle", "field", "list", "progress", "image",
                               "divider", "link", "spacer", "choice"]

    /// The kinds a block must have an `id` for: the ones whose events
    /// name it.
    public static let kindsWithID: Set<String> = ["button", "toggle", "field", "list", "choice"]

    private enum CodingKeys: String, CodingKey {
        case type, id, fallback
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        fallback = try container.decodeIfPresent(UIText.self, forKey: .fallback)
        if let id, !ManifestRules.isWellFormedName(id) {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "not a well-formed id")
        }
        if Self.kindsWithID.contains(type), id == nil {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: container.codingPath,
                                                                 debugDescription: "a \(type) needs an id"))
        }
        switch type {
        case "text": content = .text(try TextBlock(from: decoder))
        case "heading": content = .heading(try HeadingBlock(from: decoder))
        case "row": content = .row(try RowBlock(from: decoder))
        case "button": content = .button(try ButtonBlock(from: decoder))
        case "toggle": content = .toggle(try ToggleBlock(from: decoder))
        case "field": content = .field(try FieldBlock(from: decoder))
        case "list": content = .list(try ListBlock(from: decoder))
        case "progress": content = .progress(try ProgressBlock(from: decoder))
        case "image": content = .image(try ImageBlock(from: decoder))
        case "divider": content = .divider(DividerBlock())
        case "link": content = .link(try LinkBlock(from: decoder))
        case "spacer": content = .spacer(try SpacerBlock(from: decoder))
        case "choice": content = .choice(try ChoiceBlock(from: decoder))
        // A later protocol's kind: kept by its name, drawn as its fallback.
        default: content = .unknown(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch content {
        case .text(let block): try block.encode(to: encoder)
        case .heading(let block): try block.encode(to: encoder)
        case .row(let block): try block.encode(to: encoder)
        case .button(let block): try block.encode(to: encoder)
        case .toggle(let block): try block.encode(to: encoder)
        case .field(let block): try block.encode(to: encoder)
        case .list(let block): try block.encode(to: encoder)
        case .progress(let block): try block.encode(to: encoder)
        case .image(let block): try block.encode(to: encoder)
        case .divider, .unknown: break
        case .link(let block): try block.encode(to: encoder)
        case .spacer(let block): try block.encode(to: encoder)
        case .choice(let block): try block.encode(to: encoder)
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(fallback, forKey: .fallback)
    }
}

/// A number a field must hold within `range`.
enum Bounded {
    static func check<Key: CodingKey>(_ value: Double?, _ range: ClosedRange<Double>, _ key: Key,
                                      _ container: KeyedDecodingContainer<Key>) throws {
        guard let value, !range.contains(value) else { return }
        throw DecodingError.dataCorruptedError(forKey: key, in: container,
                                               debugDescription: "outside \(range.lowerBound)...\(range.upperBound)")
    }
}

/// Words. `lines` is the most lines they take; the app's own limit when
/// left out.
public struct TextBlock: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable {
        case body, secondary, caption, monospaced
    }

    public let text: UIText
    public let style: Style?
    public let lines: Int?

    public init(text: UIText, style: Style? = nil, lines: Int? = nil) {
        self.text = text
        self.style = style
        self.lines = lines
    }

    private enum CodingKeys: String, CodingKey {
        case text, style, lines
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(UIText.self, forKey: .text)
        style = try container.decodeIfPresent(Style.self, forKey: .style)
        lines = try container.decodeIfPresent(Int.self, forKey: .lines)
        try Bounded.check(lines.map(Double.init), 1...Double(UILimits.maxTextLines), CodingKeys.lines, container)
    }
}

/// A heading, of two lines at most.
public struct HeadingBlock: Codable, Equatable, Sendable {
    public let text: UIText

    public init(text: UIText) {
        self.text = text
    }
}

/// One line of a list that stands alone. With an `id` it can be tapped.
public struct RowBlock: Codable, Equatable, Sendable {
    public let title: UIText
    public let subtitle: UIText?
    /// An SF Symbol name.
    public let icon: String?
    /// A few words at the row's end, such as a time.
    public let trailing: UIText?

    public init(title: UIText, subtitle: UIText? = nil, icon: String? = nil, trailing: UIText? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.trailing = trailing
    }
}

/// A button. Pressing it is the event `tap`.
public struct ButtonBlock: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable {
        case plain, prominent, destructive
    }

    public let title: UIText
    public let style: Style?
    /// False draws it dimmed, and it cannot be pressed. True when left out.
    public let enabled: Bool?

    public init(title: UIText, style: Style? = nil, enabled: Bool? = nil) {
        self.title = title
        self.style = style
        self.enabled = enabled
    }
}

/// A switch. Turning it is the event `toggle`, with the new value.
public struct ToggleBlock: Codable, Equatable, Sendable {
    public let title: UIText
    public let value: Bool
    public let enabled: Bool?

    public init(title: UIText, value: Bool, enabled: Bool? = nil) {
        self.title = title
        self.value = value
        self.enabled = enabled
    }
}

/// A field to type in. Return is the event `submit`; leaving it changed is
/// the event `change`. Both carry the text.
public struct FieldBlock: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case text, number, secret
    }

    public let title: UIText?
    public let value: String?
    public let placeholder: UIText?
    public let kind: Kind?

    public init(title: UIText? = nil, value: String? = nil, placeholder: UIText? = nil, kind: Kind? = nil) {
        self.title = title
        self.value = value
        self.placeholder = placeholder
        self.kind = kind
    }
}

/// One row of a `list`.
public struct UIListRow: Codable, Equatable, Sendable {
    public let id: String
    public let title: UIText
    public let subtitle: UIText?
    public let icon: String?
    public let trailing: UIText?

    public init(id: String, title: UIText, subtitle: UIText? = nil, icon: String? = nil, trailing: UIText? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.trailing = trailing
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, icon, trailing
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        guard ManifestRules.isWellFormedName(id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "not a well-formed id")
        }
        title = try container.decode(UIText.self, forKey: .title)
        subtitle = try container.decodeIfPresent(UIText.self, forKey: .subtitle)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        trailing = try container.decodeIfPresent(UIText.self, forKey: .trailing)
    }
}

/// Rows, drawn together. Tapping one is the event `tap`, whose value is the
/// row's id.
public struct ListBlock: Codable, Equatable, Sendable {
    public let rows: [UIListRow]

    public init(rows: [UIListRow]) {
        self.rows = rows
    }

    private enum CodingKeys: String, CodingKey {
        case rows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rows = try container.decode([UIListRow].self, forKey: .rows)
        guard rows.count <= UILimits.maxListRows else {
            throw DecodingError.dataCorruptedError(forKey: .rows, in: container,
                                                   debugDescription: "more than \(UILimits.maxListRows) rows")
        }
    }
}

/// How far something has got, from 0 to 1. With no value it is under way
/// and nobody knows how far.
public struct ProgressBlock: Codable, Equatable, Sendable {
    public let value: Double?
    public let label: UIText?

    public init(value: Double? = nil, label: UIText? = nil) {
        self.value = value
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case value, label
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        label = try container.decodeIfPresent(UIText.self, forKey: .label)
        try Bounded.check(value, 0...1, CodingKeys.value, container)
    }
}

/// A picture: a file in the tool's folder, by a path inside it, or the
/// image itself as a `data:` address of a PNG or JPEG.
public struct ImageBlock: Codable, Equatable, Sendable {
    public let source: String
    /// What the picture shows, for VoiceOver.
    public let alt: UIText?
    /// Its height in points; the app's own when left out.
    public let height: Double?

    public init(source: String, alt: UIText? = nil, height: Double? = nil) {
        self.source = source
        self.alt = alt
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case source, alt, height
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        alt = try container.decodeIfPresent(UIText.self, forKey: .alt)
        height = try container.decodeIfPresent(Double.self, forKey: .height)
        try Bounded.check(height, 1...UILimits.maxImageHeight, CodingKeys.height, container)
    }
}

/// A line between blocks. It has no fields.
public struct DividerBlock: Codable, Equatable, Sendable {
    public init() {}
}

/// A link. The app opens it through its `open` service, so the tool's
/// manifest must list `open` in `uses`.
public struct LinkBlock: Codable, Equatable, Sendable {
    public let title: UIText
    public let url: String

    public init(title: UIText, url: String) {
        self.title = title
        self.url = url
    }
}

/// Room between blocks, in points; the app's own when left out.
public struct SpacerBlock: Codable, Equatable, Sendable {
    public let size: Double?

    public init(size: Double? = nil) {
        self.size = size
    }

    private enum CodingKeys: String, CodingKey {
        case size
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Double.self, forKey: .size)
        try Bounded.check(size, 0...UILimits.maxSpacer, CodingKeys.size, container)
    }
}

/// One option of a `choice`: what the event carries when it is picked, and
/// what the menu shows for it.
public struct UIChoiceOption: Codable, Equatable, Sendable {
    public let value: String
    public let title: UIText

    public init(value: String, title: UIText) {
        self.value = value
        self.title = title
    }
}

/// A pop-up menu: one of a fixed list of options. Picking one is the event
/// `change`, whose value is the option's. A `value` that is no option's is
/// drawn as an extra first row, as written.
public struct ChoiceBlock: Codable, Equatable, Sendable {
    /// What is being chosen, beside the menu.
    public let title: UIText?
    /// The selected option's value.
    public let value: String
    /// From 1 to `UILimits.maxChoiceOptions`, no two with one value.
    public let options: [UIChoiceOption]
    /// False draws it dimmed, and nothing can be picked. True when left out.
    public let enabled: Bool?

    public init(title: UIText? = nil, value: String, options: [UIChoiceOption], enabled: Bool? = nil) {
        self.title = title
        self.value = value
        self.options = options
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case title, value, options, enabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(UIText.self, forKey: .title)
        value = try container.decode(String.self, forKey: .value)
        options = try container.decode([UIChoiceOption].self, forKey: .options)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        func refuse(_ key: CodingKeys, _ why: String) -> DecodingError {
            DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: why)
        }
        guard (1...UILimits.maxChoiceOptions).contains(options.count) else {
            throw refuse(.options, "not from 1 to \(UILimits.maxChoiceOptions) options")
        }
        let tooLong = { (text: String) in text.unicodeScalars.count > UILimits.maxChoiceValueLength }
        guard !tooLong(value) else {
            throw refuse(.value, "a value of more than \(UILimits.maxChoiceValueLength) characters")
        }
        guard !options.contains(where: { tooLong($0.value) }) else {
            throw refuse(.options, "an option's value of more than \(UILimits.maxChoiceValueLength) characters")
        }
        guard Set(options.map(\.value)).count == options.count else {
            throw refuse(.options, "two options with one value")
        }
    }
}

// MARK: - The messages

/// `ui/open`: the person opened one of the tool's panels.
public struct UIOpenParams: Codable, Equatable, Sendable {
    /// The panel's id, as the manifest gives it.
    public let panel: String

    public init(panel: String) {
        self.panel = panel
    }
}

/// The answer to `ui/open`: the first page. A web panel answers with none.
public struct UIOpenResult: Codable, Equatable, Sendable {
    public let tree: UITree?

    public init(tree: UITree? = nil) {
        self.tree = tree
    }
}

/// What the person did.
public enum UIEventKind: String, Codable, CaseIterable, Sendable {
    /// A button, a row or a list's row was pressed.
    case tap
    /// A switch was turned. The value is its new state.
    case toggle
    /// Return was pressed in a field. The value is its text.
    case submit
    /// A field was left with other text in it. The value is its text.
    case change
    /// A web panel's page called `window.vitruvian.call`. The value is
    /// `{ "method": …, "params": … }`.
    case bridge
}

/// `ui/event`: the person acted in an open panel.
public struct UIEventParams: Codable, Equatable, Sendable {
    public let panel: String
    /// The block's id. Left out for `bridge`.
    public let block: String?
    public let event: UIEventKind
    public let value: JSONValue?

    public init(panel: String, block: String? = nil, event: UIEventKind, value: JSONValue? = nil) {
        self.panel = panel
        self.block = block
        self.event = event
        self.value = value
    }
}

/// The answer to `ui/event`. `tree` is the next page; with none, or with
/// `keep`, the page stays as it is. `reply` is what a page's
/// `window.vitruvian.call` gets back. `open` is a window panel of the same
/// tool to open, in answer to what the person did.
public struct UIEventResult: Codable, Equatable, Sendable {
    public let tree: UITree?
    public let keep: Bool?
    public let reply: JSONValue?
    public let open: String?

    public init(tree: UITree? = nil, keep: Bool? = nil, reply: JSONValue? = nil, open: String? = nil) {
        self.tree = tree
        self.keep = keep
        self.reply = reply
        self.open = open
    }
}

/// `ui/close`: the panel went away.
public struct UICloseParams: Codable, Equatable, Sendable {
    public let panel: String

    public init(panel: String) {
        self.panel = panel
    }
}

/// `ui/render`: a new page for a panel that is open, unprompted.
public struct UIRenderParams: Codable, Equatable, Sendable {
    public let panel: String
    public let tree: UITree

    public init(panel: String, tree: UITree) {
        self.panel = panel
        self.tree = tree
    }
}

/// `ui/badge`: a count or a dot beside the tool in the island's Tools
/// area. With neither, the badge goes.
public struct UIBadgeParams: Codable, Equatable, Sendable {
    public let count: Int?
    public let dot: Bool?

    public init(count: Int? = nil, dot: Bool? = nil) {
        self.count = count
        self.dot = dot
    }

    private enum CodingKeys: String, CodingKey {
        case count, dot
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        dot = try container.decodeIfPresent(Bool.self, forKey: .dot)
        try Bounded.check(count.map(Double.init), 0...Double(Int.max), CodingKeys.count, container)
    }
}

/// What a status says. The app draws each in its own style; the tool never
/// draws.
public enum StatusState: String, Codable, CaseIterable, Sendable {
    /// No mark.
    case none
    /// All is well.
    case ok
    /// Something is under way.
    case busy
    /// Something waits for the person.
    case attention
    /// Something failed.
    case failure
}

/// Where a tool's status is shown.
public enum StatusPlacement: String, CaseIterable, Sendable {
    /// On the closed island, beside the agent mark.
    case island
}

/// `ui/status`: the tool's status, a small mark the app draws on the closed
/// island. Each one replaces the last, and it goes when the tool's program
/// ends. The manifest must declare it, under `contributes.status`.
public struct UIStatusParams: Codable, Equatable, Sendable {
    public let state: StatusState
    /// What it means, in one short line, for VoiceOver and the tooltip.
    public let text: UIText?
    /// An SF Symbol name, drawn in place of the state's own glyph.
    public let icon: String?
    /// A few words for the closed island, beside the mark, in place of the
    /// allowance percent. Drawn only when the manifest's status says
    /// `activity: true`, and by an app that names
    /// `ProtocolFeature.statusActivity`; an older app ignores it.
    public let activity: UIText?
    /// A start time, in Unix seconds: the app counts the seconds since then
    /// itself, when there is no `activity`. Never below 0.
    public let since: Double?

    public init(state: StatusState, text: UIText? = nil, icon: String? = nil, activity: UIText? = nil,
                since: Double? = nil) {
        self.state = state
        self.text = text
        self.icon = icon
        self.activity = activity
        self.since = since
    }

    private enum CodingKeys: String, CodingKey {
        case state, text, icon, activity, since
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(StatusState.self, forKey: .state)
        text = try container.decodeIfPresent(UIText.self, forKey: .text)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        activity = try container.decodeIfPresent(UIText.self, forKey: .activity)
        since = try container.decodeIfPresent(Double.self, forKey: .since)
        if let since, !(since >= 0) {
            throw DecodingError.dataCorruptedError(forKey: .since, in: container,
                                                   debugDescription: "a start time before 1970")
        }
    }
}

/// What a web panel's page asked for, in a `bridge` event's value.
public struct UIBridgeCall: Codable, Equatable, Sendable {
    /// A request a tool may make of the app, such as `notify/hud`, or a
    /// method of the tool's own whose name starts with `tool/`.
    public let method: String
    public let params: JSONValue?

    public init(method: String, params: JSONValue? = nil) {
        self.method = method
        self.params = params
    }

    /// The prefix of the methods a page may call that are the tool's own.
    public static let toolsOwn = "tool/"
}
