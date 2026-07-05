# Pulumi Library - TypeScript

This directory contains the TypeScript implementation of the Vitruvian Software Pulumi Library.

## Quick Start

Install from the `ts/` directory (or via npm link/registry):

```bash
npm install @vitruviansoftware/pulumi-library
```

Then import the components you need from their respective submodules:

```typescript
import { ProjectFactory } from "@vitruviansoftware/pulumi-library/project-factory";
import { Network } from "@vitruviansoftware/pulumi-library/network";
import { SimpleBucket } from "@vitruviansoftware/pulumi-library/simple-bucket";
```

## Components

| Component | Export Name | Description |
|-----------|-------------|-------------|
| **Project** | `ProjectFactory` | Project factory: creates GCP projects with API enablement, billing association, and random suffixing |
| **IAM** | `ParentIamMember`, `ParentIamRemoveRole` | Polymorphic IAM bindings for organization, folder, and project scopes |
| **Policy** | `OrgPolicyBoolean`, `OrgPolicyList`, `DomainRestrictedSharing` | Organization policy constraint enforcement using the v2 Org Policy API |
| **Group** | `GoogleGroup` | Google Workspace / Cloud Identity group provisioning |
| **Logging** | `CentralizedLogging` | Centralized log export infrastructure with sinks and destinations |
| **Networking** | `Network`, `FirewallRules`, `NetworkPeering` | VPC networks with subnets, firewall rules, and VPC peering |
| **Security** | `HierarchicalFirewallPolicy` | Hierarchical firewall policies for organization and folder scopes |
| **Storage** | `SimpleBucket` | Secure Google Cloud Storage buckets |
| **KMS** | `Kms` | Key Management Service integration |
| **Compute** | `InstanceTemplate`, `ComputeInstance` | Google Compute Engine instance templates and instances |
| **Connectivity** | `PrivateServiceConnect`, `VpnHa`, `DnsHub` | Hybrid and internal connectivity setups |
| **CI/CD** | `CbPrivatePool` | Cloud Build private pools |
| **Billing** | `Budget` | Billing budgets and spending alerts |

## Architecture

Each module follows the same pattern:

```
src/<name>/
  └── index.ts            # ComponentResource class implementation and interfaces
```

All modules are aggregated and re-exported in `src/index.ts` to allow straightforward barrel imports.

### Resource Graph Example

```
foundation:modules:ProjectFactory ("seed-project")
├── gcp:organizations:Project ("seed-project")
├── gcp:projects:Service ("seed-project-compute.googleapis.com")
├── gcp:projects:Service ("seed-project-iam.googleapis.com")
└── gcp:billing:Budget ("seed-project-budget")
```

## Design Principles

### 1. Submodule Exports
To reduce the blast radius and avoid unnecessary dependency loading, components should be imported directly from their respective submodules rather than the top-level barrel export.

```typescript
// ✅ Correct: Import from the specific submodule
import { ParentIamMember } from "@vitruviansoftware/pulumi-library/parent-iam";

// ❌ Avoid: Importing from the barrel export
import { ParentIamMember } from "@vitruviansoftware/pulumi-library";
```

### 2. Polymorphic Abstractions (Where Applicable)
For areas like IAM, the TypeScript library opts for a polymorphic component (`ParentIamMember`) where the `parentType` dictates the underlying Pulumi resource being created (`gcp.organizations.IAMMember`, `gcp.folder.IAMMember`, etc). This keeps the surface area smaller while achieving similar flexibility to the Go implementation.

### 3. Pulumi Inputs for GCP Resource Fields
Fields that map directly to GCP resource arguments are typed as `pulumi.Input<T>` so they can accept outputs from other resources (like `project.projectId` or `folder.name`), enabling proper asynchronous dependency chains during `pulumi up`.

## Usage Examples

### Create a Project with APIs and Budgets

```typescript
import { ProjectFactory } from "@vitruviansoftware/pulumi-library/project-factory";

const project = new ProjectFactory("my-project", {
    name: "my-app-project",
    orgId: "1234567890",
    billingAccount: "XXXXXX-XXXXXX-XXXXXX",
    folderId: "folders/987654321",
    activateApis: [
        "compute.googleapis.com",
        "iam.googleapis.com",
        "storage.googleapis.com",
    ],
    randomProjectId: true,
    budgetAmount: 1000,
    budgetAlertSpentPercents: [0.5, 0.9, 1.0],
});

export const projectId = project.projectId;
```

### Bind IAM Roles

```typescript
import { ParentIamMember } from "@vitruviansoftware/pulumi-library/parent-iam";

// Organization-level
new ParentIamMember("org-admin", {
    parentType: "organization",
    parentId: "1234567890",
    member: "user:admin@example.com",
    roles: ["roles/resourcemanager.organizationAdmin"],
});

// Project-level
new ParentIamMember("project-viewer", {
    parentType: "project",
    parentId: project.projectId,
    member: "group:viewers@example.com",
    roles: ["roles/viewer"],
});
```

### Enforce Organization Policies

```typescript
import { OrgPolicyBoolean, OrgPolicyList } from "@vitruviansoftware/pulumi-library/org-policy";

// Boolean constraint — enforce
new OrgPolicyBoolean("no-serial-port", {
    organizationId: "1234567890",
    constraint: "constraints/compute.disableSerialPortAccess",
    enforce: true,
});

// List constraint — deny all
new OrgPolicyList("no-external-ip", {
    organizationId: "1234567890",
    constraint: "constraints/compute.vmExternalIpAccess",
    enforce: true, // denies all
});
```

### Create a VPC Network

```typescript
import { Network } from "@vitruviansoftware/pulumi-library/network";

const vpc = new Network("shared-vpc", {
    projectId: project.projectId,
    networkName: "vpc-shared-base",
    routingMode: "GLOBAL",
    subnets: [
        {
            subnetName: "sb-us-central1",
            subnetRegion: "us-central1",
            subnetIp: "10.0.0.0/21",
            subnetPrivateAccess: "true",
            subnetFlowLogs: "true",
            secondaryRanges: [
                { rangeName: "gke-pods", ipCidrRange: "100.64.0.0/21" },
                { rangeName: "gke-svcs", ipCidrRange: "100.64.8.0/21" },
            ],
        },
    ],
});
```

### Create a Secure Cloud Storage Bucket

```typescript
import { SimpleBucket } from "@vitruviansoftware/pulumi-library/simple-bucket";

const bucket = new SimpleBucket("app-data-bucket", {
    projectId: project.projectId,
    name: "my-secure-app-data",
    location: "US",
    versioning: true,
    forceDestroy: false,
});
```

### Export Centralized Logs

```typescript
import { CentralizedLogging } from "@vitruviansoftware/pulumi-library/centralized-logging";

const logging = new CentralizedLogging("org-logs", {
    parentResourceType: "organization",
    parentResourceId: "1234567890",
    destinationProjectId: project.projectId,
    logSinkName: "org-audit-logs",
    filter: "logName: /logs/cloudaudit.googleapis.com%2Factivity",
});
```

## Compatibility

| Dependency | Version |
|------------|---------|
| Node.js | v22+ |
| TypeScript | v5.0+ |
| Pulumi SDK | v3.0.0+ |
| Pulumi GCP Provider | v8.0.0+ |

## Development

```bash
# Install dependencies
npm install

# Build package
npm run build

# Run tests
npm test

# Run tests with coverage
npm run test:coverage
```
