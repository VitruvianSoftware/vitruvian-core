# Pulumi Platform: Sentry

First-party self-hosted Sentry infrastructure as code: manages teams, projects, client keys (DSNs), and optional issue alerts against our homelab Sentry instance (`https://sentry.lab.ipv1337.dev/api/`).

## Stacks

- **`production`**: The production self-hosted Sentry stack (`Pulumi.production.yaml`, committed non-secret config-as-code guarded by `internal/config/config_test.go`).

## CI apply and local preview

This stack is applied automatically by
[`.github/workflows/sentry-apply.yaml`](../../../../.github/workflows/sentry-apply.yaml)
against the `production` stack (before
[`infrastructure/pulumi/platform/sentry-pagerduty`](../sentry-pagerduty/README.md),
so newly added Sentry projects receive PagerDuty alert rules in the same run):

- **Triggers**: `push` to `main` (touching `infrastructure/pulumi/platform/sentry/**`,
  `infrastructure/pulumi/platform/sentry-pagerduty/**`, `.github/workflows/sentry-apply.yaml`,
  `.github/actions/homelab-tunnel-setup/**`, `.github/actions/pulumi-summary/**`,
  or the Pulumi CI helper binaries), a 6-hour `schedule`, and `workflow_dispatch`
  (`action: preview|up`, defaulting to `preview`).
