# pkg/policy — Organization Policy Enforcement

Enforces [GCP organization policy constraints](https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints) using the v2 Org Policy API.

## Overview

The `OrgPolicy` component wraps [`orgpolicy.Policy`](https://www.pulumi.com/registry/packages/gcp/api-docs/orgpolicy/policy/) to enforce boolean and list constraints at any scope (organization, folder, or project).

Supports three constraint modes:

| Mode | Fields | Description |
|------|--------|-------------|
| **Boolean** | `Boolean` | Enforce (`true`) or disable (`false`) a boolean constraint |
| **List — deny/allow all** | `DenyAll` or `AllowAll` | Blanket deny or allow for a list constraint |
| **List — specific values** | `AllowValues` and/or `DenyValues` | Allow or deny specific values for a list constraint |

## API Reference

### `OrgPolicyArgs`

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `ParentID` | `pulumi.StringInput` | ✅ | Full resource path (e.g., `"organizations/123"`, `"folders/456"`, `"projects/my-project"`) |
| `Constraint` | `pulumi.StringInput` | ✅ | Full constraint name (e.g., `"constraints/compute.disableSerialPortAccess"`) |
| `Boolean` | `pulumi.BoolPtrInput` | | Set to `true` to enforce a boolean constraint |
| `AllowValues` | `pulumi.StringArrayInput` | | Specific values to allow for list constraints |
| `DenyValues` | `pulumi.StringArrayInput` | | Specific values to deny for list constraints |
| `DenyAll` | `pulumi.BoolPtrInput` | | Set to `true` to deny all values for a list constraint |
| `AllowAll` | `pulumi.BoolPtrInput` | | Set to `true` to allow all values for a list constraint |

### `OrgPolicy` (Output)

| Field | Type | Description |
|-------|------|-------------|
| `Policy` | `*orgpolicy.Policy` | The underlying GCP org policy resource |

### Constructor

```go
func NewOrgPolicy(ctx *pulumi.Context, name string, args *OrgPolicyArgs, opts ...pulumi.ResourceOption) (*OrgPolicy, error)
```

## Examples

### Boolean Constraint — Enforce

```go
// Disable serial port access for all VMs in the organization
policy.NewOrgPolicy(ctx, "no-serial-port", &policy.OrgPolicyArgs{
    ParentID:   pulumi.String("organizations/123456"),
    Constraint: pulumi.String("constraints/compute.disableSerialPortAccess"),
    Boolean:    pulumi.Bool(true),
})
```

### List Constraint — Deny All

```go
// Deny all external IPs on VMs
policy.NewOrgPolicy(ctx, "no-external-ip", &policy.OrgPolicyArgs{
    ParentID:   pulumi.String("organizations/123456"),
    Constraint: pulumi.String("constraints/compute.vmExternalIpAccess"),
    DenyAll:    pulumi.Bool(true),
})
```

### List Constraint — Allow Specific Values

```go
// Restrict domain sharing to specific Cloud Identity customer IDs
policy.NewOrgPolicy(ctx, "restrict-domains", &policy.OrgPolicyArgs{
    ParentID:    pulumi.String("organizations/123456"),
    Constraint:  pulumi.String("constraints/iam.allowedPolicyMemberDomains"),
    AllowValues: pulumi.StringArray{pulumi.String("C0xxxxxxx")},
})
```

### Folder-Scoped Policy

```go
// Apply a policy only to a specific folder
policy.NewOrgPolicy(ctx, "folder-no-nested-virt", &policy.OrgPolicyArgs{
    ParentID:   folder.ID().ApplyT(func(id string) string { return "folders/" + id }).(pulumi.StringOutput),
    Constraint: pulumi.String("constraints/compute.disableNestedVirtualization"),
    Boolean:    pulumi.Bool(true),
})
```

## Common Constraints

| Constraint | Type | Description |
|-----------|------|-------------|
| `compute.disableSerialPortAccess` | Boolean | Block serial port access |
| `compute.disableNestedVirtualization` | Boolean | Block nested virtualization |
| `compute.requireOsLogin` | Boolean | Require OS Login for SSH |
| `iam.disableServiceAccountKeyCreation` | Boolean | Block SA key creation |
| `storage.publicAccessPrevention` | Boolean | Block public Cloud Storage |
| `compute.vmExternalIpAccess` | List | Control VM external IPs |
| `iam.allowedPolicyMemberDomains` | List | Restrict IAM member domains |
| `compute.restrictProtocolForwardingCreationForTypes` | List | Restrict protocol forwarding |
