# Workspace Operations Developer Guide

This guide covers the workspace and tab management operations implemented in Tabula's MVP.

## Architecture Overview

Workspace management is split across three layers:

1. **Extension (Frontend)**
   - Local storage for offline access
   - UI components for workspace CRUD
   - Tab management services
   - Zustand store for state management

2. **API (Backend)**
   - RESTful endpoints for workspace operations
   - Business logic enforcement (e.g., free tier limits)
   - Database operations via Prisma
   - JWT-based authentication

3. **Database (Neon Postgres)**
   - `workspaces` table for workspace metadata
   - `tabs` table for tab data
   - Foreign key constraints for data integrity
   - Cascade deletes for cleanup

## Workspace CRUD Operations

### Create Workspace

**Endpoint:** `POST /api/v1/workspaces`

**Request:**

```json
{
  "name": "Work Projects",
  "description": "Tabs related to current work projects",
  "color": "#4F46E5",
  "icon": "💼",
  "position": 0,
  "settings": {
    "autoSuspend": true,
    "suspendAfterMinutes": 30
  }
}
```

**Response (201):**

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "Work Projects",
    "description": "Tabs related to current work projects",
    "color": "#4F46E5",
    "icon": "💼",
    "position": 0,
    "createdAt": "2024-01-15T10:00:00Z",
    "updatedAt": "2024-01-15T10:00:00Z",
    "tabs": []
  }
}
```

**Free Tier Limit:**

- Maximum 10 workspaces per user
- Returns `403 Forbidden` if limit exceeded
- Paid tiers have unlimited workspaces

**Implementation:**

- Extension: `WorkspaceService.createWorkspace()`
- API: `WorkspaceService.createWorkspace()` → checks count → inserts to DB
- Store: `useWorkspaceStore.createWorkspace()`

### Get All Workspaces

**Endpoint:** `GET /api/v1/workspaces`

**Response (200):**

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Work Projects",
      "tabs": [
        {
          "id": "tab-id-1",
          "url": "https://github.com",
          "title": "GitHub",
          "position": 0,
          "isPinned": false
        }
      ]
    }
  ]
}
```

**Features:**

- Returns workspaces with nested tabs
- Ordered by position
- Tabs ordered by position within workspace

### Update Workspace

**Endpoint:** `PUT /api/v1/workspaces/:id`

**Request:**

```json
{
  "name": "Updated Name",
  "color": "#DC2626"
}
```

**Response (200):**

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "Updated Name",
    "color": "#DC2626",
    ...
  }
}
```

**Validation:**

- Only updates provided fields
- Verifies workspace ownership
- Returns `404 Not Found` if workspace doesn't exist

### Delete Workspace

**Endpoint:** `DELETE /api/v1/workspaces/:id`

**Response:** `204 No Content`

**Behavior:**

- Verifies workspace ownership
- Cascade deletes all tabs in workspace
- Clears active workspace if it was deleted
- Returns `404 Not Found` if workspace doesn't exist

## Tab Management Operations

### Save Current Tabs to Workspace

**Endpoint:** `POST /api/v1/workspaces/:id/tabs`

**Request:**

```json
{
  "tabs": [
    {
      "url": "https://github.com",
      "title": "GitHub",
      "faviconUrl": "https://github.com/favicon.ico",
      "position": 0,
      "isPinned": false,
      "metadata": {}
    }
  ]
}
```

**Response (200):**

```json
{
  "data": {
    "id": "workspace-id",
    "name": "Work Projects",
    "tabs": [...]
  }
}
```

**Behavior:**

- Deletes all existing tabs in workspace
- Inserts new tabs in a transaction
- Ensures atomicity (all or nothing)
- Updates workspace's `updatedAt` timestamp

### Restore Workspace Tabs

**Extension Only** - No direct API endpoint

**Method:** `WorkspaceService.restoreWorkspaceTabs()`

**Options:**

```typescript
{
  inNewWindow: boolean,      // Open tabs in new window
  closeCurrentTabs: boolean  // Close existing tabs first
}
```

**Behavior:**

- Retrieves workspace from storage/API
- Optionally closes current tabs
- Opens tabs from workspace
- Sets workspace as active

### Switch Workspace

**Extension Only** - Combines restore + close

**Method:** `WorkspaceService.switchToWorkspace()`

**Behavior:**

- Closes all current tabs (except pinned)
- Opens all tabs from target workspace
- Sets target workspace as active
- Updates visual indicators

### Move Tab Between Workspaces

**Endpoint:** `POST /api/v1/workspaces/tabs/move`

**Request:**

```json
{
  "tabId": "550e8400-e29b-41d4-a716-446655440000",
  "targetWorkspaceId": "550e8400-e29b-41d4-a716-446655440001",
  "position": 2
}
```

**Response (200):**

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "workspaceId": "550e8400-e29b-41d4-a716-446655440001",
    "position": 2,
    ...
  }
}
```

**Use Cases:**

- Drag & drop tab between workspaces
- Reorganizing tab collections
- Moving tabs to different contexts

### Reorder Tab Within Workspace

**Endpoint:** `POST /api/v1/workspaces/tabs/reorder`

**Request:**

```json
{
  "tabId": "550e8400-e29b-41d4-a716-446655440000",
  "newPosition": 5
}
```

