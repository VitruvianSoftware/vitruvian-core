# Tabula Requirements Specification

## 1. Product Vision

Tabula aims to be the most efficient, **privacy-conscious**, and cost-effective browser tab
management solution. It empowers users to organize their digital workspace without feature bloat or
compromising on performance, filling the gap between simple tab suspenders and heavy enterprise
workspace tools like Workona.

## 2. Core Capabilities & Status

This section outlines the high-level capabilities. Status is tracked as:

- `[x] Verified`: Manually verified in latest QA cycle.
- `[/] Implemented`: Exists in code but not fully verified.
- `[ ] Planned`: Roadmap item.

### 2.1 Workspace Management

| ID       | Requirement                                                                        | Status | Verification Note                |
| -------- | ---------------------------------------------------------------------------------- | ------ | -------------------------------- |
| **WM-1** | **Create Workspace**: Users can create named workspaces with custom icons/colors.  | `[x]`  | Verified (2025-12-23)            |
| **WM-2** | **Rename Workspace**: Users can rename existing workspaces.                        | `[x]`  | Verified. Persists after reload. |
| **WM-3** | **Delete Workspace**: Users can delete workspaces (hiding them from UI).           | `[x]`  | Verified.                        |
| **WM-4** | **Archive Workspace**: Users can archive workspaces to hide them without deletion. | `[ ]`  | Planned (Roadmap Phase 2)        |
| **WM-5** | **Sections**: Organize workspaces into sections.                                   | `[x]`  | Verified.                        |

### 2.2 Tab Management

| ID       | Requirement                                                             | Status | Verification Note                               |
| -------- | ----------------------------------------------------------------------- | ------ | ----------------------------------------------- |
| **TM-1** | **Save Tabs**: Save current window's tabs to active workspace.          | `[/]`  | Implemented in `WorkspaceService`.              |
| **TM-2** | **Restore Tabs**: Open saved tabs from a workspace.                     | `[/]`  | Implemented in `WorkspaceService`.              |
| **TM-3** | **Tab Suspension**: Automatically discard inactive tabs to free memory. | `[/]`  | `TabService.suspendInactiveTabs` exists.        |
| **TM-4** | **Reorder Tabs**: Drag-and-drop tabs within workspace.                  | `[ ]`  | Pending UI verification.                        |
| **TM-5** | **Context Menus**: Right-click to move tabs.                            | `[ ]`  | Not implemented (Missing in background script). |

### 2.3 Resource Management

| ID       | Requirement                                                        | Status | Verification Note |
| -------- | ------------------------------------------------------------------ | ------ | ----------------- |
| **RM-1** | **Add Resource**: Save arbitrary URLs as resources in a workspace. | `[x]`  | Verified.         |
| **RM-2** | **Sections**: Organize resources into named sections.              | `[x]`  | Verified.         |

### 2.4 Sync & Storage

| ID       | Requirement                                                  | Status | Verification Note                         |
| -------- | ------------------------------------------------------------ | ------ | ----------------------------------------- |
| **SS-1** | **Local Storage**: Data persists locally for offline access. | `[x]`  | Verified (Chrome Storage).                |
| **SS-2** | **Cloud Sync**: Sync data across devices when logged in.     | `[x]`  | E2E-verified two-device convergence (`sync-convergence.spec.ts`, #136). |
| **SS-3** | **Conflict Resolution**: Last-write-wins strategy.           | `[x]`  | Hybrid: server version-locking + client LWW; documented in [`conflict-resolution.md`](../architecture/conflict-resolution.md); E2E-verified (#136). |

---

## 3. Detailed Functional Requirements

### 3.1 Extension UI

- **REQ-UI-01**: Extension must provide a "Dashboard" view (`dashboard.html`) as the main interface.
- **REQ-UI-02**: Extension popup must provide quick access to active workspace and "Quick Save"
  button.
- **REQ-UI-03**: UI must visually indicate the active workspace.

### 3.2 Authentication

- **REQ-AUTH-01**: Users must be able to sign up/login via Email & Password.
- **REQ-AUTH-02**: Authentication state must persist across browser restarts.

### 3.3 Performance

- **REQ-PERF-01**: Tab suspension must reduce memory footprint by discarding DOM.
- **REQ-PERF-02**: Extension must load dashboard in < 200ms.

---

## 4. Roadmap Summary

### Phase 1: MVP (Current)

- Core Workspace & Tab Management.
- Basic Local Storage.
- Simple Authentication.

### Phase 2: Sync & History (Next)

- Real-time Cross-Device Sync.
- Session Backups (30-day history).
- Universal Search.

### Phase 3: Integrations

- Cloud Document Links (Google Drive, Notion).
- Workspace Templates.

### Phase 4: Team & Enterprise

- Shared Workspaces.
- SSO & Admin Controls.

---

_Verified Journeys tracked in: `[Verified Journeys Log](./verified_journeys.md)`._
