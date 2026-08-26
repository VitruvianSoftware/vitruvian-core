# Traefik to Envoy Gateway Migration & Decommission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fully migrate all remaining internal workloads from Traefik to Envoy Gateway (Gateway API), configure HTTPS and DNS, and decommission Traefik from the homelab k3s cluster.

**Architecture:** Add an HTTPS listener on port 443 to the `platform` Gateway with a Let's Encrypt DNS-01 wildcard certificate (`*.lab.ipv1337.dev`). Deploy Gateway API `HTTPRoute` resources and declarative `DNSEndpoint` records for `argocd`, `grafana`, `pushgateway`, and `otel`. Remove legacy `Ingress` resources, clean up Prometheus scrape targets, remove Traefik dashboards, and decommission the Traefik controller in k3s.

**Tech Stack:** Kubernetes Gateway API (`gateway.networking.k8s.io/v1`), Envoy Gateway (`gateway.envoyproxy.io/v1alpha1`), cert-manager (`cert-manager.io/v1`), external-dns (`externaldns.k8s.io/v1alpha1`), ArgoCD, Prometheus, Grafana, k3s.

## Global Constraints

- Domain convention: Public/tunnel apps use `*.ipv1337.dev`; tailscale-internal apps use `*.lab.ipv1337.dev`.
- Envoy Gateway LoadBalancer IP: `10.44.86.211` (Cilium LB-IPAM).
- All GitOps resources managed via `gitops/argocd/platform/`.
- No disruption to existing Gateway API workloads (`zitadel`, `whoami`, `storybook`, `ntfy`, `buzz`).

---

### Task 1: Enable HTTPS on Gateway & Provision Lab Wildcard Certificate

**Files:**
- Create: `gitops/argocd/platform/envoy-gateway/gateway/lab-wildcard-certificate.yaml`
- Modify: `gitops/argocd/platform/envoy-gateway/gateway/gateway.yaml`

**Interfaces:**
- Consumes: `ClusterIssuer: letsencrypt-cloudflare` in cert-manager
- Produces: Secret `lab-wildcard-tls` in namespace `envoy-gateway-system` and HTTPS :443 listener on Gateway `platform`

- [ ] **Step 1: Create the wildcard Certificate manifest**

Create `gitops/argocd/platform/envoy-gateway/gateway/lab-wildcard-certificate.yaml`:
```yaml
# Copyright (c) 2026 VitruvianSoftware
# Wildcard certificate for internal *.lab.ipv1337.dev services terminating on Envoy Gateway.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lab-wildcard-tls
  namespace: envoy-gateway-system
spec:
  secretName: lab-wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
    - "*.lab.ipv1337.dev"
    - "lab.ipv1337.dev"
```

- [ ] **Step 2: Update Gateway `platform` with HTTPS :443 listener**

Update `gitops/argocd/platform/envoy-gateway/gateway/gateway.yaml`:
```yaml
# Copyright (c) 2026 VitruvianSoftware
#
# Gateway `platform` — the shared cluster Gateway.
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: platform
  namespace: envoy-gateway-system
spec:
  gatewayClassName: envoy
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - group: ""
            kind: Secret
            name: lab-wildcard-tls
      allowedRoutes:
        namespaces:
          from: All
```

- [ ] **Step 3: Validate and apply manifests**

Run:
```bash
KUBECONFIG=~/.kube/cluster.yaml kubectl apply -f gitops/argocd/platform/envoy-gateway/gateway/lab-wildcard-certificate.yaml
KUBECONFIG=~/.kube/cluster.yaml kubectl apply -f gitops/argocd/platform/envoy-gateway/gateway/gateway.yaml
```

- [ ] **Step 4: Verify certificate readiness and gateway status**

Run:
```bash
KUBECONFIG=~/.kube/cluster.yaml kubectl get certificate lab-wildcard-tls -n envoy-gateway-system
KUBECONFIG=~/.kube/cluster.yaml kubectl get gateway platform -n envoy-gateway-system -o yaml
```
Expected: `READY=True` for certificate `lab-wildcard-tls` and `Programmed=True` for `https` listener on Gateway `platform`.

- [ ] **Step 5: Commit changes**

```bash
git add gitops/argocd/platform/envoy-gateway/gateway/
git commit -m "feat(gateway): add https port 443 listener and wildcard tls certificate"
```

---

### Task 2: Create Declarative DNSEndpoints for Internal Services

**Files:**
- Create: `gitops/argocd/platform/platform-config/lab-internal-dnsendpoints.yaml`

**Interfaces:**
- Consumes: Envoy Gateway LoadBalancer IP `10.44.86.211`
- Produces: `DNSEndpoint` CR in namespace `external-dns` synced to Cloudflare DNS

