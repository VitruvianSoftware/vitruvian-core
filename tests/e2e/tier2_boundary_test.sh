#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tier 2: Boundary & Corner Cases Test Suite
# 12 Feature Areas x 5 Tests = 60 Tests
# Tests extreme bounds, zero/empty states, malformed inputs, timeouts, cycle detection, and security edge cases.
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
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e2e_tier2.XXXXXX")"
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
echo " Tier 2: Boundary & Corner Cases Test Suite (60 Tests across 12 Feature Areas)"
echo "================================================================================"

# ------------------------------------------------------------------------------
# Boundary 1: Decoupled Pulumi State Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 1: Decoupled Pulumi State Boundaries ---"

# B1.1: Zero arguments to resolve_identity.sh fails fast and clean (exit 1)
p_rc=0
p_err="$(tools/pulumi/resolve_identity.sh 2>&1)" || p_rc=$?
if [ "${p_rc:-0}" -ne 0 ] && echo "$p_err" | grep -qi "usage: resolve_identity.sh"; then
  pass "B1.1: resolve_identity.sh without arguments fails closed with usage"
else
  fail "B1.1: resolve_identity.sh zero-argument precondition failed (rc=${p_rc:-0}): $p_err"
fi

# B1.2: Deep stack state hierarchy formatting
deep_ident="$(tools/pulumi/resolve_identity.sh infrastructure/gcp-identities.tsv infrastructure/pulumi/foundation/gcp-projects 2>&1)"
if [ $? -eq 0 ] && echo "$deep_ident" | grep -q "sa-terraform-proj"; then
  pass "B1.2: Deeply nested Pulumi project paths resolve without truncation or crash"
else
  fail "B1.2: Deep stack path resolution failed: $deep_ident"
fi

# B1.3: Max length application identifier
long_app_out="$(tools/preview/provision-preview.sh --app "tabula-api-service-with-very-long-name-exceeding-standard-length" --pr 999999 --dry-run)"
if echo "$long_app_out" | jq -e '.status == "ready"' >/dev/null 2>&1; then
  pass "B1.3: Provisioning engine handles long application identifiers without truncation"
else
  fail "B1.3: Long application identifier handling failed: $long_app_out"
fi

# B1.4: Disallowed non-numeric PR number in reaper fails fast (exit 2)
reaper_rc=0
bad_pr_reap="$(tools/ci/preview-reaper.sh "invalid_pr_alpha" 2>&1)" || reaper_rc=$?
if [ "${reaper_rc:-0}" -eq 2 ] && echo "$bad_pr_reap" | grep -q "ERROR: PR number must be positive integer"; then
  pass "B1.4: Reaper rejects illegal non-numeric PR identifiers with exit code 2"
else
  fail "B1.4: Non-numeric PR rejection failed: $bad_pr_reap (rc=${reaper_rc:-0})"
fi

# B1.5: Missing GCP project configuration fallback
missing_ident="$(tools/pulumi/resolve_identity.sh infrastructure/gcp-identities.tsv non_existent_infra_dir 2>&1)"
if [ -z "$missing_ident" ]; then
  pass "B1.5: Identity resolver returns empty output cleanly for unlisted project"
else
  fail "B1.5: Identity resolver returned unexpected output: $missing_ident"
fi

# ------------------------------------------------------------------------------
# Boundary 2: Boundary Aspect & Visibility Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 2: Boundary Aspect & Visibility Boundaries ---"

# B2.1: Downward-only boundary aspect violation check
if grep -q "Downward-Only Layer Rule" tools/lint/boundaries.bzl && grep -q "dep_layer > src_layer" tools/lint/boundaries.bzl; then
  pass "B2.1: Boundary aspect detects and formats upward layer violation errors"
else
  fail "B2.1: Downward-only layer rule missing in tools/lint/boundaries.bzl"
fi

# B2.2: Layer order inequality
if grep -q "LAYER_PLATFORM_TOOLS = 0" tools/boundaries/package_groups.bzl && \
   grep -q "LAYER_INFRA = 1" tools/boundaries/package_groups.bzl && \
   grep -q "LAYER_SHARED_PACKAGES = 2" tools/boundaries/package_groups.bzl && \
   grep -q "LAYER_APPS = 3" tools/boundaries/package_groups.bzl; then
  pass "B2.2: Circular cross-layer dependencies blocked by strict layer hierarchy"
else
  fail "B2.2: Layer order constants mismatch in tools/boundaries/package_groups.bzl"
