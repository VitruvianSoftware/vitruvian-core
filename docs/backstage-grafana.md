# Grafana in Backstage

Each catalog entity that declares a `grafana/dashboard-selector` annotation gets
a **Grafana dashboards** card on its Overview tab, linking straight to the
dashboards that describe it.

## How it is wired

```
browser ──▶ Backstage backend ──▶ proxy /grafana/api ──▶ grafana.grafana.svc.cluster.local
                                    (Bearer: GRAFANA_TOKEN)
```

The browser never talks to Grafana and never sees the token. Two consequences
worth knowing:

- the proxy targets the **in-cluster Service**, not `grafana.lab.ipv1337.dev`,
  so the traffic stays inside the cluster and does not depend on external DNS or
  the ingress being reachable;
- `grafana.domain` is still the _public_ URL, because it is only used to build
  the click-through links the card renders.

The proxy endpoint is restricted to `GET`, and only forwards `Accept` and
`Content-Type`, so a browser-supplied cookie or `Authorization` header cannot
ride along to Grafana.

## Credentials

A Grafana **service account** named `backstage` (id 35) with the **Viewer**
role. Verified behaviour:

| Request                    | Result                     |
| -------------------------- | -------------------------- |
| `GET /api/search?tag=devx` | `200` — returns dashboards |
| `POST /api/dashboards/db`  | `403` — cannot write       |
| `GET /api/admin/users`     | `404` — cannot administer  |

The token is stored as the SealedSecret
`gitops/argocd/platform/sealed-secrets-manifests/grafana-backstage-token.sealedsecret.yaml`
and injected as `GRAFANA_TOKEN`. It is generated inside the Grafana pod and
sealed without ever being printed — see the rotation recipe below.

### Rotating the token

It does not expire, so rotation is deliberate. Grafana rejects a second token
with the same name (`serviceaccounts.ErrTokenAlreadyExists`), so revoke the old
one first — list them at `/api/serviceaccounts/35/tokens`.

The token is written to a `0600` file rather than piped straight through, and
its length is asserted before sealing. This is not fussiness: `kubeseal
--validate` only proves the controller can _decrypt_ the manifest, not that the
payload is non-empty. An earlier revision of this integration sealed a
zero-byte token, passed `--validate` cleanly, and produced a `Synced=True`
SealedSecret whose Secret held nothing — the failure only surfaced as a `401`
from Grafana at request time.

```sh
set -eu
umask 077
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
POD=$(kubectl get pods -n grafana -l app.kubernetes.io/name=grafana \
        -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n grafana "$POD" -c grafana -- sh -c '
  curl -s -u "$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD" \
    -X POST http://localhost:3000/api/serviceaccounts/35/tokens \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"backstage-proxy\",\"secondsToLive\":0}"' \
| python3 -c 'import json,sys; k=json.load(sys.stdin)["key"]; \
    assert k.startswith("glsa_"); open(sys.argv[1],"w").write(k)' "$TMP/tok"

test -s "$TMP/tok"   # the assertion that was missing

kubectl create secret generic grafana-backstage-token --namespace backstage \
  --from-file=GRAFANA_TOKEN="$TMP/tok" --dry-run=client -o yaml \
| kubeseal --format yaml \
    --controller-name sealed-secrets-controller \
    --controller-namespace sealed-secrets \
> /tmp/sealed-body.yaml
```

Splice the new `apiVersion:`-onward body under this file's existing comment
header, then confirm the cluster actually received a payload:

```sh
kubectl get secret grafana-backstage-token -n backstage \
  -o jsonpath='{.data.GRAFANA_TOKEN}' | base64 -d | wc -c   # expect 46
```

The value never appears in a terminal, a log, or a process argument list at any
point.

### Verifying a rotation

Prove the new token works before merging — a bad token surfaces only as a `401`
at request time:

```sh
kubectl run grafana-token-probe -n backstage --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 \
  --overrides='{"spec":{"containers":[{"name":"c","image":"curlimages/curl:8.10.1",
    "command":["sh","-c","curl -s -o /dev/null -w \"%{http_code}\\n\" -H \"Authorization: Bearer $GRAFANA_TOKEN\" http://grafana.grafana.svc.cluster.local/api/search?tag=devx"],
    "env":[{"name":"GRAFANA_TOKEN","valueFrom":{"secretKeyRef":{"name":"grafana-backstage-token","key":"GRAFANA_TOKEN"}}}]}]}}'
```

Expect `200`. Last verified: read `200`, write `403`.

## Adding the card to an entity

Add the annotation to that component's `catalog-info.yaml`:

```yaml
metadata:
  annotations:
    grafana/dashboard-selector: devx
```

The selector is matched **as a tag** when it is a single word (`/^[\w-]+$/`),
and as a search query otherwise. Tag matching is **case-sensitive** — `kubernetes`
matches nothing, because the tag in this Grafana is `Kubernetes`.

Entities without the annotation simply do not render the card, so adding it is
opt-in and a missing dashboard never leaves an empty box on the page.

Currently annotated:

| Entity    | Selector  | Resolves to        |
| --------- | --------- | ------------------ |
| `devx`    | `devx`    | devx Build Metrics |
| `homelab` | `homelab` | Node Power         |

The other components have no dashboard of their own yet. Tag a dashboard with
the component's name and add the annotation, and the card appears — no code
change needed.

## Why there is no alerts card

The plugin ships an `EntityGrafanaAlertsCard`, and it is deliberately **not**
installed. Every endpoint it queries — `/api/alerts`,
`/api/prometheus/grafana/api/v1/alerts`, `/api/ruler/grafana/api/v1/rules` — reads
only **Grafana-managed** alert rules. This cluster has none:

```
grafana-managed rules           : 0
datasource-managed (Prometheus) : 13 groups, 42 rules
```

The 42 alerts are Prometheus rules, evaluated by Prometheus and routed through
Alertmanager. Grafana can display them, but not through any API this plugin
calls, so the card would render permanently empty. Surfacing alerts per entity
would mean either migrating rules to Grafana-managed alerting (fragmenting the
source of truth) or a small custom card that queries
`/api/prometheus/<datasource-uid>/api/v1/rules` and filters on labels — the
rules carry `severity` and `cluster` labels today, so a per-entity label would
need adding first.

The `grafana.unifiedAlerting` config key is likewise absent: it only selects
which alerting API that card queries, so with no card it would be dead config
implying a feature that is not there.
