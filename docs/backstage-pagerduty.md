# PagerDuty in Backstage

Catalog entities that map to a PagerDuty service show a **PagerDuty** card on
their Overview tab: open incidents, recent changes, and who is on call. It uses
PagerDuty's official plugin
([`@pagerduty/backstage-plugin`](https://pagerduty.github.io/backstage-plugin-docs/)
0.21.1 and `@pagerduty/backstage-plugin-backend` 0.14.0).

## How it is wired

```
browser ──▶ Backstage backend (/api/pagerduty) ──▶ api.pagerduty.com
                     (Token: PAGERDUTY_TOKEN, read-only)
```

- **Read-only, twice over.** The backend uses the read-only REST API key in the
  `backstage-pagerduty` Secret (`pagerDuty.apiToken`), and the card renders
  with `readOnly`, which hides its "create incident" button. Backstage cannot
  change the PagerDuty account.
- **The key** is sealed with `bazel run //tools/gitops:seal-pagerduty-readonly`
  (key on stdin), the same tool that seals the copy pagerduty-exporter reads.
  The Secret is mounted `optional: true`, so a missing key degrades the card
  instead of blocking Backstage's startup.
- **One `backend-defaults`.** The backend plugin asks for
  `@backstage/backend-defaults ^0.17.2`; a pnpm override in `package.json` and
  `pnpm-workspace.yaml` runs it on the backend's own 0.18.x. The Backstage boot
  smoke (`tools/ci/src/backstage_boot_smoke`) boots it with a PagerDuty config.

## Which entities show it

An entity gets the card when it carries `pagerduty.com/service-id`:

| Entity | PagerDuty service |
|---|---|
| System `platform-runtime` | Homelab cluster (`P8P1TII`) |
| System `observability-platform` | Homelab cluster (`P8P1TII`) |
| Resource `cloudnative-pg` | Homelab databases and backups (`P4CDT6V`) |
| System `vitruvian-slack-mcp` | Homelab apps and GitOps (`P13SSU5`) |
| System `vitruvian-core` | CI / delivery (`PE5K2S9`) |

The Sentry PagerDuty service has no catalog entity yet. Service ids come from
the PagerDuty stack (`infrastructure/pulumi/platform/pagerduty`, outputs
`<key>ServiceId`), or `bazel run //tools/pagerduty:read -- /services`.

## Not used

- **Scoped OAuth.** The plugin prefers a PagerDuty OAuth app; the docs do not
  say it works on the free plan, so this uses a read-only REST key instead.
- **The entity processor** (`@pagerduty/backstage-plugin-entity-processor`)
  syncs service dependencies and creates integrations; with a read-only key it
  could not write anyway. Service dependencies live in the PagerDuty Pulumi
  stack.
