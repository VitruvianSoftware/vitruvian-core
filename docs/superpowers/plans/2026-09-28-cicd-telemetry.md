# CI Pipeline Telemetry (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub Actions runs of `VitruvianSoftware/vitruvian-core` show up as traces in Tempo and as duration/failure metrics in Prometheus, with a Grafana "CI pipelines" dashboard, via a collector run by the OpenTelemetry operator.

**Architecture:** A signed GitHub webhook reaches `github-otel.ipv1337.dev` through the existing Cloudflare tunnel and Envoy gateway (only `POST /events`, rate limited). An operator-managed `OpenTelemetryCollector` in namespace `cicd-telemetry` validates the signature, turns runs into traces, deletes committer name/email, derives metrics with `spanmetrics`, and exports straight to Tempo and both Prometheus replicas. The webhook secret is generated once by a bazel tool that seals it into git and stores it as a GitHub secret; repo-config (Pulumi) declares the webhook.

**Tech Stack:** OpenTelemetry Collector contrib 0.160.0 (GitHub receiver, OTTL transform, spanmetrics), OpenTelemetry operator 0.159 (`opentelemetry.io/v1beta1`), Argo CD, Envoy Gateway 1.9.2 (`gateway.envoyproxy.io/v1alpha1`), Cilium (`cilium.io/v2`), SealedSecrets, Pulumi Go (`pulumi-github` v6.15.0), Grafana dashboards-as-code, Bazel (`rules_shell`, `aspect_rules_py`, `@pip//pyyaml`).

**Spec:** `docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md`

## Global Constraints

