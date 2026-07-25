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
# osv-scan.sh — scan this repo's dependencies for known advisories (OSV database).
#
#   bazel run //tools/osv-scan
#
# WHY OSV-SCANNER, NOT GitHub's dependency-review:
#   dependency-review reads GitHub's DEPENDENCY GRAPH, a GitHub Advanced
#   Security feature -- free on public repositories, BILLED PER ACTIVE COMMITTER
#   on private ones. Verified against the API: the code security configuration
#   that enables the graph cannot omit advanced_security (accepted values are
#   only enabled|disabled|code_security|secret_protection), so as a REQUIRED
#   check it could not survive this repo turning private without either an
#   invoice or a wedged merge queue. osv-scanner reads the LOCKFILES directly:
#   free at any visibility, runnable locally (which dependency-review never can
#   be, being a GitHub-API-only action), and it covers Cargo and PyPI too.
#
# SCOPE — `--recursive` from the repo root, deliberately:
#   osv-scanner honours .gitignore, so bazel-* symlink farms and node_modules
#   are excluded for free, while package-lock.json files that a hand-written
#   glob would miss ARE picked up. An earlier draft passed an explicit
#   --lockfile list built from globs; it missed three package-lock.json files.
#
# NO CALL ANALYSIS — not a performance tweak, a correctness one:
#   osv-scanner's Go call-graph analysis is ON BY DEFAULT and runs golang.org/x/
#   tools/go/packages, which shells out to the Go toolchain (`go env`, `go list`)
#   inside the module being analysed. In a `go work` workspace the toolchain
#   normalises go.work.sum as a side effect: measured here as exactly
#   7 insertions / 12 deletions, reproduced on demand by dropping the flag. A
#   required CI gate that mutates the working tree fails tidy-check (which
#   asserts a clean tree) and corrupts the very checkout it is inspecting.
#
#   Note the trigger, because it makes the bug intermittent and therefore easy
#   to misattribute: call analysis only runs for a module that ALREADY has a Go
#   finding, so a scan whose Go findings are all suppressed can look read-only
#   and the same scan a week later will not be.
#
#   RULED OUT — transitive dependency RESOLUTION (`--no-resolve`). The obvious
#   suspect, and wrong: resolution is served from deps.dev over the network and
#   invokes the Go toolchain zero times (verified by putting a logging shim
#   ahead of `go` on PATH for a full recursive scan). Passing --no-resolve would
#   not have fixed the mutation and WOULD have cost coverage -- it drops the 8
#   PyPI advisories that only surface once requirements.txt is resolved, in
#   exchange for 2 advisories against the unresolved pins. So resolution stays
#   ON, and the baseline is the resolved finding set.
#
#   THREE LAYERS, because one flag is a single point of failure:
#     1. --no-call-analysis for BOTH go and rust (rust call analysis executes
#        build scripts -- arbitrary code -- so it is disabled on principle, not
#        just for tree cleanliness).
#     2. GOWORK=off in the environment. go.work.sum can only be written in
#        workspace mode, so this makes the mutation impossible at the mechanism
#        level rather than trusting a flag name to survive an osv-scanner
#        upgrade. Verified: with call analysis deliberately re-enabled and the
#        Go toolchain invoked 6 times, go.work.sum is byte-identical.
#     3. And it is still ASSERTED after the fact (see the tree-cleanliness check
#        below), so a future regression fails this gate loudly instead of
#        silently reddening tidy-check two jobs later.
#
#   The cost of no call analysis is that findings are not filtered by
#   reachability, which is why the baseline has to carry unreachable advisories
#   explicitly rather than having them filtered out for free.
#
# COVERAGE ASSERTION — why this is a script and not a bare CI step:
#   A scanner that silently covers nothing reports success. That is the exact
#   false-assurance failure this gate exists to prevent, so a green result is
#   not trusted until the scan proves it parsed the sources we know are there.
#   Concretely: run from a gitignored directory (a worktree under .claude/) and
#   osv-scanner walks up to the parent .gitignore, finds itself excluded, and
#   reports "No package sources found" -- a green-looking nothing. MIN_SOURCES
#   turns that into a loud failure.
#
#   WHY --all-packages: by default the JSON `results` array holds only sources
#   that HAVE findings, which is the exact inverse of a coverage signal -- it
#   SHRINKS as the baseline suppresses findings and reaches zero precisely when
#   the repo is clean. Measured on this repo: 106 sources scanned, 103 of them
#   with findings, and 0 once osv-scanner.toml is applied. So the guard passed
#   only while the repo was unhealthy and failed the moment it was green, which
#   is backwards for something whose whole job is to detect a scan that covered
#   nothing. --all-packages makes `results` carry every source that yielded at
#   least one package, finding or not, so the count measures what was SCANNED.
#   It is also a structured field rather than a scraped log line: the
#   alternative, counting "Scanned <path> file and found N packages", depends on
#   --verbosity staying at info and on human-readable prose that carries no
#   compatibility promise -- and osv-scanner emits that prose on stdout in table
#   mode but stderr with --output-file, which is exactly the kind of detail a
#   coverage assertion should not be resting on.