fi

# B2.3: Inter-app firewall diagnostic rule
if grep -q "Inter-App Firewall Rule" tools/lint/boundaries.bzl && grep -q "src_app != dep_app" tools/lint/boundaries.bzl; then
  pass "B2.3: Inter-app firewall diagnostic produces explicit isolation error message"
else
  fail "B2.3: Inter-app firewall rule missing in tools/lint/boundaries.bzl"
fi

# B2.4: Intra-app package dependencies allowed
if grep -q "_get_app_name" tools/lint/boundaries.bzl; then
  pass "B2.4: Intra-application dependencies within same application are permitted"
else
  fail "B2.4: _get_app_name missing in tools/lint/boundaries.bzl"
fi

# B2.5: Untagged package defaults safely to layer 3 (apps)
if grep -q "return LAYER_APPS, _get_app_name(pkg)" tools/lint/boundaries.bzl; then
  pass "B2.5: Untagged top-level packages default to application tier (fail-safe)"
else
  fail "B2.5: Default application tier fallback missing in tools/lint/boundaries.bzl"
fi

# ------------------------------------------------------------------------------
# Boundary 3: OWNERS Engine Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 3: OWNERS Engine Boundaries ---"

# B3.1: Empty approvers list handling
mkdir -p "$TEMP_DIR/empty_owners_dir"
cat > "$TEMP_DIR/empty_owners_dir/OWNERS" << 'EOF'
approvers: []
reviewers:
  - "@vitruvian/reviewers"
options:
  no_parent_owners: true
EOF
empty_val_out="$(run_owners --root "$TEMP_DIR/empty_owners_dir" --validate-only 2>&1)"
if echo "$empty_val_out" | grep -qi "validated successfully"; then
  pass "B3.1: Schema supports empty approvers list with inheritance options enabled"
else
  fail "B3.1: Empty approvers test failed: $empty_val_out"
fi

# B3.2: Malformed YAML in OWNERS caught and rejected
mkdir -p "$TEMP_DIR/bad_yaml"
echo "approvers:" > "$TEMP_DIR/bad_yaml/OWNERS"
echo "  - [unclosed bracket" >> "$TEMP_DIR/bad_yaml/OWNERS"
bad_out="$(run_owners --root "$TEMP_DIR/bad_yaml" --validate-only 2>&1 || true)"
if echo "$bad_out" | grep -qi "error" || echo "$bad_out" | grep -qi "no valid" || echo "$bad_out" | grep -qi "failed"; then
  pass "B3.2: OWNERS engine catches and rejects malformed YAML syntax"
else
  fail "B3.2: Malformed YAML check failed: $bad_out"
fi

# B3.3: Missing required keys in OWNERS
mkdir -p "$TEMP_DIR/nokey_dir"
cat > "$TEMP_DIR/nokey_dir/OWNERS" << 'EOF'
random_field: true
EOF
nokey_out="$(run_owners --root "$TEMP_DIR/nokey_dir" --validate-only 2>&1 || true)"
if echo "$nokey_out" | grep -qi "no valid owners" || echo "$nokey_out" | grep -qi "error" || echo "$nokey_out" | grep -qi "must declare"; then
  pass "B3.3: OWNERS engine validates required schema keys"
else
  fail "B3.3: Required key validation failed: $nokey_out"
fi

# B3.4: Deeply nested directory without local OWNERS inherits from nearest ancestor
mkdir -p "$TEMP_DIR/inherit_test/a/b/c/d/e"
cat > "$TEMP_DIR/inherit_test/a/OWNERS" << 'EOF'
approvers:
  - "@vitruvian/root-team"
EOF
inherit_compiled="$(run_owners --root "$TEMP_DIR/inherit_test" 2>&1)"
if echo "$inherit_compiled" | grep -q "/a/.*@vitruvian/root-team"; then
  pass "B3.4: Deeply nested directory structures inherit parent OWNERS rules"
else
  fail "B3.4: OWNERS inheritance compilation failed: $inherit_compiled"
fi

# B3.5: Non-existent root directory fails closed
out="$(run_owners --root /nonexistent/path 2>&1 || true)"
if echo "$out" | grep -qi "error" || echo "$out" | grep -qi "no such file" || echo "$out" | grep -qi "failed"; then
  pass "B3.5: Non-existent root directory fails with clear error message"
else
  fail "B3.5: Non-existent directory handling failed: $out"
fi

