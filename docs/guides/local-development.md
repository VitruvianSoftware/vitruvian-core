# Local development

One page for "how do I run this thing on my machine?" — every app, in one place.
The repo-wide setup (toolchain, worktrees, the merge queue) lives in
[CONTRIBUTING](../../CONTRIBUTING.md); this page is the per-app inner loop and the
`devx` orchestration layer that backs it.

## Before anything else

```bash
nvm use && corepack enable    # Node 22 + pnpm, versions from .nvmrc / packageManager
bazel run //:doctor           # core toolchain check
bazel run //<app>:doctor      # per-app check — //apps/suites/tabula:doctor, //apps/cli/devx:doctor, …
```

Every app has a `doctor` target (`tabula`, `oauth-user-inspector`, `devx`, `homelab`,
`mcp-slack`, `nexus-agent`). Run it first whenever a build behaves strangely — it is
faster than decoding a toolchain error.

Branch work happens in an isolated worktree — this is **enforced**, not advisory:

```bash
bazel run //tools/worktree -- my-branch
```

## Pick your app

| App | Run it | Test it | Backing services |
|---|---|---|---|
| **tabula** (API) | `bazel run //apps/suites/tabula/api:api_bin` — or `devx up` (see below) | `bazel test //apps/suites/tabula/...` | Postgres + Redis |
| **tabula** (CLI) | `bazel run //apps/suites/tabula/cli:tabcli -- --help` | `bazel test //apps/suites/tabula/...` | — |
| **tabula** (extension) | `bazel build //apps/suites/tabula/extension:dist`, then load `bazel-bin/apps/suites/tabula/extension/dist` unpacked | `bazel test //apps/suites/tabula/...` | — |
| **oauth-user-inspector** | `pnpm dev` (Vite `:5173` + Express `:8080`) — or `devx up` | `bazel test //apps/web/oauth-user-inspector/...` | none (GCP Secret Manager) |
| **devx** | `bazel run //apps/cli/devx:devx -- <args>` | `bazel test //apps/cli/devx/...` | — |
| **homelab** | `bazel run //apps/cli/homelab/cmd/homelab -- <args>` | `bazel test //apps/cli/homelab/...` | — |
| **mcp-slack** | `pnpm install && pnpm build && pnpm start` | — *(no tests yet)* | — |
| **nexus-agent** | `pnpm dev` (bot); macOS app: `bazel build --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgent` | — *(no tests yet)* | — |

**Bazel is the build of record.** `pnpm`/`go` are fallbacks for editor flows and
container builds. Tests never need a hand-started database: Postgres/Redis for the
Bazel test suites come up as **hermetic, Bazel-managed test services**.

> There is no `docker-compose.yml` in this repo. If a doc tells you to run
> `docker-compose up`, it is stale — please fix it.

## Running with `devx`

`devx` is the repo's local-dev orchestrator: it provisions backing databases and runs
your services in dependency order with healthcheck gating. Apps that benefit declare a
committed **`devx.yaml`**.

```mermaid
flowchart LR
    Y["devx.yaml"] --> U["devx up"]
    U --> DB[("databases:<br/>postgres · redis")]
    U --> S["services:<br/>started in depends_on order,<br/>gated on healthchecks"]
    DB -->|"service_healthy"| S
    Y --> M["devx map<br/>(validate + visualise)"]
```

Which apps ship one today:

| App | `devx.yaml` | What it declares |
|---|---|---|
| [`tabula/api`](../../apps/suites/tabula/api/devx.yaml) | ✅ | Postgres + Redis, then the API gated on both being healthy |
| [`oauth-user-inspector`](../../apps/web/oauth-user-inspector/devx.yaml) | ✅ | Express backend + Vite frontend (no database — it has none) |
| `devx`, `homelab`, `mcp-slack`, `nexus-agent` | — | No backing services; the plain `bazel run`/`pnpm` loop above is the whole story |
| [`infrastructure/pulumi/platform/dev-local`](../../infrastructure/pulumi/platform/dev-local/devx.yaml) | ✅ | Not an app — uses `customActions` to wrap Pulumi verbs |

```bash
cd apps/suites/tabula/api
devx up      # bring up Postgres + Redis, then the API
devx map     # validate this devx.yaml and print its dependency graph
```

### Three things about `devx.yaml` that surprise people

1. **`devx up` does not write or read a `.env` file.** A `host` service receives
   *only* its own `env:` map plus `PORT`. Anything else (`JWT_SECRET`, `WORKOS_*`)
   must come from the app's own loader — `apps/suites/tabula/api` reads its gitignored
   `apps/suites/tabula/api/.env` via `dotenv`, which does **not** override what `devx` already set.
2. **Unknown keys are silently ignored.** The config is parsed non-strictly, so a
   typo or an invented field is discarded without warning. A `databases:` entry
   accepts exactly `engine`, `port`, `pull`, `seed` — there is **no `name:` and no
   `version:`** (some older `devx` docs show them; they do nothing). Validate with
   `devx map` from the file's directory.
3. **`depends_on` references a database by its *engine*** — `- name: postgres`, not a
   container or instance name.

Connection strings for devx-provisioned databases are fixed:
`postgresql://devx:devx@localhost:5432/devx` and `redis://localhost:6379`.

## Local secrets

Secrets never live in git. Local dev uses **gitignored** files seeded from a committed
`.env.example`:

| App | File | Template |
|---|---|---|
| `tabula` (API) | `apps/suites/tabula/api/.env` | ✅ `apps/suites/tabula/api/.env.example` |
| `nexus-agent` | `apps/desktop/nexus-agent/.env` | ✅ `apps/desktop/nexus-agent/.env.example` |
| `devx` | `.env` / `.env.keys` | ✅ `apps/cli/devx/.env.example` (also `devx config secrets`) |
| `oauth-user-inspector` | env vars / GCP Secret Manager | ❌ no `.env.example` yet |
| `homelab`, `mcp-slack` | env vars | ❌ no `.env.example` yet |

The three ❌ rows are a tracked gap — every app that reads env config should ship a
placeholder `.env.example`. See
[Alignment gaps](../engineering/application-alignment-gaps.md). The full three-tier
model (GCP Secret Manager / sealed-secrets / env-injected Pulumi config) is
[CONTRIBUTING § Secrets handling](../../CONTRIBUTING.md#7-secrets-handling).

## Before you push

```bash
bazel test //<app>/...
bazel run //:tidy          # REQUIRED — the tidy-check job fails the PR on any diff
git push && gh pr create   # never merge locally
```

## Related

- [App developer quick start](../getting-started/app-developer.md) — the orientation page
- [The SDLC](../concepts/sdlc.md) — what happens after you push
- [Bazel targets & tools](../reference/bazel-targets.md) — every runnable target
- [Build caching](build-cache.md) · [Remote builds](remote-build.md) — make it fast
- [Flaky tests](../engineering/flaky-tests.md) — when a test is not your fault
