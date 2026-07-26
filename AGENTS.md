# Agent guide — vitruvian-core

> **This file is the single, vendor-neutral agent guide for this repo.** It follows the
> [AGENTS.md](https://agents.md) convention, which Claude Code, Antigravity/Gemini, Copilot,
> Cursor, opencode and others all read. There is deliberately **no `CLAUDE.md`,
> `.cursorrules` or `copilot-instructions.md` at the root** — one file, so guidance cannot
> drift per tool.
>
> Keep it that way when editing:
> - **Write for any agent.** Don't assume a specific tool's commands, file layout or
>   capabilities. Prefer the repo's own `bazel run …` entrypoints, which work everywhere.
> - **No tool-specific instructions in this file.** If setup only applies to one vendor,
>   it goes in `docs/` and is linked from here (as the homelab access section does) —
>   everything in this guide should be actionable by every agent that reads it.
> - **Nested `AGENTS.md` files scope to their subtree** (`devx/`, `tabula/`,
>   `oauth-user-inspector/`) — put per-component detail there, not here. Note that an
>   `AGENTS.md` only applies to the directory it sits in and below, so one in a
>   non-source directory silently never applies.

## Orient first: principles, SDLC, docs hub

Before shaping any non-trivial change, read the
[Guiding Principles](docs/engineering/application-development-principles.md) — they
are the authoritative standard and exist precisely to steer agents toward the right
shape: everything-as-code (never click-ops or imperative one-offs), the pipeline as
the only trigger, secrets never in git, bazel-wrapped tooling, expand/contract
sequencing, and "every fix ships with the check that would catch it again". The
[SDLC walkthrough](docs/concepts/sdlc.md) explains how a change reaches production;
the [docs hub](docs/README.md) routes everything else, and the
[Bazel targets catalog](docs/reference/bazel-targets.md) lists the sanctioned tool
surface. When an app's own docs conflict with `CONTRIBUTING.md`, CONTRIBUTING wins.

## GCP identity is pinned per-infrastructure

This repo manages cloud infrastructure under multiple Google accounts (personal,
nocentre, Vitruvian). Today every first-party app here deploys under the personal
account `james.nguyen@gmail.com`. **Never assume the ambient `gcloud` account is correct.**

The mapping of infrastructure → GCP account is in
[`infrastructure/gcp-identities.tsv`](infrastructure/gcp-identities.tsv).

- **Pulumi:** the Bazel wrappers
  (`bazel run //infrastructure/pulumi/<project>:{preview,up,refresh,destroy,config,setup}`)
  read that file and automatically inject an access token for the declared
  account — you do not touch `gcloud config`. If the declared account isn't
  logged in, the wrapper fails fast and tells you which `gcloud auth login` to run.
- **Ad-hoc GCP commands** (`gcloud`, `gsutil`, …): look up the account (and project) in the map, then:

  ```bash
  export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token --account=<account>)"
  # if the map declares a project (3rd column), also:
  export GOOGLE_CLOUD_PROJECT=<gcp_project>
  ```

> Adding a new Pulumi project that uses GCP? Add a row to the map **first** — the
> wrapper silently skips injection (and falls back to the ambient account) for
> projects not listed.

## Build, test, run
- Dev environment: `bazel run //tools:bazel_env` (with [direnv](https://direnv.net); `direnv allow`).
- Build / test everything: `bazel build //...` and `bazel test //...`.
- Lint / format: `aspect lint //...` and `format`.
- Watch loop: `ibazel run //<target>`.
- Regenerate `BUILD` files after adding/moving code: `bazel run //:gazelle`.
- macOS app (nexus-agent): `bazel build --config=macos-app //nexus-agent/macos:NexusAgent`.

## Finishing work: PR, checks, land, clean up
Run every change to completion — an unmerged branch is unfinished work, not a deliverable.
1. **Open a PR.** When the work is done, push and open one (`gh pr create`) unless an open,
   related PR already covers it. Never merge locally. PR bodies are self-contained: what
   changed, why, how it was verified.
2. **Drive the checks green.** Watch them and fix what goes red — including flaky or
   non-required checks. Never present a PR as ready while any check is red.
3. **Land it.** Once approved, merge and keep watching until it actually lands; the merge
   queue can still reject on the rebased result.
4. **Clean up.** After it lands, delete the branch/worktree and return to the latest `main`.
   **Verify it landed first**, and note that `git merge-base --is-ancestor <branch-sha>
   origin/main` is always false here — `main` is squash-only, so your branch's SHAs are
   never ancestors of it. Check by PR number instead (`git log --grep "(#N)" origin/main`,
   or `bazel run //tools/landed -- <pr#|branch|sha>`), or verify the content directly.

## Rigor & validation
- **Never assume configuration parity.** When touching monorepo-wide config (matrices,
  package lists, `release-please-config.json`, workspaces), do not hand-identify the set.
  Diff the physical directory structure against the config to prove 100% parity.
- **Check sibling ecosystems.** A change for one language usually has a counterpart in
  another (Go → TypeScript, and vice versa). Confirm before declaring the task done.
- **Verify before claiming success.** Don't report a bug fixed until a test or script you
  actually ran proves it — and prove the check fails against the broken state, or it is
  not evidence. For infrastructure, assert the **live effect**, not a green apply log: a
  provider reporting `updated` does not mean the setting took.

## Conventions & landmines
- **`main` is squash-only, so branch SHAs NEVER become ancestors of `main`.** Do not verify
  "did it land?" with `git merge-base --is-ancestor <branch-sha> origin/main` — it returns
  false for *every* merged PR. That is a false negative on the dangerous side: it claims
  landed work is missing, which can lead you to redo it, or to hesitate over deleting a
  branch that is perfectly safe to delete. **Before cleaning up worktrees/branches, or
  claiming anything is in `main`, use `bazel run //tools/landed -- <pr#|branch|sha>`**,
  which resolves to the *squashed* commit and checks that. Fallbacks: `git log --grep
  "(#N)" origin/main` (GitHub appends `(#N)` to squash titles), or verify the content
  directly with `git show origin/main:<path>`. See CONTRIBUTING.md §4.1.
- **Gazelle owns most `BUILD` files** — don't hand-edit generated targets; change the source and
  re-run gazelle.
- **One Version Rule** — one resolved version per dependency per ecosystem. To deliberately
  diverge, add a *separate* hub/module, not a second version to the shared hub. See
  `docs/dependency-versioning/`.
- **Dependency changes** = edit the manifest, then re-lock, then gazelle:
  - Python: `pyproject.toml` → `./tools/repin` → `bazel run //:gazelle`
  - JS/TS: `pnpm add …` (one pnpm workspace / `pnpm-lock.yaml`)
  - Go: `go mod tidy` → `bazel mod tidy` → `bazel run //:gazelle` (multi-module `go.work`: `.`, `homelab`, `devx`)
  - JVM: edit `maven.install` in `MODULE.bazel` → `bazel run @maven//:pin`; Rust: `Cargo.toml`; Ruby: `Gemfile`
- The **`infrastructure/pulumi` Go modules are intentionally kept OUT of `go.work`** — don't add them.
- **License headers are enforced** (`addlicense`; CI `license-check`) — run the add helper before committing.
- **Build cache:** both a local `--disk_cache` (opt-in; see `user.bazelrc.example`) and remote
  RBE via `--config=remote` (BuildBuddy, needs a key) are available — no vendor is forced.

## Homelab access (tool-specific)
Driving the homelab k3s cluster or SSH-ing to its nodes from a *cloud* agent session needs
transport onto the tailnet, and that wiring is specific to whichever tool you run. The
Claude Code setup (SessionStart hooks, SOCKS5 proxy, key install) is documented separately
in [`docs/admin/claude-code-cloud-sessions.md`](docs/admin/claude-code-cloud-sessions.md)
so it does not leak into this vendor-neutral guide.

What generalises, whatever tool you are on:
- The cluster API is the HA name `https://k8s-api.lab.ipv1337.dev:6443` (a Cloudflare A
  record to the three control-plane tailnet IPs; the serving cert carries it as a
  `tls-san`, so TLS validates whichever control plane answers).
- Node access is by SSH **key**, as user `james`. Tailscale SSH is *not* enabled on these
  hosts.
- Local (non-cloud) sessions with tailnet access already need none of the proxy plumbing.

## Copybara (component sync)
The monorepo is the **single source of truth**; each standalone repo is a read-only mirror.
Components (`devx`, `homelab`, `mcp-slack`, `nexus-agent`, `oauth-user-inspector`) export one-way on
push; the `pulumi-*` trees are export-only. Nothing syncs bidirectionally. External contributions
come back only as a mirror PR labelled `import-to-monorepo`, imported hourly as a monorepo PR for
review. Never edit a mirror directly, never delete standalone-only files or import monorepo-only
ones — respect `standalone_only` (e.g. `package-lock.json`,
`.github/workflows/sync-to-monorepo.yaml`) and the gazelle-generated `BUILD` files (monorepo-only).
See `docs/admin/copybara-sync.md`.

## How this repo is maintained
- vitruvian-core was generated from the **kitchen-sink** starter and **does not auto-receive
  template updates** — platform changes are *manually ported* here (this repo doubles as the test
  bed that proves starter-template changes actually build).
- **Conventional commits** (`feat:`, `fix:`, `chore:`, `docs:` …).
- Planning docs live in `docs/archive/planning/` and `docs/superpowers/`. Ones marked `status: completed` are done —
  don't treat them as open TODOs.
