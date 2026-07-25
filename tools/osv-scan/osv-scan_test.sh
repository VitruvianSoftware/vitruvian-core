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

# Hermetic self-test for osv-scan.sh — a fake `osv-scanner` on PATH, a scratch
# git repo as ROOT, no network.
#
# It pins the three properties that took several wrong attempts to get right,
# each of which silently produced a FALSE GREEN before it was guarded:
#
#   1. Coverage. osv-scanner emits a `results` entry only for a source WITH
#      findings, so an early guard that counted results passed while the repo
#      was unhealthy and failed the moment it went clean. Worse, scanning from a
#      gitignored directory (a worktree under .claude/) makes osv-scanner walk
#      up to the parent .gitignore, exclude itself, and report nothing at all.
#      The gate must refuse to report green on a scan that covered nothing.
#   2. Read-only. osv-scanner's Go CALL ANALYSIS shells out to the toolchain and
#      rewrites go.work.sum (measured: 7 insertions / 12 deletions). A required
#      gate that mutates the tree breaks tidy-check, which asserts a clean tree.
#   3. Crash != clean. Any exit code that is not 0/1 means the scanner failed;
#      reporting green off a crash is the exact assurance failure this gate is
#      supposed to prevent.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/osv-scan.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find osv-scan.sh" >&2; exit 1; }

PASS=0; FAIL=0
check() {
  if [ "$2" = "0" ]; then printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1))
  else printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); fi
}

# A scratch git repo so the script's ROOT resolution and its tree-mutation
# assertion both have something real to work against.
new_root() {
  r="$(mktemp -d)"
  git -C "${r}" init -q 2>/dev/null
  git -C "${r}" config user.email t@t; git -C "${r}" config user.name t
  echo tracked > "${r}/tracked.txt"
  git -C "${r}" add -A >/dev/null 2>&1; git -C "${r}" commit -qm init >/dev/null 2>&1
  printf '%s' "${r}"
}

# fake_scanner <bin> <sources> <rc> [mutate]
# Emits JSON with <sources> distinct source paths, exits <rc>, and optionally
# rewrites a tracked file to simulate the call-analysis side effect.
#
# It also writes to STDERR, because that is where the real scanner puts its
# human-readable output once --output-file is in play -- which is what makes
# swallowing that stream a diagnosability bug rather than a cosmetic one.
fake_scanner() {
  bin="$1"; n="$2"; rc="$3"; mutate="${4:-}"
  mkdir -p "${bin}"
  cat > "${bin}/osv-scanner" <<EOF
#!/usr/bin/env bash
# The fatal line FIRST, then the ~26-line "unused ignores" roster the real
# scanner appends after it. That ordering is the whole point: a plain
# \`tail\` of this stream shows only the roster, which is how the first cut of
# the crash diagnostic managed to print 20 lines of nothing useful.
echo "SCANNER-STDERR-MARKER: rpc error: code = Unavailable desc = service unavailable" >&2
echo "osv-scanner.toml has unused ignores:" >&2
for i in \$(seq 1 26); do echo " - GO-2026-TRAILING-NOISE-\${i}" >&2; done
out=""
for a in "\$@"; do
  case "\$prev" in --output-file) out="\$a" ;; esac
  prev="\$a"
done
if [ -n "\${out}" ]; then
  {
    printf '{"results":['
    for i in \$(seq 1 ${n}); do
      [ "\$i" -gt 1 ] && printf ','
      printf '{"source":{"path":"/x/go.mod.%s","type":"lockfile"},"packages":[]}' "\$i"
    done
    printf ']}'
  } > "\${out}"
fi
[ -n "${mutate}" ] && echo mutated >> "${mutate}"
exit ${rc}
EOF
  chmod +x "${bin}/osv-scanner"
}

echo "osv-scan_test:"

# --- 1. syntax. --------------------------------------------------------------
bash -n "${UNDER_TEST}" 2>/dev/null; check "script parses" "$?"

