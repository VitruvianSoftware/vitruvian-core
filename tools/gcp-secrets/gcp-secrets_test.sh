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

# Hermetic regression guard for gcp-secrets.sh. Drives the REAL script against a
# fake `gcloud` that records every invocation (argv + stdin), so the assertions
# are about what the tool actually does, not what it prints.
#
# The properties under test are the ones whose failure would be a SECRET LEAK or
# a silent wrong-target write, i.e. exactly the things that make handing a human
# a raw `gcloud secrets versions add` line a bad idea in the first place:
#   1. the value goes in on STDIN, never argv (argv is world-readable via `ps`);
#   2. the value never appears in stdout/stderr;
#   3. the pinned identity + project from gcp-identities.tsv are passed on EVERY
#      call — never ambient gcloud;
#   4. an already-seeded secret is skipped, so a re-run can't stack a second
#      version and flip which value is `latest`;
#   5. --force is what allows a deliberate rotation;
#   6. an empty input skips rather than writing an empty secret.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/gcp-secrets.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() {
  printf '  ✗ %s\n' "$1" >&2
  fails=$((fails + 1))
}
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else
    printf '  ✗ %s — got %q, want %q\n' "$1" "$2" "$3" >&2
    fails=$((fails + 1))
  fi
}

# --- fixtures ----------------------------------------------------------------

# Identity map in the real TSV shape: <dir> <account> <project> <description>
cat >"$work/identities.tsv" <<'EOF'
# comment line
demo/infra/build	robot@example.test	prj-demo-1234	demo build project
EOF

# Reuse the REAL resolver, so a change to its parsing breaks this test too.
RESOLVER="$(cd "$HERE/.." && pwd)/pulumi/resolve_identity.sh"
[ -f "$RESOLVER" ] || {
  echo "resolver not found at $RESOLVER" >&2
  exit 1
}

# Fake gcloud: appends "<stdin>|<argv>" per call, and answers the two reads the
# tool makes. SEEDED lists secrets that already have an enabled version.
cat >"$work/fake-gcloud" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
calls="$CALL_LOG"
stdin_data=""
args="$*"
# Real gcloud only consumes stdin when explicitly told to (--data-file=-).
# Slurping it unconditionally would eat the value the tool is about to `read`.
case "$args" in *"--data-file=-"*) stdin_data="$(cat || true)" ;; esac
printf '%s|%s\n' "$stdin_data" "$args" >>"$calls"
case "$args" in
  *"secrets list"*)
    printf 'projects/prj-demo-1234/secrets/ALPHA_KEY\nprojects/prj-demo-1234/secrets/BETA_KEY\n' ;;
  *"secrets versions list"*)
    for s in ${SEEDED:-}; do
      case "$args" in *" $s "*) echo "projects/prj-demo-1234/secrets/$s/versions/1"; exit 0 ;; esac
    done
    : ;;
  *"versions add"*) : ;;
esac
EOF
chmod +x "$work/fake-gcloud"

run_tool() { # run_tool <subcommand> <stdin> [args...]
  local sub="$1" input="$2"
  shift 2
  : >"$work/calls"
  CALL_LOG="$work/calls" \
    SEEDED="${SEEDED:-}" \
    GCLOUD_BIN="$work/fake-gcloud" \
    GCP_IDENTITY_MAP="$work/identities.tsv" \
    GCP_IDENTITY_RESOLVER="$RESOLVER" \
    bash "$SCRIPT" "$sub" demo/infra/build "$@" <<<"$input"
}

# --- tests -------------------------------------------------------------------

echo "test 1: the value is piped on STDIN and never appears in argv"
SEEDED="" out="$(run_tool seed 'sup3r-s3cret' ALPHA_KEY 2>&1)"
add_line="$(grep 'versions add' "$work/calls" || true)"
case "${add_line%%|*}" in
  "sup3r-s3cret") pass "value arrived on stdin" ;;
  *) fail "value not on stdin — got ${add_line%%|*}" ;;
esac
case "${add_line#*|}" in
  *sup3r-s3cret*) fail "SECRET LEAKED INTO ARGV: ${add_line#*|}" ;;
  *) pass "value absent from argv (not visible to \`ps\`)" ;;
esac
case "${add_line#*|}" in
  *"--data-file=-"*) pass "uses --data-file=-" ;;
  *) fail "expected --data-file=- in: ${add_line#*|}" ;;
esac

echo "test 2: the value never reaches stdout/stderr"
case "$out" in
  *sup3r-s3cret*) fail "SECRET LEAKED INTO OUTPUT: $out" ;;
  *) pass "value absent from all output" ;;
