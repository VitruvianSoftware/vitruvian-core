# Terraform-to-Pulumi Migration Guide

This document provides operational guidance for teams migrating existing
Terraform-managed GCP infrastructure to the Pulumi foundation.

## Migration Strategies

There are three strategies for migration, each with different risk profiles:

| Strategy | Risk | Downtime | Best For |
|----------|------|----------|----------|
| **1. Import & Adopt** | Low | Zero | Existing resources that should be managed by Pulumi |
| **2. Side-by-Side** | Medium | Zero | Gradual migration while both tools coexist |
| **3. Destroy & Recreate** | High | Yes | Non-critical environments, dev/test |

---

## Strategy 1: Import & Adopt (Recommended)

Use `pulumi import` to adopt existing GCP resources into the Pulumi state
without modifying them.

### Step 1: Identify Resources to Import

List resources currently managed by Terraform:

```bash
# From your Terraform working directory
terraform state list
```

### Step 2: Map Terraform Resource Types to Pulumi

| Terraform Resource | Pulumi Resource | Import ID |
|-------------------|-----------------|-----------|
| `google_project` | `gcp.organizations.Project` | `projects/{project_id}` |
| `google_folder` | `gcp.organizations.Folder` | `folders/{folder_id}` |
| `google_project_service` | `gcp.projects.Service` | `{project_id}/{service}` |
| `google_service_account` | `gcp.serviceaccount.Account` | `projects/{project}/serviceAccounts/{email}` |
| `google_storage_bucket` | `gcp.storage.Bucket` | `{bucket_name}` |
| `google_compute_network` | `gcp.compute.Network` | `projects/{project}/global/networks/{name}` |
| `google_compute_subnetwork` | `gcp.compute.Subnetwork` | `projects/{project}/regions/{region}/subnetworks/{name}` |
| `google_kms_key_ring` | `gcp.kms.KeyRing` | `projects/{project}/locations/{location}/keyRings/{name}` |
| `google_organization_policy` | `gcp.orgpolicy.Policy` | `organizations/{org_id}/policies/{constraint}` |

### Step 3: Import Resources

```bash
# Single resource
pulumi import gcp:organizations/project:Project my-project projects/prj-b-seed-xxxx

# Bulk import from a JSON file
pulumi import -f resources.json
```

#### Bulk Import File Format (`resources.json`)

```json
{
  "resources": [
    {
      "type": "gcp:organizations/project:Project",
      "name": "seed-project",
      "id": "projects/prj-b-seed-xxxx"
    },
    {
      "type": "gcp:storage/bucket:Bucket",
      "name": "state-bucket",
      "id": "bkt-prj-b-seed-tfstate"
    }
  ]
}
```

### Step 4: Generate Code

After importing, Pulumi generates TypeScript code for each resource. Review
and integrate it into your stage's `index.ts`:

```bash
# Import generates code to stdout — redirect to a file
pulumi import gcp:organizations/project:Project seed-project projects/prj-b-seed-xxxx > imported.ts
```

### Step 5: Remove from Terraform State

After verifying the resource is correctly managed by Pulumi:

```bash
terraform state rm google_project.seed_project
```

> [!CAUTION]
> Only remove resources from Terraform state AFTER confirming they are
> successfully imported into Pulumi and `pulumi preview` shows no changes.

---

## Strategy 2: Side-by-Side Coexistence

Run Terraform and Pulumi in parallel, migrating stages incrementally.

### Architecture

```
┌─────────────────────────────────┐
│  GCP Organization               │
│                                 │
│  ┌────────────┐ ┌────────────┐  │
│  │ TF-Managed │ │ Pulumi-    │  │
│  │ Stages     │ │ Managed    │  │
│  │            │ │ Stages     │  │
│  │ 0-bootstrap│ │ 0-bootstrap│  │
│  │ 1-org      │ │ 1-org      │  │
│  │ ...        │ │ ...        │  │
│  └────────────┘ └────────────┘  │
│       ↕ Stack References ↕      │
└─────────────────────────────────┘
```

### Cross-Tool State References

Pulumi can read Terraform state to reference outputs from TF-managed stages:

```typescript
import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

// Read Terraform remote state from GCS
const tfState = new gcp.storage.BucketObject.get("tf-state", {
    bucket: "bkt-prj-b-seed-tfstate",
    name: "terraform/0-bootstrap/default.tfstate",
});
```

Alternatively, use Pulumi config to pass values between tools:

```bash
# Export from Terraform
SEED_PROJECT_ID=$(terraform output -raw seed_project_id)

# Import into Pulumi
pulumi config set seed_project_id "$SEED_PROJECT_ID"
```

### Migration Order

Migrate stages bottom-up to minimize cross-tool dependencies:

1. `5-app-infra` (leaf stage, no downstream dependents)
2. `4-projects`
3. `3-networks`
4. `2-environments`
5. `1-org`
6. `0-bootstrap` (root stage, migrate last)

---

## Strategy 3: Destroy & Recreate

For non-critical environments only.

```bash
# 1. Destroy Terraform resources
cd terraform-foundation/5-app-infra
terraform destroy

# 2. Deploy with Pulumi
cd pulumi-foundation/5-app-infra/business_unit_1/development
pulumi up
```

> [!WARNING]
> This strategy causes downtime and data loss for stateful resources
> (databases, buckets with data). Only use for ephemeral environments.

---

## State Backend Considerations

### Shared State Bucket

Both Terraform and Pulumi can use the same GCS bucket for state storage,
but with different key prefixes:

```
gs://bkt-prj-b-seed-tfstate/
├── terraform/        # Terraform state files
│   ├── 0-bootstrap/
│   └── ...
└── pulumi/           # Pulumi state files
    ├── .pulumi/
    └── ...
```

Configure Pulumi to use GCS:

```bash
pulumi login gs://bkt-prj-b-seed-tfstate/pulumi
```

### State Encryption

- **Terraform**: Entire state file encrypted at rest via GCS + optional KMS
- **Pulumi**: Per-value encryption using `--secrets-provider` with KMS

```bash
pulumi stack init production \
  --secrets-provider="gcpkms://projects/prj-b-seed/locations/us-central1/keyRings/prj-keyring/cryptoKeys/prj-key"
```

---

## Common Pitfalls

| Pitfall | Description | Mitigation |
|---------|-------------|------------|
| **Duplicate Resource** | Both tools try to manage the same resource | Always `terraform state rm` before `pulumi import` |
| **IAM Drift** | Concurrent IAM changes from both tools | Migrate IAM bindings atomically per resource |
| **State Corruption** | Manually editing state files | Use `pulumi import` / `terraform state rm` exclusively |
| **Provider Version Mismatch** | TF and Pulumi using different GCP provider versions | Pin to compatible versions during migration |
| **Missing `protect`** | Imported resources lack deletion protection | Add `{ protect: true }` to critical resources |

## Verification Checklist

After migrating each stage:

- [ ] `pulumi preview` shows **no changes** (clean state)
- [ ] `terraform plan` shows **no changes** (if TF state was cleaned)
- [ ] All outputs match between old TF and new Pulumi
- [ ] CI/CD pipeline passes end-to-end
- [ ] Downstream stages still reference correct outputs