- **Environment**: `sentry-production` (main-only, no required reviewer,
  declared in [`repo-config`](../repo-config/sentry_environments.go)). Holds
  `SENTRY_TOKEN` (minted with `bazel run //tools/sentry:ci-token`) and
  `HEADSCALE_CI_AUTHKEY` (synced via
  [`//tools/sync-env-secrets`](../../../../tools/sync-env-secrets/README.md#sentry-production)).
  If `SENTRY_TOKEN` is not seeded yet, the workflow emits a `::notice::` and
  exits `0`.
- **Non-destructive plan guard**: before `pulumi up`, the job runs
  `pulumi preview --json` and checks it with `//tools/pulumi:refuse-destructive-plan`.
  If the plan contains any `delete`, `replace`, `create-replacement`, or
  `delete-replaced` step, the job refuses to apply (deleting a Sentry project
  destroys its data), unless the change was approved.
  To delete or replace a resource on purpose, approve it in a **commit message**
  in the PR, one line per resource, using the exact URN the refusal prints:

  ```text
  Allow-destroy: urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-old
  ```

  The push to `main` then applies that change and nothing else destructive.
  Commit messages are used rather than the PR description because they land on
  `main` unchanged (it squashes with the commit messages) and cannot be edited
  after review. A replace needs only its one URN; a resource with children
  needs a line for each. The 6-hourly schedule and manual runs never honour an
  approval, so if the push run fails for another reason, re-run that same run.
- **Route**: joins the Headscale mesh (`tag:ci`) via
  [`.github/actions/homelab-tunnel-setup`](../../../../.github/actions/homelab-tunnel-setup/action.yml)
  and forwards `sentry.lab.ipv1337.dev:443` through Envoy Gateway's
  `https-sentry` NodePort (`:31103`).

For local debugging on the tailnet, export `SENTRY_TOKEN` from Bitwarden
(`sentry.lab.ipv1337.dev`, hidden field `SENTRY_TOKEN`) and run preview:

```bash
# Fetch SENTRY_TOKEN from Bitwarden (after `bazel run //tools/sync-env-secrets:unlock`)
export SENTRY_TOKEN="$(python3 -c 'import json, os, subprocess; s=open(os.path.expanduser("~/.cache/vitruvian-core/bw-session")).read().strip(); i=json.loads(subprocess.check_output(["bw","get","item","c9ff5391-5ce8-49a3-876d-b50000633e13","--nointeraction","--session",s], text=True)); print(next(f["value"] for f in i["fields"] if f["name"]=="SENTRY_TOKEN"))')"

# Preview changes
bazel run //infrastructure/pulumi/platform/sentry:preview -- --stack production
```

## Architecture & Authentication

- **Provider**: Uses [`pulumi-sentry`](https://github.com/pulumiverse/pulumi-sentry) (`v0.0.9`). Pass `GITHUB_TOKEN=$(gh auth token)` if GitHub rate-limits plugin downloads.
- **Authentication**: Requires `SENTRY_TOKEN` (stored in Bitwarden item `sentry.lab.ipv1337.dev`, hidden field `SENTRY_TOKEN`).
- **Issue Alerts**: `sentry:enableIssueAlerts` defaults to `false` because `pulumi-sentry@v0.0.9` posts to `/rules/`, which returns `404` on newer self-hosted Sentry APIs.

## DSN Routing Invariants

Every project exports both an internal and public ingest DSN:

1. **Internal Cluster / Tailnet (`sentry.lab.ipv1337.dev`)** — `<slug>_dsn_public`
   - Used by in-cluster workloads inside the homelab k3s cluster (e.g., Backstage backend, `vitruvian-slack-mcp` pod).
2. **Public / Browser / Mobile / Cloud Run (`sentry-ingest.ipv1337.dev`)** — `<slug>_dsn_browser`
   - Routed via Cloudflare Tunnel directly to Sentry Relay ingest without exposing the Sentry Web UI or admin API. Used by browser frontends, Cloud Run services, desktop apps, mobile apps, CLIs, and Atrium extensions.

## Onboarded Applications

| Ecosystem | Application | Project Slug | Platform | Route |
|---|---|---|---|---|
| **Web** | Backstage | `backstage` | `node-express` | Internal (`sentry.lab.ipv1337.dev/2`) + Browser rewrite |
| **Web** | God's Eye View | `gods-eye-view` | `node` | Browser (`sentry-ingest.ipv1337.dev/1`) |
| **Web** | Mini Party | `mini-party` | `javascript-react` | Browser (`sentry-ingest.ipv1337.dev/21`, GitHub Pages client) |
| **Web** | Mini Party Rooms | `mini-party-rooms` | `node` | Internal (`sentry.lab.ipv1337.dev/22`, homelab rooms server) |
| **Web** | OAuth User Inspector | `oauth-user-inspector` | `rust` | Browser / Cloud Run (`sentry-ingest.ipv1337.dev/7`) |
| **Web** | VitruvianSoftware.dev | `vitruviansoftware-dev` | `javascript` | Browser (`sentry-ingest.ipv1337.dev/6`) |
| **Suites** | Vitruvian Relay | `vitruvian-relay` | `rust` | Browser / Container (`sentry-ingest.ipv1337.dev/5`) |
| **Suites** | Vitruvian Tabs | `vitruvian-tabs` | `javascript-nextjs` | Browser / Cloud Run (`sentry-ingest.ipv1337.dev/11`) |
| **Suites** | Vitruvian Wand | `vitruvian-wand` | `rust` | Browser / Desktop & Android (`sentry-ingest.ipv1337.dev/9`) |
| **MCP** | Vitruvian Slack MCP | `vitruvian-slack-mcp` | `rust` | Internal (`sentry.lab.ipv1337.dev/15`) |
| **MCP** | Vitruvian Roborock MCP | `vitruvian-roborock-mcp` | `rust` | Browser (`sentry-ingest.ipv1337.dev/14`) |
| **Desktop** | Vitruvian Code | `vitruvian-code` | `apple-macos` | Browser (`sentry-ingest.ipv1337.dev/8`) |
| **Desktop** | Vitruvian Atrium | `vitruvian-atrium` | `apple-macos` | Browser (`sentry-ingest.ipv1337.dev/12`) |
| **Desktop** | Vitruvian Speaker | `vitruvian-speaker` | `apple-macos` | Browser (`sentry-ingest.ipv1337.dev/10`) |
| **Desktop** | Vitruvian Courier | `vitruvian-courier` | `go` | Browser (`sentry-ingest.ipv1337.dev/13`) |
| **Mobile** | Vitruvian Remote | `vitruvian-remote` | `android` | Browser (`sentry-ingest.ipv1337.dev/4`) |
| **Mobile** | Vitruvian Watch | `vitruvian-watch` | `android` | Browser (`sentry-ingest.ipv1337.dev/3`) |
| **CLI** | Vitruvian DevX | `vitruvian-devx` | `go` | Browser (`sentry-ingest.ipv1337.dev/18`) |
| **CLI** | Vitruvian Homelab | `vitruvian-homelab` | `rust` | Browser (`sentry-ingest.ipv1337.dev/17`) |
| **CLI** | Ostation | `ostation` | `rust` | Browser (`sentry-ingest.ipv1337.dev/16`) |
| **Extension** | Vitruvian GitHub | `vitruvian-github` | `apple-macos` | Browser (`sentry-ingest.ipv1337.dev/19`) |
| **Extension** | Vitruvian TV | `vitruvian-tv` | `rust` | Browser (`sentry-ingest.ipv1337.dev/20`) |

### Fail-Open Invariants for CLIs & Extensions

All CLI tools and Atrium extensions are instrumented to **fail open**:
- If Sentry is unreachable, misconfigured, or experiencing an outage, these clients **never block, panic, or alter program exit codes**.
- Client initialization silently ignores connection or configuration errors.
- Transports and flushes enforce strict timeouts or execute asynchronously (fire-and-forget), preventing latency during user execution or host extension cycles.

| Application | Ecosystem | Project ID | Client / Transport | Fallback DSN | Fail-Open Behavior |
|---|---|---|---|---|---|
| `vitruvian-devx` | CLI | `18` | Go (`sentry-go`) | `https://f5f0bc21a4b8f3f1c63fb5f684e070ca@sentry-ingest.ipv1337.dev/18` | `1s` HTTP timeout, `500ms` flush timeout |
| `vitruvian-homelab` | CLI | `17` | Rust (`sentry` crate, `ureq`) | `https://d28a9615550bccaa0c33eabe4c3f44ed@sentry-ingest.ipv1337.dev/17` | `500ms` shutdown timeout |
| `ostation` | CLI | `16` | Rust (`sentry` crate, `ureq`) | `https://3bacdd14dd3bb4d326948b35048dfdb6@sentry-ingest.ipv1337.dev/16` | `500ms` shutdown timeout |
| `vitruvian-github` | Atrium Extension | `19` | Swift (`SentryLite`) | `https://466d926919488c1b0dde293066f2cd09@sentry-ingest.ipv1337.dev/19` | Fire-and-forget async |
| `vitruvian-tv` | Atrium Extension | `20` | Rust (`sentry` crate, `ureq`) | `https://828935861c1450efdb3b653f342d6bcf@sentry-ingest.ipv1337.dev/20` | `250ms` shutdown timeout |

## Verifying Events

1. Open `https://sentry.lab.ipv1337.dev/` (on LAN/Tailscale) and select **Projects** → `<slug>` → **Issues**.
2. To smoke-test ingestion directly (note Cloudflare requires a non-generic `User-Agent`, e.g. `sentry.rust/0.35.0`):

```bash
curl -s -X POST "https://sentry-ingest.ipv1337.dev/api/<project_id>/store/" \
  -H "Content-Type: application/json" \
  -H "User-Agent: sentry.rust/0.35.0" \
  -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=<public_key>, sentry_client=sentry.rust/0.35.0" \
  -d '{"message":"Sentry ingest smoke test","level":"info","platform":"other"}'
```