- [ ] **Step 1: Create the internal DNSEndpoint manifest**

Create `gitops/argocd/platform/platform-config/lab-internal-dnsendpoints.yaml`:
```yaml
# Copyright (c) 2026 VitruvianSoftware
# Internal .lab.ipv1337.dev DNS endpoints pointing to Envoy Gateway LB IP (10.44.86.211).
apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: lab-internal-services
  namespace: external-dns
  annotations:
    external-dns.alpha.kubernetes.io/sync-enabled: "true"
spec:
  endpoints:
    - dnsName: argocd.lab.ipv1337.dev
      recordType: A
      recordTTL: 60
      targets:
        - 10.44.86.211
    - dnsName: grafana.lab.ipv1337.dev
      recordType: A
      recordTTL: 60
      targets:
        - 10.44.86.211
    - dnsName: pushgateway.lab.ipv1337.dev
      recordType: A
      recordTTL: 60
      targets:
        - 10.44.86.211
    - dnsName: otel.lab.ipv1337.dev
      recordType: A
      recordTTL: 60
      targets:
        - 10.44.86.211
```

- [ ] **Step 2: Apply and verify external-dns sync**

Run:
```bash
KUBECONFIG=~/.kube/cluster.yaml kubectl apply -f gitops/argocd/platform/platform-config/lab-internal-dnsendpoints.yaml
KUBECONFIG=~/.kube/cluster.yaml kubectl get dnsendpoint lab-internal-services -n external-dns
```
Expected: `DNSEndpoint` accepted by external-dns.

- [ ] **Step 3: Commit changes**

```bash
git add gitops/argocd/platform/platform-config/lab-internal-dnsendpoints.yaml
git commit -m "feat(dns): add declarative DNSEndpoint records for internal lab services"
```

---

### Task 3: Migrate Ingress Workloads to HTTPRoutes

**Files:**
- Create: `gitops/argocd/platform/platform-config/lab-internal-httproutes.yaml`
- Modify: `gitops/argocd/platform/grafana/applicationset.yaml`
- Modify: `gitops/argocd/platform/opentelemetry-collector/applicationset.yaml`
- Modify: `gitops/argocd/platform/prometheus/applicationset.yaml`

**Interfaces:**
- Consumes: Services `argocd-server.argocd`, `grafana.grafana`, `prometheus-prometheus-pushgateway.monitoring`, `opentelemetry-collector.opentelemetry`
- Produces: `HTTPRoute` resources attached to `Gateway: platform`

- [ ] **Step 1: Create HTTPRoutes for all 4 services**

Create `gitops/argocd/platform/platform-config/lab-internal-httproutes.yaml`:
```yaml
# Copyright (c) 2026 VitruvianSoftware
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-server
  namespace: argocd
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: platform
      namespace: envoy-gateway-system
  hostnames:
    - argocd.lab.ipv1337.dev
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: argocd-server
          port: 80
          weight: 1
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: grafana
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: platform
      namespace: envoy-gateway-system
  hostnames:
    - grafana.lab.ipv1337.dev
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: grafana
          port: 80
          weight: 1
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: prometheus-pushgateway
  namespace: monitoring
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: platform
      namespace: envoy-gateway-system
  hostnames:
    - pushgateway.lab.ipv1337.dev
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: prometheus-prometheus-pushgateway
          port: 9091
          weight: 1
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: opentelemetry-collector
  namespace: opentelemetry
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: platform
      namespace: envoy-gateway-system
  hostnames:
    - otel.lab.ipv1337.dev
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: opentelemetry-collector
          port: 4318
          weight: 1
```

- [ ] **Step 2: Disable legacy Ingress in Grafana, OpenTelemetry Collector, and Prometheus**

- In `gitops/argocd/platform/grafana/applicationset.yaml`: change `ingress.enabled: true` to `ingress.enabled: false`.
- In `gitops/argocd/platform/opentelemetry-collector/applicationset.yaml`: change `ingress.enabled: true` to `ingress.enabled: false`.
- In `gitops/argocd/platform/prometheus/applicationset.yaml`: change `prometheus-pushgateway.ingress.enabled: true` to `prometheus-pushgateway.ingress.enabled: false`.

- [ ] **Step 3: Apply HTTPRoutes and delete legacy Ingresses**

Run:
```bash
KUBECONFIG=~/.kube/cluster.yaml kubectl apply -f gitops/argocd/platform/platform-config/lab-internal-httproutes.yaml
KUBECONFIG=~/.kube/cluster.yaml kubectl delete ingress argocd-server -n argocd --ignore-not-found
KUBECONFIG=~/.kube/cluster.yaml kubectl delete ingress grafana -n grafana --ignore-not-found
KUBECONFIG=~/.kube/cluster.yaml kubectl delete ingress prometheus-prometheus-pushgateway -n monitoring --ignore-not-found
KUBECONFIG=~/.kube/cluster.yaml kubectl delete ingress opentelemetry-collector -n opentelemetry --ignore-not-found
```

