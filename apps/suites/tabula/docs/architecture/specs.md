# Technical Specifications

## Overview

This document provides detailed technical specifications for all components of the Tabula system,
including the browser extension, backend API, database schema, and integration points. These
specifications serve as the authoritative reference for implementation.

---

## Browser Extension Specifications

### Manifest V3 Structure

The extension uses Chrome's Manifest V3 format for enhanced security and performance.

```json
{
  "manifest_version": 3,
  "name": "Tabula - Tab & Workspace Manager",
  "version": "1.0.0",
  "description": "Organize your browser tabs into workspaces for better productivity",
  "permissions": ["tabs", "storage", "identity", "alarms", "scripting"],
  "host_permissions": ["https://api.tabula.app/*"],
  "background": {
    "service_worker": "background.js",
    "type": "module"
  },
  "action": {
    "default_popup": "popup.html",
    "default_icon": {
      "16": "icons/icon-16.png",
      "32": "icons/icon-32.png",
      "48": "icons/icon-48.png",
      "128": "icons/icon-128.png"
    }
  },
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["content.js"],
      "run_at": "document_idle"
    }
  ],
  "icons": {
    "16": "icons/icon-16.png",
    "32": "icons/icon-32.png",
    "48": "icons/icon-48.png",
    "128": "icons/icon-128.png"
  }
}
```

### Required Permissions

| Permission  | Purpose                   | Justification                             |
| ----------- | ------------------------- | ----------------------------------------- |
| `tabs`      | Query and manipulate tabs | Core functionality for tab management     |
| `storage`   | Local and sync storage    | Offline data storage and user preferences |
| `identity`  | OAuth authentication      | User login via Google/WorkOS              |
| `alarms`    | Scheduled tasks           | Periodic sync and backup operations       |
| `scripting` | Execute scripts in tabs   | Tab suspension and restoration            |

### Background Service Worker Architecture

The background service worker is the core of the extension, handling:

**Responsibilities:**

- Tab lifecycle monitoring (created, updated, removed)
- Periodic sync with backend API (every 5 minutes)
- Tab suspension logic (after 30 minutes of inactivity)
- Message routing between components
- Alarm handling for scheduled tasks

**Implementation Pattern:**

```typescript
// background/index.ts
import { TabManager } from './tab-manager';
import { SyncEngine } from './sync-engine';
import { StorageManager } from './storage-manager';

// Initialize managers
const tabManager = new TabManager();
const syncEngine = new SyncEngine();
const storageManager = new StorageManager();

// Event listeners
chrome.tabs.onCreated.addListener((tab) => {
  tabManager.handleTabCreated(tab);
});

chrome.tabs.onRemoved.addListener((tabId) => {
  tabManager.handleTabRemoved(tabId);
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'sync') {
    syncEngine.performSync();
  }
});

// Message handler
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // Route messages to appropriate handlers
  switch (message.type) {
    case 'GET_WORKSPACES':
      storageManager.getWorkspaces().then(sendResponse);
      return true;
    case 'SAVE_WORKSPACE':
      storageManager.saveWorkspace(message.payload).then(sendResponse);
      return true;
    // ... other message types
  }
});
```

### Popup UI Component Hierarchy

The popup is built with React and displays the workspace management interface.

**Component Structure:**

```
<PopupApp>
  ├── <Header>
  │   ├── <UserProfile>
  │   └── <SyncStatus>
  ├── <WorkspaceList>
  │   └── <WorkspaceCard> (repeating)
  │       ├── <WorkspaceHeader>
  │       ├── <TabList>
  │       │   └── <TabItem> (repeating)
  │       └── <WorkspaceActions>
  ├── <CreateWorkspaceButton>
  └── <Footer>
      ├── <SettingsButton>
      └── <HelpButton>
```

**Popup Dimensions:**

- Width: 400px
- Height: 600px
- Minimum height: 400px
- Maximum height: 800px

**State Management:**

```typescript
// popup/state/workspace-store.ts
interface WorkspaceState {
  workspaces: Workspace[];
  activeWorkspaceId: string | null;
  isLoading: boolean;
  error: string | null;
}

// Using Zustand for state management
const useWorkspaceStore = create<WorkspaceState>((set) => ({
  workspaces: [],
  activeWorkspaceId: null,
  isLoading: false,
  error: null,
  // Actions
  setWorkspaces: (workspaces) => set({ workspaces }),
  setActiveWorkspace: (id) => set({ activeWorkspaceId: id }),
  // ... other actions
}));
```

### Content Script Injection Points

