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

# apple-signing -- the Developer ID certificate and notary API key that sign and
# notarize the Vitruvian app, set up from the shell. See README.md.
#
#   bazel run //tools/apple-signing -- csr
#   bazel run //tools/apple-signing -- secrets <KEY_ID> <ISSUER_ID> <AuthKey_*.p8>
#   bazel run //tools/apple-signing -- check
#
# Two steps cannot live here, because Apple has no API for them: asking Apple
# for the certificate (upload the .csr at developer.apple.com > Certificates >
# + > Developer ID Application, G2) and creating the API key (App Store Connect
# > Users and Access > Integrations > Team Keys, Developer role). Both need the
# account holder signed in. Everything either side of them is here.
#
# Secrets never reach the terminal: the .p12 password is random and only ever
# piped, and every value goes to gh and bw on standard input.

set -euo pipefail

DIR=${APPLE_SIGNING_DIR:-$HOME/.vitruvian-signing}
REPO=${APPLE_SIGNING_REPO:-VitruvianSoftware/vitruvian-core}
PREFIX=${APPLE_SIGNING_SECRET_PREFIX:-VITRUVIAN}
PY=${PYTHON:-python3}

usage() {
  sed -n '/^#   bazel run/s/^#   //p' "$0" >&2
  exit 2
}

die() { echo "apple-signing: $*" >&2; exit 1; }

b64() { base64 <"$1" | tr -d '\n'; }

# The certificate's own name and team, so nothing here is tied to one person.
cert_field() { # field (CN or OU)
  openssl x509 -inform der -in "$DIR/developer-id.cer" -noout -subject -nameopt multiline |
    sed -n "s/^ *$( [ "$1" = CN ] && echo commonName || echo organizationalUnitName) *= *//p" | head -1
}

cmd_csr() {
  mkdir -p "$DIR" && chmod 700 "$DIR"
  [ ! -e "$DIR/developer-id.key" ] || die "$DIR/developer-id.key already exists; move it away first (it may be the key of a live certificate)"
  (umask 077 && openssl genrsa -out "$DIR/developer-id.key" 2048 2>/dev/null)
  openssl req -new -key "$DIR/developer-id.key" -out "$DIR/developer-id.csr" \
    -subj "/CN=Vitruvian Developer ID/O=VitruvianSoftware/C=US"
  echo "Made $DIR/developer-id.key (stays on this Mac) and $DIR/developer-id.csr."
  echo "Next: upload the .csr at developer.apple.com > Certificates > + > Developer ID Application (G2),"
  echo "      save the downloaded certificate as $DIR/developer-id.cer, then run 'secrets'."
}

# A Bitwarden secure note, unless one by that name exists already.
bw_note() { # name notes-file fields-json
  if bw list items --search "$1" | "$PY" -c 'import json,sys;sys.exit(0 if any(i["name"]==sys.argv[1] for i in json.load(sys.stdin)) else 1)' "$1"; then
    echo "    '$1' is already in Bitwarden; left as it is"
    return
  fi
  NAME_="$1" NOTES_FILE="$2" FIELDS="$3" "$PY" -c '
import json, os
print(json.dumps({"type": 2, "name": os.environ["NAME_"], "secureNote": {"type": 0},
  "notes": open(os.environ["NOTES_FILE"]).read(), "fields": json.loads(os.environ["FIELDS"])}))' |
    bw encode | bw create item >/dev/null
  echo "    saved '$1'"
}

