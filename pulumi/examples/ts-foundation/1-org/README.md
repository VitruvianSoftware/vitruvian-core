# 1-org

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **TypeScript**. See the [stage navigation table](../0-bootstrap/README.md) for an overview of all stages.

## Purpose

The purpose of this step is to set up the common folder used to house projects that contain shared resources such as Security Command Center notification, Cloud Key Management Service (KMS), org-level secrets, and org-level logging.
This stage also sets up the network folder used to house network-related projects such as DNS Hub, Interconnect, and shared VPC host projects for each environment (`development`, `nonproduction`, `production`).

This will create the following folder and project structure:

```
example-organization
└── fldr-common
    ├── prj-c-logging
    ├── prj-c-billing-export
    ├── prj-c-scc
    ├── prj-c-kms
    └── prj-c-secrets
└── fldr-network
    ├── prj-net-dns
    ├── prj-net-interconnect
    ├── prj-d-svpc
    ├── prj-n-svpc
    └── prj-p-svpc
```

### Key Resources

#### Logs

Under the common folder, a project `prj-c-logging` is used as the destination for organization-wide sinks. This includes admin activity audit logs from all projects in your organization and the billing account.

Logs are collected into a logging bucket with a linked BigQuery dataset for ad-hoc investigations, a Cloud Storage bucket for long-term archival, and Pub/Sub for streaming to external systems.

**Notes:**

