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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Foundation

/// Parsed semantic version `(major, minor, patch)` for Antigravity CLI release gates
/// (`AntigravityAcpSupport.ts:54-65`).
public struct AntigravityVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: AntigravityVersion, rhs: AntigravityVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// Pure per-release rules, mode mappings, and protocol parsers for `agy acp`,
/// ported from T3 Code's `AntigravityAcpSupport.ts`, `AntigravityAdapterV2.ts`,
/// `AntigravityProtocol.ts`, `AntigravityChildWork.ts`, and `AntigravityTurnOutcome.ts`.
public enum AntigravityACPSupport {
    /// Auth method ID used by Antigravity (`AntigravityAcpSupport.ts:132`).
    public static let authMethodID = "oauth-personal"

    /// Shown as `.connectionFailed(kind: .auth)` when `oauth-personal` fails or needs browser sign-in
    /// (`AntigravityAuth.ts:112-136` / Step 2b brief).
    public static let authSignInFailureMessage =
        "Antigravity needs authentication. Run `agy` once in Terminal to sign in, then try again."

    /// Idle session shutdown interval copied from `ProviderSessionManager.ts:61` (`DEFAULT_IDLE_TIMEOUT_MS = 30 * 60 * 1000`).
    public static let defaultIdleTimeout: TimeInterval = 30 * 60

    /// Silent-prompt watchdog interval copied from `AntigravityAdapterV2.ts:277` (`promptInactivityTimeout: "15 minutes"`).
    public static let defaultPromptInactivityTimeout: TimeInterval = 15 * 60

    /// First release offering all models to arbitrary ACP client names (`AntigravityAcpSupport.ts:89`).
    public static let openModelAccessRelease = AntigravityVersion(major: 1, minor: 5, patch: 1)

    /// Legacy model families exposed before 1.5.1 / 1.4 thinking split (`AntigravityAcpSupport.ts:217-227`).
    public static let allowlistedLegacyModels = [
        "gemini-3.8-flash-high",
        "gemini-3.8-flash-medium",
        "gemini-3.8-flash-low",
        "gpt-oss-120b-medium",
    ]

    /// Release-qualified model IDs exposed under open model access (`>= 1.5.1`).
    public static let openAccessModelFamilies = [
        "gemini-4-carbon",
        "gemini-4-argon",
        "gemini-4-hydrogen",
        "gemini-pro-orchestrator",
        "gemini-pro-orchestrator-argon",
        "gemini-3.8-flash",
        "claude-opus-5-5",
        "claude-sonnet-5-5",
        "gpt-oss-120b-medium",
    ]

    /// Title used when `invoke_subagent` has no decoded launch text (`AntigravityChildWork.ts:40`).
    public static let subagentBatchFallbackTitle = "Antigravity subagent batch"

    private static let subagentToolTitles: Set<String> = [
        "Running start_subagent",
        "Run start_subagent?",
        "Running invoke_subagent",
        "Run invoke_subagent?",
    ]

    private static let clientReadTitles: Set<String> = [
        "Running client_view_file",
        "Run client_view_file?",
    ]

    private static let questionLabelLimit = 512
    private static let toolTextLimit = 8_000

    /// Parses leading `major.minor.patch` (`AntigravityAcpSupport.ts:54-57`).
    public static func parseVersion(_ version: String?) -> AntigravityVersion? {
        guard let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        let pattern = #"^(\d+)\.(\d+)\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let r1 = Range(match.range(at: 1), in: trimmed),
              let r2 = Range(match.range(at: 2), in: trimmed),
              let r3 = Range(match.range(at: 3), in: trimmed),
              let major = Int(trimmed[r1]),
              let minor = Int(trimmed[r2]),
              let patch = Int(trimmed[r3]) else {
            return nil
        }
        return AntigravityVersion(major: major, minor: minor, patch: patch)
    }

    /// True on `1.4.2` through `1.4.5`, which write `skills/system/run-workflow/SKILL.md` unless disabled
    /// (`AntigravityAcpSupport.ts:71-78`).
    public static func writesRunWorkflowSkill(version: String?) -> Bool {
        guard let parsed = parseVersion(version) else { return false }
        let minVersion = AntigravityVersion(major: 1, minor: 4, patch: 2)
        let maxVersion = AntigravityVersion(major: 1, minor: 4, patch: 5)
        return parsed >= minVersion && parsed <= maxVersion
    }

    /// Tools disabled in session `_meta.antigravity.disabledTools` (`AntigravityAcpSupport.ts:104-106`).
    public static func disabledTools(version: String?) -> [String] {
        writesRunWorkflowSkill(version: version) ? ["run_workflow"] : []
    }

    /// Qualified Antigravity release for native range reads (`AntigravityAcpSupport.ts:84-86`).
    public static func isQualifiedRelease(version: String?) -> Bool {
        ACPClientPolicy.isQualifiedAntigravityRelease(version)
    }

    /// True on `>= 1.5.1` (`AntigravityAcpSupport.ts:89, 115-120`).
    public static func hasOpenModelAccess(version: String?) -> Bool {
        guard let parsed = parseVersion(version) else { return false }
        return parsed >= openModelAccessRelease
    }

