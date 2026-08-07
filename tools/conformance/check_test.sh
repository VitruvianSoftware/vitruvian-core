#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Regression guard for check.sh's `check_merge_queue` trigger-filter arm
# (docs/engineering/application-development-principles.md:200-204 — a fix ships
# with the test that fails without it).
#
# WHAT IS UNDER TEST, and why it needs a test at all: this arm is the guard that
# certifies "every required merge-queue check reports on merge_group AND on every
# PR". It is not a control that can merely be absent — it PRINTS a verdict, so a
# parser gap makes it print `✓ reports on merge_group + every PR` about a check
# that does not. That is what happened: the arm matched only `paths:`/
# `paths-ignore:` and was blind to a workflow-level `pull_request: branches:`,
# which has the identical never-reports effect on a PR whose base is not in the
# list. 13 of 15 required checks carried one, so stacked PRs drew 2 real contexts
# and displayed green (#1422 is the observed instance: GitHub auto-retargeted its
# base to `main` AFTER the last pull_request event, leaving 13 required contexts
# permanently uncreated and the PR unmergeable with nothing red to look at).
#
# The parser is INDENT-POSITIONAL (`I==2` for a trigger key, `I>=4` for its
# options), so the way to get this subtly wrong is to match a `branches:` that
# belongs to `push:` — which would fail in the safe-looking direction, flagging
# a workflow that is in fact fine. case_push_only_branches covers exactly that.
#
# Hermetic by construction: every case builds a throwaway ROOT holding only the
# inputs check_merge_queue reads (a repo_config main.go for the required set and
# .github/workflows/ for the producible set), plus the minimum canonical-version
# files check.sh needs to reach that arm at all. Nothing is copied from the real
# tree, so a workflow change elsewhere in the repo cannot flip these assertions.
set -uo pipefail

CHECK_SH="$(cd "$(dirname "$0")" && pwd)/check.sh"
[ -f "$CHECK_SH" ] || { echo "FATAL: check.sh not found next to $0" >&2; exit 1; }

FAILURES=0
CASES=0

# Build a throwaway ROOT: the canonical-version files check.sh reads before it
# reaches check_merge_queue, plus an empty pin registry. Values are arbitrary —
# nothing here is asserted on, they only have to parse.
new_root() {
  root="$(mktemp -d)"
  mkdir -p "$root/.github/workflows" \
           "$root/infrastructure/pulumi/platform/repo_config" \
           "$root/tools/conformance"
  printf 'go 1.26.2\n' > "$root/go.work"
  printf '22\n' > "$root/.nvmrc"
  printf '{\n  "packageManager": "pnpm@10.20.0"\n}\n' > "$root/package.json"
  printf '# file\ttool\tpinned_value\treview_by\treason\n' > "$root/tools/conformance/version-pins.tsv"
  printf '%s' "$root"
}

# Declare the required-check set the way repo_config does, so the real scraper
# (comment-stripping and all) is the thing that reads it.
declare_required() {
  root="$1"; shift
  {
    printf 'package main\n\nvar checks = []string{\n'
    for c in "$@"; do printf '\t"%s",\n' "$c"; done
    printf '}\n'
  } > "$root/infrastructure/pulumi/platform/repo_config/main.go"
}

# A workflow producing one merge_group-eligible job named $2, with $3 spliced in
# verbatim as the `pull_request` trigger body.
write_workflow() {
  root="$1"; job="$2"; pr_trigger="$3"
  {
    printf 'name: %s\non:\n  push:\n    branches: [main]\n' "$job"
    printf '%b' "$pr_trigger"
    printf '  merge_group:\njobs:\n  %s:\n    runs-on: ubuntu-latest\n    steps:\n      - run: "true"\n' "$job"
  } > "$root/.github/workflows/$job.yaml"
}

