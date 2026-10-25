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

# seal_arc_github_app_test — the checks before anything is sealed, and what is
# handed to kubectl. Fake kubectl and kubeseal on PATH; a throwaway RSA key.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/seal_arc_github_app.sh"
# With SEAL_ARC_GITHUB_APP_BIN (the Rust port, //tools/gitops:gitops-cli) the
# same checks run against the port instead of the script.
if [ -n "${SEAL_ARC_GITHUB_APP_BIN:-}" ]; then
  BIN="$(cd "$(dirname "${SEAL_ARC_GITHUB_APP_BIN}")" && pwd)/$(basename "${SEAL_ARC_GITHUB_APP_BIN}")"
  RUN=("${BIN}" seal-arc-github-app)
else
  RUN=(bash "${SCRIPT}")
fi
failures=0
ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/ws/tools/sync-env-secrets/agent-keys" "$W/ws/gitops/argocd/platform/sealed-secrets-manifests"
cat >"$W/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_DIR/kubectl.args"
printf 'kind: Secret\ndata:\n  github_app_private_key: cGxhaW4=\n'
STUB
cat >"$W/bin/kubeseal" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_DIR/kubeseal.args"
grep -q github_app_private_key && printf 'kind: SealedSecret\nspec:\n  encryptedData:\n    github_app_private_key: AgBsealed\n'
STUB
chmod +x "$W/bin/kubectl" "$W/bin/kubeseal"
KEY="$W/ws/tools/sync-env-secrets/agent-keys/vitruvian-arc.pem"
OUT="$W/ws/gitops/argocd/platform/sealed-secrets-manifests/vitruvian-arc-github-app.sealedsecret.yaml"

run() { (cd "$W/ws" && FAKE_DIR="$W" PATH="$W/bin:$PATH" BUILD_WORKSPACE_DIRECTORY="$W/ws" "${RUN[@]}" "$@") >"$W/out" 2>&1; }
reset() { rm -f "$OUT" "$W/kubectl.args" "$W/kubeseal.args"; }

echo "== refuses before sealing =="
reset
if run; then bad "no key: exited 0"; elif [ -e "$OUT" ] || [ -e "$W/kubectl.args" ]; then bad "no key: ran kubectl or wrote output"
else grep -q "agent-keys-pull" "$W/out" && ok "no key: refuses and names agent-keys-pull" || bad "no key: $(cat "$W/out")"; fi

openssl genrsa -out "$KEY" 2048 2>/dev/null
chmod 644 "$KEY"; reset
if run; then bad "mode 644: exited 0"; elif [ -e "$OUT" ]; then bad "mode 644: wrote output"
else grep -q "mode 644; expected 600" "$W/out" && ok "a key that is not mode 600 is refused" || bad "mode 644: $(cat "$W/out")"; fi

cp "$KEY" "$W/good.pem"; echo "not a key" >"$KEY"; chmod 600 "$KEY"; reset
if run; then bad "bad key: exited 0"; elif [ -e "$OUT" ]; then bad "bad key: wrote output"
else grep -q "not a valid RSA private key" "$W/out" && ok "a file that is not an RSA key is refused" || bad "bad key: $(cat "$W/out")"; fi

if run --nonsense; then bad "unknown flag: exited 0"; else ok "an unknown argument is refused"; fi

echo "== seals =="
cp "$W/good.pem" "$KEY"; chmod 600 "$KEY"; reset
if ! run; then bad "good key: failed: $(cat "$W/out")"
else
  args="$(tr '\n' ' ' <"$W/kubectl.args")"
  case "$args" in
    *"--context default create secret generic vitruvian-arc-github-app -n arc-runners"*"--from-literal=github_app_id=5387602 --from-literal=github_app_installation_id=173186413 --from-file=github_app_private_key=tools/sync-env-secrets/agent-keys/vitruvian-arc.pem"*)
      ok "kubectl gets the namespace, the two ids and the key file, with --context" ;;
    *) bad "kubectl args: $args" ;;
  esac
  head -1 "$OUT" | grep -q "^# Copyright (c) 2026 VitruvianSoftware" && ok "the output starts with the license header" || bad "header: $(head -1 "$OUT")"
  grep -q "github_app_private_key: AgBsealed" "$OUT" && ok "the sealed key is written" || bad "no sealed key in output"
  grep -q "BEGIN" "$OUT" && bad "the plaintext key reached the output" || ok "no plaintext key in the output"
fi

if [ "$failures" -ne 0 ]; then echo "seal_arc_github_app_test: $failures failure(s)" >&2; exit 1; fi
echo "seal_arc_github_app_test: all checks passed"
