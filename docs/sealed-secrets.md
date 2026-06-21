# SOP: Sealed-secrets, Bitwarden keys & MCP reinstall recovery

How the homelab's secrets survive a full cluster + app reinstall, and the exact
steps to bring the **ArgoCD** and **Grafana** MCP servers (Claude Desktop) back
without editing anything on the Mac.

Related: [Rotating secrets & API keys](key-rotation.md).

## The model

Secrets are reproducible **from git**, encrypted as Bitnami `SealedSecret`s
(`gitops/argocd/platform/sealed-secrets-manifests/`). A `SealedSecret` can only be
decrypted by the in-cluster controller's **private key** — so that key is the one
thing that must survive a reinstall, and it lives in **Bitwarden**, never in git.

ArgoCD itself is the pulumi bootstrap and comes up *before* the (ArgoCD-managed)
sealed-secrets controller, so its `argocd-secret` cannot be a `SealedSecret`. It is
instead vaulted to Bitwarden directly.

### What lives in Bitwarden (off-cluster, never committed)

| Bitwarden item (Secure Note) | Holds | Backed up / restored by |
|---|---|---|
| `dev-local sealed-secrets controller keys` | sealed-secrets controller **private key** (decrypts every SealedSecret) | `//tools/gitops:sealed-secrets-{backup,restore,verify}` |
| `dev-local argocd-secret (server.secretkey + mcp token)` | ArgoCD `server.secretkey` (token signing key) + `accounts.mcp.tokens` (token seed) | `//tools/gitops:argocd-secret-{backup,restore,verify}` |

> Prereq: `bw login` once. The targets auto-unlock (prompt for the master password,
> or use `$BW_PASSWORD` / a pre-set `$BW_SESSION`). All target wrappers default
> `KUBECONFIG=$HOME/.kube/cluster.yaml`, context `default`.

### Why the Mac never changes

- **ArgoCD MCP** uses a long-lived JWT signed by `server.secretkey`, with its id in
  `accounts.mcp.tokens`. Restoring `argocd-secret` restores *both*, so the JWT in
  `claude_desktop_config.json` keeps validating — no re-mint, no edit.
- **Grafana MCP** uses basic auth against the sealed `grafana-admin-credentials`
  password. The SealedSecret reproduces the same password, so the Grafana extension
  settings keep working unchanged.

## Reinstall recovery (run in order)

```bash
cd <repo root>
export KUBECONFIG="$HOME/.kube/cluster.yaml"

# 1. Bring the cluster + ArgoCD back up (installs the sealed-secrets controller too).
bazel run //infrastructure/pulumi/dev-local:up -- --stack local --yes

# 2. Restore the sealed-secrets master key so the controller can decrypt git secrets.
bazel run //tools/gitops:sealed-secrets-restore        # enter bw master password if prompted

# 3. Wait for ArgoCD to sync the platform apps. The grafana-admin-credentials
#    SealedSecret now decrypts into the grafana namespace.
argocd app wait grafana --grpc-web                     # or watch `argocd app list`
kubectl -n grafana get secret grafana-admin-credentials >/dev/null && echo "grafana admin secret OK"

# 4. Restore argocd-secret (signing key + mcp token seed) and restart the API server.
bazel run //tools/gitops:argocd-secret-restore         # enter bw master password if prompted
```

## Verify the MCPs

```bash
# ArgoCD: the unchanged Mac JWT should authenticate as user `mcp`.
TOKEN="$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/Library/Application Support/Claude/claude_desktop_config.json")))["mcpServers"]["argocd-mcp"]["env"]["ARGOCD_API_TOKEN"])')"
argocd account get-user-info --auth-token "$TOKEN" --server argocd.lab.ipv1337.dev --grpc-web   # -> Logged In: true, Username: mcp

# Grafana: the unchanged Mac basic-auth should reach the API.
PW="$(kubectl -n grafana get secret grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d)"
curl -sS -u "admin:$PW" https://grafana.lab.ipv1337.dev/api/org    # -> {"id":1,...}
```

Then restart Claude Desktop (Cmd-Q) and confirm both MCP servers connect.

## Maintenance

- **After first-time setup / any change to these secrets, re-run the relevant backup**
  so Bitwarden is current:
  ```bash
  bazel run //tools/gitops:sealed-secrets-backup   # after controller (re)install / key rotation
  bazel run //tools/gitops:argocd-secret-backup    # after (re)minting the mcp token
  ```
- **Verify the vault is restorable** (read-only, no cluster needed) periodically:
  ```bash
  bazel run //tools/gitops:sealed-secrets-verify
  bazel run //tools/gitops:argocd-secret-verify
  ```
- **Rotating the Grafana admin password:** create a new password, re-seal it
  (`kubectl create secret … --dry-run=client -o yaml | bazel run //tools/gitops:kubeseal -- --controller-name sealed-secrets-controller --controller-namespace sealed-secrets --format yaml`),
  overwrite `gitops/argocd/platform/sealed-secrets-manifests/grafana-admin-credentials.sealedsecret.yaml`, commit, let ArgoCD sync, then update the Grafana MCP extension settings on the Mac.
- **Rotating the ArgoCD mcp token:** `argocd account generate-token --account mcp`,
  update `claude_desktop_config.json`, then `bazel run //tools/gitops:argocd-secret-backup`.

## Notes

- The `mcp` ArgoCD account (apiKey, role:admin) is created by pulumi
  (`argocd_api_account` in `infrastructure/pulumi/dev-local`; the enablement lives in
  the gitignored `Pulumi.local.yaml` on the operator's machine).
- Losing **both** the Bitwarden items and the live cluster means re-bootstrapping from
  scratch (new signing key, new token, re-seal Grafana). Keep the Bitwarden vault backed up.
