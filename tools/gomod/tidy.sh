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
# tidy.sh — keep the `replace`-coupled Go modules' pins in sync.
#
#   bazel run //tools/gomod:tidy     # fix:   rewrite go.mod/go.sum in place
#   bazel run //tools/gomod:check    # gate:  report drift, change nothing
#
# WHY THIS EXISTS — the example modules duplicate the library's dep graph:
#   Every module under pulumi/examples/go-foundation consumes the library
#   through a `replace` to a LOCAL PATH, but still carries its own full pin of
#   the library's transitive graph (`google.golang.org/grpc v1.80.0 // indirect`
#   and friends) in its own go.mod/go.sum.
#
#   Nothing keeps those two copies in step. Dependabot tidies ONLY the module it
#   bumps -- it cannot see across a `replace` edge -- so bumping a library leaves
#   every example that consumes it unbuildable. That is not hypothetical: PRs
#   #1166/#1175/#1179 (grpc 1.80.0 -> 1.82.1) each red-lined `example-build`
#   this way, and the error the developer actually saw was:
#
#       go: updates to go.mod needed; to update it:
#           go mod tidy
#
#   -- which names no module, no dependency, and no PR. Three separate bumps
#   were diagnosed from scratch before the shared cause was obvious.
#
# WHAT THIS FIXES, AND WHAT IT DOES NOT:
#   This is the GATE, not the cure. It cannot stop a bump from desyncing the
#   examples; it makes the desync fail EARLY and LEGIBLY, against the module and
#   the diff that caused it, with the exact command that fixes it. The
#   complementary half lives in .github/dependabot.yml, which groups the library
#   and example directories into one update so a shared dependency moves on both
#   sides in the same PR -- that reduces how often this gate fires, but grouping
#   only covers deps that ALREADY exist in both go.mods, so it can never be the
#   whole answer. Hence both.
#
# WHY `go mod tidy -diff` AND NOT tidy-then-`git diff`:
#   -diff (Go 1.23+) computes the necessary changes and exits non-zero WITHOUT
#   writing. The tidy-then-diff alternative mutates the tree inside a required
#   check -- exactly the failure mode tools/osv-scan/osv-scan.sh documents at
#   length (a gate that rewrites go.work.sum corrupts the checkout it is
#   inspecting and reddens tidy-check two jobs later). Check mode here is
#   read-only by construction, not by convention.
#
# GOWORK=off, deliberately:
#   Same reason the rest of this repo's Go CI sets it. In workspace mode `go mod
#   tidy` resolves against the workspace, not the module's own requirements, so
#   it would compute a DIFFERENT (and wrong) answer than the standalone `go
#   build` that example-build runs -- and could normalise go.work.sum as a side
#   effect. The examples are also copybara-exported as standalone modules, so
#   the standalone resolution is the only one that matches how they ship.
set -euo pipefail

ROOT="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${ROOT}"

# See "GOWORK=off, deliberately" above. Exported so every `go` this script
# spawns inherits it; -mod=readonly keeps check mode honest even if a future
# edit adds a `go` invocation that would otherwise write.
export GOWORK=off

C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'
C_RESET=$'\033[0m'
[ -t 1 ] || { C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_RESET=""; }

GLYPH_OK="✓"
GLYPH_FAIL="✗"

# The `replace`-coupled set. Scoped rather than repo-wide on purpose: these are
# the modules whose pins are a FUNCTION of another in-tree module, so they are
# the ones that can silently desync. A repo-wide sweep would also drag in ~30
# independent app modules whose tidiness nothing here can affect, and pay their
# module-download cost on every run of a presubmit gate.
#
# A root is a SUBTREE (every go.mod under it) unless it ends in `/go.mod`, which
# names exactly one module. The exact form exists because the second coupled
# cluster is not subtree-shaped: `infrastructure/pulumi/pkg/secrets` is consumed
# through a local `replace` by exactly two modules -- the infra root module and
# platform/repo_config -- while the other 33 go.mods under infrastructure/pulumi
# form a SEPARATE cluster around `foundation/modules`. Taking
# `infrastructure/pulumi` as a subtree root would sweep all 35, including six
# gcp-app-infra modules that are already out of tidy on main today (their tidy
# would DROP `foundation-app-infra/modules` from require, which is a real
# question about what those stacks depend on and wants its own change, not a
# drive-by inside a Dependabot fix). Naming the two modules keeps this gate
# green on main while closing the hole that let the bump through.
#
# The hole was not hypothetical: Dependabot bumped grpc in pkg/secrets/go.mod
# alone (PR #1194 and siblings), both consumers desynced, and `go-test-infra`
# died with the same "go: updates to go.mod needed; to update it: go mod tidy"
# this tool was built to pre-empt -- while `bazel run //tools/gomod:check`
# reported every module tidy, because it was not looking at these two.
DEFAULT_ROOTS=(
  "pulumi/library/go"
  "pulumi/examples/go-foundation"
  "infrastructure/pulumi/go.mod"                # replaces ./pkg/secrets
  "infrastructure/pulumi/platform/repo_config"  # replaces ../../pkg/secrets
)

