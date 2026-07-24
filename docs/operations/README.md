# Operations

Runbooks and incident records for operating the apps and the platform. Orientation:
[Operator quick start](../getting-started/operator.md).

## Runbooks

| Runbook | When |
|---|---|
| [Break-glass deploy](break-glass-deploy-runbook.md) | Deploy apps or foundation stages from a workstation when GitHub Actions is down |
| [Sealed secrets](sealed-secrets.md) | Seal/rotate k8s platform secrets; controller-key custody (Bitwarden-backed backup/restore) |
| [Key rotation](key-rotation.md) | Rotate CI/API credentials (BuildBuddy key, Actions secrets) |
| [Foundation teardown & redeploy](foundation-teardown-redeploy-runbook.md) | Ordered teardown + fresh provision of the GCP foundation |

## Incidents

Dated postmortems live in [`incidents/`](incidents/). Write one for every SEV; carry
its action items to completion — every fix ships with the check that would catch the
regression.

- [2026-06-13 — Prometheus WAL corruption](incidents/2026-06-13-prometheus-wal-corruption.md)
- [2026-06-21 — fedora node freeze cluster cascade](incidents/2026-06-21-fedora-freeze-cluster-cascade.md)
