# Walkthrough: Foundation Environments Phase

## Summary

Promoted the `2-environments` example into the live foundation and implemented a monorepo-compatible promotion workflow using Pulumi stacks + GitHub Environment protection rules. After fixing WIF and SA configuration issues, all three environments deployed successfully.

## PRs Merged

| PR | Title | Status |
|---|---|---|
| [#724](https://github.com/VitruvianSoftware/vitruvian-core/pull/724) | feat(foundation): promote 2-environments to live foundation with monorepo promotion workflow | ✅ Merged |
| [#725](https://github.com/VitruvianSoftware/vitruvian-core/pull/725) | feat(repo-config): add GitHub Environments for foundation environments phase | ✅ Merged |
| [#727](https://github.com/VitruvianSoftware/vitruvian-core/pull/727) | fix(foundation): add missing pulumi-command/sdk to gcp-environments go.sum | ✅ Merged |
| [#729](https://github.com/VitruvianSoftware/vitruvian-core/pull/729) | fix(bootstrap): add per-environment WIF bindings for environments stage | ✅ Merged |
| [#731](https://github.com/VitruvianSoftware/vitruvian-core/pull/731) | fix(repo-config): use env SA for foundation environment variables | ✅ Merged |

## Deployment Results

```
✅ deploy-env-development     (auto)
✅ deploy-env-nonproduction   (manual approval)
✅ deploy-env-production      (manual approval)
```

## Issues Encountered & Fixed

### 1. Missing `go.sum` entry (PR #727)
- **Symptom:** `go build` failed — missing checksum for `pulumi-command/sdk`
- **Root cause:** Transitive dep from `pulumi-library/project_factory` not in `go.sum`
- **Fix:** `GOWORK=off go mod tidy`

### 2. Missing WIF bindings (PR #729)
- **Symptom:** `IAM_PERMISSION_DENIED` on `iam.serviceAccounts.getAccessToken`
- **Root cause:** WIF only had a binding for `foundation-env` but the workflow sends `foundation-env-development`
- **Fix:** Added three per-environment WIF bindings in `gcp-bootstrap` mapping each to the `env` SA

### 3. Wrong service account in GitHub Environment (PR #731)
- **Symptom:** Same IAM error after WIF fix
- **Root cause:** `repo_config` was propagating `sa-terraform-org` instead of `sa-terraform-env` to the env-phase GitHub Environments
- **Fix:** Changed lookup from `foundationVars["foundation-org"]` to `foundationVars["foundation-env"]` and added the config entry

## Architecture

Each environment is a **separate Pulumi stack** with isolated state. The release workflow chains three deploys with GitHub Environment gates:

```
PR merged → release-please → dev (auto) → nonprod (approval) → prod (approval)
```

## Key Files Changed

### Foundation Stage
| File | Purpose |
|---|---|
| [main.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-environments/main.go) | One environment per stack |
| [env_baseline.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-environments/env_baseline.go) | Per-env folder, KMS, Secrets |
| [Pulumi.{development,nonproduction,production}.yaml](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-environments) | Per-stack configs |

### CI/CD
| File | Purpose |
|---|---|
| [foundation-env-deploy.yaml](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/.github/workflows/foundation-env-deploy.yaml) | Reusable deploy workflow |
| [foundation-release.yaml](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/.github/workflows/foundation-release.yaml) | Release + chained deploy jobs |

### WIF & Auth
| File | Purpose |
|---|---|
| [build_github.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go) | Per-env WIF bindings |
| [repo_config/main.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/platform/repo_config/main.go) | GitHub Environments + env SA vars |
| [Pulumi.dev.yaml](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/platform/repo_config/Pulumi.dev.yaml) | foundation-env SA config |

### Documentation
| File | Purpose |
|---|---|
| [foundation-promotion-strategies.md](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/docs/foundation-promotion-strategies.md) | All three strategies + architecture diagram |
