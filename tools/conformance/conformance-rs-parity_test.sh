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
# Byte-for-byte parity test: runs both check.sh and check_rs against identical
# throwaway roots and asserts stdout and exit code are identical.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK_SH="$HERE/check.sh"
CHECK_RS="${1:?usage: $0 <path-to-check_rs-binary>}"

[ -f "$CHECK_SH" ] || { echo "FATAL: check.sh not found next to $0" >&2; exit 1; }
[ -x "$CHECK_RS" ] || { echo "FATAL: check_rs binary not executable at $CHECK_RS" >&2; exit 1; }

FAILURES=0
CASES=0

compare() {
  desc="$1"; root="$2"
  CASES=$((CASES + 1))

  sh_out="$(mktemp)"; rs_out="$(mktemp)"

  BUILD_WORKSPACE_DIRECTORY="$root" bash "$CHECK_SH" >"$sh_out" 2>/dev/null; sh_rc=$?
  BUILD_WORKSPACE_DIRECTORY="$root" "$CHECK_RS" >"$rs_out" 2>/dev/null; rs_rc=$?

  ok=1
  if [ "$sh_rc" != "$rs_rc" ]; then
    printf 'FAIL  %s — exit code: sh=%d rs=%d\n' "$desc" "$sh_rc" "$rs_rc"
    ok=0
  fi
  if ! diff -q "$sh_out" "$rs_out" >/dev/null 2>&1; then
    printf 'FAIL  %s — stdout differs:\n' "$desc"
    diff -u "$sh_out" "$rs_out" | head -40
    ok=0
  fi
  if [ "$ok" = 1 ]; then
    printf 'PASS  %s\n' "$desc"
  else
    FAILURES=$((FAILURES + 1))
  fi

  rm -f "$sh_out" "$rs_out"
}

new_root() {
  root="$(mktemp -d)"
  mkdir -p "$root/.github/workflows" \
           "$root/infrastructure/pulumi/platform/repo-config" \
           "$root/tools/conformance"
  printf 'go 1.26.2\n' > "$root/go.work"
  printf '22\n' > "$root/.nvmrc"
  printf '{\n  "packageManager": "pnpm@10.20.0"\n}\n' > "$root/package.json"
  printf '# file\ttool\tpinned_value\treview_by\treason\n' > "$root/tools/conformance/version-pins.tsv"
  printf '{\n  enabledManagers: ["argocd"],\n}\n' > "$root/renovate.json5"
  printf '%s' "$root"
}

# --- case: minimal passing root ------------------------------------------------
case_minimal() {
  root="$(new_root)"
  compare "minimal throwaway root" "$root"
  rm -rf "$root"
}

# --- case: with a go.mod mismatch ----------------------------------------------
case_go_mismatch() {
  root="$(new_root)"
  mkdir -p "$root/apps/foo"
  printf 'module example.com/foo\n\ngo 1.25.0\n' > "$root/apps/foo/go.mod"
  compare "go.mod version mismatch triggers fail" "$root"
  rm -rf "$root"
}

# --- case: with version pins ---------------------------------------------------
case_version_pin() {
  root="$(new_root)"
  mkdir -p "$root/apps/bar"
  printf 'module example.com/bar\n\ngo 1.25.0\n' > "$root/apps/bar/go.mod"
  printf 'apps/bar/go.mod\tgo\t1.25.0\t2099-12-31\t@test\ttest pin\n' > "$root/tools/conformance/version-pins.tsv"
  compare "version pin exempts a go.mod" "$root"
  rm -rf "$root"
}

# --- case: registry parse error ------------------------------------------------
case_bad_registry() {
  root="$(new_root)"
  printf 'bad line\n' > "$root/tools/conformance/version-pins.tsv"
  compare "malformed registry causes die()" "$root"
  rm -rf "$root"
}

case_minimal
case_go_mismatch
case_version_pin
case_bad_registry

printf '\n%d/%d parity cases passed\n' "$((CASES - FAILURES))" "$CASES"
[ "$FAILURES" -eq 0 ] || exit 1
