# Deploying the Pulumi GCP Foundation (TypeScript) with GitHub Actions

This guide walks you through deploying the [Pulumi GCP Foundation](README.md) using GitHub Actions with Workload Identity Federation (WIF) for authentication. The foundation is deployed in stages, each in its own repository, following the same branching strategy as the [Terraform Example Foundation](https://github.com/terraform-google-modules/terraform-example-foundation).

## Architecture

Each stage is deployed from its **own GitHub repository**. You will create one repository per stage and copy the corresponding code from this reference template.

```
pulumi_ts-example-foundation/     ← This reference template
├── 0-bootstrap/                  ← Copy to your gcp-bootstrap repo
├── 1-org/                        ← Copy to your gcp-org repo
├── 2-environments/               ← Copy to your gcp-environments repo
├── 3-networks-svpc/              ← Copy to your gcp-networks repo
├── 4-projects/                   ← Copy to your gcp-projects repo
└── 5-app-infra/                  ← Copy to your gcp-app-infra repo
```

### Branching Strategy

Stages 0–1 manage **shared resources** and use a single `production` branch.
Stages 2–5 manage **per-environment resources** and use environment branches:

| Repository | Branches | Deploy Trigger |
|------------|----------|----------------|
| `gcp-bootstrap` | `production` | Merge to `production` |
| `gcp-org` | `production` | Merge to `production` |
| `gcp-environments` | `development`, `nonproduction`, `production` | Merge to each branch |
| `gcp-networks` | `development`, `nonproduction`, `production` | Merge to each branch |
| `gcp-projects` | `development`, `nonproduction`, `production` | Merge to each branch |
| `gcp-app-infra` | `development`, `nonproduction`, `production` | Merge to each branch |

Changes promote through environments via pull requests:

```
feature → PR to development → merge → pulumi up (dev)
       → PR to nonproduction → merge → pulumi up (nonprod)
       → PR to production → merge → pulumi up (prod)
```

### Stack References

Downstream stages read outputs from upstream stages via [Pulumi Stack References](https://www.pulumi.com/docs/concepts/stack/#stackreferences), which replace Terraform's `terraform_remote_state` data source. These are configured via the `bootstrap_stack_name` or `org_stack_name` config values.

## Requirements

### Tools

- [Pulumi CLI](https://www.pulumi.com/docs/install/) version 3.0+
- [Node.js](https://nodejs.org/) version 18+ (LTS recommended)
- [npm](https://www.npmjs.com/) version 9+
- [Google Cloud SDK](https://cloud.google.com/sdk/install) (`gcloud`)
- [Git](https://git-scm.com/) version 2.28+

You can validate your environment with the included helper script:

```bash
./scripts/validate-requirements.sh -o <ORGANIZATION_ID> -b <BILLING_ACCOUNT_ID> -u <END_USER_EMAIL>
```

### Google Cloud

- A Google Cloud [Organization](https://cloud.google.com/resource-manager/docs/creating-managing-organization)
- A Google Cloud [Billing Account](https://cloud.google.com/billing/docs/how-to/manage-billing-account)
- Cloud Identity or Google Workspace groups for organization and billing admins
- For the user running these steps, the following roles on the **organization**:
  - `roles/resourcemanager.organizationAdmin`
  - `roles/orgpolicy.policyAdmin`
  - `roles/resourcemanager.projectCreator`
  - `roles/resourcemanager.folderCreator`
  - `roles/securitycenter.admin`
  - `roles/billing.admin` on the billing account

### Pulumi Cloud

- A [Pulumi Cloud](https://app.pulumi.com/) account (free tier is sufficient)
- A Pulumi Access Token — generate from **Settings → Access Tokens** in the Pulumi Cloud console

### GitHub

- A [GitHub account](https://docs.github.com/en/get-started) for your user or organization
- A **private** GitHub repository for each stage:
  - `gcp-bootstrap`
  - `gcp-org`
  - `gcp-environments`
  - `gcp-networks`
  - `gcp-projects`
  - `gcp-app-infra` (optional)

### Shared Library

This foundation uses the [Vitruvian Software Pulumi Library](https://github.com/VitruvianSoftware/pulumi-library) for standardized GCP components. When copying stage code to your repository, install the library:

```bash
npm install @vitruvian/pulumi-library
```

---

## Deploying Step 0: Bootstrap

The bootstrap stage creates the Seed project (state storage, KMS encryption, service accounts) and the CI/CD project with Workload Identity Federation for GitHub Actions.

1. Clone this reference template and create your bootstrap repository:

   ```bash
   git clone https://github.com/VitruvianSoftware/pulumi_ts-example-foundation.git
   git clone git@github.com:<GITHUB-OWNER>/<GITHUB-BOOTSTRAP-REPO>.git gcp-bootstrap
   ```

2. The layout should be:

   ```
   gcp-bootstrap/
   pulumi_ts-example-foundation/
   ```

3. Navigate into the bootstrap repo:

   ```bash
   cd gcp-bootstrap
   ```

4. Seed the repository:

   ```bash
   git commit --allow-empty -m 'repository seed'
   git push --set-upstream origin main

   git checkout -b production
   git push --set-upstream origin production
   ```

5. Create a working branch:

   ```bash
   git checkout -b plan
   ```

6. Copy the bootstrap stage code and pipeline templates:

   ```bash
   cp -R ../pulumi_ts-example-foundation/0-bootstrap/* .
   mkdir -p .github/workflows
   cp ../pulumi_ts-example-foundation/build/pulumi-preview.yml .github/workflows/
   cp ../pulumi_ts-example-foundation/build/pulumi-up.yml .github/workflows/
   ```

7. Install dependencies:

   ```bash
   npm install
   ```

8. Initialize the Pulumi stack and configure:

   ```bash
   pulumi stack init production

   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set group_org_admins "org-admins@example.com"
   pulumi config set group_billing_admins "billing-admins@example.com"
   pulumi config set billing_data_users "billing-data@example.com"
   pulumi config set audit_data_users "audit-data@example.com"

   # Optional governance groups (consumed by 1-org for IAM bindings)
   pulumi config set gcp_security_reviewer "security-reviewers@example.com"
   pulumi config set gcp_network_viewer "network-viewers@example.com"
   pulumi config set gcp_scc_admin "scc-admins@example.com"
   pulumi config set gcp_global_secrets_admin "secrets-admins@example.com"
   pulumi config set gcp_kms_admin "kms-admins@example.com"

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

   **Key settings** (see `config.ts` for the full list):
   - `project_prefix` (default: `prj`) — prefix for all project IDs
   - `folder_prefix` (default: `fldr`) — prefix for folder display names
   - `default_region` (default: `us-central1`) — primary region for KMS keys
   - `parent_folder` (optional) — deploy under a folder instead of org root

9. Run `pulumi up` manually for the first deployment:

   ```bash
   pulumi up
   ```

10. Export outputs needed by downstream stages and CI/CD:

    ```bash
    export CICD_PROJECT_ID=$(pulumi stack output cicd_project_id)
    export WIF_PROVIDER=$(pulumi stack output wif_provider_name)

    echo "CI/CD Project = ${CICD_PROJECT_ID}"
    echo "WIF Provider  = ${WIF_PROVIDER}"
    ```

11. **GitHub Actions secrets are auto-provisioned** by bootstrap.
    When `github_owner` and `github:token` are configured, bootstrap automatically
    creates these secrets in each stage repository:

    | Secret | Value | Provisioned By |
    |--------|-------|----------------|
    | `WIF_PROVIDER_NAME` | WIF provider full resource name | Bootstrap (auto) |
    | `SERVICE_ACCOUNT_EMAIL` | Per-stage SA email | Bootstrap (auto) |
    | `PROJECT_ID` | CI/CD project ID | Bootstrap (auto) |
    | `PULUMI_ACCESS_TOKEN` | Pulumi Cloud token | **Manual** — set via GitHub UI or `gh secret set` |

    > **Note:** `PULUMI_ACCESS_TOKEN` is NOT auto-provisioned because it is a
    > Pulumi Cloud credential, not a GCP credential managed by bootstrap. Set it
    > once as an organization-level secret in GitHub, or per-repo.

12. Commit and push:

    ```bash
    git add .
    git commit -m 'Initialize bootstrap'
    git push --set-upstream origin plan
    ```

13. Open a **pull request** from `plan` to `production` and review the GitHub Action output.
14. If the action is successful, **merge** the PR. The merge triggers `pulumi up` via the pipeline.
15. Return to the parent directory:

    ```bash
    cd ..
    ```

> **Note:** After deployment, we recommend requesting 50 additional projects quota
> for the **projects step service account** to prevent quota errors in later stages.

---

## Deploying Step 1: Organization

The organization stage creates the folder structure, shared projects (logging, billing, SCC, KMS, Secrets, Interconnect), enforces org policies, and sets up centralized logging.

1. Clone your organization repository:

   ```bash
   git clone git@github.com:<GITHUB-OWNER>/<GITHUB-ORG-REPO>.git gcp-org
   cd gcp-org
   ```

2. Seed the repository:

   ```bash
   git commit --allow-empty -m 'repository seed'
   git push --set-upstream origin main

   git checkout -b production
   git push --set-upstream origin production
   ```

3. Create a working branch:

   ```bash
   git checkout -b plan
   ```

4. Copy the org stage code and pipeline templates:

   ```bash
   cp -R ../pulumi_ts-example-foundation/1-org/* .
   mkdir -p .github/workflows
   cp ../pulumi_ts-example-foundation/build/pulumi-preview.yml .github/workflows/
   cp ../pulumi_ts-example-foundation/build/pulumi-up.yml .github/workflows/
   ```

5. Install dependencies:

   ```bash
   npm install
   ```

6. Initialize the Pulumi stack and configure:

   ```bash
   pulumi stack init production

   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set bootstrap_stack_name "<PULUMI-ORG>/<PULUMI-PROJECT>/production"
   pulumi config set domains_to_allow "example.com"
   ```

7. Check if a Security Command Center notification named `scc-notify` already exists:

   ```bash
   export ORG_STEP_SA=$(pulumi -C ../gcp-bootstrap stack output organization_step_terraform_service_account_email)

   gcloud scc notifications describe "scc-notify" \
     --format="value(name)" \
     --organization=YOUR_ORG_ID \
     --location=global \
     --impersonate-service-account=${ORG_STEP_SA}
   ```

   If it exists, set a different name: `pulumi config set scc_notification_name "scc-notify-pulumi"`

8. Commit, push, and promote via PR:

   ```bash
   git add .
   git commit -m 'Initialize org'
   git push --set-upstream origin plan
   ```

9. Open a **pull request** from `plan` to `production`, review, and merge.
10. Return to the parent directory:

    ```bash
    cd ..
    ```

---

## Deploying Step 2: Environments

The environments stage creates per-environment folders, KMS projects, and Secrets projects. **This is where environment branches begin.**

1. Clone your environments repository:

   ```bash
   git clone git@github.com:<GITHUB-OWNER>/<GITHUB-ENVIRONMENTS-REPO>.git gcp-environments
   cd gcp-environments
   ```

2. Seed the repository with **all environment branches**:

   ```bash
   git commit --allow-empty -m 'repository seed'
   git push --set-upstream origin main

   git checkout -b production
   git push --set-upstream origin production

   git checkout -b nonproduction
   git push --set-upstream origin nonproduction

   git checkout -b development
   git push --set-upstream origin development
   ```

3. Create a working branch:

   ```bash
   git checkout -b plan
   ```

4. Copy the environments stage code and pipeline templates:

   ```bash
   cp -R ../pulumi_ts-example-foundation/2-environments/* .
   mkdir -p .github/workflows
   cp ../pulumi_ts-example-foundation/build/pulumi-preview.yml .github/workflows/
   cp ../pulumi_ts-example-foundation/build/pulumi-up.yml .github/workflows/
   ```

5. Install dependencies:

   ```bash
   npm install
   ```

6. Initialize Pulumi stacks for **each environment**:

   ```bash
   # Each environment gets its own stack.
   pulumi stack init development
   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set org_stack_name "<PULUMI-ORG>/gcp-org/production"

   pulumi stack init nonproduction
   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set org_stack_name "<PULUMI-ORG>/gcp-org/production"

   pulumi stack init production
   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set org_stack_name "<PULUMI-ORG>/gcp-org/production"
   ```

7. Commit and push:

   ```bash
   git add .
   git commit -m 'Initialize environments'
   git push --set-upstream origin plan
   ```

8. **Deploy development first.** Open a PR from `plan` to `development`, review, and merge.
9. **Promote to nonproduction.** Open a PR from `development` to `nonproduction`, review, and merge.
10. **Promote to production.** Open a PR from `nonproduction` to `production`, review, and merge.
11. Return to the parent directory:

    ```bash
    cd ..
    ```

---

## Deploying Step 3: Networks

The networks stage deploys the network infrastructure. **Choose one** topology:
- **Shared VPC** (`3-networks-svpc`) — simple flat network
- **Hub-and-Spoke** (`3-networks-hub-and-spoke`) — centralized hub with spoke VPCs

1. Follow the same repository setup pattern as Steps 1-2.
2. Copy from `3-networks-svpc/` (or `3-networks-hub-and-spoke/`).
3. **Deploy the shared environment first** (manually, before environment branches):

   ```bash
   pulumi stack select shared
   pulumi up
   ```

4. Promote through environments via PRs.

---

## Deploying Step 4: Projects

The projects stage creates business unit projects attached to the Shared VPC.

1. Follow the same repository setup pattern as Steps 2-3.
2. Copy from `4-projects/`.
3. **Deploy the shared environment first** (manually).
4. Promote through environments via PRs.

> **Tip:** To create additional business units, copy the `business_unit_1` directory
> and update business codes and subnet ranges.

---

## Deploying Step 5: App Infrastructure

The app infrastructure stage deploys sample application resources.

1. Follow the same repository setup pattern as Steps 2-3.
2. Copy from `5-app-infra/`.
3. Promote through environments via PRs.

---

## CI/CD Pipeline Reference

### Pipeline Templates

This repository ships two pipeline templates in `build/`:

| Template | Trigger | Action |
|----------|---------|--------|
| `pulumi-preview.yml` | Pull request to env branches | Runs `pulumi preview`, comments on PR |
| `pulumi-up.yml` | Merge to env branches | Runs `pulumi up` to deploy |

Both templates authenticate via **Workload Identity Federation** (WIF), configured
by the 0-bootstrap stage. No service account keys are stored in GitHub.

### GitLab Alternative

If you are using GitLab instead of GitHub, see [README-GitLab](./0-bootstrap/README-GitLab.md)
for GitLab-specific CI/CD pipeline templates and configuration instructions.

### Required Secrets

Each repository needs these secrets configured:

| Secret | Description | How to obtain |
|--------|-------------|---------------|
| `WIF_PROVIDER_NAME` | WIF provider resource name | `pulumi -C gcp-bootstrap stack output wif_provider_name` |
| `SERVICE_ACCOUNT_EMAIL` | Stage-specific service account | `pulumi -C gcp-bootstrap stack output <stage>_step_terraform_service_account_email` |
| `PULUMI_ACCESS_TOKEN` | Pulumi Cloud access token | [Pulumi Cloud console](https://app.pulumi.com/) |

### Branch-to-Stack Mapping

The pipeline uses the **branch name as the Pulumi stack name**:

| Branch | Stack | Effect |
|--------|-------|--------|
| `development` | `development` | Deploys to the development environment |
| `nonproduction` | `nonproduction` | Deploys to the nonproduction environment |
| `production` | `production` | Deploys to the production environment |

---

## Using the Shared Library

All stages use the [Vitruvian Software Pulumi Library](https://github.com/VitruvianSoftware/pulumi-library) for standardized GCP components:

| Package | Description |
|---------|-------------|
| `project` | Project factory with API activation, budgets, and service account management |
| `iam` | Multi-scope IAM bindings (organization, folder, project) |
| `policy` | Organization policy enforcement (boolean and list constraints) |
| `bootstrap` | Bootstrap component (state bucket, KMS, granular service accounts) |
| `networking` | VPC and subnet management |

---

## Troubleshooting

### Stack Reference Errors

If a downstream stage fails with a stack reference error, ensure the upstream stage
has been deployed and its outputs are available:

```bash
pulumi -C ../gcp-bootstrap stack output --show-secrets
```

### Project Quota Exceeded

After deploying 0-bootstrap, request 50 additional projects for the projects step
service account to prevent quota errors in later stages.

### npm Install Failures

If `npm install` fails, ensure you are using Node.js 18+ and npm 9+:

```bash
node --version  # Should be v18+
npm --version   # Should be 9+
```