esac

echo "test 3: the pinned identity and project are passed on every call"
bad=0
while read -r line; do
  [ -n "$line" ] || continue
  case "${line#*|}" in
    *"--account=robot@example.test"*"--project=prj-demo-1234"*) ;;
    *) bad=$((bad + 1)) ;;
  esac
done <"$work/calls"
assert_eq "every gcloud call is identity+project pinned" "$bad" "0"

echo "test 4: an already-seeded secret is skipped (no second version)"
SEEDED="ALPHA_KEY" out="$(run_tool seed 'another' ALPHA_KEY 2>&1)"
assert_eq "no versions add issued" "$(grep -c 'versions add' "$work/calls" || true)" "0"
case "$out" in
  *"already has"*) pass "explains the skip" ;;
  *) fail "expected an 'already has' message — got: $out" ;;
esac

echo "test 5: --force allows a deliberate rotation"
SEEDED="ALPHA_KEY" out="$(run_tool seed 'rotated' --force ALPHA_KEY 2>&1)"
assert_eq "versions add issued under --force" "$(grep -c 'versions add' "$work/calls" || true)" "1"

echo "test 6: empty input skips rather than writing an empty secret"
SEEDED="" out="$(run_tool seed '' ALPHA_KEY 2>&1)"
assert_eq "no versions add for empty input" "$(grep -c 'versions add' "$work/calls" || true)" "0"

echo "test 7: seed with no names walks every unseeded secret in the project"
SEEDED="ALPHA_KEY" out="$(printf 'v1\n' | {
  : >"$work/calls"
  CALL_LOG="$work/calls" SEEDED="ALPHA_KEY" GCLOUD_BIN="$work/fake-gcloud" \
    GCP_IDENTITY_MAP="$work/identities.tsv" GCP_IDENTITY_RESOLVER="$RESOLVER" \
    bash "$SCRIPT" seed demo/infra/build 2>&1
})"
# ALPHA is seeded already -> skipped; BETA is not -> gets the piped value.
assert_eq "only the unseeded secret is written" "$(grep -c 'versions add' "$work/calls" || true)" "1"
case "$(grep 'versions add' "$work/calls" || true)" in
  *BETA_KEY*) pass "wrote the unseeded secret (BETA_KEY)" ;;
  *) fail "expected BETA_KEY to be written" ;;
esac

echo "test 8: an unmapped infra dir is refused (never falls back to ambient gcloud)"
if out="$(CALL_LOG="$work/calls" GCLOUD_BIN="$work/fake-gcloud" \
  GCP_IDENTITY_MAP="$work/identities.tsv" GCP_IDENTITY_RESOLVER="$RESOLVER" \
  bash "$SCRIPT" status not/in/the/map 2>&1)"; then
  fail "unmapped dir should exit non-zero — got: $out"
else
  pass "unmapped dir exits non-zero"
fi
case "$out" in
  *"not listed"*) pass "error names the cause" ;;
  *) fail "expected a 'not listed' error — got: $out" ;;
esac

echo "test 9: a gcloud auth failure FAILS LOUDLY (it exits 0 on reauth errors)"
# `gcloud secrets list` prints "ERROR: ... Reauthentication failed" to stderr and
# still EXITS 0. Suppressing stderr and trusting the status code therefore turns
# a broken credential into a confident, empty "no secrets here" — the exact
# silent-success shape this tool exists to avoid.
cat >"$work/fake-gcloud-authfail" <<'FAKE'
#!/usr/bin/env bash
echo "ERROR: (gcloud.secrets.list) There was a problem refreshing your current auth tokens: Reauthentication failed." >&2
exit 0
FAKE
chmod +x "$work/fake-gcloud-authfail"
if out="$(CALL_LOG="$work/calls" GCLOUD_BIN="$work/fake-gcloud-authfail" \
  GCP_IDENTITY_MAP="$work/identities.tsv" GCP_IDENTITY_RESOLVER="$RESOLVER" \
  bash "$SCRIPT" status demo/infra/build 2>&1)"; then
  fail "auth failure must exit non-zero — got exit 0 with: $out"
else
  pass "auth failure exits non-zero despite gcloud exiting 0"
fi
case "$out" in
  *Reauthentication*) pass "surfaces the underlying gcloud error" ;;
  *) fail "expected the gcloud error to be surfaced — got: $out" ;;
esac

if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails assertion(s)" >&2
  exit 1
fi
echo "ALL PASS"
exit 0