**Response (200):**

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "position": 5,
    ...
  }
}
```

**Use Cases:**

- Drag & drop reordering within workspace
- Manual position adjustment
- Organizing tabs by priority

### Bulk Tab Operations

**Endpoint:** `POST /api/v1/workspaces/tabs/bulk`

**Request:**

```json
{
  "tabIds": ["550e8400-e29b-41d4-a716-446655440000", "550e8400-e29b-41d4-a716-446655440001"],
  "operation": "close" // or "pin", "unpin"
}
```

**Response (200):**

```json
{
  "data": {
    "deleted": 2  // for "close" operation
  }
}
// or
{
  "data": {
    "updated": 2  // for "pin"/"unpin" operations
  }
}
```

**Operations:**

- `close`: Delete tabs from database
- `pin`: Set `isPinned = true`
- `unpin`: Set `isPinned = false`
- `suspend`: Client-side only (uses `chrome.tabs.discard()`)

**Validation:**

- All tabs must belong to user's workspaces
- Returns `403 Forbidden` if any tab ownership mismatch

## Extension-Side Tab Operations

### Close Tabs

**Method:** `TabService.closeTabs(tabIds: number[])`

**Behavior:**

- Uses `chrome.tabs.remove()` API
- Removes tabs from browser
- Does not affect stored tabs in workspaces

### Suspend Tabs

**Method:** `TabService.suspendTabs(tabIds: number[])`

**Behavior:**

- Uses `chrome.tabs.discard()` API
- Reduces memory usage
- Tab remains open but content unloaded
- Reloads when activated

### Pin/Unpin Tabs

**Method:** `TabService.setPinned(tabIds: number[], pinned: boolean)`

**Behavior:**

- Uses `chrome.tabs.update()` API
- Sets tab as pinned/unpinned in browser
- Affects tab position and behavior

### Move Tab Position

**Method:** `TabService.moveTab(tabId: number, newIndex: number)`

**Behavior:**

- Uses `chrome.tabs.move()` API
- Changes tab position in browser
- For drag & drop reordering

## State Management

### Extension State (Zustand)

```typescript
interface WorkspaceStore {
  workspaces: Workspace[];
  activeWorkspaceId: string | null;
  loading: boolean;
  error: string | null;

  loadWorkspaces: () => Promise<void>;
  createWorkspace: (input: WorkspaceCreateInput) => Promise<Workspace>;
  updateWorkspace: (id: string, input: WorkspaceUpdateInput) => Promise<Workspace>;
  deleteWorkspace: (id: string) => Promise<void>;
  saveCurrentTabs: (id: string) => Promise<void>;
  restoreTabs: (id: string, options?) => Promise<void>;
  switchWorkspace: (id: string) => Promise<void>;
  setActiveWorkspace: (id: string | null) => void;
}
```

### Local Storage Keys

- `tabula_workspaces`: Array of workspaces
- `tabula_active_workspace`: Active workspace ID
- `tabula_settings`: Extension settings

### Visual Indicators

- **Active Workspace**: Purple border, light purple background
- **Workspace Status**: "ACTIVE" badge
- **Tab Count**: Displayed on workspace card
- **Workspace Limit**: Warning message when at 10 workspaces

## Error Handling

### Common Error Codes

- `400 Bad Request`: Invalid input data
- `401 Unauthorized`: Missing or invalid auth token
- `403 Forbidden`: Workspace limit reached or permission denied
- `404 Not Found`: Workspace/tab not found
- `500 Internal Server Error`: Server error

### Extension Error Handling

```typescript
try {
  await workspaceStore.createWorkspace(input);
} catch (error) {
  // Error is already handled by store
  // UI shows error message
  console.error('Failed to create workspace:', error);
}
```

### API Error Responses

```json
{
  "error": "Forbidden",
  "message": "Maximum number of workspaces reached for free tier (10)"
}
```

## Testing

### Unit Tests

**API Service Tests:**

- `api/tests/unit/workspace.service.test.ts`
- Tests workspace CRUD operations
- Tests tab operations
- Tests limit enforcement

**Extension Service Tests:**

- `extension/src/services/workspace.test.ts`
- Tests workspace operations
- Tests tab management
- Mocks Chrome APIs

### Integration Tests

**API Integration Tests:**

- `api/tests/integration/workspace.test.ts`
- Tests full request/response cycle
- Tests authentication
- Tests error handling

### E2E Tests

**Extension E2E Tests:**

- `extension/tests/e2e.spec.ts`
- Tests workspace creation flow
- Tests tab save/restore
- Tests workspace switching

## Best Practices

1. **Always validate workspace ownership** before operations
2. **Use transactions** for multi-step operations (e.g., save tabs)
3. **Handle offline mode** gracefully in extension
4. **Provide user feedback** for all operations
5. **Implement optimistic updates** for better UX
6. **Cache workspaces** in extension local storage
7. **Sync with API** periodically for consistency
8. **Handle Chrome API errors** gracefully
9. **Test with maximum workspace limit**
10. **Consider rate limiting** when making bulk operations

## Performance Considerations

1. **Lazy load tab data** for large workspaces
2. **Paginate workspace lists** for users with many workspaces
3. **Debounce reorder operations** during drag & drop
4. **Batch tab operations** when possible
5. **Use indexes** on frequently queried fields (userId, workspaceId)
6. **Cache workspace counts** to avoid repeated queries
7. **Minimize API calls** by using local storage

## Future Enhancements

1. **Workspace sharing** for team collaboration
2. **Smart workspace suggestions** based on tab patterns
3. **Workspace templates** for common use cases
4. **Tab deduplication** across workspaces
5. **Workspace search** across tabs and metadata
6. **Workspace export/import** for backup
7. **Keyboard shortcuts** for common operations
8. **Workspace tags** for better organization
9. **Tab previews** in workspace cards
10. **Workspace analytics** for insights
