# Errata: Deviations from Upstream Terraform Foundation

This document describes known differences between the
[Pulumi Example Foundation](../README.md) and the upstream
[Google Terraform Example Foundation](https://github.com/terraform-google-modules/terraform-example-foundation)
that it is ported from. These deviations are tracked here so operators
can evaluate whether they affect their deployment and plan accordingly.

## CI/CD Tool Support

**Upstream:** Provides full deployment instructions and infrastructure for five CI/CD tools:

- Google Cloud Build (default)
- GitHub Actions
- GitLab CI/CD
- Terraform Cloud / Terraform Enterprise

**This port:** Uses **GitHub Actions** as the default CI/CD tool (with Workload
Identity Federation), reversing the upstream default of Cloud Build. Pipeline
templates are provided in `build/pulumi-preview.yml` and `build/pulumi-up.yml`.
Alternative CI/CD tool support is available via opt-in `.example` files:

- **GitLab CI/CD:** `build/gitlab-ci.yml` + `0-bootstrap/build_gitlab.go.example`
  with instructions in `0-bootstrap/README-GitLab.md`
- **Cloud Build:** `0-bootstrap/build_cb.go.example` with instructions
  in `0-bootstrap/README-CloudBuild.md`
- **Terraform Cloud:** `0-bootstrap/build_terraform_cloud.go.example`

Cloud Build triggers, per-stage log/artifact buckets, and the automated
runner-image build pipeline (`tf_cloud_builder` module) are not ported. The
private worker pool infrastructure is also not ported in the Go foundation
(the TS port includes it via the `cb-private-pool` library component).

## Policy Validation

**Upstream:** Includes a `policy-library/` directory with 28 OPA constraint
files and 81 template files, enforced via `gcloud beta terraform vet` in every
CI pipeline.

**This port:** Provides a CrossGuard policy pack in the
[TypeScript foundation's `policy-library/`](https://github.com/VitruvianSoftware/pulumi_ts-example-foundation/tree/main/policy-library)
directory with 7 policies covering public access, firewall rules, flow logs,
and naming conventions. The Go foundation references this pack via its own
`policy-library/README.md`.

The CrossGuard pack is wired into the CI/CD pipeline templates:
`build/pulumi-preview.yml`, `build/pulumi-up.yml`, and `build/gitlab-ci.yml`
all pass `--policy-pack ../policy-library`, so every preview/apply is
policy-checked. **Known gap:** coverage is narrower than TF's 28+81 constraint
suite (no GKE, BigQuery, Cloud SQL SSL, or service-usage allowlist constraints).

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
APIs enabled, but Cloud Build triggers are not provisioned by default. CI/CD
is handled by GitHub Actions with Workload Identity Federation (WIF). Cloud
Build support is available as an opt-in alternative via the `.example` files
described above, but the automated runner-image build pipeline and per-stage
log/artifact buckets are not ported.

## Networking: Interconnect and VPN

**Upstream:** Includes complete Terraform modules for:

- Dedicated Interconnect VLAN attachments
- Partner Interconnect VLAN attachments
- HA VPN configuration with BGP sessions

**This port:** Provides `.example` files implementing Interconnect and VPN
attachments in both `3-networks-svpc/` and `3-networks-hub-and-spoke/` stages.
These are opt-in scaffolds that must be activated by the operator. **Known
gaps:** the example attachments do not include BGP session/peer configuration
(TF examples create full `google_compute_router_interface` +
`google_compute_router_peer` resources), and partner interconnect
`preactivate` handling is not ported.

## VPC Service Controls

**Upstream:** Includes VPC Service Controls (VPC-SC) perimeter configuration
with Access Context Manager integration, including `access_context.auto.tfvars`
for perimeter member management.

**This port:** Implements VPC-SC perimeters and access levels in
`3-networks-svpc` and `3-networks-hub-and-spoke` via the shared library's
`vpc-service-controls` component. Access Context Manager policy creation is
supported in Stage 1. The hub project in hub-and-spoke topology now receives its
own VPC-SC perimeter, created once in the shared/hub stack (matching TF).

## Assured Workloads

**Upstream:** Stage 2 (`2-environments`) includes optional Assured Workloads
configuration for compliance-regulated environments.

**This port:** Implements Assured Workloads in Stage 2 via the
`AssuredWorkloadConfig` structure, with `FEDRAMP_MODERATE` as the default
compliance regime. The `assured_workload_id` and `assured_workload_resources`
values are exported as stack outputs, and both ports wire the configuration
into the environment stacks.

## App Infrastructure: Stage 5

**Upstream:** Stage 5 (`5-app-infra`) deploys sample workloads per business
unit environment:

- Service account + instance template + compute instance on the SVPC project
- The same on the peering project
- A Confidential Space stack (WIF pool, OIDC provider, confidential VM)

**This port:** The default `5-app-infra` program deploys the env_base workload
(service account, instance template, and compute instance on the SVPC project)
and the Confidential Space stack (WIF pool, OIDC provider, confidential VM) by
default, via the `modules/env_base` and `modules/confidential_space` packages
invoked from `main()`. **Known gap:** the peering-project workload (the same VM
on the peering project) is not yet deployed; only the SVPC-project workload and
the Confidential Space stack are created.

## Naming Conventions

**Upstream:** Uses a consistent naming scheme documented in the
[Security Foundations Guide](https://cloud.google.com/architecture/security-foundations/using-example-terraform#naming_conventions),
including random suffixes on project IDs to avoid collisions.

**This port:** ~~Does not append random suffixes.~~ **Resolved.** All project
IDs now receive a 4-character random hex suffix (e.g., `prj-b-seed-a1b2`) via
the `RandomProjectID` option on the shared `project.NewProject` component, and
the state bucket name receives an independent suffix. This matches the upstream
`terraform-google-project-factory` module's `random_project_id` feature. The
suffix is generated once by a `random.RandomId` resource and persisted in
Pulumi state.

## Essential Contacts and Tags

**Upstream:** Provides detailed configuration tables for Essential Contacts
(notification categories by group) and organization-level tags (environment
classification).

**This port:** Implements both Essential Contacts and Tags in Stage 1, but the
configuration is applied programmatically in Go rather than via `.tfvars` files.
Customization requires modifying the Go source.