    /// Client identity sent during `initialize` (`AntigravityAcpSupport.ts:115-120`).
    /// Releases prior to `1.5.1` expose non-Gemini models only to allowlisted client IDs such as `zed`.
    public static func clientInfo(version: String?) -> ACPImplementation {
        if hasOpenModelAccess(version: version) {
            return ACPImplementation(name: "vitruvian-code", title: "Vitruvian Code", version: "1.0.0")
        }
        return ACPImplementation(name: "zed", version: "0.0.0")
    }

    /// Whether `systemPrompt.append` is supported on session setup (`AntigravityAcpSupport.ts:95-97`).
    public static func appendsSystemPrompt(version: String?) -> Bool {
        isQualifiedRelease(version: version)
    }

    /// Overload consulting both the T3 release gate and advertised `_meta.antigravity.systemPrompt.append`.
    public static func appendsSystemPrompt(initializeResult: ACPInitializeResult) -> Bool {
        if appendsSystemPrompt(version: initializeResult.agentInfo?.version) {
            return true
        }
        return initializeResult.agentCapabilities?
            ._meta?["antigravity"]?
            .objectValue?["systemPrompt"]?
            .objectValue?["append"]?
            .boolValue == true
    }

    /// Whether `usage` / Gemini `usageMetadata` delta is reported per turn (`AntigravityAdapterV2.ts:279`).
    public static func reportsPerTurnPromptUsage(version: String?) -> Bool {
        guard let parsed = parseVersion(version) else { return false }
        return parsed >= AntigravityVersion(major: 1, minor: 4, patch: 5)
    }

    /// Whether `ReadRepair` is active to complete hung `client_view_file` tool calls when
    /// client file reads are served (`AntigravityAcpSupport.ts:142-145`, `AntigravityAdapterV2.ts:154`).
    public static func needsReadRepair(version: String?) -> Bool {
        !isQualifiedRelease(version: version)
    }

    /// Converts per-turn `ACPUsage` into `VitruvianCodeContextUsage` on releases that report per-turn
    /// prompt usage (`>= 1.4.5`, `AntigravityAdapterV2.ts:279-280`).
    /// For Gemini (`geminiPromptUsage: true`), `inputTokens` includes `cachedReadTokens` unless
    /// `totalTokens` equals `inputTokens + cachedTokens + outputTokens`.
    public static func promptContextUsage(
        version: String?,
        usage: ACPUsage?,
        contextWindow: Int = 0
    ) -> VitruvianCodeContextUsage? {
        guard reportsPerTurnPromptUsage(version: version), let usage else {
            return nil
        }
        let rawInput = max(0, usage.inputTokens ?? 0)
        let cachedRead = max(0, usage.cachedReadTokens ?? 0)
        let cachedWrite = max(0, usage.cachedWriteTokens ?? 0)
        let cached = cachedRead + cachedWrite
        let output = max(0, usage.outputTokens ?? 0)
        let uncachedInput: Int
        if let total = usage.totalTokens, cached > 0, total == rawInput + cached + output {
            uncachedInput = rawInput
        } else {
            uncachedInput = max(0, rawInput - cachedRead)
        }
        guard uncachedInput + cached + output > 0 else {
            return nil
        }
        return VitruvianCodeContextUsage(
            inputTokens: uncachedInput,
            cachedTokens: cached,
            outputTokens: output,
            contextWindow: max(0, contextWindow)
        )
    }

    /// Listed model IDs from version rules alone, or intersected/extracted from advertised `configOptions`
    /// (`AntigravityAcpSupport.ts:89, 200-206`).
    public static func supportedModels(
        version: String?,
        configOptions: [ACPSessionConfigOption]? = nil
    ) -> [String] {
        if let configOptions,
           let modelOption = configOptions.first(where: { $0.id == "model" && $0.type == "select" }) {
            let advertised = modelOption.flattenedSelectOptions.map(\.value)
            if !advertised.isEmpty {
                return advertised
            }
        }
        return hasOpenModelAccess(version: version) ? openAccessModelFamilies : allowlistedLegacyModels
    }

    /// Path to agy's session attachments directory inside app state (`AntigravityAdapterV2.ts:149`).
    public static func attachmentsDirectory(stateDirectory: String) -> String {
        (stateDirectory as NSString).appendingPathComponent("attachments")
    }

