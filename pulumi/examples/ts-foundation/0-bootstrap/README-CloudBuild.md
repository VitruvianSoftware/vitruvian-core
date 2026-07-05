# 0-bootstrap — Cloud Build (Alternative)

This document describes how to use **Google Cloud Build** as the CI/CD provider
instead of the default GitHub Actions. This mirrors the Terraform foundation's
default `build_cb.tf` configuration.

> [!IMPORTANT]
> Cloud Build is NOT the default for the Pulumi TS foundation. The default is
> [GitHub Actions with WIF](README-GitHub.md). Follow the steps below to switch.

## Architecture

```
┌──────────────────────────────────────────┐
│  CI/CD Project (prj-b-cicd)             │
│  ┌────────────────────────────────────┐  │
│  │ Cloud Source Repos (7 repos)       │  │
│  │   gcp-bootstrap, gcp-org, ...     │  │
│  ├────────────────────────────────────┤  │
│  │ Artifact Registry                  │  │
│  │   pulumi-builders (Docker)         │  │
│  ├────────────────────────────────────┤  │
│  │ Cloud Build Triggers (×10)         │  │
│  │   plan-{stage} / apply-{stage}     │  │
│  ├────────────────────────────────────┤  │
│  │ Private Worker Pool (optional)     │  │
│  │   VPC-peered, 10.3.0.0/24         │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

## How to Switch

### Step 1: Create the Cloud Build configuration

Since the TS foundation uses directory-based environment separation, you need
to configure Cloud Build triggers per-stage, per-environment:

```typescript
// In your 0-bootstrap/build_cb.ts (create this file):
import * as gcp from "@pulumi/gcp";

// Example: create a plan trigger for each stage
const stages = ["0-bootstrap", "1-org", "2-environments", "3-networks-svpc", "4-projects", "5-app-infra"];
for (const stage of stages) {
    new gcp.cloudbuild.Trigger(`plan-${stage}`, {
        project: cicdProjectId,
        name: `plan-${stage}`,
        triggerTemplate: {
            repoName: `gcp-${stage}`,
            branchName: ".*",
        },
        filename: "cloudbuild-pulumi-plan.yaml",
    });
}
```

### Step 2: Update the index.ts orchestration

Replace the GitHub Actions build call with Cloud Build:

```diff
-    const cbOutputs = await deployCloudbuild(cfg, bootstrapFolder, seedProject, stateBucket, stateBucketKmsKey);
+    const cbOutputs = await deployCloudBuildCI(cfg, bootstrapFolder, seedProject, stateBucket, stateBucketKmsKey);
```

### Step 3: Add Cloud Build APIs

Ensure the CI/CD project has the required APIs:

```typescript
const cloudBuildApis = [
    "cloudbuild.googleapis.com",
    "sourcerepo.googleapis.com",
    "artifactregistry.googleapis.com",
];
```

### Step 4: Deploy

```bash
cd 0-bootstrap
pulumi up
```

## Cloud Build YAML Files

Place these in each stage's repository root:

### `cloudbuild-pulumi-plan.yaml`

```yaml
steps:
  - id: 'install'
    name: 'node:22'
    entrypoint: 'npm'
    args: ['install']
  - id: 'pulumi-preview'
    name: 'pulumi/pulumi-nodejs:latest'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        pulumi login gs://${_TF_BACKEND}
        pulumi preview --stack ${_STACK} --non-interactive
    env:
      - 'PULUMI_CONFIG_PASSPHRASE=${_PULUMI_CONFIG_PASSPHRASE}'
```

### `cloudbuild-pulumi-apply.yaml`

```yaml
steps:
  - id: 'install'
    name: 'node:22'
    entrypoint: 'npm'
    args: ['install']
  - id: 'pulumi-up'
    name: 'pulumi/pulumi-nodejs:latest'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        pulumi login gs://${_TF_BACKEND}
        pulumi up --stack ${_STACK} --non-interactive --yes
    env:
      - 'PULUMI_CONFIG_PASSPHRASE=${_PULUMI_CONFIG_PASSPHRASE}'
```

## What Gets Created

| Resource | Count | Description |
|----------|-------|-------------|
| Cloud Source Repos | 7 | One per stage + `gcp-policies` + `pulumi-cloudbuilder` |
| Artifact Registry | 1 | Docker repo for custom Pulumi builder images |
| AR IAM Bindings | 5 | `artifactregistry.reader` per SA |
| Cloud Build Plan Triggers | 5 | `plan-{stage}` — runs on any branch push |
| Cloud Build Apply Triggers | 5 | `apply-{stage}` — runs on main branch only |

## Additional Outputs

| Name | Description |
|------|-------------|
| `cloudbuild_project_id` | Project ID of the CI/CD project |
| `cloud_build_private_worker_pool_id` | Worker pool ID (if enabled) |
| `artifact_repo_name` | Name of the Artifact Registry repository |
