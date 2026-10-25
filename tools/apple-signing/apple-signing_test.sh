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

# apple-signing_test -- offline tests for tools/apple-signing/apple-signing.sh.
#
# No network, no Apple, no GitHub, no Bitwarden: gh, bw, xcrun and security are
# fakes that record what they were given. The certificate is a throwaway one
# made here, with the subject shape Apple issues.

set -uo pipefail

SCRIPT=$(find "${TEST_SRCDIR:-.}" -path '*tools/apple-signing/apple-signing.sh' | head -1)
[ -n "$SCRIPT" ] || { echo "apple-signing.sh not found in runfiles"; exit 1; }
# APPLE_SIGNING_BIN runs every case against another build of the tool (the
# Rust port, :apple-signing-rs_test) instead of the script.
BIN="${APPLE_SIGNING_BIN:-}"
if [ -n "$BIN" ]; then
  case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
fi
run_tool() { if [ -n "$BIN" ]; then "$BIN" "$@"; else bash "$SCRIPT" "$@"; fi; }
WORK=$(mktemp -d "${TEST_TMPDIR:-/tmp}/apple-signing.XXXXXX")
fails=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails + 1)); fi; }

FAKES=$WORK/fakes; LOG=$WORK/log; mkdir -p "$FAKES"; : >"$LOG"
cat >"$FAKES/gh" <<'F'
#!/usr/bin/env bash
if [ "$1 $2" = "secret set" ]; then v=$(cat); echo "gh set $3 len=${#v}" >>"$LOG"
elif [ "$1 $2" = "secret list" ]; then cat "$WORK/gh-list" 2>/dev/null; fi
F
cat >"$FAKES/bw" <<'F'
#!/usr/bin/env bash
case $1 in
  status) echo '{"status":"unlocked"}' ;;
  list) cat "$WORK/bw-items" 2>/dev/null || echo '[]' ;;
  encode) cat ;;
  create) python3 -c 'import json,sys;d=json.load(sys.stdin);print("bw create "+d["name"]+" fields="+str(len(d["fields"]))+" notes="+str(len(d["notes"])))' >>"$LOG" ;;
