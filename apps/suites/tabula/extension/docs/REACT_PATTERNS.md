# React Patterns Guide

Best practices for preventing common React bugs in the Tabula extension.

## The Stale Closure Problem

When using event handlers or callbacks inside `useEffect`, the callback captures values from when it
was created. If state changes, the callback still sees the old values.

### ❌ Anti-Pattern: Stale Closure

```typescript
function Dashboard() {
  const [activeWorkspace, setActiveWorkspace] = useState(null);

  useEffect(() => {
    const handler = () => {
      // BUG: This captures activeWorkspace at effect creation time
      // If user switches workspace, this still uses the OLD workspace ID
      syncTabs(activeWorkspace.id);
    };

    chrome.tabs.onCreated.addListener(handler);
    return () => chrome.tabs.onCreated.removeListener(handler);
  }, []); // Empty deps means handler never updates
}
```

**Why this fails:** The `handler` function closes over `activeWorkspace` from the first render. Even
when `activeWorkspace` changes, the listener still uses the stale value.

---

## The Ref Pattern

Use refs to always access the current value inside callbacks.

### ✅ Pattern: Use Refs for Current Value

```typescript
function Dashboard() {
  const [activeWorkspace, setActiveWorkspace] = useState(null);
  const activeWorkspaceRef = useRef(activeWorkspace);

  // Keep ref in sync with state
  useEffect(() => {
    activeWorkspaceRef.current = activeWorkspace;
  }, [activeWorkspace]);

  useEffect(() => {
    const handler = () => {
      // CORRECT: Always gets current workspace via ref
      const current = activeWorkspaceRef.current;
      if (current) {
        syncTabs(current.id);
      }
    };

    chrome.tabs.onCreated.addListener(handler);
    return () => chrome.tabs.onCreated.removeListener(handler);
  }, []);
}
```

---

## The `useLatest` Hook

We provide a utility hook to simplify this pattern:

```typescript
import { useLatest } from './hooks/useLatest';

function Dashboard() {
  const [activeWorkspace, setActiveWorkspace] = useState(null);
  const activeWorkspaceRef = useLatest(activeWorkspace);

  useEffect(() => {
    const handler = () => {
      // Always current value
      syncTabs(activeWorkspaceRef.current?.id);
    };

    chrome.tabs.onCreated.addListener(handler);
    return () => chrome.tabs.onCreated.removeListener(handler);
  }, []);
}
```

### Implementation

```typescript
// src/hooks/useLatest.ts
export function useLatest<T>(value: T): React.RefObject<T> {
  const ref = useRef(value);
  ref.current = value;
  return ref;
}
```

---

## Real Example: useTabSync

See [useTabSync.ts](../src/hooks/useTabSync.ts) for a production example:

```typescript
export const useTabSync = ({
  activeWorkspaceRef, // Ref to current workspace
  isSwitchingRef, // Ref to switching state
  setActiveWorkspaceData,
}: UseTabSyncOptions) => {
  const syncTabs = useCallback(async () => {
    // Uses refs to always get current values
    const currentWorkspace = activeWorkspaceRef.current;
    const workspaceId = currentWorkspace?.id;
    if (!workspaceId || isSwitchingRef.current) return;

    // ... sync logic
  }, [activeWorkspaceRef, isSwitchingRef]);

  useEffect(() => {
    // These handlers use refs, so they always have current state
    chrome.tabs.onCreated.addListener(debouncedSync);
    // ...
  }, []);
};
```

---

## When to Use This Pattern

Use refs when:

1. **Event listeners** registered in `useEffect` with empty/stable deps
2. **Chrome extension APIs** that need current state in callbacks
3. **Timers** (`setTimeout`, `setInterval`) that reference state
4. **Any callback** that outlives a render cycle

---

## Testing the Pattern

See [useTabSync.test.ts](../tests/useTabSync.test.ts) for comprehensive tests:

```typescript
it('should use current workspace ID from ref, not stale closure', async () => {
  const workspace1 = createMockWorkspace({ id: 'ws-old' });
  const workspace2 = createMockWorkspace({ id: 'ws-new' });

  activeWorkspaceRef = { current: workspace1 };

  const { result } = renderHook(() => useTabSync({ activeWorkspaceRef, ... }));

  // Simulate workspace switch
  activeWorkspaceRef.current = workspace2;

  // syncTabs should use ws-new, not ws-old
  await result.current.syncTabs();

  expect(WorkspaceService.saveCurrentTabsToWorkspace).toHaveBeenCalledWith('ws-new');
});
```
