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
# secret-scan_test.sh — self-test for tools/ci/secret-scan.sh.
#
# Every property here is about the same thing: this gate must never state a
# verdict it did not earn. It is quoted as evidence — "secret-scan: no secrets
# found" gets pasted into review threads — so the expensive failures are not
# crashes but confident wrong sentences:
#
#   * an exec failure rendered as "gitleaks found a candidate secret" (the run
#     that scanned nothing, reported as a leak), and
#   * a clean result produced by some other gitleaks than the pinned one (the
#     run under different rules, reported as this gate's).
#
# Both read as authoritative and neither shows up as an error. The three
# non-zero exits are therefore asserted on their MESSAGE, not just their code —
# an rc alone cannot distinguish them, which is the original defect.
#
# gitleaks itself is stubbed. This test pins secret-scan.sh's decision logic,
# not gitleaks' detection: a real binary would make the suite depend on the
# network, the platform, and a scanner whose rules move independently of us.
#
# Run: bash tools/ci/secret-scan_test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNDER_TEST="${SCRIPT_DIR}/secret-scan.sh"
[ -f "${UNDER_TEST}" ] || { echo "FATAL: ${UNDER_TEST} not found" >&2; exit 1; }

# Read the pin out of the script rather than duplicating it: a literal here
# would keep passing after a version bump while asserting the old pin.
PINNED="$(sed -n 's/^GITLEAKS_VERSION="\([^"]*\)".*/\1/p' "${UNDER_TEST}" | head -1)"
[ -n "${PINNED}" ] || { echo "FATAL: could not read GITLEAKS_VERSION from ${UNDER_TEST}" >&2; exit 1; }
echo "secret-scan_test: pinned gitleaks version from the script = ${PINNED}"
echo

PASS=0
FAIL=0

# A throwaway git repo, because secret-scan.sh resolves ROOT via
# `git rev-parse --show-toplevel` and cd's there.
new_repo() {
  repo="$(mktemp -d)"
  git -C "${repo}" init -q
  git -C "${repo}" config user.email t@example.com
  git -C "${repo}" config user.name t
  git -C "${repo}" config commit.gpgsign false
  : > "${repo}/.gitleaks.toml"
  echo hello > "${repo}/file.txt"
  git -C "${repo}" add -A
  git -C "${repo}" commit -qm base
  printf '%s' "${repo}"
}

# A gitleaks stub: reports $2 for `version`, exits $3 for any scan subcommand.
# Version and scan behaviour are independent on purpose — the version gate must
# be reachable without a scan, and the exec-failure cases must be reachable with
# a version that satisfies the gate.
stub_gitleaks() {
  dir="$1"; version="$2"; scan_rc="$3"
  mkdir -p "${dir}"
  cat > "${dir}/gitleaks" <<STUB
#!/usr/bin/env bash
if [ "\${1:-}" = "version" ]; then printf '%s\n' "${version}"; exit 0; fi
exit ${scan_rc}
STUB
  chmod +x "${dir}/gitleaks"
}

# run_case <name> <stub-version> <stub-scan-rc> <expected-rc> <expected substring>
run_case() {
  name="$1"; version="$2"; scan_rc="$3"; want_rc="$4"; want_msg="$5"
  repo="$(new_repo)"
  bindir="$(mktemp -d)"
  stub_gitleaks "${bindir}" "${version}" "${scan_rc}"
  cp "${UNDER_TEST}" "${repo}/secret-scan.sh"

  out="$(cd "${repo}" && PATH="${bindir}:${PATH}" USE_SYSTEM_GITLEAKS=1 \
        BASE_REV="" BASE_REF="" bash ./secret-scan.sh 2>&1)"
  rc=$?

  ok=1
  [ "${rc}" = "${want_rc}" ] || ok=0
  case "${out}" in *"${want_msg}"*) : ;; *) ok=0 ;; esac

  if [ "${ok}" = 1 ]; then
    printf 'PASS  %s\n' "${name}"
    PASS=$((PASS + 1))
  else
    printf 'FAIL  %s\n      want rc=%s and substring: %s\n      got  rc=%s\n%s\n' \
      "${name}" "${want_rc}" "${want_msg}" "${rc}" "$(printf '%s\n' "${out}" | sed 's/^/        /')"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "${repo}" "${bindir}"
}

# --- the exec-failure split: rc alone cannot tell these apart -----------------
# 126/127 are the shell's "found but not executable" / "not found". They arrive
# on exactly the path a Mac developer takes by default (the pinned tarball is
# linux_x64), and before this split they printed the leak message verbatim.
run_case "exec failure 126 reports 'did not run', not a finding" \
  "${PINNED}" 126 126 "gitleaks did not run"
run_case "exec failure 127 reports 'did not run', not a finding" \
  "${PINNED}" 127 127 "gitleaks did not run"

# The instrument check: if the leak message never appeared, the two cases above
# would pass for the wrong reason. A real finding must still say "found".
run_case "a real finding is still reported as a finding" \
  "${PINNED}" 1 1 "found a candidate secret"

# --- the version gate ---------------------------------------------------------
# The escape hatch skips both the pin and the checksum. A scan by another
# gitleaks is not the scan CI runs, and must not be able to print this gate's
# clean verdict.
run_case "a system gitleaks off the pin is refused" \
  "8.29.0" 0 1 "not the pinned v${PINNED}"
run_case "the refusal names the version it actually found" \
  "8.29.0" 0 1 "'8.29.0'"

# The gate must not be so eager it blocks the supported path.
run_case "a system gitleaks ON the pin is accepted and scans" \
  "${PINNED}" 0 0 "no secrets found"

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ] || exit 1
