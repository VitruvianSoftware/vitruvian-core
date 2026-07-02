# GCP Identity Map — Design

- **Date:** 2026-06-01
- **Status:** Approved (pending spec review)
- **Author:** james.nguyen@gmail.com (with Claude)

## Problem

This machine has several Google Cloud accounts for different contexts:

| Account | Context |
|---------|---------|
| `james.nguyen@gmail.com` | Personal (`personal-llc`) |
| `james@abrial.ai` | abrial.ai work |
| `james@sandbox.vitruviansoftware.dev` | Vitruvian Software |

Pulumi's GCP provider authenticates via Application Default Credentials (ADC), which resolve to *whatever account `gcloud` happens to be set to* — and the default is often the wrong one. This already bit us: a `pulumi preview` of `lab-gmail` (a `personal-llc` stack) failed `403` on all 32 resources because ADC resolved to `james@abrial.ai`. The workaround was to inject a token for the correct account via `GOOGLE_OAUTH_ACCESS_TOKEN`, which worked cleanly and did **not** disturb the ambient `gcloud` config.

Relying on the ambient account is error-prone for both the human and for agents. We want a durable, discoverable binding of **infrastructure → GCP identity** that the tooling applies automatically and that never depends on the current `gcloud` account.

## Goals

- A single, committed, human- and agent-readable file mapping each infra unit → the GCP account it must be managed with.
- The Pulumi Bazel wrappers automatically authenticate as the declared account at run time (token injection), regardless of the ambient `gcloud` account.
- **Fail fast** if the declared account has no usable credentials — never silently fall back to the wrong identity.
- Discoverable by agents without being told (committed `AGENTS.md` pointer + the file's own header).
- Zero new runtime dependencies (no `yq`; parse with `awk`).

## Non-Goals

- A general identity-runner for arbitrary non-Pulumi commands (`gcloud`/`gsutil`/Terraform). Out of scope — for ad-hoc work, humans/agents read the map and inject the token via the documented one-liner. (Revisit when non-Pulumi GCP infra exists.)
- Changing how Pulumi Cloud login, Cloudflare tokens, or GitHub auth work.
- Managing ADC files or `gcloud` configurations.

## Approach (chosen: A)

A readable map file is the single source of truth. The existing wrapper (`tools/pulumi/pulumi_cmd.sh`) already `cd`s into the project dir under `$BUILD_WORKSPACE_DIRECTORY`; it resolves that dir against the map and, when an account is declared, injects a freshly-minted access token before exec'ing pulumi.

Rejected alternative **B** (account as a `pulumi_project` Bazel attribute): run-time enforced and local to each target, but the mapping scatters across `BUILD` files instead of being the single readable map we want, and leaves nowhere to record reference-only accounts.

## Components

### 1. The identity map — `infrastructure/gcp-identities.tsv`

Columns are separated by any run of whitespace (`awk`'s default field splitting) and aligned with spaces for readability — the `.tsv` extension is nominal, not literal tabs. `#` lines and blank lines are ignored. Columns:

| Col | Name | Meaning |
|-----|------|---------|
| 1 | `infra_dir` | Workspace-relative Pulumi project dir — the resolver key. `-` for reference-only rows (an account we use but have no infra for yet). |
| 2 | `account` | Google account email to authenticate as. |
| 3 | `gcp_project` | Default GCP project, exported as `GOOGLE_CLOUD_PROJECT`. `-` if N/A. |
| 4+ | `purpose` | Free text; may contain spaces; **must be the last column** (resolver reads only cols 1–3). |

Seed content:

```
# GCP identity map — which Google account manages each piece of infrastructure.
#
# WHY: this machine has several gcloud accounts (personal, abrial, vitruvian). GCP auth must
# NOT depend on whichever account `gcloud` is currently set to. The Pulumi Bazel wrappers
# (//tools/pulumi) read this file and inject a token for the declared account at run time
# (GOOGLE_OAUTH_ACCESS_TOKEN), so the correct identity is always used — and using the wrong
# one fails fast instead of silently succeeding against the wrong project.
#
# FORMAT: whitespace-separated. `#` and blank lines ignored. Columns:
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

Reference rows use `-` as `infra_dir`, which can never equal a real project dir, so the resolver ignores them while humans/agents can still see which account maps to which context.

### 2. Resolver — `tools/pulumi/resolve_identity.sh`

Small, single-purpose, independently testable.

- **Usage:** `resolve_identity.sh <map_file> <infra_dir>`
- **Output:** `<account>\t<gcp_project>` on a match where `infra_dir` is not `-`; otherwise nothing (exit 0).
- **Logic:** `awk` skipping `#`/blank lines, matching col1 exactly, printing cols 2–3.

### 3. Wrapper integration — `tools/pulumi/pulumi_cmd.sh`

Inserted after `export GOWORK=off`, before `exec pulumi …`:

1. Locate the map (`$BUILD_WORKSPACE_DIRECTORY/infrastructure/gcp-identities.tsv`) and resolver (`$BUILD_WORKSPACE_DIRECTORY/tools/pulumi/resolve_identity.sh`). If either is absent, skip injection (behave as today).
2. Resolve `$PROJECT_DIR` (the wrapper's `$1`) → `account`, `gcp_project`.
3. If an `account` is returned:
   - `TOKEN="$(gcloud auth print-access-token --account="$account")"`. On failure (account not logged in, or `gcloud` missing), print a clear remediation (`gcloud auth login <account>`) and **`exit 1`**.
   - `export GOOGLE_OAUTH_ACCESS_TOKEN="$TOKEN"`; if `gcp_project` is set and not `-`, also `export GOOGLE_CLOUD_PROJECT`/`CLOUDSDK_CORE_PROJECT`.
   - Print a one-line notice to stderr: `→ GCP identity: <account> (project <p>) for <dir>`.
4. If no account is returned, proceed unchanged (so `repo_config`/`dev-local` and any future non-GCP project are unaffected).

`GOOGLE_OAUTH_ACCESS_TOKEN` takes precedence over ADC in the Terraform/Pulumi google provider, so this overrides the ambient account for that one invocation only. The token is minted per-run (fresh, ~1h lifetime) and never persisted or logged.

### 4. Discoverability

- **`AGENTS.md`** (new, repo root): short pointer — "GCP infra auth is identity-pinned; see `infrastructure/gcp-identities.tsv`. The Pulumi wrappers auto-inject; never rely on the ambient `gcloud` account; for ad-hoc GCP work, look up the account there."
- **Map header** documents itself and the ad-hoc one-liner.
- **Claude memory** (`lab-gmail-gcp-identity.md`) generalized to point at the committed map.

## Testing & Verification

- **`sh_test`** (`tools/pulumi/resolve_identity_test.sh` via `rules_shell`) against a fixture map:
  - known dir → correct `account\tproject`
  - reference row (`-`) and unknown dir → empty output
  - comment/blank lines ignored; `purpose` with spaces doesn't corrupt cols 1–3
- **`gofmt`/build** unaffected (no Go changes).
- **Manual end-to-end:** `bazel run //infrastructure/pulumi/accounts/personal:preview -- --stack dev` with the ambient `gcloud` account set to `james@abrial.ai` must still authenticate as `james.nguyen@gmail.com` and refresh cleanly. Set ambient to a bogus/none and confirm the fail-fast message when the declared account lacks creds.

## Failure Modes

| Situation | Behavior |
|-----------|----------|
| Declared account not logged in / token mint fails | Print `gcloud auth login <account>`, `exit 1` before pulumi runs |
| `gcloud` not installed but account declared | Clear error + `exit 1` |
| Project dir absent from map | No injection; runs as today (documented: GCP projects must be listed) |
| Map or resolver file missing | No injection; runs as today (graceful) |

## Security

- Tokens minted inline, exported to the child pulumi process only, never echoed or written to disk.
- The map contains only account emails and project ids — no secrets. Safe to commit.
- Pinning identity reduces the risk of mutating the wrong project under an unexpected account.

## Future / Out of Scope

- General `with-identity` runner for non-Pulumi GCP commands (when such infra exists).
- Optional strict mode: warn/fail if a project imports the GCP provider but has no map entry.
- Per-account ADC files if a non-interactive/CI path is ever needed.
