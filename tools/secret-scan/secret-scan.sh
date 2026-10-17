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

# secret-scan.sh — look for secrets with the same gitleaks and the same rules CI uses.
#
# Usage:
#   bazel run //tools/secret-scan                     # the commits on this branch that main does not have
#   bazel run //tools/secret-scan -- --staged         # what `git commit` would record right now
#   bazel run //tools/secret-scan -- --range <a..b>   # the commits in a range, e.g. origin/main..HEAD
#   bazel run //tools/secret-scan -- --unpushed       # the commits no branch on origin has yet
#
# gitleaks is pinned in tools/tools.lock.json (the version CI's
# tools/ci/secret-scan.sh downloads) and the rules are the repo's .gitleaks.toml.
# A finding names the file, the line and the rule. It never prints the secret.
#
# Exit codes: 0 nothing found, 1 something found, 2 the scan could not run.
#
# Environment (tests and callers such as //tools/git):
#   GITLEAKS         path to the gitleaks binary (default: the pinned one in runfiles)
#   GITLEAKS_CONFIG  path to the rules (default: the repo's .gitleaks.toml in runfiles)

set -euo pipefail

usage() {
  sed -n '/^# secret-scan.sh/,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}
cant() { # the scan did not run: never report that as "clean"
  echo "secret-scan: $*" >&2
  echo "secret-scan: nothing was scanned, so this is NOT a clean result." >&2
  exit 2
}

# --- the pinned binary and the rules, found before any cd. ------------------
# --- begin runfiles.bash initialization v3 ---
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null
f=; set -euo pipefail
# --- end runfiles.bash initialization v3 ---
from_runfiles() { declare -F rlocation >/dev/null && rlocation "$1" 2>/dev/null || true; }
GITLEAKS="${GITLEAKS:-$(from_runfiles multitool/tools/gitleaks/gitleaks)}"
GITLEAKS_CONFIG="${GITLEAKS_CONFIG:-$(from_runfiles _main/.gitleaks.toml)}"

mode="branch"
range=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    --staged) mode="staged" ;;
    --unpushed) mode="unpushed" ;;
    --branch) mode="branch" ;;
    --range)
      [ $# -ge 2 ] || { echo "secret-scan: --range needs a range, e.g. --range origin/main..HEAD" >&2; exit 2; }
      mode="range"; range="$2"; shift ;;
    *) echo "secret-scan: unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

[ -n "${GITLEAKS}" ] && [ -x "${GITLEAKS}" ] || cant "cannot find the pinned gitleaks. Run it as: bazel run //tools/secret-scan"
[ -n "${GITLEAKS_CONFIG}" ] && [ -f "${GITLEAKS_CONFIG}" ] || cant "cannot find .gitleaks.toml. Run it as: bazel run //tools/secret-scan"

# The tree to scan: the one `bazel run` was started from. Running at its top
# level also picks up a .gitleaksignore there, as CI does.
HERE="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [ -z "${HERE}" ] || ! git -C "${HERE}" rev-parse --git-dir >/dev/null 2>&1; then
  cant "not inside a git repository"
fi
cd "${HERE}"

log_opts=""
case "${mode}" in
  staged) what="the staged changes" ;;
  range) log_opts="${range}"; what="the commits in ${range}" ;;
  unpushed) log_opts="HEAD --not --remotes=origin"; what="the commits not yet on origin" ;;
  branch)
    base_ref=""
    for r in origin/main main; do
      git rev-parse --verify --quiet "${r}^{commit}" >/dev/null && { base_ref="${r}"; break; }
    done
    [ -n "${base_ref}" ] || cant "there is no origin/main or main to compare with. Name a range instead: bazel run //tools/secret-scan -- --range <a..b>"
    base="$(git merge-base "${base_ref}" HEAD)" || cant "HEAD shares no history with ${base_ref}"
    log_opts="${base}..HEAD"
    what="the commits on this branch that ${base_ref} does not have"
    if [ "$(git rev-parse HEAD)" = "${base}" ]; then
      echo "secret-scan: this branch has no commits of its own yet; nothing to scan."
      exit 0
    fi
    ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
# Only these fields reach the screen. The finding's Secret and Match fields
# hold the secret, so they are never in the template.
printf '%s\n' '{{range .}}{{.File}}:{{.StartLine}}{{"\t"}}{{.RuleID}}{{"\t"}}{{.Commit}}{{"\n"}}{{end}}' >"${tmp}/report.tmpl"

args=(git --no-banner --no-color --redact --log-level error --exit-code 99
  --config "${GITLEAKS_CONFIG}"
  --report-format template --report-template "${tmp}/report.tmpl" --report-path "${tmp}/report.txt")
if [ "${mode}" = "staged" ]; then
  args+=(--pre-commit --staged)
else
  args+=("--log-opts=${log_opts}")
fi

# gitleaks' own output goes to a file, not the screen: even redacted, its log
# line quotes the text around a finding.
set +e
"${GITLEAKS}" "${args[@]}" . >"${tmp}/gitleaks.log" 2>&1
rc=$?
set -e

case "${rc}" in
  0)
    echo "secret-scan: no secrets found in ${what}."
    exit 0
    ;;
  99)
    n="$(grep -c . "${tmp}/report.txt" || true)"
    echo "secret-scan: gitleaks found ${n} possible secret(s) in ${what}:" >&2
    while IFS=$'\t' read -r loc rule commit; do
      [ -n "${loc}" ] || continue
      printf '  %s  (rule: %s)%s\n' "${loc}" "${rule}" "${commit:+  in commit ${commit:0:12}}" >&2
    done <"${tmp}/report.txt"
    cat >&2 <<'MSG'
The secret itself is not printed. What to do:
  * A real secret: take it out of the file. If it was ever pushed, rotate it too.
  * A false positive that is safe by construction: add a scoped allowlist entry
    to .gitleaks.toml that says why, or put a `gitleaks:allow` comment on that line.
  * Already committed on this branch: fix it in a new commit and fold it in with
      bazel run //tools/git:commit -- --fixup <sha> <file>
      bazel run //tools/git:sync -- --autosquash
MSG
    exit 1
    ;;
  *)
    # Not a verdict: say so, and show gitleaks' own words (it failed before
    # scanning, so they hold no finding).
    sed 's/^/  gitleaks: /' "${tmp}/gitleaks.log" | tail -20 >&2
    cant "gitleaks failed to run (exit ${rc})."
    ;;
esac