    /// `additionalDirectories` passed to `session/new|resume|load` when attachments directory is configured
    /// (`AntigravityAdapterV2.ts:149`).
    public static func additionalDirectories(attachmentsDirectory: String?) -> [String] {
        guard let trimmed = attachmentsDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return []
        }
        return [trimmed]
    }

    /// Builds `_meta` sent on `session/new`, `session/resume`, and `session/load`
    /// (`AntigravityAcpSupport.ts:99-112`).
    public static func sessionMeta(
        version: String?,
        capabilitiesMeta: [String: ACPJSONValue]? = nil,
        systemPromptAppend: String? = nil
    ) -> [String: ACPJSONValue]? {
        var antigravityMeta: [String: ACPJSONValue] = [:]
        let disabled = disabledTools(version: version)
        if !disabled.isEmpty {
            antigravityMeta["disabledTools"] = .array(disabled.map { .string($0) })
        }
        let supportsAppend = appendsSystemPrompt(version: version)
            || (capabilitiesMeta?["antigravity"]?.objectValue?["systemPrompt"]?.objectValue?["append"]?.boolValue == true)
        if supportsAppend,
           let append = systemPromptAppend?.trimmingCharacters(in: .whitespacesAndNewlines),
           !append.isEmpty {
            antigravityMeta["systemPrompt"] = .object(["append": .string(append)])
        }
        guard !antigravityMeta.isEmpty else { return nil }
        return ["antigravity": .object(antigravityMeta)]
    }

    /// Converts internal approval mode + plan switch to the mode ID sent to `agy acp`.
    /// Never emits `yolo` or `auto_edit` (`AntigravityAcpSupport.ts:165-184`, `AntigravityDriver.ts:286-288`).
    public static func cliSessionMode(
        for approvalMode: VitruvianCodeApprovalMode,
        planSwitch: Bool
    ) -> String {
        if planSwitch || approvalMode == .plan {
            return "plan"
        }
        return "default"
    }

    /// Maps `AntigravityAcpSupport.ts:165-175` + `182-184` directly on raw ACP mode strings too.
    public static func sanitizedCliSessionMode(_ modeID: String) -> String {
        (modeID == "yolo" || modeID == "auto_edit") ? "default" : modeID
    }

    /// Process arguments passed to `agy` (`AntigravityProvider` ACP launch). Never passes `--dangerously-skip-permissions`.
    public static func launchArguments() -> [String] {
        ["acp"]
    }

    // MARK: - Questions inside `session/request_permission` (`AntigravityProtocol.ts:49-144`)

    /// Native questions arrive via `session/request_permission` with `toolCallId` starting with `"interaction_"`
    /// (`AntigravityProtocol.ts:49-53`).
    public static func isUserInputRequest(_ request: ACPRequestPermissionParams) -> Bool {
        request.toolCall.toolCallId.hasPrefix("interaction_")
    }

    /// Extracts an `AgentQuestion` from an `interaction_*` `session/request_permission`, returning `nil` for
    /// normal approval requests or malformed option lists (`AntigravityProtocol.ts:115-144`).
    public static func extractQuestion(
        from request: ACPRequestPermissionParams,
        requestID: String
    ) -> AgentQuestion? {
        guard isUserInputRequest(request), !request.options.isEmpty else {
            return nil
        }
        var seenIDs = Set<String>()
        var mappedOptions: [AgentQuestion.Option] = []
        for option in request.options {
            let trimmedID = option.optionId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty, seenIDs.insert(trimmedID).inserted else {
                return nil
            }
            let rawLabel = option.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let labelText = rawLabel.isEmpty ? option.optionId : rawLabel
            let bounded = boundText(labelText, limit: questionLabelLimit)
            mappedOptions.append(
                AgentQuestion.Option(value: option.optionId, label: bounded, description: bounded)
            )
        }
        let rawTitle = request.toolCall.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let questionText = boundText(rawTitle.isEmpty ? "Choose an option." : rawTitle, limit: toolTextLimit)
        let field = AgentQuestion.Field(
            id: request.toolCall.toolCallId,
            type: .choice,
            label: questionText,
            description: "Question",
            required: true,
            options: mappedOptions
        )
        return AgentQuestion(
            requestID: requestID,
            title: "Question",
            message: questionText,
            url: nil,
            fields: [field]
        )
    }

    // MARK: - Child-work reports -> Subagents (`AntigravityProtocol.ts:483-504`, `AntigravityChildWork.ts:40-75`)

    public struct ChildLaunch: Equatable, Sendable {
        public let role: String
        public let prompt: String
    }

    /// Extracts `Subagents: [{Role, Prompt}]` (`AntigravityChildWork.ts:54-62`).
    public static func subagentLaunches(from rawInput: ACPJSONValue?) -> [ChildLaunch]? {
        guard let obj = rawInput?.objectValue,
              let entries = obj["Subagents"]?.arrayValue,
              !entries.isEmpty else {
            return nil
        }
        var parsed: [ChildLaunch] = []
        for entry in entries {
            guard let item = entry.objectValue,
                  let role = item["Role"]?.stringValue,
                  let prompt = item["Prompt"]?.stringValue else {
                return nil
            }
            parsed.append(ChildLaunch(role: role, prompt: prompt))
        }
        return parsed.isEmpty ? nil : parsed
    }

    /// Summarizes one or more subagent launches into `(title, prompt)` (`AntigravityChildWork.ts:65-75`).
    public static func describeSubagentLaunches(
        _ launches: [ChildLaunch]
    ) -> (title: String, prompt: String)? {
        guard !launches.isEmpty else { return nil }
        if launches.count == 1, let only = launches.first {
            return (only.role, only.prompt)
        }
        return (
            launches.map(\.role).joined(separator: ", "),
            launches.map { "\($0.role)\n\($0.prompt)" }.joined(separator: "\n\n")
        )
    }

    /// Classifies an Antigravity tool call as `"subagent"` vs `"mcp"` vs `nil`
    /// (`AntigravityProtocol.ts:483-504`, `AntigravityAdapterV2.ts:100-124`).
    public static func extractSubagentEvent(
        from notification: ACPSessionNotification
    ) -> AgentEvent? {
        let call: ACPToolCall
        switch notification.update {
        case .toolCall(let value):
            call = value
        case .toolCallUpdate(let value):
            call = value
        default:
            return nil
        }
        guard call.kind == nil || call.kind == "other" else {
            return nil
        }
        let isMcpCall = call._meta?["is_mcp_tool_call"]?.boolValue == true
        guard !isMcpCall else { return nil }

        let launches = subagentLaunches(from: call.rawInput)
        let title = call.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matchesTitle = subagentToolTitles.contains(title) || title == subagentBatchFallbackTitle
        guard matchesTitle || launches != nil else {
            return nil
        }

        let described = launches.flatMap(describeSubagentLaunches)
        let role = described?.title ?? subagentBatchFallbackTitle
        let rawOutputText = call.rawOutput?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = described?.prompt
            ?? ((rawOutputText?.isEmpty == false) ? rawOutputText! : (title.isEmpty ? subagentBatchFallbackTitle : title))
        let isTerminal = (call.status == "completed" || call.status == "failed")
        let subagent = VitruvianCodeActiveSubagent(
            id: call.toolCallId,
            typeName: "subagent",
            role: role,
            prompt: prompt,
            model: "",
            isRunning: !isTerminal
        )
        return .subagent(subagent, started: !isTerminal)
    }

    private static func boundText(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let cutoff = max(0, limit - 3)
        return String(text.prefix(cutoff)) + "..."
    }

    static func clientReadPath(from update: ACPToolCall) -> String? {
        guard let title = update.title, clientReadTitles.contains(title) else {
            return nil
        }
        if let path = update.locations?.first?.path, !path.isEmpty {
            return path
        }
        if let rawPath = update.rawInput?.objectValue?["absolute_path"]?.stringValue,
           !rawPath.isEmpty {
            return rawPath
        }
        return nil
    }
}

