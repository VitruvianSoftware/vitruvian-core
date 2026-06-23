# Design: Cilium + Gateway API + Cloudflare Tunnel (GKE-shaped dev-local)

Status: **approved, in progress** · Owner: James · Started 2026-06-23

## Goal

Move dev-local to a production-shaped, GKE-like networking stack:

- **Cilium** as CNI + kube-proxy replacement + LoadBalancer IPAM (this is what GKE
  Dataplane V2 runs under the hood — eBPF, sidecar-less).
- **Gateway API** as the ingress/routing surface (this is what GKE Gateway is),
  replacing the older `Ingress` API. Ingress is frozen upstream; Gateway API is the
  successor and the native config surface for Istio ambient / Cilium.
- **Cloudflare Tunnel** for *public* exposure of selected apps (e.g. a future
  keycloak/OIDC), while everything else stays tailscale-only — with DNS still owned
  by the existing **external-dns** (single source of truth), and sensitive surfaces
  gated by **Cloudflare Access** (Zero Trust).

The guiding principle: **the CNI swap is the only cluster-betting change.** Gateway
API and the tunnel are not coupled to it (Gateway API `HTTPRoute`s are
controller-portable), so they go first and safely; Cilium is an isolated,
well-rehearsed phase.

## Current state (grounded 2026-06-23)

- **6 nodes**, k3s `v1.35.3+k3s1`. Servers: james-macbook-pro, james-mbp32, fedora
  (3 etcd voters). Agents: james-mbp16, james-mbp, nuc9.
- **CNI: Flannel** (k3s default), pinned to the tailnet via `--flannel-iface=tailscale0`
  (`devx/internal/multinode/k3s/k3s.go`). Pod CIDR `10.42.0.0/16`, svc `10.43.0.0/16`.
- **kube-proxy: on** (no `--disable-kube-proxy`).
- **LB: MetalLB** (`10.44.86.210-215`, L2), deployed *inline by devx*
  (`k3s.go: DeployMetalLB`), not GitOps. Traefik LB = `10.44.86.210`.
- **Ingress: k3s-bundled Traefik** (HA 2 replicas via `platform-config/traefik-ha-config.yaml`).
  Apps use `Ingress` + `ingressClassName: traefik`.
- **external-dns**: provider cloudflare, zone `ipv1337.dev`, sources `service`+`ingress`,
  `policy: sync`, `txtOwnerId: bluecentre-dev`, opt-in `annotationFilter:
  external-dns.alpha.kubernetes.io/sync-enabled in (true)` (so tailscale-only apps are
  untouched). Token `cf-secret` (DNS-only).
- **Tailscale exposure**: all nodes run tailscale with `--accept-routes` (subnet
  routing); external-dns publishes `ipv1337.dev` records → the MetalLB LB IP, reachable
  over the tailnet. No tailscale k8s operator — node-level only.
- **Gateway API CRDs already installed** (`gateways`, `httproutes`, `grpcroutes`,
  `referencegrants`, `backendtlspolicies`). No Gateway/HTTPRoute resources in use yet.
- **HA API endpoint exists**: `k8s-api.lab.ipv1337.dev` (DNS-failover to the 3 CP tailnet
  IPs) — this is the stable `k8sServiceHost` Cilium's kube-proxy-replacement requires.
- **Istio**: staged but disabled (`gitops/argocd/platform/istio/applicationset.yaml`,
  gated off; `istio-system` absent). Out of scope here.
- **Platform GitOps**: `root-platform.yaml` is an `Application` with
  `directory.recurse: true` over `gitops/argocd/platform/` — so new platform AppSets
  auto-sync from git. AppSet convention: `goTemplate: true` (+ clusters generator),
  `project: platform-project`, sync-wave annotations, inline helm values.
  **Gotcha**: `goTemplate: true` Go-templates the inline values, so any literal `{{ }}`
  (Prometheus/Alertmanager/Gateway) must be wrapped in a raw-string passthrough — see
  the prometheus AppSet.

## Cloudflare prerequisites (captured 2026-06-23)

- API token (`~/.config/devx/cf-tunnel-api-token`, chmod 600): scoped
  **Cloudflare Tunnel: Edit + Access: Apps and Policies: Edit**, account-only, active.
- Account ID `076e26671555a704f46050e63fd5bb03`; Zero Trust team **`ipv1337`**
  (`ipv1337.cloudflareaccess.com`, Free plan); zone `ipv1337.dev`.
- Access identity: built-in One-Time-PIN (email) — no external IdP needed.

## Target architecture

```
Internet → Cloudflare edge (WAF + Access) → cloudflared (tunnel, HA)
                                                  │
                                          (in-cluster)
                                                  ▼
                                        Gateway (Gateway API)
                                          ├─ HTTPRoute auth.ipv1337.dev → keycloak
                                          └─ HTTPRoute whoami.ipv1337.dev → whoami
Tailnet → external-dns record → MetalLB/Cilium LB IP → Gateway → HTTPRoute → app (private)
```

