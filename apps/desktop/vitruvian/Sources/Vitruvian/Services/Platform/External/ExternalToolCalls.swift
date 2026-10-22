// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// What a tool that runs as its own program may ask of the app: each
/// request of the protocol, done through the capability broker and
/// answered with values only.
///
/// It goes through the same door as a tool compiled into the app: the
/// tool's own `ToolServices`. So a service the manifest does not list in
/// `uses` is refused by the broker, as it is for a built-in tool, and the
/// refusal is one of the protocol's four codes.
///
/// The switch below is exhaustive on purpose: a message added to the
/// protocol does not compile here until it says what the app does.
@MainActor
package struct ExternalToolCalls {
    private let tool: ToolID
    private let services: ToolServices
    /// Puts the tool's badge on its section's tile in Explore.
    private let badge: @MainActor (UIBadgeParams) -> Void
    /// Keeps the tool's status for the closed island. What it gives back
    /// is why it would not: the failure the tool is answered with.
    private let status: @MainActor (UIStatusParams) -> RPCErrorObject?
    /// Shows a notice in the island, and a macOS notification when asked.
    private let notice: @MainActor (NotifyNoticeParams) -> Void
    /// Shows the tool's slot. What it gives back is why it would not.
    private let dock: @MainActor () -> RPCErrorObject?

    package init(manifest: ToolManifest, broker: CapabilityBroker,
                 badge: @escaping @MainActor (UIBadgeParams) -> Void = { _ in },
                 status: @escaping @MainActor (UIStatusParams) -> RPCErrorObject? = { _ in nil },
                 notice: @escaping @MainActor (NotifyNoticeParams) -> Void = { _ in },
                 dock: @escaping @MainActor () -> RPCErrorObject? = { nil }) {
        tool = manifest.id
        services = broker.services(for: manifest)
        self.badge = badge
        self.status = status
        self.notice = notice
        self.dock = dock
    }

    /// Does what one request asks and answers it, once: at once, or when
    /// the work is done.
    package func serve(_ method: ToolMethod, _ params: JSONValue?, _ reply: @escaping ToolLink.Reply) {
        switch method {
        case .initialize, .commandRun, .preferencesChanged, .languageChanged, .shutdown, .commandsState, .log,
             .uiOpen, .uiEvent, .uiClose, .uiRender, .uiSlot:
            // The app's own messages, and the notices: not requests a tool
            // makes. The link answers these itself; this is for a caller
            // that does not.
            reply(.failure(RPCErrorObject(code: RPCErrorCode.methodNotFound, message: "unknown method")))

        case .uiStatus:
            // Behind nothing in `uses`: the manifest's own declaration is
            // the permission, and whoever keeps the status holds the tool
            // to it. A status the person switched off is answered the same.
            guard let asked = Self.read(UIStatusParams.self, params) else { return reply(Self.badParams) }
            if let refusal = status(asked) { return reply(.failure(refusal)) }
            reply(.success(Self.nothing))

        case .uiBadge:
            // Behind `notify`, as the protocol says.
            guard let asked = Self.read(UIBadgeParams.self, params) else { return reply(Self.badParams) }
            if let refusal = services.gate(.notify)() { return reply(.failure(Self.error(for: refusal))) }
            badge(asked)
            reply(.success(Self.nothing))

        case .notifyNotice:
            // Behind `notify`, as the HUD is.
            guard let asked = Self.read(NotifyNoticeParams.self, params) else { return reply(Self.badParams) }
            if let refusal = services.gate(.notify)() { return reply(.failure(Self.error(for: refusal))) }
            notice(asked)
            reply(.success(Self.nothing))

        case .uiDock:
            // Behind nothing in `uses`: the manifest's slot is the
            // permission, as its status is for `ui/status`.
            if let refusal = dock() { return reply(.failure(refusal)) }
            reply(.success(Self.nothing))

        case .notifyHUD:
            guard let asked = Self.read(NotifyHUDParams.self, params) else { return reply(Self.badParams) }
            reply(Self.done(services.notify.hud(icon: asked.icon, message: asked.message)))

        case .notifyBeep:
            reply(Self.done(services.notify.beep()))

        case .openURL:
            guard let asked = Self.read(OpenURLParams.self, params), let url = URL(string: asked.url),
                  url.scheme != nil else { return reply(Self.badParams) }
            switch services.open.url(url) {
            case .success(let opened): reply(Self.answer(OpenURLResult(opened: opened)))
            case .failure(let refusal): reply(.failure(Self.error(for: refusal)))
            }

        case .clipboardReadText:
            let refusal = services.clipboard.readText { text in
                reply(Self.answer(ClipboardReadTextResult(text: text)))
            }
            if let refusal { reply(.failure(Self.error(for: refusal))) }

        case .clipboardWriteText:
            guard let asked = Self.read(ClipboardWriteTextParams.self, params) else { return reply(Self.badParams) }
            let refusal = services.clipboard.write(asked.text) { written in
                reply(Self.answer(ClipboardWriteTextResult(written: written)))
            }
            if let refusal { reply(.failure(Self.error(for: refusal))) }

        case .keystrokesPaste:
            guard let asked = Self.read(KeystrokesPasteParams.self, params) else { return reply(Self.badParams) }
            reply(Self.done(services.keystrokes.paste(asked.text)))

        case .keystrokesPressMenuItem:
            guard let asked = Self.read(KeystrokesPressMenuItemParams.self, params) else {
                return reply(Self.badParams)
            }
            switch services.keystrokes.pressFrontAppMenuItem(matching: asked.equivalents.map(Self.menuKey)) {
            case .success(let pressed): reply(Self.answer(KeystrokesPressMenuItemResult(pressed: pressed)))
            case .failure(let refusal): reply(.failure(Self.error(for: refusal)))
            }

        case .processesTerminate:
            guard let asked = Self.read(ProcessesTerminateParams.self, params),
                  let pid = pid_t(exactly: asked.pid), pid > 0 else { return reply(Self.badParams) }
            terminate(pid, name: asked.name, force: asked.force, reply)

        case .storageGet:
            guard let asked = Self.read(StorageGetParams.self, params) else { return reply(Self.badParams) }
            switch services.storage.value(for: key(asked.key)) {
            case .success(let value): reply(Self.answer(StorageGetResult(value: Self.json(value))))
            case .failure(let problem): reply(.failure(Self.error(for: problem)))
            }

        case .storageSet:
            guard let asked = Self.read(StorageSetParams.self, params) else { return reply(Self.badParams) }
            let saved = key(asked.key)
            // The value is read as the kind the manifest gives the
            // preference. One of another kind is left for `set` to refuse.
            let declared = services.manifest.preferences.first { $0.key == saved }?.defaultValue
            let value = declared.flatMap { Self.value(asked.value, like: $0) } ?? Self.value(asked.value)
            guard let value else { return reply(Self.badParams) }
            if let problem = services.storage.set(value, for: saved) {
                reply(.failure(Self.error(for: problem)))
            } else {
                reply(.success(Self.nothing))
            }
        }
    }

    /// Ends a process the way the Port manager does: the app looks up when
    /// it started, so that a process id used again is never the one ended,
    /// and refuses the processes it protects.
    private func terminate(_ pid: pid_t, name: String, force: Bool, _ reply: @escaping ToolLink.Reply) {
        let processes = services.processes
        switch processes.scanner() {
        case .failure(let refusal):
            reply(.failure(Self.error(for: refusal)))
        case .success(let scanner):
            guard processes.canTerminate, !processes.isProtected(pid: pid, name: name) else {
                return reply(.failure(RefusalCode.unavailable.error()))
            }
            guard let startedAt = scanner.startTime(pid) else {
                return reply(.failure(RPCErrorObject(code: RPCErrorCode.invalidParams, message: "no such process")))
            }
            let refusal = processes.terminate(pid: pid, name: name, startedAt: startedAt, force: force) {
                reply(.success(Self.nothing))
            }
            if let refusal { reply(.failure(Self.error(for: refusal))) }
        }
    }

    /// The key a preference of this tool is saved under.
    private func key(_ preference: String) -> String {
        ExternalToolManifest.storageKey(tool: tool, preference: preference)
    }

    // MARK: - Between the protocol's values and the app's

    /// `{}`: the answer to a request that was simply done.
    static let nothing = JSONValue.object([:])

    static let badParams: Result<JSONValue, RPCErrorObject> =
        .failure(RPCErrorObject(code: RPCErrorCode.invalidParams, message: "invalid params"))

    static func read<Params: Decodable>(_ type: Params.Type, _ params: JSONValue?) -> Params? {
        try? (params ?? nothing).decode(type)
    }

    static func answer<Value: Encodable>(_ value: Value) -> Result<JSONValue, RPCErrorObject> {
        guard let json = try? JSONValue(encoding: value) else {
            return .failure(RPCErrorObject(code: RPCErrorCode.internalError, message: "the answer could not be written"))
        }
        return .success(json)
    }

    /// The answer to an operation that says nothing but whether it was
    /// refused.
    static func done(_ refusal: BrokerRefusal?) -> Result<JSONValue, RPCErrorObject> {
        refusal.map { .failure(error(for: $0)) } ?? .success(nothing)
    }

    /// The broker's four refusals, as the protocol's four codes.
    package static func error(for refusal: BrokerRefusal) -> RPCErrorObject {
        switch refusal {
        case .notDeclared(let capability):
            return RefusalCode.notInUses.error(service: AppService(rawValue: capability.rawValue))
        case .notInstalled:
            return RefusalCode.notInstalled.error()
        case .notGranted(let permission):
            return RefusalCode.permissionMissing.error(permission: permission.rawValue)
        case .unavailable:
            return RefusalCode.unavailable.error()
        }
    }

    static func error(for problem: StorageProblem) -> RPCErrorObject {
        switch problem {
        case .refused(let refusal):
            return error(for: refusal)
        case .undeclared:
            return RPCErrorObject(code: RPCErrorCode.invalidParams, message: "not a preference the manifest declares")
        case .wrongKind:
            return RPCErrorObject(code: RPCErrorCode.invalidParams, message: "not the kind of value this preference holds")
        case .tooLong:
            return RPCErrorObject(code: RPCErrorCode.invalidParams, message: "longer than a preference may be")
        }
    }

    /// A key equivalent as Accessibility counts it: 1 is Shift, 2 is
    /// Option and 4 is Control.
    static func menuKey(_ equivalent: KeyEquivalent) -> MenuKeyEquivalent {
        var mask: UInt32 = 0
        for modifier in equivalent.modifiers {
            switch modifier {
            case .shift: mask |= 1
            case .option: mask |= 2
            case .control: mask |= 4
            }
        }
        return MenuKeyEquivalent(character: equivalent.character, modifierMask: mask)
    }

    static func json(_ value: PreferenceDeclaration.Value) -> JSONValue {
        switch value {
        case .bool(let flag): return .bool(flag)
        case .string(let text): return .string(text)
        case .int(let number): return .number(Double(number))
        case .double(let number): return .number(number)
        }
    }

    /// A value from the wire as the kind of `declared`; nil when it is of
    /// another kind. A whole number is what an integer preference holds.
    static func value(_ json: JSONValue, like declared: PreferenceDeclaration.Value) -> PreferenceDeclaration.Value? {
        switch (declared, json) {
        case (.bool, .bool(let flag)): return .bool(flag)
        case (.string, .string(let text)): return .string(text)
        case (.int, .number(let number)): return Int(exactly: number).map(PreferenceDeclaration.Value.int)
        case (.double, .number(let number)): return .double(number)
        default: return nil
        }
    }

    /// A value from the wire as what it most plainly is; nil for a list, an
    /// object or null, which no preference holds.
    static func value(_ json: JSONValue) -> PreferenceDeclaration.Value? {
        switch json {
        case .bool(let flag): return .bool(flag)
        case .string(let text): return .string(text)
        case .number(let number): return .double(number)
        case .null, .array, .object: return nil
        }
    }
}
