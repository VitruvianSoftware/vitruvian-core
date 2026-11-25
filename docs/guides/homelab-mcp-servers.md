# Read-only MCP servers for the homelab

AI assistants (Claude Code, Claude Desktop) can look at the homelab through MCP
servers. Every one of them is **read-only**, and each is held read-only twice:
the server's own setting removes the write tools, and the credential it uses
cannot write even if a tool slipped through.

| What you want to see | MCP server | Read-only because |
|---|---|---|
| Dashboards, metrics, logs, traces | Grafana (`mcp-grafana --disable-write`) | Service account `mcp` has the **Viewer** role |
| Pods, deployments, events, logs | Kubernetes (`mcp-server-kubernetes`, `ALLOW_ONLY_READONLY_TOOLS=true`) | Only 8 read tools are exposed; no apply, patch, scale, delete or exec |
| **Argo CD apps: sync and health** | **Kubernetes** (see below) | Same as above |
| Errors, issues, traces | Sentry (`@sentry/mcp-server`, `SENTRY_HOST=sentry.lab.ipv1337.dev`, skills `inspect,docs`) | No issue-update or project-management tools |
| zitadel-db, backstage-db, grafana-db | Postgres MCP Pro (`--access-mode=restricted`), one per database | Login `mcp_readonly` (member of `pg_read_all_data`), through the `-ro` service, so a standby that refuses writes |
| Users, projects, apps in Zitadel | `@warnyin/zitadel-mcp` | Machine user `mcp-viewer` holds only `ORG_OWNER_VIEWER`; Zitadel answers 403 to every write. The server still *lists* write tools: they fail |
| Bucket and file names in MinIO | `mcp-server-aistor`, in-cluster at `https://minio-mcp.lab.ipv1337.dev/mcp` | Login `mcp-readonly` can list buckets and keys but cannot read an object (the buckets hold database backups) |

## Argo CD goes through the Kubernetes MCP

There is no Argo CD MCP server. Argo CD keeps its state in Kubernetes objects,
so the read-only Kubernetes MCP already sees it:

- `kubectl_get applications.argoproj.io -n argocd` lists every app;
  `kubectl_describe applications.argoproj.io <name> -n argocd` shows its sync
  status, health, last sync result and resource list.
- `appprojects.argoproj.io` and `applicationsets.argoproj.io` work the same way.

Why not a dedicated server: it needs an Argo CD API token, and minting one
needs either the admin login or a job that can read `argocd-secret` (the key
that signs every Argo CD token). Reading the same state through Kubernetes needs
neither. The local account `mcp` still exists in the dev-local stack, bound to
`role:readonly`, but nothing uses it.

## Where the pieces live

- **Server definitions (Mac):** `~/.claude.json` (Claude Code) and
  `~/Library/Application Support/Claude/claude_desktop_config.json` (Claude
  Desktop). Local servers start from small launch scripts in
  `~/.local/bin/homelab-mcp/`. The scripts read secrets from the macOS
  keychain (service `homelab-mcp`) and open a `kubectl port-forward` where a
  database has no ingress. Every secret also has a Bitwarden item named
  `Homelab MCP — …`.
- **Postgres logins:** `cluster.roles` in each `*-db` ApplicationSet, passwords
  in `sealed-secrets-manifests/<db>-db-mcp-readonly.sealedsecret.yaml`.
- **MinIO login and server:** policy and user `mcp-readonly` in
  `gitops/argocd/platform/minio-amd64`; the server in
  `gitops/argocd/platform/minio-mcp`. It is LAN/tailnet only and has no login
  of its own, so the tailnet is its only boundary.
- **Zitadel identity:** the `zitadel-mcp-viewer` Pulumi stack
  (`infrastructure/pulumi/platform/zitadel-mcp-viewer`). Its token expires on
  the date in `Pulumi.development.yaml`; move the date to rotate it.
- **Grafana account:** service account `mcp` (Viewer), created through the
  Grafana API like the Backstage one (`docs/backstage-grafana.md`).
