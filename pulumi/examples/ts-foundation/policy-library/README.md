# Policy Library

This directory contains [Pulumi CrossGuard](https://www.pulumi.com/docs/using-pulumi/crossguard/)
policy packs that enforce organizational compliance rules before infrastructure
is deployed. These policies are the Pulumi equivalent of the upstream Terraform
foundation's `policy-library/` directory which uses OPA constraints validated
via `gcloud beta terraform vet`.

## Architecture

```
policy-library/
├── README.md                   ← This file
├── index.ts                    ← Policy pack entry point
├── package.json                ← Node.js dependencies
├── tsconfig.json               ← TypeScript configuration
└── policies/
    ├── project-policies.ts     ← Project-level policies
    ├── iam-policies.ts         ← IAM policies
    └── network-policies.ts     ← Network/firewall policies
```

## Policies

### Project Policies

| Policy | Severity | Description |
|--------|----------|-------------|
| `no-default-network` | mandatory | Projects must not create the default network |
| `project-labels-required` | mandatory | Projects must have `environment` and `application_name` labels |
| `deletion-policy-prevent` | advisory | Projects should use `PREVENT` deletion policy |

### IAM Policies

| Policy | Severity | Description |
|--------|----------|-------------|
| `no-sa-key-creation` | mandatory | Service account keys must not be created (use WIF instead) |
| `no-public-access` | mandatory | Resources must not grant `allUsers` or `allAuthenticatedUsers` |
| `restrict-owner-role` | advisory | `roles/owner` should not be used in IAM bindings |

### Network Policies

| Policy | Severity | Description |
|--------|----------|-------------|
| `no-public-ip` | mandatory | Compute instances must not have external IPs |
| `require-private-google-access` | mandatory | Subnets must enable Private Google Access |
| `require-flow-logs` | advisory | Subnets should have VPC Flow Logs enabled |

## Usage

### Running Locally

```bash
cd policy-library
npm install

# Validate against a specific stack
pulumi preview --policy-pack ./policy-library

# Or apply with policy enforcement
pulumi up --policy-pack ./policy-library
```

### CI/CD Integration

Add the `--policy-pack` flag to your preview and apply steps in the CI/CD pipeline:

```yaml
# In .github/workflows/pulumi-preview.yml
- uses: pulumi/actions@v5
  with:
    command: preview
    stack-name: ${{ github.base_ref }}
    comment-on-pr: true
    policyPacks: policy-library
```

### Configuring Policy Severity

Policies can be set to `mandatory` (blocks deployment), `advisory` (warns), or
`disabled`. Override severity per-stack in your `Pulumi.<stack>.yaml`:

```yaml
config:
  pulumi:policyPacks:
    - name: foundation-policies
      enforcementLevel: advisory  # Override all to advisory for dev
```

## Relationship to Upstream Terraform Policies

The upstream Terraform foundation uses [Config Validator](https://github.com/GoogleCloudPlatform/config-validator)
with OPA Rego constraints, validated via `gcloud beta terraform vet`. This
CrossGuard policy pack provides equivalent compliance coverage using Pulumi's
native policy-as-code framework, with the advantage of being evaluated at
preview-time (before any API calls) rather than post-plan.

| Terraform Constraint | CrossGuard Equivalent | Status |
|---------------------|-----------------------|--------|
| `GCPExternalIpAccessConstraintV1` | `no-public-ip` | ✅ |
| `GCPServiceUsageConstraintV1` | Enforced via org policy in Stage 1 | ✅ |
| `GCPIAMAllowedPolicyMemberDomainsConstraintV2` | Enforced via org policy in Stage 1 | ✅ |
| `GCPResourceValuePatternConstraintV1` (labels) | `project-labels-required` | ✅ |