set -euo pipefail

ROOT="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${ROOT}"

# Floor for "the scan actually ran". 106 sources are scanned here today; if
# fewer than this are reported, something silently excluded the tree and the
# result is meaningless. Set well below the real count so ordinary churn never
# trips it.
MIN_SOURCES=50

info() { printf '\033[36m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

command -v osv-scanner >/dev/null 2>&1 ||
  die "osv-scanner not on PATH.
   CI installs it pinned + checksum-verified (see .github/workflows/supply-chain.yaml).
   Locally: go install github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.4.0"

# See "NO CALL ANALYSIS" above. GOWORK=off is the mechanism-level guarantee that
# nothing this gate spawns can rewrite go.work.sum; -mod=readonly extends the
# same promise to go.mod/go.sum. Exported, so BOTH osv-scanner invocations below
# inherit it.
export GOWORK=off
export GOFLAGS="${GOFLAGS:+${GOFLAGS} }-mod=readonly"

SCAN_ARGS=(
  scan source
  --recursive
  --no-call-analysis=go
  --no-call-analysis=rust
)
[ -f "osv-scanner.toml" ] && SCAN_ARGS+=(--config=osv-scanner.toml)

json="$(mktemp)"
scan_err="$(mktemp)"
trap 'rm -f "${json}" "${scan_err}"' EXIT

info "scanning ${ROOT} (recursive; .gitignore excludes bazel-*/node_modules)"

# Snapshot the tree so the "this gate must not mutate the checkout" promise is
# asserted rather than assumed. Compared by PATH SET, not by emptiness: a dev's
# pre-existing local edits are fine, a file the SCAN touched is not.
dirty_snapshot() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git status --porcelain 2>/dev/null | cut -c4- | sort
}
tree_before="$(dirty_snapshot)"