# Only the merge-queue section's line for $2 — the other sections of check.sh
# are irrelevant here and must not be able to influence the verdict.
mergeq_line() {
  out="$1"; ctx="$2"
  printf '%s\n' "$out" | awk -v c="$ctx" '
    /^Merge-queue required checks/ {in_s=1; next}
    in_s && /^[A-Za-z]/ && !/^ / {in_s=0}
    in_s && index($0, " " c " ") {print; exit}
  '
}

expect() {
  desc="$1"; line="$2"; want="$3"
  CASES=$((CASES + 1))
  case "$line" in
    *"$want"*) printf 'PASS  %s\n' "$desc" ;;
    *)
      printf 'FAIL  %s\n      want substring: %s\n      got line:       %s\n' \
        "$desc" "$want" "${line:-<no merge-queue line emitted>}"
      FAILURES=$((FAILURES + 1))
      ;;
  esac
}

run_check() { BUILD_WORKSPACE_DIRECTORY="$1" bash "$CHECK_SH" 2>&1; }

# --- case 1: pull_request `branches:` on a required check is the wedge --------
# The whole point of the fix. Without it this line reads "producible".
case_branches_filter() {
  root="$(new_root)"
  declare_required "$root" branches-filtered no-filter
  write_workflow "$root" branches-filtered '  pull_request:\n    branches: [main]\n'
  write_workflow "$root" no-filter '  pull_request:\n'
  out="$(run_check "$root")"
  expect "pull_request branches: filter is reported as PR-RETARGET-BLOCKED" \
    "$(mergeq_line "$out" branches-filtered)" "PR-RETARGET-BLOCKED"
  expect "an unfiltered pull_request trigger stays producible" \
    "$(mergeq_line "$out" no-filter)" "producible"
  rm -rf "$root"
}

# --- case 2: the indent-positional trap ---------------------------------------
# `branches:` under `push:` is normal and correct on a required check. Matching
# it would fail in the safe-looking direction: a green control turned red for a
# workflow that reports on every PR exactly as it should.
case_push_only_branches() {
  root="$(new_root)"
  declare_required "$root" push-branches-only
  write_workflow "$root" push-branches-only '  pull_request:\n'
  out="$(run_check "$root")"
  expect "branches: under push: alone does NOT trip the pull_request check" \
    "$(mergeq_line "$out" push-branches-only)" "producible"
  rm -rf "$root"
}

# --- case 3: the paths: wedge still reports as its own, distinct failure -------
# Pre-existing behaviour. The two wedges need different fixes, so the fix text
# must not collapse into one message.
case_paths_filter_unchanged() {
  root="$(new_root)"
  declare_required "$root" paths-filtered
  write_workflow "$root" paths-filtered '  pull_request:\n    paths:\n      - "src/**"\n'
  out="$(run_check "$root")"
  expect "pull_request paths: filter still reports as PR-BLOCKED" \
    "$(mergeq_line "$out" paths-filtered)" "PR-BLOCKED"
  rm -rf "$root"
}

# --- case 4: both filters on one workflow are reported, not deduped -----------
# They have different remedies; silently emitting one hides half the work.
case_both_filters() {
  root="$(new_root)"
  declare_required "$root" both-filtered
  write_workflow "$root" both-filtered '  pull_request:\n    branches: [main]\n    paths:\n      - "src/**"\n'
  out="$(run_check "$root")"
  section="$(printf '%s\n' "$out" | awk '/^Merge-queue required checks/{in_s=1;next} in_s && /^[A-Za-z]/ && !/^ /{in_s=0} in_s')"
  expect "a workflow with both filters reports the branches: wedge" \
    "$section" "PR-RETARGET-BLOCKED"
  expect "a workflow with both filters also reports the paths: wedge" \
    "$section" "PR-BLOCKED"
  rm -rf "$root"
}

case_branches_filter
case_push_only_branches
case_paths_filter_unchanged
case_both_filters

printf '\n%d/%d assertions passed\n' "$((CASES - FAILURES))" "$CASES"
[ "$FAILURES" -eq 0 ] || exit 1
