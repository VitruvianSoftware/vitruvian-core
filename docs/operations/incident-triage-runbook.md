# Standard Incident Triage & Operational Runbook

This document serves as the standard operational incident response guide across all Vitruvian platform services and applications.

## Incident Severity Levels

| Severity | Definition | Response Target | Channels |
| :--- | :--- | :--- | :--- |
| **SEV-1 (Critical)** | Core outage affecting public production traffic (e.g. Backstage, Tabula, Zitadel SSO down). | < 15 mins | `#incidents-critical`, ntfy priority 5 |
| **SEV-2 (Major)** | Degraded service performance, partial feature disruption, or failed deployment rollouts. | < 30 mins | `#incidents`, ntfy priority 4 |
| **SEV-3 (Minor)** | Non-blocking bug, CI/CD pipeline slowdown, or non-production environment failure. | < 2 hours | `#alerts` |

---

## 1. Initial Triage Checklist

1. **Verify Live Service Health & Uptime**:
   - Check [Uptime Kuma Status Page](https://status.ipv1337.dev) for endpoint availability.
   - Inspect [Grafana Platform Dashboards](https://grafana.lab.ipv1337.dev).
2. **Check Alertmanager Active Alerts**:
   - Query Alertmanager or [ntfy Alerts Topic](https://ntfy.ipv1337.dev/alerts).
3. **Inspect Runtime Workloads**:
   - In Backstage, open the affected Component and inspect the **Kubernetes** and **ArgoCD** tabs.
   - Or CLI: `kubectl get pods -n <namespace>` and `kubectl logs -n <namespace> -l app.kubernetes.io/name=<app> --tail=100`.
4. **Inspect Canary / Progressive Rollouts**:
   - For services using Argo Rollouts (`whoami`, `buzz`), check Canary step status and AnalysisRuns.
   - Abort or roll back if regression is detected: `kubectl argo rollouts abort <rollout> -n <namespace>`.

---

## 2. Emergency Escalation & Links

- **Grafana Alerts**: `https://grafana.lab.ipv1337.dev/alerting/list`
- **ArgoCD Operations**: `https://argocd.lab.ipv1337.dev`
- **ntfy Push Notifications**: `https://ntfy.ipv1337.dev`
- **Zitadel SSO Status**: `https://auth.ipv1337.dev`
