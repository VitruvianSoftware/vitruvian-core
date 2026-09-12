# Sharing & Permissions

How a private Tabula space ("workspace") becomes shareable, and how the backend
enforces who may read or write it (#139). This is the load-bearing layer the web
companion (#140) and M4 real-time collaboration build on; it is **additive** and
does not change single-user behavior.

> Scope note: #139 is the **server-side** model — the ACL, the share-grant API,
> and authorization enforcement. Real-time propagation to collaborators and live
> presence are M4 (see "Known limits").

## Roles: OWNER > EDIT > VIEW

Three roles, total-ordered. **OWNER is implicit** — it is `Workspace.userId`,
never a collaborator row, so the owner relationship stays immutable and a space
always has exactly one owner. **EDIT** and **VIEW** come from an active
`SpaceCollaborator` grant (or an accepted `ShareLink`, which materializes a
collaborator). Reads require VIEW+, writes require EDIT+, and share/collaborator
management requires OWNER.

## The chokepoint: `PermissionService`

Every space authorization resolves through one place
(`services/permission.service.ts`) instead of the old scattered
`WHERE userId = X` owner filter:

- `resolveAccess(userId, workspaceId)` → `'owner' | 'edit' | 'view' | null`.
  Owner short-circuits (a single workspace lookup), else an active
  `SpaceCollaborator` row, else `null`.
- `requireRole(userId, workspaceId, min)` throws **`NotFoundError` (404)** when
  the caller has _no_ access — deliberately indistinguishable from "does not
  exist" so existence is not leaked to strangers — and **`ForbiddenError` (403)**
  when the caller can see the space but the role is below `min` (e.g. a VIEW
  collaborator attempting a write).
- `listAccessUserIds(workspaceId)` → owner + active collaborators; the recipient
  set M4 fan-out and presence will use.

All workspace reads/writes (`getWorkspaceById`, `updateWorkspace`,
`deleteWorkspace`, `saveTabsToWorkspace`, tab move/reorder/bulk) call
`requireRole` at the right level. `updateWorkspace`'s `FOR UPDATE` lock keys on
`id` alone (authorization already checked), so an EDIT collaborator who does not
own the row is still allowed through. `deleteWorkspace` requires OWNER;
`moveTab` requires OWNER of the _source_ for a cross-space move so a collaborator
cannot relocate a tab out of a space shared with them. The advisory active-device
lease is owner-only, so a collaborator cannot steal the owner's live tab session
via a client-controlled `x-device-id`.

## Share-grant API

**By email** (`SpaceCollaborator`, owner-only management):

| Method   | Path                                 | Role                            |
| -------- | ------------------------------------ | ------------------------------- |
| `GET`    | `/workspaces/shared-with-me`         | any (lists the caller's grants) |
| `GET`    | `/workspaces/:id/collaborators`      | OWNER                           |
| `POST`   | `/workspaces/:id/collaborators`      | OWNER                           |
| `PATCH`  | `/workspaces/:id/collaborators/:cid` | OWNER                           |
| `DELETE` | `/workspaces/:id/collaborators/:cid` | OWNER                           |

A grant is keyed on the lowercased invitee email, so re-inviting updates the
role; an invite to an unregistered email persists as `pending` until that user
exists. The roster is **owner-only** (a VIEW grantee cannot harvest other
invitees' emails), and the share-by-email response **never reflects
active/pending**, which would reveal whether an email belongs to a registered
user (an enumeration oracle).

**By link** (`ShareLink`, multiple per space, each at a role, individually
revocable):

| Method   | Path                               | Role          |
| -------- | ---------------------------------- | ------------- |
| `GET`    | `/workspaces/:id/share-links`      | OWNER         |
| `POST`   | `/workspaces/:id/share-links`      | OWNER         |
| `DELETE` | `/workspaces/:id/share-links/:lid` | OWNER         |
| `POST`   | `/share-links/info`                | any (preview) |
| `POST`   | `/share-links/accept`              | any (redeem)  |

A link's token is **256 bits of entropy returned exactly once**; only its
SHA-256 hash is stored, so a database read never yields a usable token (mirrors
`lib/auth` refresh-token hashing). The token is carried in the request **body,
not the URL**, so it does not leak into access/proxy logs or `Referer`.
`/accept` materializes a collaborator for the caller — idempotent, never
downgrades an existing higher grant, owner-accept is a no-op. Unknown, revoked,
and expired tokens all return an **identical 404** (no oracle distinguishing
them).

## Known limits (intentional, tracked)

- **Sync engine + backups stay owner-scoped.** `/sync/push` and `BackupService`
  keep their `userId` predicates, so they **fail closed** for collaborators
  (no hole). Collaborator writes flow through the secured REST path; collaborator
  sync-push and backup of shared spaces are deferred to M4.
- **No real-time fan-out to collaborators.** A collaborator's REST edit
  publishes only to the actor's sync channel; the owner and other collaborators
  converge on next pull. Cross-user channel scoping is M4 (the Redis sync keys
  are per-`userId` by design — see [`conflict-resolution.md`](conflict-resolution.md)).
- **Presence is groundwork only.** `lib/presence.ts` fixes the Redis key
  convention (`presence:workspace:<id>`) for M4; no live presence endpoint ships.
- **Owner deletion cascades shared spaces.** Deleting the owner user cascades the
  workspace and its grants/links (a deliberate v1 data-loss decision; transfer-
  ownership / soft-delete is a future issue).

## See also

- `services/permission.service.ts`, `services/collaborator.service.ts`,
  `services/share.service.ts`, `routes/sharing.routes.ts`
- [`conflict-resolution.md`](conflict-resolution.md) — the sync engine this
  layers on.