- The various audit log types being captured in BigQuery are retained for 30 days.
- For billing data, a BigQuery dataset is created with permissions attached, however you will need to configure a billing export [manually](https://cloud.google.com/billing/docs/how-to/export-data-bigquery).

#### Security Command Center Notification

A project created under the common folder (`prj-c-scc`) hosts Security Command Center notification resources at the organization level. This includes a Pub/Sub topic, subscription, and an [SCC notification](https://cloud.google.com/security-command-center/docs/how-to-notifications) configured to stream all active findings. You can adjust the filter via the `scc_notification_filter` config value.

#### Organization Policies

14+ boolean constraints are enforced including: serial port access, nested virtualization, OS Login, SA key creation, public access prevention, etc.

#### Tags

Org-level environment classification tags are created and applied to the bootstrap, common, and network folders.

## Prerequisites

1. [0-bootstrap](../0-bootstrap/README.md) executed successfully.
1. To enable Security Command Center notifications, choose a Security Command Center tier and create and grant permissions for the Security Command Center service account as described in [Setting up Security Command Center](https://cloud.google.com/security-command-center/docs/quickstart-security-command-center).

### Troubleshooting

See [troubleshooting](../docs/TROUBLESHOOTING.md) if you run into issues during this step.

## Usage

Consider the following:

- This stage creates sinks to export logs to Cloud Logging, BigQuery, Pub/Sub, and Cloud Storage. This will result in additional charges for those copies of logs.
- This stage implements but does not enable [bucket policy retention](https://cloud.google.com/storage/docs/bucket-lock) for organization logs.
- To use the **hub-and-spoke** architecture, you will select the `3-networks-hub-and-spoke` stage instead of `3-networks-svpc` in the networking step.
- This stage manages contacts for notifications using [Essential Contacts](https://cloud.google.com/resource-manager/docs/managing-notification-contacts).

### Deploying with GitHub Actions

1. Clone the repository you created to host the `1-org` code at the same level of the `pulumi_ts-example-foundation` folder.

   ```bash
   git clone git@github.com:<GITHUB-OWNER>/<GITHUB-ORGANIZATION-REPO>.git gcp-org
   ```

1. Navigate into the repo. All subsequent steps assume you are running them from the `gcp-org` directory.

   ```bash
   cd gcp-org
   ```

1. Seed the repository if it has not been initialized yet.

   ```bash
   git commit --allow-empty -m 'repository seed'
   git push --set-upstream origin main

   git checkout -b production
   git push --set-upstream origin production
   ```

1. Create a working branch.

   ```bash
   git checkout -b plan
   ```

1. Copy the org stage code and pipeline templates.

   ```bash
   cp -R ../pulumi_ts-example-foundation/1-org/* .
   mkdir -p .github/workflows
   cp ../pulumi_ts-example-foundation/build/pulumi-preview.yml .github/workflows/
   cp ../pulumi_ts-example-foundation/build/pulumi-up.yml .github/workflows/
   ```

1. Install dependencies.

   ```bash
   npm install
   ```

1. Initialize the Pulumi stack and set the required configuration.

   ```bash
   pulumi stack init production

   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set bootstrap_stack_name "<PULUMI-ORG>/<PULUMI-PROJECT>/production"
   pulumi config set domains_to_allow "example.com"
   ```

1. (Optional) Check if your organization already has an Access Context Manager policy:

   ```bash
   export ORGANIZATION_ID="YOUR_ORG_ID"
   export ACCESS_CONTEXT_MANAGER_ID=$(gcloud access-context-manager policies list \
     --organization ${ORGANIZATION_ID} --format="value(name)")
   echo "access_context_manager_policy_id = ${ACCESS_CONTEXT_MANAGER_ID}"

   # If the above returns a value, set:
   pulumi config set create_access_context_manager_policy "false"
   ```

1. (Optional) Check if an SCC notification already exists:

   ```bash
   export ORG_STEP_SA=$(pulumi -C ../gcp-bootstrap stack output organization_step_terraform_service_account_email)

   gcloud scc notifications describe "scc-notify" \
     --format="value(name)" \
     --organization=${ORGANIZATION_ID} \
     --location=global \
     --impersonate-service-account=${ORG_STEP_SA}
   ```

   If it exists, set a different name:
   ```bash
   pulumi config set scc_notification_name "scc-notify-pulumi"
   ```

1. Commit and push.

   ```bash
   git add .
   git commit -m 'Initialize org repo'
   git push --set-upstream origin plan
   ```

1. Open a **pull request** in GitHub from the `plan` branch to the `production` branch and review the GitHub Action output.
1. If the action is successful, **merge** the pull request. The merge triggers `pulumi up` via the pipeline.

1. Before moving to the next step, go back to the parent directory.

   ```bash
   cd ..
   ```

1. Proceed to the [2-environments](../2-environments/README.md) step.

### Running Pulumi Locally

1. Navigate to the `1-org` directory:

   ```bash
   cd pulumi_ts-example-foundation/1-org
   ```

1. Install dependencies and initialize the stack:

   ```bash
   npm install
   pulumi stack init production
   ```

1. Set configuration as described above.

1. Preview and deploy:

   ```bash
   pulumi preview
   pulumi up
   ```

## Configuration Reference

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `org_id` | GCP Organization ID | `string` | n/a | yes |
| `billing_account` | Billing account ID | `string` | n/a | yes |
| `remote_state_bucket` | Bootstrap state bucket name or stack reference | `string` | n/a | yes |
| `project_prefix` | Name prefix for projects | `string` | `"prj"` | no |
| `folder_prefix` | Name prefix for folders | `string` | `"fldr"` | no |
| `default_region` | Default region for resources | `string` | `"us-central1"` | no |
| `parent_folder` | Optional parent folder ID | `string` | `""` | no |
| `enable_hub_and_spoke` | Enable Hub and Spoke network mode | `boolean` | `false` | no |
| `domains_to_allow` | Domains allowed in domain-restricted sharing policy | `string[]` | `[]` | no |
| `scc_notification_name` | Name for the SCC notification config | `string` | `"scc-notify"` | no |
| `scc_notification_filter` | Filter for SCC notifications | `string` | `"state = \"ACTIVE\""` | no |
| `create_unique_tag_key` | Create a unique tag key name | `boolean` | `false` | no |
| `enable_cai_monitoring` | Enable Cloud Asset Inventory monitoring | `boolean` | `false` | no |
| `log_export_storage_force_destroy` | Allow destroying log export bucket with objects | `boolean` | `false` | no |
| `log_export_storage_versioning` | Enable versioning on log export bucket | `boolean` | `false` | no |
| `project_deletion_policy` | Deletion policy for created projects | `string` | `"PREVENT"` | no |
| `folder_deletion_protection` | Prevent destroying folders | `boolean` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `common_folder_name` | Common folder ID |
| `network_folder_name` | Network folder ID |
| `logging_project_id` | Centralized logging project ID |
| `billing_export_project_id` | Billing export project ID |
| `scc_project_id` | SCC notifications project ID |
| `org_audit_logs_project_id` | Audit logs project ID |
| `dns_hub_project_id` | DNS hub project ID |
| `interconnect_project_id` | Interconnect project ID |
| `scc_notification_name` | SCC notification configuration name |
| `tags` | Organization-level tags |

## File Structure

| File | Description |
|------|-------------|
| `index.ts` | Orchestrates the org stage: folders, projects, policies, logging, SCC, tags, CAI monitoring |
| `config.ts` | Configuration loading for organization-level settings |
