# Repo Config — Pulumi IaC for this repo's GitHub settings

This directory contains a **self-contained, runnable Pulumi Go program** that
manages **this** generated repository's own GitHub settings:

- **Auto-delete head branch on merge** (`delete_branch_on_merge = true`).
- **Branch protection** on the default branch, fully parameterized from Pulumi
  config (see below).

Unlike `../copybara_sync` (a gated library), this module is always shipped and is
a standalone `package main` you can `pulumi up` directly.

---

## What this provisions

| Resource | Purpose |
|---|---|
| `github.NewRepository` (adopted via `pulumi.Import`) | Sets `DeleteBranchOnMerge = true` on the existing repo |
| `github.NewBranchProtection` | Protects the default branch per the config below |
| `github.NewRepositoryEnvironment` + variables | Per-component `tabula-{development,nonproduction,production}` deploy environments |
| `github.NewDependabotSecret` (`BUILDBUDDY_API_KEY`) | Gives Dependabot PRs the BuildBuddy key so `build-test` (RBE) doesn't fail `UNAUTHENTICATED` — only created when `buildbuddyApiKey` is configured |
| `github.NewIssueLabel` (`dependencies`, `go`, `ci`) | The labels `.github/dependabot.yml` applies to dependency PRs (Dependabot warns + skips if they don't exist) |

The repository **already exists** (you created it), so this program **adopts**
it with `pulumi.Import(pulumi.ID(<repoName>))` instead of creating it. It also
uses `pulumi.IgnoreChanges` for `description`, `visibility`, `hasIssues`,
`hasProjects`, `hasWiki`, and `name`, so Pulumi only owns `DeleteBranchOnMerge`
and never clobbers attributes you manage elsewhere.

---

## Config keys

Set with `pulumi config set <key> <value>`.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `repoOwner` | string | **required** | GitHub org or user that owns the repo |
| `repoName` | string | `vitruvian-core` | Repository name (override if renamed) |
| `defaultBranch` | string | `main` | Branch to protect |
| `requirePullRequest` | bool | `true` | Require a PR before merging |
| `requiredApprovals` | int | `0` | Approving reviews required (when PRs required) |
| `requireStatusChecks` | bool | `true` | Require status checks (Strict / up-to-date) |
| `statusCheckContexts` | string list | _(empty)_ | Named checks that must pass; empty → just Strict |
| `enforceAdmins` | bool | `false` | Apply protection to admins too |
| `tabulaVars` | object | _(empty)_ | Per-environment Actions variables for the tabula deploy environments (see below) |
| `tabulaProductionReviewers` | string list | _(see below)_ | GitHub usernames required to approve `tabula-production` deployments (resolved to ids; works with integration tokens) |
| `tabulaProductionReviewerIds` | int list | _(unset)_ | Numeric GitHub user ids, used verbatim (overrides `tabulaProductionReviewers`) |
| `buildbuddyApiKey` | **secret** | _(unset)_ | BuildBuddy API key mirrored into the repo's **Dependabot** secret store (see below). When unset, no Dependabot secret is managed. |

Force-pushes and branch deletions are **always** blocked on the protected
branch.

### Dependabot secret (`buildbuddyApiKey`)

GitHub does not pass regular Actions secrets to Dependabot-triggered workflow
runs, so the `build-test` job's BuildBuddy RBE auth
(`--remote_header=x-buildbuddy-api-key=$BUILDBUDDY_API_KEY`) fails with
`UNAUTHENTICATED` on every dependency PR — a false-negative unrelated to the
bump. Setting the key as a **Dependabot** secret fixes it for all Dependabot
PRs. Store the same value as the existing `BUILDBUDDY_API_KEY` Actions secret,
as an encrypted Pulumi config secret (never commit it in plaintext):

```bash
pulumi config set --secret buildbuddyApiKey <buildbuddy-api-key> --stack dev
```

`statusCheckContexts` is a JSON list, e.g.:

```bash
pulumi config set --path statusCheckContexts[0] "build"
pulumi config set --path statusCheckContexts[1] "test"
```

### Tabula deploy environments

This program also manages the GitHub Environments used by
`.github/workflows/tabula-deploy.yaml`: `tabula-development`,
`tabula-nonproduction`, and `tabula-production`. The environment name carries
the component namespace, so variables inside use bare names and
`tabula-production`'s protection rules (required reviewer, deployments only
from protected branches) are scoped to tabula alone.

