# Known Issues

## ~~Active Tabs "Loading..." or "Untitled" State~~ [RESOLVED]

**Status:** ✅ Resolved (December 24, 2024)

**Original Problem:** When opening or closing browser tabs, the "Active Tabs" panel didn't update in
real-time. Tabs would show stale titles or wouldn't appear/disappear until a manual refresh.

**Root Cause:** Two issues were identified:

1. **Stale Closure Bug:** The `activeWorkspaceId` was captured in a closure when the useEffect ran,
   causing tab syncs to target wrong workspaces.
2. **Race Condition:** After setting fresh tabs from Chrome, `loadWorkspaces()` was called which
   loaded stale data from storage and overwrote the correct tabs.

**Fix Applied:**

1. Added `activeWorkspaceRef` that stays in sync with current workspace state
2. Modified `syncTabs` to use `activeWorkspaceRef.current.id` instead of stale closure value
3. Removed the `loadWorkspaces()` call after optimistic update to prevent race condition
4. Added dedicated `handleTabRemoved` function for immediate optimistic removal of closed tabs

**Result:** Tabs now update in real-time when opened or closed.