/// Repairs hung subagent `client_view_file` tool calls when client reads were already served
/// (`AntigravityProtocol.ts:253-311`).
@MainActor
public final class AntigravityReadRepair {
    private enum Outcome {
        case served
        case refused
    }

    private struct TrackedRead {
        let path: String
        let sessionID: String
        var outcome: Outcome?
    }

    private var openOrder: [String] = []
    private var openReads: [String: TrackedRead] = [:]
    private var earlyOutcomes: [(path: String, outcome: Outcome)] = []

    public init() {}

    public func reset() {
        openOrder.removeAll()
        openReads.removeAll()
        earlyOutcomes.removeAll()
    }

    /// Matches a served or refused `fs/read_text_file` against the oldest open `client_view_file` of `path`.
    public func attempted(path: String, served: Bool) -> [ACPSessionNotification] {
        let outcome: Outcome = served ? .served : .refused
        for toolCallID in openOrder {
            guard var entry = openReads[toolCallID],
                  entry.path == path,
                  entry.outcome == nil else {
                continue
            }
            entry.outcome = outcome
            openReads[toolCallID] = entry
            guard served else { return [] }
            let update = ACPToolCall(toolCallId: toolCallID, status: "completed")
            return [ACPSessionNotification(sessionId: entry.sessionID, update: .toolCallUpdate(update))]
        }
        earlyOutcomes.append((path: path, outcome: outcome))
        return []
    }

    /// Repairs an incoming `tool_call` or `tool_call_update` notification when its read was served.
    public func repair(_ notification: ACPSessionNotification) -> ACPSessionNotification {
        let incomingCall: ACPToolCall
        let isInitialCall: Bool
        switch notification.update {
        case .toolCall(let call):
            incomingCall = call
            isInitialCall = true
        case .toolCallUpdate(let update):
            incomingCall = update
            isInitialCall = false
        default:
            return notification
        }

        if let path = AntigravityACPSupport.clientReadPath(from: incomingCall),
           openReads[incomingCall.toolCallId] == nil {
            var earlyOutcome: Outcome?
            if let earlyIndex = earlyOutcomes.firstIndex(where: { $0.path == path }) {
                earlyOutcome = earlyOutcomes.remove(at: earlyIndex).outcome
            }
            openOrder.append(incomingCall.toolCallId)
            openReads[incomingCall.toolCallId] = TrackedRead(
                path: path,
                sessionID: notification.sessionId,
                outcome: earlyOutcome
            )
        }

        guard let read = openReads[incomingCall.toolCallId] else {
            return notification
        }
        if incomingCall.status == "pending" || incomingCall.status == "in_progress" {
            guard read.outcome == .served else { return notification }
            var patched = incomingCall
            patched.status = "completed"
            return ACPSessionNotification(
                sessionId: notification.sessionId,
                update: isInitialCall ? .toolCall(patched) : .toolCallUpdate(patched),
                _meta: notification._meta
            )
        }

        guard incomingCall.status == "completed" || incomingCall.status == "failed" else {
            return notification
        }
        openReads.removeValue(forKey: incomingCall.toolCallId)
        openOrder.removeAll { $0 == incomingCall.toolCallId }
        if incomingCall.status == "completed" || read.outcome != .served {
            return notification
        }
        var patched = incomingCall
        patched.status = "completed"
        patched.rawOutput = nil
        return ACPSessionNotification(
            sessionId: notification.sessionId,
            update: isInitialCall ? .toolCall(patched) : .toolCallUpdate(patched),
            _meta: notification._meta
        )
    }
}

