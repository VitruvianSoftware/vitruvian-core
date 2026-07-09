# Foundation Port Audit v2 — With Responses to All Comments

> **Audit Date**: 2026-07-08 (updated 2026-07-09)
> **Scope**: Phases 0–3 (Bootstrap, Organization, Environments, Networks)

---

## Comment Responses

Each response addresses a specific comment from the review, in order.

---

### 1. `enforce_org_billing_creator` — Deprovisioning the TF Foundation

> *"What will happen when I deprovision the original live terraform foundation later on? How can our live pulumi take ownership?"*

The upstream TF bootstrap creates an **authoritative** `roles/billing.creator` binding at the org level — meaning it controls the complete member list for that role. When the TF foundation is deprovisioned (`terraform destroy`), that authoritative binding is removed, and nobody would have `roles/billing.creator` at the org level.

**To take ownership**: Before deprovisioning TF, flip `enforce_org_billing_creator` to `true` in the Pulumi live config and run `pulumi up`. This will make Pulumi's authoritative binding take over. Then destroy TF safely. The transition order matters: **Pulumi claims → TF releases**.

---

### 2. `kms_key_protection_level` — Why Diverged

> *"I don't understand why this diverged."*

This is **not a functional divergence** — it's a backward-compatible enhancement. Upstream hardcodes `SOFTWARE` protection level for KMS keys. Our Pulumi code defaults to `SOFTWARE` (identical to upstream) but also exposes a config knob to allow `HSM` if needed. The default behavior is identical to upstream. No fix needed — this is additive.

---

### 3. Flattened Groups Config

> *"I'm not sure the benefits or drawbacks, but ultimately I want ease of maintenance."*

**Upstream TF**: Uses a nested object variable `var.groups` with sub-fields (`create_required_groups`, `billing_project`, `billing_data_users`, `audit_data_users`, `monitoring_workspace_users`).

**Our Pulumi**: Flattens these into individual config keys (`group_billing_project`, `group_billing_data_users`, etc.).

**Maintenance tradeoff**: Individual keys are simpler to read/set in YAML config files but require remembering each key name. A nested struct is more discoverable but harder to set in Pulumi YAML configs. The current approach is fine for maintenance — no change needed.

---

### 4. `gcp-policies` — Do We Manage GCP Policies?

> *"Do we manage any gcp policies at all? If not, I would consider this a major gap."*

**Yes, we manage all 19 GCP org policies** (14 boolean + 5 list constraints) — these are **deployed and enforced** in Phase 1 with full upstream parity.

The `policy-library/` in upstream is a **different thing** — it's an OPA/Rego-based policy validation framework (28 constraint YAMLs + 81 Rego templates) used by Cloud Build pipelines to validate Terraform plans *before* apply via `gcloud terraform vet`. It's a CI/CD guardrail, not runtime infrastructure.

Since we use GitHub Actions (not Cloud Build), this specific pipeline step doesn't apply directly. However, the concept of pre-apply policy validation is still valuable. **Severity: Low** — this is a CI/CD enhancement opportunity, not a deployed infrastructure gap.

---

### 5. `time_sleep` vs `DependsOn` — Exact Count Comparison

> *"Shouldn't we use pulumi's native DependsOn exactly where upstream uses it? I want the exact count."*

These are **two different mechanisms** that serve different purposes:

