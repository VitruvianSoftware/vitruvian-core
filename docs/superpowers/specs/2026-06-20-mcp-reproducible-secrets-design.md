# Design: Reproducible MCP credentials across cluster reinstall

- **Date:** 2026-06-20
- **Status:** Draft v2 — revised after prior-art review (#174–#182)
- **Topic:** Make the ArgoCD and Grafana MCP servers (Claude Desktop) keep working
  after a full cluster + app reinstall, with minimal manual steps and nothing edited
  on the Mac.

## Goal & success criteria

After reinstalling the k3s cluster and its apps, the ArgoCD and Grafana MCP servers in
Claude Desktop must authenticate and work **without editing anything on the Mac**.
Reinstall should require only: the normal pulumi+ArgoCD bring-up, plus a small number
of `bazel run` "restore" steps that re-seat the credentials. The Mac config is fixed.

## Prior art already merged (#174–#182) — DO NOT rebuild

The homelab already migrated to Sealed Secrets today. Build on this; do not duplicate:

- **Controller, reproducible:** `gitops/argocd/platform/sealed-secrets/` (ArgoCD-managed).
- **Master key ↔ Bitwarden:** `//tools/gitops:sealed-secrets-backup` / `:sealed-secrets-restore`
  (`tools/gitops/sealed_secrets_keys.sh`). Stores the controller private key as an
  attachment on the Bitwarden Secure Note **"dev-local sealed-secrets controller keys"**.
  Auto-unlocks `bw` (BW_SESSION → BW_PASSWORD → interactive). `bw login` once.
- **Seal helper:** `//tools/gitops:kubeseal` (`tools/gitops/gitops_cmd.sh`).
- **SealedSecret pattern:** `gitops/argocd/platform/sealed-secrets-manifests/*.sealedsecret.yaml`
  wired by `gitops/argocd/applications/sealed-secrets-manifests.yaml`. Existing examples:
  `cf-secret`, `cloudflare-api-token`, `cnpg-app-credentials`, `grafana-db-credentials`
  (the last is the template to copy: `bitnami.com/v1alpha1` SealedSecret with
  `encryptedData` + `template`).

So the original spec's "make sealed-secrets first-class + Bitwarden + bazel targets"
sections are **done**. What remains is narrow and specific to the two MCPs.

## The asymmetry that drives the design

- **Grafana** is an ordinary ArgoCD-managed app that syncs *after* the sealed-secrets
  controller. → It **can** use a `SealedSecret`. (Same as grafana-db.)
- **ArgoCD itself** is the pulumi bootstrap and must come up *before* anything it
  manages — including the sealed-secrets controller. → Its `argocd-secret` **cannot**
  be a SealedSecret (chicken-and-egg). It needs an out-of-band, deterministic source.
  We reuse the **Bitwarden** pattern already proven by #181/#182.

## Design details

### 1. Grafana — sealed admin password + basic auth (uses existing flow)

- Choose a strong admin password; seal it via `//tools/gitops:kubeseal` into
  `gitops/argocd/platform/sealed-secrets-manifests/grafana-admin-credentials.sealedsecret.yaml`
  (ns `grafana`, keys `admin-user`/`admin-password`, copy the grafana-db template).
- In [grafana/applicationset.yaml](../../../gitops/argocd/platform/grafana/applicationset.yaml)
  replace `adminPassword: admin` with:
  ```yaml
  admin:
    existingSecret: grafana-admin-credentials
    userKey: admin-user
    passwordKey: admin-password
  ```
- This removes the `admin/admin` plaintext from the public repo **and** gives a
  deterministic credential. The MCP uses basic auth (`GRAFANA_USERNAME`=admin +
  that password). Delete the runtime `mcp` service account created earlier.
- Reproducible because: master key restored → controller decrypts the SealedSecret →
  `grafana-admin-credentials` Secret reproduced → Grafana admin password identical →
  Mac's basic-auth still valid. **Zero extra steps beyond the master-key restore.**

### 2. ArgoCD — Bitwarden-seated `argocd-secret` (mirror #181/#182)

- Add `//tools/gitops:argocd-secret-backup` / `:argocd-secret-restore`, a script
  modeled directly on `sealed_secrets_keys.sh` (same Bitwarden auto-unlock, mktemp,
  idempotent attachment). It backs up / restores the `argocd-secret` (ns `argocd`),
  which carries `server.secretkey` (stable signing key) + `accounts.mcp.tokens`
  (the token-id seed) + admin password. Bitwarden item: a new Secure Note,
  e.g. **"dev-local argocd-secret (server.secretkey + mcp token)"**.
- Reinstall flow: pulumi installs ArgoCD (random secret) →
  `bazel run //tools/gitops:argocd-secret-restore` overwrites it with the backed-up
  one → restart `argocd-server`. The Mac's fixed JWT (signed by the restored
  `server.secretkey`, jti present in the restored `accounts.mcp.tokens`) validates.