/// Reads agy's SQLite session database (`steps` table) read-only to detect turns that ended in an
/// upstream API or quota error (`AntigravityTurnOutcome.ts:1-216` & `AntigravityProfilePaths.ts:11-37`).
/// Emits no chat events of its own; only returns the error summary when `step_type == 17` or `stopReason == "refusal"`.
public enum AntigravityTurnOutcome {
    /// `CORTEX_STEP_TYPE_ERROR_MESSAGE` (`AntigravityTurnOutcome.ts:17`).
    public static let errorStepType = 17
    /// Maximum leading bytes decoded per step payload (`AntigravityTurnOutcome.ts:19`).
    public static let maxErrorPayloadBytes = 16_384
    /// Default quota message (`AntigravityTurnOutcome.ts:121`).
    public static let quotaExhaustedMessage = "You have reached your Antigravity quota for this period."
    /// Default error fallback (`AntigravityTurnOutcome.ts:130`).
    public static let genericErrorMessage = "Antigravity stopped this turn because of an error."

    public struct StepRecord: Equatable, Sendable {
        public let stepType: Int
        public let payloadText: String

        public init(stepType: Int, payloadText: String) {
            self.stepType = stepType
            self.payloadText = payloadText
        }
    }

    public struct Snapshot: Sendable {
        public let sessionID: String
        public let geminiHome: String
        public let startIndexByDatabase: [String: Int]
        public let sqliteExecutable: String
    }

    /// Evaluates turn failure purely from `stopReason` and the last step of the current turn
    /// (`AntigravityTurnOutcome.ts:105-142`).
    public static func turnFailureMessage(stopReason: String, lastStep: StepRecord?) -> String? {
        let errorText: String? = lastStep?.stepType == errorStepType ? lastStep?.payloadText : nil
        if errorText == nil && stopReason != "refusal" {
            return nil
        }
        let text = errorText ?? ""
        if stopReason == "refusal" || matchesQuotaExhausted(text) {
            return quotaExhaustedMessage
        }
        if let extracted = extractAPIErrorMessage(text) {
            return extracted
        }
        return genericErrorMessage
    }

    /// Captures per-turn baseline step indices before sending `session/prompt`
    /// (`AntigravityTurnOutcome.ts:152-193`).
    public static func snapshot(
        geminiHome: String,
        sessionID: String,
        sqliteExecutable: String = "/usr/bin/sqlite3"
    ) async -> Snapshot {
        guard isValidNativeSessionID(sessionID) else {
            return Snapshot(sessionID: sessionID, geminiHome: geminiHome, startIndexByDatabase: [:], sqliteExecutable: sqliteExecutable)
        }
        return await Task.detached(priority: .utility) {
            var baseline: [String: Int] = [:]
            for subdir in ["antigravity-acp", "antigravity-cli"] {
                guard let dirPath = managedPath(root: geminiHome, segments: [subdir, "conversations"], expectFile: false) else {
                    continue
                }
                let dbName = "\(sessionID).db"
                let fullDBPath = (dirPath as NSString).appendingPathComponent(dbName)
                if let dbPath = managedPath(root: geminiHome, segments: [subdir, "conversations", dbName], expectFile: true) {
                    if let maxIdx = queryMaxStepIndex(dbPath: dbPath, sqliteExecutable: sqliteExecutable) {
                        baseline[dbPath] = maxIdx
                    }
                } else {
                    // Only allow creating this DB during the turn if no symlink or foreign entry already sits there.
                    let isForeignOrLink = (try? FileManager.default.attributesOfItem(atPath: fullDBPath)) != nil
                    if !isForeignOrLink {
                        baseline[fullDBPath] = -1
                    }
                }
            }
            return Snapshot(
                sessionID: sessionID,
                geminiHome: geminiHome,
                startIndexByDatabase: baseline,
                sqliteExecutable: sqliteExecutable
            )
        }.value
    }

    /// Checks whether steps added during the turn end in `ERROR_STEP_TYPE` (`AntigravityTurnOutcome.ts:194-216`).
    public static func checkOutcome(
        snapshot: Snapshot,
        stopReason: String
    ) async -> String? {
        guard isValidNativeSessionID(snapshot.sessionID) else {
            return turnFailureMessage(stopReason: stopReason, lastStep: nil)
        }
        return await Task.detached(priority: .utility) {
            var observedStep: StepRecord?
            for subdir in ["antigravity-acp", "antigravity-cli"] {
                guard let dbPath = managedPath(
                    root: snapshot.geminiHome,
                    segments: [subdir, "conversations", "\(snapshot.sessionID).db"],
                    expectFile: true
                ),
                let startIndex = snapshot.startIndexByDatabase[dbPath] else {
                    continue
                }
                if let step = queryLastStepAfter(
                    dbPath: dbPath,
                    startIndex: startIndex,
                    sqliteExecutable: snapshot.sqliteExecutable
                ) {
                    observedStep = step
                    break
                }
            }
            return turnFailureMessage(stopReason: stopReason, lastStep: observedStep)
        }.value
    }

    /// `NATIVE_SESSION_ID = /^[\w-]+$/` (`AntigravityTurnOutcome.ts:38`).
    public static func isValidNativeSessionID(_ sessionID: String) -> Bool {
        guard !sessionID.isEmpty else { return false }
        return sessionID.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
    }

