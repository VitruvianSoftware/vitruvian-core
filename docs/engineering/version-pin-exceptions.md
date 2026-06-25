# Version-Pin Exceptions

Tracks every application/file that deviates from the repo's **canonical version** for a tool, and **why** — read alongside the policy in
[Application Development Principles §2.12 — One canonical version; pins are temporary](application-development-principles.md#212-one-canonical-version-pins-are-temporary).

**Policy recap.** The repo runs one canonical (latest) version per tool, declared once in its source-of-truth: `.bazelversion` (Bazel), `go.work` (Go),
`.nvmrc` (Node), the root `packageManager` (pnpm). Everything else — every `go.mod`, every Dockerfile `FROM node:`, every app's `packageManager` —
must match it. A deviation is allowed only as a **deliberate, temporary, justified** exception.

Each exception lives in two places, kept in sync by the conformance check:

- **`tools/conformance/version-pins.tsv`** — the **authoritative, machine-readable** registry the gate reads (`file`, `tool`, `pinned_value`, `review_by`, `owner`, `reason`).
- **this document** — the human-readable record of the _why_, the risk, and the removal plan.

`bazel run //tools/conformance:check` (CI gate **Conformance Check**) fails on: any undeclared drift; a pin whose file has caught up to canonical (delete it);
a pin past its `review_by`; and a registry pin that is **not documented in this file**. So an exception cannot be added silently, held forever, or left undocumented.

---

## Current exceptions

| Application / file | Tool | Pinned | Canonical | Owner | Review by | Tracking |
|---|---|:---:|:---:|---|:---:|---|
| [`tabula/api/Dockerfile`](../../tabula/api/Dockerfile) | Node | **20** | 22 (`.nvmrc`) | @james | 2026-09-30 | _(issue: tbd)_ |

### `tabula/api/Dockerfile` — Node 20 (canonical 22)

- **Why.** The tabula API container has not yet been validated to build and run on Node 22; the rest of the repo (and `.nvmrc`) is on 22. Its Dockerfile still bases on `node:20-slim`.
- **Why not just bump it.** Bumping a container base "blind" is exactly the class of failure that broke the oauth-user-inspector deploy (a Node/pnpm mismatch that built locally but failed in CI — see the lesson in §3.4 of the [alignment gaps](application-alignment-gaps.md)). tabula is the repo's most-deployed app, so its base image bump must be verified, not assumed.
- **Removal criteria.** Build + smoke-test `tabula/api` on `node:22-slim`; if green, change both `FROM node:20-slim` lines to `node:22-slim`, then delete this entry **and** the matching `version-pins.tsv` row. (If you align the Dockerfile but forget the row, the check fails it as a _stale pin_ — forcing the cleanup.)
- **Owner / review.** @james, by 2026-09-30.

---

## Adding an exception

1. Add a row to [`tools/conformance/version-pins.tsv`](../../tools/conformance/version-pins.tsv): `file`, `tool`, `pinned_value`, `review_by` (YYYY-MM-DD), `owner`, `reason`.
2. Add a matching entry to **Current exceptions** above — the _why_, the risk, and the removal criteria. The conformance check fails if a registry pin isn't documented here.
3. Keep `review_by` short (weeks to a few months). An exception is a temporary state with a plan to exit, not a resting place — when it expires, the check fails until you re-justify (with a fresh, shorter horizon) or remove it.

## Removing an exception

When the constraint clears, align the file to canonical, then delete **both** the `version-pins.tsv` row and the entry here. The conformance check will refuse to pass while either half is stale.
