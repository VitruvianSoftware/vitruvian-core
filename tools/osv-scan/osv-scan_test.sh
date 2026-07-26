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

# fake_scanner_seq <bin> <state> <spec>...
# A fake whose behaviour VARIES per invocation, which is what the retry tests
# need. Each <spec> is "<sources>|<rc>|<stderr>"; invocation N uses spec N and
# the last spec repeats thereafter. <sources>=0 writes no output file at all,
# reproducing the real transient failure (osv-scanner aborts before writing
# JSON). Invocations are counted in <state>/calls so a test can assert HOW MANY
# attempts happened, not merely the final exit code.
fake_scanner_seq() {
  bin="$1"; state="$2"; shift 2
  mkdir -p "${bin}" "${state}"
  : > "${state}/calls"
  i=1
  for spec in "$@"; do printf '%s\n' "${spec}" > "${state}/spec.${i}"; i=$((i+1)); done
  printf '%s' "$((i - 1))" > "${state}/nspecs"
  cat > "${bin}/osv-scanner" <<'FAKE'
#!/usr/bin/env bash
state="__STATE__"
echo call >> "${state}/calls"
printf '%s\n' "$*" >> "${state}/args"
n="$(wc -l < "${state}/calls" | tr -d ' ')"
nspecs="$(cat "${state}/nspecs")"
idx="${n}"; [ "${idx}" -gt "${nspecs}" ] && idx="${nspecs}"
IFS='|' read -r sources rc errtext < "${state}/spec.${idx}"
out=""; prev=""
for a in "$@"; do
  case "${prev}" in --output-file) out="${a}" ;; esac
  prev="${a}"
done
[ -n "${errtext}" ] && echo "${errtext}" >&2
if [ -n "${out}" ] && [ "${sources}" -gt 0 ]; then
  {
    printf '{"results":['
    for i in $(seq 1 "${sources}"); do
      [ "${i}" -gt 1 ] && printf ','
      printf '{"source":{"path":"/x/go.mod.%s","type":"lockfile"},"packages":[]}' "${i}"
    done
    printf ']}'
  } > "${out}"
fi
exit "${rc}"
FAKE
  sed "s|__STATE__|${state}|" "${bin}/osv-scanner" > "${bin}/osv-scanner.t" \
    && mv "${bin}/osv-scanner.t" "${bin}/osv-scanner"
  chmod +x "${bin}/osv-scanner"
}

run_under_test() { # <root> <bin> -> sets `out` and `rc`
  out="$(cd "$1" && BUILD_WORKSPACE_DIRECTORY="$1" OSV_RETRY_DELAY=0 \
        PATH="$2:${PATH}" bash "${UNDER_TEST}" 2>&1)"; rc=$?
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
# OSV_RETRY_DELAY=0 because this fake's stderr carries the transient marker, so
# the scan legitimately exhausts the retry budget here -- without it the test
# would sit through the real backoff.
root="$(new_root)"; bin="$(mktemp -d)"; fake_scanner "${bin}" 60 127
out="$(cd "${root}" && BUILD_WORKSPACE_DIRECTORY="${root}" OSV_RETRY_DELAY=0 PATH="${bin}:${PATH}" bash "${UNDER_TEST}" 2>&1)"; rc=$?
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

# --- 8. a TRANSIENT resolver failure is retried, and a later attempt wins. ----
# The flake this exists for: osv-scanner's transitive resolution is served from
# deps.dev over gRPC, and on 2026-07-25 that returned "Unavailable" for ~13% of
# requests -- 13 red required checks in the gate's first 16 hours. It is not an
# outage you wait out: successes and failures interleaved TWO SECONDS apart
# (09:19:48 fail / 09:19:50 pass), so the per-request failures are independent
# and a second attempt is overwhelmingly likely to land.
root="$(new_root)"; bin="$(mktemp -d)"; st="$(mktemp -d)"
fake_scanner_seq "${bin}" "${st}" \
  "0|127|failed resolution for x/requirements.txt: rpc error: code = Unavailable desc = service unavailable" \
  "60|0|"
run_under_test "${root}" "${bin}"
check "transient resolver failure is retried, then passes" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
calls="$(wc -l < "${st}/calls" | tr -d ' ')"
check "...having actually invoked the scanner twice" "$([ "${calls}" = "2" ] && echo 0 || echo 1)"
rm -rf "${root}" "${bin}" "${st}"

# --- 9. a resolver failure that even --no-resolve cannot survive fails closed. -
# Retry must not become fail-open. When the fallback ALSO fails, the network is
# no longer a sufficient explanation and the gate stays red -- here the fallback
# writes no JSON either, so there is no coverage evidence and no verdict.
# Six invocations: five of the retry budget, then the resolution-free fallback.
root="$(new_root)"; bin="$(mktemp -d)"; st="$(mktemp -d)"
fake_scanner_seq "${bin}" "${st}" \
  "0|127|failed resolution: rpc error: code = Unavailable desc = service unavailable"
run_under_test "${root}" "${bin}"
check "resolver failure surviving the fallback still FAILS (never green)" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
calls="$(wc -l < "${st}/calls" | tr -d ' ')"
check "...after the 5-attempt budget plus one --no-resolve fallback" "$([ "${calls}" = "6" ] && echo 0 || echo 1)"
rm -rf "${root}" "${bin}" "${st}"

# --- 10. a real FINDING is never retried away. -------------------------------
# The failure mode that would make this whole change a security regression:
# rc=1 is a verdict, not a transport error. Retrying it would let a later
# attempt's exit code paper over an advisory the first attempt genuinely found.
root="$(new_root)"; bin="$(mktemp -d)"; st="$(mktemp -d)"
fake_scanner_seq "${bin}" "${st}" "60|1|" "60|0|"
run_under_test "${root}" "${bin}"
check "advisories are NOT retried away" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
case "${out}" in *etrying*) check "...and the retry loop never fired" 1 ;; *) check "...and the retry loop never fired" 0 ;; esac
rm -rf "${root}" "${bin}" "${st}"

