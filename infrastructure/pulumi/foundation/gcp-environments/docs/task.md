# Tasks: Promote 2-environments to Live Foundation

## Source Code
- [x] Create `infrastructure/pulumi/foundation/gcp-environments/` directory
- [x] Copy and refactor `main.go` (single env per stack)
- [x] Copy `env_baseline.go` 
- [x] Update `Pulumi.yaml` (rename project)
- [x] Create `Pulumi.development.yaml`
- [x] Create `Pulumi.nonproduction.yaml`
- [x] Create `Pulumi.production.yaml`
- [x] Copy and update `config_test.go`
- [x] Copy `go.mod` / `go.sum` and adjust module path
- [x] Create `release-please-config.json`
- [x] Create `.release-please-manifest.json`

## CI/CD
- [x] Create `.github/workflows/foundation-env-deploy.yaml` (reusable)
- [x] Update `.github/workflows/foundation-release.yaml` (add environments jobs)

## Configuration
- [x] Update `infrastructure/gcp-identities.tsv`
- [x] Update `infrastructure/pulumi/.gitignore`
- [x] Add GitHub Environments in code (repo_config)

## Documentation
- [x] Create `docs/foundation-promotion-strategies.md`
- [x] Add architecture diagram to Option C

## Verification
- [x] Build succeeds (`bazel build`)
- [x] PR #724 — merged ✅
- [x] PR #725 — merged ✅