Content scripts are injected into all web pages for tab suspension functionality.

**Injection Configuration:**

- Run at: `document_idle` (after DOM ready)
- Matches: `<all_urls>`
- World: `ISOLATED` (default)

**Content Script Responsibilities:**

- Listen for suspension commands from background worker
- Freeze page state before suspension
- Restore page state after reactivation
- Communicate page metadata to background worker

**Implementation:**

```typescript
// content/index.ts
let isSuspended = false;

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'SUSPEND_TAB') {
    suspendTab();
    sendResponse({ success: true });
  } else if (message.type === 'RESUME_TAB') {
    resumeTab();
    sendResponse({ success: true });
  }
});

function suspendTab() {
  // Save scroll position
  const scrollPos = window.scrollY;
  chrome.storage.local.set({ [`scroll_${location.href}`]: scrollPos });

  // Set suspended flag
  isSuspended = true;

  // Notify background
  chrome.runtime.sendMessage({ type: 'TAB_SUSPENDED' });
}

function resumeTab() {
  // Restore scroll position
  chrome.storage.local.get([`scroll_${location.href}`], (result) => {
    if (result[`scroll_${location.href}`]) {
      window.scrollTo(0, result[`scroll_${location.href}`]);
    }
  });

  isSuspended = false;
}
```

### Message Passing Protocol

Communication between components uses a structured message format.

**Message Format:**

```typescript
interface Message {
  type: string; // Message type identifier
  payload?: any; // Optional data payload
  requestId?: string; // For request/response correlation
  timestamp: number; // Message timestamp
}
```

**Message Types:**

| Type               | Direction            | Purpose                 | Payload                |
| ------------------ | -------------------- | ----------------------- | ---------------------- |
| `GET_WORKSPACES`   | Popup → Background   | Fetch all workspaces    | None                   |
| `SAVE_WORKSPACE`   | Popup → Background   | Create/update workspace | `Workspace` object     |
| `DELETE_WORKSPACE` | Popup → Background   | Delete workspace        | `{ id: string }`       |
| `SWITCH_WORKSPACE` | Popup → Background   | Activate workspace      | `{ id: string }`       |
| `SUSPEND_TAB`      | Background → Content | Suspend tab             | None                   |
| `RESUME_TAB`       | Background → Content | Resume tab              | None                   |
| `TAB_SUSPENDED`    | Content → Background | Confirm suspension      | None                   |
| `SYNC_COMPLETE`    | Background → Popup   | Sync finished           | `{ success: boolean }` |

**Example Usage:**

```typescript
// Sending a message from popup to background
const response = await chrome.runtime.sendMessage({
  type: 'GET_WORKSPACES',
  timestamp: Date.now(),
});

// Handling in background worker
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'GET_WORKSPACES') {
    getWorkspaces().then(sendResponse);
    return true; // Keep channel open for async response
  }
});
```

### Local Storage Schema

The extension uses `chrome.storage.local` for offline data persistence.

**Storage Schema:**

```typescript
interface LocalStorage {
  // User data
  user: {
    id: string;
    email: string;
    name: string;
    tier: 'free' | 'pro' | 'team';
  };

  // Authentication
  auth: {
    accessToken: string;
    refreshToken: string;
    expiresAt: number;
  };

  // Workspaces (synced from backend)
  workspaces: {
    [id: string]: Workspace;
  };

  // Active workspace
  activeWorkspaceId: string;

  // Last sync timestamp
  lastSync: number;

  // Pending changes (offline queue)
  pendingChanges: Array<{
    type: 'create' | 'update' | 'delete';
    entity: 'workspace' | 'tab';
    data: any;
    timestamp: number;
  }>;
}

interface Workspace {
  id: string;
  name: string;
  description?: string;
  color?: string;
  icon?: string;
  tabs: Tab[];
  position: number;
  createdAt: number;
  updatedAt: number;
  settings: {
    autoSuspend: boolean;
    suspendAfterMinutes: number;
  };
}

interface Tab {
  id: string;
  workspaceId: string;
  url: string;
  title: string;
  faviconUrl?: string;
  position: number;
  isPinned: boolean;
  isSuspended: boolean;
  createdAt: number;
  updatedAt: number;
  metadata?: {
    lastAccessed?: number;
    accessCount?: number;
  };
}
```

**Storage Quotas:**

- `chrome.storage.local`: 10MB (Chrome default)
- `chrome.storage.sync`: 100KB (for user preferences only)

### Sync Storage for User Preferences

