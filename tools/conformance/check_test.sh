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
# Regression guard for the check.sh arms whose failure mode is SILENCE — today
# `check_merge_queue`'s trigger-filter arm and `check_renovate_schedule`
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
  # A conforming renovate.json5 (no `schedule:`), so check_renovate_schedule is
  # neutral for every case that is not about it. The cases that ARE about it
  # overwrite or remove this file.
  printf '{\n  enabledManagers: ["argocd"],\n}\n' > "$root/renovate.json5"
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

# --- case 5..8: check_renovate_schedule --------------------------------------
# A config-side `schedule:` window is invisible in every signal the repo has: the
# workflow goes green, Renovate logs `"result": "done"`, and no PR is ever
# opened. The only way to notice is to compare pins against upstream by hand,
# which nobody does — so the invariant has to be enforced, and the enforcement
# has to be tested, or it is one more control that merely *looks* present.
#
# Same hermetic ROOT as above; only renovate.json5 varies.
renovate_line() {
  printf '%s\n' "$1" | awk '
    /^Renovate cadence/ {in_s=1; next}
    in_s && /^[A-Za-z]/ && !/^ / {in_s=0}
    in_s && index($0, "renovate.json5") {print; exit}
  '
}

# The broken state this whole change exists to kill.
case_renovate_schedule_present() {
  root="$(new_root)"
  printf '{\n  enabledManagers: ["argocd"],\n  schedule: ["before 6am on monday"],\n  timezone: "UTC",\n}\n' \
    > "$root/renovate.json5"
  out="$(run_check "$root")"
  expect "a config-side schedule: window is reported as a failure" \
    "$(renovate_line "$out")" "✗"
  rm -rf "$root"
}

# The fixed state.
case_renovate_no_schedule() {
  root="$(new_root)"
  printf '{\n  enabledManagers: ["argocd"],\n  prConcurrentLimit: 3,\n}\n' > "$root/renovate.json5"
  out="$(run_check "$root")"
  expect "a config with no schedule passes" \
    "$(renovate_line "$out")" "no schedule"
  rm -rf "$root"
}

# The trap: the fixed config MUST explain why the key is absent, and that prose
# necessarily contains the string `schedule:`. A naive grep would fail the very
# file it is meant to bless — a green control turned red on correct input, which
# is how this kind of guard gets deleted instead of fixed.
case_renovate_schedule_in_comment() {
  root="$(new_root)"
  printf '{\n  enabledManagers: ["argocd"],\n  // NO `schedule`. This previously read\n  // schedule: ["before 6am on monday"], which no-opped every run.\n}\n' \
    > "$root/renovate.json5"
  out="$(run_check "$root")"
  expect "schedule: mentioned only inside a // comment does NOT trip the check" \
    "$(renovate_line "$out")" "no schedule"
  rm -rf "$root"
}

# Deleting the config while the workflow still requires one must be loud, not a
# silent early return that reads as a pass.
case_renovate_config_missing() {
  root="$(new_root)"
  rm -f "$root/renovate.json5"
  out="$(run_check "$root")"
  expect "a missing renovate.json5 fails rather than passing vacuously" \
    "$(renovate_line "$out")" "missing"
  rm -rf "$root"
}

# --- pnpm build pin: promoted from advisory to FAILING (#1501) ---------------
#
# As an advisory this rule named the exact defect that then occurred (#1500: the
# image fetched pnpm 11.20.0 against a repo pinned to 10.20.0 and the build
# broke), was read by the person it would have helped, and was skipped precisely
# because it could not refuse.
#
# It could not simply be promoted: as written it knew ONE mechanism -- a
# packageManager key in the Dockerfile's own directory -- and BOTH images it
# flagged were correctly pinned by other means, so promoting it unchanged would
# have failed the build on two false positives.
#
# ASSERT ON "pinned via", NEVER ON THE BARE MECHANISM NAME. The failure note
# lists every mechanism it looked for -- "no corepack prepare pnpm@..., no root
# package.json copied in" -- so a pattern like *"corepack prepare"* matches the
# FAILURE too and the assertion silently passes either way. A first draft of
# these cases did exactly that and survived all three mutations.
pnpm_pin_line() { # <output> <dir>
  printf '%s\n' "$1" | grep -E "${2}/Dockerfile" | grep -E 'pinned via|unpinned' | head -1
}

