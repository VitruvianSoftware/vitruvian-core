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
import VitruvianToolProtocol

// MARK: - A tool that draws

/// What the person did in one of the tool's panels, as a handler sees it.
public struct PanelEvent: Equatable, Sendable {
    /// The block's id, as the page gave it.
    public let block: String?
    public let kind: UIEventKind
    public let value: JSONValue?

    public init(block: String?, kind: UIEventKind, value: JSONValue? = nil) {
        self.block = block
        self.kind = kind
        self.value = value
    }

    /// For a tap on a row of a list: the row's id.
    public var row: String? { kind == .tap ? value?.stringValue : nil }
    /// For `submit` and `change`: the field's text. For the `change` of a
    /// `choice`: the picked option's value.
    public var text: String? { kind == .submit || kind == .change ? value?.stringValue : nil }
    /// For `toggle`: the switch's new state.
    public var isOn: Bool? { kind == .toggle ? value?.boolValue : nil }
}

/// How a handler answers what the person did.
public enum PanelAnswer: Equatable, Sendable {
    /// The next page.
    case page(UITree)
    /// The page stays as it is.
    case keep
    /// One of the tool's window panels opens, by its id. On an app that
    /// has `.openSettings`, the id of the tool's settings panel opens
    /// Settings on the tool's detail.
    case open(String)
    /// What a web panel's `window.vitruvian.call` gets back.
    case reply(JSONValue)

    var result: UIEventResult {
        switch self {
        case .page(let tree): return UIEventResult(tree: tree)
        case .keep: return UIEventResult(keep: true)
        case .open(let panel): return UIEventResult(open: panel)
        case .reply(let value): return UIEventResult(reply: value)
        }
    }
}

/// One of the tool's panels, as the manifest declares it. Made by
/// `Tool.panel(_:onOpen:onEvent:)`. Use it from the thread that runs the
/// tool, as everything of a `Tool`.
public final class Panel {
    public typealias Opened = (App, Panel) throws -> UITree?
    public typealias Acted = (App, Panel, PanelEvent) throws -> PanelAnswer
    /// A web panel's call of a method of the tool's own, one whose name
    /// starts with `tool/`: the method, its params, and the reply.
    public typealias Called = (App, String, JSONValue?) throws -> JSONValue

    /// The id the manifest gives it.
    public let id: String
    /// True while the app has it open: from `ui/open` to `ui/close`.
    public internal(set) var isOpen = false
    /// For a web panel: what its page's calls of the tool's own methods
    /// answer. With none, such a call is answered as a method not found.
    /// A call of a request the app does, such as `notify/hud`, is passed to
    /// the app as the tool's own, with no handler.
    public var onCall: Called?

    let onOpen: Opened
    let onEvent: Acted
    unowned let tool: Tool

    init(id: String, tool: Tool, onOpen: @escaping Opened, onEvent: @escaping Acted) {
        self.id = id
        self.tool = tool
        self.onOpen = onOpen
        self.onEvent = onEvent
    }

    /// Sends a new page for the panel, unprompted: `ui/render`. False, and
    /// nothing is sent, when the panel is not open. The app draws at most
    /// four pages a second for a panel; send fewer.
    @discardableResult
    public func render(_ tree: UITree) -> Bool {
        guard isOpen, let params = try? JSONValue(encoding: UIRenderParams(panel: id, tree: tree)) else { return false }
        return tool.note(.uiRender, params)
    }

    /// Puts a count, or a dot, beside the tool's page in the island's Explore
    /// gallery: `ui/badge`. With neither, the badge goes. Needs `notify` in `uses`.
    public func badge(count: Int? = nil, dot: Bool = false) throws {
        try App(tool: tool).send(UIBadgeParams(count: count, dot: dot ? true : nil))
    }
}

extension Tool {
    /// Says what a panel does. `id` is the one the manifest gives it.
    /// `onOpen` gives the first page when the person opens it; a web panel
    /// gives none. `onEvent` answers what the person did. The handle it
    /// gives back sends pages unprompted and sets the tool's badge.
    @discardableResult
    public func panel(_ id: String, onOpen: @escaping Panel.Opened,
                      onEvent: @escaping Panel.Acted = { _, _, _ in .keep }) -> Panel {
        let panel = Panel(id: id, tool: self, onOpen: onOpen, onEvent: onEvent)
        panels[id] = panel
        return panel
    }

    func openPanel(_ id: RPCID, _ params: JSONValue?) {
        guard let asked = try? params?.decode(UIOpenParams.self) else {
            return refuse(id, RPCErrorCode.invalidParams, "invalid params")
        }
        guard let panel = panels[asked.panel] else { return refuse(id, RPCErrorCode.invalidParams, "no such panel") }
        panel.isOpen = true
        do {
            answer(id, UIOpenResult(tree: try panel.onOpen(App(tool: self), panel)))
        } catch let refusal as RPCErrorObject {
            refuse(id, refusal.code, refusal.message, data: refusal.data)
        } catch {
            refuse(id, RPCErrorCode.internalError, "\(error)")
        }
    }

