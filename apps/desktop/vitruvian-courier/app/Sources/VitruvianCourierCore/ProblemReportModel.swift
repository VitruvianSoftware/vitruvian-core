// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Swift mirror of the engine's Ruling 10 crash and stderr export sanitizer (`engine/internal/logscrub`).
///
/// Ensures both engine-exported and supervisor-captured stderr lines, as well as any diagnostic report fields,
/// strip home directory paths (`/Users/<name>`), phone numbers, tokens, quoted names/messages, and raw panic
/// arguments before anything is previewed or written to a local problem report bundle.
public enum StderrExportFilter {
    public static let idToken = "[id]"
    public static let quotedToken = "[quoted]"
    public static let pathToken = "[path]"

    private static let allowedKeys: Set<String> = [
        "level", "time", "message", "error", "caller",
        "bridge", "network", "component", "sublogger", "action", "subaction",
        "event_type", "bridge_evt_type", "method", "status",
        "change", "waited", "retry_in", "batches", "took_ms",
        "messages", "chats", "people", "per_millisecond", "open_connections",
        "panic", "stack",
    ]

    private static let countKeys: Set<String> = [
        "waited", "retry_in", "batches", "took_ms", "messages", "chats", "people",
        "per_millisecond", "open_connections",
    ]

    private static let validLevels: Set<String> = [
        "trace", "debug", "info", "warn", "error", "fatal", "panic",
    ]

