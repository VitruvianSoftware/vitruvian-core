# API Reference

Technical reference for the Tabula API endpoints.

## Base URL

- **Local**: `http://localhost:8080`
- **Production**: `https://api.tabula.dev`

## Authentication

All protected endpoints require a Bearer token:

```
Authorization: Bearer <JWT_TOKEN>
```

Tokens are obtained via OAuth flow through WorkOS.

---

## Workspaces

### GET /api/v1/workspaces

List all workspaces for the authenticated user.

**Response:**

```json
{
  "data": [
    {
      "id": "ws_123",
      "name": "My Workspace",
      "color": "#6366f1",
      "position": 0,
      "sections": [...],
      "tabs": [...],
      "resources": [...],
      "notes": [...],
      "createdAt": "2024-01-01T00:00:00Z",
      "updatedAt": "2024-01-01T00:00:00Z"
    }
  ]
}
```

### PUT /api/v1/workspaces/:id

Create or update a workspace (upsert).

**Body:**

```json
{
  "name": "Workspace Name",
  "color": "#6366f1",
  "position": 0,
  "sections": [...],
  "tabs": [...],
  "resources": [...],
  "notes": [...]
}
```

### DELETE /api/v1/workspaces/:id

Delete a workspace.

---

## Backups

### GET /api/v1/backups

List all backups for the authenticated user.

**Query Parameters:**

- `workspaceId` (optional): Filter by workspace

**Response:**

```json
{
  "data": [
    {
      "id": "uuid",
      "workspaceId": "ws_123",
      "createdAt": "2024-01-01T00:00:00Z",
      "sizeBytes": 1024,
      "snapshot": {...}
    }
  ]
}
```

### POST /api/v1/backups

Create a new backup.

**Body:**

```json
{
  "workspaceId": "ws_123",
  "snapshot": {
    "workspaces": [...],
    "activeWorkspaceId": "ws_123"
  }
}
```

### GET /api/v1/backups/:id

Get a specific backup with full snapshot.

### DELETE /api/v1/backups/:id

Delete a backup.

---

## Sync (SSE)

### GET /api/v1/sync/subscribe

Subscribe to real-time updates via Server-Sent Events.

**Events:**

- `workspace_updated`: Workspace was modified
- `workspace_deleted`: Workspace was deleted
- `backup_created`: New backup created
- `connected`: Initial connection established
- `heartbeat`: Keep-alive ping

**Example:**

```javascript
const eventSource = new EventSource('/api/v1/sync/subscribe', {
  headers: { Authorization: `Bearer ${token}` },
});

eventSource.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log(data.type, data.payload);
};
```

---

## Health

### GET /health

Health check endpoint (no auth required).

**Response:**

```json
{
  "status": "ok",
  "timestamp": "2024-01-01T00:00:00Z"
}
```
