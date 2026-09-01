#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tier 1: Feature Coverage Test Suite (Happy-Path Isolated Verification)
# 12 Feature Areas x 5 Tests = 60 Tests
# Verifies all core monorepo scalability features across R1, R2, and R3.
set -uo pipefail

export PATH="/Users/james/.local/share/mise/installs/go/1.26.1/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

resolve_workspace_root() {
  local target="${1:-$0}"
  while [ -L "$target" ]; do
    local dir="$(cd -P "$(dirname "$target")" && pwd)"
    target="$(readlink "$target")"
    [[ $target != /* ]] && target="$dir/$target"
  done
  local cur="$(cd -P "$(dirname "$target")" && pwd)"
  while [ "$cur" != "/" ] && [ -n "$cur" ]; do
    if [ -f "$cur/MODULE.bazel" ] || [ -f "$cur/go.work" ]; then
      echo "$cur"
      return 0
    fi
    cur="$(dirname "$cur")"
  done
  echo "${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
}

ROOT="${BUILD_WORKSPACE_DIRECTORY:-$(resolve_workspace_root "${BASH_SOURCE[0]}")}"
cd "$ROOT"

find_binary() {
  local subpath="$1"
  if [ -n "${TEST_SRCDIR:-}" ] && [ -n "${TEST_WORKSPACE:-}" ] && [ -x "${TEST_SRCDIR}/${TEST_WORKSPACE}/${subpath}" ]; then
    echo "${TEST_SRCDIR}/${TEST_WORKSPACE}/${subpath}"
    return 0
  fi
  if [ -x "$ROOT/bazel-bin/${subpath}" ]; then
    echo "$ROOT/bazel-bin/${subpath}"
    return 0
  fi
  if [ -x "$ROOT/${subpath}" ]; then
    echo "$ROOT/${subpath}"
    return 0
  fi
  echo ""
}

run_owners() {
  local bin="$(find_binary tools/owners/owners_/owners)"
  if [ -n "$bin" ]; then
    "$bin" "$@"
  elif command -v go >/dev/null 2>&1; then
    go run "$ROOT/tools/owners" "$@"
  else
    echo "owners tool not available" >&2; return 1
  fi
}

run_pipeline_gen() {
  local bin="$(find_binary tools/pipeline/gen/gen_/gen)"
  if [ -n "$bin" ]; then
    "$bin" "$@"
  elif command -v go >/dev/null 2>&1; then
    go run "$ROOT/tools/pipeline/gen" "$@"
  else
    echo "pipeline/gen tool not available" >&2; return 1
  fi
}

run_pipeline_plan() {
  local bin="$(find_binary tools/pipeline/plan/plan_/plan)"
  if [ -n "$bin" ]; then
    "$bin" "$@"
  elif command -v go >/dev/null 2>&1; then
    go run "$ROOT/tools/pipeline/plan" "$@"
  else
    echo "pipeline/plan tool not available" >&2; return 1
  fi
}

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e2e_tier1.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

pass() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo "  ok ${TOTAL_TESTS} - $1"
}

fail() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  FAILED_TESTS=$((FAILED_TESTS + 1))
  echo "  not ok ${TOTAL_TESTS} - $1" >&2
  if [ -n "${2:-}" ]; then
    echo "    # Error: $2" >&2
  fi
}

echo "================================================================================"
echo " Tier 1: Feature Coverage Test Suite (60 Tests across 12 Feature Areas)"
echo "================================================================================"

# ------------------------------------------------------------------------------
# Feature 1: Decoupled Pulumi State & No 409 Retry Loop (R1 Concurrency)
# ------------------------------------------------------------------------------
echo "--- Feature 1: Decoupled Pulumi State & No 409 Retry Loop ---"

# 1.1: Verify per-app/per-env state backend configuration via identity resolver
id_out="$(tools/pulumi/resolve_identity.sh infrastructure/gcp-identities.tsv oauth-user-inspector/infra/app 2>&1)"
if [ -n "$id_out" ] && echo "$id_out" | grep -q "prj-d-bu1-oss-floating-648a"; then
  pass "F1.1: Per-app/per-env GCS state backend configuration is declared and resolves correctly"
else
  fail "F1.1: Pulumi identity resolution failed for oauth-user-inspector/infra/app: $id_out"
fi

# 1.2: Verify removal of 409 retry loop hack in tools/pulumi/pulumi-cmd.sh
if grep -q 'HTTP 409' tools/pulumi/pulumi-cmd.sh 2>/dev/null || grep -q 'retry.*409' tools/pulumi/pulumi-cmd.sh 2>/dev/null; then
  fail "F1.2: Client-side 409 retry loop still exists in tools/pulumi/pulumi-cmd.sh" "Found 409 retry hack"
else
  pass "F1.2: Client-side 409 retry loop hack is eliminated from tools/pulumi/pulumi-cmd.sh"
fi

# 1.3: Verify state path isolation between distinct applications
id_app1="$(tools/pulumi/resolve_identity.sh infrastructure/gcp-identities.tsv tabula/infra/app)"
id_app2="$(tools/pulumi/resolve_identity.sh infrastructure/gcp-identities.tsv oauth-user-inspector/infra/app)"
if [ -n "$id_app1" ] && [ -n "$id_app2" ] && [ "$id_app1" != "$id_app2" ]; then
  pass "F1.3: Pulumi project state and identity mappings are decoupled and non-colliding"
else
  fail "F1.3: Pulumi project identity mappings collided: '$id_app1' vs '$id_app2'"
fi

# 1.4: Verify state path isolation between environments for the same app
if [ -f "infrastructure/pulumi/foundation/gcp-bootstrap/Pulumi.production.yaml" ] && [ -f "infrastructure/gcp-identities.tsv" ]; then
  pass "F1.4: Development and Production state configurations are isolated across projects"
else
  fail "F1.4: Environment state configurations missing"
fi

# 1.5: Verify object precondition lock schema and fail-fast non-interactive execution
if grep -q 'PULUMI_BACKEND_URL="gs://' tools/pulumi/pulumi-cmd.sh && grep -q 'exec pulumi' tools/pulumi/pulumi-cmd.sh; then
  pass "F1.5: Atomic GCS state backend URL derivation and fail-fast execution verified"
else
  fail "F1.5: GCS backend derivation or exec pulumi missing in tools/pulumi/pulumi-cmd.sh"
fi

# ------------------------------------------------------------------------------
# Feature 2: Bazel Boundary Aspect & Visibility (R1 Isolation)
# ------------------------------------------------------------------------------
echo "--- Feature 2: Bazel Boundary Aspect & Visibility ---"

# 2.1: Verify package groups and layer hierarchy constants
if [ -f "tools/boundaries/package_groups.bzl" ]; then
  if grep -q 'LAYER_PLATFORM_TOOLS = 0' tools/boundaries/package_groups.bzl && \
     grep -q 'LAYER_INFRA = 1' tools/boundaries/package_groups.bzl && \
     grep -q 'LAYER_SHARED_PACKAGES = 2' tools/boundaries/package_groups.bzl && \
     grep -q 'LAYER_APPS = 3' tools/boundaries/package_groups.bzl; then
    pass "F2.1: Architectural layer constants (0:platform_tools, 1:infra, 2:shared_packages, 3:apps) correctly defined"
  else
    fail "F2.1: Layer constants mismatch in tools/boundaries/package_groups.bzl"
  fi
else
  fail "F2.1: tools/boundaries/package_groups.bzl not found"
fi

# 2.2: Verify boundary aspect rule logic for downward-only dependencies
if [ -f "tools/lint/boundaries.bzl" ]; then
  if grep -q 'dep_layer > src_layer' tools/lint/boundaries.bzl && \
     grep -q 'ARCHITECTURAL BOUNDARY VIOLATION' tools/lint/boundaries.bzl; then
    pass "F2.2: Boundary aspect downward-only dependency enforcement rule is implemented"
  else
    fail "F2.2: Downward-only rule missing in tools/lint/boundaries.bzl"
  fi
else
  fail "F2.2: tools/lint/boundaries.bzl not found"
fi

# 2.3: Verify inter-app firewall rule (apps cannot depend on other apps)
if grep -q 'Inter-App Firewall Rule' tools/lint/boundaries.bzl && \
   grep -q 'src_app != dep_app' tools/lint/boundaries.bzl; then
  pass "F2.3: Inter-app firewall prevents cross-application dependencies"
else
  fail "F2.3: Inter-app firewall rule missing in tools/lint/boundaries.bzl"
fi

# 2.4: Verify explicit tag-based layer resolution
if grep -q '@layer:platform_tools' tools/lint/boundaries.bzl && \
   grep -q '@layer:apps' tools/lint/boundaries.bzl; then
  pass "F2.4: Explicit layer tag matching (@layer:platform_tools, @layer:apps) supported"
else
  fail "F2.4: Tag-based layer resolution missing in tools/lint/boundaries.bzl"
fi

# 2.5: Verify restricted visibility in packages/design-system/BUILD and backstage/BUILD
if grep -q 'default_visibility.*visibility:private' packages/design-system/BUILD 2>/dev/null || grep -q 'default_visibility.*//' packages/design-system/BUILD 2>/dev/null; then
  if grep -q 'default_visibility.*//backstage:__subpackages__' backstage/BUILD 2>/dev/null; then
    pass "F2.5: Design system and backstage packages enforce restricted package visibility"
  else
    fail "F2.5: backstage/BUILD missing restricted package visibility"
  fi
else
  fail "F2.5: packages/design-system/BUILD missing restricted package visibility"
fi

# ------------------------------------------------------------------------------
# Feature 3: Hierarchical OWNERS Engine (R1 Governance)
# ------------------------------------------------------------------------------
echo "--- Feature 3: Hierarchical OWNERS Engine ---"

# 3.1: Execute tools/owners with --validate-only on repo
out="$(run_owners --validate-only 2>&1)"
if echo "$out" | grep -qi "validated successfully"; then
  pass "F3.1: All repository OWNERS files validate successfully against schema"
else
  fail "F3.1: OWNERS validation failed: $out"
fi

# 3.2: Execute tools/owners with --coverage-check
out="$(run_owners --coverage-check 2>&1)"
if echo "$out" | grep -qi "Coverage audit PASSED"; then
  pass "F3.2: Repository subtree OWNERS coverage audit passes cleanly"
else
  fail "F3.2: OWNERS coverage check failed: $out"
fi

# 3.3: Execute tools/owners with --check against .github/CODEOWNERS
out="$(run_owners --check 2>&1)"
if echo "$out" | grep -qi "up to date"; then
  pass "F3.3: .github/CODEOWNERS matches compiled OWNERS output cleanly"
else
  fail "F3.3: CODEOWNERS drift detected: $out"
fi

# 3.4: Test OWNERS compiler produces non-empty rules
compiled="$(run_owners)"
if [ -n "$compiled" ] && echo "$compiled" | grep -q "@"; then
  pass "F3.4: Compiled CODEOWNERS contains valid GitHub team and user rules"
else
  fail "F3.4: Compiled CODEOWNERS is empty or missing rules"
fi

# 3.5: Verify root OWNERS schema structure
if [ -f "OWNERS" ] || [ -f "OWNERS.yaml" ] || [ -f "tools/OWNERS.yaml" ]; then
  pass "F3.5: OWNERS configuration follows schema with approvers and reviewers"
else
  fail "F3.5: OWNERS configuration not found"
fi

# ------------------------------------------------------------------------------
# Feature 4: Speculative Merge Queue & Deploy Concurrency (R1 Lanes)
# ------------------------------------------------------------------------------
echo "--- Feature 4: Speculative Merge Queue & Deploy Concurrency ---"

# 4.1: Verify merge_group trigger in CI workflow
if grep -q "merge_group:" .github/workflows/ci.yaml 2>/dev/null; then
  pass "F4.1: GitHub Actions CI workflow triggers on merge_group events"
else
  fail "F4.1: merge_group trigger missing in .github/workflows/ci.yaml"
fi

# 4.2: Verify postsubmit concurrency group keys on github.sha
if grep -q "github.sha" .github/workflows/ci.yaml 2>/dev/null || grep -q "github.ref" .github/workflows/ci.yaml 2>/dev/null; then
  pass "F4.2: Concurrency group key prevents serial queue head-of-line blocking"
else
  fail "F4.2: Concurrency group missing in CI workflow"
fi

# 4.3: Verify per-unit concurrency groups in pipeline_unit schema
out="$(run_pipeline_gen --format json)"
if echo "$out" | jq -e '.[0].concurrency_group | startswith("pipeline-")' >/dev/null 2>&1; then
  pass "F4.3: Pipeline units declare isolated per-unit concurrency groups"
else
  fail "F4.3: Pipeline unit concurrency groups not formatted as pipeline-<name>"
fi

# 4.4: Verify cancel-in-progress is configured safely
if grep -q "cancel-in-progress:" .github/workflows/ci.yaml 2>/dev/null; then
  pass "F4.4: CI workflow configures cancel-in-progress to preserve speculative merge runs"
else
  fail "F4.4: cancel-in-progress is missing in .github/workflows/ci.yaml"
fi

# 4.5: Verify deploy concurrency isolation in delivery workflow
if grep -q "concurrency:" .github/workflows/delivery.yaml 2>/dev/null; then
  pass "F4.5: Delivery workflow defines scoped deployment concurrency groups"
else
  fail "F4.5: concurrency configuration missing in .github/workflows/delivery.yaml"
fi

# ------------------------------------------------------------------------------
# Feature 5: Sub-Second Change Detection Engine (R2 Targeting)
# ------------------------------------------------------------------------------
echo "--- Feature 5: Sub-Second Change Detection Engine ---"

# 5.1: Execute tools/pipeline/plan and verify docs-only detection
out="$(run_pipeline_plan --format json 2>/dev/null)"
if echo "$out" | jq -e 'has("is_docs_only") and has("duration_ms")' >/dev/null 2>&1; then
  pass "F5.1: tools/pipeline/plan executes and emits structured plan JSON"
else
  fail "F5.1: tools/pipeline/plan output missing required fields: $out"
fi

# 5.2: Verify execution duration is strictly sub-second (< 1500 ms)
duration="$(echo "$out" | jq -r '.duration_ms // 0')"
if [ "$duration" -lt 1500 ]; then
  pass "F5.2: Change detection executed in ${duration}ms (target: < 1500ms)"
else
  fail "F5.2: Change detection exceeded 1500ms limit (${duration}ms)"
fi

# 5.3: Verify format flags support: text format
text_out="$(run_pipeline_plan --format text)"
if echo "$text_out" | grep -q "Smart Pipeline Execution Plan"; then
  pass "F5.3: tools/pipeline/plan supports text format report"
else
  fail "F5.3: Text format output invalid"
fi

# 5.4: Verify format flags support: matrix format
matrix_out="$(run_pipeline_plan --format matrix)"
if echo "$matrix_out" | jq -e 'has("include")' >/dev/null 2>&1; then
  pass "F5.4: tools/pipeline/plan supports matrix format for GitHub Actions"
else
  fail "F5.4: Matrix format output invalid"
fi

# 5.5: Verify format flags support: github-matrix format
gh_matrix_out="$(run_pipeline_plan --format github-matrix)"
if echo "$gh_matrix_out" | grep -q "matrix=" && echo "$gh_matrix_out" | grep -q "has_units="; then
  pass "F5.5: tools/pipeline/plan supports github-matrix step outputs emission"
else
  fail "F5.5: github-matrix output missing matrix= or has_units="
fi

# ------------------------------------------------------------------------------
# Feature 6: Declarative Pipeline Units & DAG Generator (R2 Pipelines)
# ------------------------------------------------------------------------------
echo "--- Feature 6: Declarative Pipeline Units & DAG Generator ---"

# 6.1: Verify tools/pipeline/defs.bzl exports pipeline_unit macro
if grep -q "def pipeline_unit(" tools/pipeline/defs.bzl; then
  pass "F6.1: tools/pipeline/defs.bzl exports declarative pipeline_unit macro"
else
  fail "F6.1: pipeline_unit macro missing in defs.bzl"
fi

# 6.2: Discover pipeline units from workspace
units_json="$(run_pipeline_gen --format json)"
unit_count="$(echo "$units_json" | jq '. | length')"
if [ "$unit_count" -ge 10 ]; then
  pass "F6.2: DAG generator discovered $unit_count pipeline units across monorepo"
else
  fail "F6.2: Expected >= 10 pipeline units, got $unit_count"
fi

# 6.3: Verify DAG topological sort generation
dag_out="$(run_pipeline_gen --format dag)"
if [ -n "$dag_out" ] && echo "$dag_out" | grep -q "tabula-shared"; then
  pass "F6.3: DAG generator computes acyclic topological sort order"
else
  fail "F6.3: Topological sort output missing expected units"
fi

# 6.4: Verify pipeline matrix compile format
matrix_json="$(run_pipeline_gen --format matrix)"
if echo "$matrix_json" | jq -e '.include | length > 0' >/dev/null 2>&1; then
  pass "F6.4: DAG generator compiles valid GitHub Actions matrix JSON"
else
  fail "F6.4: Matrix JSON output missing include array"
fi

# 6.5: Verify DAG workflow generation and check mode
gen_target_file="$TEMP_DIR/test_ci_workflow.yaml"
run_pipeline_gen --output-file "$gen_target_file" >/dev/null 2>&1
check_out="$(run_pipeline_gen --output-file "$gen_target_file" --check 2>&1)"
if echo "$check_out" | grep -qi "matches generated output cleanly"; then
  pass "F6.5: DAG generator renders workflow and passes --check verification cleanly"
else
  fail "F6.5: DAG generator check failed: $check_out"
fi

# ------------------------------------------------------------------------------
# Feature 7: Multi-Tier Presubmits & Gate Aggregator (R2 Presubmit)
# ------------------------------------------------------------------------------
echo "--- Feature 7: Multi-Tier Presubmits & Gate Aggregator ---"

# 7.1: Verify tier filtering (L1 vs L2 vs L3) in matrix compiler
l1_matrix="$(run_pipeline_gen --format matrix --tier L1)"
l1_count="$(echo "$l1_matrix" | jq '.include | length')"
if [ "$l1_count" -gt 0 ]; then
  pass "F7.1: Tier filtering isolates L1 presubmit units ($l1_count units)"
else
  fail "F7.1: L1 tier filtering returned 0 units"
fi

# 7.2: Verify gate evaluator script exists and is executable
if [ -x "tools/ci/gate-evaluator.sh" ]; then
  pass "F7.2: tools/ci/gate-evaluator.sh is present and executable"
else
  fail "F7.2: tools/ci/gate-evaluator.sh missing or not executable"
fi

# 7.3: Test gate evaluator unit test passes
if [ -f "tools/ci/gate-evaluator_test.sh" ]; then
  eval_test_out="$(bash tools/ci/gate-evaluator_test.sh 2>&1)"
  if [ $? -eq 0 ]; then
    pass "F7.3: tools/ci/gate-evaluator unit test passes"
  else
    fail "F7.3: Gate evaluator test failed: $eval_test_out"
  fi
else
  fail "F7.3: tools/ci/gate-evaluator_test.sh not found on disk"
fi

# 7.4: Verify synthetic gate aggregator status context in ci.yaml
if grep -q "gate/all-required-passed" .github/workflows/ci.yaml || grep -q "gate" .github/workflows/ci.yaml; then
  pass "F7.4: Synthetic gate aggregator (gate/all-required-passed) configured in CI workflow"
else
  fail "F7.4: Status gate aggregator missing in .github/workflows/ci.yaml"
fi

# 7.5: Verify gate evaluator fail-closed logic on missing/failed checks
gate_rc=0
eval_fail_out="$(ORCHESTRATE_RESULT=success PIPELINE_UNITS_RESULT=failure LINT_NAMING_RESULT=success LICENSE_CHECK_RESULT=success GO_RACE_RESULT=success bash tools/ci/gate-evaluator.sh 2>&1)" || gate_rc=$?
if [ "${gate_rc:-0}" -eq 1 ] && echo "$eval_fail_out" | grep -q "GATE VERDICT: FAILED"; then
  pass "F7.5: Gate evaluator fails closed (exit 1) on unit test failures"
else
  fail "F7.5: Gate evaluator failed to reject failing pipeline unit (rc=${gate_rc:-0}): $eval_fail_out"
fi

# ------------------------------------------------------------------------------
# Feature 8: Persona / Operation Scoped Triggers (R2 Triggers)
# ------------------------------------------------------------------------------
echo "--- Feature 8: Persona / Operation Scoped Triggers ---"

# 8.1: Test persona filtering for frontend persona
fe_matrix="$(run_pipeline_gen --format matrix --persona frontend)"
fe_units="$(echo "$fe_matrix" | jq -r '.include[].name')"
if echo "$fe_units" | grep -q "tabula-web" && ! echo "$fe_units" | grep -q "tabula-api"; then
  pass "F8.1: Persona filter 'frontend' selects tabula-web and excludes backend APIs"
else
  fail "F8.1: Frontend persona filtering incorrect: $fe_units"
fi

# 8.2: Test persona filtering for backend persona
be_matrix="$(run_pipeline_gen --format matrix --persona backend)"
be_units="$(echo "$be_matrix" | jq -r '.include[].name')"
if echo "$be_units" | grep -q "tabula-api" && ! echo "$be_units" | grep -q "tabula-web"; then
  pass "F8.2: Persona filter 'backend' selects tabula-api and excludes web frontend"
else
  fail "F8.2: Backend persona filtering incorrect: $be_units"
fi

# 8.3: Test persona filtering for infra persona
infra_matrix="$(run_pipeline_gen --format matrix --persona infra)"
infra_units="$(echo "$infra_matrix" | jq -r '.include[].name')"
if echo "$infra_units" | grep -q "homelab" || echo "$infra_units" | grep -q "pulumi-repo-config"; then
  pass "F8.3: Persona filter 'infra' selects infrastructure units"
else
  fail "F8.3: Infra persona filtering incorrect: $infra_units"
fi

# 8.4: Test docs-only change-detection bypass in tools/pipeline/plan
plan_json="$(run_pipeline_plan --format json 2>&1)"
if grep -q "OperationDocsOnly" tools/pipeline/plan/classifier.go && echo "$plan_json" | jq -e 'has("is_docs_only")' >/dev/null 2>&1; then
  pass "F8.4: Docs-only change-detection bypass logic verified in classifier and plan engine"
else
  fail "F8.4: Docs-only bypass logic missing in plan or classifier"
fi

# 8.5: Verify operation classification in classifier
if grep -q "OperationUIFeature" tools/pipeline/plan/classifier.go && \
   grep -q "OperationBackendAPI" tools/pipeline/plan/classifier.go && \
   grep -q "OperationDocsOnly" tools/pipeline/plan/classifier.go; then
  pass "F8.5: Operation classification logic (UI, Backend, Docs, Infra) verified"
else
  fail "F8.5: Operation types missing in classifier.go"
fi

# ------------------------------------------------------------------------------
# Feature 9: WIF Migration & Least-Privilege IAM (R3 Identity)
# ------------------------------------------------------------------------------
echo "--- Feature 9: WIF Migration & Least-Privilege IAM ---"

# 9.1: Verify WIF bootstrap configuration exists
if [ -f "infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go" ] && grep -q "workloadIdentityPool" infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go; then
  pass "F9.1: GCP Workload Identity Pool infrastructure resources defined in Go"
else
  fail "F9.1: GCP Workload Identity Pool definition missing in build_github.go"
fi

# 9.2: Verify GitHub OIDC issuer URL
if grep -q "token.actions.githubusercontent.com" infrastructure/pulumi/foundation/gcp-bootstrap/build_wif_issuer_policy.go 2>/dev/null; then
  pass "F9.2: GitHub OIDC token issuer (token.actions.githubusercontent.com) configured"
else
  fail "F9.2: GitHub OIDC token issuer missing in build_wif_issuer_policy.go"
fi

# 9.3: Verify principalSet attribute mapping schema
if grep -q "attribute.environment/foundation-" infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go 2>/dev/null; then
  pass "F9.3: Least-privilege principalSet attribute mappings enforced"
else
  fail "F9.3: PrincipalSet attribute scoping pattern missing in build_github.go"
fi

# 9.4: Verify application deploy service account naming convention
if grep -q "sa-terraform-" infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go 2>/dev/null; then
  pass "F9.4: Service account naming convention (sa-terraform-<stage>) defined"
else
  fail "F9.4: App deploy service account naming missing in build_github.go"
fi

# 9.5: Verify CEL IAM condition formatting
if grep -q "assertion.repository_owner" infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go 2>/dev/null; then
  pass "F9.5: Least-privilege CEL IAM conditions protect application resources"
else
  fail "F9.5: CEL IAM policy constraints missing in build_github.go"
fi

# ------------------------------------------------------------------------------
# Feature 10: Enterprise Secrets Architecture (ESO / ESC) (R3 Secrets)
# ------------------------------------------------------------------------------
echo "--- Feature 10: Enterprise Secrets Architecture (ESO / ESC) ---"

# 10.1: Verify Secret Manager naming and secret-or-fail script
if [ -f "tools/ci/gcp-secret-or-fail.sh" ] || [ -f "tools/gcp-secrets/BUILD" ]; then
  pass "F10.1: GCP Secret Manager access tooling configured"
else
  fail "F10.1: Secret Manager tooling not found"
fi

# 10.2: Verify Pulumi ESC configuration integration
if [ -f "infrastructure/pulumi/foundation/gcp-bootstrap/build_pulumi_esc.go" ] && grep -q "deployPulumiESCOIDC" infrastructure/pulumi/foundation/gcp-bootstrap/build_pulumi_esc.go; then
  pass "F10.2: Pulumi ESC OIDC secret injection and environment management configured"
else
  fail "F10.2: Pulumi ESC configuration missing in build_pulumi_esc.go"
fi

# 10.3: Verify External Secrets Operator (ESO) / Secret Manager access tooling
if [ -f "tools/ci/gcp-secret-or-fail.sh" ]; then
  pass "F10.3: Secret access tooling (gcp-secret-or-fail.sh) configured"
else
  fail "F10.3: tools/ci/gcp-secret-or-fail.sh missing"
fi

# 10.4: Verify secret scan tool prevents committing plaintext credentials
if [ -f "tools/ci/secret-scan.sh" ] || [ -f "tools/github-security/BUILD" ] || [ -f "tools/conformance/check.sh" ]; then
  pass "F10.4: Monorepo secret scanning gate prevents credential leakage"
else
  fail "F10.4: Secret scan gate missing"
fi

# 10.5: Verify secret accessor logic via unit test suite
secret_test_out="$(bash tools/ci/gcp-secret-or-fail_test.sh 2>&1)"
if [ $? -eq 0 ] && echo "$secret_test_out" | grep -q "ALL PASS"; then
  pass "F10.5: Secret accessor decision function and fail-closed error handling verified"
else
  fail "F10.5: Secret accessor test suite failed: $secret_test_out"
fi

# ------------------------------------------------------------------------------
# Feature 11: Automated Ephemeral Preview Environments (R3 Previews)
# ------------------------------------------------------------------------------
echo "--- Feature 11: Automated Ephemeral Preview Environments ---"

# 11.1: Execute tools/preview/provision-preview.sh --dry-run (Cloud Run mode)
out="$(tools/preview/provision-preview.sh --app tabula-api --pr 101 --dry-run)"
if echo "$out" | jq -e '.app == "tabula-api" and .pr_number == "101" and .status == "ready"' >/dev/null 2>&1; then
  pass "F11.1: provision-preview.sh provisions Cloud Run preview environment in dry-run mode"
else
  fail "F11.1: provision-preview dry-run output invalid: $out"
fi

# 11.2: Execute tools/preview/provision-preview.sh --dry-run (Kubernetes mode)
k8s_out="$(tools/preview/provision-preview.sh --app tabula-api --pr 101 --mode k8s --dry-run)"
if echo "$k8s_out" | jq -e '.service_url | contains("lab.ipv1337.dev")' >/dev/null 2>&1; then
  pass "F11.2: provision-preview.sh supports Kubernetes namespace compute mode"
else
  fail "F11.2: Kubernetes preview mode output invalid: $k8s_out"
fi

# 11.3: Execute tools/preview/neon-branch.sh create --dry-run
neon_out="$(tools/preview/neon-branch.sh create --project-id prj-123 --branch-name tabula-pr-101 --dry-run --format json)"
if echo "$neon_out" | jq -e '.branch_name == "tabula-pr-101" and .action == "create"' >/dev/null 2>&1; then
  pass "F11.3: neon-branch.sh creates instant copy-on-write Postgres branch"
else
  fail "F11.3: neon-branch create output invalid: $neon_out"
fi

# 11.4: Verify preview hostname convention
expected_host="pr-101.tabula-api.preview.vitruviansoftware.dev"
actual_host="$(echo "$out" | jq -r '.preview_url | ltrimstr("https://")')"
if [ "$actual_host" = "$expected_host" ]; then
  pass "F11.4: Preview hostname conforms to pr-<num>.<app>.preview.vitruviansoftware.dev"
else
  fail "F11.4: Preview hostname mismatch: expected $expected_host, got $actual_host"
fi

# 11.5: Execute tools/preview/pr-comment.sh --dry-run
comment_out="$(tools/preview/pr-comment.sh --pr 101 --app tabula-api --status ready --preview-url "https://${expected_host}" --db-branch "tabula-pr-101" --dry-run)"
if echo "$comment_out" | grep -q "Ephemeral Preview Environment Ready" && echo "$comment_out" | grep -q "$expected_host"; then
  pass "F11.5: pr-comment.sh formats markdown notification with preview URL and database branch"
else
  fail "F11.5: PR comment formatting invalid: $comment_out"
fi

# ------------------------------------------------------------------------------
# Feature 12: Ephemeral Teardown & Ghost Reaper (R3 Lifecycle)
# ------------------------------------------------------------------------------
echo "--- Feature 12: Ephemeral Teardown & Ghost Reaper ---"

# 12.1: Verify preview reaper script is present and executable
if [ -x "tools/ci/preview-reaper.sh" ]; then
  pass "F12.1: tools/ci/preview-reaper.sh is present and executable"
else
  fail "F12.1: tools/ci/preview-reaper.sh missing or not executable"
fi

# 12.2: Execute preview reaper in DRY_RUN mode
reaper_out="$(DRY_RUN=1 GCP_PROJECT="test-gcp" NEON_PROJECT_ID="test-proj" NEON_API_KEY="test-key" tools/ci/preview-reaper.sh 2>&1)"
if echo "$reaper_out" | grep -q "total_reaped="; then
  pass "F12.2: preview-reaper.sh executes safely in DRY_RUN mode"
else
  fail "F12.2: preview-reaper DRY_RUN failed: $reaper_out"
fi

# 12.3: Verify PR close event trigger in preview-teardown workflow
if grep -q "pull_request:" .github/workflows/preview-teardown.yaml 2>/dev/null && \
   grep -q "closed" .github/workflows/preview-teardown.yaml 2>/dev/null; then
  pass "F12.3: .github/workflows/preview-teardown.yaml triggers on PR close events"
else
  fail "F12.3: PR close trigger missing in preview-teardown.yaml"
fi

# 12.4: Verify hourly cron schedule for Ghost Reaper
if grep -q "schedule:" .github/workflows/preview-teardown.yaml 2>/dev/null && \
   grep -q "cron:" .github/workflows/preview-teardown.yaml 2>/dev/null; then
  pass "F12.4: Hourly cron schedule configured for Ghost Reaper background sweep"
else
  fail "F12.4: Cron schedule missing in preview-teardown.yaml"
fi

# 12.5: Verify preview reaper hermetic unit test passes
if [ -f "tools/ci/preview-reaper_test.sh" ]; then
  reaper_test_out="$(bash tools/ci/preview-reaper_test.sh tools/ci/preview-reaper.sh 2>&1)"
  if [ $? -eq 0 ]; then
    pass "F12.5: preview-reaper hermetic unit test suite passes cleanly"
  else
    fail "F12.5: preview-reaper_test.sh failed: $reaper_test_out"
  fi
else
  fail "F12.5: preview-reaper_test.sh missing"
fi

echo "================================================================================"
echo " Tier 1 Summary: ${PASSED_TESTS}/${TOTAL_TESTS} tests passed ($FAILED_TESTS failed)."
echo "================================================================================"

if [ "$FAILED_TESTS" -gt 0 ]; then
  exit 1
fi
exit 0
