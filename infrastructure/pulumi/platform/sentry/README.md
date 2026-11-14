# Pulumi Platform: Sentry

First-party self-hosted Sentry infrastructure as code: manages teams, projects, client keys (DSNs), and optional issue alerts against our homelab Sentry instance (`https://sentry.lab.ipv1337.dev/api/`).

## Stacks

- **`production`**: The production self-hosted Sentry stack (`Pulumi.production.yaml`, gitignored under `infrastructure/pulumi/`).

## Commands

Run via the standard Bazel targets:

```bash
# Fetch SENTRY_TOKEN from Bitwarden (after `bazel run //tools/sync-env-secrets:unlock`)
export SENTRY_TOKEN="$(python3 -c 'import json, os, subprocess; s=open(os.path.expanduser("~/.cache/vitruvian-core/bw-session")).read().strip(); i=json.loads(subprocess.check_output(["bw","get","item","c9ff5391-5ce8-49a3-876d-b50000633e13","--nointeraction","--session",s], text=True)); print(next(f["value"] for f in i["fields"] if f["name"]=="SENTRY_TOKEN"))')"

# Preview changes
bazel run //infrastructure/pulumi/platform/sentry:preview -- --stack production

# Apply changes (from main)
bazel run //infrastructure/pulumi/platform/sentry:up -- --stack production --yes
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
   - Routed via Cloudflare Tunnel directly to Sentry Relay ingest without exposing the Sentry Web UI or admin API. Used by browser frontends, Cloud Run services, desktop apps, and mobile apps.

## Onboarded Applications

| Ecosystem | Application | Project Slug | Platform | Route |
|---|---|---|---|---|
| **Web** | Backstage | `backstage` | `node-express` | Internal (`sentry.lab.ipv1337.dev/2`) + Browser rewrite |
| **Web** | God's Eye View | `gods-eye-view` | `node` | Browser (`sentry-ingest.ipv1337.dev/1`) |
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
