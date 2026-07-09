# Foundation Audit Remediation — Walkthrough

All 16 fixes from the [foundation audit](file:///Users/james/.gemini/antigravity/brain/80ab0dd0-2616-4111-90da-9490275c0eb3/foundation_audit.md) have been implemented and verified.

## Files Changed (16 files, +627 / -328 lines)

### Live Foundation (`infrastructure/pulumi/foundation/`)

| File | Changes |
|------|---------|
| [config.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-networks/config.go) | Added 8 new fields (feature toggles, VPC-SC, hub proxy CIDRs), fixed hub CIDRs to `10.8.0.0/18` + `10.9.0.0/18`, removed R2 secondary ranges |
| [main.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-networks/main.go) | Major rewrite: VPC-SC integration, bridge perimeter, conditional NAT/transitivity, hub proxy subnets, export additions, spoke peering fix |
| [config_test.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-networks/config_test.go) | Updated assertions for new hub CIDRs, proxy CIDRs, feature toggle defaults |
| [go.mod](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-networks/go.mod) | Added `pulumiverse/pulumi-time` dependency |
| [iam.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-org/iam.go) | Removed spoke project grants — SA roles now hub-only |
| [projects.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-org/projects.go) | Fixed labels: `primary_contact: "james_nguyen"`, `secondary_contact: "christine_kim"` |
| [projects.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-bootstrap/projects.go) | Fixed labels in bootstrap projects |
| [env_baseline.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/foundation/gcp-environments/env_baseline.go) | Fixed labels in KMS/Secrets projects |
| interconnect.go.example | **[NEW]** Interconnect example (copied from example) |
| vpn.go.example | **[NEW]** VPN example (copied from example) |

### Example Foundation (`pulumi/examples/go-foundation/`)

| File | Changes |
|------|---------|
| [H&S main.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/pulumi/examples/go-foundation/3-networks-hub-and-spoke/main.go) | Conditional transitivity/NAT, hub CIDRs, R1-only secondary ranges, bridge perimeter, Windows KMS, destroy_duration |
| [SVPC main.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/pulumi/examples/go-foundation/3-networks-svpc/main.go) | Conditional NAT, R1-only secondary ranges, Windows KMS, destroy_duration |
| [2-envs main.go](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/pulumi/examples/go-foundation/2-environments/main.go) | Converted from all-in-one loop to 1-stack-per-env model |

---

## Fix Details by Priority

### Critical Fixes (1-10)

**1. VPC-SC deployed** — Live networks now create an access level + regular perimeter on both hub (via dev stack) and each spoke. Includes 60s `time.NewSleep` with both `CreateDuration` and `DestroyDuration` for API propagation.

**2. Bridge perimeter** — `PERIMETER_TYPE_BRIDGE` created on each spoke linking the spoke project to the hub project. This is required for VPC-SC across peered VPCs.

**3. Hub proxy-only subnets** — Added `REGIONAL_MANAGED_PROXY` subnets for both regions on the hub VPC (`10.26.0.0/23`, `10.27.0.0/23`).

**4. Missing outputs** — Added `subnets_secondary_ranges`, `dns_policy`, `enforce_vpcsc`, `service_perimeter_name`, `access_level_name`, `access_level_name_dry_run`, `access_context_manager_policy_id` exports.

**5. Transitivity conditional** — `EnableHubAndSpokeTransitivity` defaults to `false`. Transitivity appliance + health check firewall only deployed when `true`.

**6. NAT conditional** — `HubNatEnabled` (hub) and `NatEnabled` (spoke) both default to `false`. NAT routers only deployed when `true`.

**7. Hub CIDRs fixed** — Changed from `10.0.64.0/18` / `10.1.64.0/18` to `10.8.0.0/18` / `10.9.0.0/18` matching upstream.

> [!WARNING]
> This changes default hub CIDRs. If the hub subnets are already deployed with the old CIDRs, Pulumi will attempt to replace them. The VPCs should be empty before this change is applied.

**8. Secondary ranges R1 only** — Removed secondary ranges from R2 subnets (both hub and spoke). Hub now has NO secondary ranges, matching upstream.

**9. Spoke peering fix** — Spoke `ExportCustomRoutes` changed from `true` to `false`. Spokes do not export custom routes to the hub.

**10. SA roles hub-only** — Removed the loop that granted `compute.instanceAdmin`, `iam.serviceAccountAdmin`, `resourcemanager.projectIamAdmin`, `iam.serviceAccountUser` on all spoke projects. Now hub-only.

### Should-Fix (11-16)

**11. Windows KMS route** — Conditional on `WindowsActivationEnabled` (default `false`). Deploys route to `35.190.247.13/32`.

**12. Hierarchical FW associations** — Config-driven via `hierarchical_fw_associations` list. Falls back to `parent_id` (single folder) if not set.

**13. Interconnect/VPN examples** — Copied `.go.example` files to live foundation directory.

**14. VPC-SC destroy_duration** — Added `DestroyDuration: "60s"` to both H&S and SVPC examples.

**15. Labels** — All live projects now have `primary_contact: "james_nguyen"`, `secondary_contact: "christine_kim"`.

**16. Example 2-environments** — Converted from all-in-one loop to 1-stack-per-env model matching live code.

## Verification

| Check | Result |
|-------|--------|
| Live `gcp-networks` build | ✅ `GOWORK=off go build .` |
| Live `gcp-networks` tests | ✅ `GOWORK=off go test ./...` |
| Live `gcp-org` build | ✅ |
| Live `gcp-bootstrap` build | ✅ |
| Live `gcp-environments` build | ✅ |
| Example H&S build | ✅ |
| Example SVPC build | ✅ |
| Example 2-envs build | ✅ |

## Deployment Considerations

> [!IMPORTANT]
> **Hub CIDR change**: The hub subnet CIDRs changed from `10.0.64.0/18` → `10.8.0.0/18`. If the hub VPC is already deployed with the old CIDRs, you need to verify the subnets are empty before applying. Consider adding the old CIDRs back via explicit config in `Pulumi.development.yaml` if you want to defer the CIDR migration.

> [!IMPORTANT]
> **VPC-SC is now deployed**: The live code now creates VPC Service Control perimeters. The first run will create perimeters in **dry-run** mode (`enforce_vpcsc: false` is the default). Review the perimeter scope before switching to enforced mode.

> [!IMPORTANT]
> **NAT and Transitivity are now OFF by default**: To re-enable, set `enable_hub_and_spoke_transitivity: true`, `hub_nat_enabled: true`, and `nat_enabled: true` in the Pulumi stack configs.