    private static func matchesQuotaExhausted(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\breason:QUOTA_EXHAUSTED\b"#) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func extractAPIErrorMessage(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"Error (\d{3}), Message: (.+?), Status: ([A-Z_]+)"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let msgRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let message = String(text[msgRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    /// Proves every segment under canonical `root` is a genuine directory/file and none is a symlink
    /// (`AntigravityProfilePaths.ts:11-37`).
    private static func managedPath(root: String, segments: [String], expectFile: Bool) -> String? {
        let canonicalRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalRoot, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        var current = canonicalRoot
        for (index, segment) in segments.enumerated() {
            guard !segment.isEmpty, segment != ".", segment != "..", !segment.contains("/") else {
                return nil
            }
            current = (current as NSString).appendingPathComponent(segment)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: current),
                  let fileType = attrs[.type] as? FileAttributeType,
                  fileType != .typeSymbolicLink else {
                return nil
            }
            let wantsFile = expectFile && index == segments.count - 1
            if wantsFile {
                guard fileType == .typeRegular else { return nil }
            } else {
                guard fileType == .typeDirectory else { return nil }
            }
        }
        let resolved = URL(fileURLWithPath: current).resolvingSymlinksInPath().path
        return resolved == current ? current : nil
    }

    private static func queryMaxStepIndex(dbPath: String, sqliteExecutable: String) -> Int? {
        guard let rows = runSqliteJSON(
            dbPath: dbPath,
            sqliteExecutable: sqliteExecutable,
            sql: """
            SELECT COALESCE((SELECT max(idx) FROM steps WHERE EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'steps')), -1) AS idx;
            """
        ),
        let row = rows.last,
        let num = row["idx"] as? NSNumber else {
            return nil
        }
        return num.intValue
    }

    private static func queryLastStepAfter(
        dbPath: String,
        startIndex: Int,
        sqliteExecutable: String
    ) -> StepRecord? {
        guard let rows = runSqliteJSON(
            dbPath: dbPath,
            sqliteExecutable: sqliteExecutable,
            sql: """
            SELECT step_type AS stepType, hex(substr(step_payload, 1, \(maxErrorPayloadBytes))) AS hexPayload
            FROM steps WHERE idx > \(startIndex) ORDER BY idx DESC LIMIT 1;
            """
        ),
        let row = rows.last,
        let stepType = (row["stepType"] as? NSNumber)?.intValue else {
            return nil
        }
        let hexPayload = (row["hexPayload"] as? String) ?? ""
        let payloadData = decodeHex(hexPayload)
        let payloadText = String(decoding: payloadData, as: UTF8.self)
        return StepRecord(stepType: stepType, payloadText: payloadText)
    }

    private static func runSqliteJSON(
        dbPath: String,
        sqliteExecutable: String,
        sql: String
    ) -> [[String: Any]]? {
        guard FileManager.default.isExecutableFile(atPath: sqliteExecutable) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqliteExecutable)
        process.arguments = ["-readonly", "-cmd", ".timeout 100", "-json", dbPath, sql]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return json
    }

    private static func decodeHex(_ hex: String) -> Data {
        guard !hex.isEmpty else { return Data() }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            guard let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) else { break }
            if let byte = UInt8(hex[index..<next], radix: 16) {
                bytes.append(byte)
            }
            index = next
        }
        return Data(bytes)
    }
}

@MainActor
private final class AntigravityVersionBox {
    var version: String?

    init(_ version: String?) {
        self.version = version
    }
}

/// Long-lived per-chat ACP connection for Antigravity (`agy acp`), configuring `ACPConnection`
/// with T3 Code's release gates, permission policies, `oauth-personal` sign-in, session-log outcome
/// checks, child-work subagent emission, and silent-prompt watchdog.
@MainActor
public final class AntigravityACPConnection: PersistentAgentConnection {
    public var capabilities: AgentCapabilities { inner.capabilities }
    public var events: AsyncStream<AgentEvent> { inner.events }
    public var agentVersion: String? { inner.agentVersion }
    public var initializeResult: ACPInitializeResult? { inner.initializeResult }
    public var isConnected: Bool { inner.isConnected }
    public var launchSpecUsed: AgentProcessLaunchSpec { launchSpec }

    private let inner: ACPConnection
    private let launchSpec: AgentProcessLaunchSpec
    private let modeProvider: ACPConnection.ModeProvider
    private let readRepair = AntigravityReadRepair()
    private var isStarting = false

