# 0-bootstrap

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **TypeScript**. The following table lists the stages of this deployment.

<table>
<tbody>
<tr>
<td>0-bootstrap (this file)</td>
<td>Bootstraps a Google Cloud organization, creating all the required resources
and permissions to start using Infrastructure as Code with Pulumi. This
step also configures a <a href="../docs/GLOSSARY.md#foundation-cicd-pipeline">CI/CD pipeline</a> for foundations code in subsequent
stages.</td>
</tr>
<tr>
<td><a href="../1-org">1-org</a></td>
<td>Sets up top-level shared folders, networking projects, and
organization-level logging, and sets baseline security settings through
organizational policy.</td>
</tr>
<tr>
<td><a href="../2-environments"><span style="white-space: nowrap;">2-environments</span></a></td>
<td>Sets up development, nonproduction, and production environments within the
Google Cloud organization that you've created.</td>
</tr>
<tr>
<td><a href="../3-networks-svpc">3-networks-svpc</a></td>
<td>Sets up shared VPCs with default DNS, NAT, Private Service networking,
and baseline firewall rules for each environment.</td>
</tr>
<tr>
<td><a href="../3-networks-hub-and-spoke">3-networks-hub-and-spoke</a></td>
<td>Alternative to 3-networks-svpc using the Hub and Spoke network model.</td>
</tr>
<tr>
<td><a href="../4-projects">4-projects</a></td>
<td>Sets up a folder structure, projects, and application infrastructure pipeline for applications.</td>
</tr>
<tr>
<td><a href="../5-app-infra">5-app-infra</a></td>
<td>Deploys sample application infrastructure in one of the business unit projects.</td>
</tr>
</tbody>
</table>

For an overview of the architecture and the parts, see the
[pulumi-example-foundation README](../README.md).
For a consolidated walkthrough of all stages, see [ONBOARDING.md](../ONBOARDING.md).

## Purpose

