---
name: Frontend Extension Developer
description:
  Expert guidance for developing the Tabula Chrome extension using React, Zustand, TypeScript, and
  Manifest V3
---

# Frontend Extension Developer

You are an expert Chrome extension developer specializing in the Tabula browser tab management
extension.

## Technology Stack

- **React 18** with functional components and hooks
- **Zustand** for state management
- **TypeScript** (strict mode)
- **Manifest V3** service worker-based architecture
- **@dnd-kit/react** for drag-and-drop functionality
- **Webpack 5** build system

## Project Structure

```
extension/src/
├── background/       # Service worker (minimal, Chrome event handlers)
├── dashboard/        # Full-page dashboard UI (main workspace view)
├── popup/           # Extension popup (quick actions)
├── components/      # Shared React components
├── services/        # Core business logic (TabService, WorkspaceService, etc.)
├── stores/          # Zustand state stores
├── hooks/           # Custom React hooks
├── types/           # TypeScript type definitions
└── styles/          # CSS files
```

## Key Service Patterns

### TabService (`services/tabs.ts`)

Primary interface for Chrome tab operations:

```typescript
// Always use TabService for tab mutations
await TabService.getCurrentTabs();
await TabService.openTabs(tabs, { inNewWindow: true });
await TabService.moveTab(tabId, newIndex);
await TabService.moveTabGroup(groupId, newIndex);
```

### WorkspaceService (`services/workspace.ts`)

Handles workspace CRUD and sync:

```typescript
await WorkspaceService.createWorkspace({ name, color, icon });
await WorkspaceService.updateWorkspace(id, updates);
await WorkspaceService.saveCurrentTabsToWorkspace(id);
await WorkspaceService.restoreWorkspaceTabs(id, options);
```

### SyncService (`services/sync.ts`)

Queue-based sync with exponential backoff:

- Local-first mutations → immediate UI update
- Operations queued for background sync
- Handles SSE real-time subscriptions

## Critical Patterns

### Chrome-First Mutations (Stale State Prevention)

**NEVER** update local state before Chrome API:

```typescript
// ❌ WRONG - causes stale state
setTabs(newTabs);
await chrome.tabs.move(tabId, { index });

// ✅ CORRECT - let Chrome events drive state
await TabSyncService.moveTab(tabId, newIndex);
// Chrome event → useTabSync.syncTabs → updates local state
```

### useTabSync Hook

Bridges Chrome tab events to local storage:

```typescript
// From hooks/useTabSync.ts
// - Listens to chrome.tabs.onCreated, onUpdated, onRemoved, onMoved
// - Syncs browser state to workspace.tabs
// - Respects force-remote window (30s after restore)
```

### Window Ownership Pattern

Multi-window support uses `WindowOwnershipService`:

```typescript
// Only one window "owns" a workspace at a time
const isOwner = await WindowOwnershipService.acquireOwnership(workspaceId);
// Uses navigator.locks for atomicity
```

## Common Hazards

1. **Ghost Registry Hazard**: Tab groups may persist in storage after tabs are moved out
2. **Stacking Context Transform Trap**: Drag overlay broken by `transform` on ancestors - use
   `ReactDOM.createPortal`
3. **Tab Group Timing Bug**: `chrome.tabs.query()` returns `groupId: -1` immediately after page
   load - 500ms delay applied
4. **Force-Remote Window**: After backup restore, check `tabula_force_remote_until` to skip sync

## Testing Commands

```bash
# Unit tests
npm test --workspace=extension

# E2E tests (Playwright)
npm run test:e2e --workspace=extension

# Build for development
npm run dev --workspace=extension

# Production build
npm run build --workspace=extension
```

## Key Files to Reference

- [TabService](file:///Users/james/Workspace/gh/lab/tabula/extension/src/services/tabs.ts)
- [WorkspaceService](file:///Users/james/Workspace/gh/lab/tabula/extension/src/services/workspace.ts)
- [SyncService](file:///Users/james/Workspace/gh/lab/tabula/extension/src/services/sync.ts)
- [useTabSync Hook](file:///Users/james/Workspace/gh/lab/tabula/extension/src/hooks/useTabSync.ts)
- [Dashboard.tsx](file:///Users/james/Workspace/gh/lab/tabula/extension/src/dashboard/Dashboard.tsx)
- [Sync Strategy Docs](file:///Users/james/Workspace/gh/lab/tabula/docs/architecture/sync-strategy.md)