- [ ] **Step 4: Verify HTTPRoutes are Programmed and services respond**

Run:
```bash
KUBECONFIG=~/.kube/cluster.yaml kubectl get httproutes -A
curl -k -I https://10.44.86.211 -H "Host: argocd.lab.ipv1337.dev"
curl -k -I https://10.44.86.211 -H "Host: grafana.lab.ipv1337.dev"
curl -k -I https://10.44.86.211 -H "Host: pushgateway.lab.ipv1337.dev"
curl -k -I https://10.44.86.211 -H "Host: otel.lab.ipv1337.dev"
```
Expected: `HTTP/2 200` or `HTTP/2 302` responses from Envoy Gateway.

- [ ] **Step 5: Commit changes**

```bash
git add gitops/argocd/platform/platform-config/lab-internal-httproutes.yaml \
        gitops/argocd/platform/grafana/applicationset.yaml \
        gitops/argocd/platform/opentelemetry-collector/applicationset.yaml \
        gitops/argocd/platform/prometheus/applicationset.yaml
git commit -m "feat(ingress): migrate internal services from Ingress to Gateway API HTTPRoutes"
```

---

### Task 4: Clean Up Observability (Prometheus & Grafana Dashboards)

**Files:**
- Modify: `gitops/argocd/platform/prometheus/applicationset.yaml`
- Modify: `gitops/argocd/platform/grafana-dashboards/kustomization.yaml`
- Delete: `gitops/argocd/platform/grafana-dashboards/traefik.json`

**Interfaces:**
- Removes stale Traefik scrape target and dashboard from monitoring

- [ ] **Step 1: Remove Traefik scrape job from Prometheus**

In `gitops/argocd/platform/prometheus/applicationset.yaml`, remove the `job_name: 'traefik'` block (lines 924-930):
```yaml
              - job_name: 'traefik'
                kubernetes_sd_configs:
                  - role: endpoints
                relabel_configs:
                - source_labels: [__meta_kubernetes_service_name]
                  regex: 'traefik'
                  action: keep
```

- [ ] **Step 2: Remove Traefik dashboard from Grafana ConfigMaps**

In `gitops/argocd/platform/grafana-dashboards/kustomization.yaml`, remove:
```yaml
  - name: grafana-dashboard-traefik
    files:
      - traefik.json
```
Delete file: `gitops/argocd/platform/grafana-dashboards/traefik.json`.

- [ ] **Step 3: Apply and verify Prometheus alerts clear**

Run:
```bash
KUBECONFIG=~/.kube/cluster.yaml kubectl delete configmap grafana-dashboard-traefik -n grafana --ignore-not-found
```

- [ ] **Step 4: Commit changes**

```bash
git add gitops/argocd/platform/prometheus/applicationset.yaml \
        gitops/argocd/platform/grafana-dashboards/
git rm -f gitops/argocd/platform/grafana-dashboards/traefik.json
git commit -m "refactor(observability): remove traefik scrape job and dashboard"
```

---

### Task 5: Decommission Traefik Controller in k3s

**Files:**
- Delete: `gitops/argocd/platform/platform-config/traefik-ha-config.yaml`

**Cluster actions:**
- Remove Traefik Helm chart from k3s and delete remaining resources.

- [ ] **Step 1: Remove `traefik-ha-config.yaml` from GitOps**

Run:
```bash
git rm -f gitops/argocd/platform/platform-config/traefik-ha-config.yaml
git commit -m "refactor(platform): remove traefik-ha-config HelmChartConfig"
```

- [ ] **Step 2: Remove Traefik resources from cluster**

Run:
```bash
KUBECONFIG=~/.kube/cluster.yaml kubectl delete helmchart traefik -n kube-system --ignore-not-found
KUBECONFIG=~/.kube/cluster.yaml kubectl delete helmchartconfig traefik -n kube-system --ignore-not-found
KUBECONFIG=~/.kube/cluster.yaml kubectl delete deployment traefik -n kube-system --ignore-not-found
KUBECONFIG=~/.kube/cluster.yaml kubectl delete service traefik -n kube-system --ignore-not-found
```

- [ ] **Step 3: Verification**

Run:
```bash
KUBECONFIG=~/.kube/cluster.yaml kubectl get pods,svc -n kube-system -l app.kubernetes.io/name=traefik
KUBECONFIG=~/.kube/cluster.yaml kubectl get httproutes,gateway -A
```
Expected: No Traefik resources found in `kube-system`. All Gateway API resources healthy and reachable.
