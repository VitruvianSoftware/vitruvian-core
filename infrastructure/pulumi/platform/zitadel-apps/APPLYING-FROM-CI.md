# Applying `zitadel-apps` from CI (without the public edge)

> Status (2026-06-26): the live client is fixed and config-as-code matches it
> ([#300](https://github.com/VitruvianSoftware/vitruvian-core/pull/300)).
> `ZITADEL_APPS_AUTO_APPLY` is still **off** because the CI apply can't reliably
> reach the Zitadel management API yet — this doc is the plan to close that.
> **Option (a) is the chosen approach; (b)/(c) are documented for future use.**

## The problem

`auth.ipv1337.dev` is public via **Cloudflare Tunnel → Envoy Gateway → Zitadel**.
Cloudflare's bot protection (managed challenge / bot-fight) intermittently returns
**`403 error code: 1010`** ("browser signature banned") to non-browser clients.
The Pulumi `pulumiverse/zitadel` provider is a plain Go HTTP client, so its
management-API reads get blocked — surfaced as `failed to get application oidc`.
Locally the same block hit `curl`/`python` until a browser User-Agent + retries
got through; that intermittency is exactly why it can't gate a deploy.

This is **not** a provider/auth bug. With a valid token the management API works
fine — the block is purely Cloudflare's edge, in front of an endpoint that end
users never touch.

## Principle

The public, bot-protected edge exists to protect the **user-facing** auth surface
(`/authorize`, `/token`, `/userinfo`, the login UI). The Zitadel **management
API** is privileged control-plane. The correct fix is to keep those planes
separate — reach the management API over a **trusted internal path**, leaving the
public edge maximally protected — rather than punching a bot-protection hole in a
privileged endpoint (which would be the shortcut).

## Verified facts (the internal path works)

Measured 2026-06-26 against the live cluster:

| Fact | Evidence |
| --- | --- |
| The Envoy gateway LB is internal at **`10.44.86.211:80`** (HTTP only; TLS is terminated at Cloudflare) | `kubectl get svc -n envoy-gateway-system` → `envoy-…-platform` EXTERNAL-IP `10.44.86.211`, `80:30265/TCP` |
| ~~That IP is **reachable over tailnet** — the `fedora` node advertises `10.44.86.0/24`~~ **SUPERSEDED — see below** | `tailscale status --json` → fedora `PrimaryRoutes` includes `10.44.86.0/24` |
| The **management API works over the internal path** (no Cloudflare) | `curl -H 'Host: auth.ipv1337.dev' http://10.44.86.211/management/v1/orgs/me` → **401** unauthenticated (200 + the org *with* a bearer token). Either way it is Zitadel answering, not Cloudflare — the public edge returns `403 … 1010`. See the caveat below. |
| Zitadel requires the JWT-profile **audience = `https://auth.ipv1337.dev`** even over an HTTP connection — `http://…` audiences are **rejected** | minted tokens with each audience against the internal endpoint; only the `https` audience was accepted |

**Consequence:** the *connection* can be internal HTTP, but the provider must be
**presented HTTPS** so it signs the assertion with the `https://` audience. So the
internal route needs a TLS front (a local terminator, or an internal Envoy HTTPS
listener) — see the "Route auth.ipv1337.dev to the internal Envoy (TLS
terminator)" step in the workflow sketch below.

> ### ⚠️ The VIP row above is superseded, and it fails toward "it works"
>
> **`10.44.86.211` is NOT reachable from an off-cluster tailnet client** — which
> is what a GitHub runner is. It is a Cilium eBPF LB address, and a
> subnet-router-forwarded packet to it is dropped by Cilium's datapath before
> load-balancing; conntrack never sees it. `_zitadel-apps-apply.yaml` moved off
> the VIP on 2026-07-20; its "Apply the Zitadel application stack (Pulumi)" step
> carries the full reasoning inline, just above the `socat` line. **This file is
> the argument for the approach, not a copy of the command.**
>
> **Neither half of that target is defined in a workflow.** The port is the
> `http-80` `nodePort` pinned in the gateway `EnvoyProxy` patch
> (`gitops/argocd/platform/envoy-gateway/gateway/envoyproxy.yaml`) — pinned
> precisely so it cannot drift on a Service recreation. The host is *any* node's
> tailscale device, because that Service sets `externalTrafficPolicy: Cluster`
> so every node answers the NodePort. **The workflows hold copies of the port.**
> So rather than name a workflow here and have that name go stale, list them:
>
> ```sh
> EP=gitops/argocd/platform/envoy-gateway/gateway/envoyproxy.yaml
> PORT=$(awk '$1=="nodePort:" {print $2}' "$EP")
> git grep -lF ":$PORT" -- .github/workflows
> ```
>
> Two things in that command are load-bearing. `$1=="nodePort:"` anchors on the
> **field**, so a comment quoting this command does not match its own pattern.
> And `-- .github/workflows` is not tidiness: unscoped, the grep also returns
> this file (its `:38` evidence cell) and `oauth-user-inspector/docs/OPERATIONS.md`.
> Measured 2026-08-09 — **1 workflow on `main`, 2 with #1519** — so it reports
> the set instead of asserting it.
>
> **Why this row misled anyone reading it:** the fact is *true on a host that
> holds the `10.44.86.0/24` subnet route* — a laptop on the tailnet reaches the
> VIP and gets a real answer from Zitadel. It is false on a runner. So the
> measurement in the Evidence column reproduces for whoever checks it locally
> and still doesn't transfer to CI. **A reachability result is bound to the host
> that took it**, and neither the row nor the curl carries that stamp.
>
> The row is struck rather than deleted because the `PrimaryRoutes` measurement
> is still accurate — it's the *conclusion drawn from it* that doesn't hold for
> the CI case this document exists to describe.
>
> **The management-API row's evidence command was also under-specified.** It said
> `→ 200 + the org`; run exactly as printed it returns **401**, because it carries
> no bearer token. Measured from a subnet-routed host on 2026-08-09. The row's
> *conclusion* is unaffected and the 401 is arguably the better evidence for it —
> **a 401 proves Zitadel answered**, whereas the public edge returns
> `403 error code: 1010` and never reaches Zitadel at all. Fixed above so the
> command and its stated result agree; someone who runs it and sees 401 should
> read that as the internal path working, not as it being broken.

---

## (a) Tailnet internal routing — RECOMMENDED, chosen

The deploy job joins the tailnet ephemerally and talks to Zitadel over the
internal Envoy, transparently to the provider (which still uses
`https://auth.ipv1337.dev`, so issuer/audience/SNI are unchanged).

### One-time prerequisite (tailnet admin — provision once)
1. **Tailscale OAuth client** for CI: in the Tailscale admin console (or API),
   create an OAuth client scoped to `auth_keys`, tagged **`tag:ci`**. Store
   `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_SECRET` as secrets on the
   `oauth-user-inspector-development` GitHub environment. (Keyless + ephemeral —
   matches §2.6; not a static auth key.)
2. **ACL**: allow `tag:ci` to reach the gateway, e.g.
   `{"action":"accept","src":["tag:ci"],"dst":["10.44.86.211:80"]}`
   (the tailnet is devx-managed — `devx/internal/tailscale`).

### Workflow change (`zitadel-infra` job in `oauth-user-inspector-deploy.yaml`)
```yaml
      - name: Join the tailnet (ephemeral)
        uses: tailscale/github-action@<pinned-sha>   # v3
        with:
          oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
          oauth-secret:    ${{ secrets.TS_OAUTH_SECRET }}
          tags: tag:ci
          # ephemeral node; leaves the tailnet when the job ends

      - name: Route auth.ipv1337.dev to the internal Envoy (TLS terminator)
        run: |
          # self-signed cert for the host the provider expects; trust it locally
          openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/k.pem -out /tmp/c.pem \
            -days 1 -subj "/CN=auth.ipv1337.dev" -addext "subjectAltName=DNS:auth.ipv1337.dev"
          sudo cp /tmp/c.pem /usr/local/share/ca-certificates/auth-internal.crt
          sudo update-ca-certificates           # provider (Go) now trusts it
          cat /tmp/c.pem /tmp/k.pem > /tmp/ck.pem
          # terminate TLS on :443, forward decrypted HTTP to the internal Envoy
          # (Host: auth.ipv1337.dev is preserved end-to-end, so Envoy routes it)
          #
          # DO NOT target the LB VIP here — see the superseded-VIP note under
          # "Verified facts", above. It carries the query that lists the
          # workflows holding a working form; naming one of them here would go
          # stale, because the port is defined in the gateway EnvoyProxy patch
          # and the workflows only hold copies of it.
          socat OPENSSL-LISTEN:443,reuseaddr,fork,cert=/tmp/ck.pem,verify=0 \
                TCP:<a node's tailscale device>:<gateway NodePort> &
          echo "127.0.0.1 auth.ipv1337.dev" | sudo tee -a /etc/hosts

      # the existing apply step is UNCHANGED — the provider still uses
      # https://auth.ipv1337.dev; it transparently lands on the internal Envoy.
```
Cloudflare is bypassed for this job; **nothing about the public edge changes**.

### Cleaner long-term variant (no CI-side proxy)
Instead of the per-job terminator, give Envoy an **internal HTTPS listener** for
`auth.ipv1337.dev` (a `cert-manager` Certificate via Cloudflare DNS-01 + an Envoy
`Gateway` HTTPS listener, both GitOps/ArgoCD-managed). Then any internal admin
client connects `https://10.44.86.211` directly with a real cert and the CI job
only needs the tailnet on-ramp + the `/etc/hosts` line — no proxy, no self-signed
cert. Prefer this once more than one internal client needs the management API.

---

## (b) Self-hosted in-cluster runner — future option

Run a GitHub Actions **self-hosted runner inside the cluster** (or on a tailnet
host) and target the `zitadel-infra` job to it. It reaches Zitadel internally with
no tailnet on-ramp and no TLS gymnastics (talk to the in-cluster service / the
internal HTTPS listener directly).

- **Pros:** no per-job tailnet/TLS setup; natural fit for *any* in-cluster admin
  automation; lowest per-run latency.
- **Cons:** a runner to own, patch, and secure (a standing credentialed foothold
  in the cluster — scope it tightly, ephemeral/auto-scaled if possible); diverges
  from the all-GitHub-hosted-runner model used by the other deploys.
- **Use when:** you accumulate several in-cluster control-plane jobs and the
  per-job on-ramp becomes repetitive.

## (c) Pulumi Kubernetes Operator (PKO) — future option

Make the `zitadel-apps` stack a **`Stack` CRD** reconciled by the Pulumi Operator
**inside the cluster**. The apply runs in-cluster (reaching Zitadel internally),
reconciled like the rest of the platform.

- **Pros:** most GitOps-pure — fits §2.3 (closed-loop platform reconcile); no CI
  egress, no tailnet-from-CI; drift is continuously reconciled, not just on deploy.
- **Cons:** biggest change — adopt + operate PKO; diverges from how `tabula` /
  `oauth-user-inspector` deploy today (CI-Pulumi), so it splits the deploy model
  unless those migrate too; the machine-user key moves to an in-cluster (sealed)
  secret.
- **Use when:** you want the IdP-app config continuously reconciled (not
  deploy-triggered), or you migrate the app deploys to an operator model broadly.

---

## Enabling `ZITADEL_APPS_AUTO_APPLY`

Only after the apply path above is in place and a **dry run is green**:
1. Confirm a CI run (or a break-glass run on the internal path) does an in-place
   **adopt** of the existing client with **no diff** (config already matches live).
2. Set the `ZITADEL_APPS_AUTO_APPLY` variable to `true` on the
   `oauth-user-inspector-development` environment.
3. From then on, redirect-URI / client changes are a code edit + merge — the apply
   reconciles them over the internal path, and the public edge stays untouched.
