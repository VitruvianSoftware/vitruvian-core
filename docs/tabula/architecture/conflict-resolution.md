# Conflict Resolution & Cross-Device Convergence

How two installs ("devices") of Tabula converge on a shared backend. This is
the contract the sharing layer (#139), the web companion (#140), and
session-history depth build on, so it is documented precisely here and verified
end-to-end (`tabula/extension/tests/sync-convergence.spec.ts`, #136).

> Scope note: this describes **single-user, multi-device** convergence. Multi-
> **user** real-time co-editing (operational transforms / CRDTs) is M4 and out
> of scope; see "Known limits" below.

## Model: server optimistic locking + client last-write-wins

Conflict handling is a **hybrid** of two cooperating mechanisms, not pure LWW:

1. **Server — version-based optimistic locking.** Every `Workspace` and
   `SpaceGroup` row carries an integer `version` (`prisma/schema.prisma`). A
   client PUT includes the `baseVersion` it edited from
   (`WorkspaceUpdateSchema`). The service locks the row
   (`SELECT version ... FOR UPDATE`) and, if `baseVersion < currentVersion`,
   rejects with **409 Conflict** plus the server's current copy
   (`workspace.service.ts`, `spacegroup.service.ts`). A successful write
   increments `version`. This makes concurrent writes *serializable*: exactly
   one wins per round; the loser is told and must reconcile.

2. **Client — last-write-wins reconciliation keyed on `updatedAt`.** The
   extension is local-first (`chrome.storage` is the UI source of truth). On
   pull (`WorkspaceService.getAllWorkspaces`) it merges remote into local: for
   each entity, the copy with the newer `updatedAt` wins, **except** an entity
   with un-acked local edits queued in the sync queue always keeps its local
   content (`SyncService.getPendingSaveIds`) — the queued PUT will converge the
   server. On a **409**, the client compares `updatedAt`: if local is newer it
   adopts the server's `version` and **retries** (its newer content wins); if
   the server is newer it **adopts** the server copy and drops the stale write
   (`SyncService`).

Together these guarantee **convergence with no split-brain**: after activity
settles, both devices hold the identical winning state, and the **later writer
wins predictably**.

## Granularity: per-workspace

Resources, notes, tasks, sections, and tabs live **inside** the workspace JSON;
they are not independently versioned entities. Conflict resolution therefore
operates at **workspace granularity**. Two devices editing *different*
workspaces never conflict (both survive). Two devices editing the *same*
workspace concurrently resolve as a single whole-workspace write — the later
writer's entire workspace wins, so a concurrent edit to a *different field* of
the same workspace by the losing device can be overwritten.

This is **predictable, not silent**: it is the documented behavior, the loser
receives a 409 (never a silent drop), and several mechanisms keep the
concurrent-same-workspace window small in practice (below). Field-level merge
(CRDT) is future work tracked with M4 real-time collaboration.

## Supporting mechanisms

- **Real-time propagation (SSE).** REST writes publish a `sync` event over
  Redis pub/sub (`sync:updates:<userId>`); other devices' open dashboards
  receive it via `GET /sync/stream` and re-pull (`SyncService` SSE,
  echo-suppressed by `deviceId`). This shrinks the concurrent-edit window to
  ~real-time rather than the 5-minute periodic fallback.
- **Advisory active-device lease.** `activeDeviceId` / `activeDeviceSeenAt` mark
  which device is live-syncing a workspace's *tabs*. A device whose lease is
  stale (> 2 min) for another device pauses automatic tab capture rather than
  fighting write-for-write (`useTabSync`). Advisory only — it never blocks data
  edits.
- **Tombstones.** A deleted entity is tombstoned in Redis for 30 days
  (`lib/tombstones.ts`); a stale offline snapshot cannot resurrect it (PUT →
  410 Gone).
- **Durable offline queue.** Edits are enqueued to `chrome.storage` and drained
  with exponential backoff when online (`SyncService`); offline edits converge
  on reconnect.

## Convergence guarantees (verified)

`tabula/extension/tests/sync-convergence.spec.ts` exercises device A (the
extension) against device B (direct authenticated API calls with a distinct
`x-device-id`) on the live backend and asserts:

1. A local create on device A reaches the backend.
2. A backend edit by device B converges into device A (pull + merge).
3. The later write wins predictably across devices (workspace-granularity LWW),
   and both ends converge to that single winner — no split-brain.
4. Device B's edits to a resource, a note, and a task converge into device A.

## Known limits (intentional, tracked)

- **No field-level merge for concurrent same-workspace edits** — last whole-
  workspace writer wins (above). CRDT/field-merge is M4.
- **SSE is page-context only** — MV3 service workers have no `EventSource`, so
  real-time pull requires an open dashboard; closed-dashboard devices rely on
  the periodic/next-open pull.

## See also

- [`sync-strategy.md`](sync-strategy.md) — queueing, retry/backoff, SSE, backup.
- [`adr/006-realtime-engine-evaluation.md`](adr/006-realtime-engine-evaluation.md)
- `tabula/extension/src/services/sync.ts`, `.../services/workspace.ts`
- `tabula/api/src/services/workspace.service.ts`, `.../routes/workspace.routes.ts`