case_pnpm_pin_own_manifest() {
  root="$(new_root)"; mkdir -p "$root/app"
  printf 'FROM node:22\nRUN corepack enable\nRUN pnpm i\n' > "$root/app/Dockerfile"
  printf '{"name":"a","packageManager":"pnpm@10.20.0"}\n' > "$root/app/package.json"
  expect "a co-located packageManager pin passes" \
    "$(pnpm_pin_line "$(run_check "$root")" app)" "pinned via app/package.json packageManager"
  rm -rf "$root"
}

case_pnpm_pin_corepack_prepare() {
  # mcp-slack's mechanism: its package.json is the npm-PUBLISHED manifest, so a
  # corepack pin there would change the mirror's release path. It pins in the
  # Dockerfile instead, which is equally a pin.
  root="$(new_root)"; mkdir -p "$root/app"
  printf 'FROM node:22\nRUN corepack enable && corepack prepare "pnpm@10.20.0" --activate\nRUN pnpm i\n' > "$root/app/Dockerfile"
  expect "a corepack prepare pin passes with no co-located manifest" \
    "$(pnpm_pin_line "$(run_check "$root")" app)" "pinned via corepack prepare"
  rm -rf "$root"
}

case_pnpm_pin_root_copy() {
  # tabula/web's mechanism: it COPYs the ROOT package.json, which carries the
  # repo-wide pin, into the workdir corepack reads from.
  root="$(new_root)"; mkdir -p "$root/app"
  printf 'FROM node:22\nRUN corepack enable\nCOPY package.json ./\nRUN pnpm i\n' > "$root/app/Dockerfile"
  expect "copying the pinned root package.json passes" \
    "$(pnpm_pin_line "$(run_check "$root")" app)" "pinned via the root package.json"
  rm -rf "$root"
}

case_pnpm_unpinned_fails() {
  root="$(new_root)"; mkdir -p "$root/app"
  printf 'FROM node:22\nRUN corepack enable\nRUN pnpm i\n' > "$root/app/Dockerfile"
  line="$(pnpm_pin_line "$(run_check "$root")" app)"
  expect "an unpinned pnpm Dockerfile is reported unpinned" "$line" "unpinned"
  # ...as a ✗, not a ⚠. Asserting only on the word "unpinned" lets someone
  # downgrade this rule back to an advisory with no test objecting -- which is
  # the precise regression #1501 exists to prevent, and which survived the
  # first draft of these cases.
  expect "...and as a FAILING row, not an advisory" "$line" "✗"
  rm -rf "$root"
}

# Every ✗ row must also FAIL THE RUN -- for every rule, not only this one.
#
# OVERALL_FAIL is what the exit code and the banner are keyed on; FAIL_COUNT
# only feeds the summary line. A rule that increments the counter alone renders
# "✓ PASS — ... 1 fail": it reports a defect and cannot refuse it, which is the
# entire subject of #1501. I shipped exactly that into the pnpm rule below and
# caught it only by running the negative case by hand.
#
# This cannot be asserted through run_check: a scratch ROOT has none of the real
# repo's BUILD files, so ~22 unrelated rules fail and EVERY scratch run exits 1
# -- an exit-code assertion would pass regardless of what any rule did (proven:
# a first draft asserted rc=1 here and held even with the bug reintroduced). So
# it is checked structurally against the source, where it holds for all 69
# fail-emit sites today.
case_every_fail_emit_sets_overall_fail() {
  offenders="$(awk '
    /emit .*GLYPH_FAIL/ { site = NR; found = 0 }
    site && NR > site && NR <= site + 10 && /OVERALL_FAIL=1/ { found = 1 }
    site && NR == site + 10 { if (!found) print site; site = 0 }
    END { if (site && !found) print site }
  ' "$CHECK_SH" | tr "\n" " ")"
  expect "every ✗ emit also sets OVERALL_FAIL (a ✗ must fail the run)" \
    "offenders=[${offenders% }]" "offenders=[]"
}

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

