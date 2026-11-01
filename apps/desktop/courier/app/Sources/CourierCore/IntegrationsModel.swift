// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Darwin
import Foundation

/// The person's answer to a client asking to connect.
public enum PairingAnswer: Equatable, Sendable {
    case allow
    case allowAndSend
    case deny
}

/// What Settings ▸ Integrations shows of the local API (MCP for Claude and other apps) and the connections it has
/// approved, and the prompt a client asking to connect raises.
///
/// The engine owns the settings and the tokens: this model reads them (`integrations.status`,
/// `integrations.tokens`) and asks for changes. A new connection's secret comes back once, from
/// `integrations.createToken`; it is kept here only while the new-connection sheet shows it, and cleared when the
/// sheet goes.
@MainActor
public final class IntegrationsModel: ObservableObject {
    /// The local API's state; nil until the engine has answered.
    @Published public private(set) var status: IntegrationsStatus?
    @Published public private(set) var tokens: [APIToken] = []
    /// What the port field holds. It is saved only when it is a whole number from 1024 to 65535.
    @Published public var portText = String(IntegrationsStatus.defaultPort)
    /// Why the port typed was not saved; nil when it was.
    @Published public private(set) var portError: String?
    /// The last change the engine refused, for people.
    @Published public private(set) var lastError: String?

    /// Turning Remote Access on asks first.
    @Published public var isConfirmingRemoteAccess = false
    /// The connection Revoke was clicked for, waiting for the confirm.
    @Published public var tokenPendingRevoke: APIToken?

    /// The new-connection sheet: open, its fields, and once made, the connection with its secret (shown once).
    @Published public var isPresentingNewConnection = false
    @Published public var newConnectionName = ""
    @Published public var newConnectionCanSend = false
    @Published public private(set) var createdConnection: CreateTokenResult?
    @Published public private(set) var isCreating = false

    /// The client asking to connect, while its prompt shows. One at a time, as the engine allows.
    @Published public private(set) var pairRequest: PairRequest?

    public static let minimumPort = 1024
    public static let maximumPort = 65535
    /// What the person reads in the confirm before Remote Access goes on.
    public static let remoteAccessWarning = String(
        localized: "Other devices on your network will be able to connect to Courier with an approved token. Traffic is not encrypted."
    )

    public let appModel: AppModel?
    /// Contents/Helpers/courier-engine: the stdio command runs it.
    public let enginePath: String
    private let networkAddress: () -> String?
    private let explicitLifecycle: SystemLifecycleModel?

    /// - Parameters:
    ///   - enginePath: the engine the Claude Code stdio command names.
    ///   - networkAddress: this Mac's address on its network, for the endpoint Remote Access offers.
    public init(
        appModel: AppModel?,
        enginePath: String,
        lifecycle: SystemLifecycleModel? = nil,
        networkAddress: @escaping () -> String? = { LocalNetworkAddress.current() }
    ) {
        self.appModel = appModel
        self.enginePath = enginePath
        self.networkAddress = networkAddress
        self.explicitLifecycle = lifecycle
        appModel?.onConnect { [weak self] _ in await self?.refresh() }
        appModel?.onNotice { [weak self] notice in self?.receive(notice) }
    }

    private var lifecycle: SystemLifecycleModel? {
        explicitLifecycle ?? appModel?.lifecycle
    }

    private var canChange: Bool {
        AppLockGate.shared.canPerform(.settingsChange, lifecycle: lifecycle)
    }

    // MARK: - What the pane shows

    public var isEnabled: Bool { status?.enabled ?? false }
    public var isRemote: Bool { status?.remote ?? false }
    public var port: Int { status?.port ?? IntegrationsStatus.defaultPort }

    /// "Listening on 127.0.0.1:23390", "Listening on all addresses, port 23390", "Off", or why it isn't listening.
    public var statusLine: String {
        Self.statusLine(for: status)
    }

    public static func statusLine(for status: IntegrationsStatus?) -> String {
        guard let status, status.enabled else { return String(localized: "Off") }
        if status.listening {
            return status.remote
                ? String(localized: "Listening on all addresses, port \(String(status.port))")
                : String(localized: "Listening on 127.0.0.1:\(String(status.port))")
        }
        return status.error.isEmpty ? String(localized: "Not listening") : status.error
    }

    /// Whether the status line is a problem to show in red: enabled, and not listening.
    public var statusIsProblem: Bool {
        guard let status else { return false }
        return status.enabled && !status.listening
    }

    /// The MCP endpoint other apps connect to: this Mac's network address with Remote Access on, else 127.0.0.1.
    public var endpoint: String {
        let host = isRemote ? (networkAddress().map(Self.urlHost) ?? "127.0.0.1") : "127.0.0.1"
        return "http://\(host):\(port)/v0/mcp"
    }