Only non-credential identifiers are stored, as environment **variables**
(keyless Workload Identity Federation needs no key material); runtime secrets
such as `DATABASE_URL` live in GCP Secret Manager, managed by
`//infrastructure/pulumi/tabula`. `GCP_DEPLOY_SERVICE_ACCOUNT` is the CI
*deployer* identity impersonated via WIF — distinct from the Cloud Run
*runtime* service account (`tabula-api-<env>`), which the tabula Pulumi
program creates. Values are plain identifiers and are
committed in `Pulumi.<stack>.yaml`:

```bash
pulumi config set --path 'tabulaVars["development"]["GCP_PROJECT_ID"]' my-project
pulumi config set --path 'tabulaVars["development"]["GCP_DEPLOY_SERVICE_ACCOUNT"]' deployer@my-project.iam.gserviceaccount.com
pulumi config set --path 'tabulaVars["development"]["GCP_WORKLOAD_IDENTITY_PROVIDER"]' projects/123/locations/global/workloadIdentityPools/github/providers/github
# optional: GCP_REGION (the workflow defaults to us-central1)
```

Environments with no `tabulaVars` entry are still created (empty), so the
protection rules exist before their first deploy is configured.

`tabulaProductionReviewers` should stay set in the committed stack config: the
fallback (the token's own user via `GET /user`) only works for human tokens —
the Actions `GITHUB_TOKEN` is an integration token and gets a 403 from that
endpoint, which would fail the CI preview/apply runs.

---

## One-time setup

### 1. Set the GitHub provider token

```bash
export GITHUB_TOKEN=<your PAT or token with repo + admin scope>
```

### 2. Set required config and run

```bash
cd infrastructure/pulumi/repo_config
go mod tidy
pulumi config set repoOwner <your-org-or-user>
# optionally override the defaults above, e.g.:
# pulumi config set requiredApprovals 1
pulumi up --stack dev
```

> **Adoption note:** the first `pulumi up` **imports** the existing repository
> into state (it does not create it). If the import fails because the name or
> owner is wrong, fix `repoName` / `repoOwner` (and the `GITHUB_TOKEN`'s account)
> and retry — no resource is created until the import resolves.

---

## Ongoing operations

- **Tighten/loosen protection:** change the relevant config key and `pulumi up`.
- **Change the protected branch:** set `defaultBranch` and `pulumi up`.
- **Stop managing a repo:** `pulumi destroy` removes the branch protection and
  releases the repository from state (it is **not** deleted on GitHub).

---

## CI/CD automation

Two opt-in GitHub Actions workflows drive this module from CI (off by default;
enable via `bazel run //infrastructure/pulumi/repo_config:setup`, or by setting
the repo variables directly):

| Workflow | Trigger | Gate (repo variable) | Action |
|---|---|---|---|
| `.github/workflows/_repo-config-preview.yaml` | PR touching `infrastructure/pulumi/repo_config/**` | `REPO_CONFIG_PREVIEW_ENABLED=true` | posts a cleaned-up `pulumi preview --diff` comment |
| `.github/workflows/_repo-config-apply.yaml` | push to the default branch touching the same path | `REPO_CONFIG_AUTO_APPLY=true` | runs `pulumi up` |

The preview comment shows only the Pulumi diff — Bazel build output and ANSI
escape codes are stripped so the sticky comment stays readable.

Auth uses a shared least-privilege GitHub App (`Administration: write` +
`Contents: read` + `Variables: write` + `Issues: write` (dependency-PR labels) +
`Dependabot secrets: write` (the `BUILDBUDDY_API_KEY` Dependabot secret) — each
behind its own fine-grained permission) created once via
`bazel run //tools/pulumi:create-app`: the workflows mint a short-lived
installation token from `PULUMI_APP_ID` (variable) + `APP_PRIVATE_KEY` (secret),
and reach the Pulumi Cloud backend via `PULUMI_ACCESS_TOKEN` (secret).

> **Note:** if the App was created before these permissions were added, grant
> `Issues: write` and `Dependabot secrets: write` to the existing App (Developer
> settings → GitHub Apps → *…-pulumi* → Permissions) and **re-approve** the
> installation, or the auto-apply will `403` when creating the labels/secret.