    private static let userHomeRE = try! NSRegularExpression(pattern: #"(?:/Users|/home)/[^/\s:"']+/?"#)
    private static let goroutineRE = try! NSRegularExpression(pattern: #"^goroutine \d+ \[[a-zA-Z0-9 ,._-]+\]:$"#)
    private static let frameCallRE = try! NSRegularExpression(
        pattern: #"^((?:created by )?(?:panic|[A-Za-z0-9_./@-]+(?:\.\(\*?[A-Za-z0-9_]+(?:\[[^\]]+\])?\))?(?:\.[A-Za-z0-9_]+(?:\[[^\]]+\])?)+))\([^\n]*\)( in goroutine \d+)?$"#
    )
    private static let createdByRE = try! NSRegularExpression(
        pattern: #"^created by [A-Za-z0-9_./@-]+(?:\.\(\*?[A-Za-z0-9_]+(?:\[[^\]]+\])?\))?(?:\.[A-Za-z0-9_]+(?:\[[^\]]+\])?)+( in goroutine \d+)?$"#
    )
    private static let frameFileRE = try! NSRegularExpression(pattern: #"^\t(.+\.go:\d+)( \+0x[0-9a-fA-F]+)?$"#)

    private static let quotedRE = try! NSRegularExpression(pattern: #""[^"\n]*""#)
    private static let urlRE = try! NSRegularExpression(
        pattern: #"\b([a-zA-Z][a-zA-Z0-9+.-]*)://([^/\s"'<>?#]*)([^\s"'<>]*)"#
    )
    private static let matrixIDRE = try! NSRegularExpression(
        pattern: #"[@!#+][^\s:"'<>,;()\[\]{}@]+:[A-Za-z0-9.-]*[A-Za-z0-9](?::\d+)?"#
    )
    private static let eventIDRE = try! NSRegularExpression(
        pattern: #"\$[A-Za-z0-9+/_=-]{6,}(?::[A-Za-z0-9.-]*[A-Za-z0-9])?"#
    )
    private static let addressRE = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9._%+=:-]*[A-Za-z0-9_%+=-]@[A-Za-z0-9.-]*[A-Za-z0-9]"#
    )
    private static let handleRE = try! NSRegularExpression(
        pattern: #"@[A-Za-z0-9._=-]*[A-Za-z0-9_=]"#
    )
    private static let uuidRE = try! NSRegularExpression(
        pattern: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
    )
    private static let slackPairRE = try! NSRegularExpression(
        pattern: #"\b[TtEe][A-Za-z0-9]{8,10}-[UuWwCcDdGgBb][A-Za-z0-9]{8,10}\b"#
    )
    private static let slackSingleRE = try! NSRegularExpression(
        pattern: #"\b[UuWwTtCcDdGgBbEe][A-Za-z0-9]{8,10}\b"#
    )
    private static let slackTokenRE = try! NSRegularExpression(
        pattern: #"\bxox[a-zA-Z]-[A-Za-z0-9-]+\b"#
    )
    private static let intlPhoneRE = try! NSRegularExpression(
        pattern: #"\+\d(?:[ ().-]{0,2}\d){5,14}"#
    )
    private static let naPhoneRE = try! NSRegularExpression(
        pattern: #"\(?\b\d{3}\)?[ .-]\d{3}[ .-]\d{4}\b"#
    )
    private static let digitsRunRE = try! NSRegularExpression(pattern: #"\d{6,}"#)
    private static let tokenRE = try! NSRegularExpression(pattern: #"[A-Za-z0-9_+=]{8,}"#)

    /// Scrubs an array of raw stderr lines according to Ruling 10.
    public static func scrub(_ lines: [String]) -> [String] {
        var result: [String] = []
        for raw in lines {
            for subline in raw.components(separatedBy: .newlines) {
                if let clean = scrubLine(subline) {
                    result.append(clean)
                }
            }
        }
        return result
    }

    /// Scrubs a single raw stderr line according to Ruling 10, returning `nil` if the line must be dropped.
    public static func scrubLine(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        let stripped = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }

        // 1. JSON log line
        if stripped.hasPrefix("{") {
            return scrubJSONObjectLine(stripped)
        }

        // 2. Startup error prefix ("courier-engine: ...")
        if trimmed.hasPrefix("courier-engine: ") {
            let suffix = String(trimmed.dropFirst("courier-engine: ".count))
            return "courier-engine: " + scrubPath(suffix)
        }

        // 3. Panic / fatal header
        if trimmed.hasPrefix("panic: ") {
            return "panic: [redacted]"
        }
        if trimmed.hasPrefix("fatal error: ") {
            return "fatal error: [redacted]"
        }

        // 4. Goroutine header
        if matchesFull(goroutineRE, in: trimmed) != nil {
            return trimmed
        }

        // 5. Stack frame source file line ("\t/path/to/file.go:123 +0x1c4")
        if let match = matchesFull(frameFileRE, in: trimmed) {
            let filePart = substring(trimmed, range: match.range(at: 1)) ?? ""
            let offsetPart = substring(trimmed, range: match.range(at: 2)) ?? ""
            return "\t" + cleanSourcePath(filePart) + offsetPart
        }

        // 6. Stack frame function call line -> strip raw pointer/value arguments to "(...)"
        if let match = matchesFull(frameCallRE, in: trimmed) {
            let fnPart = substring(trimmed, range: match.range(at: 1)) ?? ""
            let goroutinePart = substring(trimmed, range: match.range(at: 2)) ?? ""
            return fnPart + "(...)" + goroutinePart
        }
        if matchesFull(createdByRE, in: trimmed) != nil {
            return trimmed
        }

        return nil
    }

    /// Replaces home directory prefixes (`/Users/<name>` or `/home/<name>`) with `~` and applies `redact(_:)`.
    public static func scrubPath(_ input: String) -> String {
        var s = replaceHomeDirectories(in: input)
        s = redact(s)
        return s
    }

    /// Replaces only home directory prefixes (`/Users/<name>` or `/home/<name>`) with `~` without running `redact`.
    private static func replaceHomeDirectories(in input: String) -> String {
        var s = input
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for candidate in [home, NSHomeDirectory()] {
            let clean = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !clean.isEmpty else { continue }
            let prefix = "/" + clean
            s = s.replacingOccurrences(of: prefix + "/", with: "~/")
            for delim in [":", " ", "\"", "'", "\t", "\r", "\n", ")"] {
                s = s.replacingOccurrences(of: prefix + delim, with: "~" + delim)
            }
            if s.hasSuffix(prefix) {
                s = String(s.dropLast(prefix.count)) + "~"
            }
        }
        s = replaceMatches(userHomeRE, in: s) { match in
            match.hasSuffix("/") ? "~/" : "~"
        }
        return s
    }

    /// Redacts quoted strings, URLs, Matrix IDs, addresses, handles, UUIDs, Slack IDs/tokens, phone numbers,
    /// digit runs, and opaque identifier tokens.
    public static func redact(_ input: String) -> String {
        var s = replaceHomeDirectories(in: input)
        s = replaceMatches(quotedRE, in: s) { quoted in
            guard quoted.count >= 2 else { return quotedToken }
            let inner = String(quoted.dropFirst().dropLast())
            if let match = matchesFull(urlRE, in: inner) {
                return "\"\(scrubURL(inner, match: match))\""
            }
            return quotedToken
        }
        s = replaceRegexMatches(urlRE, in: s) { text, match in
            scrubURL(text, match: match)
        }
        for regex in [matrixIDRE, eventIDRE, addressRE, handleRE, uuidRE] {
            s = replaceMatches(regex, in: s) { _ in idToken }
        }
        for regex in [slackPairRE, slackSingleRE] {
            s = replaceMatches(regex, in: s) { match in
                isSlackID(match) ? idToken : match
            }
        }
        for regex in [slackTokenRE, intlPhoneRE, naPhoneRE, digitsRunRE] {
            s = replaceMatches(regex, in: s) { _ in idToken }
        }
        s = replaceMatches(tokenRE, in: s) { word in
            isOpaqueID(word) ? idToken : word
        }
        return s
    }

    // MARK: - Private Helpers

    private static func cleanSourcePath(_ path: String) -> String {
        for marker in ["/go/pkg/mod/", "/external/", "github.com/VitruvianSoftware/courier/"] {
            if let range = path.range(of: marker) {
                if marker == "github.com/VitruvianSoftware/courier/" {
                    return String(path[range.lowerBound...])
                }
                return String(path[range.upperBound...])
            }
        }
        if let range = path.range(of: "apps/desktop/courier/") {
            let suffix = String(path[range.upperBound...])
            return "github.com/VitruvianSoftware/courier/" + suffix
        }
        return (path as NSString).lastPathComponent
    }

    private static func scrubJSONObjectLine(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let rawObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inputKeys = extractTopLevelJSONKeys(line) else {
            return nil
        }

        var parts: [String] = []
        for key in inputKeys {
            guard allowedKeys.contains(key), let val = rawObj[key] else { continue }
            if let str = val as? String {
                if key == "level" {
                    guard validLevels.contains(str) else { continue }
                    parts.append("\(encodeJSONString(key)):\(encodeJSONString(str))")
                } else if key == "time" {
                    parts.append("\(encodeJSONString(key)):\(encodeJSONString(str))")
                } else {
                    parts.append("\(encodeJSONString(key)):\(encodeJSONString(scrubPath(str)))")
                }
            } else if let num = val as? NSNumber {
                if CFGetTypeID(num) == CFBooleanGetTypeID() {
                    parts.append("\(encodeJSONString(key)):\(num.boolValue ? "true" : "false")")
                } else {
                    let rawNum = num.stringValue
                    let digitCount = rawNum.filter(\.isNumber).count
                    if !countKeys.contains(key) && digitCount >= 6 {
                        parts.append("\(encodeJSONString(key)):\(encodeJSONString(idToken))")
                    } else {
                        parts.append("\(encodeJSONString(key)):\(rawNum)")
                    }
                }
            }
        }
        guard !parts.isEmpty else { return nil }
        return "{\(parts.joined(separator: ","))}"
    }

    /// Extracts top-level JSON object keys in their original wire order so Swift and Go scrubbers emit identical JSON.
    private static func extractTopLevelJSONKeys(_ line: String) -> [String]? {
        let chars = Array(line)
        var i = 0
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        guard i < chars.count, chars[i] == "{" else { return nil }
        var depth = 0
        var expectingKey = false
        var keys: [String] = []

        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                let start = i
                i += 1
                var escaped = false
                while i < chars.count {
                    let c = chars[i]
                    if escaped {
                        escaped = false
                    } else if c == "\\" {
                        escaped = true
                    } else if c == "\"" {
                        break
                    }
                    i += 1
                }
                guard i < chars.count else { return nil }
                if depth == 1 && expectingKey {
                    let rawLiteral = String(chars[start...i])
                    if let data = rawLiteral.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(String.self, from: data) {
                        keys.append(decoded)
                    }
                    expectingKey = false
                }
                i += 1
                continue
            }
            switch ch {
            case "{":
                depth += 1
                if depth == 1 { expectingKey = true }
            case "}":
                depth -= 1
            case "[":
                depth += 1
            case "]":
                depth -= 1
            case ",":
                if depth == 1 { expectingKey = true }
            case ":":
                if depth == 1 { expectingKey = false }
            default:
                break
            }
            i += 1
        }
        return depth == 0 ? keys : nil
    }

    private static func encodeJSONString(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded.replacingOccurrences(of: "\\/", with: "/")
    }

    private static func isSlackID(_ m: String) -> Bool {
        let hasDigit = m.contains(where: \.isNumber)
        return hasDigit && (m.uppercased() == m || m.lowercased() == m)
    }

    private static func isOpaqueID(_ word: String) -> Bool {
        var digits = 0
        var letters = 0
        for ch in word.unicodeScalars {
            if ("0"..."9").contains(ch) {
                digits += 1
            } else if ("a"..."z").contains(ch) || ("A"..."Z").contains(ch) {
                letters += 1
            }
        }
        return letters > 0 && (digits >= 2 || (word.count >= 16 && digits >= 1))
    }

    private static func scrubURL(_ full: String, match: NSTextCheckingResult) -> String {
        let scheme = substring(full, range: match.range(at: 1)) ?? "https"
        var host = substring(full, range: match.range(at: 2)) ?? ""
        let rest = substring(full, range: match.range(at: 3)) ?? ""
        if let atIdx = host.lastIndex(of: "@") {
            host = String(host[host.index(after: atIdx)...])
        }
        if let colonIdx = host.firstIndex(of: ":"), !host[host.index(after: colonIdx)...].contains(":") {
            host = String(host[..<colonIdx])
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if labels.count > 2 && !isIPv4(host) {
            host = "*." + labels.suffix(2).joined(separator: ".")
        }
        var out = "\(scheme)://\(host)"
        if !rest.isEmpty && rest != "/" {
            out += "/\(pathToken)"
        }
        return out
    }

    private static func isIPv4(_ host: String) -> Bool {
        host.unicodeScalars.allSatisfy { $0 == "." || ("0"..."9").contains($0) }
    }

    private static func matchesFull(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.range == nsRange else {
            return nil
        }
        return match
    }

    private static func substring(_ text: String, range: NSRange) -> String? {
        guard range.location != NSNotFound, let r = Range(range, in: text) else { return nil }
        return String(text[r])
    }

    private static func replaceMatches(
        _ regex: NSRegularExpression,
        in text: String,
        with transform: (String) -> String
    ) -> String {
        replaceRegexMatches(regex, in: text) { full, match in
            let sub = substring(full, range: match.range) ?? ""
            return transform(sub)
        }
    }

    private static func replaceRegexMatches(
        _ regex: NSRegularExpression,
        in text: String,
        with transform: (String, NSTextCheckingResult) -> String
    ) -> String {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return text }
        var result = text
        for match in matches.reversed() {
            guard let r = Range(match.range, in: result) else { continue }
            let replacement = transform(result, match)
            result.replaceSubrange(r, with: replacement)
        }
        return result
    }
}

/// Scrubbed bridge entry written into `report.json` and `bridges.json` (never includes account display names,
/// phone numbers, tokens, or unredacted error strings).
public struct ScrubbedBridgeDiagnostic: Codable, Equatable, Sendable {
    public var network: String
    public var displayName: String
    public var bridgeID: String
    public var modulePath: String
    public var version: String
    public var mautrixVersion: String
    public var state: String
    public var error: String?
    public var message: String?
    public var startedAt: Int64
    public var accountCount: Int
    public var loginStates: [String]

