# Federating the homelab cluster with GCP

In-cluster workloads (Backstage, Grafana) can read GCP APIs — Cloud Run
revisions, Cloud Monitoring metrics — **without a service account key**.

## Why keyless is the only option

`constraints/iam.disableServiceAccountKeyCreation` is enforced org-wide, so the
usual "download a JSON key, seal it into the cluster" path is closed by policy:

```sh
gcloud resource-manager org-policies describe \
  iam.disableServiceAccountKeyCreation \
  --project prj-d-bu1-oss-floating-648a --effective
# booleanPolicy: {enforced: true}
```

The workloads also don't run on GCE, so there's no metadata server to fall back
on. Federating the cluster's own OIDC issuer is what remains — and it's the
better answer regardless: nothing long-lived to leak or rotate.

## Why the JWKS is inline

The cluster's issuer is `https://kubernetes.default.svc.cluster.local`, an
in-cluster address GCP cannot resolve. Rather than expose the Kubernetes API
server to the internet purely to satisfy OIDC discovery, the JWKS is supplied
**statically** to the provider (`JwksJson`).

The cost of that choice: **if the cluster's signing keys are rotated, this value
must be re-synced**, or every token exchange starts failing with an opaque
`invalid_grant`. Re-read it with:

```sh
kubectl get --raw /openid/v1/jwks
```

and update `cluster_jwks_json` in the bootstrap stack's config.

## Why the trust is narrow

A projected ServiceAccount token is mintable by any pod that can mount one, so
trusting the issuer alone would let _any_ workload in the cluster impersonate.
Two things keep it tight:

- **`AttributeCondition`** pins accepted subjects to an explicit list of
  `system:serviceaccount:<ns>:<name>` values. A pod in an unrelated namespace is
  rejected at the provider, before any IAM binding is consulted.
- **The `workloadIdentityUser` binding names the exact subject principal**, not
  an attribute `principalSet`. A principalSet would silently extend
  impersonation to every future subject the provider accepts.

The subject list is built with `%q`, not string concatenation — a subject
containing a quote would otherwise close the CEL literal early and have its tail
parsed as an expression. `clusterAttributeCondition` is unit-tested against
exactly that case; the test fails if it ever regresses to `%s`.

## Configuration

All of it is gated on `cluster_issuer_uri`. Unset, the whole feature is absent —
no pool, no provider, no service account.

| config key           | meaning                                                                                                      |
| -------------------- | ------------------------------------------------------------------------------------------------------------ |
| `cluster_issuer_uri` | the cluster's OIDC issuer; also added to the folder's allowed-issuer policy                                  |
| `cluster_jwks_json`  | the statically-supplied JWKS (see above)                                                                     |
| `cluster_audience`   | audience the projected token is minted for; pinning it stops replay of a token minted for the Kubernetes API |
| `cluster_subjects`   | CSV of `system:serviceaccount:<ns>:<name>` allowed to impersonate                                            |

Setting the issuer without a JWKS, or without subjects, is a hard error rather
than a partial build — a federation that accepts every ServiceAccount in the
cluster is not a useful default.

## The issuer allowlist

`constraints/iam.workloadIdentityPoolProviders` denies all external issuers by
default. The allowlist is a **single** folder-scoped resource, so it is built as
the union of every issuer this foundation federates — GitHub Actions, Pulumi
ESC, and now the cluster. Adding a second policy for the same constraint would
not add to the list; it would fight the first for the same GCP resource.

## The API must be enabled on the _credential's_ project

A 403 from a Google API here usually is **not** a missing IAM grant. Google
attributes an API call's quota to the **consumer project**, which for a
federated service account defaults to the project the account lives in
(`prj-b-cicd-e096`) — not the project being queried. So reading Cloud
Monitoring in an app project still requires `monitoring.googleapis.com` to be
enabled on the cicd project, and the error names the wrong one:

```
Cloud Monitoring API has not been used in project 1064807322707
before or it is disabled.
```

Grafana compounds this by surfacing it as a bare `403 Forbidden` on the
datasource health check, discarding the half of the message that identifies the
cause. If a read 403s, fetch the raw API error before touching IAM.

The enablements live in `build_homelab_cluster_wif.go` alongside `iam` and
`sts`. Adding a new Google API to this identity's repertoire means adding it
there too.

## Grafana: the datasource works, its health check does not

The Cloud Monitoring datasource **serves queries correctly** — verified by
querying tabula's production project through Grafana and getting real data
back:

```
POST /api/ds/query   ->  200
  frames: 1   run.googleapis.com/container/instance_count   points=2
```

But its **health check shows an error, permanently**, and that is expected
rather than a fault to chase:

- `authenticationType: gce` gets its _token_ from `google.DefaultTokenSource`,
  which resolves our external_account ADC — this is why queries work.
- It gets its _project_ from the **GCE metadata server**, via the backend's
  `gceDefaultProject` resource. Off GCE there is no metadata server, so that
  resolves to `""` and the health check queries an empty project:

```
GET .../resources/gceDefaultProject   ->  200  ""
GET .../health                        ->  ERROR "400 Bad Request"
```

Setting `gceDefaultProject` in `jsonData` does not fix the health check — the
backend re-resolves it from metadata — though it is still set, because the
frontend does read it.

**Dashboards are unaffected**: every real query names its project explicitly
(`timeSeriesList.projectName`), which is why they succeed while the health probe
does not.

The only configuration that would make the health check pass is
`authenticationType: jwt`, which requires a service account key, which
`iam.disableServiceAccountKeyCreation` forbids org-wide. So this is the correct
trade: working queries and a red health indicator, rather than no integration
at all.

## Granting access

This stack creates the identity and holds **no roles on the app projects**. The
read-only grants (`roles/monitoring.viewer`, `roles/run.viewer`) belong to the
stack that owns those projects, so the foundation never quietly accumulates
authority over workloads it doesn't manage.
