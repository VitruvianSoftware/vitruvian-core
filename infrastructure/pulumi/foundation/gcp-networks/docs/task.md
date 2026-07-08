# Task: Foundation Phase 3 — Hub-and-Spoke Networks

## Phase A: Scaffolding & CI/CD (no GCP resources yet)
- [x] Create `gcp-networks/Pulumi.yaml`
- [x] Create `gcp-networks/go.mod`
- [x] Create `gcp-networks/main.go` (config + entrypoint skeleton)
- [x] Create `gcp-networks/config.go` (NetworkConfig struct)
- [x] Create `gcp-networks/config_test.go`
- [x] Create per-stack configs (`Pulumi.{development,nonproduction,production}.yaml`)
- [x] Create `release-please-config.json` + `.release-please-manifest.json`
- [x] Create `BUILD` file
- [x] Update `infrastructure/gcp-identities.tsv` (via subagent)
- [x] Update `infrastructure/pulumi/.gitignore` (via subagent)

## Phase B: Network Resources
- [x] Create hub + spoke network code in `main.go` (hub VPC, spoke VPC, peering, DNS, NAT, firewall, PSC, transitivity)
- [x] Run `go mod tidy` and verify `go build`

## Phase C: CI/CD Workflows
- [x] Create `.github/workflows/foundation-net-deploy.yaml` (via subagent)
- [x] Update `.github/workflows/foundation-release.yaml` (via subagent)

## Phase D: WIF & Auth
- [x] Update `gcp-bootstrap/build_github_actions.go` (per-env WIF bindings for net SA — via subagent)
- [x] Update `repo_config/main.go` (GitHub Environments for net phase — via subagent)
- [x] Update `repo_config/Pulumi.dev.yaml` (foundation-net vars — via subagent)

## Phase E: PR, Deploy, Verify
- [x] Verify Go build passes
- [x] Run tests
- [x] Create PR for all changes
- [x] Watch CI checks
- [x] Merge PR → merge release-please PRs
- [x] Deploy bootstrap (WIF bindings)
- [x] Deploy repo_config (GitHub environments)
- [/] Deploy networks: dev → nonprod → prod
- [ ] Verify resources in GCP Console
- [ ] Update walkthrough