    enum CodingKeys: String, CodingKey {
        case network
        case displayName = "display_name"
        case bridgeID = "bridge_id"
        case modulePath = "module_path"
        case version
        case mautrixVersion = "mautrix_version"
        case state
        case error
        case message
        case startedAt = "started_at"
        case accountCount = "account_count"
        case loginStates = "login_states"
    }

    public init(from bridge: BridgeInfo) {
        self.network = bridge.network
        self.displayName = bridge.displayName
        self.bridgeID = bridge.bridgeID
        self.modulePath = bridge.modulePath
        self.version = bridge.version
        self.mautrixVersion = bridge.mautrixVersion
        self.state = bridge.state
        self.error = bridge.error.map(StderrExportFilter.scrubPath)
        self.message = bridge.message.map(StderrExportFilter.scrubPath)
        self.startedAt = bridge.startedAt
        let logins = bridge.accounts.flatMap(\.logins)
        self.accountCount = logins.count
        self.loginStates = logins.map(\.state.rawValue)
    }
}

/// Scrubbed diagnostic summary written to `report.json` (and `summary.json`) inside the local problem report bundle.
public struct ProblemReportDocument: Codable, Equatable, Sendable {
    public var description: String
    public var appVersion: String
    public var macOSVersion: String
    public var protocolVersion: Int
    public var schemaVersion: Int
    public var goVersion: String
    public var bridges: [ScrubbedBridgeDiagnostic]
    public var roomDetails: RoomDiagnostic?
    public var messageDetails: MessageDiagnostic?

