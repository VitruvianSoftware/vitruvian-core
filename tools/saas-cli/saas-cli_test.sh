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

# Hermetic guard for saas-cli.sh. Drives the REAL script against fake `gcloud`
# and `npx` binaries that record argv and the environment they were handed, so
# the assertions are about what actually reaches the CLI.
#
# The properties are the ones whose failure leaks a credential or targets the
# wrong account — the reasons this wrapper exists instead of a README snippet:
#   1. the API key reaches the CLI via the ENVIRONMENT, never argv (`ps`);
#   2. it never appears in stdout/stderr;
#   3. the CLI version is PINNED (a surprise major mid-incident is its own outage);
#   4. gcloud is always identity+project pinned, never ambient;
#   5. a gcloud auth failure is FATAL even though gcloud exits 0;
#   6. an unseeded/empty secret fails with the command that seeds it;
#   7. args after `--` are forwarded verbatim.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/saas-cli.sh"
RESOLVER="$(cd "$HERE/.." && pwd)/pulumi/resolve_identity.sh"
[ -f "$RESOLVER" ] || { echo "resolver not found at $RESOLVER" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else
    printf '  ✗ %s — got %q, want %q\n' "$1" "$2" "$3" >&2; fails=$((fails + 1))
  fi
}

cat >"$work/identities.tsv" <<'EOF'
tabula/infra/build	robot@example.test	prj-demo-1234	demo
EOF

# Fake gcloud: prints a per-secret value, or simulates the auth failure.
cat >"$work/fake-gcloud" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GCLOUD_LOG"
if [ "${FAKE_AUTH_FAIL:-0}" = "1" ]; then
  echo "ERROR: (gcloud.secrets.versions.access) Reauthentication failed." >&2
  exit 0   # gcloud really does exit 0 here
fi
case "$*" in
  *NEON_API_KEY*)    [ "${FAKE_EMPTY:-0}" = "1" ] && exit 0; echo "neon-key-SECRET" ;;
  *UPSTASH_API_KEY*) echo "upstash-key-SECRET" ;;
  *UPSTASH_EMAIL*)   echo "robot@example.test" ;;
esac
EOF
chmod +x "$work/fake-gcloud"

# Fake npx: records argv AND the credential-bearing env it received.
cat >"$work/fake-npx" <<'EOF'
#!/usr/bin/env bash
printf 'ARGV:%s\n' "$*" >>"$NPX_LOG"
printf 'ENV_NEON:%s\n' "${NEON_API_KEY:-}" >>"$NPX_LOG"
printf 'ENV_UPSTASH:%s\n' "${UPSTASH_API_KEY:-}" >>"$NPX_LOG"
EOF
chmod +x "$work/fake-npx"

run() { # run <subcommand> [args...]
  : >"$work/gcloud.log"; : >"$work/npx.log"
  GCLOUD_LOG="$work/gcloud.log" NPX_LOG="$work/npx.log" \
    FAKE_AUTH_FAIL="${FAKE_AUTH_FAIL:-0}" FAKE_EMPTY="${FAKE_EMPTY:-0}" \
    GCLOUD_BIN="$work/fake-gcloud" NPX_BIN="$work/fake-npx" \
    GCP_IDENTITY_MAP="$work/identities.tsv" GCP_IDENTITY_RESOLVER="$RESOLVER" \
    bash "$SCRIPT" "$@"
}

echo "test 1: the key reaches the CLI via the ENVIRONMENT, never argv"
out="$(run neon projects list 2>&1)"
argv="$(grep '^ARGV:' "$work/npx.log" | head -1)"
case "$argv" in
  *neon-key-SECRET*) fail "KEY LEAKED INTO ARGV: $argv" ;;
  *) pass "key absent from argv (not visible to \`ps\`)" ;;
esac
assert_eq "key handed over in the environment" \
  "$(grep '^ENV_NEON:' "$work/npx.log" | head -1)" "ENV_NEON:neon-key-SECRET"

echo "test 2: the key never reaches stdout/stderr"
case "$out" in
  *neon-key-SECRET*) fail "KEY LEAKED INTO OUTPUT: $out" ;;
  *) pass "key absent from all output" ;;
esac

echo "test 3: the CLI version is pinned"
case "$argv" in
  *neonctl@*) pass "neonctl invoked with an explicit version" ;;
  *) fail "neonctl not version-pinned: $argv" ;;
esac
run upstash redis list >/dev/null 2>&1 || true
case "$(grep '^ARGV:' "$work/npx.log" | head -1)" in
  *@upstash/cli@*) pass "upstash CLI invoked with an explicit version" ;;
  *) fail "upstash CLI not version-pinned" ;;
esac

echo "test 4: every gcloud call is identity+project pinned"
run neon projects list >/dev/null 2>&1 || true
bad=0
while read -r l; do
  [ -n "$l" ] || continue
  case "$l" in
    *--account=robot@example.test*--project=prj-demo-1234*) ;;
    *) bad=$((bad + 1)) ;;
  esac
done <"$work/gcloud.log"
assert_eq "no ambient-gcloud calls" "$bad" "0"

echo "test 5: forwards args after -- verbatim"
run neon connection-string my-project --database-name main >/dev/null 2>&1 || true
case "$(grep '^ARGV:' "$work/npx.log" | head -1)" in
  *"connection-string my-project --database-name main"*) pass "args forwarded verbatim" ;;
  *) fail "args mangled: $(grep '^ARGV:' "$work/npx.log" | head -1)" ;;
esac

echo "test 6: a gcloud auth failure is FATAL despite gcloud exiting 0"
if out="$(FAKE_AUTH_FAIL=1 run neon projects list 2>&1)"; then
  fail "auth failure must exit non-zero — got exit 0: $out"
else
  pass "auth failure exits non-zero"
fi
case "$out" in
  *Reauthentication*) pass "surfaces the gcloud error" ;;
  *) fail "expected the gcloud error — got: $out" ;;
esac

echo "test 7: an empty/unseeded secret fails with the seeding command"
if out="$(FAKE_EMPTY=1 run neon projects list 2>&1)"; then
  fail "empty secret must exit non-zero — got: $out"
else
  pass "empty secret exits non-zero"
fi
case "$out" in
  *"gcp-secrets:seed"*) pass "names the command that seeds it" ;;
  *) fail "expected the seed command — got: $out" ;;
esac

echo "test 8: an unknown subcommand is rejected"
if run bogus >/dev/null 2>&1; then fail "unknown subcommand should exit non-zero"; else pass "unknown subcommand rejected"; fi

if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails assertion(s)" >&2
  exit 1
fi
echo "ALL PASS"
exit 0