# --- case 5..8: check_renovate_schedule --------------------------------------
# A config-side `schedule:` window is invisible in every signal the repo has: the
# workflow goes green, Renovate logs `"result": "done"`, and no PR is ever
# opened. The only way to notice is to compare pins against upstream by hand,
# which nobody does — so the invariant has to be enforced, and the enforcement
# has to be tested, or it is one more control that merely *looks* present.
#
# Same hermetic ROOT as above; only renovate.json5 varies.
renovate_line() {
  printf '%s\n' "$1" | awk '
    /^Renovate cadence/ {in_s=1; next}
    in_s && /^[A-Za-z]/ && !/^ / {in_s=0}
    in_s && index($0, "renovate.json5") {print; exit}
  '
}

# The broken state this whole change exists to kill.
case_renovate_schedule_present() {
  root="$(new_root)"
  printf '{\n  enabledManagers: ["argocd"],\n  schedule: ["before 6am on monday"],\n  timezone: "UTC",\n}\n' \
    > "$root/renovate.json5"
  out="$(run_check "$root")"
  expect "a config-side schedule: window is reported as a failure" \
    "$(renovate_line "$out")" "✗"
  rm -rf "$root"
}

# The fixed state.
case_renovate_no_schedule() {
  root="$(new_root)"
  printf '{\n  enabledManagers: ["argocd"],\n  prConcurrentLimit: 3,\n}\n' > "$root/renovate.json5"
  out="$(run_check "$root")"
  expect "a config with no schedule passes" \
    "$(renovate_line "$out")" "no schedule"
  rm -rf "$root"
}

# The trap: the fixed config MUST explain why the key is absent, and that prose
# necessarily contains the string `schedule:`. A naive grep would fail the very
# file it is meant to bless — a green control turned red on correct input, which
# is how this kind of guard gets deleted instead of fixed.
case_renovate_schedule_in_comment() {
  root="$(new_root)"
  printf '{\n  enabledManagers: ["argocd"],\n  // NO `schedule`. This previously read\n  // schedule: ["before 6am on monday"], which no-opped every run.\n}\n' \
    > "$root/renovate.json5"
  out="$(run_check "$root")"
  expect "schedule: mentioned only inside a // comment does NOT trip the check" \
    "$(renovate_line "$out")" "no schedule"
  rm -rf "$root"
}

# Deleting the config while the workflow still requires one must be loud, not a
# silent early return that reads as a pass.
case_renovate_config_missing() {
  root="$(new_root)"
  rm -f "$root/renovate.json5"
  out="$(run_check "$root")"
  expect "a missing renovate.json5 fails rather than passing vacuously" \
    "$(renovate_line "$out")" "missing"
  rm -rf "$root"
}


case_branches_filter
case_push_only_branches
case_paths_filter_unchanged
case_both_filters
case_renovate_schedule_present
case_renovate_no_schedule
case_renovate_schedule_in_comment
case_renovate_config_missing
case_pnpm_pin_own_manifest
case_pnpm_pin_corepack_prepare
case_pnpm_pin_root_copy
case_pnpm_unpinned_fails
case_every_fail_emit_sets_overall_fail

printf '\n%d/%d assertions passed\n' "$((CASES - FAILURES))" "$CASES"
[ "$FAILURES" -eq 0 ] || exit 1