    enum CodingKeys: String, CodingKey {
        case description
        case appVersion = "app_version"
        case macOSVersion = "macos_version"
        case protocolVersion = "protocol_version"
        case schemaVersion = "schema_version"
        case goVersion = "go_version"
        case bridges
        case roomDetails = "room_details"
        case messageDetails = "message_details"
    }
}

public enum ReportUploadDisposition: Equatable, Sendable {
    case unavailable(reason: String)
    case uploaded(referenceID: String)
}

/// Spec §3 seam for uploading scrubbed problem reports. Iteration 1's `UnavailableReportUploader`
/// is offline-only and directs the person to save the scrubbed bundle locally on this Mac.
public protocol ReportUploader: Sendable {
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    func upload(bundleURL: URL, description: String) async -> ReportUploadDisposition
}

public struct UnavailableReportUploader: ReportUploader {
    public init() {}
    public var isAvailable: Bool { false }
    public var unavailableReason: String {
        String(localized: "Direct report upload isn’t available yet in Courier. Save a scrubbed problem report on this Mac instead.")
    }
    public func upload(bundleURL _: URL, description _: String) async -> ReportUploadDisposition {
        .unavailable(reason: unavailableReason)
    }
}

/// Model for the local-only **Report a Problem** sheet (`⌘⇧P`).
///
/// Builds a local diagnostic bundle containing `report.json`, `bridges.json`, `stderr-scrubbed.log`, and any
/// user-attached screenshot/video files. Never uploads anything over the network.
@MainActor
public final class ProblemReportModel: ObservableObject {
    @Published public var descriptionText: String = "" {
        didSet { rebuildPreviewText() }
    }
    @Published public var includeMessageDetails: Bool = false {
        didSet { rebuildPreviewText() }
    }
    @Published public var attachedFileURLs: [URL] = []
    @Published public private(set) var diagnostics: DiagnosticsExportResult? {
        didSet { rebuildPreviewText() }
    }
    @Published public private(set) var scrubbedSupervisorLines: [String] = [] {
        didSet { rebuildPreviewText() }
    }
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var isUploading: Bool = false
    @Published public private(set) var savedBundleURL: URL?
    @Published public private(set) var uploadNotice: String?
    @Published public private(set) var errorText: String?
    @Published public private(set) var previewJSONText: String = "{}"
    @Published public private(set) var previewStderrText: String = ""