    public convenience init(
        spec: AgentConnectionSpec,
        environment: VitruvianCodeEngine.Environment,
        geminiHomeDirectory: String? = nil,
        runtimeVersion: String? = nil,
        versionProbe: (@Sendable () async -> String?)? = nil,
        promptInactivityTimeout: TimeInterval = AntigravityACPSupport.defaultPromptInactivityTimeout,
        cancelGraceTimeout: TimeInterval = ACPConnection.defaultCancelGraceTimeout,
        sessionSetupTimeout: TimeInterval = ACPTransport.defaultSessionSetupTimeout,
        processFactory: @escaping ACPConnection.ProcessFactory = ACPLaunchedProcess.live
    ) {
        let binary = (spec.agentPath?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? spec.provider.executableName
        let resolvedBinary = VitruvianCodeSupport.locateAgent(
            named: binary,
            environment: spec.environment,
            home: environment.home,
            isExecutable: environment.isExecutable
        ) ?? binary
        let childEnv = VitruvianCodeSupport.childEnvironment(base: spec.environment, home: environment.home)
        let attachmentsDir = AntigravityACPSupport.attachmentsDirectory(stateDirectory: environment.stateDirectory)
        let geminiHome = geminiHomeDirectory ?? (environment.home as NSString).appendingPathComponent(".gemini")
        let fallbackMode = spec.configuration.approvalMode
        let fallbackPlan = spec.turnModes.plan
        let liveModeProvider = spec.liveModeProvider ?? { (fallbackMode, fallbackPlan) }
        let effectiveProbe: @Sendable () async -> String? = versionProbe ?? { [runProgram = environment.runProgram] in
            await runProgram(resolvedBinary, ["--version"])
        }

        self.init(
            launchSpec: AgentProcessLaunchSpec(
                executable: resolvedBinary,
                arguments: AntigravityACPSupport.launchArguments(),
                environment: childEnv,
                workingDirectory: spec.workingDirectory
            ),
            modeProvider: liveModeProvider,
            stateDirectory: environment.stateDirectory,
            stateDirectoryOverride: environment.stateDirectoryOverride,
            attachmentsDirectory: attachmentsDir,
            geminiHomeDirectory: geminiHome,
            runtimeVersion: runtimeVersion,
            versionProbe: effectiveProbe,
            promptInactivityTimeout: promptInactivityTimeout,
            cancelGraceTimeout: cancelGraceTimeout,
            sessionSetupTimeout: sessionSetupTimeout,
            processFactory: processFactory
        )
    }

    public init(
        launchSpec: AgentProcessLaunchSpec,
        modeProvider: @escaping ACPConnection.ModeProvider,
        stateDirectory: String? = nil,
        stateDirectoryOverride: String? = nil,
        attachmentsDirectory: String? = nil,
        geminiHomeDirectory: String? = nil,
        runtimeVersion: String? = nil,
        versionProbe: (@Sendable () async -> String?)? = nil,
        promptInactivityTimeout: TimeInterval = AntigravityACPSupport.defaultPromptInactivityTimeout,
        cancelGraceTimeout: TimeInterval = ACPConnection.defaultCancelGraceTimeout,
        sessionSetupTimeout: TimeInterval = ACPTransport.defaultSessionSetupTimeout,
        terminationGrace: TimeInterval = AgentProcess.defaultTerminationGrace,
        processFactory: @escaping ACPConnection.ProcessFactory = ACPLaunchedProcess.live
    ) {
        // Ensure CLI arguments never pass `--dangerously-skip-permissions`, `yolo`, or `auto_edit`.
        var safeSpec = launchSpec
        safeSpec.arguments = AntigravityACPSupport.launchArguments()
        self.launchSpec = safeSpec
        self.modeProvider = modeProvider

        let readRepair = self.readRepair
        let versionBox = AntigravityVersionBox(runtimeVersion)
        let additionalDirs = AntigravityACPSupport.additionalDirectories(attachmentsDirectory: attachmentsDirectory)
        let stateURL = stateDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }

        let prepareInitialize: (@MainActor @Sendable () async -> (clientInfo: ACPImplementation, policy: ACPClientPolicy)?)?
        if let versionProbe {
            prepareInitialize = {
                if versionBox.version == nil,
                   let probed = await versionProbe()?.trimmingCharacters(in: .whitespacesAndNewlines),
                   AntigravityACPSupport.parseVersion(probed) != nil {
                    versionBox.version = probed
                }
                let knownVersion = versionBox.version
                return (
                    clientInfo: AntigravityACPSupport.clientInfo(version: knownVersion),
                    policy: ACPClientPolicy.antigravity(version: knownVersion)
                )
            }
        } else {
            prepareInitialize = nil
        }

        let onInitialized: @MainActor @Sendable (ACPInitializeResult) -> ACPClientPolicy? = { initResult in
            if let reported = initResult.agentInfo?.version {
                versionBox.version = reported
            }
            return ACPClientPolicy.antigravity(version: versionBox.version)
        }
        let sessionMetaProvider: @MainActor @Sendable (ACPInitializeResult, String?) -> [String: ACPJSONValue]? = { initResult, systemPrompt in
            AntigravityACPSupport.sessionMeta(
                version: initResult.agentInfo?.version ?? versionBox.version,
                capabilitiesMeta: initResult.agentCapabilities?._meta,
                systemPromptAppend: systemPrompt
            )
        }
        let permissionInterceptor: @MainActor @Sendable (ACPRequestPermissionParams, String) -> AgentQuestion? = { params, interactionID in
            AntigravityACPSupport.extractQuestion(from: params, requestID: interactionID)
        }
        let onClientFileRead: @MainActor @Sendable (String, Bool) -> [ACPSessionNotification] = { path, served in
            guard AntigravityACPSupport.needsReadRepair(version: versionBox.version) else {
                return []
            }
            return readRepair.attempted(path: path, served: served)
        }
        let transformSessionUpdate: @MainActor @Sendable (ACPSessionNotification) -> (notification: ACPSessionNotification?, extraEvents: [AgentEvent]) = { notification in
            let repaired = AntigravityACPSupport.needsReadRepair(version: versionBox.version)
                ? readRepair.repair(notification)
                : notification
            var extraEvents: [AgentEvent] = []
            if let subagentEvent = AntigravityACPSupport.extractSubagentEvent(from: repaired) {
                extraEvents.append(subagentEvent)
            }
            return (notification: repaired, extraEvents: extraEvents)
        }
        let onPromptStarted: @MainActor @Sendable () -> Void = {
            readRepair.reset()
        }
        let promptContextUsageProvider: @MainActor @Sendable (ACPInitializeResult?, ACPUsage?, Int) -> VitruvianCodeContextUsage? = { initResult, usage, contextWindow in
            let effectiveVersion = initResult?.agentInfo?.version ?? versionBox.version
            return AntigravityACPSupport.promptContextUsage(
                version: effectiveVersion,
                usage: usage,
                contextWindow: contextWindow
            )
        }
        let promptOutcomeWatcher: (@Sendable (_ sessionID: String) async -> (@Sendable (_ stopReason: String) async -> String?)?)?
        if let geminiHome = geminiHomeDirectory {
            promptOutcomeWatcher = { (sessionID: String) async -> (@Sendable (_ stopReason: String) async -> String?)? in
                let baseline = await AntigravityTurnOutcome.snapshot(
                    geminiHome: geminiHome,
                    sessionID: sessionID
                )
                let outcomeChecker: @Sendable (_ stopReason: String) async -> String? = { (stopReason: String) async -> String? in
                    await AntigravityTurnOutcome.checkOutcome(
                        snapshot: baseline,
                        stopReason: stopReason
                    )
                }
                return outcomeChecker
            }
        } else {
            promptOutcomeWatcher = nil
        }

        let hooks = ACPConnection.Hooks(
            prepareInitialize: prepareInitialize,
            onInitialized: onInitialized,
            authMethodID: AntigravityACPSupport.authMethodID,
            authFailureMessage: AntigravityACPSupport.authSignInFailureMessage,
            additionalDirectories: additionalDirs,
            sessionMetaProvider: sessionMetaProvider,
            permissionInterceptor: permissionInterceptor,
            onClientFileRead: onClientFileRead,
            transformSessionUpdate: transformSessionUpdate,
            onPromptStarted: onPromptStarted,
            finishSubagentsOnTurnEnd: true,
            promptOutcomeWatcher: promptOutcomeWatcher,
            promptContextUsageProvider: promptContextUsageProvider,
            promptInactivityTimeout: promptInactivityTimeout,
            cancelGraceTimeout: cancelGraceTimeout
        )

        self.inner = ACPConnection(
            launchSpec: safeSpec,
            policy: .antigravity(version: runtimeVersion),
            modeProvider: modeProvider,
            hooks: hooks,
            stateFolderURL: stateURL,
            stateDirectoryOverride: stateDirectoryOverride,
            sessionSetupTimeout: sessionSetupTimeout,
            terminationGrace: terminationGrace,
            clientInfo: AntigravityACPSupport.clientInfo(version: runtimeVersion),
            processFactory: processFactory
        )
    }

