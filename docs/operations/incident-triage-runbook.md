# Standard Incident Triage & Operational Runbook

This document serves as the standard operational incident response guide across all Vitruvian platform services and applications.

## Incident Severity Levels

| Severity | Definition | Response Target | Channels |
| :--- | :--- | :--- | :--- |
| **SEV-1 (Critical)** | Core outage affecting public production traffic (e.g. Backstage, Tabula, Zitadel SSO down). | < 15 mins | `#incidents-critical`, ntfy priority 5 |
| **SEV-2 (Major)** | Degraded service performance, partial feature disruption, or failed deployment rollouts. | < 30 mins | `#incidents`, ntfy priority 4 |
| **SEV-3 (Minor)** | Non-blocking bug, CI/CD pipeline slowdown, or non-production environment failure. | < 2 hours | `#alerts` |

---

## Service Quick Reference

| Service | Namespace | Deployment Type | Rollback Command |
| :--- | :--- | :--- | :--- |
| **backstage** | `backstage` | Kubernetes (ArgoCD) | `argocd app rollback backstage` |
| **tabula** | N/A | Cloud Run | `gcloud run services rollback tabula` |
| **oauth-user-inspector**| N/A | Cloud Run | `gcloud run services rollback oauth-user-inspector` |
| **buzz** | `buzz` | Kubernetes (Helm) | `helm rollback buzz -n buzz` |
| **mcp-slack** | `mcp-slack` | Kubernetes (Deployment) | `kubectl rollout undo deployment mcp-slack -n mcp-slack` |
| **whoami** | `whoami` | Kubernetes (Argo Rollouts) | `kubectl argo rollouts undo whoami -n whoami` |
| **storybook** | `storybook` | Kubernetes (Deployment) | `kubectl rollout undo deployment storybook -n storybook` |

---

## Common Failure Modes & Troubleshooting

### Buzz DB Pool Exhaustion
**Symptoms**: The `buzz` application reports connection timeouts or errors communicating with the database.
**Context**: Buzz runs 3 replicas with topology spread. It uses a CloudNativePG (CNPG) cluster with `max_connections=100`. If each pod has a connection pool size of e.g. 40, 3 pods x 40 > 100, which will exhaust the DB pool.
**Resolution**:
1. Check the `BUZZ_DB_POOL_SIZE` environment variable in the deployment config.
2. Ensure `(BUZZ_DB_POOL_SIZE * replicas) < CNPG max_connections (100)`.
3. A safe value is `BUZZ_DB_POOL_SIZE=20` (20 * 3 = 60, which is < 100).
4. Update the configuration and restart the deployment: `kubectl rollout restart deployment buzz -n buzz`.

### CNPG Cluster Failover
**Symptoms**: Database instances are unresponsive, or failover alerts trigger.
**Context**: CloudNativePG handles failovers automatically, but sometimes manual intervention is needed if nodes are unrecoverable.
**Resolution**:
1. Check CNPG cluster status: `kubectl get cluster -n <namespace>` and `kubectl cnpg status <cluster-name> -n <namespace>`.
2. Review the logs of the primary and replica pods.
3. If necessary, promote a specific replica manually: `kubectl cnpg promote <cluster-name> <pod-name> -n <namespace>`.
4. Ensure PVCs are healthy and node storage is not full.

### Argo Rollouts Canary Failures (`whoami`)
**Symptoms**: The canary deployment is stuck in a paused state or failing its AnalysisRuns.
**Context**: `whoami` uses Argo Rollouts with an AnalysisTemplate to verify canary health before proceeding.
**Resolution**:
1. Check rollout status: `kubectl argo rollouts get rollout whoami -n whoami`.
2. Inspect the AnalysisRun to see which metrics failed.
3. If the failure is expected or a false positive, you can promote: `kubectl argo rollouts promote whoami -n whoami`.
4. If it's a real regression, abort and rollback: `kubectl argo rollouts abort whoami -n whoami` followed by `kubectl argo rollouts undo whoami -n whoami`.

### Cloud Run Deployment Failures (`tabula`)
**Symptoms**: New versions of `tabula` fail to start or serve traffic on Cloud Run.
**Context**: `tabula` uses a blue-green deployment model on Cloud Run across dev/nonprod/prod environments, integrated with Zitadel SSO.
**Resolution**:
1. Check Cloud Run logs in the GCP Console.
2. Verify that the service account has the necessary permissions.
3. Check if Zitadel SSO configurations (client IDs, secrets) are valid for the environment.
4. If the new revision is broken, rollback traffic immediately: `gcloud run services update-traffic tabula --to-revisions=<stable-revision>=100`.

### Sealed Secrets Rotation
**Symptoms**: Pods fail to start due to missing or invalid secrets.
**Context**: Secrets like `mcp-slack` tokens are managed via SealedSecrets. If the cluster's sealing key is rotated or lost, old SealedSecrets cannot be decrypted.
**Resolution**:
1. Check the SealedSecret status: `kubectl get sealedsecret <secret-name> -n <namespace> -o yaml`.
2. If decryption fails, you must re-encrypt the secret using the current public certificate (`kubeseal --cert pub-cert.pem`).
3. Apply the new SealedSecret and restart the affected workloads.

### Cloudflare Tunnel Connectivity
**Symptoms**: External traffic to applications like `backstage` or `grafana` fails with Cloudflare errors (e.g., 502 Bad Gateway).
**Context**: Edge ingress is handled by `cloudflared` tunnels.
**Resolution**:
1. Check `cloudflared` pod logs in the cluster to verify connectivity to Cloudflare's edge.
2. Restart the tunnel pods if they are stuck: `kubectl rollout restart deployment cloudflared -n <namespace>`.
3. Verify DNS routes in the Cloudflare Dashboard.

### Cert-Manager Certificate Renewal Failures
**Symptoms**: TLS certificates expire, causing browser warnings or API failures.
**Context**: Cert-Manager handles TLS certificates for Envoy Gateway HTTPRoutes and other ingress objects.
**Resolution**:
1. Check Certificate objects: `kubectl get certificates -A`.
2. Describe failing certificates to see events: `kubectl describe certificate <name> -n <namespace>`.
3. Check the ClusterIssuer/Issuer status and Cert-Manager pod logs.
4. Verify DNS/HTTP01 challenge resources are created correctly.

---

## Emergency Escalation & Links

- **Grafana Alerts**: `https://grafana.lab.ipv1337.dev/alerting/list`
- **ArgoCD Operations**: `https://argocd.lab.ipv1337.dev`
- **ntfy Push Notifications**: `https://ntfy.ipv1337.dev`
- **Zitadel SSO Status**: `https://auth.ipv1337.dev`
- **Uptime Kuma Status Page**: `https://status.ipv1337.dev`
- **K3s HA API**: `https://k8s-api.lab.ipv1337.dev:6443`

---

## Post-Incident Process

Every SEV-1 and SEV-2 incident must be followed by a blameless post-mortem within 48 hours of resolution.

1. **Blameless Review**: Focus on systemic failures and process improvements, not human error. "Why did the system allow this to happen?"
2. **Timeline**: Document the exact sequence of events:
   - Time of first impact
   - Time of detection (and how it was detected)
   - Time of mitigation actions
   - Time of full resolution
3. **Action Items**: Create tracked tasks to prevent recurrence, improve detection time, or speed up mitigation.
