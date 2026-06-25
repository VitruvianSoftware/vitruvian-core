# vitruvian-core

> A Bazel monorepo for VitruvianSoftware's applications and the self-hosted platform that runs them.

`vitruvian-core` is a polyglot (TypeScript + Go) [Bazel](https://bazel.build) monorepo. It holds every
first-party application, the [Pulumi](https://www.pulumi.com) infrastructure that hosts them, the
ArgoCD/GitOps definition of our self-hosted Kubernetes platform, and the tooling that ties it together.
Each app is also mirrored one-way to its own repo in the
[`VitruvianSoftware`](https://github.com/VitruvianSoftware) org via Copybara — but **all development
happens here**.

**New here?** Read this page, then **[CONTRIBUTING.md](CONTRIBUTING.md)** (how to work day-to-day) and the
**[Application Development Principles](docs/engineering/application-development-principles.md)** (how we
build, by app type).

## Applications

| App | Type | What it is |
|---|---|---|
| [`tabula`](tabula/) | SaaS web service | Browser tab-management product: a TypeScript API on Cloud Run, an MV3 browser extension, a web dashboard, and a CLI. The most mature deploy in the repo. |
| [`oauth-user-inspector`](oauth-user-inspector/) | SaaS web service | Full-stack OAuth/token inspector (React + Vite frontend + Express backend) served as one container on Cloud Run. |
| [`devx`](devx/) | CLI / developer tool | Local-dev orchestrator: provisions Lima VMs & devcontainers, ephemeral DBs/emulators, K3s clusters, and tunnel ingress. |
| [`homelab`](homelab/) | CLI / developer tool | Declarative multi-node K3s homelab manager for macOS (Lima VZ). |
| [`mcp-slack`](mcp-slack/) | Agent / MCP service | Slack MCP server (dual-token; ~22 tools including Canvas CRUD). |
| [`nexus-agent`](nexus-agent/) | Agent / MCP service | Telegram bot + macOS menu-bar app that bridges chats to a local AI coding CLI. |

Each application type has its own conventions — see the
[per-category playbook](docs/engineering/application-development-principles.md#3-per-category-playbook).

## Platform & infrastructure

| Path | What it is |
|---|---|
| [`infrastructure/pulumi/`](infrastructure/pulumi/) | Infrastructure as code (Go/Pulumi): per-app Cloud Run deploys, keyless deploy identities (Workload Identity Federation), this repo's own GitHub settings, and the bootstrap for the dev-local cluster. |
| [`gitops/`](gitops/) | ArgoCD app-of-apps for the **dev-local** k3s homelab — Zitadel (IdP), Prometheus/Grafana/Loki/Tempo, CNPG, MinIO, Cilium, Envoy Gateway, sealed-secrets, cloudflared. Everything reconciles from git. |
| [`tools/`](tools/) | The monorepo's own tooling: Bazel wrappers for Pulumi & GitOps, Copybara sync, OCI image rules. |

## Repository layout

```
.
├── tabula/  oauth-user-inspector/   # SaaS web services (Cloud Run)
├── devx/  homelab/                  # Go developer / ops CLIs
├── mcp-slack/  nexus-agent/         # agents / MCP services
├── infrastructure/pulumi/           # IaC: Cloud Run, deploy identity, repo config, dev-local bootstrap
├── gitops/                          # ArgoCD app-of-apps (the self-hosted platform)
├── tools/                           # Bazel pulumi/gitops wrappers, Copybara, OCI
├── docs/                            # engineering guides, per-app docs, infrastructure, planning
├── .github/workflows/               # CI/CD, deploy, Copybara
├── AGENTS.md                        # guardrails for AI agents working in this repo
└── CONTRIBUTING.md                  # the developer SOP
```

## Getting started

You'll need **Bazelisk**, **Node 22.21.1** (pinned in `.nvmrc`), **pnpm 10.20.0**, **Go**, and — for cloud
work — **gcloud** and **gh**. The full, exact setup is in
**[CONTRIBUTING § Prerequisites & toolchain](CONTRIBUTING.md#1-prerequisites--toolchain)**.

```sh
nvm use && corepack enable     # Node 22 + pnpm 10.20.0
bazel build //...              # warms the remote cache
bazel test  //...              # full test sweep — what the merge queue runs
```

Almost everything routes through Bazel. Run `bazel run //:tidy` (gazelle + buildifier + formatters) before
every PR — it's a required check. This checkout may be shared across sessions/agents, so do isolated work
in a **git worktree**.

## Find your way

| I want to… | Start here |
|---|---|
| **Change or maintain an existing app** | the app's own `README.md`, then **[CONTRIBUTING.md](CONTRIBUTING.md)** |
| **Build a new app** | **[Guiding Principles](docs/engineering/application-development-principles.md)** (pick a category + hosting target) → **[CONTRIBUTING.md](CONTRIBUTING.md)** |
| **Work on infrastructure / the platform** | **[CONTRIBUTING § Infra & IaC ops](CONTRIBUTING.md#9-infra--iac-ops)** + **[AGENTS.md](AGENTS.md)** |
| **Understand what's not yet aligned** | **[Application Alignment Gaps](docs/engineering/application-alignment-gaps.md)** |

## How we build & ship (at a glance)

- **One build graph.** Bazel (Bzlmod + Aspect rulesets) builds Go and TS; frontends and containerized web
  apps build via a Dockerfile or `oci` image, **not** Bazel. Work lands through the **merge queue**, never a
  local merge to the default branch.
- **Everything as code.** Infrastructure, deploy identities, and this repo's own GitHub settings are
  Pulumi-managed; the dev-local cluster reconciles from git via **ArgoCD** (GitOps closed-loop — no
  click-ops). Infra ops run through `bazel run //tools/pulumi:*` and `//tools/gitops:*`, never ambient CLIs.
- **Keyless deploys.** Cloud Run apps deploy via GitHub Actions **Workload Identity Federation** (no JSON
  keys), into a per-app GCP project, gated by a per-app **GitHub Environment**.
- **Secrets never live in git.** Local dev uses gitignored files; CI injects the same values from pipeline
  secrets as env; app *runtime* secrets live in GCP Secret Manager; k8s secrets via sealed-secrets. See
  [CONTRIBUTING § Secrets handling](CONTRIBUTING.md#7-secrets-handling).
- **Edit here, mirror out.** Apps sync one-way (monorepo → standalone repo) via Copybara — never edit a
  mirror.

The full rationale lives in the
[Guiding Principles](docs/engineering/application-development-principles.md); the honest current-state delta
(and what to standardize first) is in the
[Alignment Gaps](docs/engineering/application-alignment-gaps.md).

## Documentation

- **[CONTRIBUTING.md](CONTRIBUTING.md)** — the developer SOP (setup, local dev, build/test, secrets, deploy).
- **[docs/engineering/](docs/engineering/)** — application development principles & alignment gaps.
- **[docs/](docs/)** — per-app docs (e.g. [`docs/tabula/`](docs/tabula/)), [`docs/infrastructure/`](docs/infrastructure/), planning, and dependency versioning.
- **[AGENTS.md](AGENTS.md)** — conventions for AI agents (GCP identity pinning, bazel-only infra ops).

## License

First-party code is **MIT © 2026 VitruvianSoftware**, with each app shipping its own `LICENSE`. License
consistency across apps is tracked in the
[alignment gaps](docs/engineering/application-alignment-gaps.md).