assert_tree_unchanged() {
  local touched
  touched="$(comm -13 <(printf '%s\n' "${tree_before}") <(printf '%s\n' "$(dirty_snapshot)"))"
  [ -z "${touched}" ] ||
    die "the scan MUTATED the working tree -- refusing to report a verdict:
$(printf '%s\n' "${touched}" | sed 's/^/     /')
   This gate is required and must be read-only; a scan that rewrites the
   checkout breaks tidy-check downstream and corrupts what it is inspecting.
   Historically this was osv-scanner's Go call analysis normalising go.work.sum.
   Restore with \`git checkout -- <file>\`, then find which osv-scanner stage
   ran the toolchain (put a logging shim ahead of \`go\` on PATH and re-run)."
}

# Capture the exit code rather than letting `set -e` abort, so the coverage
# assertion below runs on BOTH outcomes -- a crash must never be mistaken for
# "clean". Human-readable output goes to the console; JSON drives the assertion.
set +e
osv-scanner "${SCAN_ARGS[@]}" --all-packages \
  --format json --output-file "${json}" . >/dev/null 2>"${scan_err}"
rc=$?
set -e

assert_tree_unchanged

# Coverage = sources ACTUALLY SCANNED, which --all-packages puts in `results`
# whether or not they had findings. Counting distinct paths, because a source
# can legitimately appear more than once.
sources="$(python3 -c "
import json
try:
    results = json.load(open('${json}')).get('results', [])
    print(len({r.get('source', {}).get('path') for r in results}))
except Exception:
    print(-1)
" 2>/dev/null || echo -1)"

# No parseable JSON is itself a coverage failure, and the commonest cause is the
# same one MIN_SOURCES exists for: with nothing to scan, osv-scanner exits 128
# and never writes an output file at all. Quote the scanner so the reader does
# not have to guess which of the two it was.
[ "${sources}" -ge 0 ] 2>/dev/null ||
  die "osv-scanner exited ${rc} without parseable JSON output, so there is no
   evidence it covered anything -- refusing to report a verdict. Its last words:
$(tail -n 5 "${scan_err}" | sed 's/^/     /')
   \"No package sources found\" here means the scan was run from a gitignored
   directory (a worktree under .claude/ walks up to the parent .gitignore and
   excludes itself). Run from the primary checkout."

if [ "${sources}" -lt "${MIN_SOURCES}" ]; then
  die "osv-scanner scanned only ${sources} source(s), expected >= ${MIN_SOURCES}.
   The scan did not cover this repo, so its result is meaningless -- refusing to
   report green. Most likely cause: running from a gitignored directory (a
   worktree under .claude/ walks up to the parent .gitignore and excludes
   itself). Run from the primary checkout."
fi

case "${rc}" in
  0) ok "no unaccepted advisories across ${sources} scanned sources" ;;
  1) # Re-run without --format so the findings are visible in the log. Same args,
     # same GOWORK=off, and re-asserted -- the failure path must leave the tree
     # as clean as the success path does.
     osv-scanner "${SCAN_ARGS[@]}" . 2>/dev/null || true
     assert_tree_unchanged
     die "osv-scanner found advisories not covered by osv-scanner.toml (above).
   Fix by upgrading the dependency, or -- if it is genuinely not exploitable
   here -- add an ignoredVulns entry to osv-scanner.toml with a reason, and an
   expiry unless the advisory has no fix at all." ;;
  *) # Every other exit code is a scanner FAILURE, and this gate is required, so
     # it fails closed. Quote the scanner rather than just its exit code: with
     # --output-file, osv-scanner's human-readable output goes to STDERR, so the
     # whole reason lives in ${scan_err} and was otherwise discarded on this path
     # -- leaving a red required check whose entire log was "exit 127". Observed
     # three times on 2026-07-25 (main, and two PRs), each recoverable by nothing
     # but a re-run.
     #
     # GREP, NOT `tail`. The first cut of this used tail -n 20 and printed the
     # wrong 20 lines: osv-scanner appends an "osv-scanner.toml has unused
     # ignores:" roster of ~26 advisory IDs AFTER everything else, so a plain
     # tail is pure noise and buries the one line that matters. Measured on a
     # real failure -- the fatal cause was above the cut. Falls back to the tail
     # when nothing matches, so an unanticipated failure still says something.
     excerpt="$(grep -inE 'error|fail|unavailable|unreachable|panic|fatal|timeout|refused' "${scan_err}" | tail -n 12)"
     [ -n "${excerpt}" ] || excerpt="$(tail -n 12 "${scan_err}")"
     die "osv-scanner failed to run (exit ${rc}); refusing to report green.
   Matching lines from its output (stderr is where --output-file sends it):
$(printf '%s\n' "${excerpt}" | sed 's/^/     /')
   Nothing here naming a lockfile or advisory usually means the network: the
   transitive resolution this scan keeps ON is served from deps.dev, so its
   outage surfaces as \"rpc error: code = Unavailable\" and a re-run clears it."
     ;;
esac