    func panelEvent(_ id: RPCID, _ params: JSONValue?) {
        guard let asked = try? params?.decode(UIEventParams.self) else {
            return refuse(id, RPCErrorCode.invalidParams, "invalid params")
        }
        guard let panel = panels[asked.panel], panel.isOpen else {
            return refuse(id, RPCErrorCode.invalidParams, "the panel is not open")
        }
        let app = App(tool: self)
        do {
            if asked.event == .bridge {
                answer(id, UIEventResult(reply: try bridge(asked.value, panel, app)))
            } else {
                let event = PanelEvent(block: asked.block, kind: asked.event, value: asked.value)
                answer(id, try panel.onEvent(app, panel, event).result)
            }
        } catch let refusal as RPCErrorObject {
            refuse(id, refusal.code, refusal.message, data: refusal.data)
        } catch {
            refuse(id, RPCErrorCode.internalError, "\(error)")
        }
    }

    /// A web panel's call: a request the app does is passed to the app as
    /// the tool's own, under the tool's `uses`; a method of the tool's own
    /// goes to the panel's `onCall`.
    private func bridge(_ value: JSONValue?, _ panel: Panel, _ app: App) throws -> JSONValue {
        guard let asked = try? value?.decode(UIBridgeCall.self) else {
            throw RPCErrorObject(code: RPCErrorCode.invalidParams, message: "invalid params")
        }
        if asked.method.hasPrefix(UIBridgeCall.toolsOwn) {
            guard let onCall = panel.onCall else {
                throw RPCErrorObject(code: RPCErrorCode.methodNotFound, message: "method not found")
            }
            return try onCall(app, asked.method, asked.params)
        }
        guard let method = ToolMethod(rawValue: asked.method), method.sender == .tool, method.isAnswered else {
            throw RPCErrorObject(code: RPCErrorCode.methodNotFound, message: "method not found")
        }
        return try call(method, asked.params ?? .object([:]))
    }
}

// MARK: - Writing a page

extension UIBlock {
    public static func text(_ text: UIText, style: TextBlock.Style? = nil, lines: Int? = nil) -> UIBlock {
        UIBlock(.text(TextBlock(text: text, style: style, lines: lines)))
    }

    public static func heading(_ text: UIText) -> UIBlock {
        UIBlock(.heading(HeadingBlock(text: text)))
    }

    /// A row. With an `id` it can be tapped.
    public static func row(_ id: String? = nil, _ title: UIText, subtitle: UIText? = nil, icon: String? = nil,
                           trailing: UIText? = nil) -> UIBlock {
        UIBlock(id: id, .row(RowBlock(title: title, subtitle: subtitle, icon: icon, trailing: trailing)))
    }

    public static func button(_ id: String, _ title: UIText, style: ButtonBlock.Style? = nil,
                              enabled: Bool? = nil) -> UIBlock {
        UIBlock(id: id, .button(ButtonBlock(title: title, style: style, enabled: enabled)))
    }

    public static func toggle(_ id: String, _ title: UIText, isOn: Bool, enabled: Bool? = nil) -> UIBlock {
        UIBlock(id: id, .toggle(ToggleBlock(title: title, value: isOn, enabled: enabled)))
    }

    public static func field(_ id: String, title: UIText? = nil, value: String? = nil, placeholder: UIText? = nil,
                             kind: FieldBlock.Kind? = nil) -> UIBlock {
        UIBlock(id: id, .field(FieldBlock(title: title, value: value, placeholder: placeholder, kind: kind)))
    }

    public static func list(_ id: String, _ rows: [UIListRow]) -> UIBlock {
        UIBlock(id: id, .list(ListBlock(rows: rows)))
    }

    public static func progress(_ value: Double? = nil, label: UIText? = nil) -> UIBlock {
        UIBlock(.progress(ProgressBlock(value: value, label: label)))
    }

    public static func image(_ source: String, alt: UIText? = nil, height: Double? = nil) -> UIBlock {
        UIBlock(.image(ImageBlock(source: source, alt: alt, height: height)))
    }

    public static var divider: UIBlock { UIBlock(.divider(DividerBlock())) }

    public static func link(_ title: UIText, url: String) -> UIBlock {
        UIBlock(.link(LinkBlock(title: title, url: url)))
    }

    public static func spacer(_ size: Double? = nil) -> UIBlock {
        UIBlock(.spacer(SpacerBlock(size: size)))
    }

