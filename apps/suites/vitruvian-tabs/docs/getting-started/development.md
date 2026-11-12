# Development guide

The day-to-day loop for working on Vitruvian Tabs. Assumes you've done the one-time
[Setup](setup.md).

> **Bazel is the build of record.** Vitruvian Tabs builds and tests through the monorepo graph;
> `pnpm`/`node` are editor/tooling fallbacks, not the source of truth. Repo-wide
> mechanics (branching, the merge queue, CI) live in
> [CONTRIBUTING.md](../../../../../CONTRIBUTING.md); this page is the Vitruvian Tabs-specific inner
> loop.

## The loop

```mermaid
flowchart LR
    A["bazel run //tools/worktree -- my-branch"] --> B["edit code"]
    B --> C["bazel test //apps/suites/vitruvian-tabs/..."]
    C --> D["bazel run //:tidy"]
    D --> E["git push + gh pr create"]
    E --> F["merge queue → main"]
    F --> G["auto-deploy to vitruvian-tabs-development<br/>(blue-green, CI-only)"]
```

## Run the components

| Component | Command | Notes |
|---|---|---|
| **API** | `bazel run //apps/suites/vitruvian-tabs/api:api_bin` | Reads `apps/suites/vitruvian-tabs/api/.env`; serves on `:8080` |
| **CLI** (`vitruvian-tabs`) | `bazel run //apps/suites/vitruvian-tabs/cli:vitruvian-tabs -- <args>` | The admin/ops tool |
| **Extension** | `bazel build //apps/suites/vitruvian-tabs/extension/...` | Then load `bazel-bin/apps/suites/vitruvian-tabs/extension/dist` as an unpacked extension |

**Load the extension in Chrome:** open `chrome://extensions/`, enable *Developer mode*,
click *Load unpacked*, and select `bazel-bin/apps/suites/vitruvian-tabs/extension/dist`.

Backing **Postgres and Redis for tests come up automatically** as Bazel-managed
hermetic services — you do not start a database by hand.

## Test

```bash
bazel test //apps/suites/vitruvian-tabs/...                    # all Vitruvian Tabs tests
bazel test //apps/suites/vitruvian-tabs/api/...                # scope to the API
bazel coverage //apps/suites/vitruvian-tabs/...                # with coverage
```

End-to-end extension specs run as Bazel targets under `//apps/suites/vitruvian-tabs/extension`; flaky
specs are quarantined and exercised nightly rather than blocking a merge — see the
[flaky-test policy](../../../../../docs/engineering/flaky-tests.md) and the Vitruvian Tabs
[testing guide](../guides/testing.md).

## Database migrations (Prisma)

The schema lives at `apps/suites/vitruvian-tabs/api/prisma/schema.prisma`. Migrations follow the repo's
**expand → deploy → contract** model: the deploy applies *expand* (backward-compatible)
migrations **before** traffic shifts, and genuinely destructive changes are separate
`*_contract` migrations applied only after the old revision drains. The
`migration-safety` required check **fails the PR** on an unsafe expand migration.

- Deploy-path migrations run via `bazel run //apps/suites/vitruvian-tabs/api:migrate_deploy_bin -- --phase expand`.
- The full rules (why, and how to mark a contract migration) are in
  [Guiding Principles § 2.15 and Expand/contract migrations](../../../../../docs/engineering/application-development-principles.md#215-infra-lands-before-the-app-that-needs-it--expand-deploy-contract).

## Format & land

```bash
bazel run //:tidy          # gazelle + formatters — REQUIRED before every PR
git push && gh pr create   # never merge locally; the merge queue is the only path to main
```

Use Conventional Commit subjects (`feat:`, `fix:`, `docs:` …) — they drive
release-please.

## How Vitruvian Tabs ships

Merging to `main` **auto-deploys `vitruvian-tabs-development`** via a blue-green Cloud Run
rollout (candidate at 0% traffic → smoke → promote). Promotion to
`vitruvian-tabs-nonproduction`/`vitruvian-tabs-production` is **release-gated** (the release-please PR
merges) and runs the *same* immutable image digest. Deploys are **CI-only** — there is
no local `pulumi up` to production; the pipeline is the trigger. The full picture is in
[The SDLC](../../../../../docs/concepts/sdlc.md), and the infra it deploys into is the
[infrastructure reference](../reference/infrastructure.md).

## Where to go next

- [Architecture overview](../architecture/overview.md) — the system design
- [Operations guide](../guides/operations.md) — running the deployed service
- [Infrastructure reference](../reference/infrastructure.md) — the Pulumi stacks
- [Vitruvian Tabs docs home](../index.md)
