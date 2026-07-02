# GCP Identity Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin each Pulumi/GCP infrastructure unit to a specific Google account via a committed, readable map that the Bazel wrappers auto-apply at run time — so GCP auth never depends on the ambient `gcloud` account.

**Architecture:** A whitespace-table map (`infrastructure/gcp-identities.tsv`) is the single source of truth. A tiny `awk` resolver (`tools/pulumi/resolve_identity.sh`) turns a project dir into `account<TAB>project`. The existing wrapper (`tools/pulumi/pulumi_cmd.sh`) calls the resolver and, when an account is declared, injects a freshly-minted `GOOGLE_OAUTH_ACCESS_TOKEN` before exec'ing pulumi, failing fast if that account isn't logged in. An `AGENTS.md` pointer makes it discoverable.

**Tech Stack:** Bash, `awk`, `gcloud` CLI, Bazel (`rules_shell` `sh_test`), Pulumi.

**Spec:** `docs/superpowers/specs/2026-06-01-gcp-identity-map-design.md`

**Branch:** `feat/gcp-identity-map` (the spec is already committed here).

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `tools/pulumi/resolve_identity.sh` | Pure lookup: `(map, dir) → account<TAB>project` or nothing | Create |
| `tools/pulumi/resolve_identity_test.sh` | Unit tests for the resolver | Create |
| `tools/pulumi/BUILD` | Register the `sh_test` | Modify |
| `infrastructure/gcp-identities.tsv` | The identity map (source of truth) | Create |
| `tools/pulumi/pulumi_cmd.sh` | Resolve + inject the token before running pulumi | Modify |
| `AGENTS.md` | Discoverability pointer for agents | Create |
| `~/.claude/.../memory/lab-gmail-gcp-identity.md` (+ `MEMORY.md`) | Generalize Claude memory to point at the map (local, not committed) | Modify |

---

## Task 1: Identity resolver + unit test (TDD)

**Files:**
- Create: `tools/pulumi/resolve_identity.sh`
- Test: `tools/pulumi/resolve_identity_test.sh`
- Modify: `tools/pulumi/BUILD`

- [ ] **Step 1: Write the failing test**

Create `tools/pulumi/resolve_identity_test.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for resolve_identity.sh. The resolver path is passed as $1 (via the
# sh_test `args` + `$(location)`); under `bazel test` the CWD is the runfiles
# root, so that relative path resolves.
set -euo pipefail

RESOLVER="${1:?resolver path must be passed as the first arg}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
map="$tmp/map.tsv"

cat >"$map" <<'MAP'
# comment — should be ignored
#
infrastructure/pulumi/accounts/personal    james.nguyen@gmail.com   personal-llc   Personal Cloud Run + DNS
-    james@abrial.ai   -   abrial future (reference only)
MAP

fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Known dir → "account<TAB>project" (purpose column has spaces; must not leak)
got="$(bash "$RESOLVER" "$map" "infrastructure/pulumi/accounts/personal")"
want="$(printf 'james.nguyen@gmail.com\tpersonal-llc')"
[ "$got" = "$want" ] || fail "known dir: got [$got] want [$want]"

# 2. Unknown dir → empty
got="$(bash "$RESOLVER" "$map" "infrastructure/pulumi/platform/repo_config")"
[ -z "$got" ] || fail "unknown dir should be empty, got [$got]"

# 3. The "-" reference placeholder is never matched
got="$(bash "$RESOLVER" "$map" "-")"
[ -z "$got" ] || fail "'-' placeholder should never match, got [$got]"

# 4. Missing map file → empty, exit 0
got="$(bash "$RESOLVER" "$tmp/nope.tsv" "infrastructure/pulumi/accounts/personal")"
[ -z "$got" ] || fail "missing map should be empty, got [$got]"

echo "PASS: resolve_identity.sh"
```

- [ ] **Step 2: Create a stub resolver so the test target builds**

Create `tools/pulumi/resolve_identity.sh` (stub — intentionally returns nothing):

```bash
#!/usr/bin/env bash
set -euo pipefail
exit 0
```

Make both scripts executable:

