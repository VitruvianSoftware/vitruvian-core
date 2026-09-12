# mcp-slack Helm chart

Deploys the Slack MCP server on the dev-local k3s cluster as an
internet-facing, auth-gated endpoint for Google Gemini Spark.

This is the Phase 2b deliverable. The chart is written against acceptance
criteria that were fixed **before** the code, and each criterion maps to a
specific file below.

## What this deploys

| File | Resource | Why it exists |
|---|---|---|
| `templates/deployment.yaml` | Deployment | The server; hardened, bot-token only |
| `templates/service.yaml` | Service | ClusterIP, port 80 → container 3000 |
| `templates/httproute.yaml` | HTTPRoute | Public route, **`/mcp` prefix only** |
| `templates/networkpolicy.yaml` | CiliumNetworkPolicy | Bounds egress to Slack + Zitadel |

The sustained-5xx alert is **not** here — see [Alerting](#alerting).

## Required values

Every security-relevant value is required and has **no default**. The chart
fails to render rather than deploying an endpoint that is reachable but
unbounded. A value the chart cannot interpret must never resolve to the
permissive case.

| Value | Source | If absent |
|---|---|---|
| `image.digest` | the built image's `sha256:` | render fails |
| `oidc.projectId` | `pulumi stack output projectId` (`zitadel-apps-mcp-slack`) | render fails |
| `slack.channelIds` | the Slack admin session | render fails |

Since the manifest carries `groups:read`/`groups:history`, `slack.channelIds`
gates **private** channels too — a defect there is a private-conversation
disclosure, not a wider-than-intended public read.

> **Invite the bot to every listed channel BEFORE deploying.** The intuitive
> order — add the ID, deploy, then invite — does not work. Since #1421 the
> server verifies each allow-listed conversation's visibility at startup, and
> `conversations.info` on a private channel the bot has not joined returns
> `channel_not_found`, so the process exits non-zero. With `replicas: 1` and
> self-heal that presents as CrashLoopBackOff, which reads as "the deploy is
> broken" rather than "you skipped a step".

`required` is used rather than `default` on all three: a default here would
produce a deployment that renders, syncs, reports Healthy, and is wrong.

```bash
helm template mcp-slack mcp-slack/deploy/chart \
  --set image.digest=sha256:… \
  --set oidc.projectId=… \
  --set slack.channelIds=C…,C…
```

Omit any one of them and the render aborts with a message naming the source to
take it from.

## Acceptance criteria → implementation

**1. Tunnel ingress scoped to `/mcp` only.**
`httproute.yaml` matches the `/mcp` prefix and nothing else. The server serves
both `/mcp` and `/health` on one port; `/health` is unauthenticated by design
(a probe requiring a token would be testing the IdP, not the process), and
that is only correct because the path match keeps it off the internet. Kubelet
probes address the pod IP directly and never traverse the route. Widening this
to `/` publishes an anonymous liveness oracle for a laptop-hosted cluster.

**2. Egress restricted to Slack + Zitadel.**
`networkpolicy.yaml`, as a `CiliumNetworkPolicy`. Every other control on this
endpoint — the channel allow-list, the audience check, the tool filter — is
enforced by our own process and is void the moment the bot token leaves the
pod. This policy is the layer that still holds in that case.

> **MEASURED 2026-08-06: this policy breaks the workload on this cluster.**
> Validated live in a scratch namespace against a pod with the chart's exact
> selector labels. With the policy applied, *every* DNS query times out —
> including the two names it allows — and widening the rule back to
> `matchPattern: "*"` does not help, so the failure is not the narrowing.
> Remove the `rules.dns` block and DNS works but `toFQDNs` never matches, so
> egress is blocked instead. Cilium's L7 DNS proxy is the root cause and it is
> a platform defect: the cluster runs zero CiliumNetworkPolicies, so that path
> had never been exercised. Scoped to node `fedora`, Cilium v1.17.17.
> **Do not enable the Application while this template is in the chart.**

> **This is the cluster's first CiliumNetworkPolicy and the previous attempt
> was reverted** (`cecb67b7`, revert `ec08150b`). That policy denied apiserver
> egress because it allowed the apiserver's *endpoint* IPs while traffic
> actually goes to the ClusterIP; leader election failed every ~8s.
> mcp-slack never talks to the apiserver, so that exact failure is not in this
> workload's path — but the policy is **reviewed and unexercised** against live
> cluster behaviour, and the revert's own instruction was to validate before
> re-merge. Treat it as unproven until a live preview says otherwise.

Note the `toFQDNs` rules do nothing without the explicit DNS-proxy rule that
precedes them — omit it and the policy silently denies everything rather than
allowing the two hosts named.

The DNS rule names the two hosts rather than allowing `matchPattern: "*"`.
An unrestricted resolver is an unrestricted egress channel — kube-dns
forwards upstream, so a compromised process can encode the bot token into DNS
labels and exfiltrate it without opening a connection the TCP rules would
deny. It is paired with `ndots: 1` on the pod: under the Kubernetes default
of `ndots: 5`, `slack.com` is tried against every search domain first and
those queries are refused before the real one is sent.

**3. Edge rate limit. OPEN — not satisfied today.** Nothing throttles this
hostname. It is configured at Cloudflare rather than in this repo, so it is
not a defect in this chart, but recording it here does not discharge it:
this is a go-live blocker owned by **James** (Cloudflare account), and the
endpoint should not be announced to Spark until it is in place.

**4. Pod hardening.** `deployment.yaml`: non-root (uid 10001),
`readOnlyRootFilesystem`, all capabilities dropped, no privilege escalation,
`RuntimeDefault` seccomp, resource limits, image by digest,
`terminationGracePeriodSeconds`, and `automountServiceAccountToken: false` —
the pod reads no Kubernetes objects, so an apiserver credential mounted next
to the bot token is reachable by any file read and buys nothing.
`SLACK_BOT_TOKEN` and `SLACK_TEAM_ID` come from a Secret; `SLACK_USER_TOKEN`
is deliberately absent, and the server also refuses to start on the HTTP
transport if it is present — enforced on both sides rather than by this
file's omission alone.

## Alerting

The sustained-5xx alert lives in
`gitops/argocd/platform/prometheus/applicationset.yaml`, rule group
`mcp-slack`.

It is not in this chart, and the reason is worth knowing before you try to
"fix" that. This cluster runs the plain `prometheus` chart: there is **no
prometheus-operator** and no `prometheuses.monitoring.coreos.com` CRD. The
`PrometheusRule` CRD *does* exist (installed by the valkey operator), so a
`PrometheusRule` object would be accepted by the apiserver, synced by ArgoCD,
and reported Healthy — while never being loaded by anything. Prometheus reads
its rules from `serverFiles.alerting_rules.yml`.

That matters here more than usual, because this alert is the only signal that
authentication has broken. The server keeps its listener up rather than
exiting when JWKS is unreachable, and the probes deliberately do not touch the
IdP, so the pod stays Ready while every call fails. No pod-state alert can see
it.

> **This alert depends on a server behaviour that was wrong until
> `45130c18`.** It assumes an unreachable IdP produces 5xx. `auth.ts`
> originally wrapped *every* `jwtVerify` failure — including `TypeError:
> fetch failed` from the remote JWKS — in `InvalidTokenError`, a **401**. The
> 5xx numerator was zero during the exact outage this alert exists to catch,
> and the endpoint blamed the caller's credential for our own downtime.
>
> `45130c18` fixed half of it. `auth.ts` now discriminates on whether jose
> reached a verdict (`error instanceof errors.JOSEError`) rather than on the
> shape of the failure, so an unrecognised error cannot fall through to 401
> and accuse a valid token. Anything meaning verification never completed
> becomes `IdpUnavailableError` at **503**, carrying `Retry-After` and
> deliberately no `WWW-Authenticate` — that header would send a caller
> holding a good token to re-authenticate against an IdP that is down. The
> status does survive to the wire: `writeAuthFailure` in `httpTransport.ts`
> writes `error.status`, so Envoy sees a real 503.
>
> **STILL OPEN — a slow IdP is not covered.** `JWKSTimeout` *is* a
> `JOSEError` subclass, so it takes the 401 branch. Verified by installing
> the pinned `jose@6.2.4` and introspecting at runtime: **all 14** exported
> error classes extend `JOSEError`, and `jwks/remote.js` throws `JWKSTimeout`
> on a default `timeoutDuration` of **5000ms** that `createTokenVerifier`
> does not override.
>
> So *dead* IdP (connection refused, DNS failure → raw `TypeError`) → 503 and
> this alert fires; *hanging* IdP (≥5s → `JWKSTimeout`) → 401, and a caller
> with a valid token is told their credential is bad. In that case this alert
> is not merely insensitive, it is **mathematically silent**: every request
> is 4xx, so with 4xx excluded from the denominator the expression is 0/0 =
> NaN. Tracked on #1418 (Aegis); the fix also needs a deliberate call on
> `JWKSInvalid`, `JWKInvalid` and `JWKSMultipleMatchingKeys`, which are
> IdP-side conditions currently inheriting 401 from a shared base class.
>
> Worth recording *why* this survived a fix aimed straight at it: the repro
> was mine, it pointed at a **dead** JWKS URI, and a dead URI throws a raw
> `TypeError` — the one shape that takes the correct branch. The fix was
> verified against the outage that proves it right and not against the one
> that proves it wrong.

Note what these alerts do **not** cover: `envoy_cluster_upstream_rq*` counts
*upstream* responses. When Envoy synthesises a 503 because no healthy upstream
exists, no upstream response happened and the counter never moves —
`envoy_cluster_upstream_cx_none_healthy` moves instead. Measured on this
cluster: downstream 5xx on listener `http-10080` exceeds the sum of upstream
5xx across all `httproute` clusters by **406**, and those 406 are exactly the
Envoy-generated ones. Pod-down belongs to `KubeDeploymentReplicasMismatch`.
The division is clean — but it is a division, not redundancy.

### Two alerts, not one

`McpSlackIdpUnavailable` alerts on the **503 rate directly**, with no
denominator, so nothing can go NaN. It complements the ratio rather than
duplicating it: the ratio answers "of what we answered, most failed", this one
answers "we could not reach the IdP".

A bare `> 0` threshold is defensible only because the 503 population is
provably tiny, which was verified rather than assumed:

- `IdpUnavailableError` is the only 503 the application emits.
- An unauthenticated caller **cannot** produce one. `auth.ts:289` runs
  `extractBearerToken` before `verify()`, and extraction is pure string
  parsing that throws `MissingTokenError` (401) with no network call — absent,
  malformed and non-JWT tokens all short-circuit to 401 without touching JWKS.
  Internet scanners on an exposed `/mcp` are confined to 4xx by construction.

`for: 10m` against a 5m rate window means a single 503 cannot fire it; its
rate decays to zero five minutes after the event.

> **It does not fix the slow-IdP blind spot today.** It can only see failures
> the server reports as 503, so it inherits the `JWKSTimeout` gap exactly as
> the ratio does — a hanging Zitadel still returns 401 and fires neither. It
> becomes the answer to that case only once #1418 routes `JWKSTimeout` to
> `IdpUnavailableError`. What it fixes *now* is the NaN: a dead IdP producing
> only 503s leaves the ratio at 0/0 if nothing succeeds, and this still fires.

The alert is expressed as a **ratio**, not a request rate: the endpoint is idle
between Spark sessions, so any absolute threshold is wrong in both directions.
Idle produces no alert (0/0 is NaN), and a single failed call cannot fire it
(its 5m rate decays before the 10m `for` elapses).

The denominator counts 2xx and 5xx only. 4xx is a *separate population* on
this endpoint, not noise around the same one: a request with no
`Authorization` header is rejected at 401 before the auth path reaches JWKS,
so unauthenticated probes to an internet-facing `/mcp` are unaffected by an
IdP outage and would sit in the denominator diluting it — enough of them and
a total outage never crosses `0.5`. The question worth asking is "of the
requests we actually answered, how many failed".

The metric label is `envoy_cluster_name`, not `cluster_name`. Verified against
live series: the wrong name returns no data at all, which yields an alert that
is permanently silent while still looking present.

## Deployment

Via ArgoCD: `gitops/argocd/applications/mcp-slack.yaml.disabled`, git-source
Helm, scoped to `mcp-slack-project`. It ships **disabled** — see that file's
header for the four preconditions to enabling it.

## Validation

```bash
# renders with values, and refuses without them
helm template mcp-slack mcp-slack/deploy/chart --set image.digest=… …
helm lint mcp-slack/deploy/chart --set …

# the alert rules (all groups, not just this one)
promtool check rules <extracted alerting_rules.yml>
```

The CiliumNetworkPolicy cannot be validated this way — it needs the live
cluster. That gap is stated rather than papered over.