- **`depends_on`** = explicit ordering (resource B waits for resource A to finish)
- **`time_sleep`** = artificial delay for GCP API propagation (wait 30-60s for IAM/VPC-SC to propagate internally in Google's systems)

In Pulumi, `depends_on` → `pulumi.DependsOn()`, and `time_sleep` → `time.NewSleep()`.

#### Exact `time_sleep` Count

| Phase | Upstream TF `time_sleep` | Our Example `time.NewSleep` | Our Live `time.NewSleep` | Gap |
|-------|--------------------------|-------|------|-----|
| 0-Bootstrap | 1 (Cloud Builder, 30s) | 0 | 0 | ✅ CB-specific, N/A |
| 1-Org | 3 (logs_export 30s, billing SA 30s, KMS IAM 60s) | 0 | 0 | ⚠️ Missing |
| 1-Org (cai-monitoring) | 1 (bucket creation 30s) | 0 | 0 | ⚠️ Missing |
| 2-Environments | 1 (folder destroy 60s, destroy-only) | 0 | 0 | ✅ Pulumi handles |
| 3-Networks | 2 (VPC-SC propagation 60s create+destroy, in both H&S and SVPC) | 2 (60s create-only) | 0 | 🔴 Missing |
| 4-Projects | 1 (IAM propagation 60s) | N/A | N/A | N/A (Phase 4 not ported) |
| 5-App-Infra | 1 (WI pool propagation 60s) | N/A | N/A | N/A (Phase 5 not ported) |
| **Total (Phases 0-3)** | **8** | **2** | **0** | **6 missing** |

#### Exact `depends_on` Count

| Phase | Upstream TF `depends_on` | Our Example `DependsOn` | Our Live `DependsOn` |
|-------|--------------------------|-------------------------|----------------------|
| 0-Bootstrap | ~15 | 3 | 5 |
| 1-Org | ~14 | 3 | 3 |
| 2-Environments | 4 | 4 | 4 |
| 3-Networks (H&S) | 6 | ~28 | ~16 |
| **Total** | **~39** | **~38** | **~28** |

> [!IMPORTANT]
> The `depends_on` counts are roughly at parity. The gap is in `time_sleep` — we're missing 6 propagation delays across Phases 1-3. The Phase 1 sleeps (30s for log export, 30s for billing SA IAM, 60s for KMS IAM) should be converted to `pulumi.DependsOn` chains where the delay is for ordering, and `time.NewSleep` where genuine API propagation time is needed. The Phase 3 VPC-SC sleep (60s create + 60s destroy) must be added when VPC-SC is deployed.

---

### 6. Hub-and-Spoke SA Roles on Spoke Projects — Bug Cause?

> *"Is this the cause of some of our bugs? If so, I want us to use the exact permissions that terraform foundation uses."*

**No, this was not the cause of our bugs.** Our bugs were:
1. **Route operation race conditions** — caused by parallel route-modifying operations (fixed by explicit dependency chaining)
2. **Hub project ID mismatch** — caused by hardcoded static suffix instead of dynamic lookup (fixed by dynamic `hubProjectID`)
3. **DNS peering target mismatch** — same root cause as #2

The extra spoke SA permissions didn't cause failures. However, per your principle of matching upstream exactly: **upstream only grants these 4 roles on the hub project, not on spoke projects**. This will be fixed to match upstream.

---

### 7. CAI `roles_to_monitor` — Bug Cause?

> *"Is this the cause of some of our bugs? If so, I want us to use the exact permissions that terraform foundation uses."*

**No, and the issue is deeper than originally reported.** Research reveals that `roles_to_monitor` is **not configured at all** in our Pulumi code — neither the example nor the live foundation. Our code only creates the `cai-monitoring-builder` service account and grants it 3 roles. The actual Cloud Function deployment and `roles_to_monitor` configuration from upstream's `modules/cai-monitoring/` has **not been ported**. This wasn't causing bugs because the feature is gated by `enable_scc_resources` (set to `false` in our live config), but it's a porting gap that should be documented.

---

### 8. `createProject` Returns `ApisReady` — Explanation

> *"I don't understand the divergence nor do I understand the rationale."*

When you create a GCP project and enable APIs on it, there's a propagation delay before those APIs are actually usable. In Terraform, the `project-factory` module handles this internally — the `google_project_service` resources have implicit dependencies, and TF waits for each API enablement to complete.

In Pulumi, the live code adds an explicit gate: after all API enablement resources finish, it runs a `sleep` command (via `local.NewCommand`) to wait for propagation. The `ApisReady` resource represents "all APIs are now ready to use." Downstream resources (like the billing BigQuery dataset, which needs the BigQuery API) depend on `ApisReady` instead of the project itself.

**This is actually correct behavior** — the example is the one with the gap (it doesn't gate on API readiness, which could cause intermittent failures on first deployment). This is not a divergence from upstream intent — it's implementing the same guarantee that TF's project-factory provides internally, just explicitly.

---

### 9. No `time_sleep` — Why Not `DependsOn`?

> *"Why would we ever use a sleep timer when we should be using pulumi's native DependsOn?"*

You're right that `DependsOn` should be preferred for **ordering**. However, `time_sleep` in upstream serves a **different purpose** — it adds a mandatory delay for GCP's **eventual consistency**. Some examples:

- **VPC-SC perimeters**: After creating all networking resources, GCP needs ~60s to propagate the VPC configuration before a service perimeter can be applied. `DependsOn` ensures the perimeter is created *after* the VPC, but doesn't add the delay GCP needs internally.
- **IAM bindings**: After granting an IAM role, GCP can take 30-60s to propagate it. A `DependsOn` ensures ordering but the downstream resource might still fail because the IAM role hasn't propagated yet.

**Bottom line**: Use `DependsOn` for ordering (always). Use `time.NewSleep` only where upstream uses `time_sleep` for genuine API propagation delays. Our current live code is missing the propagation delays where upstream has them.

---

### 10. Config from Pulumi Config vs StackReference — Explanation

> *"Here's another divergence and rationale that I don't understand as well."*

In TF, `data "terraform_remote_state"` reads values from another workspace's state file and returns them as **plain strings** you can use anywhere:
```hcl
local.org_id = data.terraform_remote_state.bootstrap.outputs.common_config.org_id
```

In Pulumi, `StackReference` returns **`pulumi.Output` types** which are async/deferred values. You **cannot** use them as plain Go strings:
```go
// This DOES NOT work — orgID is a pulumi.Output, not a string
orgID := stackRef.GetStringOutput(pulumi.String("org_id"))
// Cannot use orgID in: if orgID == "" { ... } or pass to non-Pulumi functions
```

So instead of reading `org_id`, `billing_account`, `project_prefix`, etc. from the bootstrap stack's outputs, we put them directly in each stack's YAML config file where they can be read as plain Go strings via `conf.Require("org_id")`.

**This is a fundamental Pulumi constraint**, not a design choice. The values that need to be used in Go control flow (conditionals, string formatting for resource names, etc.) must come from config. Values that are only passed to resource arguments can come from StackReference.

---

### 11. Example: All-in-One vs 1-Per-Env

> *"This should be fixed in our port example as well. Please confirm the fix is in place."*

**The fix is NOT in place.** The example `2-environments/main.go` still uses the all-in-one loop model:
```go
envCodes := map[string]string{"development": "d", "nonproduction": "n", "production": "p"}
for env, code := range envCodes { ... }
```
The live foundation correctly uses 1-stack-per-env. **This needs to be fixed in the example** to match the live model. Adding to the fix list.

---

### 12. `pulumi.Protect(true)` on Folders

> *"If this achieves the same objective, I would not call it a divergence."*

Agreed. Removed from the divergence list. This is simply how Pulumi implements the same `deletion_protection` guarantee that TF provides natively.

---

### 13. SharedNetwork Budget Config — Confirmation

> *"Are you absolutely positive that upstream never consumes this?"*

**Confirmed — upstream NEVER consumes it.** I searched every `.tf` file across Phase 2 (`2-environments/`) and both Phase 3 variants (`3-networks-hub-and-spoke/` and `3-networks-svpc/`). The `shared_network_budget_amount`, `shared_network_alert_spent_percents`, `shared_network_alert_pubsub_topic`, and `shared_network_budget_alert_spend_basis` variables are **defined in `variables.tf` but never referenced** in any resource or module call. This is dead code in upstream TF itself. Our faithful replication is correct.

---

### 14. Placeholder Labels

> *"I don't understand this divergence. Do we use the label or not?"*

Upstream TF **hardcodes** these labels on every project:
```hcl
labels = {
  billing_code      = "1234"
  primary_contact   = "example1"
  secondary_contact = "example2"
  ...
}
```

Our Pulumi code creates projects with labels, but **`primary_contact` and `secondary_contact` are NOT present** in our implementation at all — zero results across both example and live code. This means our projects are **missing labels** that upstream applies.

**Fix**: Add `primary_contact` and `secondary_contact` labels to our project creation. Per your instruction: `primary_contact = "james_nguyen"`, `secondary_contact = "christine_kim"` (GCP labels don't allow spaces; underscores used).

---

### 15. AssuredWorkload Zero-Value Check — Explanation

> *"I have no clue about this divergence also. Make me understand why we diverged."*

This is **not a divergence from upstream** — it's a Pulumi-specific pattern. In TF, you check `count > 0` to see if a resource was created. In Pulumi/Go, there's no `count` — instead we check if the output field was assigned:

```go
if outputs.AssuredWorkloadID != (pulumi.StringOutput{}) {
    ctx.Export("assured_workload_id", outputs.AssuredWorkloadID)
}
```

This compares the field against Go's zero value. If AssuredWorkload was not created (because `Enabled=false`), the field was never assigned and remains zero. It works correctly today. A cleaner approach would be a boolean flag, but functionally it's equivalent to TF's `count > 0` check. No fix needed.

---

### 16. VPC-SC NOT Deployed — Fix Immediately

> *"This is not an approved divergence. This is a critical bug in the porting."*

Acknowledged. Adding to the implementation plan as **Priority 1**.

---

### 17. Transitivity Always On — Not Approved

> *"This is not approved and not intentional. Fix immediately."*

Acknowledged. Upstream defaults `enable_hub_and_spoke_transitivity = false`. Will make it conditional with default `false`. Adding to fix list.

---

### 18. Route Dependency Chaining — Simple Explanation

> *"I don't understand the divergence and why our implementation is better."*

**It's not a divergence — it's solving the same problem differently because of how Pulumi works.**

GCP has a rule: only one route operation can happen at a time per VPC. Creating a route, a Cloud Router, a NAT gateway, or a VPC peering all modify routes.

- **TF**: Module-level `depends_on` naturally serializes these because TF processes one module at a time.
- **Pulumi**: Everything runs in parallel by default. Without explicit `DependsOn`, Pulumi would try to create the route, the Cloud Router, the NAT, and the peering all at once → GCP returns "route operation already in progress" (the HTTP 400 errors we saw).

Our explicit `routeDependency` variable threads each route-modifying resource to depend on the previous one, creating a serial chain. This is the **correct and necessary** way to handle GCP's constraint in Pulumi. It's not "better" — it's "required."

---

### 19. VPC-SC `time_sleep` — Why Not `DependsOn`?

> *"Why not use pulumi's DependsOn? Is this the approach upstream used?"*

Upstream uses **both** `depends_on` AND `time_sleep` together:
1. `time_sleep.wait_vpc_sc_propagation` has `depends_on = [module.main, module.peering, ...]` (ordering)
2. `time_sleep` itself adds 60s create + 60s destroy delay (propagation)
3. `module.regular_service_perimeter` has `depends_on = [time_sleep.wait_vpc_sc_propagation]` (waits for the sleep)

The `DependsOn` ensures ordering. The `time_sleep` adds the 60-second delay that GCP needs for VPC networking to fully propagate before a service perimeter can be applied. You need **both**. Our implementation should use `pulumi.DependsOn` for ordering AND `time.NewSleep` for the 60s propagation delay, matching upstream exactly.

---

### 20. Hub-and-Spoke SA Roles — Fix to Match Upstream

Fixing to grant roles only on hub project (removing spoke project grants).

---

### 21. Hub CIDRs — Upstream Confirmation

> *"Confirm with upstream H&S option."*

**Upstream H&S hub CIDRs**:
- Region1: `10.8.0.0/18`
- Region2: `10.9.0.0/18`

**Our CIDRs**:
- Region1: `10.0.64.0/18`
- Region2: `10.1.64.0/18`

This is a divergence. The original rationale was "avoid CIDR overlap with spokes" but upstream's CIDRs are designed to not overlap (`10.8.0.0/18` for hub, `10.8.64.0/18` for dev spoke — different /18 blocks within `10.8.0.0/16`). Per your principle: fixing to match upstream.

---

### 22. NAT Always Enabled — Fix

> *"Always error on the side of what upstream configured."*

Upstream defaults `nat_enabled = false` and `hub_nat_enabled = false`. Fixing to make conditional with default `false`.

---

### 23. Secondary Ranges R1+R2

> *"I highly doubt upstream only configured R1."*

**Confirmed: upstream ONLY assigns secondary ranges to R1 subnets.** Both H&S and SVPC variants:
```hcl
secondary_ranges = {
  "sb-${var.environment_code}-svpc-${var.default_region1}" = var.subnet_secondary_ranges[var.default_region1]
}
```
Region2 subnets get NO secondary ranges. This is intentional in upstream — GKE clusters are typically deployed in a single region. Per your principle: fixing to match upstream (R1 only).

---

### 24. Hub Deployed by Dev Stack — Explanation

> *"I don't understand."*

**Upstream TF**: Has 4 separate workspaces — `shared` (deploys the hub VPC), `development`, `nonproduction`, `production` (each deploys a spoke). The hub has its own isolated state.

**Our live**: Has 3 stacks — `development` (deploys hub + dev spoke), `nonproduction` (spoke only), `production` (spoke only). The `development` stack was chosen to deploy the hub because it's the first in the promotion chain (dev → nonprod → prod).

This means the hub VPC's state is bundled with the development environment's state instead of being isolated. While operationally simpler (3 stacks instead of 4), it diverges from upstream's isolation model. However, since the hub is logically shared infrastructure, bundling it with dev means a dev-environment state issue could affect the hub. Per your preference, I can add a separate `shared` stack if you'd like upstream parity.

---

### 25. Spoke Peering Export Routes

> *"I don't understand but also I don't know the upstream behavior."*

**Upstream behavior**: The peering module sets `export_peer_custom_routes = true` which means the **hub's** custom routes are exported to the spoke. `export_local_custom_routes` is NOT set (defaults to `false`) which means the **spoke's** routes are NOT exported back to the hub.

**Our live**: Has `ExportCustomRoutes=true, ImportCustomRoutes=true` on the spoke-to-hub peering, meaning BOTH directions export. This could expose spoke routes to the hub unnecessarily.

Per your principle: fixing to match upstream (hub exports to spoke, spoke does NOT export to hub).

---

### 26. Windows KMS Route

> *"Always error on the side of what upstream configured."*

Adding conditional Windows KMS route (default `false`, matching upstream).

---

### 27. Interconnect/VPN Examples

> *"Doesn't upstream leave an example that users can reference and rename to enable?"*

**Yes.** Upstream has `.tf.example` files:
- H&S: `vpn.tf.example`, `interconnect.tf.example`, `partner_interconnect.tf.example`
- SVPC: `vpn.tf.example`, `interconnect.tf.example`, `partner_interconnect.tf.example`

Our examples have `.go.example` files (correct). Our live foundation has **none**. Adding `.go.example` files to the live foundation.

---

### 28. Hierarchical FW Associations — 6 Folders

> *"Always error on the side of what upstream configured."*

Upstream associates with 6 folders: Common, Network, Bootstrap, Development, Production, Nonproduction. Fixing to match.

---

### 29. VPC-SC `time_sleep` `destroy_duration`

> *"Always error on the side of what upstream configured."*

Upstream: `create_duration = "60s"`, `destroy_duration = "60s"`. Adding both. Our example only has `create_duration`. Fixing.

---

### 30. "Via Transitivity Library" — Explanation

> *"What does this mean?"*

Upstream TF uses 4 separate modules to build the transitivity appliance:
1. `terraform-google-modules/service-accounts/google` — creates the gateway SA
2. `terraform-google-modules/vm/google//modules/instance_template` — creates the VM template
3. `terraform-google-modules/vm/google//modules/mig` — creates the managed instance group
4. `GoogleCloudPlatform/lb-internal/google` — creates the internal load balancer

Our Pulumi library bundles all 4 into a single `NewTransitivityAppliance()` call that internally creates the same resources. "Via transitivity library" means the Pulumi equivalent lives inside our `pkg/network` library component, not as separate resource calls in `main.go`.

---

### 31. "Manual `compute.NewNetworkPeering`" — Explanation

> *"What does manual mean?"*

Upstream TF uses a pre-built module (`terraform-google-modules/network/google//modules/network-peering`) that abstracts VPC peering into a single module call. Our Pulumi code creates the two peering resources **directly** using the GCP SDK:
```go
compute.NewNetworkPeering(ctx, "spoke-to-hub", ...)
compute.NewNetworkPeering(ctx, "hub-to-spoke", ...)
```
"Manual" means we're calling the GCP API resources directly rather than through a wrapper library. Functionally identical — just a different level of abstraction.

---

### 32. SVPC Mode in Live

> *"This is an option where the user chooses one or the other. Going live with H&S was what I told you we intentionally chose."*

Acknowledged. Removed from gap list. Hub-and-spoke was the intentional choice.

---

### 33-35. VPC-SC, Bridge Perimeter, Hub Proxy Subnets, Outputs — Fix Immediately

All acknowledged and added to the implementation plan below.

---

### 36. Label Contacts

> *"Add james nguyen as the primary contact and christine kim as the secondary."*

Will set `primary_contact = "james_nguyen"`, `secondary_contact = "christine_kim"` across all project labels.

---

## Complete Fix List

### Priority 1 — Critical (Fix Immediately)

| # | Fix | Phase | Scope |
|---|-----|-------|-------|
| 1 | **Deploy VPC Service Controls** in live networks (access levels, regular perimeter, bridge perimeters, `time.NewSleep` 60s create+destroy) | 3-Networks | Live |
| 2 | **Add Bridge Perimeter** (`PERIMETER_TYPE_BRIDGE`) for spoke→hub | 3-Networks | Example + Live |
| 3 | **Add hub proxy-only subnets** (`REGIONAL_MANAGED_PROXY`) for both regions | 3-Networks | Live |
| 4 | **Export missing outputs** (`subnets_secondary_ranges`, `access_level_name`, `access_level_name_dry_run`, `enforce_vpcsc`, `service_perimeter_name`, `access_context_manager_policy_id`, `dns_policy`) | 3-Networks | Live |
| 5 | **Make transitivity conditional** (default `false`, matching upstream) | 3-Networks | Example + Live |
| 6 | **Make NAT conditional** (default `false`, matching upstream) | 3-Networks | Example + Live |
| 7 | **Fix hub CIDRs** to match upstream (`10.8.0.0/18`, `10.9.0.0/18`) | 3-Networks | Example + Live |
| 8 | **Fix secondary ranges** to R1 only (matching upstream) | 3-Networks | Example + Live |
| 9 | **Fix spoke peering** export routes (spoke should NOT export custom routes to hub) | 3-Networks | Live |
| 10 | **Fix hub-and-spoke SA roles** — remove spoke project grants, hub only | 1-Org | Live |

### Priority 2 — Should Fix

| # | Fix | Phase | Scope |
|---|-----|-------|-------|
| 11 | **Add Windows KMS route** (conditional, default `false`) | 3-Networks | Example + Live |
| 12 | **Fix hierarchical FW associations** to 6 folders (matching upstream) | 3-Networks | Live |
| 13 | **Add `.go.example` files** for interconnect/VPN to live foundation | 3-Networks | Live |
| 14 | **Add `destroy_duration`** to VPC-SC `time.NewSleep` in example | 3-Networks | Example |
| 15 | **Fix labels** — add `primary_contact: "james_nguyen"`, `secondary_contact: "christine_kim"` to all project creation | All phases | Example + Live |
| 16 | **Fix example 2-environments** to use 1-stack-per-env model (matching live) | 2-Environments | Example |

### Confirmed Not Issues

| Item | Reason |
|------|--------|
| `pulumi.Protect(true)` | TF vs Pulumi difference, not a divergence |
| SVPC mode not in live | Intentional choice (H&S selected) |
| `kms_key_protection_level` | Backward-compatible enhancement, defaults match upstream |
| SharedNetwork budget dead code | Upstream bug, faithfully replicated |
| AssuredWorkload zero-value check | Pulumi-specific pattern, functionally correct |
| `gcp-policies` / policy-library | CI/CD guardrail, not deployed infrastructure |
| Config vs StackReference | Fundamental Pulumi constraint |
| `ApisReady` gate | Production hardening, matches upstream intent |

> [!IMPORTANT]
> This is a large set of changes, concentrated in Phase 3 (Networks). The most impactful is VPC-SC deployment (#1-2), which adds a security perimeter around foundation projects. I recommend tackling the fixes in priority order and deploying/verifying after each batch.

> [!WARNING]
> Fixes #7 (hub CIDRs) and #8 (secondary ranges) will change subnet CIDR ranges on the live VPCs. If any workloads are currently using these subnets, this would be a **destructive change** requiring careful migration. Please confirm whether the VPCs are currently empty before proceeding.