# --- 11. a non-transient crash is not retried either. ------------------------
# Retry is scoped to the network signature; a bad flag or a broken binary is
# deterministic, so burning the budget on it just slows the red result down.
root="$(new_root)"; bin="$(mktemp -d)"; st="$(mktemp -d)"
fake_scanner_seq "${bin}" "${st}" "0|127|Error: unknown flag: --nope"
run_under_test "${root}" "${bin}"
check "a non-network crash fails without retrying" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
calls="$(wc -l < "${st}/calls" | tr -d ' ')"
check "...in exactly one attempt" "$([ "${calls}" = "1" ] && echo 0 || echo 1)"
rm -rf "${root}" "${bin}" "${st}"

# --- 12. deps.dev down -> resolution-free fallback, GREEN but annotated. -----
# The property the whole fallback exists for. A required merge-blocking check
# must not take a third-party service's availability as an input: when deps.dev
# sheds load, every open dependency PR reddens on the single unpinned
# requirements.txt none of them touch (#1226). After the retry budget the scan
# is retried WITHOUT resolution; if that is clean the gate goes green, but the
# reduced PyPI coverage is stated rather than passed off as an unqualified pass.
root="$(new_root)"; bin="$(mktemp -d)"; st="$(mktemp -d)"
fake_scanner_seq "${bin}" "${st}" \
  "0|127|failed resolution for x/requirements.txt: rpc error: code = Unavailable desc = service unavailable" \
  "0|127|failed resolution for x/requirements.txt: rpc error: code = Unavailable desc = service unavailable" \
  "0|127|failed resolution for x/requirements.txt: rpc error: code = Unavailable desc = service unavailable" \
  "0|127|failed resolution for x/requirements.txt: rpc error: code = Unavailable desc = service unavailable" \
  "0|127|failed resolution for x/requirements.txt: rpc error: code = Unavailable desc = service unavailable" \
  "60|0|"
run_under_test "${root}" "${bin}"
check "deps.dev outage degrades to a resolution-free scan and passes" "$([ "${rc}" = "0" ] && echo 0 || echo 1)"
grep -q -- '--no-resolve' "${st}/args"; check "...the fallback actually passed --no-resolve" "$?"
case "${out}" in *UNAVAILABLE*) check "...and the degraded coverage is stated, not silent" 0 ;; *) check "...and the degraded coverage is stated, not silent" 1 ;; esac
head -5 "${st}/args" | grep -q -- '--no-resolve' && check "...and resolution stayed ON for the primary attempts" 1 || check "...and resolution stayed ON for the primary attempts" 0
rm -rf "${root}" "${bin}" "${st}"

# --- 13. the fallback still fails closed on a real advisory. -----------------
# The regression that would make the fallback a security hole: degrading to
# --no-resolve must lose COVERAGE, never the VERDICT. An advisory the
# resolution-free scan can still see has to block the merge exactly as before.
root="$(new_root)"; bin="$(mktemp -d)"; st="$(mktemp -d)"
fake_scanner_seq "${bin}" "${st}" \
  "0|127|failed resolution: rpc error: code = Unavailable desc = service unavailable" \
  "0|127|failed resolution: rpc error: code = Unavailable desc = service unavailable" \
  "0|127|failed resolution: rpc error: code = Unavailable desc = service unavailable" \
  "0|127|failed resolution: rpc error: code = Unavailable desc = service unavailable" \
  "0|127|failed resolution: rpc error: code = Unavailable desc = service unavailable" \
  "60|1|"
run_under_test "${root}" "${bin}"
check "an advisory found by the fallback still FAILS the gate" "$([ "${rc}" != "0" ] && echo 0 || echo 1)"
rm -rf "${root}" "${bin}" "${st}"

echo
if [ "${FAIL}" -ne 0 ]; then
  printf '\033[31mFAIL\033[0m — %d passed, %d failed\n' "${PASS}" "${FAIL}"; exit 1
fi
printf '\033[32mPASS\033[0m — %d passed\n' "${PASS}"