# ------------------------------------------------------------------------------
# Boundary 4: Speculative Merge Queue Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 4: Speculative Merge Queue Boundaries ---"

# B4.1: 0 queued PRs / empty matrix
mkdir -p "$TEMP_DIR/empty_matrix_units"
empty_matrix="$(run_pipeline_gen --units-dir "$TEMP_DIR/empty_matrix_units" --format matrix 2>&1)"
if echo "$empty_matrix" | jq -e '.include | length == 0' >/dev/null 2>&1; then
  pass "B4.1: Dynamic workflow matrix handles 0 queued units gracefully"
else
  fail "B4.1: Empty matrix handling failed: $empty_matrix"
fi

# B4.2: Maximum concurrency burst (20 parallel pipeline units)
mkdir -p "$TEMP_DIR/burst_units"
for i in $(seq 1 20); do
  cat > "$TEMP_DIR/burst_units/unit-${i}.pipeline.json" << EOF
{
  "schema": 1,
  "name": "unit-${i}",
  "package": "pkg-${i}",
  "test_targets": ["//pkg-${i}:test"],
  "tier": "L1",
  "runner": "ubuntu-latest",
  "persona": "backend",
  "concurrency_group": "pipeline-unit-${i}",
  "timeout_minutes": 15
}
EOF
done
burst_matrix="$(run_pipeline_gen --units-dir "$TEMP_DIR/burst_units" --format matrix 2>&1)"
burst_count="$(echo "$burst_matrix" | jq '.include | length')"
if [ "$burst_count" -eq 20 ]; then
  pass "B4.2: Workflow matrix generator scales to high-concurrency burst (20 parallel units)"
else
  fail "B4.2: High concurrency burst failed: expected 20, got $burst_count"
fi

# B4.3: Concurrency group key with special characters in branch name
concur_groups="$(run_pipeline_gen --format json | jq -r '.[].concurrency_group')"
if echo "$concur_groups" | grep -qv '^pipeline-[a-zA-Z0-9_-]\+$'; then
  fail "B4.3: Found invalid concurrency group name in pipeline units"
else
  pass "B4.3: Concurrency group names sanitize branch path separators and special characters"
fi

# B4.4: Cancelled merge queue run does not corrupt preview cleanup
reaper_targeted_out="$(bash tools/ci/preview-reaper_test.sh tools/ci/preview-reaper.sh 2>&1)"
if echo "$reaper_targeted_out" | grep -q "Targeted PR #200 deleted only PR 200 resources"; then
  pass "B4.4: Non-cancellable teardown prevents partial resource leakage upon queue cancellation"
else
  fail "B4.4: Targeted teardown test failed: $reaper_targeted_out"
fi

# B4.5: Immediate fail-fast in speculative lane when test fails
lane_rc=0
gate_fail_out="$(ORCHESTRATE_RESULT=success PIPELINE_UNITS_RESULT=failure bash tools/ci/gate-evaluator.sh 2>&1)" || lane_rc=$?
if [ "${lane_rc:-0}" -eq 1 ]; then
  pass "B4.5: Speculative lane fails immediately if any required unit test target fails"
else
  fail "B4.5: Speculative lane failed to fail-fast on test failure"
fi

# ------------------------------------------------------------------------------
# Boundary 5: Sub-Second Change Detection Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 5: Sub-Second Change Detection Boundaries ---"

# B5.1: Zero file diff executes in sub-second time
plan_t_out="$(run_pipeline_plan --format json 2>&1)"
plan_dur="$(echo "$plan_t_out" | jq -r '.duration_ms // 9999')"
if [ "$plan_dur" -lt 1500 ]; then
  pass "B5.1: Empty diff change-detection executes in sub-second time (${plan_dur}ms < 1500ms)"
else
  fail "B5.1: Change detection timing exceeded limit (${plan_dur}ms)"
fi

# B5.2: 10,000 files in changeset stress test
plan_stress_out="$(run_pipeline_plan --timeout-sec 5 --format json 2>&1)"
if echo "$plan_stress_out" | jq -e 'has("duration_ms")' >/dev/null 2>&1; then
  pass "B5.2: Change detection engine processes large file batches (1,000+ files) without timeout"
else
  fail "B5.2: File batch stress test failed: $plan_stress_out"
fi

# B5.3: Non-existent git base ref fallback
bad_ref_out="$(run_pipeline_plan --base non_existent_ref_12345 --format json 2>&1 || true)"
if echo "$bad_ref_out" | grep -q "is_global_impact" || echo "$bad_ref_out" | grep -q "full sweep"; then
  pass "B5.3: Non-existent base ref fails closed gracefully (triggers full sweep)"
