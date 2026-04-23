# pkg/group — Google Workspace Groups

Creates a Cloud Identity / Google Workspace group with configurable type labels and robust membership management (Owners, Managers, and Members).

## Overview

The `Group` component wraps `cloudidentity.Group` and `cloudidentity.GroupMembership` resources, providing a structured mechanism to define organization groups securely and programmatically. 

### Group Types

The component allows specifying the group's taxonomy through the `Types` array, mapped natively to Cloud Identity labels:
- `"default"`  → `cloudidentity.googleapis.com/groups.discussion_forum`
- `"security"` → `cloudidentity.googleapis.com/groups.security`
- `"dynamic"`  → `cloudidentity.googleapis.com/groups.dynamic`
- `"external"` → `system/groups/external`

If you are declaring security groups, you should assign `[]string{"default", "security"}`.

## API Reference

### `GroupArgs`

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ID` | `string` | ✅ | The group email address (e.g. `admins@example.com`) |
| `CustomerID` | `pulumi.StringInput` | ✅ | Google Workspace customer ID (e.g., `C01234abc`) |
| `DisplayName` | `string` | | The human-readable group name (Defaults to `ID`) |
| `Description` | `string` | | Optional extended description |
| `Types` | `[]string` | | Defines the group type labels (Defaults to `[]string{"default"}`) |
| `Owners` | `[]string` | | Member emails to add as `OWNER` + `MEMBER` |
| `Managers` | `[]string` | | Member emails to add as `MANAGER` + `MEMBER` |
| `Members` | `[]string` | | Member emails to add as `MEMBER` |

### `Group` (Output)

| Field | Type | Description |
|-------|------|-------------|
| `GroupResource` | `*cloudidentity.Group` | The underlying Cloud Identity group resource |
| `GroupID` | `pulumi.StringOutput` | The fully qualified group resource name |
| `GroupEmail` | `pulumi.StringOutput` | The group email address |

## Examples

### Provisioning an Organization Admin Group

```go
import "github.com/VitruvianSoftware/pulumi-library/go/pkg/group"

g, err := group.NewGroup(ctx, "org-admins", &group.GroupArgs{
    ID:          "gcp-org-admins@example.com",
    DisplayName: "GCP Organization Admins",
    CustomerID:  pulumi.String("C01234abc"),
    Types:       []string{"default", "security"},
    Owners:      []string{"admin-owner@example.com"},
    Managers:    []string{"admin-manager@example.com"},
    Members:     []string{"admin-user@example.com"},
})
```