    /// A pop-up menu: one of a fixed list of options. `value` is the
    /// selected option's. Picking one is the event `change`, read with
    /// `PanelEvent.text`.
    ///
    /// An app before 3.48 does not know this kind and draws `fallback`,
    /// which nobody can change. So ask `app.supports(.choice)` first, and
    /// send a `field` to an app without it. With no `fallback` given, one is
    /// written: the title, a colon and the selected option's title.
    public static func choice(_ id: String, title: UIText? = nil, value: String, options: [UIChoiceOption],
                              enabled: Bool? = nil, fallback: UIText? = nil) -> UIBlock {
        let block = ChoiceBlock(title: title, value: value, options: options, enabled: enabled)
        return UIBlock(id: id, fallback: fallback ?? block.saidPlainly, .choice(block))
    }
}

extension ChoiceBlock {
    /// What the menu says, as words: the title, a colon and the selected
    /// option's title, or that title alone, in every language either has. A
    /// value that is no option's is written as it is.
    var saidPlainly: UIText {
        let selected = options.first { $0.value == value }?.title ?? .plain(value)
        guard let title else { return selected }
        var languages = Set<String>()
        for case .languages(let text) in [title, selected] { languages.formUnion(text.byLanguage.keys) }
        func said(_ language: String) -> String { "\(title.text(for: language)): \(selected.text(for: language))" }
        if languages.isEmpty { return .plain(said("en")) }
        return .languages(LocalizedText(Dictionary(uniqueKeysWithValues: languages.map { ($0, said($0)) })))
    }
}

// The same thirteen, as functions, for a page written in `UITree { }`. A line
// that starts with a dot would join the line above it, so a page is written
// with these, one block a line.

public func text(_ text: UIText, style: TextBlock.Style? = nil, lines: Int? = nil) -> UIBlock {
    .text(text, style: style, lines: lines)
}

public func heading(_ text: UIText) -> UIBlock { .heading(text) }

public func row(_ id: String? = nil, _ title: UIText, subtitle: UIText? = nil, icon: String? = nil,
                trailing: UIText? = nil) -> UIBlock {
    .row(id, title, subtitle: subtitle, icon: icon, trailing: trailing)
}

public func button(_ id: String, _ title: UIText, style: ButtonBlock.Style? = nil, enabled: Bool? = nil) -> UIBlock {
    .button(id, title, style: style, enabled: enabled)
}

public func toggle(_ id: String, _ title: UIText, isOn: Bool, enabled: Bool? = nil) -> UIBlock {
    .toggle(id, title, isOn: isOn, enabled: enabled)
}

public func field(_ id: String, title: UIText? = nil, value: String? = nil, placeholder: UIText? = nil,
                  kind: FieldBlock.Kind? = nil) -> UIBlock {
    .field(id, title: title, value: value, placeholder: placeholder, kind: kind)
}

public func list(_ id: String, _ rows: [UIListRow]) -> UIBlock { .list(id, rows) }

public func progress(_ value: Double? = nil, label: UIText? = nil) -> UIBlock { .progress(value, label: label) }

public func image(_ source: String, alt: UIText? = nil, height: Double? = nil) -> UIBlock {
    .image(source, alt: alt, height: height)
}

public func divider() -> UIBlock { .divider }

public func link(_ title: UIText, url: String) -> UIBlock { .link(title, url: url) }

public func spacer(_ size: Double? = nil) -> UIBlock { .spacer(size) }

public func choice(_ id: String, title: UIText? = nil, value: String, options: [UIChoiceOption],
                   enabled: Bool? = nil, fallback: UIText? = nil) -> UIBlock {
    .choice(id, title: title, value: value, options: options, enabled: enabled, fallback: fallback)
}

/// Writes a page as the blocks it holds, one under the other:
///
///     UITree {
///         heading("Counter")
///         text("Pressed \(count) times")
///         button("add", "Add one", style: .prominent)
///         if count > 9 { text("That is a lot", style: .caption) }
///     }
@resultBuilder
public enum UITreeBuilder {
    public static func buildExpression(_ block: UIBlock) -> [UIBlock] { [block] }
    public static func buildExpression(_ blocks: [UIBlock]) -> [UIBlock] { blocks }
    public static func buildBlock(_ parts: [UIBlock]...) -> [UIBlock] { parts.flatMap { $0 } }
    public static func buildOptional(_ part: [UIBlock]?) -> [UIBlock] { part ?? [] }
    public static func buildEither(first part: [UIBlock]) -> [UIBlock] { part }
    public static func buildEither(second part: [UIBlock]) -> [UIBlock] { part }
    public static func buildArray(_ parts: [[UIBlock]]) -> [UIBlock] { parts.flatMap { $0 } }
}

extension UITree {
    public init(@UITreeBuilder _ blocks: () -> [UIBlock]) {
        self.init(blocks: blocks())
    }
}