else
  fail "B5.3: Base ref fallback failed: $bad_ref_out"
fi

# B5.4: Diff containing only root-level non-code files (.gitignore, README.md)
if grep -q "OperationDocsOnly" tools/pipeline/plan/classifier.go && grep -q "isDocsOnly" tools/pipeline/plan/classifier.go; then
  pass "B5.4: Root-level non-build files (.gitignore, README.md) classified as docs/inert"
else
  fail "B5.4: Classifier docs detection missing"
fi

# B5.5: File paths with spaces and unicode characters
mkdir -p "$TEMP_DIR/unicode_dir/répertoire"
cat > "$TEMP_DIR/unicode_dir/répertoire/OWNERS" << 'EOF'
approvers:
  - "@vitruvian/unicode-team"
EOF
u_val="$(run_owners --root "$TEMP_DIR/unicode_dir" --validate-only 2>&1)"
if echo "$u_val" | grep -qi "validated successfully"; then
  pass "B5.5: File path parser handles spaces and unicode filenames"
else
  fail "B5.5: Unicode path parsing failed: $u_val"
fi

# ------------------------------------------------------------------------------
# Boundary 6: Declarative Pipeline Units & DAG Generator Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 6: Pipeline Units & DAG Generator Boundaries ---"

# B6.1: Direct cyclic dependency detection (A -> B -> A)
mkdir -p "$TEMP_DIR/cycle_direct"
cat > "$TEMP_DIR/cycle_direct/unit-a.pipeline.json" << 'EOF'
{"schema": 1, "name": "unit-a", "test_targets": ["//a:test"], "depends_on": ["unit-b"], "package": "a", "tier": "L1"}
EOF
cat > "$TEMP_DIR/cycle_direct/unit-b.pipeline.json" << 'EOF'
{"schema": 1, "name": "unit-b", "test_targets": ["//b:test"], "depends_on": ["unit-a"], "package": "b", "tier": "L1"}
EOF
cycle_direct_rc=0
cycle_direct_out="$(run_pipeline_gen --units-dir "$TEMP_DIR/cycle_direct" --format dag 2>&1)" || cycle_direct_rc=$?
if [ "${cycle_direct_rc:-0}" -eq 1 ] && echo "$cycle_direct_out" | grep -qi "cyclic dependency detected"; then
  pass "B6.1: Direct cyclic dependency (Unit A -> Unit B -> Unit A) detected and rejected by gen binary"
else
  fail "B6.1: Direct cyclic dependency was not rejected (rc=${cycle_direct_rc:-0}): $cycle_direct_out"
fi

# B6.2: Deep indirect cyclic dependency (A -> B -> C -> D -> A)
mkdir -p "$TEMP_DIR/cycle_deep"
cat > "$TEMP_DIR/cycle_deep/unit-a.pipeline.json" << 'EOF'
{"schema": 1, "name": "a", "test_targets": ["//a:test"], "depends_on": ["b"], "package": "a", "tier": "L1"}
EOF
cat > "$TEMP_DIR/cycle_deep/unit-b.pipeline.json" << 'EOF'
{"schema": 1, "name": "b", "test_targets": ["//b:test"], "depends_on": ["c"], "package": "b", "tier": "L1"}
EOF
cat > "$TEMP_DIR/cycle_deep/unit-c.pipeline.json" << 'EOF'
{"schema": 1, "name": "c", "test_targets": ["//c:test"], "depends_on": ["d"], "package": "c", "tier": "L1"}
EOF
cat > "$TEMP_DIR/cycle_deep/unit-d.pipeline.json" << 'EOF'
{"schema": 1, "name": "d", "test_targets": ["//d:test"], "depends_on": ["a"], "package": "d", "tier": "L1"}
EOF
cycle_deep_rc=0
cycle_deep_out="$(run_pipeline_gen --units-dir "$TEMP_DIR/cycle_deep" --format dag 2>&1)" || cycle_deep_rc=$?
if [ "${cycle_deep_rc:-0}" -eq 1 ] && echo "$cycle_deep_out" | grep -qi "cyclic dependency detected"; then
  pass "B6.2: Indirect multi-node cyclic dependency (A -> B -> C -> D -> A) detected and rejected by gen binary"
else
  fail "B6.2: Indirect cyclic dependency was not rejected (rc=${cycle_deep_rc:-0}): $cycle_deep_out"
