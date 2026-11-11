# Vitruviancodeui

## Overview
Component package providing implementation for `apps/desktop/vitruvian-code/macos/Sources/VitruvianCodeUI`.

## Interface
- `[VitruvianCodeAutomationAndOrchestrationViews.swift:VitruvianCodeAutomationAndOrchestrationView]`
- `[VitruvianCodeChatChrome.swift:VitruvianCodeChatChrome]`
- `[VitruvianCodeChatChrome.swift:VitruvianCodeNotchBackdrop]`
- `[VitruvianCodeChatControls.swift:ModularButtonView]`
- `[VitruvianCodeChatControls.swift:SendButtonView]`
- `[VitruvianCodeChatControls.swift:QuickPromptDragHandle]`
- `[VitruvianCodeChatControls.swift:PromptFieldArrival]`
- `[VitruvianCodeChatControls.swift:ModelPickerMenuContent]`
- `[VitruvianCodeChatControls.swift:ModularModelButtonView]`
- `[VitruvianCodeChatControls.swift:ModularProviderButtonView]`
- `[VitruvianCodeChatControls.swift:ChatProviderBadge]`
- `[VitruvianCodeChatControls.swift:ChatModelBadge]`
- `[VitruvianCodeChatControls.swift:ChatWorkingDirectoryBadge]`
- `[VitruvianCodeChatControls.swift:ModeToggleStrip]`
- `[VitruvianCodeChatControls.swift:ActiveSubagentBannerView]`
- `[VitruvianCodeChatControls.swift:ChatEffortBadge]`
- `[VitruvianCodeChatControls.swift:ChatApprovalModeBadge]`
- `[VitruvianCodeChatControls.swift:UndoTurnChip]`
- `[VitruvianCodeChatStrings.swift:VitruvianCodeChatStrings]`
- `[VitruvianCodeChatView.swift:VitruvianCodeTheme]`
- Subdirectory: [Resources](./Resources/README.md)

## Invariants
- [VitruvianCodeSyntaxHighlighter.swift:258]: `"False", "None", "True", "and", "as", "assert", "async", "await", "break", "c...`

## Side Effects
- [VitruvianCodeDiffReviewAndDesignViews.swift:410]: `initialURL: String = "http://localhost:3000",`
- [VitruvianCodeDiffReviewAndDesignViews.swift:446]: `TextField("http://localhost:3000", text: $urlString)`
- [VitruvianCodeFleetAndJumpViews.swift:34]: `@State private var query = ""`
- [VitruvianCodeFleetAndJumpViews.swift:48]: `VitruvianCodeJumpSearch.filter(query: query, targets: targets, limit: 15)`
- [VitruvianCodeFleetAndJumpViews.swift:58]: `TextField("Jump to session, worktree, command, agent, or task…", text: $query)`
- [VitruvianCodeMermaidPage.swift:111]: `<meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-code/macos/Sources/VitruvianCodeUI/...`
