# Hooks

## Overview
Component package providing implementation for `apps/suites/tabula/extension/src/dashboard/hooks`.

## Interface
- `[useCrossDeviceSession.ts:UseCrossDeviceSessionReturn]`
- `[useCrossDeviceSession.ts:useCrossDeviceSession]`
- `[useDragAndDrop.ts:UseDragAndDropProps]`
- `[useDragAndDrop.ts:UseDragAndDropReturn]`
- `[useDragAndDrop.ts:useDragAndDrop]`
- `[useMenuState.ts:UseMenuStateReturn]`
- `[useMenuState.ts:useMenuState]`
- `[useNotesAndTasks.ts:UseNotesAndTasksProps]`
- `[useNotesAndTasks.ts:UseNotesAndTasksReturn]`
- `[useNotesAndTasks.ts:useNotesAndTasks]`
- `[useRelayImport.ts:UseRelayImportProps]`
- `[useRelayImport.ts:useRelayImport]`
- `[useResourceHandlers.ts:UseResourceHandlersProps]`
- `[useResourceHandlers.ts:UseResourceHandlersReturn]`
- `[useResourceHandlers.ts:useResourceHandlers]`
- `[useWorkspaceSwitch.ts:UseWorkspaceSwitchProps]`
- `[useWorkspaceSwitch.ts:ConflictInfo]`
- `[useWorkspaceSwitch.ts:UseWorkspaceSwitchReturn]`
- `[useWorkspaceSwitch.ts:useWorkspaceSwitch]`

## Invariants
- [useDragAndDrop.ts:85]: `distance: 10, // Require 10px movement before drag starts`

## Side Effects
- [useDragAndDrop.test.ts:256]: `tab: { title: "New", url: "http://test.com" },`
- [useDragAndDrop.test.ts:267]: `expect.objectContaining({ title: "New", url: "http://test.com" }),`
- [useResourceHandlers.test.tsx:66]: `url: "http://test.com",`
- [useResourceHandlers.test.tsx:70]: `query: jest.fn().mockResolvedValue([]),`
- [useResourceHandlers.test.tsx:183]: `result.current.setNewResourceUrl("http://test.com");`
- [useResourceHandlers.ts:192]: `const currentTabs = await chrome.tabs.query({ currentWindow: true });`

## Verification
- Run: `bazel test //apps/suites/tabula/extension/src/dashboard/hooks/...`