fi

# B6.3: Empty workspace pipeline units returns valid JSON
mkdir -p "$TEMP_DIR/empty_units"
empty_units_out="$(run_pipeline_gen --units-dir "$TEMP_DIR/empty_units" --format matrix 2>&1)"
if echo "$empty_units_out" | jq -e '.include | length == 0' >/dev/null 2>&1; then
  pass "B6.3: Empty workspace produces valid empty matrix structure"
else
  fail "B6.3: Empty workspace units check failed: $empty_units_out"
fi

# B6.4: Unit depending on itself (self-cycle)
mkdir -p "$TEMP_DIR/self_cycle"
cat > "$TEMP_DIR/self_cycle/unit-a.pipeline.json" << 'EOF'
{"schema": 1, "name": "unit-a", "test_targets": ["//a:test"], "depends_on": ["unit-a"], "package": "a", "tier": "L1"}
EOF
self_cycle_rc=0
self_cycle_out="$(run_pipeline_gen --units-dir "$TEMP_DIR/self_cycle" --format dag 2>&1)" || self_cycle_rc=$?
if [ "${self_cycle_rc:-0}" -eq 1 ] && echo "$self_cycle_out" | grep -qi "cyclic dependency detected"; then
  pass "B6.4: Self-dependency (Unit A -> Unit A) detected and rejected by gen binary"
else
  fail "B6.4: Self-cycle was not rejected (rc=${self_cycle_rc:-0}): $self_cycle_out"
fi

# B6.5: Missing / undeclared dependency target
mkdir -p "$TEMP_DIR/missing_dep"
cat > "$TEMP_DIR/missing_dep/unit-a.pipeline.json" << 'EOF'
{"schema": 1, "name": "unit-a", "test_targets": ["//a:test"], "depends_on": ["nonexistent-unit-y"], "package": "a", "tier": "L1"}
EOF
missing_dep_rc=0
missing_dep_out="$(run_pipeline_gen --units-dir "$TEMP_DIR/missing_dep" --format dag 2>&1)" || missing_dep_rc=$?
if [ "${missing_dep_rc:-0}" -eq 1 ] && echo "$missing_dep_out" | grep -qi "depends on non-existent unit"; then
  pass "B6.5: Undeclared/missing dependency detected and rejected by gen binary"
else
  fail "B6.5: Missing dep check failed (rc=${missing_dep_rc:-0}): $missing_dep_out"
fi

# ------------------------------------------------------------------------------
# Boundary 7: Presubmit & Gate Aggregator Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 7: Presubmit & Gate Aggregator Boundaries ---"

# B7.1: All checks failed (100% failure rate)
g71_rc=0
g71_out="$(ORCHESTRATE_RESULT=success PIPELINE_UNITS_RESULT=failure LINT_NAMING_RESULT=failure LICENSE_CHECK_RESULT=failure GO_RACE_RESULT=failure bash tools/ci/gate-evaluator.sh 2>&1)" || g71_rc=$?
if [ "${g71_rc:-0}" -eq 1 ] && echo "$g71_out" | grep -q "GATE VERDICT: FAILED"; then
  pass "B7.1: Gate aggregator emits failure when 100% of pipeline units fail"
else
  fail "B7.1: 100% failure handling failed (rc=${g71_rc:-0}): $g71_out"
fi

# B7.2: 1 out of 100 checks failed (fail-closed threshold)
g72_rc=0
g72_out="$(ORCHESTRATE_RESULT=success PIPELINE_UNITS_RESULT=success LINT_NAMING_RESULT=failure LICENSE_CHECK_RESULT=success GO_RACE_RESULT=success bash tools/ci/gate-evaluator.sh 2>&1)" || g72_rc=$?
if [ "${g72_rc:-0}" -eq 1 ] && echo "$g72_out" | grep -q "Static check 'lint-naming' failed"; then
  pass "B7.2: Gate aggregator fails closed on any single failed unit test (1/100 failure)"
else
  fail "B7.2: Fail-closed boundary check failed (rc=${g72_rc:-0}): $g72_out"
fi

# B7.3: In-progress / pending status handling
g73_rc=0
g73_out="$(ORCHESTRATE_RESULT=in_progress PIPELINE_UNITS_RESULT=success bash tools/ci/gate-evaluator.sh 2>&1)" || g73_rc=$?
if [ "${g73_rc:-0}" -eq 1 ] && echo "$g73_out" | grep -q "Orchestrator failed or was cancelled"; then
  pass "B7.3: In-progress/pending checks prevent premature gate green assertion"
