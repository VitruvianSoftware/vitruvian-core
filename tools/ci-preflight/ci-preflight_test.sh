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

# Hermetic self-test for ci-preflight.sh: a fake `gh` on PATH, a synthetic
# .github tree, no network and no credentials. The behaviour that matters most
# is the one that is easiest to get wrong -- an UNKNOWN must never be scored as
# either satisfied or missing, because a preflight that reports green when it
# could not look is worse than no preflight.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ci-preflight.sh"
[ -f "${UNDER_TEST}" ] || { echo "cannot find ci-preflight.sh" >&2; exit 1; }

PASS=0; FAIL=0
check() { # check <name> <condition-result>
  if [ "$2" = "0" ]; then printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1))
  else printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); fi
}

# make_repo <dir> — a synthetic .github tree:
#   pr.yaml   triggers on pull_request, reads PR_SECRET     (Dependabot-relevant)
#   push.yaml triggers on push only,    reads PUSH_SECRET   (not relevant)
make_repo() {
  d="$1"
  mkdir -p "${d}/.github/workflows"
  cat > "${d}/.github/workflows/pr.yaml" <<'EOF'
name: PR
on:
  pull_request:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - env:
          TOKEN: ${{ secrets.PR_SECRET }}
          GATE: ${{ vars.PR_VAR }}
        run: echo hi
EOF
  cat > "${d}/.github/workflows/push.yaml" <<'EOF'
name: Push
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - env:
          TOKEN: ${{ secrets.PUSH_SECRET }}
        run: echo hi
EOF
}

# make_fake_gh <bin> <dependabot-secret-names> [repo-secret-names]
make_fake_gh() {
  bin="$1"; dep="$2"; reposec="${3-PR_SECRET PUSH_SECRET}"
  mkdir -p "${bin}"
  cat > "${bin}/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"auth status"*)              exit 0 ;;
  *"repo view"*)                echo "acme/widget"; exit 0 ;;
  *"dependabot/secrets"*)       for n in ${dep}; do echo "\$n"; done; exit 0 ;;
  *"actions/secrets"*)          for n in ${reposec}; do echo "\$n"; done; exit 0 ;;
  *"actions/variables"*)        echo "PR_VAR"; exit 0 ;;
  *"environments"*)             exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "${bin}/gh"
}

run() { # run <repo-dir> <bin-dir> [args...]
  ( cd "$1" && PATH="$2:${PATH}" BUILD_WORKSPACE_DIRECTORY="$1" \
      bash "${UNDER_TEST}" "${@:3}" 2>&1 )
}

echo "ci-preflight_test:"

# --- 1. syntax. --------------------------------------------------------------
bash -n "${UNDER_TEST}" 2>/dev/null
check "ci-preflight.sh parses" "$?"

# --- 2. the required set is DERIVED from the workflows. ----------------------
tmp="$(mktemp -d)"; make_repo "${tmp}"
out="$(run "${tmp}" "${tmp}/nope" --list)"
grep -q "PR_SECRET" <<<"${out}" && grep -q "PUSH_SECRET" <<<"${out}" && grep -q "PR_VAR" <<<"${out}"
check "--list derives secrets and vars from the workflows" "$?"

# Only the PR-triggered one belongs in the Dependabot section.
dep_section="$(sed -n '/read by PR-triggered/,$p' <<<"${out}")"
grep -q "PR_SECRET" <<<"${dep_section}" && ! grep -q "PUSH_SECRET" <<<"${dep_section}"
check "only PR-triggered secrets are Dependabot-relevant" "$?"

# --- 3. THE #1164 CHECK: PR-triggered secret absent from the Dependabot store. -
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_repo "${tmp}"; make_fake_gh "${bin}" ""   # dependabot store empty
out="$(run "${tmp}" "${bin}")"
grep -q "empty on Dependabot PRs" <<<"${out}"
check "flags a PR-triggered secret missing from the Dependabot store" "$?"

grep -q "gh secret set" <<<"${out}"
check "names the remediation" "$?"

# --- 3b. PR detection must not depend on awk. --------------------------------
# Regression pin. The first version scraped the `on:` block with awk using an
# ERE interval (`[[:space:]]{2}`). That works under gawk and current mawk and
# matches NOTHING under an awk without interval support -- so every workflow read
# as not-PR-triggered and the tool reported no Dependabot gaps at all. Passed on
# a dev box, failed in the RBE container, and the failure mode was a false
# ALL-CLEAR from a checker. A hostile `awk` proves the dependency is gone.
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_repo "${tmp}"; make_fake_gh "${bin}" ""
cat > "${bin}/awk" <<'EOF'
#!/usr/bin/env bash
echo "awk must not be used for trigger detection" >&2
exit 127
EOF
chmod +x "${bin}/awk"
out="$(run "${tmp}" "${bin}")"
grep -q "empty on Dependabot PRs" <<<"${out}"
check "PR detection works with a hostile awk on PATH" "$?"

# --- 3c. flow-style triggers. ------------------------------------------------
tmp="$(mktemp -d)"; bin="${tmp}/bin"
mkdir -p "${tmp}/.github/workflows"
cat > "${tmp}/.github/workflows/flow.yaml" <<'EOF'
name: Flow
on: [pull_request, push]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - env:
          T: ${{ secrets.PR_SECRET }}
        run: echo hi