    public func start(_ request: AgentSessionRequest) async throws -> String {
        guard inner.isConnected else {
            throw ACPConnectionError.alreadyStopped
        }
        isStarting = true
        defer { isStarting = false }
        let sessionID = try await inner.start(request)
        guard inner.isConnected else {
            throw ACPConnectionError.alreadyStopped
        }
        let current = modeProvider()
        try await applySessionMode(approvalMode: current.mode, planSwitch: current.planSwitch)
        return sessionID
    }

    public func syncMode(approvalMode: VitruvianCodeApprovalMode, planSwitch: Bool) async throws {
        try await applySessionMode(approvalMode: approvalMode, planSwitch: planSwitch)
    }

    public func syncPlanMode(_ planSwitch: Bool) async throws {
        let current = modeProvider()
        try await syncMode(approvalMode: current.mode, planSwitch: planSwitch)
    }

    public func prompt(_ blocks: [PromptBlock]) async throws -> AgentStopReason {
        try await inner.prompt(blocks)
    }

    public func cancel() async {
        if isStarting {
            await inner.stop()
            return
        }
        await inner.cancel()
    }

    public func answer(_ requestID: String, _ choice: AgentAnswer) async throws {
        try await inner.answer(requestID, choice)
    }

    public func setConfigOption(_ id: String, _ value: AgentConfigValue) async throws -> [AgentConfigOption] {
        if id == "mode" || id == ACPSessionConfigState.sessionModeOptionID,
           case .string(let rawMode) = value {
            let safeMode = AntigravityACPSupport.sanitizedCliSessionMode(rawMode)
            return try await inner.setConfigOption(id, .string(safeMode))
        }
        return try await inner.setConfigOption(id, value)
    }

    public func stop() async {
        await inner.stop()
    }

    private func applySessionMode(
        approvalMode: VitruvianCodeApprovalMode,
        planSwitch: Bool
    ) async throws {
        let targetMode = AntigravityACPSupport.cliSessionMode(for: approvalMode, planSwitch: planSwitch)
        try await inner.setSessionMode(targetMode)
    }
}

extension AntigravityACPConnection: AgentSessionListing {
    /// agy's own past sessions over `session/list` (`AgentSessionHistory`). agy
    /// 1.5.16 advertises it and needs `oauth-personal` sign-in first, which the
    /// inner connection does when agy asks.
    public func listSessionPage(cwd: String?, cursor: String?) async throws -> AgentSessionPage {
        try await inner.listSessionPage(cwd: cwd, cursor: cursor)
    }
}
