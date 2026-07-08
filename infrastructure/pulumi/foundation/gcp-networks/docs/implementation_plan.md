# Foundation Phase 3: Hub-and-Spoke Networks (`gcp-networks`)

Promote the hub-and-spoke network architecture to the live foundation, following the same one-env-per-stack pattern and chained promotion workflow established by `gcp-environments`.

## Background

The `gcp-org` phase already creates:
- **Hub project** (`prj-net-hub`) — conditional on `enable_hub_and_spoke: true` (currently enabled)
- **Per-env spoke projects** (`prj-d-svpc`, `prj-n-svpc`, `prj-p-svpc`)
- **Hub IAM bindings** for `sa-terraform-net`
- The SA `sa-terraform-net` and its WIF base bindings (`foundation-net`, `foundation-net-preview`) already exist

What's **missing** is the actual network infrastructure inside those projects — VPCs, subnets, firewall rules, Cloud NAT, Cloud Routers, DNS, VPC peering between hub and spokes, and Private Service Connect.

> [!IMPORTANT]
> The upstream Go example (`pulumi_go-example-foundation/3-networks-hub-and-spoke`) has several known gaps documented in [GAPREPORT.md](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/docs/gap-analysis/port-cft-pulumi/GAPREPORT.md) (hardcoded subnet CIDRs, missing VPC-SC on hub, missing internet egress route, etc.). This plan creates a correct implementation, but the initial deployment will be scoped to the core network topology — VPCs, subnets, firewall, NAT, DNS, and peering. VPC Service Controls can be added incrementally after the base network is operational.


## Proposed Changes

### Pulumi Project (`gcp-networks`)

#### [NEW] `infrastructure/pulumi/foundation/gcp-networks/Pulumi.yaml`
Project definition (`name: foundation-networks`).

#### [NEW] `infrastructure/pulumi/foundation/gcp-networks/main.go`
One-env-per-stack entrypoint following the `gcp-environments` pattern:
- Reads `env` / `env_code` from per-stack config
- Stack references to `gcp-org` (for project IDs, hub project, network folder) and `gcp-environments` (for env folder)
- Calls `deployNetworkBaseline()` for the spoke
- Calls `deployHubNetwork()` for the hub (only in the `development` stack, since the hub is shared across all environments — or alternatively each stack can be idempotent about the hub)
- Exports: `network_name`, `network_self_link`, `subnets`, `nat_ip_addresses`

#### [NEW] `infrastructure/pulumi/foundation/gcp-networks/config.go`
`NetworkConfig` struct with all configurable fields:
- `Env`, `EnvCode`, `OrgID`, `BillingAccount`
- `DefaultRegion`, `SecondaryRegion`
- `OrgStackName`, `EnvStackName` (for stack references)
- `EnableHubAndSpoke` (always true for this topology)
- Subnet CIDR ranges (configurable per-env via stack config)
- DNS, NAT, firewall settings

#### [NEW] `infrastructure/pulumi/foundation/gcp-networks/spoke_network.go`
Per-environment spoke VPC deployment:
- **Shared VPC**: Enable the spoke project as a Shared VPC host
- **VPC Network**: `vpc-{env_code}-svpc` with `delete_default_routes_on_create: true`
- **Subnets**: Primary subnet + secondary ranges (pods/services for GKE)
- **Cloud Router** (×2 regions): BGP routers with custom advertised ranges
- **Cloud NAT** (×2 regions): NAT gateway with manual IP allocation
- **Firewall rules**: Foundation rules (deny all egress, allow internal, allow Windows KMS)
- **DNS Policy**: Enable inbound DNS forwarding
- **Private Service Connect**: PSC endpoint + DNS zones for `googleapis.com`, `gcr.io`, `pkg.dev`
- **Private Service Access**: Reserved IP range + service networking connection
- **VPC Peering**: Bidirectional peering between spoke VPC and hub VPC

#### [NEW] `infrastructure/pulumi/foundation/gcp-networks/hub_network.go`
Hub VPC deployment (runs once, shared across envs):
- **VPC Network**: `vpc-net-hub` with `delete_default_routes_on_create: true`
- **Hub subnet**: Small subnet for management/transitivity
- **Cloud Router + NAT**: Hub-level NAT for centralized egress
- **DNS Hub**: Central DNS zone that spokes peer to
- **Firewall rules**: Hub-level foundation rules
- **Private Service Connect**: Hub PSC for restricted APIs

#### [NEW] `infrastructure/pulumi/foundation/gcp-networks/config_test.go`
Unit test for config loading (mirrors `gcp-environments/config_test.go` pattern).

