# Errata: Deviations from Upstream Terraform Foundation

This document describes known differences between the
[Pulumi Example Foundation (TypeScript)](../README.md) and the upstream
[Google Terraform Example Foundation](https://github.com/terraform-google-modules/terraform-example-foundation)
that it is ported from. These deviations are tracked here so operators
can evaluate whether they affect their deployment and plan accordingly.

## CI/CD Tool Support

**Upstream:** Provides full deployment instructions and infrastructure for five CI/CD tools:
- Google Cloud Build (default)
- GitHub Actions
- GitLab CI/CD
- Jenkins
- Terraform Cloud / Terraform Enterprise

**This port:** Supports **GitHub Actions** (default) and **GitLab** (alternative).
The deployment pipeline templates are provided in `build/` and are copied to the
operator's repository during onboarding. There are no Jenkins or Terraform Cloud
equivalents. Cloud Source Repositories are not used as they are a
[deprecated Google Cloud product](https://cloud.google.com/source-repositories/docs).

## Policy Validation

**Upstream:** Includes a `policy-library/` directory with OPA-based constraint
templates and uses `gcloud beta terraform vet` to validate plans against
organizational policies before apply.

**This port:** Does not include policy validation infrastructure. Pulumi does
not have a direct equivalent of `terraform vet`. Policy enforcement is handled
via organization policies deployed in Stage 1 and via Pulumi's
[CrossGuard](https://www.pulumi.com/docs/using-pulumi/crossguard/) policy-as-code
framework, which can be adopted separately.

## State Backend

**Upstream:** Uses a GCS-backed Terraform remote state with
`terraform_remote_state` data sources for cross-stage communication. Each stage
has a `backend.tf` file that must be updated with the state bucket name.

**This port:** Uses Pulumi's native
[Stack References](./GLOSSARY.md#pulumi-stack-reference) for cross-stage
communication. State can be stored in Pulumi Cloud (default), a local backend,
or a self-managed GCS backend. There is no `backend.tf` equivalent to update.

## Cloud Build Integration

**Upstream:** The bootstrap stage creates Cloud Build triggers, worker pools,
and Artifact Registry repositories as part of the CI/CD project. Cloud Build
is deeply integrated into the deployment workflow.

**This port:** The CI/CD project (`prj-b-cicd`) is created with the relevant
APIs enabled, but Cloud Build triggers are not provisioned. CI/CD is handled
entirely by GitHub Actions with Workload Identity Federation (WIF).

## Networking: Interconnect and VPN

**Upstream:** Includes complete Terraform modules for:
- Dedicated Interconnect VLAN attachments
- Partner Interconnect VLAN attachments
- HA VPN configuration with BGP sessions

**This port:** Creates the Interconnect project but does not include
Interconnect or VPN resource definitions. The README provides guidance on
where to extend the code, but the resources must be added manually.

## VPC Service Controls

**Upstream:** Includes VPC Service Controls (VPC-SC) perimeter configuration
with Access Context Manager integration, including `access_context.auto.tfvars`
for perimeter member management.

**This port:** Access Context Manager policy creation is supported in Stage 1,
but VPC-SC perimeters and access levels are not configured. The firewall
policies and Private Google Access routes provide a baseline network security
posture.

## Assured Workloads

**Upstream:** Stage 2 (`2-environments`) includes optional Assured Workloads
configuration for compliance-regulated environments.

**This port:** Stage 2 creates per-environment KMS and Secrets projects but
does not include Assured Workloads resource definitions.

## App Infrastructure: Confidential Space

**Upstream:** Stage 5 (`5-app-infra`) deploys a Confidential Space workload
with integrity verification, token claim configuration, and Source Repository
integration.

**This port:** Stage 5 deploys sample Compute Engine instances using the
shared library components. Confidential Space resources are not included.

## Naming Conventions

**Upstream:** Uses a consistent naming scheme documented in the
[Security Foundations Guide](https://cloud.google.com/architecture/security-foundations/using-example-terraform#naming_conventions),
including random suffixes on project IDs to avoid collisions.

**This port:** Follows the same naming conventions. All project IDs receive
a random suffix via the shared `ProjectFactory` component to match the upstream
`terraform-google-project-factory` module's `random_project_id` feature.

## Essential Contacts and Tags

**Upstream:** Provides detailed configuration tables for Essential Contacts
(notification categories by group) and organization-level tags (environment
classification).

**This port:** Implements both Essential Contacts and Tags in Stage 1, but the
configuration is applied programmatically in TypeScript rather than via `.tfvars`
files. Customization requires modifying the TypeScript source or Pulumi config.