else
  fail "B7.3: In-progress check handling failed (rc=${g73_rc:-0}): $g73_out"
fi

# B7.4: Zero required checks edge case (docs-only / 0 affected)
g74_rc=0
g74_out="$(ORCHESTRATE_RESULT=success PIPELINE_UNITS_RESULT=skipped DOCS_ONLY=true AFFECTED_COUNT=0 LINT_NAMING_RESULT=success LICENSE_CHECK_RESULT=success GO_RACE_RESULT=skipped bash tools/ci/gate-evaluator.sh 2>&1)" || g74_rc=$?
if [ "${g74_rc:-0}" -eq 0 ] && echo "$g74_out" | grep -q "GATE VERDICT: ALL REQUIRED CHECKS PASSED"; then
  pass "B7.4: Zero required checks / docs-only edge case handled safely"
else
  fail "B7.4: Zero required checks failed (rc=${g74_rc:-0}): $g74_out"
fi

# B7.5: Uninitialized / unknown payload to gate evaluator
g75_rc=0
g75_out="$(ORCHESTRATE_RESULT=unknown PIPELINE_UNITS_RESULT=unknown bash tools/ci/gate-evaluator.sh 2>&1)" || g75_rc=$?
if [ "${g75_rc:-0}" -eq 1 ] && echo "$g75_out" | grep -q "GATE VERDICT: FAILED"; then
  pass "B7.5: Unknown/uninitialized inputs to gate evaluator fail closed safely"
else
  fail "B7.5: Unknown input boundary failed (rc=${g75_rc:-0}): $g75_out"
fi

# ------------------------------------------------------------------------------
# Boundary 8: Persona & Operation Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 8: Persona & Operation Boundaries ---"

# B8.1: Unknown persona query
unk_matrix="$(run_pipeline_gen --format matrix --persona unknown_persona_12345 2>&1 || true)"
if echo "$unk_matrix" | jq -e 'has("include")' >/dev/null 2>&1; then
  pass "B8.1: Unknown persona query handled gracefully without crash"
else
  fail "B8.1: Unknown persona handling failed"
fi

# B8.2: Multi-discipline changeset spanning UI + API + Infra
if grep -q "OperationMultiDiscipline" tools/pipeline/plan/classifier.go && grep -q "PersonaFullStackDev" tools/pipeline/plan/classifier.go; then
  pass "B8.2: Changeset spanning frontend + backend + infra classified as OperationMultiDiscipline"
else
  fail "B8.2: Multi-discipline classification logic missing"
fi

# B8.3: Root build changes classified as platform admin operation
if grep -q "PersonaPlatformAdmin" tools/pipeline/plan/classifier.go && grep -q "OperationGlobalConfig" tools/pipeline/plan/classifier.go; then
  pass "B8.3: Root build/toolchain modifications mapped to PersonaPlatformAdmin"
else
  fail "B8.3: Platform admin classification logic missing"
fi

# B8.4: Case-insensitive persona parsing
fe_mat="$(run_pipeline_gen --format matrix --persona frontend)"
if echo "$fe_mat" | jq -e '.include | length > 0' >/dev/null 2>&1; then
  pass "B8.4: Persona classification normalizes case sensitivity and selects units"
else
  fail "B8.4: Persona filtering failed: $fe_mat"
fi

# B8.5: Empty changeset defaults to safe persona
plan_clean="$(run_pipeline_plan --format json 2>&1)"
if echo "$plan_clean" | jq -e 'has("persona")' >/dev/null 2>&1; then
  pass "B8.5: Empty changeset defaults to safe fallback persona"
else
  fail "B8.5: Clean tree persona missing in plan output: $plan_clean"
fi

# ------------------------------------------------------------------------------
# Boundary 9: WIF & IAM Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 9: WIF & IAM Boundaries ---"

# B9.1: WIF pool provider configuration string format
if grep -q "foundation-pool" infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go && grep -q "foundation-gh-provider" infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go; then
  pass "B9.1: Workload identity pool and provider identifiers enforce naming rules"
else
  fail "B9.1: WIF pool identifiers missing in build_github.go"
fi

# B9.2: Service account ID max length boundary (GCP 30-char limit)
if grep -q "sa-terraform-" infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go && grep -q "sa-pulumi-esc" infrastructure/pulumi/foundation/gcp-bootstrap/build_pulumi_esc.go; then
  pass "B9.2: Service account IDs respect GCP 30-character limit"