cmd_secrets() {
  [ $# -eq 3 ] || usage
  local key_id=$1 issuer=$2 p8_in=$3
  [ -f "$DIR/developer-id.key" ] || die "no $DIR/developer-id.key; run 'csr' first"
  [ -f "$DIR/developer-id.cer" ] || die "no $DIR/developer-id.cer; download the certificate from developer.apple.com"
  [ -f "$p8_in" ] || die "no API key at $p8_in"
  [ "$(openssl x509 -inform der -in "$DIR/developer-id.cer" -noout -pubkey | openssl md5)" = \
    "$(openssl rsa -in "$DIR/developer-id.key" -pubout 2>/dev/null | openssl md5)" ] ||
    die "developer-id.cer was not issued for developer-id.key"
  local name team
  name=$(cert_field CN); team=$(cert_field OU)
  case $name in "Developer ID Application:"*) ;; *) die "developer-id.cer is '$name', not a Developer ID Application certificate" ;; esac
  unset GH_TOKEN GITHUB_TOKEN
  cd "$DIR"; umask 077

  echo "1/5 Building the certificate bundle (random password, never shown)"
  P=$(openssl rand -base64 33 | tr -d '/+=\n' | cut -c1-32); export P
  openssl x509 -inform der -in developer-id.cer -out developer-id.pem
  # 3DES and a SHA-1 MAC: what `security import` on every macOS reads.
  openssl pkcs12 -export -inkey developer-id.key -in developer-id.pem -name "$name" -out developer-id.p12 \
    -passout env:P -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
  [ "$p8_in" -ef "AuthKey_$key_id.p8" ] || mv "$p8_in" "AuthKey_$key_id.p8"
  local p8="AuthKey_$key_id.p8"

  echo "2/5 Checking Apple accepts the API key"
  xcrun notarytool history --key "$p8" --key-id "$key_id" --issuer "$issuer" >/dev/null ||
    die "Apple rejected the API key (key id $key_id, issuer $issuer)"

  echo "3/5 Saving the five GitHub secrets to $REPO"
  b64 developer-id.p12   | gh secret set "${PREFIX}_SIGNING_CERT_P12" --repo "$REPO"
  printf '%s' "$P"       | gh secret set "${PREFIX}_SIGNING_CERT_PASSWORD" --repo "$REPO"
  b64 "$p8"              | gh secret set "${PREFIX}_NOTARY_API_KEY_P8" --repo "$REPO"
  printf '%s' "$key_id"  | gh secret set "${PREFIX}_NOTARY_KEY_ID" --repo "$REPO"
  printf '%s' "$issuer"  | gh secret set "${PREFIX}_NOTARY_ISSUER_ID" --repo "$REPO"

  echo "4/5 Saving to Bitwarden (it may ask for your master password)"
  if [ "$(bw status | "$PY" -c 'import json,sys;print(json.load(sys.stdin)["status"])')" != unlocked ]; then
    BW_SESSION=$(bw unlock --raw); export BW_SESSION
  fi
  bw sync >/dev/null
  local expires; expires=$(openssl x509 -inform der -in developer-id.cer -noout -enddate | cut -d= -f2)
  b64 developer-id.p12 > p12.b64
  bw_note "Apple Developer ID Application certificate (p12)" p12.b64 "$(TEAM=$team EXP=$expires "$PY" -c '
import json, os
print(json.dumps([{"name": "p12 password", "value": os.environ["P"], "type": 1},
  {"name": "team id", "value": os.environ["TEAM"], "type": 0},
  {"name": "notes", "value": "notes = base64 of the .p12; expires " + os.environ["EXP"], "type": 0}]))')"
  bw_note "App Store Connect API key (notary)" "$p8" "$(KID=$key_id ISS=$issuer "$PY" -c '
import json, os
print(json.dumps([{"name": "key id", "value": os.environ["KID"], "type": 0},
  {"name": "issuer id", "value": os.environ["ISS"], "type": 0}]))')"
  cat developer-id.key developer-id.pem > keypair.pem
  bw_note "Apple Developer ID private key + certificate (PEM)" keypair.pem "$(TEAM=$team "$PY" -c '
import json, os
print(json.dumps([{"name": "team id", "value": os.environ["TEAM"], "type": 0},
  {"name": "what", "value": "private key then certificate, PEM", "type": 0}]))')"
  rm -f p12.b64 keypair.pem

  echo "5/5 Installing the identity in your login keychain (for signing on this Mac)"
  if command -v security >/dev/null 2>&1; then
    security find-certificate -c "Developer ID Certification Authority" >/dev/null 2>&1 || {
      curl -fsSL -o DeveloperIDG2CA.cer https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
      security import DeveloperIDG2CA.cer -k "$HOME/Library/Keychains/login.keychain-db" >/dev/null
    }
    security import developer-id.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P "$P" -T /usr/bin/codesign >/dev/null ||
      echo "    (already in the keychain)"
  else
    echo "    no 'security' command: not a Mac, skipped"
  fi
  unset P
  echo
  cmd_check
}

cmd_check() {
  local ok=0 n
  if command -v security >/dev/null 2>&1; then
    n=$(security find-identity -v -p codesigning | grep -c "Developer ID Application" || true)
    echo "  Developer ID signing identities on this Mac: $n"
  fi
  n=$(gh secret list --repo "$REPO" | grep -cE "^${PREFIX}_(SIGNING_CERT_P12|SIGNING_CERT_PASSWORD|NOTARY_API_KEY_P8|NOTARY_KEY_ID|NOTARY_ISSUER_ID)[[:space:]]" || true)
  echo "  GitHub secrets set on $REPO: $n of 5"
  [ "$n" -eq 5 ] || ok=1
  if [ -f "$DIR/developer-id.cer" ]; then
    echo "  certificate: $(cert_field CN), $(openssl x509 -inform der -in "$DIR/developer-id.cer" -noout -enddate | cut -d= -f2 | sed 's/^/expires /')"
  fi
  return $ok
}

case ${1:-} in
  csr) shift; cmd_csr "$@" ;;
  secrets) shift; cmd_secrets "$@" ;;
  check) shift; cmd_check "$@" ;;
  *) usage ;;
esac