# --- 2. healthy scan, no findings -> green. ----------------------------------
root="$(new_root)"; bin="$(mktemp -d)"; fake_scanner "${bin}" 60 0
out="$(cd "${root}" && BUILD_WORKSPACE_DIRECTORY="${root}" PATH="${bin}:${PATH}" bash "${UNDER_TEST}" 2>&1)"; rc=$?
check "clean scan with ample coverage exits 0" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
rm -rf "${root}" "${bin}"

# --- 3. THE false-green case: scan covered (almost) nothing. -----------------
# This is the .gitignore trap. Must NOT report green even though rc=0.
root="$(new_root)"; bin="$(mktemp -d)"; fake_scanner "${bin}" 3 0
out="$(cd "${root}" && BUILD_WORKSPACE_DIRECTORY="${root}" PATH="${bin}:${PATH}" bash "${UNDER_TEST}" 2>&1)"; rc=$?
check "under-covered scan FAILS despite rc=0" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
case "${out}" in *"scanned only"*|*"expected >="*) check "...and says coverage was the reason" 0 ;; *) check "...and says coverage was the reason" 1 ;; esac
rm -rf "${root}" "${bin}"

# --- 4. findings present -> red. ---------------------------------------------
root="$(new_root)"; bin="$(mktemp -d)"; fake_scanner "${bin}" 60 1
out="$(cd "${root}" && BUILD_WORKSPACE_DIRECTORY="${root}" PATH="${bin}:${PATH}" bash "${UNDER_TEST}" 2>&1)"; rc=$?
check "advisories found -> non-zero" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
rm -rf "${root}" "${bin}"

# --- 5. crash is never green. ------------------------------------------------
root="$(new_root)"; bin="$(mktemp -d)"; fake_scanner "${bin}" 60 127
out="$(cd "${root}" && BUILD_WORKSPACE_DIRECTORY="${root}" PATH="${bin}:${PATH}" bash "${UNDER_TEST}" 2>&1)"; rc=$?
check "scanner crash (127) -> non-zero, not green" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
# ...and says WHY. Failing closed is only half the job: this is a REQUIRED
# merge-queue check, so a bare "exit 127" leaves whoever is blocked with nothing
# to act on. The scanner's own words are captured either way -- surfacing them
# costs nothing and is the difference between "re-run and hope" and "deps.dev is
# down". Both observed red on main and on a Dependabot PR, 2026-07-25.
case "${out}" in *SCANNER-STDERR-MARKER*) check "...and quotes the scanner's stderr" 0 ;; *) check "...and quotes the scanner's stderr" 1 ;; esac
rm -rf "${root}" "${bin}"

# --- 6. a scan that mutates the tree must fail. ------------------------------
# Guards the go.work.sum rewrite: a required gate must never edit the checkout.
root="$(new_root)"; bin="$(mktemp -d)"; fake_scanner "${bin}" 60 0 "${root}/tracked.txt"
out="$(cd "${root}" && BUILD_WORKSPACE_DIRECTORY="${root}" PATH="${bin}:${PATH}" bash "${UNDER_TEST}" 2>&1)"; rc=$?
check "scan that MUTATES a tracked file fails" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
case "${out}" in *MUTAT*|*mutat*) check "...and names the mutation" 0 ;; *) check "...and names the mutation" 1 ;; esac
rm -rf "${root}" "${bin}"

# --- 7. the read-only flags are actually passed. -----------------------------
# Call analysis is what rewrites go.work.sum; rust call analysis additionally
# executes build scripts (arbitrary code), so both stay off.
grep -q -- '--no-call-analysis=go' "${UNDER_TEST}"; check "go call analysis disabled" "$?"
grep -q -- '--no-call-analysis=rust' "${UNDER_TEST}"; check "rust call analysis disabled" "$?"
grep -q 'GOWORK=off' "${UNDER_TEST}"; check "GOWORK=off (mutation impossible by mechanism)" "$?"

echo
if [ "${FAIL}" -ne 0 ]; then
  printf '\033[31mFAIL\033[0m — %d passed, %d failed\n' "${PASS}" "${FAIL}"; exit 1
fi
printf '\033[32mPASS\033[0m — %d passed\n' "${PASS}"