User preferences are stored in `chrome.storage.sync` to sync across devices.

**Sync Storage Schema:**

```typescript
interface SyncStorage {
  preferences: {
    theme: 'light' | 'dark' | 'auto';
    defaultSuspendTime: number; // minutes
    enableNotifications: boolean;
    syncEnabled: boolean;
    showFavicons: boolean;
    compactView: boolean;
  };
}
```

---

## API Specifications

### RESTful API Design Principles

The Tabula API follows REST conventions:

1. **Resources**: Nouns, not verbs (e.g., `/workspaces`, not `/getWorkspaces`)
2. **HTTP Methods**: Use appropriate verbs (GET, POST, PUT, DELETE)
3. **Stateless**: No server-side sessions (JWT for authentication)
4. **JSON**: All requests and responses use JSON
5. **Versioning**: URL-based versioning (`/api/v1/`)
6. **Idempotency**: PUT and DELETE are idempotent

### Authentication Flow

JWT-based authentication with access and refresh tokens.

**Registration Flow:**

```
1. Client: POST /api/v1/auth/signup
   Body: { email, password, name }

2. Server validates input and creates user
   - Hash password with bcrypt (cost: 12)
   - Insert into users table
   - Generate JWT access token (15 min expiry)
   - Generate JWT refresh token (7 day expiry)
   - Store refresh token hash in sessions table

3. Server response:
   {
     "user": { "id", "email", "name", "tier" },
     "accessToken": "eyJ...",
     "refreshToken": "eyJ...",
     "expiresAt": 1234567890
   }
```

**Login Flow:**

```
1. Client: POST /api/v1/auth/login
   Body: { email, password }

2. Server validates credentials
   - Lookup user by email
   - Compare password hash
   - Generate new tokens
   - Update last_login_at

3. Server response: Same as signup
```

**Token Refresh Flow:**

```
1. Client: POST /api/v1/auth/refresh
   Header: Authorization: Bearer <refreshToken>

2. Server validates refresh token
   - Verify JWT signature
   - Check token not expired
   - Check token hash in sessions table
   - Generate new access token
   - Rotate refresh token

3. Server response:
   {
     "accessToken": "eyJ...",
     "refreshToken": "eyJ...",
     "expiresAt": 1234567890
   }
```

**JWT Payload Structure:**

```json
{
  "sub": "user-uuid",
  "email": "user@example.com",
  "tier": "free",
  "iat": 1234567890,
  "exp": 1234567890
}
```

### Request/Response Format Standards

**Request Headers:**

```
Content-Type: application/json
Authorization: Bearer <accessToken>
User-Agent: Tabula Extension/1.0.0
```

**Successful Response Format:**

```json
{
  "data": {
    // Response data
  },
  "meta": {
    "timestamp": "2025-12-07T12:00:00Z",
    "version": "1.0"
  }
}
```

**Paginated Response Format:**

```json
{
  "data": [
    // Array of items
  ],
  "pagination": {
    "page": 1,
    "perPage": 20,
    "total": 100,
    "totalPages": 5,
    "hasNext": true,
    "hasPrev": false
  },
  "meta": {
    "timestamp": "2025-12-07T12:00:00Z"
  }
}
```

### Error Response Structure

All errors follow a consistent format for easier client-side handling.

