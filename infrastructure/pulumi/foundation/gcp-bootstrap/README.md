# foundation-bootstrap

Live **bootstrap** stage of the GCP foundation for the **vitruviansoftware.dev**
organization. Copied from the reference template at
`pulumi/examples/go-foundation/0-bootstrap` and adapted to run **inside this
monorepo** (not the upstream one-repo-per-stage model).

## What it creates

A seed project (`prj-b-seed`: KMS-encrypted state bucket) and a CI/CD project
(`prj-b-cicd`), the five granular per-stage service accounts
(`sa-terraform-{bootstrap,org,env,net,proj}`), least-privilege org/folder IAM,
and a Workload Identity Federation pool + GitHub OIDC provider — all under the
`fldr-bootstrap` folder.

## How it differs from the reference template

- **Consumes the published `pulumi-library` modules** (no `replace` directives) —
  dogfoods the mirror-published versions exactly as an external consumer would.
- **Backend is Pulumi Cloud** (org `ipv1337`), not the self-managed GCS bucket.
- **Co-tenant**: deployed under a new `fldr-foundation-1` umbrella folder
  (`parent_folder`) so it never touches the existing `fldr-foundation-0`
  foundation. The authoritative org-level `billing.creator` binding is gated
  behind `enforce_org_billing_creator` (default **false**).
- **WIF is scoped to one repo** (`VitruvianSoftware/vitruvian-core`) by **GitHub
  Environment** (`attribute.environment/foundation-<stage>`) instead of one repo
  per stage. WIF provider name + SA emails are published to GitHub Environments
  by the `infrastructure/pulumi/platform/repo_config` project, not from here.
- **Identity**: authenticates as `james@vitruviansoftware.dev` via
  `infrastructure/gcp-identities.tsv` + the Pulumi Bazel wrapper.

## Usage

```bash
# Create the umbrella folder first and record its id:
bazel run //infrastructure/pulumi/foundation/org-folders:up

# Fill the REPLACE-* placeholders in Pulumi.production.yaml (org_id,
# billing_account, group emails, parent_folder), then:
bazel run //infrastructure/pulumi/foundation/gcp-bootstrap:preview -- --diff
bazel run //infrastructure/pulumi/foundation/gcp-bootstrap:up          # manual first apply
```

Prereq: `gcloud auth login james@vitruviansoftware.dev` with
`organizationAdmin` + `billing.admin` + `projectCreator` + `folderCreator`.
