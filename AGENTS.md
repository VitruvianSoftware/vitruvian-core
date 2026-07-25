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
> - **Tool-specific setup belongs in a clearly-labelled section** (see the two "Claude Code
>   cloud sessions" sections below) so agents on other tools know to skip it. Everything
>   unlabelled applies to all.
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

## Homelab Kubernetes access (Claude Code cloud sessions)
Cloud sessions can drive the homelab k3s cluster with `kubectl` over Tailscale.
Two `SessionStart` hooks wire this up automatically (registered in
`.claude/settings.json`):
- `.claude/tailscale-up.sh` — joins the tailnet (userspace networking; exposes a
  SOCKS5 proxy on `localhost:1055`, since the sandbox has no TUN device).
- `.claude/kube-setup.sh` — installs `kubectl` and writes `~/.kube/config`
  (context `lab`) pointed at `https://k8s-api.lab.ipv1337.dev:6443`, dialing the
  apiserver through that SOCKS5 proxy.

Verify with `kubectl get nodes` (context `lab`). If it works, you're done.

**Prerequisites (set once, outside this repo):**
- Env vars on the cloud environment: `TS_AUTHKEY` (reusable, pre-authorized for
  `tag:claude-cloud`) and `LAB_SA_TOKEN` (the **non-expiring** ServiceAccount
  token — `kubectl -n claude-code get secret claude-code-token -o
  jsonpath='{.data.token}' | base64 -d`, *not* `kubectl create token`, which
  expires).
- Tailnet policy: `tag:claude-cloud` must have an ACL grant to the control-plane
  nodes on `6443`, or the node joins able to *see* the netmap but not *touch* it
  (every TCP connection is silently dropped).

**Troubleshooting:**
- `unsupported scheme "socks5h"` → kubeconfig must use `proxy-url: socks5://`
  (kubectl/client-go reject `socks5h`; only `curl` accepts it).
- `Unauthorized` (401) → `LAB_SA_TOKEN` is wrong/expired; transport is fine.
- `i/o timeout` / connection refused to `100.x` → tailnet ACL is not granting
  `tag:claude-cloud`, or `tailscaled`/the SOCKS5 proxy isn't running.
- The cluster API is the HA name `k8s-api.lab.ipv1337.dev` (Cloudflare A record →
  the 3 control-plane tailnet IPs); the apiserver serving cert carries it as a
  `tls-san`, so TLS validates against whichever control plane answers.

## Homelab SSH access (Claude Code cloud sessions)
A cloud session has **passwordless SSH into every homelab node** — use it to
configure or troubleshoot a node directly when needed. Auth is a dedicated agent
**key**, NOT Tailscale SSH: Tailscale SSH is *not* enabled on these hosts, so
`tailscale ssh` falls back to regular ssh and fails on host keys — use the key
path below.

Wiring (automatic via the merged `SessionStart` hooks):
- `kube-setup.sh` installs the private key from the `CLAUDE_SSH_KEY` env var into
  `~/.ssh/id_ed25519` each session, regenerates `id_ed25519.pub` from it, and writes
  `~/.ssh/config` (`StrictHostKeyChecking accept-new`, `GSSAPIAuthentication no`).
  It also installs `openssh-client`.
- The matching public key is in `~/.ssh/authorized_keys` for user **`james`** on each host.

Userspace networking means there's no kernel route to `100.x`, so ssh must dial
through the SOCKS5 proxy `tailscale-up.sh` exposes on `localhost:1055` (needs
`netcat-openbsd`):

```bash
ssh -o ProxyCommand='nc -X 5 -x localhost:1055 %h %p' james@<tailnet-ip> '<cmd>'
```

Nodes (k3s cluster; run `tailscale status` for live IPs): `fedora` control-plane,
`nuc9i5` + `nuc9i9` workers, and the macOS nodes (`james-macbook-pro`, …).

If it breaks (the hooks normally prevent these):
- `Permission denied (publickey)` with a correct private key → a stale `.pub` is
  advertising the wrong key: `ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub`.
- `Connection closed` over the proxy → ssh tried GSSAPI first; add
  `-o GSSAPIAuthentication=no -o PreferredAuthentications=publickey`.
- missing tools → `apt-get install -y openssh-client netcat-openbsd`.

Rotate by regenerating the pair and updating `CLAUDE_SSH_KEY` + each `authorized_keys`.

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