    public let contextRoomID: String?
    public let contextEventID: String?
    public let reportUploader: any ReportUploader
    private weak var appModel: AppModel?

    public init(
        appModel: AppModel? = nil,
        contextRoomID: String? = nil,
        contextEventID: String? = nil,
        reportUploader: any ReportUploader = UnavailableReportUploader()
    ) {
        self.appModel = appModel
        self.contextRoomID = contextRoomID
        self.contextEventID = contextEventID
        self.reportUploader = reportUploader
        rebuildPreviewText()
    }

    /// Invokes the `ReportUploader` seam and populates `uploadNotice` with the disposition message.
    public func attemptUpload() async {
        guard !AppLockGate.shared.isLocked else {
            errorText = EngineError.appLocked.localizedDescription
            return
        }
        isUploading = true
        defer { isUploading = false }
        let bundleURL = savedBundleURL ?? FileManager.default.temporaryDirectory
        let disposition = await reportUploader.upload(bundleURL: bundleURL, description: descriptionText)
        switch disposition {
        case .unavailable(let reason):
            uploadNotice = reason
        case .uploaded(let referenceID):
            uploadNotice = referenceID
        }
    }

    public var hasContextDetails: Bool {
        (contextRoomID != nil && !(contextRoomID?.isEmpty ?? true))
            || (contextEventID != nil && !(contextEventID?.isEmpty ?? true))
    }

