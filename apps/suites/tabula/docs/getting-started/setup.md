# Setup

Get a working Tabula checkout. This page covers the **one-time** setup; the
day-to-day loop is in the [Development guide](development.md).

> Tabula builds through the monorepo's Bazel graph. The prerequisites and their exact
> pinned versions are repo-wide — this page defers to the canonical
> [CONTRIBUTING § Prerequisites & toolchain](../../../CONTRIBUTING.md#1-prerequisites--toolchain)
> rather than duplicating (and drifting from) them.

## 1. Toolchain

You need **Bazelisk** (installed as `bazel`), **Node 22** (pinned in `.nvmrc`),
**pnpm** (via Corepack), and **Go** (for the `tabula/infra` Pulumi programs). For cloud
work you also need **gcloud** and **gh**.

```bash
# from the repo root
nvm use && corepack enable     # Node 22 + pnpm (versions come from .nvmrc / packageManager)
bazel run //tabula:doctor      # verify your toolchain has exactly what Tabula needs
```

`//tabula:doctor` checks Tabula's specific requirements and fails with a clear message
if anything is missing or the wrong version — run it first whenever a build behaves
oddly.

## 2. Work in a git worktree

Branch work is **enforced** to happen in an isolated worktree (a plain checkout on a
non-`main` branch will fail the workspace-status guard):

```bash
bazel run //tools/worktree -- my-tabula-branch
```

## 3. Local secrets

The API reads a **gitignored** `tabula/api/.env`. Create it from the committed
template and fill in the values:

```bash
cp tabula/api/.env.example tabula/api/.env
```

Keys: `DATABASE_URL`, `JWT_SECRET`, `WORKOS_*`, `UPSTASH_REDIS_URL`. These are **local
dev** values — production runtime secrets live in **GCP Secret Manager** and are read
by the Cloud Run runtime service account, never checked out locally. The full model is
in [CONTRIBUTING § Secrets handling](../../../CONTRIBUTING.md#7-secrets-handling).

> **No `docker-compose`, no Terraform.** Backing Postgres/Redis for tests come up as
> **Bazel-managed hermetic services** — you don't run a database by hand. There is no
> `docker-compose.yml` in this repo, and the infrastructure is Pulumi-in-Go
> (see the [infrastructure reference](../reference/infrastructure.md)).

## 4. Build & test

```bash
bazel build //tabula/...
bazel test  //tabula/...
```

That's it — you're set up. Head to the [Development guide](development.md) for the
inner loop (running the API, loading the extension, migrations, and the PR flow).

## Where to go next

- [Development guide](development.md) — the day-to-day loop
- [Tabula docs home](../index.md)
- [The SDLC](../../../docs/concepts/sdlc.md) — how a Tabula change reaches production
- [Architecture overview](../architecture/overview.md)