**Error Response Format:**

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid request parameters",
    "details": [
      {
        "field": "email",
        "message": "Email is required"
      }
    ]
  },
  "meta": {
    "timestamp": "2025-12-07T12:00:00Z",
    "requestId": "req_abc123"
  }
}
```

**Error Codes:**

| HTTP Status | Error Code            | Description                               |
| ----------- | --------------------- | ----------------------------------------- |
| 400         | `VALIDATION_ERROR`    | Request validation failed                 |
| 400         | `INVALID_REQUEST`     | Malformed request                         |
| 401         | `UNAUTHORIZED`        | Missing or invalid authentication         |
| 401         | `TOKEN_EXPIRED`       | JWT token expired                         |
| 403         | `FORBIDDEN`           | Insufficient permissions                  |
| 404         | `NOT_FOUND`           | Resource not found                        |
| 409         | `CONFLICT`            | Resource conflict (e.g., duplicate email) |
| 429         | `RATE_LIMIT_EXCEEDED` | Too many requests                         |
| 500         | `INTERNAL_ERROR`      | Server error                              |
| 503         | `SERVICE_UNAVAILABLE` | Service temporarily unavailable           |

### Pagination Format

All list endpoints support pagination using query parameters.

**Query Parameters:**

- `page`: Page number (default: 1, min: 1)
- `perPage`: Items per page (default: 20, min: 1, max: 100)
- `sortBy`: Field to sort by (e.g., `createdAt`, `name`)
- `sortOrder`: Sort order (`asc` or `desc`, default: `desc`)

**Example Request:**

```
GET /api/v1/workspaces?page=2&perPage=10&sortBy=createdAt&sortOrder=desc
```

### Versioning Strategy

API versions are specified in the URL path.

**Version Format:** `/api/v{major}/`

**Current Version:** `v1`

**Versioning Rules:**

- Major version bump for breaking changes
- Backward compatibility within a major version
- Support N-1 versions (e.g., when v2 is released, v1 is still supported)
- Deprecation notices: 6 months before version removal

**Example:**

```
/api/v1/workspaces  (current)
/api/v2/workspaces  (future, breaking changes)
```

---

## Database Specifications

### PostgreSQL 16 on Neon

**Database Configuration:**

- **Version**: PostgreSQL 16
- **Provider**: Neon (neon.tech)
- **Region**: us-east-1 (configurable)
- **Compute**: Auto-scaling (0.25 - 2 CU)
- **Storage**: Auto-scaling (starts at 0.5 GB)
- **Autosuspend**: 5 minutes of inactivity
- **Connection Pooling**: PgBouncer (built-in)

### Complete Database Schema

See ARCHITECTURE.md for the complete schema. Key tables:

1. **users**: User accounts and authentication
2. **workspaces**: Workspace definitions
3. **tabs**: Individual tabs within workspaces
4. **backups**: Workspace snapshots for recovery
5. **sessions**: Active user sessions and refresh tokens
6. **teams**: Team accounts (Phase 4)
7. **team_members**: Team membership (Phase 4)

### Migration Strategy

**Migration Tool Options:**

1. **golang-migrate** (if using Go backend)
2. **Prisma Migrate** (if using Node.js backend)
3. **Custom SQL scripts** (manual migrations)

**Migration File Naming:**

```
migrations/
  000001_create_users_table.up.sql
  000001_create_users_table.down.sql
  000002_create_workspaces_table.up.sql
  000002_create_workspaces_table.down.sql
  ...
```

**Migration Best Practices:**

- Always provide both `up` and `down` migrations
- Test migrations on dev branch before production
- Never modify existing migrations (create new ones)
- Backup database before running migrations
- Use transactions for atomic changes

**Example Migration (golang-migrate):**

```sql
-- 000001_create_users_table.up.sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255),
  name VARCHAR(255),
  tier VARCHAR(20) DEFAULT 'free',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_login_at TIMESTAMP,
  preferences JSONB DEFAULT '{}'
);

CREATE INDEX idx_users_email ON users(email);

-- 000001_create_users_table.down.sql
DROP TABLE users;
```

### Indexing Strategy

Indexes are critical for query performance. All indexes are defined in migration files.

**Index Naming Convention:**

```
idx_{table}_{column(s)}
```

**Required Indexes:**

```sql
-- User lookup
CREATE INDEX idx_users_email ON users(email);

-- Workspace queries
CREATE INDEX idx_workspaces_user ON workspaces(user_id);
CREATE INDEX idx_workspaces_team ON workspaces(team_id);

-- Tab queries
CREATE INDEX idx_tabs_workspace ON tabs(workspace_id);
CREATE INDEX idx_tabs_position ON tabs(workspace_id, position);

-- Backup queries
CREATE INDEX idx_backups_user ON backups(user_id);
CREATE INDEX idx_backups_created ON backups(created_at);
CREATE INDEX idx_backups_workspace ON backups(workspace_id);

-- Session queries
CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_token ON sessions(refresh_token_hash);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);

-- Team queries (Phase 4)
CREATE INDEX idx_team_members_team ON team_members(team_id);
CREATE INDEX idx_team_members_user ON team_members(user_id);
```

### Connection Pooling Configuration

**PgBouncer Settings (via Neon):**

- **Pool Mode**: Transaction
- **Max Connections**: 100 (adjustable)
- **Default Pool Size**: 20
- **Reserve Pool Size**: 5
- **Max Client Connections**: 1000

**Application Connection String:**

```
postgresql://user:password@host:5432/database?sslmode=require&pool_timeout=10
```

**Connection Best Practices:**

- Use connection pooling in application code
- Set reasonable timeouts (10 seconds)
- Close connections after use
- Handle connection errors gracefully

---

## Caching Specifications

### Upstash Redis

**Configuration:**

- **Provider**: Upstash (upstash.com)
- **Region**: Global (edge caching)
- **Protocol**: REST API (HTTP-based)
- **TLS**: Enabled
- **Authentication**: Token-based

**Connection:**

```typescript
import { Redis } from '@upstash/redis';

