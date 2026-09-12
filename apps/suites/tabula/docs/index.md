# Tabula documentation

Tabula is a browser tab-management product: a **TypeScript API on Cloud Run**, an
**MV3 browser extension**, a **web dashboard**, and an admin **CLI** (`tabcli`) — all
built and shipped from the `vitruvian-core` monorepo. It is the most mature deploy in
the repo.

> **Where this fits.** These docs cover Tabula specifically. For repo-wide mechanics —
> the toolchain, the merge queue, the SDLC, secrets — the canonical sources are the
> root [CONTRIBUTING.md](../../CONTRIBUTING.md) and the
> [documentation hub](../../docs/README.md). When a Tabula page and CONTRIBUTING
> disagree, **CONTRIBUTING wins** and please open a PR to fix the drift.

## Start here

| You want to… | Go to |
|---|---|
| **Run Tabula locally** | [Getting started → Setup](getting-started/setup.md) then [Development](getting-started/development.md) |
| **Understand the system** | [Architecture overview](architecture/overview.md) |
| **Operate / deploy it** | [Operations guide](guides/operations.md) · [Releases](guides/releases.md) |
| **Look up the infra** | [Infrastructure reference](reference/infrastructure.md) |
| **Use the API or CLI** | [API reference](reference/api.md) · [CLI reference](reference/cli.md) |

## Components

| Component | Path | What it is |
|---|---|---|
| **API** | [`tabula/api`](../api) | TypeScript service (Prisma + Postgres, Redis), deployed to Cloud Run |
| **Extension** | [`tabula/extension`](../extension) | Manifest-V3 browser extension (React) |
| **Web** | [`tabula/web`](../web) | Web dashboard |
| **CLI** | [`tabula/cli`](../cli) | `tabcli`, the admin/ops command-line tool |
| **Shared** | [`tabula/shared`](../shared) | Shared TypeScript types |
| **Infra** | [`tabula/infra`](../infra) | Pulumi-in-Go stacks: `build`, `data`, `identity`, `app` |

## Documentation map

- **[architecture/](architecture/overview.md)** — system design: [overview](architecture/overview.md),
  [specs](architecture/specs.md), [NFRs](architecture/nfr.md),
  [authentication](architecture/authentication.md),
  [sync strategy](architecture/sync-strategy.md),
  [conflict resolution](architecture/conflict-resolution.md),
  [sharing & permissions](architecture/sharing-and-permissions.md),
  [threat model](architecture/threat-model.md), and the
  [ADRs](architecture/adr/README.md).
- **[getting-started/](getting-started/setup.md)** — [setup](getting-started/setup.md)
  and the [development guide](getting-started/development.md).
- **[guides/](guides/operations.md)** — operator/user how-tos:
  [operations](guides/operations.md), [releases](guides/releases.md),
  [build guide](guides/build-guide.md), [testing](guides/testing.md),
  [web dashboard](guides/web-dashboard.md), [command palette](guides/command-palette.md),
  [account settings](guides/account-settings.md),
  [WorkOS configuration](guides/workos-configuration.md),
  [workspace operations](guides/workspace-operations.md).
- **[reference/](reference/api.md)** — [API](reference/api.md), [CLI](reference/cli.md),
  [extension](reference/extension.md), [infrastructure](reference/infrastructure.md).
- **[product/](product/REQUIREMENTS.md)** — requirements, gap analysis, UI design
  language, user-journey walkthroughs, competitive research.

## Quick links

- [Tabula README](../README.md) — component overview and quick start
- [Tabula CONTRIBUTING](../CONTRIBUTING.md) — Tabula-scoped contribution notes
- [Repo SOP (CONTRIBUTING.md)](../../CONTRIBUTING.md) — the authoritative build/test/deploy runbook
- [The SDLC](../../docs/concepts/sdlc.md) — how a change reaches production
- [Guiding Principles](../../docs/engineering/application-development-principles.md) — the engineering standard

> **A note on ADRs and product docs.** Architecture Decision Records are immutable by
> design — they capture a decision *at a point in time* and are not edited to match
> later reality. Some product docs likewise reflect earlier planning. Treat the
> getting-started, guides, and reference pages as the living, current material.
