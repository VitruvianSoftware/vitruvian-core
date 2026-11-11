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
