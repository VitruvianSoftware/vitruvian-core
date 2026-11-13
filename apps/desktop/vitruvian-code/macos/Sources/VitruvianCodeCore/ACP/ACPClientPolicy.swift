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

/// Per-agent ACP client capabilities and permission decision table.
public struct ACPClientPolicy: Equatable, Sendable {
    /// Matches T3 Code's `isQualifiedAntigravityRelease` constant (`AntigravityAcpSupport.ts:84-86`).
    public static let qualifiedAntigravityReleaseVersion = "1.4.5"

    /// T3 runtime mode mapped from `VitruvianCodeApprovalMode` (`vitruvian-code-acp.md`, Interfaces).
    public enum RuntimeMode: String, Equatable, Sendable {
        case fullAccess = "full-access"
        case autoAcceptEdits = "auto-accept-edits"
        case approvalRequired = "approval-required"
    }

    /// Optional sandbox policy passed to `clientPolicy.ts` (`AcpRuntimePolicy.sandboxPolicy`,
    /// `clientPolicy.ts:11, 87-98, 155-186`). `agy` runs with `nil` (`undefined`), as in T3 Code.
    public enum Sandbox: Equatable, Sendable {
        case readOnly
        case workspaceWrite(writableRoots: [String] = [])
        case dangerFullAccess
        case externalSandbox
        case unknown(String)
    }

    /// Optional approval policy override (`AcpRuntimePolicy.approvalPolicy`, `clientPolicy.ts:10, 76-80`).
    public enum ApprovalPolicy: String, Equatable, Sendable {
        case never
        case onRequest = "on-request"
        case untrusted
    }

    /// Result of evaluating an incoming `session/request_permission` against the current mode (`clientPolicy.ts:14`).
    public enum Decision: Equatable, Sendable {
        case allow(AgentPermissionOption.Kind)
        case ask
        case deny
    }

    public var readTextFile: Bool
    public var writeTextFile: Bool
    public var terminal: Bool
    public var elicitation: Bool
    public var sandbox: Sandbox?
    public var approvalPolicy: ApprovalPolicy?

    public init(
        readTextFile: Bool = false,
        writeTextFile: Bool = false,
        terminal: Bool = false,
        elicitation: Bool = false,
        sandbox: Sandbox? = nil,
        approvalPolicy: ApprovalPolicy? = nil
    ) {
        self.readTextFile = readTextFile
        self.writeTextFile = writeTextFile
        self.terminal = terminal
        self.elicitation = elicitation
        self.sandbox = sandbox
        self.approvalPolicy = approvalPolicy
    }

    /// All client features disabled and no sandbox (`AcpSessionRuntime.ts:1790-1804`).
    public static let none = ACPClientPolicy()

    /// Antigravity preset ported from `AntigravityAcpSupport.ts:84-86, 139-148` and `AcpSessionRuntime.ts:1800-1802`:
    /// - writes and terminals are never advertised;
    /// - text file reads are advertised only when the runtime version is not the qualified `1.4.5` release;
    /// - elicitation is off (Antigravity delivers questions inside `session/request_permission`);
    /// - `sandbox` is `nil` (T3 passes no `sandboxPolicy` for `agy`).
    public static func antigravity(version: String?) -> ACPClientPolicy {
        ACPClientPolicy(
            readTextFile: !isQualifiedAntigravityRelease(version),
            writeTextFile: false,
            terminal: false,
            elicitation: false,
            sandbox: nil,
            approvalPolicy: nil
        )
    }

    /// Exact port of `isQualifiedAntigravityRelease` (`AntigravityAcpSupport.ts:84-86`).
    public static func isQualifiedAntigravityRelease(_ version: String?) -> Bool {
        version?.trimmingCharacters(in: .whitespacesAndNewlines) == qualifiedAntigravityReleaseVersion
    }

    /// Builds the `initialize` `clientCapabilities` object advertising only allowed features.
    public var clientCapabilities: ACPClientCapabilities {
        ACPClientCapabilities(
            fs: ACPFileSystemCapabilities(
                readTextFile: readTextFile,
                writeTextFile: writeTextFile
            ),
            terminal: terminal,
            elicitation: elicitation ? ACPElicitationCapabilities() : nil
        )
    }

    /// Maps the app's approval mode and plan switch to T3's runtime mode
    /// (`vitruvian-code-acp.md`, section 8 and Interfaces).
    public static func runtimeMode(
        mode: VitruvianCodeApprovalMode,
        planSwitch: Bool
    ) -> RuntimeMode {
        if planSwitch {
            return .approvalRequired
        }
        switch mode {
        case .yolo:
            return .fullAccess
        case .acceptEdits:
            return .autoAcceptEdits
        case .standard, .plan, .auto:
            // `.auto` has no separate ACP review mode and falls back to `.standard` (`AntigravityProvider.ts:188-189`).
            return .approvalRequired
        }
    }