EOF
make_fake_gh "${bin}" "" "PR_SECRET"
out="$(run "${tmp}" "${bin}")"
grep -q "empty on Dependabot PRs" <<<"${out}"
check "flow-style 'on: [pull_request, …]' is detected" "$?"

# --- 3d. a nested pull_request is NOT a trigger. -----------------------------
# Guards the decision to pin the key to the top-level `on:` mapping: a
# `pull_request` appearing deeper in the file must not be read as a trigger, or
# every push-only workflow gets a spurious Dependabot finding.
tmp="$(mktemp -d)"; bin="${tmp}/bin"
mkdir -p "${tmp}/.github/workflows"
cat > "${tmp}/.github/workflows/nested.yaml" <<'EOF'
name: Nested
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    if: github.event.pull_request.number
    steps:
      - env:
          T: ${{ secrets.PUSH_SECRET }}
        run: echo pull_request
EOF
make_fake_gh "${bin}" "" "PUSH_SECRET"
out="$(run "${tmp}" "${bin}")"
! grep -q "empty on Dependabot PRs" <<<"${out}"
check "a nested pull_request reference is not a trigger" "$?"

# --- 3e. indentation width is not a trigger signal. --------------------------
# The companion to 3d, and the regression that matters more: 3d proves we do not
# over-match, this proves we do not UNDER-match. A four-space `on:` block is the
# house style in four of this repo's workflows, and a matcher pinned to two
# spaces read every one of them as not-PR-triggered -- so their secrets were
# never checked against the Dependabot store and APP_PRIVATE_KEY shipped
# unmirrored. Under-matching in a checker is a false all-clear, which is strictly
# worse than a false finding: nobody goes looking for what it did not say.
tmp="$(mktemp -d)"; bin="${tmp}/bin"
mkdir -p "${tmp}/.github/workflows"
cat > "${tmp}/.github/workflows/four-space.yaml" <<'EOF'
name: Four Space
on:
    pull_request:
        branches: [main]
jobs:
    a:
        runs-on: ubuntu-latest
        steps:
            - env:
                  T: ${{ secrets.PR_SECRET }}
              run: echo hi
EOF
make_fake_gh "${bin}" "" "PR_SECRET"
out="$(run "${tmp}" "${bin}")"
grep -q "empty on Dependabot PRs" <<<"${out}"
check "a four-space-indented pull_request trigger is detected" "$?"

# --- 4. present in the Dependabot store -> no finding. -----------------------
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_repo "${tmp}"; make_fake_gh "${bin}" "PR_SECRET"
out="$(run "${tmp}" "${bin}")"
! grep -q "empty on Dependabot PRs" <<<"${out}"
check "no Dependabot finding once the secret exists there" "$?"

# --- 5. a genuinely missing repo secret fails the run. -----------------------
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_repo "${tmp}"; make_fake_gh "${bin}" "PR_SECRET" "PR_SECRET"  # PUSH_SECRET absent
out="$(run "${tmp}" "${bin}")"; rc=$?
grep -q "MISSING" <<<"${out}" && [ "${rc}" -ne 0 ]
check "missing repo secret is reported and exits non-zero" "$?"

# --- 6. GITHUB_TOKEN is never a finding. -------------------------------------
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_repo "${tmp}"
cat > "${tmp}/.github/workflows/tok.yaml" <<'EOF'
name: Tok
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - env:
          T: ${{ secrets.GITHUB_TOKEN }}
        run: echo hi
EOF
make_fake_gh "${bin}" "PR_SECRET" "PR_SECRET PUSH_SECRET"
out="$(run "${tmp}" "${bin}")"
grep -q "provided by Actions" <<<"${out}"
check "GITHUB_TOKEN is treated as auto-provided" "$?"

# --- 7. UNKNOWN is never scored. ---------------------------------------------
# No gh at all: must exit 0 (it is an honest "could not look"), must NOT claim
# anything is missing, and must NOT claim everything is configured.
tmp="$(mktemp -d)"; make_repo "${tmp}"
out="$(run "${tmp}" "${tmp}/nope")"; rc=$?
[ "${rc}" -eq 0 ]
check "offline run exits 0 rather than failing on unknowns" "$?"

! grep -q "MISSING" <<<"${out}"
check "offline run never reports anything as MISSING" "$?"

! grep -q "every value CI references is configured" <<<"${out}"
check "offline run never claims everything is configured" "$?"

grep -q "presence NOT verified" <<<"${out}"
check "offline run says presence was not verified" "$?"

# --- 8. an all-empty API response is unknown, not "everything missing". ------
# A token without admin:repo 403s on every list. Scoring that as absence would
# report the entire CI configuration missing on a perfectly healthy repo.
tmp="$(mktemp -d)"; bin="${tmp}/bin"
make_repo "${tmp}"
mkdir -p "${bin}"
cat > "${bin}/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*) exit 0 ;;
  *"repo view"*)   echo "acme/widget"; exit 0 ;;
  *)               exit 1 ;;   # every list 403s
esac
EOF
chmod +x "${bin}/gh"
out="$(run "${tmp}" "${bin}")"; rc=$?
[ "${rc}" -eq 0 ] && ! grep -q "MISSING" <<<"${out}"
check "unreadable API is unknown, not absence" "$?"

grep -q "admin:repo" <<<"${out}"
check "unreadable API explains the likely scope problem" "$?"

echo
printf '  %d passed, %d failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