MODE="fix"
ROOTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --fix) MODE="fix" ;;
    -h | --help)
      sed -n '21,70p' "$0"
      exit 0
      ;;
    -*)
      printf '%s%s gomod%s — unknown flag: %s\n' \
        "$C_RED" "$GLYPH_FAIL" "$C_RESET" "$1" >&2
      exit 2
      ;;
    *) ROOTS+=("$1") ;;
  esac
  shift
done
[ ${#ROOTS[@]} -gt 0 ] || ROOTS=("${DEFAULT_ROOTS[@]}")

command -v go >/dev/null 2>&1 || {
  printf '%s%s gomod%s — go not on PATH. Install it (see `bazel run //:doctor`).\n' \
    "$C_RED" "$GLYPH_FAIL" "$C_RESET" >&2
  exit 1
}

# Collect modules up front so the count is known before any work: a run that
# finds zero modules is a broken invocation (wrong cwd, renamed tree), not a
# clean tree, and must never be allowed to report green.
mods=()
for root in "${ROOTS[@]}"; do
  # `<dir>/go.mod` names one module exactly; anything else is a subtree. Both
  # forms fail loudly when they match nothing -- a root that has been renamed
  # out from under this list must not silently shrink the covered set, which is
  # the same false-green this tool exists to prevent.
  case "$root" in
    */go.mod)
      [ -f "$root" ] || {
        printf '%s%s gomod%s — module does not exist: %s\n' \
          "$C_RED" "$GLYPH_FAIL" "$C_RESET" "$root" >&2
        exit 1
      }
      mods+=("$(dirname "$root")")
      ;;
    *)
      [ -d "$root" ] || {
        printf '%s%s gomod%s — root does not exist: %s\n' \
          "$C_RED" "$GLYPH_FAIL" "$C_RESET" "$root" >&2
        exit 1
      }
      while IFS= read -r mod; do
        mods+=("$(dirname "$mod")")
      done < <(find "$root" -name go.mod -not -path '*/vendor/*' | sort)
      ;;
  esac
done

if [ ${#mods[@]} -eq 0 ]; then
  printf '%s%s gomod%s — found no go.mod under: %s\n   Refusing to report green: this is a broken invocation, not a tidy tree.\n' \
    "$C_RED" "$GLYPH_FAIL" "$C_RESET" "${ROOTS[*]}" >&2
  exit 1
fi

printf '%s→%s %s %d module(s) under %s\n' \
  "$C_CYAN" "$C_RESET" \
  "$([ "$MODE" = check ] && echo "checking" || echo "tidying")" \
  "${#mods[@]}" "${ROOTS[*]}"

drifted=()
changed=0
for dir in "${mods[@]}"; do
  if [ "$MODE" = "check" ]; then
    # -diff writes the would-be patch to stdout and exits non-zero when the
    # module is out of date. Captured rather than streamed so a 27-module run
    # does not bury the summary under 27 diffs; the offenders are replayed
    # below.
    if ! diff_out="$(cd "$dir" && go mod tidy -diff 2>&1)"; then
      drifted+=("$dir")
      printf '%s%s%s %s\n' "$C_RED" "$GLYPH_FAIL" "$C_RESET" "$dir"
      printf '%s\n' "$diff_out" | sed 's/^/     /'
    fi
  else
    before=""
    [ -f "$dir/go.sum" ] && before="$(cat "$dir/go.mod" "$dir/go.sum")"
    (cd "$dir" && go mod tidy)
    after=""
    [ -f "$dir/go.sum" ] && after="$(cat "$dir/go.mod" "$dir/go.sum")"
    if [ "$before" != "$after" ]; then
      changed=$((changed + 1))
      printf '%s~%s %s\n' "$C_YELLOW" "$C_RESET" "$dir"
    fi
  fi
done

if [ "$MODE" = "check" ]; then
  if [ ${#drifted[@]} -gt 0 ]; then
    printf '\n%s%s gomod%s — %d of %d module(s) are out of sync with their `replace` targets (diffs above).\n' \
      "$C_RED" "$GLYPH_FAIL" "$C_RESET" "${#drifted[@]}" "${#mods[@]}" >&2
    printf '   Fix with:\n\n     bazel run //tools/gomod:tidy\n\n   then commit the go.mod/go.sum changes.\n\n' >&2
    printf '   If this fired on a Dependabot PR, that is the known `replace`-edge blind\n' >&2
    printf '   spot: it bumped a library module and cannot tidy the examples that consume\n' >&2
    printf '   it. Running the command above on the PR branch is the whole fix.\n' >&2
    exit 1
  fi
  printf '%s%s gomod%s — all %d module(s) tidy\n' \
    "$C_GREEN" "$GLYPH_OK" "$C_RESET" "${#mods[@]}"
else
  printf '%s%s gomod%s — tidied %d module(s), %d changed\n' \
    "$C_GREEN" "$GLYPH_OK" "$C_RESET" "${#mods[@]}" "$changed"
fi