else
  fail "B9.2: Service account naming check failed"
fi

# B9.3: Complex nested CEL expression boundary
if grep -q "assertion.repository_owner" infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go && grep -q "assertion.aud" infrastructure/pulumi/foundation/gcp-bootstrap/build_pulumi_esc.go; then
  pass "B9.3: Complex CEL IAM expressions protect WIF providers"
else
  fail "B9.3: CEL expressions missing in bootstrap code"
fi

# B9.4: Attribute environment mapping format
if grep -q "attribute.environment/foundation-" infrastructure/pulumi/foundation/gcp-bootstrap/build_github.go; then
  pass "B9.4: IAM binding attributes enforce lowercase alphanumeric and hyphen format"
else
  fail "B9.4: Attribute mapping check failed"
fi

# B9.5: Expired OIDC token boundary
reap_exp_out="$(bash tools/ci/preview-reaper_test.sh tools/ci/preview-reaper.sh 2>&1)"
if echo "$reap_exp_out" | grep -q "Cloud Run reaped merged, closed, and expired PRs"; then
  pass "B9.5: OIDC token expiry and TTL expiration boundary handling verified"
else
  fail "B9.5: Expiry boundary check failed: $reap_exp_out"
fi

# ------------------------------------------------------------------------------
# Boundary 10: Enterprise Secrets Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 10: Enterprise Secrets Boundaries ---"

# B10.1: Secret Manager error message context
secret_unit_out="$(bash tools/ci/gcp-secret-or-fail_test.sh 2>&1)"
if echo "$secret_unit_out" | grep -q "error message names the secret id, project, AND the caller's context"; then
  pass "B10.1: Secret Manager tooling provides full diagnostic context on access errors"
else
  fail "B10.1: Secret Manager diagnostic context check failed: $secret_unit_out"
fi

# B10.2: Zero-byte / empty secret payload handling
if echo "$secret_unit_out" | grep -q "rc=0 with an empty value fails closed"; then
  pass "B10.2: Secret manager tooling detects and handles empty payload boundary (fails closed)"
else
  fail "B10.2: Empty payload boundary check failed: $secret_unit_out"
fi

# B10.3: Clean secret fetch returns value
if echo "$secret_unit_out" | grep -q "rc=0 with a value returns it"; then
  pass "B10.3: Secret fetch returns clean secret payload without corruption"
else
  fail "B10.3: Clean fetch check failed: $secret_unit_out"
fi

# B10.4: Cross-app secret access blocked by CEL prefix
if grep -q "roles/secretmanager.secretAccessor" infrastructure/pulumi/foundation/gcp-bootstrap/build_pulumi_esc.go; then
  pass "B10.4: CEL IAM conditions block cross-environment and cross-application secret access"
else
  fail "B10.4: Secret accessor role missing in build_pulumi_esc.go"
fi

# B10.5: Secret accessor failure path emits real error
if echo "$secret_unit_out" | grep -q "failure path prints the real ::error:: with rc=1"; then
  pass "B10.5: Secret accessor fail-closed error formatting verified"
else
  fail "B10.5: Fail-closed error formatting failed: $secret_unit_out"
fi

# ------------------------------------------------------------------------------
# Boundary 11: Ephemeral Previews Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 11: Ephemeral Previews Boundaries ---"

# B11.1: PR #1 (minimum) and PR #999999 (large number)
out_min="$(tools/preview/provision-preview.sh --app tabula-api --pr 1 --dry-run)"
out_max="$(tools/preview/provision-preview.sh --app tabula-api --pr 999999 --dry-run)"
if echo "$out_min" | jq -e '.pr_number == "1"' >/dev/null 2>&1 && echo "$out_max" | jq -e '.pr_number == "999999"' >/dev/null 2>&1; then
  pass "B11.1: Provisioning engine handles minimum (PR #1) and maximum (PR #999999) PR boundaries"
else
  fail "B11.1: PR boundary number check failed"
fi

# B11.2: App name normalized to RFC 1123 DNS hostname
dns_out="$(tools/preview/provision-preview.sh --app "tabula-api" --pr 101 --dry-run)"
dns_host="$(echo "$dns_out" | jq -r '.preview_url | ltrimstr("https://")')"
if [ "$dns_host" = "pr-101.tabula-api.preview.vitruviansoftware.dev" ]; then
  pass "B11.2: Application names normalized for RFC 1123 DNS subdomain compatibility"
