# Headscale

## Overview
Subsystem blueprint grouping child modules under `gitops/argocd/platform/headscale`.

## Subdirectories & Boundaries
- [src](./src/README.md): Component package providing implementation for gitops/argocd/platform/headscale/src.

## ACL policy

[`policy.hujson`](./policy.hujson) is the mesh's ACL policy and its source of
truth. Headscale keeps the live policy in its database
(`HEADSCALE_POLICY_MODE=database`, so Headplane's ACL page still works), which
means Argo CD does not apply this file. After a change merges, apply it from
the main checkout:

```sh
bazel run //tools/gitops:headscale-policy-check   # validate with the live Headscale
bazel run //tools/gitops:headscale-policy-set     # check, then replace the live policy
bazel run //tools/gitops:headscale -- policy get  # confirm what is live
```

An edit made in Headplane lasts only until the next `headscale-policy-set`.

What it allows today: James's own devices reach everything (as the old
allow-all did), and `tag:ci` reaches only TCP to the Envoy gateway NodePort
`:30265` on the three wired nodes. The node list in the policy's `hosts` must match the
`candidates` in
[`zitadel-tunnel-setup`](../../../../.github/actions/zitadel-tunnel-setup/action.yml);
`headscale_values_test` fails if they drift.

## CI pre-auth key (`HEADSCALE_CI_AUTHKEY`)

The Zitadel apply workflows (`zitadel-apps-relay-apply`,
`zitadel-apps-mcp-slack-apply`, `_zitadel-apps-apply`) join the mesh from
GitHub Actions with one shared pre-auth key: user `james` (id 1), reusable,
ephemeral (a runner's node is removed when it goes offline), tagged `tag:ci`.

| Headscale key id | Created | Expires |
|---|---|---|
| 5 | 2026-11-14 | **2027-11-14 11:28 PST** |

It lives in the `oauth-user-inspector-{development,nonproduction,production}`
GitHub Environments, backed up in the Bitwarden deploy-env store
([`tools/sync-env-secrets`](../../../../tools/sync-env-secrets/README.md)).

**Rotate** before it expires (an expired key fails at "Join the Headscale
mesh"). From the main checkout, so the store is the shared one; the key goes
straight into the three store files and is never printed:

```sh
bazel run //tools/sync-env-secrets:bw-pull
key="$(bazel run //tools/gitops:headscale-preauthkey-create -- \
  -u 1 --reusable --ephemeral --tags tag:ci -e 8760h -o json 2>/dev/null | jq -r .key)"
( umask 077
  for env in development nonproduction production; do
    printf '%s' "$key" \
      >"tools/sync-env-secrets/secrets/oauth-user-inspector-$env/HEADSCALE_CI_AUTHKEY"
  done )
unset key
bazel run //tools/sync-env-secrets:bw-push
for env in development nonproduction production; do
  bazel run //tools/sync-env-secrets:apply -- "oauth-user-inspector-$env"
done
```

Once a workflow run has joined with the new key, expire the old one. Find its
key with `headscale-preauthkey-list -- -u 1` (that prints key values in full,
so do it where nothing is recorded), then
`bazel run //tools/gitops:headscale -- preauthkeys expire -u 1 <old-key>`.

Then update the table above.