const redis = new Redis({
  url: process.env.UPSTASH_REDIS_URL,
  token: process.env.UPSTASH_REDIS_TOKEN,
});
```

### Cache Key Naming Conventions

Consistent key naming ensures organized and collision-free caching.

**Key Format:**

```
{namespace}:{entity}:{identifier}:{field}
```

**Examples:**

```
session:user:abc123:data
sync:workspace:def456:state
rate:user:abc123:count
search:query:hello:results
```

**Namespaces:**

- `session:` - User session data
- `sync:` - Sync state
- `rate:` - Rate limiting counters
- `search:` - Search result cache
- `lock:` - Distributed locks

### TTL Policies Per Data Type

Different data types have different expiration requirements.

| Data Type           | TTL        | Justification                     |
| ------------------- | ---------- | --------------------------------- |
| User sessions       | 15 minutes | Match access token expiry         |
| Sync state          | 5 minutes  | Sync interval                     |
| Rate limit counters | 60 seconds | Rate limit window                 |
| Search results      | 5 minutes  | Balance freshness and performance |
| Distributed locks   | 30 seconds | Prevent deadlocks                 |
| Workspace metadata  | 10 minutes | Reduce DB queries                 |

**Example:**

```typescript
// Cache user session
await redis.set(
  `session:user:${userId}:data`,
  JSON.stringify(sessionData),
  { ex: 900 } // 15 minutes
);

// Cache search results
await redis.set(
  `search:query:${query}:results`,
  JSON.stringify(results),
  { ex: 300 } // 5 minutes
);
```

### Cache Invalidation Strategies

**Strategies:**

1. **Time-based (TTL)**: Automatic expiration (preferred)
2. **Event-based**: Invalidate on data changes
3. **Manual**: Explicit delete operations

**Invalidation Patterns:**

**On Workspace Update:**

```typescript
// Delete workspace cache
await redis.del(`workspace:${workspaceId}:data`);

// Delete user's workspace list cache
await redis.del(`user:${userId}:workspaces`);

// Update sync state
await redis.set(`sync:workspace:${workspaceId}:state`, 'updated');
```

**On User Logout:**

```typescript
// Delete all user sessions
await redis.del(`session:user:${userId}:data`);
await redis.del(`session:user:${userId}:prefs`);
```

**Cache-Aside Pattern:**

```typescript
async function getWorkspace(id: string): Promise<Workspace> {
  // Try cache first
  const cached = await redis.get(`workspace:${id}:data`);
  if (cached) {
    return JSON.parse(cached);
  }

  // Cache miss: fetch from DB
  const workspace = await db.workspaces.findById(id);

  // Update cache
  await redis.set(
    `workspace:${id}:data`,
    JSON.stringify(workspace),
    { ex: 600 } // 10 minutes
  );

  return workspace;
}
```

---

## Deployment Specifications

### Cloud Run Configuration

**Service Configuration:**

```yaml
service: tabula-api
region: us-central1

container:
  image: gcr.io/PROJECT_ID/tabula-api:latest
  port: 8080

resources:
  limits:
    cpu: 1
    memory: 512Mi

scaling:
  minInstances: 0
  maxInstances: 100
  concurrency: 80

timeout: 60s

env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: DATABASE_URL
        key: latest
  - name: JWT_SECRET
    valueFrom:
      secretKeyRef:
        name: JWT_SECRET
        key: latest
```

### Environment Variables

**Required Variables:**

- `DATABASE_URL`: Neon PostgreSQL connection string
- `JWT_SECRET`: Secret for JWT signing
- `UPSTASH_REDIS_URL`: Upstash Redis REST URL
- `UPSTASH_REDIS_TOKEN`: Upstash authentication token
- `CORS_ORIGINS`: Allowed CORS origins (comma-separated)
- `NODE_ENV` or `GO_ENV`: Environment (development, staging, production)

**Optional Variables:**

- `LOG_LEVEL`: Logging level (debug, info, warn, error)
- `RATE_LIMIT_MAX`: Max requests per window
- `RATE_LIMIT_WINDOW`: Rate limit window in seconds

---

## Revision History

- **2025-12-07**: Initial specifications document created (v1.0)

---

_This document is reviewed quarterly and updated as specifications evolve. Next review: 2025-03-07_