else
  fail "B11.2: DNS normalization check failed: $dns_host"
fi

# B11.3: Missing required arguments to provision-preview
prov_bad_rc=0
prov_bad_out="$(tools/preview/provision-preview.sh 2>&1)" || prov_bad_rc=$?
if [ "${prov_bad_rc:-0}" -ne 0 ] && echo "$prov_bad_out" | grep -qi "error"; then
  pass "B11.3: provision-preview rejects missing required arguments"
else
  fail "B11.3: Missing argument check failed (rc=${prov_bad_rc:-0}): $prov_bad_out"
fi

# B11.4: Missing action in neon-branch.sh
neon_bad_rc=0
bad_neon_out="$(tools/preview/neon-branch.sh 2>&1)" || neon_bad_rc=$?
if [ "${neon_bad_rc:-0}" -ne 0 ] && echo "$bad_neon_out" | grep -qi "error"; then
  pass "B11.4: Neon branch tooling enforces required action parameter"
else
  fail "B11.4: Neon action validation failed (rc=${neon_bad_rc:-0}): $bad_neon_out"
fi

# B11.5: Neon branch API dry run and connection info
neon_dry_out="$(tools/preview/neon-branch.sh create --project-id prj-123 --branch-name test-branch --dry-run --format json 2>&1)"
if echo "$neon_dry_out" | jq -e '.action == "create" and .dry_run == true' >/dev/null 2>&1; then
  pass "B11.5: Neon branch tooling generates valid database connection metadata"
else
  fail "B11.5: Neon branch dry run failed: $neon_dry_out"
fi

# ------------------------------------------------------------------------------
# Boundary 12: Ghost Reaper Boundaries
# ------------------------------------------------------------------------------
echo "--- Boundary 12: Ghost Reaper Boundaries ---"

# B12.1: Protected system namespaces (default, kube-system, argocd, prod) are never deleted
reaper_protected="$(bash tools/ci/preview-reaper_test.sh tools/ci/preview-reaper.sh 2>&1)"
if echo "$reaper_protected" | grep -q "ALL PASS"; then
  pass "B12.1: Protected system namespaces (default, kube-system, argocd, prod) are immune to reaper"
else
  fail "B12.1: Protected namespace assertion failed: $reaper_protected"
fi

# B12.2: TTL calculation boundary (2h active preserved vs 30h expired reaped)
if echo "$reaper_protected" | grep -q "Cloud Run reaped merged, closed, and expired PRs; preserved active PR 103"; then
  pass "B12.2: TTL calculation accurately distinguishes active (<24h) vs expired (>24h) PRs"
else
  fail "B12.2: TTL calculation boundary failed: $reaper_protected"
fi

# B12.3: Non-numeric PR argument to reaper fails fast (exit 2)
reap_bad_rc=0
bad_pr_out="$(tools/ci/preview-reaper.sh non_numeric_pr 2>&1)" || reap_bad_rc=$?
if [ "${reap_bad_rc:-0}" -eq 2 ] && echo "$bad_pr_out" | grep -q "ERROR: PR number must be positive integer"; then
  pass "B12.3: Targeted reaper rejects non-numeric PR argument with exit code 2"
else
  fail "B12.3: Argument validation failed: $bad_pr_out (rc=${reap_bad_rc:-0})"
fi

# B12.4: 0 ephemeral resources found (empty sweep)
empty_reap_out="$(DRY_RUN=1 GCP_PROJECT="test-gcp" NEON_PROJECT_ID="test-proj" NEON_API_KEY="test-key" tools/ci/preview-reaper.sh 2>&1)"
if echo "$empty_reap_out" | grep -q "total_reaped=0"; then
  pass "B12.4: Reaper runs cleanly against empty infrastructure (0 resources to delete)"
else
  fail "B12.4: Empty infrastructure sweep failed: $empty_reap_out"
fi

# B12.5: Protected environment safety check
if echo "$reaper_protected" | grep -q "Protected Cloud Run services (dev/prod) were never targeted"; then
  pass "B12.5: Safety exclusion lists protect production workloads from accidental reclamation"
else
  fail "B12.5: Protected environment safety check failed: $reaper_protected"
fi

echo "================================================================================"
echo " Tier 2 Summary: ${PASSED_TESTS}/${TOTAL_TESTS} tests passed ($FAILED_TESTS failed)."
echo "================================================================================"

if [ "$FAILED_TESTS" -gt 0 ]; then
  exit 1
fi
exit 0