    /// Loads `diagnostics.export` from the engine (passing `roomID` and `eventID` only when `includeMessageDetails`
    /// is on) and scrubs `EngineSupervisor.recentErrorOutput` through `StderrExportFilter.scrub(_:)`.
    public func loadDiagnostics() async {
        guard !AppLockGate.shared.isLocked else {
            errorText = EngineError.appLocked.localizedDescription
            return
        }
        errorText = nil
        if let rawSupervisor = appModel?.supervisor.recentErrorOutput {
            scrubbedSupervisorLines = StderrExportFilter.scrub(rawSupervisor)
        } else {
            scrubbedSupervisorLines = []
        }

        guard let client = appModel?.client else { return }
        let params = DiagnosticsExportParams(
            roomID: includeMessageDetails ? contextRoomID : nil,
            eventID: includeMessageDetails ? contextEventID : nil
        )
        do {
            var exported: DiagnosticsExportResult = try await client.call("diagnostics.export", params)
            exported.scrubbedStderr = StderrExportFilter.scrub(exported.scrubbedStderr)
            if var msg = exported.messageDetails {
                msg.statusReason = StderrExportFilter.scrubPath(msg.statusReason)
                exported.messageDetails = msg
            }
            diagnostics = exported
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Writes `report.json` (and `summary.json`), `bridges.json`, `stderr-scrubbed.log`, and any user-selected
    /// attachments into a local directory or `.zip` archive at `destinationURL`. Never makes a network call.
    public func writeBundle(to destinationURL: URL) throws {
        if AppLockGate.shared.isLocked {
            throw EngineError.appLocked
        }
        let payload = makeBundlePayload()
        try Self.writePayload(payload, to: destinationURL)
        savedBundleURL = destinationURL
    }

    /// Builds and writes the local diagnostic bundle off the main thread so the UI never blocks.
    public func saveBundle(to destinationURL: URL) async {
        guard !AppLockGate.shared.isLocked else {
            errorText = "Courier is locked."
            return
        }
        isSaving = true
        errorText = nil
        let payload = makeBundlePayload()
        do {
            try await Task.detached(priority: .userInitiated) {
                try Self.writePayload(payload, to: destinationURL)
            }.value
            savedBundleURL = destinationURL
        } catch {
            errorText = error.localizedDescription
        }
        isSaving = false
    }

    /// Default archive filename for `NSSavePanel`.
    public static func defaultArchiveFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "courier-problem-report-\(formatter.string(from: now)).zip"
    }

    // MARK: - Payload Construction & Off-Main-Thread Writer

    private struct BundlePayload: Sendable {
        let document: ProblemReportDocument
        let bridges: [ScrubbedBridgeDiagnostic]
        let stderrLines: [String]
        let attachments: [URL]
    }

    private func makeBundlePayload() -> BundlePayload {
        let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let macOSVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        let scrubbedBridges = (diagnostics?.bridges ?? []).map(ScrubbedBridgeDiagnostic.init(from:))
        var scrubbedMessage = includeMessageDetails ? diagnostics?.messageDetails : nil
        if var msg = scrubbedMessage {
            msg.statusReason = StderrExportFilter.scrubPath(msg.statusReason)
            scrubbedMessage = msg
        }
        let doc = ProblemReportDocument(
            description: StderrExportFilter.scrubPath(descriptionText),
            appVersion: appVersion,
            macOSVersion: macOSVersion,
            protocolVersion: diagnostics?.protocolVersion ?? CourierProtocol.version,
            schemaVersion: diagnostics?.schemaVersion ?? CourierProtocol.schemaVersion,
            goVersion: diagnostics?.goVersion ?? "",
            bridges: scrubbedBridges,
            roomDetails: includeMessageDetails ? diagnostics?.roomDetails : nil,
            messageDetails: scrubbedMessage
        )

        var combinedStderr: [String] = []
        for line in StderrExportFilter.scrub(diagnostics?.scrubbedStderr ?? []) {
            combinedStderr.append(line)
        }
        for line in StderrExportFilter.scrub(scrubbedSupervisorLines) where !combinedStderr.contains(line) {
            combinedStderr.append(line)
        }

        return BundlePayload(
            document: doc,
            bridges: scrubbedBridges,
            stderrLines: combinedStderr,
            attachments: attachedFileURLs
        )
    }

    private nonisolated static func writePayload(_ payload: BundlePayload, to destinationURL: URL) throws {
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let reportData = try encoder.encode(payload.document)
        let bridgesData = try encoder.encode(payload.bridges)
        let stderrText = payload.stderrLines.joined(separator: "\n") + (payload.stderrLines.isEmpty ? "" : "\n")
        let stderrData = Data(stderrText.utf8)

        let writeFiles: (URL) throws -> Void = { dir in
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try reportData.write(to: dir.appendingPathComponent("report.json"), options: .atomic)
            try reportData.write(to: dir.appendingPathComponent("summary.json"), options: .atomic)
            try bridgesData.write(to: dir.appendingPathComponent("bridges.json"), options: .atomic)
            try stderrData.write(to: dir.appendingPathComponent("stderr-scrubbed.log"), options: .atomic)

            if !payload.attachments.isEmpty {
                let attachmentsDir = dir.appendingPathComponent("attachments", isDirectory: true)
                try fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
                for (index, src) in payload.attachments.enumerated() where fm.fileExists(atPath: src.path) {
                    let ext = src.pathExtension
                    let safeName = ext.isEmpty ? "attachment-\(index + 1)" : "attachment-\(index + 1).\(ext)"
                    let dst = attachmentsDir.appendingPathComponent(safeName)
                    try? fm.removeItem(at: dst)
                    try fm.copyItem(at: src, to: dst)
                }
            }
        }

        if destinationURL.pathExtension.lowercased() == "zip" {
            let stagingRoot = fm.temporaryDirectory.appendingPathComponent("courier-report-staging-\(UUID().uuidString)", isDirectory: true)
            let bundleFolder = stagingRoot.appendingPathComponent(destinationURL.deletingPathExtension().lastPathComponent, isDirectory: true)
            defer { try? fm.removeItem(at: stagingRoot) }
            try writeFiles(bundleFolder)
            try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destinationURL)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", bundleFolder.path, destinationURL.path]
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
        } else {
            try writeFiles(destinationURL)
        }
    }

    private func rebuildPreviewText() {
        let payload = makeBundlePayload()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(payload.document),
           let str = String(data: data, encoding: .utf8) {
            previewJSONText = str
        } else {
            previewJSONText = "{}"
        }
        previewStderrText = payload.stderrLines.joined(separator: "\n")
    }

    /// Populates diagnostic state directly for snapshot and unit tests without a running engine.
    public func setSnapshotStateForTesting(
        diagnostics: DiagnosticsExportResult,
        scrubbedSupervisorLines: [String] = []
    ) {
        self.diagnostics = diagnostics
        self.scrubbedSupervisorLines = scrubbedSupervisorLines
    }
}
