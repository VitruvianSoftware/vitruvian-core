# Bazel targets & tools catalog

Every operational and developer-facing `bazel run` target in the repo, grouped by
purpose. This is the practical index behind the rule that **all tooling is a
discoverable Bazel target, never a bare script**
([Principles §2.2](../engineering/application-development-principles.md#22-infra-ops-run-only-through-the-bazel-wrappers)).

Discover targets live with `bazel query //tools/...` — if this page and the build
graph disagree, the graph wins.

```mermaid
mindmap
  root((bazel run))
    Dev loop & SDLC
      //:doctor
      //tools/worktree
      //tools/agent-app
      //tools/landed
      //tools/pipeline-status
      //:tidy
      //tools:bazel_env
    Infra & Cloud
      //<pulumi project>:preview·up·…
      //tools/gcp-token
      //tools/cloud-bootstrap
      //tools/gitops:*
      //tools/cluster:*
    Secrets
      //tools/gcp-secrets:*
      //tools/sync-env-secrets:*
      //tools/saas-cli:*
    Ship & Preview
      //tools/ci:gen
      //tools/deploy:cloud-run
      //tools/preview:*
      //tools/charts:publish
      //tools/release:publish-local
      //tools/copybara/sync
```

## Dev loop & repo hygiene

| Target | What it does |
|---|---|
| `//:doctor` | Verifies your core toolchain (bazel, git required; node/pnpm/go/gh/gcloud/docker/direnv advisory) |
| `//<app>:doctor` | Same check scoped to one app's exact requirements (`//apps/suites/tabula:doctor`, `//apps/cli/devx:doctor`, …) |
| `//tools/worktree -- <branch>` | Creates an isolated git worktree with its own Bazel server. `-- --list`, `-- --remove <branch>`. Branch work in the primary checkout is blocked — this is the sanctioned path |
| `//tools/agent-app -- env <agent>` | Mints scoped GitHub App credentials (`GH_TOKEN`, `GIT_AUTHOR_*`, `GIT_COMMITTER_*`) for automated agents and bots (`atlas`, `quill`, etc.) |
| `//tools/landed -- <pr#\|branch\|sha>` | Resolves whether a PR or branch has landed on `origin/main` by inspecting the squashed commit (`main` is squash-only) |
| `//tools/pipeline-status -- <pr#\|sha>` | Evaluates the health of post-merge push workflows on `main`, asserting that CI, delivery, and image builds completed green |
| `//:tidy` | **The single hygiene entrypoint**: gazelle → python manifest → all formatters. Required check (`tidy-check`); run before every PR |
| `//:gazelle` | Regenerate `BUILD` files after adding/moving code |
| `//tools:bazel_env` | Exposes every Bazel-managed tool (go, node, pnpm, python, prettier, …) on your `$PATH` via direnv |
| `//tools/ci-preflight` | The repo-side counterpart to `//:doctor`: every `secrets.*`/`vars.*` the workflows reference, and whether it is actually configured. Flags secrets that PR-triggered workflows read but the **Dependabot** store lacks — those silently resolve to `""` on dependency PRs. `-- --list` for the required set without touching the network |
| `//tools/gomod:tidy` | `go mod tidy` across the `replace`-coupled Go modules (library ↔ go-foundation examples), which Dependabot cannot keep in step on its own. The fix side of `//tools/gomod:check` |
| `//tools/antigravity-telemetry` | Antigravity & `agy` OTLP telemetry CLI: workstation setup (`setup`), diagnostics (`status`), test metric/trace emission (`emit`), and hook event exporter (`export`) |
| `//tools/bazel-cache:gc` | Reclaims orphaned per-worktree output base caches in `~/.cache/bazel/worktrees/` (`--execute`) |
| `//tools/remote:setup` | Opt-in build caching / RBE bootstrap — writes `user.bazelrc` for BuildBuddy or any REAPI provider. See [build cache](../guides/build-cache.md) / [remote build](../guides/remote-build.md) |

## Checks (run locally what CI gates)

| Target | Gate |
|---|---|
| `//tools/license:check` / `:verify` / `:add` | License headers: presence, MIT+holder content, auto-fix |
| `//tools/conformance:check` | Version canonicalization, merge-queue check names, app metadata ↔ CODEOWNERS, visibility firewall, nightly-sweep pairing |
| `//tools/techdocs:check` | Verifies that all 15 TechDocs sites compile cleanly with `mkdocs-techdocs-core` |

| `//tools/lint-naming` | Monorepo naming convention audit (`--check`, `--root <path>`). Validates file casing, test suffixes, and rule boundaries across all languages |
| `//tools/owners` | Validates and compiles per-subtree `OWNERS` files into `.github/CODEOWNERS` (`--check`, `--validate-only`, `--coverage-check`) |
| `//tools/osv-scan` | Lockfiles vs. the OSV advisory database (Go, npm, PyPI, Cargo). Gate: `osv-scan` |
| `//tools/npm-publish-audit:check` | Verifies against the npm registry that packages claimed published by CI actually exist |
| `//tools/gomod:check` | The `replace`-coupled Go modules (`packages/pulumi/library/go` ↔ `packages/pulumi/examples/go-foundation`) are in sync. Read-only. Gate: a step in `example-build`. Fix with `//tools/gomod:tidy` |
| `aspect lint //...` | rules_lint linters (eslint, golangci via nogo, ruff, …) |

## Infrastructure — Pulumi

Every Pulumi project package (app stacks, foundation stages, platform projects)
carries the same nine verbs, generated by the `pulumi_project` macro:

```
bazel run //<project-package>:{setup,preview,up,refresh,destroy,config,stack,state,import}
```

- **Identity is injected, never ambient** — the wrapper resolves the correct GCP
  account per project from `infrastructure/gcp-identities.tsv` and fails fast if it
  isn't logged in.
- `:preview` is your everyday verb. `:up` from a workstation is **break-glass only** —
  the pipeline is the trigger for applies
  ([Principles §2.14](../engineering/application-development-principles.md#214-the-pipeline-is-the-only-trigger-nothing-waits-on-a-humans-keystroke)).
- `:import` is the one sanctioned local state-write: adopting an existing cloud
  resource into state.

Project packages include:
- `//infrastructure/pulumi/platform/repo-config` (repository configuration, GitHub settings, sync-auth credentials)
- `//infrastructure/pulumi/platform/{dev-local,zitadel-apps,zitadel-apps-mcp-slack}`
- `//infrastructure/pulumi/foundation/...` (all stages × environments: org-folders, gcp-projects, etc.)
- `//apps/suites/tabula/infra/{identity,build,data,app}`
- `//apps/web/oauth-user-inspector/infra/{identity,app}`

Full estate map: [infrastructure reference](../infrastructure/reference.md).

Additional tooling:

| Target | What it does |
|---|---|
| `//tools/pulumi:create-app` | One-time repo-level GitHub App manifest-flow bootstrap for Pulumi Cloud / GitHub provider integration |

## Infrastructure — GitOps & cluster

| Target | What it does |
|---|---|
| `//tools/gitops:{apply,delete,diff,get,patch,status,helm,kubeseal}` | kubectl/helm/kubeseal passthroughs with the right kubeconfig baked in |
| `//gitops/argocd/platform/<component>:{apply,diff,delete}` | Per-component manifest ops (cert-manager, cilium, cnpg, prometheus, grafana, …) |
| `//tools/gitops:sealed-secrets-{backup,restore,verify}` | Bitwarden-backed custody of the sealed-secrets controller keys — **losing these loses every sealed secret** |
| `//tools/gitops:argocd-secret-{backup,restore,verify}` | Same custody pattern for the ArgoCD server secret |
| `//tools/gitops:headscale` | Full operational CLI for Headscale tailnet control plane (`-- <args...>`) |
| `//tools/gitops:headscale-apikey-{create,list,expire}` | Manage Headscale API keys |
| `//tools/gitops:headscale-user-{create,list,destroy}` | Manage Headscale user accounts |
| `//tools/gitops:headscale-node-{list,register,delete}` | Manage registered tailnet machines |
| `//tools/gitops:headscale-preauthkey-{create,list}` | Mint and list pre-authentication keys for node onboarding |
| `//tools/gitops:ntfy-bootstrap-users` | One-time user provisioning for self-hosted ntfy instance |
| `//tools/gitops:ntfy-user-{list,add,del,change-pass,change-role,access}` | Full user lifecycle and topic ACL permissions management for ntfy |
| `//tools/gitops:seal-alert-ntfy` | Encrypt and seal the alert delivery endpoint for Alertmanager |
| `//tools/gitops:seal-argocd-backstage-token` | Mint and seal read-only ArgoCD token for Backstage UI |
| `//tools/gitops:seal-headplane-secret` | Generate and seal 32-character cookie secret for Headplane |
| `//tools/gitops/appset-render:appset-render` | Offline local rendering of ArgoCD ApplicationSets for syntax and generator validation |
| `//tools/cluster:{kubectl,cordon,uncordon,drain,delete-node,label-node}` | Live-node operations |
| `//tools/cluster:{balance,placement,minio-status}` | Read-only cluster diagnostics |

Remember the GitOps rule: these are for diffing, diagnostics, and sanctioned
break-glass — the cluster's source of truth is git, reconciled by ArgoCD.

## Secrets & Cloud Identity

| Target | What it does |
|---|---|
| `//tools/gcp-secrets:status -- <app-infra-dir>` | Which GCP Secret Manager secrets still need a value |
| `//tools/gcp-secrets:seed` | Seed/rotate a secret value — **value on stdin**, never argv or logs |
| `//tools/sync-env-secrets:{apply,set,bw-push,bw-pull,unlock,lock}` | Sync GitHub Actions environment secrets from the Bitwarden-backed store |
| `//tools/sync-env-secrets:{agent-keys-pull,agent-keys-push}` | Sync GitHub App private keys for bot identities (`atlas`, `quill`, etc.) to/from Bitwarden |
| `//tools/gcp-token` | Mints short-lived GCP access tokens over the tailnet on-demand when the current machine has no local credentials (essential for cloud sessions) |
| `//tools/cloud-bootstrap` | Bootstraps a bare cloud sandbox into an authenticated developer environment (`:whoami`, `:profiles`, `:install`, `:auth`) |
| `//tools/rotate-buildbuddy-key` | Guided BuildBuddy API key rotation |
| `//tools/saas-cli:{neon,upstash,whoami}` | Pre-authenticated vendor CLIs for troubleshooting. **Read-mostly** — provisioning belongs to the Pulumi data stacks, not these CLIs |

The three-tier secrets model itself (Secret Manager / sealed-secrets / env-injected
stack config) is in [CONTRIBUTING §7](../../CONTRIBUTING.md#7-secrets-handling).

## Ship: deploy, release, mirror

| Target | What it does |
|---|---|
| `//tools/ci:gen` (or `//tools/delivery/gen:gen`) | Regenerates the declarative delivery workflow (`.github/workflows/delivery.yaml`) from declared units |
| `//tools/delivery/orchestrate` | The decision and execution engine for graph-affected deployments on push to `main` |
| `//tools/pipeline/plan` / `//tools/pipeline/gen` | Computes affected units and generates presubmit matrix jobs from `.pipeline.json` manifests |
| `//tools/deploy:cloud-run` | The generic blue-green sequencer (candidate at 0% → smoke → promote). The reusable deploy workflow calls exactly this, so the same rollout runs from a workstation when Actions is down |
| `//apps/suites/tabula/infra/app:deploy`, `//apps/web/oauth-user-inspector/infra/app:deploy` | Per-app wrappers with service/region/smoke baked in; support `--dry-run` |
| `//tools/preview:provision-preview` | Provisions ephemeral PR preview environments (allocates Neon Postgres branch, provisions stack, posts PR comment) |
| `//tools/preview:neon-branch` / `:pr-comment` | Standalone Neon database branch management and PR comment reporting for preview environments |
| `//tools/charts:publish` | Packages and publishes changed Helm charts across apps to GitHub Container Registry (GHCR) |
| `//apps/suites/tabula/api:image_push` | Push the API image to Artifact Registry |
| `//apps/suites/tabula/api:migrate_deploy_bin` | Prisma migrations (`--phase expand` / `--phase contract`) |
| `//tools/release:publish-local` | Break-glass local publisher for mirror releases (dry-run by default; `--execute` to publish) |
| `//tools/copybara/sync -- export <component>` | Drive a mirror export (CI does this on push; local = break-glass) |
| `//tools/copybara/sync -- import_pr <component> <pr>` | Import an external mirror PR as a monorepo PR |

## App binaries (inner loop)

`//apps/suites/tabula/cli:tabcli` · `//apps/suites/tabula/api:api_bin` · `//apps/cli/devx:devx` ·
`//apps/cli/homelab/cmd/homelab` · `//apps/desktop/nexus-agent:bot` · macOS app:
`bazel build --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgent`.

## CI helper scripts (context, not targets)

`tools/ci/` holds the scripts the pipeline calls: `affected-targets.sh` (what to
test), `deploy-affected.sh` (whether to deploy — fail-open), `migration-safety.sh`,
`gitops-validate.sh`, `bisect-culprit.sh`, and friends. You rarely run these by hand;
read [CI/CD approach](../engineering/ci-cd-approach.md) for how they fit together.
