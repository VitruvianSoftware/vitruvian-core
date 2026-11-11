# Hooks

## Overview
Component package providing implementation for `apps/suites/tabula/extension/src/hooks`.

## Interface
- `[useLatest.ts:useLatest]`
- `[useLiveTabs.ts:useLiveTabs]`
- `[useTabSync.ts:ACTIVE_DEVICE_STALE_MS]`
- `[useTabSync.ts:useTabSync]`
- `[useTheme.ts:Theme]`
- `[useTheme.ts:useTheme]`

## Invariants
- None

## Side Effects
- [useLiveTabs.test.ts:30]: `query: jest.fn(),`
- [useLiveTabs.test.ts:66]: `mockChrome.tabs.query.mockResolvedValue([...mockTabs]);`
- [useLiveTabs.test.ts:69]: `it("should fetch and filter out pinned tabs and extension pages on mount", as...`
- [useLiveTabs.ts:74]: `* Fetch current tabs from Chrome.`
- [useLiveTabs.ts:88]: `console.error("[useLiveTabs] Failed to fetch tabs:", err);`
- [useLiveTabs.ts:109]: `const currentTabs = await chrome.tabs.query({ currentWindow: true });`
- [useTabSync.test.ts:401]: `url: "http://localhost:3000",`
- [useTabSync.ts:266]: `// `reliable` distinguishes a genuine "no groups" from a failed query — the`
- [useTabSync.ts:333]: `// Only resurrect stored groups when the Chrome query was UNRELIABLE.`
- [useTabSync.ts:494]: `// refresh Chrome's tabs.query() briefly reports groupId -1 for grouped tabs`

## Verification
- Run: `bazel test //apps/suites/tabula/extension/src/hooks/...`