- Collector image: `otel/opentelemetry-collector-contrib:0.160.0` (same version as the existing collector).
- Namespace: `cicd-telemetry`. Collector name: `github-actions` (Service becomes `github-actions-collector`).
- Public hostname: `github-otel.ipv1337.dev`; only `POST /events` is routed.
- Webhook listen address `0.0.0.0:19418`, path `/events`, health path `/health`, `service_name: github-actions`, `include_span_events: false`.
- Secret: Kubernetes Secret `cicd-telemetry/github-otel-webhook`, key `GITHUB_WEBHOOK_SECRET`; GitHub repo secret `OTEL_GITHUB_WEBHOOK_SECRET` (Actions **and** Dependabot stores).
- Delete resource attributes `vcs.ref.head.revision.author.name` and `vcs.ref.head.revision.author.email`.
- spanmetrics namespace `cicd`, unit seconds, dimensions exactly: `cicd.pipeline.name`, `ci.span.type`, `ci.trigger`, `ci.retry` (plus built-in span name / kind / status code). No branch name as a label.
- Traces → `tempo.opentelemetry.svc.cluster.local:4317` (TLS off). Metrics → both `prometheus-server-{0,1}.prometheus-server-headless.monitoring.svc.cluster.local:9090/api/v1/write`.
- Two replicas, required pod anti-affinity by hostname, PDB `minAvailable: 1`, `nodeSelector: node.ipv1337.dev/link: wired`.
- Network policy uses label selectors / entities only — **never node-IP `ipBlock`s** (they don't match under Cilium; #2565).
- Webhook: repo `vitruvian-core` only, events `workflow_run` + `workflow_job` only, `content_type: json`, `insecure_ssl: false`.
- Secrets are never printed, logged, or put on a command line.
- Every new committed file carries the repo's MIT license header (license-check gate), except JSON dashboards (existing ones have none).
- Infra changes land through PRs and CI only — never a local `pulumi up` or `kubectl apply` of these manifests.

## Review Focus

1. **Empty webhook secret.** The receiver's check silently accepts every request when the secret is empty. Expect: the pod does not start without the Secret key, and an unsigned request gets 400. Pinned by Task 2's config test (`secretKeyRef`, `optional: false`) and Task 3's smoke check.
2. **Rotation tool fails halfway.** If `kubeseal` or `gh` fails, git and GitHub must not end up holding different secrets. Expect: nothing written, or a clear "re-run" message with no sealed file left behind. Pinned by Task 1 tests.
3. **Label explosion.** A branch name or run ID used as a metric label would create one series per PR and swamp Prometheus. Expect: the spanmetrics dimensions are exactly the approved four. Pinned by Task 2's config test.
4. **Personal data.** Committer email must not reach Tempo. Expect: both author attributes deleted before export. Pinned by Task 2's config test, and checked live in Task 3.
5. **Dependabot PR previews.** If the secret is missing from the Dependabot store, repo-config previews on Dependabot PRs render the webhook as a DELETE. Expect: the tool writes both stores. Pinned by Task 1 tests.

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/gitops/rotate_github_otel_webhook_secret.sh` | Generate the secret; seal it; store it in both GitHub stores; never print it |
| `tools/gitops/rotate_github_otel_webhook_secret_test.sh` | Hermetic test (fake `kubectl`/`kubeseal`/`gh`) |
| `tools/gitops/cicd_telemetry_smoke.sh` | Live gate: unsigned → 400; signed sample event → trace + metric |
| `tools/gitops/cicd_telemetry_smoke_test.sh` | Hermetic test of the HMAC signing (GitHub's published test vector) |
| `tools/gitops/BUILD` | Two `sh_binary` + two `sh_test` targets |
| `gitops/argocd/platform/sealed-secrets-manifests/github-otel-webhook.sealedsecret.yaml` | Generated by the tool (Task 1, operator step) |
| `gitops/argocd/platform/cicd-telemetry/collector.yaml` | `OpenTelemetryCollector` resource |
| `gitops/argocd/platform/cicd-telemetry/network-policy.yaml` | `CiliumNetworkPolicy` (ingress + egress) |
| `gitops/argocd/platform/cicd-telemetry/httproute.yaml` | Public route, `POST /events` only |
| `gitops/argocd/platform/cicd-telemetry/rate-limit.yaml` | `BackendTrafficPolicy` local rate limit |
| `gitops/argocd/platform/cicd-telemetry/dnsendpoint.yaml` | CNAME to the Cloudflare tunnel |
| `gitops/argocd/platform/cicd-telemetry/BUILD` | filegroup + `py_test` |
| `gitops/argocd/platform/cicd-telemetry/collector_config_test.py` | Invariant test over `collector.yaml` |
| `gitops/argocd/applications/cicd-telemetry.yaml` | Argo CD Application (directory source) |
| `infrastructure/pulumi/platform/repo-config/internal/cicd_webhook/webhook.go` | Webhook args + `Manage` |
| `infrastructure/pulumi/platform/repo-config/internal/cicd_webhook/webhook_test.go` | Pins URL, events, content type, TLS, repo |
| `infrastructure/pulumi/platform/repo-config/main.go` | Call `cicd_webhook.Manage` |
| `.github/workflows/_repo-config-apply.yaml`, `_repo-config-preview.yaml` | Pass `OTEL_GITHUB_WEBHOOK_SECRET` to Pulumi |
| `gitops/argocd/platform/grafana-dashboards/ci-pipelines.json` | Dashboard |
| `gitops/argocd/platform/grafana-dashboards/kustomization.yaml` | Register the dashboard |
| `gitops/argocd/platform/grafana-dashboards/tests/tier1_schema_test.py`, `tier2_promql_test.py` | Add `ci-pipelines.json` to `TARGET_DASHBOARDS` |
| docs: `docs/operations/key-rotation.md`, `docs/reference/bazel-targets.md` | Rows for the two new targets |

PR boundaries: **PR 1** = Task 1. **PR 2** = Tasks 2–3. **PR 3** = Task 4. **PR 4** = Task 5. Each PR's gate must pass before the next PR is opened.

---

### Task 1: Webhook secret tool (PR 1)

**Files:**
- Create: `tools/gitops/rotate_github_otel_webhook_secret.sh`
- Create: `tools/gitops/rotate_github_otel_webhook_secret_test.sh`
- Modify: `tools/gitops/BUILD` (append targets)
- Modify: `docs/operations/key-rotation.md` (table row), `docs/reference/bazel-targets.md` (row)
- Generated (operator step): `gitops/argocd/platform/sealed-secrets-manifests/github-otel-webhook.sealedsecret.yaml`

**Interfaces:**
- Produces: Secret `cicd-telemetry/github-otel-webhook` key `GITHUB_WEBHOOK_SECRET` (once the namespace exists); GitHub secret `OTEL_GITHUB_WEBHOOK_SECRET` in Actions + Dependabot stores. Target `//tools/gitops:rotate-github-otel-webhook-secret`.
- Env overrides (for tests): `GH_REPO` (default `VitruvianSoftware/vitruvian-core`), `KUBECONFIG`, `KUBE_CONTEXT`.

- [ ] **Step 1: Write the failing test**

Create `tools/gitops/rotate_github_otel_webhook_secret_test.sh` (license header first, as in `ntfy_manage_users_test.sh`):

```bash
#!/usr/bin/env bash
# <MIT license header, copied verbatim from tools/gitops/ntfy_manage_users_test.sh>

# Hermetic test for rotate_github_otel_webhook_secret.sh: fake kubectl,
# kubeseal and gh on PATH, a throwaway workspace. The secret must be identical
# in the sealed file and both GitHub stores, must never reach stdout, and a
# failure must leave no sealed file behind.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rotate_github_otel_webhook_secret.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find rotate_github_otel_webhook_secret.sh" >&2; exit 1; }

PASS=0; FAIL=0
check() { if [ "$2" = "0" ]; then printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); else printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); fi; }
t() { if "$@"; then echo 0; else echo 1; fi; }

WORK="$(mktemp -d "${TEST_TMPDIR:-/tmp}/rotate-otel.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/bin" "${WORK}/ws/gitops/argocd/platform/sealed-secrets-manifests"
export W="${WORK}"
OUT_REL="gitops/argocd/platform/sealed-secrets-manifests/github-otel-webhook.sealedsecret.yaml"

# Fake kubectl: `create secret generic ... --from-file=KEY=/dev/stdin` -> a
# Secret manifest whose data carries the value (base64), as the real one does.
cat > "${WORK}/bin/kubectl" <<'FAKE'
#!/usr/bin/env bash
v="$(cat)"; printf '%s' "$v" > "${W}/kubectl-got"
printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: github-otel-webhook\n  namespace: cicd-telemetry\ndata:\n  GITHUB_WEBHOOK_SECRET: %s\n' "$(printf '%s' "$v" | base64 | tr -d '\n')"
FAKE
# Fake kubeseal: turns the Secret into a SealedSecret; "encrypts" by copying.
cat > "${WORK}/bin/kubeseal" <<'FAKE'
#!/usr/bin/env bash
[ "${FAKE_KUBESEAL_FAIL:-0}" = 1 ] && exit 1
sed 's/^kind: Secret/kind: SealedSecret/; s/^apiVersion: v1/apiVersion: bitnami.com\/v1alpha1/; s/^data:/spec:\n  encryptedData:/; s/^  GITHUB_WEBHOOK_SECRET:/    GITHUB_WEBHOOK_SECRET:/'
FAKE
cat > "${WORK}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "auth status"*) exit 0 ;;
  *"secret set"*)
    [ "${FAKE_GH_FAIL:-0}" = 1 ] && exit 1
    n=$(( $(ls "${W}"/gh-stdin.* 2>/dev/null | wc -l) + 1 ))
    cat > "${W}/gh-stdin.${n}"; echo "$*" >> "${W}/gh-log" ;;
  *) echo "fake gh: unexpected: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "${WORK}"/bin/*

run() { # -> OUT, RC
  rm -f "${WORK}"/gh-* "${WORK}/kubectl-got" "${WORK}/ws/${OUT_REL}"
  OUT="$(cd "${WORK}/ws" && PATH="${WORK}/bin:${PATH}" BUILD_WORKSPACE_DIRECTORY="${WORK}/ws" bash "${UNDER_TEST}" 2>&1)"; RC=$?
}

echo "rotate_github_otel_webhook_secret.sh"

run
check "succeeds" "$RC"
SECRET="$(cat "${WORK}/kubectl-got")"
check "secret is 64 hex chars" "$(t grep -qE '^[0-9a-f]{64}$' <<<"${SECRET}")"
check "sealed file written" "$(t [ -f "${WORK}/ws/${OUT_REL}" ])"
check "sealed file has the license header" "$(t grep -q 'Copyright (c) 2026 VitruvianSoftware' "${WORK}/ws/${OUT_REL}")"
check "sealed file targets cicd-telemetry/github-otel-webhook" "$(t grep -q 'namespace: cicd-telemetry' "${WORK}/ws/${OUT_REL}")"
check "Actions store got the same secret" "$(t cmp -s <(printf '%s' "${SECRET}") "${WORK}/gh-stdin.1")"
check "Dependabot store got the same secret" "$(t cmp -s <(printf '%s' "${SECRET}") "${WORK}/gh-stdin.2")"
check "Actions store name + repo" "$(t grep -qx 'secret set OTEL_GITHUB_WEBHOOK_SECRET --repo VitruvianSoftware/vitruvian-core' "${WORK}/gh-log")"
check "Dependabot store name + repo" "$(t grep -qx 'secret set OTEL_GITHUB_WEBHOOK_SECRET --repo VitruvianSoftware/vitruvian-core --app dependabot' "${WORK}/gh-log")"
check "secret never printed" "$(grep -qF "${SECRET}" <<<"${OUT}" && echo 1 || echo 0)"

FAKE_KUBESEAL_FAIL=1 run
check "kubeseal fails: exits non-zero" "$(t [ "$RC" != 0 ])"
check "kubeseal fails: nothing sent to GitHub" "$(t [ ! -e "${WORK}/gh-log" ])"
check "kubeseal fails: no sealed file" "$(t [ ! -e "${WORK}/ws/${OUT_REL}" ])"

FAKE_GH_FAIL=1 run
check "gh fails: exits non-zero" "$(t [ "$RC" != 0 ])"
check "gh fails: no sealed file (git and GitHub can't disagree)" "$(t [ ! -e "${WORK}/ws/${OUT_REL}" ])"

echo "${PASS} passed, ${FAIL} failed"
[ "${FAIL}" = 0 ]
```

Append to `tools/gitops/BUILD`:

```starlark
# Generate the GitHub -> CI-collector webhook secret and put it in both places,
# never printed: sealed into git for the collector (cicd-telemetry), and the
# GitHub secret OTEL_GITHUB_WEBHOOK_SECRET (Actions + Dependabot) that
# repo-config uses to declare the webhook. Re-run to rotate.
#   bazel run //tools/gitops:rotate-github-otel-webhook-secret
sh_binary(
    name = "rotate-github-otel-webhook-secret",
    srcs = ["rotate_github_otel_webhook_secret.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "rotate_github_otel_webhook_secret_test",
    size = "small",
    srcs = ["rotate_github_otel_webhook_secret_test.sh"],
    data = ["rotate_github_otel_webhook_secret.sh"],
)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bazel test //tools/gitops:rotate_github_otel_webhook_secret_test --test_output=errors`
Expected: FAIL with "cannot find rotate_github_otel_webhook_secret.sh".

- [ ] **Step 3: Write the tool**

Create `tools/gitops/rotate_github_otel_webhook_secret.sh` (license header, then):

```bash
#!/usr/bin/env bash
# <MIT license header, copied verbatim from tools/gitops/seal_alert_ntfy.sh>
# Generate the shared secret GitHub signs CI webhook deliveries with, and put
# it in both places that need it -- never printed, never on a command line:
#   1. sealed into gitops/.../sealed-secrets-manifests (Secret
#      cicd-telemetry/github-otel-webhook, key GITHUB_WEBHOOK_SECRET), which the
#      CI collector reads (spec: docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md);
#   2. the GitHub secret OTEL_GITHUB_WEBHOOK_SECRET, in BOTH the Actions store
#      (repo-config apply declares the webhook with it) and the Dependabot store
#      (so previews on Dependabot PRs don't render the webhook as a DELETE).
# Order: seal to a temp file, store in GitHub, and only then move the sealed
# file into git. A failure at any step leaves no sealed file, so git and
# GitHub can never hold different values. Re-run to rotate; commit the file
# via a PR, and the next repo-config apply updates GitHub's side.
#   bazel run //tools/gitops:rotate-github-otel-webhook-secret
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"
export KUBECONFIG
KCTX="${KUBE_CONTEXT:-default}"
GH_REPO="${GH_REPO:-VitruvianSoftware/vitruvian-core}"
NS=cicd-telemetry
SECRET=github-otel-webhook
KEY=GITHUB_WEBHOOK_SECRET
GH_SECRET=OTEL_GITHUB_WEBHOOK_SECRET
OUT="gitops/argocd/platform/sealed-secrets-manifests/${SECRET}.sealedsecret.yaml"
CTRL_NS="${SEALED_SECRETS_NAMESPACE:-sealed-secrets}"
CTRL_NAME="${SEALED_SECRETS_CONTROLLER:-sealed-secrets-controller}"

for c in kubectl kubeseal gh openssl; do
  command -v "$c" >/dev/null 2>&1 || { echo "ERROR: $c not found on PATH." >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not signed in -- run 'gh auth login'." >&2; exit 1; }
cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be run via 'bazel run', not 'bazel build'}"

VALUE="$(openssl rand -hex 32)"
[ "${#VALUE}" = 64 ] || { echo "ERROR: could not generate a secret." >&2; exit 1; }

TMP="$(mktemp "${TMPDIR:-/tmp}/github-otel-webhook.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<'HEADER'
<MIT license header lines, exactly as in seal_alert_ntfy.sh's HEADER heredoc>
HEADER
printf '%s' "$VALUE" \
  | kubectl --context "$KCTX" create secret generic "$SECRET" -n "$NS" \
      --dry-run=client --from-file="${KEY}=/dev/stdin" -o yaml \
  | kubeseal --format yaml --controller-namespace "$CTRL_NS" --controller-name "$CTRL_NAME" \
  >> "$TMP" || { echo "ERROR: sealing failed -- nothing was changed." >&2; exit 1; }
echo "✓ sealed (Secret ${NS}/${SECRET}, key ${KEY})"

for store in actions dependabot; do
  flag=(); [ "$store" = dependabot ] && flag=(--app dependabot)
  printf '%s' "$VALUE" | gh secret set "$GH_SECRET" --repo "$GH_REPO" "${flag[@]}" >/dev/null \
    || { echo "ERROR: could not store ${GH_SECRET} (${store}) -- no sealed file written; re-run." >&2; exit 1; }
  echo "✓ stored ${GH_SECRET} (${store} secrets)"
done
unset VALUE

mv "$TMP" "$OUT"
trap - EXIT
echo "✓ wrote ${OUT}"
echo "next: commit ${OUT} in a PR; repo-config's next apply updates the webhook."
```

(Replace the two `<MIT license header ...>` markers with the literal header lines; the test checks the `Copyright (c) 2026 VitruvianSoftware` line.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `bazel test //tools/gitops:rotate_github_otel_webhook_secret_test --test_output=all`
Expected: `15 passed, 0 failed`.

- [ ] **Step 5: Mutation check**

Temporarily move the `mv "$TMP" "$OUT"` line above the `for store` loop; re-run; expect `gh fails: no sealed file` to FAIL. Revert. Temporarily delete the dependabot store from the loop; expect the Dependabot checks to FAIL. Revert.

- [ ] **Step 6: Docs**

`docs/reference/bazel-targets.md`, after the `//tools/gitops:ntfy-rotate-ci-password` row:

```markdown
| `//tools/gitops:rotate-github-otel-webhook-secret` | Generate/rotate the GitHub → CI-collector webhook secret: sealed into git and stored as `OTEL_GITHUB_WEBHOOK_SECRET` (Actions + Dependabot); never printed |
```

`docs/operations/key-rotation.md`, in the secrets table after the `NTFY_GITHUB_ACTIONS_PASSWORD` row:

```markdown
| `OTEL_GITHUB_WEBHOOK_SECRET` | Signs GitHub's CI webhook deliveries to the CI collector | generated — rotate with `bazel run //tools/gitops:rotate-github-otel-webhook-secret`, commit the sealed file, and repo-config's next apply updates GitHub |
```

- [ ] **Step 7: Commit, PR, merge (PR 1)**

```bash
git add tools/gitops/rotate_github_otel_webhook_secret.sh tools/gitops/rotate_github_otel_webhook_secret_test.sh tools/gitops/BUILD docs/reference/bazel-targets.md docs/operations/key-rotation.md
git commit -m "feat(tools): generate the CI webhook secret with one bazel command"
```

Open the PR; merge when green.

- [ ] **Step 8: Run the tool once (operator step) and gate**

Run from an up-to-date checkout: `bazel run //tools/gitops:rotate-github-otel-webhook-secret`. Commit the generated sealed file on a new branch as its own tiny PR (or fold into PR 2).
Gate:
- `gh secret list -R VitruvianSoftware/vitruvian-core | grep OTEL_GITHUB_WEBHOOK_SECRET` and the same with `--app dependabot` both show it.
- `kubeseal --validate --controller-namespace sealed-secrets --controller-name sealed-secrets-controller < <sealed file>` exits 0.
- The in-cluster Secret is checked in Task 3 (the namespace only exists after PR 2).

---

### Task 2: CI collector and its public surface (PR 2)

**Files:**
- Create: `gitops/argocd/platform/cicd-telemetry/collector.yaml`
- Create: `gitops/argocd/platform/cicd-telemetry/network-policy.yaml`
- Create: `gitops/argocd/platform/cicd-telemetry/httproute.yaml`
- Create: `gitops/argocd/platform/cicd-telemetry/rate-limit.yaml`
- Create: `gitops/argocd/platform/cicd-telemetry/dnsendpoint.yaml`
- Create: `gitops/argocd/platform/cicd-telemetry/BUILD`
- Create: `gitops/argocd/platform/cicd-telemetry/collector_config_test.py`
- Create: `gitops/argocd/applications/cicd-telemetry.yaml`

**Interfaces:**
- Consumes: Secret `cicd-telemetry/github-otel-webhook` key `GITHUB_WEBHOOK_SECRET` (Task 1).
- Deliberate deviation from spec §3.4: no ingress rule for Prometheus scraping — the collector's own metrics aren't scraped in phase 1 (YAGNI); add one if that changes.
- Produces: Service `cicd-telemetry/github-actions-collector` port `19418` (`webhook`); public `https://github-otel.ipv1337.dev/events`; Prometheus metrics `cicd_duration_seconds_bucket|_sum|_count` and `cicd_calls_total` with labels `cicd_pipeline_name`, `ci_span_type`, `ci_trigger`, `ci_retry`, `span_name`, `span_kind`, `status_code`, `job="github-actions"`. Traces in Tempo with `service.name = github-actions`.

- [ ] **Step 1: Write the failing test**

Create `gitops/argocd/platform/cicd-telemetry/collector_config_test.py`:

```python
#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""Invariants of the CI collector that must never silently regress.

Spec: docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md
"""
import os
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


def load():
    with open(os.path.join(HERE, "collector.yaml")) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]
    (col,) = [d for d in docs if d["kind"] == "OpenTelemetryCollector"]
    return col


class CollectorConfigTest(unittest.TestCase):
    def setUp(self):
        self.col = load()
        self.cfg = self.col["spec"]["config"]
        self.gh = self.cfg["receivers"]["github"]

    def test_webhook_secret_comes_from_the_required_secret(self):
        # An empty secret makes the receiver accept EVERY request.
        self.assertEqual(self.gh["webhook"]["secret"], "${env:GITHUB_WEBHOOK_SECRET}")
        (env,) = [e for e in self.col["spec"]["env"] if e["name"] == "GITHUB_WEBHOOK_SECRET"]
        ref = env["valueFrom"]["secretKeyRef"]
        self.assertEqual((ref["name"], ref["key"]), ("github-otel-webhook", "GITHUB_WEBHOOK_SECRET"))
        self.assertIs(ref.get("optional"), False)

    def test_raw_event_bodies_not_attached(self):
        self.assertIs(self.gh["webhook"].get("include_span_events"), False)

    def test_webhook_address(self):
        wh = self.gh["webhook"]
        self.assertEqual((wh["endpoint"], wh["path"]), ("0.0.0.0:19418", "/events"))

    def test_committer_identity_deleted(self):
        acts = self.cfg["processors"]["resource/drop-identity"]["attributes"]
        deleted = {a["key"] for a in acts if a["action"] == "delete"}
        self.assertEqual(deleted, {"vcs.ref.head.revision.author.name", "vcs.ref.head.revision.author.email"})
        self.assertIn("resource/drop-identity", self.cfg["service"]["pipelines"]["traces"]["processors"])

    def test_metric_labels_are_exactly_the_approved_four(self):
        dims = [d["name"] for d in self.cfg["connectors"]["spanmetrics"]["dimensions"]]
        self.assertEqual(dims, ["cicd.pipeline.name", "ci.span.type", "ci.trigger", "ci.retry"])

    def test_github_receiver_only_in_traces_pipeline(self):
        # In a metrics pipeline the scraper would start polling GitHub (phase 2).
        pipes = self.cfg["service"]["pipelines"]
        users = [name for name, p in pipes.items() if "github" in p.get("receivers", [])]
        self.assertEqual(users, ["traces"])

    def test_survives_one_node_down(self):
        spec = self.col["spec"]
        self.assertEqual(spec["replicas"], 2)
        self.assertEqual(spec["podDisruptionBudget"]["minAvailable"], 1)
        self.assertTrue(spec["affinity"]["podAntiAffinity"]["requiredDuringSchedulingIgnoredDuringExecution"])

    def test_operator_does_not_write_its_own_network_policy(self):
        self.assertIs(self.col["spec"]["networkPolicy"]["enabled"], False)


if __name__ == "__main__":
    unittest.main()
```

Create `gitops/argocd/platform/cicd-telemetry/BUILD`:

```starlark
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@aspect_rules_py//py:defs.bzl", "py_test")

filegroup(
    name = "manifests",
    srcs = glob(["*.yaml"]),
    visibility = ["//visibility:public"],
)

py_test(
    name = "collector_config_test",
    size = "small",
    srcs = ["collector_config_test.py"],
    data = ["collector.yaml"],
    main = "collector_config_test.py",
    deps = ["@pip//pyyaml"],
)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bazel test //gitops/argocd/platform/cicd-telemetry:collector_config_test --test_output=errors`
Expected: FAIL (`FileNotFoundError: .../collector.yaml`).

- [ ] **Step 3: Write `collector.yaml`**

```yaml
# <MIT license header>
# The CI collector: GitHub Actions webhook -> traces (Tempo) + metrics (Prometheus).
# Spec: docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md
# Invariants are pinned by collector_config_test.py in this directory.
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: github-actions
  namespace: cicd-telemetry
spec:
  mode: deployment
  image: otel/opentelemetry-collector-contrib:0.160.0
  replicas: 2
  nodeSelector:
    node.ipv1337.dev/link: wired
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: github-actions-collector
          topologyKey: kubernetes.io/hostname
  podDisruptionBudget:
    minAvailable: 1
  # #2565 turned the operand gate off operator-wide; also say it here.
  networkPolicy:
    enabled: false
  ports:
    - name: webhook
      port: 19418
      protocol: TCP
  env:
    - name: GITHUB_WEBHOOK_SECRET
      valueFrom:
        secretKeyRef:
          name: github-otel-webhook
          key: GITHUB_WEBHOOK_SECRET
          optional: false
  config:
    receivers:
      github:
        # Required by the receiver's config validation; it only runs when the
        # receiver is in a METRICS pipeline, and here it is traces-only.
        scrapers:
          scraper:
            github_org: VitruvianSoftware
        webhook:
          endpoint: 0.0.0.0:19418
          path: /events
          health_path: /health
          secret: ${env:GITHUB_WEBHOOK_SECRET}
          service_name: github-actions
          include_span_events: false
    processors:
      memory_limiter:
        check_interval: 1s
        limit_percentage: 80
        spike_limit_percentage: 20
      resource/drop-identity:
        attributes:
          - key: vcs.ref.head.revision.author.name
            action: delete
          - key: vcs.ref.head.revision.author.email
            action: delete
      transform/ci-labels:
        error_mode: ignore
        trace_statements:
          - context: span
            statements:
              - set(attributes["ci.span.type"], "job")
              - set(attributes["ci.span.type"], "step") where attributes["cicd.pipeline.task.name"] != nil
              - set(attributes["ci.span.type"], "queue") where IsMatch(name, "^queue-")
              - set(attributes["ci.span.type"], "run") where kind == SPAN_KIND_SERVER
              - set(attributes["ci.trigger"], "branch")
              - set(attributes["ci.trigger"], "main") where resource.attributes["vcs.ref.head"] == "main"
              - set(attributes["ci.trigger"], "merge_queue") where IsMatch(resource.attributes["vcs.ref.head"], "^gh-readonly-queue/")
              - set(attributes["ci.retry"], "false")
              - set(attributes["ci.retry"], "true") where resource.attributes["cicd.pipeline.run.previous_attempt.url.full"] != nil
      batch: {}
    connectors:
      spanmetrics:
        namespace: cicd
        histogram:
          unit: s
          explicit:
            buckets: [5s, 15s, 30s, 1m, 2m, 5m, 10m, 20m, 40m, 60m, 120m]
        dimensions:
          - name: cicd.pipeline.name
          - name: ci.span.type
          - name: ci.trigger
          - name: ci.retry
    exporters:
      otlp/tempo:
        endpoint: tempo.opentelemetry.svc.cluster.local:4317
        tls:
          insecure: true
      # Mirrored to BOTH replicas (per-pod headless DNS), exactly as the main
      # collector does, so the Thanos Querier can de-duplicate.
      prometheusremotewrite/replica0:
        endpoint: http://prometheus-server-0.prometheus-server-headless.monitoring.svc.cluster.local:9090/api/v1/write
        timeout: 30s
        resource_to_telemetry_conversion:
          enabled: true
      prometheusremotewrite/replica1:
        endpoint: http://prometheus-server-1.prometheus-server-headless.monitoring.svc.cluster.local:9090/api/v1/write
        timeout: 30s
        resource_to_telemetry_conversion:
          enabled: true
    service:
      pipelines:
        traces:
          receivers: [github]
          processors: [memory_limiter, resource/drop-identity, transform/ci-labels, batch]
          exporters: [otlp/tempo, spanmetrics]
        metrics:
          receivers: [spanmetrics]
          processors: [memory_limiter, batch]
          exporters: [prometheusremotewrite/replica0, prometheusremotewrite/replica1]
```

Note on `resource_to_telemetry_conversion`: it copies resource attributes onto metrics. The spanmetrics dimensions are already on the data points, so if validation (Step 5) shows it adds unwanted labels (e.g. `vcs_ref_head`), **remove it** — Review Focus #3 forbids branch labels. The label check in Task 3 Step 4 is the arbiter.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bazel test //gitops/argocd/platform/cicd-telemetry:collector_config_test --test_output=all`
Expected: `Ran 8 tests ... OK`.

- [ ] **Step 5: Validate the config with the real binary**

```bash
python3 -c "import yaml,sys;d=[x for x in yaml.safe_load_all(open('gitops/argocd/platform/cicd-telemetry/collector.yaml')) if x][0];yaml.safe_dump(d['spec']['config'],open('/tmp/cicd-otel.yaml','w'))"
docker run --rm -e GITHUB_WEBHOOK_SECRET=dummy -v /tmp/cicd-otel.yaml:/c.yaml otel/opentelemetry-collector-contrib:0.160.0 validate --config=/c.yaml
```

Expected: exit 0, no output. If OTTL rejects `kind == SPAN_KIND_SERVER`, replace that statement with `set(attributes["ci.span.type"], "run") where attributes["cicd.pipeline.task.name"] == nil and not IsMatch(name, "^queue-") and resource.attributes["cicd.pipeline.run.url.full"] != nil and parent_span_id.string == ""` and re-validate. Then re-run Step 4.

- [ ] **Step 6: Mutation check**

Delete the `email` delete action → `test_committer_identity_deleted` FAILS. Add `- name: vcs.ref.head` to dimensions → `test_metric_labels_are_exactly_the_approved_four` FAILS. Set `optional: true` → `test_webhook_secret_comes_from_the_required_secret` FAILS. Revert each.

- [ ] **Step 7: Write the public surface and network policy**

`httproute.yaml`:

```yaml
# <MIT license header>
# Public entry for GitHub's CI webhook: ONLY `POST /events`. Health, metrics
# and any other path get the gateway's 404. The signature check in the
# collector is the real lock; this keeps the surface minimal.
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: github-otel
  namespace: cicd-telemetry
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: platform
      namespace: envoy-gateway-system
  hostnames:
    - github-otel.ipv1337.dev
  rules:
    - matches:
        - method: POST
          path:
            type: Exact
            value: /events
      backendRefs:
        - group: ""
          kind: Service
          name: github-actions-collector
          port: 19418
          weight: 1
```

`rate-limit.yaml`:

```yaml
# <MIT license header>
# Caps what a flood can do to the collector. 1200/min is ~7x a busy CI hour
# (100 runs x ~100 events); revisit after the first week of real traffic.
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: github-otel-rate-limit
  namespace: cicd-telemetry
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: github-otel
  rateLimit:
    type: Local
    local:
      rules:
        - limit:
            requests: 1200
            unit: Minute
```

`dnsendpoint.yaml` (copy of ntfy's, same tunnel target):

```yaml
# <MIT license header>
apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: github-otel-tunnel
  namespace: cicd-telemetry
  annotations:
    external-dns.alpha.kubernetes.io/sync-enabled: "true"
    external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
spec:
  endpoints:
    - dnsName: github-otel.ipv1337.dev
      recordType: CNAME
      recordTTL: 1
      targets:
        - 1f7b9704-bb66-41f4-966f-5bb722e3c10e.cfargotunnel.com
      providerSpecific:
        - name: external-dns.alpha.kubernetes.io/cloudflare-proxied
          value: "true"
```

`network-policy.yaml`:

```yaml
# <MIT license header>
# The CI collector may be reached only by the platform gateway's Envoy pods
# (webhook) and may reach only Tempo, both Prometheus servers, and DNS.
# Label/entity selectors ONLY -- never node-IP ipBlocks, which Cilium never
# matches (#2565). Pattern: argocd-image-updater/resources/egress-policy.yaml.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: github-actions-collector
  namespace: cicd-telemetry
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: github-actions-collector
  ingress:
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: envoy-gateway-system
            gateway.envoyproxy.io/owning-gateway-name: platform
      toPorts:
        - ports:
            - port: "19418"
              protocol: TCP
  egress:
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: opentelemetry
            app.kubernetes.io/name: tempo
      toPorts:
        - ports:
            - port: "4317"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: monitoring
            app.kubernetes.io/name: prometheus
            app.kubernetes.io/component: server
      toPorts:
        - ports:
            - port: "9090"
              protocol: TCP
```

Kubelet probes are exempt from Cilium policy by default (host identity); if the pods fail readiness after rollout, check `hubble observe -n cicd-telemetry --verdict DROPPED` before changing anything.

`gitops/argocd/applications/cicd-telemetry.yaml`:

```yaml
# <MIT license header>
# CI pipeline telemetry: the operator-managed collector for GitHub Actions
# webhooks, its public route, rate limit, DNS and network policy.
# Spec: docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cicd-telemetry
  namespace: argocd
  annotations:
    # After the operator (CRDs + webhook) and Tempo.
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: platform-project
  source:
    repoURL: https://github.com/VitruvianSoftware/vitruvian-core.git
    targetRevision: main
    path: gitops/argocd/platform/cicd-telemetry
    directory:
      recurse: true
      exclude: "{BUILD,*.py}"
  destination:
    server: https://kubernetes.default.svc
    namespace: cicd-telemetry
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

- [ ] **Step 8: Run the repo's gitops checks locally**

```bash
bash tools/ci/chart-render.sh
bash tools/conformance/check.sh 2>&1 | tail -3
bazel test //gitops/argocd/platform/cicd-telemetry:all
```

Expected: render clean; conformance `0 fail`; test passes. Fix anything they flag (e.g. a missing license header).

- [ ] **Step 9: Commit (PR 2 continues in Task 3)**

```bash
git add gitops/argocd/platform/cicd-telemetry gitops/argocd/applications/cicd-telemetry.yaml
git commit -m "feat(otel): CI collector for GitHub Actions on the OpenTelemetry operator"
```

---

### Task 3: Live smoke check, then merge PR 2 (PR 2)

**Files:**
- Create: `tools/gitops/cicd_telemetry_smoke.sh`
- Create: `tools/gitops/cicd_telemetry_smoke_test.sh`
- Modify: `tools/gitops/BUILD`

**Interfaces:**
- Consumes: public endpoint and metric names from Task 2; Secret from Task 1.
- Produces: `//tools/gitops:cicd-telemetry-smoke` (exit 0 = gate 2 passed). Function `sign <secret-file> <payload-file>` prints `sha256=<hex>`.

- [ ] **Step 1: Write the failing test (signing matches GitHub's published vector)**

`tools/gitops/cicd_telemetry_smoke_test.sh`:

```bash
#!/usr/bin/env bash
# <MIT license header>
# GitHub's documented test vector for X-Hub-Signature-256:
# secret "It's a Secret to Everybody", payload "Hello, World!".
set -uo pipefail
UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cicd_telemetry_smoke.sh"
W="$(mktemp -d "${TEST_TMPDIR:-/tmp}/smoke.XXXXXX")"; trap 'rm -rf "$W"' EXIT
printf '%s' "It's a Secret to Everybody" > "$W/secret"
printf '%s' "Hello, World!" > "$W/payload"
got="$(SMOKE_LIB_ONLY=1 bash -c ". '$UNDER_TEST'; sign '$W/secret' '$W/payload'")"
want="sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17"
if [ "$got" = "$want" ]; then echo "PASS signature"; else echo "FAIL signature: got '$got'"; exit 1; fi
```

Append to `tools/gitops/BUILD`:

```starlark
# Gate for the CI collector (spec §4): unsigned POST -> 400; a correctly
# signed sample workflow_run event -> a trace in Tempo and a metric in
# Prometheus. Reads the secret from the cluster; never prints it.
#   bazel run //tools/gitops:cicd-telemetry-smoke
sh_binary(
    name = "cicd-telemetry-smoke",
    srcs = ["cicd_telemetry_smoke.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "cicd_telemetry_smoke_test",
    size = "small",
    srcs = ["cicd_telemetry_smoke_test.sh"],
    data = ["cicd_telemetry_smoke.sh"],
)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bazel test //tools/gitops:cicd_telemetry_smoke_test --test_output=errors`
Expected: FAIL (script missing).

- [ ] **Step 3: Write the smoke script**

`tools/gitops/cicd_telemetry_smoke.sh`:

```bash
#!/usr/bin/env bash
# <MIT license header>
# Live gate for the CI collector. 1) an unsigned POST must get 400 -- the
# receiver accepts EVERYTHING when its secret is empty, so this proves the
# secret is really set; 2) a correctly signed sample workflow_run event must
# produce a trace (Tempo) and a metric (Prometheus). The secret is read from
# the cluster into a 0600 temp file and never printed.
#   bazel run //tools/gitops:cicd-telemetry-smoke
set -euo pipefail

sign() { # sign <secret-file> <payload-file> -> sha256=<hex>
  printf 'sha256=%s\n' "$(openssl dgst -sha256 -hmac "$(cat "$1")" -r < "$2" | cut -d' ' -f1)"
}
[ -n "${SMOKE_LIB_ONLY:-}" ] && return 0 2>/dev/null

: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"; export KUBECONFIG
URL="${SMOKE_URL:-https://github-otel.ipv1337.dev/events}"
PROM="${SMOKE_PROM:-http://prometheus-server.monitoring.svc.cluster.local:9090}"
RUN_NAME="cicd-telemetry smoke test"
W="$(umask 077; mktemp -d)"; trap 'rm -rf "$W"' EXIT

# 1. unsigned -> 400
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'X-GitHub-Event: workflow_run' \
  -H 'Content-Type: application/json' --data '{}' "$URL")"
[ "$code" = 400 ] || { echo "✗ unsigned request got $code, want 400 -- is the webhook secret empty?" >&2; exit 1; }
echo "✓ unsigned request rejected (400)"

# 2. signed sample event -> 200
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; start="$(date -u -v-3M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-3 min' +%Y-%m-%dT%H:%M:%SZ)"
run_id="$(date +%s)"
cat > "$W/payload" <<JSON
{"action":"completed","workflow_run":{"id":${run_id},"name":"${RUN_NAME}","run_attempt":1,"status":"completed","conclusion":"success","run_started_at":"${start}","created_at":"${start}","updated_at":"${now}","html_url":"https://github.com/VitruvianSoftware/vitruvian-core/actions/runs/${run_id}","head_branch":"main","head_sha":"0000000000000000000000000000000000000000","head_commit":{"committer":{"name":"smoke","email":"smoke@example.invalid"}}},"repository":{"name":"vitruvian-core","full_name":"VitruvianSoftware/vitruvian-core","owner":{"login":"VitruvianSoftware"}},"sender":{"login":"cicd-telemetry-smoke"}}
JSON
kubectl -n cicd-telemetry get secret github-otel-webhook -o jsonpath='{.data.GITHUB_WEBHOOK_SECRET}' | base64 -d > "$W/secret"
[ -s "$W/secret" ] || { echo "✗ Secret cicd-telemetry/github-otel-webhook is empty or missing" >&2; exit 1; }
sig="$(sign "$W/secret" "$W/payload")"
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'X-GitHub-Event: workflow_run' \
  -H "X-GitHub-Delivery: smoke-${run_id}" -H 'Content-Type: application/json' \
  -H "X-Hub-Signature-256: ${sig}" --data-binary @"$W/payload" "$URL")"
[ "$code" = 200 ] || { echo "✗ signed request got $code, want 200" >&2; exit 1; }
echo "✓ signed sample event accepted (200)"

# 3. metric appears (spanmetrics flushes every ~15s; allow 2 min)
q="cicd_calls_total{cicd_pipeline_name=\"${RUN_NAME}\"}"
for _ in $(seq 1 24); do
  n="$(kubectl -n monitoring exec prometheus-server-0 -c prometheus-server -- \
        wget -qO- "localhost:9090/api/v1/query?query=$(printf '%s' "$q" | jq -sRr @uri)" | jq '.data.result|length')"
  [ "${n:-0}" -gt 0 ] && break; sleep 5
done
[ "${n:-0}" -gt 0 ] || { echo "✗ no ${q} in Prometheus after 2 minutes" >&2; exit 1; }
echo "✓ metric in Prometheus"

# 4. trace appears in Tempo, WITHOUT the committer email
tq="$(printf '%s' '{ resource.service.name = "github-actions" && name = "'"${RUN_NAME}"'" }' | jq -sRr @uri)"
res="$(kubectl -n opentelemetry exec tempo-0 -- wget -qO- "localhost:3200/api/search?q=${tq}&limit=1")"
tid="$(jq -r '.traces[0].traceID // empty' <<<"$res")"
[ -n "$tid" ] || { echo "✗ no trace in Tempo" >&2; exit 1; }
trace="$(kubectl -n opentelemetry exec tempo-0 -- wget -qO- "localhost:3200/api/traces/${tid}")"
if grep -q 'smoke@example.invalid' <<<"$trace"; then echo "✗ committer email reached Tempo" >&2; exit 1; fi
echo "✓ trace in Tempo (${tid}), committer email stripped"
```

(`jq` and `kubectl` must be on PATH. It execs `wget` inside `prometheus-server-0` and `tempo-0`; check first with `kubectl -n opentelemetry exec tempo-0 -- wget --help >/dev/null`. If either image lacks `wget`, replace that exec with a `kubectl port-forward` to 9090 / 3200 plus local `curl`, and keep `$PROM` pointing at the forward.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `bazel test //tools/gitops:cicd_telemetry_smoke_test --test_output=all`
Expected: `PASS signature`.

- [ ] **Step 5: Commit, open PR 2, merge when green**

```bash
git add tools/gitops/cicd_telemetry_smoke.sh tools/gitops/cicd_telemetry_smoke_test.sh tools/gitops/BUILD
git commit -m "feat(tools): live smoke gate for the CI collector"
```

PR 2 must also contain the sealed file from Task 1 Step 8 if it wasn't merged separately.

- [ ] **Step 6: Gate 2 (after merge + Argo CD sync)**

1. `kubectl -n argocd get application cicd-telemetry` → Synced / Healthy.
2. `kubectl -n cicd-telemetry get secret github-otel-webhook -o jsonpath='{.data.GITHUB_WEBHOOK_SECRET}' | wc -c` → > 0 (never print the value).
3. Both pods Ready on **different** nodes. Re-check **10 minutes later**: restart count still 0 on both.
4. `bazel run //tools/gitops:cicd-telemetry-smoke` → all four ✓.
5. Label check (Review Focus #3): `kubectl -n monitoring exec prometheus-server-0 -c prometheus-server -- wget -qO- 'localhost:9090/api/v1/series?match[]=cicd_calls_total' | jq -r '.data[0]|keys[]'` → must NOT include `vcs_ref_head`, `vcs_ref_head_revision`, or `cicd_pipeline_run_id`. If it does, remove `resource_to_telemetry_conversion` from both exporters (Task 2 Step 3 note), re-merge, re-check.

Do not start Task 4 until all five pass.

---

### Task 4: Declare the GitHub webhook in repo-config (PR 3)

**Files:**
- Create: `infrastructure/pulumi/platform/repo-config/internal/cicd_webhook/webhook.go`
- Create: `infrastructure/pulumi/platform/repo-config/internal/cicd_webhook/webhook_test.go`
- Modify: `infrastructure/pulumi/platform/repo-config/main.go` (after `copybara_sync.ManageSyncAuth`)
- Modify: `.github/workflows/_repo-config-apply.yaml`, `.github/workflows/_repo-config-preview.yaml` (env)
- Generated: BUILD files via `bazel run //:gazelle`

**Interfaces:**
- Consumes: env `OTEL_GITHUB_WEBHOOK_SECRET` (Task 1), public URL (Task 2).
- Produces: `func Args(secret pulumi.StringInput) *github.RepositoryWebhookArgs`, `func Manage(ctx *pulumi.Context) error`; Pulumi resource `github.RepositoryWebhook` named `cicd-otel-webhook`.

- [ ] **Step 1: Write the failing test**

`internal/cicd_webhook/webhook_test.go`:

```go
// <MIT license header, // style, as in main_test.go>
package cicd_webhook

import (
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// The webhook must stay narrow: one repo, two event types, JSON, TLS on,
// pointed at the CI collector's public path (spec §3.4).
func TestArgs(t *testing.T) {
	a := Args(pulumi.String("s3cret"))

	if got := a.Repository.(pulumi.String); got != "vitruvian-core" {
		t.Fatalf("Repository = %q, want vitruvian-core", got)
	}
	events := a.Events.(pulumi.StringArray)
	if len(events) != 2 || events[0] != "workflow_job" || events[1] != "workflow_run" {
		t.Fatalf("Events = %v, want [workflow_job workflow_run]", events)
	}
	if a.Active.(pulumi.Bool) != true {
		t.Fatal("webhook must be active")
	}
	c := a.Configuration.(*github.RepositoryWebhookConfigurationArgs)
	if c.Url.(pulumi.String) != "https://github-otel.ipv1337.dev/events" {
		t.Fatalf("Url = %q", c.Url)
	}
	if c.ContentType.(pulumi.String) != "json" {
		t.Fatalf("ContentType = %q, want json", c.ContentType)
	}
	if c.InsecureSsl.(pulumi.Bool) != false {
		t.Fatal("InsecureSsl must be false")
	}
	if c.Secret == nil {
		t.Fatal("Secret must be set")
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd infrastructure/pulumi/platform/repo-config && GOWORK=off go test ./internal/cicd_webhook/`
Expected: FAIL (`undefined: Args`).

- [ ] **Step 3: Implement**

`internal/cicd_webhook/webhook.go`:

```go
// <MIT license header>

// Package cicd_webhook declares the GitHub webhook that sends vitruvian-core's
// GitHub Actions run/job events to the CI collector (spec:
// docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md).
package cicd_webhook

import (
	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/repo-config/internal/secrets"
	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const (
	repoName = "vitruvian-core"
	url      = "https://github-otel.ipv1337.dev/events"
	// Written by `bazel run //tools/gitops:rotate-github-otel-webhook-secret`
	// into both the Actions and Dependabot secret stores.
	secretEnv = "OTEL_GITHUB_WEBHOOK_SECRET"
	secretCfg = "githubOtelWebhookSecret"
)

// Args is the webhook's full desired state, separate from Manage so it can be
// unit-tested without a Pulumi engine.
func Args(secret pulumi.StringInput) *github.RepositoryWebhookArgs {
	return &github.RepositoryWebhookArgs{
		Repository: pulumi.String(repoName),
		Active:     pulumi.Bool(true),
		Events:     pulumi.StringArray{pulumi.String("workflow_job"), pulumi.String("workflow_run")},
		Configuration: &github.RepositoryWebhookConfigurationArgs{
			Url:         pulumi.String(url),
			ContentType: pulumi.String("json"),
			InsecureSsl: pulumi.Bool(false),
			// StringInput does not satisfy StringPtrInput; its Output does.
			Secret:      secret.ToStringOutput(),
		},
	}
}

// Manage declares the webhook. With the secret absent (a local stack without
// it) it declares nothing and says so, rather than creating an UNSIGNED
// webhook the collector would reject.
func Manage(ctx *pulumi.Context) error {
	secret := secrets.EnvOrConfigOptional(config.New(ctx, ""), secretEnv, secretCfg)
	if secret == nil {
		ctx.Log.Warn(secretEnv+" not set: not managing the CI telemetry webhook", nil)
		return nil
	}
	_, err := github.NewRepositoryWebhook(ctx, "cicd-otel-webhook", Args(secret))
	return err
}
```

In `main.go`, directly after the `copybara_sync.ManageSyncAuth(ctx)` block, add:

```go
		// GitHub Actions run/job events -> the CI collector (cicd-telemetry).
		if err := cicd_webhook.Manage(ctx); err != nil {
			return err
		}
```

and the import `"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/repo-config/internal/cicd_webhook"`.

In **both** `_repo-config-apply.yaml` and `_repo-config-preview.yaml`, in the Pulumi step's `env:` block after `SYNC_APP_PRIVATE_KEY`:

```yaml
                  # CI telemetry webhook secret (cicd_webhook), from
                  # //tools/gitops:rotate-github-otel-webhook-secret. Needed in
                  # preview too, or the webhook renders as a pending DELETE.
                  OTEL_GITHUB_WEBHOOK_SECRET: ${{ secrets.OTEL_GITHUB_WEBHOOK_SECRET }}
```

- [ ] **Step 4: Run tests, gazelle, lint**

```bash
bazel run //:gazelle
cd infrastructure/pulumi/platform/repo-config && GOWORK=off go vet ./... && GOWORK=off go test ./... && cd -
actionlint .github/workflows/_repo-config-apply.yaml .github/workflows/_repo-config-preview.yaml
```

Expected: all pass; gazelle adds `internal/cicd_webhook/BUILD.bazel`.

- [ ] **Step 5: Mutation check**

Add `pulumi.String("push")` to `Events` → `TestArgs` FAILS. Revert.

- [ ] **Step 6: Commit, PR 3**

```bash
git add infrastructure/pulumi/platform/repo-config .github/workflows/_repo-config-apply.yaml .github/workflows/_repo-config-preview.yaml
git commit -m "feat(repo-config): send GitHub Actions run/job events to the CI collector"
```

- [ ] **Step 7: Gate 3**

1. The PR's repo-config Pulumi preview shows exactly `+ github:index:RepositoryWebhook cicd-otel-webhook` and nothing else changing. Anything else → stop.
2. After merge, the apply job runs (push trigger). Then `gh api repos/VitruvianSoftware/vitruvian-core/hooks --jq '.[]|[.config.url,.events]'` shows the one hook.
3. `gh api repos/VitruvianSoftware/vitruvian-core/hooks/<id>/deliveries --jq '.[0:10][]|.status_code'` → all `200` after the next CI run.
4. A real run is visible: Tempo search `{ resource.service.name = "github-actions" }` returns the latest workflow names; `cicd_calls_total{ci_trigger="merge_queue"}` has series after a merge-queue run.

---

### Task 5: Grafana "CI pipelines" dashboard (PR 4)

**Files:**
- Create: `gitops/argocd/platform/grafana-dashboards/ci-pipelines.json`
- Modify: `gitops/argocd/platform/grafana-dashboards/kustomization.yaml`
- Modify: `gitops/argocd/platform/grafana-dashboards/tests/tier1_schema_test.py`, `tier2_promql_test.py` (`TARGET_DASHBOARDS`)

**Interfaces:**
- Consumes: metrics `cicd_duration_seconds_bucket`, `cicd_calls_total` with labels `cicd_pipeline_name`, `ci_span_type`, `ci_trigger`, `ci_retry`, `span_name`, `status_code` (Task 2); Tempo datasource for recent failures.

- [ ] **Step 1: Add the dashboard to the test targets (failing)**

Append `"ci-pipelines.json",` to `TARGET_DASHBOARDS` in `tier1_schema_test.py` and `tier2_promql_test.py`.
Run: `bazel test //gitops/argocd/platform/grafana-dashboards/tests:tier1_schema_test --test_output=errors`
Expected: FAIL (file missing).

- [ ] **Step 2: Write the dashboard**

Base the JSON skeleton (schemaVersion, datasource `uid` variables, `tags`, time settings) on `devx-build-metrics.json`. Title `CI pipelines`, uid `ci-pipelines`, tags `["ci", "github-actions"]`. Template variables:

- `workflow`: query `label_values(cicd_calls_total{ci_span_type="run"}, cicd_pipeline_name)`, multi, include All.
- `trigger`: custom `main,merge_queue,branch`, multi, include All.

Common selector (write it out in every query): `cicd_pipeline_name=~"$workflow", ci_trigger=~"$trigger"`.

Panels (all timeseries unless stated; durations unit `s`, ratios `percentunit`):

| row | title | query |
|---|---|---|
| Speed | Run time p50 / p95 by workflow | `histogram_quantile(0.5, sum by (le, cicd_pipeline_name) (rate(cicd_duration_seconds_bucket{ci_span_type="run", cicd_pipeline_name=~"$workflow", ci_trigger=~"$trigger"}[$__rate_interval])))` and the same with `0.95` |
| Speed | Runner wait p95 vs job time p95 | `histogram_quantile(0.95, sum by (le) (rate(cicd_duration_seconds_bucket{ci_span_type="queue", cicd_pipeline_name=~"$workflow", ci_trigger=~"$trigger"}[$__rate_interval])))` and `histogram_quantile(0.95, sum by (le) (rate(cicd_duration_seconds_bucket{ci_span_type="job", cicd_pipeline_name=~"$workflow", ci_trigger=~"$trigger"}[$__rate_interval])))` |
| Speed | Slowest jobs (p95, range) — bar gauge | `topk(10, histogram_quantile(0.95, sum by (le, span_name) (increase(cicd_duration_seconds_bucket{ci_span_type="job", cicd_pipeline_name=~"$workflow", ci_trigger=~"$trigger"}[$__range]))))` |
| Speed | Slowest steps (p95, range) — bar gauge | same with `ci_span_type="step"` |
| Speed | Merge-queue time to green p95 — stat | `histogram_quantile(0.95, sum by (le) (increase(cicd_duration_seconds_bucket{ci_span_type="run", ci_trigger="merge_queue", status_code="STATUS_CODE_OK", cicd_pipeline_name=~"$workflow"}[$__range])))` |
| Reliability | Failure rate by workflow | `sum by (cicd_pipeline_name) (rate(cicd_calls_total{ci_span_type="run", status_code="STATUS_CODE_ERROR", cicd_pipeline_name=~"$workflow", ci_trigger=~"$trigger"}[$__rate_interval])) / clamp_min(sum by (cicd_pipeline_name) (rate(cicd_calls_total{ci_span_type="run", cicd_pipeline_name=~"$workflow", ci_trigger=~"$trigger"}[$__rate_interval])), 1e-9)` |
| Reliability | Failing jobs (range) — bar gauge | `topk(10, sum by (span_name) (increase(cicd_calls_total{ci_span_type="job", status_code="STATUS_CODE_ERROR", cicd_pipeline_name=~"$workflow", ci_trigger=~"$trigger"}[$__range])))` |
| Reliability | Re-run rate — stat | `sum(increase(cicd_calls_total{ci_span_type="run", ci_retry="true", cicd_pipeline_name=~"$workflow", ci_trigger=~"$trigger"}[$__range])) / clamp_min(sum(increase(cicd_calls_total{ci_span_type="run", cicd_pipeline_name=~"$workflow", ci_trigger=~"$trigger"}[$__range])), 1e-9)` |
| Reliability | Recent failures (24h) — table, Tempo datasource | TraceQL: `{ resource.service.name = "github-actions" && kind = server && status = error }`, columns start time, name, `resource.cicd.pipeline.run.url.full` as a link |

Every panel gets a one-line `description` in plain English (e.g. "How long a whole workflow run takes, middle and slow end"). Add a text panel at the top: "Data since switch-on (2026-09-28). Individual runs: last 24h (Tempo). Re-run rate counts retried runs; it is a flakiness signal, not proof."

- [ ] **Step 3: Register it**

In `kustomization.yaml` `configMapGenerator`, alphabetical position:

```yaml
  - name: grafana-dashboard-ci-pipelines
    files:
      - ci-pipelines.json
```

- [ ] **Step 4: Run the dashboard tests**

Run: `bazel test //gitops/argocd/platform/grafana-dashboards/tests:all --test_output=errors`
Expected: all pass. Fix any PromQL/unit/division findings (every ratio above already has a `clamp_min` guard).

- [ ] **Step 5: Commit, PR 4**

```bash
git add gitops/argocd/platform/grafana-dashboards/ci-pipelines.json gitops/argocd/platform/grafana-dashboards/kustomization.yaml gitops/argocd/platform/grafana-dashboards/tests/tier1_schema_test.py gitops/argocd/platform/grafana-dashboards/tests/tier2_promql_test.py
git commit -m "feat(grafana): CI pipelines dashboard (speed + reliability)"
```

- [ ] **Step 6: Gate 4**

After merge + sync, open the dashboard (Grafana API `GET /api/dashboards/uid/ci-pipelines` returns it) and confirm **every** phase-1 panel returns data for the last 6 hours: run each panel's query through Prometheus's `/api/v1/query` (or Grafana's `/api/ds/query`) and require a non-empty result. A panel with no data is a failed gate, not "no CI ran" — pick a time range that contains a merge-queue run.

---

## Phase 2 (not in this plan)

PR-flow polling (PR open → merged, open PR age, merges per week) needs the GitHub scraper in a metrics pipeline, a read-only token, `collection_interval` ≥ 5m, and egress to `api.github.com`. It gets its own short plan once phase 1 has run for a week.