    /// Evaluates whether a tool call of `toolKind` is allowed, must ask, or is denied,
    /// ported directly from `acpOperationDisposition`, `acpWorkspaceWriteAllowsMutation`
    /// and `acpReadDisposition` in `clientPolicy.ts:76-190`.
    public func decide(
        mode: VitruvianCodeApprovalMode,
        planSwitch: Bool,
        toolKind: String?,
        sandbox: Sandbox? = nil,
        locations: [ACPToolCallLocation]? = nil,
        cwd: String? = nil,
        approvalPolicy: ApprovalPolicy? = nil
    ) -> Decision {
        let effectiveSandbox = sandbox ?? self.sandbox
        let effectiveApprovalPolicy = approvalPolicy ?? self.approvalPolicy
        let normalizedKind = (toolKind?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "other"

        // `if (isAcpReadKind(toolKind)) return acpReadDisposition(runtimePolicy);` (`clientPolicy.ts:148-150`).
        if Self.isReadKind(normalizedKind) {
            return Self.readDisposition(sandbox: effectiveSandbox)
        }

        let mappedRuntimeMode = Self.runtimeMode(mode: mode, planSwitch: planSwitch)

        // `if (acpPolicyRequiresApproval(runtimePolicy)) return "ask";` (`clientPolicy.ts:76-80, 151-153`).
        if Self.policyRequiresApproval(runtimeMode: mappedRuntimeMode, approvalPolicy: effectiveApprovalPolicy) {
            return .ask
        }

        // `switch (sandboxPolicy?.type)` (`clientPolicy.ts:155-185`).
        switch effectiveSandbox {
        case .readOnly:
            // `clientPolicy.ts:157-158`.
            return .deny

        case .workspaceWrite(let writableRoots):
            // `clientPolicy.ts:159-169`.
            if Self.isMutationKind(normalizedKind) {
                return Self.workspaceWriteAllowsMutation(
                    cwd: cwd,
                    writableRoots: writableRoots,
                    locations: locations
                ) ? .allow(.allowOnce) : .deny
            }
            return .deny

        case .dangerFullAccess, .externalSandbox:
            // `clientPolicy.ts:170-172`.
            return .allow(.allowOnce)

        case nil:
            // `case undefined:` (`clientPolicy.ts:173-182`).
            if mappedRuntimeMode == .approvalRequired {
                return .deny
            }
            if mappedRuntimeMode == .autoAcceptEdits,
               effectiveApprovalPolicy == nil,
               !Self.isMutationKind(normalizedKind) {
                return .ask
            }
            return .allow(.allowOnce)

        case .unknown:
            // `default: return "deny";` (`clientPolicy.ts:183-185`).
            return .deny
        }
    }

    /// Evaluates `decide` against the concrete options on a permission request, preferring
    /// `allow_once` over `allow_always`, falling back to `.ask` when allowed but no allow option
    /// is offered, and preserving `.deny`.
    public func decide(
        mode: VitruvianCodeApprovalMode,
        planSwitch: Bool,
        toolKind: String?,
        sandbox: Sandbox? = nil,
        locations: [ACPToolCallLocation]? = nil,
        cwd: String? = nil,
        approvalPolicy: ApprovalPolicy? = nil,
        options: [AgentPermissionOption]
    ) -> Decision {
        switch decide(
            mode: mode,
            planSwitch: planSwitch,
            toolKind: toolKind,
            sandbox: sandbox,
            locations: locations,
            cwd: cwd,
            approvalPolicy: approvalPolicy
        ) {
        case .allow:
            if options.contains(where: { $0.kind == .allowOnce }) {
                return .allow(.allowOnce)
            }
            if options.contains(where: { $0.kind == .allowAlways }) {
                return .allow(.allowAlways)
            }
            return .ask
        case .ask:
            return .ask
        case .deny:
            return .deny
        }
    }

    /// Resolves an automatic `ACPPermissionOutcome` without prompting the user, or returns `nil`
    /// when the user must be shown an approval card (`.ask`).
    /// On `.deny`, selects `reject_once`, else `reject_always`, else `.cancelled`.
    public func resolvePermissionOutcome(
        mode: VitruvianCodeApprovalMode,
        planSwitch: Bool,
        toolKind: String?,
        sandbox: Sandbox? = nil,
        locations: [ACPToolCallLocation]? = nil,
        cwd: String? = nil,
        approvalPolicy: ApprovalPolicy? = nil,
        options: [AgentPermissionOption]
    ) -> ACPPermissionOutcome? {
        switch decide(
            mode: mode,
            planSwitch: planSwitch,
            toolKind: toolKind,
            sandbox: sandbox,
            locations: locations,
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            options: options
        ) {
        case .allow(let desiredKind):
            guard let option = options.first(where: { $0.kind == desiredKind }) else {
                return nil
            }
            return .selected(optionId: option.id)
        case .deny:
            if let rejectOnce = options.first(where: { $0.kind == .rejectOnce }) {
                return .selected(optionId: rejectOnce.id)
            }
            if let rejectAlways = options.first(where: { $0.kind == .rejectAlways }) {
                return .selected(optionId: rejectAlways.id)
            }
            return .cancelled
        case .ask:
            return nil
        }
    }

    /// Picks the concrete `AgentPermissionOption` to select when allowed, or `nil` otherwise.
    public func selectPermissionOption(
        mode: VitruvianCodeApprovalMode,
        planSwitch: Bool,
        toolKind: String?,
        sandbox: Sandbox? = nil,
        locations: [ACPToolCallLocation]? = nil,
        cwd: String? = nil,
        approvalPolicy: ApprovalPolicy? = nil,
        options: [AgentPermissionOption]
    ) -> AgentPermissionOption? {
        switch decide(
            mode: mode,
            planSwitch: planSwitch,
            toolKind: toolKind,
            sandbox: sandbox,
            locations: locations,
            cwd: cwd,
            approvalPolicy: approvalPolicy,
            options: options
        ) {
        case .allow(let desiredKind):
            return options.first(where: { $0.kind == desiredKind })
        case .ask, .deny:
            return nil
        }
    }

    /// `acpPolicyRequiresApproval` (`clientPolicy.ts:76-80`).
    private static func policyRequiresApproval(
        runtimeMode: RuntimeMode,
        approvalPolicy: ApprovalPolicy?
    ) -> Bool {
        if let approvalPolicy {
            return approvalPolicy != .never
        }
        return runtimeMode == .approvalRequired
    }

    /// `acpReadDisposition` (`clientPolicy.ts:87-98`).
    public static func readDisposition(sandbox: Sandbox?) -> Decision {
        switch sandbox {
        case nil, .readOnly, .workspaceWrite, .dangerFullAccess, .externalSandbox:
            return .allow(.allowOnce)
        case .unknown:
            return .deny
        }
    }

    /// `resolveAcpPermissionPath` (`clientPolicy.ts:22-28`).
    private static func resolvePermissionPath(_ path: String, cwd: String?) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        guard let cwd else { return nil }
        let trimmedCwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCwd.isEmpty else { return nil }
        return trimmedCwd.hasSuffix("/") ? trimmedCwd + trimmed : trimmedCwd + "/" + trimmed
    }

