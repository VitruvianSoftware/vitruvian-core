# 4-projects

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **Go**. See the [stage navigation table](../0-bootstrap/README.md) for an overview of all stages.

## Purpose

The purpose of this step is to set up the folder structure, projects, and infrastructure pipelines for applications that are connected as service projects to the Shared VPC created in the previous stage.

The stage mirrors upstream's `business_unit_1/{shared,development,nonproduction,production}` layout: each
environment is its own thin leaf Pulumi project (environment identity pinned in the leaf's `main.go`), and the
`shared` leaf owns the BU's once-per-BU, environment-independent resources. All resource logic lives in the
shared `modules/` packages (`base_env`, `infra_pipelines`, `single_project`).

For each business unit, this stage creates:

- A **business unit subfolder** under each environment folder (e.g., `fldr-development-bu1`)
- **Four project types** per business unit and environment (the `business_unit_1/<env>` leaves):
  - **SVPC-attached** (`prj-{env}-{bu}-sample-svpc`) — Connected as a service project to the Shared VPC host, with VPC-SC perimeter attachment
  - **Floating** (`prj-{env}-{bu}-sample-floating`) — Standalone project not attached to any VPC
  - **Peering** (`prj-{env}-{bu}-sample-peering`) — Project with its own VPC, subnet, DNS policy, and bi-directional peering to the Shared VPC host, with a full firewall policy including IAP secure tags
  - **Confidential Space** (`prj-{env}-{bu}-conf-space`) — (Optional) Project for Confidential Computing workloads with a dedicated workload service account and IAM bindings, attached to Shared VPC and VPC-SC perimeter
- An **infrastructure pipeline project** (`prj-c-{bu}-infra-pipeline`) under the common folder (the
  `business_unit_1/shared` leaf, via `modules/infra_pipelines`). Per the approved deviation, Go/TS foundations
  deploy app infrastructure from GitHub Actions via Workload Identity Federation; the faithful Cloud Build
  pipeline port is kept as the build-tagged reference in `modules/infra_pipelines/example_infra_pipelines.go`
- **CMEK storage** — KMS keyring, crypto key, and CMEK-encrypted GCS bucket on the SVPC project
- **Budget alerts** on every project with configurable thresholds
- **Project labels** matching the upstream foundation's metadata convention (8 labels per project)

Running this code as-is should generate a structure as shown below:

```
example-organization/
└── fldr-development
    └── fldr-development-bu1
        ├── prj-d-bu1-sample-floating
        ├── prj-d-bu1-sample-svpc      (+ CMEK bucket, VPC-SC)
        ├── prj-d-bu1-sample-peering   (+ VPC, subnet, DNS, peering, firewall)
        └── prj-d-bu1-conf-space       (optional, Confidential Space)
└── fldr-nonproduction
    └── fldr-nonproduction-bu1
        ├── prj-n-bu1-sample-floating
        ├── prj-n-bu1-sample-svpc
        ├── prj-n-bu1-sample-peering
        └── prj-n-bu1-conf-space
└── fldr-production
    └── fldr-production-bu1
        ├── prj-p-bu1-sample-floating
        ├── prj-p-bu1-sample-svpc
        ├── prj-p-bu1-sample-peering
        └── prj-p-bu1-conf-space
└── fldr-common
    └── prj-c-bu1-infra-pipeline       (business_unit_1/shared)
```

## Prerequisites

1. [0-bootstrap](../0-bootstrap/README.md) executed successfully.
1. [1-org](../1-org/README.md) executed successfully.
1. [2-environments](../2-environments/README.md) executed successfully.
1. [3-networks](../3-networks-svpc/README.md) executed successfully.

**Note:** As mentioned in the [0-bootstrap README](../0-bootstrap/README.md), make sure that you have requested at least 50 additional projects for the **projects step service account** (`sa-terraform-proj`), otherwise you may face a project quota exceeded error.

### Troubleshooting

See [troubleshooting](../docs/TROUBLESHOOTING.md) if you run into issues during this step.

## Usage

### Deploying with GitHub Actions

1. Each environment is its own thin leaf Pulumi project under `business_unit_1/`
   (mirroring upstream `4-projects/business_unit_1/<env>`); the environment
   identity is pinned in each leaf's `main.go`. Deploy the `shared` leaf first
   (the BU's common infra-pipeline project), then the env leaves in promotion
   order. Navigate to a leaf and initialize its stack:

   ```bash
   cd 4-projects/business_unit_1/shared
   pulumi stack init production
   ```

1. Set the required configuration for the `shared` leaf:

   ```bash
   pulumi config set business_code "bu1"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT_ID"
   pulumi config set org_stack_name "organization/vitruvian/foundation-org-shared/production"
   ```

1. For each env leaf (`business_unit_1/development`, `business_unit_1/nonproduction`,
   `business_unit_1/production`), initialize its `production` stack and set:

   ```bash
   cd ../development
   pulumi stack init production
   pulumi config set business_code "bu1"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT_ID"
   pulumi config set org_stack_name "organization/vitruvian/foundation-org-shared/production"
   pulumi config set env_stack_name "organization/vitruvian/foundation-environments-development/production"
   # network_stack_name defaults to the matching 3-networks-svpc leaf
   # (derived by name substitution); hub-and-spoke users set it explicitly:
   # pulumi config set network_stack_name "organization/vitruvian/foundation-3-networks-hub-and-spoke-development/production"
   ```

1. (Optional) Override prefixes and feature toggles:

   ```bash
   # Prefixes
   pulumi config set project_prefix "prj"     # default: prj
   pulumi config set folder_prefix "fldr"      # default: fldr

   # Budget
   pulumi config set budget_amount 1000         # default: 1000
   pulumi config set budget_spend_basis "FORECASTED_SPEND"  # default

   # VPC-SC
   pulumi config set enforce_vpcsc true          # default: true

   # Peering network
   pulumi config set peering_enabled true        # default: true
   pulumi config set peering_iap_fw_rules_enabled true  # default: true
   pulumi config set subnet_region "us-central1"
   pulumi config set subnet_ip_range "10.3.64.0/21"

   # CMEK storage
   pulumi config set cmek_enabled true           # default: true
   pulumi config set keyring_name "bu1-sample-keyring"
   pulumi config set key_rotation_period "7776000s"

   # Cold-deploy API propagation wait (seconds; 0 disables)
   pulumi config set api_propagation_seconds 120  # default: 120

   # Metadata (applied as project labels)
   pulumi config set primary_contact "example@example.com"
   pulumi config set billing_code "1234"
   ```

1. Preview and deploy:

   ```bash
   pulumi preview
   pulumi up
   ```

1. **Repeat for each env leaf** (`nonproduction`, `production`).

1. Proceed to the [5-app-infra](../5-app-infra/README.md) step.

### Adding Additional Business Units

A business unit is **data plus a directory**, not new module code: copy the
`business_unit_1` leaf tree to `business_unit_2` (as upstream does) and re-point
its identifiers. Nothing under `modules/` changes.

```bash
cp -r business_unit_1 business_unit_2
```

Then, in **each** of the four leaves (`shared`, `development`, `nonproduction`,
`production`), rename the identifiers that carry the BU:

| File | Change |
| --- | --- |
| `go.mod` | `module foundation-projects-bu2-<leaf>` — keep the `replace … => ../../modules` line, copy `go.sum` verbatim |
| `Pulumi.yaml` | `name: foundation-projects-bu2-<leaf>` (the stack name is derived from this, so it must be unique per BU) |
| `Pulumi.<stack>.yaml` | re-namespace **every** key to `foundation-projects-bu2-<leaf>:` and set `business_code: "bu2"` |
| `config_test.go` | flip the `"bu1"` assertions to `"bu2"` |
| `BUILD` | point `pulumi_project(dir = …)` at the new path |

`main.go`, `remote.go`, `config.go` and `outputs.go` are copied **unchanged** —
the environment is pinned per leaf and the BU identity is config-driven.

Choose the project types the new BU actually needs. A BU that only hosts a
serverless app wants just the floating project:

```yaml
foundation-projects-bu2-development:oss_floating_project_enabled: "true"
foundation-projects-bu2-development:floating_project_enabled: "false"   # no -sample-floating
foundation-projects-bu2-development:svpc_project_enabled: "false"
```

Three things are easy to miss:

- **The stack-config allow-list.** `Pulumi.*.yaml` is git-ignored by default;
  add a `!…/business_unit_2/*/Pulumi.*.yaml` negation or the new BU's committed
  config is silently untracked and `cfg.Require` fails on a clean checkout.
- **The deploy workflow's concurrency group** must include the business unit —
  otherwise two BUs sharing one group serialize against each other (and a
  hardcoded `business_unit_1` path deploys the wrong leaf entirely).
- **Peering CIDRs are per-BU.** `subnet_ip_range` defaults to the same range for
  every BU; if a second BU ever enables peering it needs a distinct block.

Apply through your CI pipeline, never a local `pulumi up`.

### Running Pulumi Locally

Same process as above — navigate to each leaf, initialize, configure, and deploy.

## Configuration Reference

The environment identity (`development`, `nonproduction`, `production` — or `common` for the shared leaf) is
pinned in each leaf's `main.go`, not configured.

### Env leaves (`business_unit_1/<env>`)

| Name                           | Description                                                     | Required | Default                  |
| ------------------------------ | --------------------------------------------------------------- | :------: | ------------------------ |
| `business_code`                | Short business unit identifier (e.g., `bu1`, `bu2`)             |    ✅    | —                        |
| `billing_account`              | Billing account ID                                              |    ✅    | —                        |
| `org_stack_name`               | Fully qualified Pulumi stack name of the 1-org stage            |    ✅    | —                        |
| `env_stack_name`               | Stack name of this environment's 2-environments leaf            |    ✅    | —                        |
| `network_stack_name`           | Stack name of this environment's 3-networks leaf                |          | derived from `env_stack_name` (svpc) |
| `project_prefix`               | Project name prefix                                             |          | `"prj"`                  |
| `folder_prefix`                | Folder name prefix                                              |          | `"fldr"`                 |
| `budget_amount`                | Budget amount per project (USD)                                 |          | `1000`                   |
| `budget_spend_basis`           | Budget threshold basis: `CURRENT_SPEND` or `FORECASTED_SPEND`   |          | `"FORECASTED_SPEND"`     |
| `svpc_project_enabled`         | Deploy the SVPC-attached project                                |          | `true`                   |
| `floating_project_enabled`     | Deploy the floating project                                     |          | `true`                   |
| `peering_project_enabled`      | Deploy the peering project                                      |          | `true`                   |
| `api_propagation_seconds`      | Cold-deploy wait after enabling APIs (0 disables)               |          | `120`                    |
| `enforce_vpcsc`                | Attach SVPC project to VPC-SC perimeter                         |          | `true`                   |
| `peering_enabled`              | Deploy peering VPC infrastructure                               |          | `true`                   |
| `peering_iap_fw_rules_enabled` | Create IAP SSH/RDP firewall rules + secure tags                 |          | `true`                   |
| `subnet_region`                | Region for the peering subnet                                   |          | `"us-central1"`          |
| `subnet_ip_range`              | IP CIDR range for the peering subnet                            |          | `"10.3.64.0/21"`         |
| `firewall_enable_logging`      | Enable logging on firewall rules                                |          | `true`                   |
| `windows_activation_enabled`   | Enable Windows KMS activation egress rule                       |          | `false`                  |
| `optional_fw_rules_enabled`    | Enable load balancer health check firewall rules                |          | `false`                  |
| `confidential_space_enabled`   | Deploy Confidential Space project with workload SA              |          | `false`                  |
| `cmek_enabled`                 | Create KMS keyring + CMEK-encrypted GCS bucket                  |          | `true`                   |
| `location_kms`                 | KMS keyring location                                            |          | Same as `subnet_region`  |
| `location_gcs`                 | GCS bucket location                                             |          | `"US"`                   |
| `keyring_name`                 | KMS keyring name                                                |          | `"{bu}-sample-keyring"`  |
| `key_name`                     | KMS crypto key name                                             |          | `"crypto-key-example"`   |
| `key_rotation_period`          | Crypto key rotation period                                      |          | `"7776000s"`             |
| `primary_contact`              | Primary contact email (used in project labels)                  |          | `"example@example.com"`  |
| `secondary_contact`            | Secondary contact email (used in project labels)                |          | `"example2@example.com"` |
| `billing_code`                 | Billing code for project labels                                 |          | `"1234"`                 |
| `folder_deletion_protection`   | Prevent accidental folder deletion                              |          | `true`                   |

### Shared leaf (`business_unit_1/shared`)

| Name                        | Description                                              | Required | Default                 |
| --------------------------- | -------------------------------------------------------- | :------: | ----------------------- |
| `business_code`             | Short business unit identifier                           |    ✅    | —                       |
| `billing_account`           | Billing account ID                                       |    ✅    | —                       |
| `org_stack_name`            | Fully qualified Pulumi stack name of the 1-org stage     |    ✅    | —                       |
| `infra_pipeline_enabled`    | Deploy the app-infra pipeline project                    |          | `true`                  |
| `project_prefix`            | Project name prefix                                      |          | `"prj"`                 |
| `budget_amount`             | Budget amount (USD)                                      |          | `1000`                  |
| `api_propagation_seconds`   | Cold-deploy wait after enabling APIs (0 disables)        |          | `120`                   |
| `region`                    | Exported as `default_region`                             |          | `"us-central1"`         |

## Outputs

Each env leaf exports (matching upstream `4-projects/business_unit_1/<env>/outputs.tf`):

| Name                             | Description                                                                   |
| -------------------------------- | ----------------------------------------------------------------------------- |
| `shared_vpc_project`             | SVPC-attached project ID                                                      |
| `floating_project`               | Floating project ID                                                           |
| `peering_project`                | Peering project ID                                                            |
| `peering_network`                | Peering VPC network self-link                                                 |
| `peering_subnetwork_self_link`   | Peering subnet self-link (used by 5-app-infra for instance placement)         |
| `iap_firewall_tags`              | Map of IAP secure tag values for SSH/RDP (used by 5-app-infra for VM tagging) |
| `bucket` / `keyring` / `keys`    | CMEK bucket, KMS keyring, and crypto key names (when CMEK enabled)            |
| `confidential_space_project`     | Confidential Space project ID (when enabled)                                  |
| `confidential_space_workload_sa` | Confidential Space workload service account email (when enabled)              |

The shared leaf exports:

| Name                        | Description                                        |
| --------------------------- | -------------------------------------------------- |
| `infra_pipeline_project_id` | Infrastructure pipeline project ID                 |
| `default_region`            | Default region for pipeline resources              |

## File Structure

| File                                        | Description                                                                                                   |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `business_unit_1/shared/`                   | Thin shared leaf pinning `common`/`c`; deploys the BU's infra-pipeline project via `modules/infra_pipelines`  |
| `business_unit_1/development/`              | Thin env leaf pinning `development`/`d`; BU folder + per-env projects via `modules/base_env`                  |
| `business_unit_1/nonproduction/`            | Thin env leaf pinning `nonproduction`/`n`; BU folder + per-env projects via `modules/base_env`                |
| `business_unit_1/production/`               | Thin env leaf pinning `production`/`p`; BU folder + per-env projects via `modules/base_env`                   |

Each leaf splits per upstream's file-per-concern layout: `main.go` (main.tf —
orchestration), `config.go` (variables.tf), `remote.go` (remote.tf —
cross-stage StackReferences), `outputs.go` (outputs.tf); the modules mirror
their upstream file sets too (see each directory's README).
| `modules/base_env/`                         | Per-env project orchestrator: SVPC/floating/peering project types, CMEK, peering network, Confidential Space |
| `modules/single_project/`                   | Single-project wrapper over the project factory (labels, budget, APIs, VPC-SC, API-propagation gating)       |
| `modules/infra_pipelines/`                  | App-infra pipeline project (WIF model); Cloud Build reference port behind the `example` build tag            |