    /// The endpoint on this Mac, which the setup commands use: a client on the same Mac always reaches 127.0.0.1.
    public var localEndpoint: String {
        "http://127.0.0.1:\(port)/v0/mcp"
    }

    private static func urlHost(_ address: String) -> String {
        address.contains(":") ? "[\(address)]" : address
    }

    // MARK: - Reading

    public func refresh() async {
        guard canChange, let client = appModel?.client else { return }
        do {
            let status: IntegrationsStatus = try await client.call("integrations.status", Empty())
            apply(status)
            let tokens: [APIToken] = try await client.call("integrations.tokens", Empty())
            self.tokens = tokens
        } catch {
            lastError = EngineErrorText.text(for: error, fallback: String(localized: "Couldn’t read the connection settings."))
        }
    }

    private func apply(_ status: IntegrationsStatus) {
        self.status = status
        portText = String(status.port)
        portError = nil
    }

    // MARK: - Changing

    public func setEnabled(_ enabled: Bool) async {
        await update(IntegrationsUpdateParams(enabled: enabled))
    }

    /// Off goes at once; on asks first (`isConfirmingRemoteAccess`), and `confirmRemoteAccess` turns it on.
    public func requestRemoteAccess(_ on: Bool) async {
        if on {
            isConfirmingRemoteAccess = true
        } else {
            await update(IntegrationsUpdateParams(remote: false))
        }
    }

    public func confirmRemoteAccess() async {
        isConfirmingRemoteAccess = false
        await update(IntegrationsUpdateParams(remote: true))
    }

    public func cancelRemoteAccess() {
        isConfirmingRemoteAccess = false
    }

