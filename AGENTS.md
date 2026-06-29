# Agent guide — vitruvian-core

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

## Copybara (component sync)
Components (`devx`, `homelab`, `mcp-slack`, `nexus-agent`) sync bidirectionally to standalone
repos. Never delete standalone-only files or import monorepo-only ones — respect `standalone_only`
(e.g. `package-lock.json`, `.github/workflows/sync-to-monorepo.yaml`) and the gazelle-generated
`BUILD` files (monorepo-only). See `docs/copybara-bidi-sync.md`.

## How this repo is maintained
- vitruvian-core was generated from the **kitchen-sink** starter and **does not auto-receive
  template updates** — platform changes are *manually ported* here (this repo doubles as the test
  bed that proves starter-template changes actually build).
- **Conventional commits** (`feat:`, `fix:`, `chore:`, `docs:` …).
- Planning docs live in `docs/` and `docs/planning/`. Ones marked `status: completed` are done —
  don't treat them as open TODOs.
