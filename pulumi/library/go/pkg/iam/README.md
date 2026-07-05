# pkg/iam — Scope-Isolated IAM Bindings

Additive and authoritative IAM bindings across 5 GCP scopes, each with a dedicated constructor for compile-time safety and blast radius isolation.

## Overview

Each GCP IAM scope has its own pair of constructors:

| Scope | Additive (Member) | Authoritative (Binding) |
|-------|-------------------|------------------------|
| Organization | `NewOrganizationIAMMember` | `NewOrganizationIAMBinding` |
| Folder | `NewFolderIAMMember` | `NewFolderIAMBinding` |
| Project | `NewProjectIAMMember` | `NewProjectIAMBinding` |
| Service Account | `NewServiceAccountIAMMember` | `NewServiceAccountIAMBinding` |
| Billing Account | `NewBillingIAMMember` | `NewBillingIAMBinding` |

### Why Scope-Specific Constructors?

Each constructor registers a **distinct Pulumi component type** (e.g., `pkg:iam:ProjectIAMMember` vs `pkg:iam:FolderIAMMember`). This provides:

- **Compile-time safety** — no magic strings for scope selection; incorrect usage fails at build time
- **Blast radius isolation** — a bug in folder IAM logic cannot affect project IAM bindings
- **Scope-specific Args** — each struct contains only the fields relevant to that scope (e.g., `ProjectID` vs `OrgID`)
- **Independent state** — each scope has isolated Pulumi state, preventing cross-scope corruption

### Additive vs. Authoritative

| Mode | Constructor | Behavior | When to Use |
|------|-------------|----------|-------------|
| **Additive** | `New<Scope>IAMMember` | Adds a single member to a role; does not affect other members | Most environments — safe to use alongside manual IAM |
| **Authoritative** | `New<Scope>IAMBinding` | Sets the complete list of members for a role; **removes unlisted members** | Strict environments where IAM must be fully managed by code |

> ⚠️ **Warning:** `IAMBinding` constructors will remove any members assigned to the specified role that are not included in the `Members` list. Use with extreme caution in production.

## API Reference

### Organization Scope

```go
func NewOrganizationIAMMember(ctx, name, &OrganizationIAMMemberArgs{
    OrgID:  pulumi.StringInput,  // Organization ID (numeric)
    Role:   pulumi.StringInput,
    Member: pulumi.StringInput,
})

func NewOrganizationIAMBinding(ctx, name, &OrganizationIAMBindingArgs{
    OrgID:   pulumi.StringInput,
    Role:    pulumi.StringInput,
    Members: pulumi.StringArrayInput,
})
```

### Folder Scope

```go
func NewFolderIAMMember(ctx, name, &FolderIAMMemberArgs{
    FolderID: pulumi.StringInput,  // Folder ID (numeric or "folders/ID")
    Role:     pulumi.StringInput,
    Member:   pulumi.StringInput,
})

func NewFolderIAMBinding(ctx, name, &FolderIAMBindingArgs{
    FolderID: pulumi.StringInput,
    Role:     pulumi.StringInput,
    Members:  pulumi.StringArrayInput,
})
```

### Project Scope

```go
func NewProjectIAMMember(ctx, name, &ProjectIAMMemberArgs{
    ProjectID: pulumi.StringInput,  // Project ID (string)
    Role:      pulumi.StringInput,
    Member:    pulumi.StringInput,
})

func NewProjectIAMBinding(ctx, name, &ProjectIAMBindingArgs{
    ProjectID: pulumi.StringInput,
    Role:      pulumi.StringInput,
    Members:   pulumi.StringArrayInput,
})
```

### Service Account Scope

```go
func NewServiceAccountIAMMember(ctx, name, &ServiceAccountIAMMemberArgs{
    ServiceAccountID: pulumi.StringInput,  // SA email or resource name
    Role:             pulumi.StringInput,
    Member:           pulumi.StringInput,
})

func NewServiceAccountIAMBinding(ctx, name, &ServiceAccountIAMBindingArgs{
    ServiceAccountID: pulumi.StringInput,
    Role:             pulumi.StringInput,
    Members:          pulumi.StringArrayInput,
})
```

### Billing Account Scope

```go
func NewBillingIAMMember(ctx, name, &BillingIAMMemberArgs{
    BillingAccountID: pulumi.StringInput,  // "XXXXXX-XXXXXX-XXXXXX"
    Role:             pulumi.StringInput,
    Member:           pulumi.StringInput,
})

func NewBillingIAMBinding(ctx, name, &BillingIAMBindingArgs{
    BillingAccountID: pulumi.StringInput,
    Role:             pulumi.StringInput,
    Members:          pulumi.StringArrayInput,
})
```

## Examples

### Grant a Service Account Org-Level Access

```go
iam.NewOrganizationIAMMember(ctx, "sa-org-admin", &iam.OrganizationIAMMemberArgs{
    OrgID:  pulumi.String("123456789"),
    Role:   pulumi.String("roles/resourcemanager.organizationAdmin"),
    Member: pulumi.Sprintf("serviceAccount:%s", sa.Email),
})
```

### Grant Project-Level Access Using Outputs

```go
iam.NewProjectIAMMember(ctx, "project-viewer", &iam.ProjectIAMMemberArgs{
    ProjectID: project.Project.ProjectId,  // pulumi.StringOutput
    Role:      pulumi.String("roles/viewer"),
    Member:    pulumi.String("group:developers@example.com"),
})
```

### Authoritative Binding on a Folder

```go
iam.NewFolderIAMBinding(ctx, "folder-admins", &iam.FolderIAMBindingArgs{
    FolderID: folder.ID(),
    Role:     pulumi.String("roles/resourcemanager.folderAdmin"),
    Members: pulumi.StringArray{
        pulumi.String("user:admin@example.com"),
        pulumi.Sprintf("serviceAccount:%s", bootstrapSA.Email),
    },
})
```

### Service Account Self-Impersonation

```go
iam.NewServiceAccountIAMMember(ctx, "sa-self-impersonate", &iam.ServiceAccountIAMMemberArgs{
    ServiceAccountID: sa.Name,
    Role:             pulumi.String("roles/iam.serviceAccountTokenCreator"),
    Member:           pulumi.Sprintf("serviceAccount:%s", sa.Email),
})
```

### Billing Account Binding

```go
iam.NewBillingIAMMember(ctx, "billing-user", &iam.BillingIAMMemberArgs{
    BillingAccountID: pulumi.String("XXXXXX-XXXXXX-XXXXXX"),
    Role:             pulumi.String("roles/billing.user"),
    Member:           pulumi.Sprintf("serviceAccount:%s", sa.Email),
})
```

## Deprecated API

The unified `NewIAMMember` and `NewIAMBinding` constructors (with `ParentType` string dispatch) are still available for backward compatibility but are deprecated. Migrate to the scope-specific constructors above.