- **DNS authority stays external-dns.** Public hosts get a *proxied CNAME →
  `<tunnel-id>.cfargotunnel.com`* via the `target` + `cloudflare-proxied` +
  `sync-enabled` annotations on the `HTTPRoute`/`Gateway`. Private hosts keep their
  tailnet-IP records. Same controller, same zone, differentiated by annotation.
- **Naming**: public/tunnel apps under the apex (`whoami.ipv1337.dev`,
  `auth.ipv1337.dev`); tailscale-internal stays `*.lab.ipv1337.dev`.
- **cloudflared** is a thin transport with one route → the Gateway Service; all real
  routing is `HTTPRoute`s. HA: ≥2 replicas (Cloudflare load-balances connectors).

## Phased plan

### Phase 0 — Gateway API on the current stack (low risk, reversible)
1. **Envoy Gateway** as a GitOps platform app (Envoy data plane = same as Cilium
   Gateway + GKE; survives the later Cilium swap). Pin the chart; create a
   `GatewayClass: envoy` + a `Gateway` on a MetalLB LB IP.
2. external-dns: add `--source=gateway-httproute` (keep `ingress` during transition).
3. Migrate one real app `Ingress` → `HTTPRoute`; verify DNS + routing + tailscale
   reachability end-to-end.

### Phase 1 — Cloudflare Tunnel, Gateway-API-native (low–med risk)
1. Create the tunnel as code (API, with the captured token + a generated secret) →
   tunnel ID + `credentials.json`.
2. **cloudflared** GitOps platform app (HA), credentials via SealedSecret, local config
   routing the public host(s) → the Gateway Service. ClusterIP is fine (in-cluster).
3. Public apps = `HTTPRoute` + the cfargotunnel/proxied/sync-enabled annotations →
   external-dns proxied CNAMEs.
4. **whoami** throwaway test app behind the tunnel, **gated by Cloudflare Access**
   (OTP, allow james.nguyen@gmail.com) — demonstrates the full public + Access pattern
   (the shape a future keycloak `/admin` would use). Tear down after validation.

### Phase 2 — Cilium (the one cluster-betting phase)
- **devx changes**: k3s flags `--flannel-backend=none --disable-kube-proxy
  --disable-network-policy`; replace `DeployMetalLB` with Cilium install + config:
  `kubeProxyReplacement=true`, `k8sServiceHost=k8s-api.lab.ipv1337.dev`, **LB IPAM
  reusing `10.44.86.210-215` + L2 announcements** (preserves the Gateway LB IP and
  tailscale reachability), Hubble, Gateway API support, and the correct
  device/routing for the `tailscale0` topology.
- **Validation spikes first (must pass before touching the fleet):** (1) Cilium over
  `tailscale0` (node IPs are tailnet IPs); (2) LB IPAM + L2 reproduces today's
  tailscale-subnet reachability.
- **Migration**: Flannel→Cilium can't be cleanly drained node-by-node (mixed-CNI gap).
  Default approach for dev-local: **maintenance-window rebuild** — `caffeinate` all 6
  hosts awake, reprovision nodes onto Cilium together. Recovery path stays
  `ssh→host→limactl` (CNI-independent). etcd snapshot first.

### Phase 3 — consolidate Gateway onto Cilium (optional)
- Switch `GatewayClass` `envoy → cilium`; `HTTPRoute`s carry over unchanged; cloudflared
  re-points at the Cilium Gateway Service; retire Envoy Gateway + Traefik. (Or keep
  Envoy Gateway — Cilium CNI doesn't force Cilium Gateway.)

## What this touches

| Layer | Change | Where |
|---|---|---|
| CNI / kube-proxy / LB IPAM | Flannel+kube-proxy+MetalLB → Cilium | **devx** (`k3s.go`) |
| Gateway controller | add Envoy Gateway (→ Cilium later) | GitOps platform app |
| cloudflared | new | GitOps platform app + SealedSecret |
| external-dns | `+gateway-httproute` source | GitOps (1 line) |
| Cloudflare tunnel + Access | as code (API/Terraform) | captured token |
| apps | `Ingress` → `HTTPRoute` | per-app, portable |

## Risks & rollback

- **Phase 0/1** (GitOps): revert the PR; AppSet prunes. Low.
- **Phase 2** (Cilium): the real risk. Mitigations: spike the tailscale topology on a
  throwaway first; etcd snapshot; `ssh→host→limactl` recovery; node-by-node within the
  window with verification gates; LB IPAM reuses the existing range so DNS/exposure is
  unchanged. If unrecoverable → break-glass.
- **Execution mode**: driven autonomously; fully silent until Phase 3 except a
  break-glass ping if Phase 2 leaves the cluster broken and unrecoverable.

## Decisions / defaults

- Test app: `whoami` at `whoami.ipv1337.dev`, Access-gated, torn down after.
- Public = apex (`*.ipv1337.dev`), private = `*.lab.ipv1337.dev`.
- Cloudflare Access: set up now (OTP), demonstrated on the test app.
- Gateway controller: Envoy Gateway interim → Cilium Gateway end-state.
