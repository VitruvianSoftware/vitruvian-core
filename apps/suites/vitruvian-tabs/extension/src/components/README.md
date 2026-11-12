# Components

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/extension/src/components`.

## Interface
- `[AccountSettings.tsx:AccountSettings]`
- `[CrossDeviceSessionPopover.tsx:CrossDeviceTab]`
- `[CrossDeviceSessionPopover.tsx:CrossDeviceSessionPopoverProps]`
- `[CrossDeviceSessionPopover.tsx:CrossDeviceSessionPopover]`
- `[EmptyState.tsx:EmptyState]`
- `[Login.tsx:Login]`
- `[Modal.tsx:Modal]`
- `[NoteEditor.tsx:NoteEditorProps]`
- `[NoteEditor.tsx:NoteEditor]`
- `[SyncStatusIndicator.tsx:SyncStatusIndicator]`
- `[TabConflictPopover.tsx:TabConflictPopoverProps]`
- `[TabConflictPopover.tsx:TabConflictPopover]`
- `[Tooltip.tsx:Tooltip]`
- `[UpdateBanner.tsx:UpdateBanner]`
- `[WorkspaceCard.tsx:WorkspaceCard]`
- `[WorkspaceForm.tsx:WorkspaceForm]`
- `[icons.tsx:Icon]`
- `[icons.tsx:Icons]`
- Subdirectory: [illustrations](./illustrations/README.md)
- Subdirectory: [onboarding](./onboarding/README.md)

## Invariants
- None

## Side Effects
- [NoteEditor.test.tsx:54]: `// Query by class since data-testid is not present`

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/extension/src/components/...`