```bash
chmod +x tools/pulumi/resolve_identity.sh tools/pulumi/resolve_identity_test.sh
```

- [ ] **Step 3: Register the `sh_test` in `tools/pulumi/BUILD`**

Add this load near the top of `tools/pulumi/BUILD` (after the existing `load(...)` on line 15):

```python
load("@rules_shell//shell:sh_test.bzl", "sh_test")
```

Add this target at the end of `tools/pulumi/BUILD`:

```python
# Unit tests for the GCP identity resolver. The resolver is passed to the test
# as an arg via $(location) so it works under `bazel test` without runfiles glue.
sh_test(
    name = "resolve_identity_test",
    srcs = ["resolve_identity_test.sh"],
    data = ["resolve_identity.sh"],
    args = ["$(location resolve_identity.sh)"],
)
```

- [ ] **Step 4: Run the test — verify it FAILS**

Run: `bazel test //tools/pulumi:resolve_identity_test --test_output=all`
Expected: **FAILED**. Test log shows `FAIL: known dir: got [] want [james.nguyen@gmail.com<TAB>personal-llc]` (the stub returns nothing).

- [ ] **Step 5: Implement the real resolver**

Replace the entire contents of `tools/pulumi/resolve_identity.sh` with:

```bash
#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Resolve the GCP account + project declared for a Pulumi project directory in
# the identity map. Used by tools/pulumi/pulumi_cmd.sh and unit-tested directly.
#
# Usage:  resolve_identity.sh <map_file> <infra_dir>
# Output: "<account>\t<gcp_project>" when <infra_dir> is listed (and is not the
#         "-" reference placeholder); nothing otherwise. Always exits 0.
set -euo pipefail

map="${1:?usage: resolve_identity.sh <map_file> <infra_dir>}"
dir="${2:?usage: resolve_identity.sh <map_file> <infra_dir>}"

[ -f "$map" ] || exit 0

awk -v d="$dir" '
  $1 ~ /^#/ { next }          # comment lines
  NF == 0   { next }          # blank lines
  $1 == "-" { next }          # reference-only rows
  $1 == d   { printf "%s\t%s\n", $2, $3; exit }
' "$map"
```

- [ ] **Step 6: Run the test — verify it PASSES**

Run: `bazel test //tools/pulumi:resolve_identity_test --test_output=all`
Expected: **PASSED** — test log prints `PASS: resolve_identity.sh`; `1 test passes`.

- [ ] **Step 7: Commit**

```bash
git add tools/pulumi/resolve_identity.sh tools/pulumi/resolve_identity_test.sh tools/pulumi/BUILD
git commit -m "feat(pulumi): add GCP identity resolver + unit test

awk lookup turning a Pulumi project dir into <account>\t<gcp_project> from
infrastructure/gcp-identities.tsv. Skips comments, blanks, and '-' reference
rows. Exercised by a rules_shell sh_test.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: The identity map file

**Files:**
- Create: `infrastructure/gcp-identities.tsv`

- [ ] **Step 1: Create the map**

Create `infrastructure/gcp-identities.tsv`:

```
# GCP identity map — which Google account manages each piece of infrastructure.
#
# WHY: this machine has several gcloud accounts (personal, abrial, vitruvian). GCP auth must
# NOT depend on whichever account `gcloud` is currently set to. The Pulumi Bazel wrappers
# (//tools/pulumi) read this file and inject a token for the declared account at run time
# (GOOGLE_OAUTH_ACCESS_TOKEN), so the correct identity is always used — and using the wrong
# one fails fast instead of silently succeeding against the wrong project.
#
# FORMAT: columns separated by any whitespace (awk default), aligned with spaces for
# readability (the .tsv extension is nominal). `#` and blank lines are ignored. Columns:
#   infra_dir    workspace-relative Pulumi project dir (resolver key); "-" = reference-only row
#   account      Google account email to authenticate as
#   gcp_project  default GCP project (exported as GOOGLE_CLOUD_PROJECT); "-" if N/A
#   purpose      free text; may contain spaces; MUST be the last column
#
# AD-HOC GCP WORK: look up the account here, then:
#   export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token --account=<account>)"
#
# infra_dir                        account                              gcp_project   purpose
infrastructure/pulumi/accounts/personal    james.nguyen@gmail.com               personal-llc  Personal Cloud Run + Cloudflare DNS (pulumi_lab_gmail)
# --- reference only: accounts we use, no infrastructure in this repo yet ---
-                                  james@abrial.ai                      -             abrial.ai projects (future)
-                                  james@sandbox.vitruviansoftware.dev  -             Vitruvian Software sandbox/company (future)
```

- [ ] **Step 2: Sanity-check the real map against the resolver**

Run: `bash tools/pulumi/resolve_identity.sh infrastructure/gcp-identities.tsv infrastructure/pulumi/accounts/personal`
Expected (account and project separated by a tab): `james.nguyen@gmail.com	personal-llc`

Run (a non-GCP project, must print nothing): `bash tools/pulumi/resolve_identity.sh infrastructure/gcp-identities.tsv infrastructure/pulumi/platform/repo_config`
Expected: (no output)

- [ ] **Step 3: Commit**

```bash
git add infrastructure/gcp-identities.tsv
git commit -m "feat(infra): add GCP identity map (lab-gmail + reference rows)