    /// `acpWorkspaceWriteAllowsMutation` (`clientPolicy.ts:100-141`).
    public static func workspaceWriteAllowsMutation(
        cwd: String?,
        writableRoots: [String],
        locations: [ACPToolCallLocation]?
    ) -> Bool {
        let resolvedCwd: String? = {
            guard let cwd else { return nil }
            let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return resolvePermissionPath(trimmed, cwd: FileManager.default.currentDirectoryPath)
        }()

        var canonicalRoots: [String] = []
        if let resolvedCwd,
           let canonicalCwd = ACPClientFiles.canonicalPathForContainment(resolvedCwd) {
            canonicalRoots.append(canonicalCwd)
        }
        for writableRoot in writableRoots {
            guard let resolvedRoot = resolvePermissionPath(writableRoot, cwd: resolvedCwd),
                  let canonicalRoot = ACPClientFiles.canonicalPathForContainment(resolvedRoot) else {
                continue
            }
            canonicalRoots.append(canonicalRoot)
        }
        guard !canonicalRoots.isEmpty else { return false }

        guard let locations, !locations.isEmpty else {
            return false
        }
        for location in locations {
            guard let resolvedLocation = resolvePermissionPath(location.path, cwd: resolvedCwd),
                  let canonicalPath = ACPClientFiles.canonicalPathForContainment(resolvedLocation),
                  canonicalRoots.contains(where: { ACPClientFiles.pathIsWithinRoot(canonicalPath, root: $0) }) else {
                return false
            }
        }
        return true
    }

    /// `isAcpReadKind` (`clientPolicy.ts:82-84`).
    public static func isReadKind(_ toolKind: String) -> Bool {
        toolKind == "read" || toolKind == "search" || toolKind == "think"
    }

    /// `isAcpMutationKind` (`clientPolicy.ts:188-190`).
    public static func isMutationKind(_ toolKind: String) -> Bool {
        toolKind == "edit" || toolKind == "delete" || toolKind == "move"
    }
}