#### [NEW] `infrastructure/pulumi/foundation/gcp-networks/go.mod`
Standalone module (NOT in `go.work`). Dependencies:
- `pulumi-gcp/sdk/v9`, `pulumi/sdk/v3`
- `pulumi-library/go/pkg/project_factory` (if needed for labels/APIs)

#### [NEW] Per-stack configs
- `Pulumi.development.yaml` — `env: development`, `env_code: d`, spoke CIDRs
- `Pulumi.nonproduction.yaml` — `env: nonproduction`, `env_code: n`, spoke CIDRs
- `Pulumi.production.yaml` — `env: production`, `env_code: p`, spoke CIDRs

#### [NEW] Release-please configs
- `release-please-config.json` — component `foundation-gcp-networks`
- `.release-please-manifest.json` — version `0.1.0`

#### [NEW] `BUILD`
```python
pulumi_project(name = "gcp-networks", dir = "infrastructure/pulumi/foundation/gcp-networks")
```

---

### CI/CD Workflows

#### [NEW] `.github/workflows/foundation-net-deploy.yaml`
Reusable per-environment deploy workflow — identical structure to `foundation-env-deploy.yaml` but:
- `environment: foundation-net-${{ inputs.environment }}`
- `default working_directory: infrastructure/pulumi/foundation/gcp-networks`

#### [MODIFY] `.github/workflows/foundation-release.yaml`
Add:
- `release-gcp-networks` job (release-please with `foundation-gcp-networks` component)
- Chained promotion: `deploy-net-development` → `deploy-net-nonproduction` → `deploy-net-production`

---

### WIF & Auth (Bootstrap)

#### [MODIFY] `infrastructure/pulumi/foundation/gcp-bootstrap/build_github_actions.go`
Add per-environment WIF bindings for the `net` SA (same pattern as `env`):
```go
if netSA, ok := sas["net"]; ok {
    for _, envName := range []string{"development", "nonproduction", "production"} {
        saMappings[fmt.Sprintf("net-%s", envName)] = libcicd.SAMappingEntry{...}
    }
}
```

---

### GitHub Environments (repo_config)

#### [MODIFY] `infrastructure/pulumi/platform/repo_config/main.go`
Add network-phase environments block (same pattern as env-phase):
```go
netPhaseEnvironments := []struct{ name string; requireReviewer bool }{
    {"foundation-net-development", false},
    {"foundation-net-nonproduction", true},
    {"foundation-net-production", true},
}
```
Using `foundationVars["foundation-net"]` for WIF variables.

#### [MODIFY] `infrastructure/pulumi/platform/repo_config/Pulumi.dev.yaml`
Add `foundation-net` config entry:
```yaml
foundation-net:
  GCP_PROJECT_ID: prj-b-seed-8ebb
  GCP_SERVICE_ACCOUNT: sa-terraform-net@prj-b-seed-8ebb.iam.gserviceaccount.com
  GCP_WORKLOAD_IDENTITY_PROVIDER: projects/1007864396578/.../foundation-gh-provider
```

---

### Supporting Config

#### [MODIFY] `infrastructure/gcp-identities.tsv`
Add row for `gcp-networks`.

#### [MODIFY] `infrastructure/pulumi/.gitignore`
Add:
```gitignore
!foundation/gcp-networks/Pulumi.*.yaml
/foundation/gcp-networks/foundation-networks
```

---

## Deployment Order

The deployment needs to happen in this order (same as `gcp-environments`):

1. **PR 1: Core code** — `gcp-networks` project, workflow files, supporting config
2. **PR 2: WIF bindings** — Bootstrap update (add `net-{dev,nonprod,prod}` WIF mappings)
3. **Deploy bootstrap** — Merge release-please for bootstrap, approve deploy
4. **PR 3: repo_config** — GitHub Environments + `foundation-net` vars
5. **Deploy repo_config** — Auto-deploys on merge
6. **Merge release-please for networks** — Triggers chained deploy: dev → nonprod → prod

> [!TIP]
> We can combine PRs 1+3 since repo_config auto-deploys on merge to main. The WIF bindings (PR 2) must deploy before the networks release-please PR is merged, same as the env phase.

## Verification Plan

### Automated Tests
- `go build ./...` in `gcp-networks/` (CI `build-test` job)
- `go test ./...` for config loading unit tests
- Pulumi preview in CI (PR check)

### Manual Verification
- Approve development deploy → verify VPC, subnets, NAT, DNS in GCP Console
- Approve nonproduction deploy → verify separate spoke VPC
- Approve production deploy → verify spoke-to-hub peering is bidirectional
- Verify DNS resolution via PSC endpoints