Source-of-truth mapping infra dir -> Google account. Seeds lab-gmail ->
james.nguyen@gmail.com (personal-llc) and records abrial / vitruvian
accounts as reference rows for future infrastructure.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Wire identity injection into the wrapper

**Files:**
- Modify: `tools/pulumi/pulumi_cmd.sh`

- [ ] **Step 1: Replace `tools/pulumi/pulumi_cmd.sh` with the version below**

The only change vs. the current file is the new `GCP identity injection` block inserted between `export GOWORK=off` and `exec pulumi ...`. Full file:

```bash
#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Generic Pulumi subcommand wrapper — invoked via `bazel run`, never directly.
#
# The calling `sh_binary` bakes in two leading args via `args = [<dir>, <subcmd>]`:
#   $1  workspace-relative path to the Pulumi project directory
#   $2  the pulumi subcommand to run (preview|up|destroy|refresh|config|...)
# Anything a developer appends after `--` is forwarded verbatim to pulumi, e.g.
#   bazel run //infrastructure/pulumi/platform/repo_config:up -- --stack dev --yes
#
# Pulumi compiles and runs the Go program itself; Bazel only launches the CLI
# from the real workspace tree (not the sandboxed runfiles dir).
set -euo pipefail

# `bazel run` executes from the runfiles dir; operate on the project dir instead.
PROJECT_DIR="$1"
SUBCMD="$2"
shift 2

if ! command -v pulumi >/dev/null 2>&1; then
  echo "pulumi CLI not found on PATH. Run 'bazel run //$PROJECT_DIR:setup' first," >&2
  echo "or install it from https://www.pulumi.com/docs/install/." >&2
  exit 1
fi

cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be invoked via 'bazel run', not 'bazel test'}/$PROJECT_DIR"

# These Pulumi modules are standalone Go modules (their own go.mod), deliberately
# kept out of any repo-level go.work. Disable workspace mode so Pulumi's internal
# `go build` resolves dependencies from THIS module — otherwise, inside a monorepo
# that has a go.work, the build fails with "not a known dependency".
export GOWORK=off

# --- GCP identity injection -------------------------------------------------
# Pin GCP auth to the account declared for this project in
# infrastructure/gcp-identities.tsv, so it never depends on the ambient `gcloud`
# account. The resolver is read from the workspace tree (consistent with how
# this wrapper already runs the working-tree Go program). Projects not listed in
# the map are unaffected.
_id_map="${BUILD_WORKSPACE_DIRECTORY}/infrastructure/gcp-identities.tsv"
_id_resolver="${BUILD_WORKSPACE_DIRECTORY}/tools/pulumi/resolve_identity.sh"
if [ -f "$_id_map" ] && [ -f "$_id_resolver" ]; then
  IFS=$'\t' read -r _gcp_account _gcp_project < <(bash "$_id_resolver" "$_id_map" "$PROJECT_DIR") || true
  if [ -n "${_gcp_account:-}" ]; then
    if ! command -v gcloud >/dev/null 2>&1; then
      echo "ERROR: $PROJECT_DIR is pinned to GCP identity '$_gcp_account'" >&2
      echo "(infrastructure/gcp-identities.tsv) but the gcloud CLI is not installed:" >&2
      echo "    https://cloud.google.com/sdk/docs/install" >&2
      exit 1
    fi
    if ! _gcp_token="$(gcloud auth print-access-token --account="$_gcp_account" 2>/dev/null)"; then
      echo "ERROR: $PROJECT_DIR is pinned to GCP identity '$_gcp_account'" >&2
      echo "(infrastructure/gcp-identities.tsv) but no valid credentials were found." >&2
      echo "Log in with:  gcloud auth login $_gcp_account" >&2
      exit 1
    fi
    export GOOGLE_OAUTH_ACCESS_TOKEN="$_gcp_token"
    if [ -n "${_gcp_project:-}" ] && [ "$_gcp_project" != "-" ]; then
      export GOOGLE_CLOUD_PROJECT="$_gcp_project" CLOUDSDK_CORE_PROJECT="$_gcp_project"
    fi
    echo "→ GCP identity: $_gcp_account (project ${_gcp_project:-unset}) for $PROJECT_DIR" >&2
  fi
fi
# ---------------------------------------------------------------------------

exec pulumi "$SUBCMD" "$@"
```

