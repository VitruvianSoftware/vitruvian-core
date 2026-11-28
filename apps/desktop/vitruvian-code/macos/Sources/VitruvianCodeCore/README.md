# Vitruviancodecore

## Overview
Component package providing implementation for `apps/desktop/vitruvian-code/macos/Sources/VitruvianCodeCore`.

## Interface
- `[VersionCompare.swift:VersionCompare]`
- `[VitruvianCodeDiffReview.swift:VitruvianCodeDiffLine]`
- `[VitruvianCodeDiffReview.swift:VitruvianCodeDiffHunk]`
- `[VitruvianCodeDiffReview.swift:VitruvianCodeDiffFile]`
- `[VitruvianCodeDiffReview.swift:VitruvianCodeDiffParser]`
- `[VitruvianCodeDiffReview.swift:VitruvianCodeDiffAnnotation]`
- `[VitruvianCodeDiffReview.swift:VitruvianCodeDiffReviewSession]`
- `[VitruvianCodeDiffReview.swift:VitruvianCodeDesignElementCapture]`
- `[VitruvianCodeDiffReview.swift:VitruvianCodeDesignModeScript]`
- `[VitruvianCodeDiffReview.swift:VitruvianCodePreviewKind]`
- `[VitruvianCodeDiffReview.swift:VitruvianCodeWorkspaceNoteStore]`
- `[VitruvianCodeEngine.swift:VitruvianCodeEngine]`
- `[VitruvianCodeFleetAndCatalog.swift:VitruvianCodeStreamDialect]`
- `[VitruvianCodeFleetAndCatalog.swift:VitruvianCodeCatalogPreset]`
- `[VitruvianCodeFleetAndCatalog.swift:VitruvianCodeParsedEvent]`
- `[VitruvianCodeFleetAndCatalog.swift:VitruvianCodeCatalog]`
- `[VitruvianCodeFleetAndCatalog.swift:VitruvianCodeDualQuotaWindow]`
- `[VitruvianCodeFleetAndCatalog.swift:VitruvianCodeAccountProfile]`
- `[VitruvianCodeFleetAndCatalog.swift:VitruvianCodeAccountManager]`
- `[VitruvianCodeFleetAndCatalog.swift:VitruvianCodeInboxEntry]`

## Agent connections
A chat reaches its agent through one `AgentConnection` (`AgentConnection.swift`). Which one a chat gets is `VitruvianCodeCLIProvider.resolvedConnection`: the saved choice, or the default (ACP for agy and registry agents, the Claude SDK for Claude Code, the command line otherwise). The engine applies the default where it picks a chat's provider (`withDefaultConnection`); saved settings keep `nil`.

| File (`ACP/`) | What it does |
|---|---|
| `ACPTransport.swift`, `ACPSchema.swift` | Newline-delimited JSON-RPC to the agent's process, and the ACP v1 messages |
| `ACPConnection.swift` | One live session: prompts, updates, cancel, resume, modes and session options |
| `ACPClientPolicy.swift`, `ACPClientFiles.swift`, `ACPClientTerminals.swift`, `ACPElicitation.swift` | What the app answers: permission requests by approval mode, file reads and writes, terminals, forms |
| `ACPAuth.swift` | The agent's sign-in methods, offered on the error card |
| `AntigravityACP.swift` | agy over ACP (`agy acp`) |
| `ClaudeSDKConnection.swift` | Starts the bundled Node and Claude helper against the user's `claude` |
| `ACPRegistry.swift`, `ACPRegistryAgentList.swift`, `ACPRegistryConnection.swift` | The public ACP registry: install, update, remove, and a chat with an installed agent |
| `RegistryAgents/` | Per-agent handling, such as the Claude ACP adapter's subagents |

Tests replay recorded sessions from `../../../testdata/acp/` and the helper's `../../claude-helper/protocol/examples/`.

## Invariants
- None

## Side Effects
- [VitruvianCodeFleetAndCatalog.swift:169]: `commandTemplate: "codex exec --json \"{prompt}\"",`
- [VitruvianCodeFleetAndCatalog.swift:399]: `commandTemplate: "droid exec \"{prompt}\"",`
- [VitruvianCodeQuickPromptLayout.swift:269]: `public static let query = """`
- [VitruvianCodeQuickPromptSession.swift:288]: `@Published public var designModeInitialURL: String = "http://localhost:3000"`
- [VitruvianCodeQuickPromptSession.swift:335]: `writeFile: environment.writePrivateFile`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-code/macos/Sources/VitruvianCodeCore/...`
