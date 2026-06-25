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

_None._ Every consumer currently matches its canonical version — there are **no active pins** in [`tools/conformance/version-pins.tsv`](../../tools/conformance/version-pins.tsv), and `bazel run //tools/conformance:check` is green with zero pins.

> **Retired — `tabula/api/Dockerfile` (Node 20), removed 2026-06-25.** This was the seed exception. On review it turned out to be **vestigial**: tabula's API image is built by Bazel (`//tabula/api:image`, a `node_image`) whose Node version is bound to `.nvmrc` through the toolchain (`node_version_from_nvmrc`), so the standalone `node:20` Dockerfile was a pre-Bazel leftover that nothing built. It was **deleted** rather than bumped — the real build was already on canonical Node. The general lesson is below.

---

## Preventing this class of exception

The cleanest way to avoid a hardcoded-version drift is to **not hardcode the version in the Dockerfile** — source it from the canonical file instead. The repo has two build paths, both of which can do this:

- **Bazel-built images** (`node_image`, e.g. `//tabula/api:image`, `//tabula/web`) already get their Node version from `.nvmrc` via the toolchain (`node.toolchain(node_version_from_nvmrc = "//:.nvmrc")` in `MODULE.bazel`). Nothing to pin — bump `.nvmrc` and every Bazel image follows. This is why tabula's Dockerfile was dead weight.
- **Dockerfile-built images** (e.g. `oauth-user-inspector`) parameterize the major via a build arg instead of hardcoding it:

  ```dockerfile
  # NODE_VERSION defaults to the repo canonical (.nvmrc major); CI passes it explicitly.
  ARG NODE_VERSION=22
  FROM node:${NODE_VERSION}-slim AS build
  ...
  ```

  The deploy workflow passes `--build-arg NODE_VERSION="$(cut -d. -f1 .nvmrc)"`, so CI builds always track `.nvmrc`. The conformance check resolves the `ARG NODE_VERSION` default and still enforces it equals canonical, so even the local-build default can't silently drift.

A genuine exception (an app that truly cannot run on canonical yet) is then an explicit, tracked deviation — an overridden build arg plus a registry row — not an invisible hardcoded `FROM node:<major>`.

---

## Adding an exception

1. Add a row to [`tools/conformance/version-pins.tsv`](../../tools/conformance/version-pins.tsv): `file`, `tool`, `pinned_value`, `review_by` (YYYY-MM-DD), `owner`, `reason`.
2. Add a matching entry to **Current exceptions** above — the _why_, the risk, and the removal criteria. The conformance check fails if a registry pin isn't documented here.
3. Keep `review_by` short (weeks to a few months). An exception is a temporary state with a plan to exit, not a resting place — when it expires, the check fails until you re-justify (with a fresh, shorter horizon) or remove it.

## Removing an exception

When the constraint clears, align the file to canonical, then delete **both** the `version-pins.tsv` row and the entry here. The conformance check will refuse to pass while either half is stale.