- [ ] **Step 2: Syntax-check the script**

Run: `bash -n tools/pulumi/pulumi_cmd.sh && echo "syntax OK"`
Expected: `syntax OK`

- [ ] **Step 3: Confirm the resolver test still passes (no regression)**

Run: `bazel test //tools/pulumi:resolve_identity_test`
Expected: **PASSED**.

- [ ] **Step 4: Commit**

```bash
git add tools/pulumi/pulumi_cmd.sh
git commit -m "feat(pulumi): auto-inject GCP identity from the map in the wrapper

Before running pulumi, resolve the project dir against
infrastructure/gcp-identities.tsv and, if an account is declared, inject a
freshly-minted GOOGLE_OAUTH_ACCESS_TOKEN (and GOOGLE_CLOUD_PROJECT). Fails
fast if the account is not logged in; unlisted projects are unaffected.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Discoverability — `AGENTS.md`

**Files:**
- Create: `AGENTS.md`

- [ ] **Step 1: Create `AGENTS.md` at the repo root**

```markdown
# Agent guide — vitruvian-core

## GCP identity is pinned per-infrastructure

This repo manages cloud infrastructure under multiple Google accounts (personal,
abrial, Vitruvian). **Never assume the ambient `gcloud` account is correct.**

The mapping of infrastructure → GCP account is in
[`infrastructure/gcp-identities.tsv`](infrastructure/gcp-identities.tsv).

- **Pulumi:** the Bazel wrappers
  (`bazel run //infrastructure/pulumi/<project>:{preview,up,refresh,destroy,config}`)
  read that file and automatically inject an access token for the declared
  account — you do not touch `gcloud config`. If the declared account isn't
  logged in, the wrapper fails fast and tells you which `gcloud auth login` to run.
- **Ad-hoc GCP commands** (`gcloud`, `gsutil`, …): look up the account in the map, then:

  ```bash
  export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token --account=<account>)"
  ```
```

- [ ] **Step 2: Commit**

```bash
git add AGENTS.md
git commit -m "docs: add AGENTS.md pointing at the GCP identity map

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: End-to-end verification (local; no commit)

This task proves the wrapper auto-injects the correct identity. It needs the
`james.nguyen@gmail.com` gcloud credential (already present) and network access.

