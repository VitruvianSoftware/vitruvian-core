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

Force-pushes and branch deletions are **always** blocked on the protected
branch.

`statusCheckContexts` is a JSON list, e.g.:

```bash
pulumi config set --path statusCheckContexts[0] "build"
pulumi config set --path statusCheckContexts[1] "test"
```

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
| `.github/workflows/_repo-config-preview.yaml` | PR touching `infrastructure/pulumi/repo_config/**` | `REPO_CONFIG_PREVIEW_ENABLED=true` | posts a `pulumi preview` diff comment |
| `.github/workflows/_repo-config-apply.yaml` | push to the default branch touching the same path | `REPO_CONFIG_AUTO_APPLY=true` | runs `pulumi up` |

Auth uses a shared least-privilege GitHub App (`Administration: write` +
`Contents: read`) created once via `bazel run //tools/pulumi:create-app`: the
workflows mint a short-lived installation token from `PULUMI_APP_ID` (variable) +
`APP_PRIVATE_KEY` (secret), and reach the Pulumi Cloud backend via
`PULUMI_ACCESS_TOKEN` (secret).
