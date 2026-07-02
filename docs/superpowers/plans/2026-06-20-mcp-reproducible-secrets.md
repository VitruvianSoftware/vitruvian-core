# MCP Reproducible Secrets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ArgoCD and Grafana MCP servers in Claude Desktop keep working after a full cluster + app reinstall, with the Mac config unchanged and at most a couple of `bazel run` restore steps.

**Architecture:** Build on the merged sealed-secrets stack (#174–#185). Grafana (an ArgoCD-managed app) gets a sealed admin password consumed via `admin.existingSecret`; the MCP uses basic auth. ArgoCD (the pulumi bootstrap, which can't depend on the ArgoCD-managed sealed-secrets controller) gets its `argocd-secret` — carrying the existing, still-valid `server.secretkey` + `accounts.mcp.tokens` — backed up to Bitwarden and restored on reinstall, mirroring the merged `//tools/gitops:sealed-secrets-*` targets. The existing Mac-side ArgoCD JWT stays valid because the same `server.secretkey` + token seed are restored.

**Tech Stack:** Bazel (sh_binary wrappers), bash, kubectl, kubeseal (Bitnami sealed-secrets), `bw` (Bitwarden CLI), Grafana Helm chart 10.5.15, ArgoCD (pulumi `dev-local`), `jq`.

## Global Constraints

- Bazel monorepo: drive all tooling through bazel targets, never raw CLIs where a target exists (`//tools/gitops:*`, `//infrastructure/pulumi/platform/dev-local:*`).
- `KUBECONFIG=$HOME/.kube/cluster.yaml`, context `default` (the gitops/pulumi wrappers default to this; standalone `kubectl`/`argocd` calls must set it).
- Sealed-secrets controller: name `sealed-secrets-controller`, namespace `sealed-secrets`. kubeseal must target it: `--controller-name sealed-secrets-controller --controller-namespace sealed-secrets --format yaml`.
- NEVER commit plaintext secrets or the master key. Only `SealedSecret`s (encrypted) go in git. Bitwarden holds the master key and the `argocd-secret` backup.
- Bitwarden: `bw login` once beforehand; targets auto-unlock (prompt / `$BW_PASSWORD` / `$BW_SESSION`).
- Branch first (do not work on `main`). All work on `feat/mcp-reproducible-secrets`.
- Commit messages end with the Co-Authored-By trailer.

---

## Phase 0 — Make the `mcp` ArgoCD account reproducible from git

### Task 0: Branch + commit the `mcp` account mechanism

**Files:**
- Modify (already edited in tree): `infrastructure/pulumi/platform/dev-local/pkg/applications/argocd.go`
- Modify (already edited in tree): `infrastructure/pulumi/platform/dev-local/Pulumi.example.yaml`

**Interfaces:**
- Produces: argo-cd Helm values gain `configs.cm.accounts.<name>: apiKey` + RBAC `g, <name>, role:admin`, gated on `argocd_api_account` (default `""`). Enablement (`monorepo:argocd_api_account: mcp`) lives in the gitignored `Pulumi.local.yaml` on this machine — intentional; the repo convention gitignores `Pulumi.*.yaml`.

- [ ] **Step 1: Create the working branch**

```bash
cd /Users/james/Workspace/gh/application/vitruvian/vitruvian-core
git checkout -b feat/mcp-reproducible-secrets
```

- [ ] **Step 2: Verify the pulumi program still compiles**

Run: `GOWORK=off go -C infrastructure/pulumi/platform/dev-local build ./...`
Expected: no output, exit 0.

- [ ] **Step 3: Commit the mechanism (not the gitignored stack config)**

```bash
git add infrastructure/pulumi/platform/dev-local/pkg/applications/argocd.go \
        infrastructure/pulumi/platform/dev-local/Pulumi.example.yaml
git commit -m "feat(infra): config-driven argocd apiKey account for MCP access

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 4: Confirm Pulumi.local.yaml is NOT staged (gitignored, local only)**

Run: `git status --short infrastructure/pulumi/platform/dev-local/Pulumi.local.yaml`
Expected: empty output (ignored).

---

## Phase 1 — Grafana: sealed admin password + MCP basic auth

### Task 1: Seal a strong Grafana admin password

**Files:**
- Create: `gitops/argocd/platform/sealed-secrets-manifests/grafana-admin-credentials.sealedsecret.yaml`
- Reference (pattern): `gitops/argocd/platform/sealed-secrets-manifests/grafana-db-credentials.sealedsecret.yaml`

**Interfaces:**
- Produces: a `SealedSecret` named `grafana-admin-credentials` in ns `grafana` whose decrypted `Secret` has keys `admin-user` and `admin-password`.

- [ ] **Step 1: Generate a strong password and stash it for later steps**

```bash
cd /Users/james/Workspace/gh/application/vitruvian/vitruvian-core
GRAFANA_ADMIN_PW="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)"
printf '%s' "$GRAFANA_ADMIN_PW" > /tmp/grafana_admin_pw   # consumed in Task 3/4, deleted in Task 4
echo "generated password length: ${#GRAFANA_ADMIN_PW}"
```
Expected: length ~24. (Keep `/tmp/grafana_admin_pw` until Task 4.)

- [ ] **Step 2: Seal it into a SealedSecret manifest**

```bash
kubectl --kubeconfig "$HOME/.kube/cluster.yaml" create secret generic grafana-admin-credentials \
  -n grafana \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_ADMIN_PW" \
  --dry-run=client -o yaml \
| bazel run //tools/gitops:kubeseal -- \
    --controller-name sealed-secrets-controller \
    --controller-namespace sealed-secrets \
    --format yaml \
> gitops/argocd/platform/sealed-secrets-manifests/grafana-admin-credentials.sealedsecret.yaml
```

- [ ] **Step 3: Verify it is a valid SealedSecret (encrypted, correct name/ns)**

Run:
```bash
grep -E "kind: SealedSecret|name: grafana-admin-credentials|namespace: grafana" \
  gitops/argocd/platform/sealed-secrets-manifests/grafana-admin-credentials.sealedsecret.yaml
```
Expected: all three lines present. Confirm `encryptedData:` has `admin-user`/`admin-password` and NO plaintext password appears.

- [ ] **Step 4: Prepend the repo license header**

Copy the 19-line MIT header block from `grafana-db-credentials.sealedsecret.yaml` to the top of the new file (match the existing manifests exactly).

- [ ] **Step 5: Commit**

```bash
git add gitops/argocd/platform/sealed-secrets-manifests/grafana-admin-credentials.sealedsecret.yaml
git commit -m "feat(gitops): seal grafana admin credentials

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 2: Point the Grafana chart at the sealed secret

**Files:**
- Modify: `gitops/argocd/platform/grafana/applicationset.yaml:71`

**Interfaces:**
- Consumes: `grafana-admin-credentials` Secret (Task 1).

- [ ] **Step 1: Replace the plaintext adminPassword with existingSecret**

Replace the line `adminPassword: admin` (line 71, under `helm.values`) with:

```yaml
            admin:
              existingSecret: grafana-admin-credentials
              userKey: admin-user
              passwordKey: admin-password
```
(Preserve the surrounding YAML indentation — it sits at the same level as `replicas:`.)

- [ ] **Step 2: Validate YAML parses**

Run: `python3 -c 'import yaml,sys; list(yaml.safe_load_all(open("gitops/argocd/platform/grafana/applicationset.yaml")))' && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add gitops/argocd/platform/grafana/applicationset.yaml
git commit -m "feat(gitops): grafana uses sealed admin credentials (drop plaintext admin/admin)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 3: Apply to the cluster and verify the new password works

**Files:** none (cluster operation).

- [ ] **Step 1: Apply the SealedSecret and sync grafana**

```bash
export KUBECONFIG="$HOME/.kube/cluster.yaml"
bazel run //tools/gitops:apply -- -f gitops/argocd/platform/sealed-secrets-manifests/grafana-admin-credentials.sealedsecret.yaml
argocd app sync grafana --grpc-web    # or wait for auto-sync
```

- [ ] **Step 2: Verify the controller materialized the Secret with the new password**

Run:
```bash
kubectl -n grafana get secret grafana-admin-credentials \
  -o jsonpath='{.data.admin-password}' | base64 -d | diff - /tmp/grafana_admin_pw && echo MATCH
```
Expected: `MATCH`.

- [ ] **Step 3: Verify Grafana actually accepts the new admin password**

Run:
```bash
curl -sS -u "admin:$(cat /tmp/grafana_admin_pw)" https://grafana.lab.ipv1337.dev/api/org \
  | jq -e '.id==1' && echo LOGIN_OK
```
Expected: `LOGIN_OK`. (If Grafana hasn't rolled the new password yet, `kubectl -n grafana rollout restart deploy grafana` and retry.)

### Task 4: Switch the Grafana MCP to basic auth + clean up the runtime SA

**Files:**
- Modify: `~/Library/Application Support/Claude/Claude Extensions Settings/ant.dir.gh.grafana.grafana-mcp.json`

- [ ] **Step 1: Back up and rewrite the extension settings to basic auth**

```bash
SET="$HOME/Library/Application Support/Claude/Claude Extensions Settings/ant.dir.gh.grafana.grafana-mcp.json"
cp "$SET" "$SET.bak.$(date +%Y%m%d-%H%M%S)"
GRAFANA_ADMIN_PW="$(cat /tmp/grafana_admin_pw)" SET_PATH="$SET" python3 - <<'PY'
import json,os
p=os.environ["SET_PATH"]; d=json.load(open(p))
uc=d.setdefault("userConfig",{})
uc["grafana_url"]="https://grafana.lab.ipv1337.dev"
uc["username"]="admin"
uc["password"]=os.environ["GRAFANA_ADMIN_PW"]
uc.pop("service_account_token",None)
d["isEnabled"]=True
json.dump(d,open(p,"w"),indent=2); open(p,"a").write("\n")
print("grafana MCP userConfig keys:",sorted(uc.keys()))
PY
```
Expected: keys `['grafana_url','password','username']`.

- [ ] **Step 2: Smoke-test the MCP binary with basic auth**

Run the stdio handshake against `…/Claude Extensions/ant.dir.gh.grafana.grafana-mcp/server/darwin-arm64/mcp-grafana` with `GRAFANA_URL`, `GRAFANA_USERNAME=admin`, `GRAFANA_PASSWORD=$(cat /tmp/grafana_admin_pw)` (reuse the Phase-earlier python smoke harness): initialize → tools/list → call `list_datasources`.
Expected: initialize OK, ~57 tools, `list_datasources` returns the Prometheus/Tempo datasources.

- [ ] **Step 3: Delete the now-unneeded runtime service account**

```bash
export KUBECONFIG="$HOME/.kube/cluster.yaml"
PW="$(cat /tmp/grafana_admin_pw)"
curl -sS -u "admin:$PW" -X DELETE https://grafana.lab.ipv1337.dev/api/serviceaccounts/34 ; echo
rm -f /tmp/grafana_admin_pw
```
Expected: deletion acknowledged; temp password file removed.

- [ ] **Step 4: (No commit — Mac-side config is not in the repo.)** Note in the runbook (Task 8) that the Grafana MCP password is the sealed `grafana-admin-credentials`.

---

## Phase 2 — ArgoCD: back up `argocd-secret` to Bitwarden + reinstall rehearsal

### Task 5: Add `argocd-secret` backup/restore/verify bazel targets

**Files:**
- Create: `tools/gitops/argocd_secret.sh`
- Modify: `tools/gitops/BUILD`
- Reference (pattern): `tools/gitops/sealed_secrets_keys.sh` (mirror its bw auto-unlock, traps, idempotent attachment, verify)

**Interfaces:**
- Produces: `//tools/gitops:argocd-secret-backup`, `:argocd-secret-restore`, `:argocd-secret-verify`. Backup stores a metadata-stripped `argocd-secret` YAML as a Bitwarden attachment `argocd-secret.yaml` on item `dev-local argocd-secret (server.secretkey + mcp token)`.

- [ ] **Step 1: Write the script**

Create `tools/gitops/argocd_secret.sh` (prepend the standard 19-line MIT header), body:

```bash
set -euo pipefail
SUBCMD="${1:?usage: argocd-secret-{backup|restore|verify}}"; shift || true
: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"; export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"
NS="${ARGOCD_NAMESPACE:-argocd}"
SECRET="argocd-secret"
SERVER_DEPLOY="${ARGOCD_SERVER_DEPLOY:-argocd-server}"
ITEM="${ARGOCD_BW_ITEM:-dev-local argocd-secret (server.secretkey + mcp token)}"
FILE="argocd-secret.yaml"
for t in kubectl bw jq; do command -v "$t" >/dev/null 2>&1 || { echo "ERROR: '$t' not found." >&2; exit 1; }; done
# --- bw auto-unlock (identical contract to sealed_secrets_keys.sh) ---
ss_status(){ bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo unknown; }
if [ "$(ss_status)" != "unlocked" ]; then
  case "$(ss_status)" in
    unauthenticated) echo "ERROR: run 'bw login' once, then re-run." >&2; exit 1 ;;
  esac
  if [ -n "${BW_PASSWORD:-}" ]; then BW_SESSION="$(bw unlock --passwordenv BW_PASSWORD --raw)";
  elif [ -t 0 ]; then echo "Unlocking Bitwarden — enter master password:" >&2; BW_SESSION="$(bw unlock --raw)";
  else echo "ERROR: bw locked, no TTY. export BW_SESSION or BW_PASSWORD." >&2; exit 1; fi
  export BW_SESSION
fi
tmpd="$(mktemp -d -t argocdsec.XXXXXX)"; trap 'rm -rf "$tmpd"' EXIT; F="$tmpd/$FILE"
item_id(){ bw get item "$ITEM" 2>/dev/null | jq -r '.id // empty' 2>/dev/null; }
strip(){ # remove cluster-volatile metadata so `kubectl apply` works on a fresh secret
  python3 - "$1" <<'PY'
import sys,yaml
d=yaml.safe_load(open(sys.argv[1]))
m=d.get("metadata",{})
for k in ("resourceVersion","uid","creationTimestamp","managedFields","ownerReferences","generation","selfLink"): m.pop(k,None)
ann=m.get("annotations",{}); ann.pop("kubectl.kubernetes.io/last-applied-configuration",None)
d.pop("status",None)
yaml.safe_dump(d,open(sys.argv[1],"w"))
PY
}
case "$SUBCMD" in
  backup)
    kubectl --context "$KCTX" -n "$NS" get secret "$SECRET" -o yaml > "$F"
    grep -q "kind: Secret" "$F" || { echo "ERROR: $SECRET not found in ns $NS." >&2; exit 1; }
    grep -q "server.secretkey" "$F" || { echo "ERROR: $SECRET has no server.secretkey." >&2; exit 1; }
    strip "$F"
    bw sync >/dev/null 2>&1 || true; id="$(item_id)"
    if [ -z "$id" ]; then
      id="$(jq -n --arg n "$ITEM" '{type:2,secureNote:{type:0},name:$n,notes:"ArgoCD argocd-secret (server.secretkey + accounts.mcp.tokens). Restore after a reinstall: bazel run //tools/gitops:argocd-secret-restore"}' | bw encode | bw create item | jq -r '.id')"
      echo "Created Bitwarden item: $ITEM"
    fi
    for att in $(bw get item "$id" | jq -r --arg f "$FILE" '.attachments[]? | select(.fileName==$f) | .id'); do
      bw delete attachment "$att" --itemid "$id" >/dev/null 2>&1 || true; done
    bw create attachment --file "$F" --itemid "$id" >/dev/null; bw sync >/dev/null 2>&1 || true
    echo "✓ Backed up $SECRET to Bitwarden item '$ITEM' (attachment: $FILE)."
    ;;
  restore)
    id="$(item_id)"; [ -n "$id" ] || { echo "ERROR: item '$ITEM' not found." >&2; exit 1; }
    bw sync >/dev/null 2>&1 || true
    bw get attachment "$FILE" --itemid "$id" --output "$F" >/dev/null
    grep -q "server.secretkey" "$F" || { echo "ERROR: attachment '$FILE' invalid." >&2; exit 1; }
    kubectl --context "$KCTX" -n "$NS" apply -f "$F"
    kubectl --context "$KCTX" -n "$NS" rollout restart deployment "$SERVER_DEPLOY"
    echo "✓ Restored $SECRET + restarted $SERVER_DEPLOY. The existing MCP JWT will validate."
    ;;
  verify)
    id="$(item_id)"; [ -n "$id" ] || { echo "✗ No item '$ITEM' — nothing backed up." >&2; exit 1; }
    bw sync >/dev/null 2>&1 || true
    bw get attachment "$FILE" --itemid "$id" --output "$F" >/dev/null 2>&1 || { echo "✗ no '$FILE' attachment." >&2; exit 1; }
    grep -q "server.secretkey" "$F" && grep -q "accounts.mcp.tokens" "$F" \
      && echo "✓ Backup OK: '$ITEM' holds $FILE with server.secretkey + accounts.mcp.tokens." \
      || { echo "✗ attachment present but missing required keys." >&2; exit 1; }
    ;;
  *) echo "ERROR: unknown subcommand '$SUBCMD' (backup|restore|verify)" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Add the three sh_binary targets to `tools/gitops/BUILD`**

```python
sh_binary(
    name = "argocd-secret-backup",
    srcs = ["argocd_secret.sh"],
    args = ["backup"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "argocd-secret-restore",
    srcs = ["argocd_secret.sh"],
    args = ["restore"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "argocd-secret-verify",
    srcs = ["argocd_secret.sh"],
    args = ["verify"],
    visibility = ["//visibility:public"],
)
```

- [ ] **Step 3: Build the targets**

Run: `bazel build //tools/gitops:argocd-secret-backup //tools/gitops:argocd-secret-restore //tools/gitops:argocd-secret-verify`
Expected: `Build completed successfully`.

- [ ] **Step 4: Commit**

```bash
git add tools/gitops/argocd_secret.sh tools/gitops/BUILD
git commit -m "feat(gitops): bazel backup/restore/verify of argocd-secret via Bitwarden

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 6: Back up the live `argocd-secret` and verify

**Files:** none (Bitwarden + cluster, read-only on cluster).

- [ ] **Step 1: Confirm the live secret holds the token seed (sanity)**

```bash
export KUBECONFIG="$HOME/.kube/cluster.yaml"
kubectl -n argocd get secret argocd-secret -o jsonpath='{.data.accounts\.mcp\.tokens}' | base64 -d; echo
```
Expected: a JSON array containing the mcp token id `768b7b3b-...` (matches the Mac's JWT).

- [ ] **Step 2: Back up to Bitwarden**

Run: `bazel run //tools/gitops:argocd-secret-backup` (enter bw master password if prompted).
Expected: `✓ Backed up argocd-secret to Bitwarden item ...`.

- [ ] **Step 3: Verify the backup is real**

Run: `bazel run //tools/gitops:argocd-secret-verify`
Expected: `✓ Backup OK: ... server.secretkey + accounts.mcp.tokens.`

### Task 7: Rehearse a reinstall restore on a throwaway `kind` cluster

**Files:** none (ephemeral cluster).

- [ ] **Step 1: Stand up kind + install the same ArgoCD chart**

```bash
kind create cluster --name argocd-rehearsal
# Install argo-cd chart 9.5.22 with configs.cm accounts.mcp: apiKey + rbac g, mcp, role:admin
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd --version 9.5.22 -n argocd --create-namespace \
  --set configs.params."server\.insecure"=true \
  --set-string configs.cm."accounts\.mcp"=apiKey \
  --set-string configs.rbac."policy\.csv"=$'g, mcp, role:admin'
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
```

- [ ] **Step 2: Restore the backed-up argocd-secret into kind**

```bash
KUBE_CONTEXT="kind-argocd-rehearsal" bazel run //tools/gitops:argocd-secret-restore
```
Expected: `✓ Restored argocd-secret + restarted argocd-server`.

- [ ] **Step 3: Prove the EXISTING Mac JWT validates against the rehearsal cluster**

```bash
TOKEN="$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/Library/Application Support/Claude/claude_desktop_config.json")))["mcpServers"]["argocd-mcp"]["env"]["ARGOCD_API_TOKEN"])')"
kubectl -n argocd port-forward svc/argocd-server 8081:443 >/tmp/pf.log 2>&1 &
PF=$!; sleep 3
argocd account get-user-info --auth-token "$TOKEN" --server localhost:8081 --grpc-web --insecure 2>&1 | grep -E "Logged In|Username"
kill $PF
```
Expected: `Logged In: true`, `Username: mcp` — proving a fresh install + restore makes the unchanged Mac token valid.

- [ ] **Step 4: Tear down**

```bash
kind delete cluster --name argocd-rehearsal
```

> **Note:** The live ArgoCD MCP config on the Mac needs **no change** — its JWT already matches the backed-up `server.secretkey` + token seed. This is why Phase 2 carries minimal lockout risk (no live `argocd-secret` overwrite; we only back it up).

---

## Phase 3 — Runbook + final verification

### Task 8: Write the reinstall runbook

**Files:**
- Create: `docs/sealed-secrets.md`
- Reference (style): `docs/key-rotation.md`

- [ ] **Step 1: Write `docs/sealed-secrets.md`** (SOP style) covering:
  - What the sealed-secrets master key is and why it lives in Bitwarden (item `dev-local sealed-secrets controller keys`).
  - The two Bitwarden-backed artifacts: master key + `argocd-secret`.
  - **Reinstall order** (exact commands):
    1. `bazel run //infrastructure/pulumi/platform/dev-local:up -- --stack local --yes` (with `KUBECONFIG=$HOME/.kube/cluster.yaml`)
    2. `bazel run //tools/gitops:sealed-secrets-restore` (master key) → controller decrypts all SealedSecrets (incl. `grafana-admin-credentials`).
    3. Wait for ArgoCD to sync Grafana; confirm `grafana-admin-credentials` Secret exists.
    4. `bazel run //tools/gitops:argocd-secret-restore` → restart argocd-server.
    5. Verify both MCPs (commands below).
  - **Verify MCPs:** ArgoCD `argocd account get-user-info --auth-token <mac JWT> --server argocd.lab.ipv1337.dev --grpc-web` → `Username: mcp`; Grafana `curl -u admin:<sealed pw> https://grafana.lab.ipv1337.dev/api/org`.
  - **Maintenance:** re-run `argocd-secret-backup` if the mcp token is ever regenerated; re-seal `grafana-admin-credentials` if the password changes; keep `sealed-secrets-backup` current.
  - Cross-link `docs/key-rotation.md`.

- [ ] **Step 2: Add a nav entry** if `mkdocs.yml` enumerates docs (check `grep -n sealed mkdocs.yml`; add under the infrastructure/ops section if a nav exists).

- [ ] **Step 3: Commit**

```bash
git add docs/sealed-secrets.md mkdocs.yml
git commit -m "docs: sealed-secrets + MCP reinstall runbook

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task 9: End-to-end verification + open the PR

- [ ] **Step 1: Restart Claude Desktop** (Cmd-Q) and confirm both MCP servers connect (ArgoCD 15 tools, Grafana 57 tools).
- [ ] **Step 2: Re-affirm both auth paths from the CLI** (the two verify commands from Task 8).
- [ ] **Step 3: Push the branch and open a PR**

```bash
git push -u origin feat/mcp-reproducible-secrets
gh pr create --fill --title "feat: reproducible ArgoCD + Grafana MCP credentials across reinstall"
```

---

## Self-review notes

- **Spec coverage:** Grafana sealed admin (Tasks 1–4) ✓; ArgoCD argocd-secret Bitwarden flow (Tasks 5–7) ✓; mcp account committed (Task 0) ✓; runbook (Task 8) ✓; staging rehearsal (Task 7) ✓; Mac config (Tasks 4, and ArgoCD unchanged by design) ✓.
- **Deviation from spec v2:** spec assumed we'd set a *new* fixed `server.secretkey` and re-mint the token; this plan instead backs up the *existing* live `argocd-secret` (same effect, zero live mutation, existing Mac JWT stays valid). Lower risk — update spec §2/§4 to match if desired.
- **Open question still pending user confirmation:** none blocking; defaults applied (Bitwarden backup/restore for ArgoCD; Grafana reuses `admin`; kind rehearsal; Grafana-first phasing).