    /// The port in `portText`, if it is a whole number from 1024 to 65535. Anything else is not saved, and
    /// `portError` says why.
    public static func validPort(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)),
              (minimumPort ... maximumPort).contains(value) else { return nil }
        return value
    }

    public func savePort() async {
        guard let value = Self.validPort(portText) else {
            portError = String(localized: "Enter a port from 1024 to 65535.")
            return
        }
        portError = nil
        guard value != status?.port else { return }
        await update(IntegrationsUpdateParams(port: value))
    }

    private func update(_ params: IntegrationsUpdateParams) async {
        guard canChange, let client = appModel?.client else { return }
        lastError = nil
        do {
            let status: IntegrationsStatus = try await client.call("integrations.update", params)
            apply(status)
        } catch {
            lastError = EngineErrorText.text(for: error, fallback: String(localized: "Couldn’t change the connection settings."))
        }
    }

    public func setCanSend(_ canSend: Bool, for token: APIToken) async {
        guard canChange, let client = appModel?.client else { return }
        lastError = nil
        do {
            let _: Empty = try await client.call("integrations.setCanSend", SetCanSendParams(id: token.id, canSend: canSend))
        } catch {
            lastError = EngineErrorText.text(for: error, fallback: String(localized: "Couldn’t change that connection."))
        }
        await refreshTokens()
    }

    public func confirmRevoke() async {
        guard let token = tokenPendingRevoke else { return }
        tokenPendingRevoke = nil
        guard canChange, let client = appModel?.client else { return }
        lastError = nil
        do {
            let _: Empty = try await client.call("integrations.revokeToken", TokenParams(id: token.id))
        } catch {
            lastError = EngineErrorText.text(for: error, fallback: String(localized: "Couldn’t revoke that connection."))
        }
        await refreshTokens()
    }

    private func refreshTokens() async {
        guard canChange, let client = appModel?.client,
              let tokens: [APIToken] = try? await client.call("integrations.tokens", Empty()) else { return }
        self.tokens = tokens
    }

    // MARK: - A new connection

    public func beginNewConnection() {
        newConnectionName = ""
        newConnectionCanSend = false
        createdConnection = nil
        isPresentingNewConnection = true
    }

    public var canCreateConnection: Bool {
        !isCreating && !newConnectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func createConnection() async {
        guard canCreateConnection, canChange, let client = appModel?.client else { return }
        isCreating = true
        lastError = nil
        defer { isCreating = false }
        do {
            let params = CreateTokenParams(name: newConnectionName, canSend: newConnectionCanSend)
            createdConnection = try await client.call("integrations.createToken", params)
        } catch {
            lastError = EngineErrorText.text(for: error, fallback: String(localized: "Couldn’t make the connection."))
        }
        await refreshTokens()
    }

    /// The sheet goes, and the secret with it: it can't be shown again.
    public func dismissNewConnection() {
        isPresentingNewConnection = false
        createdConnection = nil
        newConnectionName = ""
        newConnectionCanSend = false
    }

    /// Shows a made connection without asking the engine: the snapshot harness, and tests.
    public func setForTesting(status: IntegrationsStatus?, tokens: [APIToken] = [], created: CreateTokenResult? = nil) {
        self.status = status
        self.tokens = tokens
        if let status { portText = String(status.port) }
        createdConnection = created
    }

    // MARK: - Setup commands for a new connection's secret

    /// Claude Code over HTTP.
    public func claudeHTTPCommand(secret: String) -> String {
        "claude mcp add --transport http courier \(localEndpoint) --header \"Authorization: Bearer \(secret)\""
    }

    /// Claude Code over stdio, through the engine's mcp-stdio.
    public func claudeStdioCommand(secret: String) -> String {
        let engine = enginePath.contains(" ") ? "\"\(enginePath)\"" : enginePath
        let portFlag = port == IntegrationsStatus.defaultPort ? "" : " --port \(port)"
        return "claude mcp add courier -e COURIER_TOKEN=\(secret) -- \(engine) mcp-stdio\(portFlag)"
    }

    private func httpConfig(secret: String, extra: [String: String] = [:]) -> Data {
        var object: [String: Any] = ["url": localEndpoint, "headers": ["Authorization": "Bearer \(secret)"]]
        for (key, value) in extra { object[key] = value }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]))
            ?? Data()
    }

    private static let queryValue: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    /// Cursor's MCP install link, with the HTTP form.
    public func cursorLink(secret: String) -> URL? {
        let config = httpConfig(secret: secret).base64EncodedString()
        let encoded = config.addingPercentEncoding(withAllowedCharacters: Self.queryValue) ?? config
        return URL(string: "cursor://anysphere.cursor-deeplink/mcp/install?name=courier&config=\(encoded)")
    }

    /// VS Code's MCP install link, with the HTTP form.
    public func vsCodeLink(secret: String) -> URL? {
        let json = String(decoding: httpConfig(secret: secret, extra: ["name": "courier", "type": "http"]), as: UTF8.self)
        let encoded = json.addingPercentEncoding(withAllowedCharacters: Self.queryValue) ?? json
        return URL(string: "vscode:mcp/install?\(encoded)")
    }

    // MARK: - Pairing

    /// A pairing request shows its prompt, unless one already shows (the engine lets one wait at a time, so a
    /// second is not replaced in) or Courier is locked (it then times out, and the client is refused). Its end,
    /// however it came, takes the prompt away.
    public func receive(_ notice: EngineNotice) {
        switch notice {
        case let .pairRequest(request):
            guard pairRequest == nil, !(lifecycle?.isLocked ?? false) else { return }
            pairRequest = request
        case let .pairEnded(ended):
            if pairRequest?.requestID == ended.requestID { pairRequest = nil }
        case .focus:
            break
        }
    }

    /// The prompt's question. The client's name is text the client chose: it is only ever shown as plain text.
    public static func pairingQuestion(_ request: PairRequest) -> String {
        String(localized: "“\(request.clientName)” wants to read your chats in Courier.")
    }

    public func answerPairing(_ answer: PairingAnswer) async {
        guard let request = pairRequest else { return }
        pairRequest = nil
        guard let client = appModel?.client else { return }
        let params = AnswerPairingParams(
            requestID: request.requestID,
            allow: answer != .deny,
            canSend: answer == .allowAndSend ? true : nil
        )
        do {
            let _: Empty = try await client.call("integrations.answerPairing", params)
        } catch {
            // Answered too late, or the client went away: nothing was approved.
            lastError = EngineErrorText.text(for: error, fallback: String(localized: "That request to connect had already ended."))
        }
        await refreshTokens()
    }
}

/// This Mac's address on its local network, for the endpoint Remote Access offers other devices.
public enum LocalNetworkAddress {
    /// The first IPv4 address of an up, non-loopback interface (Wi-Fi or Ethernet first); else an IPv6 one that is
    /// not link-local; nil with no network.
    public static func current() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var v4: [(name: String, address: String)] = []
        var v6: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let addr = entry.pointee.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(family == UInt8(AF_INET) ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: host)
            let name = String(cString: entry.pointee.ifa_name)
            if family == UInt8(AF_INET) {
                v4.append((name, address))
            } else if !address.lowercased().hasPrefix("fe80"), !address.contains("%") {
                v6.append(address)
            }
        }
        if let preferred = v4.first(where: { $0.name.hasPrefix("en") }) { return preferred.address }
        return v4.first?.address ?? v6.first
    }
}
