# pkg/cicd — CI/CD Integrations

Provides turn-key Workload Identity Federation (WIF) components for external CI/CD integrations, mirroring the functionality of the official Google Cloud Foundation Toolkit (CFT) CI/CD submodules.

## Overview

The `cicd` package bundles Workload Identity Pools, OIDC Providers, and Service Account IAM bindings into reusable Pulumi `ComponentResource` types for seamless, keyless authentication pipelines.

The Pulumi foundation supports **three CI/CD providers**, matching the upstream Terraform foundation:

- **`GitHubOIDC`** (component): Mirrors `terraform-google-modules/github-actions-runners/google//modules/gh-oidc`. Configures WIF for GitHub Actions OIDC tokens with `assertion.repository` attribute mapping. **This is the Pulumi foundation default.**
- **`GitLabOIDC`** (component): Mirrors `0-bootstrap/modules/gitlab-oidc` (local CFT module). Configures WIF for GitLab CI OIDC tokens with the full 15-attribute mapping set (standard OIDC claims + GitLab custom claims).
- **`CloudBuild`** (component): Mirrors the upstream Terraform `build_cb.tf` which consumes `tf_cloudbuild_source`, `tf_cloudbuild_builder`, and `tf_cloudbuild_workspace` modules. Bundles Artifact Registry and per-stage plan+apply Cloud Build Triggers. Supports **three source backends**: GitHub (default), GitLab, and CSR (legacy/deprecated).

> [!WARNING]
> Google deprecated Cloud Source Repositories (CSR) for new customers in June 2024.
> New deployments should use `CloudBuildSourceGitHub` or `CloudBuildSourceGitLab`.
> The `CloudBuildSourceCSR` option is retained only for existing CSR users.

## API Reference

### `SAMappingEntry`

Shared struct used by both GitHub and GitLab OIDC components, matching the Terraform module's `map(object({sa_name, attribute}))` variable type.

| Field | Type | Description |
|-------|------|-------------|
| `SAName` | `pulumi.StringInput` | Fully-qualified SA resource name (e.g., `projects/.../serviceAccounts/...`) or a Pulumi output from another resource |
| `Attribute` | `pulumi.StringInput` | WIF attribute binding string (e.g., `attribute.repository/owner/repo`) |

### `GitHubOIDCArgs`

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project for WIF resources |
| `PoolID` | `pulumi.StringInput` | ✅ | Workload Identity Pool ID |
| `ProviderID` | `pulumi.StringInput` | ✅ | WIF Provider ID |
| `AttributeCondition` | `pulumi.StringInput` | ✅ | CEL expression restricting accepted tokens |
| `SAMapping` | `map[string]SAMappingEntry` | | Service account → attribute binding pairs |

### `GitLabOIDCArgs`

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project for WIF resources |
| `PoolID` | `pulumi.StringInput` | ✅ | Workload Identity Pool ID |
| `ProviderID` | `pulumi.StringInput` | ✅ | WIF Provider ID |
| `AttributeCondition` | `pulumi.StringInput` | ✅ | CEL expression restricting accepted tokens |
| `SAMapping` | `map[string]SAMappingEntry` | | Service account → attribute binding pairs |
| `IssuerUri` | `pulumi.StringInput` | | GitLab issuer URL (defaults to `https://gitlab.com`) |

### `CloudBuildArgs`

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project hosting Cloud Build |
| `Region` | `pulumi.StringInput` | ✅ | GCP region for Artifact Registry and triggers |
| `SourceType` | `CloudBuildSourceType` | | Source backend: `CloudBuildSourceGitHub` (default), `CloudBuildSourceGitLab`, or `CloudBuildSourceCSR` (legacy) |
| `SourceRepos` | `[]string` | | CSR repo names to create (only used with `CloudBuildSourceCSR`) |
| `ArtifactRegistryID` | `string` | | AR repository ID (defaults to `pulumi-builders`) |
| `Triggers` | `map[string]CloudBuildTriggerConfig` | | Per-stage trigger configurations |
| `ArtifactRegistryReaders` | `[]pulumi.StringInput` | | IAM members granted AR reader access |

### `CloudBuildTriggerConfig`

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `RepoName` | `string` | ✅ | Repository name (CSR name, GitHub repo, or GitLab project) |
| `RepoOwner` | `string` | | GitHub user/org or GitLab namespace (required for GitHub/GitLab, ignored for CSR) |
| `ServiceAccount` | `pulumi.StringInput` | ✅ | Full SA resource name for the trigger |
| `PlanFilename` | `string` | | Cloud Build config for plan (defaults to `cloudbuild-pulumi-plan.yaml`) |
| `ApplyFilename` | `string` | | Cloud Build config for apply (defaults to `cloudbuild-pulumi-apply.yaml`) |
| `ApplyBranchPattern` | `string` | | Regex for apply branch (defaults to `^main$`) |

## Examples

### GitHub Actions OIDC

```go
import "github.com/VitruvianSoftware/pulumi-library/go/pkg/cicd"

gh, err := cicd.NewGitHubOIDC(ctx, "foundation-gh-oidc", &cicd.GitHubOIDCArgs{
    ProjectID:          cicdProjectID,
    PoolID:             pulumi.String("foundation-pool"),
    ProviderID:         pulumi.String("foundation-gh-provider"),
    AttributeCondition: pulumi.String("assertion.repository_owner=='my-org'"),
    SAMapping: map[string]cicd.SAMappingEntry{
        "bootstrap": {
            SAName:    bootstrapSA.Name,
            Attribute: pulumi.String("attribute.repository/my-org/gcp-bootstrap"),
        },
    },
})
```

### GitLab OIDC

```go
gl, err := cicd.NewGitLabOIDC(ctx, "foundation-gl-oidc", &cicd.GitLabOIDCArgs{
    ProjectID:          cicdProjectID,
    PoolID:             pulumi.String("foundation-pool"),
    ProviderID:         pulumi.String("foundation-gl-provider"),
    AttributeCondition: pulumi.String("assertion.project_path.startsWith('my-group/')"),
    SAMapping: map[string]cicd.SAMappingEntry{
        "bootstrap": {
            SAName:    bootstrapSA.Name,
            Attribute: pulumi.String("attribute.project_path/my-group/gcp-bootstrap"),
        },
    },
})
```

### Cloud Build (GitHub source — recommended)

```go
cb, err := cicd.NewCloudBuild(ctx, "foundation-cb", &cicd.CloudBuildArgs{
    ProjectID:  cicdProjectID,
    Region:     pulumi.String("us-central1"),
    SourceType: cicd.CloudBuildSourceGitHub, // Default; CSR is deprecated
    Triggers: map[string]cicd.CloudBuildTriggerConfig{
        "bootstrap": {
            RepoName:       "gcp-bootstrap",
            RepoOwner:      "my-org",
            ServiceAccount: bootstrapSA.Email.ApplyT(func(e string) string {
                return fmt.Sprintf("projects/%s/serviceAccounts/%s", cicdProjectID, e)
            }).(pulumi.StringOutput),
        },
    },
    ArtifactRegistryReaders: []pulumi.StringInput{
        pulumi.Sprintf("serviceAccount:%s", bootstrapSA.Email),
    },
})
```
