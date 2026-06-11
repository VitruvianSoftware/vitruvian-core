# Extension Improvements Roadmap

This document outlines recommended improvements to reduce regressions and improve code
maintainability in the Tabula Chrome Extension.

## Current State

- **Dashboard.tsx**: 2900+ lines (code smell - too large)
- **Test Coverage**: 17.8% lines (below 80% threshold)
- **Known Issues**: Stale closure bugs, race conditions in state management

---

## 1. Improve Test Coverage (Highest Priority)

**Goal:** Reach 80% line coverage threshold

### Priority Test Areas

| File/Area             | Current Coverage | Priority |
| --------------------- | ---------------- | -------- |
| `Dashboard.tsx`       | Very Low         | High     |
| `stores/workspace.ts` | Low              | High     |
| `services/tabs.ts`    | Low              | Medium   |
| `components/*`        | Low              | Medium   |

### Specific Tests Needed

```typescript
// Tab sync logic - prevents regression of stale closure bug
describe('syncTabs', () => {
  it('should use current workspace ID from ref after workspace switch');
  it('should update state immediately before persisting to storage');
  it('should not call loadWorkspaces after optimistic update');
});

// Tab event handlers
describe('handleTabRemoved', () => {
  it('should immediately remove closed tab from UI');
  it('should trigger debounced sync after removal');
});
```

---

## 2. Break Down Dashboard.tsx

**Goal:** Split into focused, testable modules

### Proposed Extraction

#### Custom Hooks

```
src/hooks/
├── useTabSync.ts          # Tab change listeners, syncTabs logic
├── useWorkspaceManager.ts # Workspace CRUD, switching logic
├── useDragAndDrop.ts      # DnD context, handlers
└── useActiveWorkspace.ts  # activeWorkspace state + ref pattern
```

#### Components

```
src/components/
├── ActiveTabsPanel/       # Right sidebar Active Tabs list
├── ResourceSection/       # Collapsible resource sections
├── WorkspaceHeader/       # Workspace title, inline edit, Share button
├── SidebarWorkspaceList/  # Left sidebar workspace navigation
└── ContentTabs/           # Resources/Notes/Tasks tab switcher
```

#### Constants

```
src/constants/
├── colors.ts              # Color picker options
└── limits.ts              # MAX_WORKSPACES, etc.
```

---

## 3. Add Integration/E2E Tests

**Goal:** Catch bugs that only appear in real Chrome context

### Recommended Tools

- **Playwright** with Chrome extension support
- **Puppeteer** for browser automation

### Critical User Flows to Test

1. Open new browser tab → appears in Active Tabs
2. Close browser tab → disappears from Active Tabs
3. Switch workspace → correct tabs displayed
4. Drag resource to section → persists after refresh
5. Inline edit workspace/section name → saves correctly

---

## 4. Document React Patterns

**Goal:** Prevent stale closure bugs in the future

### Pattern: Use Refs for Callbacks

```typescript
// ❌ BAD - stale closure
useEffect(() => {
  const handler = () => {
    console.log(someState); // Captured at effect creation time
  };
  window.addEventListener('event', handler);
}, []);

// ✅ GOOD - always current value
const someStateRef = useRef(someState);
useEffect(() => {
  someStateRef.current = someState;
}, [someState]);

useEffect(() => {
  const handler = () => {
    console.log(someStateRef.current); // Always current
  };
  window.addEventListener('event', handler);
}, []);
```

### Consider a `useLatest` Hook

```typescript
function useLatest<T>(value: T): React.RefObject<T> {
  const ref = useRef(value);
  ref.current = value;
  return ref;
}
```

---

## 5. Add Regression Tests for Fixed Bugs

**Rule:** Every bug fix should include a test that would have caught it.

### Recent Bug Fixes Needing Tests

| Bug                           | Fix Date     | Test Needed                        |
| ----------------------------- | ------------ | ---------------------------------- |
| Stale closure in syncTabs     | Dec 24, 2024 | Tab sync uses current workspace ID |
| loadWorkspaces race condition | Dec 24, 2024 | Optimistic update not overwritten  |
| Tab removal not updating UI   | Dec 24, 2024 | Closed tab immediately removed     |

---

## Implementation Priority

1. **Phase 1:** Add tests for tab sync logic (prevent regressions)
2. **Phase 2:** Extract custom hooks from Dashboard.tsx
3. **Phase 3:** Extract components from Dashboard.tsx
4. **Phase 4:** Add E2E tests for critical flows
5. **Phase 5:** General coverage improvement to 80%