- The `mcp` **account** itself (apiKey, `role:admin`) is in `argocd-cm` via
  `pkg/applications/argocd.go` (+ gitignored `Pulumi.local.yaml`); that change still
  needs committing (the argocd.go part).
- Why not pulumi-config injection from Bitwarden (the considered alternative)? It works
  but means surgery on `argocd.go`/the pulumi wrapper and `configs.secret` handling;
  the backup/restore target reuses a merged, proven pattern with no chart changes and
  lower lockout risk. (Recorded as an open question in case you prefer injection.)

### 3. Mac-side Claude config (set once, never changes)

- ArgoCD MCP (`claude_desktop_config.json`): `ARGOCD_API_TOKEN` = the fixed JWT.
- Grafana MCP (extension settings json): switch to `username`/`password` basic auth.

### 4. One-time bootstrap (correctness)

1. Set/restore a fixed `server.secretkey` in `argocd-secret`; restart argocd-server.
2. `argocd account generate-token --account mcp` → capture the JWT (→ Mac) and read
   back the resulting `accounts.mcp.tokens` (now baked into the backed-up secret).
3. `argocd-secret-backup` → Bitwarden. Seal the Grafana password. Commit manifests.
4. Verify both MCPs end-to-end, then `sealed-secrets-backup` so the master key is saved.

## Reinstall runbook

Lives at **`docs/sealed-secrets.md`** (SOP style; cross-links `docs/key-rotation.md`).
Steps: pulumi up → `sealed-secrets-restore` (master key) → wait for ArgoCD sync (Grafana
SealedSecret decrypts) → `argocd-secret-restore` + restart argocd-server → verify both
MCPs. Keep it short; it mostly points at the existing targets.

## Risks & mitigations

- **ArgoCD lockout / token invalidation** when overwriting `argocd-secret` on a live
  cluster. Mitigate: back up the live `argocd-secret` first; rehearse on a throwaway
  `kind` cluster; keep the current working token until the new one verifies.
- **Helm vs restored secret:** chart `create: true` re-owns `argocd-secret` on upgrade,
  but preserves existing `server.secretkey` (lookup) and ignores unmanaged keys
  (`accounts.mcp.tokens`) — so the restored values survive upgrades. Verify on staging.
- **Two Bitwarden roots of trust** (master key + argocd-secret). Acceptable (personal
  vault); documented.
- **Grafana password change** is a live mutation on first sync — update the Mac config
  in the same change.

## Remaining work checklist

- [ ] Grafana: seal admin password, switch chart to `admin.existingSecret`, drop the
  runtime SA, point MCP at basic auth.
- [ ] ArgoCD: `argocd-secret-backup`/`-restore` bazel script; set fixed `server.secretkey`,
  mint+seed the mcp token, back up to Bitwarden; point MCP at the fixed JWT.
- [ ] Commit the `mcp` account change in `argocd.go`.
- [ ] Write `docs/sealed-secrets.md` runbook.
- [ ] Verify both MCPs after a simulated reinstall (staging).

## Out of scope / future
- Migrating the remaining plaintext/inline secrets beyond these two.
- Fixing pre-existing `argocd/grafana-db` OutOfSync.

## Open questions
1. **Phase it** (ArgoCD first, Grafana second) or land together?
2. **ArgoCD secret mechanism:** Bitwarden backup/restore target (recommended) vs
   pulumi-config injection from Bitwarden?
3. **Staging:** rehearse on a throwaway `kind` cluster before touching live ArgoCD?
4. **Grafana identity:** reuse `admin` (simplest) vs a dedicated user (Grafana OSS can't
   provision non-admin users declaratively)?
