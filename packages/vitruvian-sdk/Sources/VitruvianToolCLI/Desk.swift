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

/// What `vitruvian-tool run` answers a tool's requests with, in place of
/// the app.
///
/// Nothing here touches the Mac. No message is shown, no sound is made, no
/// link is opened, nothing is typed or pasted, and no process is ended:
/// each is said in the terminal and answered as done. The clipboard is a
/// piece of text this value holds, never the person's own. A preference is
/// kept here for the run and saved nowhere.
///
/// It refuses what the app refuses for the same reason: a service the
/// manifest's `uses` does not list, a preference the manifest does not
/// declare, a value of the wrong kind, params that are not the message's.
public struct Desk {
    public typealias Answer = Result<JSONValue, RPCErrorObject>

    private let uses: Set<String>
    private let kinds: [String: PreferenceKind]
    public private(set) var values: [String: JSONValue]
    public private(set) var clipboard: String? = "text from vitruvian-tool run"
    /// Every request is refused as not available right now, the way the app
    /// may refuse any request at any time.
    public var refuseAll = false

    public init(manifest: ToolManifestFile) {
        uses = Set(manifest.uses ?? [])
        var kinds: [String: PreferenceKind] = [:]
        var values: [String: JSONValue] = [:]
        for preference in manifest.preferences ?? [] {
            kinds[preference.id] = PreferenceKind(rawValue: preference.type)
            values[preference.id] = preference.default
        }
        self.kinds = kinds
        self.values = values
    }

    private static let done = Answer.success(.object([:]))
    private static let badParams = Answer.failure(RPCErrorObject(code: RPCErrorCode.invalidParams,
                                                                 message: "invalid params"))

    /// Answers one request, and says in a few words what the app would
    /// have done.
    public mutating func serve(_ method: String, _ params: JSONValue?) -> (answer: Answer, said: String) {
        guard let known = ToolMethod(rawValue: method), known.sender == .tool, let service = known.service else {
            return (.failure(RPCErrorObject(code: RPCErrorCode.methodNotFound, message: "method not found")),
                    "not a request a tool may make")
        }
        guard uses.contains(service.rawValue) else {
            return (.failure(RefusalCode.notInUses.error(service: service)),
                    "refused: `\(service.rawValue)` is not in the manifest's `uses`")
        }
        if refuseAll { return (.failure(RefusalCode.unavailable.error()), "refused, as --refuse asks") }
        func read<Params: Decodable>(_ type: Params.Type) -> Params? {
            try? (params ?? .object([:])).decode(type)
        }
        func answer<Value: Encodable>(_ value: Value) -> Answer {
            (try? JSONValue(encoding: value)).map(Answer.success) ?? Self.badParams
        }
        let wrong = (Self.badParams, "params that are not this message's")

        switch known {
        case .initialize, .commandRun, .preferencesChanged, .languageChanged, .shutdown, .commandsState, .log,
             .uiOpen, .uiEvent, .uiClose, .uiRender:
            // Not reached: none of these has a service.
            return wrong
        case .uiBadge:
            guard let asked = read(UIBadgeParams.self) else { return wrong }
            let badge = asked.count.flatMap { $0 > 0 ? "the count \($0)" : nil }
                ?? (asked.dot == true ? "a dot" : "no badge")
            return (Self.done, "the app would show \(badge) beside the tool in the island")
        case .notifyHUD:
            guard let asked = read(NotifyHUDParams.self) else { return wrong }
            return (Self.done, "the app would show \"\(asked.message)\" with the symbol \(asked.icon)")
        case .notifyBeep:
            return (Self.done, "the app would play the alert sound")
        case .openURL:
            guard let asked = read(OpenURLParams.self), let url = URL(string: asked.url), url.scheme != nil else {
                return wrong
            }
            return (answer(OpenURLResult(opened: true)), "the app would open \(asked.url). Not opened here")
        case .clipboardReadText:
            return (answer(ClipboardReadTextResult(text: clipboard)),
                    "given this run's own clipboard, not yours: \(clipboard.map { "\"\($0)\"" } ?? "no text")")
        case .clipboardWriteText:
            guard let asked = read(ClipboardWriteTextParams.self) else { return wrong }
            clipboard = asked.text
            return (answer(ClipboardWriteTextResult(written: true)),
                    "the app would copy \"\(asked.text)\". Kept for this run; your clipboard is untouched")
        case .keystrokesPaste:
            guard let asked = read(KeystrokesPasteParams.self) else { return wrong }
            return (Self.done, "the app would paste \"\(asked.text)\" into the app in front. Not pasted here")
        case .keystrokesPressMenuItem:
            guard let asked = read(KeystrokesPressMenuItemParams.self) else { return wrong }
            let keys = asked.equivalents.map { key in
                (key.modifiers.map(\.rawValue) + ["command", key.character]).joined(separator: "+")
            }
            return (answer(KeystrokesPressMenuItemResult(pressed: true)),
                    "the app would press the menu item for \(keys.joined(separator: " or ")). Not pressed here")
        case .processesTerminate:
            guard let asked = read(ProcessesTerminateParams.self) else { return wrong }
            return (Self.done, "the app would \(asked.force ? "end" : "ask to quit") process \(asked.pid) "
                + "(\(asked.name)). Nothing is ended here, ever")
        case .storageGet:
            guard let asked = read(StorageGetParams.self) else { return wrong }
            guard let value = values[asked.key] else { return undeclared(asked.key) }
            return (answer(StorageGetResult(value: value)), "`\(asked.key)` is \(Self.text(value))")
        case .storageSet:
            guard let asked = read(StorageSetParams.self) else { return wrong }
            guard let kind = kinds[asked.key], values[asked.key] != nil else { return undeclared(asked.key) }
            guard kind.accepts(asked.value) else {
                return (.failure(RPCErrorObject(code: RPCErrorCode.invalidParams,
                                                message: "not the kind of value this preference holds")),
                        "refused: `\(asked.key)` holds \(kind.rawValue), not \(Self.text(asked.value))")
            }
            guard StorageLimits.allows(asked.value) else {
                return (.failure(RPCErrorObject(code: RPCErrorCode.invalidParams,
                                                message: "longer than a preference may be")),
                        "refused: `\(asked.key)` would be over \(StorageLimits.maxTextLength) characters, "
                            + "the most the app saves")
            }
            values[asked.key] = asked.value
            return (Self.done, "`\(asked.key)` is now \(Self.text(asked.value)), for this run only")
        }
    }

    private func undeclared(_ key: String) -> (Answer, String) {
        (.failure(RPCErrorObject(code: RPCErrorCode.invalidParams, message: "not a preference the manifest declares")),
         "refused: the manifest declares no preference `\(key)`")
    }

    static func text(_ value: JSONValue) -> String {
        (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "?"
    }
}