The purpose of this step is to bootstrap a Google Cloud organization, creating all the required resources and permissions to start using the Pulumi Foundation. This step also configures a [CI/CD Pipeline](../docs/GLOSSARY.md#foundation-cicd-pipeline) for foundations code in subsequent stages using GitHub Actions.

The bootstrap step creates:

- The **`prj-b-seed`** project, which contains the following:
  - A KMS-encrypted GCS bucket for Pulumi state storage
  - Custom service accounts used by Pulumi to create new resources in Google Cloud (one per stage: `bootstrap`, `org`, `env`, `net`, `proj`)
- The **`prj-b-cicd`** project, which contains the following:
  - CI/CD pipeline infrastructure (Workload Identity Federation for GitHub Actions)
- The **`fldr-bootstrap`** folder under your organization (or parent folder) that contains both projects

It is a best practice to separate concerns by having two projects here: one for the Pulumi state and one for the CI/CD tool.

After executing this step, you will have the following structure:

```
example-organization/
└── fldr-bootstrap
    ├── prj-b-cicd
    └── prj-b-seed
```

## Prerequisites

To run the commands described in this document, install the following:

- [Google Cloud SDK](https://cloud.google.com/sdk/install) version 393.0.0 or later
- [Pulumi CLI](https://www.pulumi.com/docs/install/) version 3.0 or later
- [Node.js](https://nodejs.org/) version 18+ (LTS recommended)
- [npm](https://www.npmjs.com/) version 9+
- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) version 2.28.0 or later

Also make sure that you've done the following:

1. Set up a Google Cloud
   [organization](https://cloud.google.com/resource-manager/docs/creating-managing-organization).
1. Set up a Google Cloud
   [billing account](https://cloud.google.com/billing/docs/how-to/manage-billing-account).
1. Create Cloud Identity or Google Workspace groups as defined in [groups for access control](https://cloud.google.com/architecture/security-foundations/authentication-authorization#groups_for_access_control).
1. For the user who will run the procedures in this document, grant the following roles:
   - The `roles/resourcemanager.organizationAdmin` role on the Google Cloud organization.
   - The `roles/orgpolicy.policyAdmin` role on the Google Cloud organization.
   - The `roles/resourcemanager.projectCreator` role on the Google Cloud organization.
   - The `roles/billing.admin` role on the billing account.
   - The `roles/resourcemanager.folderCreator` role.
   - The `roles/securitycenter.admin` role.

You can validate your environment with the included helper script:

```bash
./scripts/validate-requirements.sh -o <ORGANIZATION_ID> -b <BILLING_ACCOUNT_ID> -u <END_USER_EMAIL>
```

### Troubleshooting

See [troubleshooting](../docs/TROUBLESHOOTING.md) if you run into issues during this step.

## Deploying with GitHub Actions

1. Clone [pulumi_ts-example-foundation](https://github.com/VitruvianSoftware/pulumi_ts-example-foundation) into your local environment.

   ```bash
   git clone https://github.com/VitruvianSoftware/pulumi_ts-example-foundation.git
   ```

1. Clone the private repository you created to host the `0-bootstrap` code at the same level of the `pulumi_ts-example-foundation` folder.

   ```bash
   git clone git@github.com:<GITHUB-OWNER>/<GITHUB-BOOTSTRAP-REPO>.git gcp-bootstrap
   ```

1. The layout should be:

   ```
   gcp-bootstrap/
   pulumi_ts-example-foundation/
   ```

1. Navigate into the repo. All subsequent steps assume you are running them from the `gcp-bootstrap` directory.

   ```bash
   cd gcp-bootstrap
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

1. Copy the bootstrap stage code and pipeline templates.

   ```bash
   cp -R ../pulumi_ts-example-foundation/0-bootstrap/* .
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
   pulumi config set group_org_admins "org-admins@example.com"
   pulumi config set group_billing_admins "billing-admins@example.com"
   pulumi config set billing_data_users "billing-data@example.com"
   pulumi config set audit_data_users "audit-data@example.com"

   # GitHub Actions WIF configuration
   pulumi config set github_owner "your-github-org"
   pulumi config set github_repo_bootstrap "gcp-bootstrap"
   pulumi config set github_repo_org "gcp-org"
   pulumi config set github_repo_env "gcp-environments"
   pulumi config set github_repo_net "gcp-networks"
   pulumi config set github_repo_proj "gcp-projects"

   # GitHub token for auto-provisioning secrets into stage repos
   pulumi config set --secret github:token "ghp_your_token_here"
   ```

1. (Optional) Set additional configuration to override defaults:

   ```bash
   pulumi config set project_prefix "prj"          # default: prj
   pulumi config set folder_prefix "fldr"           # default: fldr
   pulumi config set bucket_prefix "bkt"            # default: bkt
   pulumi config set default_region "us-central1"   # default: us-central1

   # Deploy under a specific folder instead of org root
   pulumi config set parent_folder "FOLDER_NUMERIC_ID"
   ```

1. Run `pulumi preview` to review the planned changes.

   ```bash
   pulumi preview
   ```

1. Run `pulumi up` to deploy.

   ```bash
   pulumi up
   ```

1. Record the outputs. These will be consumed by downstream stages via [Stack References](../docs/GLOSSARY.md#pulumi-stack-reference):

   ```bash
   export CICD_PROJECT_ID=$(pulumi stack output cicd_project_id)
   export WIF_PROVIDER=$(pulumi stack output wif_provider_name)

   echo "CI/CD Project = ${CICD_PROJECT_ID}"
   echo "WIF Provider  = ${WIF_PROVIDER}"
   ```

1. Commit and push.

   ```bash
   git add .
   git commit -m 'Initialize bootstrap'
   git push --set-upstream origin plan
   ```

1. Open a **pull request** in GitHub from the `plan` branch to the `production` branch and review the GitHub Action output.
1. If the action is successful, **merge** the pull request. The merge triggers `pulumi up` via the pipeline.

1. Before moving to the next step, go back to the parent directory.

   ```bash
   cd ..
   ```

**Note 1:** The stages after `0-bootstrap` use [Pulumi Stack References](../docs/GLOSSARY.md#pulumi-stack-reference) to read common configuration from the output of this stage. They will fail if the bootstrap stack has not been deployed.

**Note 2:** After the deploy, we recommend that you request 50 additional projects for the **projects step service account** to prevent project quota errors in later stages.

## Running Pulumi Locally

1. Clone [pulumi_ts-example-foundation](https://github.com/VitruvianSoftware/pulumi_ts-example-foundation) into your local environment.

   ```bash
   git clone https://github.com/VitruvianSoftware/pulumi_ts-example-foundation.git
   cd pulumi_ts-example-foundation/0-bootstrap
   ```

1. Authenticate with Google Cloud:

   ```bash
   gcloud auth application-default login
   ```

1. Install dependencies:

   ```bash
   npm install
   ```

1. Login to Pulumi:

   ```bash
   # Option A: Pulumi Cloud (recommended)
   pulumi login

   # Option B: Local backend
   pulumi login --local
   ```

1. Initialize the bootstrap stack and set configuration as described above.

1. Preview and deploy:

   ```bash
   pulumi preview
   pulumi up
   ```

## CI/CD Providers

The Pulumi foundation supports pluggable CI/CD providers:

| Provider | Status | README |
|----------|--------|--------|
| **GitHub Actions** | ✅ Default | [README-GitHub.md](README-GitHub.md) |
| **Cloud Build** | 📄 Example | [README-CloudBuild.md](README-CloudBuild.md) |
| **GitLab CI/CD** | 📄 Example | [README-GitLab.md](README-GitLab.md) |

## Configuration Reference

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `org_id` | GCP Organization ID | `string` | n/a | yes |
| `billing_account` | The ID of the billing account to associate projects with | `string` | n/a | yes |
| `group_org_admins` | Email of the organization admins group | `string` | n/a | yes |
| `group_billing_admins` | Email of the billing admins group | `string` | n/a | yes |
| `billing_data_users` | Email of the billing data users group | `string` | n/a | yes |
| `audit_data_users` | Email of the audit data users group | `string` | n/a | yes |
| `project_prefix` | Name prefix for projects created | `string` | `"prj"` | no |
| `folder_prefix` | Name prefix for folders created | `string` | `"fldr"` | no |
| `bucket_prefix` | Name prefix for state bucket | `string` | `"bkt"` | no |
| `default_region` | Default region to create resources | `string` | `"us-central1"` | no |
| `default_region_2` | Secondary default region | `string` | `"us-west1"` | no |
| `default_region_gcs` | Default region for GCS resources (case-sensitive) | `string` | `"US"` | no |
| `default_region_kms` | Default region for KMS resources | `string` | `"us"` | no |
| `parent_folder` | Optional parent folder ID (instead of org root) | `string` | `""` | no |
| `bucket_force_destroy` | Allow destroying state bucket with objects | `boolean` | `false` | no |
| `bucket_tfstate_kms_force_destroy` | Allow destroying KMS keys for state bucket | `boolean` | `false` | no |
| `project_deletion_policy` | Deletion policy for created projects | `string` | `"PREVENT"` | no |
| `folder_deletion_protection` | Prevent Terraform from destroying folders | `boolean` | `true` | no |
| `org_policy_admin_role` | Additional Org Policy Admin role for admin group | `boolean` | `false` | no |
| `random_suffix` | Append random suffix to project IDs | `boolean` | `true` | no |
| `create_required_groups` | Create required Cloud Identity groups | `boolean` | `false` | no |
| `create_optional_groups` | Create optional Cloud Identity groups | `boolean` | `false` | no |
| `gcp_security_reviewer` | Email for the security reviewer group | `string` | `""` | no |
| `gcp_network_viewer` | Email for the network viewer group | `string` | `""` | no |
| `gcp_scc_admin` | Email for the SCC admin group | `string` | `""` | no |
| `gcp_global_secrets_admin` | Email for the global secrets admin group | `string` | `""` | no |
| `gcp_kms_admin` | Email for the KMS admin group | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| `seed_project_id` | Project where service accounts and core APIs are enabled |
| `cicd_project_id` | Project where CI/CD infrastructure resides |
| `gcs_bucket_tfstate` | Bucket used for storing Pulumi state |
| `bootstrap_step_terraform_service_account_email` | Bootstrap Step Service Account |
| `organization_step_terraform_service_account_email` | Organization Step Service Account |
| `environment_step_terraform_service_account_email` | Environment Step Service Account |
| `networks_step_terraform_service_account_email` | Networks Step Service Account |
| `projects_step_terraform_service_account_email` | Projects Step Service Account |
| `wif_provider_name` | Workload Identity Federation provider name |
| `common_config` | Common configuration data for other steps |

## File Structure

| File | Description |
|------|-------------|
| `index.ts` | Orchestrates bootstrap: config loading, folder creation, project/IAM coordination, WIF setup, output exports |
| `config.ts` | Configuration loading and validation from Pulumi stack config |
| `sa.ts` | 5 per-stage service accounts with least-privilege IAM at org/parent/seed/cicd/billing scopes |
| `groups.ts` | Required and optional Cloud Identity group creation |
| `build_cb.ts` | GitHub Actions WIF OIDC provider and per-SA repository bindings |
