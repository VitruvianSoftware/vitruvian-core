# ADR-006: Real-time Sync Engine Evaluation

**Status:** Evaluated (Rejected for Migration, Monitored for Future) **Date:** 2026-01-09
**Deciders:** Tabula Core Team

## Context

Tabula's current architecture utilizes a "Local-First" synchronization strategy involving:

- **Client:** `chrome.storage` as the primary source of truth.
- **Transport:** Custom Queue-based synchronization via REST/SSE.
- **Backend:** Node.js/Fastify + Neon (Postgres) + Upstash (Redis).
- **Conflict Resolution:** Client-side "Last-Modified-Wins" logic.

As the complexity of the custom generic sync engine grows (handling race conditions, offline queues,
optimistic UI), the team evaluated **Convex** as a potential replacement for the entire backend and
sync layer.

## Decision

We will **persist with the current custom stack** (Node.js/Fastify/Postgres) and **NOT** migrate to
Convex at this time.

## Rationale

While Convex offers significant ease-of-use benefits, the architectural mismatch with our
"Local-First" extension requirement is too high.

1.  **Offline-First vs. Cloud-First:**
    - Tabula is architected as **Local-First**: The extension must work fully offline using
      `chrome.storage.local` as the synchronous source of truth for the UI.
    - Convex is **Cloud-First**: It relies on a WebSocket connection to the Convex backend. While it
      has optimistic updates, retrofitting it to treat `chrome.storage` as the primary truth while
      managing its own cache would introduce significant complexity, negating the "zero-boilerplate"
      advantage.

2.  **Data Sovereignty & Portability:**
    - The current stack uses standard **PostgreSQL** (Neon). This ensures we can migrate to any
      Postgres provider (AWS RDS, Supabase, self-hosted) without code changes.
    - Convex uses a proprietary document-relational database. Migrating away from Convex would
      require a complete rewrite of the data layer.

3.  **Migration Cost:**
    - The sync strategy, while complex, is already specified and implemented. A migration now would
      essentially be a restart of the backend codebase.

## Alternatives Considered

### Convex

**Pros:**

- **Zero "Sync" Code:** Handles real-time subscriptions, optimistic updates, and conflict resolution
  automatically.
- **Type Safety:** End-to-end type safety without an ORM.
- **Infrastructure:** Serverless and scales to zero (matches our goals).
- **Maintenance:** Would allow deleting ~40% of our backend code (SyncService, Redis management, SSE
  logic).

**Cons:**

- **Proprietary Lock-in:** Custom database query language and hosting.
- **Chrome Extension Friction:** Designed for standard React web apps; integration with Manifest V3
  Service Workers and `chrome.storage` is less proven.
- **Loss of SQL:** Cannot leverage standard SQL tools or Postgres extensions.

## Future Re-evaluation Triggers

We will re-evaluate this decision if:

1.  **Sync Complexity Becomes Unmanageable:** If the custom sync engine experiences frequent race
    conditions or bugs that consume >20% of engineering time.
2.  **Offline Requiremens Relax:** If the product direction shifts to allow "Cloud-Only" capability
    where offline access is read-only.
3.  **Convex Extension Support:** If Convex releases first-class support for "Local-First"
    architectures or specific Chrome Extension adapters.