- [ ] **Step 1: Confirm the wrong account is the ambient default (the problem we're fixing)**

Run: `gcloud config get-value account`
Expected: prints `james@abrial.ai` (or anything that is NOT `james.nguyen@gmail.com`). This is the ambient account the wrapper must override.

- [ ] **Step 2: Run a real preview through the wrapper with NO manual token in the env**

Run:
```bash
unset GOOGLE_OAUTH_ACCESS_TOKEN GOOGLE_CLOUD_PROJECT CLOUDSDK_CORE_PROJECT
bazel run //infrastructure/pulumi/accounts/personal:preview -- --stack dev --diff --non-interactive
```
Expected:
- stderr shows: `→ GCP identity: james.nguyen@gmail.com (project personal-llc) for infrastructure/pulumi/accounts/personal`
- the refresh succeeds with **no `403 IAM_PERMISSION_DENIED`** errors
- summary ends with `Resources:` … `30 unchanged` (no pending changes)

- [ ] **Step 3: Confirm the fail-fast precondition works**

Run (a deliberately bogus account that is not logged in):
```bash
gcloud auth print-access-token --account=nobody@example.com >/dev/null 2>&1; echo "exit=$?"
```
Expected: `exit=1` (non-zero) — confirming the wrapper's `if ! _gcp_token=...` guard would fire and stop before running pulumi, rather than falling back to the ambient account.

- [ ] **Step 4: Confirm a clean working tree (verification only — nothing to commit)**

Run: `git status --short`
Expected: empty (Tasks 1–4 already committed; this task changed nothing).

---

## Task 6: Generalize Claude memory (local; not committed to the repo)

**Files:**
- Modify: `/Users/james/.claude/projects/-Users-james-Workspace-gh-application-vitruvian-vitruvian-core/memory/lab-gmail-gcp-identity.md`
- Modify: `/Users/james/.claude/projects/-Users-james-Workspace-gh-application-vitruvian-vitruvian-core/memory/MEMORY.md`

- [ ] **Step 1: Rewrite the memory file body to point at the committed map**

Replace the body of `lab-gmail-gcp-identity.md` so it generalizes from "lab-gmail only" to "all GCP infra is pinned via the map." Keep the front-matter `name`/`description`/`metadata` keys; update the description to:
`GCP infra identity is pinned per-project in infrastructure/gcp-identities.tsv; Pulumi wrappers auto-inject the right account`

New body text:

```markdown
GCP auth for this repo's infrastructure is pinned per-project in the committed map
`infrastructure/gcp-identities.tsv` (infra dir → Google account → GCP project). The
Pulumi Bazel wrappers (`//tools/pulumi`, via `tools/pulumi/resolve_identity.sh`)
read it and inject `GOOGLE_OAUTH_ACCESS_TOKEN` for the declared account at run time,
so auth never depends on the ambient `gcloud` account (the machine default is
`james@abrial.ai`, which 403s on personal-llc). Failing fast on a not-logged-in
account is intentional.

Current entries: `infrastructure/pulumi/accounts/personal` → `james.nguyen@gmail.com`
(`personal-llc`). `james@abrial.ai` and `james@sandbox.vitruviansoftware.dev` are
reference rows (no in-repo infra yet). To add infra: add a row to the map; the
wrapper does the rest. For ad-hoc GCP work, see `AGENTS.md`.
```

- [ ] **Step 2: Update the index line in `MEMORY.md`**

Change the existing `lab-gmail GCP identity` bullet to:
`- [GCP infra identity map](lab-gmail-gcp-identity.md) — GCP identity is pinned per-project in infrastructure/gcp-identities.tsv; Pulumi wrappers auto-inject (never rely on ambient gcloud)`

(No git commit — this is Claude's local memory, outside the repo.)

---

## Final: Open the PR

After Tasks 1–6, push the branch and open a PR (the repo squash-merges; see PR #16/#17):

```bash
git push -u origin feat/gcp-identity-map
gh pr create --base main --head feat/gcp-identity-map \
  --title "feat(infra): pin GCP identity per-infrastructure (auto-inject in Pulumi wrappers)" \
  --body "Implements docs/superpowers/specs/2026-06-01-gcp-identity-map-design.md. Adds infrastructure/gcp-identities.tsv (source of truth), tools/pulumi/resolve_identity.sh (+ sh_test), wrapper auto-injection with fail-fast, and AGENTS.md. Verified end-to-end against the live lab-gmail dev stack while the ambient gcloud account was the wrong one."
```