esac
F
cat >"$FAKES/xcrun" <<'F'
#!/usr/bin/env bash
echo "xcrun $*" >>"$LOG"
[ "$2" = info ] && echo "  status: ${FAKE_STATUS:-In Progress}"
[ "$2" = history ] && echo "  id: sub-1"
[ -z "${XCRUN_FAILS:-}" ]
F
cat >"$FAKES/security" <<'F'
#!/usr/bin/env bash
echo "security $1" >>"$LOG"
F
chmod +x "$FAKES"/*
export PATH="$FAKES:$PATH" LOG WORK APPLE_SIGNING_DIR=$WORK/signing HOME=$WORK/home
mkdir -p "$HOME"

# Usage and unknown commands fail with 2, without touching anything.
run_tool >/dev/null 2>&1; check "no command is a usage error" '[ $? -eq 2 ]'
run_tool nope >/dev/null 2>&1; check "unknown command is a usage error" '[ $? -eq 2 ]'

# csr: a private key only its owner reads, and a request that verifies.
run_tool csr >/dev/null
check "csr makes the key" '[ -f "$APPLE_SIGNING_DIR/developer-id.key" ]'
check "the key is private" '[ "$(ls -l "$APPLE_SIGNING_DIR/developer-id.key" | cut -c1-10)" = "-rw-------" ]'
check "the request verifies" 'openssl req -in "$APPLE_SIGNING_DIR/developer-id.csr" -noout -verify >/dev/null 2>&1'
before=$(openssl md5 <"$APPLE_SIGNING_DIR/developer-id.key")
run_tool csr >/dev/null 2>&1; rc=$?
check "csr refuses to overwrite a key" '[ $rc -ne 0 ] && [ "$(openssl md5 <"$APPLE_SIGNING_DIR/developer-id.key")" = "$before" ]'

# secrets refuses before calling anything when the certificate is missing.
echo fake-p8 >"$WORK/AuthKey_K1.p8"
run_tool secrets K1 ISS "$WORK/AuthKey_K1.p8" >/dev/null 2>&1; rc=$?
check "secrets without a certificate fails" '[ $rc -ne 0 ]'
check "...and calls nothing" '[ ! -s "$LOG" ]'

# A certificate for a DIFFERENT key is refused.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$WORK/other.key" -days 1 -outform der \
  -out "$APPLE_SIGNING_DIR/developer-id.cer" -subj "/CN=Developer ID Application: TEST (TEAM123)/OU=TEAM123/O=TEST/C=US" 2>/dev/null
run_tool secrets K1 ISS "$WORK/AuthKey_K1.p8" >/dev/null 2>&1; rc=$?
check "a certificate for another key is refused" '[ $rc -ne 0 ] && [ ! -s "$LOG" ]'

# The right certificate: the shape Apple issues, for the key csr made.
openssl req -new -key "$APPLE_SIGNING_DIR/developer-id.key" -subj "/CN=Developer ID Application: TEST (TEAM123)/OU=TEAM123/O=TEST/C=US" |
  openssl x509 -req -signkey "$APPLE_SIGNING_DIR/developer-id.key" -days 1 -outform der -out "$APPLE_SIGNING_DIR/developer-id.cer" 2>/dev/null

# Apple rejecting the API key stops before any secret is saved.
XCRUN_FAILS=1 run_tool secrets K1 ISS "$WORK/AuthKey_K1.p8" >/dev/null 2>&1; rc=$?
check "a rejected API key stops the run" '[ $rc -ne 0 ] && ! grep -q "^gh set" "$LOG"'
mv "$APPLE_SIGNING_DIR/AuthKey_K1.p8" "$WORK/AuthKey_K1.p8" 2>/dev/null; : >"$LOG"

printf 'VITRUVIAN_SIGNING_CERT_P12\tx\nVITRUVIAN_SIGNING_CERT_PASSWORD\tx\nVITRUVIAN_NOTARY_API_KEY_P8\tx\nVITRUVIAN_NOTARY_KEY_ID\tx\nVITRUVIAN_NOTARY_ISSUER_ID\tx\n' >"$WORK/gh-list"
out=$(run_tool secrets K1 ISS "$WORK/AuthKey_K1.p8" 2>&1); rc=$?
check "secrets succeeds" '[ $rc -eq 0 ]'
for s in SIGNING_CERT_P12 SIGNING_CERT_PASSWORD NOTARY_API_KEY_P8 NOTARY_KEY_ID NOTARY_ISSUER_ID; do
  check "sets VITRUVIAN_$s, not empty" 'grep -q "^gh set VITRUVIAN_$s len=[1-9]" "$LOG"'
done
check "the .p12 password is 32 characters" 'grep -q "^gh set VITRUVIAN_SIGNING_CERT_PASSWORD len=32$" "$LOG"'
check "the API key is checked with Apple first" '[ "$(grep -n "^xcrun notarytool" "$LOG" | cut -d: -f1)" -lt "$(grep -n "^gh set" "$LOG" | head -1 | cut -d: -f1)" ]'
check "three Bitwarden items" '[ "$(grep -c "^bw create" "$LOG")" -eq 3 ]'
check "the p12 item carries the password field" 'grep -q "^bw create Apple Developer ID Application certificate (p12) fields=3 notes=[1-9]" "$LOG"'
check "the API key moved into the signing folder" '[ -f "$APPLE_SIGNING_DIR/AuthKey_K1.p8" ] && [ ! -e "$WORK/AuthKey_K1.p8" ]'
check "no password in the output" '! printf "%s" "$out" | grep -qiE "password[^ ]*[: =][A-Za-z0-9]{20}"'
check "the bundle opens with a 32-character password only" '! openssl pkcs12 -in "$APPLE_SIGNING_DIR/developer-id.p12" -passin pass: -noout 2>/dev/null'
check "temporary copies are gone" '[ ! -e "$APPLE_SIGNING_DIR/p12.b64" ] && [ ! -e "$APPLE_SIGNING_DIR/keypair.pem" ]'
check "the summary counts 5 of 5" 'printf "%s" "$out" | grep -q "5 of 5"'

check "secrets keeps the two (non-secret) IDs for notary-status" 'grep -qx "KEY_ID=K1" "$APPLE_SIGNING_DIR/notary.env" && grep -qx "ISSUER_ID=ISS" "$APPLE_SIGNING_DIR/notary.env"'

# notary-status: no ID lists every submission; an ID shows that one, plus
# Apple's report once there is a verdict.
: >"$LOG"; out=$(run_tool notary-status 2>&1); rc=$?
check "notary-status lists submissions" '[ $rc -eq 0 ] && grep -q "^xcrun notarytool history --key $APPLE_SIGNING_DIR/AuthKey_K1.p8 --key-id K1 --issuer ISS$" "$LOG"'
: >"$LOG"; run_tool notary-status sub-1 >/dev/null 2>&1
check "an in-progress submission shows no report yet" 'grep -q "^xcrun notarytool info sub-1 " "$LOG" && ! grep -q "notarytool log" "$LOG"'
: >"$LOG"; out=$(FAKE_STATUS=Invalid run_tool notary-status sub-1 2>&1)
check "a finished submission also shows Apple's report" 'grep -q "^xcrun notarytool log sub-1 " "$LOG" && printf "%s" "$out" | grep -q "status: Invalid"'
mv "$APPLE_SIGNING_DIR/notary.env" "$WORK/notary.env.away"; : >"$LOG"
run_tool notary-status >/dev/null 2>&1; rc=$?
check "notary-status without saved IDs fails and calls nothing" '[ $rc -ne 0 ] && [ ! -s "$LOG" ]'
mv "$WORK/notary.env.away" "$APPLE_SIGNING_DIR/notary.env"

# A second run leaves existing Bitwarden items alone.
echo '[{"name":"Apple Developer ID Application certificate (p12)"},{"name":"App Store Connect API key (notary)"},{"name":"Apple Developer ID private key + certificate (PEM)"}]' >"$WORK/bw-items"
: >"$LOG"; run_tool secrets K1 ISS "$APPLE_SIGNING_DIR/AuthKey_K1.p8" >/dev/null 2>&1
check "a rerun adds no duplicate Bitwarden items" '! grep -q "^bw create" "$LOG"'

rm -rf "$WORK"
[ $fails -eq 0 ] && echo "PASS" || { echo "$fails failed"; exit 1; }
