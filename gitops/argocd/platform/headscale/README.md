# Headscale

## Overview
Subsystem blueprint grouping child modules under `gitops/argocd/platform/headscale`.

## Subdirectories & Boundaries
- [src](./src/README.md): Component package providing implementation for gitops/argocd/platform/headscale/src.

## ACL policy

[`policy.hujson`](./policy.hujson) is the mesh's ACL policy and its source of
truth. Headscale keeps the live policy in its database
(`HEADSCALE_POLICY_MODE=database`, so Headplane's ACL page still works), and
[`configmap-policy.yaml`](./configmap-policy.yaml) (`ConfigMap/headscale-policy`)
embeds `policy.hujson` for Argo CD (`headscale-resources`). After editing
`policy.hujson`, regenerate the ConfigMap (`policy_configmap_drift_test` fails in
CI if they drift):

```sh
bazel run //gitops/argocd/platform/headscale:policy-configmap
```

Merging to `main` makes the change live automatically within ~2 minutes: Argo CD
syncs `ConfigMap/headscale-policy`, kubelet refreshes the directory-mounted
volume in place, and the `policy-sync` sidecar on `deploy/headscale` checks the
mounted file on startup and every 60 s (`headscale policy get`, then
`policy check` and `policy set` over the shared `/var/run/headscale/headscale.sock`
socket when it differs). Any edit made in Headplane is reverted on the next
60 s reconciliation when it differs from git.

Watch the sync logs and confirm the live policy:

```sh
bazel run //tools/gitops:logs -- -n headscale deploy/headscale -c policy-sync
bazel run //tools/gitops:headscale -- policy get
```

Manual push is break-glass only (`headscale-policy-check` can still validate a
local draft against live Headscale before merge). Because `policy-sync`
reconciles every 60 s from `ConfigMap/headscale-policy`, pause it before any
emergency override so your change is not overwritten while the PR is in flight:

```sh
bazel run //tools/gitops:headscale-policy-check        # validate a local change with live Headscale
bazel run //tools/gitops:headscale-policy-sync-pause   # 1. create unmanaged ConfigMap/headscale-policy-sync-pause
bazel run //tools/gitops:headscale-policy-set          # 2. break-glass: check, then replace live policy immediately
# 3. merge the fix to policy.hujson (and regenerated configmap-policy.yaml), then resume:
bazel run //tools/gitops:headscale-policy-sync-resume  # 4. delete ConfigMap/headscale-policy-sync-pause
```

Verify the rendered Helm `Deployment` (sidecar, securityContext, non-root socket
group `65533`, optional ConfigMaps, directory mounts, `policy-metrics` port `9102`)
locally with:

```sh
bazel run //gitops/argocd/platform/headscale:render-check
```

`render-check` pulls the Helm chart over the network (`helm pull`) and is
therefore non-hermetic, so it runs as a `bazel run` gate rather than a `bazel test`.

`policy-sync` also exposes Prometheus metrics via BusyBox `/busybox/httpd` on
named port `policy-metrics` (`9102`), atomically rewritten on each loop pass and
scraped by Prometheus's `kubernetes-service-endpoints` job through
[`service-policy-sync.yaml`](./service-policy-sync.yaml) (`Service/headscale-policy-sync`):

- `headscale_policy_sync_up`: `1` when the last unpaused reconciliation ended in
  sync, applied a policy, or skipped by design because `/etc/headscale-policy/policy.hujson`
  was absent (`! -e`); `0` when Headscale was not ready, `policy.hujson` existed
  but was unreadable (`! -r`) or failed to snapshot, `policy check` failed, or `policy set` failed.
- `headscale_policy_sync_last_success_timestamp_seconds`: Unix epoch timestamp of
  the last reconciliation ending with `up=1`.
- `headscale_policy_sync_paused`: `1` while `/etc/headscale-policy-pause/paused`
  is present, `0` otherwise.

Absent-file rule: when `/etc/headscale-policy/policy.hujson` does not exist
(`! -e`, for example when optional `ConfigMap/headscale-policy` is omitted on a
cluster without repo-managed policy), `policy-sync` records `up=1` and updates
`last_success_timestamp_seconds` on every tick so `HeadscalePolicySyncStale`
never fires continuously. Policy contents are never included in metrics.

What it allows today: James's own devices reach everything (as the old
allow-all did), and `tag:ci` reaches only TCP to the Envoy gateway NodePorts
`:30265` (HTTP) and `:31103` (HTTPS) on the three wired nodes. The node list in
the policy's `hosts` must match the `candidates` in
[`homelab-tunnel-setup`](../../../../.github/actions/homelab-tunnel-setup/action.yml);
`headscale_values_test` fails if they drift.

## Expiry monitoring

Every Headscale credential has an expiry date, and nothing breaks loudly
until the day it passes. `headscale-key-exporter` (in this folder:
`configmap-key-exporter.yaml`, `deployment-key-exporter.yaml`,
`service-key-exporter.yaml`) reads Headscale's own API every 5 minutes and
gives Prometheus one expiry time per pre-auth key, API key and device login.
Alerts (group `headscale` in
[`prometheus/applicationset.yaml`](../prometheus/applicationset.yaml)) go
through Alertmanager to ntfy and PagerDuty:

| Alert | When | Severity |
|---|---|---|
| `HeadscaleCredentialExpiringSoon` | 30 to 3 days left (stands down when the page takes over) | warning |
| `HeadscaleCredentialExpiringImminently` | under 3 days left | page |
| `HeadscaleKeyExporterDown` | for 30 min: a failed read, no successful read in an hour, a record it could not read, or no exporter at all | warning |
| `HeadscalePolicySyncStale` | for 5 min: last `policy-sync` `up=1` reconciliation older than 15 min while `headscale_policy_sync_paused == 0` | warning |

Expired credentials and spent single-use keys are left out, so a dead key
does not alert, and an alert resolves at the moment its key expires. That is
on purpose: expiring a key by hand, the way to retire one, looks the same to
the API and must clear the alert. To silence a key nothing uses any more,
expire it. The `user` label is the Headscale user's name, or its id for an
OIDC login: never an email, since `/metrics` is unauthenticated.

The exporter calls Headscale with an API key of its own (Secret
`headscale-key-exporter`, sealed in
`sealed-secrets-manifests/headscale-key-exporter.sealedsecret.yaml`; it syncs
at wave -4, before the exporter, so a fresh deploy does not start blind). That key is watched like the rest, and if it
expires the exporter gets a 401 and `HeadscaleKeyExporterDown` fires. Mint and
seal a fresh one, then commit the sealed file:

```sh
bazel run //tools/gitops:seal-headscale-key-exporter            # 365d; --expiration 90d to change
```

The pod re-reads the key on every refresh, so no restart is needed. Expire the
old key once the exporter is reporting again.

Tests: `bazel test //gitops/argocd/platform/headscale:key_exporter_test`
(the exporter, run straight out of the ConfigMap) and the promtool suite
`tools/ci/prometheus-rule-tests/headscale.test.yml`.

### What each credential is for (2026-11-15)

API key 1 (`sxHrjsz`, due 2026-11-20) was expired by hand on 2026-11-15: nothing used it.
Its `HeadscaleCredentialExpiringSoon` warning fired and then cleared once it was expired,
which is how this monitor was first proven end to end.

| Kind | Id | Expires | Used by |
|---|---|---|---|
| pre-auth key | 3 | 2036-10-23 | `headscale-subnet-router-auth`: the node agents and subnet router in this folder |
| pre-auth key | 4 | 2036-10-23 | not found in the repo or the cluster. Ephemeral and untagged, the kind `docs/admin/claude-code-cloud-sessions.md` asks for as `TS_AUTHKEY`, which lives outside the repo (unverified) |
| pre-auth key | 5 | 2027-11-14 | CI, `HEADSCALE_CI_AUTHKEY` (below) |
| API key | 3 (`TWRIQB0`) | 2036-11-11 | Headplane (`headplane-oidc-secret`) |
| API key | 6 (`8XhmgM0`) | 2027-11-15 | `headscale-key-exporter` |

Update this table when a key is minted, rotated or retired.

## CI pre-auth key (`HEADSCALE_CI_AUTHKEY`)

The Zitadel apply workflows (`zitadel-apps-relay-apply`,
`zitadel-apps-mcp-slack-apply`, `_zitadel-apps-apply`) and the Sentry apply
workflow (`sentry-apply`) join the mesh from GitHub Actions with
one shared pre-auth key: user `james` (id 1), reusable, ephemeral (a runner's
node is removed when it goes offline), tagged `tag:ci`.

| Headscale key id | Created | Expires |
|---|---|---|
| 5 | 2026-11-14 | **2027-11-14 11:28 PST** |

It lives in the `oauth-user-inspector-{development,nonproduction,production}`
and `sentry-production` GitHub Environments, backed up in the Bitwarden
deploy-env store
([`tools/sync-env-secrets`](../../../../tools/sync-env-secrets/README.md)).

**Rotate** before it expires (an expired key fails at "Join the Headscale
mesh"). From the main checkout, so the store is the shared one; needs `jq`.
The key goes straight into the four store files and is never printed. Run it
as a script (e.g. save it and `bash rotate.sh`), so a failure stops it rather
than closing your shell:

```sh
set -euo pipefail
bazel run //tools/sync-env-secrets:bw-pull
key="$(bazel run //tools/gitops:headscale-preauthkey-create -- \
  -u 1 --reusable --ephemeral --tags tag:ci -e 8760h -o json 2>/dev/null | jq -r .key)"
# Stop before touching the store if minting failed (an empty key would be
# pushed to Bitwarden and GitHub otherwise).
[ -n "$key" ] && [ "$key" != null ] || { echo "no key minted; store unchanged" >&2; exit 1; }
( umask 077
  for env in oauth-user-inspector-development oauth-user-inspector-nonproduction oauth-user-inspector-production sentry-production; do
    f="tools/sync-env-secrets/secrets/$env/HEADSCALE_CI_AUTHKEY"
    printf '%s' "$key" >"$f"
    chmod 600 "$f" # umask covers new files only
  done )
unset key
bazel run //tools/sync-env-secrets:bw-push
for env in oauth-user-inspector-development oauth-user-inspector-nonproduction oauth-user-inspector-production sentry-production; do
  bazel run //tools/sync-env-secrets:apply -- "$env"
done
```

Once a workflow run has joined with the new key, expire the old one. Find its
key with `headscale-preauthkey-list -- -u 1` (that prints key values in full,
so do it where nothing is recorded), then
`bazel run //tools/gitops:headscale -- preauthkeys expire -u 1 <old-key>`.

Then update the table above.
